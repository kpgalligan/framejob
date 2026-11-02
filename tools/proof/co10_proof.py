#!/usr/bin/env python3
"""Road map "creator-jobs" CO10a — a picture's cutout in the model and the
recipe (spec §11 CO-100…CO-104): `foreground` on an image clip only, the
recipe's image arm, an image's cutout drawn uncut until CO10b, and
`analyze_cutout` leaving pictures out.

    python3 tools/proof/co10_proof.py [--only S2,S3,…] [--app PATH]

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) in
one launch on a scratch `CFFIXED_USER_HOME`, with `-RCDevAnalysisHold 3600` so
the masks a cut media clip wants (CO-22) are never made: nothing here reads a
mask. The media are a copy of `media/A.mov` (640×360, 30 fps, 10 s) and a
64×48 RGB PNG this script writes with `zlib` and `struct`, on a 640×360
canvas.
- S2 `set_video {cutout: {subject: "foreground"}}` on a media clip and on a
  `freeze_frame` still each answers its exact sentence ("clip N is a media
  clip and cannot take a foreground cutout: only an image clip can", "… a
  still clip …"), `get_project` unchanged after each.
- S3 on an image clip, `{subject: "foreground"}` reads back all five keys,
  `{edge: 0.25}` merges, and `null` removes the key.
- S4 `render_frame` at 2 times with the image clip's cutout on equals the
  PNGs with it off, byte for byte, each call answering in under 10 s (no
  30 s mask wait: an image layer is never waited for, CO-102).
- S5 a project with a cut image clip and a cut media clip:
  `analyze_cutout {clips: [image], wait: 0}` answers "Clip N is an image
  clip; an image clip's Remove Background is kept but not analysed yet.";
  `analyze_cutout {wait: 0}` answers rows for the media clip only; with the
  media clip's cutout removed, `analyze_cutout {wait: 0}` answers "No video
  or still clip in the open scope has Remove Background on; an image clip's
  is kept but not analysed yet." (CO-103).
- Z1 the launch's `grep "Frame Job: "` prints nothing.

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import shutil
import struct
import sys
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co10"
HOME = WORK / "home"
MOVIE = ROOT / "tools/proof/media/A.mov"
CALL_BOUND = 300
SEC = 600_000
ROWS = ["S2", "S3", "S4", "S5", "Z1"]
HELD = ["-RCDevAnalysisHold", "3600"]
PNG_W, PNG_H = 64, 48
RENDER_TIMES = [SEC // 2, 2 * SEC]
RENDER_LIMIT = 10.0
DEFAULTS = {"subject": "person", "quality": "standard", "background": "remove",
            "edge": 0.0, "feather": 0.0}


def foreground_sentence(clip, what):
    return (f"clip {clip} is {what} and cannot take a foreground cutout: "
            "only an image clip can")


def image_sentence(clip):
    return (f"Clip {clip} is an image clip; an image clip's Remove Background is kept but "
            "not analysed yet.")


EMPTY_SENTENCE = ("No video or still clip in the open scope has Remove Background on; an "
                  "image clip's is kept but not analysed yet.")

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the media ----------------------------------------------------------------------

def movie():
    copy = WORK / "media" / "A.mov"
    if not copy.exists():
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MOVIE, copy)
    return copy


def picture():
    """A 64×48 8-bit RGB PNG: a red-to-blue ramp across, green down."""
    path = WORK / "media" / "picture.png"
    if path.exists():
        return path
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


# ---- documents ----------------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def cutout(self, clip):
        return (self.clip(clip).get("video") or {}).get("cutout")


def new_doc(client, name):
    path = WORK / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    doc.call("set_canvas", width=640, height=360, fps=[30, 1])
    doc.call("save_project")
    return doc


def close(client, path):
    try:
        client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass


def error_of(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


def track(doc):
    tracks = doc.project()["tracks"]
    if not tracks:
        doc.call("add_track")
        tracks = doc.project()["tracks"]
    return tracks[0]["id"]


def add_movie(doc, at=0, on=None):
    """A.mov added and placed at `at` on track `on` (the first); the clip's id."""
    before = {c["id"] for c in doc.project()["clips"]}
    doc.call("add_media", descriptor={
        "path": str(movie()), "kind": "video", "duration": 10 * SEC, "width": 640,
        "height": 360, "fps": [30, 1], "has_video": True})
    media = next(m["id"] for m in doc.project()["media"] if m["kind"] == "video")
    doc.call("add_clip", track=on or track(doc), media=media, at=at)
    return next(c["id"] for c in doc.project()["clips"] if c["id"] not in before)


def add_picture(doc, at=0, on=None):
    """The PNG added and placed at `at` on track `on` (the first); the clip's id."""
    before = {c["id"] for c in doc.project()["clips"]}
    doc.call("add_media", descriptor={
        "path": str(picture()), "kind": "image", "width": PNG_W, "height": PNG_H})
    media = next(m["id"] for m in doc.project()["media"] if m["kind"] == "image")
    doc.call("add_clip", track=on or track(doc), media=media, at=at)
    return next(c["id"] for c in doc.project()["clips"] if c["id"] not in before)


# ---- the rows -----------------------------------------------------------------------

def s2(client):
    doc = new_doc(client, "s2")
    try:
        clip = add_movie(doc)
        doc.call("freeze_frame", clip=clip, at=2 * SEC, duration=SEC)
        still = next(c["id"] for c in doc.project()["clips"]
                     if c["source"]["kind"] == "still")
        for what, target in [("a media clip", clip), ("a still clip", still)]:
            before = doc.project()
            sentence = foreground_sentence(target, what)
            message = error_of(lambda: doc.call(
                "set_video", clips=[target], patch={"cutout": {"subject": "foreground"}}))
            check("S2", message == f"set_video: {sentence}",
                  f"{what}: {message or 'no error'}")
            check("S2", doc.project() == before, f"{what}: get_project unchanged")
    finally:
        close(client, doc.path)


def s3(client):
    doc = new_doc(client, "s3")
    try:
        clip = add_picture(doc)
        doc.call("set_video", clips=[clip], patch={"cutout": {"subject": "foreground"}})
        stored = doc.cutout(clip)
        want = dict(DEFAULTS, subject="foreground")
        check("S3", stored == want, f"{{subject: foreground}} stored {stored}")
        doc.call("set_video", clips=[clip], patch={"cutout": {"edge": 0.25}})
        merged = doc.cutout(clip)
        check("S3", merged == dict(want, edge=0.25), f"{{edge: 0.25}} merged to {merged}")
        doc.call("set_video", clips=[clip], patch={"cutout": None})
        video = doc.clip(clip).get("video") or {}
        check("S3", "cutout" not in video, f"null removed it: {sorted(video)}")
    finally:
        close(client, doc.path)


def frames(doc, tag):
    """`render_frame` at each of RENDER_TIMES: the PNGs' bytes and each call's seconds."""
    shots, seconds = [], []
    for t in RENDER_TIMES:
        out = WORK / f"{tag}-{t}.png"
        if out.exists():
            out.unlink()
        began = time.monotonic()
        doc.call("render_frame", t=t, path=str(out))
        seconds.append(time.monotonic() - began)
        shots.append(out.read_bytes() if out.exists() else None)
    return shots, seconds


def s4(client):
    doc = new_doc(client, "s4")
    try:
        clip = add_picture(doc)
        doc.call("set_video", clips=[clip], patch={"scale": 4.0})
        uncut, uncut_s = frames(doc, "off")
        doc.call("set_video", clips=[clip], patch={"cutout": {"subject": "foreground"}})
        cut, cut_s = frames(doc, "on")
        same = [a is not None and a == b for a, b in zip(uncut, cut)]
        check("S4", len(cut) == len(RENDER_TIMES) and all(same),
              f"{len(RENDER_TIMES)} frames with the cutout on equal those with it off: {same}")
        slow = [round(s, 2) for s in uncut_s + cut_s if s >= RENDER_LIMIT]
        check("S4", not slow,
              f"each render_frame under {RENDER_LIMIT:g} s: "
              f"{[round(s, 2) for s in uncut_s + cut_s]}")
    finally:
        close(client, doc.path)


def s5(client):
    doc = new_doc(client, "s5")
    try:
        first = track(doc)
        doc.call("add_track")
        second = next(t["id"] for t in doc.project()["tracks"] if t["id"] != first)
        media = add_movie(doc, on=first)
        image = add_picture(doc, on=second)
        doc.call("set_video", clips=[media, image], patch={"cutout": {}})
        message = error_of(lambda: doc.call("analyze_cutout", clips=[image], wait=0))
        check("S5", message == f"analyze_cutout: {image_sentence(image)}",
              f"a named image clip: {message or 'no error'}")
        answer = doc.call("analyze_cutout", wait=0)
        rows = [row.get("clip") for row in answer.get("clips", [])]
        check("S5", rows == [media],
              f"clips left out: rows for {rows}, the media clip is {media}")
        doc.call("set_video", clips=[media], patch={"cutout": None})
        message = error_of(lambda: doc.call("analyze_cutout", wait=0))
        check("S5", message == f"analyze_cutout: {EMPTY_SENTENCE}",
              f"only an image clip cut: {message or 'no error'}")
    finally:
        close(client, doc.path)


BODIES = [("S2", s2), ("S3", s3), ("S4", s4), ("S5", s5)]


def app_rows(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), HELD,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for name, _ in BODIES:
                check(name, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        for name, body in BODIES:
            if name not in selected:
                continue
            try:
                body(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                check(name, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace")
                     if "Frame Job: " in line]
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
        selected.add("Z1")
    remove_work()
    HOME.mkdir(parents=True)
    print(f"CO10a — a picture's cutout in the model and the recipe ({proof_app.config()} "
          "build)", flush=True)
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
