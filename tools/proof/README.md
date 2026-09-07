# tools/proof — driving a built Reelcut over MCP

`CLAUDE.md`'s "Verifying a build" is the standard: the app is verified by
driving the built binary and comparing `render_frame` output, not by reading
code. These are the scripts that do it, one per road-map-2 phase, so a proof
can be re-run after a later change rather than believed on the strength of a
paragraph.

`mcp.py` is a ~70-line MCP client (streamable HTTP, tools only) — enough to
`initialize`, list the tools and call one. It has no dependencies.

Each `phase<N>_proof.py` makes its own projects under `work/` from test media
under `media/`, and every claim is either a placement read back through
`get_project` or a **byte comparison of two PNGs** `render_frame` wrote. A
frame claim that could be satisfied by two different-looking pictures is not
a proof, so nothing here compares sizes or timestamps.

## Running one

Make the test media once (ffmpeg is not a product dependency — see spec §11
— but it is the obvious way to get a frame-numbered test card):

```sh
mkdir -p tools/proof/media && cd tools/proof/media
ffmpeg -y -f lavfi -i "testsrc=size=640x360:rate=30:duration=10"  -pix_fmt yuv420p -c:v libx264 A.mov
ffmpeg -y -f lavfi -i "testsrc2=size=640x360:rate=30:duration=10" -pix_fmt yuv420p -c:v libx264 B.mov
ffmpeg -y -f lavfi -i "color=c=green:size=640x360:rate=30:duration=6" -pix_fmt yuv420p -c:v libx264 C.mov
```

Then launch YOUR OWN instance on YOUR OWN port and only ever kill that one
(`pgrep -f "MacOS/Reelcut"` lists them; another session may have one running):

```sh
make app
(RC_AGENT_PORT=4823 ./build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
   -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4823.log 2>&1 &)
python3 tools/proof/phase1_proof.py 4823
```

The last line is `<n>/<n> checks passed`, and the exit status is non-zero if
any failed.

`media/` and `work/` are ignored: the movies are regenerable from the lines
above and the projects are rebuilt on every run.
