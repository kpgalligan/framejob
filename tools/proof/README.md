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
```

The last line is `<n>/<n> checks passed`, and the exit status is non-zero if
any failed. The log's second line names the port the app actually bound (a
taken port falls back to an ephemeral one), and the same log is where the
startup parity check would complain — `grep "Reelcut: " /tmp/reelcut-4823.log`
must print nothing before a proof run means anything.

**The EXACT tool count belongs to the newest phase's script**, because it is
what tells a stale binary on the port from the build under test: phase 3
asserts 68, and phases 1 and 2 keep floors (63 and 65) so a later phase's
tools never fail an older proof. When phase 4 lands, the exact count moves to
its script and phase 3's becomes a floor too.

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
than accumulated.

## The offscreen harness (no running app)

`harness/` is CLAUDE.md's "Seeing the chrome": `harness/main.swift` compiles
with every `app/Sources/*.swift` but the app's own `main.swift`, links the
staticlib, opens a package from disk and `cacheDisplay`s the editor into a
PNG — `harness/build.sh` builds it into `work/harness/` (about 30 s, skipped
when the binary is newer than the sources and the staticlib; `--force`
rebuilds) and pins every `UserDefaults` key the chrome reads — the
persisted view state, the Document tab's `ReelcutInspectorRescaleClips`
checkbox and `AppleShowScrollBars` — in the argument domain, so two renders
of one package are byte-identical on one machine. `phase2_chrome.py` is the
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
