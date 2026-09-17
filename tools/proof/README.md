# tools/proof — driving a built Reelcut over MCP, and rendering its chrome offscreen

`CLAUDE.md`'s "Verifying a build" is the standard: the app is verified by
driving the built binary and comparing what it renders, not by reading
code. These are the scripts that do it — an MCP script per road-map-2 phase,
from phase 2 an offscreen-chrome script beside it, and for the fixes
`designs/reelcut-remaining.md` records, `remaining_proof.py` over MCP and
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
python3 tools/proof/phase4_proof.py 4823
python3 tools/proof/phase5_proof.py 4823
python3 tools/proof/phase6_proof.py 4823
python3 tools/proof/phase7_proof.py 4823
python3 tools/proof/phase8_proof.py 4823
python3 tools/proof/phase9_proof.py 4823
python3 tools/proof/patch_door_proof.py 4823
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
`phase9_chrome.py`; each paragraph below says what its own one renders into.
Phase 9 has two offscreen scripts: `phase9_probe.py` is a PROBE rather than a
photograph, for the reason its own section gives, and `phase9_chrome.py` is
the photograph of the one thing the harness cannot take — the breadcrumb's
corner, which is only wrong at a NON-ZERO vertical scroll (the header column
and the floating ruler do not overlap at rest) while every harness render is
at scroll 0. It is a probe too, one that builds a bare `TimelineView`, scrolls
it and captures through the harness's own `cacheDisplay` path; the untracked
`work/phase9-corner-probe/` that measured the fix at the time is superseded by
it and deleted. `remaining_probe.py` is a third probe: the app arithmetic
behind `designs/reelcut-remaining.md`'s fixes, one section per item, and its
last section photographs a bare `TimelineView`'s filmstrip tile the same way
`phase9_chrome.py` photographs the corner. `phase8_chrome.py` is the one
that puts WINDOWS on screen — its
`dispatch` mode activates a probe for about a second, because a key window is
the thing it measures.

The last line is `<n>/<n> checks passed`, and the exit status is non-zero if
any failed. The log's second line names the port the app actually bound (a
taken port falls back to an ephemeral one), and the same log is where the
startup parity check would complain — `grep "Reelcut: " /tmp/reelcut-4823.log`
must print nothing before a proof run means anything.

**The EXACT tool count belongs to the newest phase's script**, because it is
what tells a stale binary on the port from the build under test: road map 3's
`recording_proof.py` asserts **75** (`record_screen`), and phases 1 to 9 keep
floors (63, 65, 68, 70, 71, 73, 73, 73 and 74) so a later phase's tools never
fail an older proof. Road map 3's was the fifth handover and cost two rows in
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

**Auto captions, honestly.** Speech recognition is gated by a TCC grant an
agent-driven app can never obtain — the system prompt needs the app to be
frontmost — so the recogniser is out of reach of every script, and the proof
says so rather than pretending otherwise. What it DOES assert is the whole
path around it: the three ineligible sources of the contract's D-A7 are each
refused by name with the reason that belongs to them (a text clip, a
REVERSED clip, a clip of a silent movie), a timeline with nothing audible in
it is refused as that rather than as a scope, and then the grant itself —
`transcribe` refuses with the exact sentence, NAMES the framework's status
word inside it (`notDetermined` here), leaves the project JSON unchanged and
pushes no undo step. That the scope refusals are reachable at all is the
claim: the handler answers the caller's own mistakes BEFORE it reads the
grant, and a build with those two guards swapped answers all four with the
authorization sentence. What is NOT reachable HERE is the cue builder — the
≤ 2 lines, ≤ 42 characters, ≤ 6 s and one-frame-gap rules of `CaptionCues` —
because nothing in a running app calls it until a recogniser has produced
words, and no MCP call can make one. Those four rules are proved in
`phase4_chrome.py`'s section 8 instead, over the offscreen harness, which is
the one binary that can call `CaptionCues.build` directly; the paragraph on
that script says how.

**With the grant**, which means opening the app yourself once and running
File ▸ Generate Captions… so macOS can ask: import `media/speech.mov`, run
`transcribe` over it, and the two pangrams should come back as text clips on
a new "Captions" track, in order, none longer than 6 s or wider than two
42-character lines, each starting at least a frame after the one before, and
`render_frame` inside a cue should show its words burnt into the picture.
`transcribe {place: false}` returns the same cues and changes nothing.

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
CLAUDE.md records — **audio export is not bit-deterministic near a duck ramp
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

`phase5_chrome.py` is the other half, and phase 5 splits between the two more
sharply than any phase so far: four of its five features are AUDIO, which a
still frame can hold no opinion about, so everything above is the MCP
script's and what is left for the offscreen renderer is the one thing the
phase draws — the output level meter in the timeline bar. Its sections 1 to 7
(forty-five checks) are byte comparisons of harness PNGs measured against
`TimelineBar`'s own layout constants, and its new instrument is WHAT it
compares against: the second PNG is built from the tree BEFORE the meter
existed — the parent of the commit that added `LevelMeterView.swift`,
extracted with `git archive` and compiled by the same swiftc line, so the two
binaries differ by the phase's `app/Sources` changes and nothing else. At
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
flag is not named after the meter — falls back to the reference commit's own
`main.swift` when the current one will not compile against that tree, and
reports a build it cannot make at all as a scored FAILURE rather than
exiting, so a rotted instrument cannot take the model checks down with it.

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
zero and was refused by the core with a bare `Ok(None)`, which reaches a caller
as "Remove Media made no change. Either the project is already in that
state…". The section builds that exact fixture over the wire — import, a clip,
`nest` — and asserts the refusal NAMES the file and the count, that the
reason-less sentence is NOT what comes back, that `with_clips: true` takes the
entry and the NESTED clip while leaving the nest clip itself on the timeline,
and that one undo restores the whole project JSON. The check with the sharpest
teeth is the both-levels one: media used once at the top level AND once inside
a nest must be refused with "used by **2** clips", which a build counting the
top level alone still refuses — with the wrong number. Sections 3 and 4 are the
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
[port] [log path]`, **214/214**, about seven seconds). It was 184 for the
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
the time; the script is 214 since section 9 landed, and the nine have not been
re-run against it — `scoped_edit` turns the first refused op of a section into
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
when the binary is newer than the sources and the staticlib; `--force`
rebuilds) and pins every `UserDefaults` key the chrome reads — the
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
produced words, and `SFSpeechRecognizer` produces none without a Speech
Recognition grant only a frontmost app can be given. The mode is answered
before a package is opened or a default is pinned, the way `welcome` is, and
every render argument keeps the position it had — added, not rearranged,
because `phase2_chrome.py`, `phase3_chrome.py` and `phase4_chrome.py` all
depend on that order.

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
twenty word lists, which is the only way those rules can be reached without
the Speech Recognition grant (`phase4_proof.py` says so from the other
side). Each rule is asserted at its BOUNDARY rather than in the middle,
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

**Two things spoiled section 4 before it worked, and both are recorded because
each reads exactly like the defect.** A SHEET: `viewDidAppear` calls
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
grant, no media: route 1 of `designs/reelcut-remaining.md` §1b, a probe over
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
`designs/reelcut-remaining.md` that are APP arithmetic or an app PICTURE no
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
`designs/reelcut-roadmap-3.md` dated; two of them overturned the plan. The
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
`started_at` that parses as ISO-8601 UTC within a minute of the call. On this
host it is **187/187** with the two tone rows skipped by name (the headless
tier 121, the granted 66 — 9 detection, 44 landing, 13 microphone); expect
121 plus a counted skip on an ungranted or locked machine. Its honest limit:
with ONE segment the "segment equals top level" rows cannot tell a build that
copied the top level into the segment from one that did not — the two-segment
shape is `recording_probe.py`'s, whose granted tier records for real. It
needs `ffmpeg`, `ffprobe`, `osascript` and `afplay` on `PATH`. The mutants it names — the grant check hoisted, the
`.newProject` fallback deleted, the `fps:` override dropped, the undo group
split, the held-tail branch deleted, a `scope` on the tool — and the four the
fix wave built (a placement throw unwrapped, the `path` trim removed, a
named project falling through to a new document, the Goertzel share on the
wrong scale) are in its docstring with the rows that kill them.

`python3 tools/proof/recording_probe.py`, **876/876** (662 before R2; `--only
<sections>` for iteration), over a probe compiled
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
through the panel. `--mutant <name>` prepares a copy of
`app/Sources` and runs the whole thing over it; twenty-nine are named in the
docstring, every one killed — the nine R2 ones at 811–875 of 876, R1's
re-scored at 857–875.

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

**32/32** at the landing. Mutants: the sheet never presented **14/32**; the
button sending `ripple: false` **24/32**; the trial's apply guard reduced to
"only an all-`set_transition` batch" **28/32** (the split pair and the mixed
selection). **One survivor**: the button calling `applyEdit` instead of
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
deepening ticket at a time (`designs/reelcut-roadmap-7.md` §1). D1·3
(kpgalligan/reelcut#4) built it with `set_video`'s section, at **39/39**;
D1·4 and D1·5 add theirs beside it, and the file says in a marked comment
where the next one goes and what has to change in the copy.

What it asserts, per door: the four refusal sentences VERBATIM rather than
by keyword (`unknown key`, `missing key`, `bad value at`, `<group> patch
must be a json object`), the project BYTE-identical either side of every
refusal, that one `undo` after a whole batch of refusals puts back the one
real edit that preceded them — so not one refusal registered a step — and
then the merge rules read back through `get_project` (one key changed,
siblings kept, `null` clearing, a list replacing, a motion slot kept) and
the frame-grid snap the core applies to the ticks a patch carries.

**Why it exists beside `core/tests/patch_door.rs`, which proves the same
rules through the FFI.** Those tests cannot see the Swift agent door, which
until D1·3 decoded the caller's object through the app's LENIENT project
types and sent the RESULT to the core: a misspelt enum landed as the
vocabulary's first case, an unknown key inside a nested object was dropped,
a three-element colour had an alpha filled in and an out-of-range component
was clamped — each of them reported as a success. Only a call made over MCP
against the built binary tells the two apart. It needs no ffmpeg and nothing
in `media/` but `A.mov`.

Two assertions elsewhere moved here in spirit rather than in place, and both
are noted in their own files: `phase6_proof.py`'s `set_video` refusals (the
partial filter entry, the misspelt filter kind, the misspelt blend) now
assert the core's whole sentence instead of the Swift door's `patch.`-prefixed
key, and `phase3_proof.py`'s printed NOTE that a misspelt key inside a
nested object was dropped is two CHECKS now, because it no longer is. The
`set_action_end` refusals in both files are still the Swift door's until
kpgalligan/reelcut#6.
