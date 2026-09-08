# tools/proof — driving a built Reelcut over MCP, and rendering its chrome offscreen

`CLAUDE.md`'s "Verifying a build" is the standard: the app is verified by
driving the built binary and comparing what it renders, not by reading
code. These are the scripts that do it — an MCP script per road-map-2 phase,
and from phase 2 an offscreen-chrome script beside it — so a proof can be
re-run after a later change rather than believed on the strength of a
paragraph.

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

Then launch YOUR OWN instance on YOUR OWN port and only ever kill that one
(`pgrep -f "MacOS/Reelcut"` lists them; another session may have one running):

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
```

The last line is `<n>/<n> checks passed`, and the exit status is non-zero if
any failed. The log's second line names the port the app actually bound (a
taken port falls back to an ephemeral one), and the same log is where the
startup parity check would complain — `grep "Reelcut: " /tmp/reelcut-4823.log`
must print nothing before a proof run means anything.

**The EXACT tool count belongs to the newest phase's script**, because it is
what tells a stale binary on the port from the build under test: phase 5
asserts 71, and phases 1 to 4 keep floors (63, 65, 68 and 70) so a later
phase's tools never fail an older proof. That handover has now happened once
exactly as it was written down — phase 5 added `normalize_clip`, took the
exact count, and phase 4's `check` became a `>=`. It is not decoration:
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
(the saved file's version assertion is the CURRENT one, 4, not 3: an older
file must open, but what this build writes is what this build writes),
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
The schema half is the saved `project.json` (version 5, `animation` the LAST
key of every text object), a hand-made version-4 fixture that opens and
reads a null animation, and the two refusals — a kind outside the closed
enum, and a negative `in` or `out` named by its dotted key.

Every one of those checks was MUTATION-TESTED against four deliberate
breakages, which is what makes the score mean anything: the reveal taken
out of the content hash, `TextProps.animation` moved off the end, the
`text.animation` range checks deleted and `RC_FORMAT_VERSION` put back to 4
(six checks fail, and only those six); `Reveal::of` returning "all of it"
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
