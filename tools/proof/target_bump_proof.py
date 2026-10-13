#!/usr/bin/env python3
"""The deployment target, rendered: road map 8's W1a (§10.4).

The macOS 26 bump recompiles `Compositor.metal` under a new language revision
(`project.yml`'s `MTL_LANGUAGE_REVISION: UseDeploymentTarget`), and nothing
else in `tools/proof/` draws through it from two builds. This script renders
the same three ticks of one hand-written package — a media clip, a text clip
and a shape clip on three tracks, all live at every tick — and compares the
PNGs byte for byte.

    python3 tools/proof/target_bump_proof.py <socket> capture <dir>   # the CONTROL build
    python3 tools/proof/target_bump_proof.py <socket> compare <dir>   # the build under test

`capture` writes `<dir>/frames.framejob` fresh and keeps `<dir>/t<tick>.png`;
`compare` opens the SAME package and checks each render against those files.
It launches nothing and kills nothing: the caller owns the instance at <socket>.
"""

import hashlib
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, target  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FRAME = 20_000
TICKS = (0, 900_000, 1_500_000)
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
    path = os.path.join(where, name + ".framejob")
    os.mkdir(path)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as stream:
        json.dump(document, stream)
    return path


def document():
    span = 150 * FRAME
    return {
        "version": 8,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
        "media": [{"id": 20, "path": os.path.join(ROOT, "tools", "proof", "media", "A.mov"),
                   "kind": "video", "duration": 6_000_000, "width": 640, "height": 360,
                   "fps": [30, 1], "has_video": True}],
        "tracks": [{"id": 1, "name": "Footage"}, {"id": 2, "name": "Text"},
                   {"id": 3, "name": "Shape"}],
        "clips": [
            {"id": 21, "track": 1, "start": 0, "duration": span,
             "source": {"kind": "media", "media": 20, "in": 0}, "video": {}},
            {"id": 22, "track": 2, "start": 0, "duration": span,
             "source": {"kind": "text"}, "video": {}, "text": {"content": "W1a"}},
            {"id": 23, "track": 3, "start": 0, "duration": span,
             "source": {"kind": "shape"}, "video": {}, "shape": {}},
        ],
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
    project = os.path.join(where, "frames.framejob")
    if mode == "capture":
        shutil.rmtree(where, ignore_errors=True)
        os.makedirs(where)
        package(where, "frames", document())
    mcp = MCP(socket_path)
    mcp.call("open_project", path=project)
    for tick in TICKS:
        written = render(mcp, tick)
        kept = os.path.join(where, f"t{tick}.png")
        if mode == "capture":
            shutil.copyfile(written, kept)
            print(f"  kept {kept} {os.path.getsize(kept)} bytes sha256 {sha(kept)}")
            continue
        with open(written, "rb") as a, open(kept, "rb") as b:
            same = a.read() == b.read()
        check(f"t={tick} renders byte for byte as the control", same,
              f"{written} {os.path.getsize(written)} bytes {sha(written)} vs "
              f"{kept} {os.path.getsize(kept)} bytes {sha(kept)}")
    if mode == "compare":
        print(f"{passed}/{passed + failed}")
        sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
