#!/usr/bin/env python3
"""#363's render-side de-duplication, rendered: no byte changed.

#363 folds six hand-synced copies into one shared piece each — the half-float
bitmap, the LRU cache, the input pass, the scope tap's reader, the word-fade
geometry and the shader's grade steps (`gradeSteps`). A refactor is proved by
drawing the same frames from both builds, so this script builds four projects
over MCP, renders fixed frames with every scope the frame can carry, and
compares the PNGs and the scope JSON byte for byte.

    python3 tools/proof/render_dedup_proof.py <socket> capture <dir>   # the CONTROL build
    python3 tools/proof/render_dedup_proof.py <socket> compare <dir>   # the build under test

The projects, each 640×360 at 30 fps, each closed (discard) when drawn:

- **G**: the card graded on its clip — tone (exposure), Color's contrast, the
  three wheels, a master and a red curve, the hue curves, the built-in look
  `vivid` at 0.7 and sepia at 0.3 — rendered with `waveform`, `parade`,
  `vectorscope` and `histogram`, then again with `vectorscope: true,
  vectorscope_zoom: 2`.
- **A**: the card ungraded under an adjustment clip carrying G's grade.
- **S**: an SDR project with each of four stills alone at its own time:
  `still8.png`, `still16_srgb.png` (the deep path), `still_hlg.heic` (the HDR
  path) and `still_gainmap.heic`.
- **H**: the same four stills in an HLG project (the lift, the gain map's
  HDR rendition), then a title (`add_text_clip`) alone at its own time,
  rendered with all four scopes.

`capture` makes `<dir>/media/card.png` (ffmpeg `testsrc2`, one frame) and
copies the four stills from `tools/proof/work/hdr/media/` (made by
`hdr_proof.py capture <dir> --only HG0,Z1`; a missing one exits 2 naming
it), then keeps each render as `<dir>/<frame>.png` and each scope beside it
as `<dir>/<frame>.png.<scope>.json`. `compare` reads the same `<dir>/media/`
and holds every render against those files: one row per PNG and per JSON, a
missing control file a FAIL by name. Exit 0 only when every row passes; 1 on
a failed row; 2 when the fixture could not be built.

It launches nothing, kills nothing and performs no menu item: the caller owns
the instance at <socket>. It writes only under `<dir>` and
`tools/proof/work/render-dedup/`. `reveal_toll_proof.py` is the shape.
"""

import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError, target  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools/proof/work/render-dedup")
HDR_MEDIA = os.path.join(ROOT, "tools/proof/work/hdr/media")
STILLS = ("still8.png", "still16_srgb.png", "still_hlg.heic", "still_gainmap.heic")
SEC = 600_000
W, H = 640, 360
SCOPES = ("waveform", "parade", "vectorscope", "histogram")

# G's grade, in the argument shapes wheels_proof.py, curves_proof.py and
# look_proof.py send; one `set_video` per group.
GRADE = (
    {"color": {"exposure": 0.5, "contrast": 0.2}},
    {"wheels": {"lift": {"x": 0.2, "y": -0.1, "master": 0.05},
                "gamma": {"x": -0.15, "y": 0.2, "master": -0.1},
                "gain": {"x": 0.1, "y": 0.1, "master": 0.1}}},
    {"curves": {"master": [[0, 0], [0.5, 0.6], [1, 1]],
                "red": [[0, 0], [0.5, 0.45], [1, 1]]}},
    {"curves": {"hue_hue": [[0, 0], [60, 0], [120, 40], [180, 0]],
                "hue_sat": [[0, 1], [60, 1], [120, 0.5], [180, 1]]}},
    {"look": {"kind": "vivid", "amount": 0.7}},
    {"filters": [{"kind": "sepia", "amount": 0.3}]},
)

passed = 0
failed = 0


class FixtureError(RuntimeError):
    pass


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}", flush=True)
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""), flush=True)


class Doc:
    """One open project; every call names it, and a refusal is a fixture failure."""

    def __init__(self, client, name):
        self.client = client
        self.path = os.path.join(WORK, name + ".framejob")
        self.name = name
        self.call("new_project", path=self.path)
        self.call("set_canvas", width=W, height=H, fps=[30, 1])

    def call(self, tool, **arguments):
        try:
            return self.client.call_with(tool, dict(arguments, project=self.path))
        except ToolError as error:
            raise FixtureError(f"{self.name}: {error}") from None

    def clips(self):
        return (self.call("get_project").get("project") or {}).get("clips") or []

    def first_track(self):
        tracks = (self.call("get_project").get("project") or {}).get("tracks") or []
        if not tracks:
            raise FixtureError(f"{self.name}: no track")
        return tracks[0]["id"]

    def new_track(self):
        before = {t["id"] for t in (self.call("get_project").get("project") or {})["tracks"]}
        self.call("add_track")
        after = (self.call("get_project").get("project") or {})["tracks"]
        made = [t["id"] for t in after if t["id"] not in before]
        if len(made) != 1:
            raise FixtureError(f"{self.name}: add_track made {made}")
        return made[0]

    def added(self, tool, **arguments):
        """`tool` placing one clip; that clip's record."""
        before = {c["id"] for c in self.clips()}
        self.call(tool, **arguments)
        new = [c for c in self.clips() if c["id"] not in before]
        if len(new) != 1:
            raise FixtureError(f"{self.name}: {tool} placed {len(new)} clips")
        return new[0]

    def media(self, path):
        got = self.call("import_media", path=path)
        media = got.get("media") if isinstance(got, dict) else None
        if media is None:
            raise FixtureError(f"{self.name}: import_media {path} answered {got!r}")
        return media

    def grade(self, clip):
        for patch in GRADE:
            self.call("set_video", clips=[clip], patch=patch)

    def close(self):
        try:
            self.client.call_with("close_project", {"project": self.path, "discard": True})
        except ToolError as error:
            raise FixtureError(f"{self.name}: close_project: {error}") from None


def render(doc, frame, t, scopes=(), **options):
    """`render_frame` of `doc` at `t` into WORK; the files written (PNG first)."""
    out = os.path.join(WORK, frame + ".png")
    for stale in [out] + [f"{out}.{s}.json" for s in SCOPES]:
        if os.path.exists(stale):
            os.remove(stale)
    doc.call("render_frame", t=t, path=out, **{s: True for s in scopes}, **options)
    files = [out] + [f"{out}.{s}.json" for s in scopes]
    missing = [f for f in files if not os.path.exists(f)]
    if missing:
        raise FixtureError(f"{doc.name}: render_frame {frame} wrote no {missing}")
    return files


def stills_at_own_times(doc, media_dir):
    """The four stills back to back on the first track; (frame name, mid time) each,
    and the end of the last."""
    track = doc.first_track()
    at = 0
    frames = []
    for still in STILLS:
        clip = doc.added("add_clip", track=track, media=doc.media(os.path.join(media_dir, still)),
                         at=at)
        duration = clip.get("duration") or 0
        if duration <= 0:
            raise FixtureError(f"{doc.name}: {still} placed with duration {duration}")
        frames.append((os.path.splitext(still)[0], at + duration // 2))
        at += duration
    return track, frames, at


def build(client, media_dir):
    """Every project drawn; [(frame name, [files])] in order."""
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    card = os.path.join(media_dir, "card.png")
    drawn = []

    g = Doc(client, "G")
    clip = g.added("add_clip", track=g.first_track(), media=g.media(card), at=0)
    g.grade(clip["id"])
    t = clip["duration"] // 2
    drawn.append(("G", render(g, "G", t, SCOPES)))
    drawn.append(("G-zoom2", render(g, "G-zoom2", t, ("vectorscope",), vectorscope_zoom=2)))
    g.close()

    a = Doc(client, "A")
    clip = a.added("add_clip", track=a.first_track(), media=a.media(card), at=0)
    adjustment = a.added("add_adjustment_clip", track=a.new_track(), at=0,
                         duration=clip["duration"])
    a.grade(adjustment["id"])
    drawn.append(("A", render(a, "A", clip["duration"] // 2)))
    a.close()

    s = Doc(client, "S")
    _, frames, _ = stills_at_own_times(s, media_dir)
    for name, t in frames:
        drawn.append((f"S-{name}", render(s, f"S-{name}", t)))
    s.close()

    h = Doc(client, "H")
    h.call("set_canvas", output="hlg")
    track, frames, end = stills_at_own_times(h, media_dir)
    for name, t in frames:
        drawn.append((f"H-{name}", render(h, f"H-{name}", t)))
    h.added("add_text_clip", track=track, at=end, duration=SEC,
            text={"content": "Frame Job", "size": 96})
    drawn.append(("H-title", render(h, "H-title", end + SEC // 2, SCOPES)))
    h.close()
    return drawn


def make_media(where):
    media = os.path.join(where, "media")
    os.makedirs(media)
    missing = [s for s in STILLS if not os.path.exists(os.path.join(HDR_MEDIA, s))]
    if missing:
        print(f"missing {missing} under {HDR_MEDIA}: run "
              "`python3 tools/proof/hdr_proof.py capture <dir> --only HG0,Z1` first")
        sys.exit(2)
    for still in STILLS:
        shutil.copy2(os.path.join(HDR_MEDIA, still), os.path.join(media, still))
    made = subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", f"testsrc2=size={W}x{H}:rate=30",
         "-frames:v", "1", os.path.join(media, "card.png")],
        capture_output=True, text=True, timeout=120)
    if made.returncode != 0:
        print(f"ffmpeg could not make the card: {made.stderr.strip()}")
        sys.exit(2)


def main():
    if len(sys.argv) != 4 or sys.argv[2] not in ("capture", "compare"):
        sys.exit(__doc__)
    socket_path, mode, where = target(sys.argv), sys.argv[2], os.path.abspath(sys.argv[3])
    media_dir = os.path.join(where, "media")
    if mode == "capture":
        shutil.rmtree(where, ignore_errors=True)
        os.makedirs(where)
        make_media(where)
    elif not os.path.isdir(media_dir):
        print(f"no control media at {media_dir}: capture first")
        sys.exit(2)
    client = MCP(socket_path)
    try:
        drawn = build(client, media_dir)
    except FixtureError as error:
        print(f"the fixture could not be built: {error}")
        sys.exit(2)
    for frame, files in drawn:
        for written in files:
            kept = os.path.join(where, os.path.basename(written))
            label = os.path.basename(written)
            if mode == "capture":
                shutil.copyfile(written, kept)
                print(f"  kept {label} {os.path.getsize(kept)} bytes", flush=True)
                continue
            if not os.path.exists(kept):
                check(f"{label} renders byte for byte as the control", False,
                      f"no control file {kept}")
                continue
            with open(written, "rb") as a, open(kept, "rb") as b:
                same = a.read() == b.read()
            check(f"{label} renders byte for byte as the control", same,
                  f"{written} {os.path.getsize(written)} bytes vs {kept} "
                  f"{os.path.getsize(kept)} bytes")
    if mode == "capture":
        print(f"  {sum(len(f) for _, f in drawn)} files kept in {where}")
        sys.exit(0)
    print(f"{passed}/{passed + failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
