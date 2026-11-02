#!/usr/bin/env python3
"""Road map "creator-jobs" CU5 — cursor data travels (spec §11 CU-50…CU-55).

A recording's cursor file goes where its movie goes, the Media tab offers Locate… and Remove
(`set_media_cursor`), and agents read the file through `get_cursor_events`. The proof drives
its own instance (`mcp.launch`, a scratch HOME) over copies of `tools/proof/media/A.mov`
(640 × 360, 10 s) and v1 cursor files written here, per `core/src/cursor_file.rs`, with
`movie_size` [640, 360] and `in_picture: false`: 320 × 180 pt at 2 px a point, so a file unit
(points × 100) is 1/50 px. The moves run k = 0…299 every 10 ms on one line, x = 20 + k px and
y = 40 + k/2 px (no hold: every gap is under 25 ms), so the raw path at t µs is (20 + t/10⁴,
40 + t/(2·10⁴)) exactly. Clicks i = 0…4 at 0.4, 0.8, 1.2, 1.6 and 2.0 s at (100 + 2i, 80 + i)
px; scrolls at 0.6 and 1.4 s at (120, 100) px.

- M1 Consolidate Media on a saved project with A.mov imported beside its `.fjcursor`: the
  movie and the cursor file both land in `media/`, `get_project`'s paths are inside the package
  and the cursor carries no bookmark; two files copied.
- M2 the package moved, the originals removed, reopened: both paths re-anchored to the moved
  package and `render_frame` at 1 s (the cursor drawn ×3) byte-equal to before Consolidate.
- M3 (probe, `cu5_probe.swift`) `MediaPane.cursorLine`'s four strings, the Media pane's
  `media.cursor` section present iff a media is a video with a picture (and after Remove),
  Locate's attach refusing a 320 × 180 file in CU-34's sentence.
- M4 `get_cursor_events`: on a clip of the media trimmed to source [0.5 s, 2.5 s) with crop
  {l: 40, t: 20}, the clicks and scrolls in clip time with x, y and q = (x − 320 − 20,
  y − 180 − 10) to 1e-9; with media and `kinds: ["path"]` over [0, 3 s), 30 samples on the
  raw line to 1e-9 px.
- M5 the cursor file at mode 000: Consolidate copies and relinks the movie, names the cursor
  file in a failure, and `media.cursor.path` is still the original.
- M6 `set_media_cursor` with a `scope` refused: "set_media_cursor has no meaning inside nest N".
- M7 a reversed clip refused by name; `{media}` still answers.
- M8 a file of 5,003 clicks: 5,000 and `next`, then 3 from `next` with no `next`.
- M9 the tool refuses a 320 × 180 file and an `in_picture` unlike the file's, each in its
  sentence, `media.cursor` unchanged; the matching file and flag apply. And `grep "Frame Job: "`
  over the instance's log prints nothing.

    python3 tools/proof/cu5_proof.py [--only M1,M4] [--app PATH]
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/cu5"
HOME = WORK / "home"
MOVIE = ROOT / "tools/proof/media/A.mov"
SEC = 600_000
CALL_BOUND = 300
ROWS = ["M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9"]
EXACT = 1e-9

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


# ---- the fixture ----------------------------------------------------------------

def ticks(us):
    assert us % 5 == 0
    return us // 5 * 3


CLICKS = [(400_000 * (i + 1), 100 + 2 * i, 80 + i) for i in range(5)]   # (µs, px x, px y)
SCROLLS = [(600_000, 120, 100), (1_400_000, 120, 100)]


def body(movie_size=(640, 360), in_picture=False, clicks=None):
    """A v1 cursor file as `core/src/cursor_file.rs` specifies it."""
    k = range(300)
    clicks = CLICKS if clicks is None else clicks
    n = len(clicks)
    return {
        "format": "framejob-cursor", "version": 1, "in_picture": in_picture,
        "source": "display", "display_id": 1, "source_frame": [0, 0, 32000, 18000],
        "point_size": [32000, 18000], "pixels_per_point": 2.0, "content_size": [640, 360],
        "movie_size": list(movie_size), "anchor": "e2", "anchor_host_us": 1000,
        "cursor_image": "none",
        "moves": {"t": [10_000 * i for i in k], "x": [1000 + 50 * i for i in k],
                  "y": [2000 + 25 * i for i in k]},
        "images": [], "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {"t": [c[0] for c in clicks], "button": [0] * n, "down": [1] * n,
                   "x": [c[1] * 50 for c in clicks], "y": [c[2] * 50 for c in clicks],
                   "count": [1] * n},
        "scrolls": {"t": [s[0] for s in SCROLLS], "x": [s[1] * 50 for s in SCROLLS],
                    "y": [s[2] * 50 for s in SCROLLS], "dx": [0, 0], "dy": [-300, 300]},
        "geometry": [{"t": 0, "screen_rect": [0, 0, 32000, 18000],
                      "content_rect": [0, 0, 32000, 18000], "content_scale": 1.0,
                      "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {"t": [], "keys": [], "code": []}, "typed": {"t": []}},
    }


def write_cursor(path, **kwargs):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(body(**kwargs)))
    return path


def recording(name):
    """`<WORK>/rec/<name>/A.mov` with its `A.fjcursor` beside; the movie's path."""
    folder = WORK / "rec" / name
    folder.mkdir(parents=True, exist_ok=True)
    movie = folder / "A.mov"
    shutil.copyfile(MOVIE, movie)
    write_cursor(folder / "A.fjcursor")
    return movie


# ---- the app ----------------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def media(self, media_id):
        return next(m for m in self.project()["media"] if m["id"] == media_id)

    def frame(self, tag, t):
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        self.call("render_frame", t=t, path=str(out))
        return out.read_bytes() if out.exists() else None


def new_doc(client, name, folder=WORK):
    path = folder / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    folder.mkdir(parents=True, exist_ok=True)
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


def error_of(body_):
    try:
        body_()
    except mcp.ToolError as error:
        return str(error)
    return None


def imported(doc, movie):
    """Imports `movie` and puts one clip of it at 0; (media id, clip id)."""
    media = doc.call("import_media", path=str(movie))["media"]
    tracks = doc.project()["tracks"]
    if not tracks:
        doc.call("add_track")
        tracks = doc.project()["tracks"]
    doc.call("add_clip", track=tracks[0]["id"], media=media, at=0)
    clip = max(c["id"] for c in doc.project()["clips"])
    return media, clip


def near(a, b):
    return a is not None and abs(a - b) <= EXACT


# ---- M1, M2 -----------------------------------------------------------------------

def m1_m2(client):
    doc = new_doc(client, "m1")
    moved_root = WORK / "moved"
    moved = moved_root / "m1.framejob"
    try:
        movie = recording("m1")
        media, clip = imported(doc, movie)
        attached = doc.media(media).get("cursor") or {}
        check("M1", attached.get("path") == str(movie.with_suffix(".fjcursor")),
              f"import attached {attached.get('path')}")
        doc.call("set_video", clips=[clip], patch={"cursor": {"scale": 3}})
        before = doc.frame("m2-before", SEC)
        answer = doc.call("consolidate_media")
        doc.call("save_project")
        row = doc.media(media)
        inside = doc.path / "media"
        cursor = row.get("cursor") or {}
        check("M1", row["path"] == str(inside / "A.mov") and Path(row["path"]).exists(),
              f"movie at {row['path']}")
        check("M1", cursor.get("path") == str(inside / "A.fjcursor")
              and Path(cursor.get("path", "/nonexistent")).exists()
              and "bookmark" not in cursor and cursor.get("in_picture") is False,
              f"cursor {cursor}")
        check("M1", answer.get("copied") == 2, f"copied {answer.get('copied')}, "
              f"summary {answer.get('summary')!r}")
        if "M2" not in selected:
            return
        close(client, doc.path)
        if moved_root.exists():
            shutil.rmtree(moved_root)
        moved_root.mkdir(parents=True)
        os.rename(doc.path, moved)
        shutil.rmtree(movie.parent)
        client.call("open_project", path=str(moved))
        again = Doc(client, moved)
        row = again.media(media)
        cursor = row.get("cursor") or {}
        check("M2", row["path"] == str(moved / "media" / "A.mov")
              and cursor.get("path") == str(moved / "media" / "A.fjcursor"),
              f"re-anchored: movie {row['path']}, cursor {cursor.get('path')}")
        after = again.frame("m2-after", SEC)
        check("M2", before is not None and before == after,
              f"render_frame at 1 s byte-equal to before Consolidate: "
              f"{None if before is None else len(before)} / "
              f"{None if after is None else len(after)} bytes")
        close(client, moved)
    finally:
        close(client, doc.path)
        close(client, moved)


# ---- M3 (probe) -------------------------------------------------------------------

def m3():
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "cu5_probe.swift", entry)
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    binary = out / "cu5-probe"
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        check("M3", False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    good = write_cursor(out / "good.fjcursor")
    wrong = write_cursor(out / "wrong.fjcursor", movie_size=(320, 180))
    request = out / "request.json"
    request.write_text(json.dumps({"good": str(good), "wrong": str(wrong),
                                   "absent": str(out / "absent.fjcursor")}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=600, env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
        rows = json.loads(run.stdout)["rows"]
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        check("M3", False, f"the probe gave no answer: {error}")
        return
    got = next((r for r in rows if r["id"] == "M3"), None)
    check("M3", got is not None and got["pass"], (got or {}).get("detail", "no row"))


# ---- M4, M7 -----------------------------------------------------------------------

def m4_m7(client):
    doc = new_doc(client, "m4")
    try:
        media, clip = imported(doc, recording("m4"))
        doc.call("trim_start", clip=clip, to=SEC // 2)
        doc.call("trim_end", clip=clip, to=SEC // 2 + 2 * SEC)
        doc.call("set_video", clips=[clip], patch={"crop": {"l": 40, "t": 20, "r": 0, "b": 0}})
        if "M4" in selected:
            m4(doc, media, clip)
        if "M7" in selected:
            m7(doc, media, clip)
    finally:
        close(client, doc.path)


def m4(doc, media, clip):
    answer = doc.call("get_cursor_events", clip=clip)
    low, high = SEC // 2, SEC // 2 + 2 * SEC          # the clip's source window, ticks
    want_clicks = [(ticks(us) - low, x, y) for us, x, y in CLICKS if low <= ticks(us) < high]
    want_scrolls = [(ticks(us) - low, x, y) for us, x, y in SCROLLS if low <= ticks(us) < high]
    clicks, scrolls = answer.get("clicks") or [], answer.get("scrolls") or []
    check("M4", answer.get("time") == "clip" and len(clicks) == len(want_clicks) == 4
          and len(scrolls) == len(want_scrolls) == 2 and answer.get("count") == 6
          and answer.get("shortcuts") == [] and answer.get("typing") == []
          and "next" not in answer and answer.get("size") == [640, 360],
          f"time {answer.get('time')}, {len(clicks)} clicks, {len(scrolls)} scrolls, count "
          f"{answer.get('count')}, size {answer.get('size')}")
    bad = []
    for got, (t, x, y) in zip(clicks + scrolls, want_clicks + want_scrolls):
        q = got.get("q") or [None, None]
        if not (got.get("t") == t and near(got.get("x"), x) and near(got.get("y"), y)
                and near(q[0], x - 320 - 20) and near(q[1], y - 180 - 10)):
            bad.append({"got": got, "want": [t, x, y, x - 340, y - 190]})
    check("M4", not bad, f"t, x, y and q of {len(clicks) + len(scrolls)} rows: "
          f"{bad[:2] or 'all exact'}")
    path_answer = doc.call("get_cursor_events", media=media, to=3 * SEC, kinds=["path"])
    path = path_answer.get("path") or {}
    t, xs, ys = path.get("t") or [], path.get("x") or [], path.get("y") or []
    wrong = [(tt, x, y) for tt, x, y in zip(t, xs, ys)
             if not (near(x, 20 + tt / 0.6 / 10_000) and near(y, 40 + tt / 0.6 / 20_000))]
    check("M4", path_answer.get("time") == "media" and path.get("smoothing") == 0
          and t == [60_000 * j for j in range(30)] and len(xs) == len(ys) == 30 and not wrong,
          f"{len(t)} samples, smoothing {path.get('smoothing')}, off the line: {wrong[:2]}")


def m7(doc, media, clip):
    doc.call("set_reversed", clip=clip, reversed=True)
    message = error_of(lambda: doc.call("get_cursor_events", clip=clip)) or ""
    want = (f"Clip {clip} plays reversed; get_cursor_events reads only clips that play forward. "
            f"Ask with media {media} for the file's own times.")
    check("M7", want in message, f"{message[:200] or 'no refusal'}")
    answer = doc.call("get_cursor_events", media=media)
    check("M7", answer.get("ok") is True and len(answer.get("clicks") or []) == len(CLICKS),
          f"with media: {len(answer.get('clicks') or [])} clicks")


# ---- M5 ---------------------------------------------------------------------------

def m5(client):
    doc = new_doc(client, "m5")
    movie = recording("m5")
    original = movie.with_suffix(".fjcursor")
    try:
        media, _ = imported(doc, movie)
        os.chmod(original, 0)
        answer = doc.call("consolidate_media")
        row = doc.media(media)
        check("M5", row["path"] == str(doc.path / "media" / "A.mov"),
              f"movie relinked to {row['path']}")
        check("M5", (row.get("cursor") or {}).get("path") == str(original),
              f"cursor still {(row.get('cursor') or {}).get('path')}")
        failures = answer.get("failures") or []
        check("M5", any(line.startswith("A.fjcursor") for line in failures)
              and not (doc.path / "media" / "A.fjcursor").exists(),
              f"failures {failures}")
    finally:
        os.chmod(original, 0o644)
        close(client, doc.path)


# ---- M6, M8, M9 ---------------------------------------------------------------------

def m6_m8_m9(client):
    doc = new_doc(client, "m6")
    try:
        movie = recording("m6")
        media, clip = imported(doc, movie)
        file = str(movie.with_suffix(".fjcursor"))
        if "M6" in selected:
            doc.call("nest", clips=[clip])
            nest = doc.project()["nests"][0]["id"]
            message = error_of(lambda: doc.call(
                "set_media_cursor", media=media, scope=nest,
                cursor={"path": file, "in_picture": False})) or ""
            check("M6", f"set_media_cursor has no meaning inside nest {nest}" in message,
                  message[:200] or "no refusal")
        if "M9" in selected:
            m9(doc, media, movie)
        if "M8" in selected:
            m8(doc, media)
    finally:
        close(client, doc.path)


def m9(doc, media, movie):
    before = doc.media(media).get("cursor")
    wrong = write_cursor(WORK / "m9" / "wrong.fjcursor", movie_size=(320, 180))
    message = error_of(lambda: doc.call(
        "set_media_cursor", media=media, cursor={"path": str(wrong), "in_picture": False})) or ""
    check("M9", "The cursor file wrong.fjcursor was not attached: its movie_size is 320 × 180 "
          "and the movie is 640 × 360." in message, message[:200] or "no refusal")
    good = write_cursor(WORK / "m9" / "good.fjcursor")
    message = error_of(lambda: doc.call(
        "set_media_cursor", media=media, cursor={"path": str(good), "in_picture": True})) or ""
    check("M9", "The cursor file good.fjcursor was not attached: its in_picture is false and "
          "the call says true." in message, message[:200] or "no refusal")
    check("M9", doc.media(media).get("cursor") == before, "media.cursor unchanged")
    doc.call("set_media_cursor", media=media, cursor={"path": str(good), "in_picture": False})
    check("M9", doc.media(media).get("cursor") == {"path": str(good), "in_picture": False},
          f"applied: {doc.media(media).get('cursor')}")


def m8(doc, media):
    many = write_cursor(WORK / "m8" / "many.fjcursor",
                        clicks=[(1000 * (k + 1), 100, 80) for k in range(5003)])
    doc.call("set_media_cursor", media=media, cursor={"path": str(many), "in_picture": False})
    first = doc.call("get_cursor_events", media=media, kinds=["clicks"])
    nxt = first.get("next")
    want_next = ticks(1000 * 5001)
    check("M8", len(first.get("clicks") or []) == 5000 and first.get("count") == 5000
          and nxt == want_next,
          f"page 1: {len(first.get('clicks') or [])} clicks, next {nxt} (want {want_next})")
    second = doc.call("get_cursor_events", media=media, kinds=["clicks"], **{"from": nxt or 0})
    check("M8", len(second.get("clicks") or []) == 3 and "next" not in second,
          f"page 2: {len(second.get('clicks') or [])} clicks, next {second.get('next')}")


# ---- main -------------------------------------------------------------------------

def app_rows(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected - {"M3"}:
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        groups = [({"M1", "M2"}, m1_m2), ({"M4", "M7"}, m4_m7), ({"M5"}, m5),
                  ({"M6", "M8", "M9"}, m6_m8_m9)]
        for rows, body_ in groups:
            if not rows & selected:
                continue
            try:
                body_(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                for row in rows & selected:
                    check(row, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    for row in sorted(selected - {"M3"})[-1:]:
        check(row, not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


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
    if WORK.exists():
        for folder, _, files in os.walk(WORK):
            for name in files:
                try:
                    os.chmod(os.path.join(folder, name), 0o644)
                except OSError:
                    pass
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    print(f"CU5 — cursor data travels ({proof_app.config()} build)", flush=True)
    if "M3" in selected:
        m3()
    if selected - {"M3"}:
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
