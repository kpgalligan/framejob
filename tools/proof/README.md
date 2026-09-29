# tools/proof — driving a built Reelcut over MCP, and rendering its chrome offscreen

`CLAUDE.md`'s "Verifying a build" is the standard: the app is verified by
driving the built binary and comparing what it renders, not by reading
code. These are the scripts that do it — an MCP script per road-map-2 phase,
from phase 2 an offscreen-chrome script beside it, and for the fixes
`archive/reelcut-remaining.md` records, `remaining_proof.py` over MCP and
`remaining_probe.py` offscreen — so a proof can be re-run after a later
change rather than believed on the strength of a paragraph.

`mcp.py` is a ~80-line MCP client (streamable HTTP, tools only) — enough to
`initialize`, list the tools and call one: `call(tool, **args)`, or
`call_with(tool, {…})` when an ARGUMENT is itself spelled `name`
(`add_track`, `set_track`, `add_marker`, `set_marker`, `nest`), since
`call`'s own first parameter is the tool's name. It has no dependencies.
`harness/` is the offscreen renderer, described at the end.

Each `phase<N>_proof.py` makes its own projects under `work/` from test media
under `media/`, and every claim is one of three kinds: a placement read back
through `get_project`; a **byte comparison of two PNGs** — `render_frame`'s,
or the harness's, where the claim is also WHERE the changed pixels landed
against the layout constants; or a **sample-for-sample comparison of two
exports** decoded to PCM, which needs `ffmpeg` at proof time. A frame claim
that could be satisfied by two different-looking pictures is not a proof, so
nothing here compares sizes or timestamps.

## Running one

Road map 7 part 2's frame-grid proof owns a fresh Release app process. After
`make app`, run `python3 tools/proof/frame_grid_proof.py --port 5514`;
`--app PATH` selects a matching alternate `.app`. It opens a generated package,
changes fps, pastes a nested payload, copies attributes and unnests, reading
exact stored clip/property ticks after each edit. Each edit's complete
before/after project is checked through one undo and redo, followed by a
save/reopen check. It verifies the actual bound port and an empty startup
parity log before and after, times out failed calls, and terminates only the
process it launched. This is a stored-timing proof; it makes no pixel or
audio claim. The FFI companion vectors are `frame_grid_canvas.rs` and
`frame_grid_transfer.rs`.

Road map 7 part 1's extreme-time proof launches its own Release app and owns
only that process. After `make app`, run
`python3 tools/proof/extreme_time_proof.py --port 5350`; `--app PATH` selects a
matching alternate `.app` for an isolated mutation build. It writes temporary
`.reelcut` packages, checks named refusal of oversized saved values and the
next valid open in the same process, renders an admitted control, then checks
edit rejection, undo/redo and save/reopen. It refuses a fallback MCP port,
checks the startup parity log before and after, and exits nonzero for a crash,
timeout, build mismatch or failed row. The Rust companion
`core/tests/transition_bounded.rs` runs long searches in child processes with
hard 5-second and 30-second watchdogs; the parent kills only its own child.
For mutation verification, remove the `check_stored_times` call in a temporary
copy to make the endpoint and saved-file rows fail, or restore an enumerating
transition loop there to make the child watchdog fail. Restore the source and
rerun green before recording a proof claim.

Issue #34's pair makes its own media per run under `work/mixed-audio/`:
`python3 tools/proof/mixed_audio_probe.py [--sources PATH]` (no port; its
section 4 is the proof of the fix) and `python3 tools/proof/mixed_audio_proof.py
<port>` (the export path's regression guard); "Mixed audio formats on one
track" below.

Make the test media once (ffmpeg is not a product dependency — see spec §11
— but it is the obvious way to get a frame-numbered test card):

```sh
mkdir -p tools/proof/media && cd tools/proof/media
ffmpeg -y -f lavfi -i "testsrc=size=640x360:rate=30:duration=10"  -pix_fmt yuv420p -c:v libx264 A.mov
ffmpeg -y -f lavfi -i "testsrc2=size=640x360:rate=30:duration=10" -pix_fmt yuv420p -c:v libx264 B.mov
ffmpeg -y -f lavfi -i "color=c=green:size=640x360:rate=30:duration=6" -pix_fmt yuv420p -c:v libx264 C.mov
```

Phase 2 adds sound. The three movies above are silent, and a clip of a
silent movie has NO audio group (an `.m4a` clip has no video group), so the
solo proof needs two tones it can tell apart by ear and by byte, and the
paste-attributes proof needs one clip that has BOTH groups:

```sh
ffmpeg -y -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=5" -ac 2 -c:a aac -b:a 128k toneA.m4a
ffmpeg -y -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=5" -ac 2 -c:a aac -b:a 128k toneB.m4a
ffmpeg -y -f lavfi -i "testsrc=size=640x360:rate=30:duration=5" \
       -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=5" \
       -ac 2 -pix_fmt yuv420p -c:v libx264 -c:a aac -b:a 128k -shortest AV.mov
```

(5 s, 48 kHz stereo AAC; `AV.mov` is the test card with the 440 Hz tone
under it.) `phase2_proof.py` also runs `ffmpeg` at proof time, to decode
each `audio_m4a` export to raw PCM
(`-vn -f s16le -acodec pcm_s16le -ar 48000 -ac 2`) so two exports can be
compared sample for sample.

Phase 3 adds a recording with KNOWN dead air in it — `silence.mov`, a 10 s
test card whose 48 kHz stereo LPCM track is quiet over exactly 2.000–3.500 s
and 6.000–7.000 s. The spans have to be sample-exact, because
`phase3_proof.py` asserts that `detect_silence` finds them to within one
10 ms bucket:

```sh
ffmpeg -y \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=2" \
  -f lavfi -i "anullsrc=r=48000:cl=mono:d=1.5" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=2.5" \
  -f lavfi -i "anullsrc=r=48000:cl=mono:d=1" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=3" \
  -f lavfi -i "testsrc=size=640x360:rate=30:duration=10" \
  -filter_complex "[0:a][1:a][2:a][3:a][4:a]concat=n=5:v=0:a=1[a]" \
  -map 5:v -map "[a]" -pix_fmt yuv420p -c:v libx264 -c:a pcm_s16le -ac 2 \
  -t 10 silence.mov
```

Five exact-length segments concatenated, and PCM rather than AAC so nothing
is smeared across a codec frame. **The obvious spelling does not work**: one
sine with `volume=enable='between(t,2,3.5)':volume=0` puts the boundaries up
to two audio frames out, because a `volume` filter's `enable` expression is
evaluated once per ~21 ms frame rather than per sample — which is bigger than
the tolerance the proof measures against, so the fixture would be testing
ffmpeg's rounding rather than the detector's. The tone lands around
−21 dBFS with this ffmpeg's `sine`; any level between −40 dBFS and full scale
does, since the proof reaches its "everything is quiet" case with a threshold
of 0 dBFS rather than one pitched near the tone.

Phase 4 adds a recording of SPEECH — `speech.mov`, a navy card over `say`'s
rendering of two pangrams — for the person who runs the caption proof with
the Speech Recognition grant. Nothing a script can reach needs it (see
`phase4_proof.py` below), so it is the one fixture here that exists for a
human:

```sh
say -o speech.aiff "The quick brown fox jumps over the lazy dog. \
Pack my box with five dozen liquor jugs."
ffmpeg -y -f lavfi -i "color=c=navy:size=640x360:rate=30" -i speech.aiff \
  -shortest -pix_fmt yuv420p -c:v libx264 -c:a pcm_s16le -ac 2 speech.mov
```

(5.2 s; `say`'s own voice and rate, so the words are the fixture and the
timing is not.) Phase 4's other fixture is a `.srt` file, and
`phase4_proof.py` WRITES it: it is the thing being compared against, and a
proof that authors its own expected bytes cannot be reading a file somebody
edited by hand.

**Phase 5 adds NOTHING to `media/`** — `phase5_proof.py` writes its own seven
fixtures into `work/fixtures/` on every run, and that is deliberate rather
than lazy. Every claim it makes is about a LEVEL, so the amplitude and the
phase of each signal have to be exact and have to be visible beside the check
that leans on them: they are one `aevalsrc` expression per channel, listed in
that script's `FIXTURE_EXPRESSIONS`, and they are rewritten on each run
because a fixture that could be stale is a fixture that could be lying. Two
of the seven cannot be written any other way. The mono fold needs a file
whose channels DIFFER (440 Hz at half scale left, 880 Hz at a quarter right)
or "left equals right" is a tautology; the true-peak invariant needs a 12 kHz
sine at exactly 45°, whose every sample sits 3.01 dB under its real
amplitude. Worth knowing if you write another: `amerge` of two mono sines
does not give you a stereo pair at the amplitudes you asked for — it lands
18 dB down — and lavfi needs the expression SINGLE-QUOTED inside the filter
description, or the commas in `between(t,0,1.5)` are read as more options.

**Phase 6 adds nothing to `media/` either, and for a sharper reason than
phase 5's.** Every absolute claim it makes is a claim about a BYTE in a
PNG, so its fixture is two full-canvas SHAPE clips on two tracks with flat
fills and no stroke — exact by construction, deterministic, and with
nothing loading asynchronously. There is no media in the blend checks at
all, which is what `video.blend` belonging to the LAYER rather than to a
source kind buys. One `qtrle` movie is written into `work/` per run as a
cross-check that a decoded picture behaves the same way, and the line has
one trap in it:

```sh
ffmpeg -y -f lavfi -i "color=c=0x808080:size=640x360:rate=30:duration=5,format=rgb24" \
  -c:v qtrle grey80.mov
```

The `format=rgb24` must be INSIDE the filter chain. `-pix_fmt rgb24` on the
OUTPUT gives 0x7E where the card asks for 0x80, and a blend proof measured
against 126 instead of 128 fails arithmetic it got right.

**Phase 7 adds nothing to `media/` either, and `phase7_chrome.py` needs no
ffmpeg at all.** Every fixture it uses is a shape card written by the script
into `work/` — one rectangle on one track, nine packages at three canvas sizes —
and a timeline of
nothing but shapes exports through `CompositionBuilder`'s placeholder track, so
there is nothing to decode anywhere in that file. `phase7_proof.py` is the half
that needs a decoder, because ProRes 4444's alpha is a pixel format only
`ffprobe` can name.

**Road map 4's voice proofs add nothing to `media/` either, and they make
their own recordings.** `silence2_proof.py` writes `work/silence2/fixtures/`
on its first run (or on `--remake`): `speech.aiff` from `say`, the five mixes
from `tools/proof/silence_spike/README.md` VERBATIM — so what the S0 spike
measured and what S1 is proved against are the same signals — plus
`clean.wav` (the speech at 48 kHz), `tone.wav` (the `silence.mov` recipe
above, audio only), `voicetone.wav` (the speech padded to exactly 11.000 s
with the tone after it), a silent `mute.mov` and — since the 2026-09-20
reader review — `corrupt.m4a`, the clean fixture re-encoded as AAC with
bytes 45 %–70 % of the container ZEROED and the `moov` left intact, so
AVFoundation reports the full duration and the reader gives up part way (a
truncated WAV will not do it: AVFoundation reads a WAV's duration off the
bytes that are actually there). They are NOT in `media/`
and must not go there: `media/speech.aiff` is phase 4's different text, and
the whole point of these is that they are `say`'s output on THIS machine.
Which is also why nothing in either script hard-codes a second of the
recording — the TRUTH is measured per run, as the −40 dBFS level pass over
the file's digital silence, and the pinned trace is keyed on the samples'
own sha256. `silence2_probe.py` reuses the same directory and makes it by
IMPORTING `silence2_proof.py`'s recipes rather than copying them.

**Road map 5's transition proof needs a SECOND BINARY, built from an older
tree.** Four of E1's claims are about what did NOT move — a version-6
project's overlap still drawing linearly and sounding silent — and "exactly
as it did" is only checkable against a build that never had `curve` and
`audio`. So `e1_proof.py` and `e1_chrome.py` are run against the tree at
`1c3e92e`, the commit before E1's first toll, extracted and built beside the
repository and never inside it:

```sh
mkdir -p tools/proof/work/e1-reference
git archive 1c3e92e | tar -x -C tools/proof/work/e1-reference
(cd tools/proof/work/e1-reference && make app)
```

That build's format version is SIX and the core refuses a file from the
future, so every fixture the two builds share is hand-written back to version
6 (`as_version` in `e1_proof.py`, and the package `e1_chrome.py` writes) —
which is also exactly the file a person who used the app last month has on
disk. It answers 75 tools and 55 ops where this build answers 77 and 57,
which is how a row knows which instance it is talking to; `e1_proof.py`
scores that first and SKIPS the cross-build rows by name if the reference
does not answer. `e1_chrome.py` builds the reference tree's own harness out
of `tools/proof/work/e1-reference/tools/proof/harness/build.sh`, and takes
`--reference DIR` for a copy kept somewhere else.

Then launch YOUR OWN instance on YOUR OWN port and only ever kill that one
(`pgrep -f "MacOS/Reelcut"` lists them; another session may have one running).
**A direct launch of the binary runs under the TERMINAL's grants** — road map
3's R0 question 1, measured: TCC attributes a shell-launched
`Reelcut.app/Contents/MacOS/Reelcut` to the terminal that launched it
(`responsibility_get_pid_responsible_for_pid` names the terminal, not
Reelcut), so a Screen Recording or Microphone grant given to Reelcut.app in
System Settings never reaches a proof's instance, and the terminal's own
grants are what `record_screen` runs under. That is why `recording_proof.py`'s
granted tier prints whose grant it ran under. To get an instance that is
responsible for ITSELF — the shipped app's own grants, the way a person
launches it — use `open` instead, which carries the port through `--env` and
the log through `--stdout`/`--stderr`:

```sh
open -a ./build/Build/Products/Release/Reelcut.app --env RC_AGENT_PORT=4823 \
   --stdout /tmp/reelcut-4823.log --stderr /tmp/reelcut-4823.log \
   --args -ApplePersistenceIgnoreState YES -AgentServerEnabled YES
```

(One trap: `open -a` of a bundle that already has an instance running
ACTIVATES that instance rather than launching another.) The direct line
below is still the one every script here is run against:

```sh
make app
(RC_AGENT_PORT=4823 ./build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
   -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4823.log 2>&1 &)
python3 tools/proof/phase1_proof.py 4823
python3 tools/proof/phase2_proof.py 4823
python3 tools/proof/phase3_proof.py 4823
python3 tools/proof/phase3_silence_scope.py 4823
python3 tools/proof/silence2_proof.py 4823
python3 tools/proof/phase4_proof.py 4823
python3 tools/proof/phase5_proof.py 4823
python3 tools/proof/phase6_proof.py 4823
python3 tools/proof/phase7_proof.py 4823
python3 tools/proof/phase8_proof.py 4823
python3 tools/proof/phase9_proof.py 4823
python3 tools/proof/patch_door_proof.py 4823
python3 tools/proof/refusal_proof.py 4823
python3 tools/proof/clip_catalog_proof.py 4823
python3 tools/proof/op_catalog_proof.py 4823
python3 tools/proof/op_argument_proof.py 4823
python3 tools/proof/e2_proof.py 4823
```

`e1_proof.py` is the one script that takes TWO ports — its own and the
reference build's — and it is run on its own instance, after the reference
line above:

```sh
(RC_AGENT_PORT=4824 tools/proof/work/e1-reference/build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
   -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4824.log 2>&1 &)
python3 tools/proof/e1_proof.py 4823 4824
```

Road map 5's other two instruments take no port at all — they are offscreen,
and are run beside the two above:

```sh
python3 tools/proof/e1_chrome.py
python3 tools/proof/e2_chrome.py
```

**Phase 9 takes a SECOND argument**, the log path, defaulting to
`/tmp/reelcut-<port>.log` — the path the launch line above writes. It is the
only script that reads the log itself: the startup parity check logs and does
not refuse, so phase 9's fourth part (every op tool declares `scope`) would
leave a clean-looking server on the port, and the count of scope-declaring
tools is re-derived over the wire beside it. **Phase 9 adds nothing to
`media/` and needs no ffmpeg**; it reads `A.mov`, `AV.mov` and `B.mov`, which
are already there.

The offscreen scripts take no port and are run on their own —
`python3 tools/proof/phase2_chrome.py` and its successors through
`phase9_chrome.py`, and beside them road map 5's `e1_chrome.py` and
`e2_chrome.py`, each of which builds its own harness and its own probe from
`app/Sources` (`e1_chrome.py` builds a SECOND harness, from the reference
tree); each paragraph below says what its own one renders into.
Phase 9 has two offscreen scripts: `phase9_probe.py` is a PROBE rather than a
photograph, for the reason its own section gives, and `phase9_chrome.py` is
the photograph of the one thing the harness cannot take — the breadcrumb's
corner, which is only wrong at a NON-ZERO vertical scroll (the header column
and the floating ruler do not overlap at rest) while every harness render is
at scroll 0. It is a probe too, one that builds a bare `TimelineView`, scrolls
it and captures through the harness's own `cacheDisplay` path; the untracked
`work/phase9-corner-probe/` that measured the fix at the time is superseded by
it and deleted. `remaining_probe.py` is a third probe: the app arithmetic
behind `archive/reelcut-remaining.md`'s fixes, one section per item, and its
last section photographs a bare `TimelineView`'s filmstrip tile the same way
`phase9_chrome.py` photographs the corner. `refusal_probe.py` is a fourth:
the three app paths a refusal reaches that no MCP call can, driven through a
live `ProjectDocument`. `phase8_chrome.py` is the one
that puts WINDOWS on screen — its
`dispatch` mode activates a probe for about a second, because a key window is
the thing it measures.

The last line is `<n>/<n> checks passed`, and the exit status is non-zero if
any failed. The log's second line names the port the app actually bound (a
taken port falls back to an ephemeral one), and the same log is where the
startup parity check would complain — `grep "Reelcut: " /tmp/reelcut-4823.log`
must print nothing before a proof run means anything.

**The EXACT tool count belongs to the newest phase's script**, because it is
what tells a stale binary on the port from the build under test: road map 7's
`op_argument_proof.py` asserts **85** since road map 10's G4b (82 from G4a,
79 from G3b, 77 from D3·5), and every script before it keeps
a floor — phases 1 to 9's 63, 65, 68, 70, 71, 73, 73, 73 and 74, and road map
3's 75 — so a later phase's tools never fail an older proof.
That exact count is of PRODUCT tools: road map 11's dev tools are in a Release
catalog and not a Distribution one, so they are counted apart through
`dev_tools.py` (`op_argument_proof.py` section 1).
Road map 5's own proof landed AFTER D3 and asserts FLOORS for that reason:
`e1_proof.py` and `e2_proof.py` want `>= 77` and `>= 57` of this build, so a
later phase that adds a tool does not have to come back and edit them — and
`e1_proof.py`'s `== 75` / `== 55` for the REFERENCE build are exact, because
that tree is frozen at a commit.
**The sixth handover cost nothing**, which is the first time that has
happened to a handover that MOVED the number: road map 5's E1 had already
turned `recording_proof.py`'s 75 into a floor when it added two transition
tools, and road map 7's D3 adds no tool at all, so the 77 is the count the
catalog has carried since E1 and no older script had to be edited. Its PROSE
had drifted, though, and that is what D3·5 corrected:
`recording_proof.py`'s docstring, its section banner and one comment all
still called its 75 exact.
Road map 3's was the fifth handover and cost two rows in
one script, both in the same commit as the tool: `phase9_proof.py`'s `TOOLS`
became a `>=`, and its `APP_STATE_TOOLS` — asserted as an EXACT set, because
an op tool that lost its scope would leave the count right and the set
wrong — gained `record_screen`, the first scopeless tool to arrive after
that set was written. Before it, the handover had happened four times, each
time exactly as it was written down — phase 5 added
`normalize_clip`, took the exact count, and phase 4's `check` became a `>=`;
phase 6 added `add_background` and `add_blurred_background`, took the count
at 73, and phase 5's became a `>=` in the same commit; and phase 7 was the
first handover that cost NOTHING, because it added no tool at all — its
surface is new ARGUMENTS on two tools that already existed, so phase 6's own
`TOOLS = 73` stayed an exact assertion and needed no edit. Phase 8 was the
second such handover and cost nothing either, its three features having no
tool at all by design, so for two phases running THREE scripts asserted 73
exactly. **Phase 9 is what that cost.** `set_scope` is one new tool — view
state, not an op — so the count moved to 74 and all THREE of those exact
assertions had to become floors in one commit, where every earlier handover
touched one script. The sentence to take from it is not that three edits are
expensive but that an exact count left standing in an old script ACCUMULATES:
the next phase to add a tool pays for every script that took the number while
it was still current. It is not decoration:
the phase-4 count was checked against the two new tools taken out of the
catalog and the registry together, where it reads 68 — and it is not the
only check that notices. `check` never stops a run, so that build goes on to
fail every check that names either tool and then ABORTS at 4b's first
`export_captions`; the mutation paragraph below has the whole list.

**Relaunch the instance between proof sessions.** Nothing closes a document —
there is no such tool — so every project a proof makes stays open, and each
open document costs about five threads and fifteen megabytes (measured:
fifteen more documents took one instance from 174 threads and 509 MB to 254
and 734 MB). All three proofs run in sequence against one fresh instance with
room to spare — 26 documents, 197 threads — but somewhere past forty, which
is four or five proof runs on one process, the instance DEADLOCKS:
libdispatch's 64-thread soft limit is reached with every worker blocked in a
synchronous operation, and the main thread then waits for ever on
`-[NSDocument _performFileAccess:]`'s serialization semaphore (seen with
`sample <pid>`; the wedged instance had 459 threads and 2 GB resident). The
port keeps listening and the process sits at 0 % CPU, so it looks alive and
every call simply hangs — `mcp.py` waits 600 s before it gives up. Kill YOUR
instance and start a new one rather than reading a hang as a proof failure.

`phase2_proof.py` covers the catalog floor (65), phase 2's own schema keys —
`name`, `label` and `solo`, which arrived at version 3 — through a saved
`project.json` and a hand-made version-2 fixture, both read back from disk
(the saved file's version assertion is the CURRENT one, 6, not 3: an older
file must open, but what this build writes is what this build writes, so
that number moves with every bump and three phases' scripts carry it),
`set_clip`'s patch rules and refusals, `paste_attributes` (what
travels, what stays, the frame, one undo step) and solo — the last as
exports: with the SAME two-tone project, soloing the back track decodes
sample-for-sample equal to muting the front track and to a project holding
only the back track's tone, a soloed-and-muted track is silent, and a
`render_frame` over a picture track is byte-identical before and after.

`phase3_proof.py` covers the catalog count (68) and the screencast trio.
**Remove Silences**: `detect_silence` finds `silence.mov`'s two quiet spans
to the tick, and threshold, minimum length and padding each move the answer
the way they say (padding 0 widens both spans to the file's exact quiet
stretches, a 1.2 s minimum drops the 1.0 s one, a threshold at full scale
makes the whole clip — and only the clip — read as quiet); then
`ripple_delete_ranges` cuts them, and the four frames either side of the two
cuts are byte-identical to the frames that were either side of the spans, the
export is shorter by exactly the removed total (checked against ffprobe as
well as against the tool), and one undo step named "Remove Silences" puts the
whole project JSON back. The plural's ORDER and its merge are pinned against
the singular op: two disjoint ranges equal the two singular calls applied
right to left and differ from left to right, and a touching or overlapping
pair cuts exactly as the one range it merges to — `next_id` is in the oracle
because that is the only place a merge that did not happen shows up.
**Zoom to Region**: the zoomed frame is MEASURED, not read back. `A.mov`'s
colour-bar edges are located to a fraction of a pixel in the base frame,
where a canvas pixel is a source pixel, and then found again in the frame
rendered at the action's end — they land within 0.01 px of where fit's
arithmetic puts them, the region's 160 source pixels measure 640 canvas
pixels, `fill` magnifies where `fit` does not, a clip turned a quarter turn
zooms at the rotation-aware 2.25 rather than the naive 4 and puts its bars
across the frame instead of down it, and a null region renders byte-identical
to the base. **Obscure**: with one pixelating region every changed pixel is
inside it and nothing outside moved by a byte, `amount` 1 is flat 64-pixel
blocks on the grid anchored at the texture origin, halving the layer's scale
halves the changed area's offset from the canvas centre, clearing the list
returns the frame byte-identically, and the list rule is asserted on the
FRAME: an entry whose fields agree interpolates to the midpoint still, and
one whose `shape` disagrees holds the start state and switches at the end.
Its **schema half is where a later bump shows up**, and phase 6 is the
worked example: the saved `project.json`'s version assertion is the CURRENT
one, and the claim that used to read "obscure is the LAST key of every video
object" now reads "obscure, then blend". Appending `video.blend` falsified
the literal wording BY DESIGN, so the claim moved rather than went away —
what it pins is that a new key lands at the END and never in the middle,
which is the whole of what the append-only rule rests on. A phase that
appends to the video object again moves it again; one that appends anywhere
else leaves it alone.

`phase3_silence_scope.py` is the SCOPE half of Remove Silences, split out
because it needs a fixture the other script's cannot be: two tracks holding
one recording, the front one muted. `phase3_proof.py` measures what the
detector finds where everything is audible; this measures what it must NOT
find where something is not. A voice the mix has silenced reads quiet at
every tick — `SilenceDetector.level` short-circuits on a zero envelope —
while still COVERING its span, so a scope that let one in would answer with
a single cut across the whole clip, and `ripple_delete_ranges` cuts every
unlocked track, taking the audible voiceover under the muted music bed with
it. The three claims: `detect_silence {clips: [<the muted clip>]}` finds
nothing and names no clips; with only that clip selected the opening scope
is `audible`, not `selected` (`Input.defaultScope` is what the sheet's popup
opens on and what disables its "Selected clips" row); and the ordinary
reading over the AUDIBLE clip still finds the fixture's two quiet spans.
Both failing checks answer `[[padding, 10 s − padding]]` on a build without
the fix, so neither can pass against one. It needs no ffmpeg — nothing here
is exported — and runs against the same instance as the rest.

`phase4_proof.py` covers the catalog COUNT (70, the exact one) and phase 4's
three parts. It needs no ffmpeg: nothing in it is exported to a movie.

**Auto captions, end to end** (rewritten by road map 8's W2). The on-device
engine is `SpeechTranscriber` since W2 (spec §11 W-8), which asks for no TCC
grant, so the recogniser is in reach of a script. Section 4a asserts the
three ineligible sources of the contract's D-A7, each refused by name with
the reason that belongs to it (a text clip, a REVERSED clip, a clip of a
silent movie), and a timeline with nothing audible in it refused as that
rather than as a scope. It then runs `transcribe` over `media/speech.mov`:
the pangrams' words come back, `place: false` changes nothing and carries no
`truncated` key, and placed, the cues land as ONE undo step. Last come the two
LANGUAGE tiers: `zz-ZZ` is refused as a misspelling listing the tags that do
exist, and a tag the engine knows whose model is NOT INSTALLED here (fr-FR,
de-DE, ja-JP or ko-KR, the first refused) is refused by name — "a person has
to install it" — placing nothing and pushing no undo step. A host with all
four installed prints a SKIP for that row. The cue builder's four rules are
still proved at their boundaries in `phase4_chrome.py`'s section 8, and on
real speech by `speech_engine_proof.py`.

**Caption export** is where the measurement is. The `.srt` fixture is
written by the script at **25 fps**, where a frame is 40 ms exactly, so
every cue time survives the snap to the frame grid and the round trip —
import, export, and the two files are compared BYTE FOR BYTE. The same
fixture at 30 fps must NOT come back (40 ms is 1.2 frames there, and
`00:00:00,440` returns as `00:00:00,433`), and that half is what makes the
first half a proof rather than a tautology: an exporter that echoed its
input file would pass at 25 and fail at 30. The `.vtt` is DERIVED from the
SubRip in the script — header, no index lines, `.` for `,` — and compared
byte for byte too, on text containing no `&`, `<` or `>`, which WebVTT
escapes and SubRip does not. Then the refusals: no text track, two all-text
tracks (refused with both candidates named by id and name), a named track
holding a movie, a format outside the two containers, and a `.srt` path
asked for as `vtt`, which must write `talk.vtt` and not `talk.srt.vtt`.

**Text animations**, every claim off a rendered PNG. The text is one
left-aligned line of the bundled MONOSPACED font with an even character
count and no spaces, and the font is the whole point: at reveal 0.5 a
monospaced prefix inks EXACTLY half the columns the whole line inks and at
0.25 exactly a quarter, so the check needs no tolerance and a proportional
font would fail it on correct code. Measured, against a reveal-0 frame taken
per KIND with the animation SET — never off a cleared clip, whose reveal is
1 at every t, so a blank taken there would be the static frame a second time
and "neither the static frame nor the empty one" would be one comparison
written twice: `reveal = 1` is byte-identical to no animation at all for all
three kinds, reveal 0 draws nothing at all for each of them, a half-typed
line inks columns only LEFT of the whole line's midpoint and starts at the
same column it does, every pixel where the half-typed frame differs from the
whole one lies to the RIGHT of what it has typed, `word_fade` and
`line_rise` each change the frame at their midpoint, an out-only animation
is whole at the clip's first frame and changed half way through its ramp
(measured against the same kind's empty frame, so "not empty" is a claim
about pixels that are still drawn), and clearing the
animation returns the frame byte-identically. The **stale-texture guard** is
measured in ONE frame rather than two, because a `render_frame` builds its
own compositor and therefore its own texture cache: two clips with an
IDENTICAL text description, started half a second apart, are at different
reveals at the same instant, and one cache serves both — so if the core's
content hash did not cover the reveal the second layer would be handed the
first layer's texture. It reads 216 columns against 108; with the reveal
taken back out of `recipe.rs`'s `text_hash` it reads 216 against 216.
The schema half is the saved `project.json` (version 6 since phase 6 bumped
it, `animation` still the LAST key of every text object — version 6's two
keys landed on the VIDEO and SHAPE objects, so this claim is untouched by
it), a hand-made version-4 fixture that opens and
reads a null animation, and the two refusals — a kind outside the closed
enum, and a negative `in` or `out` named by its dotted key.

Every one of those checks was MUTATION-TESTED against four deliberate
breakages, which is what makes the score mean anything: the reveal taken
out of the content hash, `TextProps.animation` moved off the end, the
`text.animation` range checks deleted and `RC_FORMAT_VERSION` put back to 4
(six checks fail, and only those six — measured against a tree whose current
version was 5, so re-running that one today means putting it back to 5, not
to 4: the version assertions here name the CURRENT version and phase 6 took
it to 6); `Reveal::of` returning "all of it"
always (thirteen when it was run, and the two prose reveal-0 blanks added
since fail under it too — a build with no reveal draws the whole text at
reveal 0, which is exactly why those blanks are taken with the animation SET
and not off the cleared clip, whose reveal is 1 at every t); the grant read
before the scope, a cue's line breaks joined with a space,
`format(for:requested:)` ignoring its argument, `resolveTrack` guessing at an
ambiguity and `ramp` clamped to 0.95 (eighteen); and the two tools taken out
of the catalog and the registry, which is not the three checks it looks like
but SIXTEEN and an abort — the exact count, both "is a tool" checks, the six
schema checks that read `schema_of`'s stand-in (three per missing tool, which
is what that docstring means), `export_captions`' description check, and
every scope and grant refusal in 4a, where `transcribe` comes back "Unknown
tool"; the run then stops at 4b's first `export_captions`, the one call to
either tool that is not wrapped in `error()`. That last one was re-measured
through a PROXY rather than a fourth build — the two rows dropped from
`tools/list` and either call answered `Unknown tool: <name>` in band, which
is the whole of what removing a catalog row and a registry row is over MCP
(`AgentServer.dispatch`) — so the count above is what the script prints, not
what a reader worked out from it.

`phase5_proof.py` covers the catalog COUNT (71, the exact one) and phase 5's
sound. It NEEDS ffmpeg, twice over: to write its fixtures, and to decode
every export to raw PCM. **Nothing in it is believed because the app said
so.** That is the whole design of it, and 5d is why: `ExportLoudness` reports
"what was measured, plus the gain that was applied", so a build whose writer
dropped the gain reports −14.0 LUFS over a file that still holds −6.7, and
every check that read the report back would pass. So the script carries its
own BS.1770-4 — the two K-weighting biquads, the 400 ms blocks at 75 %
overlap, both gates, and the Annex 2 true-peak interpolator — transcribed
from the Recommendation rather than from `Loudness.swift`, and it measures
the WRITTEN FILE.

**The meter is deliberately not here**, and the script's docstring says so
rather than reaching for something adjacent: `LevelMeter` publishes to a view
and has no MCP surface at all, so no call could read a level off it, and
adding a tool so that a proof could exist would be the proof deciding the
product's API. The contract's −20 dBFS claim is a unit-style check against
that type; its resting appearance is what `phase5_chrome.py` photographs.

**Mono** is three claims off the asymmetric fixture: with `mono` on the left
channel equals the right SAMPLE FOR SAMPLE, each of those samples is the MEAN
of the two channels the same timeline writes unfolded (within one 16-bit LSB
— the fold happens in float, ahead of the quantisation the unfolded file
already carries), and setting `mono` and clearing it again writes a file
BYTE-IDENTICAL to the one taken before it was ever set. The middle one is not
decoration: a fold that copied the left channel over the right passes the
first and fails only that.

**Normalise** is read back off the tool and then measured on a file: a
−6 dBFS tone normalises to a WAV whose loudest sample is −1 dBFS ±0.1, and a
−40 dBFS tone — which the model's 4× volume ceiling cannot lift that far —
lands at the −27.95 the result CLAIMED rather than at the −1 it was asked
for, which is the check a build reporting the requested level fails. Then the
refusals by name (a silent clip, a clip whose peaks file the script deleted
off the package, an id that is not a clip, a `peak_db` above 0), the
`skipped` list in a mixed call, and the reversed mirror — measured with a
fixture loud in its first half and quiet in its second, trimmed to its first
1.4 s forwards and backwards, which must read 20 dB apart and reads the same
number twice on a build with the mirror taken out. One thing worth knowing
before adding a check: `cache/peaks/<id>.bin` is written by a fire-and-forget
task, so `Session.media` WAITS for it — a normalise issued in the same breath
as the import legitimately answers "still being analysed", which is how that
refusal is reached on purpose (by deleting the file) rather than by accident.

**Loudness** carries two different tolerances, and the difference is the
point. Integrated loudness is asserted to **±0.1 LU** between the app's
report and this script's own pass over the file, and to ±0.5 LU against the
target — two correct implementations over identical samples agree to about
1e-14, so the tight one is real. **True peak gets ±0.3 dB and two
invariants**, because BS.1770-4's true peak is an ESTIMATE: it is a 4×
oversampling FIR whose Annex 2 allows ±0.4 dB against the real inter-sample
maximum, and two correct implementations differing in tap alignment or in
where they quantise will not agree the way two loudness passes do. A
tolerance alone would pass against a build that reported the SAMPLE peak and
called it true, so it is joined by the two claims that fail such a build:
true peak is never below sample peak, and a 45° fs/4 sine reads at least
2.5 dB above its own sample peak. Beside that sits the standing limit
`app/CLAUDE.md` records — **audio export is not bit-deterministic near a duck ramp
edge** (three exports of one project gave two results differing by 38 samples
of one 16-bit LSB in an 8 ms window at a release edge) — so every fixture
here is duck-free and fade-free, and the byte-identity claims need no
tolerance at all. The ceiling is proved where it BITES: a −20 LUFS programme
with one 10 ms burst near full scale has a 19 dB peak-to-loudness ratio, so
−14 LUFS is capped by the −1 dBTP ceiling, the file lands 6 dB below the
target, and the script's own oversampling pass over it agrees the peak is
under −1.

**WAV and AIFF**: ffprobe reads both as 48 kHz stereo PCM — `pcm_s16le` in
the RIFF, `pcm_s16be` in the IFF, which is the container's decision and not
the encoder's — and the two files of one project decode to IDENTICAL PCM.
That neither is routed to `ImageSequenceWriter` is said three ways: both
carry a `loudness` block, which `Exporter.measuresLoudness` withholds from
every image sequence (the same project exported as GIF reports none); and a
21 s timeline, 630 frames at 30 fps, exports as WAV with all 21 seconds of
samples in it, past that writer's 600-frame cap.

Mutation-tested against **seven** deliberate breakages, one build each, and
the interesting thing is which checks each one reaches. The mono fold skipped
(three fail, all in 5a); the fold turned into "copy the left channel over the
right" (ONE fails — the mean); the reversed mirror returning nil and
`Result.resultDB` reporting the requested level instead of the reached one
(three: the mirror, the clamp's claim, and the export that contradicts it);
the loudness gain dropped in `ExportWriter` and true peak reported as sample
peak (EIGHT — and this is the run that justifies the whole design, because
the app still reported −14.0035 LUFS over a file this script measured at
−6.7035, and reported a true peak of −1.0027 over a file whose peak was
−0.4442, so every check that read the report agreed with it); the
`peak_dbtp`-without-`loudness_lufs` rule removed from `export_overrides.rs`
(one). The last two are the routing, and they ABORT rather than fail, which
is the honest shape of that breakage: with `audio_wav`'s `avf_preset` nulled
every export in the script throws `"wav" is not a container this build can
write` and the run stops after the ten catalog checks, and with only
`audio_aiff` nulled it gets to 62/62 and stops at 5e's AIFF export. A row
handed to the image writer cannot be exported at all, so there is nothing
left to measure about it.

`phase6_proof.py` covers the catalog COUNT (73, the exact one — phase 6 is
the newest phase, so the duty is its) and phase 6's four parts. It needs no
ffmpeg for the blend and gradient claims and uses it only for the one
`qtrle` cross-check card and for the PCM comparison 6c owes.

**Its section 0 is the FIXTURE, scored as checks rather than assumed**, and
that is the design decision the rest of the script rests on. Every absolute
number here is a byte in a PNG, and black is the one value every colour
transform fixes — so existing evidence proves nothing about a mid-tone. The
script builds a canvas at exactly 128/255 grey, renders, and asserts a
corner pixel reads (128, 128, 128, 255); then 64 and 192. **If one drifts,
the FIXTURE fails by name** and the blend checks are not blamed for a
pipeline that moved under them. Every blend expectation is then written
TWICE: once as the formula over the two MEASURED card bytes
(`round(a*b/255)`), which is the real claim about the shader, and once as
the road map's literal 64 / 192 / 255, which is the claim about the
fixture. A wrong formula fails both; a drifting pipeline fails only the
second, and the two are told apart by which line goes red.

**There is no headroom in the ±1/255 tolerance and it is already spent.**
`round(128 × 128 / 255)` is 64 against `0.25 × 255` = 63.75, so a pipeline
that drifted by one would take the multiply check with it — which is what
section 0 exists to catch first. And the thing not to "fix" while reading
those numbers: **this compositor blends in the ENCODED sRGB space,
deliberately** — nothing uses an `_srgb` format, so "multiply of 50 % grey
over 50 % grey is 25 %" is a statement about encoded values and is false in
linear light. That sentence is in the script's docstring, in
`Compositor.metal` and in spec §7.5, because it is the one thing about this
compositor a competent reader will try to correct.

**One check in it exists because of one line of Swift, and it is not the
one that was written for the job.** Metal builds a programmable-blend
pipeline with fixed-function blending still enabled — no error, no warning
— and the finished pixel is then blended a second time. What decides
whether that SHOWS is the DESTINATION's alpha and not the layer's: the
fragment stage returns the finished composite, whose alpha is
`as + ab·(1 - as)`, and over an opaque backdrop that is 1 whatever the
source's own alpha is, so `oneMinusSourceAlpha` is 0 and the second blend
contributes exactly nothing. Section 6's **blended layer at 50 % opacity**
over an opaque backdrop is therefore a real check of a real thing — the
composite at a partial source alpha is `mix(dst, blend(src, dst), 0.5)` —
and is BLIND to the double blend, as is every other fixture in the script,
all of which put a full-canvas opaque card underneath. The mutation run is
how that was learned, not reading. **Section 6b is the check that fails**:
a transparent canvas, a translucent card as the destination, and a second
card at half opacity blended over it, read on the ALPHA channel, where the
mutant lands 32/255 high while the colour moves by two. It is the only
place in this script that reads alpha.

**A blended layer with a SHADOW** (section 4) must have shadow pixels
byte-identical to the same project at `blend: "normal"` while its own
pixels differ, and what it pins is that the shadow's own DRAW stays
fixed-function source-over. It is NOT a guard on `maskState`, and the fear
that used to be written here — the mask pass draws coverage into a texture
cleared to transparent black, so a `multiply` over that is 0 everywhere and
every blended layer's shadow vanishes — is false. That is true of a naive
`src · dst` and false of the premultiplied composite the shader runs, whose
`(1 - ab)·src` term reduces the formula to `src` exactly at `ab` = 0 for
all eight modes; a build passing `state` where `maskState` belongs renders
every shadow correctly and this section stays green. The separation is
DEFENSIVE and worth keeping — it names what the mask pass means, and a
future formula without that term would make the hazard real — but no
document here should call it a bug being held back.

The rest reads as the feature does. The eight modes at the centre pixel,
each against its own formula — and overlay is measured with a **192 source
over a 64 base**, not at 128 over 128, because at 128 the branch condition
sits on the knife edge (128/255 = 0.50196 takes the screen half and gives
128.498, which rounds either way depending on where the comparison is
written), and because 96 is a number an unblended backdrop cannot produce
where 64 is. `blend: "normal"` renders byte-identical to the same project
before the key was ever set, taken IN-SCRIPT by set-and-clear the way phase
5 took `mono`'s baseline. Every frame of a cross-dissolve overlap with a
`multiply` on one half is byte-identical to the same project at `normal`,
which is the renderer's half of the core's transition rule — the core's own
half is a test in `core/tests/evaluate_tests.rs` reading the layer's
`blend` at a tick inside the overlap, which is the check a
renderer-side rule could not have had. And the refusals: `set_video
{blend}` on a nest clip named, `{blend: "normal"}` on one answering "changes
nothing", and a misspelt mode refused by name.

**Gradients** are measured the same way: a single flat-colour gradient
byte-identical to the same solid fill (the cleanest thing the
clip-to-the-path decision buys), a linear ramp monotonic per column and
hitting its stop colours at the ends, at 45° landing the first stop on the
bottom-left corner and the last on the top-right, a radial one reading its
first stop at the centre and its last at both edge midpoints, a gradient on
a `line` changing nothing at all, a three-component stop colour accepted, a
one-stop gradient refused by name, and an UNSORTED stop list ACCEPTED and
drawn as the sorted ramp — that last one pinned deliberately, so a later
reader does not "fix" the core's missing ordering check into a refusal and
break a drag half way through. The stale-cache check is phase 4's text
lesson applied to a shape: change only the gradient and the frame must
change, which is what would catch a Swift side keying its texture on
anything narrower than the recipe's hash.

**The two background commands need a PCM comparison and not just a frame**,
and that is the check the road map's own proof would have missed. Its
wording — "renders byte-identically to the same ops applied by hand over
MCP" — passes with the bug present on BOTH sides, because the bug is
inaudible in a still frame: a blurred copy that kept `enabled.audio` plays
the same recording twice, about +6 dB with comb filtering, and would move
`detect_silence`'s and the level meter's numbers too. So the copy's
`enabled.audio` is read back as FALSE, the copy is checked for no actions
and no `transition_in`, the whole thing is ONE undo step, and an export of
the project with the backdrop decodes sample-for-sample equal to an export
without it.

**6d's oracle** is the road map's: an action from `blur 0` to `blur 1`,
linear, rendered at its midpoint is BYTE-identical to a static `blur 0.5`
on an otherwise identical project. Beside it are the two regressions phase 6
closed — an edit to one filter inside an action must not flatten its
neighbour's ramp, and an earlier action that changed the filter COUNT must
not make an ordinary dial rewrite the clip's base stack — and the partial
entry `{"filters": [{"amount": 1}]}`, refused by index now rather than
silently becoming a blur.

`phase6_chrome.py` is the offscreen half (`python3
tools/proof/phase6_chrome.py`, no port, no media; renders in
`work/chrome6/`), and what it may claim is bounded by what the harness can
see: `build.sh` is a swiftc line over `app/Sources` and never compiles
`Compositor.metal` at all, and the preview well renders BLACK offscreen
because a Metal layer has no drawable — so **no claim about a blend's or a
gradient's PICTURE may be made there**, and its docstring says so first.
The temptation is larger here than it was in phases 3 and 4, because a
gradient IS a picture; the section that edits one is not. What it
photographs is the chrome: the **Blend popup** in Transform, bound to
`video.blend` and measured as the row directly below Opacity by arithmetic
over `DS.controlHeight` and `InspectorMetrics.rowSpacing`, and as eight
distinct drawings of one row; the **computed note** — that it appears for a
non-normal mode over a black canvas with nothing behind, that a non-black
canvas and a visible clip behind each suppress it, and that a HIDDEN track
and a clip with its video switched off do NOT, which is the difference
between "is there a layer" and "does anything draw"; the **Gradient
section** under its own id, below Fill, shut by the design, as many rows
tall as it has stops; and its rows **disabled for `line` and `arrow`** and
the Angle row disabled for `radial`.

**Colours are SOLVED, never hard-coded**, which `phase3_chrome.py`
established and this script needs twice over: a harness PNG carries the
display's ICC profile, and the note is drawn in `DS.accent`, which is
`NSColor.controlAccentColor` — a colour the person at the machine chooses
in System Settings. So the disabled rows are measured as
`disabled = background + α × (enabled − background)` solved per component
over every pixel two renders disagree about, against an ALIGNED pair (a
filled rectangle and a filled line have the same body height, so the rows
sit at the same y and every changed pixel is a change of DRAWING rather
than of position). The answer comes back 0.42 twice, from two different
pairs, which is `InspectorPane`'s own constant — and no colour is written
down anywhere in the file.

**Its section 7 needs an instrument the script builds**, and the reason
generalises: a menu lives in `NSApp.mainMenu` and is never drawn into a
window, so a harness that renders a window cannot photograph one at any
size, and `AppDelegate.buildMainMenu()` is private with the app as its only
caller. So the script writes a forty-line `main.swift`, compiles it against
`app/Sources` with `build.sh`'s own swiftc line, and reads the menu the
delegate actually builds — plus the answers
`EditorViewController.validateUserInterfaceItem` gives for the three new
selectors over four selections. `phase5_chrome.py` established that shape
with its `Loudness.swift` probe; this one compiles the whole module,
because a menu item names a selector on the editor and the delegate names
every other class in the app. It is cached on modification times like the
harness, and a build it cannot make is a scored FAILURE rather than an
exit, so a rotted instrument cannot take the rest of the score down.

Two things it deliberately does not claim, both worth knowing before
someone tries to add them. **The popup's LIST**: a closed `NSPopUpButton`
draws the selected item's title and nothing else, and a menu cannot be
opened offscreen — that the rows are `BlendMode.allCases` in the enum's
order, and that the order is the shader's discriminant, is the core's and
`phase6_proof.py`'s. **Which VERB the note uses**: reading "reads black
here" against "changes nothing here" off a PNG needs OCR, so what is
measured is that the seven notes are seven DIFFERENT drawings — the
sentence names the mode rather than standing still.

One thing about this phase is worth doing EARLY rather than at the end, and
phase 6 is the second phase to learn it: **re-run `phase4_chrome.py` as
soon as the Blend row exists.** That row makes Transform seven rows and
pushes every section below it down about 29 pt, and phase 4's script chose
its window height by arithmetic over the section stack — so a failure there
is the row landing, not the row being wrong, and finding that out after
everything else has been written costs a day.

**The historical cross-build sections run again (2026-09-21).**
`phase5_chrome.py` builds commit `3187c5d7` (before the meter) with that
commit's own Rust library and bridging header. `recording_probe.py` does the
same for `c1dce5f0` (before the welcome button). Both compile the CURRENT
`harness/main.swift` under `HARNESS_REFERENCE_BUILD`, so the paint path is
one instrument. The former FFI-drift skips are retired: a failed current or
historical compile is a scored failure, even if the error names
`rc_project_apply` in `ReelCore.swift`. There is no fallback to a historical
harness. Host-state skips in recording's granted tier remain separate.

`reference_build.py` keeps each caller's archived `app/Sources`, `app/Bridging`
and `core`, Rust target, Swift/Clang modules, binary, Fonts, compiler logs and
atomic stamp under its own `before/` directory. Its content key includes the
resolved historical commit; current sources, core files and staticlib;
current harness, builder, caller and Fonts; compiler/Rust/Cargo/SDK identity,
targets, flags and effective build overrides, including `CARGO_TARGET_*` and
`CARGO_PROFILE_*`. A hit also rechecks extracted source, binary and Fonts
digests. Deleting or changing an output, or changing
same-size/same-mtime input bytes, rebuilds it. The current `core/target`
staticlib is neither linked into nor written by a historical build.
Run `python3 tools/proof/reference_build_selftest.py [--integration]` for a
tiny Git fixture, failure scoring, and optional real compiler mutation.

Cold and warm runs on 2026-09-21 each scored **81/81** for phase 5 and
**29/29** for recording's `--only welcome`, without historical skips. Both
warm runs reported cache hits and kept binary/stamp mtimes unchanged. The
real compiler mutation (`#error` in a temporary guarded harness) failed
both reference builds by name, scored **36/37** in phase 5 while its
independent meter/gain rows ran, and failed recording's two §6b rows without
a historical skip. The full recording probe scored **876/876**, with
**41 skipped by name** because Screen Recording was granted but the console
was locked and `SCShareableContent` listed zero displays. A later unlocked
rerun of `--only host,granted` passed **44/44 with no skips**, including all
41 previously skipped rows; two displays were shareable. These comparisons
claim AppKit chrome geometry and pixels only; they say nothing about the
Metal preview image or live audio.

`phase5_chrome.py` is the other half, and phase 5 splits between the two more
sharply than any phase so far: four of its five features are AUDIO, which a
still frame can hold no opinion about, so everything above is the MCP
script's and what is left for the offscreen renderer is the one thing the
phase draws — the output level meter in the timeline bar. Its sections 1 to 7
(forty-five checks) are byte comparisons of harness PNGs measured against
`TimelineBar`'s own layout constants, and its new instrument is WHAT it
compares against: the second PNG is built from the tree BEFORE the meter
existed — the parent of the commit that added `LevelMeterView.swift`,
extracted with `git archive` and compiled against its matching archived
core and header with the same guarded paint instrument. At
1440 in both appearances, and at 1080 and 1600, the TIMELINE BAR differs in
exactly one 120 × 12 rectangle and nowhere else in the row; at the 900 pt
minimum it does not differ at all, because the meter VANISHES rather than
push a control that shipped.

**The comparison is scoped to that bar, and that is what lets this script
keep running.** A cross-build comparison holds the current tree against one
that ages: phase 6's inspector sections and phase 7's export chrome would
each make a whole-window comparison fail with the meter untouched, and every
earlier phase's script is meant to re-run unchanged. So sections 3, 5 and 6
score only what changed inside the row the meter went into, print what
changed elsewhere without scoring it, and **section 3b stages the future** —
the reference render against a current one whose playhead has moved, which
changes the toolbar's timecode and the ruler and nothing the bar draws, so
the window differs in four places while the bar still differs in exactly the
meter's 4 704 pixels. All five of the script's chrome mutations are bar-local
and it re-measured every one of them at the new scoping, so the row costs it
nothing; a phase that redraws the bar ITSELF has to re-baseline this
comparison, and section 3's rectangle measurements are what will say so. The
reference build is guarded the same way: it is compiled with the current
`harness/main.swift` under the GENERAL `-D HARNESS_REFERENCE_BUILD` flag —
every future non-render mode goes behind the same `#if`, which is why the
flag is not named after the meter. A build it cannot make is a scored
FAILURE rather than an exit, so a rotted reference instrument cannot take
the independent model checks down with it.

**2026-09-23, the sharp pass redrew the bar itself** — the re-baseline the
paragraph above predicted. Four controls in the row now differ from the
pre-meter tree BY DESIGN: the selection block's kind chip and the Snap box
lost their radius, the zoom slider is a `BlockSlider`, and S/M/L's end cells
are square. `sharp_columns(width)` names their columns, full bar height, from
the file's own constants (chip `PADDING`…`+ 8`; Snap box at 476, 13 wide;
the slider at `meter_rect(width).x1 + 48`, 110 wide; S/M/L at
`width − 90`…`width − 12`), so they hold at 900, 1080, 1440 and 1600, and
`sharp()` removes them where each bar-scoped set is MADE — sections 3 (both
appearances, which also feeds `bands`, `extent`, dark == light and section
4), 3b, 5 and 6 — printing the masked count (2 282 px at 1440 dark, not
scored). Everything else in the bar must still be byte-identical to the
reference: **81/81** with the mask. The meter's own fills are square now
too, but they lie inside its rectangle and change no row; the "one ink"
sentence lost its "2 pt corner radius" clause, and 100 % of the meter is
the trough ink.

Its section 8 (twenty-three checks) is the METER'S READING and
is not a picture at all: the contract's −20 dBFS claim is about the model,
the harness has no player so a lit meter could not be photographed, and the
ballistics that would light it belong to the view. It goes through a third
harness mode, `harness meter <request.json> <out.json>`, in `cues`' shape and
for `cues`' reason — the code it calls has no other caller a script can
reach, since nothing in the app reaches the meter without a playing
transport. One of the twenty-three hands that mode four magnitudes (`store`)
rather than a buffer, because the invariant it asks about — RMS never above
peak, which `LevelMeterReading.init` restores across the sink's two atomic
words — is one no real buffer can break, so a check over a measured tone
stays green against a build with the clamp deleted.

Its section 9 (thirteen checks) is the EXPORT GAIN, and it needs a third
instrument again: not the harness, which draws chrome, but a probe the
script writes and compiles from `app/Sources/Loudness.swift` ALONE — that
file has no AVFoundation in it, so `ExportLoudness.resolve` can be handed a
measured programme as four numbers and answer without a mix, a writer or a
file. That is what lets the ceiling be SWEPT rather than sampled: two
hundred true peaks a thousandth of a decibel apart, at the −1 dBTP ceiling
and at the default 0, and every resolved gain lands the shifted peak at or
under it — where a round-to-NEAREST quantisation of the same gain puts
ninety-two of the two hundred OVER, which is the check's whole point, since
one hand-picked case would land on the right side by luck. The other three
claims are the ones a real export cannot stage on purpose: a non-finite true
peak is no headroom rather than infinite headroom (a −40 LUFS programme
carrying an infinity is not boosted 26 dB), it still permits an
ATTENUATION, and it does not read as "Silent", which is what a bare
`isFinite` guard makes of it; and a mix measured PAST full scale says in its
summary that it clipped before it was written, while one that merely came
close does not. The last pair is the limit CLAUDE.md records — the write
pass decodes to Int16, which saturates before the gain reaches it — made
visible in the sentence the user reads rather than left in a paragraph.

`phase7_chrome.py` is phase 7's offscreen half (`python3
tools/proof/phase7_chrome.py`, no port, no media; renders, written stills,
exported files and every probe answer in `work/chrome7/`), and it is the first
chrome script that is mostly NOT a photograph. Phase 7's features are a save
panel, an export sheet and a window of its own: the harness renders an
`EditorViewController`'s content view, none of the three is in it, and no sheet
can be put up offscreen at all. So five of its six sections are PROBES, in
`phase6_chrome.py`'s shape — one `main.swift` compiled against the whole of
`app/Sources` by `build.sh`'s own swiftc line, cached on modification times, a
build it cannot make scored as a FAILURE rather than an exit — with several
MODES behind one binary, because compiling the module costs a minute and phase
7's four corners have nothing else in common.

**It builds a SECOND instrument, and that one is worth knowing before anything
else in the file is read.** A bare swiftc binary has no compiled shader, so
`MetalRenderer.init` returns nil and every export the probe runs fails with
"Metal is not available on this system." — which reads exactly like a queue
defect and is not one. `build_probe` therefore compiles the app's OWN
`app/Resources/Shaders/Compositor.metal` with `xcrun metal` into a
`default.metallib` beside the binary, along with the app's `Fonts` (as
`build.sh` does) and `Blank.mp4`. The answer to the question that raises is
measured rather than assumed: **`Bundle.main.resourceURL` of a bare executable
IS the directory the executable is in**, so `CompositionBuilder`'s placeholder
track finds `Blank.mp4` there and a timeline of nothing but shapes exports —
which is what lets every fixture in the file be a shape card, and the script
need no `media/` and no ffmpeg.

**Its byte claims are made over `apng`, and the reason is measured too.** A
QuickTime movie carries a creation and a modification time at one-second
resolution: two ProRes 4444 exports of one unchanged project came back 207,679
bytes each and differed in exactly SIX bytes, all inside the movie header's
time fields, when they landed in different seconds — and were byte-identical
when they landed in the same one. So a byte comparison of two `.mov` files is a
comparison of two clocks. H.264 is not deterministic at all (2,638 / 2,625 /
2,638 bytes over three exports of one project), which is VideoToolbox's rate
control rather than a defect, and is why the cancel scenario — the only one
making no byte claim — is the only place the script uses it. `apng` has no
clock, goes through `ExporterImageSequence.swift` rather than `ExportWriter`,
and came back byte-identical across processes every time. ProRes 4444's own
claims are `phase7_proof.py`'s, where `ffprobe` can read a pixel format.

Sections 1 and 2 are the two things phase 7a put where a probe can reach them.
The MENU: File ▸ Save Frame… over `saveFrame:`, taking the letter Export…
already has under ⌥⌘ rather than ⌘ — asserted as FLAGS read off `NSEvent`, so
"exactly command and option, and neither shift nor control" is a claim rather
than a number copied into the script — sitting directly under Export… with no
separator between them, and Window ▸ Export Queue over `showExportQueue:` with
no key equivalent at all. Then `validateSaveFrameAction`, which is
load-bearing and not decoration: **false on a zero-duration project and true on
one with a clip**, `nil` for a selector that is not its own, and the two
fixtures' durations scored FIRST, because a check whose precondition never held
would pass against a build whose arm returns `true` unconditionally.
`FrameWriter` is section 2 — the whole vocabulary read off the type, every
spelling `format(for:)` accepts including that `heif` is NOT one of them, and
three files written from one `CGImage` and read back. **The flatten is the
check that needed a fixture designed for it.** Over PREMULTIPLIED pixels a
flatten onto black is numerically the IDENTITY (a transparent pixel is already
0, and `src + dst(1 - a)` at `dst` = 0 is `src`), so a card in that encoding
cannot tell a build that flattens from one that merely drops the alpha channel.
The card is therefore STRAIGHT alpha — a transparent white band, a
half-transparent white band, an opaque one — where an unflattened encode writes
white and a flattened one writes black, and the sample that separates them is
scored beside the two that say the picture arrived at all.

Section 4 is the QUEUE, driven through `ExportQueueController` with **no window
ever ordered front**, which is what that type's AppKit-free design was for. Two
queued jobs write files byte-identical to two single exports through `Exporter`
itself; they run ONE at a time and IN ORDER, read off the controller's own
change notification rather than polled, so a transition between two spins of
the run loop cannot be missed; a cancelled job's half-written file is deleted
and the job behind it still runs; and `remove` refuses a job that has not
finished and takes one that has, after which `clearFinished` drops the row it
left behind. **That last pair is one probe run and the ORDER inside it is the
check**: until the review the run removed BOTH finished rows and only then
asked for a clear, so the clear ran over an already-empty list and answered 0
whatever its body did — `func clearFinished() {}` would have scored a clean
run, while Clear Finished in the queue window did nothing and every finished
row went on holding its `ReelProject`. It removes ONE row now, so the clear is
asked with exactly one finished job in the list and a gutted body answers 1.
**The claim worth the section is
immutability**: the document is EDITED between the enqueue and the run — after
both jobs are queued and before the run loop has been spun once, so the edit
precedes the first frame either job composes — and both files still equal the
PRE-edit singles while a single export of the POST-edit project differs, which
is the check a build that re-read the document would fail and a build that
merely looked immutable would pass. Two of the exports differ only in their
per-job `RecipeOptions`, which is also the one claim about the burn-in a
GIF or APNG could otherwise lose: an image sequence never goes through
`ExportWriter` at all, and an option plumbed only through the export's own
recipe key would leave every one of those files silently un-burnt. Beside it
the burn-in's PLACEMENT is measured on the exported frames at TWO canvas
heights, because it is a FRACTION of the canvas (`BURN_IN_Y_FRACTION`, 94 % of
the way down the frame) and one height cannot say so — 360 is exactly the
height at which that fraction and a hard-coded 158.4 agree.

**Section 3 is a TWO-PROCESS probe and its docstring says what that does and
does not buy.** One process writes a choice through `ExportChoice.remember()`
and a list through `ExportPresetsStore.write()` and exits; a second reads them
back, and every one of the record's nine fields survives with the name cleared,
the uniqueness rule comes back trimmed and case-insensitive, and a CORRUPT
presets file degrades to "no presets" rather than throwing. **The ninth field
is `custom_size` and it took the review to get it read back**, which is worth
recording as the shape of gap to look for: every assertion about the presets
list projected `["name"]`, the remembered record's comparison dict carried
eight keys while its sentence said nine, and so a decoder with
`customSize = nil` in it scored a clean run — while a person reapplying a
preset saved off Custom 3840 × 2160 got the document's own size with the popup
claiming the preset had been applied. It is pinned in both directions now: the
remembered record's must come back nil (it was asked with a size ROW, and
`ExportChoice` calls a record holding both a hand-edited file's state), and the
"Master" preset's whole record is compared field for field against what was
saved, beside the record next to it that must not have grown one. What it proves is
the MECHANISM under the PROBE BINARY's own `UserDefaults` domain, **not under
Reelcut.app's** — no proof script in this tree has ever launched or terminated
the app, so "the sheet reopens on last time's choice after a relaunch" is not a
sentence any of them can say. Two things it touches outside the tree it also
puts back, and the restoration is scored as a check: the probe's defaults
domain is its own (`~/Library/Preferences/phase7probe.plist`, keyed on the
executable name — measured: two runs of one binary share a domain and two
binaries do not) and its one key is removed at the end, while
`ExportPresetsStore` writes the REAL
`~/Library/Application Support/Reelcut/ExportPresets.json`, because its path is
`AppSupport.directory`'s and `NSHomeDirectory()` ignores `$HOME` on macOS
(measured) — so the script copies that file aside first and restores it in a
`finally`.

Section 5 is the one PHOTOGRAPH, and it is the Document tab's transparency
note. Two OPAQUE canvases (black against white) change the summary line and the
swatch and MOVE NOTHING, which is the control the rest of the section needs; a
translucent one pushes the Markers section under Appearance down by an exact
whole number of points with every row of the band explained and the runner-up
far worse; the growth is one LABEL row rather than a control row, solved from
the shift; and nothing above the Appearance header moves at all, so the note is
inside the section whose value it is about. Its ink is compared against the
Export button's fill measured in the SAME render — `InspectorNoteLabel` draws
in `DS.accent`, which is `NSColor.controlAccentColor`, so no colour is written
down here any more than in phase 3's or phase 6's chrome — and the 0.995
threshold is pinned from BOTH sides, at 0.99 and at 0.999.

Mutation-tested against **fifteen** deliberate breakages, each a copy of a
clean snapshot with ONE edit in it and the script run from inside that copy —
never against the working tree, because a second agent was editing the same
repository at the time and a proof measured against somebody else's mutant is
not a measurement. **The scores below are that run's own, out of the 77 checks
the script carried when it was made; it scores 78 today** — the review added
the preset's whole-record check and repaired the clear, and neither mutant set
was re-run against the repair. Thirteen died and the two that lived are the interesting
half. Dropping `FrameWriter`'s flatten (75/77) and flattening onto WHITE
instead (75/77) each kill the same two: the transparent band's sample, and the
one beside it that says the picture arrived at all — which is what the straight-alpha
card was built for, since ImageIO really does write white there when the
flatten is gone. Teaching `format(for:)` the spelling `heif` (76/77) kills the
one check written to forbid it. The validator arm returning `true`
unconditionally (75/77) kills the zero-duration refusal and the arm's own
answer. Giving Save Frame plain ⌘E (75/77) kills the letter and the modifier
pair, and turns up a fact worth keeping: AppKit BLANKS a duplicate key
equivalent in one menu, so that build's Save Frame came back with no key at all
rather than with Export…'s — the modifier is not a nicety. Making the queue's
`remove` take an unfinished job (75/77) kills both halves of that rule; making
`start` launch every waiting job at once (66/77) kills ELEVEN, which is the
queue's whole design measured in one line, and leaves job 1 orphaned in
`.running` for ever, so the run also demonstrates that two concurrent
`Exporter`s deadlock. Appending a preset instead of replacing it (72/77) fails
five checks across both processes; letting `remember()` keep the name (75/77)
fails two. On the chrome side, a `transparencyNote` that never fires (74/77)
takes the shift, the label-row solve and the accent-ink comparison, and moving
its threshold from 0.995 to 0.9 (76/77) takes the boundary check alone —
exactly the one written for it. And handing `ImageSequenceWriter` the default
`RecipeOptions` (72/77) — the defect the contract names as the one a burn-in
proof would silently miss — takes five, including both placement checks,
because nothing is drawn at all.

**The two survivors are both redundant-path mutants, and both are recorded in
the script rather than papered over.** Deleting `ExportQueueController`'s own
`removeItem` on a cancelled job scores 77/77, because
`AVAssetWriter.cancelWriting()` already removes its part-file and
`ImageSequenceWriter` already removes its own — so that check is worded as the
OUTCOME (nothing is left behind) and not as a guard on that line, and the line
stays because it says what the queue intends. Stopping `ExportWriter.cancel`
from calling `reader.cancelReading()` scores 77/77 for the same shape of
reason: `Exporter.cancel` also sets `cancelRequested`, which the pump tests per
sample, and the reader call only wakes a pump blocked inside
`copyNextSampleBuffer`. **The mutant that DOES kill the cancel checks** — the
queue marking a running job "Stopping…" and never asking the exporter to
stop — scores 75/77, taking the cancelled-state check and the one that says the
queue carries on afterwards. A check nothing can break is worth finding out
about; a check whose only mutant is redundant is worth rewording rather than
deleting.

**The run missed two mutants that a READER then found, and both are the same
shape: a check whose precondition had already been consumed.** `func
clearFinished() {}` and `customSize = nil` in `ExportChoice`'s decoder would
each have scored a clean run — the first because the probe emptied the queue
with `remove` before asking for the clear, the second because every assertion
about the presets list projected `["name"]`. Neither was among the fifteen, and
that is the point: a mutant set is a sample of the edits somebody might make,
not a search for the checks that cannot fail, and nothing but reading a probe
against its own assertions finds those.
Both are repaired above, and the repairs are the two checks the numbers in this
paragraph predate.

The script's own timeouts came out of that run. Every spin is proportionate
rather than generous — three minutes where two queued `apng` jobs take under a
second — because a DEADLOCKED queue is a real outcome (the `all-at-once` mutant
produces one) and a proof that hangs for ten minutes is a worse detection than
one that fails in three. It cost the mutation runner the same lesson, one level
up: the first batch was aborted by an unhandled `TimeoutExpired` on that very
mutant.

`phase8_proof.py` is phase 8's MCP half (`python3 tools/proof/phase8_proof.py
4861`, six sections, 79 checks), and phase 8 is the first phase whose features
have NO MCP surface at all: View ▸ Preview Quality edits nothing, the preview
window is an `NSPanel` and a second `AVPlayerLayer`, and the Media tab's
search, sort and "unused only" are a pane's own state. Adding a tool so that a
proof could exist would be the proof deciding the product's API — settled for
phase 5's level meter, inherited by phase 7's export queue, inherited again
here — so the file is two claims made with two different instruments, plus the
one answer phase 8 did change over the wire.

**It is the only script here that LAUNCHES Reelcut**, and section 1 is why.
`PreviewQuality.stored()` reads `UserDefaults.standard`, so a quality can be
put into a running app through the ARGUMENT DOMAIN at launch, exactly as
`-ApplePersistenceIgnoreState` and `-AgentServerEnabled` already travel. So the
section starts TWO instances of the binary under test on `PORT + 1` and
`PORT + 2` — one with the key absent (Full), one with `-ReelcutPreviewQuality 2`
(Quarter) — builds the identical fixture through both, and byte-compares what
comes out: three `render_frame` PNGs, an `apng` and a `gif` (both go through
`ExporterImageSequence.swift`, which has no clock in it), and a `prores_422`
compared on DECODED PIXELS, because phase 7 measured the six header bytes that
make a byte comparison of two `.mov` files a comparison of two clocks. It kills
only the two pids it started — `subprocess.Popen`'s own, SIGTERM then
SIGKILL — and nothing in the file reads `pgrep`. **Section 0 scores the launch
mechanism before section 1 leans on it**, phase 7's shape for its two ffmpeg
instruments: a build in which the argument never reached the app would make
every byte comparison pass by rendering the same quality twice, and no check
inside section 1 could tell. It EXTRACTS `enum PreviewQuality` from the app's
own source, compiles it, and runs it bare and with the argument — and pins the
trap under it, which is that an argument-domain value arrives as a **String**,
so `stored()`'s `object(forKey:) != nil` then `integer(forKey:)` spelling is
load-bearing and an `object(forKey:) as? Int` would read Full for every launch
argument ever passed.

**Section 5 exists because sections 0 and 1 together prove nothing about the
feature, and that is measured rather than argued.** No MCP call reaches the
player: `render_frame` builds its own composition and `export` builds two more,
and none of the three is the item the `AVPlayerLayer` is showing — so section 1
can say the setting does not LEAK and can never say it DOES anything. A build
whose `previewComposition` returned its argument unconditionally, the feature
deleted outright, scored a clean **65/65** against this file before section 5
was written. So section 5 is a PROBE, in the shape CLAUDE.md states for app
arithmetic no script can reach: every file in `app/Sources` except its
`main.swift` compiled against a `main.swift` of the script's own
(`harness/build.sh`'s swiftc line, cached on modification times, a build it
cannot make scored as a FAILURE rather than an exit), opening the package the
section just saved, putting an `EditorViewController` in a window and reading
the render size of the composition on the player's current item — 640 × 360 at
Full, 320 × 180 at Half, 160 × 90 at Quarter, each cross-multiplied against the
canvas so the aspect claim is an INTEGER identity and never a tolerance. The
same probe drives View ▸ Preview Quality ▸ itself with an `NSMenuItem` carrying
the row's tag, so the LIVE item's re-assignment is scored in both directions
(an in-place mutation of the retained composition would leave the player at
Full, since `AVPlayerItem.videoComposition` is a COPY property), and reads back
the validator's checkmark. **It is the app's own sources in a second process
and not the shipped binary** — the standard the offscreen harness sets, said
out loud rather than implied.

**Section 2 is the one place phase 8 changed an answer an agent can read.**
"Is this media used" was written twice in Swift and both spellings filtered
`snapshot.clips` — the TOP LEVEL alone — while the core refuses against
`every_clip()`, the timeline's clips CHAINED with every nest's. So media used
only inside a compound clip walked past the Swift guard with a user count of
zero and was refused by the core with a reason-less "nothing changed", which
reached a caller as the shared "Remove Media made no change…" and told it
nothing. (Deepening D2·2 shortened that shared sentence — an identity now says
only that the project is already in that state — D2·3 gave the core's own rule
a sentence naming the clips, and D2·4 deleted the handler's count so that
sentence is what arrives. `MediaUsage.swift`'s one spelling stays, with the
Media tab's alert as its only caller.) The section builds that exact fixture
over the wire — import, a clip,
`nest` — and asserts the core's sentence WHOLE, which names the CLIP where the
deleted guard named the file and a count; that an identity's "made no change"
is NOT what comes back; that `with_clips: true` takes the
entry and the NESTED clip while leaving the nest clip itself on the timeline;
and that one undo restores the whole project JSON. The check with the sharpest
teeth is the both-levels one: media used once at the top level AND once inside
a nest is refused naming BOTH clips, where anything counting the top level
alone names one. Sections 3 and 4 are the
"nothing else moved" half: the catalog is EXACTLY 73 for the fourth phase
running (phase 8 adds no op and no tool), no tool name mentions the preview or
the quality, the parity log is empty for all three instances the run touches,
the schema is still version 6 in `get_project` and in a saved `project.json`,
and the three view-state calls an agent has leave the project JSON and the
frame at one instant byte-identical.

Its fixture is `media/A.mov`, `B.mov` and `C.mov`, all three already in the
tree — three files rather than one because a second `import_media` of one path
is an identity edit and is refused. `ffmpeg` is needed for the ProRes decode
alone; `swiftc` and `core/target/release/libreelcut_core.a` for the two probes,
whose binaries live in `work/phase8-probe/` and `work/phase8-player/`. Packages
are `<name>-<pid>.reelcut`, phase 2's rule, and its exports are pid-named,
phase 5's. Run it against a port that already holds an instance; it launches
its own two beside it.

Mutation-tested against **four** deliberate breakages, each a copy of a clean
snapshot with ONE edit in it, the app REBUILT AND RELAUNCHED, and the script
run from inside the copy — never against the working tree, since a second lane
was editing the same repository. The copy scored 65/65 before the first edit,
so nothing below is the copy's own fault, and each mutant was confirmed to
CHANGE BEHAVIOUR before its score was believed. The preview scale moved into
`CompositionBuilder.build`, which every path shares — the exact design phase 8a
exists to prevent — scores **69/79**: all three `render_frame` comparisons,
both image-sequence exports, the ProRes pixels, and three of section 5's, where
the double scaling shows as a player at 48 × 27. It is also what proves the
launch argument reaches `PreviewQuality.stored()` INSIDE a running Reelcut,
which nothing in a clean run can observe: the Quarter instance renders 160 × 90
where the Full one renders 640 × 360. `MediaUsage.clipsUsing` losing its nest
walk scores **75/79**, and reproduces the pre-phase-8 defect exactly — the bare
"made no change" sentence for nested-only media, and "used by 1 clip" where the
truth is 2. `previewComposition` returning its argument scores **74/79**,
taking five of section 5's; **it scored 65/65 — a clean run — against the same
script before section 5 existed**, which is the whole argument for the probe
and is why it is recorded here rather than left to be discovered. **The
survivor is `usesMedia` alone losing its nest walk** (79/79, exactly the
baseline): it is a REAL behavioural change — a probe over the same sources
answers `usesMedia` false and `clipsUsing` 1 for the same nested-only file —
and no tool in the catalog calls that spelling, so nothing over MCP can see it.
That is the Media tab's "unused only" filter, and it is `phase8_chrome.py`'s to
kill.

What no script here can claim about phase 8, gathered so it is not spread
through the sections. Section 5 proves the player is asked for a smaller
buffer; it says nothing about whether the preview is FASTER, and nothing about
whether what the scaler puts on screen is the Full frame resampled once rather
than a different picture — a render size is neither a frame rate nor a pixel.
Nothing here opens the preview window, so that the second `AVPlayerLayer` shows
the same frames as the first, and that ⇧⌘P reaches it, are a person's. Nothing
here narrows the Media list, scrolls to a revealed clip, or asks
`MediaUsage.usesMedia` and `timelineClipsUsing` anything at all — the surviving
mutant above is what that costs, and those are the offscreen lane's. And the
two instances section 1 launches are compared to each other and never to a
person's eyes: two builds agreeing byte for byte is an isolation claim, not a
picture.

`phase9_proof.py` is phase 9's MCP half (`python3 tools/proof/phase9_proof.py
[port] [log path]`, **216/216** on 2026-09-19 — 214 when section 9 landed,
and two rows more since road map 7, whose records carry the 216 — about seven
seconds). It was 184 for the
phase's own gate and twenty-eight checks short of what phase 9 measured: the
review's fix wave proved two MCP-coherence fixes in
`work/lane9_marker_scope_mcp.py`, untracked (28 checks — the "29" this tree's
documents quoted for a while counted its `def check` line), and a fix with no
permanent proof is the shape this tree does not accept. **Section 9 is that
script folded in**, sentence for sentence, with the fixture rebuilt on
`fresh()` and every id read back through `get_project`, plus two checks the
fold added, so it is thirty. The
two fixes are both about a scope the caller INHERITED from `set_scope` rather
than asked for, which the core cannot tell from an explicit one, so both are
the app's (`AgentServer+Scope.swift`): (a) `add_marker`, and `set_marker`
carrying a `time`, are refused BEFORE the edit — a marker's time is the
timeline's and every tick in the call is the nest's, `add_marker`'s default
`at` most of all, since the playhead inside a nest is nest-local (the section
reads it as 0 where the timeline's is 1,200,000) — while `set_marker`'s name,
chapter and color apply and are reported as having gone to the document; an
EXPLICIT scope still hears `core/src/scope.rs`'s own sentence, unchanged, with
the nest open as well as named. (b) A result reports where its ops LANDED:
`scope` is the nest they were stamped with and `document_ops` names any op the
document-level list sent to the document instead, so `set_canvas` inside a
nest answers `document_ops: [set_canvas]` where it used to answer the open
view's `scope`, and a result with no scope anywhere carries neither key. Three
checks are the fold's own, not the lane's: the "explicit `at` is refused
identically" comparison is `is not None and ==` rather than `==`, because under
a build whose refusal is gone both calls succeed and `None == None` scored it
green; the `at must be a time in ticks (600000 per second).` refusal is matched
verbatim, so the "argument reader speaks first" claim beside it is pinned to
one voice; and the `undo` of an inherited-scope `remove_marker` is checked to
put the marker back on the DOCUMENT, renamed and chaptered, because three
explicit-scope refusals below it resolve the marker's id against the timeline
and a marker the undo had not restored would make them answer "No marker has
id" and read as scope refusals gone wrong. **Its two mutants, each in a copy of
the tree under `/tmp` with one edit, `make app` run and the copy's own binary
relaunched on its own port**: `checkDocumentLevelTicks` made a no-op scores
**209/214** — the no-`at` refusal, its way-out sentence, the identical
explicit-`at` refusal, `set_marker`'s `time` refusal and "nothing was placed"
(three markers where there was one) — and `scopeLanding` put back to the
unconditional `if let scope = effectiveScope(document)` echo scores
**209/214** — the five `document_ops` claims, `set_marker` name and chapter,
`remove_marker`, `set_canvas` and `remove_media`, every one answering the
view's `scope` instead. Otherwise it is deliberately
the SMALLER half of the phase: `phase9_probe.py` below already owns everything
the app decides before a tool call leaves it, so nothing here repeats it and
the two touch the same ideas from opposite sides — the probe reads the JSON an
op leaves with, this reads what a document that got one looks like afterwards.
Eleven sections. **The oracle is the phase's own, and the sameness in it is not
this script's to define**: `content` and `contents` are
`core/tests/common/mod.rs`'s pair transcribed key for key — strip `id`, `track`
and each action's `id`, key each clip by its start and by the INDEX of the
track it sits on, sort — which is where that pair lives BECAUSE this script
wanted it too, and a looser rule invented here would make `nest`/`unnest`'s
identity claim and phase 9's two different claims wearing one sentence. The
table is the road map's seven plus twenty-five more, thirty-two rows, and each
is scored TWICE: the two halves agree, AND each differs from the untouched
round trip — without the second, a build in which the scoped op silently did
nothing would agree perfectly with one in which the top-level op silently did
nothing and thirty-two rows would pass green. The extra rows are chosen for
what they alone could get wrong: the three that mint a TRACK inside the nest
(`detach_audio`, `add_background`, `add_blurred_background`), the two that
SOLVE against a canvas (`add_zoom_action`, `add_background`), the one that
reads the SOURCE's pixel size, the four that read a plan segment, the range
family and the two transition ops. Its fixture never changes the canvas for
exactly that reason, and the nest clip starts at 0 so both halves can send the
same time arguments — the core fixture's two reasons, restated because a
reader here cannot see that file.

**"The corresponding region of the outer frame" is an arithmetic and the
docstring spells it out.** A nest is composited at its frozen size and placed
as one layer, so at the identity transform the fold contributes scale 1 and no
offset and the region is the centred `nest.width × nest.height` rectangle —
1:1, unresampled. Two things make it exact rather than approximate: the
comparison is a byte comparison of decoded pixels, all four channels, every
pixel; and the centre never falls between them, because `set_canvas` refuses an
odd dimension by name and a nest's frozen size IS a canvas size, so
`canvas − nest` is even in both axes for any project the ops can build. So it
is not a claim that holds at one size, and section 3 makes it at three —
640 × 360 (the whole frame), 1280 × 720, and 1000 × 800, which is neither a
multiple of the nest nor its aspect — with 0 of 230,400 pixels differing each
time, over content that includes a shape BIGGER than the nest's canvas so that
the recipe's `clip_rect` (which cuts the outer render) is compared against the
view's own canvas edge (which cuts the inner one) exactly where they act. The
control is the same comparison at `scale: 0.5`, which differs in 198,045 of
230,400.

**Section 7 is the wide `Err` arm**, the phase's most surprising contract and
the one nothing but a document AT a cap can exercise: 63 tracks counted across
the timeline and every nest, then a scoped `add_track` into a nest holding
one — which SUCCEEDS at 64 and is an `Err` at 65, naming the DOCUMENT's total
although the view it was applied to holds two — and eight levels of nesting
built one scoped `nest` at a time, whose ninth is `nests are more than 8 deep`.
Both check the document is unchanged afterwards.

Two things the script found that were not in anyone's plan. **Four of the seven
refusals cannot be reached without a fixture**: `set_marker`, `remove_marker`,
`relink_media` and `remove_media` are answered by the APP's own id readers
before the core is asked anything, and `add_media` by its descriptor reader, so
a project with no markers and no media scores four passes on messages that say
nothing about scoping at all. Section 6 therefore carries a marker, a media in
use and a media in NOBODY's use (a media in use is refused for being in use,
ahead of the scope), and copies the media row back as a descriptor. And the
`set_range` limit road map 2 records is measurable rather than merely stated:
inside a nest whose own duration is 1,200,000, `set_range {start: 0}` defaults
its end to the DOCUMENT's 2,400,000 where `set_playhead` is nest-local. Section
9 pins it — a limit nobody measures is a limit nobody knows has moved — and
pins beside it that the range is cleared on the way OUT as well as in.

Mutation-tested against **nine** deliberate breakages, each in a copy of the
tree under `/tmp` with ONE edit in it, `make app` run and the app RELAUNCHED
before each score, and the script run from inside the copy — never against the
working tree, since a second lane was editing the same repository. The copy
scored 184/184 clean before and after every mutant, and each patch was verified
to have changed the file before its score was believed. **Eight killed.**
`refused_inside` answering `None` for everything: **176/184**, seven — and the
detail worth keeping is that `add_marker` and `remove_media` then answer OK and
change nothing, because the merge discards markers and the view's media never
mattered, which is exactly the "reports success, did nothing" failure the
refusal list exists to prevent. `apply_scoped` judging the VIEW instead of the
merged parent: **180/184**, four, and the 65th track leaves a document its own
writer will not serialise. The view composited at the PARENT's canvas size:
**180/184** — and here the region comparison ALONE would have survived, because
inner and outer then have the same size and the comparison degenerates into a
whole-frame identity; the render-size checks beside it are what kill it, which
is the argument for having both. `effectiveScope` dropping `?? document.scope`:
**177/179**. `merge_scope` not writing `media` back: **182/183**, and the one
failure is section 2's paste, which answers `clip 9 in nest 5 refers to unknown
media 8` — the sentence `core/src/scope.rs`'s own doc predicts. The view
carrying the parent's MARKERS: **183/184**, and this one is worth reading twice
because the core wave recorded the same mutant as EQUIVALENT: the merge
discards what the view did to them, so no core test can see it, but
`get_project` inside a scope REPORTS the view, so over the wire the markers
that should not be there are visible. A view somebody can look at is a
contract, and this is the check that makes it one. The open view overwriting an
op's explicit scope — the seam defect the orchestrator measured and fixed, put
back: **182/184**. And the scoped nest's row keeping its own clips in the view:
**81/120**, thirty-nine failures and every scoped op refused as a duplicate id.
**The survivor is `merge_scope` dropping the "union first, orphans after" rule**
(184/184, exactly the baseline). It is a real behavioural change and an honest
gap: it bites only when `unnest` runs INSIDE a scope on an inner nest that a
TIMELINE clip also shows, and nothing here stages two clips sharing one nest.
`core/tests/scope.rs` owns it —
`unnest_inside_a_scope_keeps_a_nest_a_timeline_clip_still_shows` — and the
merge is core-side, so an MCP mirror would be redundancy rather than reach.

What no script can claim about phase 9, gathered so it is not spread through
the sections. The gestures and the chrome are not this script's: ⌘↓ / ⌘↑, the
double-click that enters, and the breadcrumb in the ruler's 132 × 22 pt
corner are a PICTURE and a click count, and `phase9_chrome.py` (its own
section below) is what photographs the corner SCROLLED and delivers the clicks
— the probe reads `NestScope.names`, which is what the breadcrumb prints, and
the chrome script reads what the corner draws. Nothing here says a nest PLAYS:
a scoped
composition's audio and its 60 fps are the two things spec §10 has always left
to a person at the machine. The identity between the handle `rc_project_scoped`
returns and the view an edit is applied to is `core/tests/scope.rs`'s claim,
made in-process against one `scoped_view`; what this file adds is that the app,
the renderer and the tools all agree with that handle once it is open. And
three sections EXIT EARLY under a mutant that breaks scoping outright, which is
why `double-ids` scores out of 120 rather than 184 — 184 being the baseline at
the time; the script is 216 now (214 when section 9 landed), and the nine have not
been re-run against it — `scoped_edit` turns the first refused op of a section into
a scored failure and stops, because a crash is a worse detection than a failure
and a section that raised would leave every claim below it unrun.

`media/A.mov`, `AV.mov` and `B.mov` are all it reads and it writes nothing to
`media/`: `AV.mov` is the oracle's media clip (eight of the thirty-two rows
mean nothing on a shape), `A.mov` is sections 6 and 9's media in nobody's use,
and `B.mov` is only ever a PATH inside a paste payload. Its version packages are
`work/phase9-v<n>.reelcut` at FIXED names, which is safe for phase 2's reason
inverted — they are never saved through the document machinery, only read — and
it opens SIXTEEN documents in the instance (ten `new_project` — one per
section that needs a clean fixture, and section 7 needs two — and six
`open_project`), so the relaunch
rule below is not optional for it: two runs on one process is thirty-two, and
the deadlock is somewhere past forty. No `ffmpeg`, no `swiftc`, no window server
grant.

`media/` and `work/` are ignored: the movies are regenerable from the lines
above and the projects are rebuilt on every run. Phase 2's packages are
named `<name>-<pid>.reelcut` rather than `<name>.reelcut`, and each run
deletes the earlier ones under its name: a `project` path is matched against
every document the instance has open, there is no tool that closes one, and
once two earlier runs have left SAVED documents at a fixed path the app
answers for an old one (measured; phase 1 never saves, so its fixed names
survive a third run). A fresh path per run keeps a third phase-2 run against
one instance as honest as the first. Phase 3's packages are named the same
way and its two exports are not: an export path is never matched against an
open document, so `cut-before.mp4` and `cut-after.mp4` are overwritten rather
than accumulated. Phase 4 splits the same way — packages per pid, and the
caption files it reads and writes at fixed names, since a `.srt` is neither
read nor written through the document machinery. Phase 5 puts the pid on its
EXPORTS as well as on its packages, because half its claims are byte
comparisons between two files and a second run must never find the first
run's; its fixtures live under `work/fixtures/` and are rewritten every time.
Phase 6 keeps both for the same two reasons. **Phase 7 is split, and the split
is per SCRIPT rather than per phase** — the sentence that used to stand here
said the phase needed neither device, which is true of one of its two scripts
and false of the other. `phase7_chrome.py` needs neither: nothing IT makes is
ever handed to a running app, because the harness and the probe are fresh
processes that open a package off disk, so its packages (`work/p7-<name>.reelcut`)
and everything under `work/chrome7/` keep fixed names and are rewritten on
every run. `phase7_proof.py` keeps BOTH: it opens twelve documents in the
running binary through `new_project`, at twelve pid-named package paths, for
phase 2's measured reason, and its exports and stills are pid-named for phase
5's. Two runs of either at once would collide, and there is no reason to start
two.

## The offscreen harness (no running app)

`harness/` is CLAUDE.md's "Seeing the chrome": `harness/main.swift` compiles
with every `app/Sources/*.swift` but the app's own `main.swift`, links the
staticlib, opens a package from disk and `cacheDisplay`s the editor into a
PNG — `harness/build.sh` builds it into `work/harness/` (about 30 s, skipped
when the binary is newer than the sources, `harness/main.swift`, `build.sh`
itself and the staticlib, so a change to the build line makes the binary
stale; `--force` rebuilds) with `-D REELCUT_DEV_TOOLS`, as the app's
Debug and Release set it (road map 11 V0), so the harness links what the
app links; the other probes' own `swiftc` lines stay flag-off, as
Distribution is — and pins every `UserDefaults` key the chrome reads — the
persisted view state, the Document tab's `ReelcutInspectorRescaleClips`
checkbox and `AppleShowScrollBars` — in the argument domain, and captures on
SETTLE rather than after a fixed number of runloop turns, so two renders of
one package are byte-identical on one machine. Neither of those is what
earns the byte identity on its own: the harness spent phase 4 writing two
different PNGs for one package (nine renders one way, three the other, in
twelve) because of an ambiguous constraint in the app —
`InspectorPane.swift`'s bottom pin tying with a section's own hugging — and
`phase3_chrome.py` scored anywhere from 29 to 33 out of 33 as a result. If a
chrome proof ever starts wobbling again, that is the shape to look for
first: a render that is stable within a process and different across
processes is an Auto Layout ambiguity, and no amount of extra spinning will
settle it. `phase2_chrome.py` is the
proof that uses it: it writes six one-text-clip packages by hand under
`work/`, renders each, decodes the PNGs in pure Python and measures where
the changed pixels landed against rectangles from the layout constants —
`python3 tools/proof/phase2_chrome.py`, no port, no media; the renders and
crops of the three name places stay in `work/chrome/`.

`phase3_chrome.py` is the same shape (`python3 tools/proof/phase3_chrome.py`,
no port, no media; renders in `work/chrome3/`) and needed two new harness
arguments to reach what it claims, both view state no package carries and
both defaulting to `-`, so a nine-argument call renders exactly the bytes it
always did:

```
harness … [clip|media|document] [candidateSpans] [expandSections]
```

`candidateSpans` is `start-end` pairs in SECONDS (`"1-2,6-7"`) for
`TimelineView.candidateSpans` — only the Remove Silences sheet sets it in the
app, and a sheet cannot be put up offscreen, so without it the candidate wash
could not be photographed at all. `expandSections` is `InspectorSection` ids
to open (`"video.obscure"`), because a section built `defaultExpanded: false`
shows nothing but its header. The proof then measures the wash on the ruler
AND the lanes, that it lies UNDER the clips, and — solving for α from two
different backgrounds — that it is `DS.timelineCandidateShade`'s 0.24 and not
`DS.timelineRangeShade`'s 0.12; and, on the inspector side, that the closed
Obscure section's summary tracks the list while the open one grows by
exactly six rows per region. Nothing about the PICTURE is claimed: the
preview well renders black offscreen.

Phase 4 needed something else again, and took a second MODE rather than a
twelfth argument, because it renders nothing at all:

```
harness cues <words.json> <out.json>
```

reads `{"fps": [30, 1], "words": [{"text": "…", "start": 0, "end": 300000}]}`
— TICKS, because a frame at 30 fps is 20 000 of them and 0.0333… of a
second, and a fixture in seconds could not say "exactly one frame" exactly —
and writes the cues `CaptionCues.build` makes of that list, each with its
`start`, `end`, `text`, `tag` and the pair of times `ReelTime.snapToFrame`
puts on the frame grid next. It belongs to the harness because the harness
is the only binary in the tree that links `app/Sources` outside the app, and
that is the ONLY way the four cue rules can be reached without a person at
the machine: in the app nothing calls `CaptionCues` until a recogniser has
produced words, and until road map 8's W2 the recogniser produced none
without a Speech Recognition grant only a frontmost app could be given
(since W2 `phase4_proof.py` and `speech_engine_proof.py` reach them over MCP
as well). The mode is answered
before a package is opened or a default is pinned, the way `welcome` is, and
every render argument keeps the position it had — added, not rearranged,
because `phase2_chrome.py`, `phase3_chrome.py` and `phase4_chrome.py` all
depend on that order.

Road map 6's c1-chrome took a fourth RENDER target rather than a mode of its
own kind:

```
harness settings <out.png> <light|dark>
```

renders the Settings window (road map 6 §5d) the way `welcome` renders the
no-document window — a WINDOW, so `cacheDisplay` can have it, where a sheet
cannot be put up offscreen at all. **It builds its own
`SettingsWindowController` with a `MemoryStore` and an EMPTY environment and
never touches `.shared` or `AssemblyAIConfiguration.store()`**, and that is a
rule rather than a convenience: `Harness.pinDefaults` REPLACES the argument
domain a few lines earlier (`setVolatileDomain`), which wipes
`-RCSecretFolder` and `-RCAssemblyAIEndpoint`, so after it `store()` is the
person's real `FileStore` on `~/Library/Application Support/Reelcut/` — and
Save and Remove in that window are exactly the code that would write and
delete that file. The empty environment is why the photograph says "No API
key is set." on a machine whose shell has a real `RC_ASSEMBLYAI_KEY` in it.
`pinDefaults` also gained `ReelcutCaptionEngine` and
`ReelcutAssemblyAIRegion`, pinned to `apple` and `us` on
`ReelcutExportChoice`'s terms — ordinary use of the app writes both. Measured
on this host: 460 × 340 points at backing scale **1** for an offscreen
window (the same as `welcome`'s), byte-identical across two processes in each
appearance, light ≠ dark. Since road map 12 A2 the window has a second pane,
Settings' Assistant pane, and the harness hands it a second `MemoryStore`;
`pinDefaults` pins `ReelcutAssistantModel` to `""`, the pane's model field.
Since road map 13 P4 the pane ends with the month's spend line, which
`show()` reads from the spend folder — and `pinDefaults`' wipe takes
`-RCSpendFolder` too, so `AssistantSpend.folder()` would be the person's and
the picture would hold their ledger (spec §11 P-5). The harness therefore
hands the controller a spend folder that does not exist
(`/nonexistent/reelcut-harness-spend`): the line is an empty month, answered
synchronously, so two processes still render byte for byte the same. The
constructor, exactly as `cloud_captions_probe.py`'s hygiene section holds it:

```swift
    let settings = SettingsWindowController(
        store: { MemoryStore() }, assistantStore: { MemoryStore() }, environment: [:],
        spendFolder: { absentSpend })
```

The window is 460 × 677 points now (`cloud_captions_probe.py`'s row 18
measures it).

Road map 8's W4b took a fifth render target, in `settings`' shape:

```
harness transcribe <project.reelcut> <out.png> <light|dark> <style> [replace 0|1]
```

renders the Generate Captions card (road map 8 §5e) over a package, hosted
as a WINDOW's content view controller for `settings`' reason — a sheet
cannot be put up offscreen. It builds its own `TranscribeSheetController`
with a `MemoryStore`, an EMPTY environment, one synthetic installed
language (en-US) and `MemoryDefaults`, a `UserDefaults` subclass that
answers every keyed call from memory, the argument domain empty, and traps
every domain write (a crash, so a scored failure) — it writes nothing, and
`word_captions_sheet_support.swift` holds the same text: a named suite removed with
`removePersistentDomain(forName:)` was MEASURED to leave its
`~/Library/Preferences` plist behind, because cfprefsd writes the emptied
domain seconds after the process exits (road map 8 §10.10). `<style>` is a
`CaptionStyle` raw value chosen the way AppKit chooses it — the row
selected, then `styleChanged:` — and `replace` sets the checkbox and sends
`controlChanged:`. The preview is drawn off-Metal by
`LayerRenderers.textBitmap`, so it is NOT black here the way the editor's
preview well is. `pinDefaults` gained `ReelcutCaptionStyle`, pinned to
`subtitles` on `ReelcutExportChoice`'s terms, and DEFENSIVE: no render reads
it, since `transcribe` hands the card `MemoryDefaults` and no other mode
builds the card. The arguments come after the
render form's own count and every earlier caller's positions hold.

Phase 5 took a THIRD mode, in the same shape and for the same reason:

```
harness meter <request.json> <out.json>
```

pushes buffers of samples this script authored through the level meter's
MODEL and writes back what it published. Nothing in the app reaches that
model without a PLAYING transport — `Playback` installs the metering sinks on
a build that only playback makes — so every chrome render photographs a meter
at rest and a lit one cannot be photographed at all; and the number belongs
to the model while the ballistics that would light it belong to the view. It
renders nothing and changes no render argument. A track in its request may
carry `store` — four magnitudes written straight into `LevelMeterSink` —
instead of `samples`, which is the only way to hand the model an RMS above a
peak, the skew its clamp exists for. **The mode compiles out under
`-D HARNESS_REFERENCE_BUILD`**, and the next phase to add a mode naming a
type an older tree lacks puts it behind that same flag: `phase5_chrome.py`
builds a reference harness out of an older `app/Sources` and passes exactly
one flag, so a per-phase name would leave that build failing the day it was
invented.

Phase 8 took a TWELFTH argument rather than a fourth mode, because what it
needs is view state on a render and not an answer without one:

```
harness … [clip|media|document] [candidateSpans] [expandSections] [mediaFilter]
```

`mediaFilter` is `search|sortIndex|unusedOnly` (`"beta||"`, `"|1|"`,
`"||1"`) for the Media tab's find band, and it is `candidateSpans`' case
exactly: the band's state is view state no package carries, and the only
thing that writes it in the app is a person typing into a field and clicking
two controls. Without it the harness photographs the RESTING band and nothing
else — and the resting band is the part of phase 8c that a build with the
whole filter deleted would still draw. It drives the app's OWN controls
(`controlTextDidChange(_:)` on the field, `itemPicked:` on the popup,
`mouseDown(with:)` on the checkbox) and never touches `MediaPane.filter`,
which is private. APPENDED after `expandSections`, in the shape phase 3 set,
so every earlier chrome script's argument positions still hold — and
`phase8_chrome.py` scores that fact out of the harness's own argument
parsing rather than asserting it from memory. Phase 8 also added two
`pinDefaults` keys (`ReelcutPreviewQuality` and
`NSWindow Frame ReelcutPreviewWindow`); all six earlier chrome scripts were
re-run after they landed and scored 26, 33, 59, 81, 70 and 78 — exactly what
they scored before, which is what says a pin took nothing away.

`phase4_chrome.py` is the same shape again (`python3
tools/proof/phase4_chrome.py`, no port, no media; renders in
`work/chrome4/`) for its first seven sections, and needs no new harness
argument for them — phase 3's `expandSections` already reaches a section
built `defaultExpanded: false`, and `text.animation`'s is built that way
too. Of phase 4's three parts the harness can PHOTOGRAPH exactly one: the
TextPane **Animation** section.
Auto captions need a TCC grant no headless run can obtain, and the reveal
itself is a PICTURE, so the typewriter's prefix, the word fade's per-word
alpha and the line rise's offset belong to `phase4_proof.py` and are not
claimed here at all. What is measured is that the section exists in the
Clip tab under its own id, that it is exactly three rows tall, that its
summary and each of its three rows read the data they are bound to, that a
shape clip does not get it, and that setting a text animation changes
NOTHING else in the window. **The window is 1440 × 1100**, and the height
is measured rather than picked: Animation is the eighth of a text clip's
sixteen sections, so at phase 2's 862 pt window it is below the fold and
every comparison comes back at zero changed pixels — a score of checks that
cannot fail — while at 1300 and above opening a section moves the sections
ABOVE it too and the downward-shift arithmetic stops being pure. The eight
packages are written by hand around one clip (a version-4 file with no
`animation` key, an explicit `null`, one per kind, one moving only `in`,
one moving only `out`, and a shape clip), so nothing loads asynchronously;
the shape pair is the one exception to the window height and renders at 862,
for the reason the note on `SHAPE_HEIGHT` gives.

**Section 8 is not a picture**, and it is in this script because the harness
is: over the `cues` mode above it runs 4a's **cue builder** — the ≤ 2 lines,
≤ 42 characters, ≤ 6 s and one-frame-gap rules of `CaptionCues` — over
twenty word lists, which was the only way those rules could be reached
before road map 8's W2 removed the Speech Recognition grant (since then
`speech_engine_proof.py` checks them over MCP too, on real speech). Each rule is asserted at its BOUNDARY rather than in the middle,
because a rule tested in the middle passes against `<` where the code says
`<=`: a word of 60 characters comes back whole rather than hyphenated, a
list of one word keeps its own times, two words at the same instant both
survive into one cue, a line of exactly 42 characters stays one line while
43 breaks, a word ending exactly 6 s after its cue began still joins it
while one tick later starts a new one, a ten-second pause splits, thirty
words on one short line break at 5.95 s (so only the length rule can have
broken them), and the one frame of gap comes out EXACTLY one frame — at 30
and 25 fps, at five offsets from the frame grid, and still exactly one frame
after `ReelTime.snapToFrame` has moved both ends, which is the claim that
matters, since a gap the snap ate would be trimmed to an abutting pair by
`CaptionLayout.place` and retime the transcript. Over all twenty lists, no
cue is over two lines, no multi-word line over 42 characters, no cue over
six seconds, no pair under a frame apart, and every word comes back once and
none is invented.

The chrome's forty checks were mutation-tested against five deliberately
broken builds compiled outside the repository: dropping `animationSection()`
from `ClipPane` (17/40), giving the section another id (30/40), pointing the
header summary at `out` instead of `in` (38/40), swapping the In and Out
rows (37/40), and making the two value rows ignore `enabled: on` (37/40) —
five edits to `ClipPane` and `TextPane`, which is why the denominator is
forty and not the whole score. Section 8's nineteen were mutation-tested the
same way against five mutations of `CaptionLayout.swift`: the 42-character
rule written `<` (18/19, and the one that fell is the exactly-42 boundary
check — the whole argument for testing an edge), the six-second test widened
to never fire (15/19), the frame of gap dropped so cues merely abut (15/19),
a third line allowed (16/19), and an over-long word truncated to 42
characters (17/19).


`phase8_chrome.py` is phase 8's offscreen half (`python3
tools/proof/phase8_chrome.py`, no port, no media; renders, crops and every
probe request and answer in `work/chrome8/`), and of the three things phase 8
adds the harness can photograph exactly one. Preview Quality changes the
PLAYER's render size and the preview well is black offscreen; Preview Window
is a SECOND window and the harness captures the editor's content view. So
seven of its nine sections are PROBES in `phase6_chrome.py`'s and
`phase7_chrome.py`'s shape — one `main.swift` compiled against the whole of
`app/Sources` by `build.sh`'s own swiftc line, cached on modification times, a
build it cannot make scored as a FAILURE rather than an exit — and section 7
is the Media tab's find band, measured against `MediaPane`'s own constants.

**The probe is inside an `.app` bundle, and exactly one of its six modes needs
that.** `NSApp.target(forAction:to:from:)` searches the KEY window's responder
chain and then the MAIN window's, and a process that cannot ACTIVATE has
neither: measured, a bare swiftc binary under `.prohibited`, `.accessory` and
`.regular` alike reports `keyWindow` nil and `mainWindow` nil after
`makeKeyAndOrderFront`, so the panel and a plain window would read IDENTICALLY
and the check would pass against both. Activation needs a bundle and an
`NSApplication.run()`, and the `dispatch` mode is launched through `open -W -n`
because a bare exec of a bundle's executable is handed the focus about one time
in three. It is therefore **the first script here that puts windows on screen**
— two, for about a second. Every other mode sets `.prohibited` and orders
nothing in.

**The check worth the whole file is the dispatch guarantee**, and nothing else
in this tree would notice the defect it is looking for. Phase 8b's preview
window is an `NSPanel` rather than an `NSWindow` so that it cannot become MAIN,
because AppKit resolves a nil-target menu action through the KEY window's chain
and then the MAIN window's — so a plain window focused over the editor takes
both and every ⌘-item whose action lives on `EditorViewController` goes dead.
Section 4 asserts, with the panel key, that ⌘E, ⌘T and ⌘0 still resolve to
`EditorViewController` and that File ▸ Export… still validates ENABLED. The
mutation run says exactly what that buys: `NSPanel` → `NSWindow` scores 119/125
and the answer reads `main "…— Preview"`, all three targets NONE, Export…
disabled — the build lane's own table reproduced from the other side.

**Section 1 is the subtlest thing in the phase and the reason its fixture list
is eleven canvases long.** `PreviewQuality.renderSize(for:)` answers
`m · (w/g, h/g)` for `g = gcd(w, h)` and `m = ceil(g / divisor)`, so the render
size carries the canvas's aspect EXACTLY — which matters because
`PreviewCanvasView` maps every drag handle through `AVPlayerLayer.videoRect`,
and `videoRect` is the aspect of the BUFFER. The aspect claim is an INTEGER
cross-multiply and never a float tolerance, the rule is re-derived in the
script rather than read off the answers, a coprime canvas (1001 × 667) must
come back Full at every row, and no answer may be finer than its row asked for.
**A 1920 × 1080 fixture alone could not fail any of it**, and the mutation run
is what proves that rather than the script asserting it: with the whole rule
replaced by a naive `(w/divisor, h/divisor)` the 1920 × 1080 check still
PASSES, and the six that fall are 999 × 666, 1001 × 667 and 1366 × 768. That is
the argument for the odd canvases being in the list at all.

**Section 6b is not a claim about Reelcut**, and it is here because the Media
pane's no-rebuild design rests on three properties of AppKit that nothing else
in this suite would notice changing: hiding an arranged subview COLLAPSES it
out of an `NSStackView`'s layout (four 20 pt rows at 3 pt spacing measure 89 pt,
three of them 66), `insertArrangedSubview(_:at:)` MOVES an already-arranged view
rather than duplicating it (all 24 permutations of four rows, checked on the
LAID-OUT order as well as the arranged one), and a sibling text field keeps
first responder AND its caret offset across such a permutation while removing
that field's ancestor loses both. If AppKit ever changes there, the search
field is destroyed under the caret on the first keystroke and the pane silently
eats what somebody types.

**One check FAILS against the build this was written for, and it is a real
defect rather than a broken instrument** — the run scores **124/125**. The
preview panel's `frameAutosaveName` reads back EMPTY:
`PreviewWindowController.init` calls `setFrameAutosaveName` BEFORE
`super.init(window:)`, and `NSWindowController.init(window:)` assigns its own
`windowFrameAutosaveName` — "" unless somebody set one — to the window it is
handed, wiping the name. Nothing ever writes `NSWindow Frame
ReelcutPreviewWindow`, the `setFrameUsingName` restore beside it can never find
anything, and the panel opens centred every time — the one thing that type's
own doc says it must not do, since a preview window exists to be put on a
SECOND display. The mechanism is measured in the same probe on a BARE `NSPanel`
and a BARE `NSWindowController`, so the reading is about AppKit and not about
Reelcut, and the probe also reports that re-asking AFTER the controller has
taken the window answers true and sticks — which is the fix as well as the
proof. A build that moves the one call scores 125/125 and nothing else here
moves.

**Three things spoil section 4, and all three are recorded because each
reads exactly like the defect.** A SHEET: `viewDidAppear` calls
`offerRelinkIfNeeded`, and every media entry in the six-file fixture points at
a path that does not exist — deliberately, so no thumbnail decode ever runs —
so the Relink sheet went up and took the key window. The cure is the FIXTURE
and not a dismissal: the dispatch mode opens a package of one SHAPE clip and no
media at all, which has a duration for Export… to validate against and nothing
to relink, and `attachedSheet` is scored so a sheet that comes back is named.
And a WEAK reference: `EditorViewController.document` is weak and a document
opened this way is not registered with `NSDocumentController`, so dropping it
deallocated the document, `validateExportAction`'s first guard refused, and
File ▸ Export… validated DISABLED with the editor key and every target
resolving perfectly. The delegate holds the document now and the probe reports
both preconditions beside the answer. Beyond those, the mode is asked up to
three times on its PRECONDITION alone (the app active, the editor key AND
main), because another app activating mid-run takes the focus outright
(measured); once the precondition holds the first answer is scored, so nothing
re-rolls a failing guarantee. Every answer also carries
`Bundle.main.bundlePath`, scored against the bundle the script built —
`open -n` is asked for a PATH but LaunchServices resolves bundle IDENTIFIERS,
and a mutation run holds two copies of one bundle under one id, where a mutant
that was never consulted would read exactly like a survivor.

**The third spoiler is HOST STATE, and it is the one the script now skips by
name.** A process on a LOCKED console cannot activate at all, so there is no
key window to demand and the retry above can never succeed — the precondition
is not merely unmet, it is unaskable. The script reads `IOConsoleLocked`
(`preview_refresh_probe.py`'s and `preview_validity_probe.py`'s reading,
copied), asks the dispatch mode ONCE instead of three times, and SKIPS the six
readings that need the focus by name; the seventh, the sheet, is the same
reading either way and is still scored. Measured on ONE build, both ways:
**150/150** with the console unlocked and **144/144 with 6 skipped by name**
with it locked. Before the skip, that locked run read **144/150** — six
failures, every one of them about a window being key or main, which is
indistinguishable at a glance from the panel defect section 4 exists to catch.
A skip is not a pass: the six never reach the score, and a DEAD dispatch probe
on a locked console still fails by name (mutation: the probe forced to answer
nothing scores 142/145 with the same six skipped, failing "the dispatch probe
answered", the sheet precondition and the end-of-run "every probe invocation
answered"), so the lock cannot hide a rotted instrument.

Mutation-tested against **six** deliberate breakages, each a copy of a clean
snapshot with ONE edit in it and the script run from inside the copy — never
against the working tree, since a second lane was editing the same repository.
Five died and the sixth is the interesting one. `NSPanel` → `NSWindow` (119/125)
takes the panel's own property and four of section 4's. The naive
`(w/divisor, h/divisor)` (118/125) takes six of section 1's and leaves
1920 × 1080 green. `clipsUsing` and `usesMedia` filtering `snapshot.clips`
alone — the exact mistake `MediaUsage.swift` was written to stop — scores
121/125 and takes all three usage checks plus "Unused only". A hand-rolled
`lowercased().contains` for `localizedStandardContains` (122/125) takes the two
diacritic checks and nothing else, which is what testing a fold at its boundary
buys. Shrinking the find band from 60 pt to 52 (113/125) takes ELEVEN of
section 7's, which is the line that says the PHOTOGRAPH half can fail and not
only the probes. **The survivor is `setFrameUsingName` deleted** (124/125,
exactly the baseline): the restore is dead code today for the reason the
standing failure names — nothing ever writes the key it reads — so that line
cannot be falsified until the autosave defect above is fixed, and the two
belong in one paragraph.

Its packages (`work/p8-six.reelcut`, `p8-none`, `p8-usage`, `p8-dispatch`)
and everything under `work/chrome8/` keep fixed names and are rewritten on
every run, `phase7_chrome.py`'s rule: nothing this script makes is ever handed
to a running app, since the harness and the probe are fresh processes that
open a package off disk. **Every media entry in them points at a path that does
not exist**, which is deliberate — `MediaRowView.loadThumbnailIfNeeded` never
starts an asynchronous decode for a file it cannot find, so no render changes
halfway through a settle — and is exactly what put the Relink sheet up over the
dispatch mode.

What no instrument in this tree can reach, said here rather than left out.
**Neither preview is DISPLAYING anything**: `displayedPixelBuffer` is nil for
both layers in a process with nothing on screen, so nothing here claims the two
windows show the same frame — that needs a person at the machine. The phase's
own spike measured why the obvious instruments are useless for it —
`isReadyForDisplay` and `videoRect` read TRUE and plausible for a layer with no
superlayer at all — and both readings are scored so the next reader does not
reach for them. **Preview Quality changes no pixel any script here can
capture**: section 1 is the arithmetic that decides the render size, and that
the player's composition actually GETS it is `phase8_proof.py`'s to say — not
over MCP, which reaches no player, but through a probe of its own built the
same way this file's are. And **the frame the panel would restore cannot be tested end to end**: the
harness pins `NSWindow Frame ReelcutPreviewWindow` so no render depends on what
the machine holds, and no script here launches or terminates Reelcut.app, so
"the preview opens where it was left after a relaunch" is not a sentence any of
them can say — phase 7's presets paragraph draws the same line.

## Phase 9 — inside the nest, the app half (`phase9_probe.py`)

`python3 tools/proof/phase9_probe.py`, **48/48**. No port, no window server
grant, no media: it is a probe against the WHOLE of `app/Sources`, built with
`harness/build.sh`'s own swiftc line and cached on modification times the way
the harness is, and a build failure is a scored FAILURE rather than an exit.
That is `phase5_chrome.py`'s and `phase6_chrome.py`'s instrument, and this
file's header argues why it is the right one three times over: an op's
ENVELOPE — the `scope` key `ReelOp.scoped(_:)` writes — never appears in
anything a tool call can read back, `ReelOp.isDocumentLevel` is a list whose
whole content is a refusal the core would otherwise make (so a build with it
empty and a build with it right differ only in an error sheet), and
`NestScope`'s path arithmetic is pure Swift whose interesting cases are the
ones nobody can stage by hand — an undo that removes an inner nest while its
scope is open.

Four sections. **The envelope**: an unscoped op writes no `scope` key at all
rather than an explicit null, which is what keeps every op a project that
never enters a nest sends byte for byte what it was; `scoped(40)` adds it and
changes nothing else; `scoped(nil)` is the identity; and exactly the seven ops
`core/src/scope.rs` refuses inside a nest are the seven this side sends
unscoped. **The handle** (`rc_project_scoped` through `ReelProject.scoped`):
its clips and tracks are the nest's with the nest clip that shows it absent,
its canvas is the nest's frozen size at the DOCUMENT's rate, it has no markers
where the document has one, its duration is measured from the nest's own zero,
a nest one level deeper scopes too, an unknown nest is a nil, and the parent
handle is undisturbed. **The path**: the offsets sum each step's nest clip
start in its OWN container, the names read "Timeline › Intro › Deeper" off the
CLIPS rather than the nests, and `clamped` TRUNCATES at the first bad step —
keeping the good prefix, so an undo that removes an inner nest leaves the
person in the outer one they are also in rather than throwing them out to the
timeline. **The document**: entering swaps `editedProject` without touching
`project`, the playhead maps in and back out so the frame under it does not
move, the in/out range is cleared both ways, `editedProject` is MEMOISED (two
reads answer the same object, which is what `refreshFromDocument`'s identity
guard depends on), a scoped edit lands in the nest and leaves the timeline
clip alone in one undo step, and a document-level op sent with a nest open
lands on the DOCUMENT rather than coming back as a refusal.

Made to fail, the rule phases 4 and 5 added. Dropping the one line of
`ReelOp.json` that writes the key scores **45/48** and takes three: the
envelope check, "an edit with a scope open lands INSIDE the nest" (the op then
names a clip the timeline has not got and changes nothing) and "one op is one
undo step". Sending every op scoped — `isDocumentLevel` ignored — plus
dropping `setNestPath`'s `inOutRange = nil` scores **46/48** and takes exactly
the two checks those two lines exist for. The PICTURE half of this phase is
not here and cannot be: the breadcrumb is drawn inside the frozen ruler's
`draw`, and a scope is view state the harness has no argument for — it is
`phase9_chrome.py`'s, next, which photographs the corner with no harness
argument at all.

## Phase 9 — the corner, photographed (`phase9_chrome.py`)

`python3 tools/proof/phase9_chrome.py`, **62/62**. No port, no window server
grant, no media: route 1 of `archive/reelcut-remaining.md` §1b, a probe over
the WHOLE of `app/Sources` in `phase9_probe.py`'s shape — `harness/build.sh`'s
own swiftc line, cached on modification times under `work/cornerprobe/<tag>/`,
a build failure scored as a FAILURE rather than an exit — except that this one
RENDERS. Route 2 was two harness arguments, and three things ruled it out. The
defect is a z-order, the header column painted ABOVE the floating ruler; the
two bands overlap in exactly one square — the 132 × 22 pt corner the
breadcrumb is drawn in — and only once the pane has scrolled VERTICALLY, while
every harness render is at scroll 0, so a `scope` argument alone would have
shown a correct corner against a build that painted it out on the first
scrolled point. A vertical-scroll argument would have had to be appended after
`mediaFilter` and then proved harmless by re-running seven chrome scripts. And
half of what the fix wave changed is not a picture: how many levels one
double-click walks out (`beginGesture`'s `clicks < 2`) and what Clip ▸ Open
Nest / Close Nest validate as while a rename field is being typed into — a
click count and a validator's answer, which no photograph can read. So the
probe builds a bare `TimelineView`, feeds it a snapshot, scrolls it and
captures through the same `cacheDisplay` path the harness uses, then drives a
real `EditorViewController` over the nested package `phase9_probe.py` uses.
The untracked `work/phase9-corner-probe/` measured the fix this way at the
time; this is that instrument as a tracked script with what the scout found
wrong with it put right, and the untracked directory is deleted.

**The fixture is honestly scrollable, and the untracked probe's was not.** Ten
text tracks make 490 pt of content against a 324 pt viewport — 166 pt of room
for the 62 pt scrolled (`rowTop(1) − 10`, a row's top 10 pt under the ruler's
bottom, where a track rename's field sits) — and every scrolled scene reports
`clipMinY == pinnedY == 62`, a scroll the app can reach. The untracked probe's
six tracks were 306 pt against the same 324: `NSClipView.scroll(to:)` does not
clamp, so it reported a 62 pt scroll of a pane with no room to scroll and
photographed a state no user reaches. Its z-order pictures held anyway, which
is why the fix was right; the fixture is what a proof cannot carry.

Six scenes, each a full PNG under `work/cornerprobe/<tag>/shots/` with the
corner cropped beside it by the SCRIPT from the decoded PNG, so the crop
compared is a crop of the photographed picture and not a second capture:
`topPlain` (scroll 0, no trail — the corner every project before phase 9
drew), `top` (scroll 0, a two-level trail), `scrolledPlain`, `scrolled`,
`rename` (the same scroll with a track rename field open on the top, partly
scrolled row — the one thing that must stay above the ruler) and
`renameEnded` (then `endRename()`, the scene the untracked probe never had and
the only one that can see the restore line). Section 1 is the instrument's
honesty: all six SETTLED (two consecutive captures byte-identical), one
backing scale, the corner 132 × 22 pt at the pane's visible top-left in every
scene, and the scroll arithmetic above. Section 2 is the picture, every claim
a byte comparison of the decoded corner crop that names WHERE any difference
lies: `scrolled` == `top` (the trail survives the scroll); `scrolled` !=
`scrolledPlain` (941 px differ, every one inside the corner — the trail is
VISIBLE); `scrolledPlain` == `topPlain`, and that blank square holds at most 3
distinct pixel values where the trailed corner holds 144; `scrolled` vs
`scrolledPlain` and `top` vs `topPlain` differ ONLY inside the corner;
`rename` != `scrolled` with `content.subviews.last === headers` and the
difference confined to the corner ∪ the field's rectangle (at a 2 px slop,
because a bezeled `NSTextField` paints its halo one point outside its frame —
258 px fell outside at slop 1, measured); `renameEnded`'s corner ==
`scrolled`'s and the WHOLE frame identical, with `subviews.last === ruler`; and
`init`'s order `[headers, ruler]` read in all six. Section 3 is the gestures
on the real editor: the corner's hit compared as the `TimelineHit` enum
(`.corner` at depth 0, `.breadcrumb(level: 0)` at 1, `.breadcrumb(level: 1)`
at 2), a double-click delivered as AppKit delivers one (`clicks: 1`, its
mouse-up, `clicks: 2`) entering the nest clip where a single click only
selects, the CONTROLLER's push of the trail read after each step, the
breadcrumb double-click at depth 2 coming out ONE level, a lone click at depth
1 reaching the timeline and re-selecting clip 3, a click on the inert
top-level corner swallowed, and a breadcrumb click under an open rename ending
the field first. Section 4 is `validateNestScopeAction` at depth 0, idle,
typing and after ending, for `openNest`, `closeNest`, the three marker
selectors (nil at depth 0, false at depth 1) and `splitAtPlayhead` (nil — not
its business). The activation policy is `.prohibited`, the harness's; the one
thing that could have needed `.accessory` was the rename field taking first
responder in a never-shown window, and it does, scored in both halves.

Made to fail, three ways, each a one-line mutant that `--mutant` applies to a
COPY of `app/Sources` under `work/` and builds in its own cache — never the
tree, and not a reference build the way phase 5's is, because no git commit
has the old z-order AND a breadcrumb; the phase's one app commit ships the
fix. `init-order` (`init`'s two `addSubview` lines swapped back) scores
**52/62** and takes ten by name: the init order, the ruler front-most in the
plain scenes and at idle, `scrolled` == `top`, `scrolled` != `scrolledPlain`,
`scrolledPlain` == `topPlain`, the ≤ 3-colour corner, only-inside-the-corner,
and BOTH `renameEnded` identities — the restore puts the ruler above the
headers, which is the fixed order, so the ended scene shows the trail the
un-ended one lost. `end-rename` (`endRename`'s restore line deleted) scores
**57/62** and takes five: `renameEnded`'s `subviews.last`, its two identities,
and the two "ruler front-most again" reads in sections 3 and 4 — the untracked
probe's four scenes would have let this one through. `double-click`
(`clicks < 2` made `true`) scores **55/62** and takes seven, the second-press
check and six downstream of it, since every later step of the gesture half is
then at the wrong depth. `--sources DIR` (or `RC_APP_SOURCES`) and `--tag`
build against any other copy. The probe builds in 40–45 s and runs in about
2.5 s; a cold run of the script is about 52 s and a warm one about 8 s, and two
direct probe runs into separate directories come out byte-identical across
processes.

What is not claimed: the renders are in the light appearance only; the picture
half is a bare `TimelineView`, so the trail it draws was assigned by the probe
and the controller's push is read structurally in the gesture half rather than
photographed; and no mouse event is synthesised — `beginGesture` is called
with the hit, point, flags and click count `mouseDown` would have computed,
which is the frozen file's one line and not under test. The gesture half is
sequential, so a wrong depth propagates into the checks below it — recorded,
not changed.

## The remaining-work probe (`remaining_probe.py`)

`python3 tools/proof/remaining_probe.py`, **170/170** (141 when it landed; 156
with road map 3's 5f, the held tail over a 1 s-picture / 5 s-sound fixture;
170 with the fix wave's sparse shape, three frames 25 s apart under 60 s of
sound, and its all-sync twin). No port, no window
server grant, and no media beyond `media/A.mov` (sections 2, 3 and 5),
`AV.mov`, `B.mov` and `toneA.m4a` (section 5) plus the fixtures 5f MAKES with
`ffmpeg` at proof time under `work/remaining-probe-files/pass/` — 1 s of
`testsrc2` picture over 5 s of a 440 Hz tone, the shape of a screen recording
of a static screen with narration, and a sparse three-frame twin with
VideoToolbox and all-sync encodings — so `ffmpeg` and `ffprobe` on `PATH`
are a proof-time requirement here as for `phase2_proof.py`'s PCM decode: a standalone probe over the WHOLE of
`app/Sources` in `phase9_probe.py`'s shape — `harness/build.sh`'s own swiftc
line, cached on modification times under
`work/remainingprobe/<tree|mutant-hash>/`, a build failure scored as a
FAILURE rather than an exit — for the items in
`archive/reelcut-remaining.md` that are APP arithmetic or an app PICTURE no
tool reaches. One section per item, and one binary answering all of them by
a request `mode`, so the next item adds a `case` and a `section_…` without
touching the others: section 1 is §2b's naming (70 checks with the build
check), sections 2–5 are §2a's cache marker on the app side and road map
3's held tail seen from the strip (100).
`--sources DIR` (or `RC_APP_SOURCES`, the spelling `phase9_chrome.py` uses
too) compiles it against any other copy, which is the gate.

Section 1 is §2b, the three stem helpers, and why it is a probe is the point.
Both sites the item named are PANEL-only —
`CaptionExportOptions.formatChanged` rewrites the save panel's name field
when the Format popup moves, and
`exportCaptionsCommand` seeds that field from the document's title — and the
MCP path never comes near either: `export_captions` goes through
`AgentServer.destinationURL`, which strips only a member of
`replaceableExtensions` and appends otherwise, so `{path: "Board v1.2"}` wrote
`Board v1.2.srt` before the fix and after it, and an MCP check for that name
passes against the unfixed build. What can see it is the shape
`FrameWriter.renamed` chose in phase 7 for the same defect, a pure function of
a string run over a table of names. **1a**: `CaptionExporter.renamed` — its
known set is exactly `{srt, vtt}`, read off `Format.allCases` rather than a
second list, and fourteen rows, of which `Board v1.2` + SubRip →
`Board v1.2.srt` is the one a bare `deletingPathExtension` fails; a foreign
extension is KEPT (`talk.txt` → `talk.txt.srt`, the file the tool writes for
that path), the suffix is compared lower-cased, and `chart.png` + SubRip →
`chart.png.srt` pins the recorded divergence from MCP's `chart.srt`. **1b**:
`FrameWriter.renamed`, nine rows over the same shape — its docstring has said
since phase 7 that a probe compiled from `app/Sources` calls it with a table
of names, and none did until this one. **1c**:
`ProjectDocument.displayStem(of:)`, the title-bar stem the three panels
(Export…, Save Frame…, Export Captions…) put an extension after, whose set
is `{reelcut}` and NOT the caption set: nine rows, `Board v1.2.reelcut` →
`Board v1.2` and `talk.srt` → `talk.srt`. **1d**: the instance accessor over
live documents — a fresh `ProjectDocument()` and one told it lives at
`Board v1.2.reelcut` — because a static function nobody calls is not a fix.
**1e** is a STRUCTURAL read, and it is there because a behavioural probe
cannot see whether a panel's private method calls the helper: it reads the
four function bodies out of the sources it compiled and asserts each names its
helper and carries no `deletingPathExtension` of its own, and that each file
holds exactly the bare count it is allowed. `phase7_chrome.py`'s
`destinationProperties != nil` is the precedent, and it is weaker than a
behaviour and said to be. **1f** pins the one rule three documents state and
nothing had checked — `knownExtensions` ⊆ `AgentServer.replaceableExtensions`,
without which the panel and the tool would name one file two ways: rows built
FROM `knownExtensions` (not a second list) call `destinationURL` with each
member asked for as the other format, upper-case too, and assert the strip
(`x.srt` + WebVTT → `x.vtt`, `x.vtt` + SubRip → `x.srt`) against a non-member's
append (`x.txt` + SubRip → `x.txt.srt`), plus a coverage check that every
member read off the type has a row.

Made to fail, four ways, each a copy of `app/Sources` under
`work/remainingprobe/mutants/` and the script pointed at it with `--sources`;
the first three were scored when section 1 was 63 checks, the fourth at 108.
`caption-bare` (`CaptionExporter.renamed` back on the bare strip) scores
**59/63** and takes the `Board v1.2`, `talk.txt`, `shot.final` and `chart.png`
caption rows. `stem-bare` (`displayStem(of:)` back on the bare strip with an
empty fallback) scores **60/63** and takes the `Board v1.2`, `talk.srt` and
`talk.mov` stem rows — and 1d's live document PASSED against it, because this
Mac shows extensions and a bare strip of `Board v1.2.reelcut` is right by
accident there; the static table is the killer and the live read is a wiring
check. `site-unwired` (`exportCaptionsCommand` alone back on the bare strip,
both helpers intact) scores **60/63** and takes only 1e's three — the call,
the absence of a bare strip at that site, and the file's bare count — while
every behavioural row passed, which is what 1e is for: an unwired site with
correct helpers beside it is the unfixed defect with a proof next to it.
`no-vtt` (`vtt` removed from `replaceableExtensions`) scores **106/108** and
takes exactly the two `x.vtt` + SubRip rows — the pair the tree had never
pinned, since `phase4_proof.py` asks a `.srt` path for WebVTT and nothing had
asked a `.vtt` path for SubRip. The probe builds in about 45 s and the tree's
cached binary is reused across runs.

Sections 2–5 are the half of §2a's completion marker that a running instance
cannot be asked about; `remaining_proof.py` below is the other half.
**2**: `CacheStamp.stamp(for:url:)` as pure calls over four files the script
prepares — an original, a byte copy at another path with its times preserved
(EQUAL, which is the claim that the path is not in the stamp), the same bytes
with a later mtime (differs in `modified` alone, by the seconds the script
moved it), and a missing path (nil) — plus the key set read off the encoding
a marker carries and the shape of the two marker paths. **3**: the ledger,
visible only as a COUNT: `generateCaches` once into a fresh directory, the
`thumbs` posts counted until 1.5 s of quiet, then three calls in a row into a
second directory — one pass's worth under the ledger, because the second and
third queue behind the first and find its marker — and a fourth call after
the quiet posts nothing and leaves `0.jpg`'s inode alone. **4**: the timeline's
stale-tile wiring as PIXELS — a bare `TimelineView` (phase 9's chrome scene)
over one media whose `0.jpg` the probe wrote solid red, the file turned blue,
and `.mediaCacheDidChange` posted twice: WITHOUT `replaced` the tile stays
red (the memo rule, pinned), WITH it the tile is blue, four PNGs compared
inside the clip's rectangle with the differing box printed. **5** is the
pass's own rules, the ones the review of the first landing forced — a pass
certifies only a strip it can vouch for, and a peaks rebuild withdraws the
old floats first: **5a** deletes `0.jpg` the instant it appears (a 1 ms poll
on a thread of its own) and asserts NO marker, nine frames and a post, then
runs the SAME pass untouched and asserts all ten frames, the marker, and
`replaced` on its first post — the retry a hole earns; **5b** hands a
`hasVideo` record a text file: no frame, no marker, a post; **5c** runs an
IMAGE record over a text file with a seeded `0.jpg`: the tile is cleared, no
marker, exactly one post carrying `replaced` (the decode-failure path posts
too); **5d** makes ONE replacing pass post twice by running `A.mov` under a
20 s RECORD — `relink_media` never re-probes, so a record longer than its
file is a state the app can be in; the ten seconds past the picture are HELD
at the track's last frame since road map 3 (5f) — twenty tiles where there
were eleven and nine holes, the row its unclamped mutant fails — and asserts
`replaced` on the first post and on no later one; **5e** builds `AV.mov`'s peaks, runs the same record over a
video-only file and asserts the `.bin` and its marker are GONE with exactly
one `peaks` post (the withdrawal — the "timeline was told" claim no tool can
see), then `AV.mov` again brings the `.bin` back at its first size with one
post. A limit: 5a's poll must see `0.jpg` before a ten-frame pass finishes,
and on a machine that decodes all ten inside one step the PRECONDITION row
fails by name rather than the rule row.

Made to fail on copies of the tree with `--sources` — the first two scored
at 108 checks, the rest at 141: the ledger removed (`generateCaches` back to
a bare `Task.detached`) **107/108**, three rapid calls posting 3 where one
pass posts 1; the one `if replaced` line removed from
`TimelineCaches.invalidate` **105/108**, the tile still red after the flagged
post; `stripHolds`' presence check removed **138/141** (5a's no-marker row
and the two retry rows, since the wrongly written marker makes the retry
skip); its empty-set guard removed **139/141** (5b and 5c's no-marker rows);
`clearPeaks` back to marker-only **139/141** (5e's `.bin`-gone and
one-withdrawal-post rows); the image branch's post moved back inside the
decode's success arm **140/141** (5c's post row); `replaced` left on every
post **140/141** (5d's "no later post" row).

## The cache marker over MCP (`remaining_proof.py`)

`python3 tools/proof/remaining_proof.py [port]`, **79/79**, against a
running instance on its own port (4834 by default). It is §2a's sentence —
"a cache already on disk is not rebuilt" — claim by claim, on a SAVED
package, because an untitled document's temporary cache directory is
reachable from no tool. Fixtures are COPIED into `work/` under new names
before anything touches them (`AV.mov`, `A.mov`, `B.mov`, `C.mov`), since
`os.utime` is one of the claims and a shared fixture's mtime is not this
script's to move; earlier pids' `remaining-cache-*` packages and copies are
swept at start, the rule every other MCP proof's `Session` follows. The
instrument is `os.stat`'s inode and `st_mtime_ns`, not the marker's say-so:
ImageIO stages every thumbnail and renames it into place and the peaks file
is written `.atomic`, so a rebuilt file is a NEW inode, and "nothing moved"
is a claim about four inodes and four nanosecond mtimes across every sample
of a 3 s window against a baseline read BEFORE the trigger. The trigger is an
import of a fresh 8 KB copy of `C.mov` under a new name — a path already in
the list is an identity edit and never reaches the cache line — and the
window is BOUNDED by a positive control in the same section that MEASURES:
the same trigger with the marker deleted rebuilds at a latency dated from the
trigger that must be at most the 3 s the window samples (0.06 s and 0.09 s
here; 10 s is only the poll's cap), so a build whose rebuild lands at 4 s
fails the control rather than slipping past the window. Every sub-section
runs isolated, so a raise scores one failure and the next one runs; a
missing parity log is scored, not printed; and the package copy in 1g is
taken on a settle of the six cache files, not a pause.

Section 0 is the parity log and the catalog. Section 1, in the order the
remaining document argues it: both markers land after `AV.mov` (video AND
audio) is imported, are JSON carrying `size`, `modified` and `duration` and
NO key or value naming a path, agree with the copy's own stat, and are
byte-identical to each other; a second whole-media pass (importing `A.mov`)
moves none of the four; the thumbs marker deleted, the same trigger rebuilds
`0.jpg` at a measured latency inside the window, and the peaks half — SAMPLED
over 3 s once the rewritten thumbs marker says the pass finished, since a
single read taken before that half could have run was a race — is left
alone; the `.bin` deleted with its marker kept is rebuilt, because the peaks
head check asks for both; `os.utime` of `A`'s copy by +2 s rebuilds `A`'s
strip and moves the marker's `modified` by exactly 2; `relink_media` to a
byte copy of `A` with a LATER mtime rebuilds on the mtime alone and relinking
back rebuilds again, then `A` → `B` rebuilds with DIFFERENT `0.jpg` bytes and
`B` → `A` brings them back; a byte copy of the whole package opened under a
new path is not rebuilt in 3 s while a second copy with one marker deleted is
rebuilt at a measured latency inside it; `consolidate_media` leaves the
marker MATCHING the consolidated file — measured on this machine, `copyItem`
preserves `st_mtime_ns` to the nanosecond, so nothing is rebuilt and the
markers are untouched, which the script asserts and prints (a rebuild would
also have been correct; only a stale marker is wrong); and **1i**, the
withdrawal over MCP: a clip on `AV`, `detect_silence` answering, then
`relink_media` to a copy of `A` (the record keeps `has_audio`; the pass finds
no track and returns early) — the `.bin` is GONE inside the cap and stays
absent with its marker across the window, `detect_silence` names `AV` in
`pending_peaks` and proposes nothing rather than measuring the old file, and
relinking back brings a byte-identical `.bin` and the detector's answer with
it. The first run of 1g scored a copy with NO media green — `project.json` is
written only by a save — so 1g saves first and asserts both copies list the
media; the check is kept.

Made to fail, each mutant a copy of the tree with the app built in the copy
and its binary relaunched on its own port; the first four were scored when
the file had 69 checks, the last two at 79. The thumbs head check deleted
**65/69** — every negative claim (1b's "none of AV's four files moved", 1c's
"the thumbs half was NOT rebuilt", 1g's "none of the copy's 6 cache files
moved", 1h's "nothing was rebuilt") and nothing else. `CacheStamp.modified`
forced to 0 **59/69** — both markers' `modified`, the utime row's
precondition and its two rebuild claims, the four claims of the `A` → touched
copy → `A` relink (each differing by mtime alone), and the consolidated file's
match. A 4 s `Task.sleep` after the thumbs head check **67/69** — exactly the
two latency bounds, with every 10 s cap passing, which is what the bounds are
for. The peaks head check deleted **75/79** — 1b through the `.bin`'s inode,
1c's sampled peaks claim, 1g and 1h; the review of the first landing had
noted no mutant covered that check. `clearPeaks` back to marker-only
**76/79** — 1i's three: the `.bin` gone, absent across the window, and the
detector reporting `AV` pending. It opens THREE documents; relaunch between
full runs. Phases 2, 3, 3-silence and 5, whose fixtures read the peaks path,
were re-run against the same binary and still score 85, 121, 8 and 88.

## Road map 3 — screen recording (`recording_spike.py`, `recording_proof.py`, `recording_probe.py`)

Three instruments, in the order they came.

`python3 tools/proof/recording_spike.py` is R0, the spike that ran BEFORE the
code and stays as the record of its seven answers (`--only 2,5` for a subset; a
subset run carries the other questions' answers forward under
`carriedForward`). It compiles a Swift probe against nothing from
`app/Sources`, launches the built app both ways for question 1 (the README's
direct line, and `open -a … --env … --stdout … --stderr … --args …`) on ports
4890 and 4891, records a few seconds of the main display for the others, and
writes `work/spike/answers.json`. Its answers are pasted into
`archive/reelcut-roadmap-3.md` dated; two of them overturned the plan. The
seventh (2026-09-12, `--only 7`, three rows of three 2 s segments) is R2's:
pause and resume as segments over ONE running stream — the recording output
removed at each pause and a fresh one added at each resume, with a `.screen`
output counting frames through the pause, and the second-file microphone
stopped and restarted per segment; `pause_resume(..., micDeviceContains:
"MacBook")` picks the microphone by a substring of its name, because the day's
first row on a Bluetooth headset switched profiles mid-recording and poisoned
the file output for every later file — a host fact, recorded in the road map.

`python3 tools/proof/recording_proof.py [port]`, over MCP, in two tiers. The
HEADLESS tier always runs: the catalog at exactly 75 with `record_screen`
declaring no `scope`, the refusals in the contract's ORDER (the caller's
mistakes, the microphone grant by status word, a `project` naming nothing,
THEN the Screen Recording grant, then the display or window lookup), lane E's
held-tail rows over an `ffmpeg`-made fixture (1 s of picture under 5 s of
sound — three byte comparisons of `render_frame` PNGs and a YAVG black test),
structural reads of the tool file, and a self-test of the tone rows' Goertzel
arithmetic over a wave-written sine/noise/silence trio. The GRANTED tier
launches a SECOND instance of its own with `-RCRecordingFolder` under
`work/recordings/<pid>-files/`, prints whose grants both instances run under
(a shell-launched instance runs under its TERMINAL's — R0 q1), and records the
main display: a new project rated at 60 while the media keeps the file's own
variable rate, a landing at the playhead on the front track, a new front track
when that one is occupied, one-step undo with the file kept, `size: best` at
the pixel size, `place: false`, inside a nest, a document at `MAX_TRACKS`
(the refusal names the file), the microphone rows (a second file on a
Microphone track at the measured offset; the head-loss row), and the tone
rows. **Host state is read and named, never assumed**: a locked console (zero
shareable displays under a TRUE preflight), a muted output and a BLUETOOTH or
AirPlay output (the system-audio tap hands it digital silence — measured with
AirPods Max) each SKIP their rows with a count; a raise inside the tier
scores one failure plus a counted skip; the summary line says what did not
run. Since R2 (pause and resume) the headless tier also reads `pauses`,
`segments` and `started_at` and the three Pause phrases off the description,
section 3 reads the segment-sized `stopCeiling(segments:)` and the
`filesClause` sentence off the tool's source, and the granted tier's
detection call asserts the result's SHAPE — `pauses == 0`, one `segments`
entry equal to the top level with its own `width`/`height`/`fps`, a
`started_at` that parses as ISO-8601 UTC within a minute of the call. With a
granted, unlocked console it is **187/187** with the two tone rows skipped by
name (the headless tier 121, the granted 66 — 9 detection, 44 landing, 13
microphone); on THIS host it is **186/187**, because the default INPUT is a
Bluetooth headset whose capture session starts 150–200 ms late, so the
microphone file arrives short at the head and the head-loss row FAILS —
deliberately not skipped the way the Bluetooth OUTPUT's tone rows are, since
that row is the one thing that catches a real head loss; expect 121 plus a
counted skip on an ungranted or locked machine. Its honest limit:
with ONE segment the "segment equals top level" rows cannot tell a build that
copied the top level into the segment from one that did not — the two-segment
shape is `recording_probe.py`'s, whose granted tier records for real. It
needs `ffmpeg`, `ffprobe`, `osascript` and `afplay` on `PATH`. The mutants it names — the grant check hoisted, the
`.newProject` fallback deleted, the `fps:` override dropped, the undo group
split, the held-tail branch deleted, a `scope` on the tool — and the four the
fix wave built (a placement throw unwrapped, the `path` trim removed, a
named project falling through to a new document, the Goertzel share on the
wrong scale) are in its docstring with the rows that kill them.

`python3 tools/proof/recording_probe.py`, **983/983 with no row skipped** on
2026-09-28 (section 9 ran: a true preflight and two shareable displays),
after section 10 was added, and 984 rows since 10e's level row
(`--only chrome,grants` 184/184; the whole run not repeated); before it, **876/876 with 41 rows skipped by
name** on 2026-09-21: the locked console's granted tier had zero shareable
displays. Its historical welcome comparison ran and passed; no §6b row was
skipped. A later `--only host,granted` rerun on the unlocked desktop passed
**44/44 with no skips**, covering all 41 previously omitted granted-tier
rows. This was a focused rerun, not a new full-suite score. The earlier
858/858 with 43 skipped and 917/917 are dated scores
from before this matching-core repair (662 before R2; `--only <sections>`
for iteration), over a probe compiled
from the whole of `app/Sources` (`remaining_probe.py`'s shape): section 1 the
file naming, 2 `RecordingConfiguration.make` read back field by field over
sixteen configurations (`excludesCurrentProcessAudio` TRUE in every row — the
one mutant no MCP proof can see), 3 the recorder's state machine over a FAKED
session (an `SCContentFilter()`, an `SCStream` and an `SCRecordingOutput` all
construct in a bare Mach-O; only `startCapture` needs the grant — the join,
the one-shot settle, a microphone that dies, the sentences), 4 the landing
(every placement committed through `performGroupedEdit` and the minted ids
compared with the prediction; the untitled ORDER on the real
`ProjectDocument` through a subclassed `NSDocumentController`; the caps
thrown in the trial), 5 the chrome's structure (the File-menu row, the
welcome button, the panel's construction, the retitle and the quit guard
under a `ScreenRecorder.shared.state` the probe writes and resets, and the
fix wave's rows), 6 the welcome window's cross-build against the tree one
commit before the button (phase 5's pattern; the reference is a pickaxe on
the button's title, `HEAD` while uncommitted), 7 the catalog move, 8 host
facts printed and never asserted, and — R2 — 9 the probe's own GRANTED
tier: under the terminal's grant with a display to share (R0 q1; a bare
Mach-O can start a stream), two real `ScreenRecorder()` runs on the main
display into `work/` — start, pause with `elapsed` read twice and equal,
resume, stop → two segments named by their own start times, `pauses` 1;
then a stop while paused → one segment — and then the PANEL end to end over
a faked session on `.shared`, hidden at `recordingDidStart` for a DISPLAY
source and still hidden after a clean landing. Skipped BY NAME with its
count (41) on a locked console or under a false preflight. R2 also rebuilt
section 3's `Fake` on `Session(segments:)` — measured on the way: a
never-started `SCStream` accepts add / remove / re-add of a recording
output grant-less and writes nothing — for pause, resume, the refusals,
a stop while paused, the delegates finding a segment by identity and by
mic URL, and the three-segment walker; folded lane L's two- and
three-segment landings into 4b (the short-voice and sub-frame notes, the
24981/1000 canvas with no overlap); and added 5p–5u for the item's pure
vocabulary, `resumeProblem`, `revealIfNoted` and a real pause/resume/stop
through the panel. Section 10 (`grants`, spec §11 recording) is the press's
grants: `screenStep` over all eight combinations of granted, asked and
`launchedByLaunchd`, `microphoneStep` over four statuses, the two pane URLs
with System Settings as their resolved handler (never opened) and the
privacy extension's Info.plist and binary read for the legacy id, the
URL-scheme flag and both anchors, the opened notes, eleven presses through
`record(nil)` each under a spy of its own (ask once then open the pane; a
false opener leaves the plain refusal; a denied or restricted microphone
opens its pane; a shell launch always asks and never writes the flag), and
where the prompt and opener calls may live. Every mode runs under SEALED
grant doors — real reads, and no prompt, no pane, no write of
`ReelcutScreenRecordingAsked`. `--mutant <name>` prepares a copy of
`app/Sources` and runs the whole thing over it; thirty-seven are named in the
docstring, every one killed — the nine R2 ones at 811–875 of 876, R1's
re-scored at 857–875, section 10's eight at 171–183 of `--only chrome,grants`'
184 (170–182 of 183 before 10e's level row; emptying the step-aside scores
183/184, that row alone).

Worth knowing: the built app is ad-hoc signed, so its designated requirement
is its cdhash and a Screen Recording or Microphone grant given to Reelcut.app
(the `open -a` line) is for THAT build — after a rebuild remove and re-add it,
or answer the microphone prompt again. The proofs' direct launch never meets
this, because it runs under the terminal's stable identity.

## The preview that played black (`preview_validity_probe.py`)

A project of two screen recordings on a 28.172 fps canvas previewed BLACK at
every playhead position — reopened or not — while `render_frame` and an
export of the same project were right. The plan ended at 7858867/600000 s and
the composition `CompositionBuilder.build` made from it at
13098111667/1000000000 s: both clips run past their recording's video track,
`fill` holds the last frame from the source's timescale into ticks, and
AVFoundation reports the composition's duration in nanoseconds, rounded. The
instructions stopped a third of a nanosecond short, `AVVideoComposition.isValid`
reports an empty range there, and `AVPlayer` draws no video for an invalid
composition — no error, no failed item. `CompositionBuilder+InstructionRanges.swift`
ends the last instruction on the composition when the two differ by under a
tick.

**No MCP script can see this one, which is the reason for a probe.**
`render_frame` and `export` go through `AVAssetImageGenerator` and the export
writer, both of which tolerate the invalid composition, so every MCP
comparison passes against the broken build. The probe compiles the whole of
`app/Sources` with the harness's swiftc line and the app's `Compositor.metal`
beside it (`phase7_chrome.py`'s reason), builds its fixture with `ffmpeg` into
`work/preview-validity/` — video at timescale 600 and shorter than the audio,
the recordings' own shape, under a `project.json` with the recorded project's
exact ticks — and checks that the overrun REPRODUCES before it claims anything
about the repair. Section 4 opens the package in a real editor window and
reads `AVPlayerLayer.displayedPixelBuffer()` on the editor's own player (phase
8's measured instrument); a locked console displays nothing in any layer, so
it reads `IOConsoleLocked` and skips those five rows BY NAME.

**24/24** at the landing, console unlocked. Mutants, on the working tree with
the probe rebuilt: `instructionRanges` returning the plan's ranges
unconditionally **14/24** (the built composition invalid, the absorbing rows,
and all five player rows — the reported defect exactly); the bound widened
from one tick to eleven **21/24** (the three whole-tick rows).

## Mixed audio formats on one track (`mixed_audio_probe.py`, `mixed_audio_proof.py`)

kpgalligan/reelcut#34: an AAC clip then a WAV on ONE timeline track previewed
silent, while the WAV on a second track played. `CompositionBuilder` put every
segment of a plan audio track into one composition track, which then carried
two format descriptions; the preview's build is the one METERING build, every
audio track gets an `MTAudioProcessingTap`, and an `AVPlayerItem` over a tapped
track that changes format does not play. The builder now makes one composition
track per source audio format (`CompositionBuilder+AudioTracks.swift`, spec
§11 R2-1) — the user's workaround, applied for them.

**Section 4 of the probe is the proof of the fix, and nothing else is.** The
export's reader always played the heterogeneous track, so the probe's section
3 and the whole of `mixed_audio_proof.py` pass on the baseline too: they are
REGRESSION GUARDS for the export path, whose track count the fix changes. The
probe is `preview_validity_probe.py`'s shape — a `main.swift` over the whole
of `app/Sources` with the harness's swiftc line, `Compositor.metal` and
`Blank.mp4` beside it, a build failure scored — plus `peaks_probe.py`'s
`--sources PATH` to build it over another tree (one binary directory per
tree). It writes four tone files with `ffmpeg` per run (48 kHz stereo AAC
twice, 48 kHz stereo 16-bit WAV, 44.1 kHz mono 16-bit WAV) and four
hand-written packages: `mixed` (the report), `same` (two AAC — CONTROL),
`three` (AAC, WAV, AAC, 44.1 kHz WAV) and `split` (the workaround). Sections:
1, the MECHANISM (`mixed`'s first composition track carries one format
description); 2, the composition track ids, one mix input and one meter per
track, the video composition valid; 3, the reader over each build's audio
mix, loud in every clip and silent between, and `mixed` against `split`
sample for sample; 4, the editor's own `Playback` in a real window — seek,
play 1.2 s, the meter lit and the clock moved at least 0.4 s, silent after
pause — at `mixed` 0.5 s and 3.5 s and the CONTROLs `split` and `same` at
3.5 s. Section 4 is skipped by name only for a host with no default output
device, and that skip means the defect was NOT reproduced.

Two readings are calibrated to what was measured, both on the baseline and
the fix alike. The clock threshold is 0.4 s, not 0.8: on a Bluetooth output
(AirPods Max) the player's clock starts 0.45–0.6 s late and the CONTROLs move
0.70–0.76 s in 1.2 s, where the stall moves 0.000. And `mixed` against
`split` leaves out 3.000–3.026 s (the measured span, 3.0000208–3.0249896 s, rounded up): the plan track's envelope steps 0 → 1 at the
WAV's start, that step sits on `mixed`'s WAV track and not on `split`'s, and
AVFoundation's mix smooths it over 1200 frames; outside it the two are
byte-equal. `same`'s "one format" is one stream description, because two AAC
files are two format descriptions of one format.

**37/37** on the fix. Over the baseline (`git archive 3e1bd19 app/Sources |
tar -x -C tools/proof/work/mixed-audio/baseline`, then `--sources
tools/proof/work/mixed-audio/baseline/app/Sources`) **31/37**: section 1, three
section-2 id rows, and `mixed` at 0.5 s and 3.5 s — the STALL form, the clock
at 0.000 s and the meter silent — while both CONTROLs and all of section 3
pass. `mixed_audio_proof.py` **13/13**: `import_media`, both clips on one
track, an `audio_wav` export loud, silent between and the WAV at its own
level (−24.08 dBFS against the file's −24.08), the `split` CONTROL equal to it
outside the step, and the `same` CONTROL loud.

## The paused preview that did not follow an edit (`preview_refresh_probe.py`)

With the transport paused, changing a clip's attributes — opacity, scale,
anything the compositor reads from `RecipeSource` without a rebuild, spec
§7.6's property-only branch — left the preview on the OLD picture until the
playhead moved or the transport ran. `Playback.update` did what §7.6 said:
publish the project, find the plan JSON equal, and "re-seek to the current
time with zero tolerance to force one composed frame (the standard trick)".
On macOS 26.5.1 that trick is a no-op, measured: the completion fires with
`finished`, no composition request is issued, and `AVPlayerLayer` keeps its
buffer; re-assigning the item's `videoComposition` and `AVPlayerItem.seek`
to the same time are the same no-op, and a seek to a DIFFERENT time
composes. `Playback.refreshPausedFrame` now seeks one tick off the playhead
(inside the same frame) with the return queued behind it, landing back on
the playhead's own tick with the new recipe drawn; parked AT the end it
rests on the last frame's final tick instead, because the end tick composes
the empty canvas (every seek to it, tolerant or not, displays black — a
round trip there blanked the frame a transport had played to); and a
refresh asked for while a seek is in flight is remembered and run when the
seek lands, where the old guard dropped it. View ▸ Preview Quality relies on
the same refresh and was invisible on a paused player for the same reason.

**No MCP script can see this one either.** `render_frame` composes offline
through `AVAssetImageGenerator`, which asks the compositor fresh every
time, so every MCP frame comparison passed against the broken build. This is
`preview_validity_probe.py`'s instrument: a `main.swift` over the whole of
`app/Sources`, the app's `Compositor.metal` beside it, an `ffmpeg` test card
under a one-clip `project.json` in `work/preview-refresh/`, a real editor
window, and `AVPlayerLayer.displayedPixelBuffer()` read off the editor's own
player after each edit — applied through `ProjectDocument.applyEdit`, the
inspector's path. Two things the instrument had to learn. It captures on
SETTLE (the harness's rule): a sample at one fixed instant read the buffer
as nil about one run in three after a quality change, with the transport at
rest on the right tick and every poll since answering at once — an instant
with no buffer, not a layer left with none. And the dropped-refresh mutant
survived the obvious rows, because a seek already in flight composes AFTER
the recipe is published; the window `refreshWanted` exists for is a seek
whose frame has composed but whose completion has not yet run on main, and
the probe hits it on purpose by holding the main thread 300 ms between the
move and the edit. It reads `IOConsoleLocked` and skips every row BY NAME on
a locked console.

**58/58** at the landing, console unlocked. Mutants, on the working tree with
the probe rebuilt: the same-time seek restored **48/58** (every row where
the picture has to change); the refresh-while-seeking dropped **57/58** (the
held-thread row alone); the end branch removed **54/58** (the four end rows,
the layer black on the end tick).

## A timeline with no media, played (`media_less_playback_probe.py`)

A timeline of ONLY graphics, text, shapes or images — Insert ▸ Graphic into
an empty document is the common way to make one — showed nothing in the
editor and Play beeped (road map 10 §10.8). The core gives those layers no
composition segment (spec §7.2), so the plan has no track, and
`Playback.startRebuild` dropped the player item for any plan with no track:
a guard meant for the EMPTY timeline. `CompositionBuilder`'s placeholder,
which exports and `render_frame` already used, never got the chance. The
guard now drops the item only when the plan's duration is 0.

**No MCP script can see this one.** `render_frame` composes offline and
drew these timelines all along; the defect is in the editor's own player.
The instrument is `media_less_playback_probe.swift`, compiled as
`main.swift` over the whole of `app/Sources` (`--sources PATH` builds it
over another tree, `mixed_audio_probe.py`'s tag scheme), with the app's
`Compositor.metal`, `Fonts` and `Blank.mp4` beside it. Every subprocess
goes through `graphics_spike/bounded.py`, and a build failure scores every
row as a FAILURE. It writes five one-clip packages under
`work/media-less-playback/` each run (no ffmpeg; the image is a white PNG
written with `zlib`): `graphic` (a module whose white bar grows from a
quarter of the width to all of it), `text`, `shape` and `image`, each
white on a black 432 × 280 canvas, and `empty`, the CONTROL. It opens each
in a real editor window and reads the editor's own player: the item and its
video composition's validity, the Play/Pause validator, play, `setRate(2)`,
the in/out loop, moves of the playhead, a paused opacity edit (the
refresh branch on the placeholder item), and `displayedPixelBuffer()` as a
40 × 40-grid mean. For `empty` it checks that nothing plays, that Insert ▸
Shape then brings an item that plays, and that undo takes it away again.

**What the instrument had to learn.** `displayedPixelBuffer()` answers nil
for ANY playing layer. A media clip's did too (measured on
`preview_refresh_probe.py`'s test card, 2026-09-25). So the row that needs
frames drawn WHILE PLAYING reads them from an `AVPlayerItemVideoOutput`
added to the item for the run: the same item, composition and compositor.
The rows that read the picture (F·2, F·5, F·6, G·7) are skipped BY NAME on
a locked console (`IOConsoleLocked`). Every other row is always scored,
and a skip means the proof is not complete.

**32/32** at the fix, console unlocked. Made to fail over cadc45d's
`app/Sources` (`git archive cadc45d app/Sources | tar -x -C
tools/proof/work/media-less-playback/baseline`, then `--sources
tools/proof/work/media-less-playback/baseline/app/Sources`): **8/32**.
F·1, F·2, F·4, F·5 and F·6 fail for all four media-less fixtures (no
item), and G·7, G·8, G·9 and E·4 fail. The four F·3 validator rows and
E·1, E·2, E·3 and E·5 pass on both trees, so a failing row is the
defect and not the host.

## The playhead echo (`playhead_echo_probe.py`)

Dragging a clip flashed the playhead to 0 and back, and with the playhead
scrolled off screen it yanked the timeline back to it
(`archive/reelcut-app-notes.md`, "The playhead echo, 2026-09-26").
`Playback` reported its OWN seeks as playhead moves: the periodic time
observer fires on every time jump, so a rebuild's item swap (the new item
starts at 0) and its re-land, and the paused refresh's one-tick round trip,
all reached `onTimeChanged`, and the editor wrote each one to the document,
the timeline (which reveals any change) and the action entry rule. The fix
splits the asked seek (`seek(to:)`) from the restore (`startSeek` under
`restoring`): a restore is silent, and heard once on landing only if it
rests off the tick last reported.

**No MCP script can see this one**: no tool reads what the editor's own
player reports. The instrument is `playhead_echo_probe.swift`, compiled as
`main.swift` over the whole of `app/Sources` (`--sources PATH` builds it
over another tree), `media_less_playback_probe.py`'s build line and tag
scheme, every subprocess under `graphics_spike/bounded.py`, a build failure
or a missing ffmpeg scoring every row as a FAILURE. It writes `card.mov`
(an 8 s test card, ffmpeg) and `echo.reelcut` (432 × 280 at 30 fps, clip 3
at 0–3 s and clip 4 at 4–6 s) under `work/playhead-echo/` each run, opens
the package in a real editor window and WRAPS the editor's
`playback.onTimeChanged`, logging every tick before forwarding it. Each
action clears the log and settles 1.5 s. The rows: a paused opacity edit
(refresh·1–3), the right arrow (step·1), `setPlayhead` (seek·1), a live
drag of five ticks 0.25 s apart and a non-live move (rebuild·1–4), a
deselected action span that holds 1 s and not 0 under a structural edit
(action·1, spec §11 CI-1), the timeline zoomed to `maxZoom` and scrolled to
4 s during a live drag, with `revealPlayhead`'s band read off the clip view
(reveal·1–3), play, a structural edit mid-play and the loop wrap (play·1,
play·2, loop·1), the end-parked refresh and playing into the end (end·1,
end·2), and clip 4 deleted under a 5 s playhead (short·1, short·2). No row
reads a picture, so every row is scored whatever the console state; the
first printed line names it.

**20/20** at the fix, console unlocked. Made to fail over f7dd9e3's
`app/Sources` (`git archive f7dd9e3 app/Sources | tar -x -C
tools/proof/work/playhead-echo/baseline`, then `--sources
tools/proof/work/playhead-echo/baseline/app/Sources`): **13/20**. The five
predicted rows fail: refresh·2 (reports `[600001, 600000]`, the round
trip), rebuild·2 (`0, 600000` five times), rebuild·4 (`[0, 600000]`),
action·1 (the span re-selected, `selectedAction` 5) and reveal·2 (the clip
view's `minX` from 16132 to 3685 on the first tick). The two unpredicted
rows fail there too: play·2 (a `0` reported mid-play after the edit) and
short·2 (`[0, 3000000, 2020000]`; at the fix `[2020000]`). The thirteen
others are CONTROLS and pass on both trees, end·1 among them: parked at the
end, both trees report `[3639999]`, `duration − 1`, once.

## The transition sheet (`transition_sheet_probe.py`)

Clip ▸ Transition ▸ at a hard cut between two WHOLE files used to beep and
nothing else: `add_transition` builds the overlap from handles (spec §11,
R5-3) and a whole file has none. `setTransitionKindCommand` now tries the
batch first and, when no `add_transition` in it would land, puts up a sheet
saying why, whose **Shift Clips Left** re-sends those cuts with `ripple`
(R5-3's 2026-09-16 amendment) as one undo step. The core's rules for
`ripple` are `core/tests/ripple_transition.rs`'s; this is the COMMAND — when
the sheet appears and when it must not, what it says, what each button does,
and that a shift undoes byte for byte. A sheet, a menu validator and an undo
step have no MCP tool, so it is a probe over the whole of `app/Sources` with
an editor in a real window; `window.endSheet(_:returnCode:)` presses a button,
running the sheet's own completion. Its fixture is one six-second `ffmpeg`
movie in `work/transition-sheet/`, opened as a new project so every clip of it
is whole.

**32/32** at the landing, **39/39** since the E1 reader review (road map 5
§12, R3·1) added §8, two chosen cuts whose shifts COLLIDE — one ripple slides
the second cut's incoming clip over a predecessor that does not slide with
it, so the second `add_transition` sees an overlap and answers `Err`.
Mutants: the sheet never presented **14/32**; the button sending
`ripple: false` **24/32**; the trial's apply guard reduced to "only an
all-`set_transition` batch" **28/32** (the split pair and the mixed
selection); §8's fix reverted — the button mapping the cuts straight to
`ripple` ops from one snapshot instead of re-deciding each against the
running project — **33/39**, five of §8's six rows, with the attached error
sheet reading `clip 7 is not at a hard cut: it already overlaps clip 6 — use
set_transition or set_transition_duration` and nothing landed at all.
**One survivor**: the button calling `applyEdit` instead of
`performGroupedEdit` scores 32/32. The grouped entry point is mandatory
because an undo registration outside an AppKit event lands in an implicit
group AppKit never closes, merging it with the next such edit — and the probe
spins the run loop between every edit, which closes that group, so the merge
cannot be staged here. The rule stays, argued in the sheet's doc comment and
app/CLAUDE.md's undo pitfall.

## The patch door (`patch_door_proof.py`)

`python3 tools/proof/patch_door_proof.py [port]`. **Named for the SEAM, not
for a phase**, which is the one thing about it that is not the house shape:
what it proves is the single door every caller-authored object comes through
(`core/src/patch.rs`, `CONTEXT.md`'s **Patch**), and the doors arrive one
deepening ticket at a time (`archive/reelcut-roadmap-7.md` §1). D1·3
(kpgalligan/reelcut#4) built it with `set_video`'s section, at **39/39**;
D1·4 (#5) added eight more, at **199/199**; D1·5 (#6) added the last two —
`set_action_end` and `add_zoom_action`'s region — and it is **258/258**, with
every door the app has in it. Each door file says in a marked comment what a
LATER phase's door copies; neither kind is owed one today.

**It is four files and one script.** The sections outgrew a single file when
D1·4's eight landed, so the split went by kind — for navigation, since a
proof script is not held to the 400-line cap a new SOURCE module gets
(`archive/reelcut-roadmap-7.md` §2.4 argues it; most scripts here are well
past it):

| File | What is in it |
|---|---|
| `patch_door.py` | the harness — `Session`, and the four helpers every section is built out of. Split off ALONE, as a pure move, before a door was added |
| `patch_door_patches.py` | the doors whose caller-authored object is a PATCH: `set_video`, `set_audio`, `set_text`, `set_shape`, `set_clip`, `set_action_end` |
| `patch_door_args.py` | the doors whose object is an ARGUMENT: `add_text_clip`'s `text`, `add_shape_clip`'s `shape`, `set_canvas`'s `background`, `add_background`'s `color`, `add_zoom_action`'s `region` |
| `patch_door_proof.py` | what a patch means, which sentences the core gives, and `main`. The only one to run |

What it asserts, per door: the four refusal sentences VERBATIM rather than
by keyword (`unknown key`, `missing key`, `bad value at`, `<group> patch
must be a json object`), the project BYTE-identical either side of every
refusal, that one `undo` after a whole batch of refusals puts back the one
real edit that preceded them — so not one refusal registered a step — and
then the merge rules read back through `get_project` (one key changed,
siblings kept, `null` clearing, a list replacing, a motion slot kept) and
the frame-grid snap the core applies to the ticks a patch carries. An
ARGUMENT door has no group to name, so its wrong TYPE is the op envelope's
sentence one level out (`op "set_canvas" is not valid: invalid length 3,
expected an array of length 4`) with `props_check.rs`'s range refusal under
it; the two new-clip doors also assert that the bare-string shorthand still
makes a clip with those words, and a shape clip of that kind.

Two doors answer in their own way and §10 and §11 say so. `set_action_end`'s
patch spans three groups, so every path carries the group
(`video.filters[1].kind`) and the subject is `an action end patch`; it is the
one door that does NOT range-check, because an animation may aim past what a
stored property could hold, and a `null` there REMOVES a key from the end
state rather than clearing a property. `add_zoom_action`'s region is the one
op argument the core reads as a TYPE, so a misspelt, missing or wrong-typed
member is named INSIDE the envelope's sentence
(``op "add_zoom_action" is not valid: bad value at "region.widht": unknown
field `widht` ``) and a four-number list is refused rather than read
positionally; the absent KEY is the one judgement its handler kept, since the
op reads an absent argument and an explicit null identically and here they
are opposite edits.

**Why it exists beside `core/tests/patch_door.rs`, which proves the same
rules through the FFI.** Those tests cannot see the Swift agent door, which
until D1·3 decoded the caller's object through the app's LENIENT project
types and sent the RESULT to the core: a misspelt enum landed as the
vocabulary's first case, an unknown key inside a nested object was dropped,
a three-element colour had an alpha filled in and an out-of-range component
was clamped — each of them reported as a success. Only a call made over MCP
against the built binary tells the two apart. It needs no ffmpeg and nothing
in `media/` but `A.mov`.

Assertions elsewhere moved here in spirit rather than in place, each noted in
its own file. D1·3: `phase6_proof.py`'s `set_video` refusals (the partial
filter entry, the misspelt filter kind, the misspelt blend) now assert the
core's whole sentence instead of the Swift door's `patch.`-prefixed key, and
`phase3_proof.py`'s printed NOTE that a misspelt key inside a nested object
was dropped is two CHECKS now, because it no longer is. D1·4:
`phase2_proof.py`'s three `set_clip` typos, `phase4_proof.py`'s two text
animation kinds and `phase6_proof.py`'s three gradient refusals are the
core's sentences, and phase 6's "a THREE-component stop colour is accepted
and means the four-component one" is now a REFUSAL — a colour is four
numbers at every door, so that script is one check longer (167 → 168). D1·5:
`phase6_proof.py`'s two `set_action_end` refusals (the partial filter entry
and the misspelt blend inside an end patch) are the core's whole sentences
with the GROUP in the path, and `phase3_proof.py`'s region check asserts the
whole of the one refusal its handler kept rather than the word `region`,
which every refusal at that door said.

## What an op answers (`refusal_proof.py`)

`python3 tools/proof/refusal_proof.py [port]`. **Named for the SEAM, not for
a phase**, as the patch door is: what it proves is the answer every edit
comes back with (`core/src/outcome.rs`, `app/Sources/ReelEdit.swift`,
`CONTEXT.md`'s **Op**), and the rules that can say WHY arrive one deepening
ticket at a time (`archive/reelcut-roadmap-7.md` §4, kpgalligan/reelcut#8).
Deepening D2·2 (#10) built it with the overlap rule's section, at
**39/39** (40/40 after its review); D2·3 (#11) took it to **113/113** with
one section per rule that found its voice, each a copy of `overlap_rule`;
and D2·4 (#12), which deleted the app-side answers that stood in front of
four of them, took it to **116/116**.

An op answers one of three ways: it applied, it was an IDENTITY (valid, and
nothing needed to change), or it was REFUSED (a rule declined it, in the
rule's own words). The last two are both "the project did not change" —
neither registers an undo step, neither is an error tier, and a person at
the machine gets the same beep for both — and until D2 nothing outside the
core could tell them apart. The two sentences an agent now reads are
asserted WHOLE and never by keyword:

    <Action> made no change: the project is already in that state.
    <Action> was refused at <op>: <the rule's own sentence>

| Section | What it measures |
|---|---|
| 1 — the overlap rule | the rule's whole sentence, ids and tick counts included, out of `move_clip`, out of `duplicate` (which names the copy it never made) and out of a SCOPED call; an overlap one frame under the limit still applying, so the number in the sentence is the rule's own boundary; the project unchanged either side of every refusal; and ONE undo putting back the marker edit, so not one of them registered a step |
| 2 — an identity | four doors (`set_video`, `set_clip`, `set_canvas`, `split`) asked for the value the project already holds, each answering that whole sentence and NOTHING else — an equality, which is the only way to measure "says only that" — and naming no rule |
| 3 — several ops | `normalize_clip` sends one `set_audio` per clip, so it is where the fold over a list is observable: a list of identities answers the identity, one undo puts both clips back, and a later op still runs after an earlier identity |
| 4 — a locked track | `close_gap` over a gap that is really there and `insert_clip` with room to spare, both naming the track to unlock (`core/src/edit_time.rs`'s `locked_track`, written once for its three callers); the lock undone and both landing; and the same `close_gap` on a time that is ON a clip still answering the IDENTITY, which is the distinction the whole candidate is about, at one op |
| 5 — the track stack | the only track in a project, refused with and without `with_clips: true` — the flag is the way past the OTHER refusal and not past this one — a second track making the same call land, a track that still holds clips naming the CLIP rather than a count, and that flag then taking the track and its clip |
| 6 — a media row | a media one clip still shows, refused naming that clip and `with_clips: true`, and an unused row still going with no argument at all |
| 7 — the transition cut | a cut with no unused material, refused naming the request in whole FRAMES (15, hand-computed) and `ripple: true`; the same cut taking a RIPPLED transition, which slides the incoming clip by exactly the overlap asked for; and that rippled form on a LOCKED track, which is `locked_track`'s third caller |
| 8 — the action rules | an action inside another and an action past the clip's end, each out of `add_action` AND `set_action` in the same words; and two boundaries that land — abutting is not overlapping, and an action ending exactly at the clip's end fits |
| 9 — off the track stack | a two-track selection moved one track too far, naming the clip that would go off the top and the index it would land on, in `move_track`'s own words for the same mistake |

Every refusal and every identity also asserts the ABSENCE of two fragments
of the paragraph D2·2 deleted ("Either the project is already in that
state", "the usual reason for a placement op is the overlap rule"). That
paragraph also began "<Action> made no change", so a check looking only for
the new words would pass against a build that still sent it.

**Four checks used to measure the APP's sentence and not the core's, and
said so by name** — a `shadowed` helper at §5d, §6b, §7b and §7d, where
`AgentServer+Media.swift`'s and `AgentServer+Tracks.swift`'s `with_clips`
guards and `AgentServer+Transitions.swift`'s trial-apply each asked the same
question one step earlier and answered in their own words. D2·4
(kpgalligan/reelcut#12) deleted all four, and those checks are ordinary
`refused` calls against the core's sentence now; the helper is gone with
them, and the app's old wording is kept in road map 7 §5.4's own "what
went" table. The gap
D2·3 measured with its mutant 7 — the transition rule turned back into a
bare identity, taken by a core test and invisible here — is closed: the same
mutant is D2·4's, and this script takes it.

**What section 3 cannot reach, said so it is not rediscovered as a gap.**
Only three tools send a list of ops — `normalize_clip`, `import_captions`
and `consolidate_media` — and none can send one where NOTHING applied and
something was refused: a `set_audio` of a measured gain has no rule to
decline it, `CaptionLayout` probes its own batch and refuses app-side before
the shared reply is reached, and `consolidate_media` short-circuits an empty
plan. The op-naming half of that answer is proved in §1, which goes through
the same one format string. When a tool gains such a list, its fixture goes
in §3.

**Why it exists beside `core/tests/refusal.rs`**, which proves the three
arms through the FFI: those tests cannot see the Swift side of the seam —
whether the app reads `reason_out` at all, whether the agent's shared reply
still guesses, and whether a refusal is still no undo step once it has been
through `ProjectDocument`. It needs no ffmpeg, and nothing in `media/` but
`A.mov`, `AV.mov` and `B.mov`.

## A refusal, where a person meets it (`refusal_probe.py`)

`python3 tools/proof/refusal_probe.py`, no port and no running app. The
PROBE beside `refusal_proof.py`, for the three app paths no MCP call can
reach. The agent's own path refuses at `AgentServer.performGroupedEdit`'s
trial and never asks the document, so `ProjectDocument.applyEdit`,
`updateLiveEdit` and `endLiveEdit` never see a refusal over the wire; this
is `CLAUDE.md`'s answer for app STRUCTURE with no caller a script can reach
— a probe compiled out of `app/Sources` over `harness/build.sh`'s own
swiftc line, cached on modification times, a build failure scored as a
FAILURE rather than an exit. **15/15** at deepening D2·2 (#10).

It drives one live `ProjectDocument` over two abutting ten-second text
clips — no media file, so every tick is hand-computable — and scores five
things: that the core answers the three arms it was handed (a refused move,
an identity, and an unknown id that throws); that `applyEdit`'s two
non-applied arms leave the HANDLE where it was and do not rename the undo
step; that a refused tick mid-drag is swallowed and the gesture ends with no
step of its own; that ONE undo afterwards puts the project back to before
the marker edit, leaving the fixture's own step under it; and that the
invalid-input tier still throws in the core's own words.

**"No error dialog" is measured by the probe answering at all.**
`ProjectDocument.present(_:)` with no window runs `presentError(_:)`, a
modal alert nobody is there to dismiss, so a build that treated a refusal as
the invalid tier would BLOCK — the runner gives it a 120 s timeout and
scores a hang as the failure it is. The beep is the one consequence nothing
here can observe; it is a single statement the two non-applied arms share.

**`performGroupedEdit`'s two answers that are not an edit** (#59), section
6, scored. It used to open an undo group and balance it whatever the edit
answered, so an identity or a refusal left an EMPTY step behind — one a
person had to press ⌘Z past — and cleared the redo. It now opens its
explicit group only around an APPLIED edit (`commitEdit`). Each row starts
from a redo of its own (a real grouped edit, then undo) and holds
`canUndo`, `undoActionName`, `canRedo` and `redoActionName` to what they
were before the answer. Measured 2026-09-29: 17/17; the same probe over
HEAD 97e870a's `app/Sources` fails exactly those two rows (15/17).

## The op table, read back through the app (`op_schema_probe.py`)

`python3 tools/proof/op_schema_probe.py`, no port and no running app. Road
map 7's D3·2 publishes every op's ARGUMENTS as JSON Schema through
`rc_op_schemas`, and `ReelOp.coreSchemas()` is the app's one reader of it.
It measures the EXPORT rather than what any caller does with it — what the
catalog does with it is `clip_catalog_proof.py` below — so the instrument is
`CLAUDE.md`'s
answer for app STRUCTURE with no caller a script can reach: a probe compiled
out of `app/Sources` over `harness/build.sh`'s own swiftc line, cached on
modification times, a build failure scored as a FAILURE rather than an exit.
**28/28** at D3·2 (#16). It needs `core/target/release/libreelcut_core.a` —
`make test` or `cd core && cargo build --release` first, or the build check
fails naming the missing file.

Five sections. **The map**: `coreSchemas()`'s keys against `coreNames()`'s
names in both directions — two separate exports read separately, so a schema
map that dropped an op, or invented one, is named. **The identity**: for
each of the 57 ops the probe sends an envelope carrying one key no op has,
serde refuses it with the list of fields it DID expect, and that list is
compared to the published properties; and the same op sent with NO arguments
makes serde name the first field it could not do without, which must be one
the schema calls required. **No argument name is written in the script**,
which is what spec kpgalligan/reelcut#14 asks for in place of the Python
literals the older proofs carry. **The envelope**: neither `scope`
nor `project` is in any published schema; the catalog injects both.
**The kinds**: one representative argument per kind against the JSON Schema
the mapping owes it (an id's `minimum: 0`, ticks with none because a delta
is negative, a patch as an object with no properties, a region as the four
members the core declares and closes). **The vocabularies**: each of the
five arrives as a string — or a list of them — with a non-empty `enum`;
WHICH members it has is `core/tests/op_table.rs`'s claim against the
decoder, not a list retyped here.

The twelve kind rows are the only literals, and they are about the MAPPING
rather than about which arguments exist: they are the one claim a probe
reading the core's own answer cannot make about itself.

## The clip tools against the table (`clip_catalog_proof.py`)

`python3 tools/proof/clip_catalog_proof.py <port>`, against a running
instance. Road map 7's D3·3 migrated the clip group's 43 op tools to PRINT
the core's table instead of restating it, and this measures the identity
that makes that safe from two independent sides: the CATALOG, read over MCP
off `tools/list` from the running binary, and the TABLE, read out of the
staticlib by a probe of its own (`coreSchemas()` plus
`AgentServer.declarations`, built the way `op_schema_probe.py` builds its
probe and scored the same way when it will not compile). **23/23** at D3·3
(#17), **24/24** since D3·4 (#18) added a row, and 24/24 again on 2026-09-19.
The probe is built BEFORE the first MCP call, so no swiftc runs while
the proof is driving the app.

**No argument name is written in the script.** The expectation is computed
from the table and the declarations by an oracle written in Python rather
than imported, so a bug in the Swift merge is a failure and not a shared
opinion; the only names typed are the two ends of the clip group in catalog
order (`add_clip` … `remove_action`, which is how the group is found without
a list of 43) and the ops the behavioural section drives, and both are
checked against the core's op list first.

Four sections. **The group**: the run between those two ends holds exactly
43 op tools and 2 composites, the composites found by asking the core which
names it calls ops. **The identity**: every one of the 43 declares exactly
the core's arguments, kinds, enums, minimums and required list, plus the
injected `project` and `scope`, modified only by what the declarations list
names; descriptions are checked for EXISTING, never for content, because
what an argument is FOR is the app's. **The vocabularies**: the four a
HANDLER still parses by name — a transition kind, a zoom fit, a curve,
`paste_attributes`'s groups — against the `enum` the core now publishes,
which is the one tie the migration would otherwise have cut. **The
declarations**: every row still names an op and an argument the core has —
the staleness check `AgentServer.opsWithoutTools` has and this list has not —
and each row is true of the running app: the bare-string bodies
work AND are declared (which is the row a widening deleted from the list
falls to, since the catalog and the oracle would otherwise still agree with
each other), a boolean takes `"false"`, the two meaningful nulls are taken
and required, an empty clip list is refused by name, and `split` takes the
playhead although the core requires `at`.

It does NOT claim that `set_speed` clamps a rate rather than refusing it:
that needs a media clip, this script makes none, and the claim is the core's
own in `core/tests/op_table.rs`.

## Every op tool against the table (`op_catalog_proof.py`)

`python3 tools/proof/op_catalog_proof.py <port>`, against a running
instance. Road map 7's D3·4 migrated the last fourteen op tools — the nine
track, marker and canvas rows, the three raw media ops and the two
transitions — so this measures the WHOLE catalog where `clip_catalog_proof.py`
measures the clip group: the same two independent sides (the CATALOG over
MCP, the TABLE out of the staticlib through a probe built the way
`op_schema_probe.py` builds its own and scored the same way when it will not
compile), and the same oracle written in Python rather than imported.
**23/23** at D3·4 (#18), and **23/23** again on 2026-09-20 — the term
readers changed one row's SENTENCE and no row's verdict: `set_canvas
{fps: [0, 1]}` is now refused as `fps[0] must be…`, so the row reads the
path with the name. The probe is built BEFORE the first MCP call.
**23/23** again at road map 10's G3b (2026-09-25), once the two graphic
ops had their tools: it had failed its first check since G2a. The core now
declares 59 ops, and the declarations list has 16 rows: G3b's two
`filledByTheApp` rows take `schema` OUT of `add_graphic_clip` and
`set_graphic` (the app reads it from the module), so `expected_input` skips
such an argument and the probe's `requirement()` switch names the case. The
counts in the paragraphs below are D3·4's.

**Its structural half types no name at all**, not even the ends of a group:
the group IS the core's op list (`rc_op_names`), so an op renamed on both
sides is still measured and an op that lost its tool is named. The
behavioural half names the seven ops it drives and checks each against that
list first.

Five sections. **The catalog**: the core declares 57 ops, every one is a
tool carrying the injected `project` and `scope`, and none of the 20
app-state tools carries a `scope`. **The identity**: all 57 declare exactly
the core's arguments, kinds, enums, minimums, maximums and required list,
modified only by what the declarations list names; exactly one op tool
declares nothing but the envelope's two keys (`remove_empty_tracks`, the one
op with no arguments); every op tool carries its own description and prose on
at least one argument wherever it takes any, and all 145 published
arguments carry the app's prose while the core's table carries none of it
(135 of them until D3·5's fifth parity part made an undescribed argument a
complaint) — which is the division of labour, measured rather than
asserted. **The vocabularies**: the five a HANDLER still parses by name,
`add_transition`'s `align` among them, whose tie to `TransitionAlign` was
structural until the migration made the schema the core's. **The
declarations**: all 14 rows still name something the core has. **The running
app**: a marker with no `at` lands at the playhead although the core
requires it, a track switch takes `"true"`, a negative id is refused by name
where the schema says `minimum: 0`, `set_canvas` refuses a width one step
under the bound it publishes and names both ends and a frame rate with a
zero term where its items say `minimum: 1`, `add_transition`'s `kind` is
refused an explicit null and never offered one (the opposite of
`set_transition`'s), and `add_media`'s descriptor is an object with no
properties that refuses a string by name.

That last section is the half a generated schema cannot do without, and
D3·3's `ripple_delete_ranges.ranges` is why: the oracle is built from the
same declarations list the catalog is, so a row dropped from the list moves
BOTH sides of the comparison together and the structural half stays green.
Only a row that asks the RUNNING APP can see a declaration dropped while the
behaviour stays.


## A stranger argument, put to all 82 (`op_argument_proof.py`)

`python3 tools/proof/op_argument_proof.py <port>`, against a running
instance. Road map 7's D3·5, then the **argument gate** of
kpgalligan/reelcut#21, and **the script that owns the exact tool count**
(77). **133/133** on 2026-09-20, when the frame-rate TERM rows landed;
116/116 at #21; 86/86 at D3·5 (#19), 79 of those rows before the review added
the optional half of section 3. The probe is built BEFORE the first MCP call.
**138/138** at road map 10's G3b (2026-09-25), with `TOOLS = 79` and
`OPS = 59`: the two graphic ops' `schema` is a `filledByTheApp` row, which
the attribution section counts as used when the tool leaves it out and the
stranger section leaves out of what a tool takes; and the opaque-door
section counts 13 doors, reaching the two graphic ones by moving a
`proof.js` into the untitled fixture's
`<DARWIN_USER_TEMP_DIR>/Reelcut/*-graphics` root and pointing `set_graphic`
at the clip `add_graphic_clip` lands from it. The counts in the paragraphs
below are the ones before G3b.

It exists because of the rule D3·3 and D3·4 each paid for: **a generated
artefact is checked by asking the thing that generated it a question it did
not write the answer to.** The startup parity check's fifth part reads the
same published table the catalog prints, so it cannot see a constraint the app
still ENFORCES that the table stops DECLARING — so the weight here is on the
sections that call the running tool.

Six sections. **The fifth part, made to complain**: a probe compiled from
`app/Sources` builds the catalog this binary registers, puts it to
`AgentServer.argumentFailure` (which must say nothing), and then puts four
broken catalogs to it — an op tool with an argument the core has not got, one
missing an argument the core has, one whose argument lost its description, and
one whose prose names an argument no op has — each of which must be named with
its op, its argument and the side that has it, while an APP-STATE tool broken
the same way must draw nothing. **The catalog's size**: exactly 77 tools, 57
ops each with a tool, and the shipped binary's own parity log empty. **The
attribution**: every difference between a tool's schema and the core's table
is one `AgentServer.declarations` names — not a second computation of the
merge, which is `op_catalog_proof.py`'s, but a key-by-key attribution, plus
the inverse, that every row accounts for at least one difference, so a row
that changes nothing fails here. **The stranger argument**: for each of the
57 op tools, one CONTROL call with every required argument spelled right
(which must not be refused for a missing one — the tool's required list
proved SUFFICIENT against the running app); one call per required argument
with that argument LEFT OUT, which must be refused naming it — the handler
reads it; and one call per argument the core publishes, required or not, with
that argument MISSPELT beside the control, plus one carrying two names no op
has, each of which must draw the gate's sentence — the tool, the stranger
and EXACTLY what the tool takes, read back out of the sentence and compared
as a set to the core's row, the declarations' rows and the envelope's two
keys. That last row is what reaches all 57, `remove_empty_tracks` included,
where the refusal rows reached 51 before the gate. **Six op tools require
nothing**, so no left-out row can reach them; the gate reads a NAME against
the schema and never whether anything reads the value, so for those six what
is read instead is what the op DID — the same call twice, once with the
argument and once without it, answering two different projects. `split`'s
`clips` is the one argument this fixture cannot separate — the playhead sits
inside the only clip at that time — and it is named in the script with its
reason and asserted to be the whole of the exceptions. Then **a fraction
where a whole number belongs** — `trim_start {clip: 3.5}` and
`delete {clips: [3.5]}` — is refused rather than truncated to clip 3, and
`{clip: 3.0}` is still the id. Then **a TERM of a frame rate**, the 17 rows
of 2026-09-20 that closed `archive/reelcut-remaining.md` §5's residue: the
two `[numerator, denominator]` readers took each half through `intValue`
after the gate, so `set_canvas {fps: [29.97, 1]}` was 29 fps in silence;
both now read through `rateTerm`, and a fraction, a zero, a negative,
`Int64.max`, one past u32, a string and a JSON `true` are each refused BY
THEIR PATH (`fps[0]`, `fps[1]`, `descriptor.fps[0]`), a list of the wrong
length is refused as a PAIR, a bare `1e30` no longer traps on `Int(number)`,
the app still answers with `canvas.fps` untouched after all of them, and
`[30000, 1001]` and `[30000.0, 1001.0]` still apply and read back — through
`set_canvas` and through `add_media`'s descriptor.
**The opaque doors**: a misspelt key inside a caller's own object is named
by the CORE, which is where the dotted path lives.
**The twenty tools the core calls no op**: the same two strangers,
sent alone, and the list the gate speaks compared to the catalog's, the one
spelling a hand-written schema has — placed LAST, because on a broken gate
every one of those calls reaches its handler and `new_project` opens a
document over the fixture.

**What the stranger-argument section actually proves.** An op ARGUMENT still
never reaches the core's decoder — the handlers read arguments one at a time
and build the op — so the sentence that names a stranger is the APP's, one
sentence for all 77, and the sentence that names a misspelt KEY inside a
patch is the core's. The section proves both halves of the app's: that every
argument the catalog PRINTS is one a hand-written handler really reads (the
left-out rows), and that every name a caller writes which the catalog does
not print is refused before any handler runs (the gate rows).

**Made to fail on purpose.** With the gate's one call in `dispatch` commented
out and `intArg`'s exact read put back to `intValue`, one build scored
**37/116, exit 1**: all 57 op rows red (a misspelt required argument back to
"Missing required argument: clip", the two strangers back to "applied"), all
20 app-state rows red, both fraction rows red (`delete {clips: [3.5]}`
APPLIED, to clip 3), and no row outside those three groups. The first mutant
run, with the twenty rows placed before section 4, also turned the six door
rows red — `new_project` carrying two strangers had opened a document over
the fixture — which is why the twenty are last.

**And again for the term rows, 2026-09-20.** With `rateTerm`'s read put back
to `(raw as? NSNumber)?.intValue` and only `> 0` kept, a tree copy on its own
port scored **126/133, exit 1**: seven rows red and every one of them in the
new group — `[29.97, 1]`, `[30000, 1001.5]` and `[true, 1]` APPLIED where
they must be refused (the run prints `applied`; what rate each stored was not
read back), `[9223372036854775807, 1]`, `[4294967296, 1]` and the bare `1e30`
came back as the CORE's serde complaint ("expected u32") rather than the
app's sentence, and `add_media`'s descriptor row printed `applied; media 1 →
1`, its count then read AFTER the undo, which is why that row now counts
before it (re-scored 133/133 on a fresh instance after the reorder; the
reordered count was NOT re-run against the mutant, where the row already
went red on its sentence half). The rows that stayed green under it are the ones the old `> 0` already
covered — a zero term, a negative term, a string term, a list of the wrong
length — and the two controls. The mutant also shows what the old bare-number
path did differently from this mutant: `intValue` SATURATES at `Int64.max`
where the shipped `Int(number)` TRAPPED, so `set_canvas {fps: 1e30}` was a
crash and not a wrong rate.

**Four other proofs changed with the gate**, each a live instance of the
defect in an instrument: `phase8_proof.py` and `refusal_proof.py` sent
`add_track` a `kind` it does not take, dropped in silence since they were
written (the argument is gone, the fixtures unchanged); `phase2_proof.py`
MEASURED the missing guard with a stray `name` beside an identity patch, and
that measurement is now a check (85 → 86); `phase9_proof.py` asserted a
`scope` on `get_project` and `render_frame` was "the ignored extra key it
always was", and now asserts the gate's refusal. Every other MCP proof scored
what it scored before, one fresh instance each.

Its values are derived from the core's published kinds rather than typed: an
id by name (six names for five entities — `clips` is a list of the id space
`clip` draws from — the only argument names the script types, each checked
against the core's table first), a time as a second per argument in table
order, a bound's own minimum, a vocabulary's first member.
The two `payload` doors are named rather than skipped: the app checks a
payload's shape before forwarding, so the core cannot be reached through them
without a whole Copy payload, and what is true of them is asserted instead.

## The track context menu (`track_menu_probe.py`)

`python3 tools/proof/track_menu_probe.py`, no port and no running app,
**22/22**. A right-click on a track's header or empty lane opens that
track's menu — Hide Video, Mute Audio, Lock Track, Solo (checked from the
track's own flags) and Remove Track (`TimelineView+TrackMenu.swift`,
2026-09-23). A click is not an op, so no MCP call can reach WHICH track it
names; the instrument is `marquee_probe.py`'s builder, one probe along. It
puts a real `EditorViewController` in an offscreen `NSWindow` over three
tracks — front (a clip at 20 s) and middle empty where it is clicked, back
holding a text clip — sends synthetic right-mouse-down events through the
content view's own `menu(for:)`, performs items inside one undo group as an
event would, and reads the document back. Five sections: where a menu
opens (header, header button and empty lane do, for their row; clip, ruler
and the room below do not); a toggle and its checkmark and undo; Remove
Track on the empty middle track with a clip on the FRONT track selected —
the case Track ▸ Remove Track gets wrong — and its undo; a clip-holding
track's sheet, answered by pressing its Remove button; and the last track's
disabled item. Made to fail twice: `removeTrackCommand` ignoring its id
takes 3 rows (19/22), `menu(for:)` answering nil takes 14 (8/22). ~75 s
with a rebuild. ⌃-click is a person's check (#48).

## The marquee, from anywhere empty (`marquee_probe.py`)

`python3 tools/proof/marquee_probe.py`, no port and no running app,
**28/28**. Spec §4.4's rubber band has been in the tree since M1
(`RangeSession`), and it could only START inside a lane:
`TimelineContentView.hit(at:)` answered `.none` for the 4 pt strip under the
ruler and for everything below the last lane, and `beginGesture` swallows
`.none` — so with one or two tracks, the room a person naturally presses in
to band the clips above it did nothing at all. The fix is a hit case,
`.outside`, and one `beginMarquee` that both it and `.lane` call
(2026-09-19).

A gesture is not an op and a selection is view state, so no MCP call can
reach any of it, and a photograph cannot show what a press DID. The
instrument is `refusal_probe.py`'s: a probe compiled out of `app/Sources`
over `harness/build.sh`'s own swiftc line, cached on modification times, a
build failure a scored FAILURE. It puts a bare `TimelineView` at 1000 × 320
over two tracks of four text clips (A 0–10 s and B 12–20 s on the back
track, C 2–8 s and D 14–22 s on the front) and drives the three entry
points a mouse event reaches — `beginGesture`, `continueGesture`,
`endGesture` — with synthetic points, reading the hit test, the live
session, the selection and every post through `onSelectionChanged` and
`onEdit`. Five sections: what a press lands on (a lane's gap is `.lane`,
the room below and the strip above are `.outside`, the header column under
the lanes is still `.none`, and the room below the lanes is INSIDE the
content view's frame, which is what makes a real press there reach the hit
test); the band from a lane, the control; the band from below, from above,
and ⇧ from below adding; a press with no drag (a click clears and posts
once, a ⇧-click keeps, a double-click below closes no gap where one in a
lane's gap still asks for Close Gap); and the band's rules wherever it
starts (⇧ adds, a band over nothing ends empty, a locked track is skipped,
a band with no height still reads as the line it is).

**Made to fail on purpose**, twice. The new guard put back to `.none` —
the old code — scores **19/28** and takes exactly the nine rows that press
outside a lane, and nothing else. `beginMarquee` without its clear scores
**27/28**, taking the bare-click row alone: a DRAG over nothing still ends
empty because `RangeSession` replaces rather than adds, so the click with
no drag is the one row that can see the press-time clear.

What it cannot see is a real `mouseDown` delivered by AppKit below the
lanes — #48 lists it for a person at the machine.

## The sharp chrome pass (`sharp_chrome.py`)

`python3 tools/proof/sharp_chrome.py`, no port and no running app,
**29/29**. The sharp handoff (`designs/design_handoff_reelcut_sharp/`,
2026-09-23) squared every chrome radius token, kept a clip bar at 2 pt and
put `Controls.swift`'s `BlockSlider` (a 3 pt track, a 7 × 11 pt block knob)
in for the zoom slider. Two instruments on `e2_chrome.py`'s helpers. A
PROBE compiled from `app/Sources` (a build failure is a scored FAILURE):
the six tokens; `TimelineLayout.clipRadius`; the timeline's slider and cell
classes; a standalone `BlockSlider` in the bar's own configuration
(`.small`, 110 wide, its intrinsic 14 pt height) whose knob is 7 × 11 at 0,
0.5 and 1, centred on the bar and inside the bounds; a `cacheDisplay`
bitmap of it (`recording_probe.py`'s `renderBase64` path) whose four
corner pixels equal the knob's centre, whose track differs at x 10 and x 100
and is background 4 pt above; and an `AccentButton` whose corner pixel is
its fill. The HARNESS, the editor at 1440 × 862, dark and light, two
processes each (byte-identical), with the playhead at 2 s — at 0 s its
coral line covers the clip corner: the Export and S/M/L corner pixels
against their edges; the clip corner `(132, 627)` read along the diagonal,
`D_0 ≠ E` (not square) and `D_(s−1) ≠ L` (not 4 pt); and the zoom slider on
the bar's centreline — a knob run of 7·s px (7·s − 1 allowed at scale 1,
where the half-point ends blend) with the accent on its left and a different
colour on its right, 11·s px tall, its four corners in the knob's ink, and
the pixel over the track 4 pt to its left neither accent nor knob. Every
harness row is in POINTS through `Image.scale`. Made to fail three times:
`DS.clipRadius` 4 (25/29), an oval `drawKnob` (20/29 — the oval's centre
row is 12 px of ink at scale 2, so the run is not found and all four
slider rows go), `DS.buttonRadius` 4 (25/29). The fork it guards is spec
§11 SH-2: Rasterize's `withAlphaComponent` painted the track in the knob's
own solid ink, which the slider row caught. ~3 min with a probe rebuild.
A person still looks at both appearances (#50). One earlier row
moved with the pass, in place and dated: `phase8_chrome.py` section 7 told
the find band's hairlines from the search field by the field's rounded
corners, and now excludes the square field's box by position (150/150).

**The selected action** — `python3 tools/proof/clip_inspector_proof.py` (and `--mutant entry`, exit 0 when only S1 fails): road map 9 phase 1's probe rows S1–S6 and five harness rows over the harness's thirteenth argument, `selectAction`, with the expected inks converted into the PNG's own colour space by the probe's `--convert`; road map 9 §2 is the record.

Road map 9's phase 2 took a FOURTEENTH argument, appended after
`selectAction` in the shape phase 3 set, so every earlier call's argument
positions hold:

```
harness … [mediaFilter] [selectAction] [subTab]
```

`subTab` is the Clip tab's sub-tab — `text`, `shape`, `picture`, `sound` or
`clip` — and `-` or absent is the selection kind's default (its first tab).
It is applied after the tab switch through
`InspectorViewController.selectClipSubTab`, the path the strip's own click
takes, then four runloop turns; an unknown name exits 64. Compiled out of a
`-D HARNESS_REFERENCE_BUILD` harness, like `selectAction`. Since phase 2 a
Clip-tab photograph shows the first sub-tab's sections unless it asks: a
text clip opens on Text, so `phase3_chrome.py` asks for `picture` (where
Obscure lives), `e2_chrome.py`'s four inspector renders ask for `clip`
(where Motion presets lives), and since phase 3b `e1_chrome.py`'s renders
ask for `clip` too (where Transition lives), with its probe calling
`selectClipSubTab(.clip)` and finding the section by its id.

**The sub-tabs and the pinned block** — `python3 tools/proof/clip_inspector2_proof.py` (and `--mutant tabs`, exit 0 when only T2 rows fail in a copy whose `makeSections()` ignores the active tab): road map 9 phase 2's probe rows T1–T7 (the tabs per kind and the default, the section ids per tab, the choice kept on an action and forgotten on a selection change, the two renamed titles, the `◆N` key count, the block pinned outside every `NSScrollView`, and the park clamp on a clip shorter than a frame — which fails on the unfixed clamp, parked at 1 180 000) and harness rows H1–H4 over `subTab` (deterministic twice; the active cell's fill swaps between `picture` and `clip`; ≥ 8 px of converted mint in the Picture cell with the second action selected and none without; the Transform Scale slider's knob a single-colour run of exactly 7·s px on its centreline at scale 2, 11·s tall, its four corners in its ink). ~3 min with a probe rebuild; road map 9 §4 is the record.

**The row marks** — `python3 tools/proof/clip_inspector3_proof.py` (and `--mutant marks`, exit 0 when rows of M1, M2, M3, M4 and M6 fail and nothing else does, in a copy whose `keyedPaths()` answers nothing): road map 9 phase 3a's probe rows M1–M7 (the mark per row — Opacity ◆, Position X ◇ naming action 2, Blend blank, the filter row ◆ at end, Motion presets ⊘, Timing's Duration blank, and on a video with sound Volume ◆, Gain ○, Pan ⊘, Depth blank; the header marks and the ⊘ note; "at end" on a keyed Blend; the auto-open with collapsed keys pinned, over a rebuild, a header click and a reselect; `at(.start / .end / .playhead)`; the header's `◆N` against the sub-tab's; and a Document-tab row whose controls moved by exactly the 14 pt gutter) and harness rows H1–H4 over `selectAction` `0` and `subTab` `picture` at 1.0 s (deterministic twice; Opacity's rail holds converted mint and no converted accent; the coral tick a run of exactly 2·s px, 11·s tall; the gutter's ◆ mint in the Opacity row and absent in Scale's). ~3 min with a probe rebuild; road map 9 §6 is the record.

**Reset, Clear, the row menus and the refusal strip** — `python3 tools/proof/clip_inspector4_proof.py` (and `--mutant reset`, exit 0 when EXACTLY R1's Transform-at-default and Shadow-off rows, R2's faint tier, R5's disabled row and H2 fail, in a copy whose `InspectorRowDefault.derived` answers `differs` true always — R8's explicit rows hold): road map 9 phase 3b's probe rows R1–R8 (Reset hidden at a default and shown at scale 2, Timing with none; the summary's three inks; Clear with action 1, one `set_action_end` null under the undo name "Clear"; the row's × on hover and `removeFromAction()`; the row menus read without a hover — ◆, ◇ with Go performed, ⊘ Motion presets, Duration and Rate with none, and Scale's Reset enabled, performed and then disabled; `at(.defaults)`; the refusal strip in a real editor over a refused Add Action, spanning the inspector's width, kept by a refresh, cleared by an applied edit and not shown by an identity; and the explicit `differs` of Speed, Filters, Shape and Stroke, Stroke's Reset clicked through its own `mouseDown`) and harness rows H1–H3, the harness BUILT by the proof over the tree (or the copy) on `build.sh`'s swiftc line, dark, `subTab` `picture` (deterministic twice at 5 s with no action; the Transform header's trailing 70 pt hold no run of non-fill pixels of 14 pt or more — the summary's glyphs are shorter — and with action 1 selected at 1 s a run of 18 pt or more, the Clear button's edge). ~4 min with a probe and harness rebuild, ~3 min for the mutant; road map 9 §8 is the record.

**Retiming by drag** — `python3 tools/proof/clip_inspector5_proof.py` (and `--mutant walls`, exit 0 when EXACTLY the six rows `MUTANT_EXPECTED` names fail — D1's five wall rows, the floored wall and the action ending at the off-grid clip end among them, and D2's abutting drop — in a copy whose `ActionDragSession.update` ignores `lowerWall` and `upperWall` — the far tick is then refused and the band stays): road map 9 phase 4's probe rows D1–D6 (the session's arithmetic — frame snap, both walls on a move, a start resize keeping the end and flooring at one frame, an end resize capped at the next action, the zero-length wall asked of an IN-MEMORY clip, both keys in every `op`, the two undo names and the three HUD strings exactly; the timeline in a real editor through `beginGesture` / `continueGesture` / `endGesture` — +1 s lands at 1.5–2.5 s, selected with the playhead at its new end, ONE "Move Action" step, one far tick abutting action 4, an end-grip resize under "Resize Action", a still press with no step, and a press inside a multi-selection collapsing it; the Clip tab's lane through synthesized events into its own mouse handlers — the same move, selection on release, one step, a bare click selecting, and the core REFUSING to open the `zero` fixture, which is why no lane can show a zero-length band; the hover and the grip rule; `hit(at:)`'s `.actionEdge` and `.action`; and the lane decor's fade, hatch and wedge geometry) and harness rows H1–H3, dark, `subTab` `picture` (deterministic twice; the `av` lane's bottom-left 10 pt lighter than the well and its bottom-right corner not; with action 1 selected and nothing hovered, the selected band's last 5 pt, lower half, its fill only). ~4 min with a probe and harness rebuild, ~5 min for the mutant; road map 9 §10 is the record.

**The rest of the mode** — `python3 tools/proof/clip_inspector6_proof.py` (and `--mutant target`, exit 0 when EXACTLY K1's four routing rows fail — `op(video:)` per clip, the move session through the live edit, the nudge and the scrub — in a copy whose `CanvasEditTarget.op(video:clip:)` answers `.setVideo` always; the shape row, the text row, which routes through `op(text:)`, the start-state rows and the mouse-down capture row hold; and `--mutant live`, exit 0 when EXACTLY the capture row fails, in a copy whose `PreviewCanvasView.gestureTarget` reads the LIVE `editTarget`; and `--mutant push`, exit 0 when EXACTLY the scrub row and the capture row fail, in a copy whose `canvasPlayheadMoved` never writes `editTarget`): road map 9 phase 5's probe rows K1 (the target — `op(video:)` per clip, `start(of:in:)` at action 4's end against the base, `.base` for two clips; a `CanvasMoveSession`'s `ops(to:)` through `beginLiveEdit` / `updateLiveEdit` / `endLiveEdit` moving action 4's end and not the base, ONE step; the nudge in a real editor driven through the editor's own `selectAction(_:)`, to the end with the action and to the base without; the scrub — the editor's `setPlayhead` into action 4's span selects it and a nudge keys its end, and scrubbed back out keys it again; a move begun with no action selected and held while the playhead scrubs into that span, writing the BASE (the target captured at mouse-down); a text clip's width drag starting from its action's end width 600 and writing `set_action_end` ≈ 612; a shape's box drag staying `[set_shape, set_video]`), K2 (the Drop shadow switch's ops with action 1 selected — one `set_action_end` with `off: ["video.shadow"]`, ◆ at end, reading off, `paths(of:)` naming it — and Clear still a raw null that removes the key), K4 (the `mixed` badge on Shadow ▸ Blur and Compressor ▸ Ratio, not on their siblings), K5 (a header click's `isExpanded` and `content.isHidden` flip synchronously, animated or not) and K6 (Box ▸ Width has no row default; `ActionLaneView.refresh()` twice invalidates its cursor rects once, counted by an `NSWindow` subclass); then the BUILT app, launched by the script on port 4851 and killed by its own pid, rows K3 (`set_action_end {off}` stores the null; the frame at the action's end is BYTE-identical to the base shadow removed and differs from before; `off: ["video.opacity"]` and `["video.motion"]` are errors naming the path; `offf` is refused by the gate; no `Reelcut: ` line). K6's other two rows are dated re-measures in place: the floored wall in `clip_inspector5_probe.swift` (D1, so that proof is now 37 rows and its mutant expects the six rows `MUTANT_EXPECTED` names) and the strip shown, cleared and re-shown at an inspector 40 pt wider in `clip_inspector4_probe.swift` (R7). 25 rows (K1 ×9, K2 ×3, K4 ×2, K5 ×1, K6 ×2 in the probe, beside its build and count rows, and K3 ×6). Needs `make app` first. ~1.5 min with a probe rebuild, ~1.5 min for each mutant; road map 9 §12 is the record.

## The reversed mirror, spelled once (`source_mirror_probe.py`)

`python3 tools/proof/source_mirror_probe.py`, no port and no running app,
**40/40**. Road map 7 §10's phase C (2026-09-20, spec §11's **D4-6**): the
app's reversed mirror — a tick `p` of the played stream reads the forward
file at `pivot − p`, the pivot being the media's MODEL duration — was spelled
TWICE by convention, in `MediaPeaks.window` and in
`ReverseRenderer.walkBackwards`, with nothing shared and nothing asserting
the two agreed, and a THIRD reader, `TimelineView.sourceTime`, applied none
at all, so a reversed clip's filmstrip and waveform drew the forward file's
picture. `app/Sources/ReverseMirror.swift` is now the one home and all three
call it; the same phase made `SpeedSheetController`'s "→ duration" readout
the CORE's answer rather than a Swift quotient.

None of it is reachable over MCP — a drawn waveform is not an op, a
renderer's presentation stamps are not a placement, and a sheet's readout is
not project state — so the instrument is `marquee_probe.py`'s: a probe
compiled out of `app/Sources` over `harness/build.sh`'s own swiftc line,
cached on modification times, a build failure a scored FAILURE. Five
sections:

- **§1 one spelling.** The tick and the window mirrors against numbers
  computed by hand; `MediaPeaks.window` over 1–2 s of a reversed whole-file
  clip answering buckets **400…500**, the range it answered BEFORE the mirror
  moved (100…199 unmirrored, which is the half the mirror exists to avoid
  reading) — the claim `silence2_proof.py`'s claim 9 and `phase5_proof.py`'s
  5c depend on; and the `CMTime` overload agreeing with the tick one under
  `CompositionBuilder.time`.
- **§2 the drawn timeline.** One 6 s AUDIO media — no file needed, the
  descriptor is the media — with a hand-written `cache/peaks/<id>.bin` loud
  over its first half and silent over its second, a forward and a reversed
  whole-file clip on two tracks, a bare `TimelineView` at 1000 × 320 and
  `cacheDisplay` into a bitmap; lit pixels counted per half of each clip's
  waveform region, thresholded on the region's own range so no clip tint has
  to be known. Forward is loud LEFT, reversed loud RIGHT, and the reversed
  clip's loud COLUMNS are the forward clip's mirrored bar the blank one at
  its head. Plus the arithmetic under the picture, at ×1 and ×2.
- **§3 the renderer.** A real `ReverseRenderer(job:).run()` over
  `media/AV.mov`, both files' video stamps read back with `AVAssetReader`
  (DECODED: a compressed read of these two files answers 149 stamps for a
  150-frame source and 152 for its reversal, which is the container's
  business and not the walk's). The output is the walk `[T − following]` from
  the end of the source: same frame count, first stamp exactly 0, strictly
  ascending, and each stamp within ONE unit of the output track's own
  timescale — nothing in `ReverseRenderer` sets `mediaTimeScale`, so the
  writer is free to requantise. A missing `media/AV.mov` is a SKIP printed by
  name; "Making the test media" above has the recipe.
- **§4 the five Swift mirrors of core arithmetic**, each against the PLAN of
  the same project after phase B changed what `set_speed` writes: §10.8's
  vector (a) — a whole-file clip of a 6 233 613-tick media is 6 220 000 and
  ×2 makes it 3 100 000 — with `Transcriber`'s source length and the
  segment's `source_duration` both 6 200 000; a one-frame clip at ×1.00003
  reading 20 001 source ticks, ROUND and not floor; `TimelineView.sourceTime`
  and `MediaPeaks.sourceTick` agreeing at all 155 frame boundaries of the ×2
  clip and still inside the file at its last tick; and `Transcriber.project`,
  the inverse.
- **§5 the readout.** `SpeedSheetController.lengths` against the durations
  read back after really applying its own ops, in all three arms `set_speed`
  answers: HELD TO THE FILE (6 220 000 → 3 100 000 at ×2, where the quotient
  it replaced printed 3 110 000); APPLIED INTO THE NEIGHBOUR (A at ×0.5
  overlaps B by 400 000 against a limit of 1 000 000, so it applies at its
  full 2 000 000 and B gains a minted cross dissolve, which the readout does
  not show); REFUSED (C at ×0.5 overlaps D by 1 000 000 against a limit of
  600 000, so it reads 1 000 000 → 1 000 000 and `applying` answers the
  overlap rule's own sentence verbatim); and MIXED ([A, C] reads
  2 000 000 → 3 000 000, the applied clip's new length beside the refused
  clip's old one, which is what Apply writes).

**Made to fail on purpose**, five ways, each patched into a tree COPY with
the patch asserting its text occurs exactly once:

| Mutant | Score | What it took |
|---|---|---|
| the reversed arm dropped from `TimelineView.sourceTime` | **36/40** | both §2 picture rows and both reversed arithmetic rows, and nothing else in the file |
| `ReverseMirror.mirrored(_ window:)` returns the window unmirrored | **38/40** | §1's window row and its `MediaPeaks.window` row |
| the `CMTime` overload returns `time` | **35/37** | §1's agreement row, and §3 outright — `run()` throws, because a writer input refuses a non-ascending append |
| `lengths` put back to `(duration × speed / rate).rounded()` | **34/40** | §5's held, refused and mixed rows and their read-backs; the APPLIED row survives, 2 000 000 either way, which is why the other three exist |
| `Transcriber.contentLength` rounds DOWN | **39/40** | §4's 20 001 row alone |

**The before-numbers, for the record.** Run against the unchanged tree on
2026-09-20, §2 scored 4/5: the reversed clip's waveform was loud on the LEFT,
18 028 lit pixels against 760 on the right — the forward clip's own split
pixel for pixel — and its `sourceTime` answered the forward clip's ticks
exactly. `archive/reelcut-roadmap-7.md` §10.9 carries the table.

**The one-tick-high mirror is a known limit, not a defect to chase here**: a
reversed tick `p` covers the forward file's tick `T − 1 − p` and the app
answers `T − p`, which is the blank column at the head of the reversed clip
in §2 and one extra bucket at an exactly aligned window end. It is not fixed
because `silence2_proof.py:353` spells the mirror in Python ON PURPOSE — a
reference walk must not import what it checks — and claim 9 walks these
numbers tick-exact.

## Remove Silences by voice (`silence2_proof.py`, `silence2_probe.py`)

Road map 4's S1 — quiet judged by Silero VAD through Core ML — and the two
instruments §4g owes it, landed 2026-09-19 against the unmodified tree and
widened by the READER REVIEW of 2026-09-20 (`archive/reelcut-roadmap-4.md`
§8), whose five new sections are marked below, and again by the SCEPTIC's
pass over that review the same day, which added four rows (one in claim 10,
three at the foot of §8c) for the two defects the review's own fixes left —
and a third time by the residue of that pass's OWN review, closed the same
day, which added four rows to the MCP half (three refusals and a schema row
in claim 10) plus four at the foot of claim 4, and eleven to the probe (a
new `ducked` process and two rows under `afterPeaksGone`).

`python3 tools/proof/silence2_proof.py [port] [--remake]`, port 4823 by
default, **91/91** (61 at the landing, 79 after the reader review, 83 after
the sceptic's pass), against a running instance. It makes
its own fixtures (above), and then measures claims 1–11:

* **1, the clean fixture.** The default voice answer is compared three ways.
  Against a PYTHON REFERENCE WALK of `SilenceDetector.detect` + `refine` over
  `MediaPeaks.window`'s arithmetic at the 32 ms grid, reading the
  probabilities the app itself wrote into `cache/speech/<id>.bin` — TICK FOR
  TICK, not within a bucket, because a bucket of slack hides every mutant the
  max-over-a-step rule has. Against the TRUTH, the −40 dBFS level pass over
  the file's digital silence: the start lands LATE (q6's offset lag) and by
  at most 0.15 s, and the end within `OVERRUN` of it. And again at a
  `set_canvas fps=[100, 1]` canvas, where one frame IS one bucket so the snap
  absorbs nothing — the row the max→mean mutant is scored on. The walk
  carries the segment's own `source_duration` rather than assuming it equals
  the clip's duration; for a whole-file clip at rate 1 the two now AGREE —
  its duration is the media's snapped DOWN (spec §11,
  kpgalligan/reelcut#22) — and one row asserts exactly that, the rate being 1
  the reason claim 11 can compare bytes. Which leaves the scale factor
  `sourceTick` divides by an identity in every row above, so **1(d)** runs
  the clean clip once more at **×2**, the one place in the suite where
  `source_duration` and `duration` differ: the segment is now EXACTLY twice
  the duration (6 200 000 against 3 100 000), because `set_speed` holds the
  duration it snaps to what the file still holds at the new rate (spec §11,
  D4-3) — it used to write 3 120 000 and come back at a ratio of 1.99795 —
  and the answer is still the walk over THAT segment tick for tick. A build
  with the factor dropped from `MediaPeaks.sourceTick` scores **60/61**,
  taking 1(d) and nothing else (measured 2026-09-19); the `× speed` in place
  of the plan's ratio mutant, which that row used to take as well, is
  EQUIVALENT now that the ratio is whole (road map 7 §10.8).
* **1e, the recorder's own rate** (reader review, R4·2). Every other walked
  row is at 30 or 100 fps and 30000/1001 would be no different: all three put
  a frame on a WHOLE number of ticks. `ScreenRecorder` mints 24981/1000, where
  a frame is 24018.25 ticks, `Fps.frameDuration` truncates it to 24018 and the
  two directional snaps compose the nearest snap with that truncated step —
  arithmetic nothing scored. The walk computes the boundary from the RATE
  (`nearest_frame`'s `fps=`), the answer is asserted against it tick for tick,
  and every bound is asserted to be a real boundary of a grid whose frames are
  24018 and 24019 ticks apart by turns. A build whose `refine` snaps to the
  nearest frame rather than directionally scores **74/79**, taking this row,
  claim 1's walk, claim 9 and two of §10b.
* **2, `hum3.wav`** — the headline. A −32 dBFS hum the shipped rule is blind
  to: level at −40 answers NOTHING, voice answers both pauses, within 0.10 s
  of the bounds it found in the clean file.
* **3, `quiet2.wav`.** Level answers more ranges than voice does, and at
  least one of them lies wholly outside both real pauses — a cut into a word.
  Voice answers the two pauses. The COUNT (§4g said six; it was six here) and
  the lead-in span q6 recorded are printed, not scored.
* **4, a tone, and the fallback.** A voice whose source window holds no
  voice is judged by level for its whole span, so on a tone file voice and
  level answer the same ranges and the same total and the media is named in
  `judged_by_level` — which is what makes phase 3's fixtures answer what they
  always did. The two-clip variant (voice for 11 s, then the tone, split at
  11 s) checks that the tone clip answers the tone's TWO gaps and never one
  span across itself, AND that the voice clip is judged by the MODEL: its
  spans tick for tick against the reference walk over clip A's own segment.
  Both sides of that row are filtered to the spans ending strictly before the
  split, because the voice clip ends in a quiet run of its own that a build
  judging the tone clip by voice merges past the split — 11.0 s is exactly
  330 frames at 30 fps, so on a correct tree the run ends ON the bound and
  `<` drops it from both sides. Level mode's own spans before the split are
  printed beside it, which is how the row says it has power on this host.
  **Four rows at its foot are the second sceptic pass's** (road map 4 §8),
  on the tone session rather than a new document: the tone media's WAVEFORM
  withdrawn makes it a waveform waiter judged by level with NOTHING proposed
  inside it, and the tool's clause must say so — the whole sentence, ending
  "and nothing inside them is proposed here" — where it used to claim
  "spans inside them ARE proposed here" whatever the answer held. The clip
  is then ducked to `volume: 0.001` with the same waveform still missing,
  the FLOOR proposes its span, and the clause turns over to the proposed
  wording with a sentence naming the mix as what made it quiet. Both note
  rows fail against the pre-fix binary.
* **6 and 7, the scope rule and the nest wall**, both in voice mode: a muted
  clip and a solo-silenced one propose nothing (the gain FLOOR runs before
  the model), and no proposed span reaches into a nest while the identical
  dead air in front of it still is.
* **8, a cache withheld.** The `.bin` deleted with its marker left behind:
  the media is named in `voice_pending`, folded into `pending_peaks`, and
  NOTHING inside it is proposed, while level mode still answers the truth. A
  `relink_media` to a fresh copy rebuilds it and the answer comes back.
* **8b, a decode that stops part way** (reader review, R2·1). `corrupt.m4a`
  — the clean fixture as AAC with bytes 45 %–70 % of the container zeroed and
  the `moov` intact, so AVFoundation reports the full 10.389 s and the reader
  gives up at about 2.05 s. `writeSpeech` reads `reader.status` BEFORE the
  cancel now and anything but `.completed` writes no `.bin`, no marker and no
  post, so the media stays `voice_pending` and NOTHING inside it is proposed;
  the zero-filled tail used to be certified by a marker and voice mode
  proposed cutting 8.1 s of the 10.4 s file. Level now reports that media
  as `pending_peaks` and proposes no undecodable tail (#23). The source
  probe below awaits the actual peaks pass before checking that no waveform
  was published. The historical speech-status mutant scored **76/79**.
* **8c, the waveform withheld with the voice cache in place** (reader review,
  R3·1). Claim 8 withholds the SPEECH cache; this withholds the WAVEFORM. In
  voice mode the answer is unchanged — the model decides — yet
  `pending_peaks` names the media, because it folds both waiters, and the note
  beside it used to read "Nothing inside them is proposed for removal" about
  ranges printed in the same reply. The promise is now made about what the
  ANSWER shows — a waiter the reply already proposes a span inside is dropped
  from it and counted in its own clause — and the seven rows are: the answer
  unchanged, the media a waveform waiter and not a voice one, the note saying
  those spans ARE proposed, level mode proposing nothing inside it while
  keeping the promise, and then the DUCKED case the sceptic's pass found
  (finding 2): a clip set to `volume: 0.001` with its SPEECH cache withheld
  is a voice waiter whose span the gain FLOOR proposes anyway, before either
  cache is asked, and the note counts it rather than denying it. The two note
  rows assert the WHOLE sentence, not a substring, so a clause about "the
  rest" of a sentence that was not printed fails them. A build with the old
  sentence scores **78/79**; the pre-fix binary answered the ducked rows
  `[[60000, 6160000]]`, `voice_pending: [2]` and "… Nothing inside them is
  proposed for removal." (measured 2026-09-20 before the fix went in).
* **9, reversed.** The mirrored walk about the MEDIA's duration, tick for
  tick, and not equal to the forward answer.
* **10, the refusals**, word for word — the two `voice_confidence` rules, the
  misspelt `mode`, a `padding` at `Int64.max`, `min_length` at the ceiling
  PLUS ONE, a NEGATIVE value of each duration, a misspelt ARGUMENT, which
  the gate refuses by name before the handler runs, and what `tools/list`
  PUBLISHES for the two durations. The four rows after `padding`'s are the
  second sceptic pass's (road map 4 §8): the ceiling was scored for `padding`
  alone, so a build that kept the guard on one duration and dropped it on the
  other still scored full — measured, mutant (a) with `min_length`'s guard
  deleted now scores 89/91 and mutant (b) with `padding`'s `>= 0` deleted
  90/91 — and the bound was enforced but not DECLARED, the argument gate
  reading names and never values. The schema row is the one of the four that
  fails pre-fix; the three refusals pass pre-fix and are guards. The
  `padding` row is the sceptic's pass (finding 1): the durations stopped
  going through
  `optionalTimeArg`, which had CAPPED them at ±9.0e15 as well as snapping
  them, so the ceiling is now the tool's own, refused in a sentence naming the
  argument. Against the pre-fix binary the row does not fail with a wrong
  sentence — the call KILLS the app (`EXC_BREAKPOINT`, "Swift runtime failure:
  arithmetic overflow" inside `SilenceDetector.refine`, crash report
  `Reelcut-2026-09-20-051240.ips`), which is how it was made to fail on
  purpose.
* **10b, `min_length` and `padding` as given** (reader review, R1·1). Both
  are DURATIONS and the sheet puts neither on the frame grid; the tool read
  them through `optionalTimeArg`, which snaps, so at the DEFAULT 30 fps it ran
  the sheet's own 0.05 s (30000) as 40000, ran `min_length: 45000` as 40000
  and dropped `padding: 9999` to ZERO. Three values are asked for, each echoed
  back unchanged and each walked — and the walk is given what the CALLER
  asked for, never what the answer echoed, or a build that rounds and then
  reports the rounded value would agree with itself. A build reading them
  through `optionalTimeArg` again scores **75/79**.
* **11, the cut.** `ripple_delete_ranges` of the voice answer, exported as
  `audio_wav`: the spans about to be cut are WALKED first (reader review,
  R4·1 — without that row the section passed against both of the review's
  "no feature" builds, because it proved only that the cut matched whatever
  was answered), and then the decoded PCM is the uncut export with each span
  excised,
  to the SAMPLE and then BYTE for byte. The clip needs no trim now — the core
  snaps a media clip's length DOWN, so a whole-file clip lands on the last
  whole frame inside the file and the plan plays it at rate 1 (spec §11,
  kpgalligan/reelcut#22); the section's first row asserts that length, which
  is what the trim used to buy. Against a build that kept the nearest snap
  the clip outruns the source, the plan plays it at 0.9990 and AVFoundation's
  resampler is what gets measured — that build scores **57/61**, taking this
  row, the two beside it and claim 1's rate row (two exports of the same
  material came out eight sample frames apart there on 2026-09-19).
* **5, LAST**, because it opens eighteen more documents: `phase3_proof.py`
  and `phase3_silence_scope.py` run as subprocesses against the same binary
  and must score FULL. Their counts are printed rather than asserted.

`python3 tools/proof/silence2_probe.py [--pin]`, no port and no running app,
**76/76** (61 at the landing, 65 through the sceptic's pass). `phase9_probe.py`'s instrument — `app/Sources` whole, `build.sh`'s
own swiftc line, mtime staleness, a build failure a scored FAILURE — with
`app/Resources/Models` copied beside the binary as `build.sh` does it, and a
SECOND copy of the binary in `nomodel/` with none beside it. It runs four
modes and five processes:

* **12, the wrapper.** `writeSpeech`'s `.bin`, `probabilities(of:)`, the same
  samples fed in 1000-sample buffers with a `flush`, the SPIKE's own loop at
  `.cpuOnly` over its own `MLModel`, and a pinned trace. The streaming row is
  the EXACT one (float for float, which is what proves the remainder is
  carried across `feed` calls); the pass's `.bin` is within the 0.01 the row
  enforces with identical decisions, because the pass reads with
  `alwaysCopiesSampleData = false` and this runner's reader does not, so the
  48 kHz → 16 kHz converter hands the two paths different block sizes. The
  spike's loop stops at the last COMPLETE chunk, so it is compared over the
  common prefix.
* **`silence2_trace.json`** is the pin: 325 chunks at three decimal places,
  keyed on `sha256` of the DECODED samples of `clean.wav` rather than the
  file's bytes, since ffmpeg's WAV muxer writes an `ISFT Lavf<version>` tag
  and the bytes move with a brew upgrade while the samples do not. A
  different `say` is a SKIP printed by name with both hashes, never a
  failure; `--pin` rewrites it from this host's run.
* **13, 14, 15, the pass.** The marker's two new fields (`speechModel`,
  `speechChunkSamples`) and that it WRAPS the ordinary `CacheStamp` byte for
  byte; a second call that does nothing and posts nothing; a marker naming
  another model that rebuilds. Then the ORDER, with the notification observed
  as it arrives and the disk read at that instant: a stale `.bin` under a
  foreign marker produces exactly two posts, the old file is already GONE at
  the first and the new bytes are there at the second, and the FIRST carries
  `replaced` while the second does not — the withdrawal opens a pass that
  replaces a file on disk, which is what the flag means; `peaks` posts
  without it.
  And a movie with no audio writes nothing, whether its record claims audio
  (the relink shape) or admits it has none.
* **17, the sheet**, driven through a real `ProjectDocument` and a real
  window: the Judge by popup's rows and its Voice default, "2 cuts", two
  candidate spans washed on the timeline, Remove enabled. Then the speech
  cache cleared: "No cuts", the pending note, Remove disabled — and with the
  bytes put back WITHOUT a post, a `thumbs` notification changes nothing
  while a `peaks` or a `speech` one brings the cuts back.
  Four rows are the reader review's. Two (R2·2) are the case the sheet used
  to ignore: with BOTH caches landed and nothing pending, the `.bin` under the
  open sheet is replaced by one that says "talking" at every chunk and a
  `speech` post is made — the readout drops to No cuts and the wash to 0 —
  then the original bytes are posted back and the two cuts return. That is the
  limit `archive/reelcut-remaining.md` §5 recorded as unprovable because "no
  proof can drive the sheet"; this one does, the guard is gone, and a copy
  with it restored scores **64/65**. Two more (R3·1) withdraw the WAVEFORM
  with the voice cache in place: the sheet still says 2 cuts, and it no longer
  promises that nothing inside that file is proposed — a copy with the old
  sentence scores **64/65**. Two more again are the SECOND sceptic pass's,
  in the same state: the waveform line must stay PLAIN there (this clip is
  not ducked and holds a voice), and it must not say "quiet in the MIX"
  either — the suggested fix, routing that branch through `promise(about:)`,
  answers exactly that, falsely, because the media IS in `proposedMedia` by
  the MODEL. Both pass pre-fix; mutant (c), hedging always, fails the first
  and mutant (e), the rejected route itself, fails the second.
* **17 again, a FOURTH process, `ducked`.** `tone.wav` — no voice anywhere,
  so every clip of it is judged by level — opened as a document, its clip
  ducked to `volume: 0.001`, read in two states with one sheet up. With the
  WAVEFORM withdrawn the gain floor still proposes its span and Remove is
  enabled, and the waveform line must HEDGE ("…, unless the mix already
  turns it down far enough to be quiet") instead of promising that anything
  holding no voice is left alone. Then the SPEECH cache is withdrawn under
  it too: the media is in `voicePending` and NEVER in `judgedByLevel`
  (`SilenceDetector.detect` returns on a missing speech cache before the
  by-level test), the speech line's own promise says the mix is what made it
  quiet, and the waveform line must hedge there as well — mutant (d), the
  gate's `voicePending` arm dropped, fails that row alone and passes the
  first. The two hedge rows fail pre-fix (**74/76**).
* **16, no model at all**, in its OWN process because unavailability is
  process-wide and never retried: `isAvailable` false, the input's
  `voiceAvailable` false, the sheet on Level with the Voice row disabled and
  the reason written under it, the tool's refusal sentence, and a call with
  no `mode` falling back to level and SAYING so.

**Made to fail on purpose**, ten times, each mutant a copy of the tree with
the app rebuilt in the copy on its own port and the probe compiled from the
copy (the staticlib is copied in unchanged — every mutation is in
`app/Sources`). Against the MCP half's N at the time, 60 — claim 1(d) took
it to 61 later on 2026-09-19 and none of these three were re-run: the level
fallback removed
**52/60** (claim 4's tone rows and phase 3's re-run), the window test made
whole-file **57/60** (claim 4's two-clip tone rows alone), and the fallback
keyed per MEDIA — the pre-fix read — **59/60** (the two-clip variant's VOICE
row alone). Against the probe's 61: `speechModel` dropped from `SpeechStamp`
**53/61** (claim 13's marker rows and the whole of claim 14), and `replaced`
dropped from the withdrawal post **60/61** (that row alone). Five more are
quoted with the N they had at the time and were not re-run: the probability
forced to 1 **33/59**, max→mean over a step **54/59** (claims 1a, 1c and 9),
`voice_confidence` accepted with `mode: "level"` **58/59** (one row), the
LSTM state not fed back **57/61** (claim 12's amplitude and its decisions)
and the 64-sample context not carried **59/61** (the amplitude only — the
decisions survive it). The max→mean mutant needed no exemption: the
sensitivity line claim 1(c) prints says the mean rule moves two edges at 100
fps on this host's fixture.

Phases 2, 3, 3-silence and 5 and the remaining-work proof were re-run against
the same binary and score **86, 123, 8, 88 and 79**.

**The 2026-09-20 reader review** (`archive/reelcut-roadmap-4.md` §8) added
eight more mutants, each a tree copy on port 4872 with the app rebuilt in it
and the patch asserting its replaced text occurs exactly once. Six are named
beside the rows they take, above. The other two are the review's two "without
the feature" builds, which exist to say which claims a build with NO voice
rule would still pass: **W1**, the model's answer never reaching the cache
(`MediaImporter+Speech.swift`, `probabilities[index] = 0`), scores **58/79**
and **61/65**; **W2**, the level rule standing in for the voice rule
(`SilenceDetector.isQuiet`'s voice arm replaced by the level test), scores
**56/79** and **57/65**. Neither instrument ABORTED under either, so no claim
was left unmeasured — which is why the review could say that nine claims
pass under both and why each of those is about something other than the voice
rule (the fallback, the scope rule, the nest wall, the arguments, the cache
pass's files, a process with no model). §8's table has a cell per claim. The
binary at `1c3e92e^` was deliberately NOT built for this: it has 75 tools and
writes no `cache/speech/<id>.bin`, so the MCP half aborts in its first part
and the probe cannot compile against that `app/Sources` — every claim would
have read as "caught" while measuring nothing.

What neither can see is a narrated screencast marked by ear, a cut LISTENED
to across a voice-mode boundary, and the sheet's note when one file is
pending while another is judged by level — #54 lists all three for a
person at the machine.

## Transitions and motion (`e1_proof.py`, `e1_chrome.py`, `e2_proof.py`, `e2_chrome.py`)

Road map 5's E1 and E2 — transitions learning direction, easing and an audio
crossfade, and clips learning In / Out / During motion presets — and the four
instruments §4e and §6e owe them, landed 2026-09-19 against the tree as it
stood.

`python3 tools/proof/e1_proof.py [port] [reference_port]`, 4825 and 4826 by
default, **95/95** at the landing and **99/99** since the E1 reader review
(road map 5 §12, R4·1) added §6(c), against TWO running instances: this build and the build
at `1c3e92e` (the reference paragraph in "Running one" says how to make it).
Fixtures are `media/`'s two tones, `AV.mov` and `silence.mov`, plus shape
cards the app draws; **the tones are TRIMMED first**, because a file placed
whole has no handle and `add_transition` is built from handles. The handles
are MEASURED and not assumed: `toneA.m4a` is written as five seconds and
decodes to 2 986 400 ticks, which snaps to 149 frames, so "a two-second
handle" is really 59 — a fixture that assumed 60 would be measuring ffmpeg's
padding rather than the op.

* **0, the two instances.** 77 tools and 57 ops as FLOORS here, `== 75` and
  `== 55` on the reference, and both parity logs grepped empty. The two
  counts are what tells the instances apart.
* **1, the schema.** A hand-written version-6 file opens with `curve:
  linear, audio: false`; a copy of it saves as the header's `RC_FORMAT_VERSION` with `audio` the
  LAST key of `transition_in`, read off the text; `set_transition` over a
  stored style keeps the curve and the flag; and `set_transition_style` at a
  hard cut stores a MINTED transition that nothing draws (the frame at the
  cut is byte-identical before and after).
* **2, the three wipes.** At p = 0.25 on a two-second overlap: which SIDE
  the incoming colour is on and where the boundary sits, to a pixel —
  `wipe_left` at column 480, `wipe_up` at row 270, `wipe_down` at row 90 —
  then `ease_in_out` moving the first to 640·(1 − smoothstep(0.25)) = 540.
  The overlap is two seconds because a one-second one puts p = 0.25 off the
  30 fps grid. And the old `wipe` renders BYTE-IDENTICAL to the reference
  build on the version-6 fixture.
* **3, the push and the dissolve.** A minted `push_left`'s seam at
  smoothstep(0.25) and at 0.25 under `linear`; five ticks of a version-6
  cross dissolve byte-identical to the reference build.
* **4, `add_transition`.** Centre, `before`, `after`, the step-down against
  the overlap rule, the odd frame landing on B, a 2× clip whose head is
  converted ONCE, a nest (which answers a zero head, so `center` takes the
  whole overlap from A's tail and `before` has nowhere to take it from), an
  action rebased so it still renders the same SOURCE frame at its end, the
  five refusals by their own words, and one `undo` restoring `get_project`
  byte for byte. **Every bullet starts from P0** — `undo` until the dump
  matches, asserted — or from its own named session, because the step-down
  reads both clips' durations and a bullet built on the last one's leftovers
  would be measuring a different rule.
* **5, the crossfade**, exported as `audio_wav` and decoded to PCM: each
  tone's level by projection onto its OWN frequency (a Goertzel filter) in
  25 ms windows — 11 cycles of 440 Hz and 22 of 880 Hz at 48 kHz, so neither
  leaks into the other's bin — tracking `cos` and `sin` of the eased
  progress within 0.3 dB and summing flat within 0.5 dB; a muted incoming
  clip; a version-6 export sample-identical to the reference build's within
  this build's own measured wobble (0); a nested pair, where the inner
  overlap still obeys the law and the outer one fades the nest out; and a
  HARD CUT with the incoming clip muted, which is what says the first 25 ms
  the other rows skip belong to the host's mix — no transition and no ramp
  there, and the same half-scale burst (0.496 of the tone, then −140 dBFS
  from 25 ms on).
* **6, Remove Silences.** A quiet run that crosses a cut is proposed with no
  transition there and wholly suppressed with one, the wall being the
  overlap widened by its own length; the answer's KEY SET is the same either
  way, so a wall is never reported; and the crossfade's own dip is inside
  the wall, with a faded tail on its own as the control that says the
  detector can see a dip at all. **(c) the WIDENING itself**, which the
  first three rows cannot see — the run they use is short enough that what
  an exact wall leaves of it is dropped by the length filter. Here the quiet
  ends AT the cut and is long enough to survive: the proposal is applied
  with `ripple_delete_ranges`, the pair is found again by GEOMETRY (a split
  does not keep the ids) and the overlap it leaves is measured against half
  of the shorter clip. An exact wall leaves 1 660 000 ticks against a limit
  of 150 000 — a project outside the rule that neither
  `ripple_delete_ranges` nor `validate` checks, which is §3f's own
  argument.

**Mutants, from the E1 reader review** (named patches of the tree in a copy,
each asserted to replace its text exactly once). **X1, handles never clamp**
(`|h| want.min(h)` → `|_| want`): **92/99**, all seven in §4. **X2, no
crossfade** (the constant-power angle replaced by full gain both ways):
**92/99**, all seven in §5. **X3, no easing in picture or sound**
(`transition_of_later` forcing the default curve, so `get_project` still
SAYS `ease_in_out`): **92/99** — two in §2 and §3, five in §5. **X4, walls
exact rather than widened**: **97/99**, both in §6(c) — it scored 95/95, a
clean pass, against the script as it stood, which is why §6(c) exists. **X5,
the section's both-keys rule deleted**: **99/99** — this script reaches none
of the section's writes, which is `e1_chrome.py`'s §3.

`python3 tools/proof/e1_chrome.py [--reference DIR]`, no port, **14/14** at
the landing and **21/21** since the E1 reader review (road map 5 §12, R4·2)
added §3, the section's WRITES. The harness on BOTH trees over one
hand-written version-6 package, and a probe built from `app/Sources`.

* **§3, the Curve popup and the Crossfade Audio checkbox, DRIVEN.** The
  popup is sent `itemPicked:` (what its own popped-up menu sends) and the
  checkbox a synthesized `mouseDown`, on the same clip with its transition
  stored and with it cleared. With one stored each row writes its ONE key
  and the other is kept, under the undo names "Transition Curve" and
  "Transition Audio"; with NOTHING stored each sends BOTH keys, so the
  minted transition is what the section was showing and the untouched row
  does not silently become `ease_in_out` / on. Mutant **X5**, the both-keys
  rule deleted (`if stored() == nil` → `if false`): **19/21**, exactly those
  last two rows — it had scored 14/14, 95/95 and 32/32 against all three
  instruments before §3 existed. **X1**, **X2**, **X3** and **X4** all score
  **21/21**: none of them touches what the section stores.

* **The section's body is two rows taller than it was**: the vertical EXTENT
  of the pixels that opening `video.transition` changes, measured on each
  tree, and the claim is the DIFFERENCE — 129 − 71 = 58 pt = 2 × 29
  (`DS.controlHeight` + `InspectorMetrics.rowSpacing`). The difference is
  what makes it a measurement: the extent includes the header's disclosure
  triangle and the body's insets, and those are the same on both trees, so
  they cancel. A `shift_match` measurement does NOT apply here — Transition
  is the LAST section in a shape clip's stack (the audio group below it is
  empty), so opening it moves nothing and there is no shift to find.
* **The menu**: `TransitionKind.allCases` with the case index as the tag,
  the three wipes at 10–12, None alone under a separator at −1.
* **The validator**: a KIND enabled at a hard cut and at an overlap and dead
  at a gap and on a first clip; None enabled for every selection, because a
  clip can carry a stored transition the timeline does not draw; and the
  checkmark on the kind the clip stores and on nothing else.
* **The rows**: Kind, Curve and Duration as labels, plus one checkbox.
  Crossfade Audio carries NO row label — `inspectorCheckRow` passes nil and
  the title lives inside `OptionCheckboxControl`, which is private — so it is
  counted rather than read by name, and nothing private is widened.
* **The batch**: Clip ▸ Transition ▸ Cross Dissolve over a selection of two,
  one at a hard cut and one at a gap, makes the overlap at the cut, leaves
  the other clip exactly where it was rather than aborting the selection, and
  puts up no sheet.

`python3 tools/proof/e2_proof.py [port]`, 4825 by default, **69/69** after
E2-27 (61/61 before it), one
instance. Cards on a black backdrop; `NONE` is the same session with the
motion cleared, re-rendered and put back, which is the control half the rows
here are measured against.

* **1, the schema**: a version-7 file opens with `motion: null`; a save
  writes version 8 with `motion` the LAST key of the video object; three
  nulls normalise back to null; a misspelt key, an unknown kind, a negative
  duration and a zero period are each refused BY NAME; `set_action_end`
  refuses a motion; and two files nothing in the app can write — an action
  whose `end` carries a motion, which draws the BASE motion, and a
  hand-written `period: 0`, which is inactive and draws no NaN. Both of
  those fixtures are placed and sized so the wrong answer is a DIFFERENT
  picture: a NaN reaches the recipe as JSON null and Swift reads a field's
  default, which on a card already at the origin is the same frame.
* **2, the slides**: off the canvas at the first frame, byte-identical to no
  motion at `in`, and the leading edge at `ease_out(0.5)` — on a plain card,
  on a 30°-ROTATED one (its bounding box) and on a CROPPED one, where the
  pivot is the VISIBLE centre.
* **3, `fade`, `zoom_in`, `pop`**: the eased opacity, the box and the
  opacity at `u` = 0.5, the same for a cropped card about its visible centre,
  and `pop` passing 1.0 at u = 0.6 and 0.8 and landing on exactly 1 at u = 1.
* **4, the four continuous presets**: one whole period of a `spin` is
  byte-identical to no motion — measured twice, once plainly and once on the
  INCOMING half of a cross dissolve, which is the only place a rotation of
  360 that is not exactly 0 SHOWS (`partnerBox` answers nil for a rotated
  partner and the outgoing layer loses its coverage correction); an eighth
  of a turn as a 45° bounding box; a `shake` identical on a 60 s clip and a
  5 s one at the same clip time; a `drift` read against the CLIP; a `bounce`
  lifted by exactly 0.08·A·H.
* **5, composition**: the tent (a 4 s card with 3 s edges, so both halves
  land on the grid), an action moving `x` under an arrival, two slots
  MULTIPLYING, and a nest scaling every inner layer about the nest clip's
  placed centre.
* **6, the model rules**: `get_project` un-moved while the frame moves, and
  a split taken MID-ARRIVAL writing two pieces that are still at the origin
  — which is the half a render check cannot see, since `split_clip` writes
  the second piece's props straight out of `evaluate_clip`; then the split
  and ripple-delete rules for the two edge slots, and a split text clip's
  first half still ending fully revealed.
* **7, the export path**: an `apng` of a one-second in/out range taken apart
  with ffmpeg, frame 13 at t = 12/25 s having the card's leading column where
  `ease_out` puts it. The APNG comes out at the CANVAS's size and not the
  preset's 960 × 540: an image format is written with the picture fitted
  inside the size, aspect kept and never upscaled (`core/src/export_size.rs`).
* **8, zero-duration edges (E2-27)**: explicit zero In and Out retain their
  kind through `get_project`, save and reopen, with first/last PNG bytes equal
  to the no-motion card. A one-frame Fade In changes the first frame; a
  two-frame Fade Out changes the last drawn frame; undo restores the stored
  zeros and the matching PNGs. Run against an owned Release app on its bound
  port, with an empty `rg 'Reelcut: ' /tmp/reelcut-<port>.log` parity scan.

`env RC_ASSEMBLYAI_KEY=proof-key python3 tools/proof/e2_chrome.py`, no port,
**52/52** after E2-27 (35/35 before it; 24/24 until the E2
  reader review of 2026-09-20 added nine rows, and its residue run two,
  `archive/reelcut-roadmap-5.md` §12).

E2-27 extends that same script with no-motion versus zero In, zero Out and
both-zero name-strip pixel equality; a one-frame positive wedge on each
side; the expanded and collapsed zero Motion inspector; and an actual-source
probe of the selection-aware wrapping note, editable zero Duration, quick
pick, popup/menu None, Reset, one-step undo, and menu title refresh through
same-kind mixed activity, different kinds and no selection. The note probe
measures its intrinsic height, actual height and clearance to the In row;
the opened PNG is `tools/proof/work/chrome-e2/zero-open.png` for visual
inspection. A focused FFI regression is
`cd core && cargo test --release --test motion_zero`.

* **The wedges**, measured as the pixels that differ from the same card with
  no motion: an arrival's triangle over x 132–174 and a departure's over
  279–300 on a four-second card at the default 42 pt/s zoom, both inside the
  16 pt name strip. A `during` draws no wedge at all — it is continuous and
  has no length to show — and one 11 pt glyph at the strip's right end.
  Beside them, from the E2 reader review: the glyph GIVES WAY to a label dot,
  measured as the same LABELLED card with and without a `during`, so the dot
  is in both renders and the only pixels that differ are the glyph's — its
  right edge lands at x 285.0 against the dot's left edge at x 288, and 10.0
  pt left of where it sits unlabelled (N·2); and the strip's GATE, a clip
  whose media declares `has_video: false` carrying a full motion in its props
  and rendering BYTE-IDENTICAL to the same clip with none, which is the only
  fixture shape that exercises `InspectorTab.hasPixels` — every other clip
  here is a shape clip, and shape clips always have pixels (R4·4).
* **The section**, opened with `expandSections=video.motion`: the changed
  pixels are inside the inspector column and span a body at least seven rows
  deep. It is rendered at 1600 pt rather than 862: Motion is the tenth
  section in a shape clip's stack and its header is below the fold at the
  window every other chrome script photographs.
* **The menu**: three slots and a Preview, `EdgeMotion.allCases` in In and
  Out and `DuringMotion.allCases` in During with None at −1, every one dead
  with nothing selected, the stored kind checked and the empty slots
  checking None — and two clips that DISAGREE checking nothing at all in
  that slot while still checking None in the slots they agree on. And, from
  the E2 reader review, a tag NO builder writes: −7 checks nothing on a card
  whose In slot is empty, which is the one fixture where that differs from
  None (None checks `on` there); anywhere else the two readings look alike,
  and the EXTREMES of the same rule — `Int.min`, `Int.max`, `count`, `count
  + 1` and `0` — all check `.off` on that card with None beside them as the
  control, added by the review's residue run (N·1).
* **The rows and their liveness**: the seven labels in order, and Period,
  In Duration and Amount live or dead according to what the clip carries —
  each read on a fixture that HAS the thing and on one that does not, so
  three fixtures: a `pulse` with an arrival, a `drift`, and a clip with an
  arrival and no `during` at all.
  Liveness is read off `alphaValue` (1, or 0.42 when the row is off), since
  a control's own `isActive` is private.
* **Commands in a real window**: During ▸ None clearing the during and
  KEEPING the arrival (a `motion` patch replaces the whole object, so the
  command has to carry the other two slots), and the section's In popup —
  driven by ObjC dispatch on `itemPicked:`, the message the menu itself
  sends — writing the clip's BASE motion with the playhead inside an action
  and leaving that action's `end` with no `motion` in it. The E2 reader
  review added three more, and its residue run a fourth. A tag no builder
  writes (−7) sent to `setMotionIn:` on a card whose In IS set leaves
  `project.json` byte-identical, where reading every negative tag as None
  cleared it — the fixture matters, because on a card with no In the same
  call is nil over nil and the bytes match either way (N·1). The residue run
  put the four EXTREME tags through the same door on the same card —
  `Int.min`, `Int.max`, `count` and `count + 1`, none of which writes a byte
  — with tag `0` last as the positive control, since a gate that refused
  everything would pass the other four (N·1). During ▸ * over TWO clips that
  disagree about their arrival writes one op PER CLIP: each keeps its own
  arrival while both gain the during (R4·3) — and beside it, as a CONTROL
  rather than a made-to-fail row, one undo puts `project.json` back byte for
  byte, which no mutant of the app's own code can falsify, because
  `NSUndoManager` groups by run-loop turn (measured: a batch split into one
  `applyEdit` per op is still one undo step). And the zoom band's second
  pill FOLLOWS the clip: armed over a clip with no `during`, the trail
  across a During ▸ Pulse and a During ▸ None is `['', '<the note>', '']`,
  the band never re-armed (N·3).

**Twenty-five mutants**, each in a copy of the tree under a scratch
directory with the app rebuilt in the copy on its own port, every patch
asserting its replaced text occurs exactly once, and the original tree never
touched. E1: `cos`/`sin` swapped, the `Side` close removed, `minted` writing
linear, `set_transition` minting over a stored style, `align` ignored, the
speed applied twice in `extended`, the action rebase removed, the step-down
removed, the overlap walls removed, the menu batch unfiltered, `wipe_up`
given `(0, 1)`. E2: the `NSNull` rule removed from `MotionProps`, the
`rem_euclid` removed, the guards removed, `motion::apply` added to
`evaluate_clip`, the totals replaced instead of multiplied, the text
fallback used for a shape, the period read as a fraction of the clip, the
tent removed, the pivot compensation removed, the split rule removed, the
`evaluate_clip` restore removed, the `set_action_end` refusal removed,
`structural` not widened, `drift` using the period. Every score is in
`archive/reelcut-roadmap-5.md` §12, with the rows each one took.

**The E2 reader review added nineteen more** (2026-09-20, same shape, same
scratch copy, every patch asserting one occurrence): eight NAMED mutants of
today's tree for reader 4's table — no motion at all, the spins reversed, y
up, departures never running, a nest clip's own motion dropped, every
container the project canvas, the menu writing one op over every id, and the
strip's gate and its measure gone — and eleven more that are this review's
own fixes REVERTED or bounded: the reduction's 360 not mapped back, that
same reduction narrowed back to its FIRST attempt (an exact `== 360.0`,
which the fix pass replaced with a band, tested as an f32 of degrees, and
which fails `motion_edges` 2 of 7), the paste normalisation removed, the
same normalisation made too wide, the patch path's range check removed, both
halves of the negative-tag fix, the pinned `let right = strip.maxX -
padding`, that glyph fix simply REVERTED, the zoom note not re-read, a batch
split into one `applyEdit` per op, and — from the residue run — `N1ext`, the
negative-tag gate widened back to N·1's own defect, which kills the two
extremes rows and the two −7 rows with them (31/35). Two of those eleven
kill nothing and say so: the batch split (its row is a control) and the
plain glyph revert, which is pixel-identical BY CONSTRUCTION and is the
reason that fix is recorded as a fragility rather than a defect. Two of the
eight named mutants pass `e2_proof.py` entirely, and that is what the two
limits below say.

Three of those mutants SURVIVED their first fixture and the fixture was
strengthened rather than the mutant excused, which is worth knowing before
writing another row here: a whole `spin` reduces to a rotation the
compositor cannot see, so it had to be measured on a dissolve's incoming
half; a degenerate `period` makes every field NaN and a NaN reaches Swift as
a field DEFAULT, so the card had to be moved off the origin; and an action's
end patch that differs only by a KIND leaves the same picture at every tick,
because the action loop interpolates and a string it can only take whole, so
the patch had to differ by a number.

**Two things `e2_proof.py` cannot see, measured rather than guessed** (road
map 5 §12, R4·1 and R4·2). A mutant that turns every spin the OTHER way
scores **61/61**: §4's rows are an eighth-turn bounding box and a whole
period byte-identical to no motion, and neither can see a DIRECTION — a
card's bounding box at +45° and −45° is the same rectangle, a whole turn
reduces to 0 either way, and the fixtures are rectangles symmetric about
their own centre. A mutant that measures every container against the PROJECT
canvas scores **61/61** too: §5's nest rows are about a nest CLIP's own
arrival, and none is about a clip INSIDE a nest sliding against the nest's
frozen canvas. Both properties are pinned through the FFI in
`core/tests/motion.rs` and `core/tests/motion_edges.rs`, so they are proved
— just not over MCP. Closing the first needs a CROPPED fixture, where the
pivot compensation makes the drawn position depend on the sign of φ; closing
the second needs a nest whose canvas differs from the project's and a render
part-way through the slide. Neither row was written.

What neither pair can see is in #54: a
crossfade across a Remove Silences cut HEARD, an eased push FELT, the three
wipes read as directions, and whether each preset's numbers look right at an
ordinary clip length.

## Road map 6 — the cloud spike (`cloud_spike/`)

C0, run 2026-09-20: eight questions about AssemblyAI that
`archive/reelcut-roadmap-6.md` §3 leaned on, MEASURED. Its own README
(`tools/proof/cloud_spike/README.md`) is the full one — the instrument table,
the fixtures, the key and spend rules, the ledger's outcomes — and the
ANSWERS are in road map 6 §3, not here.

```sh
python3 tools/proof/cloud_spike/cloud_spike.py --selftest    # free, no key, loopback only
python3 tools/proof/cloud_spike/cloud_spike.py               # all eight rows
python3 tools/proof/cloud_spike/cloud_spike.py --only q3,q4  # a subset; the rest carry forward with their dates
python3 tools/proof/cloud_spike/cloud_spike.py --leakcheck tools/proof/cloud_spike tools/proof/work/cloud_spike archive/reelcut-roadmap-6.md
```

**Nothing here is a pass.** Every row is a MEASUREMENT, and the two ways a
run is wrong are a row that did not run and a reservation left open — the
runner prints `SPIKE INCOMPLETE`, names each with its reason, and exits **2**.
Exit **0** means every requested row ran and every reservation is closed; exit
**1** is an instrument failure, and a probe that will not build is the ROW's
recorded failure, never an exit.

The instruments are `cloud_spike.py` (the runner), `aai.py` (a stdlib
`urllib` client, the `Scrubber`, the `Ledger`), `fake.py` (the in-process
stand-in), `selftest.py`, `fixtures.py`, `cloud_rows.py` (q1, q2, q5, q6, q8 —
the paid ones), `local_rows.py` (q3, q4, q7, probe and bundle building,
`run_bounded`) and three standalone Swift probes — `extract.swift` (the
AVFoundation one, at `Transcriber.extractSettings`, taking NOTHING from
`app/Sources`), `ats_probe.swift` and `keychain_probe.swift`.

**What costs money.** q1, q2, q5, q6 and q8 make real calls at $0.21 an hour
of audio; q3, q4 and q7 cost nothing. `Ledger.reserve` runs BEFORE every
upload and refuses the call that would pass **$2.00**. Its events are
`reserve → uploaded → created → billed → closed`, each written as a temp file
in the same directory and an `os.replace`, and **nothing in the instruments
deletes, truncates or moves `ledger.json`** — not `--remake`, which rebuilds
`fixtures/`, `bin/` and `bundles/` and nothing else, and not `--selftest`,
which works in a `mkdtemp` root of its own. A reservation closes `deleted`,
`no_transcript`, `upload_only` or `unresolved`, and only the last owes a line
in a person-check issue (#53). Every run with a key starts and ends by
settling the ledger: DELETE everything created and not closed, and for an
upload whose submit reply was lost, `find_own` — ONE page of the list, matched
only against an upload URL this ledger recorded, the body parsed and dropped
inside the method — then a DELETE of what it returns. The spike never deletes,
reads, counts, prints or records anything about a transcript it did not
create. The 2026-09-20 run spent **$0.4353** over 26 calls and closed all 26
reservations; road map 6 §3b is the record.

**The key.** `RC_ASSEMBLYAI_KEY` is read in one place, `aai.client_from_env`,
and the only thing said about it anywhere is the word `present`. A row that
needs it and does not find it is SKIPPED BY NAME with its reason and the run
exits 2 — a skip is not a pass. Every child process gets an environment with
it removed, every printed or written string goes through `Scrubber.clean`, and
`answers.json` and `ledger.json` are `assert_clean`ed before the write. There
is no base-URL variable: `Client.__init__` takes the live base with a real key
or a loopback base with `selftest-dummy` and raises otherwise, no redirect is
followed, and no URL out of a response body is ever requested.

**`--selftest`** is twenty-five checks in seven groups against `fake.Fake` over
loopback, and each group was broken on purpose once and seen to fail before it
was trusted: the `authorization` header sent empty (1a, 24/25); the pair guard
made `if False` (1b, 24/25); `build_opener(NoRedirect)` → `build_opener()`
(1c, 23/25 — the stock opener FOLLOWED the redirect and the second port saw
the request); `recover`'s `find_own` replaced by `200, []` (1d, 24/25);
`remake()` given an `os.remove` of the ledger (1e, 23/25); `run_bounded`'s
`child.kill()` deleted (1f, 24/25); the pause-crossing threshold moved from
33 ms to 33 000 ms (1g, 24/25). Two of those first scored 25/25 and the CHECK
was strengthened rather than the mutant excused — 1e watched a file called
`remake-ledger.json` rather than the real name, and 1f looked for its own hung
child with `pgrep -f "import time; time.sleep(60)"`, whose parentheses `pgrep`
reads as a regular-expression group, so it matched nothing and passed against
a `run_bounded` with the kill taken out.

**`--leakcheck PATH…`** compares in process and prints file NAMES only — never
the secret, never a URL, never a line. It looks for the key and for every
upload URL in `ledger.json`, in every path given except `ledger.json` itself,
which is the one place an upload URL is allowed to be. `clean` is the only
good answer.

---

## Road map 6 — the cloud parts, with no cloud (`assemblyai_fake.py`, `cloud_captions_probe.py`)

C1's second pipeline (road map 6 §10.9) built every part that can be proved
with no AssemblyAI job running, and these two instruments are what prove it.
**Neither makes a call to any AssemblyAI host, and neither can be made to:**
the probe removes `RC_ASSEMBLYAI_KEY` from every child it starts, the fake
binds loopback, and the only credentials either ever sees are the dummies
`proof-key` and `wrong-key`.

### The stand-in server

```sh
python3 tools/proof/assemblyai_fake.py --dir <logdir>
```

Binds `127.0.0.1` on port 0 and prints `port <n>` as its FIRST stdout line,
flushed, which is how a caller learns where it is. It speaks §5c's five calls
— `POST /v2/upload`, `POST /v2/transcript`, `GET /v2/transcript/{id}`,
`DELETE /v2/transcript/{id}`, `GET /v2/transcript?limit=1` — plus R6-14's
`GET /v2/transcript?limit=200` recovery page and three
control routes: `POST /__control/scenario` (replaces the scenario whole and
resets the counters), `GET /__control/log` (requests, failures, created
transcript IDs and confirmed deletes) and
`GET /__control/words` (the exact bytes it serves as `words`, serialised
once, so "byte-equal to what was served" is a comparison and not a hope).

Reused from `cloud_spike/fake.py`: the handler skeleton and its three `do_*`
forwards, `_json`, the lower-cased header log, `redirect_next`, and the
transcript table with its poll count. NOT its 404-after-delete — q6 measured
**200** with `audio_url: "http://deleted_by_user"` and
`text: "Deleted by user."`. Its `words` after a delete is `null`, this fake's
own choice: `work/cloud_spike/answers.json`'s recorded body is cut at 300
bytes inside the `"wor…` KEY, so the key is measured present and its value
was never recorded.

**The redaction rule is R6-9 (e) and it is the reason a proof is safe to run
on a machine where the person has a real key.** An `authorization` value
reaches the log only when it is `proof-key` or `wrong-key`; anything else is
logged as `<redacted: not an allow-listed dummy>`, answered 401, appended to
`failures`, and written nowhere at all.

Other measured answers it reproduces: `audio_duration` is the uploaded
audio's seconds rounded UP, read from the WAV's `data` chunk or the FLAC's
STREAMINFO (q1); an unsupported `language_code` is a **400 at submission**
with q5's sentence verbatim.

### The probe

```sh
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only mapping,stamp
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --mutant no-retry
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only submission
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only submission --mutant no-submit-recovery
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only cache_write
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only cache_write --mutant cache-write-assumed
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only stamp
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only keyless
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only keyless --mutant keyless-ui-requires-key
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only keyless --mutant keyless-any-cache
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only keyless --mutant keyless-omits-deferred
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --only keyless --mutant keyless-late-cancel
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --sources /Users/kevingalligan/.codex/litecode/reelcut/fix-remaining-bugs-series/03-issue-30/baseline/app/Sources --only stamp
```

The `submission` section checks one POST and exact uploaded-URL selection
through dropped, timed-out, server and unreadable replies; first-page lag,
malformed or hostile rows, auth refusals and bounded exhaustion. Its
full-engine rows cancel during a recovery-list request and check the recovered
ID's DELETE or the exact dashboard warning, no later media, and temporary
audio removal. The mutant must fail those recovery assertions.

**R6-16 / #32:** `--only keyless` seeds real cache files and markers through
the dummy-key loopback fake, then runs fresh nil-client processes over
narrow and legacy markers. It compares exact cues, request counts of every
method and package bytes; rejects mixed, malformed, missing, stale, changed
request/source and refresh batches without partial cues or extraction; and
checks valid empty words and pending safe/unsafe deletion IDs. The real sheet
rows measure Generate, notes/hints, click placement, stale facts, first
progress cancellation and a semaphore-synchronized worker success queued
before Stop, with uncancelled/failed controls. The four named copy mutants
must compile and fail semantic KL rows.

**R6-15 / #30:** `--only stamp` now checks the four-field writer and its
sorted six-key outer object, all nine independent identity fields and six
irrelevant source fields, raw ten-field legacy and narrow markers, strict
rejection of each missing/null/wrong-typed relevant field, and byte-identical
readback. New-process loopback runs seed one real transcript, replace only
its marker with each raw legacy variant, and require the same cues, ID and
cache bytes, `cached` estimate, zero upload ticks and zero additional HTTP
requests. Source modification, language and explicit refresh still upload
once each; pending DELETE is retried on a current cache and a failed DELETE
holds a stale cache without replacing it. Fixture/setup failures are scored.
The captured pre-fix sources compiled and scored **45/72**, with 27 named
semantic failures including irrelevant-field rebilling. Current sources
scored **72/72** with no skips in the focused run.
The specified `stamp,estimate,verbatim,cache_write,run,chrome,hygiene`
run passed **351/351** with no skips after the fresh Release build.

**186/186** on the tree, measured three times on 2026-09-20 with no skips,
and **196/196** on 2026-09-20 after 05-review's finding 1 added row 12's
second request — the five degenerate speeds (`0`, a negative, NaN,
`+infinity`, `greatestFiniteMagnitude`), none of which traps: the first four
read as 1, and the largest finite speed passes the guard unchanged. Then
**283/283** (2026-09-20, c1-run; the captured run printed "in 12 s"): 196 plus the 87 that pipeline
added — the `mapping` section's `projected` (the on-device twin over the same
job) and its clip whose `start` is within ten million ticks of `Int64.max`,
the whole `jobs` section, the whole `run` section, and hygiene's two replaced
S rows.

Then **463/463** (2026-09-20, c1-chrome, in 228 s, no skips), and
**469/469** (in 88 s) after that pipeline's review pass added six `chrome`
rows. What c1-chrome added to pipeline 3's 283 is the whole `estimate`
section, the whole `chrome` section, `mapping` rows for R6-10's EXTENSION to
the one integer multiply (ONE CHILD PER MILLISECOND: 0, −1, `Int64.min`,
`Int64.max`, `Int64.max / 600` and either side of it, and of its negative),
one `run` row (every mid-run pair carries a detail) and `hygiene` rows — no
run has ever printed that split, so it is named and not counted here. What a
run DID print, on the fix-pass tree, is each section's own total:
`--only estimate` **96/96**, `--only chrome` **76/76**, `--only hygiene`
**27/27**.

Thirteen sections: `mapping` (5i·12), `jobs` (spec §11's R6-10 — a clip `speed`
the OPS cannot write and the CORE's reader accepts, spliced into a project's
JSON text, read back through `ReelProject.from(json:)` and driven through
`Transcriber.jobs` and both mappings, ONE CHILD PROCESS PER SPEED because an
unclamped `Ticks(_:)` traps and a trap has to be that speed's own scored
failure), `stamp` (13), `client` (15, over an injected `URLProtocol` with no
socket), `cancel` (16, against the fake), `secrets` (17 and R6-9's three
rules and the loopback table), `cues` (19, through the harness's `cues`
mode), `extract` (the WAV against the BASELINE tree, the FLAC, the fallback
and `wholeAsset`), `verbatim` (the served bytes all the way to disk and
back), `run` (`CloudProgress` over a table, then
`CloudTranscriber.transcribe` itself against the fake — every
`(fraction, detail)` it published, non-decreasing, inside its phase's band of
its media's share, holding at the 0.95 point, ending at 1.0; and the
`reelcut-upload-*` a cancelled, an errored and a 401'd run leave behind,
which is none, with a CONTROL that one was there while the body was going
out), `cache_write` (all four initial-write/DELETE combinations against the
loopback fake, a blocked cache folder, a marker-only failure, the next-run
janitor, a zero-word failed run, and the production UI/MCP report formatters;
`cache-write-assumed` changes the reported write result to `true` in a
source COPY and must fail on the unwritten failed-DELETE case), `estimate`
(row 14 — `CloudEstimate` with no disk in it: §8's two dated
rates, every arm of `fate` one row each, and `describe`, `money` and
`reasons` over a table of one file, many, cached and uploaded mixed, speakers
on, nothing to upload, no rows at all, a held media, an unreadable one, a
price under a cent and a duration no file has; the money recomputed IN
PYTHON, the duration pinned once exactly as `rc_timecode_format` prints it
and everywhere else by its shape), `chrome` (row 18 — the Engine popup and
both hint texts, Language re-populated both ways, `runRequest()` per control
state, the vocabulary through the TOOL's own `TranscriptOptions.keyterms`,
the cap note's three readings, the button with and without a credential, a
Mac with NO on-device model at all, the Settings window's rows and its Save /
Verify / Remove through R6-9's disposable folder, the report card's lines,
the bar as displayed, the estimate against a real RUN over two rounds, the
Reelcut menu read off a real `AppDelegate`, `project.yml` diffed against
pipeline 3's tree, and the Settings window PHOTOGRAPHED through the harness,
two processes per appearance) and `hygiene` (the redaction, the language
table, the empty run, the three files that construct a `CloudTranscriber`,
the one declaration of `func keyterms(`, the harness's code naming neither
`SettingsWindowController.shared` nor `AssemblyAIConfiguration.store`, the
Settings sentence byte-identical to pipeline 3's in both files, and the
credential).

The `cache_write` section proves the changed Swift source and report
formatters without building a Metal app. It cannot prove a fresh built-app
MCP result; that requires `make app` and the loopback proof below.

`cloud_captions_probe.py --only settings_verify` compiles all current Swift
sources against the current staticlib and drives the Settings controller's
actual Verify action against delayed loopback fakes. Its nine scenarios cover
unchanged success/refusal through sync and reopen, typed and saved key changes,
Remove, a region change with the same endpoint, both reply orders for two
requests, and no key. The unchanged success case also overlaps two direct
Verify actions with identical inputs and saves that same key. Each scenario
checks the visible status/button snapshots and the fake's exact Verify GETs;
the `verify-ignores-input` and `verify-ignores-owner` source-copy mutants must
compile and fail the matching behavior rows. This section needs no audio
fixture, screenshot, baseline tree or built app bundle. It does not prove a
fresh app build when MetalToolchain is unavailable.

**Every `chrome` child is launched with BOTH launch arguments** —
`-RCAssemblyAIEndpoint <the fake>` so nothing can leave the machine, and
`-RCSecretFolder <a folder under work/cloudprobe/>` so the Settings window's
Save and Remove, which are exactly the code that would write the person's
own key file, write into a disposable directory instead. Every sheet and
window it builds gets a `UserDefaults(suiteName:)` that is removed
afterwards, and the `verify` op refuses to run at all unless the resolved
base URL's host is loopback.

It compiles two entries with `harness/build.sh`'s own `swiftc` line — never
`build.sh` itself, which hard-codes the tree: the probe, and a four-argument
`reference` entry (`<media> <inTicks> <lengthTicks> <out.wav>`) that is also
compiled against `git archive 515e6a80 app/Sources` under
`-D CLOUD_PROBE_BASELINE`, which is how "the moved extractor writes the same
WAV" is a comparison of two TREES. `--wall` (default 1800 s) bounds the whole
run and every child has a timeout whose expiry is that row's answer.

**Eight more mutants landed with c1-chrome** (2026-09-20). Five against the
full 463 of the tree its review read:
`rate-halved` (§8's `perHour` halved) **438/463**, caught by twenty-four
`estimate` rows and the Settings paragraph's own dated rate;
`no-credential-check` (the credential taken out of the cloud button's rule)
**462/463**; `masked-shows-value` (`sync` putting the STORED key in the
field's `stringValue`) **461/463**; `no-ms-clamp` (R6-10's extension
removed) **459/463**, four of the nine ms rows failing by TRAP; and
`empty-closing-detail` (the per-media closing publish sending an empty
detail again) **462/463**. Three more came with that review's fixes and were
scored over the `chrome` section alone (`--only chrome`, **76** rows):
`stale-tooltip` (the cloud reasons left hovering over the on-device summary)
**75/76**; `stale-region-hint` (the hint left naming the OLD region after a
settings change) **75/76**; `two-stores-per-sync` (`sync` building a second
store to read the same key file twice) **75/76** — each failing its own row
and no other.

**Mutant scores**, each a tree COPY with one text replaced, asserted to occur
exactly once (2026-09-20, against 186):

| `--mutant` | What it breaks | Score |
|---|---|---|
| `mapping-no-in` | the `in` term dropped from the projection | 180/186 |
| `no-fifth-rule` | the speaker-change flush removed | 179/186 |
| `no-retry` | the upload retry removed | 182/186 |
| `store-0644` | the key file written `0644` | 184/186 |
| `env-first` | the environment read before the store | 185/186 |
| `stamp-drops-field` | `speaker_labels` dropped from the stamp | 185/186 |
| `no-speed-guard` | the degenerate-speed guard removed from the mapping | 14/15 over `--only mapping` |
| `no-speed-clamp` | R6-10's clamp removed from `Transcriber.placed` | 1/2 over `--only mapping` — it TRAPS at the first request, which is the point |
| `no-length-clamp` | R6-10's bound removed from `Transcriber.contentLength` | 28/30 over `--only jobs` |

**Host-state inputs.** `say` makes the speech fixture (road map 4's text) and
its absence skips the whole `extract` section by name. `ffmpeg`, when it is
on PATH, is the FLAC row's SECOND decoder; `AVAudioFile` is always the first
and the row names which one answered. `git` unpacks the baseline tree, and a
baseline that will not build is a SKIP printed by name with its row count,
every other build failure still being the failure it was.
`work/cloud_spike/fixtures/late.mov` is C0's late-audio fixture, untracked
and rebuildable only by the spike's runner; without it the `audio_track_start_ms`
row skips by name.

**And one host fact the `extract` section had to be redesigned around.** This
Mac's 16 kHz extract is NOT bit-deterministic. Measured: over ten separate
processes of one binary over one fixture, and over five trials of three
decodes inside one process, decodes of the same audio land on one of exactly
**two** byte strings that differ in **one byte** — one 16-bit sample's low
bit, at offset 132098 of a 336 532-byte WAV — in either direction, about one
decode in five. It does not depend on the range asked for, on the binary, or
on the order within a process. So rows W and Q do not compare one decode
against one decode, which a coin would decide a third of the time. They
decode each side five to six times and assert what a real change breaks: one
length, at most two distinct strings in the whole population, and those two
differing in a single sample — with a CONTROL row that measures one range
form disagreeing with ITSELF at that same byte, which is what makes the
comparison about this host rather than about the code.

## Road map 6 — the cloud engine through the built app (`cloud_captions_proof.py`)

C1's third pipeline (road map 6 §10.10). It drives `make app`'s binary over
MCP against `assemblyai_fake.py`, and, like the probe beside it, **makes no
call to any AssemblyAI host and cannot be made to**: every instance is
launched with `-RCAssemblyAIEndpoint http://127.0.0.1:<the fake's port>` and
`-RCSecretFolder <a folder under work/cloudproof/>` (spec §11's R6-9), and
the only credential any of them can have is the dummy `proof-key` — or, for
row 1's no-key arm, nothing at all.

```sh
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py --mutant no-hold
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py --port-base 5030
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py --port-base 5470
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py --mutant keyless-agent-requires-key --port-base 5480
```

R6-14's built-app row drops a submit reply, then repeats with one hidden
list page. It reads back placed captions, the package cache, the fake's
created IDs and DELETE log; a second run must use the cache without another
submission.

For R6-15, row 4 compares the marker's entire four-field `source` object
with independent `os.stat` size/rounded modification second and `get_project`
duration/audio presence. It no longer waits for a thumbnail, peaks or speech
marker or reads display-cache constants from one.
The fresh built-app proof on ports 5430–5432 passed **157/157**, with no
skips and no startup parity complaints in any owned app log.

**115/115** on the tree, no skips, in 45–50 s, measured three times on
2026-09-20, and again at **115/115 in 51 s** after c1-chrome (road map 6
§10.11) — the row COUNT is unchanged on purpose, since that pipeline changed
no tool, no schema and no op. `--binary` points at another build,
`--port-base` (4955) moves the three instances, `--wall` (1800 s) bounds the
run.

**Every instance is now launched `-ReelcutCaptionEngine assemblyai`**, which
pins the SHEET's memory of what a person last chose to the wrong answer for a
tool. R6-2 says an agent call reads that key never, and before c1-chrome an
instance where it read `apple` could not tell a build that obeys R6-2 from
one that does not. The tenth mutant,
**`agent-reads-remembered-engine`** — the tool falling back to
`UserDefaults`'s `ReelcutCaptionEngine` when a call named no engine — scores
**110/115**, failing row 8's "the fake's log is EMPTY" and four of row 1's.

It launches and kills **three** instances, each on its own port with a fake
of its own on port 0, each killed by its own `Popen` pid in a `finally`, each
with a row asserting `grep "Reelcut: "` finds nothing in its log — nothing in
this file ever reads `pgrep`, so another session's instance is none of its
business.

* **A** (4955, `RC_ASSEMBLYAI_KEY=proof-key`) — rows 1's caller arms, 2, LOG,
  3, 4, 5, 7, 8, 9, 10.
* **B** (4956, the variable REMOVED) — row 1's no-key arm.
* **C** (4957, `proof-key`) — rows 6, 11, H, T.

The rows are 5i's 1–11 plus four of this pipeline's own: **H** a media over
AssemblyAI's ten-hour limit (the duration rewritten in a SAVED package and
the package reopened, since no op can make a media longer than its file);
**T** no `reelcut-upload-*` surviving a cancelled, an errored or a refused
run, with a CONTROL that one is there while the body is going out; **K** the
dummy key in no app log, in none of the MCP answers and refusals the run
accumulated, and in no file the run wrote; **X** no logged header or JSON
body holding this host's user name or home path.

It imports `build`, `run_probe`, `run_cues`, `Fake`, `child_env`,
`population`, `wav_samples`, `make_fixture`, `word` and `MUTANTS` from
`cloud_captions_probe.py` rather than copying any of them, so the probe
binary and the harness it reuses are the ones that file builds.

The R6-16 MCP rows seed a package on an owned keyed instance and reopen it
on a separate owned keyless instance with an invalid endpoint setting. They
check `place:false`, placement, exact cues, one-step undo/redo, whole-batch
mixed refusal, deferred cleanup notes and unchanged package bytes/request
count. `keyless-agent-requires-key` must build and fail the named keyless
result row.

**Mutant scores**, each a COPY of the tree from `tree_copy.make_copy` —
`app/` and `agent/` copied, every other build input `project.yml` names a
SYMLINK to the tree's, `core` already built, so `project.yml`'s pre-build
`cargo build --release` is a no-op — one text asserted to occur exactly
once, the copy's own `make app` under a 900 s wall (since issue batch B7;
`xcodegen generate` plus the Makefile's `xcodebuild` line before it), then
every row on port base 4960 (2026-09-20, against 115):

| `--mutant` | What it breaks | Score |
|---|---|---|
| `stamp-always-stale` | the stamp comparison deleted | 107/115 |
| `mapping-no-in` | the `in` term dropped from the projection | 111/115 |
| `no-delete` | the remote DELETE removed | 91/101 |
| `no-retry` | the upload retry removed | 113/115 |
| `no-fifth-rule` | the speaker-change flush removed | 114/115 |
| `universal-2-only` | `speech_models` pinned to Universal-2 | 112/115 |
| `no-janitor` | the janitor removed | 109/115 |
| `auth-carries-on` | the 401 arm not ending the run | 114/115 |
| `no-hold` | R6-11's hold removed | 111/115 |

`no-delete` is the one whose TOTAL moves: with no transcript ever deleted,
R6-11 holds every media a later row touches, so rows 7, 11 and H throw where
the tree's build answers — scored as three row failures each named for its
row, never as a traceback, because a mutant's score is the measurement.

**Host-state inputs.** `media/speech.mov` (road map 4's fixture; this file's
own section says how to make it) and `say` for the second media, without
which row 5's relink arms and row 6 skip BY NAME. `ffmpeg`, when it is on
PATH, is row 2's second FLAC decoder; `AVAudioFile` always runs and the row
names which answered. Three free loopback ports, and one free port per fake.

**One thing row 2 had to be designed around, measured here.**
`media/speech.mov`'s 16 kHz extract is not repeatable at ALL — four extracts,
four distinct byte strings of one length (167 930 bytes), spans 105–228 bytes
— where the `say` AIFF over the identical code is the TWO-string,
one-sample population `archive/reelcut-remaining.md` §5 records. The
difference is the AAC decode, not the resampler. So row 2's upload-count and
request claims are made over `speech.mov` and its BYTE population over the
AIFF, with the .mov's own spread printed as a row beside it, named as the
reason. Road map 6 §5i·2 was revised, dated, to say the same.

### `cloud_captions_live.py` — the LIVE rows, 20 and 21, which SPEND money

Road map 6 §5i's last two rows, against `api.assemblyai.com` itself. They
are reached only through `cloud_captions_proof.py --live`, which runs them
INSTEAD of rows 1–11, and the flag is off by default, so a routine proof run
cannot spend a cent:

```sh
python3 tools/proof/cloud_captions_proof.py --live --port-base 4980
```

**What it spends.** One transcription of the eleven-second `say` fixture —
about $0.00064 at AssemblyAI's published $0.21 an hour — and nothing else.
`tools/proof/work/cloudlive/ledger.json` is the spike's own append-only
ledger (`cloud_spike/aai.py`'s `Ledger`, shared rather than respelled): a
reservation is written BEFORE every billable call, the gate refuses at
**$0.25** or at **six transcriptions**, and it counts an `extra` reservation
for every `POST /v2/transcript` line and every transcript id the APP made
that the ledger had not already accounted for — so the ceiling counts what
the app DID, not what the rows expected. Nothing deletes or truncates the
ledger; an open or `unresolved` row from an earlier run is a FAIL and stops
the next one before it calls. The run's ledger is a `LiveLedger`
(`cloud_live_ledger.py`), so every reservation is ALSO made first in the
proofs' ledger, `~/Library/Application Support/Reelcut Proofs/spend.jsonl`
(spec §11 P-6), at its worst case — the planned seconds at
`AssemblyAIRates`' $0.21 + $0.02 an hour, read from
`app/Sources/CloudEstimate.swift` — refused `budget:` past the month's $5
(an `extra` is recorded, never refused), and settled there at the billed
seconds, or at $0 when it closed `no_transcript` or `no_upload`. Before the
first call, row **B** checks that the month's budget covers one; when it
does not, B FAILs with the refusal and the rest SKIP. The keyless run never
opens the proofs' ledger; its budget CONTROL uses scratch ledgers under
`work/cloudlive/controls/`.

**What it uploads.** Only `work/cloudprobe/fixtures/speech.aiff`, the
synthetic `say` fixture. Never a real recording, never a file from outside
`work/`.

**What it deletes.** The app deletes its own transcript (R6-4) and the row
proves it with C0's q6 sentinel — a GET that answers 200 with `audio_url`
`http://deleted_by_user` and text "Deleted by user." — and `cleanup` runs in
a `finally` over the set of every id this run's own lines named plus the one
in the cache file, closing a reservation `deleted` only when the sentinel
passes for each. Nothing here ever LISTS the account: an id the run did not
see is an id these files do not know exists.

**The key.** `cloud_spike/aai.py`'s `client_from_env` is its one reader and
never returns the string. Exactly two processes have it: the app under test,
which INHERITS it (`key=INHERIT` — never a launch argument, which `ps` would
show), and the proof's own `Client`, for the read-backs the app cannot do.
Every other child is `child_env()`'s environment, with the variable removed.
The leak row compares IN PROCESS over the captured lines, every MCP answer
and refusal, the package, the secret folder, `work/cloudlive/` and both
instances' `/tmp/reelcut-<port>.log` files, and prints only a boolean.

**Two instances, both with no endpoint override** and with `-RCSecretFolder`
pointed at an EMPTY directory, which is the arm of R6-9 that keeps the
person's real store closed and leaves the environment as the only
credential. **L0** carries the DUMMY key and is the free control: the real
service answers `POST /v2/upload → 401`, the run is refused in the key's own
sentence, and ZERO `POST /v2/transcript` lines are printed — if that arm
submits anything, the real key is never used at all. **L1** carries the
person's own, and is row 20 and row 21.

**A pty, not a log file.** `AssemblyAIClient+Session.swift`'s `note` is a
`print`, and `print` is BLOCK-buffered under a file redirect: an instance
whose stdout is a file writes its client lines 4096 bytes at a time and cuts
the last one in half (measured — `/tmp/reelcut-4960.log` holds exactly 4096
bytes of them and 4970–4972 hold none). The live rows COUNT those lines, so a
live instance gets a `pty` and a reader thread that splits on `b"\n"` in
bytes, decodes with `errors="replace"`, treats `OSError` and an empty read
alike as EOF, and never raises — an unexpected exception sets
`reader_failed` (a FAIL row) and the thread keeps DRAINING, so the app can
never block in `print` with a transcript half made. Instances A, B and C of
the stand-in proof are NOT changed: their rows do not count lines.

**Skips, by name, each counted.** `RC_ASSEMBLYAI_KEY` absent (printed as the
word `absent`, never the value); no TCP connect to `api.assemblyai.com:443`
in 5 s; no `say`; the ledger gate refusing; and, inside row 20, the race for
the provider's own bytes — a GET of the app's own transcript id every 0.25 s
for at most 30 s, which the app's DELETE can win. `LIVE_ROW_COUNT` (37, with road map 13 P3's budget CONTROL) is
what a precondition skip reports, and the run prints the number of checks it
actually made beside it.

**The money half is `cloud_live_ledger.py`**, imported by the live module so
every name is reachable on it: the ledger gate, the line parsing
(`submits`, `uploads_ok`, `ids`, `account`), the deletions and the CONTROLs
that make each of those fail on purpose in the same process. Two files
because one would pass the 400-line cap on a new file.

---

## The C1 reader review's instruments (2026-09-21)

Road map 6 §10.13 is the record. The review added ONE script, three scenario
keys, one flag on both cloud instruments, and rows and mutants inside what was
already there. **No live call was made and nothing was spent.**

### `makefile_env_proof.py` — H·2, the two keys and `make app`

```sh
(unset ANTHROPIC_API_KEY RC_ASSEMBLYAI_KEY; python3 tools/proof/makefile_env_proof.py)
(unset ANTHROPIC_API_KEY RC_ASSEMBLYAI_KEY; python3 tools/proof/makefile_env_proof.py --mutant no-unexport)
(unset ANTHROPIC_API_KEY RC_ASSEMBLYAI_KEY; python3 tools/proof/makefile_env_proof.py --mutant no-unexport-anthropic)
```

**3/3** on the tree, and **2/3** under each mutant (road map 12 A1 part 2
added the Anthropic key). It builds a tree COPY at
`tools/proof/work/makefile-env/tree` with `tree_copy.make_copy`: `app/`,
`project.yml` and `Makefile` are copied; every other build input
`project.yml` names is a SYMLINK to the tree's (`core` already built, so the
copy links the tree's staticlib); and `agent/` is COPIED without
`node_modules`, because the helper's build step runs `bun install` and
`bun build`, which write into it, and a copy keeps bun out of the tree. It
runs `make app` inside the copy with both keys POPPED and a dummy in each
place, `RCDUMMY-makefile-env-proof-5d1c` for `RC_ASSEMBLYAI_KEY` and
`RCDUMMY-makefile-env-proof-anthropic-9b3e` for `ANTHROPIC_API_KEY`. Then it
searches every file under the copy's `build/` and `Reelcut.xcodeproj/`
**in process** for each dummy's bytes. It prints paths and booleans and
nothing else; the person's own values are never read, printed or searched
for.

Three rows:
- The copy's `make app` made `Reelcut.app`'s binary. A failed build holds
  nothing, and "no file holds the dummy" would be true of it for the wrong
  reason.
- **No file of 553 holds the AssemblyAI dummy.**
- **No file of 553 holds the Anthropic dummy.**

Each `unexport` directive is asserted to occur exactly once in the tree's
`Makefile`. `--mutant no-unexport` removes `unexport RC_ASSEMBLYAI_KEY` in
the COPY, and `--mutant no-unexport-anthropic` removes
`unexport ANTHROPIC_API_KEY`. Under each, that key's row FAILS, with the
dummy in
`build/Build/Intermediates.noindex/XCBuildData/<hash>.xcbuilddata/task-store.msgpack`
and one attachment beside it. These are the CONTROLS that the instrument can
see a leak of either key. **It measures the `app` recipe ONLY** and says so
in its header and in its first printed line: `app` is the one recipe that
runs `xcodebuild`, which is the one tool measured to write its environment
down.

### Three new scenario keys on the fake

| Key | What it does |
|---|---|
| `stall {route, seconds}` | that route answers NOTHING for `seconds` and then answers normally — what an IDLE timeout is measured against |
| `drop_reply [{route, times}]` | the route's EFFECT happens and the socket closes unanswered; `times: -1` is always |
| `echo_authorization` | a FORCED failure's `error` sentence carries the allow-listed dummy it received, so a relay of the service's sentence can be caught carrying a credential |

`drop_reply` on `submit` is what mints a transcript the caller never learns
the id of; `stall` on `delete` is what makes the janitor's bill measurable;
`echo_authorization` is what made row E's branch reachable.

### `--fake-mutant`, on both cloud instruments

```sh
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py --fake-mutant fake-logs-any-key --only hygiene
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py --fake-mutant fake-logs-any-key --port-base 4990
```

`--mutant` copies `app/` only and loads the fake from the working tree, so a
mutant of the INSTRUMENT cannot be one of its rows. `--fake-mutant` copies
`assemblyai_fake.py` (stdlib only, so a copy runs from any folder) to
`<WORK>/mutants/<name>/`, patches the COPY — the text asserted to occur
exactly once — and rebinds the probe's one `FAKE` global, which is the name
`Fake.__enter__` reads. The proof reaches it through the MODULE, so the
rebinding is the one its own `Fake` sees. **The working tree's fake is never
edited.** The two flags are refused together: a cell measures one thing.

One row: `fake-logs-any-key`, the review's Z11, which makes the fake log any
`authorization` value rather than only the two allow-listed dummies.

### New rows and mutants inside the two cloud instruments

`cloud_captions_probe.py` — **492 rows** on the tree (469 at the review's
baseline; 488 when the mutant matrix ran, 490 with Z5's sharper row, 492 after
the review's fix pass). New: a fourth `words` shape in section 15 (an array
holding an element that is not a word); section `run`'s **J** block, six rows
about the janitor and a Stop already pressed, three of them CONTROLs; section
`run`'s **I** block, **five** rows about a cache file's `transcript_id` being
somebody else's string — three about what reaches the wire and what R6-11
holds, and two from the fix pass, that such an id is in neither
`janitorDeleted` nor the cache file's `remote_deleted`; section `run`'s
sharper Z5 row, that **no line the child printed holds the dummy**, with its
CONTROL that the child printed client lines to look in; three `EINTR` rows in
section 17; three hygiene rows about what shields `chromeSettings`' default
store; two rows in section 12 holding `Transcriber.project` to the PRE-C1 line
and naming the one place they differ by decision. Its `MUTANTS` table gained
`janitor-deaf`, `eintr-unwritable`, `any-id-on-the-wire`,
`refused-id-reported-as-deleted` and the review's ten named Z mutants.

`cloud_captions_proof.py` — **146 rows** (115 at the baseline, 142 when the
mutant matrix ran), and `--port-base` is now honoured under `--mutant` as
well. New rows: **O** (a hostile `audio_duration` cannot kill the app, 12
checks over three trials), **M** (a cache write that failed certifies nothing,
5), **E** (a relayed server sentence carries no credential, 6) and **B** (a
failed run names what it already cost, 8 — four of them from the fix pass, a
run whose cache write is stopped the way row M stops it). Its
`CLOUD_MUTANTS` table gained `audio-seconds-plus`, `marker-over-stale-file`,
`key-relayed-verbatim`, `silent-about-the-bill`, `bill-promises-cache` and
the seven Z mutants it scores; `no-janitor` was RE-AIMED at the janitor's new
line and `no-delete` at `fetch`'s, which now reads the client's three-state
answer.

Row M's write is made to fail by setting the cache file's `UF_IMMUTABLE`
flag: an `.atomic` write renames over the file, which the flag refuses, while
the FOLDER stays writable so the marker's own write still succeeds — which is
the whole point of that row.

**B4 (2026-09-29, #71, #76, #81, #94, #116).** `cloud_captions_probe.py`
gained four rows, **735/737** on the tree against 731/733 before (the two
failures are the same two rows both times: F's ffmpeg decoder, a host fact,
and 18's `project.yml` diff check, #156). Section 15 has two #71 rows, a
`completed` body served
under `../upload` and under `t_other`, each `malformed` with one DELETE to
the POLLED `/v2/transcript/t_probe` (`words-empty` is their CONTROL); the
hygiene section has **K (#76)**, that the probe's Swift names no
`UserDefaults` suite and removes no persistent domain, with its CONTROL on a
planted string. Every defaults object the probe builds is now a
`ProbeDefaults` (in `PROBE_HEAD`): the harness's `MemoryDefaults`, override
for override, except that its argument domain is the process's own, seeded
from the launch arguments and replaceable in memory, so R6-9 and SV's second
endpoint still read what the chrome child was launched with and nothing
reaches `~/Library/Preferences` (0 `cloudprobe-*` plists after a run and a
35 s wait). Row I's wording now says which five ids are hostile (media
11–15) and which one is the control (16). New mutant `echoed-id-trusted`:
42/44 under `--only client`, failing exactly the two #71 rows.
`cloud_captions_proof.py` gained four rows, **171/171** against 167/167:
row 2's `endpoint` is `127.0.0.1` (#94), KL MCP's keyless result has no
`endpoint`, and **LOG** (instance A, after row 2) reads the client's lines
out of the instance's redirected log and holds them to the fake's request
list in order (#116), with a CONTROL that the fake saw an upload, a submit,
a poll and a DELETE. New mutants `endpoint-whole-url` (169/171: row 2's
`endpoint` and KL MCP's absence check) and `note-block-buffered` (170/171:
LOG's sequence check; its CONTROL passes). Both were scored against a copy
built by hand and run with `--binary`, because `--mutant`'s copy lacks
`docs/`, `graphic/tests/graphics/` and `agent/`, and its `xcodebuild` fails.

### Road map 7 part 6 — core argument contract

Run `python3 tools/proof/op_contract_proof.py` from the repository root. It
runs four FFI suites in sequence: `op_nullability` (all 54 optional fields,
required Boolean and scope), `op_default_booleans` (four defaulted plain
booleans and nullable semantic controls), `op_ticks` (the exact 27-op / 36-pair
published tick inventory at 30/1 and 30000/1001), and `op_tick_payloads`
(picture timing versus source/audio precision). The Rust commands are also
available directly with `cd core && cargo test --release --test NAME`.

Three negative controls use `--mutant null-as-absent`,
`--mutant unsnapped-marker`, or `--mutant nearest-transition`. Each copies
the current core and tests into its own temporary tree, uses a private Cargo
target and mutates only that copy. A successful negative control **exits 1**
after compiling and observing its named behavioral assertion fail; anchor,
compile or attribution failures exit 2. The nearest-transition control runs
both handle and ripple assertions. No built app or cloud account is needed.

### Peaks decode completion — issue #23

`python3 tools/proof/peaks_probe.py` authors 44.1/48 kHz mono/stereo WAV,
all-zero PCM, normal and corrupt AAC, a delayed PCM MOV with a real empty edit,
a delayed AAC with a millisecond target edit list, and a physically truncated
WAV under `tools/proof/work/peaks-probe/`. It compiles the actual
`app/Sources/*.swift` with `peaks_probe.swift` using the offscreen harness's
Swift compiler line; `--sources PATH` selects a copied app-source tree for a
mutant. A compile/setup failure is scored as a failure. The Swift probe awaits
each actual `MediaImporter.peaks` pass, reads its marker and payload, and
compares every WAV bucket against an independent Python count of authored
frames, including the positive tail and stereo channel maximum. It also
feeds real decoded `CMSampleBuffer`s through the same accumulator and final
publication path to test completed streams missing final/middle buffers,
nonfinite and short blocks, genuine silence, legacy cache migration and reuse,
and nil/unknown/corrupt cache states. The valid delayed AAC is a deliberate
boundary control: its edit target ends at 1.250 s on a 1 ms grid, while the
reader returns PCM through 1.249333 s. A whole-second WAV boundary does not
receive a whole-second allowance. A source with a decoded 0/1 timestamp and
missing tail is rejected through publication and readback, while a fully
covered coarse fractional target is published and read back. Coarse metadata
only limits edge-shortfall tolerance, not exact coverage. The truncated WAV is
qualified against AVFoundation's physical track extent, not its original header.

After `make app`, start a fresh owned Release app on port 5410 with
`RC_ASSEMBLYAI_KEY` unset, `-ApplePersistenceIgnoreState YES` and
`-AgentServerEnabled YES`; verify its log names that port and contains no
`Reelcut: ` parity complaint. Then run
`python3 tools/proof/peaks_proof.py 5410`. The built-app checks use
`detect_silence` and `normalize_clip` to distinguish pending corrupt audio,
real silence and an audible clip, verify unchanged project JSON on refusal,
and reject an old false-silent cache before the next normal pass migrates it.
The existing `remaining_proof.py` checks surviving inodes across repeat opens
and consolidation; its peaks assertions now compare the versioned wrapper's
`source` to the unchanged thumbnail stamp. `source_mirror_probe.py` writes a
versioned marker beside its independently authored waveform.

For negative controls, copy `app/Sources` into a temporary directory and run
`python3 tools/proof/peaks_probe.py --sources PATH` after exactly one change:
remove the `status == .completed` guard in `finishPeaks`; remove its
`!peaks.failed`/`acceptedFrames`/`covers` guards; let `loadPeaks` accept a
bare `CacheStamp`; or require a positive bucket in `PeakBuckets.covers`.
Each mutant must compile and fail a named assertion tied to that behavior;
setup errors are not evidence. Re-run the pristine probe afterward. Road map
4 §9 records the actual scores and limitations.

The review-fixed pristine source probe scored **80/80**; the built-app proof
**21/21**, with zero parity complaints. The existing cache/source-mirror,
phase 3 and silence 2 gates scored **170/170**, **40/40**, **79/79**,
**123/123** and **91/91** in their respective source and MCP runs. Four
sequential compiled source-copy mutants against the 71-row probe before four
additional positive controls scored **70/71** (status), **67/71** (coverage
and ingestion), **70/71** (legacy) and **68/69** (zero amplitude). Their
named killed assertions did not change when the final positive controls were
added. Two further compiled source-copy mutants scored **79/80** each:
restoring unbounded 0/1 timestamp tolerance published a missing tail, and
restoring the coarse-grid pre-rejection withheld fully covered PCM. The
pristine **80/80** run was repeated after those mutants; road map 4 §9 and
the litecode checks and fix-notes files hold the evidence.

## Road map 8 — the word captions spike (`words_spike/`)

W0, run complete on 2026-09-22: the seven questions
`archive/reelcut-roadmap-8.md` §3 asks before any word-caption code is
written. **The answers are in that document's §10.1, and §3a lists every
design section a row overturned.** `tools/proof/words_spike/README.md` is how
to run it again; this paragraph is the entry in this table.

```sh
python3 tools/proof/words_spike/words_spike.py                  # all seven rows
python3 tools/proof/words_spike/words_spike.py --only q4,q5     # a subset; the rest carry forward
python3 tools/proof/words_spike/words_spike.py --leakcheck tools/proof/words_spike \
    tools/proof/work/words_spike archive/reelcut-roadmap-8.md tools/proof/README.md
```

Five instruments. `speech_probe.swift` is a standalone `@main async` probe
built at `-target arm64-apple-macos26.0` (the line
`tools/proof/silence_spike/level_apple.swift:7` already proved here) that
takes nothing from `app/Sources`; it answers `words`, `sf`, `assets` and
`cancel`, and it never calls `requestAuthorization` or `downloadAndInstall`.
`text_probe.swift` is compiled AS `main.swift` over every file in
`app/Sources` but the app's own, module `Reelcut`, at
`-target arm64-apple-macos15.0` — `peaks_probe.py:101-117`'s line — and
answers `tokens`, `raster`, `stress` and `fonts`; it registers
`app/Resources/Fonts` and the spike's own `fonts/` at `.process` scope with
the harness's own loop before anything asks for a face, because a bare Mach-O
has no `ATSApplicationFontsPath` and `CTFontCreateWithName` never answers nil.
`tokens.rs` is `str::split_whitespace` alone, `rustc -O`, no dependencies.
`scratch_rows.py` rsyncs a copy of the tree, moves the five deployment-target
pins IN THE COPY, builds it, and drives the app it built on port 4831 by PID:
the tree's `project.yml`, `Makefile` and `tools/proof/harness/build.sh` are
never written, which `git status --short -- app core project.yml Makefile
tools/proof/harness` proves afterwards.

Two rules the spike learned the hard way, worth carrying into the next one.
**A bounded child whose answer does not fit a 64 KiB pipe deadlocks
`local_rows.run_bounded`**, which reads only after the child exits — the
ten-minute probe prints 1 755 words and hung twice, which read exactly like a
length ceiling in the Speech framework and was not one;
`speech_rows.run_drained` is the version that drains while it waits. And **a
bound enforced by an `await` is not a bound**: when a `SpeechAnalyzer` stops
answering, nothing on the cooperative pool gets scheduled either, so
`speech_probe`'s watchdog is an ordinary `Thread` that prints what arrived and
exits.

Only q2 spends money — three synthetic `say` fixtures, about 75 s of audio,
each uploaded once and DELETEd, with `Ledger.reserve` before every upload and
a $2.00 ceiling. `ten.wav` is never uploaded. `--leakcheck` carries its OWN
secret list (the key plus this ledger's upload URLs) and exempts only
`work/words_spike/ledger.json`; it is not `cloud_spike.leakcheck`, which is
pinned to the other spike's ledger, and nothing under `cloud_spike/` was
edited.

The full run scored **exit 0 with all seven rows `run`** and every reservation
closed. One SUB-row did not run and is named in road map 8 §10.3 and in
#52: q3's no-network case, which would change
host network state.

## Road map 10 — the graphics spike (`graphics_spike/`)

G0, run complete on 2026-09-24: the nine questions
`archive/reelcut-roadmap-10.md` §3 asks before any graphics code is written.
**The answers are in that document's §10.1, and §3a lists every design
section a row rewrote.** `tools/proof/graphics_spike/README.md` is how to
run it again; this paragraph is the entry in this table.

```sh
python3 tools/proof/graphics_spike/graphics_spike.py                    # all nine
python3 tools/proof/graphics_spike/graphics_spike.py --only q4,q5       # a subset; the rest carry forward
python3 tools/proof/graphics_spike/graphics_spike.py --only q5 --mutant # the on-purpose failure: exit 0 only if caught
python3 tools/proof/graphics_spike/graphics_spike.py --only q7          # git check, make app, the app on port 4843
```

The instruments are a scratch Rust crate (`rquickjs` 0.14.0 and `resvg`
0.48.1 with only `text`, its own `[workspace]`, a CLI whose every
subcommand prints one JSON object), the six §5k graphics, two Swift probes
(`q9_probe.swift` calls a throwaway core export; `q7_watch.swift` is a
`DispatchSource` on a folder) and a Python runner over `bounded.py`, which
puts every child in its own process group under a hard bound, drains its
pipes while it waits (the 64 KiB lesson of the words spike above) and
answers an expiry as `expired: True`. **q1 and q9 patch the core** —
`core/Cargo.toml`, `core/Cargo.lock`, `core/src/lib.rs` and a new
`core/src/ffi_graphic.rs` — and **delete `core/target`** for their cold
builds; `rows_build.revert()` always runs after them and writes `git diff
c874069 --stat -- core app` and `git status --short -- core app`, both
empty, into `answers.json`. q7 runs last, on the app built from the reverted
tree, launches its own instance on port 4843 by PID and kills only that;
`grep "Reelcut: " tools/proof/work/graphics_spike/reelcut-4843.log` must
print nothing. q7 measures the package with `media/` as the STAND-IN for
`graphics/`, which the unchanged app's whitelist cannot keep; the
`graphics/` run is the CONTROL, expected absent.

The full run scored **exit 0 with all nine rows `run`** and the git check
empty; `--only q5 --mutant` caught the counter mutant (137 mismatches,
exit 0) and `--only q7` re-ran q7 (exit 0). Nothing was left unrun; two
answers are by proxy or by reading, and road map 10 §10.2 names them.

## Road map 10's G1d — the engine through the app (`graphics_ffi_probe.py`, `graphics_ffi_probe.swift`)

The nine `rc_graphic_*` exports have no caller a script can reach before
G3, so the probe is compiled from `app/Sources` over `harness/build.sh`'s
swiftc line (a probe that will not build is a scored FAILURE) and drives
the app's own wrappers — `GraphicLibrary`, `GraphicModule`, `GraphicRaster`
in `ReelCore.swift`. It runs under `graphics_spike/bounded.py`'s `run`
(600 s bound, its own process group). The Swift side loads every `.ttf` in
`app/Resources/Fonts`, compiles `graphic/tests/graphics/lower-third.js`,
and prints one JSON object (kept as `work/graphics-ffi-probe/answer.json`)
beside the raw BGRA of frame 30 and its PNG; the Python side scores P1–P9
with oracles of its own: P1 built and answered; P2 every bundled `.ttf`
taken (the folder's count) and 16 zero bytes refused; P3 `describeJSON`'s
schema keys in the module's order and its revision equal to `hashlib`'s
SHA-256 of the fixture; P4 frame 30 an `<svg` with no warnings; P5 the
SHA-256 of the BGRA equal to the crate's pin (`graphic/tests/pins.json`
`lower-third.30`, read from the file) and
`work/graphics-ffi-probe/lower-third-30.png` a PNG with a 1920×1080 IHDR;
P6 frame 30 twice byte-identical and frame 0 different; P7 a syntax error
naming line 3; P8 a top-level `while (true) {}` at 50 ms failing inside the
bound in the budget's sentence; P9 `{"size":"big"}` at frame 30 answering
the one `props.size` warning with frame 30. A run took 74 s, most of it
the build.

`--mutant frame-off-by-one` builds from a COPY of `app/Sources` with
`GraphicModule.svg`'s `Int64(frame)` replaced by `Int64(frame + 1)` (the
anchor asserted to occur exactly once) and exits 0 only if P5 FAILED.

```sh
python3 tools/proof/graphics_ffi_probe.py                              # → 9/9
python3 tools/proof/graphics_ffi_probe.py --mutant frame-off-by-one   # exit 0 = P5 FAILED
```

## Road map 10's G3a — the package's `graphics/` store (`graphics_store_probe.py`, `graphics_store_probe.swift`, `graphics_store_proof.py`)

**The probe.** The watcher and the save whitelist have no MCP caller yet,
so `graphics_store_probe.swift` is compiled from `app/Sources` over
`harness/build.sh`'s swiftc line (a probe that will not build fails all
seventeen rows) and drives the app's own `GraphicStore` and
`ProjectDocument`, under `graphics_spike/bounded.py`'s `run`. Every wait
pumps `RunLoop.main` — which runs the store's main-queue drain — in polls of
at most 2 s. It prints one JSON object (kept as
`work/graphics-store-probe/answer.json`); the Python side scores W1–W13 and
C1–C4 with oracles of its own: `hashlib` for every revision and its own
literals for the core's name sentence and the scan's warnings. W1 an
untitled root made at start, empty and silent; W2 a package store that
creates nothing, then sees an outside `mkdir graphics` + `mv x.js` (one post,
ONE `folderDidAppear`) and an in-place edit after it; W3 a rename-over; W4
an in-place `O_TRUNC` rewrite on the same inode; W5 a removal; W6 two files
coalesced into one post; W7 `Bad.js` and `d.js.partial` posting nothing and
`Bad.js` warned; W8 `fonts/` and `assets/` moving the library version (every
module named, `library: true`, the 0-byte PNG warned and skipped); W9 the
app's own `write` creating `graphics/` (one callback, no `.partial`) and
refusing `Bad` in the core's sentence; W10 the folder swapped as a save
swaps it (no post, then an edit posts: re-armed by path); W11
`packageDidMove(to:)`; W12 `stop()` dropping a pending pass; W13 a write
and a `rescan()` at once being ONE post. C1 a saved document's
`fileWrapper(ofType:)` written over its own package keeps `graphics/x.js`;
C2 an untitled document restored from autosave seeds its root and its save
carries the file; C3 a fresh untitled document's save has no `graphics/`;
C4 a document is freed after `close()` AND after being dropped unclosed.

**`TMPDIR` does not move `NSTemporaryDirectory()`** on this host (measured
2026-09-25: it answers `DARWIN_USER_TEMP_DIR` whatever the variable says),
so the untitled roots land in the per-user temporary directory; the probe
reports that directory, W1 and C2 are scored against it, and the probe
removes every root it made before it answers.

Three mutants, each built from a COPY of `app/Sources` with one anchor
asserted to occur exactly once: `whitelist-removed` (the `graphics/` line in
`fileWrapper(ofType:)` deleted) exits 0 only when C1's file is ABSENT;
`no-file-sources` (the per-module `arm` deleted) only when W4 FAILED;
`strong-callback` (`[weak self]` removed from `folderDidAppear`) only when
C4 FAILED — which it can only do through C4's unclosed half, since
`close()` drops the store and breaks the cycle either way.

**The proof.** `graphics_store_proof.py` is G0's q7 package rows against
`graphics/` itself, with the built app: its own instance on its own port
(default 4851), launched and stopped by PID, the log at
`work/graphics-store/reelcut-<port>.log`. S2 `new_project {path}` leaves no
`graphics/`; S3 a `graphics/` made from outside while open is saved without
"changed by another application"; S4 survives a relaunch and a save; S5 a
Save As; S6 an autosave in place (15.1 s after the edit in the recorded
run); S7 an untitled project's first save carries a file moved into its
root; S8 a package that never gets a graphic stays without `graphics/`
through a save; S9 a folder made while the app was closed survives open and
save; S1 the parity grep over every launch prints nothing.

```sh
python3 tools/proof/graphics_store_probe.py                              # → 17/17
python3 tools/proof/graphics_store_probe.py --mutant whitelist-removed   # exit 0 = C1 ABSENT
python3 tools/proof/graphics_store_probe.py --mutant no-file-sources     # exit 0 = W4 FAILED
python3 tools/proof/graphics_store_probe.py --mutant strong-callback     # exit 0 = C4 FAILED
make app && python3 tools/proof/graphics_store_proof.py                  # → 9/9
```

Made to fail by hand (road map 10 §10.6): the whitelist line commented out
and the app rebuilt, S3 through S7 and S9 failed (3/9), S3 with `x.js`
ABSENT after the save; and `folderDidAppear` set to nil instead, S3 alone
failed, its save refused with "The document “P1.reelcut” could not be
saved. The file has been changed by another application."

## Road map 10's G3b — a graphic clip drawn (`graphics_proof.py`)

The registry, the compositor case and the two op tools against the BUILT
app: its own instance on its own port (default 4879), launched and stopped
by PID, the log at `work/graphics/reelcut-<port>.log`, every child bounded
and every wait a bounded poll. The modules are written outside a package and
`mv`d into its `graphics/` from the shell. `bar.js` is the script's own —
one rect at x = frame × 4, 100 wide, filled with `props.color`, no fonts, no
`meta` size so its raster is the canvas and maps 1:1 — plus the crate's
fixtures `lower-third.js` and `callout.js`. PNGs are read with
`e1_proof.py`'s decoder, stopped after the row a pixel needs so a 5 s poll is
not spent decoding. P1 `add_graphic_clip` (polled ≤ 5 s while the store sees
the module) stores `graphic.name` and meta's 120 frames; P2 frame 30's EDGE
pixels (122,50) red and (222,50) black pin the frame number, with frame 31
differing as a CONTROL; P3 a 17-frame `move_clip` makes frame 47 frame 30's
bytes; S1 a `split` at frame 40 leaves frame 41's bytes; R1 `set_graphic`
props change the frame, `{nope: 1}` is refused naming `props.nope`, and one
undo restores the bytes; H1 a module rewritten by `mv` redraws within 5 s;
L1 a stored prop the new schema dropped still draws (G-4's leniency); F1
`lower-third` draws its accent bar through the bundled fonts, and is
MEASURED against `graphics_ffi_probe.py`'s frame-30 BGRA over black; K1
save, relaunch, open; K2 Save As; T1 frame 30 at 29.97 fps (tick 600 600) is
the 30 fps frame's bytes; K3 an untitled project's graphic saved for the
first time and reopened; A1 a transparent canvas with `callout` as
`prores_4444`, decoded at 2 s, alpha 0 at a corner and 255 on the stroke; Z1
the parity grep over every launch.

`--mutant frame-plus-one` copies the tree with `tree_copy.make_copy` (`app/`
and `agent/` copied, every other build input `project.yml` names linked),
replaces the one anchor in `LayerRenderersGraphic.swift` so the module is
asked for `frame + 1`, builds the copy with its own `make app` into its own
directory, drives it
through P1 and P2, and exits 0 only if P1 held and P2 FAILED. The rows after
P2 are relative, so a uniform +1 moves both sides of them.

```sh
make app && python3 tools/proof/graphics_proof.py --port 4879          # → 14/14
python3 tools/proof/graphics_proof.py --mutant frame-plus-one          # exit 0 = P2 FAILED
```

## Road map 10's G3c — a failing graphic and the export pin (`graphics_proof.py` E1–Q3)

The same script, seven rows after A1; the score is **21/21**. E1–E3 reopen
P1, `mv` in three modules of the script's own and add ONE front track, and
each row adds its clip there and `undo`es it (a `spin` clip left behind
would cost every later render its budget). E1 `throw10` (throws
`"boom at ten"` at frame 10): frame 9 names no `throw10` and draws RED;
frame 10's reply names it, `frame 10` and the message, and the picture is
the error card — (1,540) its border (230,40,40), (1900,1060) its fill
(64,8,8); `export` answers an error naming both, and nothing is at the
path. `bar`'s stale-`color` warning from L1 appears in every E reply and is
right (G-4). E2 `spin` (`while(true){}`): `render_frame` returns within 3 s
naming the budget, and `get_project` answers within 5 s. E3 `nofont`: the
reply names `Nope Sans` and the set's `IBM Plex Mono`. E4 a fresh project's
`pin.js` clip exported `prores_4444` over MCP is RED at 2 s — the `export`
tool passes the document's set, since an unpinned offline key slates. **No
MCP row can race a module swap**: the server is one thread and `export`
holds it until the file is written, so the swap is made deterministic
in-process instead. Q1–Q3 are `graphics_pin_probe.swift`, built like
`phase7_chrome.py`'s probe (every `app/Sources` file but `main.swift`, the
harness's swiftc line, `Fonts`, `Blank.mp4` and a `default.metallib`
beside it, cached in `work/graphics-pin-probe/`; a probe that will not
build is three FAILURES) over the saved project PQ: Q1 a job ENQUEUED with
the document's set, then the canvas turned blue and the document's set
REMOVED (`stopGraphicStore()`) before the run loop spins — the file is RED
at (480,540) and BLACK at (1440,540), and the CONTROL with no set is the
slate; Q2 the same through `Exporter.export`; Q3 one `LayerRenderers` asked
twice for `nofont` warns both times and the second answer is the pool's
texture. ffmpeg's rawvideo is read through `subprocess.run(timeout=120)`.

**Made to fail by hand (2026-09-25).** (a) `finish`'s mapping line deleted:
E1 fell alone — the export answered "The export was cancelled." instead of
naming the graphic (20/21). (b) the `pin` line in `Exporter.export`
deleted: E4, Q1 and Q2 fell, with the pixel the slate's (25,28,33) — and
A1 (the slate is opaque) and E1 (the export succeeded, a slate in place of
the card) with them (16/21). Each was reverted and rebuilt.

```sh
make app && python3 tools/proof/graphics_proof.py --port 4881          # → 21/21
python3 tools/proof/graphics_proof.py --mutant frame-plus-one          # exit 0 = P2 FAILED
```

## Road map 10's G4a — the agent's write/read loop (`graphics_proof.py` G1–G8)

The same script, eight rows more; the score is **29/29**. G6 runs FIRST, on
the fresh launch before any project is open: `graphic_reference {}` is not
an error and its text is `docs/graphics-api.md`, which is also the app's
`Contents/Resources/GraphicsAPI.md` (read beside `--app`). G1–G5 and G7 run
after A1, each call naming its package. G1 on a new WG: `get_graphic {}`
names `<WG>/graphics`, absent, no modules; `write_graphic` of `BROKEN_BAR`
(`bar()` with line 2, its schema, replaced by `export const schema = {
title: ;`) answers `ok: false`, `meta {}`, `schema {}` and an ERROR on line
2 — the engine's lines are the module's own, and the column is never
asserted — with those bytes on disk; `bar()` then answers `ok`, schema keys
title and color (compared sorted: a JSON object has no order), hashlib's
revision, `<WG>/graphics/bar.js`, no clips and "not undoable". G2 `API.md`
and `API.d.ts` in the folder are the docs' bytes, and `get_graphic {}` says
it exists with one module. G3 `add_graphic_clip` succeeds on the FIRST
attempt (a control: no poll), `get_graphic {name: bar}` lists the clip and
the source, and `get_project`'s `graphics` is `[{name, revision, ok,
clips}]`. G4 saved and clean; a blue `bar.js` written answers its own
revision and leaves `unsaved_changes` false (G-3); ONE `render_frame` at
frame 30, no poll, is blue at (170,50) — the registry was current when the
reply left. G5 `{name: "Bad"}` is refused as "is not a module name" (the
core's sentence) and a missing `source` is named. G7 a new NG with a track,
saved: no `graphics/` (the manual never creates it), and `get_graphic {}`
says so. G8, on a fresh instance (K3's pattern), an untitled root from
`get_graphic {}` given only `fonts/Anton-Regular.ttf` and saved to NF: the
font arrives, no `.js` does, and `get_graphic {}` now names `NF/graphics`.
The mutant copy links `docs/` beside `core/`, since the post-build step
copies the reference out of it.

**Made to fail by hand (2026-09-25)**, each reverted and rebuilt: (a) the
`store.rescan()` in `writeGraphic` deleted — G1–G4 fell (25/29), every
write answering "No module named" because the scan had not yet seen the
file; (b) `writeManual()` deleted from `write()` and `ensureFolder()` — G2
fell alone; (c) `holdsContent` counting regular files only — G8 fell alone.

```sh
make app && python3 tools/proof/graphics_proof.py --port 4883          # → 29/29
python3 tools/proof/graphics_proof.py --mutant frame-plus-one          # exit 0 = P2 FAILED
```

## Road map 10's G4b — the contact sheet, the imports, the loop (`graphics_proof.py` C1–C4, I1–I4, G9, L2)

The same script, ten rows more; the score is **39/39**. The sheets are
decoded through ffmpeg (`decode_rgba`) — `decode_png`'s Python loops are too
slow for a 3848 px row — and every pixel claim is an RGB read or a row
comparison of that decode. On WG after G7, where `bar.js` is BLUE since G4
and its clip sits at 0: **C1** `render_graphic {frames: [0, 0], background:
"#000000", max_width: 8192}` is a 3848×1104 PNG whose cell 0 (columns
0–1919) and cell 1 (1928–3847) are byte-identical over rows 0–1079 and whose
text names "2 frame"; `frames: [0, 30]` makes the two cells differ. **C2**
Placement: `render_frame` at frame 30 and `render_graphic {frame: 30,
background: "#000000", max_width: 8192}` agree in every RGB pixel of the
1920×1080 cell — 0 of 2 073 600 differ, F1's comparison. **C3** `{frame: 30,
format: "svg"}` answers ok, frame 30, a rect at `x="120"` and no
diagnostics. **I1** `needsfont` (120 px white text in `'Oswald'`): its sheet
over black has 0 lit pixels and names Oswald; `import_graphic_font
/Library/Fonts/Oswald-Medium.ttf` answers `families ["Oswald"]` — the
engine's name; CoreText's is "Oswald Medium" — with `library_families`
holding Oswald, IBM Plex Mono and Source Sans 3, its path in `fonts/`, not
replaced, and `get_graphic {}`'s `families` the same list; the sheet then
lights pixels and names no Oswald; Arial answers `["Arial"]` and says
`replaced` the second time; a `.ttf` of text is refused "loaded no face" and
a `.txt` naming ".ttf". A missing Oswald file is a FAIL, never a skip.
**I2** `usesasset` (`<image href="${asset("red.png")}">`) names red.png and
is black at (50,50); `import_graphic_asset graphic/tests/assets/red.png`
answers `red.png` and `assets ["red.png"]`, as `get_graphic {}` does; the
sheet is then (255,0,0) there with no red.png in the text; an empty file is
refused "empty" and a `.txt` naming "PNG". **G9** `chmod 311 <WG>/graphics`
(bounded): `write_graphic {name: ghost}` is refused saying it "was written"
and the scan "does not list" it; after `chmod 755` the same write is ok.
**I3** `save_project` on WG: `fonts/Oswald-Medium.ttf`, `fonts/Arial.ttf`
and `assets/red.png` are in the package and `unsaved_changes` is false.
**I4** a new IE whose `graphics/` holds NO module: the Oswald import's
`library_families` holds Oswald at once, and `needsfont` written after it
lights pixels with no warning (since G5b the store posts a library change
even with no module, so the import's own `rescan()` rebuilds the registry's
set; G4b's `catchUpLibrary` is gone, and I4 passing is what proves the post
does its job). **L2** the loop of §5h on a
new LP: `graphic_reference`, BROKEN_BAR (ok false, line 2), `bar()` (ok),
`render_graphic {frames: [0, 15, 30]}` at the DEFAULT `max_width` — its
path read out of "Written to …" — is exactly **2048×1202** and names "3
frame", `add_graphic_clip`, `render_frame` at frame 30 is RED at (122,50),
and `set_graphic {props: {title: "Looped"}}` changes that frame ("Loop"
would not: `bar()` draws the title's LENGTH, and "Jane" is four letters
too). **C4**, in `run_e` after E1 on P1: `render_graphic {name: throw10,
frames: [9, 10], max_width: 8192}` names `"throw10"`, `frame 10` and `boom
at ten`; cell 1 is the card — (1929,540) BORDER, (3828,1060) CARD — and cell
0's (50,50) is RED.

**Made to fail by hand (2026-09-25)**, each reverted and rebuilt: (a) the
module asked for `frame + 1` in `renderGraphic` — C2 (1440 pixels differ),
C3 and C4 fell (36/39); (b) `store.rescan()` deleted from
`importGraphicFont` — I1 and I4 fell (37/39); (c) the extension check
deleted from `importGraphicAsset` — I2 fell alone; (d) `catchUpLibrary`
deleted from `importGraphicFont` — I4 fell alone.

```sh
make app && python3 tools/proof/graphics_proof.py --port 4883          # → 39/39
python3 tools/proof/graphics_proof.py --mutant frame-plus-one          # exit 0 = P2 FAILED
```

## The deployment target, rendered (`target_bump_proof.py`)

W1a, road map 8 §10.4: the macOS 26 bump recompiles `Compositor.metal`
(`project.yml`'s `MTL_LANGUAGE_REVISION: UseDeploymentTarget`), and the
harness compiles only `.swift` and paints a black preview well, so nothing
else here draws through the new `default.metallib`. This script writes one
hand-made package — `A.mov`, a text clip and a shape clip on three tracks,
all live at ticks 0, 900 000 and 1 500 000 — renders those three ticks with
`render_frame` and keeps the PNGs; `compare` renders the same package on
another build and checks each PNG byte for byte, `3/3`. It launches nothing
and kills nothing: `capture` on the CONTROL build's own instance, `compare`
on a fresh instance of the build under test.

```sh
python3 tools/proof/target_bump_proof.py <port> capture tools/proof/work/target-bump   # the control build
python3 tools/proof/target_bump_proof.py <port> compare tools/proof/work/target-bump   # the build under test → 3/3
```

## Word captions, the core (`words_core_proof.py`)

W1b, road map 8 §10.5: format version 9 adds `text.case`, `text.words` and
`text.word_style`, and the core is the one counter, rebaser, snapper and
recipe of them (spec §11 W-1 to W-6). The script is the core's half, so its
rows are placements read back through `get_project`, refusal sentences, a
saved `project.json`'s text, and ONE byte comparison — a CONTROL until W3
(two `render_frame` PNGs a word apart were identical while no renderer read
`word`), INVERTED since W3 (road map 8 §10.7): the same two frames must now
DIFFER, because the active word is drawn. A version-10 package refused "(version 9)";
a page added through `add_text_clip` read back on the 30 fps grid; six calls
the door turns away (W-2's count sentence, a `words[0]` with no `end`,
`active_scale` 2, a reversed word, `set_action_end` naming `text.words`,
`case: "shouting"`) between an undo marker and ONE `undo` that takes the
marker back; a content edit keeping or clearing the words; `split` mid-page
and after a content-switching action; `trim_start`, `trim_end`, `roll`,
`add_transition {align: "before"}`; `paste_attributes` keeping content and
words; `set_canvas fps [24, 1]`; and the save and re-open. The recipe's
`word` / `word_pop` are not reachable over MCP (no tool returns a recipe), so
those rows are `core/tests/words.rs`'s, through the FFI. It launches nothing
and kills nothing: run it on a fresh instance of the build under test.

`--mutant` copies `core/` to a temporary tree (`op_contract_proof.py`'s
pattern), replaces an anchor that must occur exactly once, and runs the one
test that should catch it with a 900 s ceiling; exit 0 means that test
FAILED in the copy. `hash-arm` drops the `word` / `word_pop` inserts from
`text_hash` (`words::a_styled_page_hashes_a_word_apart_differently`);
`trim-rebase` drops `trim_start`'s `rebase_words` call
(`words::trim_start_rebases_the_words_by_its_delta`); `count-check` disables
the count comparison
(`schema_v9::a_count_mismatch_is_an_error_in_the_rules_own_words`).

```sh
python3 tools/proof/words_core_proof.py <port>                       # the build under test → 27/27
python3 tools/proof/words_core_proof.py --mutant hash-arm            # exit 0 = the named test FAILED
python3 tools/proof/words_core_proof.py --mutant trim-rebase
python3 tools/proof/words_core_proof.py --mutant count-check
```

## The on-device engine (`speech_engine_proof.py`, `speech_engine_probe.swift`)

W2, road map 8 §10.6: the on-device engine is `SpeechAnalyzer` +
`SpeechTranscriber` behind the unchanged `Transcriber` path (spec §11 W-8).
The script makes its own fixtures under `work/speech_engine/` —
`pangram.wav` (`say --data-format=LEI16@16000` of `silence2_proof.SPEECH_TEXT`,
23 words), `ten.wav` (the pangram repeated with 0.8 s of zeros until past
600 s) and `silence.wav` (3 s of zeros) — and scores three parts in one run:

- **MCP rows** against the build on the port given (launch a fresh instance
  first; the script launches and kills nothing). `transcribe {engine: apple,
  place: false}` over the pangram holds at least 20 of its 23 words, no cue
  text has a leading, trailing or double space, the result carries no
  `truncated` and no `note`, the project is unchanged and no undo step is
  pushed. `ten.wav` comes back WHOLE: at least 100 cues, the first within
  5 s of the start and the last ending within 5 s of the end, every cue
  ≤ 2 lines × ≤ 42 characters, ≤ 6 s, sorted and a frame apart. `silence.wav`
  answers the exact nothingRecognized sentence; `zz-ZZ` is a misspelling
  listing at least ten tags; and the first of fr-FR, de-DE, ja-JP, ko-KR
  refused as not installed is refused with "not installed" and "a person has
  to install it" in under 5 s, identically twice. No model is downloaded; a
  host with all four installed is a named SKIP.
- **Probe rows**: `speech_engine_probe.swift`, compiled from `app/Sources`
  minus `main.swift` at `-target arm64-apple-macos26.0` with the probe as
  `main.swift` (a probe that will not build is a scored FAILURE). P1 cancels
  a ten-minute run at 300 ms, and again once the analysis has reported
  progress, and expects `.cancelled` within 5 s; P2 reads the two language
  lists (installed ⊆ supported, all BCP-47), `en-US` and `en_US` agreeing in
  `identifier(.bcp47)`, and `AssetInventory.reservedLocales` empty after the
  runs; P3 `defaultLanguage` answering this Mac's own tag over both lists;
  P4 `Transcriber().transcribe` with the first uninstalled supported
  language throwing `.notInstalled` in under 5 s; P5 the sheet's Download
  row, driven by hand — offered for fr-FR, Cancel shown but disabled while
  the download waits for its request's `Progress`, both popups locked and
  the label naming French mid-download with en-US selected, and after
  `downloadFinished(.success(()))` the popups back and fr-FR still selected
  (nothing is ever downloaded); P6 `SpeechEngine.transcribe` over the pangram,
  every run trimmed; P7 over `ten.wav`, at least 1 000 runs and the last
  ending within 5 s of the end. P8, run last because every row above goes
  through `SpeechEngine.gate`, holds that gate for 90 s from a detached task
  and expects `SpeechEngine.transcribe` over the pangram to answer at least
  20 of its words in under 30 s regardless (a SKIP where en-US is not
  installed).
- **Mutants**: six tree copies under `work/speech_engine/mutants/`, one
  once-only anchor each, the probe rebuilt from each; a mutant scores when
  its NAMED row fails. `keep-last-result-only` (P7), `drop-the-trim` (P6),
  `skip-installed-check` (P4), `raw-compare-default` (P3),
  `cancel-live-before-progress` (P5 awaiting progress) and
  `release-before-signal` (P8, which waits out its 60 s bound).

```sh
python3 tools/proof/speech_engine_proof.py <port>                # MCP + probe + mutants
python3 tools/proof/speech_engine_proof.py <port> --no-mutants   # MCP + probe
```

## Road map 8's W3 — the word-caption picture

W3 (road map 8 §10.7) taught the app to decode format version 9's `case`,
`words` and `word_style` and the recipe's `word` / `word_pop`, and to draw a
timed page. Four instruments; each launches nothing and kills nothing, and
the two MCP ones run on a FRESH instance each, with
`grep "Reelcut: " /tmp/reelcut-<port>.log` printing nothing first.

### The reveal toll, rendered (`reveal_toll_proof.py`)

The three reveal routines moved out of `LayerRenderersText.swift` as a pure
move before the fourth routine landed, and `TextProps` / `TextPatch` moved
out of their ledger files. `target_bump_proof.py`'s shape over a
hand-written version-9 640×360 package: a static title, a typewriter, a
word_fade, an OUTLINED word_fade (the partial-alpha transparency layer) and
a two-line line_rise over a backdrop, each 5 s with `in` and `out` of 1 s,
rendered at 0, 0.4, 0.8, 2.0, 4.6 and 4.9 s. `capture` (on the UNCHANGED
build) keeps the six PNGs and exits 0 only if all six differ — a fixture
whose frames were equal would prove nothing was animated; `compare` checks
each byte for byte, `6/6`.

```sh
python3 tools/proof/reveal_toll_proof.py <port> capture tools/proof/work/reveal-toll   # the control build
python3 tools/proof/reveal_toll_proof.py <port> compare tools/proof/work/reveal-toll   # → 6/6
```

### The picture over MCP (`words_picture_proof.py`)

Seven rows, each a byte comparison of two `render_frame` PNGs of a
hand-written version-9 package in `work/words-picture/` (the PNGs are kept
there under stable names), or a sentence off `tools/list`: R1 two frames
+0.20 s and +0.30 s after a word start (after the 0.12 s pop) identical; R2
the frame a frame before a word start differs from the frame at it; R3 a
build page a frame before its first word equals a frame before the clip
(and the page does draw at the word); R4 `case: upper` on "straße ist"
differs from `as_written` and equals "STRASSE IST" typed; R5 the four
bundled faces and `NoSuchFont-Black` give five distinct PNGs; R6 `set_text`'s
patch description names `case (as_written|upper`, `words (one {start, end}`
and `word_style (null or {mode: highlight|build`; R7 an UNTIMED page with a
colour-only `word_style` equals its unstyled twin.

```sh
python3 tools/proof/words_picture_proof.py <port>     # → 7/7
```

### The arithmetic, in a probe (`words_picture_probe.py`, `words_picture_probe.swift`)

The box, the headroom, the ink and the Content write have no caller a
script can reach, so the probe is compiled from `app/Sources` over
`harness/build.sh`'s swiftc line (a probe that will not build is a scored
FAILURE) and registers `app/Resources/Fonts` at `.process` scope. The Swift
side measures and prints one JSON object (kept as
`work/words-picture-probe/answer.json`); the Python side scores P1–P9: P1 the
bitmap is `measuredSize` at every word and pop {0, .3, .58, 1}, four faces ×
1080×1920 and 1920×1080, one line and wrapped, `valign` middle, top and
bottom, at `active_scale` 1.15 and 1.5 with the default pill and — since
W4a — 1.5 with NO pill, plus each of §5h's five word styles in its own
face, case, outline, scale and pill through `CaptionStyle` (204 pages); P2 no ink outside that box, drawn by the
renderer's own `drawWords` into a bitmap two em larger each side; P3 word 1
≠ word 2, a build page inkless at word 0; P4 `laidContent` and the red
active word's extents against the LAID midpoint of "STRASSE IST"; P5 each
face round-trips its PostScript name, is not the fallback, and the file at
`kCTFontURLAttribute` has the pinned sha256; P6 `contentEdit`'s three cases
and `contentOps` (a) (b) (c); P7 the headroom rule; P8 `measuredSize` with
and without `words`; P9 the popped word's red ink is at least 0.95 × 1.5 its
unpopped width. About 575 s, most of it P1/P2's 204 pages, so its bound is
1500 s.

`--mutant` builds from a COPY of `app/Sources` with one anchor asserted to
occur exactly once and exits 0 when at least one row FAILED within 1500 s:
`ignore-word` (drawText's words arm never taken), `drop-headroom` (the
insets without `wordHeadroom`), `skip-case` (`laidContent` is `content`),
`keep-words` (`contentEdit` never clears `words`), `clip-then-scale` (the
active token's midpoint clip set before the pop's CTM, P9) and
`flat-vertical` (the vertical headroom pinned to 0.30 em, P2 at 1.5).

```sh
python3 tools/proof/words_picture_probe.py                        # → 11/11
python3 tools/proof/words_picture_probe.py --mutant ignore-word   # exit 0 = a row FAILED
```

### The inspector's two items, offscreen (`words_picture_chrome.py`)

Through `tools/proof/harness/` at 1440×1600 with `text.content`,
`text.style` and `text.animation` opened: four packages of one text clip,
"TITLE 2026" — already capitals, so switching `case` cannot move a glyph or
the canvas overlay's handles — as written, `case: upper`, with a
colour-only `word_style` and two timed words, and the same with
`words: []`. The CONTROL renders the title twice, identical; then title vs
UPPERCASE, title vs styled (the Reveal rows greyed and the word-style
note) and styled vs untimed (the Content footnote) each differ, with every
changed pixel inside the inspector column (x ≥ 1440 − 304 pt). Run it AFTER
anything that builds the harness, never beside it.

```sh
python3 tools/proof/words_picture_chrome.py           # → 5/5
```

## Road map 8's W4a — generation

W4a (road map 8 §10.9) pages a run's words into width-measured, word-timed
pages in five styles and places them. Two instruments: a probe for the
pager's arithmetic, which no script can reach, and an MCP proof that
launches its OWN instance and its own `assemblyai_fake.py`.

### The pager, in a probe (`word_captions_probe.py`, `word_captions_probe.swift`, `word_captions_support.swift`)

Compiled from `app/Sources` over `harness/build.sh`'s swiftc line with the
two Swift files beside it (a probe that will not build is a scored FAILURE),
the fonts registered at `.process` scope. The fixed list is
`work/words_spike/fixtures/fixtures.json`'s `talk_text` (W0's; present on a
host that ran the spike), one token every 0.3 s from 1.0 s, each spoken for
0.18 s, with one 40-letter compound after the first sentence and every token
from the sixth unpunctuated mid-sentence one on 0.3 s later ("editing |
video", a 0.42 s gap — W4b's fix for W4a's review nit 2) — 117 words —
paged in every word style on 1080×1920 and 1920×1080. The WIDTH checks
measure `LayerRenderers.measuredSize` of `CaptionStyle.textProps` directly,
never `CaptionPages.fits`. P0 every page's shape (one timing per token,
starts non-decreasing, inside the span); P1 every multi-word page within
0.86 of the width; P2 every page closed by width alone would not take its
next word, or is one balance move from such a page, and a page ending `,;:`
is exempt only where `clauseMark`'s own conditions held (at least
`clauseMinimum` of the budget, the page plus m ≤ `clauseWindow` next words
laying where one more did not, and no balance move explaining it), with at
least one such page; P3 no lone word unless
its break was forced, no balance move improves it, or it is at least half
the budget; P4 a lone over-wide word shrinks in 5 % steps to the floor
before it wraps; P5 no two-line page but Karaoke or a wrapped lone word
(`layout(for:).lines.count`); P6 abutment where the gap is under
`breakGap`, under the standard rules AND a hold of 0.1 s (under §8's own
numbers `hold` outlasts `breakGap`, so only the short hold sees the no-blink
rule do anything); P7 the canvases page differently; P8 the first page at
raw start + `lead` per engine; P9 `cues(.subtitles)` equals
`CaptionCues.build`; P11 two abutting spans per engine and style; P12 the
0.42 s gap closes a page in every style and canvas; and P10,
`SpeechEngine` over `speech_engine_proof.make_fixtures()`'s `say` pangram,
paged by gap and punctuation and again with road map 4's two detector
pauses as forced breaks — the row asserts the first breaks at both, and
whether the second changes any page is PRINTED (a host without en-US
installed is a named SKIP). About 70 s.

`--mutant` builds from a COPY of `app/Sources`, each anchor asserted to
occur exactly once, and exits 0 when its NAMED row failed: `width-count`
(`fits` → at most 3 tokens, P2), `drop-balance` (P3), `drop-no-blink` (P6),
`drop-lead` (both leads 0, P8), `drop-span` (the clamp and the last
page's bound removed, P11), W4b's two: `drop-gap` (the `breakGap`
disjunct removed, P12) and `drop-clause` (`clauseMark` never fires, P2), and
the W4b residue's `loosen-clause` (`clauseMark`'s two limits loosened — any
mark, any head — so a short comma head closes a page early; P2, with the
slack printed).

```sh
python3 tools/proof/word_captions_probe.py                          # → 15/15
python3 tools/proof/word_captions_probe.py --mutant drop-span       # exit 0 = P11 FAILED
```

### Generation over MCP (`word_captions_proof.py`)

Launches its own instance on the port given, with `-RCSecretFolder` under
`work/word_captions/`, `-RCAssemblyAIEndpoint` at its own fake and the dummy
key, and kills both by PID. G1 `apple` + `highlight` over `media/speech.mov`
on 1080×1920 — every placed clip Montserrat-Black, `case` upper,
`word_style` highlight, one timing per token; G2 Width off pixels — each
page rendered at `start + frame` with and without the captions (`undo`),
every differing column inside `[0.07 W, 0.93 W]`; G3 the cloud engine over
the fake's five words — `subtitles` with `place: false` gives the pinned
cue, `highlight` answers from the cache with `words`; G4 `pill` with
`replace: true` replaces exactly the old track and NOT an empty "Captions 2"
track added beside it (W4a's review nit 1), one `undo` restores it whole
and `redo` swaps back; G5 three refusals by name, the `place` one matched
on "when place is true" (nit 4: "place" is a substring of "replace"); G6 `apple` +
`one_word` over the `say` pangram; G7 `tools/list`; G8 `speech.mov` split
at its midpoint, then `highlight` — no `trimmed`, no `skipped`, every page
inside one clip — and `pill` with `replace: true`. Then `grep "Reelcut: "`
on its log.

```sh
env -u RC_ASSEMBLYAI_KEY python3 tools/proof/word_captions_proof.py 4891   # → 19/19
```


## Road map 8's W4b — the sheet (`word_captions_chrome.py`, `word_captions_sheet_probe.swift`)

W4b (road map 8 §10.10) gave File ▸ Generate Captions… its Style popup, the
preview and the Replace checkbox. A sheet cannot be put up offscreen, so the
card is proved two ways by ONE script, run AFTER anything that builds the
harness, never beside it.

**Photographs**, through the harness's `transcribe` target (above), over
three v9 packages the script writes under `work/chrome-words-sheet/` — one
audio media on `media/speech.aiff` (the file must exist: `mediaURL(for:)`
drops a missing one) and one clip on it: `tall` 1080×1920, `wide`
1920×1080, and `track`, `tall` plus a "Captions" track holding one text clip
over the clip. Rows: the harness builds; every render wrote a PNG; CONTROL —
`tall`, Subtitles, light, twice, byte-identical; the six styles six distinct
PNGs in each appearance; each style light ≠ dark; Highlight 9:16 ≠ 16:9;
`track` with Replace checked ≠ `tall` with Replace asked for (disabled, so
off).

**Structure**, through `word_captions_sheet_probe.swift` compiled over
`app/Sources` with `harness/build.sh`'s swiftc line and
`word_captions_sheet_support.swift` beside it (the fixture, the builders,
S8's readers and `MemoryDefaults`, moved out so the probe stays under 400
lines; a probe that will not build is a scored FAILURE), every sheet over its
own `MemoryDefaults`: S1
the popup's six rows in `CaptionStyle.allCases` order, opening on Subtitles;
S2 six byte-distinct previews on 1080×1920, Highlight's differing between
the two canvases, the sample page's token counts (the width closes
Highlight at 4 on 1080 wide, §5h, and the balance step leaves 3; all 5 on
1920 wide), Karaoke previewed as written (its `textBitmap` differs from the
same props in capitals) and Highlight upper; S3 Replace disabled with no
caption track, with an EMPTY "Captions" track, with Subtitles, and over a
"Captions" track holding a media clip — enabled over one text clip, the
label reading `Replaces “Captions” (1 caption).`; S4 the remembered style
(Pill written, a second sheet opens on Pill, "bold" opens on Subtitles); S5
`finish` with Pill and Replace — one caption track of Montserrat-ExtraBold,
upper, `active_pill` pages, the old track gone, one undo restores it
(the sheet presented from a host with a no-op animator, so `finish`'s
`dismiss` has something to dismiss); S6 the preview's words — the fixed
sample with no transcript (the miss cached), a transcript's own words when
one is written before the sheet (a different preview), the fixed sample and
the no-file preview byte for byte when the transcript has no word in the
clip; S7 `replaceExisting` false whenever the checkbox is disabled; S8 a
shrunk page is ONE page — a lone Highlight word from a ladder that shrinks
without wrapping ("Straightforward", 68.85 of 81) has its preview props,
its committed props (less `words`) and `CaptionStyle.textProps` at its own
size all equal, its committed outline 0.08 × its own size, and it measures
and draws (`textBitmap`) inside the 928.8 px budget where the same text at
the base size does not; the same three-way equality for a word wrapped at
the floor (64.8, `width` the budget); and Subtitles' preview props equal to
its committed props whole; S9 the preview is drawn 0 times across five
`refresh()`es and a Vocabulary keystroke (the image object is the same —
`preview()` mints a new one per call), and anew on each style change, with
`previewKey` the style, the first job's clip and the canvas.

`--mutant` copies `app/Sources`, asserts each anchor once, runs only the
probe, and exits 0 when its NAMED row failed: `preview-ignores-style` (the
preview drawn from fixed Highlight props, S2), `replace-without-track`
(Replace live for any word style, S3's no-track row), `style-not-remembered`
(`styleChanged` writes nothing, S4) and `replace-empty-track`
(`replaceableTracks` without its at-least-one-clip guard, S3's empty-track
row), and the W4b residue's three: `commit-wider-outline` (`pagePatch`'s
outline 1.25 × the pager's, S8's shrunk row), `preview-base-size` (the
preview measured at the style's size, not the page's, S8's shrunk row) and
`preview-redraws` (the key guard always true, S9). 80 s for the whole script
with the harness already built (its rebuild, when `build.sh` finds it stale,
is about 65 s more), 66 s a mutant. Afterwards `ls ~/Library/Preferences | grep -c
"reelcut.harness.transcribe\|wordsheet-"` prints 0: neither half writes a
defaults suite.

```sh
tools/proof/harness/build.sh --force
python3 tools/proof/word_captions_chrome.py                                 # → 31/31
python3 tools/proof/word_captions_chrome.py --mutant replace-empty-track    # exit 0 = S3 FAILED
```

## Space is the transport's (`space_key_proof.py`, `space_key_probe.swift`)

kpgalligan/reelcut#35, spec §11 K-1: a bare Space toggles play from any
focus but a field being typed into, decided by `EditorWindow.sendEvent`
before dispatch. The probe is compiled AS `main.swift` over `app/Sources`
(`harness/build.sh`'s swiftc line, a build failure is a scored FAILURE) with
the app's `Compositor.metal` built into a `default.metallib` beside it. S1
asks `SpaceKey.route` directly — window, plain view and slider are the
transport's; an editable `NSTextView`, `NSButton`, `NSPopUpButton`,
`NSSegmentedControl`, `CanvasOverlayView` and an attached sheet keep the
key; an auto-repeat is held; ⌘/⌥/⌃ Space, a `j` and a key-up are not
routed; ⇧ and ⇪ are. S2 drives the app's OWN window
(`makeWindowControllers()`) with synthesized events through
`NSWindow.sendEvent` and reads `editor.playback.isPlaying`: (a) from the
window as first responder — the state an inspector field's commit leaves —
Space plays and pauses; (b) a custom view first responder never sees the
key and play toggles; (c) the timecode field types it; (d) the canvas
overlay toggles on key-UP; (e) an `NSButton` first responder is handed the
Space (its `keyDown` sees it once — whether AppKit then presses it depends on
Full Keyboard Access, a host setting, so FKA and the press are printed in the
detail and not scored; #48 is the press's
hands-on check); (f) an auto-repeat is
swallowed; (g) the window is an `EditorWindow`; (h) (road map 12 A2) the
Assistant tab's composer, shown by `showAssistant` — View ▸ Assistant's own
method — and first responder, types the Space and play stays paused. For (h)
the probe runs with a DUMMY key in a `-RCSecretFolder` of its own (so the
composer shows), `-ReelcutInspectorCollapsed NO`, and `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY` popped from its environment. The beep is not observable;
(a) and (b) together are the claim that the window returned before
`super.sendEvent`.

The package is the grey card at 0–6 s plus 6 s of `media/A.mov` after it:
over a shape-only plan `Playback` has no item and `play()` refuses, so a
media track is what lets the transport move. Needs `media/A.mov` (a scored
row when missing), no ffmpeg.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` (S1, S2g and S2h compiled out)
in `work/space-key/baseline/`, and exits 0 only when EXACTLY S2a and S2b fail
there and no S1, S2g or S2h row is present. Measured 2026-09-24: 28/28 on the
fix; `--baseline b69972e` fails exactly S2a and S2b and exits 0. Measured
2026-09-27 with S2h (road map 12 A2): 29/29, and the baseline still exactly
S2a and S2b. Road map 2 §2 Phase 8's #35 record says why
S2e scores the hand-off rather than the press.

```sh
python3 tools/proof/space_key_proof.py                      # → 29/29
python3 tools/proof/space_key_proof.py --baseline b69972e   # exit 0 = exactly S2a, S2b FAIL
```

## The text editor grows as you type (`text_edit_proof.py`, `text_edit_probe.swift`)

kpgalligan/reelcut#36: the in-canvas text editor is sized, after every
change, to the box the typed string will have once applied. The probe is
compiled AS `main.swift` over `app/Sources` (`harness/build.sh`'s swiftc
line, a build failure is a scored FAILURE) with the app's `Compositor.metal`
built into a `default.metallib` beside it, and registers
`app/Resources/Fonts` itself — a bare binary has no bundle, and without the
fonts the editor and CoreText fall back to different faces (T0 is that
CONTROL). In the app's own window it opens the editor over a text clip with
`beginTextEditing`, puts the caret at the end and types one key event at a
time through `NSWindow.sendEvent`, recording the editor's frame and its
laid-out line count after each; it then cancels, APPLIES each typed prefix
through the canvas's `onEdit` (the `set_text` a commit sends), and compares
with the box the canvas draws, grown by the editor's 2 canvas-pixel margin,
within 1 pt per edge, and with CoreText's line count for the applied text
(`LayerRenderers.layout(for:)`). T1 is an auto-sized centred text, T2 a
700 px fixed-width left-aligned one on a 24 px backdrop. Each group has
three CONTROLS (every key typed, every prefix applied, the applied box
moved) and the two rows of the fix. T3 opens the editor over a 12 px
left-aligned "Hi" whose box is under the editor's 60 × 24 pt floor (a
CONTROL) and checks the frame hangs from the box's top-left, within 1 pt —
it passes on the baseline too, and fails if the floor is widened about the
box's centre. No media, no ffmpeg.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` (nothing compiled out) in
`work/text-edit/baseline/`, and exits 0 only when EXACTLY the four fix rows
fail there. Measured 2026-09-24: 15/15 on the fix; `--baseline b76a2f3`
fails exactly those four and exits 0. Road map 2 §2 Phase 4's #36 record
has the numbers.

```sh
python3 tools/proof/text_edit_proof.py                      # → 15/15
python3 tools/proof/text_edit_proof.py --baseline b76a2f3   # exit 0 = exactly the four fix rows FAIL
```

## Return applies in the canvas text editor (`text_apply_proof.py`, `text_apply_probe.swift`)

kpgalligan/reelcut#37 (spec §11 K-2): in the in-canvas text editor a bare
Return applies, a Return with ⇧, ⌘, ⌥ or ⌃ is a new line, and Esc on a
changed string asks Cancel / Revert / Apply in a sheet. The probe is
compiled AS `main.swift` over `app/Sources` (`harness/build.sh`'s swiftc
line, a build failure is a scored FAILURE) with the app's `Compositor.metal`
built into a `default.metallib` beside it. K1 asks `TextEditKey.route` row
by row (pure). A0–A11 open the app's own window over one text clip "Hello"
(`text_edit_proof.text_clip`), each row its own `beginTextEditing` session
with the caret at the end, send the keys through `NSWindow.sendEvent`, and
read the clip's content, whether a `CanvasTextView` is still in the tree,
`window.attachedSheet` and `document.undoManager` back; between rows the
probe ends any sheet, cancels the editor and undoes every step. A0 and A7
are CONTROLS. The sheet never becomes key under `.prohibited`, so its
buttons are pressed with `performClick`, and which one Return and Esc press
is READ: Apply as the panel's `defaultButtonCell` (macOS 26's `NSAlert`
leaves the first button's own `keyEquivalent` empty — measured), Cancel by
its `keyEquivalent`. No fonts, no media, no ffmpeg.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` (K1 compiled out) in
`work/text-apply/baseline/`, and exits 0 only when EXACTLY the labels in
`BASELINE_EXPECTED` fail there and no K1 row is present. Measured
2026-09-24: 27/27 on the fix; `--baseline 7e946ed` fails exactly A1, A2,
A4, A6, A8, A9, A10 and A11 (A3's ⇧Return and A5's ⌥Return already put a
"\n" there) and exits 0. Road map 2 §2 Phase 4's #37 record has the
details.

```sh
python3 tools/proof/text_apply_proof.py                      # → 27/27
python3 tools/proof/text_apply_proof.py --baseline 7e946ed   # exit 0 = exactly A1 A2 A4 A6 A8–A11 FAIL
```

## Road map 10 — the person's playback-check projects (`graphics_playback_samples.py`)

Not a proof: it BUILDS the three projects #56's "Graphics playing,
WATCHED" check asks a person to play, through the
built app's MCP tools (its own instance on port 4891, killed after), into
`tools/proof/work/playback-check/` (ignored by git):
- `Playback-1080p.reelcut` — 1920×1080 at 30 fps: `lower-third` (0–5 s),
  then `kinetic-type` (5–10 s);
- `Playback-4K.reelcut` — 3840×2160 at 30 fps: `title-card` (0–4 s), then
  `kinetic-type` (4–9 s), for the stutter and Activity Monitor memory rows;
- `Error-card.reelcut` — a small module that throws from frame 60, so the
  error card shows from 2 s.

Run `python3 tools/proof/graphics_playback_samples.py` after `make app`;
it replaces the three packages. Built 2026-09-25 at `0ade58c`, with a
`render_frame` of each confirmed by eye.

## Road map 10's G5a — the Graphic sub-tab (`graphics_inspector_proof.py`, `graphics_inspector_probe.swift`)

One script with three instruments (road map 10 §10.9 G5a; spec §11 G-15):

- **The fixture, over MCP.** One owned instance on its own port (default
  4887; its log is `work/graphics-inspector/reelcut-<port>.log`) runs
  `new_project`, `write_graphic six` (one schema entry of each type: a
  string whose default holds `{"}:`, a number 12–200, an unbounded number, a
  boolean, a colour defaulting to "#FF5A36", an enum and an asset; text drawn
  in `'Nope Sans'`), `import_graphic_asset red.png`, `add_graphic_clip`,
  `set_graphic {props: {size: 90}}` and `save_project`. The instance is then
  stopped, and `"old": 1` and `"zzz": 2` are written into the clip's props in
  `project.json`: the external edit G-4 tolerates, which the tool refuses.
- **The probe** is compiled as `main.swift` over `app/Sources` on
  `harness/build.sh`'s swiftc line, with `app/Resources/Fonts` copied beside
  it. It runs over a COPY of the fixture and scores rows I1–I12. These cover
  the module's key order, one row per type, Reset against the default, the
  colour arithmetic and the null rule, stale keys and ⌫, the structure
  signature, the tabs and section ids, the first-frame report, the tool's
  edit read back, Fit to Canvas, `sourceSize(of:)` and the graphic's own In
  point after a trim. A probe that will not build is a scored FAILURE. The
  readout's text and the popup's items are private, so the probe reads them
  by `Mirror`. Nothing in the app is widened for it.
- **The harness** (`harness/build.sh`) renders the fixture at 1440 × 1500
  with the subTab set to `graphic` and the four sections expanded. It renders
  light twice (H1) and dark twice (H2). Each pair must be byte-identical, and
  light must differ from dark. The PNGs are kept as
  `work/graphics-inspector/gi-{light,dark}-{a,b}.png`, for a person to LOOK
  at. The harness now starts the document's graphic store
  (`startGraphicStore()`, under `#if !HARNESS_REFERENCE_BUILD`). Without that
  call a graphic clip's sub-tab has no schema.

```sh
make app
python3 tools/proof/graphics_inspector_proof.py --port 4887    # → 50/50
python3 tools/proof/graphics_inspector_proof.py --mutant stale # exit 0 = the five I5 rows FAIL alone
```

The mutant builds the probe over a copy of `app/Sources` whose
`GraphicSchemaRows.staleKeys` returns `[]`. It makes a fresh fixture in a
temporary directory. The one I5 row it cannot touch is the compile row
naming line 2, so that row is not expected to fail.

## Road map 10's G5b — the graphics menus and templates (`graphics_menu_proof.py`, `graphics_menu_probe.swift`; `graphics_proof.py` W1)

Road map 10 §10.9 G5b; spec §11 G-16. Two instruments and one row:

- **R1, the bundle.** The built app's `Contents/Resources/GraphicTemplates/`
  holds exactly the six modules of `graphic/tests/graphics/`, byte-equal
  (project.yml's "Copy Graphic Templates" script).
- **The fixture, over MCP.** One owned instance on its own port (default
  4889; its log is `work/graphics-menu/reelcut-<port>.log`) runs
  `new_project {path: GM}` and `save_project`: a package with NO module.
- **The probe** is compiled as `main.swift` over `app/Sources` on
  `harness/build.sh`'s swiftc line, with `app/Resources/Fonts`,
  `GraphicTemplates/` (from `graphic/tests/graphics/`) and `GraphicsAPI.md`
  (from `docs/graphics-api.md`) copied beside it — its `resourceURL`, where
  the app finds all three. It runs over two COPIES of GM and scores M1–M10:
  the probe builds (M1, a scored failure otherwise); the menu bar's Insert
  right after Edit and its Graphic submenu, each template's URL byte-equal
  to its source (M2); File's two items after Consolidate Media…, Help's
  Graphics Reference, no key equivalent on the ten new items (M3); no
  target for the four editor selectors with no window, and Graphics
  Reference live until the copied `GraphicsAPI.md` is moved away, a CONTROL
  (M4); the four validate false before `startGraphicStore()` and true after
  (M5); the Lower Third item at 2 s — the file byte-equal, one clip at
  1 200 000 lasting 3 000 000, "Insert Graphic", level 0 after a run-loop
  turn, one undo removes it and the file stays (M6); again → `lower-third-2`
  (M7); `insertGraphic(from: "My Counter (v2).js", grouped: true)` →
  `my-counter-v2`, level 0 at once, one undo removes it and `lower-third-2`
  STAYS (M8); a module that does not compile throws naming it and places
  nothing (M9); `importFont` / `importAsset` on the second copy, the
  registry's library holding Oswald at once, the refusals naming ".ttf" and
  "PNG" (M10). **The probe never calls `endUndoGrouping`**: a command run
  outside an AppKit event opens the implicit event group, and the probe
  closes it the way AppKit does, a run-loop turn in `.default` mode
  (`text_apply_probe.swift`'s `spin`).
- **W1, in `graphics_proof.py`** (after I4): a new module-less IW; its
  families lack Oswald (CONTROL); from the SHELL `mkdir -p IW/graphics/fonts`
  and `cp` Oswald in; `get_graphic {}` polled for at most 5 s until its
  families hold Oswald; `write_graphic needsfont` then lights pixels naming
  no Oswald — the watcher's own post, no tool in the path.

**Made to fail by hand (2026-09-25)**, each reverted: (a) `|| outcome.library`
removed from `GraphicStore.drain()` (app rebuilt) — `graphics_proof.py` fell
to 38/40, I4 and W1 alone; (b) From File… dropped from `graphicMenu()` — M2
fell alone (13/14); (c) M7's run-loop turn removed from the probe — M7's own
level check and M8 fell (12/14): with the implicit group still open, M8's
grouped edit nested inside it and one undo took `lower-third-2` too.

```sh
make app
python3 tools/proof/graphics_menu_proof.py --port 4889    # → 14/14
python3 tools/proof/graphics_proof.py --port 4883         # → 40/40
```

## Road map 11's V0 — the dev tools are absent from Distribution (`dist_check.py`)

`make dist` builds the Distribution configuration — Release without the
Swift condition `REELCUT_DEV_TOOLS` (spec §11 V-1) — into
`build/Build/Products/Distribution/`, beside Release's product and never in
it, then runs this check, and a failure fails `make`. The script reads each
app's `Contents/MacOS/Reelcut` in process, as bytes, with the stdlib only,
and prints the needle and both paths before its rows:

- **D1** — the needle is read from `app/Sources/AgentServer+DevTools.swift`:
  exactly one BARE `static let devToolsMarker = "…"` line (a trailing `//`
  comment fails it), ASCII, at least 16 UTF-8 bytes;
- **D2** — the Release binary exists; **D3** — the Distribution binary exists;
- **D4** — the Release binary holds the needle: the POSITIVE CONTROL, without
  which an absence check passes against a build that never had the tools;
- **D5** — the Distribution binary does not hold the needle;
- **D6–D13** — each bundle's assistant helper: present, signed with the
  hardened runtime, entitlements exactly `allow-jit`, no needle (road map
  12's A4, the last section of this file).

No row is ever skipped: if D1 fails, D4, D5, D12 and D13 FAIL too, and so
does each when its binary or helper is missing. The last line is
`dist_check: <passed>/13`; the exit is 0 only at 13/13.
`dist_check_mutants.py` makes each helper row fail on purpose; the last
section of this file has its cases.

**Why a marker and not the tool names.** Swift string literals of 15 UTF-8
bytes or fewer are stored inline in the code of an `-O` binary, not as
contiguous bytes: measured on the Release binary with
`LC_ALL=C grep -c -a -F`, `RC_AGENT_PORT` (13 bytes) and `unsaved_changes`
(15) are found 0 times, `AgentServerEnabled` (18) once. A name like
`snapshot_ui` (11) could never be a needle. The marker is kept live in the
optimised binary by the log line the flag-on `devTools()` writes, so a dev
tool added to the seam needs no edit here.

```sh
make dist                                                  # → dist_check: 13/13
python3 tools/proof/dist_check.py [--release APP] [--dist APP]
```

**Made to fail by hand (2026-09-26, when there were five rows)**, each
reverted and the seam file `cmp`-identical afterwards: `--release` pointed at the Distribution app — D4
FAIL (4/5); `--dist` at the Release app — D5 FAIL (4/5); `--release` at a
missing path — D2 and D4 FAIL (3/5); `--dist` at a missing path — D3 and D5
FAIL (3/5); a trailing `// note` on the marker line, a 12-byte marker, and a
second declaration line — each D1, D4 and D5 FAIL (2/5). Each exits 1. And
the build mutant: `Distribution: {SWIFT_ACTIVE_COMPILATION_CONDITIONS:
REELCUT_DEV_TOOLS}` added under the target's `settings.configs` in
`project.yml` — `make dist` exits 2 with D5 FAIL (the marker once in the
Distribution binary); with `project.yml` restored, 5/5 again.

## Road map 11's V1 — the capture spike (`capture_spike/`)

The spike behind V2's `snapshot_ui` and `perform_menu_item`: the preview well
of a live editor under `cacheDisplay` and three ways of putting a still under
the canvas overlay (q1), a sheet put up by a menu item and the inventory of
which menu items reach a sheet, a window or a modal run loop (q2), switching a
live window's appearance (q3), and `hasAmbiguousLayout` plus the truncation
heuristic in an `-O` build (q4). A probe built from `app/Sources` with
`-O -wmo -D REELCUT_DEV_TOOLS`, six bounded modes, 38 scored rows, a digest.
Its README has the rows, the build line and the output; the answers are in
`archive/reelcut-roadmap-11.md`'s V1 record (condensed in
`designs/adr/roadmap-11-dev-tools.md`). The W, S and A rows need the
probe's window on screen and the probe active — run it with the terminal
frontmost and the display on; otherwise they skip by name. W4a–c's answer
depends on the display scale (the recorded digest is scale 2's; on a scale-1
screen W4a–c pass): the probe puts its windows on a scale-2 (built-in)
screen when one exists, and without one W4a–c skip as
`host: no scale-2 screen`. Since road map 11's V2b the inventory's site grep
(`capture_spike/inventory.py`) also counts the APP-MODAL `presentError(` —
`presentError(_:)` and `NSApp.presentError(_:)`, not the sheet form
`presentError(_:modalFor:…)` — as a loop token.

```sh
python3 tools/proof/capture_spike/capture_spike.py [--only q1,q2,q3,q4] [--rebuild]
```

## Road map 11's V2a — `snapshot_ui` (`v2_snapshot.py`, `v2_layout_probe.swift`, `v2_cover.swift`)

The phase proof of the first dev tool, `snapshot_ui`, over `mcp.py`. It
runs against the Release app launched fresh on its port with the pinned
defaults the V2a spec's Verification lists (`-ReelcutInspectorWidth 304
-ReelcutTimelineHeight 300 -ReelcutInspectorCollapsed NO
-ReelcutSafeGuidesVisible NO -ReelcutTimelineTrackHeight 1
-ReelcutInspectorSection.text.animation '<false/>'`). Before the first MCP
call it:
- writes two fixtures, `work/v2_snapshot/fixtures/{v2well,note}.reelcut`:
  V1's magenta-canvas well with a second shape at 3–6 s, and V1's note;
- builds `v2_layout_probe.swift` over `harness/build.sh`'s swiftc line;
- builds `v2_cover.swift`, a standalone opaque non-activating panel.

A build failure is a scored FAIL of the rows that need it.

The 30 rows:
- **T**: the schema, the parity log and the dev-tool marker, and the gate.
- **N**: the listing.
- **O**: occlusion, under the cover. The captures are byte-identical
  covered, uncovered and across a `set_selection`, and O5 checks that the
  app was inactive.
- **C**: capture bytes, the image block, region sizes, the refusals, and
  Welcome/Settings.
- **F**: the preview fill.
  - F0 samples the well's centre, covered.
  - F2: the overlay's marks kept under the picture.
  - F3: the fill removed. It compares against the run's first capture,
    taken before any fill.
  - F4: `no_frame`.
- **A**: `appearance` refused, whatever its value, naming `-RCDevAppearance`
  (since V3: a live switch left build-time colours in the launch look). A1: both
  looks refused and no file written; A2: the captures before and after the
  refusals byte-identical. Mutant (V3): the refusal line removed fails A1 and
  C4 (its two `appearance` cases) and nothing else of T, C, A.
- **L**: the layout dump.
  - **L2 compares `problems` to `KNOWN`**, the filed defects listed as data
    in the script. It fails on a problem not listed AND on a listed defect
    that no longer appears. `KNOWN` is empty, so L2 expects no problem: its
    one entry, the toolbar's duration label, was the label's 2 pt alignment
    inset, and with the rule on alignment rects L2 failed `#129 MISSING`
    until it was removed (2026-09-29).
  - **L3 is #70's regression row**: the Reveal section's word-style note
    (`TextPane.wordStyleNote`) on a word-styled page must fit its row
    (intrinsic ≤ frame + 0.5 pt) with no `truncated` problem naming it; not in
    the dump fails, hidden skips as `host: Reveal collapsed`. It FAILED against
    the old sentence (2026-09-29: intrinsic 289.5 vs frame 271, truncated
    problem listed) and passes with the new one at 304 pt (194.5 vs 271) and
    at 280 pt (194.5 vs 247).
- **P1–P7**: the three rules and their controls, put to synthetic trees by
  the probe. P7: `outside_superview` measures the ALIGNMENT rect — a label
  pinned flush to its container, whose frame passes it by the inset, has no
  problem, and a label whose alignment rect is 10 pt past its container is
  flagged `[0, 0, 10, 0]`. It FAILED against the frame rule (the flush label
  flagged, the other `[0, 0, 12, 0]`) before the rule changed.

Output is one line per row, then `scores:` and `digest:`. Exit 0 iff no row
failed.

**The cover** is at floating level over the editor window's frame. It is up
for about a second per episode, twice a run, and each episode is bounded at
60 s. Keep the pointer off the Reelcut window while this runs.

**Named host skips:**
- a locked console skips the O rows and F0;
- O2 skips as `host: editor occluded without the cover` when the person's
  windows cover the editor both before and after the episode;
- any comparison whose `scale`, `active`, `key` or `color_space` differ.

**Colour management.** Captures are in the window's colour space. F0's
yellow bound is B < 100 because the built-in Display P3 screen gives the
fixture's sRGB yellow as [255, 255, 84].

```sh
python3 tools/proof/v2_snapshot.py <port> [--log PATH] [--only T,N,O,C,F,A,L,P]
```

`dev_tools.py` names the dev tools once (`DEV_TOOLS`, in catalog order: the
four of road map 11, then road map 12 A1's `assistant_send` and
`assistant_answer`) and reads the startup marker's count
(`dev_marker_count`). The scripts that assert an exact tool set subtract
`DEV_TOOLS` first.

## Road map 11's V2b — `perform_menu_item` and `cancel_sheet` (`v2_menu.py`, `v2_menu_probe.swift`)

The phase proof of the second and third dev tools, over `mcp.py`. It runs
against the Release app launched fresh on its port with V2a's pinned defaults
plus `-RCSecretFolder "$PWD/tools/proof/work/v2_menu/secrets"` (the Settings
window it opens then reads no real key store) and `-RCSpendFolder
"$PWD/tools/proof/work/v2_menu/spend"` (its month line then reads no real
spend ledger, spec §11 P-5; road map 13 P4). Before the first MCP call it:
- writes three fixtures, `work/v2_menu/fixtures/menu_{a,b}.reelcut` (version
  10, 640×360 at 30 fps, one track, a shape at 0 s and one at 3 s) and
  `menu_late.reelcut` (the first shape only), and deletes `fixtures/late.mov`;
  B is opened, then A, so A is the front project;
- for the H rows, builds `v2_menu_probe.swift` over `harness/build.sh`'s swiftc
  line into `work/v2_menu/probe/`, with `graphic/tests/graphics/*.js` copied to
  `GraphicTemplates/` beside it so Insert ▸ Graphic has its template items;
- for the D rows, builds `v2_snapshot.py`'s cover (`v2_cover.swift`).

A build failure is a scored FAIL of the rows that need it; a call that throws
where a row expected an answer fails the rest of that letter's rows by name.

The 27 rows:
- **T**: both schemas (`{path, project}` and `{project}`, nothing required,
  no `scope`), the parity log, the marker count, and the gate on each tool.
- **H**: the probe walks `AppDelegate().buildMainMenu()` with
  `UIMenu.leaves(of:)` and prints each leaf's refusal and the whole
  `UIMenu.verdicts`. H1 puts its leaves to `inventory.check` (0 problems);
  H2 holds the table to `inventory.json` both ways; H3 holds each leaf's
  refusal to the table's verdict; H4 is the control — a fake leaf and a
  removed table row are each reported exactly. H5 (#133): two items share an
  action in a menu of the probe's own, one targeting an object that answers
  it and one an object that does not; `UIMenu.target` answers nil for the
  second (disabled, no fallback to the chain) and the object for the first.
  It FAILED before the change (the silent item's target was the silent
  object, enabled true).
- **N**: the live listing: an inventoried selector carries its verdict and
  refusal, every other one is `unclassified` (AppKit's injected items, printed
  as `selector ×count`), and every inventoried selector is live.
- **D**: delivery with Reelcut inactive and B covered — the cover over B, then
  Add Marker to B and to the implicit (front) project, Export… on B captured
  through `snapshot_ui window: sheet` and cancelled, and Settings… opened and
  captured. Each answer must read `active: false`.
- **U**: U1, two performed Add Markers are two undo steps. U2 (#167): Add
  Marker at 2.5 s, then `undo` (`undone: "Add Marker"`, `can_redo: true`);
  View ▸ Zoom In, then `redo` must answer `redone: "Add Marker"` with the
  marker back; View ▸ Zoom Out, then `undo` must answer `undone: "Add
  Marker"` with it gone. A refused `redo` fails the row with its text. It
  FAILED before the change ("There is nothing to redo"): the eager group an
  item that registers nothing still closed was a step, and cleared redo.
- **R**: the refusals — `undo:` (`framework`; its path read from the listing,
  since its validator retitles it "Undo Add Marker"), `newProject:`
  (`modal`), a disabled item, an unknown item and menu, a submenu, an empty
  path, and a Window-menu window item (`unclassified`).
- **S**: Export…, Remove Track and Add Media… on A, each opened, captured (the
  file panel refused by `snapshot_ui`) and cancelled with nothing changed;
  `cancel_sheet` with no sheet refused; and every answer of the run settled
  inside the 3 s bound with no modal window.
- **L1** (#135), last: the late sheet. On `menu_late.reelcut` it adds a 2 s
  video media at `late.mov` (missing), a clip of it at 6 s, and reverses the
  clip — a missing file makes no reverse job, so no sheet (checked). It then
  writes `late.mov` as non-movie bytes and performs Add Marker: the edit's
  `ensureReversedMedia` puts the reverse progress sheet up a run-loop turn
  AFTER the action returns, and the failed render keeps it up with Close. It
  passes when `sheet_at_return` is false, `sheet` is not null, the settle
  settled, the markers went +1 and the sheet's layout shows a visible
  "Reversing"; `cancel_sheet` then closes it (at most three calls). Its
  mutant does NOT fail it: with `settleAfter` returning at once (settled, 0
  ms), L1 still passed, because the answer's later main-thread hop already
  runs after the sheet's `DispatchQueue.main.async`.

It performs only Add Marker, Export…, Remove Track, Add Media… (the last three
cancelled), Settings…, and View ▸ Zoom In and Zoom Out (U2), and never Quit,
Close, Save, Revert, Allow Agent Connections, New Recording or a Help item.

**The cover** is up once a run, over B's frame, for about two seconds.
**Named host skips:** Reelcut active skips every D row as `host: Reelcut
active`, a locked console as `host: console locked`; R6 skips as `host: no
window-list item` when AppKit put no window in the Window menu.

```sh
python3 tools/proof/v2_menu.py <port> [--log PATH] [--only T,H,N,D,U,R,S,L]
```

## Road map 11's V3 — the screen catalog (`screens.py`)

The catalog's runner, over `mcp.py`, dependency-free. It walks every screen
file in `designs/screens/` (the format is that folder's `README.md`), drives
its OWN Release instance into each screen over MCP and the dev tools, captures
it light and dark through `snapshot_ui`, and writes `screens.md` — each
picture beside its prose and its layout problems — ready to attach to a design
request.

```sh
python3 tools/proof/screens.py [--port 4871] [--app build/Build/Products/Release/Reelcut.app] \
    [--screens designs/screens] [--out tools/proof/work/screens/<YYYY-MM-DD-HHMMSS>] \
    [--only ID,…] [--compare EARLIER_OUT]
```

**The launch** (`screens.launch`, which `v3_tools.py` shares): the app's
binary with `-ApplePersistenceIgnoreState YES -AgentServerEnabled YES
-RCSecretFolder <out>/../secrets -RCSpendFolder <out>/../spend
-RCAssemblyAIEndpoint http://127.0.0.1:9 -NSRecentDocumentsLimit 0` and every
`PINS` pair — the spend folder removed before each launch and never created,
so Settings' month line is an empty month and the person's ledger is never
read (spec §11 P-5, P-7); the environment without
`RC_ASSEMBLYAI_KEY` and with `RC_AGENT_PORT`; stdin closed, stdout and stderr
to `<out>/app.<look>.log` (`app.log` without a look), its own session; the port
read from the log's `listening on` line. `stop()` terminates that pid and kills
it after 10 s; nothing else is ever signalled.

**One instance per look.** The walk runs twice, each time on a fresh instance:
first launched with `-RCDevAppearance light`, then with `-RCDevAppearance
dark` — a dev-only launch default (`DevAppearance.swift`) that sets
`NSApp.appearance` before any window is built. `snapshot_ui` is never asked for
an `appearance` (it refuses one): switching a live window left the colours its
views took when they were built in the launch look, so each "light" capture was
a mix the app never draws. Every capture must answer the look its instance was
launched in, or the screen fails. Measured on this (Dark) host, 2026-09-27,
Welcome, the Demo editor, its inspector with the video selected and Settings,
each launch capturing with no `appearance`: `-RCDevAppearance dark` gives all
four byte-identical to a plain launch; `-RCDevAppearance light` gives Welcome,
the inspector and Settings byte-identical to a launch with
`-NSRequiresAquaSystemAppearance YES` (the one launch argument that makes this
process's system look light), and the editor different only in the timeline —
97 786 px, the grey alternate lanes one level apart (140 against 139) and the
vertical scroller's track (233 against 255). On that forced-light system,
`-RCDevAppearance dark` still answers dark, with Welcome, the inspector and
Settings byte-identical to the plain dark launch and the editor different only
in the 17 pt scroller column (4 488 px). `-AppleInterfaceStyle Light` or `Dark`
as a launch argument changes nothing, so no Apple argument gives a dark app on
a light system. A real Light host was not available (the machine's setting was
not changed).

**The pins.** `PINS` is the offscreen harness's `pinDefaults`
(`harness/main.swift:289-395`) minus `AgentServerEnabled`, as launch arguments
(booleans and numbers as plist fragments, `<false/>`, `<real>304</real>`), plus
`ReelcutInspectorSection.<id>` for every section id in `app/Sources`
(`SECTIONS`), each pinned to its FIRST-RUN state: collapsed unless
`defaultExpanded`, except `audio.volume` and `clip.timing`, which
`ClipPane.makeSections()`'s `expandByDefault` walk opens on the Sound and Clip
sub-tabs and which any pin would stop — so those two are pinned open, and
screens 09 and 10 `expect` a row inside each. Nothing is ever written with
`defaults`. P2 holds the pins to the tree: the section ids in `app/Sources` are
exactly `SECTIONS`'s, and every `static let …Key = "Reelcut…"/"RC…"` literal is
pinned or in `NOT_SHOWN` (with why no captured screen draws it), and every
`NOT_SHOWN` key is such a literal. Road map 12 A1 added three such literals
and A2 covered them: `ReelcutAssistantModel` is pinned `""` (Settings'
Assistant pane draws it as its model field), and `RCDevAssistantSend` /
`RCDevAssistantReport`, the dev launch default no screen launches with, are
`NOT_SHOWN`.

**The key.** The Settings capture cannot show an AssemblyAI key: the secret
folder is rebuilt EMPTY before launch (the run refuses to start if it is not
empty after), `RC_ASSEMBLYAI_KEY` and `ANTHROPIC_API_KEY` are stripped from the
child's environment (so the Assistant tab's screen, 11b, shows the no-key
pointer and Settings' Assistant pane says `No API key is set.` too), the
Settings field is never filled from the store (`SettingsWindowController.swift`),
`snapshot_ui` never writes a secure field's text, and screen 02 `expect`s
`No API key is set.` — if it is not visible, the screen fails and its files
are deleted. The script never reads a key file.

**No recording, transcription, export or network.** Steps come only from
`STEP_TOOLS`; a menu item must be a leaf the dev tool classifies `sheet` or
`window`; no sheet button is pressed except through `cancel_sheet`; the engine
is pinned `apple` and the AssemblyAI endpoint is a dead loopback port.

**The recorder hazard.** File ▸ New Recording… puts up a non-activating panel
(`RecorderPanelController.swift:207`) whose default button is Record
(`Sheets.swift:86`) — and Record asks for the Screen Recording and microphone
grants. Showing it asks and records nothing. Since #137 (spec §11, "The
recorder panel takes key only from an active Reelcut") `show()` makes it key
only when Reelcut is active (`:332`); shown from the background it is ordered
front without key (`:334`) and Reelcut stays inactive (`v3_tools.py`'s R3).
But an instance that is ACTIVE when New Recording… runs still gets a key panel
with Record on Return, and the script cannot hold its child inactive. So the
path is still allowed only in the run's LAST screen (16), the captures follow
the perform at once, the instance is stopped straight after them, and the run
prints `recorder panel up (<look>): <ms> ms; active before New Recording…
<True|False>` (the perform's answer to the child's exit, and the listing's
`active` read after `open_project`, before the perform) and each capture's
`key` and `active`, unscored. With `active before … False` the captures must
read `key False active False`; with `True` the look is the host state `host:
Reelcut active before New Recording…`, not a failure. The panel goes up once
per instance, so twice a run. Measured before #137: 134–140 ms over four runs
with both looks from one instance, then 62–70 ms per instance with one capture
each; the panel was key with Reelcut ACTIVE — putting it up brought Reelcut to
the front. Measured after it (2026-09-29): 106 ms light and 100 ms dark,
`active before New Recording… False` for both, and each capture `key False
active False`. **Keep your hands off the keyboard while the last screen of each
look runs.**

**Unpinnable inputs.** The recorder's Source row names the host's display and
its size note is that display's size (`RecorderPanelController+Rows.swift`);
the Export sheet's presets come from the person's `ExportPresets.json`; the
Generate Captions sheet's language list is the installed speech models; the
window lands on whichever screen AppKit picks, at its scale and colour profile.
Two runs on one machine are byte-identical but for the captures named below; two
machines need not be.

**Rows**, one line each as `<ID> <pass|fail|skip> — <reason>`: `P2` the pins;
`P1.light` and `P1.dark` each launch (child alive, port bound, Welcome up,
`grep "Reelcut: "` empty, the dev tools in `tools/list`, the marker count);
`P3.light` and `P3.dark` each instance's end (child alive and the log clean,
read just before the child is stopped); one row per screen, scored after both
looks — a pass needs both, and each look first prints an indented progress line
`  <id> <look>: <state> — <reason>`. 22 rows for the 17 screens (road map 12 A2 added 11b, the Assistant tab).
Then `new problems:` with each, `recorder panel up (<look>):`, `scores:`, `digest:`
(sha256 of the sorted `ID=state` lines) and `out:`; with `--compare`, every PNG
against the same name in the earlier run — `same`, `differs: N px in [x0,y0,x1,y1]`,
`size differs` or `only in one run` — and `compare: S/N byte-identical`, not
scored. Exit 0 iff no row failed. A screen fails on a front-block problem
(`front block: …`, before any step), a missing fixture medium (naming this
README's "Running one" recipe), a tool error, a failed `expect` (its files
deleted), or a sheet left attached (closed with `cancel_sheet`; one that will
not close fails every later screen). Layout problems are classified against
`KNOWN` (empty since #70 was fixed) and new ones are reported, never scored.

**Outputs** in `<out>`: `<id>.<capture>.<light|dark>.png` and `.layout.json`,
`screens.md`, `results.json` (the rows and, per capture, its PNG's sha256, scale,
points, pixels, window facts and known/new problems), and `app.light.log` and
`app.dark.log`. The fixtures are rebuilt by each instance under
`work/screens/fixtures/`; a fixture that names `sound` clips (`demo`: `video`
and `tone`) is ready only once `detect_silence` in level mode answers no
`pending_peaks` for them (`wait_for_peaks`, polled every 0.5 s, printed as
`fixture demo: peaks cached after <n> poll(s), <ms> ms`), and one still pending
after 60 s fails every screen on that fixture for that look.

**What is not byte-identical across runs** (2026-09-29, the #70/#136/#141–#143/#155 batch): two runs of
the same build answered `compare: 52/52 byte-identical`, 04 and 15 included —
04 now waits for the peaks, and 15's button row is no longer ambiguous (#141).
Against the build before that batch the run answered `compare: 50/52 byte-identical`:
only 15's sheet, `differs: 5939 px in [296,834,760,895]` dark and `differs:
721 px in [296,857,421,873]` light, its new footnote "captions go on a new
track" and the row it no longer squeezes. Before it (2026-09-27, `compare:
45/48`) 04 differed by 832 px in the Music clip's waveform band and 15's light
sheet by 1 546 px around Cancel and Generate. One of that batch's runs' dark instance
failed 04–16 with `1 media still pending_peaks after 60 s`: toneA.m4a's peaks
never landed in that instance's package, though its speech cache did, and
nothing retries them before the next open (#169).

**Mutants** (2026-09-27), each a copy of `designs/screens/` in a scratch folder
passed as `--screens`: File ▸ "Exprot…" in 12 fails 12 as not a menu leaf and
13 passes; 06's front block missing a comma fails 06 as `front block: not JSON`;
an `export` step in 04 fails 04 as `front block:` before any step runs (exit 1);
02's `visible_text` changed fails 02 and leaves no `02-*` file; 13 without its
`after` fails 13 with `left a sheet attached: NSWindow` and 14 still passes.

## Road map 11's V3 — the tab tool and the recorder window (`v3_tools.py`)

The proof of V3's two app additions: the dev tool `select_inspector_tab` and
`snapshot_ui`'s `recorder` window. It launches its own instance through
`screens.launch` (the same pins) and builds `screens.py`'s `demo` fixture.

```sh
python3 tools/proof/v3_tools.py [--port 4872] [--app APP] [--only L,T,R]   # → 8/8
```

- **L1**: as `screens.py`'s P1, plus the four dev tools in `dev_tools.py`'s
  order immediately before `import_media`, and `select_inspector_tab`'s
  properties exactly `{tab, sub_tab, project}`, none required, no `scope`.
- **T1**: with the video clip selected, `{}` answers `clip` / `picture` /
  `[picture, sound, clip]`, and inspector captures before and after it are
  byte-identical. **T2**: `{tab: document}` answers `document` / null, and its
  dump shows `Frame rate` and no `Position X`. **T3**: `{tab: clip}` answers
  `picture`; `{tab: clip, sub_tab: clip}` answers `clip` and its dump shows
  `Reversed frames` and no `Position X`; after `set_selection [text]`, `{}`
  answers `text`. **T4**: each refusal by its words, and `{}` after each
  answers what it did before; the missing sub-tab is `sound` on the text clip
  from the Document tab. A section's title is drawn, not a text field, so the
  dumps are read for row labels. The windowless-document refusal is not
  reachable over MCP.
- **R1**: before New Recording…, `snapshot_ui {window: recorder}` is refused
  `not open`, no `recorder` row is listed, and the menu listing has
  `["File", "New Recording…"]` with verdict `window`. **R2, the last row to
  touch the app**: the listing's `active` is read, then the item is performed;
  `windows_opened` holds one `recorder` row; the capture's pixels are its
  points × scale; `project` and `view` with it are refused by name; the item is
  still titled `New Recording…`; the readings are printed; the instance is
  stopped and `recorder panel up` printed (56–60 ms before #137; 70 and 72 ms
  on 2026-09-29). **R3** (#137) makes no MCP call: from R2's readings, with
  Reelcut inactive before New Recording…, the answer's `active` and the
  capture's `active` and `key` must all be false. It skips by name as `host:
  console locked` or `host: Reelcut active before New Recording…`. Against the
  build before the `show()` change (a `ditto` copy, `--app`) it FAILED —
  `active before New Recording… False; the answer's active True; the capture's
  active True key True` — and passed after it.

**Mutants** (2026-09-27), each built with `make app`, run, restored and
`cmp`-checked: `selectInspectorTab` calling `ClipPane.choose(_:)` instead of
`selectClipSubTab(_:)` fails T3 alone (the answer says `clip`, the dump still
shows Picture's rows); `UISnapshot.openWindow(.recorder)` answering
`RecorderPanelController.shared.window` fails R1 alone (the capture is taken
instead of refused).

## Road map 12's A0 — the assistant spike (`assistant_spike/`, `anthropic_fake.py`)

The spike behind A1's plumbing: Rasterize's Bun helper (`agent/`, renamed
`reelcut-agent`) built, placed in `Contents/Helpers` and signed by Rasterize's
own build step, in a COPY of the tree under `work/assistant_spike/tree/`
(`tree_copy.make_copy` with `agent=False`, the copy's own agent step removed
from its `project.yml` before Rasterize's is spliced in) with a hook (`AssistantSpikeHook.swift`) that exists only there. It answers
whether the helper launches from a Release and a Distribution bundle under
the hardened runtime and needs its one entitlement (B, H), how big the
catalog is and whether it wants tool search (C), whether a stand-in Messages
server scripts a whole turn — a `tool_use`, the tool's result, then text —
against the built app (F, T), whether `export` replaces an existing file
(E), and what an agent edit does to a timeline drag in progress (D, a probe
built from `app/Sources`). 32 scored rows, a digest. Its README has the rows,
the copy, the run order and the output; the answers are in
`archive/reelcut-roadmap-12.md` §7 (condensed in
`designs/adr/roadmap-12-assistant.md`). `anthropic_fake.py` is the stand-in, at
the top level because A1 reuses it: `port <n>` first, a scripted reply per
`POST /v1/messages` (SSE when the body asks to stream), and R6-9(e)'s
credential rule — only `proof-key` and `wrong-key` are ever logged.
`ANTHROPIC_API_KEY` is popped from every child's environment; with it
present, C3 counts the catalog through `count_tokens` and L1 searches every
file the spike and the builds wrote for it, and without it C3 estimates and
L1 skips as `host: no key`.

```sh
python3 tools/proof/assistant_spike/assistant_spike.py [--only B,H,C,F,T,E,D,L] [--rasterize ~/devel/rasterize]
```

## Road map 12's A1 — the agent lane (`assistant_lane_proof.py`, `assistant_lane_probe.swift`)

A line of `make test` (spec §11 AI-3's "`make test`-reachable
probe"). It launches no app instance, reads no key and uses no media: every
child gets the environment without `RC_ASSEMBLYAI_KEY` and
`ANTHROPIC_API_KEY`. The probe is compiled AS `main.swift` over every file in
`app/Sources` but the app's own `main.swift`, on `harness/build.sh`'s swiftc
line with `-D REELCUT_DEV_TOOLS`, into `work/assistant_lane/probe/`, and
rebuilt only when a source, the probe, the proof or the staticlib is newer
than it (about 90 s when it is). It prints one `ANSWER {json}` line; nothing
in it calls `start()`, and every row makes its own documents.

- **L0** (the proof, from the source — the probe cannot see `main.swift`):
  `app/Sources/main.swift` has a line `AgentLane.prepareAtLaunch()` at top
  level, between no `#if` and its `#endif`, before the `NSApplicationMain`
  line.
- **L1** (AI-3): after `prepareAtLaunch()` alone, `submit add_marker {at,
  name}` answers ok and `get_project` lists the marker.
- **L2** (AI-2): 20 concurrent calls, `serve` from background threads (to B by
  its saved path) alternating with `submit` (pinned to A): every marker on its
  own document, none refused.
- **L3** (AI-5): B frontmost, a `submit` pinned to A lands on A; with
  `project` = B's path it is refused with the AI-5 sentence and neither
  changes; once A is closed, "no longer open".
- **L4** (AI-7): `submit` of `record_screen`, `transcribe {engine:
  "assemblyai"}` and `snapshot_ui` each answers its refusal as written and the
  hook is never called; `serve snapshot_ui` is not refused by the lane.
- **L5** (AI-7): `export` Deny to a fresh path ("export writes P", the
  declined sentence, no file) and onto a sentinel ("export REPLACES S", bytes
  unchanged); `save_project` Allow writes Q, again Deny asks "save_project
  REPLACES Q"; `serve save_project` asks nothing and writes R.
- **L6**: the assistant's catalog has no `record_screen` and no dev tool, and
  has `transcribe`, `export` and every `AssistantPrompt.coreTools` name (A1
  part 3: a core tool the catalog lacked would be loaded up front by a name
  the helper was never given).
- **L7** (#144, AI-12, `serve` from a background thread) and **L8** (the same
  through `submit`): `add_marker` made between two ticks of a clip-body drag,
  driven through `TimelineView`'s gesture methods, has not returned two ticks
  later; after `endGesture` it answers ok, the marker is present and the clip
  moved; Undo "Add Marker" removes the marker and leaves the clip, Undo "Move
  Clips" puts the clip back at 0.
- **L9**: `onMainWhenIdle` on main with a gesture live runs its body at once.
- **C1** (control): `execute` on main between two ticks, as A0's D2 ran it,
  loses the marker — the instrument can see #144.
- **M1** (made to fail on purpose): L0 against a scratch copy of `main.swift`
  with the prepare line deleted, and the probe's L1 under `--no-prepare`
  (the gate is empty, so `add_marker` is refused for `at` and `name`), must
  BOTH fail.

A probe that does not build is a scored FAIL. Exit 0 only when every row
passes.

```sh
python3 tools/proof/assistant_lane_proof.py               # L0–L9, C1, M1
python3 tools/proof/assistant_lane_proof.py --no-prepare  # the mutant alone: L0 and L1 FAIL, exit 1
```

## Road map 12's A1 part 2 — the helper and its build (assistant_helper_proof.py)

The helper (`agent/`, spec §11 AI-1), its build and road map 12 §2's three
`configure` fields. It launches no app and reads no key: every child's
environment has `RC_ASSEMBLYAI_KEY` and `ANTHROPIC_API_KEY` popped. The
helper only ever gets `proof-key`, and every `configure` it is sent points
`api_base` at a running `anthropic_fake.py`, so no row reaches
api.anthropic.com. Each child runs under a wall in its own process group
(rule H): P1 30 s; the helper 20 s to `ready`, 60 s for a turn and 5 s to
exit; P5 180 s. It works in `work/assistant_helper/`, prints
`<ID> ok|FAIL|skip — <reason>` per row and then `n/m`, and exits 0 only when
no row fails. An instrument that cannot run is a scored FAIL.

- **P0**, the wiring, read from the source:
  - `project.yml` has exactly one "Build Agent Helper" item, after "Copy
    Graphic Templates" and before `schemes:`, with
    `basedOnDependencyAnalysis: false` and `agent/build.sh" helper`.
  - The Makefile's `typecheck` runs `/bin/sh agent/build.sh typecheck`.
  - `unexport ANTHROPIC_API_KEY` occurs once.
- **P1**, never skips. `build.sh helper` and `build.sh typecheck` run with a
  fresh empty `HOME`, `PATH=/usr/bin:/bin` and a scratch
  `TARGET_BUILD_DIR`. Each exits non-zero with a first stderr line
  `error: bun is not installed …` and places no helper. It skips only as
  `host: bun at a fixed path`, when bun is at `/opt/homebrew/bin` or
  `/usr/local/bin`.
- **P2r / P2d**, the Release helper and, with `--dist`, the Distribution
  one. Each is present, shows `flags=0x10002(adhoc,runtime)`, has
  entitlements that parse as exactly `{com.apple.security.cs.allow-jit:
  true}`, and passes `codesign --verify --strict`.
- **P3**. The Release helper is launched with exactly `HOME`, `TMPDIR` and
  `PATH=/usr/bin:/bin`. It answers a `configure` with `ready` and exits 0
  once stdin closes. The stand-in sees only the Models API `GET`, no POST,
  and no failures.
- **P4**, the §2 fields reach the API. `configure` carries `get_project` and
  `add_marker`, `core_tools ["get_project"]`, `search_guide "P4-GUIDE"`,
  `compaction_instructions "P4-COMPACTION"`, `system "P4-SYSTEM"` and
  `auto_compact_tokens 1`, and one `send` follows. The checks:
  - The first POST's system is `P4-SYSTEM\n\nP4-GUIDE`.
  - Its tools are `tool_search_tool_bm25`, `get_project` with no
    `defer_loading`, and `add_marker` with `defer_loading: true`.
  - The POST after `compaction_started` carries `P4-COMPACTION`. The SDK
    sends that POST inside the same turn, so the second `send`, kept for
    the other case, was not needed.
- **P5**, the control. A scratch copy of `agent/` without `node_modules`,
  with `const p5: number = "p5";` appended to `main.ts`, fails `build.sh
  typecheck` with a tsc error naming `src/main.ts`.
- **Mutants**, each running only its row, which must FAIL (exit 1). A mutant
  whose row skipped on this host exits 2 and says the control could not be
  performed; it is never read as caught:
  - `skip-without-bun` runs P1 against a scratch `build.sh` whose guard
    `exit 1` (asserted once) became `exit 0`.
  - `no-fields` runs P4 with the three fields omitted. The system then ends
    in "undefined", `get_project` is deferred, and the summary POST lacks
    the instructions.

```sh
python3 tools/proof/assistant_helper_proof.py --dist build/Build/Products/Distribution/Reelcut.app  # 7/7
python3 tools/proof/assistant_helper_proof.py --mutant skip-without-bun  # P1 FAIL, exit 1
python3 tools/proof/assistant_helper_proof.py --mutant no-fields         # P4 FAIL, exit 1
```

## Road map 12's A1 part 3 — the session (assistant_session_proof.py)

Real assistant turns in the built Release app against a running
`anthropic_fake.py` (spec §11 AI-3, AI-5, AI-7, AI-8, AI-10, AI-11, AI-13):
the session (`AssistantSession.swift`) driven over MCP by the dev tools
`assistant_send` / `assistant_answer`, and without the MCP server by the
dev-only launch default `-RCDevAssistantSend` / `-RCDevAssistantReport`. It
works in `work/assistant_session/`, posts each row's scenario to
`/__control/scenario` and reads `/__control/log`, prints `<ID> ok|FAIL —
<detail>` per row and then `n/m`, and scores an instrument that cannot run
as a FAIL. Walls: a port in 60 s; MCP calls 300 s; each assistant `timeout`
60 s; the W report 150 s; the mutant build 900 s.

Safety: every child's environment has `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY` popped and none sets either. The only key is the dummy
`proof-key`, in a `0600` `anthropic-key` in a `0700` scratch
`-RCSecretFolder`, and `RC_ASSISTANT_BASE_URL` always names the stand-in.
Each app runs in its own process group; only the proof's own apps are
killed, with the helper children each started (named by ppid and path,
`ps -o pid=,ppid=,comm=`, before the app goes).

Launch A (`-AgentServerEnabled YES`, port 4872, the scratch folder, the
variable):
- **A0**: no `Reelcut: ` line; the dev-tool marker counts
  `len(DEV_TOOLS)` = 6; the dev block is `DEV_TOOLS + ["import_media"]`.
- **T1** (AI-5, AI-10): `new_project` A then B (B frontmost). A scripted
  `add_marker {at: 1200000, name: "A1 part 3"}` with no `project`, then text;
  `assistant_send {project: A}` answers `finished` with that text and one
  `add_marker` `tool_result` event, `is_error` false; A has the marker at
  1200000, B has none; one MCP `undo {project: A}` removes it.
- **T2** (T1's stand-in log): `GET /v1/models/claude-opus-5-5`; every POST's
  model `claude-opus-5-5` and credential `proof-key`; the first POST's
  system is two non-empty halves joined by `\n\n`; its tools are
  `tool_search_tool_bm25` then the Release `tools/list` less
  `record_screen` and `DEV_TOOLS`, in order, with exactly the four core tools
  up front and every other `defer_loading: true`.
- **R**: `allow` with nothing pending, `stop` while idle and `answer:
  "maybe"` are each refused as written; the project is unchanged and the
  stand-in hears nothing.
- **D** (Deny): a text clip is added to A; the scripted `export {preset:
  "h264", path: P_D}` makes `assistant_send` answer `asking`, "export writes
  P_D", no file; `deny` answers `finished`, still no file; POST 2 carries that
  call's `tool_result`, `is_error` true, "The person declined: export writes
  P_D."; the events hold the answer by `person`.
- **E** (Allow): onto a sentinel at P_E the question is "export REPLACES
  P_E"; `allow` answers `finished`; P_E has `ftyp` at byte 4; POST 2's
  `tool_result` has `is_error` false.
- **S** (Stop): export to a fresh P_S plus a spare text reply; `send` →
  `asking`; `stop` → `finished`; no file; the answer by `stop`; no stand-in
  failures. The POST count is printed as a measure.
- **X** (helper death): export to a fresh P_X → `asking`; the app's own
  helper child is SIGKILLed; within 10 s a new `assistant_send` is taken and
  its scripted marker at 2400000 lands on A; no file at P_X; the app lives.
- **K1**: `proof-key` is in no MCP answer of launch A and nowhere in its log.

Launch B, **W** (`-AgentServerEnabled NO`, the launch default,
`-ReelcutAssistantModel claude-proof-model`, the folder, the variable, no
`RC_AGENT_PORT`): the report is `ok`, `server_running` false, `finished`,
with an `add_marker` `tool_result` `is_error` false and the marker in its
`get_project`; the stand-in saw `GET /v1/models/claude-proof-model` and
POSTs with that model and `proof-key`, no failures; the log has no
`Reelcut: ` and no `listening on` line.

Launch C, **K2** (AI-13: `-AgentServerEnabled YES`, port 4873, NO
`-RCSecretFolder`, the variable set): after `new_project`, `assistant_send`
is refused "No Anthropic API key is set…"; the stand-in logged no request;
the app has no helper child.

**Mutant `no-prepare`**: a copy of the tree in `work/assistant_session/mutant/tree`
from `tree_copy.make_copy` (`app/`, `project.yml`, `Makefile` copied; every
other build input `project.yml` names symlinked; `agent/` copied without
`node_modules`), its `AgentLane.prepareAtLaunch()` line (asserted once)
deleted and `make app` run there; W alone against it must FAIL — the report
`ok: false`, naming AI-3 — and the run exits 1. A mutant that did not build
exits 2: the control was not performed.

The mid-drag row is not reachable live (no MCP tool begins a gesture); the
lane's L8 measures `submit`, the one door the session uses, mid-drag.

```sh
python3 tools/proof/assistant_session_proof.py                       # 11/11
python3 tools/proof/assistant_session_proof.py --mutant no-prepare   # W FAIL, exit 1
```

## Road map 12's A2 — the Assistant tab (assistant_tab_proof.py, assistant_tab_probe.swift)

The inspector's fourth tab (spec §11 AI-4, AI-7, AI-8, AI-11, AI-14), read
back two ways: a probe for the arithmetic and structure no script reaches,
and the built Release app driven through the tab's OWN controls. It works in
`work/assistant_tab/` and reuses `assistant_session_proof.py`'s stand-in,
`App`, secret folder and helpers (its `WORK` re-pointed here), prints `<ID>
ok|FAIL — <detail>` per row and then `n/m`, and scores an instrument that
cannot run as a FAIL. Safety as the session proof's: every child's
environment has `ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY` popped; the only
keys are dummies in `0600` files in scratch folders; the helper speaks to the
stand-in or to a dead loopback port.

**P** — `assistant_tab_probe.swift`, compiled AS `main.swift` over
`app/Sources` minus `main.swift` on `harness/build.sh`'s swiftc line with `-D
REELCUT_DEV_TOOLS` (a build failure fails every P row), `AgentLane.prepareAtLaunch()`
first, the Release build's helper copied to `<probe dir>/Contents/Helpers/reelcut-agent`
(a bare binary's `Bundle.main.bundleURL` is its own folder), run with
`-RCSecretFolder` holding `probe-dummy-key`, `-ReelcutInspectorCollapsed NO`
and `RC_ASSISTANT_BASE_URL=http://127.0.0.1:9`:
- **P1** the transcript over a scripted event list: 16 entries exactly
  (a text run and a progress run each ONE entry, broken by any other event;
  `add_marker (at: 1200000, name: P1)` with `project` dropped; `failed: …`;
  Rasterize's four compaction sentences; `Allowed:` / `Declined:` /
  `Declined (stop):` with the question's sentence; the error), the usage,
  two `extended` changes, `argumentSummary`'s `""` / 70-character cut, and
  Clear and `endConversation` keeping the window size.
- **P2** the meter's three figures.
- **P3** `showAssistant`: the Assistant tab, the composer first responder.
- **P4** on an `AssistantView` in a window of its own: an idle Return sends
  and empties the composer (the control); with a question shown, Return
  answers nothing, sends nothing and stops nothing; Send reads Stop; Allow's
  and Deny's own `mouseDown` answer true, then false, once each.
- **P5** AI-14: from Media a changed selection shows Clip (the control);
  from Assistant it stays; `clipPicked()` shows Clip.
- **P6** a REAL session (the helper runs, nothing is sent): a posted model
  change closes it, nils `assistant` and writes "The model is now …; the
  next message starts a new conversation."; a second session is closed by
  the Clear button, and the transcript empties.
- **P7** Settings' Assistant pane over `MemoryStore`s and a scratch suite:
  empty state; Save writes, empties the field, masks the placeholder and posts
  `key` (the key in no status text); Remove; `claude-opus-5-5` over an unset
  model posts nothing; a new model writes the suite and posts `model`, and the
  same text again posts nothing; in a `SettingsWindowController` the
  Transcription heading is still first and the Assistant pane last.

**Live A** (`-AgentServerEnabled YES`, port 4874, `proof-key` in
`-RCSecretFolder`, `RC_ASSISTANT_BASE_URL` at the stand-in,
`-ReelcutInspectorCollapsed NO`), every turn through `assistant_send` /
`assistant_answer` with `pane: true`, and the tab read back through
`snapshot_ui`'s inspector dump by accessibility id (`assistant.*`):
- **L0** no `Reelcut: ` line.
- **L1** `perform_menu_item View ▸ Assistant` → `select_inspector_tab {}`
  answers `assistant`; composer, Send and Clear visible, the no-key pointer
  and the question hidden; no layout problem inside the `AssistantView`.
- **L2** a scripted `add_marker` turn typed into the composer: `finished`;
  the entries are exactly person, `add_marker (…`, the reply and the turn's
  cost line (road map 13 P2: exactly `Cost: $0.0012 · Reelcut's estimate at
  LiteLLM prices (bundled table of <day>; not refreshed: no price cache is
  configured)`, the dollars from `prices.py`, `<day>` the local date of
  anthropic.json's `litellm_commit_date`); the composer is empty; Send reads
  Send; the marker is on the project.
- **L3** Deny: the row reads `export writes <D>`, Send reads Stop, Allow and
  Deny are visible and the tab has no layout problem while asking; after it
  no file, the row hidden, `Declined: export writes <D>` in the transcript.
- **L4** Allow over a sentinel E: `export REPLACES <E>`, a movie at E
  (`ftyp`), `Allowed: …`.
- **L5** Stop while asking: no file, `Declined (stop): …`.
- **L6** with the Media tab showing, `assistant_send {pane: true}` is refused
  `… select_inspector_tab {tab: "assistant"} first.` and the stand-in hears
  nothing.
- **K** `proof-key` in no MCP answer, no layout dump and not the log.

**Launch B**, **N1** (the variable set, NO `-RCSecretFolder`: no key, AI-13;
port 4877): View ▸ Assistant shows "Add your Anthropic API key in Settings
to use the assistant." and Open Settings…, and neither the composer nor Send.

**Mutant `no-forward`**: the tree copied as the session proof's mutant is
(`tree_copy.make_copy`, into `work/assistant_tab/mutant/tree`),
the ONE `session.onEvent =` line deleted from
`EditorViewController+Assistant.swift`, `make app` there, then L1's steps and
L2 alone: L2 must FAIL (the transcript holds only the person's line) and the
run exits 1; a copy that did not build exits 2.

Measured 2026-09-27: 16/16; the mutant's L2 FAILS with entries `['person:
…']` and Send still reading Stop (exit 1). In this agent's shell sandbox the
process-group kill at cleanup is refused (`PermissionError`, from `killpg` —
the unchanged session proof hits it too), so these proofs were run outside
it.

```sh
python3 tools/proof/assistant_tab_proof.py                        # 16/16
python3 tools/proof/assistant_tab_proof.py --mutant no-forward    # L2 FAIL, exit 1
```

## Road map 12's A3 — the prompt (assistant_prompt_proof.py, assistant_prompt_probe.swift, assistant_prompt_eval.py)

The assistant's texts, the live context each message carries, and the
evaluation against a real model (spec §11 AI-7, AI-9, AI-15). It works in
`work/assistant_prompt/`, reuses `assistant_session_proof.py`'s stand-in,
`App`, secret folder and helpers (its `WORK` re-pointed here), prints `<ID>
ok|FAIL|SKIP — <detail>` per row and then `n/m pass, k skipped` (the cap's
failures counted apart), and scores an instrument that cannot run as a FAIL.

**F and M** — `assistant_prompt_probe.swift`, compiled AS `main.swift` over
`app/Sources` minus `main.swift` on `harness/build.sh`'s swiftc line with `-D
REELCUT_DEV_TOOLS` (rebuilt only when stale; a build failure fails every
row), `AgentLane.prepareAtLaunch()` first. Its fixture is an untitled
document edited through `AgentLane.submit` pinned to it: two `add_track`, a
text clip "Welcome", two shapes, an action on the text clip, a marker, a
64 × 64 image through `add_media`, and `nest` over the second shape; then
`get_project`.
- **F1** every backticked token in the three texts is an identifier path
  whose whole is an assistant-catalog tool or whose every segment is an
  argument name (any depth of any `inputSchema`) or a key at any depth of
  the fixture's `get_project`; no snake_case word outside backticks but
  `<reelcut_context>`; no withheld tool (the unconditional rows and the dev
  tools) anywhere.
- **F2** `ReelTime.perSecond == RC_TIMESCALE`, and the system prompt and
  `get_project`'s note both say it.
- **F3** each `sharedIdKinds` name backticked in the system prompt; every
  array under such a key at any depth of the fixture's `project` holds
  objects with integer ids; each kind has one; all distinct and below
  `next_id`.
- **F4** `searchTopics` ∪ `coreTools` is the assistant's catalog, each tool
  once; the guide shows every topic's words and each core tool backticked.
- **F5** every ask-first row's tool, and each conditional withheld row's
  tool and key backticked and its value in double quotes, in the system
  prompt.
- **F6** no text holds `\n\n`; system ≤ 6000, guide ≤ 1500, compaction ≤
  1000 characters; none empty.
- **F7** `AssistantLiveContext.text` for four samples equals the template;
  `message(t, document:)` is the block, a newline and `t`; `message(t, nil)`
  is `t`; each label is a key of `get_project`.
- **M1–M4** each checker FAILS on a mutated copy: `` system + " `add_markers`" ``
  (F1), the timescale's digits → 60000 (F2), the first topic's last tool
  dropped (F4), `system + " record_screen"` (F1).

`--probe` runs these alone (no app, no bun): it is a line of
`make test`.

**Launch S** (Release, port 4878, `-AgentServerEnabled YES`, `proof-key` in a
scratch `-RCSecretFolder`, `RC_ASSISTANT_BASE_URL` at the stand-in), in a
saved project with a 6 s text clip (a playhead is clamped to the project's
end):
- **S0** no `Reelcut: ` line.
- **S2** `set_playhead 2400000` and the text clip selected: turn 1's last user
  text is exactly the block (from `get_project`'s name and path) + `\n` +
  the person's text; after `set_playhead 4800000` and an empty selection,
  turn 2 carries the new block, and its `messages[0]` equals turn 1's.
- **S1** S2's POST 1's system is `system + "\n\n" + search_guide`.
- **S3** a scripted reply of `input_tokens: 300000` (`anthropic_fake.py`'s
  reply field) makes the helper compact: `compaction_started`, and POST 2
  carries `compaction_instructions` verbatim.

**Mutant `bare-send`**: the tree copied as the session proof's mutant is
(`tree_copy.make_copy`, into `work/assistant_prompt/mutant/tree`),
`AssistantPrompt.message(text, document: document)` → `text` in the copy's
`AssistantSession.swift`, `make app` there, S2 alone on port 4881: it must
FAIL (exit 1); a copy that did not build exits 2.

**The evaluation** (`assistant_prompt_eval.py`, imported, never a child).
Launch E: port 4880, `proof-key`, `-ReelcutAssistantModel claude-opus-5-5`,
`RC_ASSISTANT_BASE_URL` at the RELAY — a thread in the proof's own process
on 127.0.0.1:0 that takes only `x-api-key: proof-key` (else 401, the value
never logged), routes `GET /v1/models/*` and `POST /v1/messages*` only, and
forwards with the real credential less `x-api-key`, `authorization`,
`host`, `content-length`, `connection` and `accept-encoding`. Each row is its
own saved project `E<n>.reelcut` (a background plate to 6 s; "Welcome" on
Titles 0–3 s; a rectangle on Shapes 0–6 s; E5 nests it), judged by
`get_project` placement only — "unchanged" is each clip's id, track, start,
duration, kind and content:
- **E1** "Put a marker called Intro at 3 seconds." → one new marker at
  1800000 named Intro, clips unchanged. **E2** in E1's window, "Undo that."
  → the fixture's markers. **E3** playhead 2400000, the title selected,
  "Split the selected clip at the playhead." → the title split at 2400000,
  every other clip unchanged. **E4** "Change the title to say Hello
  Reelcut." → its content, timing kept. **E5** "Inside the nest, move the
  rectangle so it starts at 1 second." → the nested rectangle at 600000,
  duration kept, the nest clip unchanged. **E6** "Export this project as a
  movie to <abs>/E6.mp4." → every question denied (at most 3): no file,
  exactly one export question, the project unchanged. A turn past 600 s is
  stopped and FAILs. A row whose session met a cap refusal FAILs `cap:
  refused at $<spent> of $<cap>`.
- **H** every POST the relay saw was within `BODY_BYTES_BOUND` (256,000
  bytes less image data) and `MAX_TOKENS_BOUND` (32,000); a breach FAILs
  and says the arithmetic is stale. It prints the worst POST priced.
- **K** (live only) the key's bytes in no file under `work/assistant_prompt/`
  nor the app log.
Per row it prints the tools called, the tokens and the dollars at `RATES`,
then the run's and the ledger's totals.

**The cap and the budget.** Per POST, under one lock, the relay prices the
WORST case — the body less image data at one token per 3 bytes plus 1600 per
image, all at the cache-write rate, plus the body's `max_tokens` at the
output rate. When settled spend + reserved + that would pass the cap it
answers 400 `invalid_request_error` naming the cap and writes nothing to the
proofs' ledger. Otherwise it reserves that worst case in the proofs' ledger
(`budget.SpendLedger`, road map 13 P3, spec §11 P-6) and answers 400 naming
the BUDGET instead when this UTC month's recorded Anthropic spend plus it
would pass $25; only once that reservation is made does the cap count it,
so a POST the budget refuses holds no cap reservation. A forwarded reply's
whole usage is read and priced by the table (`budget.settle_anthropic`: the
table's price, `table`; usage it cannot price at each class's dearest rate,
`worst`; a reply whose usage cannot be read, or the relay's own 502, at the
reservation, `reserved`), settled in the proofs' ledger, and one run-ledger
line appended `{run,row,path,status,model,usage,dollars,refused,basis}`, a
refused line with `why` `cap` or `budget` (never a header or a body).
`RATES` is **an upper bound, not a quote**: each token class at its dearest
rate over every row and `above_200k` tier of `agent/prices/anthropic.json`
(`budget.anthropic_worst_row`), the two cache writes folded into the dearer
— today $10.00 input, $20.00 cache write, $1.00 cache read and $50.00
output per MTok. The headroom arithmetic, printed before the first request:
the helper sends `max_tokens` 32,000 on every POST and all 85 definitions,
deferred ones included; the A2 session proof's largest logged body was
230,340 bytes, bounded at 256,000 ≈ 85,333 tokens. The worst POST is
85,333 × $20.00 + 32,000 × $50.00 per MTok ≈ $1.71 + $1.60 = $3.31. A row is
bounded at one cache write of that body ($1.71) + 4 cache reads ($0.34) + 5
rounds × 2,000 output ($0.50) ≈ $2.55, an estimate that bills every
definition byte. The floor is the worst POST + 6 rows ≈ $18.59;
`SUGGESTED_CAP` is $20.00, under the month's $25. Below the floor it prints
`WARNING: below the floor; rows past $<cap − worst> of settled spend will
fail naming the cap` and still runs. A row whose session met the budget
FAILs `budget: …` before the cap is considered, and the summary counts
`<c> on the cap, <b> on the budget, <n> otherwise`.

**Modes.** Without `--live` or `--rehearse`, E1–E6, H and K SKIP "not asked
(--live)". `--live` needs an explicit `--cap <dollars>` (any positive
figure; raising it is the runner's decision): without one it prints the
arithmetic and exits 2 before launching anything; with no key, E1–E6, H and
K SKIP "host: no key". Live: the relay's upstream is `https://api.anthropic.com`,
its credential `anthropic_key()` — the ONE read of the owner's key:
`ANTHROPIC_API_KEY` when set, else `.secrets/anthropic-key` at the repo
root (gitignored, `chmod 600`; a looser mode warns), so a live run needs
nobody at the machine — whose
presence alone is printed — the ledger `work/assistant_prompt/ledger.jsonl`,
and the proofs' ledger `budget.LEDGER`, which only a keyed `--live` opens (K
scans it for the key too). `--rehearse` runs the same rows with the stand-in
upstream, the credential `proof-key`, the cap `SUGGESTED_CAP` unless `--cap`,
scripted right calls (`add_marker`; `undo`; `split` with `clips`;
`set_text`; `move_clip` with `scope`; `export`), the ledger
`work/assistant_prompt/rehearsal/ledger.jsonl` and a scratch proofs' ledger,
`work/assistant_prompt/rehearsal/spend.jsonl`, deleted first; `--month-spent
D` (rehearsal only, D ≥ 0) seeds it with D dollars already spent this month,
so `--month-spent 24.99` fails every E row `budget:` with nothing sent to
the stand-in. Each run prints the ledger's month line after building the
relay and again with the report;
`--wrong` scripts the mistakes (3000000; no undo; `split` without `clips`;
"Hello"; no `scope`; `export` again after the deny) and every E row FAILs.
H runs in rehearsal on the real helper's real bodies — only usage is
scripted — so rehearsal is what shows the worst POST.

Key safety: every child's environment has `ANTHROPIC_API_KEY`,
`RC_ASSEMBLYAI_KEY` and `RC_AGENT_PORT` popped. The app and helper get only
`proof-key` over the existing stdin path; the real key leaves the runner
only as the relay's `x-api-key` to the live API. Rule H: the proof's own
process groups only, plus the helper children each app started.

Measured 2026-09-27: `--probe` 11/11; the default run 15/15 with 8 SKIP;
`--rehearse` 22/22 (K SKIP), H's worst POST priced $2.55 at `RATES`;
`--wrong` fails E1–E6 (exit 1); `--cap 0.0001` prints the WARNING first,
fails E1–E6 `cap:` and the stand-in logs 0 POSTs (exit 1); `--live` with no
`--cap` exits 2 having launched nothing; the `bare-send` mutant's S2 FAILS
(exit 1). The live run is owed (#157).

```sh
python3 tools/proof/assistant_prompt_proof.py --probe                   # F1–F7, M1–M4 (make test)
python3 tools/proof/assistant_prompt_proof.py                           # + S0–S3; E, H, K SKIP
python3 tools/proof/assistant_prompt_proof.py --rehearse                # + E1–E6, H
python3 tools/proof/assistant_prompt_proof.py --rehearse --wrong        # every E row FAILs, exit 1
python3 tools/proof/assistant_prompt_proof.py --rehearse --cap 0.0001   # WARNING; E rows fail `cap:`
python3 tools/proof/assistant_prompt_proof.py --mutant bare-send        # S2 FAIL, exit 1
python3 tools/proof/assistant_prompt_proof.py --live --cap 15           # spends: the key from .secrets/ or the env
```

## Road map 12's A4 — the helper in both bundles (`dist_check.py` D6–D13, `dist_check_mutants.py`)

Both bundles carry the assistant helper, `Contents/Helpers/reelcut-agent`,
which `agent/build.sh helper` copies in and signs `--options runtime` with
`agent/entitlements.plist` before Xcode signs the app. `dist_check.py` holds
each bundle's helper to that contract, after D1–D5 and with none skipped:

- **D6 / D7** — the Release / Distribution helper exists;
- **D8 / D9** — it is signed with the hardened runtime: the first
  `flags=0x…(…)` in `codesign -dv --verbose=4`'s display (which goes to
  STDERR; the CodeDirectory line) lists `runtime`, and
  `codesign --verify --strict` exits 0. `runtime`, not `adhoc`, so a
  Developer ID signature passes too;
- **D10 / D11** — `codesign -d --entitlements - --xml`'s stdout, parsed as a
  plist, is exactly `{com.apple.security.cs.allow-jit: true}`;
- **D12 / D13** — it does not hold the `devToolsMarker` needle.

A missing helper FAILs its three rows ("no Release helper (D6)"); no needle
(D1) FAILs D12 and D13. A missing `codesign`, a timeout (120 s) or output
that does not parse FAILs the row with the reason. Every child gets
`child_env()`, the environment without `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY`.

**Made to fail on purpose, scripted.** `dist_check_mutants.py` runs
`dist_check.py` as a child once per case, with the mutated side a SKELETON
bundle under `work/dist_check_mutants/<case>/`: `Contents/MacOS/Reelcut` a
symlink to the real app's untouched binary and the helper a COPY, mutated
and re-signed ad hoc; nothing is written into `build/`. A case passes iff
the FAIL ids equal its expected set exactly, the last line is
`dist_check: <13 − |set|>/13` and the exit is 0 for an empty set, 1
otherwise; a failed setup step is a scored FAIL naming it.

| Case | The mutation | Expected FAIL |
|---|---|---|
| `control` | both sides the real apps | none |
| `skeleton` | both sides skeletons, helpers copied untouched | none |
| `no-helper-release` / `-dist` | no helper in the skeleton | D6 D8 D10 D12 / D7 D9 D11 D13 |
| `no-runtime-release` / `-dist` | re-signed with `agent/entitlements.plist`, no `--options runtime` | D8 / D9 |
| `extra-entitlement-release` / `-dist` | re-signed `--options runtime` with allow-jit plus `disable-library-validation` | D10 / D11 |
| `no-entitlements-dist` | re-signed `--options runtime`, no entitlements | D11 |
| `marker-release` / `-dist` | the needle written over the copy at the first `compaction_instructions`, re-signed as `build.sh` signs | D12 / D13 |

```sh
make dist                                                  # → dist_check: 13/13
python3 tools/proof/dist_check_mutants.py [--release APP] [--dist APP]   # → dist_check_mutants: 11/11
python3 tools/proof/dist_check.py --dist /nonexistent/Reelcut.app        # D3 D5 D7 D9 D11 D13 FAIL, 7/13, exit 1
```

**Measured 2026-09-28**, every command as `(unset ANTHROPIC_API_KEY
RC_ASSEMBLYAI_KEY; …)`: `make dist` built Release then Distribution and
ended `dist_check: 13/13`; each helper is 57719424 bytes,
`flags=0x10002(adhoc,runtime)`, entitlements exactly allow-jit, the needle 0
times. `dist_check_mutants.py` scored 11/11 in about 3 s, each case failing
exactly its set: no-runtime's reason "CodeDirectory flags (adhoc) lack
runtime", extra-entitlement's the two-key dict, no-entitlements' "the
entitlements do not parse", marker's "1 occurrences". `--dist` at a missing
path: D3, D5, D7, D9, D11 and D13 FAIL, 7/13, exit 1.

## Road map 13's P1 — the price table (`prices.py`, `prices_proof.py`, `prices_crosscheck.py`)

`agent/prices/anthropic.json` is LiteLLM's Anthropic rows (every entry whose
`litellm_provider` is `"anthropic"`) in US dollars per million tokens, with
the LiteLLM commit and committer date it came from (spec §11 P-1). `make
prices` (`agent/prices/update.py`, network, stdlib only) is its only writer:
it asks GitHub for the newest commit touching LiteLLM's
`model_prices_and_context_window.json`, fetches the file at that commit,
keeps input, output, cache_read, cache_write_5m, cache_write_1h and their
`above_200k` tier (a field LiteLLM lacks is absent, never 0), writes a temp
file beside the table and `os.replace`s it. It prints `commit <sha> <date>`,
`rows <n>`, then `unchanged` or each added / removed / changed id; any
failure is `error: …` on stderr, exit 1, and the file's bytes untouched.

`tools/proof/prices.py` is the proofs' reader (importable: `load`,
`match_model`, `price`); `agent/src/pricing.ts` is the helper's. Both answer
`agent/prices/cases.json`, the hand-checked cases over a pinned fixture
table, and never re-derive a rate. A model matches by exact id, or by the id
less a trailing `-YYYYMMDD` when that is a key; nothing else is stripped.
Unknown models, fast mode, a non-standard `service_tier`, a non-global
`inference_geo`, a malformed count and a class whose rate the row lacks each
answer `unknown` with its cause, never $0. With `usage.iterations`, each
entry prices at its own model (spec §11 P-2).

**`prices_proof.py`** — a line of `make test`; no network.

- **C:\<name\>** — each case through `prices.py`.
- **K** — the committed table: format 1, the unit, the provider, a 40-hex
  commit; `claude-opus-5-5` and `claude-fable-5-1` hold all five base rates
  as finite numbers ≥ 0; 1000 input tokens on opus price as dollars > 0.
- **T** — `/bin/sh agent/build.sh test` exits 0 (`bun test`, its JUnit report
  in `build/agent/bun-test.xml`, deleted first; 300 s wall).
- **A** — every case name has a passing `case: <name>` testcase in the JUnit
  report AND a passing C row; prints the case count and `cases.json`'s sha256.

Made to fail on purpose: `--mutant py-disagrees` prices C with every
`cache_read` rate doubled in memory (the cache-read C rows and A FAIL by
name); `--mutant ts-disagrees` runs T and A on a scratch copy of `agent/`
under `work/prices/ts-disagrees/` (`node_modules` ignored) whose `opus-mixed`
expects its dollars + 0.01 (T and A FAIL naming `opus-mixed`).

**`prices_crosscheck.py`** — network, not in `make test`. **X0** fetches
`https://platform.claude.com/docs/en/about-claude/pricing.md` and parses the
table under `## Model pricing` (its five rate headers; `$<n> / MTok` after
stripping `<sup>…</sup>`); **X1** `claude-opus-5-5` ↔ "Claude Opus 5.5" and
**X2** `claude-fable-5-1` ↔ "Claude Fable 5.1" compare each of the five rates
after `round(…, 6)`, a mismatch named `<id> <key>: table <a>, page <b>`.
`--mutant table` sets opus's cache_read to 0.21 in memory (X1 FAILs naming
`claude-opus-5-5 cache_read`); `--mutant page` deletes the "Claude Fable 5.1"
line (X2 FAILs naming `claude-fable-5-1`).

```sh
make prices                                               # network; the table's only writer
python3 tools/proof/prices_proof.py                       # C × 23, K, T, A: 26/26
python3 tools/proof/prices_proof.py --mutant py-disagrees # exit 1
python3 tools/proof/prices_proof.py --mutant ts-disagrees # exit 1
python3 tools/proof/prices_crosscheck.py                  # X0–X2 (network)
python3 tools/proof/prices_crosscheck.py --mutant table   # exit 1
python3 tools/proof/prices_crosscheck.py --mutant page    # exit 1
python3 agent/prices/update.py --api-base http://127.0.0.1:9   # the fetch control: exit 1, file untouched
```

**Measured 2026-09-28**, every command with `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY` unset: `make prices` wrote LiteLLM
`b79fc9f1b0249cb533391dd7c941082f0cd6ddb1` (2026-09-28T06:07:45Z), 20 rows;
a rerun printed `unchanged` and `diff` was empty. `prices_proof.py` scored
26/26 (bun test: 24 testcases, 0 failing; `cases.json` sha256
`ce70456a…763e1c`). `py-disagrees`: C:opus-cache-read, C:opus-mixed,
C:fable-cache-read, C:long-context and A FAIL, 21/26, exit 1.
`ts-disagrees`: T (failing `case: opus-mixed`) and A FAIL, 24/26, exit 1.
The fetch control: `error: fetching http://127.0.0.1:9/…: URLError …
Connection refused`, exit 1, the table's shasum `124dd034…` before and after.
The cross-check: 18 page rows parsed, X1 and X2 equal on all five rates,
3/3; `--mutant table` X1 FAIL "claude-opus-5-5 cache_read: table 0.21, page
0.2", `--mutant page` X2 FAIL "claude-fable-5-1: the page has no 'Claude
Fable 5.1' row", each 2/3, exit 1.

## Road map 13's P2 — the helper prices every response (`spend_proof.py`, `spend_probe.swift`; `prices_proof.py` R)

The helper keeps the price table in force (`agent/src/priceTable.ts`): the
bundled `anthropic.json`, or the cache `configure`'s `price_cache` names,
refreshed at most once a day from LiteLLM's raw `main` file (or
`price_feed`). It emits `prices` once per `configure` and a `cost` for every
response and compaction summary, at the prices in force when the turn
started. The app writes one `spend.jsonl` line per `cost` into the spend
folder and ends each turn's transcript with the cost line
(`AssistantSpend.swift`, spec §11 P-5).

**`prices_proof.py` R** (in `make test`): `update.py`'s `reduce_table` over
`agent/prices/reduce_cases.json`'s `litellm` block answers exactly its
`models` — the opus and fable rows, an `_above_200k_tokens` row, a row with
no `…_above_1hr`, a bedrock row dropped and batch fields dropped. The
helper's `reduceLiteLLM` answers the same fixture in `bun test`
(`reduce:` tests). `--mutant reduce-disagrees` raises the expected opus
input by 1: R FAILs, exit 1.

**`spend_proof.py`** — no network: the API is `anthropic_fake.py`, the feed
an in-process `http.server` on 127.0.0.1:0 serving the fixture's LiteLLM
block with opus input at `8e-06` (`/litellm.json`), the same without fable
(`/no-fable.json`), and one that holds its answer until the proof releases
it (`/held.json`). A stand-in reply is 100 input and 10 output tokens on
`claude-opus-5-5`: $0.0006 bundled, $0.001 at the feed; every expected
dollar is `prices.py`'s, every expected date the local date of the instant.

- **H1–H9**, the Release helper over stdio (`assistant_helper_proof`'s
  `Helper`): no cache (bundled, "no price cache is configured", one `cost`
  per POST equal to `prices.py`); a fetch (one GET, the cache written, the
  reply at $0.001); the same cache (cached, no GET); a cache aged 25 h and a
  dead feed (cached, with the `fetching …` problem, the cache unchanged); a
  feed without fable (bundled, the problem names `claude-fable-5-1`, no
  cache); `http://example.invalid/` (refused by name); compaction (`cost`
  count = POST count, a `cost` before `compaction_failed`);
  `claude-proof-model` (unknown, cause `model`); and the turn's prices over
  the held feed (the turn's two `cost`s bundled although `prices` (fetched)
  arrived between them, the next turn's fetched).
- **L0–L2**, the Release app (`assistant_session_proof`'s `App`;
  `assistant_tab_proof`'s `Dump`, `open_tab`; ports 4897, 4898): no
  `Reelcut: ` line; with `-RCSpendFolder` scratch and `-RCPriceFeed` local, a
  priming turn, the cache within 10 s, then a two-reply pane turn whose
  events carry `cost` only as `{type, cost, prices}` and `claude-opus-5-5`
  nowhere, one ledger line per `cost` with the listed keys only and no key or
  text, and the last entry exactly `Cost: $0.0020 · … (fetched <day>)`; with
  the override and no `-RCSpendFolder`, bundled with the problem, the feed
  hears nothing, and the person's `spend.jsonl` and `anthropic-prices.json`
  keep their existence, size and mtime (a concurrent person session can
  fail this row; rerun).
- **S1–S5**, `spend_probe.swift` over `app/Sources` on `build_probe`'s
  swiftc line: the cost line's formats and `day`
  (`2026-09-29T01:00:00Z` in America/New_York is `2026-09-28`; an
  unparseable `as_of` its first 10 characters); the transcript's sum and its
  resets; the ledger whitelist; `record` (two lines at 0600, a nested
  folder created, a file as the folder refused); P-5's table over a
  `UserDefaults` answering the argument domain.

Made to fail: `--mutant stale-refresh` builds a scratch `agent/` with
`REFRESH_AFTER_MS = 0` through its own `build.sh helper` and runs H2 and
H3 on it (H3 FAILs: a GET and a fetched `prices`); `--mutant
unknown-as-zero` runs the probe over a copy of `app/Sources` whose cost line
renders unknown as `$0.0000` (S1 FAILs). Either exits 2 when its instrument
did not build.

```sh
python3 tools/proof/prices_proof.py --mutant reduce-disagrees  # R FAIL, exit 1
python3 tools/proof/spend_proof.py                            # 17/17
python3 tools/proof/spend_proof.py --mutant stale-refresh     # H3 FAIL, exit 1
python3 tools/proof/spend_proof.py --mutant unknown-as-zero   # S1 FAIL, exit 1
```

Measured 2026-09-28: `spend_proof.py` 17/17; `stale-refresh` 1/2 (H3 FAIL:
no `prices` before `ready`, 1 GET, a later fetched `prices`), exit 1;
`unknown-as-zero` 4/5 (S1 FAIL: `Cost: $0.0000 · …` for an unknown), exit 1;
`prices_proof.py` 27/27 and `reduce-disagrees` 26/27, exit 1.

## Road map 13's P3 — the proofs' ledger and the budgets (`budget.py`, `budget_proof.py`)

Every paid proof request is held to the month's budget (spec §11 P-3, P-6):
$25 for Anthropic, $5 for AssemblyAI, the owner's numbers, constants in
`budget.py` that nothing takes from a flag or the environment.

**`budget.py`** (stdlib and `prices.py`) is the only writer of the proofs'
ledger, `LEDGER` = `~/Library/Application Support/Reelcut Proofs/spend.jsonl`
— outside the repo, so it survives `rm -rf tools/proof/work` and a clone and
every worktree shares it, and outside the app's spend folder (P-5). One JSON
object per line, appended with one `os.write` to a file opened
`O_APPEND|O_CREAT` 0600 in a folder made 0700: `format` 1, `at` (UTC,
`%Y-%m-%dT%H:%M:%SZ`), `service`, `kind`, `id` (`<proof>/<run>/<pid>/<n>`);
a `reserve` adds `proof`, `run`, `row`, `worst`; a `refused` adds those and
`month_total`, `budget`; a `settle` adds `dollars`, `basis` and, for
Anthropic, `model` and `usage`, for AssemblyAI `seconds`. Never a key, a
header, a body or a text.

- `SpendLedger(path, service, proof, run, now=None)` — `month()` (UTC),
  `month_total()`, `refusal(worst)` (writes nothing), `reserve(worst, row,
  gate=True)`, `settle(rid, dollars, basis, **detail)` (never raises),
  `describe()`. The month's total is a fold: a `reserve` made in the month
  counts its largest `settle`, or its `worst` while it has none; a `settle`
  with no `reserve` counts its own dollars in its own month; a `refused`
  counts nothing. `reserve` reads, folds and appends under one
  `flock(LOCK_EX)`, and with `gate` appends a `refused` line and raises
  `BudgetRefused` (`budget: $<total> of the $<budget> <service> budget is
  recorded for <YYYY-MM> (UTC) in <path>; this request's worst case is
  $<worst>`) when total + worst passes the budget. It fails CLOSED: a line
  that does not parse, or a file that cannot be read or written, refuses by
  name until a person repairs it.
- `anthropic_worst_row(table)` — each class's dearest usable rate over every
  row and `above_200k` tier; the relay's `RATES` come from it.
  `settle_anthropic(usage, model, table, reserved, whole)` — `table` at
  `prices.price`; else, less `speed` / `service_tier` / `inference_geo` and
  each iteration's `model`, at the worst row, `worst`; else, or when the
  reply was not whole, the reservation, `reserved`.
- `assemblyai_rates()` reads `AssemblyAIRates` in
  `app/Sources/CloudEstimate.swift` — `perHour`, `speakersPerHour` and
  `readOn` must each be declared exactly once, as a literal, inside the enum
  (its use sites elsewhere in the file are ignored), else `ValueError`.
  `assemblyai_worst(seconds)` adds both rates; `assemblyai_dollars(seconds,
  speakers=False)` is the billed price.

Only a keyed live run opens `LEDGER`: `assistant_prompt_proof.py --live`
with the key, and `cloud_captions_proof.py --live` with `RC_ASSEMBLYAI_KEY`
(`cloud_live_ledger.LiveLedger`). Rehearsals, CONTROLs and `budget_proof.py`
use scratch ledgers.

**`budget_proof.py`** — a line of `make test`; no network, no app, no
key. It works in `work/budget/` (made fresh), prints `<ID> ok|FAIL — detail`
and then `n/m`, exits 0 or 1, and scores an instrument that cannot run as a
FAIL.

- **P** the budgets are `{anthropic 25, assemblyai 5}`; `LEDGER` is absolute
  and outside the repo; worst POST ≤ the floor ≤ `SUGGESTED_CAP` ≤ $25.
- **F1** the fold over a hand-written file: last month's $30 counts nothing;
  this month's reserve 2 settled 0.5, open reserve 1, refused 9 and orphan
  settle 0.25 → $1.75; AssemblyAI's 4 settled 4 → $4.00. **F2** an absent
  file is $0; a non-JSON line refuses naming `line 2`, and `reserve`
  appends nothing.
- **G1** at $24.00 a $1.00 reservation passes (the edge) and $0.01 is refused
  `budget:` with exactly one `refused` line; `gate=False` still records.
  **G2** with an injected clock, $25 recorded in August counts nothing in
  September. **G3** a nested folder is created 0700 and the file is 0600.
- **W** `anthropic_worst_row` over a two-row fixture (one tiered) is the
  per-class maximum; no committed rate exceeds it, and it equals the
  proof's own loop over the table.
- **S1** a known model settles at `prices.price`'s dollars, `table`; **S2** an
  unknown model and a `speed: fast` request at the counts × the worst row,
  `worst`; **S3** an unknown-model iteration the same; **S4** a malformed
  count and a reply that is not whole at the reservation, `reserved`.
- **U1** `read_usage` keeps `service_tier` and the `cache_creation` object,
  overlays `message_delta`'s output, and a stream with no `message_stop` or
  a body with no `usage` is not whole. **U2** `Evaluation.finish` over a
  usage holding a string, an object and a bool totals only the integers.
- **R1–R4** `ev.Relay` over `anthropic_fake.py` with a scratch proofs'
  ledger: a streamed `claude-opus-5-5` POST forwarded, reserved at
  `measure`'s worst and settled $0.0006, `table`; at $24.999 recorded and a
  cap of 1.5 × the POST's worst, TWO POSTs each answered 400 naming the
  budget, nothing sent to the stand-in, two `refused` lines, no cap refusal
  and `_reserved` 0 (a leaked cap reservation would make the second a cap
  refusal); a cap below the worst answers the cap and writes no
  proofs'-ledger line; upstream `http://127.0.0.1:9` answers 502 and settles
  at the reservation, `reserved`.
- **A1** `assemblyai_rates()` is finite, its `per_hour` equals
  `aai.RATE_PER_HOUR`, and a copy of `CloudEstimate.swift` without its one
  `static let perHour` line (the use sites kept) is a `ValueError`. **A2**
  `cloud_live_ledger.controls()`'s budget CONTROL holds: over scratch ledgers
  seeded at this month's $5.00, a gated `LiveLedger.reserve` is refused
  `budget:` and neither ledger gains a reservation, while an `extra` is
  recorded in both. **A3** a `LiveLedger` reservation `billed` 11 s settles
  `assemblyai_dollars(11)`, one closed `no_upload` settles $0, and the
  month's total is their sum.
- **A4** (issue batch B7, #163) `cloud_live_ledger.spike_ledger` over scratch
  files: unkeyed, it is a plain `aai.Ledger` and writes no spend file; keyed,
  one reservation writes one `reserve` line with proof `words_spike` and an
  `upload_only` close settles it at $0; keyed over a spend file seeded at
  this month's $5.00, `reserve` raises `aai.BudgetError` starting `budget: `
  and the run ledger gains nothing. **A5** each spike's text
  (`cloud_spike.py`, `words_spike.py`) has one `spike_ledger(` and no
  `aai.Ledger(`; CONTROL: that text with `spike_ledger(` turned into
  `aai.Ledger(` fails the predicate.
- **N** `LEDGER`'s existence, size and mtime are the same before and after.

Made to fail on purpose: `--mutant no-budget` sets both budgets to infinity
in memory (P, G1, R2, A2 and A4 FAIL); `--mutant unknown-as-zero` replaces
`budget.anthropic_worst_row` with all-zero rates after import (W, S2 and S3
FAIL). Either exits 1.

```sh
python3 tools/proof/budget_proof.py                          # 23/23 (make test)
python3 tools/proof/budget_proof.py --mutant no-budget       # P G1 R2 A2 A4 FAIL, exit 1
python3 tools/proof/budget_proof.py --mutant unknown-as-zero # W S2 S3 FAIL, exit 1
(unset ANTHROPIC_API_KEY RC_ASSEMBLYAI_KEY; python3 tools/proof/assistant_prompt_proof.py --rehearse --month-spent 24.99 --cap 10)  # E1–E6 FAIL budget:, exit 1
```

Measured 2026-09-28, every command with `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY` unset: `budget_proof.py` 21/21 (R1 reserved $0.050807
at `measure`'s worst and settled $0.0006 `table`; R2 two 400s naming the
budget at $24.9990, 0 stand-in POSTs, `_reserved` 0); `no-budget` 17/21 (P,
G1, R2, A2 FAIL), exit 1; `unknown-as-zero` 18/21 (W, S2, S3 FAIL), exit 1.
`assistant_prompt_proof.py --rehearse` 22/22 with K SKIP, H's worst POST
priced $3.1137, the scratch ledger at $0.0072 after six rows; `--rehearse
--month-spent 24.99 --cap 10` E1–E6 FAIL `budget:` (worst cases
$3.1031–$3.1049), "0 on the cap, 6 on the budget, 0 otherwise", the
stand-in logged 0 POSTs, exit 1; `--rehearse --cap 0.0001` E1–E6 FAIL
`cap:`, "6 on the cap, 0 on the budget", exit 1. `cloud_captions_proof.py
--live` with no key: the eight CONTROLs ok (the budget one included), 29
rows SKIP "absent", 9/9. `budget.LEDGER` was absent before and after every
command.

## Road map 13's P4 — spend in the UI (`spend_ui_proof.py`, `spend_ui_probe.swift`)

The app shows two figures, each Reelcut's own estimate (spec §11 P-4, P-7):
the Assistant tab's Spend row, the transcript's sum of `cost` events since
its last Clear (`AssistantTurnCost.figure`, `assistant.spend`), and Settings
▸ Assistant's month line, `spend.jsonl` folded over the UTC calendar month
off main (`AssistantSpendMonth.swift`, `settings.assistant.spend`, with its
note `settings.assistant.spendnote`). No network, no key but the dummy
`proof-key`, every child with `ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY`
popped; work in `work/spend_ui/`.

- **M1–M3, C1–C3**, `spend_ui_probe.swift` over `app/Sources` on
  `assistant_tab_proof`'s `build_probe` line, run with
  `TZ=America/Los_Angeles` (so a local-zone month would differ from UTC's at
  both edges) and a scratch folder: the fold over a September 2026 fixture
  (both edges in, the seconds either side out, a fractional second in,
  `dollars` null and `true` unpriced, a torn line, `[]` and a bad time
  unreadable, `assemblyai` skipped, blanks ignored = {0.875, 3, 2, 3}); every
  Settings sentence and `amount`; `month` and `title` at both edges; the
  transcript's conversation sum, its figures and `.conversationCost` before
  `.usage` on `clear()` and `endConversation`; `AssistantView.reload` /
  `apply` → `assistant.spend` and its tooltip; the pane in an
  `orderFrontRegardless()` window — no folder, an absent ledger (still absent
  after), a fixture ledger (`Reading the spend ledger…`, then its sentence
  within 5 s), then `AssistantSpend.record` → the sentence unchanged when
  `record` returns, then the new one within 5 s.
- **U0–U3**, the Release app (`asp.App`, the stand-in; ports 4899, 4893):
  no `Reelcut: ` line; a seeded `-RCSpendFolder` ledger (this UTC month's
  start + 1 s priced, the previous month's end − 1 s, one unpriced, one
  torn) → Reelcut ▸ Settings… and `snapshot_ui window: settings`: the month
  line equals the script's own Python fold and sentence, the note is exact,
  and neither label has a layout problem; the tab
  reads "Nothing yet", then after a two-reply and a one-reply pane turn
  "$%.4f · Reelcut's estimate" of the tool-view dollars, and Settings,
  re-captured (up to 5 s), equals the fold of the ledger as it now is; with
  the override and no `-RCSpendFolder`, "This launch keeps no spend
  ledger.", and the person's `spend.jsonl` and `anthropic-prices.json` keep
  their existence, size and mtime across that launch and the whole run.

Made to fail: each mutant runs the probe rows over a copy of `app/Sources`
with one literal of `AssistantSpendMonth.swift` replaced, exactly once, and
exits 1 when its named rows all FAIL, 3 when one passed (it survived), 2 when the literal
is not found once or the probe did not build. `--mutant local-month`
(`TimeZone.gmt` → `TimeZone.current`) FAILs M1 and M3; `--mutant
unknown-as-zero` (`summary.unpriced += 1` → `summary.priced += 1`) FAILs M1.

```sh
python3 tools/proof/spend_ui_proof.py                            # 10/10
python3 tools/proof/spend_ui_proof.py --mutant local-month       # M1 M3 FAIL, exit 1
python3 tools/proof/spend_ui_proof.py --mutant unknown-as-zero   # M1 FAIL, exit 1
```

Measured 2026-09-28, every command with `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY` unset: `spend_ui_proof.py` 10/10 (U1 "September 2026
(UTC): 2 responses; 1 could not be priced, the rest came to $0.50. 1 ledger
line could not be read."; U2 the tab "$0.0018 · Reelcut's estimate" over
three $0.0006 responses, Settings "… 5 responses; …"); `local-month` 4/6
(M1 dollars 100.375 for 0.875, M3 the month starting 2026-08-01 07:00 UTC),
exit 1; `unknown-as-zero` 4/6 (M1 priced 5, unpriced 0; C3 also FAILs),
exit 1. The person's two files were absent before and after.

Measured again 2026-09-29 (issue batch B5), once U1 no longer counted a 2 pt
label overhang apart (the layout rule measures alignment rects since #140):
`spend_ui_proof.py` 10/10, U1's "layout problems on the two labels []" with
the same month line as above, U2 the tab "$0.0018 · Reelcut's estimate" over
three $0.0006 responses and Settings "… 5 responses; …"; the person's two
files absent before and after.

## Issue batch B1 — export cancel, the nested gate, import_media's wait (`export_cancel_proof.py`, `export_cancel_probe.swift`)

Three fixes against the built app: the pre-export graphics gate follows nests
however deep (#73), `import_media` waits as long as an ffmpeg conversion may
run (`FFmpegRewrap.longestConversion` + 300 s, #67), and an export's Cancel
during the loudness measurement only sets a flag, the measurement's own loop
cancelling its reader (#74, spec §11 G-17). One owned instance on
`--port` (4893), launched with `-ApplePersistenceIgnoreState YES
-AgentServerEnabled YES -RCFFmpegImport always -RCFFmpegPath
<work>/standin/ffmpeg` and stopped by PID; work in `work/export-cancel/`,
its log `reelcut-<port>.log` there. Every child runs under
`graphics_spike/bounded.py`. `--only gate,import,cancel` picks groups (Z1
always runs); `--runs` (30) is M1's count.

- **G1** (CONTROL) `write_graphic gate` (compiles, 30 frames, one rect),
  `add_graphic_clip`, `nest` it, `add_text_clip` right after, `nest` both:
  `get_project` shows timeline nest clip → nest B (a nest clip and the
  text) → nest A (the `gate` clip), and `export h264` writes its file.
- **G2** `write_graphic gate` with a syntax error answers `ok: false` (and
  `get_project`'s `graphics` says so within 5 s); `export h264` onto a
  sentinel file is an error starting "The export was not started:" naming
  `"gate"`, and the sentinel's bytes are unchanged.
- **I1** stand-in tools, because the host's Homebrew ffmpeg does not load
  (`dyld: Library not loaded: …libx265.215.dylib`) and nothing here may need
  a real one: `standin/ffprobe` prints fixed JSON (one `h264` 640×360
  `30/1` stream, 10 s, 4096 bytes), so the plan is a stream copy;
  `standin/ffmpeg` exits 0 for `-encoders`, else sleeps 45 s, copies
  `media/A.mov` to its last argument (the app's `.partial.mov`) and touches
  `standin/ffmpeg.exited` on exit. `import_media` of 4096 random bytes as
  `slow-<uuid hex>.mkv` answers ok after ≥ 45 s, kind `video`, 640×360, a
  `.mov` directly inside `~/Library/Application Support/Reelcut/Rewrapped/`.
  Cleanup runs whatever the call answered and before the instance stops:
  it waits for `ffmpeg.exited` (120 s from the call), then for no
  `.partial.mov` (10 s), then deletes every Rewrapped entry starting
  `slow-<hex>-` whose resolved parent is that folder, and the fixture; an
  expired bound fails the row and names the leftovers.
- **M0** (CONTROL) 300 s of 48 kHz stereo 16-bit `os.urandom` noise
  (`wave`), imported over MCP onto four tracks at 0 with
  `noise_reduction: 1.0`, saved; the probe's uncancelled run is `success`
  with a measurement `window` ≥ 3.0 s.
- **M1** `--runs` probe runs, each cancelling from main `delay` s (uniform
  in [0.2, window/2], the seed printed) after "Measuring loudness…" first
  shows: every run rc 0 (a signal or an expiry is a crash), cancelled while
  the phase read "Measuring loudness…", `outcome` `cancelled`, no file left.
  Prints the crash count.
- **M2** every M1 latency (cancel to completion) ≤ 1.0 s.
- **Z1** no `Reelcut: ` line in the launch's log.

`export_cancel_probe.swift` is built like `graphics_proof.py`'s pin probe
(every `app/Sources` file but `main.swift`, this file as `main.swift`,
`harness/build.sh`'s swiftc line with `-D REELCUT_DEV_TOOLS`, `Fonts`,
`Blank.mp4` and a `default.metallib` beside it) into
`work/export-cancel-probe/`, rebuilt when stale; a probe that will not build
scores M0–M2 as FAILURES. `export_cancel_probe <package> <out.m4a>
<delay|-1>` opens the package as the app does, exports `audio_m4a` through
`Exporter`, polls `phaseDescription` in ≤ 10 ms run-loop slices under a
300 s deadline and prints one JSON object (`outcome`, `error`, `window`,
`phase_at_cancel`, `latency`, `left`).

Made to fail, each by hand, reverted and rebuilt after:

- (a) + (b) in ONE `make app`: `collectGraphicNames`' recursive call removed
  and `probeCeiling` set to 30 → `--only gate,import`: G2 FAIL ("The export
  was stopped: the graphic "gate" does not compile — … No file was
  written.", sentinel changed — the mid-export abort, not the gate), I1 FAIL
  (30.0 s, "Timed out reading slow-<hex>.mkv."; cleanup clean), exit 1.
- (c) `ExporterLoudness`'s in-loop `isCancelled` early return removed (probe
  rebuild only) → `--only cancel --runs 5`: M2 FAIL, latencies 73.5–136.7 s
  (the measurement runs to its end), M1 ok, exit 1.
- CONTROL, measured not scored: HEAD's `Exporter.swift` and
  `ExporterLoudness.swift` (the main-thread `cancelReading` in `cancel()`)
  → `--only cancel --runs 30`: 0 crashes of 30, latencies 0.358–0.842 s.
  This fixture does not reproduce a crash with the old cancel; the change
  rests on G3c's writer-side crash (12 of 30) and on G-17's rule, not on a
  crash seen here.

```sh
python3 tools/proof/export_cancel_proof.py --port 4893          # 7/7
python3 tools/proof/export_cancel_proof.py --only gate,import    # G1 G2 I1 Z1
python3 tools/proof/export_cancel_proof.py --only cancel --runs 5
```

Measured 2026-09-29, every command with `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY` unset, two full runs: 7/7 both times; I1 45.4 s both;
M0 window 143.0 s and 139.5 s; M1 0 crashes of 30 both; M2 latencies
0.421–0.889 s and 0.411–0.790 s. M2's 1.0 s bound is not far above them:
the cancel waits for the sample buffer in flight over four noise-reduced
tracks. The second full run took 1632 s of wall time, most of it M1 (each
run measures for its `delay`, up to window/2).

## Issue batch B3 — editor keys, undo steps, the transition ring (`editor_keys_undo_proof.py`, `editor_keys_undo_probe.swift`)

kpgalligan/reelcut#59 #60 #61 #66 #68 #69. `python3
tools/proof/editor_keys_undo_proof.py`, no port and no running app. The probe
is compiled AS `main.swift` over `app/Sources` (`harness/build.sh`'s swiftc
line; a build failure is a scored FAILURE) with `Compositor.metal` built
beside it, and runs with `-ReelcutInspectorCollapsed NO` and
`ANTHROPIC_API_KEY` / `RC_ASSEMBLYAI_KEY` popped. The driver writes four
packages under `work/editor-keys-undo/`: `card` (`space_key_proof.py`'s
fixture — a grey card 0–6 s, then `media/A.mov` as clip 3 at 6–12 s),
`ringPair` (shape cards A 0–6 s and B 4–10 s with a linear cross dissolve
in), `ringAlone` (A only) and `ringAbut` (A, and B at 6–12 s with no
transition). F, C, R and M each open their OWN fresh `card` editor
(`makeWindowControllers()`), so no group's undo stack or open implicit group
reaches another; keys are synthesized `NSEvent`s through `window.sendEvent`.

- **U** (#59, a windowless document, two text clips): U1 an identity and U2 a
  refused move through `performGroupedEdit`, each from a redo of its own,
  leave undo and redo as they were. U3 (control) a real grouped edit
  registers one step named for it.
- **F** (#60, clip 2 on the Picture sub-tab, the Transform section's Scale
  field): F1 type `50`, Return → `video.scale == 0.5` AND the editor's root
  view is first responder; F2 then a bare I sets the in point; F3 focus the
  field again, Esc, then a bare O sets the out point.
- **C** (#61, the root view first responder): C1 I with Caps Lock; C2 ↓ with
  `[.numericPad, .function]` steps to 6 s; C3 End with `[.function]` goes to
  12 s. C4 (control) `handleEditorKey` answers false for ⌘I, ⌥I, ⌃I and ⌥↓,
  and none moves the range or the playhead.
- **R** (#69, `beginClipRename(2)`, "Renamed" typed): R1 Esc closes the
  field, keeps the name, makes no undo step and leaves the root view first
  responder; R2 a rename ended by `beginGesture` on the track's M: the first
  undo unmutes and keeps "Renamed", the second restores the name. R3
  (control) Return commits one "Rename Clip" step.
- **M** (#68, the Media tab, `MediaPane.select(20)`, searches through
  `MediaSearchField.controlTextDidChange`): M1 (control) "A.mov" keeps
  media 20 selected and Insert / Overwrite at Playhead live; M2 "zzz" clears
  `selectedMedia` and both go dead.
- **D** (#66, `cacheDisplay` of the timeline's content): the device-pixel
  columns wholly inside A's ring stroke, `[body.maxX − 2, body.maxX]`, over
  the stroke's straight run (1 pt + the clip radius in from the body's top
  and bottom). D1 with A selected ringPair's columns are byte-identical to
  ringAlone's; D2 (control) with nothing selected they differ; D3 (control)
  ringAbut with A selected is byte-identical to ringAlone.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` in
`work/editor-keys-undo/baseline/`, linked to the CURRENT `libreelcut_core.a`
(valid while a batch changes nothing under `core/`), and exits 0 only when
EXACTLY U1 U2 F1 F2 F3 C1 C2 C3 R1 R2 M2 D1 fail there and every control
passes. Needs `media/A.mov` (a scored row when missing), no ffmpeg.
Measured 2026-09-29: 21/21 on the fix (18 probe rows); `--baseline 97e870a`
(HEAD before the batch) fails exactly those twelve and exits 0.

```sh
python3 tools/proof/editor_keys_undo_proof.py                     # → 21/21
python3 tools/proof/editor_keys_undo_proof.py --baseline 97e870a  # exit 0 = exactly the twelve FAIL
```

## Issue batch B7 — one tree copy, stale pins, proof nits, spike ledgers (`tree_copy.py`, `capture_spike/inventory.py --check`; #146 #156 #166 #77 #82 #163)

**One tree copy (#146).** Every proof that builds the app in a copy gets the
copy from `tree_copy.make_copy(dest, agent=True)`. The rule: `app/` (without
`Info.plist` or `*.entitlements`) and `agent/` (without `node_modules`) are
COPIED, because the build writes into them; `project.yml` and `Makefile` are
copied; every other top-level directory `project.yml` names as `NAME/` (not
after a name character) is a SYMLINK to the tree's, found by
`build_inputs()` rather than listed by hand — today `core`, `docs` and
`graphic`. `build` and `Reelcut.xcodeproj` are never linked. So the next
build input a `project.yml` step reads is in every copy the day it lands.
The builders: `makefile_env_proof.make_copy` (`work/makefile-env/tree`), the
session, tab and prompt mutants (`work/<proof>/mutant/tree`), the cloud
mutants (`work/cloudproof/mutants/<name>`) and graphics' `frame-plus-one`
(`work/graphics/mutant`), the last two now built by the copy's own
`make app` (whose `unexport` keeps both keys out of the copy's build
database) instead of xcodegen and xcodebuild; and the assistant spike's
`make_tree` (`agent=False`), which removes the copy's own `Build Agent
Helper` item from its `project.yml` before splicing Rasterize's in (B3's
anchors "project.yml's own Build Agent Helper item" and "one Build Agent
Helper step"). `python3 tools/proof/tree_copy.py --selftest` scores T1–T4:
the five inputs found and neither generated name; a copy's shape; `agent=False`
leaves no `agent`; and the CONTROL that a `designs/` line in `project.yml`
adds `designs`.

The cloud mutants `silent-about-the-bill` (row B) and
`marker-over-stale-file` (row M) are re-aimed at today's text; every
`CLOUD_MUTANTS` before-text occurs exactly once in the tree.

**Row 18 (#156)** of `cloud_captions_probe.py --only chrome` compares only
`project.yml`'s `info:` and `entitlements:` blocks (`project_yml_blocks`)
against the baseline's: 14 lines (the `LSMinimumSystemVersion` bump, the
deleted Speech usage string and the microphone comment's aside). The ATS
and microphone checks stay.

**The inventory's sites by token (#166).** `inventory.resolve` pairs the
inventory's sites with the grep's per file and token, in line order, when
the two counts agree (otherwise each pin stands as written); I2 and I3 read
through that mapping, and `line_of`'s cache is keyed by the full path.
`python3 tools/proof/capture_spike/inventory.py --check` is a line of
`make test`, no app: K1 I2 and I3 over the tree, its detail listing the pins
found at another line; K2 (CONTROL) three lines put at the top of every file
holding a site, no problem; K3 (CONTROL) the inventory's site keys rewritten
through `resolve`, the first one's line blanked, exactly that site reported
under I2. Residue: a SWAP inside one file and token — one site removed and
another added, so the group's counts still agree — is absorbed by the
in-order pairing and I2 reports neither; the old line pins caught it. The
b7Probe row below is that case.

**The format version (#77).** `words_core_proof.py` reads
`RC_FORMAT_VERSION` from `core/include/reelcut_core.h`
(`CURRENT_VERSION`, `NEWER_VERSION = CURRENT + 1`); the version gate's and
save-and-reopen's rows are built from the two.

**#82's boxes.** (1) `harness/main.swift` and `phase4_chrome.py` say what is
true: the app reaches `CaptionCues.build` through `CaptionPages` once a
transcription (`SpeechTranscriber`, no grant, spec §11 W-8, or the cloud
engine) has produced words, and `transcribe` over MCP; the harness's cue
mode is the one place that hands it an arbitrary word list. (2)
`speech_engine_probe.swift`'s P8 cancels the stall and requires it to drain
within 5 s (both branches). (3) `cloud_rows.record_delete`: a 2xx closes the
reservation `deleted` with its status; anything else leaves it open (owed by
`undeleted()`, retried by the next `settle`) and answers `delete_failed`.
Beyond `speech_rows._cloud_call`'s q2, it is used at `cloud_rows.call` and
at both spikes' `settle` undeleted loops. (4) `media_less_playback_probe.py
--sources <missing>` fails every row with "--sources <path> is not a
directory" and exits 1, no traceback. (5) `graphics_menu_probe.swift`'s M3
finds From File… by title and action, not as the Graphic menu's last item.
(6) Struck: since 77b0bb8 the cited scripts read `tools/list` through
`mcp.schemas()`; the literals that remain are property names a check has to
spell, an app-state tool has no table to read them from, and the gate
refuses a stale name loudly.

**The spikes' ledger (#163).** A keyed C0 or W0 run makes its ledger with
`cloud_live_ledger.spike_ledger`: a `SpikeLedger` (a `LiveLedger` whose
refusal is the `aai.BudgetError` the spikes catch, and whose `upload_only`
settles at $0) over the proofs' ledger; unkeyed, a plain `aai.Ledger`.
`budget_proof.py` A4 and A5 hold it (P3's section).

Measured 2026-09-29, `RC_ASSEMBLYAI_KEY` and `ANTHROPIC_API_KEY` unset for
every run that could read them, the proofs' `spend.jsonl` absent before and
after:

| Command | Answer |
|---|---|
| `tree_copy.py --selftest` | 4/4 |
| `capture_spike/inventory.py --check` | 3/3 (K1: `WelcomeWindowController.swift:189 → 204`) |
| …with `func b7Probe() { _ = NSAlert().runModal() }` appended to `AppDelegate.swift` (reverted) | K1 FAIL naming `AppDelegate.swift:255`; K2 FAIL (the copies carry it: four `runModal` sites against three pins, so each pin stands as written and the three-line shift breaks them); K3 FAIL with `[]` (blanking `:121` brings the group back to three and three, `resolve` re-pairs `121 → 170 → 212 → 255` in line order, and neither the blanked pin nor the new site is reported — the swap residue above); 0/3, exit 1 |
| …with two lines atop `AppDelegate.swift` (reverted) | 3/3; K1 lists `121 → 123`, `170 → 172`, `212 → 214` and `189 → 204` |
| `make typecheck` | 0 errors, 7 warnings, tsc silent |
| `make test` | exit 0; lane 12/12, prompt probe 11/11, prices 27/27, budget 23/23, inventory 3/3 |
| `budget_proof.py --mutant no-budget` | 18/23, P G1 R2 A2 A4 FAIL, exit 1 |
| `cloud_spike.py --selftest` | 25/25 |
| `words_spike.py --only q2` (scratch work root) | q2 skipped: `RC_ASSEMBLYAI_KEY is not set`, exit 2 |
| `make app` | BUILD SUCCEEDED |
| `makefile_env_proof.py` | 3/3 |
| `cloud_captions_proof.py --mutant silent-about-the-bill` | built; 169/171, the two row-B checks FAIL, exit 1 |
| `cloud_captions_proof.py --mutant marker-over-stale-file` | built; 169/171, the two row-M checks FAIL, exit 1 |
| `graphics_proof.py --mutant frame-plus-one --port 4898` | built; P1 ok, P2 FAIL, exit 0 |
| `assistant_session_proof.py --mutant no-prepare` | built; W FAIL, 0/1, exit 1 |
| `assistant_tab_proof.py --mutant no-forward` | built; L2 FAIL, 0/1, exit 1 |
| `assistant_prompt_proof.py --mutant bare-send` | built; S2 FAIL, 0/1, exit 1 |
| `assistant_spike.py --only B` | B1–B6 pass, B3 "11 anchors, each once"; the copy's `project.yml` holds one `name: Build Agent Helper` |

Before and after, on the tree (HEAD 5481ce6, then this batch):

| Command | HEAD | B7 |
|---|---|---|
| `cloud_captions_probe.py --only chrome` | 75/76, row 18's `project.yml` check FAIL | 76/76 |
| …a temporary line inside `info:` / in `postBuildScripts` (reverted) | — | 75/76 (row 18 FAIL) / 76/76 |
| `v2_menu.py 4899 --only H` | 4 pass, 1 fail (H1: `WelcomeWindowController.swift:189` stale) | 5 pass |
| `words_core_proof.py 4893` | 27/27 | 27/27 (the header at 11: `11 12`; restored: `10 11`) |
| `speech_engine_proof.py 4894 --no-mutants` | 29/29 | 29/29 (P8: drained within 5 s: true) |
| `graphics_menu_proof.py --port 4895` | 14/14 | 14/14; From File… removed (reverted): 12/14, M2 and M3 FAIL |
| `media_less_playback_probe.py` | 32/32 | 32/32 |
| `media_less_playback_probe.py --sources /nonexistent/Sources` | a `FileNotFoundError` traceback, exit 1 | 0/32, each row "--sources /nonexistent/Sources is not a directory", exit 1 |
| `phase4_chrome.py` | 59/59 | 59/59 |

`grep "Reelcut: "` printed nothing over every instance's log.

```sh
python3 tools/proof/tree_copy.py --selftest                       # → 4/4
python3 tools/proof/capture_spike/inventory.py --check            # → 3/3 (make test)
```

## Issue batch B8 — the graphics store and menus, render_graphic's svg arguments, the Graphic sub-tab (`graphics_store_probe.py`, `graphics_menu_proof.py`, `graphics_inspector_proof.py`, `graphics_proof.py`; #75 #104 #106)

Spec §11 G-19 is the decision. The new rows:

- **`graphics_store_probe.py`** — W14 (a font and an asset rewritten IN
  PLACE each post once with `library` true: every font and asset file has
  its own source, at most 16 a pass), W15 (a write over an immutable `q.js`
  throws and leaves no `.partial` and the file as it was), W16
  (`holdsContent` ignores a `.partial`), C5 (the untitled graphics root is
  removed at close and at the first save's re-point; CONTROL: a saved
  package's `graphics/` stays) and C6 (the untitled cache root is removed at
  close ONLY — it survives the first save, whose package holds the copy;
  CONTROL: an opened package's `cache/` stays). Mutants `partial-left` (W15),
  `scratch-kept` (C5), `cache-kept` (C6), `no-library-file-sources` (W14);
  `no-file-sources` (W4) is re-anchored on the module arm line plus the two
  after it, because the library arm line spells the same call.
- **`graphics_menu_proof.py`** — M11 (a `counter.js` written to disk a moment
  before Insert ▸ Graphic is not overwritten: the clip is `counter-2`) and
  M12 (a module that is not UTF-8 is refused before it is written).
- **`graphics_inspector_proof.py`** — I6 reworked (a default, a `max` — the
  rebuilt slider's `upper` follows — and an enum's options each change the
  signature), I13 (`decimals(for:)` and "0.50"), I14 (the Title field's own
  height is `DS.controlHeight`, and its row fits as tall as Offset's), I16
  (the schema and layer memos), I17 (the Document tab's marker name field's
  height) and I15 (two clips' asset names in the popup and the signature).
  `--mutant` is now a table of seven, each held to "exactly these rows fail".
- **`graphics_proof.py`** — C5 (`render_graphic` svg refuses `path`, then
  `background` and `max_width`, by name, and writes no file), C6 (frame 150
  of a 120-frame module is DRAWN, `progress` 1) and G8's untitled root gone
  after the first save.

Run on 2026-09-29 (this host: ffmpeg is broken, `libx265.215.dylib` not
loaded, so `graphics_proof.py`'s pixel rows fail for that reason alone):

| Command | Answer |
|---|---|
| `make typecheck` | 0 errors, 7 warnings, tsc silent |
| `make app` | BUILD SUCCEEDED |
| `capture_spike/inventory.py --check` | 3/3; `ProjectDocument.swift` still 1335 lines |
| `graphics_store_probe.py` | 22/22 |
| `graphics_store_probe.py --mutant partial-left` / `scratch-kept` / `cache-kept` / `no-library-file-sources` | MUTANT PASS: W15 / C5 / C6 / W14 failed, and nothing else |
| `graphics_store_probe.py --mutant no-file-sources` | MUTANT PASS: W4 failed (with W2, W10, W11) |
| `graphics_menu_proof.py --port 4871` | 16/16 |
| …`holdsModule`'s disk check removed by hand (reverted) | 15/16, M11 FAIL: clips `counter`, `counter.js` overwritten |
| …`String(decoding:as:)` restored in `insertGraphic` by hand (reverted) | 15/16, M12 FAIL: `latin1.js` written, "does not compile" |
| `graphics_inspector_proof.py --port 4872` | 59/59 |
| `graphics_inspector_proof.py --mutant` each of `stale`, `entry-signature`, `step-decimals`, `title-height`, `marker-height`, `merged-asset-names`, `no-schema-memo` | MUTANT PASS, each exactly its rows (5, 3, 2, 1, 1, 1, 1) |
| `graphics_proof.py --port 4873` at the pre-change HEAD (a tree copy) | 29/40; A1 C1 C2 I1 I2 I4 W1 C4 E4 Q1 Q2 FAIL (ffmpeg) |
| `graphics_proof.py --port 4873` with B8 | 31/42; the same eleven FAIL; C5, C6, G8 and Z1 ok |
| …in one hand-mutated `make app` (a tree copy: the svg refusal removed, a `frame >= length` refusal added) | 29/42; C5 and C6 FAIL besides the eleven |

`grep "Reelcut: "` printed nothing over every instance's log.

```sh
python3 tools/proof/graphics_store_probe.py                                  # → 22/22
python3 tools/proof/graphics_store_probe.py --mutant cache-kept              # → MUTANT PASS
python3 tools/proof/graphics_menu_proof.py --port 4871                       # → 16/16
python3 tools/proof/graphics_inspector_proof.py --port 4872                  # → 59/59
python3 tools/proof/graphics_inspector_proof.py --mutant title-height --port 4872
python3 tools/proof/graphics_proof.py --port 4873                            # C5, C6, G8
```

## Issue batch B9 — a lane queue per document, the session's two unproven paths, the prompt's literals, the support folder at 0700 (`assistant_lane_proof.py`, `assistant_tab_proof.py`, `assistant_prompt_proof.py`, `agent/`'s `bun test`; #148 #150 #158 #108)

`AgentLane.submit` now answers on its DOCUMENT's serial queue (#148), and
`AppSupport.ensureDirectory` is the one creator of the support folder and
anything under it, `0700` at each level it makes (#108); the helper's price
cache folder is made with `mode: 0o700`. The new rows:

- **`assistant_lane_probe.swift`** (in `make test`) — L10 (#148: a question
  pending in window A, held by a `HeldHook`, holds A's next call but not
  window B's, which answers within 10 s; Deny then answers A's first as
  declined and runs A's second; no file), L11 (#150: the credential over
  literal dummies — the store first, `ANTHROPIC_API_KEY` trimmed, blank is
  none, and `store()` with `RC_ASSISTANT_BASE_URL` in its dictionary is an
  empty `MemoryStore` whose credential is the environment's) and L12 (#108:
  `ensureDirectory` makes `T/a/b/c` at 0700 each and leaves `T`, keeps a
  0755 `T/open`, refuses `T/file/x` as "`<T/file>` is not a folder",
  changes nothing on a second call; `FileStore.write` and
  `AssistantSpend.record` through it, every level 0700, all under the run's
  work folder).
- **`assistant_lane_proof.py`** (in `make test`) — S1 (each of
  `SUPPORT_CREATORS` spells no `createDirectory(` and calls
  `AppSupport.ensureDirectory(` once) and M2 (S1's checker over the tree
  with `AssistantSpend.swift`'s call put back must FAIL). `--mutant NAME`
  builds the probe over a copy of `app/Sources` in
  `work/assistant_lane/mutants/<name>/` with one text replaced once and runs
  its one row: `one-queue` (L10), `no-env-fallback` (L11), `mode-0755`
  (L12); exit 1 when the row fails, 2 when the copy cannot be made or built.
- **`assistant_tab_proof.py`** — P8 (#150, the probe alone under
  `--close <path>` against the stand-in: a window closed with an `export`
  question pending, the session held strongly so `deinit` cannot stand in —
  closed, `editor.assistant` nil, exactly one answer after the question,
  `{allowed: false, by: "close"}`, the window's next lane call answered
  within 10 s, no file, no stand-in failure). `--mutant` takes
  `no-forward` (unchanged: the `make app` tree copy and L2) and
  `no-close-decline` (the probe over a copy of `app/Sources` without
  `close()`'s `decline(by: "close")`, and P8 alone).
- **`assistant_prompt_probe.swift`** (in `make test`) — F7 also runs
  `checkLiterals` (every `none`/`null` in the three texts in double quotes,
  and `("none": the timeline)` with the live block's own no-scope word);
  F8 (every ask-first row's reason begins "It writes " or "It copies ", and
  the system prompt says "These tools write files, so each asks the person
  first: "); M5 (`"none"` unquoted must fail) and M6 (an ask-first
  `transcribe` that "spends the person's money" must fail).
- **`agent/src/priceTable.test.ts`** — "refresh: the cache's missing folders
  are made 0700; an existing folder keeps its mode".

Run on 2026-09-29:

| Command | Answer |
|---|---|
| `make typecheck` | 0 errors, 7 warnings, tsc silent |
| `make test` | exit 0; lane 17/17 (L0–L12, C1, M1, S1, M2); prompt probe F1–F8, M1–M6 ok, 14/14; prices 27/27 (T: 37 testcases, failing none) |
| `make app` | BUILD SUCCEEDED |
| `assistant_lane_proof.py --mutant one-queue` | L10 FAIL: Other on B "no answer", exit 1 |
| `assistant_lane_proof.py --mutant no-env-fallback` | L11 FAIL: 4/6 checks, exit 1 |
| `assistant_lane_proof.py --mutant mode-0755` | L12 FAIL: 1/6 checks, every level made 755, exit 1 |
| `sh agent/build.sh test` | 37 pass, 0 fail |
| …with `, mode: 0o700` dropped by hand (restored) | 36 pass, 1 fail: the new case (Expected 448, Received 493) |
| `assistant_tab_proof.py` | 17/17, P8 ok |
| `assistant_tab_proof.py --mutant no-close-decline` | P8 FAIL: no answer after the question, the next call unanswered in 10 s; 0/1, exit 1 |
| `assistant_tab_proof.py --mutant no-forward` | L2 FAIL; 0/1, exit 1 |
| `assistant_prompt_proof.py` | 18/18 pass, 8 skipped (E1–E6, H, K: not asked) |
| `assistant_session_proof.py` | 11/11 |
| `spend_proof.py` | 17/17; L2's person's files unchanged |
| `cloud_captions_probe.py --only secrets` | 40/40, "the DIRECTORY it created is 0700" ok |

`grep "Reelcut: "` printed nothing over every instance's log (each live
proof's L0/S0/A0 row).

```sh
python3 tools/proof/assistant_lane_proof.py                        # → 17/17
python3 tools/proof/assistant_lane_proof.py --mutant one-queue     # L10 FAILS, exit 1
python3 tools/proof/assistant_tab_proof.py                         # → 17/17
python3 tools/proof/assistant_tab_proof.py --mutant no-close-decline   # P8 FAILS, exit 1
python3 tools/proof/assistant_prompt_proof.py --probe              # F1–F8, M1–M6
```

## Issue batch B10 — save_project and the menu tool's undo step (`save_project_proof.py`, `v2_menu.py` U2; #138 #167 #58 #84)

`ProjectDocument.cacheDirectory` calls `packageContentsDidChangeOnDisk()`
when it creates `cache/` in a package that has none, only if the package's
date, read before it creates `cache/`, is still `fileModificationDate` (N1
keeps an outside change's conflict), and that method re-reads the date
through a FRESH `URL`: at open, `fileURL` still holds the date
NSDocument cached, so a re-read through it changed nothing. Measured: with
the call alone, and no fresh `URL`, the build scored 3/8 and refused every
in-place save, C3 included. `save_project {project, path}` whose path is the
document's own file, however spelled (`AgentServer.canonical`), is a plain
save (#138). `UIMenu.perform` runs a `ProjectDocument`'s item inside
`inUndoGroupIfRegistered` (`ProjectDocument+UndoGroup.swift`), whose group
opens at the item's first undo registration (#167).
`ProjectSnapshot.formatVersion` is `Int(RC_FORMAT_VERSION)` (#84). The
Verify bookkeeping moved to `SettingsWindowController+Verify.swift` as a pure
move (#58).

- **`save_project_proof.py <port> [--log PATH]`** — needs a fresh instance
  per run. Each row writes its own version-9 package under
  `work/save_project/`, with no `cache/`. T1 checks the parity log. P0
  (control) checks that `cache/` exists after the open. P1 is an unedited
  plain save: `unsaved_changes: false`, and `version` is the header's.
  P2 and P3 add a marker and save to the document's own path, spelled as
  opened (P2) or `<dir>/./<name>.reelcut` (P3): 1 marker on disk, and
  `get_project`'s path is unchanged string for string. C1 is an edited
  plain save. C2 (control) saves C1's document to `copy.reelcut`. C3
  (control) saves an unedited document to its own path. N1 dirties a
  document, removes its `cache/` from outside, has `import_media` recreate
  it, and wants the plain save refused as "changed by another application"
  with no marker on disk. A failed row quotes the tool's error.
- **`v2_menu.py` U2** — Add Marker, `undo`, View ▸ Zoom In, then `redo`
  must redo it; View ▸ Zoom Out, then `undo` must undo it.
- **`cloud_captions_probe.py`** — the hygiene row's `CloudTranscriber(` file
  and the `verify-*` mutants name `SettingsWindowController+Verify.swift`.
  `two-stores-per-sync` is re-aimed at `sync()`'s `effectiveCredential`
  line, with a second `self.store().read()`. It had been stale since
  49af3f4.

Run on 2026-09-29. Baseline = HEAD 7084a4d's `make app`, copied to
`work/b10/Reelcut-baseline.app`; its sources went to `work/b10/baseline-src/`.

| Command | Answer |
|---|---|
| `cloud_captions_probe.py --only chrome,settings_verify --sources <baseline-src>` | 116/116 |
| `cloud_captions_probe.py --only chrome,settings_verify,hygiene` (after #58) | 147/147; its 116 chrome/settings_verify rows identical to the baseline's |
| `… --only settings_verify --mutant verify-ignores-input` | 38/41, 3 SV rows FAIL, exit 1 |
| `… --only settings_verify --mutant verify-ignores-owner` | 37/41, 4 SV rows FAIL, exit 1 |
| `… --only chrome --mutant two-stores-per-sync` | 75/76: `18: ONE sync builds ONE store` FAIL, `got 2`; the other 74 rows identical to the unmutated run |
| `save_project_proof.py` on the baseline (before N1 existed) | 5 pass, 3 fail: P1 and C1 "The document “<name>.reelcut” could not be saved. The file has been changed by another application."; P3 path re-spelled `…/./p3.reelcut` |
| `v2_menu.py --only U` on the baseline | U1 pass; U2 FAIL, "redo: There is nothing to redo. Only an undo makes a redo step." |
| `cloud_captions_proof.py --binary <baseline>` | 171/171 |
| `make typecheck` | 0 errors, 7 warnings, tsc silent |
| `make test` | exit 0 |
| `make app` | BUILD SUCCEEDED |
| `save_project_proof.py` | 9/9 |
| `save_project_proof.py`, `cacheDirectory`'s `before == fileModificationDate` removed | 8 pass, 1 fail: N1 "saved … over an outside change; 1 marker(s) on disk" |
| `v2_menu.py` | 27/27, no skip |
| `editor_keys_undo_proof.py` / `refusal_probe.py` | 21/21 / 17/17 |
| `screens.py --only 03-empty-editor,04-editor` | 7/7, no `FixtureError` |
| `cloud_captions_proof.py` | 171/171, row for row as the baseline |

The issue's "locked" refusal (an edited save to the document's own path) did
not reproduce on the baseline. The sequences tried were add_marker,
write_graphic, add_text_clip and import_media, each followed by a save to
the document's own path. `grep "Reelcut: "` printed nothing on any launch
log.

```sh
python3 tools/proof/save_project_proof.py 4861        # fresh instance → 9/9
python3 tools/proof/v2_menu.py 4862 --only U          # U1, U2
```
