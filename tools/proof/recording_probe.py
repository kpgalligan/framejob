#!/usr/bin/env python3
"""Road map 3 — the recorder's APP half, measured: R1 (sections 1–8), R2's
pause and resume (rows 3o–3t, section 4b, rows 5p–5u, 7d, and section 9),
the grants a press checks (section 10, spec §11 recording), issue batch
B17's unreadable segment and File ▸ Pause Recording (sections 11 and 12),
and issue batch B27's closed segment's did-fail (3r, 3r2), the recorder's
pause notification (F6, F7) and the countdown's meter (section 13), and
issue batch B42's finishing notification (F8, F9) and the countdown's
cleared resumeProblem (F10), issue batch B49's square `StickerButton`
(section 6, re-pinned to spec §11 SH-4), and issue batch B55's left-out
segment's readable microphone (section 14, U7, and rows in U1, U2, U6 and
3r; #181 item 2), and issue batch B64's voice-over (#99 phase 1: section 15
with no grant, and its granted tier 15g, which records the MICROPHONE alone
and never the screen), and issue batch B66's voice-over doors (#99 phase 2:
V9, V10 and section 16, `voiceover_doors`), and Include Frame Job windows
(section 17, `exclusion`, spec §11 recording.md).

Why a probe and not an MCP script. Three of the things R1a added have no
caller a running binary can be asked to reach, and one of them is the row
the phase's own mutant list names:

  * `RecordingFiles` — where a recording goes and what it is called — is
    pure Foundation over a folder; over MCP the only thing visible is a path
    in a tool's answer, one name at a time, and never the collision rule.
  * `RecordingConfiguration.make` builds the two ScreenCaptureKit
    configurations from a `RecordingChoice`. It is PURE so that every field
    can be read back here, and `excludesCurrentProcessAudio` is the reason
    it has to be: the mutant that flips it is INVISIBLE over MCP — nothing
    plays during a headless recording, so the file sounds the same either
    way — and section 2's read-back is the only row in the tree that sees
    it. R0 q4 (`.best` does not scale by itself; pixels are asked for) and
    q6a (`showMouseClicks` needs BGRA) are pinned on the same rows.
  * `ScreenRecorder`'s state machine has a fresh-instance face — idle,
    `stop()` while idle, an inert meter — that needs no filter and no
    grant; everything past `start` needs an `SCContentFilter`, which needs
    `SCShareableContent`, which needs the Screen Recording grant and a real
    call, so it is `recording_proof.py`'s over MCP and not this file's.

So this is `remaining_probe.py`'s instrument, reused verbatim where it
applies: a `main.swift` compiled against the WHOLE of `app/Sources` with
`swift_build.py`'s line, cached by content, a
request JSON in and an answer JSON out dispatched on `mode`, `--sources` /
`RC_APP_SOURCES` to point it at a mutant copy, and a build failure scored
as a FAILURE rather than an exit so a rotted instrument cannot take the
rest of the score down with it. The probe NEVER presents a picker, starts a
stream, or puts up the status item — a bare Mach-O has no bundle, and
`Transcriber.swift` records what a usage-string prompt does to one. **Every
mode runs under SEALED grant doors**: before the dispatch the probe's
`main` puts a `RecorderGrantDoors` in `RecorderPanelController.grantDoors`
whose three reads are real and whose two prompts, the asked-flag write and
the System Settings opener do nothing (the opener answering false), so no
mode can put up a prompt, open a pane or touch `FrameJobScreenRecordingAsked`.
It DOES call `record(_:)` — in section 5k (the R1 review's window-row
guard), because the fix under test is that a press over the "Window…" row
with no filter refuses at the door and reaches no capture — the tree's path
returns before any grant is read; only the `window-row-unguarded` mutant
falls through, and there the sealed doors are what it meets; in 9c, the
granted tier's panel; and in section 10e, each row under a spy of its own.
The two grants' current readings are printed as HOST FACTS and never
asserted (section 8).

Section 1 (`files`): `RecordingFiles.folder()` with `-RCRecordingFolder`
pinned in the volatile argument domain (the harness's own pin) and without
it; `stem(at:)` for two fixed dates, one with single-digit hour, minute and
second so the zero padding is pinned; `uniqueURL` over a folder holding
`X.mov` and `X (2).mov` → `X (3).mov`; `microphoneURL(beside:)` → the
` (Microphone).m4a` spelling, and ` (Microphone) (2)` when that is taken;
`create()` makes a nested folder and accepts an existing one; and
`RecordingChoice()`'s defaults.

Section 2 (`configuration`): `make` read back field by field over the 16
combinations of rate {30, 60} × resolution {nominal, best} × system audio
{off, on} × show clicks {off, on}, for a 1728×1117 display at scale 2 (this
machine's, R0): width/height 1728×1117 under nominal and 3456×2234 under
best, `minimumFrameInterval` 1/rate, `showsCursor` true, `showMouseClicks`
from the choice, `pixelFormat` BGRA (1111970369) iff clicks else the default
`420v` (875704438), `capturesAudio` from the choice with 48000 × 2,
`excludesCurrentProcessAudio` TRUE and `captureMicrophone` FALSE in every
row, `videoCodecType` `hvc1` where `availableVideoCodecTypes` offers it
(`avc1` otherwise — the expectation is derived from the list the probe read
off the returned configuration), `outputFileType`
`com.apple.quicktime-movie`, and `outputURL` the URL passed in.

Section 3 (`state`): a fresh `ScreenRecorder()` — never `.shared` — starts
idle with `isRecording` false and `elapsed` 0; `stop()` while idle completes
with `RecorderError.notRecording` and leaves it idle; a second `stop()`
answers the same, and one with no completion at all is accepted;
`publishMicrophoneLevel()` while idle with nothing prepared publishes
NOTHING (observed through `meter.addObserver`, which fires once on
subscription and must not fire
again); the meter is the recorder's own and not `LevelMeter.shared`;
`RecordingGrant.microphoneRefusal` names the status word for
`.notDetermined`, `.denied` and `.restricted`; the Screen Recording refusal
names the System Settings pane; and `RecordingMeter.linear` is pinned at
−20 dB → 0.1, 0 dB → 1, +6 dB → 1 (clamped), −∞ → 0. **Then the R1
review's recorder fixes** (lane R), in rows 3g–3n: the two ceilings'
sentences differ and name "start"/"20 s" against "writing"/"10 s"
(finding 5), and `filesKept` appends " The recording is at <movie>; the
microphone at <mic>." (finding 6); the grant sentences from a probe — which
is launched by this script, so `getppid()` is never 1 — are the pane
sentence as PREFIX plus the launch clause naming the parent's pid (R0 q1:
a shell-launched Frame Job runs under the terminal's grants, and the pane
sentence alone sent a person to grant the wrong application); and **the
machine past `start`, driven through a faked `Session`** in a second
request: the review measured that `SCContentFilter()` and
`SCStream(filter:configuration:delegate:)` CONSTRUCT without a grant and
only `startCapture` needs one, so the probe builds a `Session` from those,
a PNG at the movie URL (a "movie" `MediaImporter.probe` answers with a
descriptor) and — since R2 — a `SpyAudioOutput`, an `AVCaptureAudioFileOutput`
subclass with no session that COUNTS `stopRecording` and keeps the URLs
`startRecording(to:)` is asked for (a bare output delivers nothing either
way) — which HOLDS the finishing wait until the probe drives
the microphone's did-finish itself, so every row is deterministic — and
calls the three delegate methods as the frameworks would. Rows: a second
`stop()` while `.finishing` is registered and never `.busy`, and one
driven did-finish delivers ONE outcome to `onFinish` and both completions
(finding 1); the meter goes silent at `beginFinishing` (finding 8); a
microphone whose did-start never came answers `.success` with
`micDescriptor` nil and `micProblem` set (finding 0); a `checkFinished()`
and a duplicate did-finish DURING `settle`'s probe leave `onFinish` at one
call (finding 2, the measured double conclude); a microphone did-finish
carrying an error while `.recording` leaves the state `.recording`, sets
`microphoneProblem` at once and silences the meter, and `stop` then lands
a `.success` whose `micProblem` names the file the writer left (finding
3); an unreadable movie past `beginFinishing` fails with `filesKept`
naming both files, the movie alone without a microphone file (finding 6);
a did-finish nobody asked for followed by `didStopWithError(.userStopped)`
yields `stoppedBy` `.userStopped`, while a `stop()` that ended the
recording keeps `.stopped` (finding 7); `prepareMicrophone(nil)` and with
an unknown id are no-ops that leave it idle; and two `stop()`s while
`.arming` are both held. What a faked session cannot reach is the arm
timer (20 s) and `failStart`, which is why finding 5's row is the two
sentences and not the timer.

**Then R2a — pause and resume over the SAME faked session** (rows 3o–3t),
which stands on one more measurement: `addRecordingOutput` accepts an
output on a never-started, grant-less `SCStream`, `removeRecordingOutput`
of an added output returns, and a fresh output can be added after the
remove — while a second output beside an attached one, an output never
added, and any add after `stopCapture` all throw −3812, and no file is
ever written — so the `Fake` now ADDS its last segment's output (R1's
pre-`startCapture` order) and `pause()` / `resume()` run their real
bodies. 3o: `pause()` → `.paused`, `isPaused`, still `isRecording`, the
segment stamped, the meter silenced, the writer asked to stop ONCE,
`elapsed` read twice 0.3 s apart EQUAL (and about the second recorded), a
poll publishing nothing, a second `pause()` `.alreadyPaused` by name;
`resume()` → `.recording` with a SECOND segment minted in the choice's
folder as `Screen Recording <date> at <time>.mov` (its own start time,
never the first's name), its mic file beside it, `micRecordingCalledAt`
stamped, the ONE writer restarted to exactly that file; the closed
segment's did-finish and mic did-finish landing AFTER the resume INERT
(the state stays `.recording`, only its flags move); the new pair's
did-starts stamping segment 1 alone (found by output identity and by file
URL); a stray output and a stray file changing nothing; `resume()` while
recording `.notPaused`; a second pause; `stop()` while PAUSED beginning
finishing as `.stopped` with the pause's stamp KEPT and no second
`stopRecording`; and the walker, meeting segment 1's movie written EMPTY,
LEAVING THAT SEGMENT OUT (issue batch B17, #97; until then it failed the
recording): a `.success` of segment 0 alone with `pauses` 2, and
`unreadable[0]` segment 1's movie with both its files kept, case
`finishFailed`, the note ending " Its files are kept at <movie>, <mic>.".
3p: a refused pause (the output never added, so the remove throws)
rethrown as `.finishFailed` with the recorder STAYING `.recording` and
nothing changed. 3q: a refused resume (the state paused
BY THE PROBE with the output still attached, so the add throws) rethrown
as `.startFailed` with the recorder STAYING `.paused`, no segment minted,
no `startRecording`. 3r (rewritten by issue batch B27, #181; until then
it pinned the did-fail ENDING the recording): a did-FAIL on a CLOSED
segment (paused, its did-finish still in flight, so built with
`screenFinished = false` — the did-fail is what finishes it) leaves the
recorder `.recording` with no `screenFailure` and no writer stopped, the
segment's `outputFailure` the writer's sentence; `stop()` then stops the
open segment's writer once, and ONE `.success` lands `closedfail1.png`
alone with `pauses` 1 and `unreadable` segment 0 — both files kept, case
`finishFailed`, "The recording failed: the writer gave up" — left out
UNPROBED although its PNG would read — while its microphone,
`closedfail0-mic.png`, IS probed (issue batch B55, #181 item 2):
`unreadable[0].micPath` is that file at `position` 0. 3r2: segment 0 a NORMALLY closed
segment (the Fake's default `screenFinished`), segment 1 open; a real
`pause()`, then segment 1's did-fail → the recorder STAYS `.paused`, and
still after its microphone's did-finish; `stop()` → a `.success` of
segment 0 alone within `settled()`'s 5 s, `pauses` 2, `unreadable`
segment 1 with both files. 3s: the
pause's own did-finish inert, then an external `.userStopped` while paused
landing ONE segment with `pauses` 1 — the count is STORED per press, never
`segments − 1` (the R2 review: a pause with no resume before the stop read
0) — and, the review's other three: a NON-external stream stop while
paused LANDING as `systemStopped` rather than failing with every file
whole on disk; a did-start landing after its own segment's pause IGNORED
(the span never runs backwards); and a second resume within one second
minting a name the session does not already HOLD (three different names,
no file of any of them yet). 3t: the walker over THREE closed segments
with chosen stamps — `elapsed` 2 + 3 + 1.5 = 6.5 s with the two gaps
never counted, frozen; ONE result of three `RecordingSegment`s in order,
`pauses` 2, the result's `descriptor` and `startedAt` the first's;
segment 0's microphone never started (no file — the sentence, offset 0),
segment 1's landed with ITS OWN offset −12 000, segment 2's writer failed
(the writer's sentence naming the file it left); `micProblem` the two
sentences joined by a space in order. Beside them 3g pins
`RecorderError.notPaused`'s sentence and `filesKept` over two movies and
two microphone files, each list comma-joined.

Section 4 (`landing`) is the LANDING — `RecordingLanding.placement`,
`remainderPlacement` (R1's `microphonePlacement`, over every segment since R2) through `ProjectDocument.untitled(around:)`, and
`resolve` — lane B's fifteen scratch rows made tracked, one check per fact.
Every placement row COMMITS the op list through the document's own door
(`performGroupedEdit`, the panel's) and compares what the core minted with
what the landing predicted, so a prediction and a commit that disagree fail
by name rather than by a later beep. Row 1: a fresh 1920×1080/30 project
with an empty front track → `[add_media, add_clip]`, media 2 / clip 3
predicted and minted. Row 2: a clip already at 0 on the front track, the
playhead at 1 s → `[add_media, add_track(index: 1), add_clip(track: 5)]`,
the clip on the NEW front track at 600 000. Row 3: `place: false` → the
media op alone and no clip id; 3b with a microphone → two `add_media`s and
no clips. Rows 4a–4e: a 30 fps canvas and a microphone descriptor, the
offset rule — +12 000 at 0 → seven ops ending `trim_start`, `move_clip`,
the mic clip on the new back track "Microphone" at 0 with `in` one frame
(20 000) and its length shortened by it; −18 000 at 0 → five ops, the mic
clip at 20 000 (the core snaps 18 000 to the grid) with `in` 0; +12 000 at
1 s → five ops, the picture at 600 000 and the mic at 580 000; +3 000 at 0
→ five ops and no trim (sub-frame); 0 → five ops. The lengths are the
SNAPPED ones — `add_clip` snaps a clip's length to the frame grid, so the
3 012 000-tick microphone file becomes a 3 020 000-tick clip, which was lane
B's one wrong first expectation. Row 4f: `beginLiveEdit()` then a placement
throws "A drag is in progress; the recording can be added when it ends."
Row 5: `untitled(around:)` on the REAL `ProjectDocument` through a
subclassed `NSDocumentController` (the probe has no Info.plist, so the
shared controller cannot name a document class; the subclass answers
`defaultType` and makes a `ProjectDocument` with `fileType` set, exactly as
the plist would) — `displayName` is the recording's stem, the document is
edited, `fileURL` nil, `fileType` the package type, `canvas.fps` [60, 1]
while `media[0].fps` stays [24981, 1000] (decision 3), no undo step, one
window controller, the controller's documents 0 → 1. Row 5b: with a
microphone at +12 000 and 60 fps → two media, tracks ["Microphone",
"Track 1"], the mic clip on the back track at 0 with `in` 10 000, ONE undo
step named "Add Microphone" — not "Add Recording": the step removes the
voice and keeps the picture, and its name says what ⌘Z will do; 5c: one
undo → one media, one clip, one track, and the document is STILL edited —
`untitled(around:)` makes the import count `makeWindowControllers` would
have made BEFORE the microphone's edit, so the undo takes the count from
two to one, where the review had measured it reaching zero and ⌘W closing
a recording's document without a prompt; the redo is named the same and
puts the voice back.
Row 6: `resolve` over TWO open documents — B's key → B, A's → A, an unknown
key → `.newProject` while both are open (the mutant answering the FIRST
document fails here), B closed → B's key is `.newProject` and A's is still
A, `.newProject` → `.newProject`. Row 7: inside an open nest (`setNestPath`)
→ eight UNSCOPED ops, the picture on a new track INSIDE the nest, the nest
at three tracks with "Microphone" at the back, the document's clips still
one (the nest clip). Row 8: the caps in the TRIAL — a document filled to
`MAX_TRACKS` (64): without a microphone the picture lands on the empty
front track (no track needed); with one, `placement` THROWS the core's own
"too many tracks: 65 (max 64)" and nothing is committed — the picture goes
down with the voice, the one-list limit `RecordingLanding.placement`'s doc
records; inside a nest at the cap (63 outer tracks and the nest's one,
whose clip blocks the playhead) the picture alone throws the same sentence,
because the trial applies each scoped op to the PARENT handle — the scoped
apply itself — and `check_caps` runs on the merged parent there exactly as
at the commit (the landing's first comment said the trial could not see
it, and this row is what shows it can); one track under the cap the same
nested landing trials clean and commits the 64th track inside the nest.

Section 4b (`segments`) is the landing over a SEQUENCE (R2b) — lane L's
scratch instrument folded in, every row committed through the document's
own door and compared with the prediction, over the R2 review's
`Placement` (four lists with ONE entry per segment, nil where nothing was
minted, and `notes`). A: two segments on a fresh document → `[add_media,
add_media, add_clip, add_clip]`, `mediaIds [2, 3]`, `clipIds [4, 5]`, the
mic lists `[nil, nil]`, clip 2 starting at clip 1's END on the same
track, no transition (touching is a cut), one undo step "Add Recording",
the second add_clip SENT at 3 000 000 — the end read off the trial. B:
off-grid durations (3 000 007, 1 504 999) — each clip's length as the
core SNAPS it, each start the previous end, never a sum. C and D: a
blocker refusing the second (7–15 s) or the first (1–9 s) segment on the
front track → ALL on a new front track with the predicted id, touching
from 0, the blocker's track untouched. E: the microphone floor — voice 2
wants 3 000 000 − 11 000 and the floor is voice 1's end 3 020 000, so it
lands AT the floor with a 40 000-tick head trimmed (in 40 000, length
2 980 000), the ops `add_clip` at the floor, `trim_start` to floor + head,
`move_clip` by −head — never at 2 989 000, which the core would snap a
frame UNDER the floor and accept as a transition. E2: a lagging voice
(−30 000) above the floor, no trim. E3: offsets 4 000 / 9 999 / 10 000 /
15 000 / 31 000 AT the floor — the head is the core's snap of the
shortfall, half away from zero, so 9 999 sends no trim and 10 000 one
frame. E4: the hazard on the core directly — an `add_clip` three quarters
of a frame under a clip's end is snapped a frame early and ACCEPTED with
a transition. F: a mic-less middle segment — the mic lists THREE entries
with the middle nil (the review: an iterator over "the segments that have
a file" misaligned the two lists). G: `place: false` — three `add_media`,
clip lists all nil, no clip. H: inside a nest — unscoped ops, two clips
inside touching, the parent's one clip untouched. J: an INEXACT canvas
rate (24981/1000, decision 3's shape) — each later segment at or after
the previous end by at most a frame, and measured, clip 3 a whole frame
after clip 2's end because that end's nearest grid point is a tick UNDER
it, never an overlap, no transition. K: a voice SHORTER than its head
(the review's numbers — mic 1 ending 3 040 000, picture 2 at 3 000 000,
mic 2 an 80 ms file at +18 000) mints NO clip and ONE note naming the
file, its media still landing, no `trim_start` in the list — never the
old 20 000-tick sliver placed late. L: a microphone file under one frame
(R0 q7's 2 ms file) — no clip, a note, the pictures and voice 1 land. M:
a PICTURE under a frame in the middle — `clipIds [id, nil, id]`, a note,
segment 3 following segment 1's END. N: `remainderPlacement` with NO clip
1 (the document holds the picture's media alone) — the microphone's MEDIA
only, `[add_media]`, every clip entry nil, a note. I: `untitled(around:)`
through the real order for three segments with voices on 1 and 3 —
displayName the first's stem, canvas [60, 1], ONE undo step "Add
Recording Segments", five media, tracks [Microphone, Track 1], three
pictures touching from 0, voice 1 at 0 (3 010 000 long on the 60 fps
grid) and voice 3 at the 60 fps snap of picture 3's start − 11 000, one
undo leaving segment 1 alone with the document STILL dirty; one segment
with a voice → "Add Microphone" (R1's name) with a 10 000 head; one alone
→ no undo step; `remainderActionName` and `remainderPlacement(...) == nil`
pinned as pure calls.

Section 5 (`chrome`) is the CHROME's structure, lane C's 64 scratch rows
made tracked: a probe compiled over `app/Sources` that instantiates
`AppDelegate()` and runs `applicationWillFinishLaunching` (`phase6_chrome.py`'s
menu instrument), with the seven `FrameJobRecording…` keys pinned in the
argument domain as the harness pins them. The File menu's row after "New
Project" is "New Recording…", key `n`, modifiers ⌥⌘, action `newRecording:`,
target nil, exactly one; `validateMenuItem` while idle answers true and
leaves the title; the welcome window's three `StickerButton`s are Open
Video… / New Project / New Recording… with the third's action
`newRecording:` and no target; the panel is an `NSPanel` whose style mask
holds `.nonactivatingPanel`, `.titled` and `.closable`, level `.floating`,
`hidesOnDeactivate` false, `isExcludedFromWindowsMenu`, `isReleasedWhenClosed`
false, no delegate, titled "New Recording", Record Into's first row "New
Project", Microphone's "Off", Source = `NSScreen.screens` + a separator +
"Window…" (tag 1), the Record button "Record" in `DS.meterClip`,
`currentChoice()` at the defaults, phase idle, the meter 120 pt wide, the
content 500 pt wide; `setNote` of a long sentence grows the window keeping
its top edge and `setNote("")` shrinks it back; `AccentButton`'s default
fill is `DS.accent` and a passed colour is stored; `RecorderStatusItem.label`
at 0 / 61.9 / 3661 / −3; and `LevelMeterView(meter:)` over a fresh meter
renders byte-identical to a default view at rest, while a 0.9 peak published
to the fresh meter changes ITS render and not the default's. **Two rows lane
C could not write**, because they need the recorder in a state no probe may
put it in through the front door: with `ScreenRecorder.shared.state` set to
`.recording` BY THE PROBE — the setter is internal, a probe-only
manipulation, reset to `.idle` in the same run — `validateMenuItem` retitles
the item "Stop Recording" and `applicationShouldTerminate` answers
`.terminateCancel` (and brings the panel forward); back at `.idle` the title
is "New Recording…" and, the export queue being idle, the reply is
`.terminateNow`.

**Then the R1 review's chrome fixes** (lane P2), in rows 5h–5o. 5h is
STRUCTURAL over the source (comment-stripped), the reads a running panel
cannot show: `+Recording.swift` and `+Grants.swift` gate no grant ask on
`canAsk` and `+Grants.swift` still asks on a press (fix 1), the countdown and
the tick are added in `.common` run-loop modes (fix 6), `microphoneAnswered`
(`+Grants.swift` since the grants moved) guards visibility and re-enables
the button (fix 9), `beginCountdown` prepares the microphone and every exit
discards it (fix 11), the attempt is numbered and bounded (fix 2), and
`newRecording` routes through all three doors (fix 12); `+Landing.swift`'s
`land()` compares the document's handle (fix 3). 5i–5o are DRIVEN through the
panel's own internal setters, each reset in the same run: the countdown grows
the card and `fitWindowToContent` constrains its bottom onto the screen (fix
5, `no-constrain`); `show()` beeps and shows nothing while
`hiddenForRecording` (fix 7, `show-while-hidden`); `record(_:)` over the
Window… row with no filter stays idle with the choose-a-window note (fix 8,
`window-row-unguarded`); a `rebuildDestinations` while `.recording` leaves
the rows untouched (fix 4, `sync-while-recording`); a stale arm ceiling is
ignored and the current one fails to idle with the 20 s sentence (fix 2,
`arm-no-generation`); `landingNote` is a pure function of the stop reason,
the chosen destination and the microphone problem (fix 10); and
`newRecording` with the recorder recording and the panel idle stops the
recorder rather than showing the panel (fix 12, `route-to-show`).

**Then R2c** (rows 5p–5u, the `chrome-pause` mode — its own process, so
the panel and the delegate are fresh). 5p: `RecorderStatusItem`'s pure
vocabulary — `menuTitles(paused:)` `[Pause Recording, Stop Recording]` /
`[Resume Recording, Stop Recording]`, the two tooltips, `pauseGlyph` ❚❚,
and `title(elapsed:paused:)`: "● 1:01" with the dot in `DS.meterClip` and
the time uncoloured in monospaced digits, "❚❚ 1:01" with NO colour
attribute on the glyph (the menu bar's own) and the frozen time. 5q: the
panel's `.paused` phase drawn — Stop enabled, the controls locked, the
footnote the glyph and the time in `DS.textFaint`; `.recording`'s coral
dot; `.idle`'s folder. 5r: `pauseRecording()` / `resumeRecording()`
against a recorder that refuses (idle) — a pause beeps and STAYS
`.recording` with no note; a refused resume stays `.paused` and keeps the
sentence as `resumeProblem` STATE drawn into the note at once, a second
refusal REPLACING it (one copy, never two), a live `microphoneProblem`
composed in FRONT of it by the tick and left there by a second tick (the
R2 review: the tick used to wipe it), `liveNote` pinned pure over the
four combinations; then a REAL pause and resume through the panel over a
faked session built on `ScreenRecorder.shared` (a probe-only
manipulation, torn down to idle in the same run): the phase follows the
recorder's own transitions, the footnote goes from "● 0:02" to "❚❚ 0:02"
and HOLDS through a later refresh, a stale `resumeProblem` is cleared by
the resume that lands, and `stopRecording()` while paused goes to
`recorder.stop()` (`.stopping`, the recorder `.finishing`, `stopAsked`).
5s: `revealIfNoted` both ways — `showWhenLanded` with an EMPTY note stays
hidden and clears the flag, with a note comes back, with the panel not on
screen before stays hidden; `revealControls()` (the quit guard's call)
shows the panel when nothing has it hidden and beeps with no item to
open; `landingNote`'s `.userStopped` sentence naming the SYSTEM's
screen-recording indicator, and its two R2 arguments — a refused resume's
sentence, then the placement's notes LAST. 5t: New Recording… with the
panel `.paused` stopping THROUGH THE PANEL; the recorder `.paused` (probe-
written, reset) retitling the item Stop Recording and cancelling ⌘Q. 5u,
structural over the comment-stripped source, the reads no headless
process can drive: `recordingDidStart` hides the panel for EVERY source —
`hiddenForRecording = true` and `orderOut` with no `.picked` in the body
— remembers `showWhenLanded` and hands the item the three closures;
`recordingEnded` clears the flag and shows NOTHING; the three ends call
`revealIfNoted()`, whose body conjoins `showWhenLanded` with a non-empty
note; `update` rebuilds the item's menu only when `paused` FLIPS and
ignores the argument once `freeze()`d, which the tool's chrome calls too;
the tick runs through `.paused` and passes `paused:`; `newRecording`
names `.paused`; the tool's chrome (`AgentServer+RecordingChrome.swift`
since issue batch B27) passes the three closures and
`paused: recorder.isPaused`; `show()`'s guard is unchanged; `+Pause.swift`
keeps `resumeProblem` and clears it on a landed resume; `landed` passes
`resumeProblem` and the notes, `failedToLand` names the files through
`filesClause`; closing the panel during `.starting` stops or abandons the
attempt; the quit guard calls `revealControls()`, which opens the item's
menu; and the welcome button's action is `showRecorderPanel`, which only
shows (5c and 6a read the live button). What no headless probe can do is
put the status item UP — `show()` would put a real item in this
machine's menu bar — so the menu's rebuild is a structural read and the
`menu-static` mutant is caught there.

Section 6 (`welcome`) is the welcome window's CROSS-BUILD — `phase5_chrome.py`'s
pattern: the tree one commit before the button existed, `git archive`d into
`work/recordingprobe/before/` and compiled with its own Rust core and header,
using THIS tree's `harness/main.swift` under `-D HARNESS_REFERENCE_BUILD`.
The reference is found by a pickaxe on the button's
title (`git log -S"New Recording" -- app/Sources/WelcomeWindowController.swift`,
the LAST hash + `^`; HEAD while the change is uncommitted), because the
file's adding commit is the initial commit and `--diff-filter=A` would name
the wrong tree. The reference's buttons are still the pill (spec §11 SH-1:
⌈textWidth⌉ + 38 by 34); the tree's are SH-4's square block (issue batch
B49, #100: ⌈textWidth⌉ + 32 by 28, on `bounds.insetBy(0.5)`). Both harnesses
render `welcome` in both appearances. 6a reads the live layout through the
probe's own `welcome` mode with the vendored fonts registered: each
intrinsic size and frame, the row Σ (⌈textWidth⌉ + 32) + 2 × 12 wide,
28 tall and centred at x = 360, and each button's own bitmap sampled at
(1.5, 1.5) and (1.5, mid-height) — one opaque fill for a square block, a
clear corner for a pill. 6c is the shape (1440×1200, four channels) and a
determinism pair (two renders of this tree, byte-identical). 6d: the
welcome column is centred on its height, so the 6 pt shorter row moves
everything above it 3 pt down and everything below it 3 pt up. The diff is
read inside the BAND of the reference's row — full width, 34 pt from the
laid-out top less 3 — and its extent must be x from the row's left + 0.5
(the primary's fill, no stroke) to its right (the secondary's 1 pt stroke)
and y the pill row's ink 3 pt higher (1.25 to 32 pt down the band: the
pill's 1.5 pt stroke overhang and its 2 pt shadow), the row's y DERIVED from
that bottom edge and compared with the laid-out frame. Nothing in the band
changes outside the new row's x-span. Above the band every pixel row must
equal the reference's 3 pt higher, and below it the reference's 3 pt lower,
the strips at the two edges equal in place — no tolerance; a mismatch
prints its count and first rows. The lockup's own rows are left out of the
"above" comparison, because rename R2 changed the mark and the wordmark
(spec §11 NM-11): the probe's `welcome` mode reports the lockup's frame,
its rows are the render's from ⌊top × scale⌋ to ⌈bottom × scale⌉, how many
of them differ is printed, and a missing frame fails the row. The old
two-button row lies inside the band and the new row's x-span. The in-band
clusters are PRINTED and never counted as one, and a scored row asks that
the reference was compiled with this tree's own harness. A new mode that
names a type absent from the old tree must respect the reference guard or
the build fails by name. Section 6 renders through the TREE's harness
(`build.sh` hard-codes `app/Sources`), whatever `--sources` says, so a
`--mutant` changes only the probe — 6a's samples and layout; the mutant
that turns the button's action is caught by section 5's structural read,
which is what a pixel cannot see.

Section 7 (`catalog`) is the toll's gate from the inside:
`AgentServer.shared.catalogJSON()` — the very string the startup parity
check reads — parsed for its 75 names, the 55 core ops (`ReelOp.coreNames()`)
plus the twenty app-state tools; the LAST twelve in the order the old file
had them (`import_media`, `import_captions`, `consolidate_media`,
`add_media`, `relink_media`, `remove_media`, `transcribe`,
`export_captions`, `render_frame`, `export` — `7a198db^`'s order — with
`set_media_color`, which 2a8421b added among the media rows, after
`remove_media`, then `record_screen`); `scope` on every op tool's schema and on none of the
twenty, `record_screen`'s among them; and `record_screen`'s declared
argument names. 7d (R2d): the tool's description names the two menus'
rows, `pauses`, `segments`, `started_at`, `mic_offset`, `mic_problem`, the
two undo names, the wall-clock span, the TOTAL, `user_stopped` and the
system's screen-recording indicator.

Section 8 (`host`): CGPreflightScreenCaptureAccess(), the microphone's
status word, the console lock (`CGSessionCopyCurrentDictionary()`'s
`CGSSessionScreenIsLocked`) and the active display count — PRINTED, never
asserted, so a reader of a probe log knows which tiers of
`recording_proof.py` could have run on that machine.

Section 9 (`granted`) is the probe's own GRANTED tier (R2e), the one
section that starts a stream: under this process's grant (R0 q1: a
shell-launched Mach-O runs under its TERMINAL's; the spike showed a bare
probe can start a stream) and with a shareable display, a real
`ScreenRecorder()` — never `.shared` — on the main display, the folder
pinned under `work/` by `-RCRecordingFolder` and deleted after. 9a:
start, 1 s, `pause()`, `elapsed` read twice 0.5 s apart and EQUAL, the
removed output's did-finish landing while paused (R0 q7's 5–25 ms),
`resume()`, the new output's did-start (8–10 ms), 1 s, `stop()` → ONE
result of TWO segments with `pauses` 1, each movie probing with pictures
at about a second, the two names DIFFERENT and each the local-time
spelling of ITS OWN start, segment 2's start ≥ 1.9 s after segment 1's,
elapsed before the stop about 2 s against a wall clock at least 0.8 s
longer, both files on disk with bytes. 9b: start, 1 s, pause, stop while
paused → one segment with `pauses` 1 (the press is counted, not the
files). 9c: the PANEL end to end over `ScreenRecorder.shared` — Record
over the main display, the countdown, then at `recordingDidStart` the
panel HIDDEN with `showWhenLanded` remembered true, the item up, `show()`
showing nothing; `pauseRecording()` → "❚❚ 0:01" faint and HELD through the
30 Hz tick, `resumeRecording()` → two segments, `stopRecording()` → the
landing as a new project, after which the panel STAYS HIDDEN because the
note is empty (decision 7 driven, not read), the item down, the recorder
idle, and the document holding two media and two touching clips under
"Add Recording Segments" at [60, 1]. Without the grant or with zero
shareable displays the tier is SKIPPED BY NAME with its row count printed
— the count is taken by running the same row code over an empty answer
with `check` swapped for a counter, so it cannot drift from the tier —
and the summary line says so; never a vacuous pass. The microphone is
not used here: the probe has no usage string, and a prompt would abort
it. **On the host this was written on the console was LOCKED for every
run** (0 shareable displays under a TRUE preflight, the state phase 8
recorded), so the tier compiled and skipped, and its rows are unmeasured
until somebody runs the script with the console unlocked.

Section 10 (`grants`) is the press's grants (spec §11 recording: the first
press asks for Screen Recording, every later one opens System Settings at
the pane, and only in a launchd-owned launch). 10a: `screenStep` over all
eight combinations of granted, asked and `launchedByLaunchd` — granted
proceeds, a shell launch always asks, a launchd-owned press that has asked
opens the pane, else it asks. 10b: `microphoneStep` — authorized proceeds,
`notDetermined` asks, denied and restricted open the pane. 10c: the two
URLs' exact `absoluteString` and scheme; `NSWorkspace.urlForApplication(toOpen:)`
resolving each to `/System/Applications/System Settings.app` (resolved,
never opened); and, read by Python, `SecurityPrivacyExtension.appex`'s
Info.plist (`legacyBundleIdentifier` the URLs' host, the URL-scheme flag
true) and its binary's bytes (both anchors present). 10d:
`screenRecordingOpenedNote` is the pane sentence, the opened sentence and
`launchClause`; `microphoneOpenedNote` keeps the refusal's head and fix.
10e: DRIVEN through `RecorderPanelController.shared.record(nil)` with one
spy per row — an in-memory asked flag, the launchd answer, prompt counters,
the URLs handed to the opener and the Bool it answers, the microphone
prompt's completion HELD; `show()` is called once before the rows (it
rebuilds the microphone popup) and a fake `probe-mic` row added after it.
Launchd-owned: 1 ungranted asks once, opens nothing, sets the flag; 2 the
next press opens the Screen Recording pane with the opened note and asks no
more; 3 an opener answering false leaves the plain refusal; 4 and 5 a
denied or restricted microphone opens the Microphone pane with no prompt;
6 `notDetermined` asks once with the button disabled, and the held answer,
fired with the status now denied, re-enables it with the refusal and opens
nothing; 7 authorized and 8 Off count down with nothing called; 9 granted
leaves the flag false. Shell-launched: 10 two presses ask twice, open
nothing and never write the flag; 11 a flag already true still asks. 10f,
structural over the comment-stripped source: `CGRequestScreenCaptureAccess(`,
`requestAccess(` and `NSWorkspace` in no `AgentServer+Recording*` or
`ScreenRecorder*` file; `x-apple.systempreferences` only in
`RecordingSetup.swift`; `CGRequestScreenCaptureAccess(` only in
`+Grants.swift`.

Section 11 (`unreadable`, issue batch B17, #97) runs in its own process
with `RCFFmpegImport` merged into the volatile argument domain as `never`
before any probe, so an EMPTY `.mov` never reaches `FFmpegRewrap`'s
consent alert; a readable "movie" is `writePNG`'s PNG. Over the Fake, mic
on, every segment closed, `.paused`, then `stop`: U1 [PNG, EMPTY, PNG] → a
`.success` of segments 0 and 2 in order, each with its microphone, `pauses`
2, `unreadable` segment 1 alone with both its files kept and case
`finishFailed`, the note "A segment was left out. <the probe's sentence>
Its files are kept at <movie>, <mic>." exactly, and the stop's completion
the same outcome, once — and (issue batch B55) segment 1's microphone PNG
READ although its movie did not: `unreadable[0].micPath` is it, `position`
1. U2 [EMPTY, EMPTY], every microphone a readable PNG → the recording
still FAILS (spec §11 recording: no readable movie, no result) with
`filesKept(finishFailed)` naming both movies, then both microphone files,
and both microphone files are still on disk after it (`micsOnDisk`, B55).
U7 (B55) [no movie file at all, twice], readable microphones →
`filesKept(finishFailed)` ending " The microphone is at <mic 0>, <mic 1>."
— `namingFiles` names the microphone files when no movie is on disk.
U3 [EMPTY, PNG] with no
microphone → a `.success` whose `path` and `startedAt` are the SECOND
segment's. U4, pure: `UnreadableSegment("/x/a.mov", [], .timedOut)`'s
sentence exactly, one with two files kept, and an empty list's note nil.
U5: `landingNote(… unreadable:)` puts the sentence after the closed
document and before the microphone, and `unreadable: nil` equals the R1
call. U6: `recordingFields` carries `unreadable` —
`[{path, kept_files, reason, mic_path, mic_duration}]` for U1's result,
whose left-out microphone read (B55) — only when non-empty; `resultNotes`
is [unreadable, the left-out voice's note, microphone] (B55);
`savedButNotAdded` ends with the note and never says "was added to the
project" (B55), and a clean result's sentence is R1's. M1: a `.recording` Fake with a
microphone, `pause()`, then a microphone did-finish carrying −11805 →
`microphoneProblem` nil, `liveNote` empty, the segment's `micFailure`
set; the screen's did-finish and `stop` → a `.success` whose segment 0
`micProblem` begins "The microphone recording failed: " (3k stays the
mid-segment control).

Section 12 (`file_pause`, issue batch B17, #98 a and b) runs in its own
process with the menu bar built by `applicationWillFinishLaunching`. F1:
the item directly after New Recording… is "Pause Recording", action
`pauseOrResumeRecording:`, nil target, no key, and exactly one item in the
bar sends it. F2: `validateMenuItem` with `ScreenRecorder.shared.state`
set by the probe — idle, arming and finishing disabled "Pause Recording";
recording enabled "Pause Recording"; paused enabled "Resume Recording" —
each the status item's own `menuTitles(paused:)[0]`. F3: a faked session
on `ScreenRecorder.shared` (chrome-pause's shape) with the panel
`.recording`: the action → both `.paused`; again → both `.recording`, two
segments. F4: the panel idle, the recorder `.recording` (a tool's
recording): the action pauses the recorder, the panel idle and not shown;
again resumes it. F5: both idle → nothing changes. W0 prints the widths of
"● 0:00" and "❚❚ 0:00". W1: every title for 0, 59, 61.9, 599, 3599, 3661
and 35 999 s, both marks, fits: ceil(width) + 2 × `titleInset` ≤
`itemLength`. W2: `itemLength` is that formula at `widestElapsed`, whose
label is 9:59:59. W3, structural: `show()`'s comment-stripped body holds
`statusItem(withLength: Self.itemLength)` and the file's code never says
`variableLength` — the probe never puts the item up. **Issue batch B27
(#181 item 4)**: F6 — a counting observer of
`ScreenRecorder.pauseDidChangeNotification` (object `ScreenRecorder.shared`)
installed before F3: F4's pause action posts ONCE, counted before any spin,
with `isPaused` true inside the block; its resume action once more with
`isPaused` false; F5 posts nothing (F3's panel-path posts are printed, not
asserted). F7, structural over the comment-stripped
`AgentServer+RecordingChrome.swift`: `show`'s body adds an observer for the
notification with `object: recorder` whose block calls `tick()`, and
`remove()` calls `removeObserver` — the item itself is never put up.
**Issue batch B42 (#193 items 1 and 2)**: F8 — a counting observer of
`ScreenRecorder.finishingDidBeginNotification` (object
`ScreenRecorder.shared`) installed before F3: F3–F5 post none; then a
faked tool's recording, paused by the action, and File ▸ Stop Recording
(`newRecording`) → ONE post, counted before any spin, with the recorder
`finishing` inside the block; after the call the panel is idle and not
shown and the recorder `.finishing`. F9, structural like F7: `show`'s body
adds an observer for that notification with `object: recorder` whose block
calls `freeze()`, and `remove()` calls `removeObserver(finishObserver)`.
F10: a stale `resumeProblem` with the panel idle, `beginCountdown()` → nil,
the phase read straight after a countdown; `cancelCountdown()` and
`disarmTick()` → idle; the choice's microphone is printed, not asserted.

Section 13 (`preroll`, issue batch B27, #98 c) runs in its own process and
reads the Microphone status BEFORE touching a device, so it cannot prompt;
with a status other than `.authorized`, or no qualifying device, its rows
are SKIPPED BY NAME with their count (`preroll_rows_count`, the granted
tier's counter). The device is the first of the app's own
`DiscoverySession([.microphone, .external], .audio)` list whose transport
is built in, else USB — never a virtual or aggregate input, which reads a
flat floor. P0 prints the status word, the device and its transport. P1: a
fresh `ScreenRecorder()` — never `.shared` — `prepareMicrophone(id)` →
prepared for that device, running, `.idle`. P2: 30 polls at 1/30 s → max
`peakLeft` above 1e-6 (−120 dBFS), `.idle` throughout. P3:
`discardPreparedMicrophone()` → the reading silent, nothing prepared, and a
later poll publishes nothing. P4: `RecorderPanelController.shared` — shown,
the main display and the device selected, a `GrantSpy` granted and
authorized — `record(nil)` → the countdown with the device prepared on
`.shared` and nothing asked; 1.2 s later still counting, the recorder idle,
and an observer on `ScreenRecorder.shared.meter` saw max `peakLeft` above
1e-6. P5: `record(nil)` (Cancel) → the panel and the recorder idle, the
session let go, the reading silent at once and 0.3 s later with no
non-silent publish after the cancel. The countdown never reaches 0; the
sealed doors are restored and the panel ordered out.

Section 14 (`leftout`, issue batch B55, #181 item 2, spec §11 recording)
runs in its own process with `ProbeDocumentController` first, as
`segments` does, over results CONSTRUCTED with no stream: A a 5 s picture
with a 5 s voice at offset 0, B left out with a 3 s voice that read, C a
5 s picture with a 5 s voice, the choice at 60 fps. X1: a fresh document
(30 fps) at playhead 0 — stretches [segment 0, B's voice, segment 1];
picture A at 0; B's voice at 3 000 000, 1 800 000 long, `in` 0, on the
Microphone track; picture C at 4 800 000 on A's track; C's voice at
4 800 000; no picture clip in [3 000 000, 4 800 000); five media and five
clips predicted and minted, both left-out lists included; "Add Recording",
no note. X2: B at position 0, playhead 1 s — the voice at 600 000, picture
A at 2 400 000, C at its end. X3: X1's result through `untitled(around:)`
— the voice at clip 1's end, 1 800 000 long, on the Microphone track,
picture C 1 800 000 after clip 1's end, "Add Recording Segments",
`newProjectLeftOutIds` naming the voice, one undo leaving picture A alone.
X4: B before a new project's only segment (no voice of its own) — media
with no clip, `leadingVoiceNote`'s sentence in the notes, "Add
Microphone" (and "Add Recording Segments" when B's voice did not read).
X5: `place: false` — the voice's media in the left-out list, no clip. X6:
`recordingFields`' `unreadable[0]` carries `mic_path`, `mic_duration`,
`mic_media` and `mic_clip` (X1's ids); `resultNotes` is [unreadable, the
voice's note]; `savedButNotAdded` never says "was added to the project";
`record_screen`'s description says "without its picture". X7, the
control: a left-out B whose voice did NOT read gives X1's document the
byte-identical op list of the same result without B. X8 (issue batch B61,
#213): a new project whose only segment's picture A0 is 5 000 ticks — under
one 60 fps frame, so the core mints no clip for it (the control, 4b·M's
precedent) — with a 5 s voice of its own and B left out after it: both
voices land as media with no clip, and the notes are exactly
`unplacedNote`'s sentence for A0's voice, then for B's.

**Measured 2026-10-01 by issue batch B55**, `--only
state,unreadable,landing,segments,catalog,leftout`: 470/470 — the build
row 1; section 3, 141; section 11, 30; section 4, 164; section 4b, 83;
section 7, 28; section 14, 23. The `landing` and `segments` rows, unedited,
are the control that a recording with no left-out voice lands as before.

**Measured 2026-09-28 against the tree with section 10: 983/983, with no
row skipped** — section 9 RAN (a true preflight and two shareable
displays). By section: the build row 1; section 1, 21; section 2, 242;
section 3, 133; section 4, 164; section 4b, 83; section 5, 117 (5h's
`+Grants` "in the sources" row added); 5p–5u, 59; section 6, 28; section 7,
27; section 8, 1; section 9, 42; section 10, 65. `--only chrome,grants` is
183/183. Since then section 10e gained one row (the panel steps down to
normal level for every prompt or pane, 2026-09-28): `--only chrome,grants`
measured 184/184, so the whole run is 984 rows; it has not been re-run
whole since.

**Measured 2026-09-12 against the tree after R2's fix wave: 876/876**, with
section 9's 41 rows SKIPPED by name (the console was locked — 0 shareable
displays under a TRUE preflight) and counted in the summary line rather
than passed. By section: the build row 1; section 1, 21; section 2, 242;
section 3, 133 (R1's 76, then 3g's two R2 sentences and 3o–3t's 55);
section 4, 164; section 4b, 83; section 5, 116; 5p–5u, 59; section 6,
28; section 7, 27 (7d's 14 among them); section 8, 1; section 9, 1 plus
the 41 skipped. The four rows the first run against the landed wave
failed were all the script's own expectations and no defect: 3o's
second-pause span is measured from the DRIVEN did-start stamp (about
1.4 s, not 2), 3s read an intermediate state the wave's synchronous
`checkFinished` now passes through inside the spin (the landed result was
right), and 4b·J's gap at the inexact rate is exactly `frameDuration`,
the band the code documents as `≤ frame` where the row had `< frame`.

The gate, on COPIES of `app/Sources` under `work/` (`--mutant <name>`,
`phase9_chrome.py`'s `prepare_mutant` shape, which points `--sources` at
the copy); every name kills. The four section-4 names (`no-import-count`,
`mic-trim`, `resolve-first`, `fps-override`) were re-measured on
2026-09-11 after the review's fix wave, against a tree scoring 620/620
(section 4 is 164 of those, eleven of them the wave's — 5c's two dirty
rows and row 8's nine); the other four stand as measured earlier that day
against 559/560, when 6b's "one program" row was the tree's one failure
(it has since turned green, so their denominators read 560 below):

  excludes         `excludesCurrentProcessAudio = true` → `false`
                   (RecordingSetup.swift) — 543/560, the sixteen section-2
                   rows that read the field.
  fps-override     `makeProject`'s `fps:` parameter ignored
                   (ProjectDocument.swift) — 617/620: 4·5's canvas.fps,
                   4·5b's canvas.fps and its in point (the head snaps to
                   the file's 24981/1000 grid instead of the 60 fps one).
  resolve-first    `resolve` answers the FIRST open document instead of
                   the `recipeKey` match (RecordingLanding.swift) — 616/620,
                   four 4·6 rows (B's key → A; an unknown key → A twice;
                   B's key after B closed → A).
  welcome-action   the welcome button's action → `newProject:`
                   (WelcomeWindowController.swift) — 557/560: 5c's third
                   button and 6a's live read; no pixel row moves, which is
                   why the structural read exists.
  retitle          `validateMenuItem`'s retitle line deleted
                   (AppDelegate.swift) — 557/560, 5g's two title rows.
  quit-guard       `applicationShouldTerminate`'s recording guard deleted
                   (AppDelegate.swift) — 557/560, 5g's .terminateCancel
                   and the panel brought forward.
  no-import-count  `untitled(around:)`'s import count deleted
                   (ProjectDocument+Recording.swift) — 619/620:
                   4·5c's "still edited after the undo" row, the review's
                   ⌘W-without-a-prompt.
  mic-trim         `addMicrophoneClip`'s trim dropped, a negative start
                   placed at 0 untrimmed (RecordingLanding+Microphone.swift) —
                   613/620: 4·4a's op list, start/in, length and the
                   trim/move pair, 4·5b's in point, 4·7's op list and head.
  busy-finishing   `stop()` while `.finishing` answers `.busy` again
                   (ScreenRecorder+Stop.swift) — 617/620, measured against a
                   tree at 620/620: 3i's second stop answered at once,
                   the joined completion receiving `.busy`, and the three
                   outcomes no longer one.
  no-oneshot       `isSettling` always false, the settling guard removed
                   (ScreenRecorder+Finishing.swift) — 617/620: 3j's flag,
                   3j's `onFinish` called FOUR times (the stopCapture
                   completion, the direct `checkFinished`, the duplicate
                   did-finish — each a second settle), and 3k's once row.
  mic-fails-all    `settle` returns the microphone failure BEFORE the
                   movie probe (ScreenRecorder+Finishing.swift) — 618/620:
                   3k's `.success` row (a `filesKept(finishFailed)`
                   instead) and its `micProblem` row.
  no-path          the path clause not appended in `conclude`
                   (ScreenRecorder+Finishing.swift) — 618/620: 3l's two
                   naming rows, the case reading `finishFailed` bare.

Lane P2's, the R1 review's chrome fixes (section 5's rows), measured
2026-09-11 against a tree at 662/662:

  canask-restored  the grant ask gated on canAsk again
                   (RecorderPanelController+Recording.swift) — 661/662:
                   5h's "gates no grant ask on canAsk" (fix 1).
  no-handle-check  land() no longer compares the document's handle
                   (RecorderPanelController+Landing.swift) — 661/662:
                   5h's handle-comparison read (fix 3).
  sync-while-recording  rebuildDestinations runs during a recording
                   (RecorderPanelController+Rows.swift) — 660/662: 5l's
                   two rows, the seeded row rebuilt away (fix 4).
  no-constrain     the grown card is not constrained to its screen
                   (RecorderPanelController+Showing.swift) — 661/662: 5h's
                   fitWindowToContent read — NSWindow.setFrame re-seats an
                   off-screen titled panel on this multi-display host, so
                   the source read is the kill and not the geometry (fix 5).
  show-while-hidden  show() un-hides the panel into a picked recording
                   (RecorderPanelController+Showing.swift) — 661/662: 5j (fix 7).
  window-row-unguarded  Record over the Window… row with no filter falls
                   through (RecorderPanelController+Recording.swift) —
                   660/662: 5k's two rows (fix 8).
  arm-no-generation  the arm ceiling ignores the generation
                   (RecorderPanelController+Recording.swift) — 661/662:
                   5m's stale-ceiling row (fix 2).
  route-to-show    New Recording… shows the panel instead of stopping a
                   tool's recording (AppDelegate+Recording.swift) —
                   660/662: 5h's routing read and 5o (fix 12).

**Road map 3, R2's mutants**, one per rule, measured 2026-09-12 against
the tree at 876/876 with section 9 skipped (the locked console) — except
`elapsed-through-pause`, during whose run the display happened to wake,
so section 9 RAN and its denominator is 917; that run is also the one
measurement of the granted tier on this host, 37 of its 41 rows passing
under a mutant that touches none of them and the other four being that
mutant's own kills:

  segment-stacked      `at = landed.end` deleted in placeBackToBack
                       (RecordingLanding+Placing.swift) — 811/871: every
                       4b sequence row (A–D, F, H, J–M, I), the second clip
                       refused against the first on both tracks, so a
                       throw where a list was expected; the denominator is
                       871 because a row that throws skips its reads.
  mic-floor-dropped    `floor = placed.end` deleted in addMicrophones
                       (RecordingLanding+Microphone.swift) — 863/876: 4b·E's
                       voice 2 landed a frame under the floor with a
                       transition, E3's three trimmed offsets, K's three.
  menu-static          `rebuildMenu(paused: paused)` deleted from update
                       (RecorderStatusItem.swift) — 875/876: 5u's read of
                       update's body. Structural, and honestly so: the
                       probe never puts the item UP.
  hide-picked-only     recordingDidStart's hidesForRecording guard narrowed
                       to `source == .picked`
                       (RecorderPanelController+Recording.swift) — 875/876:
                       5u's read; 9c's driven kill sits in the skipped tier.
  reveal-always        revealIfNoted's note test dropped
                       (RecorderPanelController+Landing.swift) — 874/876:
                       5s's empty-note row (the panel came back) and 5u's
                       read of the conjunction.
  elapsed-through-pause  every segment counted to now (ScreenRecorder.swift)
                       — 909/917: 3o's frozen pair and second-pause span,
                       3s's late did-start span, 3t's 6.5 s, and — the
                       tier having run — 9a's frozen pair and 2 s against
                       the wall clock, 9b's pair, 9c's held footnote.
  resume-first-offset  `result` reads the FIRST segment's stamps
                       (ScreenRecorder+Finishing.swift) — 875/876: 3t's
                       segment-1 offset (0 for −12 000).
  resume-no-segment    `session?.segments.append(segment)` deleted
                       (ScreenRecorder+Pause.swift) — 859/876: 3o's seventeen
                       rows after the resume, 3s's two, 5r's real resume.
  pause-no-mic-stop    the writer's stopRecording dropped from pause()
                       (ScreenRecorder+Pause.swift) — 873/876: 3o's three
                       stop counts.

Four R1 mutants were RE-AIMED at the wave's rewritten lines and
re-measured (the old text no longer occurred once, which `prepare_mutant`
refuses): `mic-trim` is now `head` forced to 0 in addMicrophoneClip —
857/876 (4·4a, 4·5b, 4·7, 4b·E, E3's three, I2, K); `quit-guard` deletes
the guard whose call is `revealControls()` — 872/876 (5g's two, 5t, 5u);
`welcome-action` turns `showRecorderPanel(_:)` — 873/876 (5c, 6a, 5u);
`mic-fails-all` returns the FIRST segment's micFailure before the probes
(the field moved from the session to the segment; the R1 text no longer
COMPILED, which scored 0/1 and is exactly what the build row is for) —
867/876 (3k's two, 3t's seven). The other sixteen R1 mutants re-scored
against 876 on the same day: excludes 860, fps-override 868, resolve-first
872, retitle 873, no-import-count 874 (4·5c's dirty row and 4b·I's),
busy-finishing 873, no-oneshot 872, no-path 872, canask-restored 875,
no-handle-check 875, sync-while-recording 874, no-constrain 875,
show-while-hidden 874, window-row-unguarded 874, arm-no-generation 875,
route-to-show 874 — every one below the count.

**The grants' mutants** (section 10), measured 2026-09-28 with
`--only chrome,grants` against 183/183, and re-measured the same day against
184/184 when 10e gained its level row: each scored exactly one more (the
level row passes under each), so each figure below is +1 of 184 today:

  ask-every-press   `screenStep` ignores `asked` → `.ask` (RecordingSetup.swift)
                    — 178/183: 10a's asked-and-launchd row, 10e 2's three
                    rows, 10e 3's tried pane.
  open-first-press  `screenStep` always `.openPane` for an ungranted press
                    (RecordingSetup.swift) — 170/183: 10a's three ask rows,
                    10e 1's four, 10e 2's two, 10e 10's three, 10e 11.
  asked-forgotten   the `rememberScreenAsked()` call deleted
                    (RecorderPanelController+Grants.swift) — 179/183: 10e 1's
                    flag, 10e 2's three rows.
  shell-remembers   the `if owned` guard on `rememberScreenAsked()` dropped
                    (RecorderPanelController+Grants.swift) — 182/183: 10e 10's
                    flag row.
  shell-opens       `screenStep`'s launchd arm deleted (RecordingSetup.swift) —
                    181/183: 10a's shell-and-asked row, 10e 11.
  mic-denied-asks   `.denied` → `.ask` in `microphoneStep` (RecordingSetup.swift)
                    — 179/183: 10b's denied row, 10e 4's three rows.
  panes-swapped     the two pane anchors swapped (RecordingSetup.swift) —
                    177/183: 10c's two URLs, 10e 2, 3, 4 and 5's opened URL.
  opened-claimed    the opener's answer ignored in the screen arm
                    (RecorderPanelController+Grants.swift) — 182/183: 10e 3's
                    plain-refusal row.

`canask-restored` was RE-AIMED at `+Grants.swift`'s live `requestScreen`
line when the ask moved there; `Transcriber.canAsk` no longer exists, so the
copy does not compile and scores 0/1 on the build row, as it did before the
move. `window-row-unguarded` re-scored 181/183 (5k's two rows), 182/184 today; under the
sealed doors its fall-through meets no prompt. Emptying
`stepAsideForSystemUI()` scores 183/184: the level row alone.

**Issue batch B17's mutants** (sections 11 and 12, and 3o), measured
2026-09-30 against the tree at 161/161 for `--only state,unreadable` and
34/34 for `--only file_pause` (the selected run
`--only state,unreadable,file_pause,landing,segments,chrome,chrome_pause,catalog,grants`
scored 711/711, and the whole run 1045/1045 with no row skipped, section 9
running). Three of them put back the code before the batch:

  unreadable-fails-all  the walker's failure arm concludes with the
                    segment's error again (ScreenRecorder+Finishing.swift) —
                    147/161: 3o's two, U1's five, U3's two, U4's nil-note row
                    and U6's four (both read U1's result, which is gone).
  no-unreadable-note    `unreadableNote` always nil (RecordingResult.swift) —
                    157/161: 3o's note, U1's note, U6's notes and
                    savedButNotAdded.
  boundary-promoted     the `stoppedAt == nil` clause dropped
                    (ScreenRecorder+Delegates.swift) — 160/161: M1's
                    microphoneProblem row.
  pause-item-untitled   the validator arm's title line deleted
                    (AppDelegate.swift) — 33/34: F2's paused row.
  pause-item-enabled    the arm returns true (AppDelegate.swift) — 31/34:
                    F2's idle, arming and finishing rows.
  pause-route-recorder  the action's two panel arms deleted
                    (AppDelegate+Recording.swift) — 33/34: F3's pause row.
  status-variable-length  `Self.itemLength` → `NSStatusItem.variableLength`
                    (RecorderStatusItem.swift) — 32/34: W3's two reads.
  width-short-label     `widestElapsed` → 0 (RecorderStatusItem.swift) —
                    27/34: W1's six titles from 59:59 up, W2's label row.

`--sources` over `git archive HEAD` of the tree before the batch
(`5e81c5a`) scores 0/1 and exits 1: the probe names `unreadable`,
`UnreadableSegment` and `pauseOrResumeRecording`, so it does not build
there — a build failure, the three mutants above being the behavioural
controls.

**Issue batch B27's mutants** (3r, 3r2, F6, F7 and section 13), measured
2026-09-30, each `--mutant <name>` with `--only preroll` (10 rows),
`--only state` (141) or `--only file_pause` (39), against a tree scoring
the whole run 1066/1066 with no row skipped (section 13 and section 9
running). Three of them put back the code before the batch:

  preroll-gated     publishMicrophoneLevel's idle arm deleted — the
                    `.recording` gate again (ScreenRecorder+Microphone.swift)
                    — 8/10: P2, P4's meter row.
  preroll-no-tick   `armTick()` not called from beginCountdown
                    (RecorderPanelController+Recording.swift) — 9/10: P4's
                    meter row.
  preroll-no-silence  the discard's silence deleted
                    (ScreenRecorder+Microphone.swift) — 7/10: P3's silence
                    row, P5's two.
  closed-fail-fails-all  the did-fail's `stoppedAt` arm deleted
                    (ScreenRecorder+Delegates.swift) — 133/141: 3r's four
                    rows but the stop row, 3r2's four.
  closed-fail-probed  the walker's `outputFailure` check deleted
                    (ScreenRecorder+Finishing.swift) — 137/141: 3r's two
                    result rows and 3r2's two (its segment 1 is a readable
                    PNG too).
  pause-no-post     the post in pause() deleted (ScreenRecorder+Pause.swift)
                    — 38/39: F6's pause row.
  chrome-no-observer  the chrome's addObserver deleted
                    (AgentServer+RecordingChrome.swift) — 38/39: F7's show
                    row; 45/46 re-measured by B42.

**Issue batch B42's mutants** (F8, F9, F10, #193), measured 2026-10-01,
each `--mutant <name> --only file_pause` (46 rows), against a tree scoring
46/46 there and the whole run 1073/1073 with no row skipped (section 9 and
section 13 running). Each puts back the code before the batch:

  finish-no-post    the post in beginFinishing deleted
                    (ScreenRecorder+Finishing.swift) — 45/46: F8's stop row.
  chrome-no-freeze  the chrome's finishing addObserver deleted
                    (AgentServer+RecordingChrome.swift) — 45/46: F9's show
                    row.
  countdown-keeps-resume-problem  beginCountdown's `resumeProblem = nil`
                    deleted (RecorderPanelController+Recording.swift) —
                    45/46: F10's cleared row.

**Issue batch B49's mutants** (6a, #100, spec §11 SH-4), measured
2026-10-01, each `--mutant <name> --only welcome` (35 rows), against a tree
scoring 35/35 there and 212/212 for `--only chrome,chrome_pause,welcome`.
Section 6's renders are the tree's whatever the mutant, so each is caught by
the probe's own layout and samples:

  sticker-pill-size  `intrinsicContentSize` takes the pill's 6 pt back
                    (Controls.swift) — 28/35: 6a's intrinsic, laid-out and
                    tall rows, and 6d's two (iv) rows in each appearance (the
                    probe's laid-out top, 394, no longer matches the tree's
                    render).
  sticker-round     the block's radius is half its height (Controls.swift)
                    — 34/35: 6a's corner row.

**Issue batch B55's mutants** (#181 item 2: section 14, U1, U6, U7 and
3r), measured 2026-10-01 against the tree at 470/470 for `--only
state,unreadable,landing,segments,catalog,leftout` (195/195 for `--only
state,unreadable,leftout`, 31/31 for `--only unreadable`). Two put back the
code before the batch:

  leftout-mic-unprobed  a left-out segment's microphone never probed
                    (ScreenRecorder+Finishing.swift) — 191/195 with `--only
                    state,unreadable,leftout`: 3r's micPath row, U1's micPath
                    row, U6's fields and notes rows.
  leftout-no-gap    `slotLength` answers 0 (RecordingLanding+LeftOut.swift)
                    — 190/195: X1's picture C, voice C and empty-slot rows,
                    X2, X3's picture C.
  leftout-voice-dropped  `stretches` omits every left-out voice
                    (RecordingResult.swift) — 181/195: X1's six rows but A's
                    and the undo name, X2, X3's three rows but the one-undo
                    row, X4's two, X5, X6's ids row.
  mics-unnamed      `namingFiles` names nothing when no movie is on disk
                    (ScreenRecorder+Finishing.swift) — 30/31 with `--only
                    unreadable`: U7.

**Issue batch B61's mutants** (#213: section 14's X8), measured
2026-10-01 against the tree at 27/27 for `--only leftout`. Each removes one
of `remainderPlacement`'s unplaced-voice notes (RecordingLanding+Remainder
.swift) and is caught by X8's notes row alone:

  unplaced-voice-unnoted    a segment's voice gets no `unplacedNote` when
                    clip 1 is missing — 26/27 with `--only leftout`: X8's
                    notes row.
  unplaced-leftout-unnoted  a left-out segment's voice gets none — 26/27:
                    X8's notes row.

**Issue batch B64's sections and mutants** (#99 phase 1, the voice-over;
spec §11 recording, "A voice-over is a recording with no picture").
Section 15 (`voiceover`, its own process, no grant): V1 `voiceOverStem` at
the two fixed dates, and `nextVoiceOverURL` answering the free name, then
` (2)` when that name is HELD, then ` (3)` when it is on disk and ` (2)` is
held; V2 a fresh recorder refusing a `.display` choice and a nil
microphone before `startVoiceOver` returns, staying idle, `heldSegmentCount`
0 and `heldFilePaths` empty; V3 two voice segments (3 s, 2 s) in a 30 fps
document whose one track holds [0, 10 s], the playhead at 2 s: ops
[add_media, add_media, add_track, add_clip, add_clip], the track at index 0
named "Microphone", the clips at 1 200 000 and 3 000 000, the predicted ids
the minted ones, every `mic…` id nil, the front track unchanged, and one
undo giving back the project JSON byte for byte; V4 `place: false` media
only; V5 a 5 000-tick segment with no clip and its `tooShortNote`, and no
`add_track` when every segment is under a frame; V6 inside an open nest,
the ops unscoped and the clips on the nest's new back track; V7 a new
project at rate 30 (1920×1080 [30, 1], clip 2 at clip 1's end on track 1,
"Add Recording Segments", one undo leaving clip 1); V8, the control, the
same descriptors with a `.display` source taking the picture rule (a new
FRONT track). Section 15g (`voiceover_granted`) builds a SECOND binary with
an `__TEXT,__info_plist` holding `NSMicrophoneUsageDescription` alone
(`recording_spike.py`'s precedent), and is SKIPPED BY NAME with its row
count unless the Microphone status reads `.authorized` and a default audio
input exists — it never asks; a signal is scored as a failure. G1: start →
1 s → pause (the notification; `elapsed` equal twice 0.5 s apart) → resume
(`heldSegmentCount` 2) → 1 s → stop: one result, `isVoiceOver`, two on-disk
`.m4a` segments with no picture, 0.6–1.6 s each, named by their own start
(±1 s), `pauses` 1, `finishingDidBegin` once, idle after, a second start
`.busy`; G2 start → 1 s → pause → 0.5 s → stop gives one segment, `pauses`
1; G3 G1's result through `voiceOverPlacement` gives two touching clips on
"Microphone". The files go under `work/` and are deleted. Measured
2026-10-02, each `--mutant <name> --only voiceover,voiceover_granted`, against
a tree at 30/30 for `--only voiceover` and 14/14 for `--only
voiceover_granted` on a host whose Microphone grant reads authorized:

  voice-front-track     `placement`'s forward to `voiceOverPlacement`
                    deleted (RecordingLanding.swift) — 40/43: V3's track row
                    and front-track row, V6's nest row.
  voice-held-ignored    `nextVoiceOverURL` ignores `held`
                    (ScreenRecorder+VoiceOver.swift) — 41/43: V1's held and
                    on-disk rows.
  voice-track-always    the Microphone track kept with no clip
                    (RecordingLanding+VoiceOver.swift) — 42/43: V5's
                    every-segment-short row.
  voice-pause-unbranched  `pause()`'s forward deleted
                    (ScreenRecorder+Pause.swift) — 35/43: G1's eight rows but
                    the start row and the finishing row, G2, G3. Caught on a
                    GRANTED host only: where 15g skips, nothing runs it.

**Issue batch B66's rows, section and mutants** (#99 phase 2, the
voice-over's doors and B64's review nits 2 and 3). Section 15 gains V9, a
30 fps document filled to 64 tracks: segments of 5 000 and 4 000 ticks land
with no throw as media alone (ops [add_media, add_media], clipIds
[nil, nil], the two `tooShortNote`s, 64 tracks after the commit), while the
control, 5 000 ticks and 2 s, still throws `too many tracks: 65 (max 64)`;
and V10, a fresh `ScreenRecorder()` holding a hand-built `VoiceSession` (a
`SpyAudioOutput`, a bare `AVCaptureSession`, one segment on a 1 s WAV
written with `AVAudioFile`): a did-finish stamped BEFORE `stop()` is still
the microphone stopping on its own (the sentence on a `.success`), one
stamped after it is not (the control), and one stamped before `pause()`
finishes the voice-over from paused (`pauses` 1, idle after). Section 16
(`voiceover_doors`, Swift mode `voiceover-doors`, its own process) drives
`RecorderPanelController.shared`, never shown, under a `GrantSpy` whose
Screen Recording READ is counted: D1 the Source rows end "Window…" (tag 1),
"Camera" (tag 3, camera-recording CR1c) and "Microphone Only" (tag 2),
screens + 4; D2 choosing it greys System
Audio, Show Clicks and Size with their values kept, Microphone, Rate and
Record Into live, the size note `voiceOverSizeNote`; D3 the display key
(a sentinel) and the set of nine `FrameJobRecording…` keys unchanged, the row
kept through `rebuildSources()` + `restoreChoices()`; D4 a display row
brings the three back; D5 Microphone Off refuses with
`microphoneOffSentence`, no screen read, no microphone request; D6 a
microphone authorized with the screen absent counts down, no screen read or
request, nothing opened; D7 the countdown's end is the recorder's own
refusal for that choice (no device carries "probe-mic"), idle, never hidden
— begun by the row itself when D6 did not reach it; D8 `hidesForRecording`
(false for a camera too, since CR1c);
D9 the Pause / Resume button; D10 `record_screen`'s `recordingSourceKind`
— nine calls, the exact sentences, a JSON null not a stranger; D11 the
voice-over's `microphoneNote` and "its file is at". 5d now ends the Source
rows at Microphone Only (screens + 4 since CR1c's Camera row, whose key makes
5d's eight, and CR2a's Format popup's key its nine), 7c's arguments gain `source` (and,
with camera-recording CR1b, spec §11 CAM-4, `camera`, and CR2a's `camera_format`; D10's vocabulary
sentence lists `screen, voice_over, camera` since) and 7d's
phrases `voice_over` and `Microphone Only`. Measured 2026-10-02, each
`--mutant <name> --only voiceover,voiceover_doors`, against a tree at 66/66
there:

  voice-own-stop-asked  `unasked` back to `stoppedAt == nil`
                    (ScreenRecorder+VoiceOverFinishing.swift) — 64/66: V10a,
                    V10c.
  voice-cap-trial-always  `canLand` → `true`
                    (RecordingLanding+VoiceOver.swift) — 65/66: V9a.
  voice-panel-hides     `hidesForRecording` → `{ true }`
                    (RecorderPanelController+VoiceOver.swift) — 65/66: D8.
  voice-screen-grant-read  `beginIfGranted`'s forward deleted
                    (RecorderPanelController+Recording.swift) — 64/66: D5, D6.
  voice-row-live        `screenOnly` → `idle`
                    (RecorderPanelController+VoiceOver.swift) — 65/66: D2.
  voice-strangers-admitted  `strangers` → `[]`
                    (AgentServer+RecordingArguments.swift) — 64/66: D10's
                    display row and its all-five row.

Section 17 (`exclusion`, Include Frame Job windows, spec §11 recording.md;
section 14 on its own branch, renumbered when it merged beside B55's)
runs in its own process with the six older `FrameJobRecording…` keys pinned
in the argument domain and the seventh, `FrameJobRecordingIncludeFrameJobWindows`,
NOT pinned — it is the key under test — and removed from
`UserDefaults.standard` before and after the rows. X1, pure:
`RecordingExclusion.make` over four cases — (false, "com.example.own", 42)
→ (["com.example.own"], []); (false, nil, 42) → ([], []); (true,
"com.example.own", 42) → ([], [42]); (true, "com.example.own", nil) → ([],
[]). X2: `RecorderPanelController.shared` with the key absent → the
checkbox off and `currentChoice().includeFrameJobWindows` false; its title,
its target the panel and its action `controlChanged:`, in the panel's
window; set on and `controlChanged(checkbox)` → the key reads true and the
choice is true; set off with no action, then `restoreChoices()` → on. X3:
`phase = .countdown(3)`, then `.recording` (written by the probe, reset to
`.idle`) → disabled; `.idle` → enabled. X4, structural over the
comment-stripped sources (`read_code`, `function_body`): `presentPicker`
sets `excludedBundleIDs` and `excludedWindowIDs` from
`recordingExclusion(`'s value and never names
`Bundle.main.bundleIdentifier`; `startRecording` passes `excluding:` and
builds the exclusion from `choice.includeFrameJobWindows` above the
`shareableContent` closure; `recordScreen` reads
`"include_framejob_windows"` above `screenRecordingGranted` (the name it is
read into taken from the whole `let` statement, which wraps onto the line
above since the rename — #371) and passes it
to `RecordingExclusion.make(` (with `panelWindowID: nil`) and to
`RecordingChoice(`; and `filter`'s display arm holds
`excludingApplications:` and `excludingWindows:`. What no row here can see
is a recording's PICTURE with Frame Job in it — REC-11 is the person's check.

**Include Frame Job windows' mutants** (section 17), measured 2026-09-30 on
its branch, each `--mutant <name> --only exclusion` (28 rows, the build row
among them), against a tree scoring `--only exclusion` 28/28; each exits 1:

  exclusion-ignores-include  `make`'s `if includeFrameJobWindows` → `if false`
                    (ScreenRecorder+Content.swift) — 26/28: X1's two
                    include rows.
  choice-drops-include  `currentChoice()`'s read of the checkbox deleted
                    (RecorderPanelController+Rows.swift) — 27/28: X2's
                    choice-after-on row.
  persist-drops-include  `persistChoices`'s write of the key deleted
                    (RecorderPanelController+Rows.swift) — 26/28: X2's
                    key-after-on and restored rows.
  lock-drops-include  the checkbox dropped from `syncControlsEnabled()`'s
                    controls (RecorderPanelController+VoiceOver.swift since
                    the merge; `syncPhase()` in +Pause.swift on its branch)
                    — 26/28: X3's countdown and recording rows.
  tool-ignores-include  `record_screen` passes `false` to
                    `RecordingExclusion.make` (AgentServer+Recording.swift)
                    — 27/28: X4's make row.

Two older mutants were RE-AIMED by B55, because the walker's two left-out
arms now call `probeLeftOutMicrophone` before recursing:
`unreadable-fails-all` (the probe-failure arm) re-scored 156/172 with
`--only state,unreadable` — 3o's two, U1's six (its new micPath row
among them), U3's two, U4's nil-note row and U6's five; and
`closed-fail-probed` (the `outputFailure` arm) re-scored 137/142 with
`--only state` — 3r's two result rows and its new micPath row, 3r2's two.

6b's "one program" row, the tree's one failure when this file was first
written, turned green when the harness literalised the six recorder keys
in its pin map (R1's landing): both cross-builds are one program again.

    python3 tools/proof/recording_probe.py                 # the tree
    python3 tools/proof/recording_probe.py --only state,segments   # a subset
    python3 tools/proof/recording_probe.py --only unreadable,file_pause   # B17's
    python3 tools/proof/recording_probe.py --only state,file_pause,preroll   # B27's
    python3 tools/proof/recording_probe.py --only file_pause   # B42's
    python3 tools/proof/recording_probe.py --only welcome   # B49's
    python3 tools/proof/recording_probe.py --only state,unreadable,leftout   # B55's
    python3 tools/proof/recording_probe.py --only leftout   # B61's
    python3 tools/proof/recording_probe.py --only voiceover,voiceover_granted   # B64's
    python3 tools/proof/recording_probe.py --only voiceover,voiceover_doors   # B66's
    python3 tools/proof/recording_probe.py --only exclusion   # Include Frame Job windows
    python3 tools/proof/recording_probe.py --mutant excludes
    python3 tools/proof/recording_probe.py --sources <dir> # any copy
    RC_APP_SOURCES=<dir> python3 tools/proof/recording_probe.py

A `--mutant` run is scored as the tree is (its rows, exit 1 when any
failed); when its control could not be performed — the text to replace not
found exactly once, or the probe not built — it prints `mutant <name>: the
control could not be performed — <why>` and exits 2 (rule R, issue batch
B13).
"""

import argparse
import hashlib
import itertools
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib

from reference_build import build_reference as build_matching_reference
import swift_build

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work")
PROBE = os.path.join(WORK, "recordingprobe")
TREE_SOURCES = os.path.join(ROOT, "app", "Sources")
# The files section 1 makes: the collision folder and the created folder.
FILES = os.path.join(WORK, "recording-probe-files")
# Section 6's instruments: the tree's harness (`build.sh`) and the reference
# build, `phase5_chrome.py`'s `build_reference` into `before/`.
BEFORE = os.path.join(PROBE, "before")
RENDERS = os.path.join(PROBE, "welcome")
BUILD = os.path.join(ROOT, "tools", "proof", "harness", "build.sh")
HARNESS_MAIN = os.path.join(ROOT, "tools", "proof", "harness", "main.swift")
STATICLIB = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
BRIDGING = os.path.join(ROOT, "app", "Bridging", "FrameJob-Bridging-Header.h")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
WELCOME_FILE = "app/Sources/WelcomeWindowController.swift"

passed = 0
failed = 0
# Rows a tier could not run — counted and NAMED in the summary, never a
# vacuous pass (recording_proof.py's rule for host state). Section 9's are
# host state; section 6b's are the tree's own history (see `skip_rows`).
skipped = 0
skips = []


def skip_rows(count, reason):
    """`count` checks that did not run, and why. A skip is not a pass: the
    tail names every reason and the count beside it, so a reader sees what
    was measured and what could not be."""
    global skipped
    skipped += count
    skips.append((count, reason))
    print(f"  SKIPPED by name: {reason} — {count} rows did not run")


STEM_RE = r"Screen Recording \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}"


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def check_table(label, rows, answers, keys, got_key, expect_key="expect"):
    """One check per row of a table. `rows` is what the request carried, each
    with an `expect` and an optional `why`; `answers` is what the probe sent
    back for the same rows, matched by `keys` — never by position, so a probe
    that dropped or reordered a row fails by name rather than shifting every
    later check onto the wrong answer."""
    by = {tuple(a.get(k) for k in keys): a for a in answers}
    for row in rows:
        answer = by.get(tuple(row.get(k) for k in keys), {})
        got = answer.get("error") or answer.get(got_key)
        spelled = " + ".join(str(row[k]) for k in keys if row.get(k) is not None)
        why = f" — {row['why']}" if row.get("why") else ""
        check(f"{label}: {spelled!r} → {row[expect_key]!r}{why}",
              got == row[expect_key], f"got {got!r}")


def read_code(sources, name):
    """A source file with its comments removed, so a structural read can look
    for a token in CODE without a doc comment that mentions it (the header of
    `+Grants.swift` names `canAsk` to say it no longer gates a thing)
    answering yes. `/* */` blocks and `//`/`///` line tails go; nothing this
    probe searches for lives inside a string literal with a `//` in it."""
    path = os.path.join(sources, name)
    if not os.path.exists(path):
        return None
    text = re.sub(r"/\*.*?\*/", "", open(path).read(), flags=re.S)
    out = []
    for line in text.splitlines():
        cut = line.find("//")
        out.append(line[:cut] if cut >= 0 else line)
    return "\n".join(out)


def function_body(lines, signature):
    """The brace-balanced body of the function whose declaration line contains
    `signature`, as a list of lines, or None. Comment-stripped input, so the
    braces counted are code's."""
    start = next((i for i, l in enumerate(lines) if signature in l), None)
    if start is None:
        return None
    depth = 0
    seen = False
    body = []
    for line in lines[start:]:
        depth += line.count("{") - line.count("}")
        body.append(line)
        if "{" in line:
            seen = True
        if seen and depth <= 0:
            return body
    return body


# --------------------------------------------------------------------------
# The probe. One binary, one JSON request in, one JSON answer out, dispatched
# on the request's `mode`, so a later section is a new `case` and nothing
# else moves. A mode the binary does not know is answered BY NAME, which is
# what makes a stale binary a scored failure with a reason rather than a
# silent pass. No NSApplication in the first three modes and no run loop
# beyond the spins section 3 needs for a main-hopped completion; the later
# modes make a `.prohibited` NSApplication because a document window, a
# menu bar and a panel need one — and NOTHING that prompts.

PROBE_SOURCE = r'''
import AVFoundation
import AppKit
import CoreAudio
import CoreText
import ScreenCaptureKit

/// Spins the main run loop until `done` or `seconds` pass — the shape
/// every completion-handler face in the app needs to be observed from a
/// process with no NSApplication.
func spin(_ seconds: Double, until done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if done() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return done()
}

// ---- mode "files": RecordingFiles and the choice's defaults --------------
func files(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let override = request["override"] as? String ?? ""
    // The harness's pin: the volatile argument domain is searched first.
    UserDefaults.standard.setVolatileDomain(
        [RecordingFiles.folderDefaultsKey: override], forName: UserDefaults.argumentDomain)
    out["folderPinned"] = RecordingFiles.folder().path
    UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    out["folderDefault"] = RecordingFiles.folder().path
    out["keyRead"] = RecordingFiles.folderDefaultsKey
    out["choiceFolder"] = RecordingChoice().folder.path

    out["stems"] = (request["stemDates"] as? [Double] ?? []).map { seconds -> [String: Any] in
        ["seconds": seconds,
         "stem": RecordingFiles.stem(at: Date(timeIntervalSince1970: seconds))]
    }

    let unique = URL(fileURLWithPath: request["uniqueFolder"] as? String ?? "", isDirectory: true)
    out["uniqueX"] = RecordingFiles.uniqueURL(in: unique, stem: "X", ext: "mov").path
    out["uniqueFree"] = RecordingFiles.uniqueURL(in: unique, stem: "Y", ext: "mov").path
    out["micBeside"] = RecordingFiles.microphoneURL(
        beside: unique.appendingPathComponent("X.mov")).path
    out["micBesideTaken"] = RecordingFiles.microphoneURL(
        beside: unique.appendingPathComponent("Z.mov")).path

    let create = URL(fileURLWithPath: request["createFolder"] as? String ?? "", isDirectory: true)
    do { try RecordingFiles.create(create); out["created"] = true } catch { out["created"] = "\(error)" }
    var isDirectory: ObjCBool = false
    out["createdIsDirectory"] =
        FileManager.default.fileExists(atPath: create.path, isDirectory: &isDirectory)
        && isDirectory.boolValue
    do { try RecordingFiles.create(create); out["createdAgain"] = true } catch { out["createdAgain"] = "\(error)" }

    let choice = RecordingChoice()
    out["choiceDefaults"] = [
        "rate": choice.rate, "systemAudio": choice.systemAudio, "showClicks": choice.showClicks,
        "resolution": choice.resolution.rawValue, "microphone": choice.microphone as Any,
        "newProject": choice.destination == .newProject,
        "mainDisplay": choice.source == .display(CGMainDisplayID()),
        "includeFrameJobWindows": choice.includeFrameJobWindows,
    ]
    return out
}

// ---- mode "configuration": RecordingConfiguration.make read back ---------
func configuration(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let sizeSpec = request["displayPointSize"] as? [Double] ?? [0, 0]
    let size = CGSize(width: sizeSpec[0], height: sizeSpec[1])
    let scale = CGFloat(request["scale"] as? Double ?? 1)
    let url = URL(fileURLWithPath: request["outputURL"] as? String ?? "/tmp/x.mov")
    out["freshPixelFormat"] = Int(SCStreamConfiguration().pixelFormat)
    let rows = request["rows"] as? [[String: Any]] ?? []
    out["rows"] = rows.map { row -> [String: Any] in
        var choice = RecordingChoice()
        choice.rate = row["rate"] as? Int ?? 60
        choice.resolution = RecordingResolution(rawValue: row["resolution"] as? String ?? "") ?? .nominal
        choice.systemAudio = row["systemAudio"] as? Bool ?? true
        choice.showClicks = row["showClicks"] as? Bool ?? false
        let made = RecordingConfiguration.make(
            choice, displayPointSize: size, scale: scale, outputURL: url)
        let stream = made.stream
        let output = made.output
        return [
            "rate": choice.rate, "resolution": choice.resolution.rawValue,
            "systemAudio": choice.systemAudio, "showClicks": choice.showClicks,
            "width": stream.width, "height": stream.height,
            "minimumFrameInterval": [Int(stream.minimumFrameInterval.value),
                                     Int(stream.minimumFrameInterval.timescale)],
            "showsCursor": stream.showsCursor, "showMouseClicks": stream.showMouseClicks,
            "pixelFormat": Int(stream.pixelFormat), "capturesAudio": stream.capturesAudio,
            "sampleRate": stream.sampleRate, "channelCount": stream.channelCount,
            "excludesCurrentProcessAudio": stream.excludesCurrentProcessAudio,
            "captureMicrophone": stream.captureMicrophone,
            "captureResolution": stream.captureResolution.rawValue,
            "videoCodecType": output.videoCodecType.rawValue,
            "availableVideoCodecTypes": output.availableVideoCodecTypes.map { $0.rawValue },
            "outputFileType": output.outputFileType.rawValue,
            "outputURL": output.outputURL.path,
        ]
    }
    return out
}

// ---- mode "state": a fresh recorder with no framework call --------------

/// Names a `RecorderError`'s case, the `filesKept` wrapper's inner case
/// included, so a row can say which failure it saw and not only its words.
func caseName(_ error: RecorderError) -> String {
    switch error {
    case .busy: return "busy"
    case .notRecording: return "notRecording"
    case .notPaused: return "notPaused"
    case .alreadyPaused: return "alreadyPaused"
    case .startFailed: return "startFailed"
    case .finishFailed: return "finishFailed"
    case .startTimedOut: return "startTimedOut"
    case .timedOut: return "timedOut"
    case .microphoneDevice: return "microphoneDevice"
    case .cameraDevice: return "cameraDevice"
    case .filesKept(let inner, _, _): return "filesKept(\(caseName(inner)))"
    }
}

/// One outcome — what `onFinish` or a stop completion received — as JSON.
/// `micDescriptor` is the FIRST segment's (R1's rows read it as the
/// recording's); `segments` carries every one in the walker's order, each
/// with its own offset and problem (R2).
func spell(_ outcome: Result<RecordingResult, Error>) -> [String: Any] {
    switch outcome {
    case .success(let result):
        return [
            "kind": "success", "path": result.descriptor.path,
            "micDescriptor": result.segments[0].micDescriptor != nil,
            "micProblem": result.micProblem as Any, "stoppedBy": "\(result.stoppedBy)",
            "pauses": result.pauses, "startedAt": result.startedAt.timeIntervalSince1970,
            "segments": result.segments.map { segment -> [String: Any] in
                [
                    "path": segment.descriptor.path, "duration": segment.descriptor.duration,
                    "hasVideo": segment.descriptor.hasVideo,
                    "hasAudio": segment.descriptor.hasAudio,
                    "width": segment.descriptor.width, "height": segment.descriptor.height,
                    "micDescriptor": segment.micDescriptor != nil,
                    "micPath": segment.micDescriptor?.path as Any,
                    "micOffset": segment.micOffset, "micProblem": segment.micProblem as Any,
                    "startedAt": segment.startedAt.timeIntervalSince1970,
                ]
            },
            // Issue batch B17 (#97): the segments left out, and their note.
            "unreadable": result.unreadable.map { left -> [String: Any] in
                [
                    "moviePath": left.moviePath, "keptFiles": left.keptFiles,
                    "case": caseName(left.error), "description": left.error.localizedDescription,
                    // Issue batch B55 (#181 item 2): its microphone, when it read.
                    "micPath": left.micDescriptor?.path as Any, "position": left.position,
                ]
            },
            "unreadableNote": result.unreadableNote as Any,
        ]
    case .failure(let error):
        var spelled: [String: Any] = ["kind": "failure", "description": error.localizedDescription]
        if let recorder = error as? RecorderError { spelled["case"] = caseName(recorder) }
        return spelled
    }
}

/// A thrown error by case name and sentence, for the two synchronous entries.
func spellError(_ error: any Error) -> String {
    if let recorder = error as? RecorderError {
        return "\(caseName(recorder)): \(recorder.localizedDescription)"
    }
    return "other: \(error.localizedDescription)"
}

/// A 16×16 PNG at `url`: a "movie" `MediaImporter.probe` answers with a
/// descriptor (it routes an image extension to ImageIO), which is what lets
/// a faked session reach `.success` with no stream ever started. An EMPTY
/// file is the other fixture — one the probe refuses, for the failure rows.
func writePNG(_ url: URL) -> Bool {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
        let data = rep.representation(using: .png, properties: [:])
    else { return false }
    return (try? data.write(to: url)) != nil
}

func emptyFile(_ url: URL) -> Bool {
    FileManager.default.createFile(atPath: url.path, contents: Data())
}

/// `RCFFmpegImport` pinned to never, MERGED into the volatile argument
/// domain: a `.mov` the walker cannot read must never reach `FFmpegRewrap`'s
/// consent alert (`MediaImporter.probeAllowingRewrap` offers a refused
/// non-image to it), exactly as a person who said never would have it.
func pinNeverRewrap() {
    var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    domain[FFmpegRewrap.policyDefaultsKey] = FFmpegRewrap.Policy.never.rawValue
    UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
}

/// The microphone output the faked session carries: an
/// `AVCaptureAudioFileOutput` with no session, so the two calls the recorder
/// makes on it — `stopRecording()` at a pause and at the stop,
/// `startRecording(to:…)` at a resume — are COUNTED and their URLs kept
/// rather than forwarded (a session-less output writes nothing either way;
/// R1's bare output measured `stopRecording` delivering nothing). The
/// finishing wait therefore HOLDS until the probe drives the did-finish
/// itself, which is what makes every row deterministic rather than a race
/// against a writer.
final class SpyAudioOutput: AVCaptureAudioFileOutput {
    var stops = 0
    var starts: [String] = []
    override func stopRecording() { stops += 1 }
    override func startRecording(
        to outputFileURL: URL, outputFileType fileType: AVFileType,
        recordingDelegate delegate: any AVCaptureFileOutputRecordingDelegate
    ) {
        starts.append(outputFileURL.path)
    }
}

/// One (movie, microphone) pair of a hand-built session. `closed` is a
/// segment a pause has already shut — `stoppedAt` stamped, both did-finishes
/// landed — unless the stamps say otherwise; the stamps are what `elapsed`
/// and the per-segment offset are computed from.
struct FakeSegment {
    var movie: URL
    var mic: URL?
    var closed = false
    var screenStart: Date? = nil
    var micStart: Date? = nil
    var stoppedAt: Date? = nil
    var screenFinished: Bool? = nil
    var micFailure: String? = nil
}

/// A session the machine can be driven through with no stream started —
/// the R1 review measured that `SCContentFilter()` and
/// `SCStream(filter:configuration:delegate:)` CONSTRUCT without a grant and
/// only `startCapture` needs one; `SCRecordingOutput(configuration:delegate:)`
/// constructs beside them. **And the R2 probe measured the pause's pair on
/// that never-started, grant-less stream**: `addRecordingOutput` accepts an
/// output, `removeRecordingOutput` of an added output returns, and a fresh
/// output can be added after the remove (a second output while one is
/// attached, an output never added, or any add after `stopCapture` throws
/// −3812; no file is ever written) — so the LAST segment's output is added
/// here, R1's pre-`startCapture` order, and `pause()` / `resume()` run their
/// real bodies. Earlier segments are the closed ones a pause left behind.
/// The delegate methods are called directly, as the frameworks would call
/// them (each hops to main itself).
final class Fake {
    let recorder = ScreenRecorder()
    let stream: SCStream
    let outputs: [SCRecordingOutput]
    let micOutput: SpyAudioOutput?
    let movie: URL
    let mic: URL?
    var finishes: [[String: Any]] = []
    /// The add that puts the last segment's output on the stream, or why not.
    var attachFailure: String?

    /// R1's shape: one open segment, its output attached.
    convenience init(movie: URL, mic: URL?, state: ScreenRecorder.State) {
        self.init(
            segments: [FakeSegment(movie: movie, mic: mic)], mic: mic != nil, state: state,
            folder: movie.deletingLastPathComponent())
    }

    /// `segments` in order; `mic` says whether the session carries a
    /// microphone output at all (a segment's `mic` URL is then its file);
    /// `attach` puts the LAST segment's output on the stream — false for a
    /// recording whose output was never added, the one way `pause()`'s
    /// remove can throw. `folder` is where a `resume()` mints its files.
    init(
        segments: [FakeSegment], mic: Bool, state: ScreenRecorder.State, folder: URL,
        attach: Bool = true
    ) {
        movie = segments[0].movie
        self.mic = segments[0].mic
        var choice = RecordingChoice()
        choice.folder = folder
        let size = CGSize(width: 16, height: 16)
        let configs = RecordingConfiguration.make(
            choice, displayPointSize: size, scale: 1, outputURL: segments[0].movie)
        stream = SCStream(
            filter: SCContentFilter(), configuration: configs.stream, delegate: recorder)
        var outs: [SCRecordingOutput] = []
        for segment in segments {
            let made = RecordingConfiguration.make(
                choice, displayPointSize: size, scale: 1, outputURL: segment.movie)
            outs.append(SCRecordingOutput(configuration: made.output, delegate: recorder))
        }
        outputs = outs
        micOutput = mic ? SpyAudioOutput() : nil
        if attach, let last = outs.last {
            do { try stream.addRecordingOutput(last) } catch { attachFailure = "\(error)" }
        }
        let now = Date()
        var built: [ScreenRecorder.Segment] = []
        for (index, segment) in segments.enumerated() {
            var made = ScreenRecorder.Segment(
                movieURL: segment.movie, micURL: segment.mic, output: outs[index],
                addedAt: segment.screenStart ?? now)
            made.screenStartedAt = segment.screenStart
            made.micStartedAt = segment.micStart
            if segment.mic != nil { made.micRecordingCalledAt = segment.micStart ?? now }
            made.micFailure = segment.micFailure
            if segment.closed {
                made.stoppedAt = segment.stoppedAt ?? now
                made.screenFinished = segment.screenFinished ?? true
                made.micFinished = segment.mic != nil
            }
            built.append(made)
        }
        recorder.session = ScreenRecorder.Session(
            choice: choice, mayAsk: true, displayPointSize: size, scale: 1, stream: stream, micSession: nil,
            micOutput: micOutput, calledAt: now,
            onFinish: { [weak self] outcome in self?.finishes.append(spell(outcome)) },
            segments: built)
        // A hand-built session of n closed segments came from n − 1 pauses;
        // a real `pause()` on it counts on from there.
        recorder.session?.pauses = max(0, built.count - 1)
        recorder.state = state
    }

    var state: String { "\(recorder.state)" }
    var stoppedBy: String { recorder.session.map { "\($0.stoppedBy)" } ?? "nil" }
    var segmentCount: Int { recorder.session?.segments.count ?? -1 }
    var pauses: Int { recorder.session?.pauses ?? -1 }
    func segment(_ index: Int) -> ScreenRecorder.Segment? {
        guard let segments = recorder.session?.segments, segments.indices.contains(index) else {
            return nil
        }
        return segments[index]
    }
    /// Segment `index`'s output — the recorder's own for one a `resume()`
    /// minted, this fake's for the hand-built ones (still known once the
    /// session is gone, for a callback driven after the conclude).
    private func output(_ index: Int) -> SCRecordingOutput? {
        segment(index)?.output ?? (outputs.indices.contains(index) ? outputs[index] : nil)
    }

    /// Lights the recorder's own meter, as a poll would.
    func light() {
        recorder.meter.publish(
            LevelMeterReading(peakLeft: 0.5, peakRight: 0.5, rmsLeft: 0.3, rmsRight: 0.3),
            from: ObjectIdentifier(recorder))
    }
    func screenStarted(_ index: Int = 0) {
        guard let output = output(index) else { return }
        recorder.recordingOutputDidStartRecording(output)
    }
    func screenFinished(_ index: Int = 0) {
        guard let output = output(index) else { return }
        recorder.recordingOutputDidFinishRecording(output)
    }
    func screenFailed(_ index: Int, _ message: String) {
        guard let output = output(index) else { return }
        recorder.recordingOutput(
            output,
            didFailWithError: NSError(
                domain: SCStreamError.errorDomain, code: SCStreamError.Code.internalError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: message]))
    }
    /// A did-finish for an output that belongs to no segment of this session.
    func strayScreenFinished() {
        let configuration = SCRecordingOutputConfiguration()
        configuration.outputURL = movie.deletingLastPathComponent().appendingPathComponent("stray.mov")
        let stray = SCRecordingOutput(configuration: configuration, delegate: recorder)
        recorder.recordingOutputDidFinishRecording(stray)
    }
    func micStarted(url: URL) {
        guard let micOutput else { return }
        recorder.fileOutput(micOutput, didStartRecordingTo: url, from: [])
    }
    func micFinished(error: Error?) {
        guard let mic else { return }
        micFinished(url: mic, error: error)
    }
    func micFinished(url: URL, error: Error?) {
        guard let micOutput else { return }
        recorder.fileOutput(micOutput, didFinishRecordingTo: url, from: [], error: error)
    }
    func streamStopped(_ code: SCStreamError.Code) {
        recorder.stream(
            stream,
            didStopWithError: NSError(domain: SCStreamError.errorDomain, code: code.rawValue))
    }
    /// True once the recorder is idle again — the conclude landed.
    func settled() -> Bool { spin(5) { recorder.state == .idle } }
}

/// One segment's stamps and flags, as JSON.
func describeSegment(_ segment: ScreenRecorder.Segment?) -> [String: Any] {
    guard let segment else { return ["missing": true] }
    return [
        "movie": segment.movieURL.path, "mic": segment.micURL?.path as Any,
        "addedAt": segment.addedAt.timeIntervalSince1970,
        "micCalled": segment.micRecordingCalledAt != nil,
        "screenStartedAt": segment.screenStartedAt?.timeIntervalSince1970 as Any,
        "micStartedAt": segment.micStartedAt?.timeIntervalSince1970 as Any,
        "stoppedAt": segment.stoppedAt?.timeIntervalSince1970 as Any,
        "screenFinished": segment.screenFinished, "micFinished": segment.micFinished,
        "micFailure": segment.micFailure as Any,
    ]
}

/// Finding 1 (JOIN), 8 (the meter at `beginFinishing`) and 0's "never
/// started" arm: two stops on one recording, both answered once, beside
/// `onFinish`, with a microphone whose did-start never came.
func scenarioJoin(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("join.png")
    out["pngWritten"] = writePNG(movie)
    let fake = Fake(
        movie: movie, mic: work.appendingPathComponent("join (Microphone).m4a"), state: .recording)
    fake.light()
    out["meterLitBefore"] = !fake.recorder.meter.reading.isSilent
    var first: [[String: Any]] = []
    var second: [[String: Any]] = []
    fake.recorder.stop { first.append(spell($0)) }
    out["stateAfterStop"] = fake.state
    out["meterSilentAfterStop"] = fake.recorder.meter.reading.isSilent
    fake.recorder.stop { second.append(spell($0)) }
    out["secondStopAnsweredAtOnce"] = second.count
    out["stateAfterSecondStop"] = fake.state
    _ = spin(0.3) { false }
    out["stateAfterStopCapture"] = fake.state
    fake.screenFinished()
    _ = spin(0.3) { false }
    out["stateAfterScreenFinish"] = fake.state
    fake.micFinished(error: nil)
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["firstStopCount"] = first.count
    out["secondStopCount"] = second.count
    out["onFinish"] = fake.finishes.first ?? [:]
    out["firstStop"] = first.first ?? [:]
    out["secondStop"] = second.first ?? [:]
    out["microphoneProblemAfter"] = fake.recorder.microphoneProblem as Any
    var late: [[String: Any]] = []
    fake.recorder.stop { late.append(spell($0)) }
    out["stopAfterConclude"] = late.first ?? [:]
    return out
}

/// Finding 2: `settle` once. The settle is called directly (the flag is
/// set before the probe is even queued), then a second `checkFinished` and
/// a driven duplicate did-finish land during the probe; `onFinish` must
/// still be called once. Without the guard the second entry launches a
/// second probe and a second conclude — the review measured exactly that.
func scenarioOneShot(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("oneshot.png")
    out["pngWritten"] = writePNG(movie)
    let fake = Fake(movie: movie, mic: nil, state: .recording)
    var first: [[String: Any]] = []
    fake.recorder.stop { first.append(spell($0)) }
    fake.recorder.session?.segments[0].screenFinished = true
    fake.recorder.settle()
    out["settlingAfterSettle"] = fake.recorder.isSettling
    out["stateAfterSettle"] = fake.state
    fake.recorder.checkFinished()
    fake.screenFinished()
    out["settled"] = fake.settled()
    _ = spin(0.5) { false }
    out["onFinishCount"] = fake.finishes.count
    out["firstStopCount"] = first.count
    out["onFinish"] = fake.finishes.first ?? [:]
    return out
}

/// Finding 3 and finding 0's "writer reported an error" arm: the microphone
/// dies while the picture records; the recording goes on, the problem is
/// live, the meter is silent, and `stop` lands the picture with the
/// problem on the result and the file it left named.
func scenarioMicDies(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("micdies.png")
    let mic = work.appendingPathComponent("micdies (Microphone).m4a")
    out["pngWritten"] = writePNG(movie) && emptyFile(mic)
    out["micPath"] = mic.path
    let fake = Fake(movie: movie, mic: mic, state: .recording)
    fake.light()
    let error = NSError(
        domain: AVFoundationErrorDomain, code: AVError.deviceWasDisconnected.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "The device was disconnected."])
    fake.micFinished(error: error)
    _ = spin(0.3) { false }
    out["stateAfterMicFailure"] = fake.state
    out["microphoneProblemLive"] = fake.recorder.microphoneProblem as Any
    out["meterSilentAfterMicFailure"] = fake.recorder.meter.reading.isSilent
    fake.recorder.publishMicrophoneLevel()
    out["meterSilentAfterPoll"] = fake.recorder.meter.reading.isSilent
    var first: [[String: Any]] = []
    fake.recorder.stop { first.append(spell($0)) }
    fake.screenFinished()
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["firstStopCount"] = first.count
    out["onFinish"] = fake.finishes.first ?? [:]
    out["microphoneProblemAfter"] = fake.recorder.microphoneProblem as Any
    return out
}

/// Finding 6: a failure past `beginFinishing` names the files it left —
/// both when a microphone file exists, the movie alone when not. The
/// unreadable "movie" is an EMPTY `.png`: `MediaImporter.probeAllowingRewrap`
/// hands a refused non-image to `FFmpegRewrap.assist`, whose consent
/// alert a process with no NSApplication cannot put up, and excludes an
/// image by name — so the row cannot depend on whether ffmpeg is here.
func scenarioPath(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("path.png")
    let mic = work.appendingPathComponent("path (Microphone).m4a")
    out["filesWritten"] = emptyFile(movie) && emptyFile(mic)
    out["moviePath"] = movie.path
    out["micPath"] = mic.path
    let fake = Fake(movie: movie, mic: mic, state: .recording)
    var first: [[String: Any]] = []
    fake.recorder.stop { first.append(spell($0)) }
    fake.screenFinished()
    fake.micFinished(error: nil)
    out["settled"] = fake.settled()
    out["onFinish"] = fake.finishes.first ?? [:]
    out["firstStop"] = first.first ?? [:]

    let alone = work.appendingPathComponent("alone.png")
    out["aloneWritten"] = emptyFile(alone)
    out["alonePath"] = alone.path
    let fake2 = Fake(movie: alone, mic: nil, state: .recording)
    fake2.recorder.stop()
    fake2.screenFinished()
    out["aloneSettled"] = fake2.settled()
    out["aloneOnFinish"] = fake2.finishes.first ?? [:]
    return out
}

/// Finding 7: an external stop whose did-finish landed first adopts the
/// reason; a stop that ENDED the recording keeps `.stopped` whatever the
/// stream then says.
func scenarioExternal(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("external.png")
    out["pngWritten"] = writePNG(movie)
    let mic = work.appendingPathComponent("external (Microphone).m4a")
    let fake = Fake(movie: movie, mic: mic, state: .recording)
    fake.screenFinished()
    _ = spin(1) { fake.recorder.state == .finishing }
    out["stateAfterUnaskedFinish"] = fake.state
    out["stoppedByBefore"] = fake.stoppedBy
    fake.streamStopped(.userStopped)
    _ = spin(0.3) { false }
    out["stoppedByAfter"] = fake.stoppedBy
    fake.micFinished(error: nil)
    out["settled"] = fake.settled()
    out["onFinish"] = fake.finishes.first ?? [:]

    let fake2 = Fake(movie: movie, mic: mic, state: .recording)
    fake2.recorder.stop()
    fake2.streamStopped(.userStopped)
    _ = spin(0.3) { false }
    out["askedStoppedBy"] = fake2.stoppedBy
    fake2.screenFinished()
    fake2.micFinished(error: nil)
    out["askedSettled"] = fake2.settled()
    out["askedOnFinish"] = fake2.finishes.first ?? [:]
    return out
}

/// `prepareMicrophone` with nothing to prepare, and a stop while arming.
func scenarioIdleFaces(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let recorder = ScreenRecorder()
    recorder.prepareMicrophone(nil)
    out["afterNil"] = ["state": "\(recorder.state)", "prepared": recorder.preparedMicrophone != nil]
    recorder.prepareMicrophone("no-such-device-id")
    out["afterUnknown"] = [
        "state": "\(recorder.state)", "prepared": recorder.preparedMicrophone != nil,
    ]
    recorder.discardPreparedMicrophone()
    out["afterDiscard"] = [
        "state": "\(recorder.state)", "prepared": recorder.preparedMicrophone != nil,
    ]

    let fake = Fake(movie: work.appendingPathComponent("arming.mov"), mic: nil, state: .arming)
    var first: [[String: Any]] = []
    var second: [[String: Any]] = []
    fake.recorder.stop { first.append(spell($0)) }
    fake.recorder.stop { second.append(spell($0)) }
    _ = spin(0.2) { false }
    out["arming"] = [
        "state": fake.state, "pendingStop": fake.recorder.pendingStop,
        "registered": fake.recorder.stopCompletions.count,
        "answered": first.count + second.count,
        "stopAsked": fake.recorder.session?.stopAsked ?? false,
    ]
    return out
}

// ---- R2: pause and resume over the faked session ----------------------

/// The pause and the resume, driven through their real bodies (the `Fake`
/// doc: the pair works on a never-started stream). One open segment with a
/// microphone whose picture began 1 s ago and 12 ms after its voice;
/// `pause()` closes it, `elapsed` freezes, `resume()` mints the next pair
/// in the work folder, the closed segment's late callbacks are inert, the
/// new pair's did-starts stamp only their own segment, a stray output and a
/// stray file change nothing, a second `pause()` then `stop()` while paused
/// takes the finishing path with the segment's stamp KEPT and no second
/// `stopRecording` — and the walker, meeting an EMPTY second movie, fails
/// naming all four files, comma-joined.
func scenarioPause(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("pause.png")
    let mic = work.appendingPathComponent("pause-mic.png")
    out["written"] = writePNG(movie) && writePNG(mic)
    var first = FakeSegment(movie: movie, mic: mic)
    first.screenStart = Date(timeIntervalSinceNow: -1.0)
    first.micStart = first.screenStart!.addingTimeInterval(-0.012)
    let fake = Fake(segments: [first], mic: true, state: .recording, folder: work)
    out["attached"] = fake.attachFailure ?? "ok"
    fake.light()
    out["elapsedBefore"] = fake.recorder.elapsed
    do {
        try fake.recorder.pause()
        out["pause"] = "ok"
    } catch { out["pause"] = spellError(error) }
    out["stateAfterPause"] = fake.state
    out["isPaused"] = fake.recorder.isPaused
    out["isRecordingWhilePaused"] = fake.recorder.isRecording
    out["segment0AfterPause"] = describeSegment(fake.segment(0))
    out["meterSilentAfterPause"] = fake.recorder.meter.reading.isSilent
    out["micStopsAfterPause"] = fake.micOutput?.stops ?? -1
    let a = fake.recorder.elapsed
    _ = spin(0.3) { false }
    let b = fake.recorder.elapsed
    out["elapsedA"] = a
    out["elapsedB"] = b
    fake.light()
    fake.recorder.publishMicrophoneLevel()
    out["meterLitAfterPollWhilePaused"] = !fake.recorder.meter.reading.isSilent
    do {
        try fake.recorder.pause()
        out["pauseAgain"] = "ok"
    } catch { out["pauseAgain"] = spellError(error) }
    do {
        try fake.recorder.resume()
        out["resume"] = "ok"
    } catch { out["resume"] = spellError(error) }
    out["stateAfterResume"] = fake.state
    out["segmentsAfterResume"] = fake.segmentCount
    out["segment1AfterResume"] = describeSegment(fake.segment(1))
    out["segment0AfterResume"] = describeSegment(fake.segment(0))
    out["micStartsAfterResume"] = fake.micOutput?.starts ?? []
    out["folder"] = work.path
    let c = fake.recorder.elapsed
    _ = spin(0.3) { false }
    out["elapsedC"] = c
    out["elapsedD"] = fake.recorder.elapsed
    // The closed segment's did-finishes land AFTER the resume: inert.
    fake.screenFinished(0)
    fake.micFinished(url: mic, error: nil)
    _ = spin(0.2) { false }
    out["stateAfterLateFinish"] = fake.state
    out["segment0AfterLateFinish"] = describeSegment(fake.segment(0))
    out["segment1AfterLateFinish"] = describeSegment(fake.segment(1))
    // The new pair's did-starts stamp segment 1 alone.
    fake.screenStarted(1)
    if let micURL = fake.segment(1)?.micURL { fake.micStarted(url: micURL) }
    _ = spin(0.2) { false }
    out["segment1Stamped"] = describeSegment(fake.segment(1))
    out["segment0Stamped"] = describeSegment(fake.segment(0))
    // A did-finish for no segment's output, and one for a file no segment
    // asked for: nothing.
    fake.strayScreenFinished()
    fake.micFinished(url: work.appendingPathComponent("stray.m4a"), error: nil)
    _ = spin(0.2) { false }
    out["stateAfterStray"] = fake.state
    out["segmentsAfterStray"] = fake.segmentCount
    out["segment1AfterStray"] = describeSegment(fake.segment(1))
    do {
        try fake.recorder.resume()
        out["resumeWhileRecording"] = "ok"
    } catch { out["resumeWhileRecording"] = spellError(error) }
    // A second pause, then a stop while paused.
    do {
        try fake.recorder.pause()
        out["secondPause"] = "ok"
    } catch { out["secondPause"] = spellError(error) }
    out["stateAfterSecondPause"] = fake.state
    let stampAtPause = fake.segment(1)?.stoppedAt
    out["micStopsAfterSecondPause"] = fake.micOutput?.stops ?? -1
    out["elapsedAtSecondPause"] = fake.recorder.elapsed
    var stops: [[String: Any]] = []
    fake.recorder.stop { stops.append(spell($0)) }
    out["stateAfterStop"] = fake.state
    out["stoppedBy"] = fake.stoppedBy
    out["stoppedAtKept"] = fake.segment(1)?.stoppedAt == stampAtPause && stampAtPause != nil
    out["micStopsAfterStop"] = fake.micOutput?.stops ?? -1
    out["segment1AtStop"] = describeSegment(fake.segment(1))
    // Segment 1's files: EMPTY, so the movie will not probe and the
    // sentence names every file that exists.
    let movie1 = fake.segment(1)?.movieURL
    let mic1 = fake.segment(1)?.micURL
    out["emptyWritten"] = movie1.map(emptyFile) == true && mic1.map(emptyFile) == true
    out["paths"] = [movie.path, mic.path, movie1?.path ?? "", mic1?.path ?? ""]
    fake.screenFinished(1)
    if let mic1 { fake.micFinished(url: mic1, error: nil) }
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["onFinish"] = fake.finishes.first ?? [:]
    out["stopCount"] = stops.count
    out["stop"] = stops.first ?? [:]
    out["elapsedAfter"] = fake.recorder.elapsed
    return out
}

/// `pause()` refused: the output was never added, so the remove throws and
/// the recorder STAYS recording with nothing changed — no stamp, no
/// `stopRecording`, the meter still lit; a `stop()` then closes it as ever.
func scenarioPauseRefused(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("pauserefused.png")
    let mic = work.appendingPathComponent("pauserefused-mic.png")
    out["written"] = writePNG(movie) && writePNG(mic)
    let fake = Fake(
        segments: [FakeSegment(movie: movie, mic: mic)], mic: true, state: .recording,
        folder: work, attach: false)
    fake.light()
    do {
        try fake.recorder.pause()
        out["pause"] = "ok"
    } catch { out["pause"] = spellError(error) }
    out["stateAfter"] = fake.state
    out["segment0"] = describeSegment(fake.segment(0))
    out["micStops"] = fake.micOutput?.stops ?? -1
    out["meterLit"] = !fake.recorder.meter.reading.isSilent
    fake.recorder.stop()
    out["stateAfterStop"] = fake.state
    out["micStopsAfterStop"] = fake.micOutput?.stops ?? -1
    fake.screenFinished(0)
    fake.micFinished(error: nil)
    out["settled"] = fake.settled()
    out["onFinish"] = fake.finishes.first ?? [:]
    return out
}

/// `resume()` refused: the state is `.paused` BY THE PROBE with the
/// segment's output still attached (a probe-only manipulation), so the add
/// throws −3812 and the recorder STAYS paused with no segment minted and no
/// `startRecording`; a `stop()` then lands the one segment.
func scenarioResumeRefused(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("resumerefused.png")
    let mic = work.appendingPathComponent("resumerefused-mic.png")
    out["written"] = writePNG(movie) && writePNG(mic)
    let fake = Fake(
        segments: [FakeSegment(movie: movie, mic: mic)], mic: true, state: .paused, folder: work)
    out["attached"] = fake.attachFailure ?? "ok"
    do {
        try fake.recorder.resume()
        out["resume"] = "ok"
    } catch { out["resume"] = spellError(error) }
    out["stateAfter"] = fake.state
    out["segments"] = fake.segmentCount
    out["micStarts"] = fake.micOutput?.starts ?? []
    out["filesInFolder"] = (try? FileManager.default.contentsOfDirectory(atPath: work.path))?
        .filter { $0.hasPrefix("Screen Recording") }.count ?? -1
    var stops: [[String: Any]] = []
    fake.recorder.stop { stops.append(spell($0)) }
    out["stateAfterStop"] = fake.state
    fake.screenFinished(0)
    fake.micFinished(error: nil)
    out["settled"] = fake.settled()
    out["onFinish"] = fake.finishes.first ?? [:]
    out["stopCount"] = stops.count
    return out
}

/// A did-fail on a CLOSED segment is that segment's (issue batch B27, #181):
/// segment 0 was paused (stamped) but its did-finish is still in flight —
/// built with `screenFinished = false`, because its did-FAIL is what
/// finishes it — when its writer reports a failure instead; segment 1 is
/// open. The recording goes ON (still `.recording`, no `screenFailure`, no
/// writer stopped); a `stop()` then finishes it and the walker leaves
/// segment 0 out UNPROBED — its PNG would read — with the writer's sentence.
func scenarioClosedFail(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let m0 = work.appendingPathComponent("closedfail0.png")
    let x0 = work.appendingPathComponent("closedfail0-mic.png")
    let m1 = work.appendingPathComponent("closedfail1.png")
    let x1 = work.appendingPathComponent("closedfail1-mic.png")
    out["written"] = writePNG(m0) && writePNG(x0) && writePNG(m1) && writePNG(x1)
    out["paths"] = [m0.path, m1.path, x0.path, x1.path]
    var closed = FakeSegment(movie: m0, mic: x0, closed: true)
    closed.screenFinished = false
    closed.screenStart = Date(timeIntervalSinceNow: -5)
    closed.stoppedAt = Date(timeIntervalSinceNow: -3)
    var open = FakeSegment(movie: m1, mic: x1)
    open.screenStart = Date(timeIntervalSinceNow: -2)
    let fake = Fake(segments: [closed, open], mic: true, state: .recording, folder: work)
    out["attached"] = fake.attachFailure ?? "ok"
    fake.screenFailed(0, "the writer gave up")
    _ = spin(0.3) { false }
    out["stateAfterFail"] = fake.state
    out["screenFailure"] = fake.recorder.session?.screenFailure.map { caseName($0) } ?? "nil"
    out["segment0"] = describeSegment(fake.segment(0))
    out["outputFailure0"] = fake.segment(0)?.outputFailure.map { spellError($0) } ?? "nil"
    out["micStopsAfterFail"] = fake.micOutput?.stops ?? -1
    var stops: [[String: Any]] = []
    fake.recorder.stop { stops.append(spell($0)) }
    out["stateAfterStop"] = fake.state
    out["micStopsAfterStop"] = fake.micOutput?.stops ?? -1
    fake.screenFinished(1)
    fake.micFinished(url: x1, error: nil)
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["onFinish"] = fake.finishes.first ?? [:]
    out["stopCount"] = stops.count
    return out
}

/// The same routing from PAUSED (issue batch B27, #181): segment 0 is a
/// NORMALLY closed segment whose did-finish has landed (the Fake's default
/// `screenFinished`), segment 1 open. A real `pause()` closes segment 1,
/// whose writer then reports a did-FAIL — the recorder STAYS `.paused`; its
/// microphone's did-finish lands, and a `stop()` lands segment 0 alone with
/// segment 1 left out. Only segment 1's did-fail and mic did-finish are driven.
func scenarioClosedFailPaused(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let m0 = work.appendingPathComponent("closedfailpaused0.png")
    let x0 = work.appendingPathComponent("closedfailpaused0-mic.png")
    let m1 = work.appendingPathComponent("closedfailpaused1.png")
    let x1 = work.appendingPathComponent("closedfailpaused1-mic.png")
    out["written"] = writePNG(m0) && writePNG(x0) && writePNG(m1) && writePNG(x1)
    out["paths"] = [m0.path, m1.path, x0.path, x1.path]
    var closed = FakeSegment(movie: m0, mic: x0, closed: true)
    closed.screenStart = Date(timeIntervalSinceNow: -5)
    closed.stoppedAt = Date(timeIntervalSinceNow: -3)
    var open = FakeSegment(movie: m1, mic: x1)
    open.screenStart = Date(timeIntervalSinceNow: -2)
    let fake = Fake(segments: [closed, open], mic: true, state: .recording, folder: work)
    out["attached"] = fake.attachFailure ?? "ok"
    do {
        try fake.recorder.pause()
        out["pause"] = "ok"
    } catch { out["pause"] = spellError(error) }
    fake.screenFailed(1, "the writer gave up while paused")
    _ = spin(0.3) { false }
    out["stateAfterFail"] = fake.state
    out["screenFailure"] = fake.recorder.session?.screenFailure.map { caseName($0) } ?? "nil"
    out["outputFailure1"] = fake.segment(1)?.outputFailure.map { spellError($0) } ?? "nil"
    fake.micFinished(url: x1, error: nil)
    _ = spin(0.2) { false }
    out["stateAfterMic"] = fake.state
    fake.recorder.stop()
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["onFinish"] = fake.finishes.first ?? [:]
    return out
}

/// An external stop while PAUSED: the pause's did-finish has landed (inert),
/// then the indicator's `.userStopped` arrives and takes the finishing path
/// with its reason — one segment, `stoppedBy` userStopped.
func scenarioExternalPaused(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("externalpaused.png")
    out["written"] = writePNG(movie)
    var first = FakeSegment(movie: movie, mic: nil)
    first.screenStart = Date(timeIntervalSinceNow: -2)
    let fake = Fake(segments: [first], mic: false, state: .recording, folder: work)
    do {
        try fake.recorder.pause()
        out["pause"] = "ok"
    } catch { out["pause"] = spellError(error) }
    fake.screenFinished(0)
    _ = spin(0.2) { false }
    out["stateAfterPauseFinish"] = fake.state
    out["segment0"] = describeSegment(fake.segment(0))
    let frozen = fake.recorder.elapsed
    out["pauses"] = fake.pauses
    fake.streamStopped(.userStopped)
    // The hop to main lands on the next turn; `beginFinishing` then runs
    // `checkFinished` synchronously and the one closed segment settles at
    // once, so the state is read the moment the hop has run.
    _ = spin(1) { fake.recorder.state != .paused }
    out["stateAfterExternal"] = fake.state
    out["stoppedBy"] = fake.stoppedBy
    out["settled"] = fake.settled()
    out["onFinish"] = fake.finishes.first ?? [:]
    out["elapsedFrozen"] = frozen
    return out
}

/// A stream stop while PAUSED with a code that is NOT an external stop (the
/// R2 review): nothing was writing, every file is closed, so the recording
/// LANDS as `.systemStopped` rather than failing with every file whole on
/// disk.
func scenarioSystemStopPaused(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("systempaused.png")
    out["written"] = writePNG(movie)
    var first = FakeSegment(movie: movie, mic: nil)
    first.screenStart = Date(timeIntervalSinceNow: -2)
    let fake = Fake(segments: [first], mic: false, state: .recording, folder: work)
    do {
        try fake.recorder.pause()
        out["pause"] = "ok"
    } catch { out["pause"] = spellError(error) }
    fake.screenFinished(0)
    _ = spin(0.2) { false }
    fake.streamStopped(.internalError)
    _ = spin(0.2) { false }
    out["stateAfter"] = fake.state
    out["stoppedBy"] = fake.stoppedBy
    out["settled"] = fake.settled()
    out["onFinish"] = fake.finishes.first ?? [:]
    return out
}

/// Two races the R2 review named, on the resume's ~10 ms window: a
/// did-start landing AFTER its own segment's pause is ignored (the span
/// would otherwise run backwards; it is clamped at 0 anyway), and a second
/// resume within the same second mints a DIFFERENT name from the one the
/// session already holds, although no file of either exists yet.
func scenarioLateDidStart(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("latedidstart.png")
    out["written"] = writePNG(movie)
    var first = FakeSegment(movie: movie, mic: nil)
    first.screenStart = Date(timeIntervalSinceNow: -1.0)
    let fake = Fake(segments: [first], mic: false, state: .recording, folder: work)
    do {
        try fake.recorder.pause()
        try fake.recorder.resume()
        try fake.recorder.pause()
        out["transitions"] = "ok"
    } catch { out["transitions"] = spellError(error) }
    out["segmentsAfter"] = fake.segmentCount
    // The did-start for segment 1 arrives after its own pause.
    fake.screenStarted(1)
    _ = spin(0.2) { false }
    out["segment1"] = describeSegment(fake.segment(1))
    out["elapsed"] = fake.recorder.elapsed
    do {
        try fake.recorder.resume()
        try fake.recorder.pause()
        out["secondResume"] = "ok"
    } catch { out["secondResume"] = spellError(error) }
    out["movies"] = (fake.recorder.session?.segments ?? []).map { $0.movieURL.path }
    out["pauses"] = fake.pauses
    out["stateAfter"] = fake.state
    out["filesExist"] = (fake.recorder.session?.segments ?? []).dropFirst().map {
        FileManager.default.fileExists(atPath: $0.movieURL.path)
    }
    return out
}

/// The walker over three closed segments, paused: the stamps are chosen so
/// `elapsed` is 2 + 3 + 1.5 s with two gaps of a second that it must not
/// count, segment 0's microphone never started (no file), segment 1's
/// began 20 ms AFTER its picture (offset −12 000), segment 2's writer
/// failed with its file left behind. A `stop()` while paused probes every
/// pair in order and answers ONE result with three `RecordingSegment`s.
func scenarioWalker(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let t0 = Date(timeIntervalSinceNow: -20)
    var segments: [FakeSegment] = []
    var paths: [[String: Any]] = []
    for index in 0..<3 {
        let movie = work.appendingPathComponent("walker\(index).png")
        let mic = work.appendingPathComponent("walker\(index)-mic.png")
        var segment = FakeSegment(movie: movie, mic: mic, closed: true)
        var written = writePNG(movie)
        switch index {
        case 0:
            segment.screenStart = t0
            segment.stoppedAt = t0.addingTimeInterval(2.0)
        case 1:
            segment.screenStart = t0.addingTimeInterval(3.0)
            segment.micStart = t0.addingTimeInterval(3.020)
            segment.stoppedAt = t0.addingTimeInterval(6.0)
            written = written && writePNG(mic)
        default:
            segment.screenStart = t0.addingTimeInterval(7.0)
            segment.micStart = t0.addingTimeInterval(7.0)
            segment.stoppedAt = t0.addingTimeInterval(8.5)
            segment.micFailure = "The microphone recording failed: boom."
            written = written && writePNG(mic)
        }
        segments.append(segment)
        paths.append(["movie": movie.path, "mic": mic.path, "written": written,
                      "screenStart": segment.screenStart!.timeIntervalSince1970])
    }
    out["paths"] = paths
    let fake = Fake(segments: segments, mic: true, state: .paused, folder: work)
    out["elapsedPaused"] = fake.recorder.elapsed
    _ = spin(0.2) { false }
    out["elapsedPausedAgain"] = fake.recorder.elapsed
    var stops: [[String: Any]] = []
    fake.recorder.stop { stops.append(spell($0)) }
    out["stateAfterStop"] = fake.state
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["onFinish"] = fake.finishes.first ?? [:]
    out["stop"] = stops.first ?? [:]
    return out
}

func state(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    // The driven half, in its own request so a fake that will not build
    // fails its rows and not the idle machine's.
    if request["drive"] as? Bool == true, let path = request["work"] as? String {
        // The policy pinned to never for the life of this probe (the helper).
        pinNeverRewrap()
        let work = URL(fileURLWithPath: path, isDirectory: true)
        out["join"] = scenarioJoin(work)
        out["oneShot"] = scenarioOneShot(work)
        out["micDies"] = scenarioMicDies(work)
        out["path"] = scenarioPath(work)
        out["external"] = scenarioExternal(work)
        out["idleFaces"] = scenarioIdleFaces(work)
        out["pause"] = scenarioPause(work)
        out["pauseRefused"] = scenarioPauseRefused(work)
        out["resumeRefused"] = scenarioResumeRefused(work)
        out["closedFail"] = scenarioClosedFail(work)
        out["closedFailPaused"] = scenarioClosedFailPaused(work)
        out["externalPaused"] = scenarioExternalPaused(work)
        out["systemStopPaused"] = scenarioSystemStopPaused(work)
        out["lateDidStart"] = scenarioLateDidStart(work)
        out["walker"] = scenarioWalker(work)
        return out
    }
    let recorder = ScreenRecorder()
    out["initialState"] = "\(recorder.state)"
    out["isRecording"] = recorder.isRecording
    out["elapsed"] = recorder.elapsed
    out["meterIsOwn"] = recorder.meter !== LevelMeter.shared

    func stopOnce() -> String {
        var outcome: String? = nil
        recorder.stop { result in
            switch result {
            case .success: outcome = "success"
            case .failure(let error):
                if case RecorderError.notRecording = error { outcome = "notRecording" }
                else { outcome = "other: \(error)" }
            }
        }
        return spin(1) { outcome != nil } ? (outcome ?? "?") : "no completion within 1 s"
    }
    out["stopWhileIdle"] = stopOnce()
    out["stateAfterStop"] = "\(recorder.state)"
    out["elapsedAfterStop"] = recorder.elapsed
    out["stopWhileIdleAgain"] = stopOnce()
    // A stop with no completion at all — the panel's spelling — is accepted
    // and changes nothing either.
    recorder.stop()
    out["stateAfterBareStop"] = "\(recorder.state)"

    var publishes = 0
    let observation = recorder.meter.addObserver { _ in publishes += 1 }
    let onSubscribe = publishes
    recorder.publishMicrophoneLevel()
    _ = spin(0.2) { false }
    out["meterCallsOnSubscribe"] = onSubscribe
    out["meterPublishesFromIdle"] = publishes - onSubscribe
    out["meterReadingIsSilent"] = recorder.meter.reading.isSilent
    withExtendedLifetime(observation) {}

    out["ppid"] = Int(getppid())
    out["screenPane"] = RecordingGrant.screenRecordingPaneSentence
    out["launchClause"] = RecordingGrant.launchClause
    out["micRefusal"] = [
        "notDetermined": RecordingGrant.microphoneRefusal(.notDetermined),
        "denied": RecordingGrant.microphoneRefusal(.denied),
        "restricted": RecordingGrant.microphoneRefusal(.restricted),
    ]
    out["screenRefusal"] = RecordingGrant.screenRecordingRefusal
    out["errors"] = [
        "busy": RecorderError.busy.localizedDescription,
        "notRecording": RecorderError.notRecording.localizedDescription,
        "timedOut": RecorderError.timedOut.localizedDescription,
        "startTimedOut": RecorderError.startTimedOut.localizedDescription,
        "startFailed": RecorderError.startFailed("why").localizedDescription,
        "filesKept": RecorderError.filesKept(
            .timedOut, movie: "/m/a.mov", microphone: "/m/a (Microphone).m4a"
        ).localizedDescription,
        "filesKeptAlone": RecorderError.filesKept(.finishFailed("why."), movie: "/m/a.mov",
            microphone: nil).localizedDescription,
        "notPaused": RecorderError.notPaused.localizedDescription,
        "filesKeptTwo": RecorderError.filesKept(
            .timedOut, movie: "/m/a.mov, /m/b.mov", microphone: "/m/x.m4a, /m/y.m4a"
        ).localizedDescription,
    ]
    out["linear"] = (request["decibels"] as? [Double] ?? []).map { dB -> [String: Any] in
        ["dB": dB, "linear": Double(RecordingMeter.linear(fromDecibels: Float(dB)))]
    }
    out["linearOfNegativeInfinity"] = Double(RecordingMeter.linear(fromDecibels: -.infinity))
    out["linearOfNaN"] = Double(RecordingMeter.linear(fromDecibels: .nan))
    // Host facts, never asserted: both are callable from a bare Mach-O.
    out["host"] = [
        "screenRecordingGranted": RecordingGrant.screenRecordingGranted,
        "microphoneStatus": RecordingGrant.name(of: RecordingGrant.microphoneStatus),
        "bundleIdentifier": Bundle.main.bundleIdentifier as Any,
    ]
    return out
}

// ---- mode "unreadable": a segment whose movie will not probe (#97) ---------

/// U1–U3's shape: closed segments of a `.paused` session over the given
/// movie fixtures — `true` a PNG "movie" `MediaImporter.probe` reads, `false`
/// an EMPTY `.mov` it refuses (or, with `writeMovies` false, NO file at all —
/// U7, issue batch B55) — each with a microphone PNG when `mic`, then
/// `stop`: the outcome as `onFinish` and the stop's completion receive it,
/// whether every microphone file is still on disk after it (`micsOnDisk`),
/// and the raw result for U6's pure rows.
func scenarioUnreadable(
    _ work: URL, _ tag: String, readable: [Bool], mic: Bool, writeMovies: Bool = true
) -> (out: [String: Any], result: RecordingResult?) {
    var out: [String: Any] = [:]
    let t0 = Date(timeIntervalSinceNow: -20)
    var segments: [FakeSegment] = []
    var movies: [String] = []
    var mics: [String] = []
    var written = true
    for (index, ok) in readable.enumerated() {
        let movie = work.appendingPathComponent("\(tag)-\(index)." + (ok ? "png" : "mov"))
        let micURL = mic ? work.appendingPathComponent("\(tag)-\(index)-mic.png") : nil
        written = written && (ok ? writePNG(movie) : (writeMovies ? emptyFile(movie) : true))
        if let micURL { written = written && writePNG(micURL) }
        var segment = FakeSegment(movie: movie, mic: micURL, closed: true)
        let start = t0.addingTimeInterval(Double(index) * 3)
        segment.screenStart = start
        segment.micStart = start
        segment.stoppedAt = start.addingTimeInterval(2)
        segments.append(segment)
        movies.append(movie.path)
        if let micURL { mics.append(micURL.path) }
    }
    out["written"] = written
    out["movies"] = movies
    out["mics"] = mics
    out["startedAt"] = segments.map { $0.screenStart?.timeIntervalSince1970 ?? 0 }
    let fake = Fake(segments: segments, mic: mic, state: .paused, folder: work)
    var stops: [[String: Any]] = []
    var raw: RecordingResult?
    fake.recorder.stop { outcome in
        stops.append(spell(outcome))
        if case .success(let result) = outcome { raw = result }
    }
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["onFinish"] = fake.finishes.first ?? [:]
    out["stopCount"] = stops.count
    out["stop"] = stops.first ?? [:]
    out["micsOnDisk"] = mics.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    out["moviesOnDisk"] = movies.filter { FileManager.default.fileExists(atPath: $0) }.count
    return (out, raw)
}

/// M1: a microphone did-finish carrying an error for a segment the machine
/// ASKED to stop — the pause's, −11805 for a writer stopped before its first
/// sample — is that segment's `micFailure` and never the session's
/// `microphoneProblem`; the stop then lands it as the segment's `micProblem`.
func scenarioMicBoundary(_ work: URL) -> [String: Any] {
    var out: [String: Any] = [:]
    let movie = work.appendingPathComponent("boundary.png")
    let mic = work.appendingPathComponent("boundary (Microphone).m4a")
    out["written"] = writePNG(movie)
    var first = FakeSegment(movie: movie, mic: mic)
    let start = Date(timeIntervalSinceNow: -1.0)
    first.screenStart = start
    first.micStart = start
    let fake = Fake(segments: [first], mic: true, state: .recording, folder: work)
    out["attached"] = fake.attachFailure ?? "ok"
    do {
        try fake.recorder.pause()
        out["pause"] = "ok"
    } catch { out["pause"] = spellError(error) }
    let error = NSError(
        domain: AVFoundationErrorDomain, code: -11805,
        userInfo: [NSLocalizedDescriptionKey: "Cannot Record"])
    fake.micFinished(url: mic, error: error)
    _ = spin(0.3) { false }
    out["stateAfterMicFinish"] = fake.state
    out["microphoneProblem"] = fake.recorder.microphoneProblem as Any
    out["liveNote"] = RecorderPanelController.liveNote(
        microphoneProblem: fake.recorder.microphoneProblem, resumeProblem: nil)
    out["segment0"] = describeSegment(fake.segment(0))
    fake.screenFinished(0)
    _ = spin(0.2) { false }
    out["stateAfterScreenFinish"] = fake.state
    var stops: [[String: Any]] = []
    fake.recorder.stop { stops.append(spell($0)) }
    out["settled"] = fake.settled()
    out["onFinishCount"] = fake.finishes.count
    out["onFinish"] = fake.finishes.first ?? [:]
    out["stopCount"] = stops.count
    return out
}

/// U4–U6, pure: the sentence, the note, the landing's order and the tool's
/// fields, notes and `savedButNotAdded` over U1's own result.
func unreadablePure(_ result: RecordingResult?) -> [String: Any] {
    var out: [String: Any] = [:]
    out["timedOut"] = RecorderError.timedOut.localizedDescription
    out["aloneSentence"] = UnreadableSegment(
        moviePath: "/x/a.mov", keptFiles: [], error: .timedOut
    ).sentence
    out["keptSentence"] = UnreadableSegment(
        moviePath: "/x/b.mov", keptFiles: ["/x/b.mov", "/x/b (Microphone).m4a"],
        error: .finishFailed("The recording could not be read: x.")
    ).sentence
    out["closedSentence"] = RecorderPanelController.destinationClosedSentence
    out["landing"] = [
        "r1": RecorderPanelController.landingNote(
            stoppedBy: .userStopped, chosen: .document(recipeKey: 1), landedAsNewProject: true,
            micProblem: "Mic."),
        "nil": RecorderPanelController.landingNote(
            stoppedBy: .userStopped, chosen: .document(recipeKey: 1), landedAsNewProject: true,
            micProblem: "Mic.", unreadable: nil),
        "all": RecorderPanelController.landingNote(
            stoppedBy: .userStopped, chosen: .document(recipeKey: 1), landedAsNewProject: true,
            micProblem: "Mic.", resumeProblem: "Resume.", notes: ["Note one.", "Note two."],
            unreadable: "Unreadable."),
        "only": RecorderPanelController.landingNote(
            stoppedBy: .stopped, chosen: .newProject, landedAsNewProject: false, micProblem: nil,
            unreadable: "Unreadable."),
    ]
    guard let result else {
        out["missing"] = true
        return out
    }
    if let segment = result.segments.first {
        let emptyNote = RecordingResult(
            segments: result.segments, choice: result.choice, stoppedBy: .stopped, pauses: 0
        ).unreadableNote
        out["emptyNoteIsNil"] = emptyNote == nil
        let micSegment = RecordingSegment(
            descriptor: segment.descriptor, micDescriptor: nil, micOffset: 0,
            startedAt: segment.startedAt, micProblem: "Mic gone.")
        let both = RecordingResult(
            segments: [micSegment], choice: result.choice, stoppedBy: .stopped, pauses: 1,
            unreadable: result.unreadable)
        let clean = RecordingResult(
            segments: result.segments, choice: result.choice, stoppedBy: .stopped, pauses: 1)
        out["unreadableNote"] = result.unreadableNote as Any
        out["fieldsUnreadable"] = AgentServer.recordingFields(result)["unreadable"] ?? NSNull()
        out["cleanHasUnreadable"] = AgentServer.recordingFields(clean)["unreadable"] != nil
        out["notesBoth"] = AgentServer.resultNotes(both)
        out["leftOutVoiceNote"] = both.leftOutVoiceNote as Any
        out["microphoneNoteBoth"] = AgentServer.microphoneNote(both) as Any
        out["notesClean"] = AgentServer.resultNotes(clean)
        let inner = AgentServer.ToolError(message: "a drag is in progress")
        out["savedWith"] = AgentServer.savedButNotAdded(result, inner).message
        out["savedClean"] = AgentServer.savedButNotAdded(clean, inner).message
        out["filesClause"] = result.filesClause
    }
    return out
}

func unreadableMode(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    pinNeverRewrap()
    let work = URL(
        fileURLWithPath: request["work"] as? String ?? NSTemporaryDirectory(), isDirectory: true)
    let u1 = scenarioUnreadable(work, "u1", readable: [true, false, true], mic: true)
    out["u1"] = u1.out
    out["u2"] = scenarioUnreadable(work, "u2", readable: [false, false], mic: true).out
    out["u3"] = scenarioUnreadable(work, "u3", readable: [false, true], mic: false).out
    out["u7"] = scenarioUnreadable(
        work, "u7", readable: [false, false], mic: true, writeMovies: false
    ).out
    out["pure"] = unreadablePure(u1.result)
    out["boundary"] = scenarioMicBoundary(work)
    return out
}

// ---- shared by the AppKit modes ------------------------------------------

/// Every descendant of one class, in subview order — which for a stack view
/// is its arranged order.
func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
    var found: [T] = []
    for sub in view.subviews {
        if let hit = sub as? T { found.append(hit) }
        found.append(contentsOf: descendants(type, in: sub))
    }
    return found
}

/// A view's own bitmap through `cacheDisplay` — the harness's paint path —
/// as base64 PNG, so two renders compare as strings.
func renderBase64(_ view: NSView) -> String {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return "none" }
    view.cacheDisplay(in: view.bounds, to: rep)
    return (rep.representation(using: .png, properties: [:]) ?? Data()).base64EncodedString()
}

func spellReply(_ reply: NSApplication.TerminateReply) -> String {
    switch reply {
    case .terminateCancel: return "terminateCancel"
    case .terminateNow: return "terminateNow"
    case .terminateLater: return "terminateLater"
    @unknown default: return "unknown"
    }
}

// ---- mode "landing": RecordingLanding and ProjectDocument.untitled --------

/// A probe outside the bundle has no Info.plist, so the shared controller
/// cannot answer `defaultType` or find the document class: subclass it (the
/// FIRST controller instantiated becomes `.shared`) so
/// `openUntitledDocumentAndDisplay` runs the real path on a `ProjectDocument`
/// with `fileType` set, exactly as the app's plist would make it.
final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document = ProjectDocument()
        document.fileType = typeName
        return document
    }
}

func fpsPair(_ f: Fps) -> [Int] { [f.num, f.den] }

/// A `Placement` list as plain ints — one overload per shape the tree has
/// had (`[UInt32]`, and `[UInt32?]` with −1 where nothing was minted), so
/// the probe compiles against either.
func ids(_ list: [UInt32]) -> [Int] { list.map { Int($0) } }
func ids(_ list: [UInt32?]) -> [Int] { list.map { $0.map { Int($0) } ?? -1 } }

/// One minted clip as plain numbers.
func describeClip(_ clip: ClipSnapshot) -> [String: Any] {
    var inPoint: Ticks = -1
    var mediaId = -1
    if case .media(let m, let i, _) = clip.source {
        inPoint = i
        mediaId = Int(m)
    }
    return [
        "id": Int(clip.id), "track": Int(clip.track), "start": clip.start,
        "duration": clip.duration, "in": inPoint, "media": mediaId, "end": clip.end,
        "transition": clip.transitionIn != nil,
    ]
}

/// Commits `placement.ops` through the document's own door — the panel's —
/// and reports what the core minted beside what the landing predicted, so a
/// row compares the two instead of trusting either.
func commit(_ document: ProjectDocument, _ placement: RecordingLanding.Placement) -> [String: Any] {
    let beforeDoc = document.project.snapshot
    let beforeView = document.editedProject.snapshot
    document.performGroupedEdit(RecordingLanding.actionName, placement.ops)
    let afterDoc = document.project.snapshot
    let afterView = document.editedProject.snapshot
    let media: [Int] = ProjectSnapshot.addedMedia(from: beforeDoc, to: afterDoc).map { Int($0) }
    let clipsBefore = Set(beforeView.clips.map { $0.id })
    let clips: [[String: Any]] =
        afterView.clips.filter { !clipsBefore.contains($0.id) }.map(describeClip)
    let tracksBefore = Set(beforeView.tracks.map { $0.id })
    let tracks: [[String: Any]] = afterView.tracks.filter { !tracksBefore.contains($0.id) }
        .map { ["id": Int($0.id), "name": $0.name] }
    let viewTracks: [[String: Any]] = afterView.tracks.map { ["id": Int($0.id), "name": $0.name] }
    let scopes: [Int] = placement.ops.map { op -> Int in op.scope.map { Int($0) } ?? -1 }
    let predicted: [String: Any] = [
        "media": Int(placement.mediaId), "clip": placement.clipId.map { Int($0) } ?? -1,
        "micMedia": placement.micMediaId.map { Int($0) } ?? -1,
        "micClip": placement.micClipId.map { Int($0) } ?? -1,
    ]
    // The four lists, in segment order; an entry nothing was minted for
    // (the fix wave's `[UInt32?]`) reads −1.
    let predictedLists: [String: Any] = [
        "media": ids(placement.mediaIds), "clips": ids(placement.clipIds),
        "micMedia": ids(placement.micMediaIds), "micClips": ids(placement.micClipIds),
    ]
    return [
        "ops": placement.ops.map { $0.name }, "opJSON": placement.ops.map { $0.json },
        "scopes": scopes, "predicted": predicted, "predictedLists": predictedLists,
        "nextIdBefore": Int(beforeDoc.nextId),
        "frontTrackBefore": Int(beforeView.tracks.last?.id ?? 0),
        "mintedMedia": media, "mintedClips": clips, "mintedTracks": tracks,
        "viewTracks": viewTracks, "notes": placement.notes,
        "documentClips": afterDoc.clips.count, "viewClips": afterView.clips.count,
        "documentMedia": afterDoc.media.count, "documentTracks": afterDoc.tracks.count,
        "canUndo": document.undoManager?.canUndo ?? false,
        "undoName": document.undoManager?.undoActionName ?? "",
        "frame": afterDoc.canvas.fps.frameDuration,
    ]
}

func landing(_ request: [String: Any]) -> [String: Any] {
    // FIRST, before anything reaches `NSDocumentController.shared`.
    let controller = ProbeDocumentController()
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain(
        ["ApplePersistenceIgnoreState": true,
         "AppleShowScrollBars": "Always"],
        forName: UserDefaults.argumentDomain)
    var out: [String: Any] = [:]
    out["controllerIsProbe"] = NSDocumentController.shared === controller

    let second: Ticks = 600_000
    let picture = MediaDescriptor(
        path: "/nowhere/Screen Recording 2026-09-10 at 14.03.22.mov", kind: .video,
        duration: 5 * second, width: 1728, height: 1118, fps: Fps(num: 24981, den: 1000),
        hasVideo: true, hasAudio: true)
    let microphone = MediaDescriptor(
        path: "/nowhere/Screen Recording 2026-09-10 at 14.03.22 (Microphone).m4a", kind: .audio,
        duration: 5 * second + 12_000, hasAudio: true)
    out["pictureDuration"] = picture.duration
    out["microphoneDuration"] = microphone.duration
    func result(
        mic: Bool, offset: Ticks = 0, rate: Int = 60, descriptor: MediaDescriptor? = nil,
        micDescriptor: MediaDescriptor? = nil
    ) -> RecordingResult {
        var choice = RecordingChoice()
        choice.rate = rate
        return RecordingResult(
            descriptor: descriptor ?? picture,
            micDescriptor: mic ? (micDescriptor ?? microphone) : nil,
            micOffset: offset, choice: choice, startedAt: Date(), stoppedBy: .stopped,
            micProblem: nil)
    }
    /// A fresh document with a clip at 0 on its one track.
    func blocked() -> ProjectDocument {
        let d = ProjectDocument()
        let blocker = MediaDescriptor(
            path: "/nowhere/blocker.mov", kind: .video, duration: 8 * second, width: 640,
            height: 360, fps: .thirty, hasVideo: true)
        let t = d.project.snapshot.tracks[0].id
        d.performGroupedEdit("seed", [.addMedia(descriptor: blocker)])
        let bid = d.project.snapshot.media.last?.id ?? 0
        d.performGroupedEdit("seed clip", [.addClip(track: t, media: bid, at: 0)])
        return d
    }

    // Row 1: a fresh project, an empty front track.
    do {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(result(mic: false), in: d, place: true)
        out["row1"] = commit(d, p)
    } catch { out["row1"] = ["error": "\(error)"] }

    // Row 2: a clip already at the playhead on the front track.
    do {
        let d = blocked()
        d.playhead = 1 * second
        let p = try RecordingLanding.placement(result(mic: false), in: d, place: true)
        out["row2"] = commit(d, p)
    } catch { out["row2"] = ["error": "\(error)"] }

    // Row 3, 3b: place false, without and with a microphone.
    do {
        let d = ProjectDocument()
        out["row3"] = commit(d, try RecordingLanding.placement(result(mic: false), in: d, place: false))
    } catch { out["row3"] = ["error": "\(error)"] }
    do {
        let d = ProjectDocument()
        out["row3b"] = commit(
            d, try RecordingLanding.placement(result(mic: true, offset: 12_000), in: d, place: false))
    } catch { out["row3b"] = ["error": "\(error)"] }

    // Rows 4a–4e: the offset rule, cases from the request.
    var micRows: [[String: Any]] = []
    for row in request["micCases"] as? [[String: Any]] ?? [] {
        var facts: [String: Any]
        do {
            let d = ProjectDocument()
            d.playhead = Ticks(row["playhead"] as? Int ?? 0)
            let p = try RecordingLanding.placement(
                result(mic: true, offset: Ticks(row["offset"] as? Int ?? 0)), in: d, place: true)
            facts = commit(d, p)
        } catch { facts = ["error": "\(error)"] }
        facts["name"] = row["name"] as? String ?? "?"
        micRows.append(facts)
    }
    out["micRows"] = micRows

    // Row 4f: a live gesture is refused by name.
    do {
        let d = ProjectDocument()
        d.beginLiveEdit()
        let liveDuring = d.isLiveEditing
        var refused = ""
        do { _ = try RecordingLanding.placement(result(mic: false), in: d, place: true) }
        catch { refused = error.localizedDescription }
        d.endLiveEdit("noop")
        out["row4f"] = ["message": refused, "liveDuring": liveDuring, "liveAfter": d.isLiveEditing,
                        "clips": d.project.snapshot.clips.count,
                        "media": d.project.snapshot.media.count]
    }

    // Rows 5, 5b, 5c: the untitled ORDER on the real ProjectDocument.
    let tmp = URL(
        fileURLWithPath: request["tempFolder"] as? String ?? NSTemporaryDirectory(),
        isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let movie = tmp.appendingPathComponent("Screen Recording 2026-09-10 at 14.03.22.mov")
        try Data("not a movie".utf8).write(to: movie)
        var desc = picture
        desc.path = movie.path
        let docsBefore = NSDocumentController.shared.documents.count
        let (d, _) = try ProjectDocument.untitled(around: result(mic: false, rate: 60, descriptor: desc))
        let s = d.project.snapshot
        // Keyed one at a time: one literal of this size is past what swiftc
        // will type-check in reasonable time.
        var row5: [String: Any] = [:]
        row5["displayName"] = d.displayName ?? "<nil>"
        row5["isDocumentEdited"] = d.isDocumentEdited
        row5["fileURL"] = d.fileURL?.path ?? "<nil>"
        row5["fileType"] = d.fileType ?? "<nil>"
        row5["packageType"] = ProjectDocument.projectTypeIdentifier
        row5["canvasFps"] = fpsPair(s.canvas.fps)
        row5["mediaFps"] = s.media.first.map { fpsPair($0.fps) } ?? []
        row5["canUndo"] = d.undoManager?.canUndo ?? false
        row5["windows"] = d.windowControllers.count
        row5["documentsBefore"] = docsBefore
        row5["documentsAfter"] = NSDocumentController.shared.documents.count
        row5["clips"] = s.clips.count
        row5["tracks"] = s.tracks.count
        row5["media"] = s.media.count
        row5["canvas"] = [s.canvas.width, s.canvas.height]
        row5["importSourceURL"] = d.importSourceURL?.path ?? "<nil>"
        row5["moviePath"] = movie.path
        row5["stem"] = movie.deletingPathExtension().lastPathComponent
        row5["clip"] = s.clips.first.map(describeClip) ?? [:]
        row5["trackId"] = Int(s.tracks.first?.id ?? 0)
        out["row5"] = row5
        // 5b: with a microphone — one grouped edit after the adopt, before the window.
        let movie2 = tmp.appendingPathComponent("Screen Recording 2026-09-10 at 15.00.00.mov")
        try Data("not a movie".utf8).write(to: movie2)
        let mic2 = tmp.appendingPathComponent(
            "Screen Recording 2026-09-10 at 15.00.00 (Microphone).m4a")
        try Data("not audio".utf8).write(to: mic2)
        var desc2 = picture
        desc2.path = movie2.path
        var micDesc = microphone
        micDesc.path = mic2.path
        let (d2, _) = try ProjectDocument.untitled(
            around: result(mic: true, offset: 12_000, rate: 60, descriptor: desc2,
                           micDescriptor: micDesc))
        let s2 = d2.project.snapshot
        func clip(of media: UInt32?) -> ClipSnapshot? {
            s2.clips.first { c in
                if case .media(let m, _, _) = c.source { return m == media }
                return false
            }
        }
        var row5b: [String: Any] = [:]
        row5b["displayName"] = d2.displayName ?? "<nil>"
        row5b["isDocumentEdited"] = d2.isDocumentEdited
        row5b["canUndo"] = d2.undoManager?.canUndo ?? false
        row5b["undoName"] = d2.undoManager?.undoActionName ?? ""
        row5b["media"] = s2.media.count
        row5b["tracks"] = s2.tracks.map { $0.name }
        row5b["clips"] = s2.clips.count
        row5b["mic"] = clip(of: s2.media.last?.id).map(describeClip) ?? [:]
        row5b["picture"] = clip(of: s2.media.first?.id).map(describeClip) ?? [:]
        row5b["backTrack"] = Int(s2.tracks.first?.id ?? 0)
        row5b["frontTrack"] = Int(s2.tracks.last?.id ?? 0)
        row5b["frame"] = s2.canvas.fps.frameDuration
        row5b["canvasFps"] = fpsPair(s2.canvas.fps)
        row5b["mediaFps"] = s2.media.map { fpsPair($0.fps) }
        row5b["windows"] = d2.windowControllers.count
        row5b["stem"] = movie2.deletingPathExtension().lastPathComponent
        row5b["fileURL"] = d2.fileURL?.path ?? "<nil>"
        out["row5b"] = row5b
        // 5c: one undo removes the microphone's media and clip, keeps the
        // picture — and the document STAYS dirty: the import count is made
        // BEFORE the microphone's edit, so the undo takes the count from two
        // to one, not from one to zero (the review's ⌘W with no prompt).
        d2.undoManager?.undo()
        let s3 = d2.project.snapshot
        var row5c: [String: Any] = [:]
        row5c["media"] = s3.media.count
        row5c["clips"] = s3.clips.count
        row5c["tracks"] = s3.tracks.count
        row5c["canUndo"] = d2.undoManager?.canUndo ?? true
        row5c["canRedo"] = d2.undoManager?.canRedo ?? false
        row5c["pictureMedia"] = s3.media.first.map { Int($0.id) } ?? -1
        row5c["clipMedia"] = s3.clips.first.map(describeClip)?["media"] as? Int ?? -1
        row5c["isDocumentEdited"] = d2.isDocumentEdited
        row5c["redoName"] = d2.undoManager?.redoActionName ?? ""
        d2.undoManager?.redo()
        row5c["isDocumentEditedAfterRedo"] = d2.isDocumentEdited
        row5c["mediaAfterRedo"] = d2.project.snapshot.media.count
        row5c["undoNameAfterRedo"] = d2.undoManager?.undoActionName ?? ""
        out["row5c"] = row5c
        d.close()
        d2.close()
        out["documentsAfterClose"] = NSDocumentController.shared.documents.count
    } catch { out["row5"] = ["error": "\(error)"] }

    // Row 6: resolve — by recipeKey among TWO open documents.
    do {
        guard let a = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
                as? ProjectDocument,
            let b = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
                as? ProjectDocument
        else { throw ReelCoreError(message: "no untitled document") }
        func resolved(_ key: Int) -> String {
            switch RecordingLanding.resolve(.document(recipeKey: key)) {
            case .document(let found): return found === a ? "A" : (found === b ? "B" : "other")
            case .newProject: return "newProject"
            }
        }
        var facts: [String: Any] = [
            "keyA": a.recipeKey, "keyB": b.recipeKey,
            "openDuring": NSDocumentController.shared.documents.count,
            "firstIsA": (NSDocumentController.shared.documents.first as? ProjectDocument) === a,
        ]
        let unknown = max(a.recipeKey, b.recipeKey) + 1000
        facts["B"] = resolved(b.recipeKey)
        facts["A"] = resolved(a.recipeKey)
        facts["unknownWithBoth"] = resolved(unknown)
        b.close()
        facts["BAfterClose"] = resolved(b.recipeKey)
        facts["AAfterBClose"] = resolved(a.recipeKey)
        facts["unknownWithA"] = resolved(unknown)
        if case .newProject = RecordingLanding.resolve(.newProject) {
            facts["plain"] = "newProject"
        } else {
            facts["plain"] = "document"
        }
        a.close()
        facts["AAfterClose"] = resolved(a.recipeKey)
        facts["openAfter"] = NSDocumentController.shared.documents.count
        out["row6"] = facts
    } catch { out["row6"] = ["error": "\(error)"] }

    // Row 7: inside an open nest — the clips land INSIDE, ids as predicted.
    do {
        let d = blocked()
        let cid = d.project.snapshot.clips.last?.id ?? 0
        d.performGroupedEdit("nest", [.nest(clips: [cid], name: "N")])
        let s = d.project.snapshot
        guard let nestClip = s.clips.first, let nest = s.nests.first else {
            throw ReelCoreError(message: "no nest")
        }
        d.setNestPath([NestScopeStep(nest: nest.id, clip: nestClip.id)], playhead: 0, selection: [])
        let scope = d.scope.map { Int($0) } ?? -1
        let p = try RecordingLanding.placement(result(mic: true, offset: 12_000), in: d, place: true)
        var facts = commit(d, p)
        let inner = d.editedProject.snapshot
        let outer = d.project.snapshot
        facts["scope"] = scope
        facts["nestId"] = Int(nest.id)
        facts["innerClips"] = inner.clips.count
        facts["innerTracks"] = inner.tracks.map { ["id": Int($0.id), "name": $0.name] }
        facts["innerFrontTrack"] = Int(inner.tracks.last?.id ?? 0)
        facts["innerBackTrack"] = Int(inner.tracks.first?.id ?? 0)
        facts["innerMedia"] = inner.media.count
        facts["outerClips"] = outer.clips.count
        facts["outerTracks"] = outer.tracks.count
        facts["outerMedia"] = outer.media.count
        out["row7"] = facts
    } catch { out["row7"] = ["error": "\(error)"] }

    // Row 8: the caps in the TRIAL — a document at MAX_TRACKS (64), at the
    // top level and inside a nest. `placement` applies each scoped op to the
    // PARENT handle, which is the scoped apply itself, so `check_caps` on the
    // merged parent refuses in the trial with the core's sentence and nothing
    // is committed. 8d is the positive control, one track under the cap.
    do {
        var row8: [String: Any] = [:]
        func fill(_ d: ProjectDocument, _ count: Int) {
            d.performGroupedEdit("fill", (0..<count).map { _ in ReelOp.addTrack(index: 0) })
        }
        // 8a, 8b: the top level, an empty front track — the picture alone
        // needs no track; the microphone's would be the 65th.
        let d = ProjectDocument()
        fill(d, 63)
        row8["tracks"] = d.project.snapshot.tracks.count
        do {
            let p = try RecordingLanding.placement(result(mic: false), in: d, place: true)
            row8["pictureOps"] = p.ops.map { $0.name }
        } catch { row8["pictureOps"] = ["error: \(error.localizedDescription)"] }
        do {
            let p = try RecordingLanding.placement(
                result(mic: true, offset: 12_000), in: d, place: true)
            row8["micError"] = "<no throw: \(p.ops.map { $0.name })>"
        } catch { row8["micError"] = error.localizedDescription }
        let after = d.project.snapshot
        row8["mediaAfter"] = after.media.count
        row8["clipsAfter"] = after.clips.count
        row8["tracksAfter"] = after.tracks.count
        row8["undoNameAfter"] = d.undoManager?.undoActionName ?? ""
        // 8c: inside a nest at the cap — `count` outer tracks and the nest's
        // one, whose clip blocks the playhead, so the picture needs a track
        // of its own, counted on the MERGED parent.
        func nested(fill count: Int) throws -> ProjectDocument {
            let n = blocked()
            let cid = n.project.snapshot.clips.last?.id ?? 0
            n.performGroupedEdit("nest", [.nest(clips: [cid], name: "N")])
            fill(n, count)
            let snap = n.project.snapshot
            guard let nestClip = snap.clips.first, let nest = snap.nests.first else {
                throw ReelCoreError(message: "no nest")
            }
            n.setNestPath(
                [NestScopeStep(nest: nest.id, clip: nestClip.id)], playhead: 0, selection: [])
            return n
        }
        let n = try nested(fill: 62)
        row8["nestScope"] = n.scope.map { Int($0) } ?? -1
        row8["nestOuterTracks"] = n.project.snapshot.tracks.count
        row8["nestInnerTracks"] = n.editedProject.snapshot.tracks.count
        do {
            let p = try RecordingLanding.placement(result(mic: false), in: n, place: true)
            row8["nestError"] = "<no throw: \(p.ops.map { $0.name })>"
        } catch { row8["nestError"] = error.localizedDescription }
        row8["nestMediaAfter"] = n.project.snapshot.media.count
        row8["nestInnerClipsAfter"] = n.editedProject.snapshot.clips.count
        row8["nestInnerTracksAfter"] = n.editedProject.snapshot.tracks.count
        row8["nestOuterTracksAfter"] = n.project.snapshot.tracks.count
        // 8d: one under the cap, the same landing trials clean and commits —
        // the 64th track, inside the nest.
        let u = try nested(fill: 61)
        do {
            let p = try RecordingLanding.placement(result(mic: false), in: u, place: true)
            var facts = commit(u, p)
            facts["innerTracksAfter"] = u.editedProject.snapshot.tracks.count
            facts["outerTracksAfter"] = u.project.snapshot.tracks.count
            row8["under"] = facts
        } catch { row8["under"] = ["error": error.localizedDescription] }
        out["row8"] = row8
    } catch { out["row8"] = ["error": "\(error)"] }
    return out
}

// ---- mode "segments": the landing over a SEQUENCE (road map 3, R2b) ----

/// Lane L's scratch rows made tracked: two- and three-segment results
/// placed back to back on ONE track with the ends READ off the handle, the
/// sequence falling to a new track whole, the microphone floor, a
/// mic-less middle, `place: false`, inside a nest, and `remainderPlacement`
/// through the real untitled order. Every row commits through the
/// document's own door and reports what the core minted beside the
/// prediction; the checks are the script's.
func segments(_ request: [String: Any]) -> [String: Any] {
    let controller = ProbeDocumentController()
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain(
        ["ApplePersistenceIgnoreState": true,
         "AppleShowScrollBars": "Always"],
        forName: UserDefaults.argumentDomain)
    var out: [String: Any] = [:]
    out["controllerIsProbe"] = NSDocumentController.shared === controller
    let tmp = URL(
        fileURLWithPath: request["tempFolder"] as? String ?? NSTemporaryDirectory(),
        isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let second: Ticks = 600_000

    func picture(_ n: Int, ticks: Ticks = 5 * 600_000) -> MediaDescriptor {
        MediaDescriptor(
            path: tmp.appendingPathComponent("seg\(n).mov").path, kind: .video, duration: ticks,
            width: 1728, height: 1118, fps: Fps(num: 24981, den: 1000), hasVideo: true,
            hasAudio: true)
    }
    func mic(_ n: Int, ticks: Ticks) -> MediaDescriptor {
        MediaDescriptor(
            path: tmp.appendingPathComponent("seg\(n) (Microphone).m4a").path, kind: .audio,
            duration: ticks, hasAudio: true)
    }
    func segment(
        _ n: Int, ticks: Ticks = 5 * 600_000, micTicks: Ticks? = nil, offset: Ticks = 0
    ) -> RecordingSegment {
        RecordingSegment(
            descriptor: picture(n, ticks: ticks), micDescriptor: micTicks.map { mic(n, ticks: $0) },
            micOffset: offset, startedAt: Date())
    }
    func result(_ list: [RecordingSegment], rate: Int = 60) -> RecordingResult {
        var choice = RecordingChoice()
        choice.rate = rate
        return RecordingResult(
            segments: list, choice: choice, stoppedBy: .stopped, pauses: list.count - 1)
    }
    func blocked(from: Ticks, seconds: Ticks) -> ProjectDocument {
        let d = ProjectDocument()
        let blocker = MediaDescriptor(
            path: "/nowhere/blocker.mov", kind: .video, duration: seconds * second, width: 640,
            height: 360, fps: .thirty, hasVideo: true)
        let t = d.project.snapshot.tracks[0].id
        d.performGroupedEdit("seed", [.addMedia(descriptor: blocker)])
        let bid = d.project.snapshot.media.last?.id ?? 0
        d.performGroupedEdit("seed clip", [.addClip(track: t, media: bid, at: from)])
        return d
    }
    /// `commit` plus the facts a sequence row reads: the front track before,
    /// `next_id` before, and every clip in the edited container after.
    func placed(_ d: ProjectDocument, _ p: RecordingLanding.Placement) -> [String: Any] {
        var facts = commit(d, p)
        facts["allClips"] = d.editedProject.snapshot.clips.map(describeClip)
        return facts
    }
    func row(_ body: () throws -> [String: Any]) -> [String: Any] {
        do { return try body() } catch { return ["error": "\(error)"] }
    }

    // A: two segments on a fresh document.
    out["A"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(result([segment(1), segment(2)]), in: d, place: true)
        return placed(d, p)
    }
    // B: off-grid durations — the end is READ off the core, never summed.
    out["B"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([segment(1, ticks: 5 * second + 7), segment(2, ticks: 1_504_999), segment(3)]),
            in: d, place: true)
        return placed(d, p)
    }
    // C: the second segment refuses on the front track (a blocker at 7–15 s).
    out["C"] = row {
        let d = blocked(from: 7 * second, seconds: 8)
        let p = try RecordingLanding.placement(result([segment(1), segment(2)]), in: d, place: true)
        var facts = placed(d, p)
        facts["frontTrackAfter"] = Int(d.project.snapshot.tracks.last?.id ?? 0)
        return facts
    }
    // D: the FIRST refuses (a blocker at 1–9 s).
    out["D"] = row {
        let d = blocked(from: 1 * second, seconds: 8)
        let p = try RecordingLanding.placement(result([segment(1), segment(2)]), in: d, place: true)
        var facts = placed(d, p)
        facts["frontTrackAfter"] = Int(d.project.snapshot.tracks.last?.id ?? 0)
        return facts
    }
    // E: the microphone floor — segment 2's voice wants 3 000 000 − 11 000,
    // the floor is voice 1's end.
    out["E"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([
                segment(1, micTicks: 3_012_000, offset: 0),
                segment(2, micTicks: 3_012_000, offset: 11_000),
            ]), in: d, place: true)
        return placed(d, p)
    }
    // E2: a lagging microphone (negative offset) is above the floor: no trim.
    out["E2"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([
                segment(1, micTicks: 3_012_000, offset: 0),
                segment(2, micTicks: 3_012_000, offset: -30_000),
            ]), in: d, place: true)
        return placed(d, p)
    }
    // E3: rounding AT the floor — voice 1 ends exactly where picture 2 starts.
    var boundary: [[String: Any]] = []
    for offset in request["boundaryOffsets"] as? [Int] ?? [] {
        var facts = row {
            let d = ProjectDocument()
            let p = try RecordingLanding.placement(
                result([
                    segment(1, micTicks: 3_000_000, offset: 0),
                    segment(2, micTicks: 3_000_000, offset: Ticks(offset)),
                ]), in: d, place: true)
            return placed(d, p)
        }
        facts["offset"] = offset
        boundary.append(facts)
    }
    out["E3"] = boundary
    // E4: the hazard the floor exists for, on the core directly: an add_clip
    // three quarters of a frame under a clip's end is snapped a frame EARLY
    // and accepted — as a transition.
    out["E4"] = row {
        let d = ProjectDocument()
        d.performGroupedEdit(
            "seed", [.addMedia(descriptor: mic(1, ticks: 3_000_000)),
                     .addMedia(descriptor: mic(2, ticks: 3_000_000))])
        let ids = d.project.snapshot.media.map { $0.id }
        let t = d.project.snapshot.tracks[0].id
        d.performGroupedEdit("seed clip", [.addClip(track: t, media: ids[0], at: 0)])
        let frame = d.project.snapshot.canvas.fps.frameDuration
        // `.project` is nil for BOTH non-applied arms (`ReelEdit.swift`),
        // which is the reading this row wants: "accepted" asks only whether
        // the overlap the recorder left was taken as a transition.
        let raw = try d.project.applying(
            .addClip(track: t, media: ids[1], at: 3_000_000 - (frame - frame / 4)))
            .project
        return [
            "frame": frame, "accepted": raw != nil,
            "clip": raw?.snapshot.clips.last.map(describeClip) ?? [:],
        ]
    }
    // F: a middle segment with no microphone.
    out["F"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([
                segment(1, micTicks: 3_000_000, offset: 0), segment(2),
                segment(3, micTicks: 3_000_000, offset: 12_000),
            ]), in: d, place: true)
        return placed(d, p)
    }
    // G: place false.
    out["G"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([segment(1, micTicks: 3_000_000), segment(2)]), in: d, place: false)
        return placed(d, p)
    }
    // H: inside a nest whose one clip blocks the playhead.
    out["H"] = row {
        let n = blocked(from: 0, seconds: 8)
        let cid = n.project.snapshot.clips.last?.id ?? 0
        n.performGroupedEdit("nest", [.nest(clips: [cid], name: "N")])
        let snap = n.project.snapshot
        guard let nestClip = snap.clips.first, let nest = snap.nests.first else {
            throw ReelCoreError(message: "no nest")
        }
        n.setNestPath([NestScopeStep(nest: nest.id, clip: nestClip.id)], playhead: 0, selection: [])
        let p = try RecordingLanding.placement(result([segment(1), segment(2)]), in: n, place: true)
        var facts = placed(n, p)
        facts["scopeOpen"] = n.scope == nest.id
        facts["outerClips"] = n.project.snapshot.clips.count
        facts["outerMedia"] = n.project.snapshot.media.count
        facts["outerTracks"] = n.project.snapshot.tracks.count
        return facts
    }
    // J: an INEXACT canvas rate (24981/1000, decision 3's shape): the
    // previous end is not a grid point, so each later segment lands at the
    // first grid point at or after it — touching or a sub-frame gap, never
    // a tick of overlap and never a minted cross dissolve (the R2 review).
    out["J"] = row {
        let d = ProjectDocument()
        d.performGroupedEdit("rate", [.setCanvas(fps: Fps(num: 24981, den: 1000))])
        let p = try RecordingLanding.placement(
            result([segment(1), segment(2), segment(3)]), in: d, place: true)
        var facts = placed(d, p)
        facts["canvasFps"] = fpsPair(d.project.snapshot.canvas.fps)
        return facts
    }
    // K: a voice SHORTER than its head — mic 1 ends 3 040 000, picture 2 is
    // at 3 000 000, mic 2 is an 80 ms file with offset +18 000 — mints NO
    // clip and a note, never a sliver placed late (the R2 review's numbers).
    out["K"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([
                segment(1, micTicks: 3_040_000, offset: 0),
                segment(2, micTicks: 48_000, offset: 18_000),
            ]), in: d, place: true)
        return placed(d, p)
    }
    // L: a microphone file under one frame (R0 q7's real 2 ms file).
    out["L"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([
                segment(1, micTicks: 3_000_000, offset: 0), segment(2, micTicks: 1_200, offset: 0),
            ]), in: d, place: true)
        return placed(d, p)
    }
    // M: a PICTURE under one frame in the middle.
    out["M"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(
            result([segment(1), segment(2, ticks: 5_000), segment(3)]), in: d, place: true)
        return placed(d, p)
    }
    // N: remainderPlacement with NO clip 1 — the document holds the first
    // picture's media and no clip (makeProject tolerates a first picture the
    // core refuses): the fallback lands the microphone MEDIA only.
    out["N"] = row {
        let d = ProjectDocument()
        d.performGroupedEdit("seed", [.addMedia(descriptor: picture(1))])
        guard let p = try RecordingLanding.remainderPlacement(
            result([segment(1, micTicks: 3_000_000, offset: 12_000)]), in: d)
        else { return ["nil": true] }
        return placed(d, p)
    }

    // I: untitled(around:) — the remainder, through the real order.
    for n in 1...3 {
        try? Data("not a movie".utf8).write(to: tmp.appendingPathComponent("seg\(n).mov"))
        try? Data("not audio".utf8).write(
            to: tmp.appendingPathComponent("seg\(n) (Microphone).m4a"))
    }
    out["names"] = [
        "three": RecordingLanding.remainderActionName(
            for: result([segment(1, micTicks: 3_012_000), segment(2), segment(3)])),
        "oneMic": RecordingLanding.remainderActionName(for: result([segment(1, micTicks: 1000)])),
        "oneAlone": RecordingLanding.remainderActionName(for: result([segment(1)])),
        "twoNoMic": RecordingLanding.remainderActionName(for: result([segment(1), segment(2)])),
        "microphoneActionName": RecordingLanding.microphoneActionName,
        "segmentsActionName": RecordingLanding.segmentsActionName,
        "actionName": RecordingLanding.actionName,
    ]
    out["remainderNil"] = row {
        let d = ProjectDocument()
        return ["nil": try RecordingLanding.remainderPlacement(result([segment(1)]), in: d) == nil]
    }
    out["I"] = row {
        let r = result([
            segment(1, micTicks: 3_012_000, offset: 0), segment(2),
            segment(3, micTicks: 3_012_000, offset: 11_000),
        ])
        let docsBefore = NSDocumentController.shared.documents.count
        let (d, landingNotes) = try ProjectDocument.untitled(around: r)
        let s = d.project.snapshot
        var facts: [String: Any] = [:]
        facts["notes"] = landingNotes
        facts["displayName"] = d.displayName ?? "<nil>"
        facts["canvasFps"] = fpsPair(s.canvas.fps)
        facts["frame"] = s.canvas.fps.frameDuration
        facts["edited"] = d.isDocumentEdited
        facts["undoName"] = d.undoManager?.undoActionName ?? ""
        facts["media"] = s.media.count
        facts["tracks"] = s.tracks.map { $0.name }
        facts["backTrack"] = Int(s.tracks.first?.id ?? 0)
        facts["frontTrack"] = Int(s.tracks.last?.id ?? 0)
        facts["clips"] = s.clips.map(describeClip)
        facts["windows"] = d.windowControllers.count
        facts["documents"] = NSDocumentController.shared.documents.count - docsBefore
        d.undoManager?.undo()
        let u = d.project.snapshot
        facts["afterUndo"] = [
            "clips": u.clips.count, "media": u.media.count, "tracks": u.tracks.count,
            "edited": d.isDocumentEdited, "redoName": d.undoManager?.redoActionName ?? "",
        ]
        d.close()
        return facts
    }
    out["I2"] = row {
        let (d, _) = try ProjectDocument.untitled(
            around: result([segment(1, micTicks: 3_012_000, offset: 12_000)]))
        let s = d.project.snapshot
        var facts: [String: Any] = [:]
        facts["undoName"] = d.undoManager?.undoActionName ?? ""
        facts["backTrack"] = Int(s.tracks.first?.id ?? 0)
        facts["tracks"] = s.tracks.map { $0.name }
        facts["clips"] = s.clips.map(describeClip)
        facts["media"] = s.media.count
        d.close()
        return facts
    }
    out["I3"] = row {
        let (d, landingNotes) = try ProjectDocument.untitled(around: result([segment(1)]))
        let facts: [String: Any] = [
            "canUndo": d.undoManager?.canUndo ?? true, "edited": d.isDocumentEdited,
            "media": d.project.snapshot.media.count, "clips": d.project.snapshot.clips.count,
            "notes": landingNotes,
        ]
        d.close()
        return facts
    }
    out["documentsAfterClose"] = NSDocumentController.shared.documents.count
    return out
}

// ---- mode "leftout": a left-out segment's readable voice (issue batch B55) ----

/// Section 14's rows (#181 item 2, spec §11 recording): results CONSTRUCTED —
/// no stream, no recording — of a 5 s picture A with a 5 s voice at offset
/// 0, a left-out B whose 3 s voice read, and a 5 s C with a 5 s voice, landed
/// in a fresh document (30 fps) and through `untitled(around:)` (60 fps).
/// Every document row commits through the document's own door and reports
/// what the core minted beside the prediction; the checks are the script's.
func leftout(_ request: [String: Any]) -> [String: Any] {
    let controller = ProbeDocumentController()
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain(
        ["ApplePersistenceIgnoreState": true,
         "AppleShowScrollBars": "Always"],
        forName: UserDefaults.argumentDomain)
    var out: [String: Any] = [:]
    out["controllerIsProbe"] = NSDocumentController.shared === controller
    let tmp = URL(
        fileURLWithPath: request["tempFolder"] as? String ?? NSTemporaryDirectory(),
        isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let second: Ticks = 600_000

    func picture(_ name: String) -> MediaDescriptor {
        MediaDescriptor(
            path: tmp.appendingPathComponent("\(name).mov").path, kind: .video,
            duration: 5 * second, width: 1728, height: 1118, fps: Fps(num: 24981, den: 1000),
            hasVideo: true, hasAudio: false)
    }
    func mic(_ name: String, _ ticks: Ticks) -> MediaDescriptor {
        MediaDescriptor(
            path: tmp.appendingPathComponent("\(name) (Microphone).m4a").path, kind: .audio,
            duration: ticks, hasAudio: true)
    }
    func segment(_ name: String, voice: Bool = true) -> RecordingSegment {
        RecordingSegment(
            descriptor: picture(name), micDescriptor: voice ? mic(name, 5 * second) : nil,
            micOffset: 0, startedAt: Date())
    }
    func leftB(position: Int, voice: Bool = true) -> UnreadableSegment {
        UnreadableSegment(
            moviePath: tmp.appendingPathComponent("B.mov").path,
            keptFiles: [tmp.appendingPathComponent("B.mov").path, mic("B", 3 * second).path],
            error: .finishFailed("The recording could not be read: the probe's B."),
            micDescriptor: voice ? mic("B", 3 * second) : nil, position: position)
    }
    func result(_ list: [RecordingSegment], _ left: [UnreadableSegment]) -> RecordingResult {
        var choice = RecordingChoice()
        choice.rate = 60
        return RecordingResult(
            segments: list, choice: choice, stoppedBy: .stopped,
            pauses: list.count + left.count - 1, unreadable: left)
    }
    func stretchNames(_ r: RecordingResult) -> [String] {
        r.stretches.map { stretch in
            switch stretch {
            case .segment(let k): return "segment\(k)"
            case .voiceOnly(let i): return "voice\(i)"
            }
        }
    }
    func lists(_ p: RecordingLanding.Placement) -> [String: Any] {
        [
            "media": ids(p.mediaIds), "clips": ids(p.clipIds), "micMedia": ids(p.micMediaIds),
            "micClips": ids(p.micClipIds), "leftOutMicMedia": ids(p.leftOutMicMediaIds),
            "leftOutMicClips": ids(p.leftOutMicClipIds),
        ]
    }
    func placed(_ d: ProjectDocument, _ p: RecordingLanding.Placement) -> [String: Any] {
        var facts = commit(d, p)
        facts["lists"] = lists(p)
        facts["allClips"] = d.editedProject.snapshot.clips.map(describeClip)
        facts["allTracks"] = d.editedProject.snapshot.tracks.map {
            ["id": Int($0.id), "name": $0.name] as [String: Any]
        }
        return facts
    }
    func row(_ body: () throws -> [String: Any]) -> [String: Any] {
        do { return try body() } catch { return ["error": "\(error)"] }
    }
    for name in ["A", "C"] {
        try? Data("not a movie".utf8).write(to: tmp.appendingPathComponent("\(name).mov"))
    }
    for name in ["A", "B", "C"] {
        try? Data("not audio".utf8).write(to: URL(fileURLWithPath: mic(name, 0).path))
    }
    let r1 = result([segment("A"), segment("C")], [leftB(position: 1)])
    out["micB"] = mic("B", 3 * second).path
    out["pathA"] = picture("A").path

    // X1: a document at playhead 0 — B's voice in its slot, C after it.
    var x1Placement: RecordingLanding.Placement?
    out["X1"] = row {
        let d = ProjectDocument()
        let p = try RecordingLanding.placement(r1, in: d, place: true)
        x1Placement = p
        var facts = placed(d, p)
        facts["stretches"] = stretchNames(r1)
        return facts
    }
    // X2: B recorded FIRST (position 0), the playhead at 1 s.
    out["X2"] = row {
        let r = result([segment("A"), segment("C")], [leftB(position: 0)])
        let d = ProjectDocument()
        d.playhead = 1 * second
        let p = try RecordingLanding.placement(r, in: d, place: true)
        var facts = placed(d, p)
        facts["stretches"] = stretchNames(r)
        return facts
    }
    // X3: X1's result as a new project.
    out["X3"] = row {
        let (d, notes) = try ProjectDocument.untitled(around: r1)
        let s = d.project.snapshot
        var facts: [String: Any] = [:]
        facts["notes"] = notes
        facts["undoName"] = d.undoManager?.undoActionName ?? ""
        facts["clips"] = s.clips.map(describeClip)
        facts["tracks"] = s.tracks.map { ["id": Int($0.id), "name": $0.name] as [String: Any] }
        facts["media"] = s.media.map { ["id": Int($0.id), "path": $0.path] as [String: Any] }
        facts["leftOutIds"] = AgentServer.newProjectLeftOutIds(r1, in: d).map {
            ["micMedia": $0.micMedia.map { Int($0) } ?? -1,
             "micClip": $0.micClip.map { Int($0) } ?? -1]
        }
        d.undoManager?.undo()
        let u = d.project.snapshot
        facts["afterUndo"] = [
            "clips": u.clips.map(describeClip), "media": u.media.count,
            "tracks": u.tracks.count,
        ]
        d.close()
        return facts
    }
    // X4: B before the only segment, which has no voice of its own.
    let r4 = result([segment("A", voice: false)], [leftB(position: 0)])
    out["X4"] = row {
        let (d, notes) = try ProjectDocument.untitled(around: r4)
        let s = d.project.snapshot
        let facts: [String: Any] = [
            "notes": notes, "undoName": d.undoManager?.undoActionName ?? "",
            "clips": s.clips.map(describeClip),
            "media": s.media.map { ["id": Int($0.id), "path": $0.path] as [String: Any] },
            "leadingNote": RecordingLanding.leadingVoiceNote(
                mic("B", 3 * second).path, before: picture("A").path),
            "actionName": RecordingLanding.remainderActionName(for: r4),
            "actionNameWithoutB": RecordingLanding.remainderActionName(
                for: result([segment("A", voice: false)], [leftB(position: 0, voice: false)])),
        ]
        d.close()
        return facts
    }
    // X5: place: false.
    out["X5"] = row {
        let d = ProjectDocument()
        return placed(d, try RecordingLanding.placement(r1, in: d, place: false))
    }
    // X6: what the tool says about X1's landing.
    out["X6"] = row {
        guard let p = x1Placement else { return ["error": "X1 did not place"] }
        let fields = AgentServer.recordingFields(
            r1, ids: AgentServer.documentIds(r1, placement: p),
            leftOutIds: AgentServer.documentLeftOutIds(r1, placement: p))
        let inner = AgentServer.ToolError(message: "a drag is in progress")
        var description = ""
        let json = try AgentServer.shared.catalogJSON()
        let tools = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] ?? []
        for tool in tools where tool["name"] as? String == "record_screen" {
            description = tool["description"] as? String ?? ""
        }
        return [
            "unreadable": fields["unreadable"] ?? NSNull(),
            "resultNotes": AgentServer.resultNotes(r1),
            "leftOutVoiceNote": r1.leftOutVoiceNote as Any,
            "unreadableNote": r1.unreadableNote as Any,
            "saved": AgentServer.savedButNotAdded(r1, inner).message,
            "description": description,
        ]
    }
    // X7: a left-out B whose voice did NOT read — the control: nothing moves.
    out["X7"] = row {
        let withB = result([segment("A"), segment("C")], [leftB(position: 1, voice: false)])
        let withoutB = result([segment("A"), segment("C")], [])
        let d1 = ProjectDocument()
        let d2 = ProjectDocument()
        let p1 = try RecordingLanding.placement(withB, in: d1, place: true)
        let p2 = try RecordingLanding.placement(withoutB, in: d2, place: true)
        return [
            "with": p1.ops.map { $0.json }, "without": p2.ops.map { $0.json },
            "withNames": p1.ops.map { $0.name }, "withoutNames": p2.ops.map { $0.name },
            "withLists": lists(p1), "withoutLists": lists(p2),
        ]
    }
    // X8 (issue batch B61, #213): a new project whose first picture the core
    // refuses (5 000 ticks, under one 60 fps frame — 4b·M's precedent), with
    // a voice of its own and a left-out B's voice — both media only, noted.
    try? Data("not a movie".utf8).write(to: tmp.appendingPathComponent("A0.mov"))
    try? Data("not audio".utf8).write(to: URL(fileURLWithPath: mic("A0", 0).path))
    let shortA0 = MediaDescriptor(
        path: tmp.appendingPathComponent("A0.mov").path, kind: .video,
        duration: 5_000, width: 1728, height: 1118, fps: Fps(num: 24981, den: 1000),
        hasVideo: true, hasAudio: false)
    out["micA"] = mic("A0", 5 * second).path
    out["pathA0"] = shortA0.path
    out["X8"] = row {
        let r8 = result(
            [RecordingSegment(
                descriptor: shortA0, micDescriptor: mic("A0", 5 * second), micOffset: 0,
                startedAt: Date())],
            [leftB(position: 1)])
        let (d, notes) = try ProjectDocument.untitled(around: r8)
        let s = d.project.snapshot
        let facts: [String: Any] = [
            "notes": notes, "clips": s.clips.map(describeClip),
            "media": s.media.map { ["id": Int($0.id), "path": $0.path] as [String: Any] },
        ]
        d.close()
        return facts
    }
    out["documentsAfterClose"] = NSDocumentController.shared.documents.count
    return out
}

// ---- mode "chrome": the menu, the welcome buttons, the panel, the guard ---
func chrome(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
        RecorderPanelController.includeFrameJobWindowsKey: false,
    ], forName: UserDefaults.argumentDomain)
    // The one call that builds the menu: `buildMainMenu()` is private.
    let delegate = AppDelegate()
    delegate.applicationWillFinishLaunching(
        Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

    // The File menu.
    let fileItems = NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu?.items ?? []
    let newProjectIndex = fileItems.firstIndex { $0.title == "New Project" } ?? -1
    var next: [String: Any] = [:]
    if newProjectIndex >= 0, fileItems.indices.contains(newProjectIndex + 1) {
        let item = fileItems[newProjectIndex + 1]
        next = ["title": item.title, "key": item.keyEquivalent,
                "modifiers": item.keyEquivalentModifierMask.rawValue,
                "action": item.action.map { NSStringFromSelector($0) } ?? "",
                "hasTarget": item.target != nil, "separator": item.isSeparatorItem]
    }
    out["file"] = ["newProjectIndex": newProjectIndex, "next": next,
                   "count": fileItems.filter { $0.title == "New Recording…" }.count]

    // validateMenuItem while idle.
    let item = NSMenuItem(title: "New Recording…", action: #selector(AppDelegate.newRecording(_:)),
                          keyEquivalent: "")
    let enabled = delegate.validateMenuItem(item)
    out["validate"] = ["enabled": enabled, "title": item.title,
                       "recorderIdle": !ScreenRecorder.shared.isRecording]

    // The welcome window's buttons.
    let welcome = WelcomeWindowController.shared
    let buttons = welcome.window?.contentView.map { descendants(StickerButton.self, in: $0) } ?? []
    out["welcome"] = [
        "count": buttons.count, "titles": buttons.map { $0.title },
        "actions": buttons.map { $0.action.map { NSStringFromSelector($0) } ?? "" },
        "targets": buttons.map { $0.target != nil },
    ]

    // The panel.
    let panel = RecorderPanelController.shared
    let window = panel.window as? NSPanel
    let choice = panel.currentChoice()
    var info: [String: Any] = [:]
    info["isPanel"] = window != nil
    info["nonactivating"] = window?.styleMask.contains(.nonactivatingPanel) ?? false
    info["titled"] = window?.styleMask.contains(.titled) ?? false
    info["closable"] = window?.styleMask.contains(.closable) ?? false
    info["floating"] = (window?.level ?? .normal) == .floating
    info["hidesOnDeactivate"] = window?.hidesOnDeactivate ?? true
    info["excluded"] = window?.isExcludedFromWindowsMenu ?? false
    info["released"] = window?.isReleasedWhenClosed ?? true
    info["delegateNil"] = window?.delegate == nil
    info["title"] = window?.title ?? ""
    info["visible"] = window?.isVisible ?? true
    info["destinationFirst"] = panel.destinationPopup.item(at: 0)?.title ?? ""
    info["destinationCount"] = panel.destinationPopup.numberOfItems
    info["microphoneFirst"] = panel.microphonePopup.item(at: 0)?.title ?? ""
    info["sourceLast"] = panel.sourcePopup.lastItem?.title ?? ""
    info["sourceLastTag"] = panel.sourcePopup.lastItem?.tag ?? -1
    info["sourceCount"] = panel.sourcePopup.numberOfItems
    info["sourceSeparatorIndex"] =
        panel.sourcePopup.itemArray.firstIndex { $0.isSeparatorItem } ?? -1
    info["screens"] = NSScreen.screens.count
    info["recordTitle"] = panel.recordButton.title
    info["recordFillIsClip"] = panel.recordButton.fill == DS.meterClip
    info["recordTargetIsPanel"] = panel.recordButton.target === panel
    info["rate"] = choice.rate
    info["resolution"] = choice.resolution.rawValue
    info["systemAudio"] = choice.systemAudio
    info["showClicks"] = choice.showClicks
    info["microphoneOff"] = choice.microphone == nil
    info["newProject"] = choice.destination == .newProject
    info["mainDisplay"] = choice.source == .display(CGMainDisplayID())
    info["includeFrameJobWindows"] = choice.includeFrameJobWindows
    info["includeFrameJobTitle"] = panel.includeFrameJobCheckbox.title
    info["idle"] = panel.phase == .idle
    info["controlsEnabled"] = panel.sourcePopup.isEnabled && panel.destinationPopup.isEnabled
    info["countdownHidden"] = panel.countdownLabel.isHidden
    info["noteHidden"] = panel.noteLabel.isHidden
    info["meterWidth"] = panel.meterView.fittingSize.width
    info["contentWidth"] = window?.contentView?.frame.width ?? 0
    info["contentHeight"] = window?.contentView?.frame.height ?? 0
    info["cardHeight"] = panel.card.fittingSize.height
    info["sizeNote"] = panel.sizeNote.stringValue
    info["status"] = panel.statusLabel.stringValue
    out["panel"] = info
    // A note appears, the window refits; cleared, it shrinks back.
    let before = window?.frame ?? .zero
    panel.setNote("A sentence long enough to wrap onto a second line of the note label, so the card grows.")
    let grown = window?.frame ?? .zero
    let noteShownWhileSet = !panel.noteLabel.isHidden
    panel.setNote("")
    let back = window?.frame ?? .zero
    out["refit"] = ["grew": grown.height > before.height,
                    "topKept": abs(grown.maxY - before.maxY) < 0.5,
                    "back": abs(back.height - before.height) < 0.5,
                    "noteShown": noteShownWhileSet, "noteHiddenAfter": panel.noteLabel.isHidden]
    // The nine keys the harness pins are the panel's own, by name.
    out["keys"] = [RecorderPanelController.displayKey, RecorderPanelController.microphoneKey,
                   RecorderPanelController.systemAudioKey, RecorderPanelController.showClicksKey,
                   RecorderPanelController.rateKey, RecorderPanelController.sizeKey,
                   RecorderPanelController.includeFrameJobWindowsKey,
                   RecorderPanelController.cameraKey, RecorderPanelController.cameraFormatKey]

    // AccentButton stores its fill.
    let plain = AccentButton(title: "x", symbol: nil, fallback: "", tooltip: "", action: nil)
    let red = AccentButton(title: "x", symbol: nil, fallback: "", tooltip: "", action: nil, fill: .red)
    out["accent"] = ["defaultIsAccent": plain.fill == DS.accent, "storedRed": red.fill == NSColor.red]

    // The status item's label.
    out["statusLabel"] = ["0": RecorderStatusItem.label(for: 0),
                          "61": RecorderStatusItem.label(for: 61.9),
                          "3661": RecorderStatusItem.label(for: 3661),
                          "neg": RecorderStatusItem.label(for: -3)]

    // LevelMeterView(meter:) observes THAT meter and not .shared.
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                        styleMask: .borderless, backing: .buffered, defer: false)
    let fresh = LevelMeter()
    let own = LevelMeterView(meter: fresh)
    let dflt = LevelMeterView()
    for (index, view) in [own, dflt].enumerated() {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = NSRect(x: 10, y: 10 + CGFloat(index) * 20, width: 120, height: 12)
        host.contentView?.addSubview(view)
    }
    let restOwn = renderBase64(own), restDflt = renderBase64(dflt)
    let loud = LevelMeterReading(peakLeft: 0.9, peakRight: 0.9, rmsLeft: 0.5, rmsRight: 0.5)
    fresh.publish(loud, from: ObjectIdentifier(fresh))
    _ = spin(0.25) { false }
    let liveOwn = renderBase64(own), liveDflt = renderBase64(dflt)
    LevelMeter.shared.publish(loud, from: ObjectIdentifier(host))
    _ = spin(0.25) { false }
    let sharedDflt = renderBase64(dflt)
    out["meter"] = ["restEqual": restOwn == restDflt, "ownLit": liveOwn != restOwn,
                    "defaultStill": liveDflt == restDflt, "defaultLitByShared": sharedDflt != restDflt]
    fresh.publish(.silent, from: ObjectIdentifier(fresh))
    LevelMeter.shared.publish(.silent, from: ObjectIdentifier(host))

    // The two rows lane C could not write: the recorder's state written BY
    // THE PROBE — `state` is internal so `+Finishing` can write it — and reset
    // before the answer. Nothing here starts a stream: the retitle and the
    // quit guard both read `isRecording`, which is `state != .idle`.
    let recorder = ScreenRecorder.shared
    var quit: [String: Any] = [
        "stateBefore": "\(recorder.state)", "queueIdle": ExportQueueController.shared.isIdle,
        "panelVisibleBefore": window?.isVisible ?? true,
    ]
    recorder.state = .recording
    quit["isRecordingWhileSet"] = recorder.isRecording
    let stopItem = NSMenuItem(
        title: "New Recording…", action: #selector(AppDelegate.newRecording(_:)), keyEquivalent: "")
    quit["recordingEnabled"] = delegate.validateMenuItem(stopItem)
    quit["recordingTitle"] = stopItem.title
    quit["recordingReply"] = spellReply(delegate.applicationShouldTerminate(app))
    quit["panelVisibleAfterCancel"] = window?.isVisible ?? false
    recorder.state = .idle
    let idleItem = NSMenuItem(
        title: "Stop Recording", action: #selector(AppDelegate.newRecording(_:)), keyEquivalent: "")
    quit["idleEnabled"] = delegate.validateMenuItem(idleItem)
    quit["idleTitle"] = idleItem.title
    quit["idleReply"] = spellReply(delegate.applicationShouldTerminate(app))
    quit["stateAfter"] = "\(recorder.state)"
    out["quit"] = quit

    // ---- the R1 review's chrome fixes, driven where a probe can reach them.
    // fix 5 — fitWindowToContent constrains the grown card to its screen.
    if let screen = NSScreen.main {
        // Placed 10 pt above the screen's PHYSICAL bottom, so the 118 pt the
        // countdown and its note add would carry the bottom off the screen —
        // `constrainFrameRect` clamps to the screen frame, not the Dock's
        // visibleFrame, which one earlier measurement (bottom above the Dock)
        // read as "does nothing".
        // Placed far BELOW every screen (a multi-display desktop makes
        // `NSScreen.main` a secondary panel here, so a bottom-of-Dock offset
        // reads as "does nothing"): a window that overlaps no screen resolves
        // `window.screen` to nil, so `fitWindowToContent` constrains to this
        // same `NSScreen.main`, and the constrain must lift the whole frame
        // back onto it.
        let sf = screen.frame
        let placedY = sf.minY - 3000
        panel.phase = .idle
        var f = window?.frame ?? .zero
        f.origin = NSPoint(x: sf.minX + 40, y: placedY)
        window?.setFrame(f, display: false)
        let idleHeight = window?.frame.height ?? 0
        panel.phase = .countdown(3)
        panel.setNote(
            "A sentence long enough to wrap onto a second line so the card grows well past "
                + "where a panel parked at the bottom of the screen would leave room for it.")
        let grown = window?.frame ?? .zero
        out["constrain"] = [
            "screenMinY": Double(sf.minY), "visibleMinY": Double(screen.visibleFrame.minY),
            "idleHeight": Double(idleHeight),
            "minY": Double(grown.minY), "height": Double(grown.height),
            "unconstrainedMinY": Double(placedY + idleHeight - grown.height),
        ]
        panel.setNote("")
        panel.phase = .idle
    }

    // fix 7 — show() beeps and shows nothing while a picked recording hid the panel.
    window?.orderOut(nil)
    panel.hiddenForRecording = true
    panel.show()
    out["showHidden"] = ["visibleAfterShow": window?.isVisible ?? true]
    panel.hiddenForRecording = false
    panel.cancelCountdown()
    window?.orderOut(nil)

    // fix 8 — Record over the "Window…" row with no picked filter refuses first.
    _ = panel.sourcePopup.selectItem(withTag: RecorderPanelController.windowTag)
    panel.pickedFilter = nil
    panel.setNote("")
    panel.record(nil)
    out["windowRow"] = [
        "phaseIdle": panel.phase == .idle, "note": panel.noteLabel.stringValue,
        "sentence": RecorderPanelController.chooseWindowSentence,
    ]
    panel.cancelCountdown()
    panel.phase = .idle
    panel.selectDisplay(CGMainDisplayID())
    panel.setNote("")

    // fix 4 — a rebuild while recording leaves the Record Into rows untouched.
    panel.destinationPopup.removeAllItems()
    panel.destinationPopup.menu?.addItem(
        NSMenuItem(title: "New Project", action: nil, keyEquivalent: ""))
    let seeded = NSMenuItem(title: "Seeded Doc", action: nil, keyEquivalent: "")
    seeded.representedObject = NSNumber(value: 4242)
    panel.destinationPopup.menu?.addItem(seeded)
    panel.destinationPopup.select(seeded)
    let seededBefore = (panel.destinationPopup.selectedItem?.representedObject as? NSNumber)?.intValue
    panel.phase = .recording
    panel.rebuildDestinations()
    let seededAfter = (panel.destinationPopup.selectedItem?.representedObject as? NSNumber)?.intValue
    out["syncRec"] = [
        "before": seededBefore ?? -1, "after": seededAfter ?? -1,
        "count": panel.destinationPopup.numberOfItems,
    ]
    panel.phase = .idle
    panel.rebuildDestinations()

    // fix 2 — the .starting attempt is bounded, and a stale ceiling is ignored.
    panel.phase = .starting
    panel.startGeneration = 7
    panel.launched = false
    panel.armTimedOut(generation: 6)
    let armStale = panel.phase == .starting
    panel.armTimedOut(generation: 7)
    let armFired = panel.phase == .idle
    let armNote = panel.noteLabel.stringValue
    panel.phase = .starting
    panel.startGeneration = 8
    panel.launched = true
    panel.armTimedOut(generation: 8)
    let armLaunched = panel.phase == .starting
    panel.launched = false
    panel.phase = .idle
    panel.setNote("")
    out["arm"] = [
        "staleStayed": armStale, "firedIdle": armFired, "note": armNote,
        "launchedIgnored": armLaunched,
    ]

    // fix 10 — the landing note, a pure function over the three facts it carries.
    out["landingNote"] = [
        "userStoppedNewProj": RecorderPanelController.landingNote(
            stoppedBy: .userStopped, chosen: .document(recipeKey: 1), landedAsNewProject: true,
            micProblem: nil),
        "userStoppedSameDoc": RecorderPanelController.landingNote(
            stoppedBy: .userStopped, chosen: .document(recipeKey: 1), landedAsNewProject: false,
            micProblem: nil),
        "stoppedNewProjChosenNew": RecorderPanelController.landingNote(
            stoppedBy: .stopped, chosen: .newProject, landedAsNewProject: true, micProblem: nil),
        "micProblem": RecorderPanelController.landingNote(
            stoppedBy: .stopped, chosen: .document(recipeKey: 1), landedAsNewProject: false,
            micProblem: "The microphone stopped."),
        "plain": RecorderPanelController.landingNote(
            stoppedBy: .stopped, chosen: .newProject, landedAsNewProject: false, micProblem: nil),
        "closedSentence": RecorderPanelController.destinationClosedSentence,
        "menuBarSentence":
            "Stopped from the system's screen-recording indicator; the recording was added.",
    ]

    // fix 12 — New Recording… routes a TOOL's recording to the recorder, not the panel.
    window?.orderOut(nil)
    ScreenRecorder.shared.state = .recording
    let routePhaseIdle = panel.phase == .idle
    delegate.newRecording(nil)
    out["route"] = [
        "panelPhaseIdle": routePhaseIdle, "panelShown": window?.isVisible ?? true,
    ]
    ScreenRecorder.shared.state = .idle
    window?.orderOut(nil)

    return out
}

// ---- mode "chrome-pause": the status item's vocabulary, the .paused phase,
// the panel's two entries, the reveal, and the route (road map 3, R2c) ----
func chromePause(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
        RecorderPanelController.includeFrameJobWindowsKey: false,
    ], forName: UserDefaults.argumentDomain)
    let delegate = AppDelegate()
    delegate.applicationWillFinishLaunching(
        Notification(name: NSApplication.willFinishLaunchingNotification, object: app))
    let work = URL(fileURLWithPath: request["work"] as? String ?? NSTemporaryDirectory(),
                   isDirectory: true)

    // The status item's vocabulary, pure.
    out["menuTitles"] = [
        "recording": RecorderStatusItem.menuTitles(paused: false),
        "paused": RecorderStatusItem.menuTitles(paused: true),
    ]
    out["tooltip"] = [
        "recording": RecorderStatusItem.tooltip(paused: false),
        "paused": RecorderStatusItem.tooltip(paused: true),
    ]
    out["pauseGlyph"] = RecorderStatusItem.pauseGlyph
    func describeTitle(_ title: NSAttributedString) -> [String: Any] {
        let markColor = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let markFont = title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let last = title.length - 1
        let timeColor = title.attribute(.foregroundColor, at: last, effectiveRange: nil)
        let timeFont = title.attribute(.font, at: last, effectiveRange: nil) as? NSFont
        let size = NSFont.systemFontSize
        return [
            "string": title.string, "markHasColor": markColor != nil,
            "markIsClip": markColor == DS.meterClip,
            "markFontIsSystem": markFont == NSFont.systemFont(ofSize: size),
            "timeHasColor": timeColor != nil,
            "timeFontIsMonoDigits":
                timeFont == NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
        ]
    }
    out["titleRecording"] = describeTitle(RecorderStatusItem.title(elapsed: 61.9, paused: false))
    out["titlePaused"] = describeTitle(RecorderStatusItem.title(elapsed: 61.9, paused: true))
    out["titlePausedHour"] = describeTitle(RecorderStatusItem.title(elapsed: 3661, paused: true))

    // The panel's .paused phase, drawn.
    let panel = RecorderPanelController.shared
    let window = panel.window as? NSPanel
    window?.orderOut(nil)
    panel.setNote("")
    panel.phase = .paused
    out["pausedPhase"] = [
        "buttonTitle": panel.recordButton.title, "enabled": panel.recordButton.isEnabled,
        "status": panel.statusLabel.stringValue,
        "statusFaint": panel.statusLabel.textColor == DS.textFaint,
        "controlsDisabled": !panel.sourcePopup.isEnabled && !panel.destinationPopup.isEnabled
            && !panel.microphonePopup.isEnabled,
        "countdownHidden": panel.countdownLabel.isHidden,
    ]
    panel.phase = .recording
    out["recordingPhase"] = [
        "buttonTitle": panel.recordButton.title, "status": panel.statusLabel.stringValue,
        "statusClip": panel.statusLabel.textColor == DS.meterClip,
    ]
    panel.phase = .idle
    out["idlePhase"] = ["status": panel.statusLabel.stringValue,
                        "statusFaint": panel.statusLabel.textColor == DS.textFaint]

    // The two entries against a recorder that refuses (idle): each answered
    // as +Pause.swift says — a pause beeps and stays, a resume writes the
    // note after what is there and stays paused.
    panel.pauseRecording()
    out["pauseFromIdle"] = "\(panel.phase)"
    panel.phase = .recording
    panel.pauseRecording()
    out["pauseRefused"] = ["phase": "\(panel.phase)", "recorder": "\(ScreenRecorder.shared.state)",
                           "note": panel.noteLabel.stringValue]
    panel.phase = .paused
    panel.setNote("")
    panel.resumeProblem = nil
    panel.resumeRecording()
    out["resumeRefused"] = ["phase": "\(panel.phase)", "note": panel.noteLabel.stringValue,
                            "noteShown": !panel.noteLabel.isHidden,
                            "resumeProblem": panel.resumeProblem as Any]
    // A second refused resume REPLACES the sentence (state, not text).
    panel.resumeRecording()
    out["resumeRefusedTwice"] = panel.noteLabel.stringValue
    // With a live microphone problem the note is composed from the two
    // pieces of STATE, the microphone's first, and a tick's
    // syncMicrophoneNote leaves it alone rather than wiping the resume's.
    ScreenRecorder.shared.microphoneProblem = "The microphone recording failed: boom."
    panel.syncMicrophoneNote()
    out["resumeRefusedWithMic"] = panel.noteLabel.stringValue
    panel.syncMicrophoneNote()
    out["resumeRefusedWithMicAgain"] = panel.noteLabel.stringValue
    ScreenRecorder.shared.microphoneProblem = nil
    panel.resumeProblem = nil
    panel.setNote("")
    panel.phase = .recording
    panel.resumeRecording()
    out["resumeFromRecording"] = "\(panel.phase)"
    panel.phase = .idle
    out["liveNote"] = [
        "none": RecorderPanelController.liveNote(microphoneProblem: nil, resumeProblem: nil),
        "mic": RecorderPanelController.liveNote(microphoneProblem: "boom.", resumeProblem: nil),
        "resume": RecorderPanelController.liveNote(
            microphoneProblem: nil, resumeProblem: "The recording is not paused."),
        "both": RecorderPanelController.liveNote(
            microphoneProblem: "boom.", resumeProblem: "The recording is not paused."),
    ]
    out["landingNoteR2"] = [
        "userStopped": RecorderPanelController.landingNote(
            stoppedBy: .userStopped, chosen: .newProject, landedAsNewProject: true, micProblem: nil),
        "resume": RecorderPanelController.landingNote(
            stoppedBy: .stopped, chosen: .newProject, landedAsNewProject: true, micProblem: nil,
            resumeProblem: "The recording could not be resumed: x."),
        "all": RecorderPanelController.landingNote(
            stoppedBy: .userStopped, chosen: .document(recipeKey: 1), landedAsNewProject: true,
            micProblem: "Mic.", resumeProblem: "Resume.", notes: ["Note one.", "Note two."]),
        "notesOnly": RecorderPanelController.landingNote(
            stoppedBy: .stopped, chosen: .newProject, landedAsNewProject: true, micProblem: nil,
            notes: ["Note."]),
    ]

    // A REAL pause and resume through the panel, over a faked session on
    // ScreenRecorder.shared (a probe-only manipulation, torn down below):
    // the phase follows the recorder's own transitions.
    let shared = ScreenRecorder.shared
    let movie = work.appendingPathComponent("panel.png")
    _ = writePNG(movie)
    var choice = RecordingChoice()
    choice.folder = work
    let size = CGSize(width: 16, height: 16)
    let configs = RecordingConfiguration.make(
        choice, displayPointSize: size, scale: 1, outputURL: movie)
    let stream = SCStream(filter: SCContentFilter(), configuration: configs.stream, delegate: shared)
    let output = SCRecordingOutput(configuration: configs.output, delegate: shared)
    var attached = "ok"
    do { try stream.addRecordingOutput(output) } catch { attached = "\(error)" }
    var first = ScreenRecorder.Segment(movieURL: movie, micURL: nil, output: output, addedAt: Date())
    first.screenStartedAt = Date(timeIntervalSinceNow: -2)
    shared.session = ScreenRecorder.Session(
        choice: choice, mayAsk: true, displayPointSize: size, scale: 1, stream: stream, micSession: nil,
        micOutput: nil, calledAt: Date(), onFinish: { _ in }, segments: [first])
    shared.state = .recording
    panel.phase = .recording
    let statusRecording = panel.statusLabel.stringValue
    panel.pauseRecording()
    let statusPaused = panel.statusLabel.stringValue
    _ = spin(0.3) { false }
    panel.refreshStatusLabel()
    out["panelPause"] = [
        "attached": attached, "phase": "\(panel.phase)", "recorder": "\(shared.state)",
        "statusRecording": statusRecording, "statusPaused": statusPaused,
        "statusHeld": panel.statusLabel.stringValue,
        "statusFaint": panel.statusLabel.textColor == DS.textFaint,
        "buttonTitle": panel.recordButton.title,
    ]
    panel.resumeProblem = "a stale refusal"
    panel.resumeRecording()
    out["panelResume"] = ["phase": "\(panel.phase)", "recorder": "\(shared.state)",
                          "segments": shared.session?.segments.count ?? -1,
                          "resumeProblemCleared": panel.resumeProblem == nil]
    panel.pauseRecording()
    panel.stopRecording()
    out["panelStopWhilePaused"] = ["phase": "\(panel.phase)", "recorder": "\(shared.state)",
                                  "stopAsked": shared.session?.stopAsked ?? false]
    shared.timer?.invalidate()
    shared.timer = nil
    shared.session = nil
    shared.state = .idle
    shared.stopCompletions = []
    shared.pendingStop = false
    panel.phase = .idle
    out["tornDown"] = "\(shared.state)"

    // revealIfNoted, both ways, and once more with the panel never on screen.
    window?.orderOut(nil)
    panel.showWhenLanded = true
    panel.setNote("")
    panel.revealIfNoted()
    out["revealEmpty"] = ["visible": window?.isVisible ?? true, "cleared": !panel.showWhenLanded]
    panel.showWhenLanded = true
    panel.setNote("Stopped from the menu bar; the recording was added.")
    panel.revealIfNoted()
    out["revealNoted"] = ["visible": window?.isVisible ?? false, "cleared": !panel.showWhenLanded]
    window?.orderOut(nil)
    panel.showWhenLanded = false
    panel.revealIfNoted()
    out["revealNotOnScreenBefore"] = ["visible": window?.isVisible ?? true]
    panel.setNote("")

    // revealControls — the quit guard's call: the panel when it is not
    // hidden for a recording; the status item's menu when it is, and a beep
    // with no item to open.
    window?.orderOut(nil)
    panel.hiddenForRecording = false
    panel.revealControls()
    out["revealControlsShown"] = window?.isVisible ?? false
    window?.orderOut(nil)
    panel.hiddenForRecording = true
    panel.revealControls()
    out["revealControlsHidden"] = ["visible": window?.isVisible ?? true,
                                  "itemUp": panel.statusItem != nil]
    panel.hiddenForRecording = false

    // New Recording… while the panel is paused stops through the panel.
    window?.orderOut(nil)
    panel.phase = .paused
    delegate.newRecording(nil)
    out["routePaused"] = ["phase": "\(panel.phase)", "panelShown": window?.isVisible ?? true]
    panel.phase = .idle

    // The retitle and the quit guard while PAUSED (probe-written, reset).
    ScreenRecorder.shared.state = .paused
    let item = NSMenuItem(
        title: "New Recording…", action: #selector(AppDelegate.newRecording(_:)), keyEquivalent: "")
    out["pausedValidate"] = [
        "enabled": delegate.validateMenuItem(item), "title": item.title,
        "isRecording": ScreenRecorder.shared.isRecording,
        "isPaused": ScreenRecorder.shared.isPaused,
        "reply": spellReply(delegate.applicationShouldTerminate(app)),
    ]
    ScreenRecorder.shared.state = .idle
    window?.orderOut(nil)
    out["stateAfter"] = "\(ScreenRecorder.shared.state)"
    return out
}

// ---- mode "file-pause": File ▸ Pause/Resume Recording, the item's width (#98) --

/// A faked session on `ScreenRecorder.shared`, chrome-pause's shape: one open
/// segment whose output is ADDED to a never-started, grant-less stream, so
/// the recorder's real `pause()` / `resume()` run. Torn down by the next.
func fakeSharedRecording(_ work: URL, _ name: String) -> String {
    let shared = ScreenRecorder.shared
    let movie = work.appendingPathComponent("\(name).png")
    _ = writePNG(movie)
    var choice = RecordingChoice()
    choice.folder = work
    let size = CGSize(width: 16, height: 16)
    let configs = RecordingConfiguration.make(
        choice, displayPointSize: size, scale: 1, outputURL: movie)
    let stream = SCStream(filter: SCContentFilter(), configuration: configs.stream, delegate: shared)
    let output = SCRecordingOutput(configuration: configs.output, delegate: shared)
    var attached = "ok"
    do { try stream.addRecordingOutput(output) } catch { attached = "\(error)" }
    var first = ScreenRecorder.Segment(movieURL: movie, micURL: nil, output: output, addedAt: Date())
    first.screenStartedAt = Date(timeIntervalSinceNow: -2)
    shared.session = ScreenRecorder.Session(
        choice: choice, mayAsk: true, displayPointSize: size, scale: 1, stream: stream, micSession: nil,
        micOutput: nil, calledAt: Date(), onFinish: { _ in }, segments: [first])
    shared.state = .recording
    return attached
}

/// Back to idle with no session — a probe-only manipulation, chrome-pause's.
func tearDownShared() {
    let shared = ScreenRecorder.shared
    shared.timer?.invalidate()
    shared.timer = nil
    shared.session = nil
    shared.state = .idle
    shared.stopCompletions = []
    shared.pendingStop = false
}

func filePause(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
        RecorderPanelController.includeFrameJobWindowsKey: false,
    ], forName: UserDefaults.argumentDomain)
    let delegate = AppDelegate()
    delegate.applicationWillFinishLaunching(
        Notification(name: NSApplication.willFinishLaunchingNotification, object: app))
    let work = URL(
        fileURLWithPath: request["work"] as? String ?? NSTemporaryDirectory(), isDirectory: true)
    let pauseAction = #selector(AppDelegate.pauseOrResumeRecording(_:))

    // F1: the item, under New Recording…, and how many the bar holds.
    func leaves(_ menu: NSMenu?) -> [NSMenuItem] {
        (menu?.items ?? []).flatMap { [$0] + leaves($0.submenu) }
    }
    let fileItems = NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu?.items ?? []
    let newIndex = fileItems.firstIndex { $0.title == "New Recording…" } ?? -1
    var next: [String: Any] = [:]
    var fileItem: NSMenuItem?
    if newIndex >= 0, fileItems.indices.contains(newIndex + 1) {
        let item = fileItems[newIndex + 1]
        fileItem = item
        next = ["title": item.title, "key": item.keyEquivalent,
                "action": item.action.map { NSStringFromSelector($0) } ?? "",
                "hasTarget": item.target != nil, "separator": item.isSeparatorItem]
    }
    out["file"] = ["newRecordingIndex": newIndex, "next": next,
                   "inBar": leaves(NSApp.mainMenu).filter { $0.action == pauseAction }.count]

    // F2: the validator over each recorder state the probe sets.
    let item = fileItem ?? NSMenuItem(title: "Pause Recording", action: pauseAction, keyEquivalent: "")
    var validate: [[String: Any]] = []
    let states: [ScreenRecorder.State] = [.idle, .arming, .finishing, .recording, .paused]
    for state in states {
        ScreenRecorder.shared.state = state
        let enabled = delegate.validateMenuItem(item)
        validate.append(["state": "\(state)", "enabled": enabled, "title": item.title])
    }
    ScreenRecorder.shared.state = .idle
    out["validate"] = validate
    out["menuTitles"] = [
        "recording": RecorderStatusItem.menuTitles(paused: false)[0],
        "paused": RecorderStatusItem.menuTitles(paused: true)[0],
    ]

    // F6 (issue batch B27, #181): the recorder's pause notification, counted
    // from before F3 — each post's `isPaused`, read INSIDE the block.
    var posts: [Bool] = []
    let postObserver = NotificationCenter.default.addObserver(
        forName: ScreenRecorder.pauseDidChangeNotification, object: ScreenRecorder.shared,
        queue: nil
    ) { _ in posts.append(ScreenRecorder.shared.isPaused) }
    // F8 (issue batch B42, #193): the recorder's finishing notification,
    // counted from before F3 — the state read INSIDE each block.
    var finishPosts: [String] = []
    let finishObserver = NotificationCenter.default.addObserver(
        forName: ScreenRecorder.finishingDidBeginNotification, object: ScreenRecorder.shared,
        queue: nil
    ) { _ in finishPosts.append("\(ScreenRecorder.shared.state)") }

    // F3: the panel's own recording, through the panel.
    let panel = RecorderPanelController.shared
    panel.window?.orderOut(nil)
    panel.setNote("")
    let attached3 = fakeSharedRecording(work, "f3")
    panel.phase = .recording
    delegate.pauseOrResumeRecording(nil)
    let f3Paused = ["panel": "\(panel.phase)", "recorder": "\(ScreenRecorder.shared.state)"]
    delegate.pauseOrResumeRecording(nil)
    out["f3"] = [
        "attached": attached3, "paused": f3Paused, "panel": "\(panel.phase)",
        "recorder": "\(ScreenRecorder.shared.state)",
        "segments": ScreenRecorder.shared.session?.segments.count ?? -1,
    ]
    tearDownShared()
    panel.resumeProblem = nil
    panel.phase = .idle

    // F4: a recording the panel does not own (a tool's), through the recorder.
    panel.window?.orderOut(nil)
    let attached4 = fakeSharedRecording(work, "f4")
    let f3Posts = posts
    posts = []
    delegate.pauseOrResumeRecording(nil)
    // Counted BEFORE any spin: the post is synchronous inside pause().
    let f4PausePosts = posts
    posts = []
    let f4Paused: [String: Any] = [
        "panel": "\(panel.phase)", "recorder": "\(ScreenRecorder.shared.state)",
        "visible": panel.window?.isVisible ?? false,
    ]
    delegate.pauseOrResumeRecording(nil)
    let f4ResumePosts = posts
    posts = []
    out["f4"] = [
        "attached": attached4, "paused": f4Paused, "panel": "\(panel.phase)",
        "recorder": "\(ScreenRecorder.shared.state)",
        "segments": ScreenRecorder.shared.session?.segments.count ?? -1,
        "visible": panel.window?.isVisible ?? false,
    ]
    tearDownShared()

    // F5: nothing recording — nothing changes.
    posts = []
    delegate.pauseOrResumeRecording(nil)
    out["f5"] = [
        "panel": "\(panel.phase)", "recorder": "\(ScreenRecorder.shared.state)",
        "session": ScreenRecorder.shared.session != nil,
        "visible": panel.window?.isVisible ?? false,
    ]
    out["f6"] = [
        "f3": f3Posts, "f4Pause": f4PausePosts, "f4Resume": f4ResumePosts, "f5": posts.count,
    ]
    NotificationCenter.default.removeObserver(postObserver)

    // F8 (b, c): File ▸ Stop Recording over a tool's PAUSED recording — the
    // default arm's `ScreenRecorder.shared.stop()` posts the finishing
    // notification once, synchronously, with the recorder `.finishing`.
    let f8Before = finishPosts
    finishPosts = []
    panel.window?.orderOut(nil)
    let attached8 = fakeSharedRecording(work, "f8")
    delegate.pauseOrResumeRecording(nil)
    let f8Paused = "\(ScreenRecorder.shared.state)"
    delegate.newRecording(nil)
    // Counted BEFORE any spin: the post is synchronous inside beginFinishing.
    let f8StopPosts = finishPosts
    out["f8"] = [
        "before": f8Before, "attached": attached8, "paused": f8Paused, "stopPosts": f8StopPosts,
        "panel": "\(panel.phase)", "visible": panel.window?.isVisible ?? false,
        "recorder": "\(ScreenRecorder.shared.state)",
    ]
    tearDownShared()
    NotificationCenter.default.removeObserver(finishObserver)

    // F10 (#193): a new countdown clears a stale resumeProblem.
    panel.phase = .idle
    panel.resumeProblem = "F10 stale"
    panel.beginCountdown()
    let f10Problem: Any = panel.resumeProblem ?? NSNull()
    let f10Phase = "\(panel.phase)"
    panel.cancelCountdown()
    panel.disarmTick()
    out["f10"] = [
        "problem": f10Problem, "phase": f10Phase, "after": "\(panel.phase)",
        "microphone": panel.currentChoice().microphone ?? NSNull(),
    ]
    panel.window?.orderOut(nil)

    // W0–W2: the titles against the one length.
    func width(_ elapsed: TimeInterval, _ paused: Bool) -> Double {
        Double(RecorderStatusItem.title(elapsed: elapsed, paused: paused).size().width)
    }
    out["w0"] = ["recording": width(0, false), "paused": width(0, true)]
    let elapsed = request["elapsed"] as? [Double] ?? []
    out["widths"] = elapsed.flatMap { e in
        [false, true].map { paused -> [String: Any] in
            ["elapsed": e, "paused": paused, "width": width(e, paused),
             "label": RecorderStatusItem.label(for: e)]
        }
    }
    out["itemLength"] = Double(RecorderStatusItem.itemLength)
    out["titleInset"] = Double(RecorderStatusItem.titleInset)
    out["widestElapsed"] = RecorderStatusItem.widestElapsed
    out["widestLabel"] = RecorderStatusItem.label(for: RecorderStatusItem.widestElapsed)
    out["widestWidths"] = [
        width(RecorderStatusItem.widestElapsed, false), width(RecorderStatusItem.widestElapsed, true),
    ]
    out["stateAfter"] = "\(ScreenRecorder.shared.state)"
    return out
}

// ---- mode "welcome": the button row's geometry, from the live layout ------
func welcome(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    // The harness registers the vendored fonts beside its binary; without
    // them `DS.sans` falls back to the system face and every width is wrong.
    if let fonts = request["fonts"] as? String,
        let names = try? FileManager.default.contentsOfDirectory(atPath: fonts)
    {
        var registered = 0
        for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
            CTFontManagerRegisterFontsForURL(
                URL(fileURLWithPath: fonts).appendingPathComponent(name) as CFURL, .process, nil)
            registered += 1
        }
        out["fontsRegistered"] = registered
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    NSApp.appearance = NSAppearance(named: .aqua)
    // `show()`, as the harness's welcome mode does — it rebuilds the recent
    // list, which is what decides the stack's height and so the row's y.
    let controller = WelcomeWindowController.shared
    controller.show()
    for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard let root = controller.window?.contentView else {
        return ["error": "the welcome window has no content view"]
    }
    root.layoutSubtreeIfNeeded()
    let buttons = descendants(StickerButton.self, in: root)
    out["buttons"] = buttons.map { button -> [String: Any] in
        let frame = root.convert(button.bounds, from: button)
        let top = root.isFlipped ? frame.minY : root.bounds.height - frame.maxY
        let font = button.font ?? DS.sans(13, weight: .semibold)
        // Issue batch B49 (#100): two raw samples of the button's own bitmap,
        // `sharp_chrome.py`'s `pixel` — the pixel holding the POINT, top-left
        // origin — 1.5 pt into the top-left corner and 1.5 pt in at mid-height.
        // A square block's two are one opaque fill; a pill's corner is clear.
        var corner: [Int] = []
        var middle: [Int] = []
        if let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
            button.cacheDisplay(in: button.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / button.bounds.width
            let sample = { (x: CGFloat, y: CGFloat) -> [Int] in
                var samples = [Int](repeating: 0, count: max(rep.samplesPerPixel, 4))
                rep.getPixel(
                    &samples, atX: Int((x * scale).rounded(.down)), y: Int((y * scale).rounded(.down)))
                return Array(samples.prefix(rep.samplesPerPixel))
            }
            corner = sample(1.5, 1.5)
            middle = sample(1.5, button.bounds.midY)
        }
        return [
            "title": button.title,
            "textWidth": Double(button.title.size(withAttributes: [.font: font]).width),
            "intrinsic": [Double(button.intrinsicContentSize.width),
                          Double(button.intrinsicContentSize.height)],
            "frame": [Double(frame.minX), Double(top), Double(frame.width), Double(frame.height)],
            "font": font.fontName,
            "action": button.action.map { NSStringFromSelector($0) } ?? "",
            "corner": corner,
            "middle": middle,
        ]
    }
    out["spacing"] = Double((buttons.first?.superview as? NSStackView)?.spacing ?? -1)
    // Rename R2 (spec §11 NM-11): the lockup's frame, top-left origin as each
    // button's, so 6d can leave its own rows out of the "above" comparison.
    if let lockup = descendants(BrandLockupView.self, in: root).first {
        let frame = root.convert(lockup.bounds, from: lockup)
        let top = root.isFlipped ? frame.minY : root.bounds.height - frame.maxY
        out["lockup"] = [Double(frame.minX), Double(top), Double(frame.width), Double(frame.height)]
    }
    out["contentSize"] = [Double(root.bounds.width), Double(root.bounds.height)]
    out["rootFlipped"] = root.isFlipped
    out["recentCount"] = NSDocumentController.shared.recentDocumentURLs.count
    out["backingScale"] = Double(controller.window?.backingScaleFactor ?? 0)
    return out
}

// ---- mode "catalog": the tool list the parity check reads ------------------
func catalog(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    do {
        let json = try AgentServer.shared.catalogJSON()
        let tools = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] ?? []
        out["tools"] = tools.map { tool -> [String: Any] in
            let schema = tool["inputSchema"] as? [String: Any] ?? [:]
            let properties = schema["properties"] as? [String: Any] ?? [:]
            return [
                "name": tool["name"] as? String ?? "", "hasScope": properties["scope"] != nil,
                "properties": properties.keys.sorted(),
                "required": (schema["required"] as? [String] ?? []).sorted(),
                "description": tool["description"] as? String ?? "",
            ]
        }
        out["bytes"] = json.utf8.count
    } catch { out["error"] = "\(error)" }
    out["coreOps"] = ReelOp.coreNames()
    return out
}

// ---- mode "host": facts a reader of the log needs, never asserted ---------
func host(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    out["screenRecordingPreflight"] = CGPreflightScreenCaptureAccess()
    out["microphoneStatus"] = RecordingGrant.name(of: RecordingGrant.microphoneStatus)
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    out["sessionDictionary"] = session != nil
    out["screenIsLockedKeyPresent"] = session?["CGSSessionScreenIsLocked"] != nil
    out["screenIsLocked"] = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    out["activeDisplays"] = Int(count)
    out["screens"] = NSScreen.screens.count
    out["bundleIdentifier"] = Bundle.main.bundleIdentifier as Any
    return out
}

// ---- mode "granted": the probe's own granted tier (road map 3, R2e) ------

/// One real recording of the main display on a FRESH `ScreenRecorder()`:
/// start, a second, `pause()`, `elapsed` twice half a second apart, then —
/// with `resume` — `resume()`, a second more, and `stop()`. Every wait is
/// bounded. `spell` carries each segment's probed descriptor.
func grantedRun(_ filter: SCContentFilter, _ choice: RecordingChoice, resume: Bool)
    -> [String: Any]
{
    var out: [String: Any] = [:]
    let recorder = ScreenRecorder()
    var finishes: [[String: Any]] = []
    var startError: String?
    var started = false
    let t0 = Date()
    recorder.start(filter: filter, choice: choice, mayAsk: true,
                   onFinish: { finishes.append(spell($0)) }) {
        error in
        startError = error.map { $0.localizedDescription }
        started = true
    }
    out["started"] = spin(ScreenRecorder.armCeiling + 5) { started }
    out["startError"] = startError as Any
    out["startLatency"] = Date().timeIntervalSince(t0)
    guard started, startError == nil else { return out }
    out["stateAfterStart"] = "\(recorder.state)"
    out["segment0"] = describeSegment(recorder.segment0)
    _ = spin(1.0) { false }
    out["elapsedBeforePause"] = recorder.elapsed
    do {
        try recorder.pause()
        out["pause"] = "ok"
    } catch { out["pause"] = spellError(error) }
    out["stateAfterPause"] = "\(recorder.state)"
    out["isPaused"] = recorder.isPaused
    let a = recorder.elapsed
    _ = spin(0.5) { false }
    let b = recorder.elapsed
    out["elapsedA"] = a
    out["elapsedB"] = b
    let removed = Date()
    out["segment0FinishedWhilePaused"] =
        spin(3) { recorder.session?.segments.first?.screenFinished == true }
    out["didFinishLatency"] = Date().timeIntervalSince(removed)
    _ = spin(0.5) { false }
    if resume {
        do {
            try recorder.resume()
            out["resume"] = "ok"
        } catch { out["resume"] = spellError(error) }
        out["stateAfterResume"] = "\(recorder.state)"
        out["segmentsAfterResume"] = recorder.session?.segments.count ?? -1
        let added = Date()
        out["segment1DidStart"] =
            spin(3) { recorder.session?.segments.count == 2
                && recorder.session?.segments[1].screenStartedAt != nil }
        out["didStartLatency"] = Date().timeIntervalSince(added)
        out["segment1"] = describeSegment(
            recorder.session.flatMap { $0.segments.count > 1 ? $0.segments[1] : nil })
        _ = spin(1.0) { false }
        out["elapsedBeforeStop"] = recorder.elapsed
        out["elapsedWall"] = Date().timeIntervalSince(t0)
    }
    var stops: [[String: Any]] = []
    recorder.stop { stops.append(spell($0)) }
    out["stateAfterStop"] = "\(recorder.state)"
    let stopped = Date()
    out["concluded"] = spin(30) { recorder.state == .idle }
    out["stopLatency"] = Date().timeIntervalSince(stopped)
    out["onFinishCount"] = finishes.count
    out["onFinish"] = finishes.first ?? [:]
    out["stopCount"] = stops.count
    out["stop"] = stops.first ?? [:]
    out["elapsedAfter"] = recorder.elapsed
    var sizes: [String: Int] = [:]
    for segment in (finishes.first?["segments"] as? [[String: Any]]) ?? [] {
        if let path = segment["path"] as? String {
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            sizes[path] = (attributes?[.size] as? NSNumber)?.intValue ?? -1
        }
    }
    out["sizes"] = sizes
    return out
}

extension ScreenRecorder {
    var segment0: Segment? { session?.segments.first }
}

func granted(_ request: [String: Any]) -> [String: Any] {
    // FIRST: the untitled landing in run 3 needs the probe's controller.
    let controller = ProbeDocumentController()
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let folder = URL(fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory(),
                     isDirectory: true)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
        RecorderPanelController.includeFrameJobWindowsKey: false,
        RecordingFiles.folderDefaultsKey: folder.path,
        FFmpegRewrap.policyDefaultsKey: FFmpegRewrap.Policy.never.rawValue,
        "ApplePersistenceIgnoreState": true,
        "AppleShowScrollBars": "Always",
    ], forName: UserDefaults.argumentDomain)
    var out: [String: Any] = [:]
    out["controllerIsProbe"] = NSDocumentController.shared === controller
    out["preflight"] = CGPreflightScreenCaptureAccess()
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    out["locked"] = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    out["folderPinned"] = RecordingFiles.folder().path
    var content: SCShareableContent?
    var listFailure = ""
    var answered = false
    ScreenRecorder.shareableContent { outcome in
        switch outcome {
        case .success(let listed): content = listed
        case .failure(let error): listFailure = error.localizedDescription
        }
        answered = true
    }
    out["answered"] = spin(20) { answered }
    out["displays"] = content?.displays.count ?? -1
    out["listFailure"] = listFailure
    guard CGPreflightScreenCaptureAccess() else {
        out["skipped"] = "CGPreflightScreenCaptureAccess() is false under this process's grant"
        return out
    }
    guard let content, !content.displays.isEmpty else {
        out["skipped"] = "no shareable display (\(content?.displays.count ?? -1); "
            + (listFailure.isEmpty ? "the console is locked or every display is asleep" : listFailure)
            + ")"
        return out
    }
    do { try RecordingFiles.create(folder) } catch { return ["error": "\(error)"] }
    let filter: SCContentFilter
    do {
        filter = try ScreenRecorder.filter(
            for: .display(CGMainDisplayID()), in: content,
            excluding: RecordingExclusion.make(
                includeFrameJobWindows: false, ownBundleID: Bundle.main.bundleIdentifier,
                panelWindowID: nil))
    } catch { return ["error": "\(error)"] }
    out["filter"] = ["width": Double(filter.contentRect.width),
                     "height": Double(filter.contentRect.height),
                     "scale": Double(filter.pointPixelScale)]
    var choice = RecordingChoice()
    choice.folder = folder
    choice.microphone = nil
    out["run1"] = grantedRun(filter, choice, resume: true)
    out["run2"] = grantedRun(filter, choice, resume: false)

    // Run 3: the PANEL, end to end — Record over the main display, the
    // panel hidden at recordingDidStart, Pause and Resume through the two
    // entries the status item calls, Stop, the landing as a new project,
    // and the panel STAYING hidden because the note is empty (decision 7).
    // `ScreenRecorder.shared` and the pinned folder, the panel's own path.
    var r3: [String: Any] = [:]
    let panel = RecorderPanelController.shared
    let window = panel.window
    panel.selectDisplay(CGMainDisplayID())
    panel.show()
    r3["visibleBefore"] = window?.isVisible ?? false
    r3["destinationNewProject"] = panel.currentChoice().destination == .newProject
    r3["microphoneOff"] = panel.currentChoice().microphone == nil
    r3["sourceMain"] = panel.currentChoice().source == .display(CGMainDisplayID())
    let docsBefore = NSDocumentController.shared.documents.count
    panel.record(nil)
    if case .countdown = panel.phase { r3["countdownBegan"] = true } else { r3["countdownBegan"] = false }
    r3["recording"] = spin(Double(RecorderPanelController.countdownSeconds) + ScreenRecorder.armCeiling + 5) {
        panel.phase == .recording
    }
    r3["atStart"] = [
        "visible": window?.isVisible ?? true, "hiddenForRecording": panel.hiddenForRecording,
        "showWhenLanded": panel.showWhenLanded, "itemShowing": panel.statusItem?.isShowing ?? false,
        "note": panel.noteLabel.stringValue, "recorder": "\(ScreenRecorder.shared.state)",
    ]
    panel.show()
    r3["showWhileHidden"] = window?.isVisible ?? true
    _ = spin(1.0) { false }
    panel.pauseRecording()
    let statusAtPause = panel.statusLabel.stringValue
    r3["paused"] = [
        "phase": "\(panel.phase)", "recorder": "\(ScreenRecorder.shared.state)",
        "status": statusAtPause, "faint": panel.statusLabel.textColor == DS.textFaint,
        "elapsed": ScreenRecorder.shared.elapsed,
    ]
    _ = spin(0.7) { false }
    r3["statusHeld"] = panel.statusLabel.stringValue
    r3["elapsedHeld"] = ScreenRecorder.shared.elapsed
    panel.resumeRecording()
    r3["resumed"] = ["phase": "\(panel.phase)", "recorder": "\(ScreenRecorder.shared.state)",
                     "segments": ScreenRecorder.shared.session?.segments.count ?? -1]
    _ = spin(1.0) { false }
    panel.stopRecording()
    r3["stopping"] = "\(panel.phase)"
    r3["landed"] = spin(40) { panel.phase == .idle }
    r3["afterLanding"] = [
        "visible": window?.isVisible ?? true, "note": panel.noteLabel.stringValue,
        "hiddenForRecording": panel.hiddenForRecording, "showWhenLanded": panel.showWhenLanded,
        "itemDown": panel.statusItem == nil, "recorder": "\(ScreenRecorder.shared.state)",
    ]
    r3["documentsOpened"] = NSDocumentController.shared.documents.count - docsBefore
    if let d = NSDocumentController.shared.documents.last as? ProjectDocument {
        let s = d.project.snapshot
        r3["document"] = [
            "media": s.media.count, "tracks": s.tracks.map { $0.name },
            "clips": s.clips.sorted { $0.start < $1.start }.map(describeClip),
            "undoName": d.undoManager?.undoActionName ?? "",
            "displayName": d.displayName ?? "<nil>", "canvasFps": fpsPair(s.canvas.fps),
            "edited": d.isDocumentEdited,
            "mediaPaths": s.media.map { $0.path },
        ]
        d.close()
    }
    out["run3"] = r3
    return out
}

// ---- mode "grants": the step a press takes, the panes, the press ---------

/// The doors every mode runs under (installed before the dispatch): the
/// three READS are real, and every door that could prompt, open System
/// Settings or write `FrameJobScreenRecordingAsked` does nothing — so no mode,
/// the window-row mutant's fall-through and the granted tier's press
/// included, can put up a prompt or a pane.
func sealedDoors() -> RecorderGrantDoors {
    RecorderGrantDoors(
        screenGranted: { RecordingGrant.screenRecordingGranted },
        launchedByLaunchd: { RecordingGrant.launchedByLaunchd },
        requestScreen: {},
        screenAsked: { false },
        rememberScreenAsked: {},
        microphoneStatus: { RecordingGrant.microphoneStatus },
        requestMicrophone: { _ in },
        openSettings: { _ in false },
        cameraStatus: { RecordingGrant.cameraStatus },
        requestCamera: { _ in })
}

/// One row's doors: an in-memory asked flag, the launchd answer, the grant
/// and the microphone status the row chooses, counters for the two
/// prompts, the URLs the opener was handed and the Bool it answers, and
/// the microphone prompt's completion HELD until the row fires it.
final class GrantSpy {
    var granted = false
    var asked = false
    var launchd = true
    var mic: AVAuthorizationStatus = .authorized
    var openAnswer = true
    /// Reads of the Screen Recording grant (issue batch B66's D5, D6).
    var screenReads = 0
    var screenRequests = 0
    var micRequests = 0
    var remembered = 0
    var opened: [String] = []
    var held: (() -> Void)?

    var doors: RecorderGrantDoors {
        RecorderGrantDoors(
            screenGranted: {
                self.screenReads += 1
                return self.granted
            },
            launchedByLaunchd: { self.launchd },
            requestScreen: { self.screenRequests += 1 },
            screenAsked: { self.asked },
            rememberScreenAsked: {
                self.remembered += 1
                self.asked = true
            },
            microphoneStatus: { self.mic },
            requestMicrophone: { answered in
                self.micRequests += 1
                self.held = answered
            },
            openSettings: { url in
                self.opened.append(url.absoluteString)
                return self.openAnswer
            },
            cameraStatus: { RecordingGrant.cameraStatus },
            requestCamera: { _ in })
    }
}

func levelName(_ level: NSWindow.Level?) -> String {
    switch level {
    case .some(.floating): return "floating"
    case .some(.normal): return "normal"
    case .some(let other): return "\(other.rawValue)"
    case .none: return "none"
    }
}

func stepName(_ step: RecordingGrant.Step) -> String {
    switch step {
    case .proceed: return "proceed"
    case .ask: return "ask"
    case .openPane: return "openPane"
    }
}

func grants(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    // 10a — screenStep over all eight combinations.
    var screen: [[String: Any]] = []
    for granted in [false, true] {
        for asked in [false, true] {
            for launchd in [false, true] {
                let step = RecordingGrant.screenStep(
                    granted: granted, asked: asked, launchedByLaunchd: launchd)
                screen.append(["granted": granted, "asked": asked, "launchd": launchd,
                               "step": stepName(step)])
            }
        }
    }
    out["screenSteps"] = screen
    // 10b — microphoneStep over the four statuses.
    let statuses: [(String, AVAuthorizationStatus)] = [
        ("authorized", .authorized), ("notDetermined", .notDetermined),
        ("denied", .denied), ("restricted", .restricted),
    ]
    out["microphoneSteps"] = statuses.map { (word, status) -> [String: Any] in
        ["status": word, "step": stepName(RecordingGrant.microphoneStep(status))]
    }
    // 10c — the two URLs, and the application that would open them
    // (resolved, never opened).
    let screenURL = RecordingGrant.screenRecordingPaneURL
    let micURL = RecordingGrant.microphonePaneURL
    var urls: [String: String] = [:]
    urls["screen"] = screenURL?.absoluteString ?? "<nil>"
    urls["screenScheme"] = screenURL?.scheme ?? "<nil>"
    var screenHost = ""
    if let url = screenURL, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
        screenHost = parts.path
    }
    urls["screenHost"] = screenHost
    urls["microphone"] = micURL?.absoluteString ?? "<nil>"
    urls["microphoneScheme"] = micURL?.scheme ?? "<nil>"
    var screenHandler = "<nil>"
    if let url = screenURL, let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
        screenHandler = app.path
    }
    var micHandler = "<nil>"
    if let url = micURL, let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
        micHandler = app.path
    }
    urls["screenHandler"] = screenHandler
    urls["microphoneHandler"] = micHandler
    out["urls"] = urls
    // 10d — the opened notes against the refusals they extend.
    out["notes"] = [
        "paneSentence": RecordingGrant.screenRecordingPaneSentence,
        "openedSentence": RecordingGrant.paneOpenedSentence,
        "launchClause": RecordingGrant.launchClause,
        "screenOpened": RecordingGrant.screenRecordingOpenedNote,
        "screenRefusal": RecordingGrant.screenRecordingRefusal,
        "micOpenedDenied": RecordingGrant.microphoneOpenedNote(.denied),
        "micOpenedRestricted": RecordingGrant.microphoneOpenedNote(.restricted),
        "micRefusalDenied": RecordingGrant.microphoneRefusal(.denied),
        "micRefusalRestricted": RecordingGrant.microphoneRefusal(.restricted),
    ]

    // 10e — the press, through record(_:), one spy per row.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
        RecorderPanelController.includeFrameJobWindowsKey: false,
    ], forName: UserDefaults.argumentDomain)
    let panel = RecorderPanelController.shared
    // show() ONCE: in .idle it rebuilds the microphone popup, which would
    // drop the fake row below.
    panel.show()
    panel.selectDisplay(CGMainDisplayID())
    let fake = NSMenuItem(title: "Probe Microphone", action: nil, keyEquivalent: "")
    fake.representedObject = "probe-mic"
    panel.microphonePopup.menu?.addItem(fake)
    func reset() {
        panel.cancelCountdown()
        panel.phase = .idle
        panel.setNote("")
    }
    func press(_ spy: GrantSpy) -> [String: Any] {
        RecorderPanelController.grantDoors = spy.doors
        panel.record(nil)
        return [
            "phase": "\(panel.phase)", "note": panel.noteLabel.stringValue,
            "screenRequests": spy.screenRequests, "micRequests": spy.micRequests,
            "opened": spy.opened, "asked": spy.asked, "remembered": spy.remembered,
            "buttonEnabled": panel.recordButton.isEnabled,
            "micChoice": panel.currentChoice().microphone ?? "",
            "level": levelName(panel.window?.level),
        ]
    }
    var rows: [String: Any] = [:]
    out["visible"] = panel.window?.isVisible ?? false
    panel.microphonePopup.selectItem(at: 0)

    reset()
    let first = GrantSpy()
    rows["1"] = press(first)
    reset()
    rows["2"] = press(first)
    reset()
    let third = GrantSpy()
    third.asked = true
    third.openAnswer = false
    rows["3"] = press(third)

    panel.microphonePopup.select(fake)
    for (key, status) in [("4", AVAuthorizationStatus.denied), ("5", .restricted)] {
        reset()
        let spy = GrantSpy()
        spy.granted = true
        spy.mic = status
        rows[key] = press(spy)
    }
    reset()
    let sixth = GrantSpy()
    sixth.granted = true
    sixth.mic = .notDetermined
    var six = press(sixth)
    sixth.mic = .denied
    let heldFired = sixth.held != nil
    sixth.held?()
    six["heldFired"] = heldFired
    six["afterPhase"] = "\(panel.phase)"
    six["afterNote"] = panel.noteLabel.stringValue
    six["afterButtonEnabled"] = panel.recordButton.isEnabled
    six["afterOpened"] = sixth.opened
    six["afterMicRequests"] = sixth.micRequests
    six["afterLevel"] = levelName(panel.window?.level)
    rows["6"] = six
    reset()
    let seventh = GrantSpy()
    seventh.granted = true
    seventh.mic = .authorized
    rows["7"] = press(seventh)
    reset()
    panel.microphonePopup.selectItem(at: 0)
    let eighth = GrantSpy()
    eighth.granted = true
    eighth.mic = .denied
    rows["8"] = press(eighth)
    reset()
    let ninth = GrantSpy()
    ninth.granted = true
    rows["9"] = press(ninth)
    reset()
    let tenth = GrantSpy()
    tenth.launchd = false
    var ten = press(tenth)
    reset()
    let tenSecond = press(tenth)
    ten["second"] = tenSecond
    rows["10"] = ten
    reset()
    let eleventh = GrantSpy()
    eleventh.launchd = false
    eleventh.asked = true
    rows["11"] = press(eleventh)
    reset()
    out["rows"] = rows
    out["countdown"] = "\(RecorderPanelController.Phase.countdown(RecorderPanelController.countdownSeconds))"
    RecorderPanelController.grantDoors = sealedDoors()
    panel.window?.orderOut(nil)
    return out
}

// ---- mode "preroll": the countdown's meter (issue batch B27, #98 c) -------

/// The first microphone of the app's OWN discovery list (the panel's rows,
/// `ScreenRecorder.microphone(withID:)`'s session) whose transport is BUILT
/// IN, else the first that is USB — never a virtual or aggregate input,
/// which reads a flat floor.
func prerollDevice() -> AVCaptureDevice? {
    let devices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
    ).devices
    func transport(_ device: AVCaptureDevice) -> UInt32 { UInt32(bitPattern: device.transportType) }
    return devices.first { transport($0) == kAudioDeviceTransportTypeBuiltIn }
        ?? devices.first { transport($0) == kAudioDeviceTransportTypeUSB }
}

/// P1–P3 on a fresh `ScreenRecorder()` — never `.shared` — then P4–P5
/// through the PANEL on `.shared`, whose countdown is cancelled at 1.2 s so
/// it never reaches 0 and nothing is recorded. The Microphone status is
/// read BEFORE any device is touched, so nothing here can prompt.
func preroll(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let status = RecordingGrant.microphoneStatus
    out["status"] = RecordingGrant.name(of: status)
    guard status == .authorized else {
        out["skipped"] = "the Microphone status is \(RecordingGrant.name(of: status)), not "
            + "authorized — a pre-roll level needs a running input, and a probe may not prompt"
        return out
    }
    guard let device = prerollDevice() else {
        out["skipped"] = "no built-in or USB microphone is connected (a virtual or aggregate "
            + "input reads a flat floor, so it proves no level)"
        return out
    }
    let id = device.uniqueID
    out["device"] = device.localizedName
    out["transport"] =
        UInt32(bitPattern: device.transportType) == kAudioDeviceTransportTypeBuiltIn ? "built-in" : "USB"

    // P1 — prepared on a fresh recorder.
    let recorder = ScreenRecorder()
    var published: [LevelMeterReading] = []
    let watch = recorder.meter.addObserver { published.append($0) }
    recorder.prepareMicrophone(id)
    out["p1"] = [
        "prepared": recorder.preparedMicrophone?.deviceID == id,
        "running": recorder.preparedMicrophone?.session.isRunning ?? false,
        "state": "\(recorder.state)",
    ]
    // P2 — 30 polls at 1/30 s, the panel's rate.
    var peak: Float = 0
    var idle = true
    for _ in 0..<30 {
        recorder.publishMicrophoneLevel()
        peak = max(peak, recorder.meter.reading.peakLeft)
        if recorder.state != .idle { idle = false }
        RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 30))
    }
    out["p2"] = ["maxPeakLeft": Double(peak), "idleThroughout": idle, "publishes": published.count]
    // P3 — the discard publishes silence, and a later poll publishes nothing.
    recorder.discardPreparedMicrophone()
    let silentAfterDiscard = recorder.meter.reading.isSilent
    let countAfterDiscard = published.count
    recorder.publishMicrophoneLevel()
    out["p3"] = [
        "silent": silentAfterDiscard, "prepared": recorder.preparedMicrophone != nil,
        "laterPublishes": published.count - countAfterDiscard,
    ]
    withExtendedLifetime(watch) {}

    // P4 — the panel's countdown on `.shared`, metered by its own tick.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
        RecorderPanelController.includeFrameJobWindowsKey: false,
    ], forName: UserDefaults.argumentDomain)
    let shared = ScreenRecorder.shared
    let panel = RecorderPanelController.shared
    panel.show()
    panel.selectDisplay(CGMainDisplayID())
    panel.selectMicrophone(id)
    let spy = GrantSpy()
    spy.granted = true
    spy.mic = .authorized
    RecorderPanelController.grantDoors = spy.doors
    var sharedReadings: [LevelMeterReading] = []
    let sharedWatch = shared.meter.addObserver { sharedReadings.append($0) }
    let chosen = panel.currentChoice().microphone ?? ""
    panel.record(nil)
    let phaseAtPress = "\(panel.phase)"
    let preparedAtPress = shared.preparedMicrophone?.deviceID == id
    _ = spin(1.2) { false }
    let sharedPeak = sharedReadings.map(\.peakLeft).max() ?? 0
    out["p4"] = [
        "chosen": chosen == id, "phaseAtPress": phaseAtPress, "preparedAtPress": preparedAtPress,
        "phase": "\(panel.phase)", "maxPeakLeft": Double(sharedPeak),
        "recorderState": "\(shared.state)", "screenRequests": spy.screenRequests,
        "micRequests": spy.micRequests,
    ]
    // P5 — Cancel: the bar goes dark and stays dark.
    panel.record(nil)
    let cancelIndex = sharedReadings.count
    let p5Phase = "\(panel.phase)"
    let p5Prepared = shared.preparedMicrophone != nil
    let p5Silent = shared.meter.reading.isSilent
    _ = spin(0.3) { false }
    let after = sharedReadings[cancelIndex...]
    out["p5"] = [
        "phase": p5Phase, "prepared": p5Prepared, "silent": p5Silent,
        "silentLater": shared.meter.reading.isSilent,
        "nonSilentAfter": after.filter { !$0.isSilent }.count,
        "recorderState": "\(shared.state)",
    ]
    withExtendedLifetime(sharedWatch) {}
    RecorderPanelController.grantDoors = sealedDoors()
    panel.window?.orderOut(nil)
    return out
}

// ---- mode "voiceover": #99 phase 1 — a voice-over's pure faces -----------

/// The landing's fixtures for a voice-over: `.m4a` descriptors and a result
/// whose every segment's descriptor is one, `micDescriptor` nil — the shape
/// `ScreenRecorder+VoiceOverFinishing.swift` produces.
func voiceOverResult(
    _ list: [MediaDescriptor], source: RecordingSource = .voiceOver, rate: Int = 30
) -> RecordingResult {
    var choice = RecordingChoice()
    choice.source = source
    choice.rate = rate
    choice.microphone = "probe"
    return RecordingResult(
        segments: list.map {
            RecordingSegment(descriptor: $0, micDescriptor: nil, micOffset: 0, startedAt: Date())
        }, choice: choice, stoppedBy: .stopped, pauses: list.count - 1)
}

/// A silent mono 48 kHz WAV of `seconds` at `url`, written with
/// `AVAudioFile` — a file `MediaImporter.probe` reads as audio (B66's V10).
func writeWAV(_ url: URL, seconds: Double) -> Bool {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else {
        return false
    }
    let frames = AVAudioFrameCount(48_000 * seconds)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return false }
    buffer.frameLength = frames
    do {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    } catch {
        return false
    }
    return true
}

func voiceover(_ request: [String: Any]) -> [String: Any] {
    let controller = ProbeDocumentController()
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain(
        ["ApplePersistenceIgnoreState": true,
         "AppleShowScrollBars": "Always"],
        forName: UserDefaults.argumentDomain)
    var out: [String: Any] = [:]
    out["controllerIsProbe"] = NSDocumentController.shared === controller
    let tmp = URL(
        fileURLWithPath: request["tempFolder"] as? String ?? NSTemporaryDirectory(),
        isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let second: Ticks = 600_000

    // V1: the stem and the held-aware free name.
    out["stems"] = (request["stemDates"] as? [Double] ?? []).map { seconds -> [String: Any] in
        ["seconds": seconds,
         "stem": RecordingFiles.voiceOverStem(at: Date(timeIntervalSince1970: seconds))]
    }
    let names = tmp.appendingPathComponent("names", isDirectory: true)
    try? FileManager.default.createDirectory(at: names, withIntermediateDirectories: true)
    let nameDate = Date(timeIntervalSince1970: request["nameDate"] as? Double ?? 0)
    let free = ScreenRecorder.nextVoiceOverURL(in: names, at: nameDate, holding: [])
    let held = ScreenRecorder.nextVoiceOverURL(in: names, at: nameDate, holding: [free.path])
    let onDisk = FileManager.default.createFile(atPath: free.path, contents: Data())
    let third = ScreenRecorder.nextVoiceOverURL(in: names, at: nameDate, holding: [held.path])
    out["v1"] = [
        "free": free.path, "held": held.path, "third": third.path, "onDisk": onDisk,
        "folder": names.path,
    ]

    // V2: the refusals a fresh recorder answers before returning.
    let recorder = ScreenRecorder()
    var finishes = 0
    func refusal(_ choice: RecordingChoice) -> [String: Any] {
        var answer: String?
        recorder.startVoiceOver(
            choice: choice, mayAsk: true, onFinish: { _ in finishes += 1 }, completion: { error in
                answer = error.map(spellError) ?? "nil"
            })
        let beforeReturn = answer != nil
        return ["answer": answer ?? "unanswered", "beforeReturn": beforeReturn,
                "state": "\(recorder.state)"]
    }
    var display = RecordingChoice()
    display.source = .display(CGMainDisplayID())
    display.microphone = "probe"
    display.folder = tmp
    var noMic = RecordingChoice()
    noMic.source = .voiceOver
    noMic.microphone = nil
    noMic.folder = tmp
    out["v2"] = [
        "display": refusal(display), "noMic": refusal(noMic),
        "state": "\(recorder.state)", "isRecording": recorder.isRecording,
        "voiceSession": recorder.voiceSession != nil, "session": recorder.session != nil,
        "heldSegmentCount": recorder.heldSegmentCount, "heldFilePaths": recorder.heldFilePaths,
        "finishes": finishes, "sentence": ScreenRecorder.voiceOverNeedsMicrophoneSentence,
    ]

    func voice(_ name: String, _ ticks: Ticks) -> MediaDescriptor {
        MediaDescriptor(
            path: tmp.appendingPathComponent("\(name).m4a").path, kind: .audio, duration: ticks,
            hasAudio: true)
    }
    /// A 30 fps document with a 10 s clip at 0 on its one track, the
    /// playhead at 2 s.
    func seeded() -> ProjectDocument {
        let d = ProjectDocument()
        let blocker = MediaDescriptor(
            path: "/nowhere/blocker.mov", kind: .video, duration: 10 * second, width: 640,
            height: 360, fps: .thirty, hasVideo: true)
        let t = d.project.snapshot.tracks[0].id
        d.performGroupedEdit("seed", [.addMedia(descriptor: blocker)])
        let bid = d.project.snapshot.media.last?.id ?? 0
        d.performGroupedEdit("seed clip", [.addClip(track: t, media: bid, at: 0)])
        d.playhead = 2 * second
        return d
    }
    func tracks(_ s: ProjectSnapshot) -> [[String: Any]] {
        s.tracks.map { ["id": Int($0.id), "name": $0.name] as [String: Any] }
    }
    func row(_ body: () throws -> [String: Any]) -> [String: Any] {
        do { return try body() } catch { return ["error": "\(error)"] }
    }
    let pair = [voice("V1", 3 * second), voice("V2", 2 * second)]

    // V3: two voice segments in a document whose front track is taken.
    out["V3"] = row {
        let d = seeded()
        let beforeJSON = d.project.json
        let before = d.project.snapshot
        let p = try RecordingLanding.placement(voiceOverResult(pair), in: d, place: true)
        var facts = commit(d, p)
        let after = d.project.snapshot
        facts["canvasFps"] = fpsPair(after.canvas.fps)
        facts["tracksBefore"] = tracks(before)
        facts["tracksAfter"] = tracks(after)
        facts["blockerBefore"] = before.clips.map(describeClip)
        facts["blockerAfter"] = after.clips.filter { c in before.clips.contains { $0.id == c.id } }
            .map(describeClip)
        facts["playhead"] = d.playhead
        d.undoManager?.undo()
        facts["undoRestores"] = d.project.json == beforeJSON
        return facts
    }
    // V4: place false — media only.
    out["V4"] = row {
        let d = seeded()
        return commit(d, try RecordingLanding.placement(voiceOverResult(pair), in: d, place: false))
    }
    // V5: a segment under a frame, then every segment under one.
    out["V5"] = row {
        let d = seeded()
        let short = voice("V5short", 5_000)
        let p = try RecordingLanding.placement(
            voiceOverResult([short, voice("V5long", 2 * second)]), in: d, place: true)
        var facts = commit(d, p)
        let fps = d.project.snapshot.canvas.fps
        facts["expectedNote"] =
            d.project.snapshot.media.first { $0.path == short.path }
            .flatMap { RecordingLanding.tooShortNote($0, at: fps) } ?? "<no media>"
        let e = seeded()
        let q = try RecordingLanding.placement(
            voiceOverResult([voice("V5a", 5_000), voice("V5b", 4_000)]), in: e, place: true)
        facts["allShort"] = commit(e, q)
        return facts
    }
    // V6: inside an open nest.
    out["V6"] = row {
        let d = seeded()
        let cid = d.project.snapshot.clips.last?.id ?? 0
        d.performGroupedEdit("nest", [.nest(clips: [cid], name: "N")])
        let s = d.project.snapshot
        guard let nestClip = s.clips.first, let nest = s.nests.first else {
            throw ReelCoreError(message: "no nest")
        }
        d.setNestPath([NestScopeStep(nest: nest.id, clip: nestClip.id)], playhead: 0, selection: [])
        let outerBefore = d.project.snapshot
        let p = try RecordingLanding.placement(voiceOverResult(pair), in: d, place: true)
        var facts = commit(d, p)
        let inner = d.editedProject.snapshot
        let outer = d.project.snapshot
        facts["scope"] = d.scope.map { Int($0) } ?? -1
        facts["innerTracks"] = tracks(inner)
        facts["innerClips"] = inner.clips.map(describeClip)
        facts["outerClipsBefore"] = outerBefore.clips.count
        facts["outerClips"] = outer.clips.count
        facts["outerTracksBefore"] = outerBefore.tracks.count
        facts["outerTracks"] = outer.tracks.count
        facts["outerMediaBefore"] = outerBefore.media.count
        facts["outerMedia"] = outer.media.count
        facts["innerMedia"] = inner.media.count
        return facts
    }
    // V7: a voice-over as a new project, at rate 30.
    for name in ["V7a", "V7b"] {
        try? Data("not audio".utf8).write(to: tmp.appendingPathComponent("\(name).m4a"))
    }
    out["V7"] = row {
        let r = voiceOverResult([voice("V7a", 3 * second), voice("V7b", 2 * second)], rate: 30)
        let (d, notes) = try ProjectDocument.untitled(around: r)
        let s = d.project.snapshot
        var facts: [String: Any] = [:]
        facts["notes"] = notes
        facts["canvas"] = [s.canvas.width, s.canvas.height]
        facts["canvasFps"] = fpsPair(s.canvas.fps)
        facts["clips"] = s.clips.map(describeClip)
        facts["tracks"] = tracks(s)
        facts["media"] = s.media.map { ["id": Int($0.id), "path": $0.path] as [String: Any] }
        facts["undoName"] = d.undoManager?.undoActionName ?? ""
        d.undoManager?.undo()
        facts["afterUndo"] = d.project.snapshot.clips.map(describeClip)
        d.close()
        return facts
    }
    // V8 (control): the same descriptors with a screen source.
    out["V8"] = row {
        let d = seeded()
        let before = d.project.snapshot
        let p = try RecordingLanding.placement(
            voiceOverResult(pair, source: .display(CGMainDisplayID())), in: d, place: true)
        var facts = commit(d, p)
        facts["tracksBefore"] = tracks(before)
        facts["tracksAfter"] = tracks(d.project.snapshot)
        return facts
    }
    // V9 (issue batch B66, nit 3): a 30 fps document at the 64-track cap.
    func capped() -> ProjectDocument {
        let d = ProjectDocument()
        let have = d.project.snapshot.tracks.count
        d.performGroupedEdit("fill", (have..<64).map { _ in ReelOp.addTrack(index: 0, name: "Fill") })
        return d
    }
    out["V9"] = row {
        let d = capped()
        let a = voice("V9a", 5_000)
        let b = voice("V9b", 4_000)
        var facts: [String: Any] = [:]
        facts["tracksBefore"] = d.project.snapshot.tracks.count
        facts["canvasFps"] = fpsPair(d.project.snapshot.canvas.fps)
        do {
            let p = try RecordingLanding.placement(voiceOverResult([a, b]), in: d, place: true)
            facts.merge(commit(d, p)) { _, new in new }
            let fps = d.project.snapshot.canvas.fps
            facts["expectedNotes"] = [a, b].map { v in
                d.project.snapshot.media.first { $0.path == v.path }
                    .flatMap { RecordingLanding.tooShortNote($0, at: fps) } ?? "<no media>"
            }
            facts["tracksAfter"] = d.project.snapshot.tracks.count
        } catch {
            facts["error"] = (error as? ReelCoreError)?.message ?? "\(error)"
        }
        let e = capped()
        do {
            _ = try RecordingLanding.placement(
                voiceOverResult([voice("V9c", 5_000), voice("V9d", 2 * second)]), in: e, place: true)
            facts["control"] = "no throw"
        } catch {
            facts["control"] = (error as? ReelCoreError)?.message ?? "\(error)"
        }
        return facts
    }
    // V10 (issue batch B66, nit 2): a writer's did-finish judged by when it
    // ARRIVED, on a fresh recorder holding a hand-built voice session.
    pinNeverRewrap()
    func voiceRow(
        _ name: String, _ drive: (ScreenRecorder, SpyAudioOutput, URL) -> [String: Any]
    ) -> [String: Any] {
        let wav = tmp.appendingPathComponent("\(name).wav")
        guard writeWAV(wav, seconds: 1) else { return ["error": "the WAV could not be written"] }
        let recorder = ScreenRecorder()
        let spy = SpyAudioOutput()
        var outcomes: [Result<RecordingResult, Error>] = []
        var choice = RecordingChoice()
        choice.source = .voiceOver
        choice.microphone = "probe"
        choice.folder = tmp
        recorder.voiceSession = ScreenRecorder.VoiceSession(
            choice: choice, mayAsk: true, micSession: AVCaptureSession(), micOutput: spy,
            fileDelegate: VoiceOverFileDelegate(recorder: recorder),
            onFinish: { outcomes.append($0) },
            segments: [ScreenRecorder.VoiceSegment(url: wav, calledAt: Date())])
        recorder.state = .recording
        var facts = drive(recorder, spy, wav)
        _ = spin(5) { !outcomes.isEmpty && recorder.state == .idle }
        facts["outcomes"] = outcomes.count
        facts["finalState"] = "\(recorder.state)"
        if let first = outcomes.first { facts["outcome"] = spell(first) }
        return facts
    }
    out["V10a"] = voiceRow("V10a") { recorder, spy, wav in
        let before = Date()
        Thread.sleep(forTimeInterval: 0.01)
        recorder.stop()
        recorder.voiceFileFinished(wav, output: spy, finishedWell: true, error: nil, at: before)
        return [:]
    }
    out["V10b"] = voiceRow("V10b") { recorder, spy, wav in
        recorder.stop()
        Thread.sleep(forTimeInterval: 0.01)
        recorder.voiceFileFinished(wav, output: spy, finishedWell: true, error: nil, at: Date())
        return [:]
    }
    out["V10c"] = voiceRow("V10c") { recorder, spy, wav in
        let before = Date()
        Thread.sleep(forTimeInterval: 0.01)
        var paused = "ok"
        do { try recorder.pause() } catch { paused = spellError(error) }
        let stateAfterPause = "\(recorder.state)"
        recorder.voiceFileFinished(wav, output: spy, finishedWell: true, error: nil, at: before)
        return ["pause": paused, "stateAfterPause": stateAfterPause]
    }
    out["documentsAfterClose"] = NSDocumentController.shared.documents.count
    return out
}

// ---- mode "voiceover-granted": the real writer, microphone alone ---------

/// G1–G3 on a fresh `ScreenRecorder()` — never `.shared` — over the default
/// audio input. The Microphone status is READ first and the mode answers
/// `skipped` unless it is `.authorized` and a default input exists: nothing
/// here asks for a grant, and nothing touches the screen.
func voiceoverGranted(_ request: [String: Any]) -> [String: Any] {
    let controller = ProbeDocumentController()
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain(
        ["ApplePersistenceIgnoreState": true],
        forName: UserDefaults.argumentDomain)
    var out: [String: Any] = [:]
    out["controllerIsProbe"] = NSDocumentController.shared === controller
    let status = RecordingGrant.microphoneStatus
    out["status"] = RecordingGrant.name(of: status)
    guard status == .authorized else {
        out["skipped"] = "the Microphone grant reads \(RecordingGrant.name(of: status)), not "
            + "authorized — the probe never asks for it"
        return out
    }
    guard let device = AVCaptureDevice.default(for: .audio) else {
        out["skipped"] = "no default audio input device"
        return out
    }
    out["device"] = device.localizedName
    let folder = URL(
        fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory(), isDirectory: true)
    var choice = RecordingChoice()
    choice.source = .voiceOver
    choice.microphone = device.uniqueID
    choice.folder = folder
    choice.rate = 30

    func run(resume: Bool) -> (facts: [String: Any], result: RecordingResult?) {
        let recorder = ScreenRecorder()
        var pauseNotes = 0
        var finishNotes = 0
        let pauseWatch = NotificationCenter.default.addObserver(
            forName: ScreenRecorder.pauseDidChangeNotification, object: recorder, queue: nil
        ) { _ in pauseNotes += 1 }
        let finishWatch = NotificationCenter.default.addObserver(
            forName: ScreenRecorder.finishingDidBeginNotification, object: recorder, queue: nil
        ) { _ in finishNotes += 1 }
        defer {
            NotificationCenter.default.removeObserver(pauseWatch)
            NotificationCenter.default.removeObserver(finishWatch)
        }
        var facts: [String: Any] = [:]
        var outcomes: [Result<RecordingResult, Error>] = []
        var started = "unanswered"
        recorder.startVoiceOver(
            choice: choice, mayAsk: true, onFinish: { outcomes.append($0) },
            completion: { started = $0.map(spellError) ?? "nil" })
        facts["start"] = started
        facts["stateAfterStart"] = "\(recorder.state)"
        var busy = "unanswered"
        recorder.startVoiceOver(
            choice: choice, mayAsk: true, onFinish: { _ in }, completion: { busy = $0.map(spellError) ?? "nil" })
        facts["busy"] = busy
        _ = spin(1.0) { false }
        do {
            try recorder.pause()
            facts["pause"] = "ok"
        } catch { facts["pause"] = spellError(error) }
        facts["stateAfterPause"] = "\(recorder.state)"
        facts["pauseNotesAfterPause"] = pauseNotes
        let e1 = recorder.elapsed
        _ = spin(0.5) { false }
        let e2 = recorder.elapsed
        facts["elapsedPaused"] = [e1, e2]
        if resume {
            do {
                try recorder.resume()
                facts["resume"] = "ok"
            } catch { facts["resume"] = spellError(error) }
            facts["heldAfterResume"] = recorder.heldSegmentCount
            facts["heldPaths"] = recorder.heldFilePaths
            _ = spin(1.0) { false }
        }
        var stops = 0
        recorder.stop { _ in stops += 1 }
        _ = spin(15) { !outcomes.isEmpty && recorder.state == .idle }
        _ = spin(0.3) { false }
        facts["outcomes"] = outcomes.count
        facts["stops"] = stops
        facts["finishNotes"] = finishNotes
        facts["pauseNotes"] = pauseNotes
        facts["finalState"] = "\(recorder.state)"
        facts["voiceSessionAfter"] = recorder.voiceSession != nil
        var result: RecordingResult?
        if let first = outcomes.first {
            var spelled = spell(first)
            if case .success(let r) = first {
                result = r
                spelled["isVoiceOver"] = r.isVoiceOver
                spelled["onDisk"] = r.segments.map {
                    FileManager.default.fileExists(atPath: $0.descriptor.path)
                }
            }
            facts["outcome"] = spelled
        }
        return (facts, result)
    }

    let g1 = run(resume: true)
    out["G1"] = g1.facts
    out["G2"] = run(resume: false).facts
    if let result = g1.result {
        do {
            let d = ProjectDocument()
            let p = try RecordingLanding.voiceOverPlacement(result, in: d, place: true)
            var facts = commit(d, p)
            facts["tracksAfter"] = d.project.snapshot.tracks.map {
                ["id": Int($0.id), "name": $0.name] as [String: Any]
            }
            out["G3"] = facts
        } catch { out["G3"] = ["error": "\(error)"] }
    } else {
        out["G3"] = ["error": "G1 gave no result"]
    }
    return out
}

// ---- mode "voiceover-doors": #99 phase 2 — the panel's row, the tool ----

/// D1–D11 (issue batch B66) over `RecorderPanelController.shared`, NEVER
/// shown, under a `GrantSpy`'s doors whose Screen Recording read is counted,
/// and `AgentServer.shared`'s argument reader. The eight `FrameJobRecording…`
/// values are put back as they were at the end, so the probe's own defaults
/// domain is left as it was found.
func voiceoverDoors(_ request: [String: Any]) -> [String: Any] {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let keys = [
        RecorderPanelController.displayKey, RecorderPanelController.microphoneKey,
        RecorderPanelController.systemAudioKey, RecorderPanelController.showClicksKey,
        RecorderPanelController.rateKey, RecorderPanelController.sizeKey,
        RecorderPanelController.includeFrameJobWindowsKey, RecorderPanelController.cameraKey,
        RecorderPanelController.cameraFormatKey,
    ]
    let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
        for (key, value) in zip(keys, originals) {
            if let value { UserDefaults.standard.set(value, forKey: key) } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    var out: [String: Any] = [:]
    let panel = RecorderPanelController.shared
    let spy = GrantSpy()
    spy.granted = false
    spy.mic = .authorized
    RecorderPanelController.grantDoors = spy.doors
    let fake = NSMenuItem(title: "Probe Microphone", action: nil, keyEquivalent: "")
    fake.representedObject = "probe-mic"
    panel.microphonePopup.menu?.addItem(fake)
    func reset() {
        panel.cancelCountdown()
        panel.phase = .idle
        panel.setNote("")
    }
    func voiceRow() -> NSMenuItem? { panel.sourcePopup.menu?.item(withTag: RecorderPanelController.voiceOverTag) }
    func choose(_ item: NSMenuItem?) {
        if let item { panel.sourcePopup.select(item) }
        panel.controlChanged(panel.sourcePopup)
    }
    func screenOnly() -> [String: Any] {
        [
            "systemAudio": panel.systemAudioSwitch.isEnabled, "showClicks": panel.showClicksSwitch.isEnabled,
            "size": panel.sizePopup.isEnabled,
            "includeFrameJob": panel.includeFrameJobCheckbox.isEnabled,
            "values": [
                panel.systemAudioSwitch.state == .on ? 1 : 0, panel.showClicksSwitch.state == .on ? 1 : 0,
                panel.sizePopup.indexOfSelectedItem,
            ],
        ]
    }
    func recordingKeys() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("FrameJobRecording") }.sorted()
    }
    out["visible"] = panel.window?.isVisible ?? true
    out["shown"] = false

    // D1 — the Source rows.
    let items = panel.sourcePopup.itemArray
    out["D1"] = [
        "titles": items.suffix(3).map { $0.title }, "tags": items.suffix(3).map { $0.tag },
        "count": items.count, "screens": NSScreen.screens.count,
        "separatorIndex": items.firstIndex { $0.isSeparatorItem } ?? -1,
    ]

    // D2 — choosing it. A display row first, its values put in a known
    // non-default state, so "unchanged" means something.
    reset()
    choose(panel.sourcePopup.item(at: 0))
    panel.systemAudioSwitch.state = .off
    panel.showClicksSwitch.state = .on
    panel.sizePopup.selectItem(at: 1)
    panel.persistChoices()
    let before = screenOnly()
    // D3's baseline: a sentinel in the display key, and the key set.
    UserDefaults.standard.set(777, forKey: RecorderPanelController.displayKey)
    let keysBefore = recordingKeys()
    choose(voiceRow())
    out["D2"] = [
        "source": panel.currentChoice().source == .voiceOver, "selected": panel.voiceOverSelected,
        "before": before, "after": screenOnly(),
        "microphone": panel.microphonePopup.isEnabled, "rate": panel.ratePopup.isEnabled,
        "destination": panel.destinationPopup.isEnabled, "sourceEnabled": panel.sourcePopup.isEnabled,
        "sizeNote": panel.sizeNote.stringValue, "expectedNote": RecorderPanelController.voiceOverSizeNote,
    ]

    // D3 — session only: no key written for the row, and a rebuild keeps it.
    let displayAfter = UserDefaults.standard.integer(forKey: RecorderPanelController.displayKey)
    let keysAfter = recordingKeys()
    panel.rebuildSources()
    panel.restoreChoices()
    out["D3"] = [
        "display": displayAfter, "keysBefore": keysBefore, "keysAfter": keysAfter,
        "kept": panel.voiceOverSelected, "keptSource": panel.currentChoice().source == .voiceOver,
    ]

    // D4 — a display row brings the three back.
    choose(panel.sourcePopup.item(at: 0))
    let d4 = screenOnly()
    out["D4"] = [
        "display": panel.currentChoice().source == .display(panel.selectedDisplayID),
        "after": d4,
    ]

    // D5 — Microphone Only with Microphone Off.
    reset()
    choose(voiceRow())
    panel.microphonePopup.selectItem(at: 0)
    panel.record(nil)
    out["D5"] = [
        "phase": "\(panel.phase)", "note": panel.noteLabel.stringValue,
        "expected": RecorderPanelController.microphoneOffSentence,
        "screenReads": spy.screenReads, "screenRequests": spy.screenRequests,
        "micRequests": spy.micRequests, "opened": spy.opened,
    ]

    // D6 — a microphone chosen and authorized, the screen grant absent.
    reset()
    panel.microphonePopup.select(fake)
    panel.record(nil)
    out["D6"] = [
        "phase": "\(panel.phase)", "note": panel.noteLabel.stringValue,
        "screenReads": spy.screenReads, "screenRequests": spy.screenRequests,
        "micRequests": spy.micRequests, "opened": spy.opened,
    ]

    // D7 — the countdown runs out: the recorder's own refusal for that
    // choice (no device carries "probe-mic"), the panel idle again. A
    // countdown D6 did not reach is begun here, so the row reads the
    // countdown's END whatever the press did; its screen reads are its own.
    let readsBefore = spy.screenReads
    var begunHere = false
    if case .countdown = panel.phase {} else {
        reset()
        panel.microphonePopup.select(fake)
        panel.beginCountdown()
        begunHere = true
    }
    let choice = panel.currentChoice()
    _ = spin(6) { panel.phase == .idle }
    var expected = "unanswered"
    ScreenRecorder().startVoiceOver(choice: choice, mayAsk: true, onFinish: { _ in }) { error in
        expected = error?.localizedDescription ?? "nil"
    }
    out["D7"] = [
        "phase": "\(panel.phase)", "note": panel.noteLabel.stringValue, "expected": expected,
        "screenReads": spy.screenReads - readsBefore, "begunHere": begunHere,
        "recorderIdle": ScreenRecorder.shared.state == .idle, "hidden": panel.hiddenForRecording,
    ]
    reset()

    // D8 — which sources the panel hides for.
    out["D8"] = [
        "voiceOver": RecorderPanelController.hidesForRecording(.voiceOver),
        "camera": RecorderPanelController.hidesForRecording(.camera),
        "display": RecorderPanelController.hidesForRecording(.display(CGMainDisplayID())),
        "window": RecorderPanelController.hidesForRecording(.window(1)),
        "picked": RecorderPanelController.hidesForRecording(.picked),
    ]

    // D9 — the Pause / Resume button.
    reset()
    choose(voiceRow())
    let idleHidden = panel.voiceOverPauseButton.isHidden
    panel.phase = .recording
    let recording: [String: Any] = [
        "hidden": panel.voiceOverPauseButton.isHidden, "title": panel.voiceOverPauseButton.title,
    ]
    panel.phase = .paused
    let paused: [String: Any] = [
        "hidden": panel.voiceOverPauseButton.isHidden, "title": panel.voiceOverPauseButton.title,
    ]
    panel.phase = .idle
    choose(panel.sourcePopup.item(at: 0))
    panel.phase = .recording
    let displayHidden = panel.voiceOverPauseButton.isHidden
    panel.phase = .idle
    out["D9"] = [
        "idleHidden": idleHidden, "recording": recording, "paused": paused,
        "displayHidden": displayHidden,
    ]
    reset()

    // D10 — `record_screen`'s source reader.
    func kind(_ a: [String: Any]) -> String {
        do {
            return "ok: " + (try AgentServer.shared.recordingSourceKind(a)).rawValue
        } catch let error as AgentServer.ToolError {
            return "error: " + error.message
        } catch {
            return "other: \(error)"
        }
    }
    out["D10"] = [
        "empty": kind([:]), "screen": kind(["source": "screen"]), "x": kind(["source": "x"]),
        "display": kind(["source": "voice_over", "display": 0]),
        "all": kind([
            "source": "voice_over", "size": "best", "show_clicks": true, "system_audio": true,
            "window": 5, "display": 1,
        ]),
        "micFalse": kind(["source": "voice_over", "microphone": false]),
        "micTrue": kind(["source": "voice_over", "microphone": true]),
        "sizeNull": kind(["source": "voice_over", "size": NSNull()]),
        "displayNull": kind(["source": "voice_over", "display": NSNull()]),
    ]

    // D11 — what the tool's answer says for a voice-over.
    var c = RecordingChoice()
    c.source = .voiceOver
    let problem = "The microphone stopped recording on its own: It reported no error. "
        + "The voice-over ends where it stopped."
    let result = RecordingResult(
        segments: [
            RecordingSegment(
                descriptor: MediaDescriptor(path: "/nowhere/v.m4a", kind: .audio, duration: 600_000, hasAudio: true),
                micDescriptor: nil, micOffset: 0, startedAt: Date(), micProblem: problem)
        ], choice: c, stoppedBy: .stopped, pauses: 0)
    out["D11"] = [
        "note": AgentServer.microphoneNote(result) as Any, "problem": problem,
        "timeout": AgentServer.finishTimeoutSentence(movies: ["/nowhere/v.m4a"], voiceOver: true),
        "screenTimeout": AgentServer.finishTimeoutSentence(movies: ["/nowhere/v.mov"]),
    ]
    reset()
    return out
}

// ---- mode "exclusion": Include Frame Job windows (spec §11 recording.md; section 17) ----
/// Its own process, with the six older keys pinned in the argument domain
/// and the seventh NOT pinned — it is the key under test — and removed from
/// `UserDefaults.standard` before and after the rows.
func exclusionMode(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    // X1 — `RecordingExclusion.make`, pure.
    let cases = request["cases"] as? [[String: Any]] ?? []
    out["x1"] = cases.map { row -> [String: Any] in
        let include = row["include"] as? Bool ?? false
        let bundle = row["bundle"] as? String
        let panelID = (row["panel"] as? Int).map { CGWindowID($0) }
        let made = RecordingExclusion.make(
            includeFrameJobWindows: include, ownBundleID: bundle, panelWindowID: panelID)
        return ["tag": row["tag"] as? String ?? "", "bundleIDs": made.bundleIDs,
                "windowIDs": made.windowIDs.map { Int($0) }]
    }

    // X2 — the checkbox, persisted and restored.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
    ], forName: UserDefaults.argumentDomain)
    let key = RecorderPanelController.includeFrameJobWindowsKey
    UserDefaults.standard.removeObject(forKey: key)
    let panel = RecorderPanelController.shared
    let box = panel.includeFrameJobCheckbox
    panel.restoreChoices()
    var x2: [String: Any] = [:]
    x2["key"] = key
    x2["absent"] = UserDefaults.standard.object(forKey: key) == nil
    x2["offWhenAbsent"] = box.state == .off
    x2["choiceOffWhenAbsent"] = panel.currentChoice().includeFrameJobWindows == false
    x2["title"] = box.title
    x2["targetIsPanel"] = box.target === panel
    x2["action"] = box.action.map { NSStringFromSelector($0) } ?? ""
    x2["inWindow"] = box.window === panel.window
    box.state = .on
    panel.controlChanged(box)
    x2["keyAfterOn"] = UserDefaults.standard.object(forKey: key) as? Bool as Any
    x2["choiceAfterOn"] = panel.currentChoice().includeFrameJobWindows
    box.state = .off
    panel.restoreChoices()
    x2["restoredOn"] = box.state == .on
    out["x2"] = x2

    // X3 — locked with the other controls while anything is in flight. The
    // phases are written by the probe and put back to idle.
    var x3: [String: Any] = [:]
    panel.phase = .countdown(3)
    x3["countdown"] = box.isEnabled
    panel.phase = .recording
    x3["recording"] = box.isEnabled
    panel.phase = .idle
    x3["idle"] = box.isEnabled
    out["x3"] = x3

    box.state = .off
    UserDefaults.standard.removeObject(forKey: key)
    out["removedAfter"] = UserDefaults.standard.object(forKey: key) == nil
    return out
}

// ---- dispatch -------------------------------------------------------------
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: probe <request.json> <answer.json>\n".utf8))
    exit(2)
}
// Sealed before any mode runs: no mode can prompt, open System Settings or
// touch `FrameJobScreenRecordingAsked` (section 10's rows put spies in).
RecorderPanelController.grantDoors = sealedDoors()
var answer: [String: Any] = [:]
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let mode = request["mode"] as? String ?? ""
    switch mode {
    case "files":
        answer = files(request)
    case "configuration":
        answer = configuration(request)
    case "state":
        answer = state(request)
    case "landing":
        answer = landing(request)
    case "segments":
        answer = segments(request)
    case "leftout":
        answer = leftout(request)
    case "chrome":
        answer = chrome(request)
    case "chrome-pause":
        answer = chromePause(request)
    case "unreadable":
        answer = unreadableMode(request)
    case "file-pause":
        answer = filePause(request)
    case "granted":
        answer = granted(request)
    case "welcome":
        answer = welcome(request)
    case "catalog":
        answer = catalog(request)
    case "host":
        answer = host(request)
    case "grants":
        answer = grants(request)
    case "preroll":
        answer = preroll(request)
    case "voiceover":
        answer = voiceover(request)
    case "voiceover-granted":
        answer = voiceoverGranted(request)
    case "voiceover-doors":
        answer = voiceoverDoors(request)
    case "exclusion":
        answer = exclusionMode(request)
    default:
        answer["error"] = "unknown mode \"\(mode)\" — the binary predates the section asking"
    }
    answer["mode"] = mode
} catch {
    answer["error"] = "\(error)"
}
let out = try JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
try out.write(to: URL(fileURLWithPath: args[2]))
'''


def probe_dir(sources):
    """The tree's probe lives at `work/recordingprobe/tree/`; a mutant copy
    gets its own directory named by a digest of its path, so pointing the
    script at a copy never invalidates — or, worse, reuses — the tree's
    cached binary."""
    if os.path.realpath(sources) == os.path.realpath(TREE_SOURCES):
        return os.path.join(PROBE, "tree")
    digest = hashlib.sha1(os.path.realpath(sources).encode()).hexdigest()[:10]
    return os.path.join(PROBE, f"mutant-{digest}")


def build_probe(sources):
    """`remaining_probe.py`'s builder: `swift_build.build` (reused when every
    input is byte-identical to a cached build's), and a reason instead of an
    exit when it will not build."""
    here = probe_dir(sources)
    os.makedirs(here, exist_ok=True)
    binary = os.path.join(here, "recordingprobe")
    entry = os.path.join(here, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    if not os.path.isdir(sources):
        return None, f"{sources} is not a directory"
    files = sorted(
        os.path.join(sources, name)
        for name in os.listdir(sources)
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=files + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if built.reused:
        print(f"recording probe: {binary} (up to date)")
    else:
        print(f"recording probe: {binary} (built in {built.seconds:.1f} s from {sources})")
    return binary, None


def run_probe(binary, tag, request, timeout=120):
    """One request in, one answer out, both kept beside the binary under
    the section's tag so a failed row can be read back after the run."""
    here = os.path.dirname(binary)
    req = os.path.join(here, f"request-{tag}.json")
    out = os.path.join(here, f"answer-{tag}.json")
    with open(req, "w") as f:
        json.dump(request, f, indent=1)
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run([binary, req, out], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, f"the probe did not answer within {timeout} s"
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


def fresh_dir(*parts):
    path = os.path.join(FILES, *parts)
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    return path


# --------------------------------------------------------------------------
# Section 1 — RecordingFiles.

# Two dates: one ordinary, one at a single-digit hour, minute and second, so
# the zero padding in `HH.mm.ss` is pinned. Both are spelled in LOCAL time
# on both sides — `stem(at:)` formats in `TimeZone.current`, and
# `time.localtime` is the same zone — so the expectation is built from the
# same clock the app names its files by.
STEM_DATES = [
    time.mktime((2026, 9, 10, 14, 3, 22, 0, 0, -1)),
    time.mktime((2026, 1, 2, 3, 5, 7, 0, 0, -1)),
]


def expected_stem(seconds):
    return time.strftime("Screen Recording %Y-%m-%d at %H.%M.%S", time.localtime(seconds))


def section_files(binary, sources):
    print("\nSection 1 — RecordingFiles: the folder, the name, the collision rule")
    unique = fresh_dir("unique")
    for name in ("X.mov", "X (2).mov", "Z.mov", "Z (Microphone).m4a"):
        with open(os.path.join(unique, name), "wb") as f:
            f.write(b"\0")
    created_root = os.path.join(FILES, "created")
    shutil.rmtree(created_root, ignore_errors=True)
    created = os.path.join(created_root, "nested", "deep")
    override = "~/rc-probe-recordings"
    answer, error = run_probe(binary, "files", {
        "mode": "files", "override": override, "stemDates": STEM_DATES,
        "uniqueFolder": unique, "createFolder": created})
    check("1: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    check("1a: folder() reads `-RCRecordingFolder` from the argument domain, tilde-expanded "
          "(`FFmpegRewrap`'s `-RCFFmpegPath` shape)",
          answer.get("folderPinned") == os.path.expanduser(override),
          f"got {answer.get('folderPinned')!r}")
    check("1a: the key is spelled `RCRecordingFolder`",
          answer.get("keyRead") == "RCRecordingFolder", f"got {answer.get('keyRead')!r}")
    default = os.path.expanduser("~/Movies/Frame Job Recordings")
    check("1a: folder() without the override is `~/Movies/Frame Job Recordings` (decision 2)",
          answer.get("folderDefault") == default, f"got {answer.get('folderDefault')!r}")
    check("1a: RecordingChoice().folder defaults to folder()",
          answer.get("choiceFolder") == default, f"got {answer.get('choiceFolder')!r}")
    stems = {round(s.get("seconds", 0)): s.get("stem") for s in answer.get("stems", [])}
    for seconds in STEM_DATES:
        want = expected_stem(seconds)
        got = stems.get(round(seconds))
        check(f"1b: stem(at:) → {want!r} (the Screenshot app's spelling, local time)",
              got == want, f"got {got!r}")
    check("1c: uniqueURL over `X.mov` + `X (2).mov` → `X (3).mov`",
          answer.get("uniqueX") == os.path.join(unique, "X (3).mov"),
          f"got {answer.get('uniqueX')!r}")
    check("1c: uniqueURL of a free stem is the plain name",
          answer.get("uniqueFree") == os.path.join(unique, "Y.mov"),
          f"got {answer.get('uniqueFree')!r}")
    check("1d: microphoneURL(beside: X.mov) → `X (Microphone).m4a`",
          answer.get("micBeside") == os.path.join(unique, "X (Microphone).m4a"),
          f"got {answer.get('micBeside')!r}")
    check("1d: microphoneURL(beside: Z.mov) with `Z (Microphone).m4a` taken → "
          "`Z (Microphone) (2).m4a` (the same collision rule)",
          answer.get("micBesideTaken") == os.path.join(unique, "Z (Microphone) (2).m4a"),
          f"got {answer.get('micBesideTaken')!r}")
    check("1e: create() makes a nested folder", answer.get("created") is True,
          f"got {answer.get('created')!r}")
    check("1e: … and it is a directory on disk",
          answer.get("createdIsDirectory") is True and os.path.isdir(created))
    check("1e: create() of an existing folder is not an error",
          answer.get("createdAgain") is True, f"got {answer.get('createdAgain')!r}")
    defaults = answer.get("choiceDefaults") or {}
    for key, want in [("rate", 60), ("systemAudio", True), ("showClicks", False),
                      ("resolution", "nominal"), ("microphone", None), ("newProject", True),
                      ("mainDisplay", True), ("includeFrameJobWindows", False)]:
        check(f"1f: RecordingChoice() default {key} = {want!r}", defaults.get(key) == want,
              f"got {defaults.get(key)!r}")


# --------------------------------------------------------------------------
# Section 2 — RecordingConfiguration.make, sixteen rows.

DISPLAY_POINTS = [1728.0, 1117.0]
SCALE = 2.0
OUTPUT_URL = "/tmp/recording-probe/Screen Recording.mov"
BGRA = 1111970369      # kCVPixelFormatType_32BGRA, 'BGRA'
DEFAULT_420V = 875704438  # a fresh SCStreamConfiguration's pixelFormat, '420v' (R0 q6a)
# SCCaptureResolutionType: automatic 0, best 1, nominal 2 (SCStream.h:77–80).
RESOLUTION_RAW = {"nominal": 2, "best": 1}

CONFIGURATION_ROWS = [
    {"rate": rate, "resolution": resolution, "systemAudio": audio, "showClicks": clicks}
    for rate, resolution, audio, clicks in itertools.product(
        [30, 60], ["nominal", "best"], [False, True], [False, True])
]


def expected_configuration(row, available):
    factor = SCALE if row["resolution"] == "best" else 1
    return {
        "width": int(round(DISPLAY_POINTS[0] * factor)),
        "height": int(round(DISPLAY_POINTS[1] * factor)),
        "minimumFrameInterval": [1, row["rate"]],
        "showsCursor": True,
        "showMouseClicks": row["showClicks"],
        "pixelFormat": BGRA if row["showClicks"] else DEFAULT_420V,
        "capturesAudio": row["systemAudio"],
        "sampleRate": 48000,
        "channelCount": 2,
        "excludesCurrentProcessAudio": True,
        "captureMicrophone": False,
        "captureResolution": RESOLUTION_RAW[row["resolution"]],
        "videoCodecType": "hvc1" if "hvc1" in available else "avc1",
        "outputFileType": "com.apple.quicktime-movie",
        "outputURL": OUTPUT_URL,
    }


def section_configuration(binary, sources):
    print("\nSection 2 — RecordingConfiguration.make read back, 16 rows × 15 fields")
    answer, error = run_probe(binary, "configuration", {
        "mode": "configuration", "displayPointSize": DISPLAY_POINTS, "scale": SCALE,
        "outputURL": OUTPUT_URL, "rows": CONFIGURATION_ROWS})
    check("2: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    check(f"2: a fresh SCStreamConfiguration reads `420v` ({DEFAULT_420V}) — the default the "
          "clicks-off rows keep (R0 q6a)",
          answer.get("freshPixelFormat") == DEFAULT_420V, f"got {answer.get('freshPixelFormat')!r}")
    keys = ["rate", "resolution", "systemAudio", "showClicks"]
    by = {tuple(a.get(k) for k in keys): a for a in answer.get("rows", [])}
    available = None
    for row in CONFIGURATION_ROWS:
        got = by.get(tuple(row[k] for k in keys), {})
        spelled = (f"{row['rate']} fps {row['resolution']} audio={'on' if row['systemAudio'] else 'off'} "
                   f"clicks={'on' if row['showClicks'] else 'off'}")
        if available is None:
            available = got.get("availableVideoCodecTypes") or []
            print(f"  host: availableVideoCodecTypes = {available}")
        want = expected_configuration(row, got.get("availableVideoCodecTypes") or [])
        for field, value in want.items():
            check(f"2 [{spelled}] {field} → {value!r}", got.get(field) == value,
                  f"got {got.get(field)!r}")


# --------------------------------------------------------------------------
# Section 3 — the state machine's fresh-instance face, and the grants' words.

LINEAR_ROWS = [
    {"dB": -20.0, "expect": 0.1, "why": "−20 dB is a tenth of full scale"},
    {"dB": 0.0, "expect": 1.0, "why": "0 dB is full scale"},
    {"dB": 6.0, "expect": 1.0, "why": "clamped: nothing above full scale reaches the bar"},
    {"dB": -60.0, "expect": 0.001},
]


def section_state(binary, sources):
    print("\nSection 3 — a fresh ScreenRecorder(), no framework call; the grants' sentences; the "
          "machine driven through a faked session")
    answer, error = run_probe(binary, "state", {
        "mode": "state", "decibels": [row["dB"] for row in LINEAR_ROWS]})
    check("3: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    host = answer.get("host") or {}
    print(f"  host: CGPreflightScreenCaptureAccess() = {host.get('screenRecordingGranted')}, "
          f"microphone status = {host.get('microphoneStatus')}, "
          f"bundleIdentifier = {host.get('bundleIdentifier')} (facts, not asserted)")
    check("3a: a fresh recorder is idle", answer.get("initialState") == "idle",
          f"got {answer.get('initialState')!r}")
    check("3a: isRecording is false while idle", answer.get("isRecording") is False)
    check("3a: elapsed is 0 while idle", answer.get("elapsed") == 0, f"got {answer.get('elapsed')!r}")
    check("3a: the meter is the recorder's own, not LevelMeter.shared",
          answer.get("meterIsOwn") is True)
    check("3b: stop() while idle completes with RecorderError.notRecording",
          answer.get("stopWhileIdle") == "notRecording", f"got {answer.get('stopWhileIdle')!r}")
    check("3b: … and leaves the recorder idle", answer.get("stateAfterStop") == "idle",
          f"got {answer.get('stateAfterStop')!r}")
    check("3b: … with elapsed still 0", answer.get("elapsedAfterStop") == 0)
    check("3b: a second stop() answers the same",
          answer.get("stopWhileIdleAgain") == "notRecording",
          f"got {answer.get('stopWhileIdleAgain')!r}")
    check("3b: stop() with no completion (the panel's spelling) is accepted while idle and "
          "leaves it idle", answer.get("stateAfterBareStop") == "idle",
          f"got {answer.get('stateAfterBareStop')!r}")
    check("3c: addObserver fires once on subscription (the meter's contract, pinned so the "
          "next row means what it says)", answer.get("meterCallsOnSubscribe") == 1,
          f"got {answer.get('meterCallsOnSubscribe')!r}")
    check("3c: publishMicrophoneLevel() while idle publishes NOTHING",
          answer.get("meterPublishesFromIdle") == 0,
          f"got {answer.get('meterPublishesFromIdle')!r}")
    check("3c: … and the meter reads silent", answer.get("meterReadingIsSilent") is True)
    refusal = answer.get("micRefusal") or {}
    for word in ("notDetermined", "denied", "restricted"):
        text = refusal.get(word) or ""
        check(f"3d: microphoneRefusal(.{word}) names the status word",
              f"(status: {word})" in text, f"got {text!r}")
    check("3d: microphoneRefusal(.notDetermined) says where the grant is asked for "
          "(Record in File ▸ New Recording…)",
          "File ▸ New Recording…" in (refusal.get("notDetermined") or ""),
          f"got {refusal.get('notDetermined')!r}")
    check("3d: microphoneRefusal(.denied) names System Settings ▸ Privacy & Security ▸ Microphone",
          "System Settings ▸ Privacy & Security ▸ Microphone" in (refusal.get("denied") or ""),
          f"got {refusal.get('denied')!r}")
    screen = answer.get("screenRefusal") or ""
    check("3d: screenRecordingRefusal names the pane and says to relaunch",
          "Screen & System Audio Recording" in screen and "relaunch" in screen, f"got {screen!r}")
    errors = answer.get("errors") or {}
    check("3e: RecorderError.startFailed(why) describes as `why`",
          errors.get("startFailed") == "why", f"got {errors.get('startFailed')!r}")
    check("3e: RecorderError.timedOut names the 10 s ceiling",
          "10 s" in (errors.get("timedOut") or ""), f"got {errors.get('timedOut')!r}")
    check("3e: busy and notRecording read as sentences",
          (errors.get("busy") or "").endswith(".") and (errors.get("notRecording") or "").endswith("."),
          f"got {errors.get('busy')!r}, {errors.get('notRecording')!r}")
    linear = [{"dB": r.get("dB"), "linear": round(r.get("linear", -1), 6)}
              for r in answer.get("linear", [])]
    check_table("3f: RecordingMeter.linear", LINEAR_ROWS, linear, ["dB"], "linear")
    check("3f: linear(−∞) is 0", answer.get("linearOfNegativeInfinity") == 0,
          f"got {answer.get('linearOfNegativeInfinity')!r}")
    check("3f: linear(NaN) is 0 (a non-finite reading is silence)",
          answer.get("linearOfNaN") == 0, f"got {answer.get('linearOfNaN')!r}")

    # The R1 review's fixes (lane R): the two ceilings' sentences, the launch
    # clause, and the machine driven through a faked session.
    start_timed_out = errors.get("startTimedOut") or ""
    timed_out = errors.get("timedOut") or ""
    check("3g: RecorderError.startTimedOut names the ARM ceiling — 'start' and '20 s' (finding 5)",
          "start" in start_timed_out and "20 s" in start_timed_out, f"got {start_timed_out!r}")
    check("3g: … and the two timeout sentences differ, timedOut naming 'writing' and '10 s'",
          start_timed_out != timed_out and "writing" in timed_out and "10 s" in timed_out,
          f"got {start_timed_out!r} / {timed_out!r}")
    check("3g: filesKept appends ' The recording is at <movie>; the microphone at <mic>.' to the "
          "inner sentence (finding 6)",
          errors.get("filesKept") == timed_out + " The recording is at /m/a.mov; the microphone "
          "at /m/a (Microphone).m4a.", f"got {errors.get('filesKept')!r}")
    check("3g: … and names the movie alone when no microphone file exists",
          errors.get("filesKeptAlone") == "why. The recording is at /m/a.mov.",
          f"got {errors.get('filesKeptAlone')!r}")
    check("3g: RecorderError.notPaused reads 'The recording is not paused.' (R2)",
          errors.get("notPaused") == "The recording is not paused.", f"got {errors.get('notPaused')!r}")
    check("3g: filesKept over two movies and two microphone files keeps its shape with each list "
          "comma-joined — ' The recording is at /m/a.mov, /m/b.mov; the microphone at /m/x.m4a, "
          "/m/y.m4a.' (R2)",
          errors.get("filesKeptTwo") == timed_out + " The recording is at /m/a.mov, /m/b.mov; the "
          "microphone at /m/x.m4a, /m/y.m4a.", f"got {errors.get('filesKeptTwo')!r}")

    ppid = answer.get("ppid")
    pane = answer.get("screenPane") or ""
    clause = answer.get("launchClause") or ""
    check("3h: the probe is launched by another process (getppid() != 1) — the precondition "
          "of the launch clause", isinstance(ppid, int) and ppid != 1, f"got {ppid!r}")
    check("3h: launchClause names the launching process by pid and the two ways out",
          f"launched by another process (pid {ppid})" in clause and "the terminal's" in clause
          and 'open -a "Frame Job"' in clause, f"got {clause!r}")
    check("3h: screenRecordingRefusal is the pane sentence + the clause — the pane sentence its "
          "PREFIX, so recording_proof.py's match holds",
          bool(clause) and screen == pane + clause and screen.startswith(pane)
          and pane.endswith("then relaunch."), f"got {screen!r}")
    for word in ("notDetermined", "denied", "restricted"):
        text = refusal.get(word) or ""
        check(f"3h: microphoneRefusal(.{word}) keeps its head and ends with the clause",
              text.startswith(f"The microphone is not granted to Frame Job (status: {word}). ")
              and text.endswith(clause) and len(text) > len(clause), f"got {text!r}")

    section_state_driven(binary, sources)


def section_state_driven(binary, sources):
    """The machine past `start`, driven through a faked `Session` — a second
    request so a fake that will not build fails these rows alone."""
    work = fresh_dir("state")
    answer, error = run_probe(binary, "state-drive", {"mode": "state", "drive": True, "work": work})
    check("3i: the driven probe answers — SCContentFilter(), SCStream and SCRecordingOutput "
          "construct with no grant and stopCapture on a never-started stream returns",
          answer is not None and not answer.get("error"), error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return

    join = answer.get("join") or {}
    check("3i: the PNG 'movie' was written", join.get("pngWritten") is True)
    check("3i: the meter was lit before the stop (the precondition of the next row)",
          join.get("meterLitBefore") is True)
    check("3i: stop() while recording → .finishing", join.get("stateAfterStop") == "finishing",
          f"got {join.get('stateAfterStop')!r}")
    check("3i: … and the meter goes silent AT beginFinishing, not at settle (finding 8)",
          join.get("meterSilentAfterStop") is True)
    check("3i: a second stop() while .finishing is REGISTERED — answered nothing at once, "
          "never .busy (finding 1)", join.get("secondStopAnsweredAtOnce") == 0
          and join.get("stateAfterSecondStop") == "finishing",
          f"answered {join.get('secondStopAnsweredAtOnce')!r}, "
          f"state {join.get('stateAfterSecondStop')!r}")
    check("3i: the finishing wait holds through stopCapture's completion and the screen's "
          "did-finish while the microphone's did-finish is outstanding (finding 0: always waited "
          "for)", join.get("stateAfterStopCapture") == "finishing"
          and join.get("stateAfterScreenFinish") == "finishing",
          f"got {join.get('stateAfterStopCapture')!r} then {join.get('stateAfterScreenFinish')!r}")
    check("3i: the microphone's did-finish lets it settle to idle", join.get("settled") is True)
    check("3i: onFinish was called EXACTLY once", join.get("onFinishCount") == 1,
          f"got {join.get('onFinishCount')!r}")
    check("3i: the first stop's completion was called exactly once", join.get("firstStopCount") == 1,
          f"got {join.get('firstStopCount')!r}")
    check("3i: the joined stop's completion was called exactly once, with the outcome and not "
          ".busy", join.get("secondStopCount") == 1
          and (join.get("secondStop") or {}).get("kind") == "success",
          f"count {join.get('secondStopCount')!r}, got {join.get('secondStop')!r}")
    on_finish = join.get("onFinish") or {}
    check("3i: all three received the ONE outcome", on_finish == join.get("firstStop") == join.get("secondStop")
          and on_finish.get("kind") == "success", f"got {on_finish!r}")
    check("3i: a microphone that never started (no did-start, an absent file) is a .success with "
          "micDescriptor nil and micProblem saying so (finding 0)",
          on_finish.get("micDescriptor") is False
          and on_finish.get("micProblem") == "The microphone never started recording, so the "
          "picture was recorded without it.", f"got {on_finish!r}")
    check("3i: microphoneProblem is nil again once idle", join.get("microphoneProblemAfter") is None,
          f"got {join.get('microphoneProblemAfter')!r}")
    check("3i: a stop() after the conclude is .notRecording — the joined completions were "
          "drained, not kept", (join.get("stopAfterConclude") or {}).get("case") == "notRecording",
          f"got {join.get('stopAfterConclude')!r}")

    once = answer.get("oneShot") or {}
    check("3j: settle() sets the settling flag before its probe is queued and stays .finishing",
          once.get("settlingAfterSettle") is True and once.get("stateAfterSettle") == "finishing",
          f"got {once.get('settlingAfterSettle')!r}, {once.get('stateAfterSettle')!r}")
    check("3j: … and concludes", once.get("settled") is True)
    check("3j: a checkFinished() and a duplicate did-finish DURING the probe change nothing — "
          "onFinish once (finding 2, the measured double conclude)",
          once.get("onFinishCount") == 1 and once.get("firstStopCount") == 1,
          f"onFinish {once.get('onFinishCount')!r}, stop {once.get('firstStopCount')!r}")
    check("3j: … with a success", (once.get("onFinish") or {}).get("kind") == "success",
          f"got {once.get('onFinish')!r}")

    dies = answer.get("micDies") or {}
    live = dies.get("microphoneProblemLive")
    check("3k: a microphone did-finish carrying an error while .recording leaves the state "
          ".recording (finding 3: the picture records on)", dies.get("stateAfterMicFailure") == "recording",
          f"got {dies.get('stateAfterMicFailure')!r}")
    check("3k: … sets microphoneProblem at once, with the writer's sentence",
          live == "The microphone recording failed: The device was disconnected.", f"got {live!r}")
    check("3k: … and publishes silence to the meter, which a later poll does not relight",
          dies.get("meterSilentAfterMicFailure") is True and dies.get("meterSilentAfterPoll") is True,
          f"got {dies.get('meterSilentAfterMicFailure')!r}, {dies.get('meterSilentAfterPoll')!r}")
    check("3k: stop then lands", dies.get("settled") is True)
    landed = dies.get("onFinish") or {}
    check("3k: … as a .success with micDescriptor nil (finding 0: the movie is probed FIRST and "
          "the microphone cannot fail it)", landed.get("kind") == "success"
          and landed.get("micDescriptor") is False, f"got {landed!r}")
    check("3k: … whose micProblem is the writer's sentence naming the file it left",
          landed.get("micProblem") == "The microphone recording failed: The device was "
          f"disconnected. What it wrote is at {dies.get('micPath')}.",
          f"got {landed.get('micProblem')!r}")
    check("3k: onFinish once, the stop's completion once",
          dies.get("onFinishCount") == 1 and dies.get("firstStopCount") == 1)
    check("3k: microphoneProblem is nil again once idle", dies.get("microphoneProblemAfter") is None)

    path = answer.get("path") or {}
    failed = path.get("onFinish") or {}
    check("3l: an unreadable movie past beginFinishing is a failure that names BOTH files "
          "(finding 6)", failed.get("kind") == "failure"
          and failed.get("case") == "filesKept(finishFailed)"
          and (failed.get("description") or "").startswith("The recording could not be read: ")
          and (failed.get("description") or "").endswith(
              f" The recording is at {path.get('moviePath')}; the microphone at {path.get('micPath')}."),
          f"got {failed!r}")
    check("3l: … delivered identically to the stop's completion", path.get("firstStop") == failed)
    alone = path.get("aloneOnFinish") or {}
    check("3l: with no microphone file the movie alone is named",
          alone.get("case") == "filesKept(finishFailed)"
          and (alone.get("description") or "").endswith(f" The recording is at {path.get('alonePath')}.")
          and "microphone" not in (alone.get("description") or ""), f"got {alone!r}")

    ext = answer.get("external") or {}
    check("3m: a did-finish nobody asked for begins finishing as .stopped",
          ext.get("stateAfterUnaskedFinish") == "finishing" and ext.get("stoppedByBefore") == "stopped",
          f"got {ext.get('stateAfterUnaskedFinish')!r}, {ext.get('stoppedByBefore')!r}")
    check("3m: didStopWithError(.userStopped) arriving AFTER it is adopted (finding 7)",
          ext.get("stoppedByAfter") == "userStopped", f"got {ext.get('stoppedByAfter')!r}")
    check("3m: … and the result says userStopped", ext.get("settled") is True
          and (ext.get("onFinish") or {}).get("stoppedBy") == "userStopped",
          f"got {ext.get('onFinish')!r}")
    check("3m: a stop() that ENDED the recording keeps .stopped whatever the stream says next",
          ext.get("askedStoppedBy") == "stopped" and ext.get("askedSettled") is True
          and (ext.get("askedOnFinish") or {}).get("stoppedBy") == "stopped",
          f"got {ext.get('askedStoppedBy')!r}, {ext.get('askedOnFinish')!r}")

    faces = answer.get("idleFaces") or {}
    for key, label in (("afterNil", "prepareMicrophone(nil)"),
                       ("afterUnknown", "prepareMicrophone(<an unknown id>)"),
                       ("afterDiscard", "discardPreparedMicrophone() with nothing prepared")):
        got = faces.get(key) or {}
        check(f"3n: {label} is a no-op — idle, nothing prepared",
              got.get("state") == "idle" and got.get("prepared") is False, f"got {got!r}")
    arming = faces.get("arming") or {}
    check("3n: two stop()s while .arming are both held — registered 2, answered 0, pendingStop, "
          "stopAsked, still arming (no .busy)",
          arming.get("state") == "arming" and arming.get("pendingStop") is True
          and arming.get("registered") == 2 and arming.get("answered") == 0
          and arming.get("stopAsked") is True, f"got {arming!r}")

    section_state_r2(answer)


def section_state_r2(answer):
    """Road map 3, R2a over the faked session: the pause, the resume, the
    two refusals, a closed segment's failure, an external stop while paused,
    and the walker over three segments."""
    print("  3o — pause() and resume() over the faked session (R2a)")
    p = answer.get("pause") or {}
    paths = p.get("paths") or ["", "", "", ""]
    s0p = p.get("segment0AfterPause") or {}
    check("3o: the fixtures were written and the segment's output was ADDED to the never-started, "
          "grant-less stream (R1's pre-startCapture order; the R2 probe measured the pair works there)",
          p.get("written") is True and p.get("attached") == "ok", f"{p.get('attached')!r}")
    check("3o: elapsed before the pause is about a second (the did-start stamp is 1 s back)",
          0.9 <= p.get("elapsedBefore", 0) <= 1.6, f"got {p.get('elapsedBefore')}")
    check("3o: pause() while .recording returns without throwing", p.get("pause") == "ok",
          f"got {p.get('pause')!r}")
    check("3o: … → .paused, isPaused, and STILL isRecording (File ▸ Stop Recording, the quit guard "
          "and .busy read a paused recording as one in progress)",
          p.get("stateAfterPause") == "paused" and p.get("isPaused") is True
          and p.get("isRecordingWhilePaused") is True,
          f"{p.get('stateAfterPause')!r}, isPaused {p.get('isPaused')}, isRecording "
          f"{p.get('isRecordingWhilePaused')}")
    check("3o: … the segment's stoppedAt is stamped and its did-finish is not yet in",
          s0p.get("stoppedAt") is not None and s0p.get("screenFinished") is False, f"{s0p}")
    check("3o: … the meter goes silent AT the pause", p.get("meterSilentAfterPause") is True)
    check("3o: … and the microphone's writer was asked to stop exactly once (pause-no-mic-stop)",
          p.get("micStopsAfterPause") == 1, f"got {p.get('micStopsAfterPause')}")
    check("3o: elapsed read twice 0.3 s apart while paused is EQUAL — frozen, and about the second "
          "recorded (elapsed-through-pause)",
          p.get("elapsedA") == p.get("elapsedB") and 0.9 <= (p.get("elapsedA") or 0) <= 1.6,
          f"{p.get('elapsedA')} then {p.get('elapsedB')}")
    check("3o: publishMicrophoneLevel() while paused publishes NOTHING — a meter lit by hand stays "
          "as it was", p.get("meterLitAfterPollWhilePaused") is True)
    check("3o: a second pause() throws .alreadyPaused by name — its own sentence, since 'no recording "
          "is in progress' would be false while isRecording is true (the R2 review)",
          (p.get("pauseAgain") or "").startswith("alreadyPaused: The recording is already paused."),
          f"got {p.get('pauseAgain')!r}")
    check("3o: resume() while .paused returns without throwing → .recording with TWO segments "
          "(resume-no-segment)",
          p.get("resume") == "ok" and p.get("stateAfterResume") == "recording"
          and p.get("segmentsAfterResume") == 2,
          f"{p.get('resume')!r}, {p.get('stateAfterResume')!r}, {p.get('segmentsAfterResume')}")
    s1 = p.get("segment1AfterResume") or {}
    movie1 = s1.get("movie") or ""
    check("3o: the new segment's movie is minted in the choice's folder as `Screen Recording <date> "
          "at <time>.mov` — ITS OWN start time through uniqueURL (decision 6), not the first's name",
          os.path.dirname(movie1) == p.get("folder")
          and re.fullmatch(STEM_RE + r"( \(\d+\))?\.mov", os.path.basename(movie1)) is not None
          and movie1 != paths[0], f"got {movie1!r}")
    check("3o: … its microphone file beside it, ` (Microphone).m4a`",
          s1.get("mic") == os.path.splitext(movie1)[0] + " (Microphone).m4a", f"got {s1.get('mic')!r}")
    check("3o: … micRecordingCalledAt stamped where the call is made; no did-start yet, nothing "
          "finished, no stoppedAt",
          s1.get("micCalled") is True and s1.get("screenStartedAt") is None
          and s1.get("micStartedAt") is None and s1.get("stoppedAt") is None
          and s1.get("screenFinished") is False and s1.get("micFinished") is False, f"{s1}")
    check("3o: … and the ONE writer was restarted to exactly that file (startRecording once, the new "
          "mic path)", p.get("micStartsAfterResume") == [s1.get("mic")],
          f"got {p.get('micStartsAfterResume')}")
    s0r = p.get("segment0AfterResume") or {}
    check("3o: the closed segment is untouched by the resume — still stamped, still unfinished",
          s0r.get("stoppedAt") == s0p.get("stoppedAt") and s0r.get("screenFinished") is False, f"{s0r}")
    check("3o: elapsed grows again after the resume",
          p.get("elapsedD", 0) > p.get("elapsedC", 0) >= p.get("elapsedB", 0),
          f"B {p.get('elapsedB')}, C {p.get('elapsedC')}, D {p.get('elapsedD')}")
    late0 = p.get("segment0AfterLateFinish") or {}
    late1 = p.get("segment1AfterLateFinish") or {}
    check("3o: the closed segment's did-finish and its mic's did-finish landing AFTER the resume are "
          "INERT — the state stays .recording and only ITS flags move (R0 q7: 5–25 ms after the "
          "remove; the resume never waits)",
          p.get("stateAfterLateFinish") == "recording" and late0.get("screenFinished") is True
          and late0.get("micFinished") is True and late1.get("screenFinished") is False
          and late1.get("micFinished") is False,
          f"state {p.get('stateAfterLateFinish')!r}, 0 {late0}, 1 {late1}")
    s1s = p.get("segment1Stamped") or {}
    s0s = p.get("segment0Stamped") or {}
    check("3o: the new output's did-start (found by identity) and the mic's did-start for the NEW "
          "file (found by URL) stamp segment 1",
          s1s.get("screenStartedAt") is not None and s1s.get("micStartedAt") is not None, f"{s1s}")
    check("3o: … and leave segment 0's stamps where they were",
          s0s.get("screenStartedAt") == s0p.get("screenStartedAt")
          and s0s.get("micStartedAt") == s0p.get("micStartedAt"), f"{s0s} vs {s0p}")
    stray = p.get("segment1AfterStray") or {}
    check("3o: a did-finish for an output of NO segment and a mic did-finish for a file no segment "
          "asked for change nothing",
          p.get("stateAfterStray") == "recording" and p.get("segmentsAfterStray") == 2
          and stray.get("screenFinished") is False and stray.get("micFinished") is False,
          f"state {p.get('stateAfterStray')!r}, {stray}")
    check("3o: resume() while .recording throws .notPaused by name",
          (p.get("resumeWhileRecording") or "").startswith("notPaused: "),
          f"got {p.get('resumeWhileRecording')!r}")
    check("3o: a second pause() closes segment 1 — .paused, the writer asked to stop a second time",
          p.get("secondPause") == "ok" and p.get("stateAfterSecondPause") == "paused"
          and p.get("micStopsAfterSecondPause") == 2,
          f"{p.get('secondPause')!r}, {p.get('stateAfterSecondPause')!r}, stops "
          f"{p.get('micStopsAfterSecondPause')}")
    check("3o: elapsed at the second pause is the two recorded spans — the first's second plus the "
          "second's, measured from its DRIVEN did-start stamp (about 0.4 s before the pause), never "
          "from the add and never the gap",
          1.25 <= p.get("elapsedAtSecondPause", 0) <= 1.95, f"got {p.get('elapsedAtSecondPause')}")
    check("3o: stop() while PAUSED begins finishing as .stopped",
          p.get("stateAfterStop") == "finishing" and p.get("stoppedBy") == "stopped",
          f"{p.get('stateAfterStop')!r}, {p.get('stoppedBy')!r}")
    check("3o: … with the segment's stoppedAt KEPT from the pause and NO second stopRecording — "
          "the pause did both, only stopCapture remains",
          p.get("stoppedAtKept") is True and p.get("micStopsAfterStop") == 2,
          f"kept {p.get('stoppedAtKept')}, stops {p.get('micStopsAfterStop')}")
    fin = p.get("onFinish") or {}
    check("3o: segment 1's files written EMPTY, its two did-finishes driven, the recorder settled",
          p.get("emptyWritten") is True and p.get("settled") is True,
          f"written {p.get('emptyWritten')}, settled {p.get('settled')}, state {p.get('stateAfterStop')!r}")
    left = fin.get("unreadable") or []
    check("3o: the walker meets an unreadable second movie and LEAVES THAT SEGMENT OUT (issue batch "
          "B17, #97): a .success of the one readable segment (pause.png), pauses 2",
          fin.get("kind") == "success" and fin.get("pauses") == 2
          and [x.get("path") for x in fin.get("segments") or []] == [paths[0]], f"got {fin!r}")
    check("3o: … unreadable[0] is segment 1's movie with both its files kept (movie, then "
          "microphone), case finishFailed, and the note ends \" Its files are kept at <movie>, "
          "<mic>.\"",
          len(left) == 1 and left[0].get("moviePath") == paths[2]
          and left[0].get("keptFiles") == [paths[2], paths[3]] and left[0].get("case") == "finishFailed"
          and (fin.get("unreadableNote") or "").endswith(f" Its files are kept at {paths[2]}, {paths[3]}."),
          f"unreadable {left!r}, note {fin.get('unreadableNote')!r}")
    check("3o: onFinish once, the stop's completion once, both the same outcome",
          p.get("onFinishCount") == 1 and p.get("stopCount") == 1 and p.get("stop") == fin,
          f"onFinish {p.get('onFinishCount')}, stop {p.get('stopCount')}")
    check("3o: elapsed is 0 again once idle", p.get("elapsedAfter") == 0, f"got {p.get('elapsedAfter')}")

    print("  3p — pause() refused")
    pr = answer.get("pauseRefused") or {}
    check("3p: a remove that throws (an output never added; −3812) is rethrown as .finishFailed 'The "
          "recording could not be paused: …' — a file that could not be closed",
          (pr.get("pause") or "").startswith("finishFailed: The recording could not be paused: "),
          f"got {pr.get('pause')!r}")
    check("3p: … and the recorder STAYS .recording with nothing changed — no stamp, no stopRecording, "
          "the meter still lit",
          pr.get("stateAfter") == "recording" and (pr.get("segment0") or {}).get("stoppedAt") is None
          and pr.get("micStops") == 0 and pr.get("meterLit") is True,
          f"{pr.get('stateAfter')!r}, {pr.get('segment0')}, stops {pr.get('micStops')}, lit {pr.get('meterLit')}")
    check("3p: a stop() then closes it as ever — finishing, the writer asked to stop once, a .success",
          pr.get("stateAfterStop") == "finishing" and pr.get("micStopsAfterStop") == 1
          and pr.get("settled") is True and (pr.get("onFinish") or {}).get("kind") == "success",
          f"{pr.get('stateAfterStop')!r}, stops {pr.get('micStopsAfterStop')}, {pr.get('onFinish')}")

    print("  3q — resume() refused")
    rr = answer.get("resumeRefused") or {}
    check("3q: an add that throws (the segment's output still attached — a second output on one "
          "stream is −3812; the state paused BY THE PROBE) is rethrown as .startFailed 'The recording "
          "could not be resumed: …'",
          rr.get("attached") == "ok"
          and (rr.get("resume") or "").startswith("startFailed: The recording could not be resumed: "),
          f"attached {rr.get('attached')!r}, got {rr.get('resume')!r}")
    check("3q: … and the recorder STAYS .paused with no segment minted and no startRecording",
          rr.get("stateAfter") == "paused" and rr.get("segments") == 1 and rr.get("micStarts") == [],
          f"{rr.get('stateAfter')!r}, {rr.get('segments')}, {rr.get('micStarts')}")
    check("3q: a stop() then lands the one segment",
          rr.get("stateAfterStop") == "finishing" and rr.get("settled") is True
          and (rr.get("onFinish") or {}).get("kind") == "success" and rr.get("stopCount") == 1
          and len((rr.get("onFinish") or {}).get("segments") or []) == 1, f"{rr.get('onFinish')}")

    print("  3r — a did-fail on a CLOSED segment is that segment's (issue batch B27, #181)")
    cf = answer.get("closedFail") or {}
    cpaths = cf.get("paths") or ["", "", "", ""]
    check("3r: a did-fail on a CLOSED segment (paused; its did-finish still in flight) does NOT end the "
          "recording — still .recording, no screenFailure on the session (closed-fail-fails-all)",
          cf.get("written") is True and cf.get("attached") == "ok"
          and cf.get("stateAfterFail") == "recording" and cf.get("screenFailure") == "nil",
          f"attached {cf.get('attached')!r}, {cf.get('stateAfterFail')!r}, {cf.get('screenFailure')!r}")
    check("3r: … the closed segment flagged finished with its outputFailure the writer's sentence, and "
          "no writer asked to stop",
          (cf.get("segment0") or {}).get("screenFinished") is True
          and cf.get("outputFailure0") == "finishFailed: The recording failed: the writer gave up"
          and cf.get("micStopsAfterFail") == 0,
          f"0 {cf.get('segment0')}, {cf.get('outputFailure0')!r}, stops {cf.get('micStopsAfterFail')}")
    check("3r: stop() then finishes it — .finishing, the open segment's writer asked to stop once",
          cf.get("stateAfterStop") == "finishing" and cf.get("micStopsAfterStop") == 1,
          f"{cf.get('stateAfterStop')!r}, stops {cf.get('micStopsAfterStop')}")
    fin = cf.get("onFinish") or {}
    segs = fin.get("segments") or []
    left = fin.get("unreadable") or []
    u0 = left[0] if left else {}
    check("3r: ONE .success — onFinish once, the completion once — of the OPEN segment alone "
          "(closedfail1.png), pauses 1",
          cf.get("settled") is True and cf.get("onFinishCount") == 1 and cf.get("stopCount") == 1
          and fin.get("kind") == "success" and [x.get("path") for x in segs] == [cpaths[1]]
          and fin.get("pauses") == 1, f"got {fin!r}")
    check("3r: unreadable is the CLOSED segment — closedfail0.png, both files kept, case finishFailed, "
          "\"The recording failed: the writer gave up\" — left out UNPROBED although its PNG would read "
          "(closed-fail-probed)",
          len(left) == 1 and u0.get("moviePath") == cpaths[0]
          and u0.get("keptFiles") == [cpaths[0], cpaths[2]] and u0.get("case") == "finishFailed"
          and u0.get("description") == "The recording failed: the writer gave up", f"got {left!r}")
    check("3r: … and its microphone, closedfail0-mic.png, is probed although the segment is left out "
          "— unreadable[0].micPath is that file, position 0 (issue batch B55, #181 item 2; "
          "leftout-mic-unprobed)",
          u0.get("micPath") == cpaths[2] and u0.get("position") == 0,
          f"micPath {u0.get('micPath')!r}, position {u0.get('position')!r}")

    print("  3r2 — a did-fail on the segment a pause just closed, while PAUSED (issue batch B27, #181)")
    cp = answer.get("closedFailPaused") or {}
    ppaths = cp.get("paths") or ["", "", "", ""]
    check("3r2: a real pause(), then the closed segment's did-fail — the recorder STAYS .paused, no "
          "screenFailure, the segment's outputFailure the writer's sentence (closed-fail-fails-all)",
          cp.get("written") is True and cp.get("attached") == "ok" and cp.get("pause") == "ok"
          and cp.get("stateAfterFail") == "paused" and cp.get("screenFailure") == "nil"
          and cp.get("outputFailure1")
          == "finishFailed: The recording failed: the writer gave up while paused",
          f"{cp.get('pause')!r}, {cp.get('stateAfterFail')!r}, {cp.get('screenFailure')!r}, "
          f"{cp.get('outputFailure1')!r}")
    check("3r2: … still .paused once its microphone's did-finish lands",
          cp.get("stateAfterMic") == "paused", f"{cp.get('stateAfterMic')!r}")
    pfin = cp.get("onFinish") or {}
    psegs = pfin.get("segments") or []
    pleft = pfin.get("unreadable") or []
    pu = pleft[0] if pleft else {}
    check("3r2: stop() → ONE .success of segment 0 alone within settled()'s 5 s, pauses 2",
          cp.get("settled") is True and cp.get("onFinishCount") == 1 and pfin.get("kind") == "success"
          and [x.get("path") for x in psegs] == [ppaths[0]] and pfin.get("pauses") == 2, f"got {pfin!r}")
    check("3r2: … unreadable is segment 1 with both its files kept, case finishFailed, the writer's "
          "sentence",
          len(pleft) == 1 and pu.get("moviePath") == ppaths[1]
          and pu.get("keptFiles") == [ppaths[1], ppaths[3]] and pu.get("case") == "finishFailed"
          and pu.get("description") == "The recording failed: the writer gave up while paused",
          f"got {pleft!r}")

    print("  3s — an external stop while paused")
    ep = answer.get("externalPaused") or {}
    check("3s: the pause's own did-finish while .paused is inert (stoppedAt says it was asked for)",
          ep.get("pause") == "ok" and ep.get("stateAfterPauseFinish") == "paused"
          and (ep.get("segment0") or {}).get("screenFinished") is True,
          f"{ep.get('pause')!r}, {ep.get('stateAfterPauseFinish')!r}, {ep.get('segment0')}")
    check("3s: didStopWithError(.userStopped) while PAUSED takes the finishing path with its reason — "
          "and with the one segment already closed, beginFinishing's own checkFinished settles it on "
          "the same turn (the R2 review: a stop from paused no longer waits for stopCapture's completion)",
          ep.get("stateAfterExternal") in ("finishing", "idle")
          and ep.get("stoppedBy") in ("userStopped", "nil"),
          f"{ep.get('stateAfterExternal')!r}, {ep.get('stoppedBy')!r}")
    efin = ep.get("onFinish") or {}
    check("3s: … and lands ONE segment as userStopped with pauses 1 — the count is STORED per press, "
          "never segments − 1 (a pause with no resume before the stop was still a pause; the R2 review)",
          ep.get("settled") is True and efin.get("stoppedBy") == "userStopped"
          and efin.get("pauses") == 1 and ep.get("pauses") == 1 and len(efin.get("segments") or []) == 1,
          f"{efin}, session pauses {ep.get('pauses')}")
    check("3s: elapsed while paused was about the 2 s recorded",
          1.9 <= ep.get("elapsedFrozen", 0) <= 2.4, f"got {ep.get('elapsedFrozen')}")
    sp = answer.get("systemStopPaused") or {}
    sfin = sp.get("onFinish") or {}
    check("3s: a stream stop while PAUSED with a NON-external code (nothing is writing; every file is "
          "closed) LANDS the recording as systemStopped rather than failing it (the R2 review)",
          sp.get("pause") == "ok" and sp.get("stateAfter") in ("finishing", "idle")
          and sp.get("stoppedBy") in ("systemStopped", "nil") and sp.get("settled") is True
          and sfin.get("kind") == "success" and sfin.get("stoppedBy") == "systemStopped"
          and len(sfin.get("segments") or []) == 1, f"{sp.get('stateAfter')!r}, {sfin}")
    ld = answer.get("lateDidStart") or {}
    s1 = ld.get("segment1") or {}
    check("3s: a did-start landing AFTER its own segment's pause (inside the resume's ~10 ms window) is "
          "IGNORED — screenStartedAt stays nil, the add's own call is the span's start — and elapsed "
          "is the first segment's second plus nothing negative",
          ld.get("transitions") == "ok" and ld.get("segmentsAfter") == 2 and s1.get("screenStartedAt") is None
          and s1.get("stoppedAt") is not None and 0.95 <= (ld.get("elapsed") or 0) <= 1.3,
          f"{ld.get('transitions')!r}, {s1}, elapsed {ld.get('elapsed')}")
    movies = ld.get("movies") or []
    check("3s: a second resume within the same second mints a name the session does not already HOLD "
          "(no file of either exists yet) — three different movie names, the held one skipped",
          ld.get("secondResume") == "ok" and len(movies) == 3 and len(set(movies)) == 3
          and ld.get("filesExist") == [False, False] and ld.get("pauses") == 3 and ld.get("stateAfter") == "paused",
          f"{movies}, exist {ld.get('filesExist')}, pauses {ld.get('pauses')}")

    print("  3t — the walker over three closed segments")
    w = answer.get("walker") or {}
    wp = w.get("paths") or []
    check("3t: three closed segments' fixtures — movies 0–2, microphone files 1 and 2 (0's never "
          "started)", len(wp) == 3 and all(x.get("written") for x in wp), f"{wp}")
    check("3t: elapsed over three closed segments is 2 + 3 + 1.5 = 6.5 s — the SUM of the spans, "
          "the two 1 s gaps never counted, and frozen (elapsed-through-pause)",
          abs(w.get("elapsedPaused", 0) - 6.5) < 0.01
          and w.get("elapsedPaused") == w.get("elapsedPausedAgain"),
          f"{w.get('elapsedPaused')} then {w.get('elapsedPausedAgain')}")
    fin = w.get("onFinish") or {}
    segs = fin.get("segments") or []
    check("3t: stop() while paused settles ONE result of THREE RecordingSegments in order, pauses 2",
          w.get("stateAfterStop") == "finishing" and w.get("settled") is True
          and w.get("onFinishCount") == 1 and fin.get("kind") == "success" and fin.get("pauses") == 2
          and [s.get("path") for s in segs] == [x.get("movie") for x in wp],
          f"{w.get('stateAfterStop')!r}, settled {w.get('settled')}, {fin}")
    if len(segs) != 3 or len(wp) != 3:
        for _ in range(6):
            check("3t: (a segment row could not be read — see above)", False)
        return
    check("3t: the result's descriptor and startedAt are the FIRST segment's",
          fin.get("path") == wp[0].get("movie")
          and abs(fin.get("startedAt", 0) - wp[0].get("screenStart", 1)) < 0.001, f"{fin.get('path')}")
    check("3t: segment 0's microphone never started — no file, micDescriptor nil, the sentence, "
          "offset 0", segs[0].get("micDescriptor") is False
          and segs[0].get("micProblem") == "The microphone never started recording, so the picture "
          "was recorded without it." and segs[0].get("micOffset") == 0, f"{segs[0]}")
    check("3t: segment 1's microphone landed with ITS OWN offset −12 000 (its picture began 20 ms "
          "before its voice) — never the first segment's (resume-first-offset)",
          segs[1].get("micDescriptor") is True and segs[1].get("micOffset") == -12_000
          and segs[1].get("micProblem") is None and segs[1].get("micPath") == wp[1].get("mic"),
          f"{segs[1]}")
    check("3t: segment 2's writer failed — micDescriptor nil, the writer's sentence naming the file "
          "it left", segs[2].get("micDescriptor") is False
          and segs[2].get("micProblem") == "The microphone recording failed: boom. What it wrote is "
          f"at {wp[2].get('mic')}.", f"{segs[2]}")
    check("3t: the result's micProblem is the segments' sentences JOINED by a space, in order",
          fin.get("micProblem") == f"{segs[0].get('micProblem')} {segs[2].get('micProblem')}",
          f"got {fin.get('micProblem')!r}")
    check("3t: each segment's startedAt is its OWN screen did-start; the stop's completion received "
          "the same result",
          all(abs(s.get("startedAt", 0) - x.get("screenStart", 1)) < 0.001 for s, x in zip(segs, wp))
          and w.get("stop") == fin, f"{[s.get('startedAt') for s in segs]}")


# --------------------------------------------------------------------------
# Section 11 — issue batch B17 (#97): a segment whose movie will not probe is
# LEFT OUT; a microphone failure at a segment boundary stays that segment's.

SYSTEM_STOP_SENTENCE = "Stopped from the system's screen-recording indicator; the recording was added."


def section_unreadable(binary, sources):
    print("\nSection 11 — issue batch B17 (#97): an unreadable segment is left out and named; a "
          "boundary microphone failure is the segment's")
    work = fresh_dir("unreadable")
    answer, error = run_probe(binary, "unreadable", {"mode": "unreadable", "work": work})
    check("11: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return

    print("  U1 — [readable, EMPTY, readable], a microphone on every segment")
    u1 = answer.get("u1") or {}
    movies = u1.get("movies") or ["", "", ""]
    mics = u1.get("mics") or ["", "", ""]
    fin = u1.get("onFinish") or {}
    segs = fin.get("segments") or []
    left = fin.get("unreadable") or [{}]
    check("U1: the fixtures were written — a PNG movie, an EMPTY .mov, a PNG movie, each with a "
          "microphone PNG", u1.get("written") is True and len(movies) == 3 and len(mics) == 3,
          f"{u1.get('written')}, {movies}, {mics}")
    check("U1: stop() while paused settles a .success — the unreadable middle segment does not fail "
          "the recording (unreadable-fails-all)",
          u1.get("settled") is True and fin.get("kind") == "success", f"got {fin!r}")
    check("U1: … of segments 0 and 2, in order, each with its microphone landed",
          [x.get("path") for x in segs] == [movies[0], movies[2]]
          and [x.get("micPath") for x in segs] == [mics[0], mics[2]], f"{segs}")
    check("U1: … and pauses 2 — the presses, never the files", fin.get("pauses") == 2,
          f"got {fin.get('pauses')}")
    check("U1: unreadable names segment 1 alone — its movie, both its files kept (movie, then "
          "microphone), case finishFailed",
          len(fin.get("unreadable") or []) == 1 and left[0].get("moviePath") == movies[1]
          and left[0].get("keptFiles") == [movies[1], mics[1]] and left[0].get("case") == "finishFailed",
          f"{fin.get('unreadable')!r}")
    reason = left[0].get("description") or ""
    check("U1: the note is \"A segment was left out. The recording could not be read: <the probe's "
          "words> Its files are kept at <movie>, <mic>.\" (no-unreadable-note)",
          reason.startswith("The recording could not be read: ")
          and fin.get("unreadableNote") == f"A segment was left out. {reason} Its files are kept at "
          f"{movies[1]}, {mics[1]}.", f"got {fin.get('unreadableNote')!r}")
    check("U1: … and its microphone READ although its movie did not — unreadable[0].micPath is "
          "segment 1's microphone, position 1, the segments landed before it (issue batch B55, "
          "#181 item 2; leftout-mic-unprobed)",
          left[0].get("micPath") == mics[1] and left[0].get("position") == 1,
          f"micPath {left[0].get('micPath')!r}, position {left[0].get('position')!r}")
    check("U1: onFinish once, the stop's completion once, the same outcome",
          u1.get("onFinishCount") == 1 and u1.get("stopCount") == 1 and u1.get("stop") == fin,
          f"onFinish {u1.get('onFinishCount')}, stop {u1.get('stopCount')}")

    print("  U2 — [EMPTY, EMPTY], every microphone READABLE: no readable movie, so the recording "
          "still fails (spec §11 recording, B55) and every file is kept")
    u2 = answer.get("u2") or {}
    m2 = u2.get("movies") or ["", ""]
    c2 = u2.get("mics") or ["", ""]
    f2 = u2.get("onFinish") or {}
    description = f2.get("description") or ""
    check("U2: with NO readable movie the recording FAILS — filesKept(finishFailed), the first "
          "segment's error, naming both movies then both microphone files",
          u2.get("written") is True and u2.get("settled") is True and f2.get("kind") == "failure"
          and f2.get("case") == "filesKept(finishFailed)"
          and description.startswith("The recording could not be read: ")
          and description.endswith(
              f" The recording is at {m2[0]}, {m2[1]}; the microphone at {c2[0]}, {c2[1]}."),
          f"got {f2!r}")
    check("U2: onFinish once, the stop's completion once, the same outcome",
          u2.get("onFinishCount") == 1 and u2.get("stopCount") == 1 and u2.get("stop") == f2,
          f"onFinish {u2.get('onFinishCount')}, stop {u2.get('stopCount')}")
    check("U2: … and the failure deleted no file — both readable microphone files are still on disk "
          "for the person to import (B55)",
          u2.get("micsOnDisk") is True and len(c2) == 2, f"{u2.get('micsOnDisk')}, {c2}")

    print("  U7 — [no movie file at all, no movie file at all], every microphone readable (B55)")
    u7 = answer.get("u7") or {}
    c7 = u7.get("mics") or ["", ""]
    f7 = u7.get("onFinish") or {}
    d7 = f7.get("description") or ""
    check("U7: with NO movie file on disk the failure still names each microphone file — "
          "filesKept(finishFailed) ending \" The microphone is at <mic 0>, <mic 1>.\" (mics-unnamed)",
          u7.get("written") is True and u7.get("settled") is True and u7.get("moviesOnDisk") == 0
          and f7.get("kind") == "failure" and f7.get("case") == "filesKept(finishFailed)"
          and d7.startswith("The recording could not be read: ")
          and d7.endswith(f" The microphone is at {c7[0]}, {c7[1]}.") and u7.get("micsOnDisk") is True,
          f"got {f7!r}, movies on disk {u7.get('moviesOnDisk')}")

    print("  U3 — [EMPTY, readable], no microphone")
    u3 = answer.get("u3") or {}
    m3 = u3.get("movies") or ["", ""]
    s3 = u3.get("startedAt") or [0, 0]
    f3 = u3.get("onFinish") or {}
    l3 = f3.get("unreadable") or [{}]
    check("U3: a .success of the one readable segment, whose path and startedAt — the RESULT's — are "
          "the SECOND segment's",
          u3.get("written") is True and u3.get("settled") is True and f3.get("kind") == "success"
          and len(f3.get("segments") or []) == 1 and f3.get("path") == m3[1]
          and abs((f3.get("startedAt") or 0) - s3[1]) < 0.001, f"got {f3!r}")
    check("U3: … the first segment left out with its movie alone kept",
          len(f3.get("unreadable") or []) == 1 and l3[0].get("moviePath") == m3[0]
          and l3[0].get("keptFiles") == [m3[0]], f"{f3.get('unreadable')!r}")

    print("  U4–U6 — pure")
    pure = answer.get("pure") or {}
    check("U4: UnreadableSegment(\"/x/a.mov\", no files, .timedOut).sentence is \"A segment was left "
          "out. <.timedOut's sentence> It left no file on disk.\"",
          bool(pure.get("timedOut")) and pure.get("aloneSentence")
          == f"A segment was left out. {pure.get('timedOut')} It left no file on disk.",
          f"got {pure.get('aloneSentence')!r}")
    check("U4: … and with two files kept, \"… Its files are kept at /x/b.mov, /x/b (Microphone).m4a.\"",
          pure.get("keptSentence") == "A segment was left out. The recording could not be read: x. "
          "Its files are kept at /x/b.mov, /x/b (Microphone).m4a.", f"got {pure.get('keptSentence')!r}")
    check("U4: a result with nothing left out has unreadableNote nil", pure.get("emptyNoteIsNil") is True,
          f"{pure.get('emptyNoteIsNil')}")
    landing = pure.get("landing") or {}
    closed = pure.get("closedSentence") or ""
    check("U5: landingNote's order — the stop's sentence, the closed document, UNREADABLE, the "
          "microphone, the resume, the placement's notes",
          bool(closed) and landing.get("all") == f"{SYSTEM_STOP_SENTENCE} {closed} Unreadable. Mic. "
          "Resume. Note one. Note two.", f"got {landing.get('all')!r}")
    check("U5: unreadable: nil is the R1 call, byte for byte",
          landing.get("nil") == landing.get("r1") == f"{SYSTEM_STOP_SENTENCE} {closed} Mic.",
          f"{landing.get('nil')!r} against {landing.get('r1')!r}")
    check("U5: the unreadable sentence alone is the whole note", landing.get("only") == "Unreadable.",
          f"got {landing.get('only')!r}")
    note = pure.get("unreadableNote")
    fu = pure.get("fieldsUnreadable")
    fu0 = fu[0] if isinstance(fu, list) and len(fu) == 1 and isinstance(fu[0], dict) else {}
    check("U6: record_screen's fields carry unreadable — [{path, kept_files, reason, mic_path, "
          "mic_duration}] — for U1's result, its microphone having read (B55; no ids without a landing)",
          sorted(fu0) == ["kept_files", "mic_duration", "mic_path", "path", "reason"]
          and fu0.get("path") == movies[1] and fu0.get("kept_files") == [movies[1], mics[1]]
          and fu0.get("reason") == reason and fu0.get("mic_path") == mics[1]
          and isinstance(fu0.get("mic_duration"), int), f"got {fu!r}")
    check("U6: … and no unreadable key at all when nothing was left out",
          pure.get("cleanHasUnreadable") is False, f"{pure.get('cleanHasUnreadable')}")
    voice_note = f"The left-out segment's microphone, {mics[1]}, was added to the project without its picture."
    check("U6: resultNotes is [the unreadable note, the left-out voice's note, the microphone note], in "
          "that order; [] for a clean result (B55)",
          bool(note) and bool(pure.get("microphoneNoteBoth"))
          and pure.get("leftOutVoiceNote") == voice_note
          and pure.get("notesBoth") == [note, voice_note, pure.get("microphoneNoteBoth")]
          and pure.get("notesClean") == [], f"{pure.get('notesBoth')!r}, {pure.get('notesClean')!r}")
    clause = pure.get("filesClause") or ""
    check("U6: savedButNotAdded ends with the unreadable note; a clean result's sentence is R1's",
          pure.get("savedWith") == f"The recording was saved at {clause} but could not be added: a "
          f"drag is in progress {note}"
          and pure.get("savedClean") == f"The recording was saved at {clause} but could not be added: "
          "a drag is in progress", f"{pure.get('savedWith')!r}, {pure.get('savedClean')!r}")
    check("U6: … and a failed landing never says the voice was added — savedButNotAdded holds no "
          "\"was added to the project\" (B55)",
          "was added to the project" not in (pure.get("savedWith") or "x was added to the project"),
          f"{pure.get('savedWith')!r}")

    print("  M1 — a microphone failure at a segment boundary")
    b = answer.get("boundary") or {}
    s0 = b.get("segment0") or {}
    check("M1: a recording session with a microphone, its output attached, paused",
          b.get("written") is True and b.get("attached") == "ok" and b.get("pause") == "ok",
          f"{b.get('written')}, {b.get('attached')!r}, {b.get('pause')!r}")
    check("M1: a microphone did-finish carrying −11805 for the PAUSED segment (stoppedAt set — asked "
          "for) is that segment's micFailure, the recorder still paused",
          (s0.get("micFailure") or "").startswith("The microphone recording failed: ")
          and b.get("stateAfterMicFinish") == "paused", f"{s0}, {b.get('stateAfterMicFinish')!r}")
    check("M1: … and NOT the session's microphoneProblem — the live note stays empty "
          "(boundary-promoted)",
          b.get("microphoneProblem") is None and b.get("liveNote") == "",
          f"{b.get('microphoneProblem')!r}, {b.get('liveNote')!r}")
    bf = b.get("onFinish") or {}
    bs = bf.get("segments") or [{}]
    check("M1: the stop lands a .success whose segment 0 micProblem begins \"The microphone recording "
          "failed: \" — once to onFinish and once to the stop",
          b.get("settled") is True and bf.get("kind") == "success" and len(bf.get("segments") or []) == 1
          and (bs[0].get("micProblem") or "").startswith("The microphone recording failed: ")
          and b.get("onFinishCount") == 1 and b.get("stopCount") == 1, f"{bf!r}")


# --------------------------------------------------------------------------
# Section 4 — the landing (road map 3, R1b): lane B's rows as tracked checks.

SEC = 600_000
FRAME_30 = 20_000                      # one frame at the fresh project's 30 fps
FRAME_60 = 10_000                      # one frame at the recorder's 60 fps
PICTURE_LEN = 5 * SEC                  # the picture descriptor's 5 s
MIC_LEN = 5 * SEC + 12_000             # the microphone file, 5.02 s
# `add_clip` snaps a clip's length to the canvas frame grid, DOWNWARD — a
# LENGTH is bounded by the file it came from (spec §11, kpgalligan/framejob#22),
# where a START is rounded to the nearest frame. Lane B's one wrong first
# expectation, kept here as the rule rather than the number.
MIC_LEN_SNAPPED = MIC_LEN // FRAME_30 * FRAME_30                     # 3 000 000
RECORDING_STEM = "Screen Recording 2026-09-10 at 14.03.22"
MIC_STEM = "Screen Recording 2026-09-10 at 15.00.00"
PACKAGE_TYPE = "com.kgalligan.framejob-project"
DRAG_REFUSAL = "A drag is in progress; the recording can be added when it ends."
ACTION_NAME = "Add Recording"
# `untitled(around:)`'s microphone step: it removes the voice and keeps the
# picture, so it is not called "Add Recording".
MIC_ACTION_NAME = "Add Microphone"
# The core's sentence for the 65th track (`core/src/format.rs`, check_caps).
CAP_SENTENCE = "too many tracks: 65 (max 64)"
MIC_OPS = ["add_media", "add_clip", "add_media", "add_track", "add_clip"]
MIC_OPS_TRIMMED = MIC_OPS + ["trim_start", "move_clip"]

# The offset rule at a 30 fps canvas: the mic clip's start and `in`, with
# the op list's length. `micAt` is what the add_clip op SENDS (the core
# snaps it); `micStart` is what lands.
MIC_CASES = [
    {"name": "4a", "playhead": 0, "offset": 12_000, "ops": MIC_OPS_TRIMMED,
     "micAt": 0, "micStart": 0, "micIn": FRAME_30,
     "why": "+20 ms at 0 → the head trimmed one frame"},
    {"name": "4b", "playhead": 0, "offset": -18_000, "ops": MIC_OPS,
     "micAt": 18_000, "micStart": FRAME_30, "micIn": 0,
     "why": "−30 ms at 0 → the mic clip later, the core snapping 18 000 to the frame"},
    {"name": "4c", "playhead": SEC, "offset": 12_000, "ops": MIC_OPS,
     "micAt": SEC - 12_000, "micStart": SEC - FRAME_30, "micIn": 0,
     "why": "+20 ms at 1 s → the mic clip earlier"},
    {"name": "4d", "playhead": 0, "offset": 3_000, "ops": MIC_OPS,
     "micAt": 0, "micStart": 0, "micIn": 0,
     "why": "+5 ms at 0 → sub-frame, no trim"},
    {"name": "4e", "playhead": 0, "offset": 0, "ops": MIC_OPS,
     "micAt": 0, "micStart": 0, "micIn": 0, "why": "0 at 0"},
]


def op_json(row):
    """The op list a row committed, as parsed JSON objects, in order."""
    out = []
    for text in row.get("opJSON") or []:
        try:
            out.append(json.loads(text))
        except ValueError:
            out.append({})
    return out


def landing_row_common(tag, r, ops, media_ids, front_track):
    """What every placing row shares: the op names, the minted media equal to
    the prediction, and the picture clip where the prediction said."""
    pred = r.get("predicted") or {}
    check(f"{tag}: ops {ops}", r.get("ops") == ops, r.get("error") or f"got {r.get('ops')}")
    check(f"{tag}: the core minted exactly the media the landing predicted {media_ids}",
          r.get("mintedMedia") == media_ids and [pred.get("media")] == media_ids[:1],
          f"minted {r.get('mintedMedia')}, predicted {pred}")
    clips = r.get("mintedClips") or []
    picture = next((c for c in clips if c.get("media") == pred.get("media")), None)
    check(f"{tag}: the picture clip's id is the predicted {pred.get('clip')}",
          picture is not None and picture.get("id") == pred.get("clip") != -1,
          f"clips {clips}")
    check(f"{tag}: the picture clip is on track {front_track} at in 0 with the picture's "
          f"5 s ({PICTURE_LEN})",
          picture is not None and picture.get("track") == front_track and picture.get("in") == 0
          and picture.get("duration") == PICTURE_LEN, f"{picture}")
    check(f"{tag}: one undo step, named {ACTION_NAME!r}",
          r.get("canUndo") is True and r.get("undoName") == ACTION_NAME,
          f"canUndo {r.get('canUndo')}, name {r.get('undoName')!r}")
    return pred, clips, picture


def section_landing(binary, sources):
    print("\nSection 4 — RecordingLanding: placement, the microphone's offset rule, "
          "untitled(around:), resolve, and inside a nest")
    tmp = fresh_dir("untitled")
    answer, error = run_probe(binary, "landing", {
        "mode": "landing", "tempFolder": tmp,
        "micCases": [{k: c[k] for k in ("name", "playhead", "offset")} for c in MIC_CASES]})
    check("4: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    check("4: the probe's NSDocumentController subclass is `.shared` — the first one made — so "
          "the untitled path runs on a real ProjectDocument",
          answer.get("controllerIsProbe") is True)
    check(f"4: the fixtures are a {PICTURE_LEN}-tick picture and a {MIC_LEN}-tick microphone",
          answer.get("pictureDuration") == PICTURE_LEN and answer.get("microphoneDuration") == MIC_LEN,
          f"{answer.get('pictureDuration')}, {answer.get('microphoneDuration')}")

    # Row 1.
    r = answer.get("row1") or {}
    print("  row 1 — a fresh 1920×1080/30 project, an empty front track")
    check("4·1: next_id before the edit is 2 (one track, nothing else)", r.get("nextIdBefore") == 2,
          r.get("error") or f"got {r.get('nextIdBefore')}")
    pred, clips, picture = landing_row_common("4·1", r, ["add_media", "add_clip"], [2], 1)
    check("4·1: predicted media 2 / clip 3 — next_id and next_id + 1", pred == {
        "media": 2, "clip": 3, "micMedia": -1, "micClip": -1}, f"{pred}")
    check("4·1: the clip is at 0 (the playhead) and no track was added",
          picture is not None and picture.get("start") == 0 and r.get("mintedTracks") == [],
          f"{picture}, tracks {r.get('mintedTracks')}")
    ops = op_json(r)
    check("4·1: add_clip names the front track 1, media 2, at 0",
          len(ops) == 2 and ops[1] == {"op": "add_clip", "track": 1, "media": 2, "at": 0}, f"{ops}")
    check("4·1: the document holds one clip", r.get("documentClips") == 1, f"{r.get('documentClips')}")

    # Row 2.
    r = answer.get("row2") or {}
    print("  row 2 — a clip at 0 on the front track, the playhead at 1 s")
    check("4·2: next_id before the edit is 4 (the blocker's media and clip took 2 and 3)",
          r.get("nextIdBefore") == 4, r.get("error") or f"got {r.get('nextIdBefore')}")
    pred, clips, picture = landing_row_common("4·2", r, ["add_media", "add_track", "add_clip"], [4], 5)
    ops = op_json(r)
    check("4·2: add_track(index: 1) — the front of a one-track container",
          len(ops) == 3 and ops[1] == {"op": "add_track", "index": 1}, f"{ops}")
    check("4·2: add_clip names the NEW track 5 (next_id + 1), media 4, at 600000",
          len(ops) == 3 and ops[2] == {"op": "add_clip", "track": 5, "media": 4, "at": SEC}, f"{ops}")
    check("4·2: predicted clip 6 — after the media and the track", pred.get("clip") == 6, f"{pred}")
    tracks = r.get("mintedTracks") or []
    check("4·2: one new track, id 5, and it is the FRONT of the stack",
          tracks == [{"id": 5, "name": "Track 2"}] and (r.get("viewTracks") or [{}])[-1].get("id") == 5,
          f"tracks {tracks}, view {r.get('viewTracks')}")
    check("4·2: the clip landed at 600000 on it",
          picture is not None and picture.get("start") == SEC and picture.get("track") == 5, f"{picture}")
    check("4·2: the blocker is still there — two clips in the document",
          r.get("documentClips") == 2, f"{r.get('documentClips')}")

    # Row 3, 3b.
    r = answer.get("row3") or {}
    print("  row 3 — place: false")
    pred = r.get("predicted") or {}
    check("4·3: place false → [add_media] alone", r.get("ops") == ["add_media"],
          r.get("error") or f"got {r.get('ops')}")
    check("4·3: clipId nil and no microphone ids",
          pred == {"media": 2, "clip": -1, "micMedia": -1, "micClip": -1}, f"{pred}")
    check("4·3: the media was minted with id 2 and no clip or track",
          r.get("mintedMedia") == [2] and r.get("mintedClips") == [] and r.get("mintedTracks") == [],
          f"{r.get('mintedMedia')}, {r.get('mintedClips')}, {r.get('mintedTracks')}")
    check("4·3: the document holds no clip", r.get("documentClips") == 0)
    r = answer.get("row3b") or {}
    pred = r.get("predicted") or {}
    check("4·3b: place false with a microphone → [add_media, add_media]",
          r.get("ops") == ["add_media", "add_media"], r.get("error") or f"got {r.get('ops')}")
    check("4·3b: both media predicted (2, 3), neither clip",
          pred == {"media": 2, "clip": -1, "micMedia": 3, "micClip": -1}, f"{pred}")
    check("4·3b: minted media [2, 3], no clips, no tracks",
          r.get("mintedMedia") == [2, 3] and r.get("mintedClips") == [] and r.get("mintedTracks") == [],
          f"{r.get('mintedMedia')}, {r.get('mintedClips')}, {r.get('mintedTracks')}")

    # Rows 4a–4e.
    print("  rows 4a–4e — the microphone's offset rule at a 30 fps canvas")
    by_name = {m.get("name"): m for m in answer.get("micRows") or []}
    for case in MIC_CASES:
        tag = f"4·{case['name']}"
        r = by_name.get(case["name"], {})
        print(f"  {tag}: offset {case['offset']:+} at {case['playhead']} — {case['why']}")
        check(f"{tag}: the canvas frame is {FRAME_30} ticks", r.get("frame") == FRAME_30,
              r.get("error") or f"got {r.get('frame')}")
        pred, clips, picture = landing_row_common(tag, r, case["ops"], [2, 4], 1)
        check(f"{tag}: predicted media 2, clip 3, mic media 4, mic track 5, mic clip 6 — each "
              "off the purely-applied result before it, never one next_id read",
              pred == {"media": 2, "clip": 3, "micMedia": 4, "micClip": 6}, f"{pred}")
        mic = next((c for c in clips if c.get("media") == pred.get("micMedia")), None)
        view = r.get("viewTracks") or []
        check(f"{tag}: the picture clip is at the playhead {case['playhead']}",
              picture is not None and picture.get("start") == case["playhead"], f"{picture}")
        check(f"{tag}: a new BACK track named Microphone (index 0), id 5",
              r.get("mintedTracks") == [{"id": 5, "name": "Microphone"}]
              and view and view[0] == {"id": 5, "name": "Microphone"} and len(view) == 2,
              f"minted {r.get('mintedTracks')}, view {view}")
        ops = op_json(r)
        check(f"{tag}: add_track is index 0 with the name",
              len(ops) > 3 and ops[3] == {"op": "add_track", "index": 0, "name": "Microphone"},
              f"{ops[3] if len(ops) > 3 else ops}")
        check(f"{tag}: the mic's add_clip sends at {case['micAt']} on track 5",
              len(ops) > 4 and ops[4] == {"op": "add_clip", "track": 5, "media": 4, "at": case["micAt"]},
              f"{ops[4] if len(ops) > 4 else ops}")
        check(f"{tag}: the mic clip is the predicted id 6 on track 5",
              mic is not None and mic.get("id") == 6 and mic.get("track") == 5, f"{mic}")
        check(f"{tag}: the mic clip starts at {case['micStart']} with in {case['micIn']}",
              mic is not None and mic.get("start") == case["micStart"] and mic.get("in") == case["micIn"],
              f"{mic}")
        check(f"{tag}: its length is the SNAPPED file length {MIC_LEN_SNAPPED} less the head "
              f"({MIC_LEN_SNAPPED - case['micIn']})",
              mic is not None and mic.get("duration") == MIC_LEN_SNAPPED - case["micIn"], f"{mic}")
        if case["ops"] is MIC_OPS_TRIMMED:
            check(f"{tag}: trim_start(clip 6, to {FRAME_30}) then move_clip([6], −{FRAME_30}) — "
                  "start back to 0, `in` keeps the head",
                  len(ops) == 7 and ops[5] == {"op": "trim_start", "clip": 6, "to": FRAME_30}
                  and ops[6] == {"op": "move_clip", "clips": [6], "delta": -FRAME_30}, f"{ops[5:]}")
        check(f"{tag}: two clips in the document", r.get("documentClips") == 2, f"{r.get('documentClips')}")

    # Row 4f.
    r = answer.get("row4f") or {}
    print("  row 4f — a live gesture")
    check(f"4·4f: beginLiveEdit() then placement throws {DRAG_REFUSAL!r}",
          r.get("message") == DRAG_REFUSAL, f"got {r.get('message')!r}")
    check("4·4f: the document was live during the call and not after endLiveEdit",
          r.get("liveDuring") is True and r.get("liveAfter") is False, f"{r}")
    check("4·4f: nothing was placed", r.get("clips") == 0 and r.get("media") == 0, f"{r}")

    # Row 5.
    r = answer.get("row5") or {}
    print("  row 5 — untitled(around:) on the real ProjectDocument, no microphone, 60 fps")
    check(f"4·5: displayName is the recording's stem {RECORDING_STEM!r}",
          r.get("displayName") == RECORDING_STEM == r.get("stem"),
          r.get("error") or f"got {r.get('displayName')!r}")
    check("4·5: the document is edited (dirty, as an opened movie is)", r.get("isDocumentEdited") is True,
          f"{r.get('isDocumentEdited')}")
    check("4·5: fileURL is nil — untitled", r.get("fileURL") == "<nil>", f"{r.get('fileURL')!r}")
    check(f"4·5: fileType is the package type {PACKAGE_TYPE!r}",
          r.get("fileType") == PACKAGE_TYPE == r.get("packageType"),
          f"{r.get('fileType')!r} vs {r.get('packageType')!r}")
    check("4·5: canvas.fps is [60, 1] — the recorder's rate (decision 3)",
          r.get("canvasFps") == [60, 1], f"got {r.get('canvasFps')}")
    check("4·5: … while media[0].fps stays the file's [24981, 1000]",
          r.get("mediaFps") == [24981, 1000], f"got {r.get('mediaFps')}")
    check("4·5: the canvas is the recording's 1728×1118", r.get("canvas") == [1728, 1118],
          f"got {r.get('canvas')}")
    check("4·5: no undo step — the first project is what the document is",
          r.get("canUndo") is False, f"{r.get('canUndo')}")
    check("4·5: one window controller", r.get("windows") == 1, f"{r.get('windows')}")
    check("4·5: the controller's documents went 0 → 1 (no double addDocument)",
          r.get("documentsBefore") == 0 and r.get("documentsAfter") == 1,
          f"{r.get('documentsBefore')} → {r.get('documentsAfter')}")
    check("4·5: one media, one track, one clip at 0 on it",
          r.get("media") == 1 and r.get("tracks") == 1 and r.get("clips") == 1
          and (r.get("clip") or {}).get("start") == 0
          and (r.get("clip") or {}).get("track") == r.get("trackId"), f"{r}")
    check("4·5: importSourceURL is the movie (what points the save panel at its folder)",
          r.get("importSourceURL") == r.get("moviePath") and r.get("moviePath"),
          f"{r.get('importSourceURL')!r}")

    # Row 5b, 5c.
    r = answer.get("row5b") or {}
    print("  row 5b — with a microphone at +12 000, 60 fps")
    check(f"4·5b: displayName {MIC_STEM!r}, edited", r.get("displayName") == MIC_STEM
          and r.get("isDocumentEdited") is True, f"{r.get('displayName')!r}")
    check("4·5b: two media, tracks [Microphone, Track 1], two clips",
          r.get("media") == 2 and r.get("tracks") == ["Microphone", "Track 1"] and r.get("clips") == 2,
          f"{r.get('media')}, {r.get('tracks')}, {r.get('clips')}")
    mic = r.get("mic") or {}
    check("4·5b: the mic clip is on the BACK track at 0",
          mic.get("track") == r.get("backTrack") and mic.get("start") == 0, f"{mic}, back {r.get('backTrack')}")
    check(f"4·5b: its in point is one 60 fps frame ({FRAME_60}) — the 12 000-tick head snapped",
          mic.get("in") == FRAME_60 == r.get("frame"), f"in {mic.get('in')}, frame {r.get('frame')}")
    picture = r.get("picture") or {}
    check("4·5b: the picture stays at 0 on the front track (makeProject placed it)",
          picture.get("start") == 0 and picture.get("track") == r.get("frontTrack"), f"{picture}")
    check(f"4·5b: ONE undo step named {MIC_ACTION_NAME!r} — not {ACTION_NAME!r}: the step removes "
          "the voice and keeps the picture",
          r.get("canUndo") is True and r.get("undoName") == MIC_ACTION_NAME, f"{r.get('undoName')!r}")
    check("4·5b: canvas.fps [60, 1], both media at their files' rates",
          r.get("canvasFps") == [60, 1] and r.get("mediaFps") == [[24981, 1000], [30, 1]],
          f"{r.get('canvasFps')}, {r.get('mediaFps')}")
    check("4·5b: one window controller, fileURL nil", r.get("windows") == 1 and r.get("fileURL") == "<nil>",
          f"{r.get('windows')}, {r.get('fileURL')!r}")
    r = answer.get("row5c") or {}
    check("4·5c: one undo → one media, one clip, one track (the picture stays, the voice goes)",
          r.get("media") == 1 and r.get("clips") == 1 and r.get("tracks") == 1, f"{r}")
    check("4·5c: … the clip left is the picture's, and the step is redoable",
          r.get("clipMedia") == r.get("pictureMedia") != -1 and r.get("canRedo") is True
          and r.get("canUndo") is False, f"{r}")
    check("4·5c: … and the document is STILL edited after the undo — the import count was made "
          "BEFORE the microphone's edit, so ⌘Z takes the count two → one, never to zero (the "
          "review measured ⌘W closing without a prompt)",
          r.get("isDocumentEdited") is True, f"isDocumentEdited {r.get('isDocumentEdited')}")
    check(f"4·5c: the redo is named {MIC_ACTION_NAME!r}; redone, the voice is back (two media), "
          "the document edited, the undo step named again",
          r.get("redoName") == MIC_ACTION_NAME and r.get("mediaAfterRedo") == 2
          and r.get("isDocumentEditedAfterRedo") is True and r.get("undoNameAfterRedo") == MIC_ACTION_NAME,
          f"{r}")
    check("4·5: both documents closed cleanly", answer.get("documentsAfterClose") == 0,
          f"{answer.get('documentsAfterClose')}")

    # Row 6.
    r = answer.get("row6") or {}
    print("  row 6 — resolve, over two open documents")
    check("4·6: two untitled documents open, A listed first", r.get("openDuring") == 2
          and r.get("firstIsA") is True, r.get("error") or f"{r}")
    check("4·6: B's recipeKey → B (not the first document)", r.get("B") == "B", f"got {r.get('B')}")
    check("4·6: A's recipeKey → A", r.get("A") == "A", f"got {r.get('A')}")
    check("4·6: an unknown key → .newProject while both are open",
          r.get("unknownWithBoth") == "newProject", f"got {r.get('unknownWithBoth')}")
    check("4·6: B closed → B's key is .newProject", r.get("BAfterClose") == "newProject",
          f"got {r.get('BAfterClose')}")
    check("4·6: … and A's is still A", r.get("AAfterBClose") == "A", f"got {r.get('AAfterBClose')}")
    check("4·6: an unknown key with A open → .newProject", r.get("unknownWithA") == "newProject",
          f"got {r.get('unknownWithA')}")
    check("4·6: .newProject → .newProject", r.get("plain") == "newProject", f"got {r.get('plain')}")
    check("4·6: A closed → .newProject, nothing left open",
          r.get("AAfterClose") == "newProject" and r.get("openAfter") == 0, f"{r}")

    # Row 7.
    r = answer.get("row7") or {}
    print("  row 7 — inside an open nest")
    nest_ops = ["add_media", "add_track", "add_clip", "add_media", "add_track", "add_clip",
                "trim_start", "move_clip"]
    check("4·7: the document's scope is the nest", r.get("scope") == r.get("nestId") != -1
          and r.get("scope") is not None, r.get("error") or f"scope {r.get('scope')}, nest {r.get('nestId')}")
    check(f"4·7: eight ops {nest_ops}", r.get("ops") == nest_ops, f"got {r.get('ops')}")
    check("4·7: every op is UNSCOPED — the door stamps the scope",
          bool(r.get("scopes")) and all(s == -1 for s in r.get("scopes")), f"{r.get('scopes')}")
    pred = r.get("predicted") or {}
    check("4·7: the core minted the predicted media",
          r.get("mintedMedia") == [pred.get("media"), pred.get("micMedia")] and pred.get("media") != -1,
          f"{r.get('mintedMedia')} vs {pred}")
    clips = r.get("mintedClips") or []
    picture = next((c for c in clips if c.get("media") == pred.get("media")), None)
    mic = next((c for c in clips if c.get("media") == pred.get("micMedia")), None)
    check("4·7: both clips carry their predicted ids",
          picture is not None and mic is not None and picture.get("id") == pred.get("clip")
          and mic.get("id") == pred.get("micClip"), f"{clips} vs {pred}")
    ops = op_json(r)
    check("4·7: the picture's add_track is index 1 (the nest had one track) and the clip is on "
          "the nest's new FRONT track",
          len(ops) > 1 and ops[1] == {"op": "add_track", "index": 1}
          and picture is not None and picture.get("track") == r.get("innerFrontTrack"),
          f"{ops[1] if len(ops) > 1 else ops}, picture {picture}, front {r.get('innerFrontTrack')}")
    inner = r.get("innerTracks") or []
    check("4·7: the nest has three tracks with Microphone at the BACK, and the mic clip is on it",
          len(inner) == 3 and inner[0].get("name") == "Microphone"
          and mic is not None and mic.get("track") == inner[0].get("id") == r.get("innerBackTrack"),
          f"{inner}, mic {mic}")
    check(f"4·7: the head is trimmed one frame ({FRAME_30}) — the nest's frozen 30 fps canvas",
          mic is not None and mic.get("in") == FRAME_30 and mic.get("start") == 0
          and r.get("frame") == FRAME_30, f"{mic}, frame {r.get('frame')}")
    check("4·7: the nest holds three clips; the document's timeline still holds ONE (the nest clip) "
          "on one track", r.get("innerClips") == 3 and r.get("outerClips") == 1
          and r.get("outerTracks") == 1 and r.get("documentClips") == 1, f"{r}")
    check("4·7: the media went on the DOCUMENT (three, the blocker's and the two files)",
          r.get("outerMedia") == 3 and r.get("innerMedia") == 3, f"{r.get('outerMedia')}, {r.get('innerMedia')}")

    # Row 8.
    r = answer.get("row8") or {}
    print("  row 8 — the caps in the TRIAL: a document at MAX_TRACKS (64), top level and inside a nest")
    check("4·8: the document holds MAX_TRACKS = 64 tracks", r.get("tracks") == 64,
          r.get("error") or f"got {r.get('tracks')}")
    check("4·8a: without a microphone the picture lands on the empty front track at the cap — "
          "[add_media, add_clip], no track needed",
          r.get("pictureOps") == ["add_media", "add_clip"], f"got {r.get('pictureOps')}")
    check(f"4·8b: with a microphone the TRIAL throws the core's own sentence {CAP_SENTENCE!r} — the "
          "microphone's track would be the 65th",
          CAP_SENTENCE in str(r.get("micError")), f"got {r.get('micError')!r}")
    check("4·8b: … and nothing landed — the picture goes down with the voice (the one-list limit): "
          "media 0, clips 0, tracks 64, the last undo step still the fill's",
          r.get("mediaAfter") == 0 and r.get("clipsAfter") == 0 and r.get("tracksAfter") == 64
          and r.get("undoNameAfter") == "fill",
          f"media {r.get('mediaAfter')}, clips {r.get('clipsAfter')}, tracks {r.get('tracksAfter')}, "
          f"undo {r.get('undoNameAfter')!r}")
    check("4·8c: inside a nest at the cap — 63 outer tracks and the nest's one — with the scope open",
          r.get("nestScope") not in (None, -1) and r.get("nestOuterTracks") == 63
          and r.get("nestInnerTracks") == 1,
          f"scope {r.get('nestScope')}, outer {r.get('nestOuterTracks')}, inner {r.get('nestInnerTracks')}")
    check(f"4·8c: the picture alone throws {CAP_SENTENCE!r} in the TRIAL — check_caps runs on the MERGED "
          "parent, and the trial applies each scoped op to that parent (the sentence the landing's "
          "old comment said the trial could not see)",
          CAP_SENTENCE in str(r.get("nestError")), f"got {r.get('nestError')!r}")
    check("4·8c: nothing landed inside or out — the blocker's media alone, the nest's one clip on its "
          "one track, 63 outer tracks",
          r.get("nestMediaAfter") == 1 and r.get("nestInnerClipsAfter") == 1
          and r.get("nestInnerTracksAfter") == 1 and r.get("nestOuterTracksAfter") == 63,
          f"media {r.get('nestMediaAfter')}, inner clips {r.get('nestInnerClipsAfter')}, inner tracks "
          f"{r.get('nestInnerTracksAfter')}, outer tracks {r.get('nestOuterTracksAfter')}")
    u = r.get("under") or {}
    check("4·8d: one track UNDER the cap the same nested landing trials clean and commits — "
          "[add_media, add_track, add_clip], the 64th track inside the nest (2 inner, 62 outer)",
          u.get("ops") == ["add_media", "add_track", "add_clip"] and u.get("innerTracksAfter") == 2
          and u.get("outerTracksAfter") == 62, u.get("error") or f"{u}")
    pred = u.get("predicted") or {}
    minted_track = (u.get("mintedTracks") or [{}])[0].get("id")
    picture = next((c for c in u.get("mintedClips") or [] if c.get("media") == pred.get("media")), None)
    check("4·8d: … the picture clip minted with its predicted id, on the new inner track",
          picture is not None and picture.get("id") == pred.get("clip") != -1
          and picture.get("track") == minted_track is not None, f"{picture} vs {pred}, track {minted_track}")


# --------------------------------------------------------------------------
# Section 4b — the landing over a SEQUENCE (road map 3, R2b): lane L's rows.

SEG_LEN = 5 * SEC                      # each picture fixture's 5 s
SEGMENTS_ACTION_NAME = "Add Recording Segments"
# Offsets AT the floor (voice 1 ends exactly where picture 2 starts): the
# head is the offset snapped to the 30 fps grid, half away from zero, so
# 9 999 is no trim and 10 000 is one frame.
BOUNDARY_OFFSETS = [4_000, 9_999, 10_000, 15_000, 31_000]
SEQUENCE_OPS = ["add_media", "add_media", "add_clip", "add_clip"]
SEQUENCE_OPS_NEW_TRACK = ["add_media", "add_media", "add_track", "add_clip", "add_clip"]


def snap(ticks, frame):
    """The core's own rounding of a time argument to the frame grid."""
    return (ticks + frame // 2) // frame * frame


def section_segments(binary, sources):
    print("\nSection 4b — the landing over a SEQUENCE (road map 3, R2b): touching clips on ONE track "
          "with the ends read off the handle, the two-try rule over the whole sequence, the "
          "microphone floor, and the untitled remainder")
    tmp = fresh_dir("segments")
    answer, error = run_probe(binary, "segments", {
        "mode": "segments", "tempFolder": tmp, "boundaryOffsets": BOUNDARY_OFFSETS})
    check("4b: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    check("4b: the probe's NSDocumentController subclass is `.shared`", answer.get("controllerIsProbe") is True)

    def lists(r):
        return r.get("predictedLists") or {}

    def clips_of(r, ids):
        """The minted clips for a list of predicted ids, an entry nothing
        was minted for (−1) skipped."""
        by = {c.get("id"): c for c in r.get("mintedClips") or []}
        return [by.get(i) or {} for i in ids if i != -1]

    def one_track(cs):
        return bool(cs) and all(c.get("track") == cs[0].get("track") for c in cs)

    def touching(cs):
        return bool(cs) and all(cs[i + 1].get("start") == cs[i].get("end") for i in range(len(cs) - 1))

    def no_transition(cs):
        return not any(c.get("transition") for c in cs)

    # A.
    r = answer.get("A") or {}
    print("  A — two segments on a fresh document")
    check(f"4b·A: ops {SEQUENCE_OPS}", r.get("ops") == SEQUENCE_OPS, r.get("error") or f"got {r.get('ops')}")
    check("4b·A: mediaIds [2, 3], clipIds [4, 5], the two mic lists one nil entry per segment — every "
          "list ONE entry per segment, each id off the purely-applied result before it",
          lists(r) == {"media": [2, 3], "clips": [4, 5], "micMedia": [-1, -1], "micClips": [-1, -1]},
          f"{lists(r)}")
    check("4b·A: no note — everything landed", r.get("notes") == [], f"{r.get('notes')}")
    check("4b·A: the singulars are the FIRST of each list (R1's fields kept)",
          r.get("predicted") == {"media": 2, "clip": 4, "micMedia": -1, "micClip": -1}, f"{r.get('predicted')}")
    check("4b·A: the core minted the media and the clips the landing predicted",
          r.get("mintedMedia") == [2, 3] and sorted(c.get("id") for c in r.get("mintedClips") or []) == [4, 5],
          f"media {r.get('mintedMedia')}, clips {r.get('mintedClips')}")
    cs = clips_of(r, [4, 5])
    check(f"4b·A: clip 1 at 0 for the 5 s ({SEG_LEN}), in 0",
          cs[0].get("start") == 0 and cs[0].get("duration") == SEG_LEN and cs[0].get("in") == 0, f"{cs[0]}")
    check("4b·A: clip 2 starts at clip 1's END on the SAME track — back to back (segment-stacked)",
          cs[1].get("start") == cs[0].get("end") == SEG_LEN and cs[1].get("track") == cs[0].get("track") == 1,
          f"{cs[1]} after {cs[0]}")
    check("4b·A: neither carries a transition — two clips meeting at one tick are a cut, not an overlap",
          no_transition(cs))
    check(f"4b·A: no track was added; one undo step named {ACTION_NAME!r}",
          r.get("mintedTracks") == [] and r.get("undoName") == ACTION_NAME and r.get("canUndo") is True,
          f"tracks {r.get('mintedTracks')}, undo {r.get('undoName')!r}")
    ops = op_json(r)
    check(f"4b·A: the second add_clip is SENT at {SEG_LEN} — the end read off the trial",
          len(ops) == 4 and ops[3] == {"op": "add_clip", "track": 1, "media": 3, "at": SEG_LEN}, f"{ops}")

    # B.
    r = answer.get("B") or {}
    print("  B — off-grid durations: the end is READ off the core, never summed")
    cs = clips_of(r, lists(r).get("clips") or [])
    check("4b·B: three clips minted", len(cs) == 3 and all(cs), r.get("error") or f"{cs}")
    if len(cs) == 3:
        check("4b·B: clip 1's 3 000 007 ticks snapped to 3 000 000 (the 30 fps grid) — the length the "
              "core reports", cs[0].get("duration") == 3_000_000, f"{cs[0]}")
        check("4b·B: clip 2 at 3 000 000 — clip 1's END, not 3 000 007",
              cs[1].get("start") == 3_000_000 == cs[0].get("end"), f"{cs[1]}")
        check("4b·B: clip 2's 1 504 999 snapped to 1 500 000", cs[1].get("duration") == 1_500_000, f"{cs[1]}")
        check("4b·B: clip 3 at 4 500 000, clip 2's end", cs[2].get("start") == 4_500_000 == cs[1].get("end"),
              f"{cs[2]}")
        check("4b·B: all on one track, touching, no transitions",
              one_track(cs) and touching(cs) and no_transition(cs), f"{cs}")

    # C, D.
    for tag, title in (("C", "the SECOND segment refuses on the front track (a blocker at 7–15 s)"),
                       ("D", "the FIRST segment refuses (a blocker at 1–9 s)")):
        r = answer.get(tag) or {}
        print(f"  {tag} — {title}: ALL on a new track")
        check(f"4b·{tag}: ops {SEQUENCE_OPS_NEW_TRACK}", r.get("ops") == SEQUENCE_OPS_NEW_TRACK,
              r.get("error") or f"got {r.get('ops')}")
        cs = clips_of(r, lists(r).get("clips") or [])
        new_track = r.get("frontTrackAfter")
        tracks = r.get("mintedTracks") or [{}]
        check(f"4b·{tag}: one new FRONT track with the predicted id — next_id after the two media "
              f"({(r.get('nextIdBefore') or 0) + 2})",
              len(tracks) == 1 and tracks[0].get("id") == new_track == (r.get("nextIdBefore") or 0) + 2
              and (r.get("viewTracks") or [{}])[-1].get("id") == new_track,
              f"tracks {tracks}, front after {new_track}, next_id before {r.get('nextIdBefore')}")
        check(f"4b·{tag}: BOTH clips on the new track, touching from 0, no transition — the sequence "
              "never splits",
              len(cs) == 2 and all(c.get("track") == new_track for c in cs) and cs[0].get("start") == 0
              and touching(cs) and no_transition(cs), f"{cs}")
        check(f"4b·{tag}: the blocker's track still holds only the blocker",
              sum(1 for c in r.get("allClips") or [] if c.get("track") == r.get("frontTrackBefore")) == 1,
              f"{r.get('allClips')}")
        ops = op_json(r)
        check(f"4b·{tag}: add_track(index: 1), then both add_clips name the new track",
              len(ops) == 5 and ops[2] == {"op": "add_track", "index": 1}
              and ops[3].get("track") == new_track == ops[4].get("track"), f"{ops}")

    # E.
    r = answer.get("E") or {}
    print("  E — the microphone floor: voice 2 wants 3 000 000 − 11 000, the floor is voice 1's end")
    frame = r.get("frame") or FRAME_30
    check(f"4b·E: the canvas frame is {FRAME_30}", frame == FRAME_30, r.get("error") or f"got {frame}")
    check("4b·E: ops — the pictures, then each voice's media, ONE Microphone track, voice 1's add_clip, "
          "voice 2's add_clip at the floor + trim_start + move_clip",
          r.get("ops") == ["add_media", "add_media", "add_clip", "add_clip", "add_media", "add_media",
                           "add_track", "add_clip", "add_clip", "trim_start", "move_clip"],
          f"got {r.get('ops')}")
    L = lists(r)
    check("4b·E: two mic media ids and two mic clip ids, one per segment, none nil",
          len(L.get("micMedia") or []) == 2 and len(L.get("micClips") or []) == 2
          and -1 not in (L.get("micMedia") or [-1]) and -1 not in (L.get("micClips") or [-1]), f"{L}")
    tracks = r.get("mintedTracks") or []
    check("4b·E: one Microphone track, at the BACK, added once",
          len(tracks) == 1 and tracks[0].get("name") == "Microphone"
          and (r.get("viewTracks") or [{}])[0].get("id") == tracks[0].get("id")
          and len(r.get("viewTracks") or []) == 2, f"{tracks}, view {r.get('viewTracks')}")
    m = clips_of(r, L.get("micClips") or [])
    # A LENGTH snaps DOWN, so the clip stops on the last whole frame inside
    # the file (spec §11); `snap` above is still the rule for a START.
    d1 = 3_012_000 // frame * frame
    head = snap(d1 - (3_000_000 - 11_000), frame)
    check(f"4b·E: voice 1 at 0, the snapped length {d1}, in 0",
          len(m) == 2 and m[0].get("start") == 0 and m[0].get("duration") == d1 and m[0].get("in") == 0,
          f"{m[:1]}")
    check(f"4b·E: voice 2 at the floor {d1} — voice 1's end, read off the trial — with the head {head} "
          f"trimmed (in {head}, length {d1 - head}), never at 2 989 000, which the core would snap a "
          "frame UNDER the floor and accept as a transition (mic-floor-dropped)",
          len(m) == 2 and m[1].get("start") == d1 == m[0].get("end") and m[1].get("in") == head
          and m[1].get("duration") == d1 - head, f"{m[1:]}")
    check("4b·E: the two voices touch on one track, and no minted clip carries a transition",
          len(m) == 2 and m[1].get("track") == m[0].get("track") and no_transition(r.get("mintedClips") or []),
          f"{r.get('mintedClips')}")
    check("4b·E: every minted clip id was predicted",
          sorted(c.get("id") for c in r.get("mintedClips") or [])
          == sorted((L.get("clips") or []) + (L.get("micClips") or [])), f"{r.get('mintedClips')} vs {L}")
    ops = op_json(r)
    mic2 = (L.get("micClips") or [0, 0])[1]
    check(f"4b·E: the ops send add_clip at the floor {d1}, trim_start to {d1 + head}, move_clip by −{head}",
          len(ops) == 11 and ops[8].get("op") == "add_clip" and ops[8].get("at") == d1
          and ops[9] == {"op": "trim_start", "clip": mic2, "to": d1 + head}
          and ops[10] == {"op": "move_clip", "clips": [mic2], "delta": -head}, f"{ops[8:]}")

    # E2.
    r = answer.get("E2") or {}
    print("  E2 — a lagging microphone (offset −30 000) is above the floor: no trim")
    check("4b·E2: no trim_start in the ops", not r.get("error") and "trim_start" not in (r.get("ops") or []),
          r.get("error") or f"{r.get('ops')}")
    m = clips_of(r, lists(r).get("micClips") or [])
    check(f"4b·E2: voice 2 at the core's snap of 3 030 000 ({snap(3_030_000, frame)}), in 0, above voice "
          "1's end, no transition",
          len(m) == 2 and m[1].get("start") == snap(3_030_000, frame) and m[1].get("in") == 0
          and m[1].get("start") >= m[0].get("end") and not m[1].get("transition"), f"{m}")

    # E3.
    print("  E3 — rounding AT the floor: voice 1 ends exactly where picture 2 starts")
    rows = {row.get("offset"): row for row in answer.get("E3") or []}
    for offset in BOUNDARY_OFFSETS:
        r = rows.get(offset) or {}
        m = clips_of(r, lists(r).get("micClips") or [])
        h = snap(offset, frame)
        check(f"4b·E3: offset +{offset} → voice 2 AT the floor ({3_000_000}) with the head {h} trimmed "
              f"({'no trim' if h == 0 else 'one frame' if h == frame else f'{h // frame} frames'}), no "
              "transition on either",
              len(m) == 2 and m[1].get("start") == m[0].get("end") == 3_000_000 and m[1].get("in") == h
              and not m[0].get("transition") and not m[1].get("transition"), r.get("error") or f"{m}")
        check(f"4b·E3: offset +{offset} → trim_start sent iff the head is non-zero",
              ("trim_start" in (r.get("ops") or [])) == (h > 0), f"{r.get('ops')}")

    # E4.
    r = answer.get("E4") or {}
    check("4b·E4: the hazard the floor exists for, on the core directly — an add_clip three quarters "
          "of a frame under a clip's end is snapped a frame EARLY (2 980 000) and ACCEPTED, as a "
          "one-frame overlap carrying a transition",
          r.get("accepted") is True and (r.get("clip") or {}).get("start") == 3_000_000 - (r.get("frame") or 0)
          and (r.get("clip") or {}).get("transition") is True, r.get("error") or f"{r}")

    # F.
    r = answer.get("F") or {}
    print("  F — a middle segment with no microphone")
    L = lists(r)
    check("4b·F: the mic lists have THREE entries with the middle one nil — ONE entry per segment, "
          "aligned by index with the clips (the R2 review: an iterator over the segments that have a "
          "file misaligned the two lists)",
          len(L.get("micMedia") or []) == 3 and (L.get("micMedia") or [0])[1] == -1
          and (L.get("micMedia") or [-1])[0] != -1 and (L.get("micMedia") or [-1, -1, -1])[2] != -1
          and len(L.get("micClips") or []) == 3 and (L.get("micClips") or [0])[1] == -1
          and len(L.get("clips") or []) == 3, r.get("error") or f"{L}")
    m = clips_of(r, L.get("micClips") or [])
    check(f"4b·F: voice 3 at the snap of picture 3's start − 12 000 ({snap(2 * SEG_LEN - 12_000, frame)}), "
          "above the floor, in 0",
          len(m) == 2 and m[1].get("start") == snap(2 * SEG_LEN - 12_000, frame) and m[1].get("in") == 0,
          f"{m}")
    cs = clips_of(r, L.get("clips") or [])
    check("4b·F: three pictures touching on one track, no transitions",
          len(cs) == 3 and touching(cs) and one_track(cs) and no_transition(cs), f"{cs}")

    # G.
    r = answer.get("G") or {}
    L = lists(r)
    check("4b·G: place false → [add_media, add_media, add_media] — every picture's, then the "
          "microphone's — clipIds and micClipIds one nil per segment, micMediaIds [id, nil], no clip "
          "minted, three media in the document",
          r.get("ops") == ["add_media"] * 3 and L.get("clips") == [-1, -1] and L.get("micClips") == [-1, -1]
          and len(L.get("micMedia") or []) == 2 and (L.get("micMedia") or [-1])[0] != -1
          and (L.get("micMedia") or [0, 0])[1] == -1 and len(L.get("media") or []) == 2
          and r.get("mintedClips") == [] and r.get("documentMedia") == 3, r.get("error") or f"{r.get('ops')}, {L}")

    # H.
    r = answer.get("H") or {}
    print("  H — inside a nest whose clip blocks the playhead: the ends are read off the VIEW")
    check(f"4b·H: the scope is open and the ops are {SEQUENCE_OPS_NEW_TRACK}, every one UNSCOPED (the "
          "door stamps)", r.get("scopeOpen") is True and r.get("ops") == SEQUENCE_OPS_NEW_TRACK
          and bool(r.get("scopes")) and all(s == -1 for s in r.get("scopes")),
          r.get("error") or f"{r.get('ops')}, scopes {r.get('scopes')}")
    cs = clips_of(r, lists(r).get("clips") or [])
    check("4b·H: two clips INSIDE the nest, touching, one track, no transition",
          len(cs) == 2 and touching(cs) and one_track(cs) and no_transition(cs), f"{cs}")
    check("4b·H: the parent still holds ONE clip (the nest) on one track, and three media",
          r.get("outerClips") == 1 and r.get("outerMedia") == 3 and r.get("outerTracks") == 1, f"{r}")

    # J.
    r = answer.get("J") or {}
    print("  J — an INEXACT canvas rate (24981/1000): the previous end is not a grid point")
    cs = clips_of(r, lists(r).get("clips") or [])
    jf = r.get("frame") or 0
    check("4b·J: the canvas is 24981/1000 and three clips landed on one track",
          r.get("canvasFps") == [24981, 1000] and len(cs) == 3 and one_track(cs), r.get("error") or f"{r.get('canvasFps')}, {cs}")
    check("4b·J: each later segment starts AT or AFTER the previous end, by at most a frame — touching, "
          "or the next grid point up when the core would have snapped the end a tick DOWN (measured: "
          "clip 3 a whole 24 018-tick frame after clip 2's 6 004 564, whose nearest grid point is "
          "6 004 563) — never a tick of overlap (the R2 review)",
          len(cs) == 3 and all(0 <= cs[i + 1].get("start", -1) - cs[i].get("end", 0) <= max(jf, 1) for i in range(2)),
          f"{[(c.get('start'), c.get('end')) for c in cs]}, frame {jf}")
    check("4b·J: … and at least one of the two joins is NOT a touch — the inexact rate is doing something "
          "the row can see", len(cs) == 3 and any(cs[i + 1].get("start") != cs[i].get("end") for i in range(2)),
          f"{[(c.get('start'), c.get('end')) for c in cs]}")
    check("4b·J: no cross dissolve minted between two halves of one recording — no transitionIn anywhere",
          len(cs) == 3 and no_transition(r.get("mintedClips") or []), f"{r.get('mintedClips')}")

    # K, L, M, N — what the landing could not place, named in `notes`.
    r = answer.get("K") or {}
    print("  K — a voice SHORTER than its head (mic 1 ends 3 040 000; picture 2 at 3 000 000; mic 2 an "
          "80 ms file with offset +18 000)")
    L = lists(r)
    check("4b·K: the second voice mints NO clip — micClipIds [id, nil] — and no sliver is placed late "
          "(the review's 20 000-tick clip at 3 060 000)",
          len(L.get("micClips") or []) == 2 and (L.get("micClips") or [-1])[0] != -1
          and (L.get("micClips") or [0, 0])[1] == -1 and "trim_start" not in (r.get("ops") or [])
          and len(r.get("mintedClips") or []) == 3, r.get("error") or f"{L}, ops {r.get('ops')}, clips {r.get('mintedClips')}")
    check("4b·K: … its MEDIA still lands (micMediaIds two ids), and ONE note names that file",
          len(L.get("micMedia") or []) == 2 and -1 not in (L.get("micMedia") or [-1])
          and len(r.get("notes") or []) == 1 and "seg2 (Microphone).m4a" in (r.get("notes") or [""])[0],
          f"{L}, notes {r.get('notes')}")
    check("4b·K: no refused op in the list — the trial's ops all committed, no transition anywhere",
          r.get("canUndo") is True and no_transition(r.get("mintedClips") or []), f"{r.get('mintedClips')}")
    r = answer.get("L") or {}
    L = lists(r)
    check("4b·L: a microphone file under one frame (R0 q7's 2 ms file) mints no clip and a note naming it; "
          "the pictures and voice 1 land",
          len(L.get("micClips") or []) == 2 and (L.get("micClips") or [-1])[0] != -1
          and (L.get("micClips") or [0, 0])[1] == -1 and len(r.get("mintedClips") or []) == 3
          and len(r.get("notes") or []) == 1 and "seg2 (Microphone).m4a" in (r.get("notes") or [""])[0],
          r.get("error") or f"{L}, clips {r.get('mintedClips')}, notes {r.get('notes')}")
    r = answer.get("M") or {}
    L = lists(r)
    cs = clips_of(r, L.get("clips") or [])
    check("4b·M: a PICTURE under one frame in the middle mints no clip — clipIds [id, nil, id] — and a "
          "note naming its movie; its media lands",
          L.get("clips", [None, None, None])[1:2] == [-1] and (L.get("clips") or [-1])[0] != -1
          and (L.get("clips") or [-1, -1, -1])[2] != -1 and len(r.get("notes") or []) == 1
          and "seg2.mov" in (r.get("notes") or [""])[0] and r.get("documentMedia") == 3,
          r.get("error") or f"{L}, notes {r.get('notes')}")
    check("4b·M: … and segment 3's picture follows segment 1's END on the same track, no transition",
          len(cs) == 2 and cs[1].get("start") == cs[0].get("end") and one_track(cs) and no_transition(cs), f"{cs}")
    r = answer.get("N") or {}
    L = lists(r)
    check("4b·N: remainderPlacement with NO clip 1 (the document holds the picture's media alone) lands "
          "the microphone's MEDIA only — [add_media], micMediaIds [id], micClipIds [nil], clipIds [nil]",
          r.get("ops") == ["add_media"] and len(L.get("micMedia") or []) == 1 and (L.get("micMedia") or [-1])[0] != -1
          and L.get("micClips") == [-1] and L.get("clips") == [-1] and r.get("mintedClips") == [],
          r.get("error") or f"{r.get('ops')}, {L}, {r.get('mintedClips')}")
    check("4b·N: … with a note saying so", len(r.get("notes") or []) >= 1, f"{r.get('notes')}")

    # I.
    names = answer.get("names") or {}
    print("  I — untitled(around:): the remainder through the real order, and its two names")
    check(f"4b·I: remainderActionName — three segments → {SEGMENTS_ACTION_NAME!r}; one with a microphone "
          f"→ {MIC_ACTION_NAME!r}; two without → {SEGMENTS_ACTION_NAME!r}",
          names.get("three") == SEGMENTS_ACTION_NAME == names.get("twoNoMic")
          and names.get("oneMic") == MIC_ACTION_NAME, f"{names}")
    check(f"4b·I: the constants are those two strings and {ACTION_NAME!r} stays the document landing's",
          names.get("segmentsActionName") == SEGMENTS_ACTION_NAME
          and names.get("microphoneActionName") == MIC_ACTION_NAME and names.get("actionName") == ACTION_NAME,
          f"{names}")
    check("4b·I: remainderPlacement of one segment with no microphone is nil — nothing to add",
          (answer.get("remainderNil") or {}).get("nil") is True, f"{answer.get('remainderNil')}")
    r = answer.get("I") or {}
    check("4b·I: three segments, voices on 1 and 3 — displayName seg1 (the first segment IS the "
          "document), canvas [60, 1], one window, one document opened",
          r.get("displayName") == "seg1" and r.get("canvasFps") == [60, 1] and r.get("windows") == 1
          and r.get("documents") == 1, r.get("error") or f"{r.get('displayName')!r}, {r.get('canvasFps')}, "
          f"windows {r.get('windows')}, documents {r.get('documents')}")
    check(f"4b·I: edited, ONE undo step named {SEGMENTS_ACTION_NAME!r}",
          r.get("edited") is True and r.get("undoName") == SEGMENTS_ACTION_NAME, f"{r.get('undoName')!r}")
    check("4b·I: five media (three pictures, two voices), tracks [Microphone, Track 1]",
          r.get("media") == 5 and r.get("tracks") == ["Microphone", "Track 1"],
          f"{r.get('media')}, {r.get('tracks')}")
    clips = r.get("clips") or []
    pics = sorted([c for c in clips if c.get("track") == r.get("frontTrack")], key=lambda c: c.get("start", 0))
    mics = sorted([c for c in clips if c.get("track") == r.get("backTrack")], key=lambda c: c.get("start", 0))
    check("4b·I: three pictures touching on Track 1 from 0, no transitions — segments 2 and 3 placed "
          "from clip 1's END", len(pics) == 3 and pics[0].get("start") == 0 and touching(pics)
          and no_transition(pics), f"{pics}")
    check(f"4b·I: the untitled canvas frame is {FRAME_60} (60 fps)", r.get("frame") == FRAME_60, f"{r.get('frame')}")
    want3 = snap((pics[2].get("start") if len(pics) == 3 else 0) - 11_000, FRAME_60)
    check(f"4b·I: voice 1 at 0, 3 010 000 long (3 012 000 snapped to the 60 fps grid); voice 3 at the "
          f"60 fps snap of picture 3's start − 11 000 ({want3}), untrimmed (above the floor)",
          len(mics) == 2 and mics[0].get("start") == 0 and mics[0].get("duration") == 3_010_000
          and mics[1].get("start") == want3 and mics[1].get("in") == 0, f"{mics}")
    u = r.get("afterUndo") or {}
    check("4b·I: one undo leaves segment 1 alone — one clip, one media, one track — the document STILL "
          "edited (the import count is made first), the redo named the same",
          u.get("clips") == 1 and u.get("media") == 1 and u.get("tracks") == 1 and u.get("edited") is True
          and u.get("redoName") == SEGMENTS_ACTION_NAME, f"{u}")
    r2 = answer.get("I2") or {}
    check(f"4b·I2: one segment with a microphone at +12 000: the step is {MIC_ACTION_NAME!r} — R1's "
          "landing, R1's name", r2.get("undoName") == MIC_ACTION_NAME and r2.get("media") == 2
          and r2.get("tracks") == ["Microphone", "Track 1"], r2.get("error") or f"{r2}")
    m2 = [c for c in r2.get("clips") or [] if c.get("track") == r2.get("backTrack")]
    check(f"4b·I2: … the voice at 0 with a {FRAME_60} head trimmed",
          len(m2) == 1 and m2[0].get("start") == 0 and m2[0].get("in") == FRAME_60, f"{m2}")
    r3 = answer.get("I3") or {}
    check("4b·I3: one segment, no microphone: NO undo step, still dirty, one media, one clip",
          r3.get("canUndo") is False and r3.get("edited") is True and r3.get("media") == 1
          and r3.get("clips") == 1, r3.get("error") or f"{r3}")
    check("4b·I: every document closed", answer.get("documentsAfterClose") == 0,
          f"{answer.get('documentsAfterClose')}")


# --------------------------------------------------------------------------
# Section 5 — the chrome's structure (road map 3, R1c): lane C's rows.

PANEL_ROWS = [
    ("isPanel", True), ("nonactivating", True), ("titled", True), ("closable", True),
    ("floating", True), ("hidesOnDeactivate", False), ("excluded", True), ("released", False),
    ("delegateNil", True), ("title", "New Recording"), ("visible", False),
    ("destinationFirst", "New Project"), ("destinationCount", 1), ("microphoneFirst", "Off"),
    ("sourceLast", "Microphone Only"), ("sourceLastTag", 2), ("recordTitle", "Record"),
    ("recordFillIsClip", True), ("recordTargetIsPanel", True), ("rate", 60),
    ("resolution", "nominal"), ("systemAudio", True), ("showClicks", False),
    ("microphoneOff", True), ("newProject", True), ("mainDisplay", True),
    ("includeFrameJobWindows", False), ("includeFrameJobTitle", "Include Frame Job windows"), ("idle", True),
    ("controlsEnabled", True), ("countdownHidden", True), ("noteHidden", True), ("meterWidth", 120),
]
COMMAND_OPTION = (1 << 20) | (1 << 19)   # NSEvent.ModifierFlags.command | .option
RECORDING_KEYS = ["displayKey", "microphoneKey", "systemAudioKey", "showClicksKey", "rateKey", "sizeKey",
                  "includeFrameJobWindowsKey"]


def section_chrome(binary, sources):
    print("\nSection 5 — the chrome's structure: the menu item, the welcome button, the panel, "
          "the status label, the meter view, and the quit guard")
    answer, error = run_probe(binary, "chrome", {"mode": "chrome"})
    check("5: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    print("  5a — File ▸ New Recording…")
    f = answer.get("file") or {}
    n = f.get("next") or {}
    check("5a: New Project is in the File menu", f.get("newProjectIndex", -1) >= 0, f"{f}")
    check("5a: the row after it is New Recording… (no separator between)",
          n.get("title") == "New Recording…" and n.get("separator") is False, f"{n}")
    check("5a: keyEquivalent n", n.get("key") == "n", f"{n.get('key')!r}")
    check(f"5a: modifiers ⌥⌘ (command | option = {COMMAND_OPTION})",
          n.get("modifiers") == COMMAND_OPTION, f"{n.get('modifiers')}")
    check("5a: action newRecording:", n.get("action") == "newRecording:", f"{n.get('action')!r}")
    check("5a: target nil — resolved down the responder chain, so it works with no document",
          n.get("hasTarget") is False, f"{n.get('hasTarget')}")
    check("5a: exactly one New Recording… row", f.get("count") == 1, f"{f.get('count')}")
    print("  5b — validateMenuItem, idle")
    v = answer.get("validate") or {}
    check("5b: the recorder is idle in the probe", v.get("recorderIdle") is True)
    check("5b: validateMenuItem returns true", v.get("enabled") is True, f"{v}")
    check("5b: … and leaves the title New Recording…", v.get("title") == "New Recording…", f"{v}")
    print("  5c — the welcome window")
    w = answer.get("welcome") or {}
    check("5c: three StickerButtons", w.get("count") == 3, f"{w.get('titles')}")
    check("5c: in the order Open Video… / New Project / New Recording…",
          w.get("titles") == ["Open Video…", "New Project", "New Recording…"], f"{w.get('titles')}")
    actions = w.get("actions") or []
    check("5c: the third's action is showRecorderPanel: — its OWN selector since the R2 review, which "
          "only shows (newRecording's first arm STOPS a running recording under a label that never "
          "retitles)", len(actions) == 3 and actions[2] == "showRecorderPanel:", f"{actions}")
    check("5c: … and its target nil", (w.get("targets") or [True] * 3)[-1] is False, f"{w.get('targets')}")
    check("5c: the other two are openDocument: and newProject:, unchanged",
          actions[:2] == ["openDocument:", "newProject:"], f"{actions}")
    print("  5d — the panel")
    p = answer.get("panel") or {}
    for key, want in PANEL_ROWS:
        check(f"5d: panel.{key} == {want!r}", p.get(key) == want, f"got {p.get(key)!r}")
    check("5d: Source rows = NSScreen.screens + a separator + Window… + Camera + Microphone Only "
          "(B66, CR1c)",
          p.get("sourceCount") == p.get("screens", -9) + 4
          and p.get("sourceSeparatorIndex") == p.get("screens"),
          f"count {p.get('sourceCount')}, screens {p.get('screens')}, separator at {p.get('sourceSeparatorIndex')}")
    check("5d: the window content is the card's size, 500 pt wide",
          abs(p.get("contentWidth", 0) - 500) < 0.5
          and abs(p.get("contentHeight", 0) - p.get("cardHeight", -1)) < 0.5,
          f"{p.get('contentWidth')} × {p.get('contentHeight')}, card {p.get('cardHeight')}")
    check("5d: the size note spells points and pixels",
          "points" in (p.get("sizeNote") or "") and "pixels" in (p.get("sizeNote") or ""),
          f"{p.get('sizeNote')!r}")
    check("5d: the footnote names the folder", (p.get("status") or "").startswith("saved in "),
          f"{p.get('status')!r}")
    rf = answer.get("refit") or {}
    check("5d: setNote(long) shows the note and grows the window", rf.get("grew") is True
          and rf.get("noteShown") is True, f"{rf}")
    check("5d: … keeping the window's TOP edge", rf.get("topKept") is True, f"{rf}")
    check("5d: … and setNote(\"\") hides it and shrinks the window back",
          rf.get("back") is True and rf.get("noteHiddenAfter") is True, f"{rf}")
    keys = answer.get("keys") or []
    check("5d: nine distinct FrameJobRecording… keys",
          len(set(keys)) == 9 and all(k.startswith("FrameJobRecording") for k in keys), f"{keys}")
    harness = open(HARNESS_MAIN).read()
    # The pins are spelled as string LITERALS in the harness, not as
    # `RecorderPanelController.<key>`, so that a tree from before the recorder
    # existed can still compile this instrument under -D HARNESS_REFERENCE_BUILD
    # (the phase-5 cross-build); the probe reads the constants' VALUES off the
    # app and looks for each of those strings in the harness's text.
    check("5d: the harness pins every one of them by VALUE",
          len(keys) == 9 and all(f'"{k}"' in harness for k in keys), f"{keys}")
    print("  5e — AccentButton(fill:) and RecorderStatusItem.label")
    a = answer.get("accent") or {}
    check("5e: AccentButton's default fill is DS.accent", a.get("defaultIsAccent") is True, f"{a}")
    check("5e: a passed fill is stored", a.get("storedRed") is True, f"{a}")
    s = answer.get("statusLabel") or {}
    for key, want in [("0", "0:00"), ("61", "1:01"), ("3661", "1:01:01"), ("neg", "0:00")]:
        check(f"5e: label(for: {key}) → {want!r}", s.get(key) == want, f"got {s.get(key)!r}")
    print("  5f — LevelMeterView(meter:)")
    m = answer.get("meter") or {}
    check("5f: a view over a fresh meter renders byte-identical to a default view at rest",
          m.get("restEqual") is True, f"{m}")
    check("5f: a 0.9 peak published to the fresh meter changes ITS render", m.get("ownLit") is True, f"{m}")
    check("5f: … and not the default (.shared) view's", m.get("defaultStill") is True, f"{m}")
    check("5f: a reading on .shared lights the default view", m.get("defaultLitByShared") is True, f"{m}")
    print("  5g — the retitle and the quit guard, the recorder's state written BY THE PROBE "
          "(a probe-only manipulation: `state` is internal, and it is reset in the same run)")
    q = answer.get("quit") or {}
    check("5g: the recorder was idle and the export queue is idle before the manipulation",
          q.get("stateBefore") == "idle" and q.get("queueIdle") is True, f"{q}")
    check("5g: with state = .recording the recorder reads isRecording", q.get("isRecordingWhileSet") is True)
    check("5g: validateMenuItem retitles the item Stop Recording (and keeps it enabled)",
          q.get("recordingTitle") == "Stop Recording" and q.get("recordingEnabled") is True,
          f"{q.get('recordingTitle')!r}, enabled {q.get('recordingEnabled')}")
    check("5g: applicationShouldTerminate answers .terminateCancel",
          q.get("recordingReply") == "terminateCancel", f"got {q.get('recordingReply')!r}")
    check("5g: … and brings the panel forward (it was not visible before)",
          q.get("panelVisibleBefore") is False and q.get("panelVisibleAfterCancel") is True,
          f"before {q.get('panelVisibleBefore')}, after {q.get('panelVisibleAfterCancel')}")
    check("5g: back at .idle the item reads New Recording… again",
          q.get("idleTitle") == "New Recording…" and q.get("idleEnabled") is True,
          f"{q.get('idleTitle')!r}")
    check("5g: … and the guard no longer cancels — .terminateNow, the queue being idle",
          q.get("idleReply") == "terminateNow", f"got {q.get('idleReply')!r}")
    check("5g: the probe left the recorder idle", q.get("stateAfter") == "idle", f"{q.get('stateAfter')}")

    print("  5h — the R1 review's chrome fixes, structural (no probe can press a panel's "
          "way into a capture)")
    rec = read_code(sources, "RecorderPanelController+Recording.swift")
    grants = read_code(sources, "RecorderPanelController+Grants.swift")
    land = read_code(sources, "RecorderPanelController+Landing.swift")
    base = read_code(sources, "RecorderPanelController.swift")
    showing = read_code(sources, "RecorderPanelController+Showing.swift")
    rows = read_code(sources, "RecorderPanelController+Rows.swift")
    route = read_code(sources, "AppDelegate+Recording.swift")
    status = read_code(sources, "RecorderStatusItem.swift")
    for name, code in [
        ("+Recording", rec), ("+Grants", grants), ("+Landing", land), ("base", base),
        ("+Showing", showing), ("+Rows", rows), ("+Recording (route)", route), ("status item", status),
    ]:
        check(f"5h: {name} is in the sources", code is not None)
    if None in (rec, grants, land, base, showing, rows, route, status):
        return
    # fix 1: the grant is asked on every press — no `canAsk` gate survives here
    # (canask-restored puts one back).
    check("5h: `+Recording.swift` and `+Grants.swift` gate no grant ask on canAsk (fix 1)",
          "canAsk" not in rec and "canAsk" not in grants, "a canAsk gate is back")
    check("5h: … and `+Grants.swift` still asks CGRequestScreenCaptureAccess on a press",
          "CGRequestScreenCaptureAccess()" in grants)
    # fix 3: land() compares the document's handle before trusting the commit.
    check("5h: `+Landing.swift`'s land() compares the project handle (fix 3, no-handle-check)",
          "!== before" in land, "the handle is not compared")
    # fix 6: the countdown and the tick run in .common run-loop modes.
    common = rec.count("forMode: .common")
    check("5h: `+Recording.swift` adds the countdown and the tick in .common modes (fix 6)",
          common == 2, f"found {common} .common timers, want 2")
    status_raw = ""
    status_path = os.path.join(sources, "RecorderStatusItem.swift")
    if os.path.exists(status_path):
        status_raw = open(status_path).read()
    check("5h: `RecorderStatusItem.swift`'s doc names the .common run-loop mode (fix 6)",
          ".common" in status_raw)
    # fix 5: fitWindowToContent constrains the grown frame to its screen.
    fit_body = "\n".join(function_body(showing.splitlines(), "func fitWindowToContent()") or [])
    check("5h: fitWindowToContent constrains the frame to its screen before setFrame "
          "(fix 5, no-constrain)",
          "constrainFrameRect" in fit_body and "window.screen" in fit_body, fit_body)
    # fix 9: microphoneAnswered guards visibility and re-enables the button.
    mic_body = function_body(grants.splitlines(), "func microphoneAnswered()")
    joined_mic = "\n".join(mic_body or [])
    check("5h: microphoneAnswered guards `window?.isVisible == true` (fix 9)",
          "isVisible == true" in joined_mic, joined_mic)
    check("5h: … and re-enables the Record button either way (fix 9)",
          "recordButton.isEnabled = true" in joined_mic)
    # fix 11: the microphone is prepared at the countdown and let go on every exit.
    check("5h: beginCountdown prepares the microphone (fix 11)",
          "prepareMicrophone" in "\n".join(function_body(rec.splitlines(), "func beginCountdown()") or []))
    for site, code, sig in [
        ("cancelCountdown", rec, "func cancelCountdown()"),
        ("startFailed", rec, "func startFailed(_ error: any Error)"),
        ("panelWillClose", base, "func panelWillClose(_ note: Notification)"),
    ]:
        body = "\n".join(function_body(code.splitlines(), sig) or [])
        check(f"5h: {site} discards the prepared microphone (fix 11)",
              "discardPreparedMicrophone" in body, body)
    check("5h: the tick reads ScreenRecorder.microphoneProblem (fix 11)",
          "microphoneProblem" in "\n".join(function_body(rec.splitlines(), "func syncMicrophoneNote()") or []))
    # fix 2: the start attempt is numbered and bounded.
    start_body = "\n".join(function_body(rec.splitlines(), "func startRecording()") or [])
    check("5h: startRecording numbers the attempt and arms the ceiling (fix 2)",
          "startGeneration" in start_body and "ScreenRecorder.armCeiling" in start_body, start_body)
    check("5h: a stale shareableContent answer is ignored by generation (fix 2)",
          "generation == self.startGeneration" in rec)
    # fix 12: New Recording… routes by whose recording it is.
    route_body = "\n".join(function_body(route.splitlines(), "func newRecording(_ sender: Any?)") or [])
    for token in ["panel.stopRecording()", "ScreenRecorder.shared.stop()", "panel.show()"]:
        check(f"5h: newRecording routes through `{token}` (fix 12)", token in route_body, route_body)

    print("  5i — the countdown grows the card (fix 5's premise; the constrain itself is 5h's "
          "structural read, because on this multi-display host NSWindow.setFrame already re-seats "
          "an off-screen titled panel, so a geometry differential cannot see the constrain)")
    c = answer.get("constrain") or {}
    check("5i: NSScreen.main was available to place the panel", bool(c), "no constrain answer")
    if c:
        check("5i: the countdown numeral and its note grow the card well past its idle height "
              "(fix 5's premise — 88 pt for the numeral, more with a note)",
              c.get("height", 0) > c.get("idleHeight", 1e9) + 40,
              f"idle {c.get('idleHeight')} -> grown {c.get('height')}")

    print("  5j — show() while hiddenForRecording (fix 7, show-while-hidden)")
    sh = answer.get("showHidden") or {}
    check("5j: show() leaves the panel invisible while a picked recording hid it",
          sh.get("visibleAfterShow") is False, f"{sh}")

    print("  5k — Record over the Window… row with no filter (fix 8, window-row-unguarded)")
    wr = answer.get("windowRow") or {}
    check("5k: record(_:) starts no countdown — the phase stays idle",
          wr.get("phaseIdle") is True, f"phaseIdle {wr.get('phaseIdle')}")
    check("5k: … and the note reads the choose-a-window sentence",
          wr.get("note") == wr.get("sentence") and bool(wr.get("sentence")), f"{wr}")

    print("  5l — a rebuild while recording leaves Record Into untouched (fix 4, sync-while-recording)")
    sr = answer.get("syncRec") or {}
    check("5l: the selected row's representedObject is unchanged (4242)",
          sr.get("after") == 4242 and sr.get("before") == 4242, f"{sr}")
    check("5l: … and the row was not rebuilt away (two items stand)",
          sr.get("count") == 2, f"count {sr.get('count')}")

    print("  5m — the .starting ceiling and its generation guard (fix 2, arm-no-generation)")
    ar = answer.get("arm") or {}
    check("5m: a stale ceiling (wrong generation) does nothing — the phase stays .starting",
          ar.get("staleStayed") is True, f"{ar}")
    check("5m: the current generation's ceiling fails the attempt to idle",
          ar.get("firedIdle") is True, f"{ar}")
    check("5m: … with the 20 s start sentence",
          ar.get("note") == "The recording did not start within 20 s.", f"{ar.get('note')!r}")
    check("5m: a launched attempt's ceiling is the recorder's, not the panel's",
          ar.get("launchedIgnored") is True, f"{ar}")

    print("  5n — the landing note is a pure function of the three facts (fix 10)")
    ln = answer.get("landingNote") or {}
    closed = ln.get("closedSentence") or "\u0000"
    menubar = ln.get("menuBarSentence") or "\u0000"
    check("5n: menu-bar stop into a NEW project names both the stop and the closed document",
          menubar in (ln.get("userStoppedNewProj") or "")
          and closed in (ln.get("userStoppedNewProj") or ""), f"{ln.get('userStoppedNewProj')!r}")
    check("5n: … but the SAME document does not name a closed one",
          menubar in (ln.get("userStoppedSameDoc") or "")
          and closed not in (ln.get("userStoppedSameDoc") or ""), f"{ln.get('userStoppedSameDoc')!r}")
    check("5n: a chosen NEW project that lands as one says nothing",
          ln.get("stoppedNewProjChosenNew") == "", f"{ln.get('stoppedNewProjChosenNew')!r}")
    check("5n: a microphone problem on an ordinary stop is the whole note",
          ln.get("micProblem") == "The microphone stopped.", f"{ln.get('micProblem')!r}")
    check("5n: an ordinary landing says nothing", ln.get("plain") == "", f"{ln.get('plain')!r}")

    print("  5o — New Recording… routes a tool's recording to the recorder (fix 12, route-to-show)")
    rt = answer.get("route") or {}
    check("5o: the panel was idle and the recorder read as recording",
          rt.get("panelPhaseIdle") is True, f"{rt}")
    check("5o: newRecording did not show the panel — it stopped the recorder instead",
          rt.get("panelShown") is False, f"panelShown {rt.get('panelShown')}")


# --------------------------------------------------------------------------
# Section 5, continued — road map 3, R2c: the status item's vocabulary, the
# .paused phase, the panel's two entries, the reveal, and the route.

PAUSE_GLYPH = "❚❚"


def section_chrome_pause(binary, sources):
    print("\nSection 5 (continued) — R2c: the status item's vocabulary, the .paused phase, "
          "pauseRecording()/resumeRecording(), revealIfNoted both ways, the route while paused, and the "
          "structural reads")
    work = fresh_dir("chrome-pause")
    answer, error = run_probe(binary, "chrome-pause", {"mode": "chrome-pause", "work": work})
    check("5p: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    print("  5p — RecorderStatusItem, pure")
    mt = answer.get("menuTitles") or {}
    check("5p: menuTitles(paused: false) is [Pause Recording, Stop Recording]",
          mt.get("recording") == ["Pause Recording", "Stop Recording"], f"{mt.get('recording')}")
    check("5p: menuTitles(paused: true) is [Resume Recording, Stop Recording]",
          mt.get("paused") == ["Resume Recording", "Stop Recording"], f"{mt.get('paused')}")
    tt = answer.get("tooltip") or {}
    check("5p: the tooltip says which — 'Frame Job is recording' / 'Frame Job's recording is paused'",
          tt.get("recording") == "Frame Job is recording" and tt.get("paused") == "Frame Job's recording is paused",
          f"{tt}")
    check("5p: pauseGlyph is ❚❚ (two heavy vertical bars, U+275A)", answer.get("pauseGlyph") == PAUSE_GLYPH,
          f"{answer.get('pauseGlyph')!r}")
    tr = answer.get("titleRecording") or {}
    check("5p: title(61.9, recording) is '● 1:01' — the dot in DS.meterClip (the coral), the time "
          "uncoloured in monospaced digits, the mark in the system face",
          tr.get("string") == "● 1:01" and tr.get("markIsClip") is True and tr.get("timeHasColor") is False
          and tr.get("timeFontIsMonoDigits") is True and tr.get("markFontIsSystem") is True, f"{tr}")
    tp = answer.get("titlePaused") or {}
    check(f"5p: title(61.9, paused) is '{PAUSE_GLYPH} 1:01' — the glyph with NO colour attribute (the "
          "menu bar's own), the FROZEN time in the same face",
          tp.get("string") == f"{PAUSE_GLYPH} 1:01" and tp.get("markHasColor") is False
          and tp.get("timeHasColor") is False and tp.get("timeFontIsMonoDigits") is True, f"{tp}")
    check(f"5p: title(3661, paused) is '{PAUSE_GLYPH} 1:01:01'",
          (answer.get("titlePausedHour") or {}).get("string") == f"{PAUSE_GLYPH} 1:01:01",
          f"{(answer.get('titlePausedHour') or {}).get('string')!r}")

    print("  5q — the panel's .paused phase, drawn")
    pp = answer.get("pausedPhase") or {}
    check("5q: .paused — the button reads Stop and is enabled, the controls locked, the countdown hidden",
          pp.get("buttonTitle") == "Stop" and pp.get("enabled") is True and pp.get("controlsDisabled") is True
          and pp.get("countdownHidden") is True, f"{pp}")
    check("5q: … the footnote is the pause glyph and the frozen time, in DS.textFaint",
          (pp.get("status") or "").startswith(PAUSE_GLYPH + " ") and pp.get("statusFaint") is True, f"{pp}")
    rp = answer.get("recordingPhase") or {}
    check("5q: .recording — Stop, the coral dot and the time in DS.meterClip",
          rp.get("buttonTitle") == "Stop" and (rp.get("status") or "").startswith("● ")
          and rp.get("statusClip") is True, f"{rp}")
    ip = answer.get("idlePhase") or {}
    check("5q: .idle — the footnote names the folder again, faint",
          (ip.get("status") or "").startswith("saved in ") and ip.get("statusFaint") is True, f"{ip}")

    print("  5r — pauseRecording() / resumeRecording() (+Pause.swift)")
    check("5r: pauseRecording() while idle beeps and stays idle", answer.get("pauseFromIdle") == "idle",
          f"{answer.get('pauseFromIdle')!r}")
    pr = answer.get("pauseRefused") or {}
    check("5r: pauseRecording() while .recording over a recorder that refuses (idle → .notRecording) "
          "BEEPS and leaves the phase .recording with no note — the panel never claims a state the "
          "recorder refused",
          pr.get("phase") == "recording" and pr.get("recorder") == "idle" and pr.get("note") == "", f"{pr}")
    rr = answer.get("resumeRefused") or {}
    check("5r: resumeRecording() while .paused over a recorder that refuses (.notPaused) STAYS paused, "
          "keeps the sentence as resumeProblem STATE and draws it into the note at once",
          rr.get("phase") == "paused" and rr.get("note") == "The recording is not paused."
          and rr.get("noteShown") is True and rr.get("resumeProblem") == "The recording is not paused.",
          f"{rr}")
    check("5r: a second refused resume REPLACES the sentence — one copy in the note, never two",
          answer.get("resumeRefusedTwice") == "The recording is not paused.",
          f"{answer.get('resumeRefusedTwice')!r}")
    both = ("The microphone stopped: The microphone recording failed: boom. The picture is still "
            "recording. The recording is not paused.")
    check("5r: with a live microphone problem the tick composes the note from the two pieces of state, "
          "the microphone's sentence FIRST and the resume's after it — and a second tick leaves it (the "
          "R2 review: the tick used to wipe the resume's sentence)",
          answer.get("resumeRefusedWithMic") == both and answer.get("resumeRefusedWithMicAgain") == both,
          f"{answer.get('resumeRefusedWithMic')!r} then {answer.get('resumeRefusedWithMicAgain')!r}")
    check("5r: resumeRecording() while .recording beeps and stays", answer.get("resumeFromRecording") == "recording",
          f"{answer.get('resumeFromRecording')!r}")
    ln2 = answer.get("liveNote") or {}
    check("5r: liveNote is pure — empty with neither sentence, the microphone's wrapped, the resume's "
          "bare, both joined in that order",
          ln2.get("none") == "" and ln2.get("mic") == "The microphone stopped: boom. The picture is still recording."
          and ln2.get("resume") == "The recording is not paused."
          and ln2.get("both") == "The microphone stopped: boom. The picture is still recording. The "
          "recording is not paused.", f"{ln2}")
    pp2 = answer.get("panelPause") or {}
    check("5r: a REAL pause through the panel over a faked session on ScreenRecorder.shared (its output "
          "attached): .recording → .paused, the recorder .paused, the footnote from '● 0:02' to "
          f"'{PAUSE_GLYPH} 0:02' in DS.textFaint, the button still Stop",
          pp2.get("attached") == "ok" and pp2.get("phase") == "paused" and pp2.get("recorder") == "paused"
          and pp2.get("statusRecording") == "● 0:02" and pp2.get("statusPaused") == f"{PAUSE_GLYPH} 0:02"
          and pp2.get("statusFaint") is True and pp2.get("buttonTitle") == "Stop", f"{pp2}")
    check("5r: … and the footnote HOLDS through a later refresh — elapsed is frozen",
          pp2.get("statusHeld") == f"{PAUSE_GLYPH} 0:02", f"{pp2.get('statusHeld')!r}")
    pr2 = answer.get("panelResume") or {}
    check("5r: a REAL resume: .paused → .recording, the recorder .recording with TWO segments, and a "
          "stale resumeProblem CLEARED (a sentence about a refusal the person got past must not bring "
          "the panel back)",
          pr2.get("phase") == "recording" and pr2.get("recorder") == "recording" and pr2.get("segments") == 2
          and pr2.get("resumeProblemCleared") is True, f"{pr2}")
    ps = answer.get("panelStopWhilePaused") or {}
    check("5r: stopRecording() while paused goes to recorder.stop() — .stopping, the recorder .finishing, "
          "stopAsked", ps.get("phase") == "stopping" and ps.get("recorder") == "finishing"
          and ps.get("stopAsked") is True, f"{ps}")
    check("5r: the probe tore the shared recorder down to idle",
          answer.get("tornDown") == "idle" and answer.get("stateAfter") == "idle",
          f"{answer.get('tornDown')!r}, {answer.get('stateAfter')!r}")

    print("  5s — revealIfNoted, both ways (decision 7)")
    re_ = answer.get("revealEmpty") or {}
    check("5s: showWhenLanded with an EMPTY note → the panel stays hidden, and the flag is cleared "
          "(reveal-always)", re_.get("visible") is False and re_.get("cleared") is True, f"{re_}")
    rn = answer.get("revealNoted") or {}
    check("5s: showWhenLanded with a note → the panel comes back, and the flag is cleared",
          rn.get("visible") is True and rn.get("cleared") is True, f"{rn}")
    check("5s: a note with the panel NOT on screen as the recording began → stays hidden",
          (answer.get("revealNotOnScreenBefore") or {}).get("visible") is False,
          f"{answer.get('revealNotOnScreenBefore')}")
    check("5s: revealControls() (the quit guard's call) shows the panel when no recording has it hidden",
          answer.get("revealControlsShown") is True, f"{answer.get('revealControlsShown')}")
    rc = answer.get("revealControlsHidden") or {}
    check("5s: … and while hiddenForRecording with no status item to open it beeps and shows nothing "
          "(with an item it opens the item's menu — openMenu(), a structural read below)",
          rc.get("visible") is False and rc.get("itemUp") is False, f"{rc}")
    lr = answer.get("landingNoteR2") or {}
    check("5s: landingNote's .userStopped sentence names the SYSTEM's screen-recording indicator (Frame Job's "
          "own item is a menu-bar item too now)",
          lr.get("userStopped") == "Stopped from the system's screen-recording indicator; the recording was "
          "added.", f"{lr.get('userStopped')!r}")
    check("5s: landingNote carries a refused resume's sentence, and the placement's notes LAST, in order "
          "after the stop, the closed document and the microphone",
          lr.get("resume") == "The recording could not be resumed: x."
          and lr.get("all") == "Stopped from the system's screen-recording indicator; the recording was "
          "added. The document you chose was closed, so the recording opened as a new project. Mic. "
          "Resume. Note one. Note two." and lr.get("notesOnly") == "Note.", f"{lr}")

    print("  5t — the route and the guard while paused")
    rt = answer.get("routePaused") or {}
    check("5t: New Recording… with the panel .paused stops THROUGH THE PANEL (.stopping) and shows nothing",
          rt.get("phase") == "stopping" and rt.get("panelShown") is False, f"{rt}")
    pv = answer.get("pausedValidate") or {}
    check("5t: with the recorder .paused the item reads Stop Recording (isRecording true, isPaused true) "
          "and ⌘Q is cancelled", pv.get("title") == "Stop Recording" and pv.get("enabled") is True
          and pv.get("isRecording") is True and pv.get("isPaused") is True and pv.get("reply") == "terminateCancel",
          f"{pv}")

    print("  5u — structural: the hide for EVERY source, the reveal's condition, the menu rebuilt on the "
          "flip, the tick through .paused, the route, the tool's closures")
    rec = read_code(sources, "RecorderPanelController+Recording.swift")
    land = read_code(sources, "RecorderPanelController+Landing.swift")
    status = read_code(sources, "RecorderStatusItem.swift")
    route = read_code(sources, "AppDelegate+Recording.swift")
    tool = read_code(sources, "AgentServer+Recording.swift")
    tool_chrome = read_code(sources, "AgentServer+RecordingChrome.swift")
    pause = read_code(sources, "RecorderPanelController+Pause.swift")
    base = read_code(sources, "RecorderPanelController.swift")
    showing = read_code(sources, "RecorderPanelController+Showing.swift")
    for name, code in [("+Recording", rec), ("+Landing", land), ("status item", status),
                       ("+Recording (route)", route), ("AgentServer+Recording", tool),
                       ("AgentServer+RecordingChrome", tool_chrome), ("+Pause", pause),
                       ("base", base), ("+Showing", showing)]:
        check(f"5u: {name} is in the sources", code is not None)
    if None in (rec, land, status, route, tool, tool_chrome, pause, base, showing):
        return
    body = "\n".join(function_body(rec.splitlines(), "func recordingDidStart()") or [])
    check("5u: recordingDidStart hides the panel for EVERY source — hiddenForRecording = true and "
          "orderOut with no `.picked` in the body (hide-picked-only)",
          "hiddenForRecording = true" in body and "orderOut" in body and ".picked" not in body, body)
    check("5u: … remembers whether it WAS visible (showWhenLanded = window?.isVisible == true)",
          "showWhenLanded = window?.isVisible == true" in body, body)
    check("5u: … and hands the item the three closures (onPause, onResume, onStop)",
          all(t in body for t in ("onPause:", "onResume:", "onStop:")), body)
    ended = "\n".join(function_body(land.splitlines(), "func recordingEnded(") or [])
    check("5u: recordingEnded clears hiddenForRecording and shows NOTHING (no orderFront, no show())",
          "hiddenForRecording = false" in ended and "orderFront" not in ended and "show()" not in ended, ended)
    check("5u: the three ends call revealIfNoted() — three call sites beside its definition",
          land.count("revealIfNoted()") == 4, f"found {land.count('revealIfNoted()')}")
    reveal = "\n".join(function_body(land.splitlines(), "func revealIfNoted()") or [])
    check("5u: revealIfNoted orders front only under showWhenLanded AND a non-empty note, and clears "
          "the flag either way",
          "showWhenLanded, !noteLabel.stringValue.isEmpty" in reveal and "showWhenLanded = false" in reveal,
          reveal)
    upd = "\n".join(function_body(status.splitlines(), "func update(elapsed: TimeInterval, paused: Bool)") or [])
    check("5u: RecorderStatusItem.update rebuilds the menu when `paused` FLIPS — compares it with "
          "menuShowsPaused and calls rebuildMenu(paused: paused) (menu-static)",
          "paused != menuShowsPaused" in upd and "rebuildMenu(paused: paused)" in upd, upd)
    status_raw = open(os.path.join(sources, "RecorderStatusItem.swift")).read()
    check("5u: the item's doc still names the .common run-loop mode and the panel still adds both timers "
          "in it", ".common" in status_raw and rec.count("forMode: .common") == 2,
          f"{rec.count('forMode: .common')} timers")
    tick = "\n".join(function_body(rec.splitlines(), "func armTick()") or [])
    check("5u: the tick runs through .paused and passes paused: to the item",
          "self.phase == .paused" in tick and "paused: self.phase == .paused" in tick, tick)
    nr = "\n".join(function_body(route.splitlines(), "func newRecording(_ sender: Any?)") or [])
    check("5u: newRecording's panel arm names .paused beside .recording and .starting",
          "case .recording, .paused, .starting:" in nr, nr)
    check("5u: the tool's RecordingToolChrome (AgentServer+RecordingChrome.swift since B27) passes the "
          "three closures and paused: recorder.isPaused",
          all(t in tool_chrome for t in ("onPause:", "onResume:", "onStop:", "paused: recorder.isPaused")))
    check("5u: show()'s guard is unchanged — beeps while hiddenForRecording",
          "guard !hiddenForRecording else {" in showing
          and "NSSound.beep()" in "\n".join(function_body(showing.splitlines(), "func show()") or []))
    resume_body = "\n".join(function_body(pause.splitlines(), "func resumeRecording()") or [])
    check("5u: +Pause.swift — a refused pause beeps; a refused resume keeps resumeProblem and redraws "
          "the note through syncMicrophoneNote; a landed resume clears it",
          "NSSound.beep()" in "\n".join(function_body(pause.splitlines(), "func pauseRecording()") or [])
          and "resumeProblem = error.localizedDescription" in resume_body
          and "syncMicrophoneNote()" in resume_body and "resumeProblem = nil" in resume_body, resume_body)
    landed_body = "\n".join(function_body(land.splitlines(), "func landed(") or [])
    failed_body = "\n".join(function_body(land.splitlines(), "func failedToLand(") or [])
    check("5u: landed passes resumeProblem and the placement's notes to landingNote; failedToLand names "
          "every file through filesClause",
          "resumeProblem: resumeProblem" in landed_body and "notes: notes" in landed_body
          and "filesClause" in failed_body, f"{landed_body}\n{failed_body}")
    close_body = "\n".join(function_body(base.splitlines(), "func panelWillClose(") or [])
    check("5u: closing the panel during .starting stops or abandons the attempt as the countdown's "
          "cancel does (case .starting: stopRecording())",
          "case .countdown: cancelCountdown()" in close_body and "case .starting: stopRecording()" in close_body,
          close_body)
    app_delegate = read_code(sources, "AppDelegate.swift") or ""
    quit_body = "\n".join(function_body(app_delegate.splitlines(), "func applicationShouldTerminate(") or [])
    check("5u: the quit guard calls revealControls() — the status item's menu when the panel is hidden "
          "for a recording, the panel otherwise", "revealControls()" in quit_body, quit_body)
    reveal_controls = "\n".join(function_body(pause.splitlines(), "func revealControls()") or [])
    check("5u: revealControls opens the item's menu (openMenu) and beeps only with no item",
          "openMenu()" in reveal_controls and "NSSound.beep()" in reveal_controls and "show()" in reveal_controls,
          reveal_controls)
    check("5u: RecorderStatusItem freezes at the Stop — update ignores `paused` once frozen — and the "
          "tool's chrome freezes it too",
          "let paused = frozen ? menuShowsPaused : paused" in upd and "func freeze()" in status
          and "chrome.freeze()" in tool, upd)
    welcome_code = read_code(sources, "WelcomeWindowController.swift") or ""
    check("5u: the welcome button's action is showRecorderPanel, which only shows",
          "AppDelegate.showRecorderPanel(_:)" in welcome_code
          and "RecorderPanelController.shared.show()" in "\n".join(
              function_body(route.splitlines(), "func showRecorderPanel(") or []))


# --------------------------------------------------------------------------
# Section 12 — issue batch B17 (#98 a, b): File ▸ Pause/Resume Recording and
# the status item's one fixed length.

STATUS_ELAPSED = [0.0, 59.0, 61.9, 599.0, 3599.0, 3661.0, 35999.0]


def section_file_pause(binary, sources):
    print("\nSection 12 — issue batch B17 (#98 a, b): File ▸ Pause/Resume Recording — the item, its "
          "validator and its route — and the status item's one fixed length")
    work = fresh_dir("file-pause")
    answer, error = run_probe(binary, "file-pause",
                              {"mode": "file-pause", "work": work, "elapsed": STATUS_ELAPSED})
    check("12: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return

    f = answer.get("file") or {}
    n = f.get("next") or {}
    check("F1: the File menu's item directly after New Recording… is Pause Recording, action "
          "pauseOrResumeRecording:, nil target, no key, not a separator",
          f.get("newRecordingIndex", -1) >= 0 and n.get("title") == "Pause Recording"
          and n.get("action") == "pauseOrResumeRecording:" and n.get("hasTarget") is False
          and n.get("key") == "" and n.get("separator") is False, f"{f}")
    check("F1: … and exactly one item in the whole bar sends it", f.get("inBar") == 1,
          f"got {f.get('inBar')}")
    titles = answer.get("menuTitles") or {}
    rows = {v.get("state"): v for v in answer.get("validate") or []}
    for state, enabled in [("idle", False), ("arming", False), ("finishing", False),
                           ("recording", True), ("paused", True)]:
        v = rows.get(state) or {}
        want = titles.get("paused" if state == "paused" else "recording")
        check(f"F2: validateMenuItem with the recorder {state} → enabled {enabled}, titled {want!r} — "
              f"the status item's own menuTitles(paused:)[0]",
              want in ("Pause Recording", "Resume Recording") and v.get("enabled") is enabled
              and v.get("title") == want, f"{v}, titles {titles}")
    f3 = answer.get("f3") or {}
    p3 = f3.get("paused") or {}
    check("F3: the panel's own recording — the action pauses THROUGH THE PANEL: panel and recorder "
          "both .paused (pause-route-recorder)",
          f3.get("attached") == "ok" and p3.get("panel") == "paused" and p3.get("recorder") == "paused",
          f"{f3}")
    check("F3: … and again resumes: both .recording, with TWO segments",
          f3.get("panel") == "recording" and f3.get("recorder") == "recording"
          and f3.get("segments") == 2, f"{f3}")
    f4 = answer.get("f4") or {}
    p4 = f4.get("paused") or {}
    check("F4: a recording the panel does not own (a tool's) — the action pauses the RECORDER, the "
          "panel idle and not shown",
          f4.get("attached") == "ok" and p4.get("recorder") == "paused" and p4.get("panel") == "idle"
          and p4.get("visible") is False, f"{f4}")
    check("F4: … and again resumes the recorder — two segments, the panel still idle and hidden",
          f4.get("recorder") == "recording" and f4.get("segments") == 2 and f4.get("panel") == "idle"
          and f4.get("visible") is False, f"{f4}")
    f5 = answer.get("f5") or {}
    check("F5: with nothing recording the action changes nothing — both idle, no session, the panel "
          "hidden",
          f5.get("panel") == "idle" and f5.get("recorder") == "idle" and f5.get("session") is False
          and f5.get("visible") is False, f"{f5}")
    check("F: the recorder is idle once the probe tears its faked sessions down",
          answer.get("stateAfter") == "idle", f"{answer.get('stateAfter')!r}")

    # Issue batch B27 (#181): the recorder's pause notification, which the
    # tool's status item flips on.
    f6 = answer.get("f6") or {}
    print(f"  F6: the panel's own pause and resume (F3) posted {f6.get('f3')} (isPaused inside each "
          f"block; a fact, not asserted)")
    check("F6: F4's pause action — a recording the panel does not own — posts "
          "ScreenRecorder.pauseDidChangeNotification ONCE, synchronously (counted before any spin), "
          "isPaused true inside the block (pause-no-post)",
          f6.get("f4Pause") == [True], f"{f6}")
    check("F6: … the resume action posts once more, isPaused false inside the block",
          f6.get("f4Resume") == [False], f"{f6}")
    check("F6: F5's action with nothing recording posts nothing", f6.get("f5") == 0, f"{f6}")
    chrome = read_code(sources, "AgentServer+RecordingChrome.swift") or ""
    lines = chrome.splitlines()
    show_body = "\n".join(function_body(lines, "func show(_ recorder: ScreenRecorder)") or [])
    added = show_body.split("addObserver(", 1)[1].split("}", 1)[0] if "addObserver(" in show_body else ""
    check("F7: RecordingToolChrome.show (AgentServer+RecordingChrome.swift, comment-stripped) adds an "
          "observer for ScreenRecorder.pauseDidChangeNotification with object: recorder whose block "
          "calls tick() (chrome-no-observer)",
          "forName: ScreenRecorder.pauseDidChangeNotification" in added and "object: recorder" in added
          and "tick()" in added, show_body)
    remove_body = "\n".join(function_body(lines, "func remove()") or [])
    check("F7: … and remove() calls removeObserver", "removeObserver" in remove_body, remove_body)

    # Issue batch B42 (#193): the recorder's finishing notification, which
    # freezes the tool's status item at a stop from any door, and the stale
    # resumeProblem a new countdown clears.
    f8 = answer.get("f8") or {}
    check("F8: F3–F5 (pauses, resumes, a teardown, an idle action) post no "
          "ScreenRecorder.finishingDidBeginNotification", f8.get("before") == [], f"{f8}")
    check("F8: File ▸ Stop Recording (newRecording) over a tool's PAUSED recording posts "
          "finishingDidBeginNotification ONCE, synchronously (counted before any spin), the "
          "recorder finishing inside the block (finish-no-post)",
          f8.get("attached") == "ok" and f8.get("paused") == "paused"
          and f8.get("stopPosts") == ["finishing"], f"{f8}")
    check("F8: … and after the call the panel is idle and not shown, the recorder .finishing",
          f8.get("panel") == "idle" and f8.get("visible") is False
          and f8.get("recorder") == "finishing", f"{f8}")
    segments = show_body.split("addObserver(")[1:]
    finishing = next((part.split("}", 1)[0] for part in segments
                      if "forName: ScreenRecorder.finishingDidBeginNotification" in part), "")
    check("F9: RecordingToolChrome.show (comment-stripped) adds an observer for "
          "ScreenRecorder.finishingDidBeginNotification with object: recorder whose block calls "
          "freeze() (chrome-no-freeze)",
          "object: recorder" in finishing and "freeze()" in finishing, show_body)
    check("F9: … and remove() calls removeObserver on finishObserver",
          "removeObserver(finishObserver)" in remove_body, remove_body)
    f10 = answer.get("f10") or {}
    print(f"  F10: the choice's microphone is {f10.get('microphone')!r} (a fact, not asserted)")
    check("F10: beginCountdown() over a stale resumeProblem clears it "
          "(countdown-keeps-resume-problem)", "problem" in f10 and f10.get("problem") is None,
          f"{f10}")
    check("F10: … the phase straight after is the countdown, and cancelCountdown() with "
          "disarmTick() leaves the panel idle",
          str(f10.get("phase", "")).startswith("countdown") and f10.get("after") == "idle", f"{f10}")

    w0 = answer.get("w0") or {}
    print(f"  W0: '● 0:00' is {w0.get('recording')} pt wide and '{PAUSE_GLYPH} 0:00' "
          f"{w0.get('paused')} pt (facts, not asserted)")
    length = answer.get("itemLength") or 0
    inset = answer.get("titleInset") or 0
    widths = answer.get("widths") or []
    check(f"W1: a width for each of {len(STATUS_ELAPSED)} times × both marks",
          len(widths) == 2 * len(STATUS_ELAPSED), f"got {len(widths)}")
    for row in widths:
        need = math.ceil(row.get("width") or 0) + 2 * inset
        mark = PAUSE_GLYPH if row.get("paused") else "●"
        check(f"W1: '{mark} {row.get('label')}' needs {need:g} pt ≤ itemLength {length:g}",
              0 < need <= length + 1e-9, f"width {row.get('width')}")
    ww = answer.get("widestWidths") or []
    check("W2: itemLength is the wider mark's title at widestElapsed, rounded up, plus 2 × titleInset "
          "(6 pt)",
          len(ww) == 2 and inset == 6
          and abs(length - (max(math.ceil(w) for w in ww) + 2 * inset)) < 1e-9, f"{length}, {ww}, {inset}")
    check("W2: widestElapsed is 35 999 s, labelled 9:59:59 (width-short-label)",
          answer.get("widestElapsed") == 35999 and answer.get("widestLabel") == "9:59:59",
          f"{answer.get('widestElapsed')}, {answer.get('widestLabel')!r}")
    code = read_code(sources, "RecorderStatusItem.swift") or ""
    show = "\n".join(function_body(code.splitlines(), "func show()") or [])
    check("W3: show() puts the item up at statusItem(withLength: Self.itemLength) "
          "(status-variable-length)", "statusItem(withLength: Self.itemLength)" in show, show)
    check("W3: … and RecorderStatusItem.swift's CODE never says variableLength",
          bool(code) and "variableLength" not in code)


# --------------------------------------------------------------------------
# Section 6 — the welcome window's cross-build (phase 5's pattern).
#
# PNG, in pure Python, and the pixel helpers: `phase5_chrome.py`'s, unchanged
# — every chrome script carries its own copy so one can be run without the
# others.

WELCOME_W = 720
WELCOME_H = 600
WELCOME_CENTER_X = 360               # the stack is centred on the content view
STICKER_H = 28                       # StickerButton.bodyHeight (spec §11 SH-4)
STICKER_PAD = 32                     # intrinsicContentSize: ceil(textWidth) + 32
# The reference tree's pill (SH-1): bodyHeight 28 + 6, ceil(textWidth) + 32 + 6.
WAS_STICKER_H = 34
WAS_STICKER_PAD = 38
# The welcome column is centred on its height, so a row 6 pt shorter moves
# everything above it 3 pt down and everything below it 3 pt up.
COLUMN_SHIFT = (WAS_STICKER_H - STICKER_H) / 2
# `StickerButton.draw` now: a block on `bounds.insetBy(0.5)`. The primary
# (leftmost) has no stroke, so its fill starts 0.5 pt in; the secondary
# (rightmost) strokes 1 pt centred on that edge, reaching its frame.
INK_LEFT = 0.5
# The pill's ink: the body at (2, 2) with a 1.5 pt stroke centred on its edge
# (0.75 outside), the sticker shadow offset by 2 — from 1.25 pt to 32 down.
WAS_INK_TOP = 2 - 0.75
WAS_INK_BOTTOM = 28 + 2 + 2
PIXEL = 0.5                          # one Retina pixel — section 6 uses the render's own


class Rect:
    def __init__(self, name, x, y, w, h):
        self.name, self.x0, self.y0, self.x1, self.y1 = name, x, y, x + w, y + h

    def contains(self, x, y, scale, slop=0):
        return (self.x0 - slop) * scale <= x < (self.x1 + slop) * scale \
            and (self.y0 - slop) * scale <= y < (self.y1 + slop) * scale

    def __str__(self):
        return (f"{self.name} x {self.x0:g}–{self.x1:g} y {self.y0:g}–{self.y1:g} pt "
                f"({self.x1 - self.x0:g} × {self.y1 - self.y0:g})")


def decode_png(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path} is not a PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        sys.exit(f"{path}: only 8-bit non-interlaced PNGs are decoded here")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            sys.exit(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, channels, rows


class Image:
    def __init__(self, path, points=WELCOME_W):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)
        self.scale = self.width / points


def changed_pixels(a, b):
    """Every (x, y) whose bytes differ, found by XOR-ing whole rows."""
    if (a.width, a.height, a.channels) != (b.width, b.height, b.channels):
        return None
    out = []
    ch = a.channels
    for y, (ra, rb) in enumerate(zip(a.rows, b.rows)):
        if ra == rb:
            continue
        x = int.from_bytes(ra, "big") ^ int.from_bytes(rb, "big")
        xb = x.to_bytes(len(ra), "big")
        for m in re.finditer(rb"[^\x00]+", xb):
            for px in range(m.start() // ch, (m.end() - 1) // ch + 1):
                out.append((px, y))
    return out


def clusters(pixels, cell=12):
    """Bounding boxes of changed pixels grouped within `cell` px of each other."""
    buckets = {}
    for x, y in pixels:
        buckets.setdefault((x // cell, y // cell), []).append((x, y))
    parent = {k: k for k in buckets}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for cx, cy in buckets:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (cx + dx, cy + dy)
                if n in buckets:
                    parent[find(n)] = find((cx, cy))
    groups = {}
    for k, pts in buckets.items():
        groups.setdefault(find(k), []).extend(pts)
    boxes = []
    for pts in groups.values():
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        boxes.append((min(xs), min(ys), max(xs), max(ys), len(pts)))
    return sorted(boxes, key=lambda b: (b[1], b[0]))


def describe(boxes, scale, limit=12):
    lines = []
    for x0, y0, x1, y1, n in boxes[:limit]:
        lines.append(
            f"      x {x0}–{x1} y {y0}–{y1} px  = x {x0 / scale:.1f}–{(x1 + 1) / scale:.1f}"
            f" y {y0 / scale:.1f}–{(y1 + 1) / scale:.1f} pt  ({n} px)")
    if len(boxes) > limit:
        lines.append(f"      … and {len(boxes) - limit} more clusters")
    return "\n".join(lines)


def outside(pixels, rects, scale, slop=0):
    return [p for p in pixels if not any(r.contains(p[0], p[1], scale, slop) for r in rects)]


def extent(pixels, scale):
    """The bounding box of a changed set, in POINTS — the rectangle a diff
    claims, to be compared with the one the constants predict. None when
    nothing changed, which every caller reports as a failure rather than
    letting an empty set agree with anything."""
    if not pixels:
        return None
    xs = [x for x, _ in pixels]
    ys = [y for _, y in pixels]
    return (min(xs) / scale, min(ys) / scale, (max(xs) + 1) / scale, (max(ys) + 1) / scale)


def same_file(a, b):
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


def git(*args):
    result = subprocess.run(
        ["git", "-C", ROOT] + list(args), capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit("git " + " ".join(args) + " failed:\n" + result.stderr)
    return result.stdout


def reference_commit():
    """The tree immediately BEFORE the welcome window's third button existed.

    Found by a PICKAXE on the button's title rather than by the file's
    adding commit — `WelcomeWindowController.swift` was added in the
    initial commit, so `--diff-filter=A` would name a tree from before the
    welcome window had any button at all. The last commit whose diff
    introduces or removes "New Recording" in that file, minus one; while the
    change is still uncommitted the pickaxe names nothing and HEAD is
    already that tree — the case this was written under.
    """
    hits = git("log", "--format=%H", '-SNew Recording', "--", WELCOME_FILE).split()
    return (hits[-1] + "^") if hits else "HEAD"


def build_reference(commit):
    """Build archived Swift with its matching archived core and header."""
    return build_matching_reference(root=ROOT, before=BEFORE, commit=commit,
                                    harness_main=HARNESS_MAIN, fonts=FONTS,
                                    proof_script=__file__)


def build_harness():
    """The TREE's harness through `build.sh` — which hard-codes `app/Sources`,
    so this is the tree whatever `--sources` says. None with the reason when
    it will not build."""
    start = time.time()
    result = subprocess.run([BUILD], capture_output=True, text=True)
    elapsed = time.time() - start
    if result.returncode != 0:
        return None, (result.stdout + result.stderr).strip().splitlines()[-6:]
    binary = result.stdout.strip().splitlines()[-1]
    built = "built" in result.stderr
    print(f"harness: {binary} ({'built in %.0f s' % elapsed if built else 'up to date'})")
    return binary, None


def render_welcome(binary, out, appearance):
    """One offscreen render of the welcome window: `harness welcome <png>
    <appearance>`, the mode's own four-argument form. None with the reason
    when the render failed."""
    result = subprocess.run([binary, "welcome", out, appearance], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip().splitlines()[-3:]
    if result.stderr.strip():
        print(f"      {os.path.basename(out)}: {result.stderr.strip()}")
    return out, None


def close(a, b, tolerance=PIXEL):
    return a is not None and b is not None and abs(a - b) <= tolerance + 1e-9


def section_welcome(binary, sources):
    print("\nSection 6 — the welcome window against the tree one commit before the button: "
          "the three-button row and the column's 3 pt re-centring are all that changed, "
          "besides the lockup's mark and wordmark (rename R2, spec §11 NM-11), whose rows "
          "are left out")
    if os.path.realpath(sources) != os.path.realpath(TREE_SOURCES):
        print("  (this section renders the TREE through harness/build.sh, not --sources; a "
              "--mutant changes only the probe's own 6a layout and samples, and the renders "
              "stay the tree's)")
    os.makedirs(RENDERS, exist_ok=True)

    # The row's geometry from the live layout, with the fonts registered.
    answer, error = run_probe(binary, "welcome", {"mode": "welcome", "fonts": FONTS})
    check("6: the probe answers (the welcome mode)", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    buttons = (answer or {}).get("buttons") or []
    spacing = (answer or {}).get("spacing")
    check("6a: the vendored fonts registered, and the buttons draw in Source Sans 3 (the variable "
          "face's semibold instance, `SourceSans3-Roman_SemiBold` as CoreText names it) — the face "
          "the harness renders with, not the system fallback",
          (answer or {}).get("fontsRegistered", 0) >= 4
          and buttons and all((b.get("font") or "").startswith("SourceSans3") for b in buttons),
          f"registered {(answer or {}).get('fontsRegistered')}, fonts {[b.get('font') for b in buttons]}")
    check("6a: three buttons, the third New Recording… with action showRecorderPanel:",
          len(buttons) == 3 and buttons[2].get("title") == "New Recording…"
          and buttons[2].get("action") == "showRecorderPanel:", f"{[(b.get('title'), b.get('action')) for b in buttons]}")
    check("6a: the stack's spacing is 12 (WelcomeWindowController)", spacing == 12, f"{spacing}")
    check(f"6a: the content view is {WELCOME_W}×{WELCOME_H} pt",
          (answer or {}).get("contentSize") == [WELCOME_W, WELCOME_H], f"{(answer or {}).get('contentSize')}")
    widths = [math.ceil(b.get("textWidth", 0)) + STICKER_PAD for b in buttons]
    check(f"6a: each button's intrinsic size is ⌈textWidth⌉ + {STICKER_PAD} × {STICKER_H} "
          "(StickerButton.intrinsicContentSize)",
          buttons and all(b.get("intrinsic") == [w, STICKER_H] for b, w in zip(buttons, widths)),
          f"intrinsic {[b.get('intrinsic') for b in buttons]}, predicted {widths}")
    row_w = sum(widths) + (len(widths) - 1) * (spacing or 0)
    row_x = WELCOME_CENTER_X - row_w / 2
    frames = [b.get("frame") or [0, 0, 0, 0] for b in buttons]
    laid_x = min(f[0] for f in frames) if frames else None
    laid_right = max(f[0] + f[2] for f in frames) if frames else None
    laid_top = frames[0][1] if frames else None
    check(f"6a: laid out, the row is {row_w:g} pt wide from x {row_x:g} — Σ widths + 2 × 12, centred "
          f"at {WELCOME_CENTER_X}",
          close(laid_x, row_x, 0.01) and close(laid_right, row_x + row_w, 0.01)
          and all(f[2] == w for f, w in zip(frames, widths)),
          f"frames {frames}")
    check(f"6a: … {STICKER_H} pt tall on one line",
          frames and all(close(f[1], laid_top, 0.01) and f[3] == STICKER_H for f in frames), f"{frames}")
    corners = [(b.get("corner"), b.get("middle")) for b in buttons]
    check("6a: each button's corner sample (1.5, 1.5) is opaque and equal to its middle sample "
          "(1.5, mid-height) — a square block, not a pill (spec §11 SH-4)",
          buttons and all(c and m and c[-1] == 255 and c == m for c, m in corners),
          f"(corner, middle) {corners}")
    print(f"      the row: x {row_x:g}–{row_x + row_w:g}, top {laid_top}, widths {widths}, "
          f"recents listed {(answer or {}).get('recentCount')}")
    row = Rect("the button row", row_x, laid_top if laid_top is not None else 0, row_w, STICKER_H)

    # The two instruments.
    harness, why = build_harness()
    check("6b: the tree's harness builds", harness is not None, "\n      ".join(why or []))
    commit = reference_commit()
    reference, sha, note = build_reference(commit)
    print(f"      reference: {commit} = {sha[:12]}")
    print(f"      compiled with {note.splitlines()[0] if note else '?'}")
    check("6b: the reference tree built, so there is a 'before' to compare the welcome window "
          "against", reference is not None,
          "      " + (note or "").replace("\n", "\n      "))
    check("6b: … compiled with THIS tree's own harness/main.swift (one program, two app trees)",
          reference is not None and note.startswith("this tree's own"),
          (note or "").splitlines()[0] if note else "")
    tree = os.path.join(BEFORE, "tree", "app", "Sources")
    panel_present = os.path.exists(os.path.join(tree, "RecorderPanelController.swift"))
    welcome_path = os.path.join(tree, "WelcomeWindowController.swift")
    welcome_text = open(welcome_path).read() if os.path.exists(welcome_path) else ""
    check("6b: the reference tree has no RecorderPanelController.swift and its welcome window "
          "names no New Recording — so every changed pixel is the button's",
          os.path.isdir(tree) and not panel_present and welcome_text and "New Recording" not in welcome_text,
          f"panel present {panel_present}, 'New Recording' in welcome: {'New Recording' in welcome_text}")
    if harness is None or reference is None:
        print("   the comparison cannot run without both instruments.")
        return

    # The renders: this tree twice in light (determinism), once in dark; the
    # reference in both.
    def png(tag):
        return os.path.join(RENDERS, tag + ".png")

    start = time.time()
    renders = {}
    for tag, which, appearance in [("now-light-a", harness, "light"), ("now-light-b", harness, "light"),
                                   ("now-dark", harness, "dark"), ("was-light", reference, "light"),
                                   ("was-dark", reference, "dark")]:
        out, why = render_welcome(which, png(tag), appearance)
        renders[tag] = out
        if out is None:
            print(f"      {tag}: render failed: {' '.join(why or [])}")
    check("6c: all five renders wrote a PNG", all(renders.values()),
          f"{[k for k, v in renders.items() if v is None]}")
    if not all(renders.values()):
        return
    print(f"      rendered 5 PNGs in {time.time() - start:.1f} s into {os.path.relpath(RENDERS, ROOT)}")
    images = {tag: Image(path) for tag, path in renders.items()}
    now = images["now-light-a"]
    scale = now.scale
    # The PNG is at the main display's backing scale: 1440×1200 on the Retina
    # desktop (scale 2), 720×600 while the display is ASLEEP or the console
    # locked, when AppKit reports scale 1 for a window that is on no screen.
    # The geometry below is in points and holds at either; what is pinned is
    # that the scale is whole, the same for all five, and the channels four.
    shapes = {(i.width, i.height, i.channels) for i in images.values()}
    check(f"6c: the shape is {WELCOME_W}×{WELCOME_H} pt at a whole backing scale — {now.width}×"
          f"{now.height} here, scale {scale:g} (1440×1200 at the Retina desktop's 2) — 4 channels, "
          "the same for all five renders",
          len(shapes) == 1 and scale in (1, 2) and now.height == WELCOME_H * scale and now.channels == 4,
          f"{[(t, i.width, i.height, i.channels) for t, i in images.items()]}")
    pixel = 1 / scale                # the slop an anti-aliased edge earns: one render pixel
    check("6c: determinism — this tree rendered twice, in two processes → byte-identical PNGs",
          same_file(renders["now-light-a"], renders["now-light-b"]))
    check("6c: … and a different build from the reference, so the comparison is not a file "
          "against itself", not same_file(renders["now-light-a"], renders["was-light"]))

    check("6d: the probe answered a button row, so there is a row top to place the reference "
          "band from", laid_top is not None, "no buttons answered")
    if laid_top is None:
        return
    was_top = laid_top - COLUMN_SHIFT          # the reference row's top, 3 pt higher
    band = Rect("the reference row's band", 0, was_top, WELCOME_W, WAS_STICKER_H)
    ink_x0, ink_x1 = row.x0 + INK_LEFT, row.x1
    ink_y0, ink_y1 = was_top + WAS_INK_TOP, was_top + WAS_INK_BOTTOM
    print(f"      predicted: {row}")
    print(f"      predicted: {band}")
    print(f"      predicted: the band's ink x {ink_x0:g}–{ink_x1:g}, y {ink_y0:g}–{ink_y1:g} pt")
    shift = round(COLUMN_SHIFT * scale)        # the column's move in render pixel rows
    band_top = round(band.y0 * scale)
    band_bottom = round(band.y1 * scale)

    def mismatches(now_img, was_img, ys, offset):
        return [y for y in ys if now_img.rows[y] != was_img.rows[y + offset]]

    for appearance, was, tag in (("light", "was-light", "now-light-a"), ("dark", "was-dark", "now-dark")):
        diff = changed_pixels(images[was], images[tag])
        if diff is None:
            check(f"6d {appearance}: the two renders have one shape", False)
            continue
        in_band = [p for p in diff if band.contains(p[0], p[1], scale)]
        boxes = clusters(in_band)
        print(f"\n   {appearance}: {len(in_band)} changed pixels in the band in {len(boxes)} cluster(s) "
              f"({len(diff)} in the whole render, the column's move included) — printed, never "
              "counted as one:")
        print(describe(boxes, scale))
        check(f"6d {appearance}: (i) the third button changed SOMETHING in the band", bool(in_band))
        stray = outside(in_band, [Rect("the row's x-span", row.x0, band.y0, row_w, WAS_STICKER_H)], scale)
        check(f"6d {appearance}: (ii) nothing in the band changed outside the new row's x-span "
              f"({row.x0:g}–{row.x1:g})",
              not stray, "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
        box = extent(in_band, scale)
        print(f"      extent: {box}")
        check(f"6d {appearance}: (iii) the band's extent x is {ink_x0:g}–{ink_x1:g} — the primary's "
              "fill 0.5 pt in on the left, the secondary's 1 pt stroke reaching its frame on the "
              "right — within a pixel",
              box is not None and close(box[0], ink_x0, pixel) and close(box[2], ink_x1, pixel), f"{box}")
        check(f"6d {appearance}: (iv) … and its y is {ink_y0:g}–{ink_y1:g} — the pill row's ink, "
              f"{COLUMN_SHIFT:g} pt higher — within a pixel",
              box is not None and close(box[1], ink_y0, pixel) and close(box[3], ink_y1, pixel), f"{box}")
        derived_top = (box[3] - WAS_INK_BOTTOM + COLUMN_SHIFT) if box else None
        check(f"6d {appearance}: (iv) the row's y DERIVED from the band's bottom edge ({derived_top}) "
              f"is the laid-out row's ({laid_top})", close(derived_top, laid_top, pixel),
              f"{derived_top} vs {laid_top}")
        now_img, was_img = images[tag], images[was]
        height = now_img.height
        lockup = (answer or {}).get("lockup")
        if lockup and len(lockup) == 4:
            lockup_rows = range(math.floor(lockup[1] * scale),
                                math.ceil((lockup[1] + lockup[3]) * scale))
        else:
            lockup_rows = None
        everything = mismatches(now_img, was_img, range(shift, band_top), -shift) \
            + mismatches(now_img, was_img, range(0, shift), 0)
        above = [y for y in everything if lockup_rows is None or y not in lockup_rows]
        in_lockup = len(everything) - len(above)
        rows_text = (f"y {lockup_rows.start}–{lockup_rows.stop - 1}" if lockup_rows is not None
                     else "no lockup frame answered")
        check(f"6d {appearance}: (v) above the band every pixel row is the reference's {shift} rows "
              f"higher (y {shift}–{band_top}), and the first {shift} are equal in place — the "
              "headline and the paragraph moved down 3 pt and nothing else; the lockup's own rows "
              f"({rows_text}) are left out, because rename R2 changed the mark and the wordmark "
              "(spec §11 NM-11)",
              lockup_rows is not None and not above,
              f"lockup {lockup}; {len(above)} rows differ outside it, first y {sorted(above)[:12]}; "
              f"{in_lockup} lockup rows differ")
        print(f"      {appearance}: {in_lockup} of the lockup's rows differ from the reference's "
              f"(left out of (v) above; lockup frame {lockup})")
        below = mismatches(now_img, was_img, range(band_bottom, height - shift), shift) \
            + mismatches(now_img, was_img, range(height - shift, height), 0)
        check(f"6d {appearance}: (v) below the band every pixel row is the reference's {shift} rows "
              f"lower (y {band_bottom}–{height - shift}), and the last {shift} are equal in place — "
              "Recent and the formats line moved up 3 pt and nothing else",
              not below, f"{len(below)} rows differ, first y {sorted(below)[:12]}")
        old_widths = [math.ceil(b.get("textWidth", 0)) + WAS_STICKER_PAD for b in buttons[:2]]
        old_w = sum(old_widths) + (spacing or 0)
        old = Rect("the old two-button row", WELCOME_CENTER_X - old_w / 2, was_top, old_w, WAS_STICKER_H)
        check(f"6d {appearance}: (vi) the old two-button row ({old.x0:g}–{old.x1:g}, top {old.y0:g}) "
              "lies inside the band and inside the new row's x-span, so the extent is the new row's "
              "and not a union with something that moved elsewhere",
              old.x0 >= row.x0 - 1e-9 and old.x1 <= row.x1 + 1e-9
              and old.y0 >= band.y0 - 1e-9 and old.y1 <= band.y1 + 1e-9, f"{old} vs {row}, {band}")


# --------------------------------------------------------------------------
# Section 7 — the catalog after the toll: 75 names, the file groups last.

APP_STATE_TOOLS = [
    "open_project", "new_project", "save_project", "get_project", "import_media",
    "import_captions", "export_captions", "transcribe", "consolidate_media", "detect_silence",
    "normalize_clip", "set_playhead", "set_range", "set_selection", "set_scope", "undo", "redo",
    "render_frame", "export", "record_screen", "write_graphic", "get_graphic", "graphic_reference",
    "render_graphic", "import_graphic_font", "import_graphic_asset", "close_project",
    "delete_graphic", "rename_graphic", "restore_graphic", "sync_audio",
    "export_status", "cancel_export", "detect_fillers", "transcribe_for_fillers",
    "get_transcript",
]
# `git show 7a198db^:app/Sources/AgentCatalog.swift`'s last ten rows, in order,
# with `set_media_color` (2a8421b) after `remove_media` and `export_status`,
# `cancel_export` (#326) after `export`, and `get_transcript` (CT-4) after `transcribe`.
FILE_GROUP_ORDER = [
    "import_media", "import_captions", "consolidate_media", "add_media", "relink_media",
    "remove_media", "set_media_color", "transcribe", "get_transcript", "export_captions",
    "render_frame", "export",
    "export_status", "cancel_export",
]
RECORD_SCREEN_ARGUMENTS = [
    "camera", "camera_format", "display", "include_framejob_windows", "microphone", "path", "place",
    "project", "rate", "seconds", "show_clicks", "size", "source", "system_audio", "window",
]


def section_catalog(binary, sources):
    print("\nSection 7 — the catalog the parity check reads: 75 names, the file groups last, "
          "scope on every op tool and on no app-state tool")
    answer, error = run_probe(binary, "catalog", {"mode": "catalog"})
    check("7: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    tools = answer.get("tools") or []
    names = [t.get("name") for t in tools]
    ops = answer.get("coreOps") or []
    print(f"      {len(names)} tools, {len(ops)} core ops, {answer.get('bytes')} bytes of catalog")
    # Floors since road map 5's E1 added `add_transition` and
    # `set_transition_style`: the exact counts belong to the newest phase's
    # script (`tools/proof/README.md`), and what THIS one is about is the
    # catalog's shape and its ORDER, neither of which a later op moves.
    check("7a: the core declares at least 55 ops (rc_op_names), none twice",
          len(ops) >= 55 and len(set(ops)) == len(ops), f"{len(ops)}")
    check("7a: the catalog has at least 75 tools, no name twice", len(names) >= 75 and len(set(names)) == len(names),
          f"{len(names)} names, {len(set(names))} distinct")
    check("7a: they are the 55 ops plus the thirty-six app-state tools, record_screen among them",
          set(names) == set(ops) | set(APP_STATE_TOOLS), f"missing {sorted(set(ops) | set(APP_STATE_TOOLS) - set(names))}, "
          f"extra {sorted(set(names) - set(ops) - set(APP_STATE_TOOLS))}")
    check("7a: no app-state tool is also an op", not set(APP_STATE_TOOLS) & set(ops),
          f"{sorted(set(APP_STATE_TOOLS) & set(ops))}")
    check("7b: the LAST fifteen are the old file's ten file rows in its order, set_media_color "
          "after remove_media, get_transcript after transcribe, export_status and cancel_export "
          "after export, then record_screen",
          names[-15:] == FILE_GROUP_ORDER + ["record_screen"], f"{names[-15:]}")
    check("7b: … so everything before them is the groups that stayed and the clip rows — none "
          "of the fourteen appears earlier", not set(FILE_GROUP_ORDER) & set(names[:-15]),
          f"{sorted(set(FILE_GROUP_ORDER) & set(names[:-15]))}")
    by = {t.get("name"): t for t in tools}
    without = [n for n in ops if not (by.get(n) or {}).get("hasScope")]
    check("7c: every op tool's schema declares `scope`", not without, f"without: {without}")
    with_scope = [n for n in APP_STATE_TOOLS if (by.get(n) or {}).get("hasScope")]
    check("7c: none of the thirty-six app-state tools declares it", not with_scope, f"with: {with_scope}")
    rs = by.get("record_screen") or {}
    check("7c: record_screen's schema has no `scope` key", rs and rs.get("hasScope") is False, f"{rs}")
    check(f"7c: record_screen declares exactly {RECORD_SCREEN_ARGUMENTS}",
          rs.get("properties") == RECORD_SCREEN_ARGUMENTS, f"{rs.get('properties')}")
    check("7c: … requiring seconds alone", rs.get("required") == ["seconds"], f"{rs.get('required')}")
    check("7c: every tool carries `project`", all("project" in (t.get("properties") or []) for t in tools),
          f"{[t.get('name') for t in tools if 'project' not in (t.get('properties') or [])]}")
    description = rs.get("description") or ""
    for phrase in ["Pause Recording", "Resume Recording", "Stop Recording", "pauses", "segments",
                   "started_at", "mic_offset", "mic_problem", "Add Recording Segments", "Add Microphone",
                   "wall clock", "TOTAL", "user_stopped", "screen-recording indicator",
                   "unreadable", "voice_over", "Microphone Only"]:
        check(f"7d: record_screen's description names {phrase!r} (R2d)", phrase in description,
              f"{len(description)} chars of description")


# --------------------------------------------------------------------------
# Section 8 — host facts, printed and never asserted.

def section_host(binary, sources):
    print("\nSection 8 — host facts (printed, never asserted): which tiers of recording_proof.py "
          "could have run on this machine")
    answer, error = run_probe(binary, "host", {"mode": "host"})
    check("8: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    locked = answer.get("screenIsLocked")
    present = answer.get("screenIsLockedKeyPresent")
    print(f"  host: CGPreflightScreenCaptureAccess() = {answer.get('screenRecordingPreflight')} "
          f"(under the TERMINAL's grant — road map 3, R0 q1)")
    print(f"  host: microphone status = {answer.get('microphoneStatus')}")
    print(f"  host: console locked = {locked} (CGSSessionScreenIsLocked "
          f"{'present' if present else 'absent — the key appears only while locked'})")
    print(f"  host: active displays = {answer.get('activeDisplays')} (CGGetActiveDisplayList), "
          f"NSScreen.screens = {answer.get('screens')}")
    print(f"  host: bundleIdentifier = {answer.get('bundleIdentifier')} — a bare Mach-O, so nothing "
          f"here could have prompted")


# --------------------------------------------------------------------------
# Section 9 — the probe's own GRANTED tier (road map 3, R2e).

def granted_run_rows(tag, r, title, resume):
    """One `grantedRun`'s rows: the start, the pause, the frozen elapsed,
    the resume when asked, the stop, the result and its files."""
    print(f"  {title}")
    check(f"{tag}: the start landed — no error, within the arm ceiling",
          r.get("started") is True and r.get("startError") is None,
          f"{r.get('startError')!r} after {r.get('startLatency')} s")
    print(f"      start → completion {r.get('startLatency', 0):.3f} s")
    check(f"{tag}: recording after the start", r.get("stateAfterStart") == "recording",
          f"{r.get('stateAfterStart')!r}")
    check(f"{tag}: elapsed before the pause is about a second (the did-start counts, the arm does not)",
          0.85 <= (r.get("elapsedBeforePause") or 0) <= 1.6, f"got {r.get('elapsedBeforePause')}")
    check(f"{tag}: pause() → .paused, isPaused",
          r.get("pause") == "ok" and r.get("stateAfterPause") == "paused" and r.get("isPaused") is True,
          f"{r.get('pause')!r}, {r.get('stateAfterPause')!r}")
    check(f"{tag}: elapsed read twice 0.5 s apart while paused is EQUAL (elapsed-through-pause)",
          r.get("elapsedA") is not None and r.get("elapsedA") == r.get("elapsedB"),
          f"{r.get('elapsedA')} then {r.get('elapsedB')}")
    check(f"{tag}: the removed output's did-finish landed while paused (R0 q7: 5–25 ms after the remove)",
          r.get("segment0FinishedWhilePaused") is True, f"{r.get('didFinishLatency')} s")
    print(f"      did-finish after the remove: {r.get('didFinishLatency', 0):.3f} s")
    if resume:
        check(f"{tag}: resume() → .recording with two segments",
              r.get("resume") == "ok" and r.get("stateAfterResume") == "recording"
              and r.get("segmentsAfterResume") == 2,
              f"{r.get('resume')!r}, {r.get('stateAfterResume')!r}, {r.get('segmentsAfterResume')}")
        check(f"{tag}: the new output's did-start landed (R0 q7: 8–10 ms after the add)",
              r.get("segment1DidStart") is True, f"{r.get('didStartLatency')} s")
        print(f"      did-start after the add: {r.get('didStartLatency', 0):.3f} s")
        check(f"{tag}: elapsed before the stop is about 2 s — two recorded seconds with the paused second "
              "excluded — against a wall clock at least 0.8 s longer",
              1.7 <= (r.get("elapsedBeforeStop") or 0) <= 2.7
              and (r.get("elapsedWall") or 0) >= (r.get("elapsedBeforeStop") or 0) + 0.8,
              f"elapsed {r.get('elapsedBeforeStop')}, wall {r.get('elapsedWall')}")
    check(f"{tag}: stop() → finishing → idle within the bound; onFinish once, the completion once",
          r.get("stateAfterStop") == "finishing" and r.get("concluded") is True
          and r.get("onFinishCount") == 1 and r.get("stopCount") == 1,
          f"{r.get('stateAfterStop')!r}, concluded {r.get('concluded')} in {r.get('stopLatency')} s, "
          f"onFinish {r.get('onFinishCount')}, stop {r.get('stopCount')}")
    print(f"      stop → conclude {r.get('stopLatency', 0):.3f} s")
    fin = r.get("onFinish") or {}
    segs = fin.get("segments") or []
    return fin, segs


def granted_rows_count(folder):
    """How many rows the granted tier would score — counted by running the
    same row code over an EMPTY answer with `check` swapped for a counter,
    so the number a skip prints is the tier's by construction and cannot
    drift from it."""
    global check
    real = check
    counted = [0]

    def counter(name, ok, detail=""):
        counted[0] += 1

    check = counter
    try:
        import io
        import contextlib
        with contextlib.redirect_stdout(io.StringIO()):
            granted_rows({}, folder)
    finally:
        check = real
    return counted[0]


def section_granted(binary, sources):
    print("\nSection 9 — the probe's own GRANTED tier: a real ScreenRecorder() on the main display "
          "under this process's grant (R0 q1: the terminal's), and the panel end to end")
    folder = fresh_dir("granted")
    answer, error = run_probe(binary, "granted", {"mode": "granted", "folder": folder}, timeout=300)
    check("9: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    print(f"  host: CGPreflightScreenCaptureAccess() = {answer.get('preflight')}, console locked = "
          f"{answer.get('locked')}, shareable displays = {answer.get('displays')} (listed: "
          f"{answer.get('answered')}{', ' + answer['listFailure'] if answer.get('listFailure') else ''})")
    if answer.get("skipped"):
        skip_rows(granted_rows_count(folder), answer["skipped"])
        return
    granted_rows(answer, folder)
    shutil.rmtree(folder, ignore_errors=True)
    print(f"      the recordings under {os.path.relpath(folder, ROOT)} were deleted")


def granted_rows(answer, folder):
    """Every row below the skip point, over the probe's answer."""
    check("9: the probe's NSDocumentController subclass is .shared and the recordings folder is pinned "
          "under work/ by -RCRecordingFolder",
          answer.get("controllerIsProbe") is True and answer.get("folderPinned") == folder,
          f"{answer.get('folderPinned')!r} vs {folder!r}")
    f = answer.get("filter") or {}
    print(f"      the main display's filter: {f.get('width')}×{f.get('height')} pt at scale {f.get('scale')}")

    fin, segs = granted_run_rows("9a", answer.get("run1") or {},
                                 "9a — a fresh ScreenRecorder(): start, 1 s, pause, resume, 1 s, stop", True)
    r = answer.get("run1") or {}
    check("9a: a .success of TWO segments, pauses 1, stoppedBy stopped",
          fin.get("kind") == "success" and len(segs) == 2 and fin.get("pauses") == 1
          and fin.get("stoppedBy") == "stopped", f"{fin}")
    check("9a: both movies probe with pictures, about a second each (600 000 ticks ± 250 000)",
          len(segs) == 2 and all(s.get("hasVideo") and abs((s.get("duration") or 0) - SEC) <= 250_000 for s in segs),
          f"{[s.get('duration') for s in segs]}")
    print(f"      durations: {[s.get('duration') for s in segs]} ticks")
    names = [os.path.basename(s.get("path") or "") for s in segs]
    check("9a: the two movies are in the pinned folder with two DIFFERENT names, each `Screen Recording "
          "<date> at <time>.mov` — its own start time (decision 6)",
          len(segs) == 2 and all(os.path.dirname(s.get("path") or "") == folder for s in segs)
          and all(re.fullmatch(STEM_RE + r"( \(\d+\))?\.mov", n) for n in names) and names[0] != names[1],
          f"{names}")
    check("9a: segment 2's start is at least 1.9 s after segment 1's (a recorded second and a paused one "
          "between)", len(segs) == 2 and (segs[1].get("startedAt") or 0) - (segs[0].get("startedAt") or 0) >= 1.9,
          f"{[s.get('startedAt') for s in segs]}")

    def stem_matches(segment, name):
        started = segment.get("startedAt") or 0
        stem = re.sub(r"( \(\d+\))?\.mov$", "", name)
        return stem in {expected_stem(math.floor(started)), expected_stem(math.floor(started) - 1)}

    check("9a: each movie's stem is the local-time spelling of ITS OWN start (to the second; the did-start "
          "may cross a second boundary after the call that named the file)",
          len(segs) == 2 and all(stem_matches(s, n) for s, n in zip(segs, names)),
          f"{names} vs {[s.get('startedAt') for s in segs]}")
    check("9a: no microphone — micDescriptor nil and micOffset 0 on both segments, micProblem nil",
          len(segs) == 2 and all(s.get("micDescriptor") is False and s.get("micOffset") == 0 for s in segs)
          and fin.get("micProblem") is None, f"{segs}")
    check("9a: the result's path is the FIRST segment's movie", len(segs) == 2 and fin.get("path") == segs[0].get("path"))
    check("9a: idle after, elapsed 0", r.get("elapsedAfter") == 0, f"{r.get('elapsedAfter')}")
    sizes = r.get("sizes") or {}
    check("9a: both files are on disk with bytes in them", len(sizes) == 2 and all(v > 0 for v in sizes.values()),
          f"{sizes}")

    fin, segs = granted_run_rows("9b", answer.get("run2") or {}, "9b — start, 1 s, pause, stop while paused", False)
    r = answer.get("run2") or {}
    check("9b: a stop while paused answers ONE segment with pauses 1 (the press is counted, not the "
          "files), stoppedBy stopped",
          fin.get("kind") == "success" and len(segs) == 1 and fin.get("pauses") == 1
          and fin.get("stoppedBy") == "stopped", f"{fin}")
    check("9b: its movie is about a second with pictures, in the pinned folder",
          len(segs) == 1 and segs[0].get("hasVideo") is True and abs((segs[0].get("duration") or 0) - SEC) <= 250_000
          and os.path.dirname(segs[0].get("path") or "") == folder, f"{segs}")
    check("9b: idle after, elapsed 0", r.get("elapsedAfter") == 0, f"{r.get('elapsedAfter')}")

    r = answer.get("run3") or {}
    print("  9c — the PANEL end to end: Record over the main display, hidden at the start, Pause and Resume "
          "through the entries the status item calls, Stop, and a clean landing that keeps it hidden "
          "(decision 7)")
    check("9c: the panel was visible, over the main display, Record Into New Project, microphone Off",
          r.get("visibleBefore") is True and r.get("destinationNewProject") is True
          and r.get("microphoneOff") is True and r.get("sourceMain") is True, f"{r}")
    check("9c: Record began the countdown, and the recording started within the bound",
          r.get("countdownBegan") is True and r.get("recording") is True,
          f"countdown {r.get('countdownBegan')}, recording {r.get('recording')}")
    a = r.get("atStart") or {}
    check("9c: at recordingDidStart for a DISPLAY source the panel is HIDDEN — isVisible false, "
          "hiddenForRecording, showWhenLanded remembered TRUE — the item up, the note empty, the recorder "
          "recording (hide-picked-only)",
          a.get("visible") is False and a.get("hiddenForRecording") is True and a.get("showWhenLanded") is True
          and a.get("itemShowing") is True and a.get("note") == "" and a.get("recorder") == "recording", f"{a}")
    check("9c: show() while hidden shows nothing", r.get("showWhileHidden") is False, f"{r.get('showWhileHidden')}")
    p = r.get("paused") or {}
    check(f"9c: pauseRecording() (the item's Pause Recording) → .paused, the recorder .paused, the footnote "
          f"'{PAUSE_GLYPH} 0:01' faint",
          p.get("phase") == "paused" and p.get("recorder") == "paused" and p.get("status") == f"{PAUSE_GLYPH} 0:01"
          and p.get("faint") is True, f"{p}")
    check("9c: … and 0.7 s later the 30 Hz tick has left the footnote and elapsed exactly where they were",
          r.get("statusHeld") == f"{PAUSE_GLYPH} 0:01" and r.get("elapsedHeld") == p.get("elapsed"),
          f"{r.get('statusHeld')!r}, {r.get('elapsedHeld')} vs {p.get('elapsed')}")
    rs = r.get("resumed") or {}
    check("9c: resumeRecording() (the item's Resume Recording) → .recording, two segments",
          rs.get("phase") == "recording" and rs.get("recorder") == "recording" and rs.get("segments") == 2, f"{rs}")
    check("9c: stopRecording() → .stopping, then the landing → .idle within the bound",
          r.get("stopping") == "stopping" and r.get("landed") is True, f"{r.get('stopping')!r}, {r.get('landed')}")
    al = r.get("afterLanding") or {}
    check("9c: after a CLEAN landing the panel STAYS HIDDEN — the note is empty, so revealIfNoted showed "
          "nothing (reveal-always); hiddenForRecording and showWhenLanded cleared, the item down, the "
          "recorder idle",
          al.get("visible") is False and al.get("note") == "" and al.get("hiddenForRecording") is False
          and al.get("showWhenLanded") is False and al.get("itemDown") is True and al.get("recorder") == "idle",
          f"{al}")
    d = r.get("document") or {}
    clips = d.get("clips") or []
    check(f"9c: one document opened — two media, ['Track 1'], two clips touching from 0 with no transition, "
          f"the undo step {SEGMENTS_ACTION_NAME!r}, canvas [60, 1], edited",
          r.get("documentsOpened") == 1 and d.get("media") == 2 and d.get("tracks") == ["Track 1"]
          and len(clips) == 2 and clips[0].get("start") == 0 and clips[1].get("start") == clips[0].get("end")
          and not any(c.get("transition") for c in clips) and d.get("undoName") == SEGMENTS_ACTION_NAME
          and d.get("canvasFps") == [60, 1] and d.get("edited") is True, f"{d}")
    paths = d.get("mediaPaths") or []
    check("9c: its displayName is the FIRST segment's stem and both media are files in the pinned folder",
          len(paths) == 2 and d.get("displayName") == os.path.splitext(os.path.basename(paths[0]))[0]
          and all(os.path.dirname(p) == folder for p in paths), f"{d.get('displayName')!r}, {paths}")


# --------------------------------------------------------------------------
# Section 10 — the grants a press checks (spec §11 recording): the step, the
# panes, the notes, the press through a spy, and where the calls may live.

SCREEN_PANE_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
MICROPHONE_PANE_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
SETTINGS_APP = "/System/Applications/System Settings.app"
PRIVACY_EXTENSION = "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex"


def expected_screen_step(granted, asked, launchd):
    if granted:
        return "proceed"
    if not launchd:
        return "ask"
    return "openPane" if asked else "ask"


MICROPHONE_STEPS = {"authorized": "proceed", "notDetermined": "ask", "denied": "openPane",
                    "restricted": "openPane"}


def find_key(obj, key):
    """The first value under `key` anywhere in a plist tree, or None."""
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        for value in obj.values():
            found = find_key(value, key)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = find_key(value, key)
            if found is not None:
                return found
    return None


def section_grants(binary, sources):
    import plistlib
    print("\nSection 10 — the grants a press checks: the step, the two panes, the notes, the press "
          "through a spy (no prompt, no pane), and where the calls may live")
    answer, error = run_probe(binary, "grants", {"mode": "grants"})
    check("10: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return

    print("  10a — screenStep over granted × asked × launchedByLaunchd")
    by = {(r.get("granted"), r.get("asked"), r.get("launchd")): r.get("step")
          for r in answer.get("screenSteps") or []}
    for granted, asked, launchd in itertools.product([False, True], repeat=3):
        want = expected_screen_step(granted, asked, launchd)
        got = by.get((granted, asked, launchd))
        check(f"10a: granted {granted}, asked {asked}, launchd {launchd} → {want}", got == want,
              f"got {got!r}")

    print("  10b — microphoneStep")
    mic = {r.get("status"): r.get("step") for r in answer.get("microphoneSteps") or []}
    for status, want in MICROPHONE_STEPS.items():
        check(f"10b: {status} → {want}", mic.get(status) == want, f"got {mic.get(status)!r}")

    print("  10c — the two pane URLs, their handler, and the extension that answers them")
    u = answer.get("urls") or {}
    check("10c: the Screen Recording pane URL, exactly", u.get("screen") == SCREEN_PANE_URL,
          f"{u.get('screen')!r}")
    check("10c: the Microphone pane URL, exactly", u.get("microphone") == MICROPHONE_PANE_URL,
          f"{u.get('microphone')!r}")
    check("10c: both schemes are x-apple.systempreferences",
          u.get("screenScheme") == "x-apple.systempreferences"
          and u.get("microphoneScheme") == "x-apple.systempreferences", f"{u}")
    check(f"10c: the screen URL resolves to {SETTINGS_APP} (resolved, never opened)",
          (u.get("screenHandler") or "").rstrip("/") == SETTINGS_APP, f"{u.get('screenHandler')!r}")
    check(f"10c: the microphone URL resolves to {SETTINGS_APP}",
          (u.get("microphoneHandler") or "").rstrip("/") == SETTINGS_APP,
          f"{u.get('microphoneHandler')!r}")
    host = SCREEN_PANE_URL.split(":", 1)[1].split("?", 1)[0]
    info_path = os.path.join(PRIVACY_EXTENSION, "Contents", "Info.plist")
    try:
        with open(info_path, "rb") as f:
            info = plistlib.load(f)
    except (OSError, plistlib.InvalidFileException) as exc:
        info = None
        info_error = str(exc)
    else:
        info_error = ""
    check("10c: the privacy extension's Info.plist reads", info is not None, info_error)
    legacy = find_key(info, "legacyBundleIdentifier") if info is not None else None
    allows = find_key(info, "allowsXAppleSystemPreferencesURLScheme") if info is not None else None
    check(f"10c: its legacyBundleIdentifier is the URLs' host ({host})",
          legacy == host and u.get("screenHost") == host, f"legacy {legacy!r}, URL {u.get('screenHost')!r}")
    check("10c: allowsXAppleSystemPreferencesURLScheme is true", allows is True, f"{allows!r}")
    binary_path = os.path.join(PRIVACY_EXTENSION, "Contents", "MacOS", "SecurityPrivacyExtension")
    try:
        with open(binary_path, "rb") as f:
            blob = f.read()
    except OSError:
        blob = b""
    for anchor in ["Privacy_ScreenCapture", "Privacy_Microphone"]:
        check(f"10c: the extension's binary holds {anchor}", anchor.encode() in blob,
              f"{len(blob)} bytes read")

    print("  10d — the opened notes")
    n = answer.get("notes") or {}
    pane = n.get("paneSentence") or "\u0000"
    opened = n.get("openedSentence") or "\u0000"
    clause = n.get("launchClause")
    screen_opened = n.get("screenOpened") or ""
    check("10d: the opened sentence names System Settings and the pane",
          opened == " System Settings is open at that pane.", f"{opened!r}")
    check("10d: the screen's opened note starts with the pane sentence",
          screen_opened.startswith(pane), f"{screen_opened!r}")
    check("10d: … holds the opened sentence", opened in screen_opened, f"{screen_opened!r}")
    check("10d: … and ends with launchClause (non-empty from a probe)",
          bool(clause) and screen_opened.endswith(clause)
          and screen_opened == pane + opened + clause, f"{screen_opened!r}")
    for word in ["denied", "restricted"]:
        key = word.capitalize()
        got = n.get(f"micOpened{key}") or ""
        refusal = n.get(f"micRefusal{key}") or "\u0000"
        head = refusal[: len(refusal) - len(clause or "")]
        check(f"10d: microphoneOpenedNote(.{word}) keeps the refusal's head and fix, then the opened "
              "sentence and the clause",
              bool(clause) and refusal.endswith(clause) and got == head + opened + clause
              and f"(status: {word})" in got, f"{got!r}")

    print("  10e — the press, through record(_:), one spy per row (launchd true for rows 1–9)")
    rows = answer.get("rows") or {}
    refusal = n.get("screenRefusal") or "\u0000"
    countdown = answer.get("countdown") or "\u0000"
    check("10e: the panel is on screen for the rows", answer.get("visible") is True,
          f"{answer.get('visible')}")
    r = rows.get("1") or {}
    check("10e 1: ungranted, not asked → ONE request", r.get("screenRequests") == 1, f"{r}")
    check("10e 1: … nothing opened", r.get("opened") == [], f"{r.get('opened')}")
    check("10e 1: … the flag set", r.get("asked") is True and r.get("remembered") == 1, f"{r}")
    check("10e 1: … idle, the refusal note", r.get("phase") == "idle" and r.get("note") == refusal,
          f"{r.get('phase')}, {r.get('note')!r}")
    r = rows.get("2") or {}
    check("10e 2: pressed again → still one request", r.get("screenRequests") == 1, f"{r}")
    check("10e 2: … the Screen Recording pane opened, once", r.get("opened") == [SCREEN_PANE_URL],
          f"{r.get('opened')}")
    check("10e 2: … the opened note", r.get("note") == screen_opened and r.get("phase") == "idle",
          f"{r.get('note')!r}")
    r = rows.get("3") or {}
    check("10e 3: asked, the opener answers false → the pane was tried",
          r.get("opened") == [SCREEN_PANE_URL] and r.get("screenRequests") == 0, f"{r}")
    check("10e 3: … and the note is the plain refusal, never the opened one",
          r.get("note") == refusal, f"{r.get('note')!r}")
    for key, word in [("4", "denied"), ("5", "restricted")]:
        r = rows.get(key) or {}
        want = n.get(f"micOpened{word.capitalize()}")
        check(f"10e {key}: granted, mic {word} → the Microphone pane opened",
              r.get("opened") == [MICROPHONE_PANE_URL] and r.get("micChoice") == "probe-mic",
              f"{r.get('opened')}, choice {r.get('micChoice')!r}")
        check(f"10e {key}: … no requests", r.get("screenRequests") == 0 and r.get("micRequests") == 0,
              f"{r}")
        check(f"10e {key}: … idle, microphoneOpenedNote(.{word})",
              r.get("phase") == "idle" and r.get("note") == want, f"{r.get('note')!r}")
    r = rows.get("6") or {}
    check("10e 6: mic notDetermined → ONE microphone request, the button disabled",
          r.get("micRequests") == 1 and r.get("buttonEnabled") is False and r.get("phase") == "idle",
          f"{r}")
    check("10e 6: the held answer fired with the status now denied → the button enabled",
          r.get("heldFired") is True and r.get("afterButtonEnabled") is True, f"{r}")
    check("10e 6: … the note microphoneRefusal(.denied)",
          r.get("afterNote") == n.get("micRefusalDenied") and r.get("afterPhase") == "idle",
          f"{r.get('afterNote')!r}")
    check("10e 6: … and nothing opened (a prompt's answer never opens Settings)",
          r.get("afterOpened") == [] and r.get("afterMicRequests") == 1, f"{r}")
    r = rows.get("7") or {}
    check(f"10e 7: mic authorized → {countdown}", r.get("phase") == countdown, f"{r.get('phase')}")
    check("10e 7: … nothing called",
          r.get("screenRequests") == 0 and r.get("micRequests") == 0 and r.get("opened") == []
          and r.get("remembered") == 0, f"{r}")
    r = rows.get("8") or {}
    check(f"10e 8: mic Off (its status denied) → {countdown}",
          r.get("phase") == countdown and r.get("micChoice") == "", f"{r}")
    check("10e 8: … nothing called",
          r.get("screenRequests") == 0 and r.get("micRequests") == 0 and r.get("opened") == [],
          f"{r}")
    r = rows.get("9") or {}
    check("10e 9: granted with the flag false → the flag stays false",
          r.get("asked") is False and r.get("remembered") == 0 and r.get("phase") == countdown, f"{r}")
    r = rows.get("10") or {}
    s = r.get("second") or {}
    check("10e 10: launchd false, ungranted, flag false, pressed twice → two requests",
          r.get("screenRequests") == 1 and s.get("screenRequests") == 2, f"{r.get('screenRequests')}, "
          f"{s.get('screenRequests')}")
    check("10e 10: … nothing opened", r.get("opened") == [] and s.get("opened") == [], f"{s.get('opened')}")
    levels = {k: (rows.get(k) or {}).get("level") for k in [str(i) for i in range(1, 12)]}
    levels["10b"] = ((rows.get("10") or {}).get("second") or {}).get("level")
    levels["6after"] = (rows.get("6") or {}).get("afterLevel")
    stepped = ["1", "2", "3", "4", "5", "6", "6after", "10", "10b", "11"]
    check("10e: the panel steps down to normal level for every prompt or pane, and floats "
          "again for every press that goes on (7 follows 6's normal)",
          all(levels.get(k) == "normal" for k in stepped)
          and all(levels.get(k) == "floating" for k in ["7", "8", "9"]), f"{levels}")
    check("10e 10: … the flag still false (a shell launch never remembers)",
          s.get("asked") is False and s.get("remembered") == 0, f"{s}")
    check("10e 10: … the refusal note each time",
          r.get("note") == refusal and s.get("note") == refusal, f"{r.get('note')!r} / {s.get('note')!r}")
    r = rows.get("11") or {}
    check("10e 11: launchd false, ungranted, flag TRUE → one request, nothing opened",
          r.get("screenRequests") == 1 and r.get("opened") == [] and r.get("note") == refusal, f"{r}")

    print("  10f — where the calls may live (comment-stripped source)")
    names = sorted(n for n in os.listdir(sources) if n.endswith(".swift"))
    tool_side = [n for n in names
                 if n.startswith("AgentServer+Recording") or n.startswith("ScreenRecorder")]
    check("10f: the tool's side has files to read", len(tool_side) >= 4, f"{tool_side}")
    codes = {name: read_code(sources, name) or "" for name in names}
    for token in ["CGRequestScreenCaptureAccess(", "requestAccess(", "NSWorkspace"]:
        holders = [name for name in tool_side if token in codes[name]]
        check(f"10f: `{token}` in no AgentServer+Recording*/ScreenRecorder* file", holders == [],
              f"{holders}")
    holders = [name for name in names if "x-apple.systempreferences" in codes[name]]
    check("10f: `x-apple.systempreferences` only in RecordingSetup.swift",
          holders == ["RecordingSetup.swift"], f"{holders}")
    holders = [name for name in names if "CGRequestScreenCaptureAccess(" in codes[name]]
    check("10f: `CGRequestScreenCaptureAccess(` only in RecorderPanelController+Grants.swift",
          holders == ["RecorderPanelController+Grants.swift"], f"{holders}")


# --------------------------------------------------------------------------
# Section 14 — issue batch B55 (#181 item 2, spec §11 recording): a left-out
# segment's readable microphone lands without its picture, in its slot.

LEFTOUT_B_LEN = 3 * SEC                # B's voice, 3 s — its slot at 30 and 60 fps


def leftout_clip(clips, media):
    """The one clip whose source is `media`, or {} (none, or several)."""
    hits = [c for c in clips if c.get("media") == media]
    return hits[0] if len(hits) == 1 else {}


def section_leftout(binary, sources):
    print("\nSection 14 — issue batch B55 (#181 item 2): a left-out segment's readable voice lands in "
          "its picture's slot, the picture track empty there")
    tmp = fresh_dir("leftout")
    answer, error = run_probe(binary, "leftout", {"mode": "leftout", "tempFolder": tmp})
    check("14: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    check("14: the shared controller is the probe's", answer.get("controllerIsProbe") is True,
          f"{answer.get('controllerIsProbe')}")
    mic_b = answer.get("micB") or "?"
    path_a = answer.get("pathA") or "?"

    print("  X1 — [A, left-out B (3 s voice), C] in a fresh document, playhead 0")
    x1 = answer.get("X1") or {}
    lists = x1.get("lists") or {}
    clips = x1.get("allClips") or []
    media = lists.get("media") or [-1, -1]
    mic_media = lists.get("micMedia") or [-1, -1]
    lo_media = (lists.get("leftOutMicMedia") or [-1])[0]
    lo_clip = (lists.get("leftOutMicClips") or [-1])[0]
    pic_a = leftout_clip(clips, media[0])
    pic_c = leftout_clip(clips, media[1] if len(media) > 1 else -1)
    voice_b = leftout_clip(clips, lo_media)
    voice_c = leftout_clip(clips, mic_media[1] if len(mic_media) > 1 else -1)
    tracks = {t.get("id"): t.get("name") for t in x1.get("allTracks") or []}
    check("X1: the stretches are [segment 0, B's voice, segment 1] and the placement lands — no throw",
          not x1.get("error") and x1.get("stretches") == ["segment0", "voice0", "segment1"],
          f"{x1.get('error') or x1.get('stretches')}")
    check("X1: picture A at 0, 3 000 000 long (5 s at 30 fps)",
          pic_a.get("start") == 0 and pic_a.get("duration") == PICTURE_LEN, f"{pic_a}")
    check("X1: B's voice at 3 000 000 — picture A's end — 1 800 000 long, `in` 0, on the "
          "Microphone track (leftout-no-gap, leftout-voice-dropped)",
          voice_b.get("start") == PICTURE_LEN and voice_b.get("duration") == LEFTOUT_B_LEN
          and voice_b.get("in") == 0 and tracks.get(voice_b.get("track")) == "Microphone"
          and voice_b.get("id") == lo_clip, f"{voice_b}, leftOut clip {lo_clip}")
    check("X1: picture C at 4 800 000 — the slot's end — on picture A's track (leftout-no-gap, "
          "leftout-voice-dropped)",
          pic_c.get("start") == PICTURE_LEN + LEFTOUT_B_LEN and pic_c.get("track") == pic_a.get("track"),
          f"{pic_c}")
    check("X1: C's voice at 4 800 000 on the same Microphone track, `in` 0 — later segments keep "
          "their timing against their own voices",
          voice_c.get("start") == PICTURE_LEN + LEFTOUT_B_LEN and voice_c.get("in") == 0
          and voice_c.get("track") == voice_b.get("track"), f"{voice_c}")
    covering = [c for c in clips if c.get("track") == pic_a.get("track")
                and c.get("start", 0) < PICTURE_LEN + LEFTOUT_B_LEN and c.get("end", 0) > PICTURE_LEN]
    check("X1: no picture clip covers [3 000 000, 4 800 000) — the picture track is empty in the slot",
          bool(pic_a) and not covering, f"{covering}")
    predicted_media = sorted(m for m in media + mic_media + [lo_media] if m != -1)
    predicted_clips = sorted(c for c in (lists.get("clips") or []) + (lists.get("micClips") or [])
                             + (lists.get("leftOutMicClips") or []) if c != -1)
    minted_clips = sorted(c.get("id") for c in x1.get("mintedClips") or [])
    check("X1: predicted equals minted — five media and five clips, both left-out lists included",
          predicted_media == sorted(x1.get("mintedMedia") or []) and len(predicted_media) == 5
          and predicted_clips == minted_clips and len(minted_clips) == 5 and lo_media != -1
          and lo_clip != -1,
          f"media {predicted_media} vs {x1.get('mintedMedia')}, clips {predicted_clips} vs {minted_clips}")
    check("X1: one undo step, \"Add Recording\", and no placement note",
          x1.get("undoName") == ACTION_NAME and x1.get("notes") == [],
          f"{x1.get('undoName')!r}, {x1.get('notes')}")

    print("  X2 — B recorded first (position 0), playhead at 1 s")
    x2 = answer.get("X2") or {}
    l2 = x2.get("lists") or {}
    c2 = x2.get("allClips") or []
    m2 = l2.get("media") or [-1, -1]
    v2 = leftout_clip(c2, (l2.get("leftOutMicMedia") or [-1])[0])
    a2 = leftout_clip(c2, m2[0])
    k2 = leftout_clip(c2, m2[1] if len(m2) > 1 else -1)
    check("X2: B's voice at 600 000 (the playhead), 1 800 000 long; picture A at 2 400 000 and C at "
          "its end (leftout-no-gap, leftout-voice-dropped)",
          x2.get("stretches") == ["voice0", "segment0", "segment1"]
          and v2.get("start") == SEC and v2.get("duration") == LEFTOUT_B_LEN
          and a2.get("start") == SEC + LEFTOUT_B_LEN
          and k2.get("start") == SEC + LEFTOUT_B_LEN + PICTURE_LEN,
          f"{x2.get('error') or x2.get('stretches')}, voice {v2}, A {a2}, C {k2}")

    print("  X3 — X1's result as a new project (60 fps)")
    x3 = answer.get("X3") or {}
    c3 = x3.get("clips") or []
    by_path = {m.get("path"): m.get("id") for m in x3.get("media") or []}
    pa3 = leftout_clip(c3, by_path.get(path_a, -2))
    vb3 = leftout_clip(c3, by_path.get(mic_b, -2))
    pc3 = [c for c in c3 if c.get("track") == pa3.get("track") and c.get("id") != pa3.get("id")]
    tracks3 = {t.get("id"): t.get("name") for t in x3.get("tracks") or []}
    check("X3: B's voice at clip 1's end, 1 800 000 long, on the Microphone track (leftout-no-gap, "
          "leftout-voice-dropped)",
          not x3.get("error") and bool(pa3) and vb3.get("start") == pa3.get("end")
          and vb3.get("duration") == LEFTOUT_B_LEN and tracks3.get(vb3.get("track")) == "Microphone",
          f"{x3.get('error') or ''} A {pa3}, voice {vb3}")
    check("X3: picture C at clip 1's end + 1 800 000, on clip 1's track",
          len(pc3) == 1 and pc3[0].get("start") == (pa3.get("end") or 0) + LEFTOUT_B_LEN, f"{pc3}")
    check("X3: one undo step \"Add Recording Segments\"; newProjectLeftOutIds names B's voice",
          x3.get("undoName") == "Add Recording Segments"
          and x3.get("leftOutIds") == [{"micMedia": by_path.get(mic_b, -2), "micClip": vb3.get("id", -2)}],
          f"{x3.get('undoName')!r}, {x3.get('leftOutIds')}")
    after = x3.get("afterUndo") or {}
    check("X3: one undo leaves picture A alone",
          [c.get("media") for c in after.get("clips") or []] == [by_path.get(path_a, -2)]
          and after.get("media") == 1, f"{after}")

    print("  X4 — B recorded before a new project's only segment")
    x4 = answer.get("X4") or {}
    m4 = {m.get("path"): m.get("id") for m in x4.get("media") or []}
    check("X4: B's voice lands as media with no clip, and the notes carry leadingVoiceNote's sentence "
          "(leftout-voice-dropped)",
          not x4.get("error") and mic_b in m4
          and not [c for c in x4.get("clips") or [] if c.get("media") == m4.get(mic_b)]
          and bool(x4.get("leadingNote")) and x4.get("leadingNote") in (x4.get("notes") or [])
          and mic_b in (x4.get("leadingNote") or "") and path_a in (x4.get("leadingNote") or ""),
          f"{x4.get('error') or ''} media {sorted(m4)}, notes {x4.get('notes')}")
    check("X4: the step is \"Add Microphone\" — one segment plus a left-out voice; \"Add Recording "
          "Segments\" when B's voice did not read",
          x4.get("undoName") == MIC_ACTION_NAME and x4.get("actionName") == MIC_ACTION_NAME
          and x4.get("actionNameWithoutB") == "Add Recording Segments",
          f"{x4.get('undoName')!r}, {x4.get('actionName')!r}, {x4.get('actionNameWithoutB')!r}")

    print("  X5 — place: false")
    x5 = answer.get("X5") or {}
    l5 = x5.get("lists") or {}
    check("X5: B's voice media is in the left-out list and minted; no clip lands at all "
          "(leftout-voice-dropped)",
          not x5.get("error") and (l5.get("leftOutMicMedia") or [-1])[0] != -1
          and (l5.get("leftOutMicMedia") or [-1])[0] in (x5.get("mintedMedia") or [])
          and l5.get("leftOutMicClips") == [-1] and x5.get("mintedClips") == [],
          f"{x5.get('error') or l5}, minted clips {x5.get('mintedClips')}")

    print("  X6 — what record_screen says about X1's landing")
    x6 = answer.get("X6") or {}
    u6 = x6.get("unreadable")
    e6 = u6[0] if isinstance(u6, list) and len(u6) == 1 and isinstance(u6[0], dict) else {}
    check("X6: unreadable[0] carries mic_path, mic_duration, mic_media and mic_clip — X1's ids "
          "(leftout-voice-dropped)",
          e6.get("mic_path") == mic_b and e6.get("mic_duration") == LEFTOUT_B_LEN
          and e6.get("mic_media") == lo_media and e6.get("mic_clip") == lo_clip and lo_clip != -1,
          f"{x6.get('error') or e6}")
    voice_note = f"The left-out segment's microphone, {mic_b}, was added to the project without its picture."
    check("X6: resultNotes is [unreadable, the left-out voice's note]; savedButNotAdded says no "
          "\"was added to the project\"",
          x6.get("leftOutVoiceNote") == voice_note
          and x6.get("resultNotes") == [x6.get("unreadableNote"), voice_note]
          and "was added to the project" not in (x6.get("saved") or "x was added to the project"),
          f"{x6.get('resultNotes')}, saved {x6.get('saved')!r}")
    check("X6: record_screen's description says the voice lands \"without its picture\"",
          "without its picture" in (x6.get("description") or ""), f"{len(x6.get('description') or '')} chars")

    print("  X7 — the control: a left-out B whose voice did NOT read changes nothing")
    x7 = answer.get("X7") or {}
    check("X7: the op list is byte for byte the same result's without B, and so are the lists",
          not x7.get("error") and bool(x7.get("with")) and x7.get("with") == x7.get("without")
          and x7.get("withNames") == x7.get("withoutNames")
          and (x7.get("withLists") or {}).get("leftOutMicMedia") == [-1]
          and {k: v for k, v in (x7.get("withLists") or {}).items() if not k.startswith("leftOut")}
          == {k: v for k, v in (x7.get("withoutLists") or {}).items() if not k.startswith("leftOut")},
          f"{x7.get('error') or ''} {x7.get('withNames')} vs {x7.get('withoutNames')}")

    print("  X8 — a new project whose first picture the core refuses, its voice and B's (B61, #213)")
    x8 = answer.get("X8") or {}
    mic_a = answer.get("micA") or "?"
    path_a0 = answer.get("pathA0") or "?"
    c8 = x8.get("clips")
    m8 = {m.get("path"): m.get("id") for m in x8.get("media") or []}
    check("X8 control: the core minted no clip for the 5 000-tick first picture (clips == [])",
          not x8.get("error") and c8 == [], f"{x8.get('error') or c8}")
    check("X8: A0's voice and B's voice are in the media list, neither with a clip",
          mic_a in m8 and mic_b in m8
          and not [c for c in c8 or [] if c.get("media") in (m8.get(mic_a), m8.get(mic_b))],
          f"media {sorted(m8)}, clips {c8}")
    unplaced = "was added to the media list without a clip: {} has no clip on the timeline for it to follow."
    want8 = [f"{mic_a} {unplaced.format(path_a0)}", f"{mic_b} {unplaced.format(path_a0)}"]
    check("X8: the notes are exactly unplacedNote for A0's voice, then for B's — the segment's voice "
          "first, then the left-out voice (unplaced-voice-unnoted, unplaced-leftout-unnoted)",
          x8.get("notes") == want8, f"{x8.get('notes')} vs {want8}")
    check("14: every document the section opened is closed", answer.get("documentsAfterClose") == 0,
          f"{answer.get('documentsAfterClose')}")


# --------------------------------------------------------------------------
# Section 13 — issue batch B27 (#98 c): the countdown's meter, read from the
# PREPARED capture session.

PREROLL_FLOOR = 1e-6   # −120 dBFS: above it, a real input is delivering levels


def preroll_rows(answer):
    """Every row of section 13 over the probe's answer."""
    p1 = answer.get("p1") or {}
    check("P1: a fresh ScreenRecorder() — never .shared — prepareMicrophone(id) leaves the session "
          "prepared for that device and running, the recorder still .idle",
          p1.get("prepared") is True and p1.get("running") is True and p1.get("state") == "idle", f"{p1}")
    p2 = answer.get("p2") or {}
    check(f"P2: 30 polls at 1/30 s while IDLE publish the prepared session's level — max peakLeft "
          f"> {PREROLL_FLOOR:g} (−120 dBFS), the state .idle throughout (preroll-gated)",
          (p2.get("maxPeakLeft") or 0) > PREROLL_FLOOR and p2.get("idleThroughout") is True, f"{p2}")
    p3 = answer.get("p3") or {}
    check("P3: discardPreparedMicrophone() publishes silence while idle and forgets the session "
          "(preroll-no-silence)",
          p3.get("silent") is True and p3.get("prepared") is False, f"{p3}")
    check("P3: … and a later poll, nothing prepared, publishes nothing",
          p3.get("laterPublishes") == 0, f"{p3}")
    p4 = answer.get("p4") or {}
    check("P4: the PANEL's Record (spied grants: granted, authorized) starts the countdown with the "
          "chosen microphone prepared on .shared, asking nothing",
          p4.get("chosen") is True and str(p4.get("phaseAtPress", "")).startswith("countdown")
          and p4.get("preparedAtPress") is True and p4.get("screenRequests") == 0
          and p4.get("micRequests") == 0, f"{p4}")
    check(f"P4: 1.2 s into the countdown — still counting, the recorder .idle — the panel's own tick "
          f"has lit ScreenRecorder.shared.meter: max peakLeft > {PREROLL_FLOOR:g} "
          f"(preroll-no-tick, preroll-gated)",
          str(p4.get("phase", "")).startswith("countdown") and p4.get("recorderState") == "idle"
          and (p4.get("maxPeakLeft") or 0) > PREROLL_FLOOR, f"{p4}")
    p5 = answer.get("p5") or {}
    check("P5: Cancel → the panel .idle, the shared recorder's session let go, the reading silent at "
          "once (preroll-no-silence)",
          p5.get("phase") == "idle" and p5.get("prepared") is False and p5.get("silent") is True
          and p5.get("recorderState") == "idle", f"{p5}")
    check("P5: … and still silent 0.3 s later, with no non-silent publish after the cancel",
          p5.get("silentLater") is True and p5.get("nonSilentAfter") == 0, f"{p5}")


def preroll_rows_count():
    """Section 13's row count, taken as `granted_rows_count` takes the
    granted tier's — the row code run over an empty answer with `check`
    swapped for a counter — so a skip's number cannot drift from the rows."""
    global check
    real = check
    counted = [0]

    def counter(name, ok, detail=""):
        counted[0] += 1

    check = counter
    try:
        import io
        import contextlib
        with contextlib.redirect_stdout(io.StringIO()):
            preroll_rows({})
    finally:
        check = real
    return counted[0]


def section_preroll(binary, sources):
    print("\nSection 13 — issue batch B27 (#98 c): the countdown's meter, read from the PREPARED "
          "capture session, and dark once it is let go")
    answer, error = run_probe(binary, "preroll", {"mode": "preroll"})
    check("13: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    print(f"  P0: Microphone status {answer.get('status')}; device {answer.get('device')!r} "
          f"({answer.get('transport')}) — facts, not asserted")
    if answer.get("skipped"):
        skip_rows(preroll_rows_count(), answer["skipped"])
        return
    preroll_rows(answer)

    def dbfs(value):
        return f"{20 * math.log10(value):.1f} dBFS" if value and value > 0 else "silent"
    print(f"  P2/P4: max peakLeft {dbfs((answer.get('p2') or {}).get('maxPeakLeft'))} over the fresh "
          f"recorder's 30 polls, {dbfs((answer.get('p4') or {}).get('maxPeakLeft'))} over the "
          f"countdown's 1.2 s — facts, not asserted")


# --------------------------------------------------------------------------
# Section 15 — #99 phase 1: the voice-over, the recorder's microphone-alone
# mode (spec §11 recording, "A voice-over is a recording with no picture").

VOICE_OPS = ["add_media", "add_media", "add_track", "add_clip", "add_clip"]
VOICE_NAME_DATE = time.mktime((2026, 10, 2, 9, 15, 4, 0, 0, -1))


def expected_voice_stem(seconds):
    return time.strftime("Voice-over %Y-%m-%d at %H.%M.%S", time.localtime(seconds))


def section_voiceover(binary, sources):
    print("\nSection 15 — #99 phase 1: the voice-over's names, refusals and landing (no grant)")
    tmp = fresh_dir("voiceover")
    answer, error = run_probe(binary, "voiceover", {
        "mode": "voiceover", "tempFolder": tmp, "stemDates": STEM_DATES,
        "nameDate": VOICE_NAME_DATE})
    check("15: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    check("15: the shared controller is the probe's", answer.get("controllerIsProbe") is True,
          f"{answer.get('controllerIsProbe')}")

    print("  V1 — the stem and the free name")
    stems = {s.get("seconds"): s.get("stem") for s in answer.get("stems") or []}
    for seconds in STEM_DATES:
        want = expected_voice_stem(seconds)
        check(f"V1: voiceOverStem → {want!r}", stems.get(seconds) == want, f"got {stems.get(seconds)!r}")
    v1 = answer.get("v1") or {}
    folder = v1.get("folder") or "?"
    stem = expected_voice_stem(VOICE_NAME_DATE)
    free = os.path.join(folder, f"{stem}.m4a")
    two = os.path.join(folder, f"{stem} (2).m4a")
    three = os.path.join(folder, f"{stem} (3).m4a")
    check("V1: nextVoiceOverURL over an empty folder, nothing held → <stem>.m4a",
          v1.get("free") == free, f"{v1.get('free')!r}")
    check("V1: … with that name HELD (not on disk) → <stem> (2).m4a (voice-held-ignored)",
          v1.get("held") == two, f"{v1.get('held')!r}")
    check("V1: … with <stem>.m4a on DISK and (2) held → <stem> (3).m4a (voice-held-ignored)",
          v1.get("onDisk") is True and v1.get("third") == three, f"{v1}")

    print("  V2 — a fresh recorder's refusals, answered before startVoiceOver returns")
    v2 = answer.get("v2") or {}
    display = v2.get("display") or {}
    no_mic = v2.get("noMic") or {}
    check("V2: a .display choice is refused (startFailed) before returning, the recorder idle",
          str(display.get("answer", "")).startswith("startFailed: ")
          and display.get("beforeReturn") is True and display.get("state") == "idle", f"{display}")
    check("V2: a nil microphone is refused with voiceOverNeedsMicrophoneSentence before returning",
          no_mic.get("answer") == f"startFailed: {v2.get('sentence')}"
          and no_mic.get("beforeReturn") is True and no_mic.get("state") == "idle", f"{no_mic}")
    check("V2: the recorder stays idle with no session, onFinish never called",
          v2.get("state") == "idle" and v2.get("isRecording") is False
          and v2.get("voiceSession") is False and v2.get("session") is False
          and v2.get("finishes") == 0, f"{v2}")
    check("V2: heldSegmentCount 0 and heldFilePaths empty",
          v2.get("heldSegmentCount") == 0 and v2.get("heldFilePaths") == [], f"{v2}")

    print("  V3 — two voice segments (3 s, 2 s), a 30 fps document whose front track holds "
          "[0, 10 s], playhead 2 s")
    v3 = answer.get("V3") or {}
    ops = op_json(v3)
    track_op = next((o for o in ops if o.get("op") == "add_track"), {})
    check("V3: ops [add_media, add_media, add_track, add_clip, add_clip] (voice-front-track)",
          v3.get("ops") == VOICE_OPS, v3.get("error") or f"{v3.get('ops')}")
    check("V3: the document is 30 fps and the playhead is at 2 s",
          v3.get("canvasFps") == [30, 1] and v3.get("playhead") == 2 * SEC,
          f"{v3.get('canvasFps')}, {v3.get('playhead')}")
    after = v3.get("tracksAfter") or []
    minted_tracks = v3.get("mintedTracks") or []
    check("V3: add_track at index 0 named \"Microphone\" — the new track is the BACK one "
          "(voice-front-track)",
          track_op.get("index") == 0 and track_op.get("name") == "Microphone"
          and len(minted_tracks) == 1 and bool(after) and after[0] == minted_tracks[0]
          and after[0].get("name") == "Microphone", f"{track_op}, after {after}")
    clips = sorted(v3.get("mintedClips") or [], key=lambda c: c.get("start", 0))
    check("V3: the clips start at 1 200 000 and 3 000 000, touching, on the new track, `in` 0, "
          "no transition (voice-front-track)",
          [c.get("start") for c in clips] == [2 * SEC, 5 * SEC]
          and [c.get("duration") for c in clips] == [3 * SEC, 2 * SEC]
          and all(c.get("track") == (minted_tracks or [{}])[0].get("id") for c in clips)
          and all(c.get("in") == 0 and not c.get("transition") for c in clips), f"{clips}")
    lists = v3.get("predictedLists") or {}
    check("V3: the predicted media and clip ids are the minted ones",
          lists.get("media") == v3.get("mintedMedia") and len(lists.get("media") or []) == 2
          and sorted(lists.get("clips") or []) == sorted(c.get("id") for c in clips)
          and len(clips) == 2, f"predicted {lists}, minted {v3.get('mintedMedia')} {clips}")
    check("V3: every mic… id is nil",
          lists.get("micMedia") == [-1, -1] and lists.get("micClips") == [-1, -1]
          and (v3.get("predicted") or {}).get("micMedia") == -1
          and (v3.get("predicted") or {}).get("micClip") == -1, f"{lists}")
    before = v3.get("tracksBefore") or []
    check("V3: the front track is unchanged — same track, same name, the 10 s clip where it was",
          bool(before) and after[-1:] == before[-1:] and v3.get("blockerBefore") == v3.get("blockerAfter")
          and len(v3.get("blockerBefore") or []) == 1, f"{before} → {after}")
    check("V3: one undo step \"Add Recording\", and one undo gives back the project JSON byte for byte",
          v3.get("undoName") == ACTION_NAME and v3.get("undoRestores") is True,
          f"{v3.get('undoName')!r}, restores {v3.get('undoRestores')}")

    print("  V4 — place: false")
    v4 = answer.get("V4") or {}
    check("V4: media only — ops [add_media, add_media], no clip, no track, every clip id nil",
          v4.get("ops") == ["add_media", "add_media"] and v4.get("mintedClips") == []
          and v4.get("mintedTracks") == [] and (v4.get("predictedLists") or {}).get("clips") == [-1, -1]
          and len(v4.get("mintedMedia") or []) == 2, v4.get("error") or f"{v4}")

    print("  V5 — a segment under a frame")
    v5 = answer.get("V5") or {}
    l5 = v5.get("predictedLists") or {}
    check("V5: a 5 000-tick segment gets no clip and its tooShortNote; the 2 s one lands",
          (l5.get("clips") or [0])[0] == -1 and len(v5.get("mintedClips") or []) == 1
          and v5.get("notes") == [v5.get("expectedNote")] and "too short" in (v5.get("expectedNote") or ""),
          v5.get("error") or f"clips {l5.get('clips')}, notes {v5.get('notes')}, want {v5.get('expectedNote')!r}")
    short = v5.get("allShort") or {}
    check("V5: every segment under a frame → no add_track is sent, no track, no clip, two notes "
          "(voice-track-always)",
          short.get("ops") == ["add_media", "add_media"] and short.get("mintedTracks") == []
          and short.get("mintedClips") == [] and len(short.get("notes") or []) == 2,
          short.get("error") or f"{short.get('ops')}, tracks {short.get('mintedTracks')}")

    print("  V6 — inside an open nest")
    v6 = answer.get("V6") or {}
    inner = v6.get("innerTracks") or []
    inner_clips = [c for c in v6.get("innerClips") or []
                   if c.get("id") in [m.get("id") for m in v6.get("mintedClips") or []]]
    check("V6: the ops come back unscoped and add_media lands in the document's one list",
          v6.get("scopes") == [-1] * 5 and v6.get("scope", -1) != -1
          and v6.get("outerMedia") == (v6.get("outerMediaBefore") or 0) + 2,
          v6.get("error") or f"scopes {v6.get('scopes')}, scope {v6.get('scope')}, "
          f"media {v6.get('outerMediaBefore')} → {v6.get('outerMedia')}")
    check("V6: the clips sit on the NEST's new back track \"Microphone\", touching from the "
          "nest-local playhead 0; the parent's clips and tracks unchanged",
          v6.get("ops") == VOICE_OPS and bool(inner) and inner[0].get("name") == "Microphone"
          and len(inner_clips) == 2 and all(c.get("track") == inner[0].get("id") for c in inner_clips)
          and sorted(c.get("start") for c in inner_clips) == [0, 3 * SEC]
          and v6.get("outerClips") == v6.get("outerClipsBefore")
          and v6.get("outerTracks") == v6.get("outerTracksBefore"),
          f"inner tracks {inner}, clips {inner_clips}, outer {v6.get('outerClips')}/"
          f"{v6.get('outerTracks')}")

    print("  V7 — a voice-over as a new project, rate 30")
    v7 = answer.get("V7") or {}
    c7 = sorted(v7.get("clips") or [], key=lambda c: c.get("start", 0))
    check("V7: canvas 1920×1080 at [30, 1]",
          v7.get("canvas") == [1920, 1080] and v7.get("canvasFps") == [30, 1],
          v7.get("error") or f"{v7.get('canvas')} {v7.get('canvasFps')}")
    first_track = (v7.get("tracks") or [{}])[0].get("id")
    check("V7: clip 2 sits at clip 1's end on track 1 (the document's one track)",
          len(c7) == 2 and c7[0].get("start") == 0 and c7[1].get("start") == c7[0].get("end")
          and c7[0].get("track") == c7[1].get("track") == first_track
          and len(v7.get("tracks") or []) == 1, f"{c7}, tracks {v7.get('tracks')}")
    check("V7: the undo step is \"Add Recording Segments\", no note, and one undo leaves clip 1",
          v7.get("undoName") == SEGMENTS_ACTION_NAME and v7.get("notes") == []
          and len(v7.get("afterUndo") or []) == 1 and c7[:1]
          and (v7.get("afterUndo") or [{}])[0].get("id") == c7[0].get("id"),
          f"{v7.get('undoName')!r}, notes {v7.get('notes')}, after undo {v7.get('afterUndo')}")

    print("  V8 — the control: the same descriptors with a .display source take the picture rule")
    v8 = answer.get("V8") or {}
    ops8 = op_json(v8)
    t8 = next((o for o in ops8 if o.get("op") == "add_track"), {})
    after8 = v8.get("tracksAfter") or []
    minted8 = v8.get("mintedTracks") or []
    check("V8: a new FRONT track (index 1), not named \"Microphone\" — the picture rule",
          v8.get("ops") == VOICE_OPS and t8.get("index") == 1 and t8.get("name") != "Microphone"
          and len(minted8) == 1 and after8[-1:] == minted8, v8.get("error") or f"{t8}, {after8}")

    print("  V9 — a 30 fps document at the 64-track cap (issue batch B66, nit 3)")
    v9 = answer.get("V9") or {}
    expected_notes = v9.get("expectedNotes") or []
    check("V9: the document is 30 fps and holds 64 tracks before the landing",
          v9.get("canvasFps") == [30, 1] and v9.get("tracksBefore") == 64,
          f"{v9.get('canvasFps')}, {v9.get('tracksBefore')}")
    check("V9a: 5 000 and 4 000 ticks → no throw, ops [add_media, add_media], clipIds [nil, nil], "
          "notes the two tooShortNotes, 64 tracks after the commit (voice-cap-trial-always)",
          not v9.get("error") and v9.get("ops") == ["add_media", "add_media"]
          and (v9.get("predictedLists") or {}).get("clips") == [-1, -1]
          and len(expected_notes) == 2 and "<no media>" not in expected_notes
          and v9.get("notes") == expected_notes and v9.get("tracksAfter") == 64,
          v9.get("error") or f"ops {v9.get('ops')}, clips {(v9.get('predictedLists') or {}).get('clips')}, "
          f"notes {v9.get('notes')} want {expected_notes}, tracks {v9.get('tracksAfter')}")
    check("V9b (control): 5 000 ticks and 2 s at the cap → throws too many tracks: 65 (max 64)",
          "too many tracks: 65 (max 64)" in str(v9.get("control")), f"{v9.get('control')!r}")

    print("  V10 — a did-finish judged by when it ARRIVED (issue batch B66, nit 2)")
    own = ("The microphone stopped recording on its own: It reported no error. "
           "The voice-over ends where it stopped.")

    def first_segment(row):
        segments = ((row.get("outcome") or {}).get("segments") or [{}])
        return segments[0] if segments else {}

    v10a = answer.get("V10a") or {}
    o10a = v10a.get("outcome") or {}
    check("V10a: stop(), then a did-finish that ARRIVED before it → one .success whose segment "
          "says the microphone stopped on its own (voice-own-stop-asked)",
          v10a.get("outcomes") == 1 and o10a.get("kind") == "success"
          and first_segment(v10a).get("micProblem") == own,
          v10a.get("error") or f"{v10a.get('outcomes')} outcomes, {o10a.get('kind')} "
          f"{o10a.get('description') or ''}, micProblem {first_segment(v10a).get('micProblem')!r}")
    v10b = answer.get("V10b") or {}
    o10b = v10b.get("outcome") or {}
    check("V10b (control): stop(), then a did-finish that arrived AFTER it → .success, no micProblem",
          v10b.get("outcomes") == 1 and o10b.get("kind") == "success"
          and first_segment(v10b).get("micProblem") is None,
          v10b.get("error") or f"{v10b.get('outcomes')} outcomes, {o10b.get('kind')} "
          f"{o10b.get('description') or ''}, micProblem {first_segment(v10b).get('micProblem')!r}")
    v10c = answer.get("V10c") or {}
    o10c = v10c.get("outcome") or {}
    check("V10c: pause(), then a did-finish that arrived before it → the recorder finishes by itself: "
          ".success, pauses 1, the on-its-own sentence, idle after (voice-own-stop-asked)",
          v10c.get("pause") == "ok" and v10c.get("stateAfterPause") == "paused"
          and v10c.get("outcomes") == 1 and o10c.get("kind") == "success" and o10c.get("pauses") == 1
          and first_segment(v10c).get("micProblem") == own and v10c.get("finalState") == "idle",
          v10c.get("error") or f"pause {v10c.get('pause')} → {v10c.get('stateAfterPause')}, "
          f"{v10c.get('outcomes')} outcomes, {o10c.get('kind')}, pauses {o10c.get('pauses')}, "
          f"micProblem {first_segment(v10c).get('micProblem')!r}, final {v10c.get('finalState')}")
    check("15: every document the section opened is closed", answer.get("documentsAfterClose") == 0,
          f"{answer.get('documentsAfterClose')}")


VOICE_STRANGERS = ["display", "window", "system_audio", "show_clicks", "size"]
VOICE_TAIL = " cannot be given — a voice-over records the microphone alone."


def section_voiceover_doors(binary, sources):
    print("\nSection 16 — #99 phase 2: the voice-over's doors — the panel's Microphone Only row "
          "and record_screen's source (no grant; the panel never shown)")
    answer, error = run_probe(binary, "voiceover-doors", {"mode": "voiceover-doors"})
    check("16: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if not answer or answer.get("error"):
        return
    check("16: the panel is never shown", answer.get("visible") is False, f"{answer.get('visible')}")

    d1 = answer.get("D1") or {}
    check("D1: the Source rows end \"Window…\" (tag 1), \"Camera\" (tag 3), \"Microphone Only\" "
          "(tag 2), with no separator between",
          d1.get("titles") == ["Window…", "Camera", "Microphone Only"] and d1.get("tags") == [1, 3, 2]
          and d1.get("separatorIndex") == d1.get("screens"), f"{d1}")
    check("D1: count = NSScreen.screens + 4", d1.get("count") == (d1.get("screens") or -9) + 4, f"{d1}")

    d2 = answer.get("D2") or {}
    before = d2.get("before") or {}
    after = d2.get("after") or {}
    check("D2: choosing it via controlChanged → currentChoice().source is .voiceOver",
          d2.get("source") is True and d2.get("selected") is True, f"{d2}")
    check("D2: System Audio, Show Clicks, Size and Include Frame Job windows disabled, their values "
          "unchanged (voice-row-live)",
          after.get("systemAudio") is False and after.get("showClicks") is False
          and after.get("size") is False and after.get("includeFrameJob") is False
          and before.get("includeFrameJob") is True
          and after.get("values") == before.get("values")
          and before.get("systemAudio") is True and before.get("values") == [0, 1, 1],
          f"before {before}, after {after}")
    check("D2: Source, Microphone, Rate and Record Into stay enabled",
          d2.get("sourceEnabled") is True and d2.get("microphone") is True
          and d2.get("rate") is True and d2.get("destination") is True, f"{d2}")
    check("D2: the size note reads voiceOverSizeNote",
          d2.get("sizeNote") == d2.get("expectedNote") and bool(d2.get("expectedNote")),
          f"{d2.get('sizeNote')!r}")

    d3 = answer.get("D3") or {}
    check("D3: the display key is not written for the row (the sentinel 777 kept), and the set of "
          "FrameJobRecording… keys is unchanged — session only",
          d3.get("display") == 777 and d3.get("keysBefore") == d3.get("keysAfter")
          and len(d3.get("keysAfter") or []) == 9, f"{d3}")
    check("D3: rebuildSources() + restoreChoices() keep the row",
          d3.get("kept") is True and d3.get("keptSource") is True, f"{d3}")

    d4 = answer.get("D4") or {}
    a4 = d4.get("after") or {}
    check("D4: a display row → source .display, the four enabled again",
          d4.get("display") is True and a4.get("systemAudio") is True and a4.get("showClicks") is True
          and a4.get("size") is True and a4.get("includeFrameJob") is True, f"{d4}")

    d5 = answer.get("D5") or {}
    check("D5: Record with Microphone Off → idle, the note microphoneOffSentence, 0 screen reads, "
          "0 microphone requests (voice-screen-grant-read)",
          d5.get("phase") == "idle" and d5.get("note") == d5.get("expected") and bool(d5.get("expected"))
          and d5.get("screenReads") == 0 and d5.get("screenRequests") == 0
          and d5.get("micRequests") == 0 and d5.get("opened") == [], f"{d5}")

    d6 = answer.get("D6") or {}
    check("D6: a microphone chosen and authorized, the screen grant absent → countdown(3), 0 screen "
          "reads, 0 screen requests, nothing opened (voice-screen-grant-read)",
          d6.get("phase") == "countdown(3)" and d6.get("screenReads") == 0
          and d6.get("screenRequests") == 0 and d6.get("micRequests") == 0 and d6.get("opened") == [],
          f"{d6}")

    d7 = answer.get("D7") or {}
    check("D7: the countdown run out → idle, the note exactly a fresh recorder's startVoiceOver "
          "refusal for the same choice, still no screen read, the panel never hidden",
          d7.get("phase") == "idle" and d7.get("note") == d7.get("expected")
          and d7.get("expected") not in (None, "", "nil", "unanswered")
          and d7.get("screenReads") == 0 and d7.get("recorderIdle") is True
          and d7.get("hidden") is False, f"{d7}")

    d8 = answer.get("D8") or {}
    check("D8: hidesForRecording — false for .voiceOver and .camera, true for .display, .window, "
          ".picked (voice-panel-hides)",
          d8.get("voiceOver") is False and d8.get("camera") is False and d8.get("display") is True and d8.get("window") is True
          and d8.get("picked") is True, f"{d8}")

    d9 = answer.get("D9") or {}
    r9 = d9.get("recording") or {}
    p9 = d9.get("paused") or {}
    check("D9: the Pause button is hidden while idle", d9.get("idleHidden") is True, f"{d9}")
    check("D9: Microphone Only + .recording → visible, \"Pause\"",
          r9.get("hidden") is False and r9.get("title") == "Pause", f"{r9}")
    check("D9: … + .paused → visible, \"Resume\"",
          p9.get("hidden") is False and p9.get("title") == "Resume", f"{p9}")
    check("D9: a display source + .recording → hidden", d9.get("displayHidden") is True, f"{d9}")

    d10 = answer.get("D10") or {}
    voice_tail_all = ("error: With source voice_over, " + ", ".join(VOICE_STRANGERS) + VOICE_TAIL)
    rows = [
        ("{} → .screen", "empty", "ok: screen"),
        ("{source: screen} → .screen", "screen", "ok: screen"),
        ("{source: x} → the vocabulary sentence", "x",
         'error: source must be one of screen, voice_over, camera (got "x").'),
        ("{source: voice_over, display: 0} → display refused by name (voice-strangers-admitted)",
         "display", "error: With source voice_over, display" + VOICE_TAIL),
        ("all five strangers → named in voiceOverScreenOnlyArguments order "
         "(voice-strangers-admitted)", "all", voice_tail_all),
        ("{source: voice_over, microphone: false} → refused", "micFalse",
         "error: With source voice_over, microphone cannot be false — a voice-over records "
         "the microphone alone."),
        ("{source: voice_over, microphone: true} → .voiceOver", "micTrue", "ok: voice_over"),
        ("{source: voice_over, size: null} → .voiceOver (a null is not given)", "sizeNull",
         "ok: voice_over"),
        ("{source: voice_over, display: null} → .voiceOver", "displayNull", "ok: voice_over"),
    ]
    for label, key, want in rows:
        check(f"D10: {label}", d10.get(key) == want, f"got {d10.get(key)!r}")

    d11 = answer.get("D11") or {}
    check("D11: microphoneNote of a voice-over result is its micProblem, verbatim",
          d11.get("note") == d11.get("problem") and bool(d11.get("problem")), f"{d11.get('note')!r}")
    check("D11: finishTimeoutSentence(movies: [p], voiceOver: true) says \"its file is at\"; the "
          "screen's still says \"its movie is at\"",
          "its file is at /nowhere/v.m4a" in (d11.get("timeout") or "")
          and "its movie is at /nowhere/v.mov" in (d11.get("screenTimeout") or ""), f"{d11}")


# The granted tier's probe embeds an Info.plist holding the microphone's
# usage string ALONE (recording_spike.py's precedent): no bundle name, no
# screen key — a voice-over never touches the screen.
VOICE_INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>NSMicrophoneUsageDescription</key><string>The Frame Job recording probe records a short voice-over to check the recorder.</string>
</dict></plist>
"""


def build_voice_probe(sources):
    """`build_probe`'s line with `-sectcreate __TEXT __info_plist` added, into a
    directory of its own beside the tree's (or the mutant's), so the two
    binaries never share a cache."""
    here = probe_dir(sources) + "-voiceover"
    os.makedirs(here, exist_ok=True)
    binary = os.path.join(here, "recordingprobe")
    entry = os.path.join(here, "main.swift")
    plist = os.path.join(here, "Info.plist")
    for path, text in ((entry, PROBE_SOURCE), (plist, VOICE_INFO_PLIST)):
        if not os.path.exists(path) or open(path).read() != text:
            with open(path, "w") as f:
                f.write(text)
    if not os.path.isdir(sources):
        return None, f"{sources} is not a directory"
    files = sorted(
        os.path.join(sources, name)
        for name in os.listdir(sources)
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(
            sources=files + [entry], output=binary,
            link_args=["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker",
                       "__info_plist", "-Xlinker", plist],
            link_inputs=[plist])
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if built.reused:
        print(f"recording probe (voice-over): {binary} (up to date)")
    else:
        print(f"recording probe (voice-over): {binary} (built in {built.seconds:.1f} s)")
    return binary, None


def run_voice_probe(binary, request, timeout=120):
    """`run_probe` for the granted tier, which also names a SIGNAL — a probe
    killed by one is a scored failure, never a skip."""
    here = os.path.dirname(binary)
    req = os.path.join(here, "request-voiceover-granted.json")
    out = os.path.join(here, "answer-voiceover-granted.json")
    with open(req, "w") as f:
        json.dump(request, f, indent=1)
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run([binary, req, out], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, f"the probe did not answer within {timeout} s"
    if result.returncode < 0:
        return None, f"the probe was killed by signal {-result.returncode}"
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


def voice_stem_near(path, started):
    """True when `path`'s file name is the voice-over stem of a second within
    1 s of `started` — the name is the CALL's, the start the did-start's."""
    name = os.path.basename(path or "")
    return any(name.startswith(expected_voice_stem(started + d)) for d in (-1, 0, 1))


def voiceover_granted_rows(answer):
    """Every row of the granted tier over the probe's answer."""
    g1 = answer.get("G1") or {}
    o1 = g1.get("outcome") or {}
    s1 = o1.get("segments") or []
    check("G1: startVoiceOver completes nil and the recorder is .recording; a second start "
          "mid-recording is .busy",
          g1.get("start") == "nil" and g1.get("stateAfterStart") == "recording"
          and str(g1.get("busy", "")).startswith("busy: "), f"{g1.get('start')}, {g1.get('busy')}")
    check("G1: pause() after 1 s → .paused, pauseDidChangeNotification posted (voice-pause-unbranched)",
          g1.get("pause") == "ok" and g1.get("stateAfterPause") == "paused"
          and g1.get("pauseNotesAfterPause") == 1, f"{g1.get('pause')}, {g1.get('stateAfterPause')}")
    e = g1.get("elapsedPaused") or [None, None]
    check("G1: elapsed is equal twice 0.5 s apart while paused, and above 0",
          e[0] is not None and e[0] == e[1] and e[0] > 0, f"{e}")
    check("G1: resume() → heldSegmentCount 2, two different paths",
          g1.get("resume") == "ok" and g1.get("heldAfterResume") == 2
          and len(set(g1.get("heldPaths") or [])) == 2, f"{g1.get('resume')}, {g1.get('heldPaths')}")
    check("G1: one result, isVoiceOver, 2 segments, pauses 1, the stop completion answered once",
          g1.get("outcomes") == 1 and o1.get("kind") == "success" and o1.get("isVoiceOver") is True
          and len(s1) == 2 and o1.get("pauses") == 1 and g1.get("stops") == 1,
          f"{g1.get('outcomes')} outcomes, {o1.get('kind')} {o1.get('description') or ''}, "
          f"{len(s1)} segments, pauses {o1.get('pauses')}")
    check("G1: each segment an on-disk .m4a, no picture, 0.6–1.6 s",
          len(s1) == 2 and all(str(s.get("path", "")).endswith(".m4a") for s in s1)
          and (o1.get("onDisk") or []) == [True, True]
          and all(s.get("hasVideo") is False for s in s1)
          and all(0.6 <= (s.get("duration") or 0) / SEC <= 1.6 for s in s1),
          f"{[(s.get('path'), s.get('duration'), s.get('hasVideo')) for s in s1]}, onDisk {o1.get('onDisk')}")
    check("G1: each name is the stem of its own start (±1 s), and the two names differ",
          len(s1) == 2 and all(voice_stem_near(s.get("path"), s.get("startedAt") or 0) for s in s1)
          and s1[0].get("path") != s1[1].get("path"), f"{[(s.get('path'), s.get('startedAt')) for s in s1]}")
    check("G1: finishingDidBeginNotification posted once; the recorder ends idle with no session",
          g1.get("finishNotes") == 1 and g1.get("finalState") == "idle"
          and g1.get("voiceSessionAfter") is False,
          f"{g1.get('finishNotes')}, {g1.get('finalState')}, {g1.get('voiceSessionAfter')}")
    g2 = answer.get("G2") or {}
    o2 = g2.get("outcome") or {}
    check("G2: start → 1 s → pause → 0.5 s → stop while paused gives 1 segment with pauses 1",
          g2.get("outcomes") == 1 and o2.get("kind") == "success"
          and len(o2.get("segments") or []) == 1 and o2.get("pauses") == 1
          and g2.get("finalState") == "idle",
          f"{g2.get('outcomes')} outcomes, {o2.get('kind')} {o2.get('description') or ''}, "
          f"{len(o2.get('segments') or [])} segments, pauses {o2.get('pauses')}")
    g3 = answer.get("G3") or {}
    c3 = sorted(g3.get("mintedClips") or [], key=lambda c: c.get("start", 0))
    tracks = {t.get("id"): t.get("name") for t in g3.get("tracksAfter") or []}
    check("G3: G1's result through voiceOverPlacement gives two touching clips on \"Microphone\"",
          g3.get("ops") == VOICE_OPS and len(c3) == 2 and c3[0].get("start") == 0
          and c3[1].get("start") == c3[0].get("end")
          and all(tracks.get(c.get("track")) == "Microphone" for c in c3),
          g3.get("error") or f"{g3.get('ops')}, {c3}")


def voiceover_granted_rows_count():
    """The tier's row count, taken as `preroll_rows_count` takes section 13's."""
    global check
    real = check
    counted = [0]

    def counter(name, ok, detail=""):
        counted[0] += 1

    check = counter
    try:
        import io
        import contextlib
        with contextlib.redirect_stdout(io.StringIO()):
            voiceover_granted_rows({})
    finally:
        check = real
    return counted[0]


def section_voiceover_granted(binary, sources):
    print("\nSection 15g — #99 phase 1: a real voice-over, the microphone alone (granted tier; "
          "never the screen)")
    probe, error = build_voice_probe(sources)
    check("15g: the voice-over probe builds, its Info.plist the microphone's usage string alone",
          probe is not None, error or "")
    if probe is None:
        return
    folder = fresh_dir("voiceover-granted")
    answer, error = run_voice_probe(probe, {"mode": "voiceover-granted", "folder": folder})
    try:
        check("15g: the probe answers (a signal is a failure)",
              answer is not None and not answer.get("error"),
              error or (answer or {}).get("error", ""))
        if not answer or answer.get("error"):
            return
        print(f"  G0: Microphone status {answer.get('status')}; default input "
              f"{answer.get('device')!r} — facts, not asserted")
        if answer.get("skipped"):
            skip_rows(voiceover_granted_rows_count(), answer["skipped"])
            return
        voiceover_granted_rows(answer)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    check("15g: the voice-over files are deleted", not os.path.exists(folder), folder)


# --------------------------------------------------------------------------
# Section 17 — Include Frame Job windows (spec §11 recording.md).

EXCLUSION_CASES = [
    {"tag": "off", "include": False, "bundle": "com.example.own", "panel": 42,
     "expect": (["com.example.own"], []), "why": "today's rule: the application, whole"},
    {"tag": "off-no-bundle", "include": False, "bundle": None, "panel": 42,
     "expect": ([], []), "why": "a bare probe has no bundle: nothing"},
    {"tag": "on", "include": True, "bundle": "com.example.own", "panel": 42,
     "expect": ([], [42]), "why": "no application; the panel's own window"},
    {"tag": "on-no-panel", "include": True, "bundle": "com.example.own", "panel": None,
     "expect": ([], []), "why": "the tool's door: no window"},
]


def section_exclusion(binary, sources):
    print("\nSection 17 — Include Frame Job windows: the exclusion, the checkbox, its lock, "
          "and the two doors' reads")
    request = {"mode": "exclusion",
               "cases": [{k: c[k] for k in ("tag", "include", "bundle", "panel")}
                         for c in EXCLUSION_CASES]}
    answer, error = run_probe(binary, "exclusion", request)
    check("17: the probe answers", answer is not None and not answer.get("error"),
          error or (answer or {}).get("error", ""))
    if answer and not answer.get("error"):
        by = {row.get("tag"): row for row in answer.get("x1") or []}
        for case in EXCLUSION_CASES:
            got = by.get(case["tag"]) or {}
            pair = (got.get("bundleIDs"), got.get("windowIDs"))
            want = (case["expect"][0], case["expect"][1])
            check(f"X1: make(include {case['include']}, bundle {case['bundle']!r}, panel "
                  f"{case['panel']!r}) → bundleIDs {want[0]}, windowIDs {want[1]} — {case['why']}",
                  pair == want, f"got {pair}")
        x2 = answer.get("x2") or {}
        check("X2: the key is FrameJobRecordingIncludeFrameJobWindows, absent before the rows",
              x2.get("key") == "FrameJobRecordingIncludeFrameJobWindows" and x2.get("absent") is True,
              f"{x2.get('key')!r}, absent {x2.get('absent')!r}")
        check("X2: with the key absent the checkbox is off", x2.get("offWhenAbsent") is True,
              f"{x2.get('offWhenAbsent')!r}")
        check("X2: … and currentChoice().includeFrameJobWindows is false",
              x2.get("choiceOffWhenAbsent") is True, f"{x2.get('choiceOffWhenAbsent')!r}")
        check("X2: titled \"Include Frame Job windows\"", x2.get("title") == "Include Frame Job windows",
              f"{x2.get('title')!r}")
        check("X2: its target is the panel and its action controlChanged:",
              x2.get("targetIsPanel") is True and x2.get("action") == "controlChanged:",
              f"target panel {x2.get('targetIsPanel')!r}, action {x2.get('action')!r}")
        check("X2: it is in the panel's window", x2.get("inWindow") is True, f"{x2.get('inWindow')!r}")
        check("X2: on + controlChanged(checkbox) → the key reads true",
              x2.get("keyAfterOn") is True, f"{x2.get('keyAfterOn')!r}")
        check("X2: … and currentChoice().includeFrameJobWindows is true",
              x2.get("choiceAfterOn") is True, f"{x2.get('choiceAfterOn')!r}")
        check("X2: set off with no action, restoreChoices() → on again (read back from the key)",
              x2.get("restoredOn") is True, f"{x2.get('restoredOn')!r}")
        x3 = answer.get("x3") or {}
        check("X3: disabled during the countdown", x3.get("countdown") is False, f"{x3}")
        check("X3: disabled while recording", x3.get("recording") is False, f"{x3}")
        check("X3: enabled again when idle", x3.get("idle") is True, f"{x3}")
        check("17: the key is removed again after the rows", answer.get("removedAfter") is True,
              f"{answer.get('removedAfter')!r}")

    # X4 — structural, over the comment-stripped sources.
    picker = (read_code(sources, "RecorderPanelController+Picker.swift") or "").splitlines()
    body = "\n".join(function_body(picker, "func presentPicker(") or [])
    bundle_line = next((l for l in body.splitlines() if "excludedBundleIDs =" in l), "")
    window_line = next((l for l in body.splitlines() if "excludedWindowIDs =" in l), "")
    check("X4: presentPicker builds its exclusion from recordingExclusion(",
          "recordingExclusion(" in body, body[:200])
    check("X4: … sets excludedBundleIDs from its bundleIDs and excludedWindowIDs from its windowIDs",
          ".bundleIDs" in bundle_line and ".windowIDs" in window_line,
          f"{bundle_line.strip()!r} / {window_line.strip()!r}")
    check("X4: … and never names Bundle.main.bundleIdentifier itself",
          bool(body) and "Bundle.main.bundleIdentifier" not in body)
    recording = (read_code(sources, "RecorderPanelController+Recording.swift") or "").splitlines()
    start = function_body(recording, "func startRecording(") or []
    start_text = "\n".join(start)
    made = next((i for i, l in enumerate(start) if "recordingExclusion(" in l), None)
    lookup = next((i for i, l in enumerate(start) if "ScreenRecorder.shareableContent" in l), None)
    check("X4: startRecording passes excluding:", "excluding:" in start_text, start_text[:200])
    check("X4: … built from choice.includeFrameJobWindows ABOVE the shareableContent closure",
          made is not None and lookup is not None and made < lookup
          and "choice.includeFrameJobWindows" in start[made],
          f"exclusion at {made}, lookup at {lookup}")
    server = (read_code(sources, "AgentServer+Recording.swift") or "").splitlines()
    tool = function_body(server, "func recordScreen(") or []
    read_at = next((i for i, l in enumerate(tool) if '"include_framejob_windows"' in l), None)
    grant_at = next((i for i, l in enumerate(tool) if "screenRecordingGranted" in l), None)
    check("X4: recordScreen reads \"include_framejob_windows\" above screenRecordingGranted",
          read_at is not None and grant_at is not None and read_at < grant_at,
          f"read at {read_at}, grant at {grant_at}")
    name = None
    if read_at is not None:
        # #371: the `let` may wrap, its name on a line above the read — join the
        # statement from its `let` through the read's line before matching.
        start = next((i for i in range(read_at, -1, -1) if re.search(r"\blet\s+\w+\s*=", tool[i])),
                     read_at)
        m = re.search(r"let\s+(\w+)\s*=", " ".join(tool[start:read_at + 1]))
        name = m.group(1) if m else None
    tool_text = "\n".join(tool)

    def call(text, opener):
        at = text.find(opener)
        if at < 0:
            return ""
        depth = 0
        for i in range(at + len(opener) - 1, len(text)):
            depth += {"(": 1, ")": -1}.get(text[i], 0)
            if depth == 0:
                return text[at:i + 1]
        return text[at:]

    make = call(tool_text, "RecordingExclusion.make(")
    choice = call(tool_text, "RecordingChoice(")
    check("X4: … passes it to RecordingExclusion.make( with panelWindowID: nil",
          name is not None and re.search(rf"includeFrameJobWindows:\s*{name}\b", make) is not None
          and re.search(r"panelWindowID:\s*nil", make) is not None, f"{name!r}: {make!r}")
    check("X4: … and to RecordingChoice(",
          name is not None and re.search(rf"includeFrameJobWindows:\s*{name}\b", choice) is not None,
          f"{name!r}: {choice!r}")
    content = (read_code(sources, "ScreenRecorder+Content.swift") or "").splitlines()
    filt = "\n".join(function_body(content, "static func filter(") or [])
    display = filt.split("case .display", 1)[-1].split("case .window", 1)[0] if "case .display" in filt else ""
    check("X4: filter's display arm holds excludingApplications: and excludingWindows:",
          "excludingApplications:" in display and "excludingWindows:" in display, display[:200])




# --------------------------------------------------------------------------
# The mutants. Each is one string replaced in a COPY of the tree's
# `app/Sources` under `work/`, and the replacement must match exactly once,
# or the copy is not the mutant it claims to be (`phase9_chrome.py`'s
# `prepare_mutant`).

MUTANTS = {
    "excludes": (
        "RecordingSetup.swift",
        "        stream.excludesCurrentProcessAudio = true\n",
        "        stream.excludesCurrentProcessAudio = false\n",
        "excludesCurrentProcessAudio flipped to false — the timeline's own playback in the file"),
    "fps-override": (
        "ProjectDocument.swift",
        "            fps ?? (descriptor.hasVideo && descriptor.fps.double > 0 ? descriptor.fps : .thirty)\n",
        "            (descriptor.hasVideo && descriptor.fps.double > 0 ? descriptor.fps : .thirty)\n",
        "makeProject's fps: parameter ignored — the canvas takes the file's own rate (decision 3 undone)"),
    "resolve-first": (
        "RecordingLanding.swift",
        "        guard let document = open.first(where: { $0.recipeKey == key }) else {\n",
        "        guard let document = open.first else {\n",
        "resolve answers the FIRST open document, whatever key was asked for"),
    "welcome-action": (
        "WelcomeWindowController.swift",
        "            action: #selector(AppDelegate.showRecorderPanel(_:)))\n",
        "            action: #selector(AppDelegate.newProject(_:)))\n",
        "the welcome button's action pointed at newProject:"),
    "retitle": (
        "AppDelegate.swift",
        '            item.title = ScreenRecorder.shared.isRecording ? "Stop Recording" : "New Recording…"\n',
        "",
        "validateMenuItem's retitle line deleted — the item never reads Stop Recording"),
    "quit-guard": (
        "AppDelegate.swift",
        "        if ScreenRecorder.shared.isRecording {\n"
        "            RecorderPanelController.shared.revealControls()\n"
        "            return .terminateCancel\n"
        "        }\n",
        "",
        "applicationShouldTerminate's recording guard deleted — ⌘Q quits through a recording"),
    "no-import-count": (
        "ProjectDocument+Recording.swift",
        "            document.fileModificationDate = nil\n"
        "            document.countEditChange(.changeDone)\n",
        "",
        "untitled(around:)'s import count deleted — the microphone's edit is the only count, so one "
        "undo reads clean and ⌘W closes the recording's document without a prompt"),
    "mic-trim": (
        "RecordingLanding+Microphone.swift",
        "        let head = start < floor ? ReelTime.snapToFrame(floor - start, fps: fps) : 0\n",
        "        let head: Ticks = 0\n",
        "addMicrophoneClip's head always 0 — a start below the floor is placed AT the floor "
        "untrimmed, the voice late"),
    # Lane R's four, the R1 review's recorder fixes (section 3's driven rows).
    "busy-finishing": (
        "ScreenRecorder+Stop.swift",
        "        case .finishing:\n"
        "            if let completion { stopCompletions.append(completion) }\n"
        "        }\n",
        "        case .finishing:\n"
        "            completion?(.failure(RecorderError.busy))\n"
        "        }\n",
        "stop() while .finishing answers .busy again instead of joining (finding 1 undone)"),
    "no-oneshot": (
        "ScreenRecorder+Finishing.swift",
        "    var isSettling: Bool { session?.settling ?? false }\n",
        "    var isSettling: Bool { false }\n",
        "the settling guard removed — a callback during the probe settles again (finding 2 undone)"),
    "mic-fails-all": (
        "ScreenRecorder+Finishing.swift",
        "        if let failure = done.screenFailure { return conclude(done, .failure(failure)) }\n",
        "        if let failure = done.screenFailure { return conclude(done, .failure(failure)) }\n"
        "        if let failure = done.segments.compactMap({ $0.micFailure }).first {\n"
        "            return conclude(done, .failure(RecorderError.finishFailed(failure)))\n"
        "        }\n",
        "settle returns any segment's microphone failure BEFORE the movie probes (finding 0 undone; "
        "re-aimed at R2's segments, where micFailure moved from the session to the segment)"),
    "no-path": (
        "ScreenRecorder+Finishing.swift",
        "        if case .failure(let error) = outcome, let failure = error as? RecorderError {\n"
        "            delivered = .failure(Self.namingFiles(failure, done))\n"
        "        }\n",
        "",
        "the path clause not appended — a failure past beginFinishing names no file (finding 6 undone)"),
    # Lane P2's, the R1 review's chrome fixes (section 5's structural and driven rows).
    "canask-restored": (
        "RecorderPanelController+Grants.swift",
        "            requestScreen: { _ = CGRequestScreenCaptureAccess() },\n",
        "            requestScreen: { if Transcriber.canAsk { _ = CGRequestScreenCaptureAccess() } },\n",
        "the grant ask gated on canAsk again — Record under a scripted agent launch shows a refusal "
        "for a button nobody but a person pressed (fix 1 undone)"),
    "no-handle-check": (
        "RecorderPanelController+Landing.swift",
        "                guard document.project !== before else {\n"
        "                    failedToLand(\n"
        "                        result,\n"
        "                        ReelCoreError(\n"
        "                            message: \"the project refused the placement and nothing was added\"))\n"
        "                    return\n"
        "                }\n",
        "",
        "land() no longer checks the document's handle — a refused commit is reported as added "
        "(fix 3 undone)"),
    "sync-while-recording": (
        "RecorderPanelController+Rows.swift",
        "        guard phase == .idle else { return }\n",
        "",
        "rebuildDestinations runs during a recording — Record Into follows the front document "
        "away from the captured choice (fix 4 undone)"),
    "no-constrain": (
        "RecorderPanelController+Showing.swift",
        "        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first\n"
        "        frame = window.constrainFrameRect(frame, to: screen)\n",
        "",
        "the grown card is not constrained to its screen — the countdown pushes a bottom-parked "
        "panel under the Dock (fix 5 undone)"),
    "show-while-hidden": (
        "RecorderPanelController+Showing.swift",
        "        guard !hiddenForRecording else {\n"
        "            NSSound.beep()\n"
        "            return\n"
        "        }\n",
        "",
        "show() un-hides the panel into a picked-window recording (fix 7 undone)"),
    "window-row-unguarded": (
        "RecorderPanelController+Recording.swift",
        "        if sourcePopup.selectedItem?.tag == Self.windowTag, pickedFilter == nil {\n"
        "            setNote(Self.chooseWindowSentence)\n"
        "            return\n"
        "        }\n",
        "",
        "Record over the Window… row with no filter falls through to the main display "
        "(fix 8 undone)"),
    "arm-no-generation": (
        "RecorderPanelController+Recording.swift",
        "        guard phase == .starting, generation == startGeneration, !launched else { return }\n",
        "        guard phase == .starting, !launched else { return }\n",
        "the arm ceiling ignores the generation — a stale attempt's ceiling fails the current one "
        "(fix 2 undone)"),
    "route-to-show": (
        "AppDelegate+Recording.swift",
        "                ScreenRecorder.shared.stop()\n",
        "                panel.show()\n",
        "New Recording… shows the panel instead of stopping a tool's recording (fix 12 undone)"),
    # Road map 3, R2 — one per rule (sections 3o–3t, 4b, 5p–5u, 9).
    "segment-stacked": (
        "RecordingLanding+Placing.swift",
        "            at = landed.end\n",
        "",
        "a later segment placed at the playhead, not the previous clip's end — the sequence stacks"),
    "mic-floor-dropped": (
        "RecordingLanding+Microphone.swift",
        "            floor = placed.end\n",
        "",
        "the microphone floor dropped — a later voice is placed below the previous voice's end"),
    "menu-static": (
        "RecorderStatusItem.swift",
        "        rebuildMenu(paused: paused)\n",
        "",
        "the status item's menu not rebuilt when paused flips — Pause Recording stays while paused"),
    "hide-picked-only": (
        "RecorderPanelController+Recording.swift",
        "        guard Self.hidesForRecording(currentChoice().source) else { return }\n",
        "        guard currentChoice().source == .picked else { return }\n",
        "the panel's hide narrowed back to a picked window (decision 7 undone)"),
    "reveal-always": (
        "RecorderPanelController+Landing.swift",
        "        if showWhenLanded, !noteLabel.stringValue.isEmpty { window?.orderFront(nil) }\n",
        "        if showWhenLanded { window?.orderFront(nil) }\n",
        "the reveal made unconditional — the panel comes back after every clean landing"),
    "elapsed-through-pause": (
        "ScreenRecorder.swift",
        "            total += max(0, (segment.stoppedAt ?? now).timeIntervalSince(start))\n",
        "            total += max(0, now.timeIntervalSince(start))\n",
        "elapsed counts every segment to now — a paused recording's clock keeps running"),
    "resume-first-offset": (
        "ScreenRecorder+Finishing.swift",
        "    ) -> RecordingSegment {\n"
        "        let segment = done.segments[index]\n",
        "    ) -> RecordingSegment {\n"
        "        let segment = done.segments[0]\n",
        "every segment's offset and stamps read off the FIRST segment"),
    "resume-no-segment": (
        "ScreenRecorder+Pause.swift",
        "        session?.segments.append(segment)\n",
        "",
        "resume() mints no segment — the new output has nothing to report on"),
    "pause-no-mic-stop": (
        "ScreenRecorder+Pause.swift",
        "        current.micOutput?.stopRecording()\n"
        "        state = .paused\n",
        "        state = .paused\n",
        "pause() leaves the microphone's writer running through the pause"),
    # The grants a press checks (spec §11 recording; section 10's rows).
    "ask-every-press": (
        "RecordingSetup.swift",
        "        if asked { return .openPane }\n",
        "        if asked { return .ask }\n",
        "screenStep ignores the asked flag — every press puts up a prompt that never comes again"),
    "open-first-press": (
        "RecordingSetup.swift",
        "        if !launchedByLaunchd { return .ask }\n"
        "        if asked { return .openPane }\n"
        "        return .ask\n",
        "        return .openPane\n",
        "screenStep always opens the pane — the first press never asks, so the app is never listed"),
    "asked-forgotten": (
        "RecorderPanelController+Grants.swift",
        "            if owned { doors.rememberScreenAsked() }\n",
        "",
        "the ask is never remembered — every press asks and the pane never opens"),
    "shell-remembers": (
        "RecorderPanelController+Grants.swift",
        "            if owned { doors.rememberScreenAsked() }\n",
        "            doors.rememberScreenAsked()\n",
        "a shell-launched press writes the flag — a later Finder launch would never be asked"),
    "shell-opens": (
        "RecordingSetup.swift",
        "        if !launchedByLaunchd { return .ask }\n",
        "",
        "screenStep's launchd arm deleted — a shell-launched press that finds the flag opens the pane"),
    "mic-denied-asks": (
        "RecordingSetup.swift",
        "        case .denied, .restricted: return .openPane\n",
        "        case .denied: return .ask\n"
        "        case .restricted: return .openPane\n",
        "a denied microphone asks again — a prompt the system will never show"),
    "panes-swapped": (
        "RecordingSetup.swift",
        "        string: \"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture\")\n"
        "\n"
        "    /// System Settings ▸ Privacy & Security ▸ Microphone.\n"
        "    static let microphonePaneURL = URL(\n"
        "        string: \"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone\")\n",
        "        string: \"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone\")\n"
        "\n"
        "    /// System Settings ▸ Privacy & Security ▸ Microphone.\n"
        "    static let microphonePaneURL = URL(\n"
        "        string: \"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture\")\n",
        "the two pane anchors swapped — each press opens the other grant's pane"),
    "opened-claimed": (
        "RecorderPanelController+Grants.swift",
        "            let opened = RecordingGrant.screenRecordingPaneURL.map(doors.openSettings) ?? false\n",
        "            _ = RecordingGrant.screenRecordingPaneURL.map(doors.openSettings)\n"
        "            let opened = true\n",
        "the opener's answer ignored — the note claims System Settings is open when it did not open"),
    # Issue batch B17 (#97, #98 a, b) — sections 11 and 12, and 3o.
    "unreadable-fails-all": (
        "ScreenRecorder+Finishing.swift",
        "                let left = Self.leftOut(done, at: index, error)\n"
        "                self.probeLeftOutMicrophone(done, at: index, left: left, position: landed.count) {\n"
        "                    [weak self] left in\n"
        "                    self?.probeSegment(done, at: index + 1, landed: landed, skipped: skipped + [left])\n"
        "                }\n",
        "                self.conclude(done, .failure(Self.unreadable(done, at: index, error)))\n",
        "an unreadable segment fails the whole recording again (#97 undone — the code before B17; "
        "re-aimed by B55 at the arm that now probes the left-out microphone)"),
    "no-unreadable-note": (
        "RecordingResult.swift",
        "        unreadable.isEmpty ? nil : unreadable.map(\\.sentence).joined(separator: \" \")\n",
        "        nil\n",
        "unreadableNote always nil — a left-out segment is named at neither door"),
    "boundary-promoted": (
        "ScreenRecorder+Delegates.swift",
        "                if self.microphoneProblem == nil, current.segments[index].stoppedAt == nil {\n",
        "                if self.microphoneProblem == nil {\n",
        "a segment-boundary microphone failure promoted to the session's microphoneProblem again "
        "(the code before B17)"),
    "pause-item-untitled": (
        "AppDelegate.swift",
        "            item.title = RecorderStatusItem.menuTitles(paused: ScreenRecorder.shared.isPaused)[0]\n",
        "",
        "File ▸ Pause Recording's validator arm never retitles — it reads Pause Recording while paused"),
    "pause-item-enabled": (
        "AppDelegate.swift",
        "            return ScreenRecorder.shared.state == .recording || ScreenRecorder.shared.state == .paused\n",
        "            return true\n",
        "File ▸ Pause Recording enabled with no recording running"),
    "pause-route-recorder": (
        "AppDelegate+Recording.swift",
        "        case .recording:\n"
        "            panel.pauseRecording()\n"
        "        case .paused:\n"
        "            panel.resumeRecording()\n",
        "",
        "File ▸ Pause Recording pauses the panel's own recording behind the panel's back"),
    "status-variable-length": (
        "RecorderStatusItem.swift",
        "        let item = NSStatusBar.system.statusItem(withLength: Self.itemLength)\n",
        "        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)\n",
        "the status item back at variableLength — it resizes as the time and the mark change "
        "(the code before B17)"),
    "width-short-label": (
        "RecorderStatusItem.swift",
        "    static let widestElapsed: TimeInterval = 35_999\n",
        "    static let widestElapsed: TimeInterval = 0\n",
        "the item sized for 0:00 — a longer label is wider than the item"),
    # Issue batch B27 (#98 c, #181 items 1 and 4) — section 13, 3r/3r2, F6/F7.
    "preroll-gated": (
        "ScreenRecorder+Microphone.swift",
        "        } else if state == .idle, let prepared = preparedMicrophone, prepared.session.isRunning {\n"
        "            connection = prepared.output.connection(with: .audio)\n",
        "",
        "publishMicrophoneLevel's idle arm gone — the .recording gate restored, the countdown's bar dead "
        "(the code before B27)"),
    "preroll-no-tick": (
        "RecorderPanelController+Recording.swift",
        "        recorder.prepareMicrophone(currentChoice().microphone)\n"
        "        armTick()\n",
        "        recorder.prepareMicrophone(currentChoice().microphone)\n",
        "beginCountdown no longer arms the tick — nothing polls the prepared session"),
    "preroll-no-silence": (
        "ScreenRecorder+Microphone.swift",
        "        if state == .idle { meter.publish(.silent, from: ObjectIdentifier(self)) }\n",
        "",
        "discardPreparedMicrophone publishes no silence — the bar holds its level after a cancel"),
    "closed-fail-fails-all": (
        "ScreenRecorder+Delegates.swift",
        "            if self.session?.segments[index].stoppedAt != nil {\n"
        "                // A CLOSED segment's writer gave up (#181): that segment's\n"
        "                // alone — the walker leaves it out — never the recording's.\n"
        "                if self.session?.segments[index].outputFailure == nil {\n"
        "                    self.session?.segments[index].outputFailure =\n"
        "                        .finishFailed(\"The recording failed: \" + error.localizedDescription)\n"
        "                }\n"
        "                self.outputEnded(asked: true)\n"
        "                return\n"
        "            }\n",
        "",
        "a closed segment's did-fail fails the whole recording again (the code before B27)"),
    "closed-fail-probed": (
        "ScreenRecorder+Finishing.swift",
        "        if let failure = done.segments[index].outputFailure {\n"
        "            let left = Self.leftOut(done, at: index, reason: failure)\n"
        "            return probeLeftOutMicrophone(done, at: index, left: left, position: landed.count) {\n"
        "                [weak self] left in\n"
        "                self?.probeSegment(done, at: index + 1, landed: landed, skipped: skipped + [left])\n"
        "            }\n"
        "        }\n",
        "",
        "the walker probes a segment whose writer failed after it closed — a movie that reads lands "
        "(re-aimed by B55 at the arm that now probes the left-out microphone)"),
    "pause-no-post": (
        "ScreenRecorder+Pause.swift",
        "        meter.publish(.silent, from: ObjectIdentifier(self))\n"
        "        NotificationCenter.default.post(name: Self.pauseDidChangeNotification, object: self)\n",
        "        meter.publish(.silent, from: ObjectIdentifier(self))\n",
        "pause() posts no pauseDidChangeNotification — a tool's item flips a second late"),
    "chrome-no-observer": (
        "AgentServer+RecordingChrome.swift",
        "        observer = NotificationCenter.default.addObserver(\n"
        "            forName: ScreenRecorder.pauseDidChangeNotification, object: recorder, queue: nil\n"
        "        ) { [weak self] _ in self?.tick() }\n",
        "",
        "the tool's chrome observes nothing — its item flips only at the 1 Hz tick (the code before B27)"),
    # Include Frame Job windows (spec §11 recording.md) — section 17.
    "exclusion-ignores-include": (
        "ScreenRecorder+Content.swift",
        "        if includeFrameJobWindows {\n",
        "        if false {\n",
        "RecordingExclusion.make ignores the box — Frame Job is always excluded (the code before)"),
    "choice-drops-include": (
        "RecorderPanelController+Rows.swift",
        "        choice.includeFrameJobWindows = includeFrameJobCheckbox.state == .on\n",
        "",
        "currentChoice() never reads the checkbox — the panel's recording excludes Frame Job whatever it says"),
    "persist-drops-include": (
        "RecorderPanelController+Rows.swift",
        "        defaults.set(\n"
        "            includeFrameJobCheckbox.state == .on, forKey: Self.includeFrameJobWindowsKey)\n",
        "",
        "persistChoices never writes the key — the box forgets its setting at the next show"),
    "lock-drops-include": (
        "RecorderPanelController+VoiceOver.swift",
        "            systemAudioSwitch, showClicksSwitch, sizePopup, includeFrameJobCheckbox,\n",
        "            systemAudioSwitch, showClicksSwitch, sizePopup,\n",
        "the checkbox stays live while a recording is in flight"),
    "tool-ignores-include": (
        "AgentServer+Recording.swift",
        "                    includeFrameJobWindows: includeFrameJob,\n",
        "                    includeFrameJobWindows: false,\n",
        "record_screen reads include_framejob_windows and excludes Frame Job anyway"),
    # Issue batch B42 (#193 items 1 and 2) — F8, F9, F10.
    "finish-no-post": (
        "ScreenRecorder+Finishing.swift",
        "        NotificationCenter.default.post(name: Self.finishingDidBeginNotification, object: self)\n",
        "",
        "beginFinishing posts no finishingDidBeginNotification — File ▸ Stop leaves a tool's item live"),
    "chrome-no-freeze": (
        "AgentServer+RecordingChrome.swift",
        "        finishObserver = NotificationCenter.default.addObserver(\n"
        "            forName: ScreenRecorder.finishingDidBeginNotification, object: recorder, queue: nil\n"
        "        ) { [weak self] _ in self?.freeze() }\n",
        "",
        "the tool's chrome does not freeze at a finish it did not start (the code before B42)"),
    "countdown-keeps-resume-problem": (
        "RecorderPanelController+Recording.swift",
        "        countdownTimer?.invalidate()\n        resumeProblem = nil\n",
        "        countdownTimer?.invalidate()\n",
        "beginCountdown keeps a stale resumeProblem (the code before B42)"),
    # Issue batch B49 (#100, spec §11 SH-4) — 6a's samples and layout.
    "sticker-pill-size": (
        "Controls.swift",
        "        return NSSize(width: ceil(textWidth) + 32, height: Self.bodyHeight)\n",
        "        return NSSize(width: ceil(textWidth) + 32 + 6, height: Self.bodyHeight + 6)\n",
        "StickerButton's intrinsic size takes the pill's 6 pt margins back (the code before B49)"),
    "sticker-round": (
        "Controls.swift",
        "            roundedRect: body, xRadius: DS.buttonRadius, yRadius: DS.buttonRadius)\n",
        "            roundedRect: body, xRadius: body.height / 2, yRadius: body.height / 2)\n",
        "StickerButton's block is drawn with the pill's radius, half its height"),
    # Issue batch B55 (#181 item 2) — section 14, U1, U6, U7 and 3r.
    "leftout-mic-unprobed": (
        "ScreenRecorder+Finishing.swift",
        "        guard let micURL = segment.micURL, segment.micFailure == nil,\n",
        "        guard let micURL = segment.micURL, segment.micFailure == nil, position < 0,\n",
        "a left-out segment's microphone is never probed — both left-out arms pass it through "
        "(the code before B55)"),
    "leftout-no-gap": (
        "RecordingLanding+LeftOut.swift",
        "        return max(0, SilenceDetector.snapDownToFrame(voice.duration, fps: fps))\n",
        "        return max(0, SilenceDetector.snapDownToFrame(0, fps: fps))\n",
        "slotLength answers 0 — the left-out voice takes no time on the picture track"),
    "leftout-voice-dropped": (
        "RecordingResult.swift",
        "            unreadable.indices.filter { unreadable[$0].position == k && unreadable[$0].micDescriptor != nil }\n",
        "            unreadable.indices.filter { _ in false }\n",
        "stretches omits every left-out voice — a voice that read is never landed"),
    "mics-unnamed": (
        "ScreenRecorder+Finishing.swift",
        "        guard !movies.isEmpty || !mics.isEmpty else { return error }\n",
        "        guard !movies.isEmpty else { return error }\n",
        "namingFiles names nothing when no movie is on disk, readable microphone files included "
        "(the code before B55)"),
    # Issue batch B61 (#213) — section 14's X8.
    "unplaced-voice-unnoted": (
        "RecordingLanding+Remainder.swift",
        "                if let mic = segment.micDescriptor { notes.append(unplacedNote(mic.path, behind: path)) }\n",
        "                _ = segment\n",
        "a segment's voice lands as media with no clip and no note when clip 1 is missing"),
    "unplaced-leftout-unnoted": (
        "RecordingLanding+Remainder.swift",
        "                if let mic = left.micDescriptor { notes.append(unplacedNote(mic.path, behind: path)) }\n",
        "                _ = left\n",
        "a left-out segment's voice lands as media with no clip and no note when clip 1 is missing"),
    # #99 phase 1, the voice-over — section 15's V1, V3, V5 and 15g's G1.
    "voice-front-track": (
        "RecordingLanding.swift",
        "        if result.isVoiceOver { return try voiceOverPlacement(result, in: document, place: place) }\n",
        "",
        "placement no longer forwards a voice-over — its files take the picture rule (the front track)"),
    "voice-held-ignored": (
        "ScreenRecorder+VoiceOver.swift",
        "        while manager.fileExists(atPath: candidate.path) || held.contains(candidate.path) {\n",
        "        while manager.fileExists(atPath: candidate.path) {\n",
        "nextVoiceOverURL ignores the held names — a resume inside the second reuses a file name"),
    "voice-track-always": (
        "RecordingLanding+VoiceOver.swift",
        "            if placed.contains(where: { $0.clip != nil }) {\n",
        "            if !placed.isEmpty {\n",
        "the Microphone track is kept with no clip on it"),
    "voice-pause-unbranched": (
        "ScreenRecorder+Pause.swift",
        "        if voiceSession != nil { return try pauseVoiceOver() }\n",
        "",
        "pause() no longer forwards a voice-over — it reads the screen session and refuses"),
    # #99 phase 2 (issue batch B66) — section 15's V9, V10 and section 16.
    "voice-own-stop-asked": (
        "ScreenRecorder+VoiceOverFinishing.swift",
        "        let unasked = current.segments[index].stoppedAt.map { arrived < $0 } ?? true\n",
        "        let unasked = current.segments[index].stoppedAt == nil\n",
        "a did-finish is unasked only with no stoppedAt — one that arrived before a Pause or Stop "
        "press reached main is taken as asked (the code before B66)"),
    "voice-cap-trial-always": (
        "RecordingLanding+VoiceOver.swift",
        "        let canLand = shortNotes.contains { $0 == nil }\n",
        "        let canLand = true\n",
        "the Microphone track is tried even when no file can make a clip (the code before B66)"),
    "voice-panel-hides": (
        "RecorderPanelController+VoiceOver.swift",
        "    static func hidesForRecording(_ source: RecordingSource) -> Bool { source != .voiceOver && source != .camera }\n",
        "    static func hidesForRecording(_ source: RecordingSource) -> Bool { true }\n",
        "the panel orders out for a voice-over too"),
    "voice-screen-grant-read": (
        "RecorderPanelController+Recording.swift",
        "        if voiceOverSelected { return beginVoiceOverIfGranted() }\n",
        "",
        "Record with Microphone Only goes through the screen's press — the Screen Recording grant read"),
    "voice-row-live": (
        "RecorderPanelController+VoiceOver.swift",
        "        let screenOnly = idle && !voiceOverSelected\n",
        "        let screenOnly = idle\n",
        "System Audio, Show Clicks and Size stay live with Microphone Only chosen"),
    "voice-strangers-admitted": (
        "AgentServer+RecordingArguments.swift",
        "        let strangers = Self.voiceOverScreenOnlyArguments.filter { a[$0] != nil && !(a[$0] is NSNull) }\n",
        "        let strangers = [String]()\n",
        "record_screen takes the screen-only arguments with source voice_over and ignores them"),
}


def prepare_mutant(name):
    """A fresh copy of the tree's `app/Sources` with one line changed. The
    tree itself is never touched."""
    file_name, before, after, what = MUTANTS[name]
    target = os.path.join(PROBE, f"mutant-{name}", "Sources")
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    for entry in os.listdir(TREE_SOURCES):
        if entry.endswith(".swift"):
            shutil.copy2(os.path.join(TREE_SOURCES, entry), os.path.join(target, entry))
    path = os.path.join(target, file_name)
    with open(path) as f:
        text = f.read()
    if text.count(before) != 1:
        print(f"mutant {name}: the control could not be performed — the text to replace "
              f"occurs {text.count(before)} times in {file_name}, not once — the tree has "
              f"moved and the mutant needs re-aiming", file=sys.stderr, flush=True)
        sys.exit(2)
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    print(f"  mutant {name}: {what}\n")
    return target


SECTIONS = [section_files, section_configuration, section_state, section_unreadable, section_landing,
            section_segments, section_chrome, section_chrome_pause, section_file_pause,
            section_welcome, section_catalog, section_host, section_granted, section_grants,
            section_preroll, section_leftout, section_voiceover, section_voiceover_granted,
            section_voiceover_doors, section_exclusion]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--sources", default=os.environ.get("RC_APP_SOURCES", TREE_SOURCES),
                        help="an app/Sources directory to compile the probe against — a "
                             "mutant copy under work/ for the gate (default: the tree's, "
                             "or $RC_APP_SOURCES, the spelling remaining_probe.py shares)")
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="prepare a named mutant copy of the tree's app/Sources and "
                             "compile against it (overrides --sources)")
    parser.add_argument("--only",
                        help="a comma-separated subset of sections to run, by the name after "
                             "`section_` (files, configuration, state, unreadable, landing, "
                             "segments, chrome, chrome_pause, file_pause, welcome, catalog, host, "
                             "granted, grants, preroll, leftout, voiceover, voiceover_granted, "
                             "voiceover_doors, exclusion) — for "
                             "iterating on "
                             "one; the full run is what the counts in the docstring are")
    args = parser.parse_args()
    sources = os.path.abspath(args.sources)
    sections = SECTIONS
    if args.only:
        wanted = {name.strip() for name in args.only.split(",")}
        sections = [s for s in SECTIONS if s.__name__.removeprefix("section_") in wanted]
        unknown = wanted - {s.__name__.removeprefix("section_") for s in SECTIONS}
        if unknown:
            sys.exit(f"--only names no section: {sorted(unknown)}")

    print("recording — road map 3's app half (R1, and R2's pause and resume): files, configurations, "
          "the machine over a faked session, the landing of a sequence, the chrome, the welcome "
          "cross-build, the catalog, and the granted tier\n")
    if args.mutant:
        sources = prepare_mutant(args.mutant)
    if sources != os.path.realpath(TREE_SOURCES):
        print(f"  (compiling against {sources}, not the tree)\n")
    binary, error = build_probe(sources)
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if args.mutant and binary is None:
        # Rule R (issue batch B13): a probe that did not build performs no
        # control, and is never read as a caught mutant.
        print(f"\n{passed}/{passed + failed} checks passed")
        print(f"mutant {args.mutant}: the control could not be performed — the probe did not "
              f"build")
        return 2
    if binary is not None:
        for section in sections:
            section(binary, sources)

    tail = ""
    if skips:
        tail = " (" + str(skipped) + " skipped by name — " \
            + "; ".join(f"{n}: {why}" for n, why in skips) + ")"
    print(f"\n{passed}/{passed + failed} checks passed{tail}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
