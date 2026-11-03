#!/usr/bin/env python3
"""Road map "creator-jobs" CU11 — motion blur (spec §11 CU-110…CU-116).

    python3 tools/proof/cu11_proof.py [--only K1,Z1] [--app PATH]

CU11a's rows, over MCP on one launch (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a
scratch `CFFIXED_USER_HOME`, the document closed after its row:
- K1 `set_video`'s `motion_blur` (CU-113, CU-111): on a new project, `add_media` an image
  descriptor (a 64 × 48 PNG the proof writes) and `add_clip`; `{motion_blur: 0.5}` reads back
  0.5 through `get_project`; `{motion_blur: 1.5}` is an error carrying "video.motion_blur must
  be between 0 and 1, not 1.5" and leaves the project unchanged; `{motion_blur: 0}` removes the
  key; the clip `nest`ed, the nest clip's `{motion_blur: 0.5}` is refused "clip N shows a nest
  and cannot take motion blur: set it on the clips inside"; an `add_adjustment_clip`'s is refused
  "clip N is an adjustment clip and cannot take motion blur".
- Z1 the launch's `grep "Frame Job: "` prints nothing.

CU11b adds MB1–MB4 (the drawn blur). CU11a's mutants M1–M6 are `core/tests/motion_blur.rs`'s and
`core/tests/cursor_track.rs`' (spec §11 CU-116).

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import shutil
import struct
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

WORK = ROOT / "tools/proof/work/cu11"
HOME = WORK / "home"
SEC = 600_000
CALL_BOUND = 300
PNG_W, PNG_H = 64, 48

APP_ROWS = ["K1", "Z1"]
ROWS = APP_ROWS

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def picture():
    """A 64×48 8-bit RGB PNG: a red-to-blue ramp across, green down."""
    path = WORK / "media" / "picture.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = b"".join(
        b"\x00" + bytes(v for x in range(PNG_W)
                        for v in (x * 255 // (PNG_W - 1), y * 255 // (PNG_H - 1),
                                  255 - x * 255 // (PNG_W - 1)))
        for y in range(PNG_H))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", PNG_W, PNG_H, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    return path


class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def added(self, tool, **arguments):
        """The id of the one clip `tool` adds."""
        before = {c["id"] for c in self.project()["clips"]}
        self.call(tool, **arguments)
        return next(c["id"] for c in self.project()["clips"] if c["id"] not in before)


def error_of(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


def k1(client):
    path = WORK / "k1.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    try:
        doc.call("add_media", descriptor={
            "path": str(picture()), "kind": "image", "width": PNG_W, "height": PNG_H})
        media = next(m["id"] for m in doc.project()["media"] if m["kind"] == "image")
        tracks = doc.project()["tracks"]
        if not tracks:
            doc.call("add_track")
            tracks = doc.project()["tracks"]
        track = tracks[0]["id"]
        clip = doc.added("add_clip", track=track, media=media, at=0)

        doc.call("set_video", clips=[clip], patch={"motion_blur": 0.5})
        stored = (doc.clip(clip).get("video") or {}).get("motion_blur")
        check("K1", stored == 0.5, f"set 0.5: get_project reads {stored}")

        before = doc.project()
        message = error_of(lambda: doc.call(
            "set_video", clips=[clip], patch={"motion_blur": 1.5}))
        sentence = "video.motion_blur must be between 0 and 1, not 1.5"
        check("K1", message is not None and sentence in message, f"1.5: {message}")
        check("K1", doc.project() == before, "1.5 leaves the project unchanged")

        doc.call("set_video", clips=[clip], patch={"motion_blur": 0})
        video = doc.clip(clip).get("video") or {}
        check("K1", "motion_blur" not in video, f"0 removes the key: video {video}")

        doc.call("add_track")
        upper = next(t["id"] for t in doc.project()["tracks"] if t["id"] != track)
        adjustment = doc.added("add_adjustment_clip", track=upper, at=0, duration=SEC)
        message = error_of(lambda: doc.call(
            "set_video", clips=[adjustment], patch={"motion_blur": 0.5}))
        sentence = f"clip {adjustment} is an adjustment clip and cannot take motion blur"
        check("K1", message is not None and sentence in message, f"adjustment: {message}")

        doc.call("nest", clips=[clip])
        nest = next(c["id"] for c in doc.project()["clips"]
                    if c["source"]["kind"] == "nest")
        message = error_of(lambda: doc.call(
            "set_video", clips=[nest], patch={"motion_blur": 0.5}))
        sentence = (f"clip {nest} shows a nest and cannot take motion blur: "
                    "set it on the clips inside")
        check("K1", message is not None and sentence in message, f"nest: {message}")
    finally:
        try:
            client.call("close_project", project=str(path), discard=True)
        except mcp.ToolError:
            pass


def app_rows(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for name in selected:
                check(name, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        if "K1" in selected:
            try:
                k1(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                check("K1", False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    selected |= {"Z1"}
    if WORK.exists():
        shutil.rmtree(WORK)
    HOME.mkdir(parents=True)
    print(f"CU11 — motion blur ({proof_app.config()} build)", flush=True)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
