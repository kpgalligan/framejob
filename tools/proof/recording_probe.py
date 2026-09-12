#!/usr/bin/env python3
"""Road map 3, R1 — the recorder's APP half, measured (sections 1–8).

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
`harness/build.sh`'s own swiftc line, cached on modification times, a
request JSON in and an answer JSON out dispatched on `mode`, `--sources` /
`RC_APP_SOURCES` to point it at a mutant copy, and a build failure scored
as a FAILURE rather than an exit so a rotted instrument cannot take the
rest of the score down with it. The probe NEVER presents a picker, starts a
stream, or puts up the status item — a bare Mach-O has no bundle, and
`Transcriber.swift` records what a usage-string prompt does to one. It DOES
call `record(_:)` in one place (section 5k, the R1 review's window-row
guard), because the fix under test is that a press over the "Window…" row
with no filter refuses at the door and reaches no capture — the tree's path
returns before any grant is read; only the `window-row-unguarded` mutant
falls through, and on the shell-launched host R0 q1 measured (grant present)
it stops at a countdown numeral, not a system prompt. The two grants' current
readings are printed as HOST FACTS and never asserted (section 8).

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
`publishMicrophoneLevel()` while idle publishes NOTHING (observed through
`meter.addObserver`, which fires once on subscription and must not fire
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
a shell-launched Reelcut runs under the terminal's grants, and the pane
sentence alone sent a person to grant the wrong application); and **the
machine past `start`, driven through a faked `Session`** in a second
request: the review measured that `SCContentFilter()` and
`SCStream(filter:configuration:delegate:)` CONSTRUCT without a grant and
only `startCapture` needs one, so the probe builds a `Session` from those,
a PNG at the movie URL (a "movie" `MediaImporter.probe` answers with a
descriptor) and a bare `AVCaptureAudioFileOutput` whose `stopRecording`
delivers nothing — which HOLDS the finishing wait until the probe drives
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

Section 4 (`landing`) is the LANDING — `RecordingLanding.placement`,
`microphonePlacement` through `ProjectDocument.untitled(around:)`, and
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

Section 5 (`chrome`) is the CHROME's structure, lane C's 64 scratch rows
made tracked: a probe compiled over `app/Sources` that instantiates
`AppDelegate()` and runs `applicationWillFinishLaunching` (`phase6_chrome.py`'s
menu instrument), with the six `ReelcutRecording…` keys pinned in the
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
cannot show: `+Recording.swift` gates no grant ask on `canAsk` and still asks
on a press (fix 1), the countdown and the tick are added in `.common`
run-loop modes (fix 6), `microphoneAnswered` guards visibility and re-enables
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

Section 6 (`welcome`) is the welcome window's CROSS-BUILD — `phase5_chrome.py`'s
pattern: the tree one commit before the button existed, `git archive`d into
`work/recordingprobe/before/` and compiled with the same swiftc line, the
same staticlib and (first) THIS tree's `harness/main.swift` under
`-D HARNESS_REFERENCE_BUILD`, falling back to the reference commit's own
harness and SAYING so. The reference is found by a pickaxe on the button's
title (`git log -S"New Recording" -- app/Sources/WelcomeWindowController.swift`,
the LAST hash + `^`; HEAD while the change is uncommitted), because the
file's adding commit is the initial commit and `--diff-filter=A` would name
the wrong tree. Both harnesses render `welcome` in both appearances; the
score is the shape (1440×1200, four channels), a determinism pair (two
renders of this tree, byte-identical), and then `extent(diff)` equal to the
INK of the three-button row — the row itself is Σ over the three titles of
(⌈textWidth⌉ + 38) + 2 × 12 spacing wide, 34 tall and centred at x = 360
(`StickerButton.intrinsicContentSize` in `Controls.swift`, the stack's
spacing in `WelcomeWindowController.swift`, the widths measured by the
probe's own `welcome` mode with the vendored fonts registered), and the ink
sits inside it by `StickerButton.draw`'s margins: 2 pt top and left less
the 1.5 pt stroke's 0.75 overhang, the 2 pt sticker shadow bottom and
right — so the ink is 30.75 pt tall and the row's y is DERIVED from the
diff's bottom edge and compared with the laid-out frame. Nothing outside
the row may change (a third button moves the other two, and the old row is
inside the new one), the changed-pixel clusters are PRINTED and never
counted as one, and a scored row asks that the reference was compiled with
this tree's own harness — the fallback would mean the harness names a type
the older tree lacks outside the reference guard. Section 6 always renders
through the TREE's harness (`build.sh` hard-codes `app/Sources`), whatever
`--sources` says; the mutant that turns the button's action is caught by
section 5's structural read, which is what a pixel cannot see.

Section 7 (`catalog`) is the toll's gate from the inside:
`AgentServer.shared.catalogJSON()` — the very string the startup parity
check reads — parsed for its 75 names, the 55 core ops (`ReelOp.coreNames()`)
plus the twenty app-state tools; the LAST eleven in the order the old file
had them (`import_media`, `import_captions`, `consolidate_media`,
`add_media`, `relink_media`, `remove_media`, `transcribe`,
`export_captions`, `render_frame`, `export` — `df6b916^`'s order — then
`record_screen`); `scope` on every op tool's schema and on none of the
twenty, `record_screen`'s among them; and `record_screen`'s declared
argument names.

Section 8 (`host`): CGPreflightScreenCaptureAccess(), the microphone's
status word, the console lock (`CGSessionCopyCurrentDictionary()`'s
`CGSSessionScreenIsLocked`) and the active display count — PRINTED, never
asserted, so a reader of a probe log knows which tiers of
`recording_proof.py` could have run on that machine.

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
                   (ScreenRecorder.swift) — 617/620, measured against a
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
                   (RecorderPanelController.swift) — 661/662: 5h's
                   fitWindowToContent read — NSWindow.setFrame re-seats an
                   off-screen titled panel on this multi-display host, so
                   the source read is the kill and not the geometry (fix 5).
  show-while-hidden  show() un-hides the panel into a picked recording
                   (RecorderPanelController.swift) — 661/662: 5j (fix 7).
  window-row-unguarded  Record over the Window… row with no filter falls
                   through (RecorderPanelController+Recording.swift) —
                   660/662: 5k's two rows (fix 8).
  arm-no-generation  the arm ceiling ignores the generation
                   (RecorderPanelController+Recording.swift) — 661/662:
                   5m's stale-ceiling row (fix 2).
  route-to-show    New Recording… shows the panel instead of stopping a
                   tool's recording (AppDelegate+Recording.swift) —
                   660/662: 5h's routing read and 5o (fix 12).

**The tree's one failing row is 6b's "one program" row, and it is the
harness's to fix, not this script's**: `tools/proof/harness/main.swift`
pins the six recorder keys as `RecorderPanelController.<key>` in
`pinDefaults`, OUTSIDE the `HARNESS_REFERENCE_BUILD` guard, so a reference
tree from before that type existed cannot compile the current instrument
and `build_reference` falls back to the reference commit's own
`main.swift` (the same fallback `phase5_chrome.py`'s reference build now
takes, silently, against its pre-meter tree). Six string literals in the
pin map — every other key there is one — would make both cross-builds one
program again and turn this row green.

    python3 tools/proof/recording_probe.py                 # the tree
    python3 tools/proof/recording_probe.py --mutant excludes
    python3 tools/proof/recording_probe.py --sources <dir> # any copy
    RC_APP_SOURCES=<dir> python3 tools/proof/recording_probe.py
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
STATICLIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
BRIDGING = os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
WELCOME_FILE = "app/Sources/WelcomeWindowController.swift"

passed = 0
failed = 0


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
    `+Recording.swift` names `canAsk` to say it no longer gates a thing)
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
    case .startFailed: return "startFailed"
    case .finishFailed: return "finishFailed"
    case .startTimedOut: return "startTimedOut"
    case .timedOut: return "timedOut"
    case .microphoneDevice: return "microphoneDevice"
    case .filesKept(let inner, _, _): return "filesKept(\(caseName(inner)))"
    }
}

/// One outcome — what `onFinish` or a stop completion received — as JSON.
func spell(_ outcome: Result<RecordingResult, Error>) -> [String: Any] {
    switch outcome {
    case .success(let result):
        return [
            "kind": "success", "path": result.descriptor.path,
            "micDescriptor": result.micDescriptor != nil,
            "micProblem": result.micProblem as Any, "stoppedBy": "\(result.stoppedBy)",
        ]
    case .failure(let error):
        var spelled: [String: Any] = ["kind": "failure", "description": error.localizedDescription]
        if let recorder = error as? RecorderError { spelled["case"] = caseName(recorder) }
        return spelled
    }
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

/// A session the machine can be driven through with no stream started —
/// the R1 review measured that `SCContentFilter()` and
/// `SCStream(filter:configuration:delegate:)` CONSTRUCT without a grant and
/// only `startCapture` needs one; `SCRecordingOutput(configuration:delegate:)`
/// constructs beside them. The microphone output, when asked for, is a bare
/// `AVCaptureAudioFileOutput` with no session: `stopRecording` on it
/// delivers nothing, so the finishing wait HOLDS until this probe drives
/// the did-finish itself, which is what makes every row below deterministic
/// rather than a race against the writer. The delegate methods are called
/// directly, as the frameworks would call them (each hops to main itself).
final class Fake {
    let recorder = ScreenRecorder()
    let stream: SCStream
    let output: SCRecordingOutput
    let micOutput: AVCaptureAudioFileOutput?
    let movie: URL
    let mic: URL?
    var finishes: [[String: Any]] = []

    init(movie: URL, mic: URL?, state: ScreenRecorder.State) {
        self.movie = movie
        self.mic = mic
        let configs = RecordingConfiguration.make(
            RecordingChoice(), displayPointSize: CGSize(width: 16, height: 16), scale: 1,
            outputURL: movie)
        stream = SCStream(
            filter: SCContentFilter(), configuration: configs.stream, delegate: recorder)
        output = SCRecordingOutput(configuration: configs.output, delegate: recorder)
        micOutput = mic == nil ? nil : AVCaptureAudioFileOutput()
        recorder.session = ScreenRecorder.Session(
            choice: RecordingChoice(), movieURL: movie, micURL: mic, stream: stream,
            output: output, micSession: nil, micOutput: micOutput, calledAt: Date(),
            onFinish: { [weak self] outcome in self?.finishes.append(spell(outcome)) })
        recorder.state = state
    }

    var state: String { "\(recorder.state)" }
    var stoppedBy: String { recorder.session.map { "\($0.stoppedBy)" } ?? "nil" }

    /// Lights the recorder's own meter, as a poll would.
    func light() {
        recorder.meter.publish(
            LevelMeterReading(peakLeft: 0.5, peakRight: 0.5, rmsLeft: 0.3, rmsRight: 0.3),
            from: ObjectIdentifier(recorder))
    }
    func screenFinished() { recorder.recordingOutputDidFinishRecording(output) }
    func micFinished(error: Error?) {
        guard let micOutput, let mic else { return }
        recorder.fileOutput(micOutput, didFinishRecordingTo: mic, from: [], error: error)
    }
    func streamStopped(_ code: SCStreamError.Code) {
        recorder.stream(
            stream,
            didStopWithError: NSError(domain: SCStreamError.errorDomain, code: code.rawValue))
    }
    /// True once the recorder is idle again — the conclude landed.
    func settled() -> Bool { spin(5) { recorder.state == .idle } }
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
    fake.recorder.session?.screenFinished = true
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

func state(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    // The driven half, in its own request so a fake that will not build
    // fails its rows and not the idle machine's.
    if request["drive"] as? Bool == true, let path = request["work"] as? String {
        let work = URL(fileURLWithPath: path, isDirectory: true)
        out["join"] = scenarioJoin(work)
        out["oneShot"] = scenarioOneShot(work)
        out["micDies"] = scenarioMicDies(work)
        out["path"] = scenarioPath(work)
        out["external"] = scenarioExternal(work)
        out["idleFaces"] = scenarioIdleFaces(work)
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
        "duration": clip.duration, "in": inPoint, "media": mediaId,
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
    return [
        "ops": placement.ops.map { $0.name }, "opJSON": placement.ops.map { $0.json },
        "scopes": scopes,
        "predicted": [
            "media": Int(placement.mediaId), "clip": placement.clipId.map { Int($0) } ?? -1,
            "micMedia": placement.micMediaId.map { Int($0) } ?? -1,
            "micClip": placement.micClipId.map { Int($0) } ?? -1,
        ] as [String: Any],
        "nextIdBefore": Int(beforeDoc.nextId),
        "frontTrackBefore": Int(beforeView.tracks.last?.id ?? 0),
        "mintedMedia": media, "mintedClips": clips, "mintedTracks": tracks,
        "viewTracks": viewTracks,
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
        ["ApplePersistenceIgnoreState": true, "AgentServerEnabled": false,
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
        let d = try ProjectDocument.untitled(around: result(mic: false, rate: 60, descriptor: desc))
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
        let d2 = try ProjectDocument.untitled(
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

// ---- mode "chrome": the menu, the welcome buttons, the panel, the guard ---
func chrome(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain([
        RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
        RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
        RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
        "AgentServerEnabled": false,
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
    // The six keys the harness pins are the panel's own, by name.
    out["keys"] = [RecorderPanelController.displayKey, RecorderPanelController.microphoneKey,
                   RecorderPanelController.systemAudioKey, RecorderPanelController.showClicksKey,
                   RecorderPanelController.rateKey, RecorderPanelController.sizeKey]

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
        "menuBarSentence": "Stopped from the menu bar; the recording was added.",
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
        return [
            "title": button.title,
            "textWidth": Double(button.title.size(withAttributes: [.font: font]).width),
            "intrinsic": [Double(button.intrinsicContentSize.width),
                          Double(button.intrinsicContentSize.height)],
            "frame": [Double(frame.minX), Double(top), Double(frame.width), Double(frame.height)],
            "font": font.fontName,
            "action": button.action.map { NSStringFromSelector($0) } ?? "",
        ]
    }
    out["spacing"] = Double((buttons.first?.superview as? NSStackView)?.spacing ?? -1)
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

// ---- dispatch -------------------------------------------------------------
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: probe <request.json> <answer.json>\n".utf8))
    exit(2)
}
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
    case "chrome":
        answer = chrome(request)
    case "welcome":
        answer = welcome(request)
    case "catalog":
        answer = catalog(request)
    case "host":
        answer = host(request)
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
    """`remaining_probe.py`'s builder: the same swiftc line as
    `harness/build.sh`, the same staleness rule, and a reason instead of an
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
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in files + [entry, lib]
    ):
        print(f"recording probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + files + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"recording probe: {binary} (built in {time.time() - start:.1f} s from {sources})")
    return binary, None


def run_probe(binary, tag, request):
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
        result = subprocess.run([binary, req, out], capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return None, "the probe did not answer within 120 s"
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
    default = os.path.expanduser("~/Movies/Reelcut Recordings")
    check("1a: folder() without the override is `~/Movies/Reelcut Recordings` (decision 2)",
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
                      ("mainDisplay", True)]:
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

    ppid = answer.get("ppid")
    pane = answer.get("screenPane") or ""
    clause = answer.get("launchClause") or ""
    check("3h: the probe is launched by another process (getppid() != 1) — the precondition "
          "of the launch clause", isinstance(ppid, int) and ppid != 1, f"got {ppid!r}")
    check("3h: launchClause names the launching process by pid and the two ways out",
          f"launched by another process (pid {ppid})" in clause and "the terminal's" in clause
          and "open -a Reelcut.app" in clause, f"got {clause!r}")
    check("3h: screenRecordingRefusal is the pane sentence + the clause — the pane sentence its "
          "PREFIX, so recording_proof.py's match holds",
          bool(clause) and screen == pane + clause and screen.startswith(pane)
          and pane.endswith("then relaunch."), f"got {screen!r}")
    for word in ("notDetermined", "denied", "restricted"):
        text = refusal.get(word) or ""
        check(f"3h: microphoneRefusal(.{word}) keeps its head and ends with the clause",
              text.startswith(f"The microphone is not granted to Reelcut (status: {word}). ")
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


# --------------------------------------------------------------------------
# Section 4 — the landing (road map 3, R1b): lane B's rows as tracked checks.

SEC = 600_000
FRAME_30 = 20_000                      # one frame at the fresh project's 30 fps
FRAME_60 = 10_000                      # one frame at the recorder's 60 fps
PICTURE_LEN = 5 * SEC                  # the picture descriptor's 5 s
MIC_LEN = 5 * SEC + 12_000             # the microphone file, 5.02 s
# `add_clip` snaps a clip's length to the canvas frame grid — lane B's one
# wrong first expectation, kept here as the rule rather than the number.
MIC_LEN_SNAPPED = (MIC_LEN + FRAME_30 // 2) // FRAME_30 * FRAME_30   # 3 020 000
RECORDING_STEM = "Screen Recording 2026-09-10 at 14.03.22"
MIC_STEM = "Screen Recording 2026-09-10 at 15.00.00"
PACKAGE_TYPE = "com.kgalligan.reelcut-project"
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
# Section 5 — the chrome's structure (road map 3, R1c): lane C's rows.

PANEL_ROWS = [
    ("isPanel", True), ("nonactivating", True), ("titled", True), ("closable", True),
    ("floating", True), ("hidesOnDeactivate", False), ("excluded", True), ("released", False),
    ("delegateNil", True), ("title", "New Recording"), ("visible", False),
    ("destinationFirst", "New Project"), ("destinationCount", 1), ("microphoneFirst", "Off"),
    ("sourceLast", "Window…"), ("sourceLastTag", 1), ("recordTitle", "Record"),
    ("recordFillIsClip", True), ("recordTargetIsPanel", True), ("rate", 60),
    ("resolution", "nominal"), ("systemAudio", True), ("showClicks", False),
    ("microphoneOff", True), ("newProject", True), ("mainDisplay", True), ("idle", True),
    ("controlsEnabled", True), ("countdownHidden", True), ("noteHidden", True), ("meterWidth", 120),
]
COMMAND_OPTION = (1 << 20) | (1 << 19)   # NSEvent.ModifierFlags.command | .option
RECORDING_KEYS = ["displayKey", "microphoneKey", "systemAudioKey", "showClicksKey", "rateKey", "sizeKey"]


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
    check("5c: the third's action is newRecording:", len(actions) == 3 and actions[2] == "newRecording:",
          f"{actions}")
    check("5c: … and its target nil", (w.get("targets") or [True] * 3)[-1] is False, f"{w.get('targets')}")
    check("5c: the other two are openDocument: and newProject:, unchanged",
          actions[:2] == ["openDocument:", "newProject:"], f"{actions}")
    print("  5d — the panel")
    p = answer.get("panel") or {}
    for key, want in PANEL_ROWS:
        check(f"5d: panel.{key} == {want!r}", p.get(key) == want, f"got {p.get(key)!r}")
    check("5d: Source rows = NSScreen.screens + a separator + Window…",
          p.get("sourceCount") == p.get("screens", -9) + 2
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
    check("5d: six distinct ReelcutRecording… keys",
          len(set(keys)) == 6 and all(k.startswith("ReelcutRecording") for k in keys), f"{keys}")
    harness = open(HARNESS_MAIN).read()
    # The pins are spelled as string LITERALS in the harness, not as
    # `RecorderPanelController.<key>`, so that a tree from before the recorder
    # existed can still compile this instrument under -D HARNESS_REFERENCE_BUILD
    # (the phase-5 cross-build); the probe reads the constants' VALUES off the
    # app and looks for each of those strings in the harness's text.
    check("5d: the harness pins every one of them by VALUE",
          len(keys) == 6 and all(f'"{k}"' in harness for k in keys), f"{keys}")
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
    land = read_code(sources, "RecorderPanelController+Landing.swift")
    base = read_code(sources, "RecorderPanelController.swift")
    rows = read_code(sources, "RecorderPanelController+Rows.swift")
    route = read_code(sources, "AppDelegate+Recording.swift")
    status = read_code(sources, "RecorderStatusItem.swift")
    for name, code in [
        ("+Recording", rec), ("+Landing", land), ("base", base), ("+Rows", rows),
        ("+Recording (route)", route), ("status item", status),
    ]:
        check(f"5h: {name} is in the sources", code is not None)
    if None in (rec, land, base, rows, route, status):
        return
    # fix 1: the grant is asked on every press — no `canAsk` gate survives here
    # (canask-restored puts one back).
    check("5h: `+Recording.swift` gates no grant ask on canAsk (fix 1)",
          "canAsk" not in rec, "a canAsk gate is back")
    check("5h: … and still asks CGRequestScreenCaptureAccess on a press",
          "CGRequestScreenCaptureAccess()" in rec)
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
    fit_body = "\n".join(function_body(base.splitlines(), "func fitWindowToContent()") or [])
    check("5h: fitWindowToContent constrains the frame to its screen before setFrame "
          "(fix 5, no-constrain)",
          "constrainFrameRect" in fit_body and "window.screen" in fit_body, fit_body)
    # fix 9: microphoneAnswered guards visibility and re-enables the button.
    mic_body = function_body(rec.splitlines(), "func microphoneAnswered()")
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
# Section 6 — the welcome window's cross-build (phase 5's pattern).
#
# PNG, in pure Python, and the pixel helpers: `phase5_chrome.py`'s, unchanged
# — every chrome script carries its own copy so one can be run without the
# others.

WELCOME_W = 720
WELCOME_H = 600
WELCOME_CENTER_X = 360               # the stack is centred on the content view
STICKER_H = 34                       # StickerButton.bodyHeight 28 + 6
STICKER_PAD = 32 + 6                 # intrinsicContentSize: ceil(textWidth) + 32 + 6
# `StickerButton.draw` at rest: the body at (2, 2) with a 1.5 pt stroke
# centred on its edge (0.75 outside), the sticker shadow offset by 2. So a
# button's ink runs from 1.25 pt to (width − 2) across and from 1.25 to 32
# down — a 30.75 pt tall band inside the 34 pt row.
INK_LEFT = 2 - 0.75
INK_TOP = 2 - 0.75
INK_RIGHT_INSET = 2
INK_BOTTOM = 28 + 2 + 2
INK_H = INK_BOTTOM - INK_TOP
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
    """`git archive` the reference tree into `work/`, then compile it with the
    SAME swiftc line, staticlib and bridging header the current build uses —
    so the two binaries differ by the phase's own `app/Sources` changes and by
    nothing else.

    Returns `(binary, sha, note)`, with `binary` None when it could not be
    built at all; `note` says which `main.swift` the reference was compiled
    with, and section 6 prints it and scores the failure. It is a returned
    failure rather than a `sys.exit` for one reason: this build is the only
    thing in the script that reaches BACKWARDS in the history, so it is the
    only thing that can rot on its own, and a rotted instrument must not take
    the sections that need no reference at all down with it.

    **The instrument, and what happens when it will not fit.** The reference
    is compiled with the CURRENT `harness/main.swift` under
    `-D HARNESS_REFERENCE_BUILD`, which compiles out every mode naming a type
    an older tree lacks (that file's header states the convention). Both
    renders then come out of one program, which is the whole value of the
    comparison. When the current instrument will not compile against the older
    tree anyway — a mode a later phase forgot to guard, or an `app/Sources`
    change the reference tree cannot satisfy — it falls back to the reference
    commit's OWN `harness/main.swift` and says so, because a comparison made
    with two builds of the instrument is worth more than no comparison, and
    far more than a script that exits before its first check. The fallback is
    the apology, not the plan: the fix is the guard — and section 6 SCORES
    which one was used.

    Skipped when the stamp beside the binary still names the same commit and
    the same instrument. `harness/build.sh` is not reused because it hard-codes
    `app/Sources`; everything else about the two builds is deliberately equal,
    down to the `-module-name`.
    """
    sha = git("rev-parse", commit).strip()
    binary = os.path.join(BEFORE, "harness")
    stamp = os.path.join(BEFORE, "stamp.json")
    instrument = [
        sha,
        os.path.getmtime(HARNESS_MAIN), os.path.getsize(HARNESS_MAIN),
        os.path.getmtime(STATICLIB), os.path.getsize(STATICLIB),
    ]
    if os.path.exists(binary) and os.path.exists(stamp):
        with open(stamp) as f:
            kept = json.load(f)
        if isinstance(kept, dict) and kept.get("instrument") == instrument:
            return binary, sha, kept.get("note", "")

    for path in (binary, stamp):
        if os.path.exists(path):
            os.remove(path)
    tree = os.path.join(BEFORE, "tree")
    subprocess.run(["rm", "-rf", tree], check=True)
    os.makedirs(tree, exist_ok=True)
    # The reference commit's own copy of the harness comes out of the archive
    # beside its `app/Sources`, unused unless the current one will not build.
    archive = subprocess.run(
        ["git", "-C", ROOT, "archive", sha, "app/Sources", "tools/proof/harness/main.swift"],
        capture_output=True, check=True)
    subprocess.run(["tar", "-x", "-C", tree], input=archive.stdout, check=True)
    sources = sorted(
        os.path.join(tree, "app", "Sources", name)
        for name in os.listdir(os.path.join(tree, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"],
        capture_output=True, text=True, check=True).stdout.strip()

    def compile_with(main):
        return subprocess.run(
            ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0",
             "-module-name", "Reelcut", "-import-objc-header", BRIDGING,
             "-D", "HARNESS_REFERENCE_BUILD",
             "-L", os.path.dirname(STATICLIB), "-lreelcut_core"]
            + sources + [main, "-o", binary],
            capture_output=True, text=True)

    theirs = os.path.join(tree, "tools", "proof", "harness", "main.swift")
    attempts = [(HARNESS_MAIN, "this tree's own harness/main.swift, so both renders "
                               "come out of one program")]
    if os.path.exists(theirs):
        attempts.append((theirs, f"{sha[:8]}'s OWN harness/main.swift — the current one "
                                 "does not compile against that tree, so the two renders "
                                 "are two builds of the instrument as well as two builds "
                                 "of the app; see build_reference"))
    start, note, used, failures = time.time(), None, None, []
    for candidate, description in attempts:
        result = compile_with(candidate)
        if result.returncode == 0 and os.path.exists(binary):
            note, used = description, candidate
            break
        failures.append(
            f"with {os.path.relpath(candidate, ROOT)}:\n"
            + "\n".join((result.stdout + result.stderr).strip().splitlines()[:6]))
    if note is None:
        return None, sha, (f"the reference harness ({sha[:8]}) did not build.\n"
                           + "\n".join(failures))
    if used != HARNESS_MAIN:
        print(f"reference: WARNING — fell back to {sha[:8]}'s own harness/main.swift")
        for failure in failures:
            print("      " + failure.replace("\n", "\n      "))
    # The harness registers the fonts sitting BESIDE its own binary, and
    # without them every label in the reference render falls back to the
    # system face — which shows up as a full-window diff and looks exactly
    # like a layout change (phase 5 measured it).
    subprocess.run(["rm", "-rf", os.path.join(BEFORE, "Fonts")], check=True)
    subprocess.run(["cp", "-R", FONTS, os.path.join(BEFORE, "Fonts")], check=True)
    with open(stamp, "w") as f:
        json.dump({"instrument": instrument, "note": note}, f)
    print(f"reference: built {sha[:8]} in {time.time() - start:.0f} s")
    return binary, sha, note


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
          "the three-button row is all that changed")
    if os.path.realpath(sources) != os.path.realpath(TREE_SOURCES):
        print("  (this section renders the TREE through harness/build.sh, not --sources; a "
              "mutant of the button is section 5's to catch)")
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
    check("6a: three buttons, the third New Recording… with action newRecording:",
          len(buttons) == 3 and buttons[2].get("title") == "New Recording…"
          and buttons[2].get("action") == "newRecording:", f"{[(b.get('title'), b.get('action')) for b in buttons]}")
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
          "against — see build_reference for the two instruments it tries",
          reference is not None, "      " + (note or "").replace("\n", "\n      "))
    check("6b: … compiled with THIS tree's own harness/main.swift (one program, two app trees) — "
          "the fallback means the harness names a type the older tree lacks outside the "
          "HARNESS_REFERENCE_BUILD guard", reference is not None and note.startswith("this tree's own"),
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

    ink = Rect("the row's ink", row.x0 + INK_LEFT, row.y0 + INK_TOP,
               row_w - INK_LEFT - INK_RIGHT_INSET, INK_H)
    print(f"      predicted: {row}")
    print(f"      predicted: {ink}")
    for appearance, was, tag in (("light", "was-light", "now-light-a"), ("dark", "was-dark", "now-dark")):
        diff = changed_pixels(images[was], images[tag])
        if diff is None:
            check(f"6d {appearance}: the two renders have one shape", False)
            continue
        boxes = clusters(diff)
        print(f"\n   {appearance}: {len(diff)} changed pixels in {len(boxes)} cluster(s) — printed, "
              "never counted as one:")
        print(describe(boxes, scale))
        check(f"6d {appearance}: the third button changed SOMETHING", bool(diff))
        box = extent(diff, scale)
        print(f"      extent: {box}")
        check(f"6d {appearance}: the diff's extent is the ink of the three-button row — x from "
              f"{ink.x0:g} to {ink.x1:g} (the row less the 1.25 pt stroke overhang on the left and "
              f"the 2 pt shadow on the right), within a pixel",
              box is not None and close(box[0], ink.x0, pixel) and close(box[2], ink.x1, pixel), f"{box}")
        check(f"6d {appearance}: … and {INK_H:g} pt tall — the {STICKER_H} pt row less the 2 pt top "
              "margin the stroke reaches 0.75 into and the 2 pt under the shadow (StickerButton.draw)",
              box is not None and close(box[3] - box[1], INK_H, pixel), f"{box[3] - box[1] if box else None}")
        derived_top = (box[3] - INK_BOTTOM) if box else None
        check(f"6d {appearance}: the row's y DERIVED from the diff's bottom edge ({derived_top}) is the "
              f"laid-out row's ({laid_top})", close(derived_top, laid_top, pixel), f"{derived_top} vs {laid_top}")
        stray = outside(diff, [row], scale)
        check(f"6d {appearance}: nothing outside the row changed — the lockup, the headline, the "
              "paragraph, Recent and the formats line are where they were",
              not stray, "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
        old_w = row_w - widths[-1] - (spacing or 0)
        old = Rect("the old two-button row", WELCOME_CENTER_X - old_w / 2, row.y0, old_w, STICKER_H)
        check(f"6d {appearance}: the old two-button row ({old.x0:g}–{old.x1:g}) lies inside the new one, "
              "so the extent is the new row's and not a union with something that moved elsewhere",
              old.x0 >= row.x0 - 1e-9 and old.x1 <= row.x1 + 1e-9, f"{old} vs {row}")


# --------------------------------------------------------------------------
# Section 7 — the catalog after the toll: 75 names, the file groups last.

APP_STATE_TOOLS = [
    "open_project", "new_project", "save_project", "get_project", "import_media",
    "import_captions", "export_captions", "transcribe", "consolidate_media", "detect_silence",
    "normalize_clip", "set_playhead", "set_range", "set_selection", "set_scope", "undo", "redo",
    "render_frame", "export", "record_screen",
]
# `git show df6b916^:app/Sources/AgentCatalog.swift`'s last ten rows, in order.
FILE_GROUP_ORDER = [
    "import_media", "import_captions", "consolidate_media", "add_media", "relink_media",
    "remove_media", "transcribe", "export_captions", "render_frame", "export",
]
RECORD_SCREEN_ARGUMENTS = [
    "display", "microphone", "path", "place", "project", "rate", "seconds", "show_clicks", "size",
    "system_audio", "window",
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
    check("7a: the core declares 55 ops (rc_op_names)", len(ops) == 55 and len(set(ops)) == 55, f"{len(ops)}")
    check("7a: the catalog has exactly 75 tools, no name twice", len(names) == 75 and len(set(names)) == 75,
          f"{len(names)} names, {len(set(names))} distinct")
    check("7a: they are the 55 ops plus the twenty app-state tools, record_screen among them",
          set(names) == set(ops) | set(APP_STATE_TOOLS), f"missing {sorted(set(ops) | set(APP_STATE_TOOLS) - set(names))}, "
          f"extra {sorted(set(names) - set(ops) - set(APP_STATE_TOOLS))}")
    check("7a: no app-state tool is also an op", not set(APP_STATE_TOOLS) & set(ops),
          f"{sorted(set(APP_STATE_TOOLS) & set(ops))}")
    check("7b: the LAST eleven are the old file's ten file rows in its order, then record_screen",
          names[-11:] == FILE_GROUP_ORDER + ["record_screen"], f"{names[-11:]}")
    check("7b: … so the first 64 are byte-for-byte the groups that stayed and the clip rows — none "
          "of the ten appears earlier", not set(FILE_GROUP_ORDER) & set(names[:-11]),
          f"{sorted(set(FILE_GROUP_ORDER) & set(names[:-11]))}")
    by = {t.get("name"): t for t in tools}
    without = [n for n in ops if not (by.get(n) or {}).get("hasScope")]
    check("7c: every op tool's schema declares `scope`", not without, f"without: {without}")
    with_scope = [n for n in APP_STATE_TOOLS if (by.get(n) or {}).get("hasScope")]
    check("7c: none of the twenty app-state tools declares it", not with_scope, f"with: {with_scope}")
    rs = by.get("record_screen") or {}
    check("7c: record_screen's schema has no `scope` key", rs and rs.get("hasScope") is False, f"{rs}")
    check(f"7c: record_screen declares exactly {RECORD_SCREEN_ARGUMENTS}",
          rs.get("properties") == RECORD_SCREEN_ARGUMENTS, f"{rs.get('properties')}")
    check("7c: … requiring seconds alone", rs.get("required") == ["seconds"], f"{rs.get('required')}")
    check("7c: every tool carries `project`", all("project" in (t.get("properties") or []) for t in tools),
          f"{[t.get('name') for t in tools if 'project' not in (t.get('properties') or [])]}")


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
        "            action: #selector(AppDelegate.newRecording(_:)))\n",
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
        "            RecorderPanelController.shared.show()\n"
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
        "            if head > 0 {\n"
        "                clipOps += [\n"
        "                    .trimStart(clip: clip, to: head), .moveClip(clips: [clip], delta: -head),\n"
        "                ]\n"
        "            }\n",
        "",
        "addMicrophoneClip's trim dropped — a negative start is placed at 0 untrimmed, the voice late"),
    # Lane R's four, the R1 review's recorder fixes (section 3's driven rows).
    "busy-finishing": (
        "ScreenRecorder.swift",
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
        "        if let failure = done.micFailure {\n"
        "            return conclude(done, .failure(RecorderError.finishFailed(failure)))\n"
        "        }\n",
        "settle returns the microphone failure BEFORE the movie probe (finding 0 undone)"),
    "no-path": (
        "ScreenRecorder+Finishing.swift",
        "        if case .failure(let error) = outcome, let failure = error as? RecorderError {\n"
        "            delivered = .failure(Self.namingFiles(failure, done))\n"
        "        }\n",
        "",
        "the path clause not appended — a failure past beginFinishing names no file (finding 6 undone)"),
    # Lane P2's, the R1 review's chrome fixes (section 5's structural and driven rows).
    "canask-restored": (
        "RecorderPanelController+Recording.swift",
        "            _ = CGRequestScreenCaptureAccess()\n",
        "            if Transcriber.canAsk { _ = CGRequestScreenCaptureAccess() }\n",
        "the grant ask gated on canAsk again — Record under -AgentServerEnabled shows a refusal "
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
        "RecorderPanelController.swift",
        "        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first\n"
        "        frame = window.constrainFrameRect(frame, to: screen)\n",
        "",
        "the grown card is not constrained to its screen — the countdown pushes a bottom-parked "
        "panel under the Dock (fix 5 undone)"),
    "show-while-hidden": (
        "RecorderPanelController.swift",
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
        sys.exit(f"mutant {name}: the text to replace occurs {text.count(before)} times in "
                 f"{file_name}, not once — the tree has moved and the mutant needs re-aiming")
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    print(f"  mutant {name}: {what}\n")
    return target


SECTIONS = [section_files, section_configuration, section_state, section_landing, section_chrome,
            section_welcome, section_catalog, section_host]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--sources", default=os.environ.get("RC_APP_SOURCES", TREE_SOURCES),
                        help="an app/Sources directory to compile the probe against — a "
                             "mutant copy under work/ for the gate (default: the tree's, "
                             "or $RC_APP_SOURCES, the spelling remaining_probe.py shares)")
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="prepare a named mutant copy of the tree's app/Sources and "
                             "compile against it (overrides --sources)")
    args = parser.parse_args()
    sources = os.path.abspath(args.sources)

    print("recording — road map 3 R1's app half: files, configurations, the idle machine, the "
          "landing, the chrome, the welcome cross-build, the catalog\n")
    if args.mutant:
        sources = prepare_mutant(args.mutant)
    if sources != os.path.realpath(TREE_SOURCES):
        print(f"  (compiling against {sources}, not the tree)\n")
    binary, error = build_probe(sources)
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is not None:
        for section in SECTIONS:
            section(binary, sources)

    print(f"\n{passed}/{passed + failed} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
