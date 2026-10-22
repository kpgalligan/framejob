#!/usr/bin/env python3
"""Issue batch B88 phase 3 — the Debug app answers, renders and exports as
the Release app does (spec §11 V-4, which amends V-1).

    python3 tools/proof/debug_release_proof.py

It launches three instances of this tree's built products, each from
`proof_app.binary()` (Debug, then Release twice), each on its own scratch
socket and scratch home (`CFFIXED_USER_HOME`), each with `-FrameJobPreviewQuality
0` pinned (the one defaults key on a scored path), and stops each by its own
pid. A stale product is refused by `mcp.launch` before anything starts:
`make app-debug` and `make app` first. On each it builds one fixture over MCP
at `work/debug-release/<side>/fixture.framejob`: a 640×360 canvas, `media/A.mov`
as a video clip, a text clip, a timed word caption (highlight) and a graphic
clip whose picture moves with the frame.

  T1  `tools/list` parses equal (Debug, Release)
  T2  `get_project` parses equal, each side's own folder spelled `<WORK>`
  T3  `render_frame` PNGs byte-equal at five times
  T4  a ProRes 422 export of the in/out range masked-equal
      (`video_configuration_proof.same_movie`: `mvhd`/`tkhd`/`mdhd` times zeroed)
  T5  the two bundles' `Resources/agent-catalog.json` (the snapshot `framejob-mcp`
      lists from) parse equal; their bytes are reported, not scored: the
      writer's key order is Swift's per-process hash seed, so two runs of one
      Release executable differ in bytes too
  T6  `perform_menu_item ["Frame Job"]` answers the same text on both (the
      bundle's name, "Frame Job Debug", does not reach the menus)
  C0  CONTROL: two Release instances, T3's five renders byte-equal
  C1  sensitivity: one graphic prop changed on the Debug side alone is seen
      by T2's and T3's comparisons (then undone)
  Z1  no `Frame Job: ` line in any instance's log (the parity check)
  Z2  each instance's `mcp._GUARDED` record names its own bundle's
      `CFBundleIdentifier`, and Debug's and Release's differ

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row passes.
"""

import hashlib
import json
import os
import plistlib
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mcp  # noqa: E402
import proof_app  # noqa: E402
from video_configuration_proof import same_movie  # noqa: E402

ROOT = proof_app.ROOT
WORK = ROOT / "tools/proof/work/debug-release"
MEDIA = ROOT / "tools/proof/media/A.mov"
SEC = 600_000
TICKS = (0, 300_000, 600_000, 900_000, 1_140_000)
WRITTEN = re.compile(r"Written to (\S+\.png)\.")
WORDS = "the quick brown fox"
TIMINGS = [{"start": 120_000, "end": 300_000}, {"start": 360_000, "end": 540_000},
           {"start": 600_000, "end": 780_000}, {"start": 840_000, "end": 1_020_000}]
HIGHLIGHT = {"mode": "highlight", "active_color": [1.0, 0.85, 0.0, 1.0], "active_scale": 1.2,
             "active_pill": {"color": [0.55, 0.27, 0.93, 1.0], "padding": 0.2, "radius": 0.25},
             "spoken_color": [0.8, 0.8, 0.8, 1.0], "upcoming_color": [1.0, 1.0, 1.0, 0.5]}
MODULE = ("export const meta = { name: \"Drift\", durationInFrames: 60 };\n"
          "export const schema = {\n"
          "  x: { type: \"number\", default: 40, min: 0, max: 600 },\n"
          "  fill: { type: \"color\", default: \"#22aa66\" },\n"
          "};\n"
          "export function render(frame, props, ctx) {\n"
          "  return svg(ctx, `<rect x=\"${props.x + frame * 3}\" y=\"240\" width=\"80\" "
          "height=\"60\" fill=\"${props.fill}\"/>`);\n"
          "}\n")

results = []


def row(name, ok, detail):
    results.append((name, bool(ok)))
    print(f"{name} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def sha(data):
    return hashlib.sha256(data).hexdigest()[:16]


def chosen_binary(config):
    """`proof_app.binary()` with `RC_PROOF_APP` set to `config` for the call."""
    saved = os.environ.get(proof_app.ENV)
    os.environ[proof_app.ENV] = config
    try:
        return proof_app.binary()
    finally:
        os.environ.pop(proof_app.ENV) if saved is None else os.environ.__setitem__(
            proof_app.ENV, saved)


class Side:
    """One launched instance and its fixture."""

    def __init__(self, name, config):
        self.name, self.config = name, config
        self.binary = chosen_binary(config)
        self.bundle = self.binary.parents[2]
        self.folder = WORK / name
        self.project = str(self.folder / "fixture.framejob")
        socket_path = mcp.scratch_socket()
        home = os.path.join(os.path.dirname(socket_path), "home")
        os.makedirs(home)
        env = {**mcp._child_env(), "CFFIXED_USER_HOME": home}
        self.launched = mcp.launch(self.binary, ["-FrameJobPreviewQuality", "0"], env=env,
                                   socket_path=socket_path, seconds=60)
        self.socket = socket_path
        self.client = self.launched.client
        if self.client is None:
            self.launched.stop()
            raise RuntimeError(f"{name}: {self.binary} did not listen at {socket_path}; its "
                               f"log is {self.launched.log_path}")
        print(f"  {name}: pid {self.launched.child.pid}, {self.binary}", flush=True)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, arguments)

    def build(self):
        os.makedirs(self.folder)
        self.call("new_project", path=self.project)
        self.call("set_canvas", project=self.project, width=640, height=360)
        footage = self.state()["project"]["tracks"][0]["id"]
        media = self.call("import_media", project=self.project, path=str(MEDIA))["media"]
        self.call("add_clip", project=self.project, track=footage, media=media, at=0)
        titles, words, graphic = (self.new_track(n) for n in ("Titles", "Words", "Graphic"))
        title = self.call("add_text_clip", project=self.project, track=titles, at=0,
                          duration=2 * SEC, text="Debug = Release")["new_clips"][0]
        self.call("set_video", project=self.project, clips=[title], patch={"y": -120})
        self.call("add_text_clip", project=self.project, track=words, at=0, duration=2 * SEC,
                  text={"content": WORDS, "words": TIMINGS, "word_style": HIGHLIGHT})
        written = self.call("write_graphic", project=self.project, name="drift", source=MODULE)
        if not (isinstance(written, dict) and written.get("ok")):
            raise RuntimeError(f"{self.name}: write_graphic answered {written}")
        self.call("add_graphic_clip", project=self.project, track=graphic, at=0, name="drift",
                  duration=2 * SEC)
        self.call("set_range", project=self.project, start=0, end=2 * SEC)
        self.call("save_project", project=self.project)
        self.graphic = next(c["id"] for c in self.state()["project"]["clips"]
                            if c["source"].get("kind") == "graphic")

    def new_track(self, name):
        return self.call("add_track", project=self.project, name=name)["new_tracks"][0]

    def state(self):
        return self.call("get_project", project=self.project)

    def normalised(self):
        return json.loads(json.dumps(self.state()).replace(str(self.folder), "<WORK>"))

    def render(self, tick):
        answer = str(self.call("render_frame", project=self.project, t=tick))
        found = WRITTEN.search(answer)
        if not found:
            raise RuntimeError(f"{self.name}: render_frame said {answer}")
        with open(found.group(1), "rb") as handle:
            return handle.read()

    def export(self):
        path = str(self.folder / "fixture.mov")
        reply = self.client.export(project=self.project, preset="prores_422",
                                   range="in_out", path=path)
        if not (isinstance(reply, dict) and reply.get("ok")):
            raise RuntimeError(f"{self.name}: export answered {reply}")
        return reply["path"]

    def menu(self):
        try:
            return f"answer: {self.call('perform_menu_item', path=['Frame Job'])}"
        except mcp.ToolError as error:
            return f"refusal: {error}"

    def log_complaints(self):
        with open(self.launched.log_path, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]

    def bundle_id(self):
        with open(self.bundle / "Contents/Info.plist", "rb") as handle:
            return plistlib.load(handle).get("CFBundleIdentifier")


def frames(side):
    return {tick: side.render(tick) for tick in TICKS}


def differing(a, b):
    return [tick for tick in TICKS if a[tick] != b[tick]]


def main():
    if len(sys.argv) > 1:
        sys.exit(__doc__)
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    sides = []
    try:
        for name, config in (("debug", "debug"), ("release", "release"),
                             ("release-b", "release")):
            sides.append(Side(name, config))
        debug, release, control = sides
        for side in sides:
            side.build()

        a, b = debug.client.tools(), release.client.tools()
        row("T1", a == b and len(a) > 0, f"tools/list {len(a)} vs {len(b)} tools, "
            f"{'equal' if a == b else 'different'}")
        a, b = debug.normalised(), release.normalised()
        clips = len(a.get("project", {}).get("clips", []))
        row("T2", a == b and clips == 4,
            f"get_project {clips} clips, {'equal' if a == b else 'different'}"
            f" (sha {sha(json.dumps(a, sort_keys=True).encode())} vs "
            f"{sha(json.dumps(b, sort_keys=True).encode())})")
        shots = {side.name: frames(side) for side in sides}
        off = differing(shots["debug"], shots["release"])
        row("T3", not off and len({sha(p) for p in shots["debug"].values()}) == len(TICKS),
            f"render_frame at {list(TICKS)}: {len(TICKS) - len(off)}/{len(TICKS)} byte-equal, "
            f"{len({sha(p) for p in shots['debug'].values()})} distinct pictures; differing "
            f"{off or 'none'}")
        same, detail = same_movie(debug.export(), release.export())
        row("T4", same, f"prores_422 in/out (2 s): {detail}")
        texts = [(side.bundle / "Contents/Resources/agent-catalog.json").read_bytes()
                 for side in (debug, release)]
        parsed = [json.loads(text) for text in texts]
        row("T5", parsed[0] == parsed[1] and len(parsed[0].get("tools", [])) > 0,
            f"agent-catalog.json {len(parsed[0].get('tools', []))} tools, parsed "
            f"{'equal' if parsed[0] == parsed[1] else 'different'}; bytes "
            f"{'equal' if texts[0] == texts[1] else 'differ'} (not scored: key order)")
        a, b = debug.menu(), release.menu()
        row("T6", a == b and "About Frame Job" in a and "Frame Job Debug" not in a,
            f"{'same' if a == b else 'different'}: {a!r}" + ("" if a == b else f" vs {b!r}"))

        off = differing(shots["release"], shots["release-b"])
        row("C0", not off, f"CONTROL: two Release instances, {len(TICKS) - len(off)}/"
            f"{len(TICKS)} renders byte-equal; differing {off or 'none'}")
        debug.call("set_graphic", project=debug.project, clips=[debug.graphic],
                   patch={"props": {"x": 300}})
        moved_state = debug.normalised() != release.normalised()
        moved = [tick for tick in TICKS if debug.render(tick) != shots["release"][tick]]
        debug.call("undo", project=debug.project)
        restored = debug.normalised() == release.normalised()
        row("C1", moved_state and moved == list(TICKS) and restored,
            f"Debug's graphic x 40 → 300: get_project {'differs' if moved_state else 'EQUAL'}, "
            f"renders differ at {moved}; undone, get_project "
            f"{'equal again' if restored else 'STILL DIFFERENT'}")
    finally:
        for side in sides:
            side.launched.stop()

    complaints = {side.name: side.log_complaints() for side in sides}
    row("Z1", not any(complaints.values()), f"`Frame Job: ` lines: "
        f"{ {name: lines[:3] for name, lines in complaints.items() if lines} or 'none'}")
    guarded = {side.name: (mcp._GUARDED.get(side.socket, {}).get("domain"), side.bundle_id())
               for side in sides}
    row("Z2", all(g == b and g for g, b in guarded.values())
        and guarded["debug"][0] != guarded["release"][0],
        f"guarded domain vs bundle id: {guarded}")
    failed = [name for name, ok in results if not ok]
    print(f"{len(results) - len(failed)}/{len(results)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
