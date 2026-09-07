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

Then launch YOUR OWN instance on YOUR OWN port and only ever kill that one
(`pgrep -f "MacOS/Reelcut"` lists them; another session may have one running):

```sh
make app
(RC_AGENT_PORT=4823 ./build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
   -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4823.log 2>&1 &)
python3 tools/proof/phase1_proof.py 4823
python3 tools/proof/phase2_proof.py 4823
```

The last line is `<n>/<n> checks passed`, and the exit status is non-zero if
any failed. The log's second line names the port the app actually bound (a
taken port falls back to an ephemeral one), and the same log is where the
startup parity check would complain — `grep "Reelcut: " /tmp/reelcut-4823.log`
must print nothing before a proof run means anything.

`phase2_proof.py` covers the catalog count (65), the version-3 schema (a
saved `project.json` and a hand-made version-2 fixture, both read back from
disk), `set_clip`'s patch rules and refusals, `paste_attributes` (what
travels, what stays, the frame, one undo step) and solo — the last as
exports: with the SAME two-tone project, soloing the back track decodes
sample-for-sample equal to muting the front track and to a project holding
only the back track's tone, a soloed-and-muted track is silent, and a
`render_frame` over a picture track is byte-identical before and after.

`media/` and `work/` are ignored: the movies are regenerable from the lines
above and the projects are rebuilt on every run. Phase 2's packages are
named `<name>-<pid>.reelcut` rather than `<name>.reelcut`, and each run
deletes the earlier ones under its name: a `project` path is matched against
every document the instance has open, there is no tool that closes one, and
once two earlier runs have left SAVED documents at a fixed path the app
answers for an old one (measured; phase 1 never saves, so its fixed names
survive a third run). A fresh path per run keeps a third phase-2 run against
one instance as honest as the first.

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
