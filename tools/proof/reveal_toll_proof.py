#!/usr/bin/env python3
"""The reveal toll, rendered: road map 8's W3 (§10.7), step 1.

`LayerRenderersText.swift` paid its size toll before the word-caption routine
landed: the three reveal routines moved to `LayerRenderersReveal.swift` as a
PURE MOVE, and `TextProps` / `TextPatch` left their ledger files for files of
their own. A pure move is proved by drawing the same frames from both builds.
This script renders six ticks of one hand-written version-9 package — a
static title, a typewriter, a word_fade, an OUTLINED word_fade (the
partial-alpha transparency-layer path) and a two-line line_rise over a
backdrop, all five live at every tick, each 5 s with `in` and `out` of 1 s —
and compares the PNGs byte for byte.

    python3 tools/proof/reveal_toll_proof.py <socket> capture <dir>   # the CONTROL build
    python3 tools/proof/reveal_toll_proof.py <socket> compare <dir>   # the build under test

`capture` writes `<dir>/frames.reelcut` fresh and keeps `<dir>/t<tick>.png`;
`compare` opens the SAME package and checks each render against those files.
It launches nothing and kills nothing: the caller owns the instance at <socket>.
`target_bump_proof.py` is the shape.
"""

import hashlib
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, target  # noqa: E402

SEC = 600_000
SPAN = 5 * SEC
# 0, 0.4 s and 0.8 s inside the arrival; 2.0 s in the hold; 4.6 s and 4.9 s
# inside the departure.
TICKS = (0, 240_000, 480_000, 1_200_000, 2_760_000, 2_940_000)
WRITTEN = re.compile(r"Written to (\S+\.png)\.")

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


def package(where, name, document):
    path = os.path.join(where, name + ".reelcut")
    os.mkdir(path)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as stream:
        json.dump(document, stream)
    return path


def animation(kind):
    return {"kind": kind, "in": SEC, "out": SEC}


def document():
    texts = [
        # (track, y, text) — one text per track, stacked down the canvas.
        (1, -140, {"content": "Static title", "size": 36}),
        (2, -80, {"content": "typed out slowly", "size": 36,
                  "animation": animation("typewriter")}),
        (3, -20, {"content": "one word at a time", "size": 36,
                  "animation": animation("word_fade")}),
        (4, 40, {"content": "outlined words fade", "size": 36,
                 "color": [1.0, 1.0, 1.0, 1.0],
                 "outline": {"width": 4, "color": [0.0, 0.0, 0.0, 1.0]},
                 "animation": animation("word_fade")}),
        (5, 125, {"content": "first line rises\nsecond line follows", "size": 30,
                  "backdrop": {"color": [0.1, 0.2, 0.6, 0.8], "padding": 10, "radius": 6},
                  "animation": animation("line_rise")}),
    ]
    clips = []
    for index, (track, y, text) in enumerate(texts):
        clips.append({"id": 20 + index, "track": track, "start": 0, "duration": SPAN,
                      "source": {"kind": "text"}, "video": {"y": y}, "text": text})
    return {
        "version": 9,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1],
                   "background": [0.35, 0.35, 0.35, 1.0]},
        "media": [],
        "tracks": [{"id": track, "name": f"T{track}"} for track, _, _ in texts],
        "clips": clips,
        "markers": [], "nests": [], "next_id": 30,
    }


def render(mcp, tick):
    answer = str(mcp.call("render_frame", t=tick))
    found = WRITTEN.search(answer)
    if not found:
        raise RuntimeError(f"render_frame said something else: {answer}")
    return found.group(1)


def sha(path):
    with open(path, "rb") as stream:
        return hashlib.sha256(stream.read()).hexdigest()


def main():
    if len(sys.argv) != 4 or sys.argv[2] not in ("capture", "compare"):
        sys.exit(__doc__)
    socket_path, mode, where = target(sys.argv), sys.argv[2], os.path.abspath(sys.argv[3])
    project = os.path.join(where, "frames.reelcut")
    if mode == "capture":
        shutil.rmtree(where, ignore_errors=True)
        os.makedirs(where)
        package(where, "frames", document())
    mcp = MCP(socket_path)
    mcp.call("open_project", path=project)
    kept_hashes = set()
    for tick in TICKS:
        written = render(mcp, tick)
        kept = os.path.join(where, f"t{tick}.png")
        if mode == "capture":
            shutil.copyfile(written, kept)
            kept_hashes.add(sha(kept))
            print(f"  kept {kept} {os.path.getsize(kept)} bytes sha256 {sha(kept)}")
            continue
        with open(written, "rb") as a, open(kept, "rb") as b:
            same = a.read() == b.read()
        check(f"t={tick} renders byte for byte as the control", same,
              f"{written} {os.path.getsize(written)} bytes {sha(written)} vs "
              f"{kept} {os.path.getsize(kept)} bytes {sha(kept)}")
    if mode == "capture":
        # A capture whose six frames are not all different would prove the
        # animations were not drawn at all — the fixture would be a CONTROL
        # of nothing.
        print(f"  {len(kept_hashes)} distinct frames of {len(TICKS)}")
        sys.exit(0 if len(kept_hashes) == len(TICKS) else 1)
    print(f"{passed}/{passed + failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
