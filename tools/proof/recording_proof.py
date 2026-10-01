#!/usr/bin/env python3
"""Road map 3, R1 and R2 — `record_screen`, driven against the built binary
over MCP.

`record_screen` is File ▸ New Recording… without the panel: `ScreenRecorder`
run for a fixed number of seconds from the agent and landed through the
same `RecordingLanding` the panel lands with (`AgentServer+Recording.swift`,
its arguments in `+RecordingArguments.swift`, its result and sentences in
`+RecordingResult.swift`). This script is what a LIVE SERVER can say about
it, in two tiers, and the split between them is the whole design: a
headless machine — no Screen Recording grant, or a console with no display
to share — can still measure the catalog, every refusal and the order the
refusals come in, while the recording itself is measured only where a
recording can be made, and a run that could not make one SAYS so with a
count rather than passing vacuously.

**The HEADLESS tier always runs** (sections 0–4, on the instance at `port`):

* Section 0, the catalog. AT LEAST 75 tools — a FLOOR since road map 5's E1
  added two, and the exact count belongs to road map 7's
  `op_argument_proof.py` at 77 (`tools/proof/README.md`'s handover) — with
  `record_screen` declaring exactly its
  ten arguments plus the injected `project`, `seconds` its only required
  one, and NO `scope`: it is an app-state tool like `transcribe`, and
  `AgentCatalog.tool` injects `scope` for the core's op names only. Exactly
  55 tools carry `scope` (that 55 is `rc_op_names` read through
  `AgentCatalog.opNames`, the live core's op count) and the twenty without
  one are named, not counted. The description is read for the phrases the
  R1 review made it owe — `mic_problem`, the `Add Microphone` undo step, the
  launching process — and for R2's: `Pause Recording` and `Resume Recording`
  (the status item's two menus), the `Add Recording Segments` undo step, and
  the result keys `pauses`, `segments` and `started_at` beside R1's
  twenty-four. R2 adds no tool — there is deliberately no tool that pauses —
  and the parity log is read too.
* Section 1, the refusals, each asserted as the EXACT sentence, each leaving
  `get_project`'s whole answer byte-identical and pushing no undo step. And
  the ORDER: the caller's own mistakes (`seconds` absent, 0, 601, `"x"`;
  `display` with `window`; `rate` 24; `size` "huge"; a `project` naming
  nothing open) are answered before any grant is read and before the
  display list is asked for, so a row that combines `seconds: 0` with a
  `display: 99` — a mistake only the LOOKUP can see — must answer the
  seconds sentence. A build that hoisted the grant check above the argument
  checks fails those rows on an ungranted machine; a build that hoisted the
  lookup fails them everywhere. The `project` refusal's "stands" row
  compares the FRONTMOST document's path before and after the refused call
  (a build that fell through to a fresh document would put one in front);
  it used to read the media list of a document no code path adds to, which
  passed against every build — and the frontmost path alone cannot either,
  measured: on an instance nothing activates, `NSApp.orderedDocuments.first`
  is the launch-time untitled document whatever is opened later, so the row
  also bounds the call's TIME under a second, since a fall-through has to
  record the 2 s span first. The microphone row is CONDITIONAL on the
  host, and is written so it never records: `microphone: true` beside a
  `project` that names nothing — with the grant absent the microphone
  sentence comes first and names the framework's own status word
  (`notDetermined`, `denied` or `restricted`, the way `phase4_proof.py`
  reads `transcribe`'s); with it, the project's by-name refusal comes
  instead, which is the only way a headless script can see the check was
  passed rather than skipped. The Screen Recording sentence is matched as a
  PREFIX — `RecordingGrant.screenRecordingPaneSentence` — because the
  refusal now ends with the launch clause under a shell launch (R0 q1: the
  grant that counts is the terminal's, and the sentence says whose).
* Section 2, the held last frame — lane E's `CompositionBuilder.heldTail`,
  which needs no grant: a fixture with 1 s of picture and 5 s of sound
  (`ffmpeg`, `testsrc2` + `sine`, NO `-shortest`) opened as a project, then
  `render_frame` at 0.99 s, 3 s and 4.9 s — three PNGs with EQUAL sha256
  and a luma average that is not black's 16.0 (`ffmpeg`'s `signalstats`);
  `trim_start` to 2 s and a render at 2 s equal to the 0.99 s frame; and
  `set_speed` 2.0 with a render at 2.4 s (source 4.8 s, held) equal to it
  and a render at 0.4 s (source 0.8 s, frame 24) a DIFFERENT non-black
  frame. Every claim is an equality between renders, never a literal hash.
  Its first row is the gate, always scored (issue batch B27, #181):
  `ffmpeg -version` must RUN (`ffmpeg_runs()`), and a FAIL — never a skip —
  names why: not on PATH, the exit code with ffmpeg's first stderr line (a
  missing dylib), or no answer within 30 s. On PATH alone was not enough:
  a broken install is on PATH and cannot run.
* Section 3, the tool's SOURCE, read where no call can reach: the stop
  ceiling's derivation (`stopCeiling(segments:)` — `finishCeiling + 2 × 30 ×
  max(n, 1) + 5` over the segments the recorder holds, 75 s unpaused and
  60 s more per further segment, independent of `seconds`; the R2 review
  found a fixed 75 s shorter than two segments' probes), the old "`.busy`
  mid-finish" claim gone from
  the file, the status item the tool now puts up, the alert clause on both
  timeout sentences, the gesture wait bound to the panel's own constants by
  name, `mic_problem` in the result, the zero-display sentence ahead of the
  range sentence, `path`'s trim, and R2's: the status item's THREE closures
  (Pause and Resume as the recorder's `pause()` / `resume()` under `try?`,
  Stop freezing the item's mark before the recorder's `stop()`, the tick
  passing `elapsed` and `isPaused` — read in `RecordingToolChrome`, which
  issue batch B27 moved to `AgentServer+RecordingChrome.swift`), the finish timeout reading the
  session's SEGMENTS — their count sizing the ceiling — and its sentence
  pluralised by count, `savedButNotAdded` built over
  `RecordingResult.filesClause`, which names every segment's movie and
  every microphone file comma-joined,
  `pauses` and `segments` written unconditionally with `started_at` from an
  ISO 8601 UTC formatter with fractional seconds, `duration` as the SUM over
  segments, and NO `result.micDescriptor` or `result.micOffset` in either
  file's CODE (the doc comment that names them is skipped, or the read would
  be satisfied by the sentence saying they are gone). These are structural reads of Swift —
  `phase7_chrome.py`'s `destinationProperties != nil` is the precedent —
  and they claim exactly that: the text is there. A 75 s stop ceiling and
  a menu-bar item are not things a script can wait out or photograph.
* Section 4, the tone arithmetic's SELF-TEST: the Goertzel share the tone
  rows score (below) run over a synthesized sine, noise and silence written
  and read through the `wave` module, no recording and no `ffmpeg` — sine
  ≈ 1, noise < 0.01, silence 0 — so the tone rows cannot be wrong about
  their own scale again.

**The GRANTED tier** is decided by the script's OWN probe, not by the tool:
a small `swiftc` program (compiled into `work/recordingproof/`, cached on
its mtime) reads `CGPreflightScreenCaptureAccess()`, the session's
`CGSSessionScreenIsLocked`, the main display's point size and backing scale,
and how many displays `SCShareableContent` lists — all under the same
terminal grant the instance runs under (R0 q1). Then one detection call,
`record_screen {seconds: 1, place: false, path: …}` against a document the
script opened (never with none open, which would open one), and three
outcomes:

* the probe's preflight is FALSE → the tool must answer the Screen
  Recording sentence (the pane sentence as a prefix), and the tier is
  SKIPPED with its count;
* the preflight is TRUE and the probe lists NO display — a locked console
  or a sleeping display, which is what this host looked like the night this
  script was written (locked at 23:03, the display asleep, zero active
  displays) — → the tool must NAME that ("No display is shareable right
  now — the console is locked or every display is asleep; nothing can be
  recorded until one is.") rather than hang or spell it as an index out of
  range, and the tier is SKIPPED with its count and the lock state printed;
* the preflight is TRUE with displays → any refusal is a FAILURE quoting
  it (a `userDeclined` start after a true preflight is the case the road
  map names), and the tier runs.

When it runs, the detection call's own ANSWER is the first thing read
(R2d — the result's shape with one segment, on the headless instance's
document): `pauses` 0 and an integer; `segments` a list of exactly one
entry whose `path` and `duration` are the top level's (one segment: the
TOTAL is the segment's), whose `media` is the top level's AND the
document's media entry for that path, which carries no `clip` (`place:
false`), whose `width`, `height` and `fps` are the top level's (each entry
carries its own descriptor's — the fix wave's addition), whose
`mic_offset` is the top level's and which has no `mic_path` or
`mic_problem` (no microphone was asked for), whose keys are a subset of
the fourteen the description names, and whose `started_at` is spelled
`YYYY-MM-DDTHH:MM:SS.mmmZ` and parses (`datetime.fromisoformat`) to an
instant between the call and a minute after it — a formatter left in local
time fails that row by the host's UTC offset wherever the host is not at
UTC.

With the grant, the tier launches a SECOND instance of the same binary on
`GRANTED_PORT` with `-RCRecordingFolder` pointing into `work/recordings/`
(`phase8_proof.py`'s `Instance`, copied whole), reads the Microphone grant
off THAT instance (the one the microphone rows run on — it used to be read
off the port instance, whose grant is a fact about another process), prints
in its summary line the binary it launched and the RESPONSIBLE application
of BOTH instances — the launchd-started ancestor of each, which is whose
Screen Recording grant a direct launch runs under (R0 q1) — and asserts, in
this order because the first row needs NO document open:

* no document → `landed: new_project`; the file under the folder with the
  dated name; `duration` in [1.5 s, 3.5 s]; `width`/`height` the main
  display's POINT size under `nominal`, allowing +1 on an odd dimension
  (the H.264 writer rounds up to even); the new document addressable by
  `project: <the recording's path>`; its `canvas.fps` `[60, 1]` while the
  media's `fps` is NOT `[60, 1]` — ONE row, decision 3, the row the "fps
  override deleted" mutant fails — SKIPPED with a count on a run where the
  file's own rate happens to be exactly 60/1, since then the override
  cannot be told from the file; no undo step (a mic-less new project's
  first project is what the document is); and the R2 shape — `pauses` 0
  with one segment whose `path` and `duration` are the top level's, whose
  `width`, `height` and `fps` are its own descriptor's and equal the top
  level's, whose `started_at` is within a minute after the call, and whose `media` and
  `clip` — looked up by PATH on the document `untitled(around:)` built —
  are the top level's;
* into a saved document with an EMPTY front track: the clip at the
  playhead ON that track with the new media id (the two-try rule's first
  branch, no track minted); `undo` removes media and clip in ONE step, the
  whole project fingerprint back to what it was, the file still on disk;
  a `render_frame` at the clip's midpoint that is neither black nor the
  frame the project rendered there before the recording; and the one
  segment carrying the placement's PREDICTED `media` and `clip`, equal to
  the top level's;
* the same playhead with the front track now OCCUPIED → a new front track
  (the second branch), which the `new_tracks` key reports;
* `size: "best"` → the display's PIXEL size, even rounding allowed;
* `place: false` → media alone: `new_media`, no `new_clips`, no `clip`,
  and the segment with the media and no `clip` either;
* `path: "  "` (blank) → the file lands in the instance's own
  `-RCRecordingFolder`, never in the process's working directory (the R1
  review: `URL(fileURLWithPath: "")` IS the cwd);
* inside an OPEN nest (`nest`, then `set_scope`) → the answer carries
  `scope` and `document_ops: ["add_media"]`, the view shows the clip with
  the new media — the segment's `clip` and `media` are those — and after
  `set_scope {}` the timeline does not;
* `system_audio: true` with NOTHING of this script's playing → `has_audio`
  true, `audio_tracks` 1; and then, while `afplay` plays a 30 s 1 kHz tone
  this script writes with the `wave` module, a second recording → the two
  files decoded to PCM (`ffmpeg`, a proof-time requirement here as it is
  for `phase2_proof.py`; a decode failure names ffmpeg's cause, #193 —
  whether `ffmpeg -version` runs and, when it does, which recording did not
  decode) and read through a Goertzel filter at 1 kHz on
  PARSEVAL's scale: the 1 kHz SHARE of a file is 2·|X[k]|² / (n·Σx²), which
  a pure tone puts at 1.0 and noise near 2/n, with n truncated to a
  multiple of 48 so 1000 Hz sits exactly on a bin. The tone recording's
  share must be ≥ 100× the silent one's (floored at 0.001), and ≥ 0.25 with
  an RMS ≥ 0.05 (−26 dBFS; R0 measured 0.35 at unity) — a unity tone
  dominates whatever else the host is playing. The first version of these
  rows divided a bin power by n and compared it with an RMS squared, two
  different scales, which is what section 4's self-test now pins. The rows
  do NOT assume a quiet host — measured 2026-09-11 02:30, Plex was playing
  into the tap with nothing of ours running — and they are SKIPPED with a
  count when the host's output is MUTED (`osascript` reads `output muted`),
  because a muted output reaches the tap unreliably: measured, R0's
  0.35-RMS tone arrived at −23 dB once and not at all once (00:25 the same
  night) — or is a Bluetooth / AirPlay device, which hands the tap digital
  silence on this host (measured 12:10 with AirPods Max);
* `system_audio: false` → `has_audio` false, `audio_tracks` 0;
* a document at `MAX_TRACKS` (64) with its front track occupied at the
  playhead → the recording is MADE and then cannot be added (the two-try
  rule's `add_track` meets the core's cap in the trial), and the refusal is
  "The recording was saved at <path> but could not be added: too many
  tracks…" — the file at that path, the document untouched. That is the R1
  review's rule that a failure after the file was written names it, at the
  one post-record throw site a script can reach; the other two (a live
  drag, an untitled document that will not open) are the same helper;
* the MICROPHONE rows, only when `codesign -d --entitlements` on the built
  app lists `com.apple.security.device.audio-input` AND the grant is
  authorized on the launched instance — otherwise skipped WITH A COUNT:
  `mic_path` exists with the ` (Microphone).m4a` spelling, `mic_media` and
  `mic_clip` present, the microphone clip on a track named "Microphone",
  the two clips' starts apart by the answer's `mic_offset` to within half
  a frame (the core snaps every start to the grid), `mic_duration` not more
  than two frames SHORTER than `duration` (the row that would have seen lane
  A's −421 ms head loss, which `prepareMicrophone` now pays before the
  start; a LONGER file is the microphone leading by `mic_offset`, measured
  +66 and +70 ms with a prepared session, and is not a loss), NO
  `mic_problem` on a microphone that landed, the one segment's `mic_path`,
  `mic_duration`, `mic_offset`, `mic_media` and `mic_clip` equal to the top
  level's with no `mic_problem` in it, both files' ids created and
  one undo removing both; then a recording at PLAYHEAD 0 — one segment,
  `pauses` 0, its `mic_offset` the one the branch reads — where the
  measured offset decides the landing's branch: an offset of at least half
  a frame trims the voice clip's HEAD (start 0, `in` the snapped offset);
  one of at most minus half a frame places it LATE by the snapped amount
  with `in` 0; and one within half a frame either way sends no trim and no
  delay, so that row is SKIPPED with its count and the number printed.

Every file the tier writes lives under `work/recordings/<pid>-…` and is
deleted at the end; the fixture movie and the compiled probe stay in
`work/recordingproof/`, the way every earlier proof's fixtures do. The
headless tier opens THREE documents on `port` (the refusals', the fixture's
and the detection's) and the granted instance holds four (the new project,
the placement document, the full one and the microphone's), so
`tools/proof/README.md`'s forty-document rule is nowhere near.

**A row group that raises scores ONE failure and reports the rest as a
skip** (`run_rows`): the granted tier's summary then still says how many
of its promised checks did not run, and its last row — that the tier made
exactly the checks its skip counts promise — still holds, because the
promise is reduced by the same number.

**Mutants, named with the row that kills each**, because a mutated binary
costs a `make app` and the fix wave runs them: the grant check hoisted
above the argument checks → the ordering rows (section 1; on an UNGRANTED
host — with the grant they are a statement about the sentence, and the
lookup-hoist rows are what still bite); the display lookup hoisted → the
`seconds: 0, display: 99` row on any host; the `.newProject` fallback
deleted → the no-document row; the `fps:` override deleted → the
`canvas.fps` row; the undo group split into two edits → the one-step undo
row; lane E's `heldTail` branch deleted → all three fixture rows (the 3 s
and 4.9 s frames go black); a `scope` declared on the tool → section 0's
"no scope" row; `savedButNotAdded` unwired at the placement throw → the
full-document row (the sentence is then the core's alone, no path in it);
`path`'s trim removed → the blank-path row (the file lands in the cwd);
`mic_problem` dropped from the result → section 3's read, and the
microphone note row; `pauses` or `segments` dropped from the result →
section 0's key reads and every shape row; `started_at` spelled in local
time → the within-a-minute rows, by the host's UTC offset (at UTC they
survive, and section 3's formatter read is what catches it there); the
timeout sentence's plural arm deleted → section 3. **What one segment
cannot tell**, said so the number is not mistaken for coverage: a build
writing the top level's values INTO the segment rather than the segment's
own, or leaving `duration` as the first segment's rather than the sum, is
byte-identical on every row here, because with one segment the two are
equal. No tool pauses — deliberately: a pause is a person's, from the menu
bar or the panel — so the two-segment result and the machine behind it are
`recording_probe.py`'s (its section 9 records, pauses and resumes under the
terminal's grant), and this script claims the one-segment shape and the
text.

**What this script does not claim.** The panel, the status item, the
welcome button and the menu item are a picture and a click, and they are
`recording_probe.py`'s and the chrome proofs' — so is a PAUSE, which only
the item's menu or the panel can send (R2: no tool pauses), and with it
every claim about a second segment. The two configurations a
choice becomes are pure and `recording_probe.py` reads every field back —
including `excludesCurrentProcessAudio`, which no recording can show. A
picker-made source (`.picked`) needs a person: the tool never presents one.
And a microphone that FAILS mid-recording (the `mic_problem` answer with a
sentence in it) needs a device to unplug: what is measured is that a
microphone that lands carries no such key, and the source read of the key.

    python3 tools/proof/recording_proof.py [port] [log path]
"""

import hashlib
import json
import math
import os
import random
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import wave
from datetime import datetime

from mcp import MCP, ToolError
from dev_tools import DEV_TOOLS

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4895
LOG = sys.argv[2] if len(sys.argv) > 2 else f"/tmp/reelcut-{PORT}.log"
GRANTED_PORT = 4896

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
ROOT = os.path.dirname(os.path.dirname(HERE))
APP = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app")
BINARY = os.path.join(APP, "Contents", "MacOS", "Reelcut")
SOURCES = os.path.join(ROOT, "app", "Sources")
FIXTURES = os.path.join(WORK, "recordingproof")
SHORT_VIDEO = os.path.join(FIXTURES, "short-video.mov")
PROBE_SOURCE = os.path.join(FIXTURES, "displayprobe.swift")
PROBE = os.path.join(FIXTURES, "displayprobe")
RECORDINGS = os.path.join(WORK, "recordings")
# The granted tier's files: the -RCRecordingFolder of the second instance,
# the detection call's `path`, the saved documents and the tone.
RUN = os.path.join(RECORDINGS, f"{os.getpid()}-files")
PROBE_FOLDER = os.path.join(RECORDINGS, f"{os.getpid()}-probe")
DOCS = os.path.join(RECORDINGS, f"{os.getpid()}-docs")
# The self-test's three WAVs, written and read through `wave` alone.
SELFTEST = os.path.join(RECORDINGS, f"{os.getpid()}-selftest")

SEC = 600_000

# The whole catalog after road map 3's R1: phase 9's 74 plus `record_screen`.
# The EXACT count belonged to this script when road map 3 wrote it
# (tools/proof/README.md's handover rule); `phase9_proof.py`'s 74 became a floor in the same
# commit that added the tool.
# Road map 5's E1 added `add_transition` and `set_transition_style`, so this
# is a FLOOR now and the exact count belongs to the newest phase's script —
# the rule `tools/proof/README.md` states, applied to this script the way
# phase 9's was applied to it. That script is road map 7's
# `op_argument_proof.py`, at 77.
TOOLS = 75

# `rc_op_names`' own length, asserted as the number of tools declaring
# `scope`. R1 adds NO op, so this is phase 9's number unmoved.
OPS = 55  # a floor too, for the same reason

# The twenty tools that are not §6 rows and therefore carry no `scope`,
# spelled out: an op tool that silently lost its scope would leave the count
# right and this set wrong, and vice versa. `record_screen` is the twentieth.
APP_STATE_TOOLS = {
    "open_project", "new_project", "save_project", "get_project", "import_media",
    "import_captions", "export_captions", "transcribe", "consolidate_media",
    "detect_silence", "normalize_clip", "set_playhead", "set_range", "set_selection",
    "set_scope", "undo", "redo", "render_frame", "export", "record_screen",
    "write_graphic", "get_graphic", "graphic_reference", "render_graphic",
    "import_graphic_font", "import_graphic_asset", "close_project",
}

# `record_screen`'s own arguments (road map 3, R1d), as declared; `project`
# is injected by `AgentCatalog.tool` for every tool and is asserted beside
# them.
RECORD_PROPERTIES = {
    "display", "window", "seconds", "microphone", "system_audio", "show_clicks", "rate",
    "size", "place", "path",
}

# `RecordingGrant.screenRecordingPaneSentence`, verbatim — the PREFIX of
# `screenRecordingRefusal`, which appends the launch clause (the launching
# process's pid) when the app was not started by launchd.
SCREEN_SENTENCE = (
    "Screen Recording is not granted to Reelcut. Turn it on in System Settings ▸ "
    "Privacy & Security ▸ Screen & System Audio Recording, then relaunch.")
# `RecordingGrant.microphoneRefusal`'s head, with the status word captured.
MIC_SENTENCE = re.compile(r"^The microphone is not granted to Reelcut \(status: (\w+)\)\. ")
MIC_STATUS_WORDS = {"notDetermined", "denied", "restricted"}
# The two fixes a microphone refusal names, followed (under a shell launch)
# by the launch clause — so the tail is matched as CONTAINED, not as the end.
MIC_FIX = {
    "notDetermined": "Press Record in File ▸ New Recording… once to grant it.",
}
MIC_FIX_DEFAULT = ("Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, then "
                   "relaunch.")
# `AgentServer.targetDocument`'s sentence for a `project` naming nothing.
NO_OPEN_PROJECT = re.compile(
    r"^No open project is at (.+)\. get_project reports the open project's path; "
    r"open_project opens another\.$")
# `AgentServer+RecordingArguments.recordingSource`'s sentence for a list
# with no display in it — a locked console, every display asleep.
NO_DISPLAY_SENTENCE = ("No display is shareable right now — the console is locked or every "
                       "display is asleep; nothing can be recorded until one is.")
# `AgentServer+RecordingResult.savedButNotAdded`'s shape — the ONE-segment
# sentence, byte for byte R1's; a paused recording's names every movie
# comma-joined in group 1, which no row here can produce (no tool pauses).
SAVED_BUT_NOT_ADDED = re.compile(
    r"^The recording was saved at (.+?\.mov)( and its microphone at (.+?\.m4a))? but could "
    r"not be added: (.+)$", re.DOTALL)
# The recorder's file name (`RecordingFiles.stem`), made unique with ` (n)`.
DATED_NAME = re.compile(
    r"^Screen Recording \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}( \(\d+\))?\.mov$")
# `segments[…].started_at`'s spelling (`AgentServer.startedAtFormatter`):
# ISO 8601 in UTC to the millisecond, with the Z.
STARTED_AT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")
# The fourteen keys one entry of `segments` may carry (R2d, and the fix
# wave's per-segment size): seven always — `path`, `duration`, `width`,
# `height`, `fps`, `started_at`, `mic_offset` — three on the microphone's
# terms, four ids when known.
SEGMENT_KEYS = {
    "path", "duration", "width", "height", "fps", "started_at", "mic_offset", "mic_path",
    "mic_duration", "mic_problem", "media", "clip", "mic_media", "mic_clip",
}
# What `undo` answers with nothing on the stack (`AgentServer+History.swift`).
NOTHING_TO_UNDO = "There is nothing to undo."
# `AgentServer+Render.swift`'s sentence, read the way every earlier script
# reads it.
FRAME_SENTENCE = re.compile(r"Written to (\S+\.png)\.")
# `AgentServer.start()`'s two NSLog lines: the bound port, and the startup
# parity check complaining — which must never appear.
BOUND_PORT = re.compile(r"listening on http://127\.0\.0\.1:(\d+)/mcp")
PARITY = "Reelcut: "
# Black, as ffmpeg's signalstats reports a video-range PNG rendered black.
BLACK_YAVG = 16.0
# `core/src/format.rs`'s cap, the one refusal in the placement's trial a
# script can reach.
MAX_TRACKS = 64

# The granted tier's rows, so a skip can report what it did not run: the
# recording rows of `granted_rows` (the launched instance's parity read and
# this constant's own self-check are beside them and not in it). Counted by
# hand and CHECKED against the live count when the tier runs, so the constant
# cannot go stale unnoticed. `MIC_CHECKS` is the microphone rows' own count,
# skipped separately. Rows a run may skip INSIDE a group (the fps row, the
# two tone rows, the head-trim row) are counted here and subtracted when
# they are skipped, so the self-check row still holds.
GRANTED_CHECKS = 44
MIC_CHECKS = 13
TONE_CHECKS = 2
# The detection call's own answer, read for R2d's one-segment shape before
# the second instance is launched; in the tier's promise, and in every
# skip of the tier.
DETECTION_CHECKS = 9

failures = []
checks = 0
skipped = []
# Every instance this run LAUNCHED, so the cleanup can never reach a process
# it did not start (`tools/proof/README.md`'s first rule).
launched = []
logs = {}


def check(ok_, what):
    global checks
    checks += 1
    if ok_:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def section(name, run, *args):
    """One section, isolated: a section that raises scores ONE failure and
    the run goes on — phase 7's idiom, for phase 7's reason (a crash is a
    worse detection than a failure, because every later section goes
    unrun)."""
    global checks
    print(f"\n{name}")
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — the point is to keep scoring
        checks += 1
        what = f"section {name.split(' ')[0]} ran to the end (raised {error!r})"
        print(f"  FAIL {what}")
        failures.append(what)


def skip(what, count):
    """A tier or a group of rows that could not run on this host, reported
    with the number of checks it would have made — never a vacuous pass."""
    print(f"  SKIP {what} — {count} checks not run")
    skipped.append((what, count))


def skipped_total():
    return sum(count for _, count in skipped)


def run_rows(name, promised, run, *args):
    """One group of the granted tier's rows, which promises `promised`
    checks. A group that raises scores ONE failure and the rows it never
    reached are reported as a skip — so the summary still says what did not
    run, and the tier's self-check can subtract it. Returns (checks of the
    promise that were NOT made — skipped inside or never reached, failures
    the raise added)."""
    before_checks, before_skipped = checks, skipped_total()
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — score it, then carry on
        check(False, f"the {name} ran to their end (raised {error!r})")
        made = checks - before_checks - 1
        inside = skipped_total() - before_skipped
        rest = max(0, promised - made - inside)
        skip(f"the rest of the {name}", rest)
        return inside + rest, 1
    return skipped_total() - before_skipped, 0


# ---- driving the server --------------------------------------------------


def call(mcp, tool, args):
    return mcp.call_with(tool, args)


def attempt(mcp, tool, args):
    """Both halves of a call: `(answer, None)` when it succeeded, `(None,
    message)` — the refusal with the tool's own prefix stripped — when it
    did not. For the one call whose ANSWER a later row reads when it lands
    (the detection call, R2d's shape rows)."""
    try:
        return mcp.call_with(tool, args), None
    except ToolError as error:
        text = str(error)
        prefix = f"{tool}: "
        return None, (text[len(prefix):] if text.startswith(prefix) else text)


def refusal(mcp, tool, args):
    """The refusal MESSAGE with the tool's own prefix stripped, or None when
    the call succeeded."""
    return attempt(mcp, tool, args)[1]


def parse_started_at(text):
    """`started_at` as a POSIX timestamp, or None when it is not a string
    that parses to an AWARE instant. `datetime.fromisoformat` reads the `Z`
    since Python 3.11; the replacement keeps the row honest on an older
    interpreter, where it would otherwise raise and the row would score
    the interpreter rather than the tool."""
    if not isinstance(text, str):
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.timestamp() if parsed.tzinfo is not None else None


def state(mcp, document=None):
    """`get_project`'s whole answer: the project and the view state around it."""
    return mcp.call_with("get_project", {"project": document} if document else {})


def project(mcp, document=None):
    found = state(mcp, document).get("project")
    if not isinstance(found, dict) or "tracks" not in found or "clips" not in found:
        raise RuntimeError(f"get_project did not answer a readable project: {found!r}")
    return found


def fingerprint(mcp, document=None):
    """The whole `get_project` answer as one string — the project AND the
    view state — for "was anything touched" and "did undo put it back"."""
    return json.dumps(state(mcp, document), sort_keys=True)


def frontmost_path(mcp):
    """The path of the document `get_project` answers for with no `project`
    — the frontmost one, `NSApp.orderedDocuments`'s first."""
    found = state(mcp).get("project")
    return found.get("path") if isinstance(found, dict) else None


def new_document(mcp, name):
    """A saved document, `<name>-<pid>.reelcut` under `DOCS`, so every later
    call can name it by `project`: an untitled draft has no path, and the
    granted instance holds several documents at once."""
    os.makedirs(DOCS, exist_ok=True)
    path = os.path.join(DOCS, f"{name}-{os.getpid()}.reelcut")
    if os.path.exists(path):
        shutil.rmtree(path)
    mcp.call_with("new_project", {"path": path})
    return path


def render(mcp, document, t):
    """`render_frame` at `t`, as the PNG's path."""
    answer = str(mcp.call_with("render_frame", {"project": document, "t": int(t)}))
    found = FRAME_SENTENCE.search(answer)
    if not found:
        raise RuntimeError(f"render_frame said something else: {answer[:200]}")
    return found.group(1)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def read(path):
    with open(path, "rb") as handle:
        return handle.read()


def source(name):
    """One file of `app/Sources`, as text, for the structural reads."""
    return read(os.path.join(SOURCES, name)).decode("utf-8")


def code(text):
    """`text` without its comment lines — for a read that the CODE must
    fail to contain, which a doc comment naming the absent thing would
    otherwise satisfy."""
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("//"))


def parity_lines(path):
    """The startup parity check's complaints in one log, if any."""
    if not os.path.exists(path):
        return None
    return [line for line in read(path).decode("utf-8", "replace").splitlines()
            if PARITY in line]


def luma_average(png):
    """ffmpeg's `signalstats` YAVG of one frame: 16.0 for a black PNG."""
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", png, "-vf", "signalstats,metadata=print:file=-",
         "-f", "null", "-"],
        capture_output=True, text=True)
    found = re.search(r"lavfi\.signalstats\.YAVG=([0-9.]+)", out.stdout + out.stderr)
    return float(found.group(1)) if found else None


# ---- an instance of this build, launched and killed by this script -------
#
# `phase8_proof.py`'s `Instance` (its lines 351–397), copied rather than
# imported for the reason that file gives — a proof script's instruments
# travel with it. Two tokens differ: the log's tag says `recording`, and the
# client takes this script's longer timeout, because a `record_screen`
# blocks for its whole recording.


class Instance:
    """One Reelcut launched BY THIS SCRIPT, on a port of its own.

    No proof script in this tree had ever launched the app before phase 8,
    and this one does it for one reason: `PreviewQuality` is read from
    `UserDefaults` at `Playback.init` and there is no tool that sets it, so
    the only way a proof can put a quality into a running Reelcut is the
    argument domain at launch. `-ApplePersistenceIgnoreState` and
    `-AgentServerEnabled` already travel that way (CLAUDE.md's launch line);
    this adds one more argument to the same list.

    **It kills only what it started.** `subprocess.Popen`'s own pid, SIGTERM
    then SIGKILL, and nothing in this file ever reads `pgrep` — another
    session's instance is none of its business (`tools/proof/README.md`)."""

    def __init__(self, tag, port, extra=()):
        self.tag = tag
        self.log = f"/tmp/reelcut-recording-{tag}-{os.getpid()}.log"
        logs[tag] = self.log
        self.handle = open(self.log, "wb")
        env = dict(os.environ, RC_AGENT_PORT=str(port))
        self.process = subprocess.Popen(
            [BINARY, "-ApplePersistenceIgnoreState", "YES", "-AgentServerEnabled", "YES",
             *extra],
            stdout=self.handle, stderr=subprocess.STDOUT, env=env)
        launched.append(self)
        self.port = self._await_port()
        self.mcp = MCP(self.port, timeout=180)

    def _await_port(self, seconds=45):
        """The port the instance actually bound, off its own log."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(
                    f"the {self.tag} instance exited with {self.process.returncode} before "
                    f"it bound a port — {self.log}")
            found = BOUND_PORT.search(read(self.log).decode("utf-8", "replace"))
            if found:
                return int(found.group(1))
            time.sleep(0.2)
        raise RuntimeError(f"the {self.tag} instance never named a port in {self.log}")

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            deadline = time.time() + 10
            while time.time() < deadline and self.process.poll() is None:
                time.sleep(0.2)
            if self.process.poll() is None:
                self.process.send_signal(signal.SIGKILL)
                self.process.wait(timeout=10)
        self.handle.close()


def stop_launched():
    for instance in launched:
        try:
            instance.stop()
        except Exception as error:  # noqa: BLE001 — cleanup must not raise
            print(f"  (could not stop the {instance.tag} instance: {error!r})")


# ---- 0. the catalog ------------------------------------------------------


def catalog_part(mcp):
    listed = mcp.schemas().values()
    names = {tool["name"] for tool in listed}
    check(len(names) >= TOOLS,
          f"the catalog holds at least road map 3's {TOOLS} tools (got {len(names)}) — phase "
          "9's 74 plus record_screen; the exact count belongs to the newest phase's script, "
          "and this one became a floor when road map 5's E1 added two")
    check("record_screen" in names, "record_screen is among them")

    schemas = {tool["name"]: tool["inputSchema"] for tool in listed}
    schema = schemas.get("record_screen", {"properties": {}})
    declared = set(schema.get("properties", {}))
    check(declared == RECORD_PROPERTIES | {"project"},
          "record_screen declares exactly its ten arguments plus the injected project: "
          f"{sorted(declared - RECORD_PROPERTIES - {'project'})} unexpected, "
          f"{sorted((RECORD_PROPERTIES | {'project'}) - declared)} missing")
    check(schema.get("required") == ["seconds"],
          f"and requires seconds alone (got {schema.get('required')})")
    check("scope" not in declared,
          "and declares NO scope — it is an app-state tool, not a §6 op, and the parity "
          "check's fourth part reads op tools only; a later phase that starts demanding a "
          "scope of app-state tools fails loudly here")
    for name, kind in (("seconds", "number"), ("display", "integer"), ("window", "integer"),
                       ("rate", "integer"), ("size", "string"), ("path", "string"),
                       ("microphone", "boolean"), ("system_audio", "boolean"),
                       ("show_clicks", "boolean"), ("place", "boolean")):
        check(schema["properties"].get(name, {}).get("type") == kind,
              f"{name} is declared {kind}")
    check(schema["properties"].get("rate", {}).get("enum") == [30, 60],
          "rate's enum is [30, 60]")
    check(schema["properties"].get("size", {}).get("enum") == ["nominal", "best"],
          "size's enum is [nominal, best]")
    description = [tool for tool in listed if tool["name"] == "record_screen"][0]["description"]
    for phrase in ("File ▸ New Recording…", "Reelcut Recordings", "new_project", "Microphone",
                   "REFUSAL ORDER", "mic_problem", "Add Microphone", "launching process",
                   "Stop Recording", "The recording was saved at",
                   # R2d: the status item's two menus and the undo step a
                   # paused recording's remainder is named by.
                   "Pause Recording", "Resume Recording", "Add Recording Segments"):
        check(phrase in description, f"the description says \"{phrase}\"")
    for key in ("path", "mic_path", "mic_duration", "mic_offset", "mic_problem", "media",
                "mic_media", "clip", "mic_clip", "duration", "width", "height", "fps",
                "has_audio", "audio_tracks", "stopped_by", "landed", "note", "project",
                "new_media", "new_clips", "new_tracks", "scope", "document_ops",
                # R2d's three: the two keys always present, and the one only a
                # segment carries.
                "pauses", "segments", "started_at",
                # Issue batch B17 (#97): present only when a segment was left out.
                "unreadable"):
        check(re.search(rf"(?<![a-z_]){re.escape(key)}(?![a-z_])", description) is not None,
              f"…and names the result key {key}")

    scoped = sorted(
        tool["name"] for tool in listed
        if "scope" in (tool["inputSchema"].get("properties") or {}))
    check(len(scoped) >= OPS,
          f"at least {OPS} tools declare the envelope's scope (got {len(scoped)}) — R1 adds "
          "no op, and the exact number is the newest phase's to assert")
    check(names - set(scoped) - set(DEV_TOOLS) == APP_STATE_TOOLS,
          "and the tools WITHOUT one are exactly the twenty-seven app-state tools (the dev "
          "tools apart), named: "
          f"{sorted(names - set(scoped) - set(DEV_TOOLS) - APP_STATE_TOOLS)} unexpected, "
          f"{sorted(APP_STATE_TOOLS - (names - set(scoped)))} missing")

    complaints = parity_lines(LOG)
    check(complaints == [],
          f"the startup parity check logged nothing to {LOG} "
          f"({'no such log' if complaints is None else len(complaints)} lines)")


# ---- 1. the refusals, exact and in order ---------------------------------


def refusal_part(mcp):
    document = new_document(mcp, "refusals")
    before = fingerprint(mcp, document)

    def refused(args, expected, why):
        message = refusal(mcp, "record_screen", dict(args, project=document))
        ok_ = message == expected
        check(ok_, f"{json.dumps(args)} → {why}: {message!r}")
        return message

    refused({}, "Missing required argument: seconds", "seconds absent is refused by name")
    refused({"seconds": 0}, "seconds must be 1…600 (got 0).", "seconds 0 is out of range")
    refused({"seconds": 601}, "seconds must be 1…600 (got 601).", "seconds 601 is out of range")
    refused({"seconds": "x"}, "seconds must be a number.", "a non-number is refused by type")
    refused({"seconds": 2, "display": 0, "window": 5},
            "Pass display or window, not both — a recording is of one or the other.",
            "display and window together are refused")
    refused({"seconds": 2, "rate": 24}, "rate must be 30 or 60 (got 24).",
            "rate 24 is refused listing both")
    refused({"seconds": 2, "size": "huge"}, 'size must be one of nominal, best (got "huge").',
            "size huge is refused listing both")
    refused({"seconds": 2, "display": -1}, "display must be 0 or more (got -1).",
            "a negative display index is refused before any lookup")

    # A `project` naming nothing open: `target(_:)`'s own sentence, which
    # must STAND — never a silent fall-through to a fresh document. The
    # frontmost document is read before and after: a build that fell
    # through would open a new one in front, and no media list could see
    # that (the old row read a document nothing adds to).
    front_before = frontmost_path(mcp)
    asked = time.monotonic()
    message = refusal(mcp, "record_screen", {"seconds": 2, "project": "/nowhere/x.reelcut"})
    elapsed = time.monotonic() - asked
    check(message is not None and NO_OPEN_PROJECT.match(message)
          and "/nowhere/x.reelcut" in message,
          f"a project naming nothing open is refused by name, and stands: {message!r}")
    # Measured on this instance: `NSApp.orderedDocuments.first` is the
    # launch-time untitled document whatever is opened later (an agent-driven
    # app is never active, so no window it makes is ever ordered front), so
    # the frontmost path alone cannot see a fresh document. What can: a
    # fall-through has to RECORD for the 2 s span before it could open one,
    # and a by-name refusal answers in a millisecond (measured 0.001 s).
    front_after = frontmost_path(mcp)
    check(elapsed < 1.0 and front_after == front_before,
          f"…and it answered in {elapsed:.3f} s — under a second, so nothing was recorded "
          f"into a fresh document, which would have taken the 2 s span — with the frontmost "
          f"document unchanged ({front_before!r} → {front_after!r})")

    # The ORDER. Each row pairs the caller's own mistake with a later-stage
    # refusal and must answer the earlier one. The `display: 99` rows are
    # the ones that bite on a GRANTED host: only the lookup can see 99.
    refused({"seconds": 0, "display": 99, "rate": 24, "size": "huge", "microphone": True},
            "seconds must be 1…600 (got 0).",
            "ORDER: seconds 0 wins over a bad rate, size, microphone and a display only "
            "the lookup can refuse")
    refused({"seconds": 601, "display": 99}, "seconds must be 1…600 (got 601).",
            "ORDER: seconds 601 wins over display 99")
    refused({"seconds": 2, "rate": 24, "display": 99}, "rate must be 30 or 60 (got 24).",
            "ORDER: rate 24 wins over display 99")
    refused({"seconds": 2, "size": "huge", "display": 99},
            'size must be one of nominal, best (got "huge").',
            "ORDER: size huge wins over display 99")
    message = refusal(mcp, "record_screen",
                      {"seconds": 2, "rate": 24, "project": "/nowhere/x.reelcut"})
    check(message == "rate must be 30 or 60 (got 24).",
          f"ORDER: rate 24 wins over a project naming nothing: {message!r}")
    message = refusal(mcp, "record_screen",
                      {"seconds": 2, "display": 99, "project": "/nowhere/x.reelcut"})
    check(message is not None and NO_OPEN_PROJECT.match(message) is not None,
          f"ORDER: the project's by-name refusal wins over display 99 — the target is "
          f"resolved above the grant and the lookup: {message!r}")

    # The microphone, conditional on the host and never recording: with the
    # grant absent its sentence comes first; with it, the project refusal
    # is what shows the check was passed rather than skipped.
    message = refusal(mcp, "record_screen",
                      {"seconds": 2, "microphone": True, "project": "/nowhere/x.reelcut"})
    named = MIC_SENTENCE.match(message or "")
    if named:
        word = named.group(1)
        check(word in MIC_STATUS_WORDS,
              f"the Microphone grant is absent here and the refusal NAMES the framework's "
              f"status word: {word}")
        fix = MIC_FIX.get(word, MIC_FIX_DEFAULT)
        check(fix in message,
              f"…and names the fix for {word} (the launch clause may follow it): {message!r}")
        check(refusal(mcp, "record_screen",
                      {"seconds": 0, "microphone": True, "project": "/nowhere/x.reelcut"})
              == "seconds must be 1…600 (got 0).",
              "ORDER: seconds 0 wins over the microphone grant")
    else:
        check(message is not None and NO_OPEN_PROJECT.match(message) is not None,
              "the Microphone grant is authorized for this shell, so microphone: true is "
              f"NOT refused at the argument stage and the project refusal follows: "
              f"{message!r}")
        check(not (message or "").startswith("The microphone is not granted"),
              "…and the answer is not the microphone sentence")
        check(refusal(mcp, "record_screen",
                      {"seconds": 0, "microphone": True, "project": "/nowhere/x.reelcut"})
              == "seconds must be 1…600 (got 0).",
              "ORDER: seconds 0 wins over the microphone stage either way")

    # A window id nothing carries, and a display past the list, are answered
    # by the LOOKUP, which needs the grant: with it, the lookup's sentence
    # (or, on a console with no display, the no-display sentence); without
    # it, the grant's, matched as a prefix because the launch clause may
    # follow. Either is a named refusal and neither records.
    for args, own in (({"seconds": 2, "window": 4294967295},
                       re.compile(r"^No window with id 4294967295 is shareable\.$")),
                      ({"seconds": 2, "display": 99},
                       re.compile(r"^display must be 0…\d+ \(got 99\); \d+ displays? (is|are) "
                                  r"shareable\.$"))):
        message = refusal(mcp, "record_screen", dict(args, project=document))
        check(message is not None
              and (message.startswith(SCREEN_SENTENCE) or own.match(message)
                   or message == NO_DISPLAY_SENTENCE),
              f"{json.dumps(args)} is refused by the lookup's own sentence, or by the grant's "
              f"where the grant is absent: {message!r}")

    check(fingerprint(mcp, document) == before,
          "every refusal left get_project's whole answer byte-identical")
    undone = refusal(mcp, "undo", {"project": document})
    check(undone is not None and undone.startswith(NOTHING_TO_UNDO),
          f"and pushed no undo step: {undone!r}")


# ---- 2. the held last frame (lane E), which needs no grant ---------------


def ffmpeg_runs():
    """Whether `ffmpeg -version` runs, and why not (issue batch B27, #181):
    `(True, <its first line>)`, else `(False, <why>)` — not on PATH, the exit
    code with its first non-empty stderr line (a missing dylib), or no
    answer within 30 s. On PATH is not enough: a broken install is there
    and cannot run."""
    try:
        ran = subprocess.run(["ffmpeg", "-version"], capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        return False, "not on PATH"
    except subprocess.TimeoutExpired:
        return False, "did not answer -version within 30 s"
    if ran.returncode != 0:
        line = next((l.strip() for l in ran.stderr.splitlines() if l.strip()), "")
        return False, f"exited {ran.returncode}: {line}"
    return True, (ran.stdout.splitlines() or [""])[0]


def fixture_part(mcp):
    ok, why = ffmpeg_runs()
    check(ok, f"ffmpeg runs (`ffmpeg -version`: {why}) — tools/proof/README.md: needed at proof "
              f"time; the fixture rows cannot run without it")
    if not ok:
        return
    os.makedirs(FIXTURES, exist_ok=True)
    made = subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-t", "1", "-i",
         "testsrc2=size=640x360:rate=30", "-f", "lavfi", "-t", "5", "-i",
         "sine=frequency=440:sample_rate=48000", "-map", "0:v", "-map", "1:a", "-c:v",
         "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", SHORT_VIDEO],
        capture_output=True, text=True)
    check(made.returncode == 0 and os.path.exists(SHORT_VIDEO),
          f"ffmpeg wrote the fixture: 1 s of testsrc2 over 5 s of a 440 Hz sine, no "
          f"-shortest ({made.stderr.strip()[:120]!r})")
    opened = mcp.call_with("open_project", {"path": SHORT_VIDEO})
    summary = opened["project"]
    check(summary["path"] == SHORT_VIDEO and summary["clips"] == 1,
          "open_project made an untitled document around it with one clip, addressable by "
          "the movie's path")
    # About 5 s, not exactly: AAC's encoder trims the tail (measured 4.967 s
    # here, one 30 fps frame short), and what matters is that the document
    # runs to the SOUND's end, four seconds past the picture's.
    check(4.9 * SEC <= summary["duration"] <= 5 * SEC and summary["fps"] == [30, 1],
          f"the document runs to the sound's end, about 5 s, at 30 fps: {summary['duration']} "
          f"ticks, {summary['fps']}")
    reported = project(mcp, SHORT_VIDEO)
    clip = reported["clips"][0]["id"]
    media = reported["media"][0]
    check(4.9 * SEC <= media["duration"] <= 5 * SEC and media["has_video"]
          and media["has_audio"],
          f"and the media record reads the asset's length with both tracks: "
          f"{media['duration']} ticks")
    before = fingerprint(mcp, SHORT_VIDEO)

    # (1) Three frames: the last real frame, and two past the video track's
    # end that must HOLD it rather than go black.
    frames = {t: render(mcp, SHORT_VIDEO, t) for t in (594_000, 1_800_000, 2_940_000)}
    hashes = {t: digest(path) for t, path in frames.items()}
    check(len(set(hashes.values())) == 1,
          "render_frame at 0.99 s, 3 s and 4.9 s are byte-identical PNGs — the 1 s video "
          "track's last frame is held to the end of the 5 s sound")
    yavg = luma_average(frames[1_800_000])
    check(yavg is not None and abs(yavg - BLACK_YAVG) > 1.0,
          f"and the held frame is not black (signalstats YAVG {yavg}, black is {BLACK_YAVG})")
    held = hashes[594_000]

    # (2) A trim whose in point is past the video's end: every frame held.
    mcp.call_with("trim_start", {"project": SHORT_VIDEO, "clip": clip, "to": 1_200_000})
    trimmed = digest(render(mcp, SHORT_VIDEO, 1_200_000))
    check(trimmed == held,
          "after trim_start to 2 s the frame at 2 s (source 2 s, past the picture) equals "
          "the 0.99 s frame")
    mcp.call_with("undo", {"project": SHORT_VIDEO})
    check(fingerprint(mcp, SHORT_VIDEO) == before, "undo restored the project")

    # (3) At double speed the hold sits under the speed step: 2.4 s is source
    # 4.8 s (held), 0.4 s is source 0.8 s (frame 24, a different picture).
    mcp.call_with("set_speed", {"project": SHORT_VIDEO, "clip": clip, "rate": 2.0})
    fast_tail = digest(render(mcp, SHORT_VIDEO, 1_440_000))
    check(fast_tail == held,
          "at speed 2.0 the frame at 2.4 s (source 4.8 s) equals the 0.99 s frame — the "
          "hold is applied BEFORE the speed scaling")
    early = render(mcp, SHORT_VIDEO, 240_000)
    early_hash = digest(early)
    early_yavg = luma_average(early)
    check(early_hash != held,
          "…while the frame at 0.4 s (source 0.8 s, frame 24 of testsrc2) is a different "
          "picture")
    check(early_yavg is not None and abs(early_yavg - BLACK_YAVG) > 1.0,
          f"and not black either (YAVG {early_yavg})")
    mcp.call_with("undo", {"project": SHORT_VIDEO})
    check(fingerprint(mcp, SHORT_VIDEO) == before, "undo restored the project again")


# ---- 3. the tool's source, read where no call can reach -------------------


def source_part():
    tool = source("AgentServer+Recording.swift")
    arguments = source("AgentServer+RecordingArguments.swift")
    result = source("AgentServer+RecordingResult.swift")

    check("static func stopCeiling(segments: Int) -> TimeInterval" in tool
          and "ScreenRecorder.finishCeiling + 2 * 30 * TimeInterval(max(segments, 1)) + 5"
          in tool,
          "the stop wait is `stopCeiling(segments:)` = finishCeiling + 2 × 30 × max(n, 1) + 5 "
          "(75 s unpaused, 60 s more per further segment), derived from the recorder's finish "
          "ceiling and two sequential probe ceilings PER SEGMENT, independent of seconds — "
          "R2's review found a fixed 75 s shorter than two segments' probes")
    check("Self.stopCeiling(segments: segments)" in tool and ".now() + seconds + 30" not in tool
          and "static let stopCeiling" not in tool,
          "…and the wait after stop() reads it over the segment count — the old "
          "`.now() + seconds + 30` and the fixed constant are both gone")
    check("mid-finish is `.busy`" not in tool and "`.busy` by contract" not in tool
          and "JOINS the finishing" in tool,
          "the header no longer claims a second stop() mid-finish is .busy — it says it joins")
    # R2d: the item takes THREE closures now; R1's one-closure literal is the
    # text that moved.
    chrome = source("AgentServer+RecordingChrome.swift").split("final class RecordingToolChrome")[1]
    check("RecorderStatusItem(" in chrome and "onPause:" in chrome and "onResume:" in chrome
          and ("onStop: { [weak self] in\n                self?.freeze()\n"
               "                ScreenRecorder.shared.stop()\n            })") in chrome
          and "func freeze() { item?.freeze() }" in chrome
          and "forMode: .common" in chrome,
          "a recording the tool starts gets a RecorderStatusItem with three closures — "
          "onPause, onResume and a Stop that FREEZES the item's mark and time and then is "
          "the recorder's own stop() — ticked by a timer in .common modes")
    check("_ = try? ScreenRecorder.shared.pause()" in chrome
          and "_ = try? ScreenRecorder.shared.resume()" in chrome,
          "…whose Pause and Resume are the recorder's pause() / resume() under try? — the "
          "one refusal possible is a race with the recording's own end, with no panel to "
          "say it in")
    check("item.update(elapsed: recorder.elapsed, paused: recorder.isPaused)" in chrome,
          "…and the tick passes the recorder's elapsed (frozen while paused) and isPaused "
          "into the item, so the menu flips with the state")
    check("chrome.remove()" in tool.split("let deliver")[1].split("finished.signal()")[0],
          "…and the item comes down inside onFinish, before the landing")
    check(tool.count("Self.recordingAlertClause") >= 1
          and result.count("recordingAlertClause") >= 3,
          "the tool's start timeout, its finish timeout sentence and the recorder's own "
          "start timeout all carry the system-alert clause")
    check("RecorderPanelController.landingRetryLimit" in tool
          and "RecorderPanelController.landingRetryInterval" in tool
          and "Thread.sleep" in tool,
          "the wait for a live drag is bound to the panel's own limit and interval BY NAME, "
          "and sleeps on the server thread rather than on main")
    check(tool.count("Self.savedButNotAdded(result, error)") == 3,
          "all three post-record throw sites — the placement, the commit, the untitled "
          "document — go through savedButNotAdded")
    # R2d: the finish timeout names EVERY segment's movie, and the sentence
    # is pluralised by count — with one movie it is R1's, byte for byte.
    check("static func finishTimeoutSentence(movies: [String])" in result
          and "Self.finishTimeoutSentence(movies: movies)" in tool
          and "recorder.session?.segments.map(\\.movieURL.path)" in tool
          and "let count = recorder.session?.segments.count ?? 1" in tool
          and "session?.movieURL" not in tool,
          "the finish timeout reads the session's SEGMENTS — their count for the ceiling, "
          "their movies for the sentence — and the single movieURL R1 read is gone from the "
          "tool")
    timeout = result.split("static func finishTimeoutSentence")[1].split("\n    }\n")[0]
    check("case 1:" in timeout and "its movie is at \\(movies[0])." in timeout
          and "its movies are at " in timeout and 'movies.joined(separator: ", ")' in timeout
          and "stopCeiling(segments: movies.count)" in timeout,
          "…and its sentence is pluralised by count and states the ceiling it waited, sized "
          "by the same count: one movie spelled as R1 spelled it, several comma-joined")
    saved = result.split("static func savedButNotAdded")[1].split("\n    }\n")[0]
    clause = source("RecordingResult.swift").split("var filesClause")[1].split("\n    }\n")[0]
    check("The recording was saved at \\(result.filesClause) but could " in saved
          and 'segments.map { $0.descriptor.path }.joined(separator: ", ")' in clause
          and "segments.compactMap { $0.micDescriptor?.path }" in clause
          and '" and its microphone at " + mics[0]' in clause
          and '" and its microphone files at " + mics.joined(separator: ", ")' in clause,
          "savedButNotAdded builds over RecordingResult.filesClause — EVERY segment's movie, "
          "comma-joined, then every microphone file that landed, singular for one — so the "
          "one-segment sentence is byte for byte R1's, the shape section 5's full-document "
          "row matches live")
    # R2d: the two keys are written unconditionally, each segment through
    # `segmentFields`, and `duration` is the sum.
    fields = result.split("static func recordingFields")[1].split("\n    }\n")[0]
    check('"pauses": result.pauses, "segments": segments' in fields
          and "segmentFields(segment, ids:" in fields
          and "static func segmentFields" in result
          and '"started_at": startedAtFormatter.string(from: segment.startedAt)' in result,
          "the result writes pauses and segments in its literal — always present — with each "
          "entry built by segmentFields, which writes started_at")
    formatter = result.split("static let startedAtFormatter")[1].split("}()")[0]
    check(".withInternetDateTime" in formatter and ".withFractionalSeconds" in formatter
          and "TimeZone(secondsFromGMT: 0)" in formatter,
          "started_at's formatter is ISO 8601 with fractional seconds, pinned to UTC")
    check("let total = result.segments.reduce(Ticks(0)) { $0 + $1.descriptor.duration }"
          in fields and '"duration": total' in fields,
          "duration is the SUM over the segments — the read is here because one segment "
          "cannot tell the total from the first's over MCP")
    check("result.micDescriptor" not in code(result) and "result.micOffset" not in code(result)
          and "result.micDescriptor" not in code(tool) and "result.micOffset" not in code(tool)
          and "first.micOffset" in fields and "first.micDescriptor" in fields,
          "neither file's CODE reads a result-level micDescriptor or micOffset — the top "
          "level's are the FIRST segment's (R2a: the convenience deliberately does not exist, "
          "so a reader compiled against it would be wrong for a paused recording)")
    check('fields["mic_problem"] = problem' in result and "microphoneNote" in result,
          "the result carries mic_problem and the note mentions it")
    check("The recording was saved at" in result and "but could not "
          in result and "be added: " in result,
          "savedButNotAdded's sentence names the file and carries the inner error")
    lookup = arguments.split("throws -> RecordingSource {")[1]
    no_display = lookup.find(NO_DISPLAY_SENTENCE.split(" — ")[0])
    range_sentence = lookup.find("display must be 0…")
    check(0 <= no_display < range_sentence,
          "an empty display list is refused by the no-display sentence BEFORE the range "
          "sentence")
    folder = arguments.split("func recordingFolder")[1].split("\n    }\n")[0]
    check("trimmingCharacters" in folder and "isEmpty" in folder,
          "path is trimmed and an empty string counts as absent")
    check("stopReasonName" in result and "newProjectIds" in result
          and "func recordingFields" not in tool,
          "the result shaping lives in +RecordingResult.swift and not in the tool file")


# ---- 4. the tone arithmetic, self-tested --------------------------------


def tone_share(samples, rate=48_000, frequency=1000.0):
    """The 1 kHz SHARE of a signal on Parseval's scale: a Goertzel filter
    run un-normalised gives |X[k]|², and Σ|x|² = (1/n)·Σ|X[k]|², so the
    share of the total in the pair of bins ±k is 2·|X[k]|² / (n·Σ|x|²) — a
    pure tone is 1.0, white noise about 2/n, silence 0. `n` is truncated to
    a multiple of 48 so 1000 Hz sits exactly on bin n/48 and leaks into
    nothing. None for no samples."""
    n = len(samples) - len(samples) % 48
    if n == 0:
        return None
    k = int(round(n * frequency / rate))
    coeff = 2 * math.cos(2 * math.pi * k / n)
    s1 = s2 = 0.0
    total = 0.0
    for raw in samples[:n]:
        x = raw / 32768.0
        total += x * x
        s0 = x + coeff * s1 - s2
        s2, s1 = s1, s0
    g = s1 * s1 + s2 * s2 - coeff * s1 * s2
    return {"rms": math.sqrt(total / n), "share": 2 * g / (n * total) if total > 0 else 0.0}


def wav_samples(path):
    """A 16-bit mono WAV's samples, through the `wave` module."""
    with wave.open(path) as w:
        n = w.getnframes()
        return struct.unpack(f"<{n}h", w.readframes(n))


def write_wav(path, samples, rate=48_000):
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(b"".join(struct.pack("<h", s) for s in samples))


def selftest_part():
    os.makedirs(SELFTEST, exist_ok=True)
    n = 48_000 + 17  # not a multiple of 48, so the truncation is exercised
    rng = random.Random(7)
    trio = {
        "sine": [int(16_383 * math.sin(2 * math.pi * 1000 * i / 48_000)) for i in range(n)],
        "noise": [rng.randint(-16_383, 16_383) for _ in range(n)],
        "silence": [0] * n,
    }
    shares = {}
    for name, samples in trio.items():
        path = os.path.join(SELFTEST, f"{name}.wav")
        write_wav(path, samples)
        shares[name] = tone_share(wav_samples(path))
    sine, noise, silence = shares["sine"], shares["noise"], shares["silence"]

    def spelled(measured, key, spec):
        return format(measured[key], spec) if measured is not None else "?"

    check(sine is not None and abs(sine["share"] - 1.0) < 0.01,
          f"a 1 kHz sine at −6 dBFS has a 1 kHz share of about 1 (share "
          f"{spelled(sine, 'share', '.6f')}, RMS {spelled(sine, 'rms', '.3f')})")
    check(noise is not None and noise["share"] < 0.01,
          f"white noise has a share under 0.01 (share {spelled(noise, 'share', '.2e')})")
    check(silence is not None and silence["share"] == 0.0 and silence["rms"] == 0.0,
          f"silence has a share of exactly 0 (share {spelled(silence, 'share', 'g')})")
    shutil.rmtree(SELFTEST, ignore_errors=True)


# ---- the granted tier ----------------------------------------------------


DISPLAY_PROBE = '''import AppKit
import CoreAudio
import ScreenCaptureKit
// The host's facts under this terminal's grant, for recording_proof.py:
// the preflight, the session's lock state, the main display's point size
// and backing scale, how many displays ScreenCaptureKit will share, and the
// default OUTPUT device with its transport — because the system-audio tap
// delivered digital silence for a Bluetooth output (measured 2026-09-11,
// AirPods Max: afplay and say both playing, the recording all zeros) where
// the built-in speakers had given R0's unity tone.
func outputDevice() -> (name: String, transport: String) {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                     &size, &device) == noErr, device != 0 else {
        return ("?", "?")
    }
    var name: CFString = "?" as CFString
    var nameSize = UInt32(MemoryLayout<CFString>.size)
    address.mSelector = kAudioObjectPropertyName
    _ = withUnsafeMutablePointer(to: &name) {
        AudioObjectGetPropertyData(device, &address, 0, nil, &nameSize, $0)
    }
    var transport = UInt32(0)
    var transportSize = UInt32(MemoryLayout<UInt32>.size)
    address.mSelector = kAudioDevicePropertyTransportType
    _ = AudioObjectGetPropertyData(device, &address, 0, nil, &transportSize, &transport)
    let code = String(bytes: [24, 16, 8, 0].map { UInt8((transport >> $0) & 0xff) },
                      encoding: .macOSRoman) ?? "?"
    return (name as String, code)
}
let output = outputDevice()
let id = CGMainDisplayID()
let bounds = CGDisplayBounds(id)
var scale = 1.0
if let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 {
    scale = Double(mode.pixelWidth) / Double(mode.width)
}
var locked = false
if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
    locked = (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
}
let done = DispatchSemaphore(value: 0)
var displays = -1
var failure = ""
SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
    displays = content?.displays.count ?? -1
    if let error { failure = "\\(error.localizedDescription)" }
    done.signal()
}
let answered = done.wait(timeout: .now() + 20) == .success
let facts: [String: Any] = [
    "preflight": CGPreflightScreenCaptureAccess(), "locked": locked,
    "width": Int(bounds.width), "height": Int(bounds.height), "scale": scale,
    "displays": displays, "answered": answered, "failure": failure,
    "asleep": CGDisplayIsAsleep(id) != 0,
    "output": output.name, "transport": output.transport,
]
let data = try JSONSerialization.data(withJSONObject: facts)
print(String(decoding: data, as: UTF8.self))
'''


def display_probe():
    """The host's facts, from a probe compiled once and cached on its own
    mtime. None when it will not build, which the caller scores."""
    os.makedirs(FIXTURES, exist_ok=True)
    if not os.path.exists(PROBE_SOURCE) or read(PROBE_SOURCE).decode() != DISPLAY_PROBE:
        with open(PROBE_SOURCE, "w") as handle:
            handle.write(DISPLAY_PROBE)
    if (not os.path.exists(PROBE)
            or os.path.getmtime(PROBE) < os.path.getmtime(PROBE_SOURCE)):
        sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                             capture_output=True, text=True).stdout.strip()
        built = subprocess.run(
            ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", PROBE_SOURCE, "-o",
             PROBE], capture_output=True, text=True)
        if built.returncode != 0:
            print(built.stderr[:800])
            return None
    out = subprocess.run([PROBE], capture_output=True, text=True, timeout=60)
    try:
        return json.loads(out.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        print(out.stdout[:400], out.stderr[:400])
        return None


def responsible_application(pid=None):
    """The ancestor of `pid` (this process by default) that launchd started
    — the application whose grants a shell-launched Reelcut runs under
    (R0 q1). "?" for a pid that cannot be walked."""
    pid = os.getpid() if pid is None else pid
    name = "?"
    for _ in range(32):
        out = subprocess.run(["ps", "-o", "ppid=,comm=", "-p", str(pid)],
                             capture_output=True, text=True).stdout.split(None, 1)
        if len(out) < 2:
            break
        parent, comm = int(out[0]), out[1].strip()
        name = comm
        if parent <= 1:
            break
        pid = parent
    return name


def listening_pid(port):
    """The pid listening on `port` — the instance this script was handed,
    which it did not launch and never touches; `lsof` is a READ."""
    try:
        out = subprocess.run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
                             capture_output=True, text=True, timeout=20).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None
    return int(out[0]) if out else None


def size_matches(width, height, host, best):
    """The display's point size (pixels under `best`), allowing +1 on an odd
    dimension: the H.264 writer rounds up to even (R0 q4: 1117 → 1118)."""
    factor = host["scale"] if best else 1
    want_w, want_h = round(host["width"] * factor), round(host["height"] * factor)
    even = lambda want, got: got == want or (want % 2 == 1 and got == want + 1)
    return even(want_w, width) and even(want_h, height)


def write_tone(path, seconds=4.0, frequency=1000.0, rate=48_000):
    """A 1 kHz sine at −6 dBFS, mono 16-bit — enough to be heard through
    the system-audio capture at unity."""
    write_wav(path, [int(16_383 * math.sin(2 * math.pi * frequency * n / rate))
                     for n in range(int(seconds * rate))], rate)


WIRELESS_TRANSPORTS = {"blue": "a Bluetooth device", "blea": "a Bluetooth LE device",
                       "airp": "an AirPlay destination"}


def tone_power(path):
    """The recording decoded to mono 48 kHz PCM through `ffmpeg` and measured
    by `tone_share`. None when it cannot be decoded."""
    pcm = os.path.join(RUN, "tone-measure.wav")
    try:
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", path, "-ac", "1", "-ar",
                        "48000", "-f", "wav", pcm], check=True, capture_output=True,
                       timeout=120)
        samples = wav_samples(pcm)
    except (OSError, subprocess.SubprocessError, wave.Error, struct.error):
        return None
    return tone_share(samples)


def pcm_failure(silent, loud):
    """The PCM row's sentence when a recording did not decode (#193): whether
    ffmpeg runs (`ffmpeg_runs()`), and when it does, which recording did not
    decode."""
    ok, why = ffmpeg_runs()
    if not ok:
        return (f"the two recordings decoded to PCM — ffmpeg does not run "
                f"(`ffmpeg -version`: {why})")
    if silent is None and loud is None:
        which = "neither recording decoded"
    elif silent is None:
        which = "the silent recording did not decode"
    else:
        which = "the tone recording did not decode"
    return f"the two recordings decoded to PCM — ffmpeg runs ({why}) and {which}"


def describe(measured):
    """`share s, RMS r` for a tone measurement, or `?` for none."""
    if measured is None:
        return "?"
    return f"share {measured['share']:.4f}, RMS {measured['rms']:.4f}"


def output_muted():
    """Whether the host's default output is muted — read through osascript, the
    one reader that needs no framework; an unreadable answer counts as NOT
    muted, so a host without osascript scores the capture row as written."""
    try:
        out = subprocess.run(["osascript", "-e", "output muted of (get volume settings)"],
                             capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return False
    return out == "true"


def granted_tier(mcp):
    host = display_probe()
    if host is None:
        check(False, "the display probe built and answered (a rotted instrument is a "
                     "FAILURE, not an exit)")
        skip("the granted tier (no host facts)", GRANTED_CHECKS + MIC_CHECKS)
        return
    print(f"  host: output {host.get('output', '?')!r} over {host.get('transport', '?')!r}; "
          f"preflight {host['preflight']}, locked {host['locked']}, display asleep "
          f"{host['asleep']}, {host['displays']} shareable display(s), main "
          f"{host['width']}×{host['height']} at scale {host['scale']}")

    document = new_document(mcp, "detect")
    asked = time.time()
    detection, message = attempt(
        mcp, "record_screen",
        {"seconds": 1, "place": False, "path": PROBE_FOLDER, "project": document})
    # Everything the tier promises, for a skip of the whole of it.
    tier = GRANTED_CHECKS + DETECTION_CHECKS + MIC_CHECKS
    if not host["preflight"]:
        check(message is not None and message.startswith(SCREEN_SENTENCE),
              f"with the preflight FALSE the tool refuses with the Screen Recording sentence, "
              f"naming the pane (the launch clause may follow it): {message!r}")
        skip("the granted tier: the Screen Recording grant is absent for this shell", tier)
        return
    if host["displays"] <= 0:
        check(message == NO_DISPLAY_SENTENCE,
              f"with the preflight TRUE and no display to share, the tool NAMES the "
              f"condition rather than hanging or spelling it as an index: {message!r}")
        skip(f"the granted tier: ScreenCaptureKit lists no display (console locked: "
             f"{host['locked']}, display asleep: {host['asleep']})", tier)
        return
    check(message is None,
          f"detection: 1 s, place: false, into the headless instance's document — a TRUE "
          f"preflight with {host['displays']} display(s) followed by a refusal is a failure: "
          f"{message!r}")
    if message is not None:
        skip("the granted tier: the detection recording was refused", tier)
        return

    # The tier's promise starts HERE — the detection answer's shape rows come
    # before the second instance, so `counted` is read before them and the
    # self-check at the end covers them too.
    counted = checks
    promised = GRANTED_CHECKS + DETECTION_CHECKS
    not_made = 0
    raised = 0
    skipped_inside, failed = run_rows("detection shape rows", DETECTION_CHECKS, detection_rows,
                                      mcp, detection, document, asked)
    not_made += skipped_inside
    raised += failed

    # The microphone's first precondition, read off the signed binary.
    entitled = "com.apple.security.device.audio-input" in subprocess.run(
        ["codesign", "-d", "--entitlements", "-", APP], capture_output=True, text=True).stdout

    instance = Instance("granted", GRANTED_PORT, extra=("-RCRecordingFolder", RUN))
    try:
        # The second precondition, read off the LAUNCHED instance — the one
        # the microphone rows run on — with the same never-records call.
        mic = refusal(instance.mcp, "record_screen",
                      {"seconds": 1, "microphone": True, "project": "/nowhere/x.reelcut"})
        authorized = mic is not None and NO_OPEN_PROJECT.match(mic) is not None
        port_pid = listening_pid(PORT)
        print(f"  granted tier: {BINARY} launched by this script on port {instance.port}, "
              f"under the grants of {responsible_application(instance.process.pid)}; the "
              f"instance on port {PORT} (pid {port_pid}) runs under "
              f"{responsible_application(port_pid) if port_pid else '?'}")
        skipped_inside, failed = run_rows("recording rows", GRANTED_CHECKS, granted_rows,
                                          instance.mcp, host)
        not_made += skipped_inside
        raised += failed
        if entitled and authorized:
            promised += MIC_CHECKS
            skipped_inside, failed = run_rows("microphone rows", MIC_CHECKS, microphone_rows,
                                              instance.mcp)
            not_made += skipped_inside
            raised += failed
        else:
            skip("the microphone rows: "
                 + ("the built app lacks com.apple.security.device.audio-input; "
                    if not entitled else "")
                 + ("the Microphone grant is not authorized for the launched instance "
                    f"({mic!r})" if not authorized else ""),
                 MIC_CHECKS)
    finally:
        stop_launched()
    complaints = parity_lines(instance.log)
    check(complaints == [], f"the launched instance's parity log is empty ({instance.log})")
    ran = checks - counted - 1
    expected = promised - not_made + raised
    check(ran == expected,
          f"the tier made the {expected} checks its skip counts promise (made {ran}; "
          f"{promised} promised, {not_made} skipped by name, {raised} added by a raise)")


def segment_of(answer):
    """The first entry of `segments`, or an empty dict when the key is not a
    non-empty list — so a row reads `{}` and fails rather than raising."""
    segments = answer.get("segments")
    return segments[0] if isinstance(segments, list) and segments else {}


def detection_rows(mcp, answer, document, asked):
    """The detection call's own answer — 1 s, `place: false`, no microphone,
    never paused — read for R2d's result shape with ONE segment, on the
    headless instance's document. `asked` is when the call was made."""
    pauses = answer.get("pauses")
    check(pauses == 0 and isinstance(pauses, int) and not isinstance(pauses, bool),
          f"a recording nobody paused answers pauses 0, an integer: {pauses!r}")
    segments = answer.get("segments")
    check(isinstance(segments, list) and len(segments) == 1,
          f"segments is ALWAYS present and holds exactly one entry for it: "
          f"{type(segments).__name__} of {len(segments) if isinstance(segments, list) else '?'}")
    segment = segment_of(answer)
    check(segment.get("path") == answer["path"],
          "the segment's path is the top level's — the recording's file")
    check(segment.get("duration") == answer["duration"],
          f"…and its duration is the top level's: with one segment the TOTAL is the "
          f"segment's ({answer['duration']} ticks)")
    started = segment.get("started_at")
    check(isinstance(started, str) and STARTED_AT.match(started) is not None,
          f"started_at is spelled as ISO 8601 UTC to the millisecond with a Z: {started!r}")
    instant = parse_started_at(started)
    check(instant is not None and -1.0 <= instant - asked <= 60.0,
          f"…and parses (datetime.fromisoformat) to an instant between the call and a minute "
          f"after it: {'?' if instant is None else format(instant - asked, '+.3f')} s after "
          f"the call was made — a formatter in local time is off by the host's UTC offset "
          f"here")
    listed = {m["id"]: m for m in project(mcp, document)["media"]}
    check(segment.get("media") == answer["media"] and "clip" not in segment
          and listed.get(answer["media"], {}).get("path") == segment.get("path")
          and segment.get("mic_offset") == answer["mic_offset"]
          and "mic_path" not in segment and "mic_problem" not in segment,
          "the segment's media is the top level's and is the document's entry for that path; "
          "it carries no clip (place: false), its mic_offset is the top level's, and with no "
          "microphone asked for it has no mic_path and no mic_problem")
    check(segment.get("width") == answer["width"] and segment.get("height") == answer["height"]
          and segment.get("fps") == answer["fps"],
          f"the segment carries its own width, height and fps, the top level's for one "
          f"segment: {segment.get('width')}×{segment.get('height')} at {segment.get('fps')}")
    check(set(segment) <= SEGMENT_KEYS,
          f"its keys are among the fourteen the description names: "
          f"{sorted(set(segment) - SEGMENT_KEYS)} unexpected")


def granted_rows(mcp, host):
    # (a) NO document open: the recording opens as a new project.
    asked = time.time()
    answer = mcp.call_with("record_screen", {"seconds": 2})
    path = answer["path"]
    check(answer["landed"] == "new_project" and answer["ok"],
          f"with no document open the recording landed as a NEW project: {answer['landed']}")
    check(os.path.dirname(path) == RUN,
          f"the file is in the -RCRecordingFolder folder: {path}")
    check(DATED_NAME.match(os.path.basename(path)) is not None,
          f"…named by date and time: {os.path.basename(path)}")
    check(os.path.exists(path), "…and exists on disk")
    check(1.5 * SEC <= answer["duration"] <= 3.5 * SEC,
          f"a 2 s recording's probed duration is in [1.5 s, 3.5 s]: {answer['duration']} ticks")
    check(size_matches(answer["width"], answer["height"], host, best=False),
          f"nominal size is the main display's POINT size (even rounding allowed): "
          f"{answer['width']}×{answer['height']} for {host['width']}×{host['height']}")
    check(answer["project"]["path"] == path,
          "and is addressable by project: <the recording's path>")
    check(answer["stopped_by"] == "stopped", f"stopped_by is stopped: {answer['stopped_by']}")
    # R2d's shape on the new-project door: one segment, its ids looked up by
    # PATH on the document `untitled(around:)` built.
    segments = answer.get("segments")
    segment = segment_of(answer)
    check(answer.get("pauses") == 0 and isinstance(segments, list) and len(segments) == 1,
          f"never paused: pauses 0 and one segment (pauses {answer.get('pauses')!r}, "
          f"{len(segments) if isinstance(segments, list) else '?'} segment(s))")
    check(segment.get("path") == path and segment.get("duration") == answer["duration"],
          "the segment's path and duration are the top level's")
    check(segment.get("width") == answer["width"] and segment.get("height") == answer["height"]
          and segment.get("fps") == answer["fps"],
          "…and so are its own width, height and fps")
    instant = parse_started_at(segment.get("started_at"))
    check(instant is not None and -1.0 <= instant - asked <= 60.0,
          f"its started_at is within a minute after the call: {segment.get('started_at')!r}, "
          f"{'?' if instant is None else format(instant - asked, '+.3f')} s")
    reported = project(mcp, path)
    media = reported["media"][0]
    if media["fps"] == [60, 1]:
        # The override cannot be told from the file: a build that dropped
        # `fps:` would also show [60, 1] here. Named, counted, not passed.
        skip("the canvas.fps row: the file's own rate is exactly 60/1 on this run, so the "
             "override cannot be told from the file", 1)
    else:
        check(reported["canvas"]["fps"] == [60, 1] and answer["project"]["fps"] == [60, 1]
              and media["fps"] != [60, 1],
              f"get_project: canvas.fps [60, 1] (the recorder's rate) while media[0].fps is "
              f"the file's own, {media['fps']}, which is NOT [60, 1] — decision 3, and the "
              "row the fps-override mutant fails (the canvas would then carry the file's rate)")
    check(media["id"] == answer["media"] and answer["fps"] == media["fps"],
          "the answer's media id and fps are the media record's")
    clips = reported["clips"]
    check(len(clips) == 1 and clips[0]["id"] == answer["clip"]
          and clips[0]["source"]["media"] == answer["media"] and clips[0]["start"] == 0,
          "the one clip shows the recording from 0")
    check(answer["has_audio"] and answer["audio_tracks"] == 1,
          "the movie holds one audio track (system audio is on by default)")
    check(segment.get("media") == answer["media"] and segment.get("clip") == answer["clip"],
          "the segment's media and clip — looked up by PATH on the new document — are the "
          "top level's")
    undone = refusal(mcp, "undo", {"project": path})
    check(undone is not None and undone.startswith(NOTHING_TO_UNDO),
          f"a mic-less new project has NO undo step — its first project is what it is: "
          f"{undone!r}")

    # (b) Into a saved document with an empty front track at the playhead.
    document = new_document(mcp, "granted")
    mcp.call_with("set_canvas", {"project": document, "fps": [60, 1]})
    back = project(mcp, document)["tracks"][0]["id"]
    mcp.call_with("add_shape_clip",
                  {"project": document, "track": back, "at": 0, "duration": 10 * SEC,
                   "shape": {"kind": "rectangle"}})
    front = mcp.call_with("add_track", {"project": document, "index": 1})["new_tracks"][0]
    mcp.call_with("set_playhead", {"project": document, "t": 2 * SEC})
    before = fingerprint(mcp, document)
    before_png = digest(render(mcp, document, 3 * SEC))
    answer = mcp.call_with("record_screen", {"seconds": 2, "project": document})
    check(answer["landed"] == "document" and answer["ok"],
          f"into an open document the recording landed there: {answer['landed']}")
    check("new_tracks" not in answer,
          "the empty front track ACCEPTED the clip — no track was minted")
    reported = project(mcp, document)
    clip = [c for c in reported["clips"] if c["id"] == answer["clip"]]
    check(len(clip) == 1 and clip[0]["track"] == front and clip[0]["start"] == 2 * SEC
          and clip[0]["source"]["media"] == answer["media"],
          "get_project shows the new clip at the playhead on the front track with the new "
          "media id")
    check(answer["new_media"] == [answer["media"]] and answer["new_clips"] == [answer["clip"]],
          "the created ids are reported: one media, one clip")
    segment = segment_of(answer)
    check(answer.get("pauses") == 0 and segment.get("media") == answer["media"]
          and segment.get("clip") == answer["clip"],
          "the document landing's one segment carries the placement's PREDICTED ids, equal "
          "to the top level's")
    midpoint = 2 * SEC + answer["duration"] // 2
    after = render(mcp, document, midpoint)
    yavg = luma_average(after)
    check(digest(after) != before_png and yavg is not None and abs(yavg - BLACK_YAVG) > 1.0,
          f"render_frame at the clip's midpoint differs from the frame before the "
          f"recording and is not black (YAVG {yavg})")
    undone = mcp.call_with("undo", {"project": document})
    check(undone["undone"] == "Add Recording",
          f"undo walks one step named Add Recording: {undone['undone']}")
    check(fingerprint(mcp, document) == before,
          "…and that ONE step removed media and clip: the whole project is back")
    check(os.path.exists(answer["path"]), "…while the file stays on disk")
    mcp.call_with("redo", {"project": document})

    # (c) The same playhead with the front track now occupied → a new track.
    answer = mcp.call_with("record_screen", {"seconds": 2, "project": document})
    check(len(answer.get("new_tracks", [])) == 1
          and [c for c in project(mcp, document)["clips"]
               if c["id"] == answer["clip"]][0]["track"] == answer["new_tracks"][0],
          "with the front track occupied the clip lands on a NEW front track — the "
          f"two-try rule's second branch: new_tracks {answer.get('new_tracks')}")

    # (d) size best → the pixel size.
    mcp.call_with("set_playhead", {"project": document, "t": 6 * SEC})
    answer = mcp.call_with("record_screen", {"seconds": 2, "size": "best", "project": document})
    check(size_matches(answer["width"], answer["height"], host, best=True),
          f"size best records the display's PIXEL size: {answer['width']}×{answer['height']} "
          f"for {host['width']}×{host['height']} at scale {host['scale']}")

    # (e) place: false → the media alone.
    answer = mcp.call_with("record_screen", {"seconds": 1, "place": False, "project": document})
    check("new_media" in answer and "new_clips" not in answer and "clip" not in answer
          and "add_clip" in answer.get("note", ""),
          "place: false lands the media alone, with import_media's note and no clip id")
    segment = segment_of(answer)
    check(segment.get("media") == answer["media"] and "clip" not in segment,
          "…and its one segment has the media and no clip either")

    # (e2) A blank path is the default folder, never the process's cwd
    # (`URL(fileURLWithPath: "")` is the cwd — the R1 review's finding).
    answer = mcp.call_with("record_screen",
                           {"seconds": 1, "place": False, "path": "  ", "project": document})
    check(os.path.dirname(answer["path"]) == RUN,
          f"path: \"  \" (blank) lands the file in the instance's own recording folder, not "
          f"the working directory: {answer['path']}")

    # (f) Inside an open nest.
    nested = mcp.call_with(
        "add_shape_clip",
        {"project": document, "track": back, "at": 20 * SEC, "duration": 2 * SEC,
         "shape": {"kind": "ellipse"}})["new_clips"][0]
    mcp.call_with("nest", {"project": document, "clips": [nested]})
    nest = project(mcp, document)["nests"][0]["id"]
    mcp.call_with("set_scope", {"project": document, "nest": nest})
    mcp.call_with("set_playhead", {"project": document, "t": 0})
    answer = mcp.call_with("record_screen", {"seconds": 2, "project": document})
    check(answer.get("scope") == nest and answer.get("document_ops") == ["add_media"],
          f"inside an open nest the answer says where it landed: scope {answer.get('scope')}, "
          f"document_ops {answer.get('document_ops')}")
    view = project(mcp, document)
    check(any(c["id"] == answer["clip"] and c["source"]["media"] == answer["media"]
              for c in view["clips"]),
          "and the nest's view shows the clip with the new media")
    segment = segment_of(answer)
    check(segment.get("clip") == answer["clip"] and segment.get("media") == answer["media"],
          "…and the segment's ids are the ones the view shows — predicted inside the scope")
    mcp.call_with("set_scope", {"project": document})
    outside = project(mcp, document)
    check(not any(c["id"] == answer["clip"] for c in outside["clips"])
          and any(c["id"] == answer["clip"] for n in outside["nests"] for c in n["clips"]),
          "…while the timeline does not: the clip is in the nest, not beside it")

    # (g) System audio: a recording with nothing of ours playing, then one
    # under a tone, then off. The two files are compared by their 1 kHz
    # SHARE (Parseval's scale, `tone_share`) rather than by `detect_silence`,
    # because a host may be playing anything (measured: Plex, into the tap,
    # at 02:30) and a threshold detector cannot tell a tone from music; a
    # Goertzel filter can.
    mcp.call_with("set_playhead", {"project": document, "t": 30 * SEC})
    answer = mcp.call_with("record_screen", {"seconds": 2, "project": document})
    check(answer["has_audio"] and answer["audio_tracks"] == 1,
          "system_audio true with nothing of ours playing still writes one audio track")
    silent = tone_power(answer["path"])

    tone = os.path.join(RUN, "tone.wav")
    write_tone(tone, seconds=30.0)
    player = subprocess.Popen(["afplay", tone])
    try:
        time.sleep(1.0)
        mcp.call_with("set_playhead", {"project": document, "t": 40 * SEC})
        answer = mcp.call_with("record_screen", {"seconds": 2, "project": document})
    finally:
        player.terminate()
        player.wait(timeout=10)
    check(answer["has_audio"] and answer["audio_tracks"] == 1,
          "system_audio true while a tone plays: has_audio true, one track")
    loud = tone_power(answer["path"])
    transport = host.get("transport", "?")
    print(f"  1 kHz share: silent {describe(silent)}; tone {describe(loud)}")
    if transport in WIRELESS_TRANSPORTS:
        # A Bluetooth or AirPlay output hands the tap NOTHING on this host —
        # measured 2026-09-11 with AirPods Max as the default output: afplay
        # and `say` both alive through a 3 s recording, the file decoding to
        # RMS 0.0 and peak 0.0, where R0 had measured the built-in speakers'
        # tone at unity. Named and skipped with its count, never passed.
        skip(f"the tone rows: the default output {host.get('output', '?')!r} is "
             f"{WIRELESS_TRANSPORTS[transport]}, which delivers nothing to the system-audio "
             "tap on this host — choose a wired or built-in output to score capture",
             TONE_CHECKS)
    elif output_muted():
        # A muted output reaches the tap unreliably (R0's unity tone arrived
        # at −23 dB once and not at all once, the same night), so nothing
        # about capture can be scored here — the rows are SKIPPED with their
        # count, never passed. The numbers are printed above for the record.
        skip("the tone rows: the host's output is MUTED, so the tap gets the tone "
             "unreliably — unmute to score capture", TONE_CHECKS)
    elif silent is None or loud is None:
        check(False, pcm_failure(silent, loud))
        skip("the tone rows: no PCM to measure", TONE_CHECKS - 1)
    else:
        check(loud["share"] >= 100 * max(silent["share"], 0.001),
              f"the tone recording's 1 kHz share is ≥ 100× the silent recording's, floored "
              f"at 0.001 ({loud['share']:.4f} vs {silent['share']:.4f}): the tone was captured")
        check(loud["share"] >= 0.25 and loud["rms"] >= 0.05,
              f"…and the tone is at least a quarter of that recording's power at an RMS of "
              f"at least 0.05, −26 dBFS (share {loud['share']:.4f}, RMS {loud['rms']:.4f}; "
              "R0 measured 0.35 at unity): a unity tone dominates whatever else the host "
              "plays")

    mcp.call_with("set_playhead", {"project": document, "t": 50 * SEC})
    answer = mcp.call_with("record_screen",
                           {"seconds": 2, "system_audio": False, "project": document})
    check(not answer["has_audio"] and answer["audio_tracks"] == 0,
          "system_audio false writes a movie with no audio track: has_audio false, 0 tracks")

    # (h) A document at MAX_TRACKS with its front track occupied: the
    # recording is made, the placement's second try meets the cap in the
    # TRIAL, and the refusal names the file that exists.
    full = new_document(mcp, "full")
    tracks = project(mcp, full)["tracks"]
    for _ in range(MAX_TRACKS - len(tracks)):
        mcp.call_with("add_track", {"project": full, "index": len(tracks)})
        tracks = project(mcp, full)["tracks"]
    mcp.call_with("add_shape_clip",
                  {"project": full, "track": tracks[-1]["id"], "at": 0, "duration": 10 * SEC,
                   "shape": {"kind": "rectangle"}})
    mcp.call_with("set_playhead", {"project": full, "t": 1 * SEC})
    before = fingerprint(mcp, full)
    message = refusal(mcp, "record_screen", {"seconds": 1, "project": full})
    named = SAVED_BUT_NOT_ADDED.match(message or "")
    check(named is not None and "too many tracks" in (message or ""),
          f"at MAX_TRACKS ({len(tracks)}) with the front track occupied, the recording is made "
          f"and the refusal names the file and the core's own sentence: {message!r}")
    check(named is not None and os.path.exists(named.group(1))
          and os.path.dirname(named.group(1)) == RUN,
          f"…and the file it names exists in the recording folder: "
          f"{named and named.group(1)}")
    check(fingerprint(mcp, full) == before,
          "…while the document is untouched — nothing landed and no step was pushed")


def microphone_rows(mcp):
    document = new_document(mcp, "microphone")
    fps = project(mcp, document)["canvas"]["fps"]
    frame = SEC * fps[1] // fps[0]

    def snapped(length):
        return (length + frame // 2) // frame * frame

    def landed(answer):
        reported = project(mcp, document)
        tracks = {t["id"]: t for t in reported["tracks"]}
        clips = {c["id"]: c for c in reported["clips"]}
        return tracks, clips.get(answer["clip"]), clips.get(answer.get("mic_clip"))

    mcp.call_with("set_playhead", {"project": document, "t": 2 * SEC})
    answer = mcp.call_with("record_screen", {"seconds": 2, "microphone": True, "project": document})
    mic_path = answer.get("mic_path")
    check(mic_path is not None and os.path.exists(mic_path)
          and mic_path.endswith(" (Microphone).m4a"),
          f"microphone: true writes a second file beside the movie: {mic_path}")
    check("mic_media" in answer and "mic_clip" in answer and "mic_duration" in answer,
          "the answer carries mic_media, mic_clip and mic_duration")
    segment = segment_of(answer)
    check(segment.get("mic_path") == mic_path
          and segment.get("mic_duration") == answer.get("mic_duration")
          and segment.get("mic_offset") == answer["mic_offset"],
          "the one segment's mic_path, mic_duration and mic_offset are the top level's")
    check(segment.get("mic_media") == answer.get("mic_media")
          and segment.get("mic_clip") == answer.get("mic_clip")
          and "mic_problem" not in segment,
          "…and its mic_media and mic_clip too, with no mic_problem in it")
    tracks, picture, voice = landed(answer)
    check(voice is not None and tracks[voice["track"]]["name"] == "Microphone"
          and voice["source"]["media"] == answer["mic_media"],
          "the microphone clip is on a track named Microphone, showing the second file")
    check(picture is not None and voice is not None
          and abs((picture["start"] - voice["start"]) - answer["mic_offset"]) <= frame // 2,
          f"the two clips' starts differ by the measured mic_offset ({answer['mic_offset']} "
          f"ticks, {answer['mic_offset'] / 600:.1f} ms) to within half a frame: picture "
          f"{picture and picture['start']}, microphone {voice and voice['start']}")
    # A HEAD LOSS is a microphone file SHORTER than the movie: lane A's smoke
    # run measured −421 ms, the first 0.4 s of voice simply absent, before
    # `prepareMicrophone` paid `startRunning()`'s cost ahead of the start. A
    # LONGER file is the opposite and is normal now: a prepared session's
    # did-start lands in ~25 ms and the stream's in ~70, so the microphone
    # LEADS by the measured mic_offset and its file holds that lead plus the
    # writers' tail difference (R0: 13–43 ms movie, 40–74 ms microphone) —
    # measured here +92.6 and +109.6 ms against offsets of +66 and +70 ms.
    # So the bound is one-sided, and the raw numbers are printed either way.
    gap = answer.get("mic_duration", 0) - answer["duration"]
    check("mic_duration" in answer and gap >= -2 * frame,
          f"the microphone file is not SHORTER than the movie by more than two frames "
          f"({2 * frame} ticks, {2 * frame / 600:.0f} ms) — no head loss: microphone "
          f"{answer.get('mic_duration')} vs movie {answer['duration']} ticks, a difference of "
          f"{gap / 600:+.1f} ms against a mic_offset of {answer['mic_offset'] / 600:+.1f} ms "
          f"(a residual of {(gap - answer['mic_offset']) / 600:+.1f} ms of tail); lane A's "
          "−421 ms fails here")
    check("mic_problem" not in answer
          and "microphone file could not be used" not in answer.get("note", ""),
          "a microphone that landed carries no mic_problem and no note about one")
    check(sorted(answer["new_media"]) == sorted([answer["media"], answer["mic_media"]])
          and sorted(answer["new_clips"]) == sorted([answer["clip"], answer["mic_clip"]]),
          "both files' media and clips are reported as created")
    undone = mcp.call_with("undo", {"project": document})
    check(undone["undone"] == "Add Recording"
          and len(project(mcp, document)["media"]) == 0,
          "one undo removes both files' media and clips")

    # At playhead 0 the measured offset picks the landing's branch: a
    # positive one trims the voice's HEAD (the clip cannot start before 0),
    # a negative one places the voice LATE, and one within half a frame
    # sends neither — `RecordingLanding.addMicrophoneClip`'s three cases.
    mcp.call_with("set_playhead", {"project": document, "t": 0})
    answer = mcp.call_with("record_screen", {"seconds": 2, "microphone": True, "project": document})
    tracks, picture, voice = landed(answer)
    offset = answer["mic_offset"]
    gap = answer.get("mic_duration", 0) - answer["duration"]
    check(answer.get("pauses") == 0 and len(answer.get("segments") or []) == 1
          and segment_of(answer).get("mic_offset") == offset,
          f"the playhead-0 recording is one segment, never paused, whose mic_offset is the "
          f"one the branch below reads ({offset} ticks)")
    check(picture is not None and voice is not None and picture["start"] == 0
          and tracks[voice["track"]]["name"] == "Microphone",
          f"at playhead 0 the picture is at 0 and the voice is on its Microphone track: "
          f"mic_offset {offset} ticks ({offset / 600:+.1f} ms), durations differ by "
          f"{gap / 600:+.1f} ms")
    if voice is None:
        skip("the head-trim row: no voice clip landed", 1)
    elif offset >= frame // 2:
        head = snapped(offset)
        check(voice["start"] == 0 and voice["source"]["in"] == head,
              f"the picture began {offset / 600:.1f} ms AFTER the microphone, so the voice "
              f"clip starts at 0 with its head TRIMMED to the snapped offset ({head} ticks): "
              f"start {voice['start']}, in {voice['source']['in']}")
    elif offset <= -(frame // 2):
        late = snapped(-offset)
        check(voice["start"] == late and voice["source"]["in"] == 0,
              f"the picture began {-offset / 600:.1f} ms BEFORE the microphone, so the voice "
              f"clip is placed late by the snapped offset ({late} ticks) with in 0: start "
              f"{voice['start']}, in {voice['source']['in']}")
    else:
        skip(f"the head-trim row: the measured mic_offset is {offset} ticks "
             f"({offset / 600:+.1f} ms), within half a frame ({frame // 2} ticks) of zero, so "
             "the landing sends no trim and no delay on this run; a run whose offset is at "
             "least half a frame either way scores it", 1)


# ---- main ----------------------------------------------------------------


def cleanup():
    for folder in (RUN, PROBE_FOLDER, DOCS, SELFTEST):
        shutil.rmtree(folder, ignore_errors=True)


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT, timeout=180)
    print(f"road map 3, R1 and R2 — record_screen, against 127.0.0.1:{PORT}")
    try:
        section("0 — the catalog: 75 or more, record_screen's arguments, no scope on it",
                catalog_part, mcp)
        section("1 — the refusals, exact and in order, touching nothing", refusal_part, mcp)
        section("2 — the held last frame (lane E), which needs no grant", fixture_part, mcp)
        section("3 — the tool's source, read where no call can reach", source_part)
        section("4 — the tone arithmetic, self-tested on a synthesized trio", selftest_part)
        section("5 — the granted tier: the host's facts, then a second instance of its own",
                granted_tier, mcp)
    finally:
        stop_launched()
        cleanup()

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what, count in skipped:
        print(f"  skipped: {what} — {count} checks")
    if skipped:
        print(f"  skipped in all: {skipped_total()} checks")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
