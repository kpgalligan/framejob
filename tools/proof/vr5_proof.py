#!/usr/bin/env python3
"""Road map "creator-jobs" VR5 — screen recordings follow the cursor (spec §11 VR-50…VR-52,
VR-55).

    python3 tools/proof/vr5_proof.py [--only V1,V2,…] [--mutant NAME] [--app PATH]

The fixture: ffmpeg's `testsrc` 1920 × 1080, 30 fps, 20 s, copied once per document, on a
1920 × 1080 30 fps canvas, one clip of the whole movie at 0, and a v1 cursor file beside each
copy (`core/src/cursor_file.rs`; `movie_size` the movie's, 2 px a point, so a file unit is
1/50 px; `import_media` attaches it, CU-34). Its path in movie px, y = 540 throughout: x 400 →
1100 linearly over 0–8 s (87.5 px a second), held at 1100 to 9.9 s, 1700 from 10.0 s (a down
click at 10.0 s), held to 13.9 s, 300 from 14.0 s (a down click at 14.0 s), held to 16 s, 300 →
600 over 16–18 s with typed marks every 0.2 s making one stretch 16–18 s, held at 600 to 20 s;
a move every 50 ms. One launch, `-RCDevAnalysisCanned YES -RCDevFollowAccept YES
-FrameJobFollowKind subject -FrameJobFollowWhereEmpty fit`, on a scratch `CFFIXED_USER_HOME`.

The derivation (the 9:16 copy: the window 607.5 px of the picture, its centre clamped to
303.75…1616.25): the sweep is inside the clamp range; at 0.144 W a second a 0.4 s move ends
0.06 W behind and the 0.5 s hold adds 0.07 W, so the cursor stays within ≈ ±0.21 W of the
window's centre; both clicks' clamped centres lie more than 0.8 W from the window's target, so
each gets an arrival; from 16.84 s the pointer is more than 0.20 W from the window, so without
the typing hold a move would start inside 16–18 s. The direct `reframe_clip {follow: cursor}`
calls use `zoom: 2` on the 16:9 canvas (the window 960 px, its centre clamped to 480…1440;
both clicks more than 0.2 W from the target): at zoom 1 the window is the whole picture.

A placement is read back through `get_project` and evaluated here (`vr2a_proof.py`'s
`placement`): the window's centre in picture px is `(960 − x/scale, 540 − y/scale)`, and a
picture point lands on the canvas at `W/2 + x + scale·(px − 960)`, `H/2 + y + scale·(py − 540)`.

Rows:
- V1 In the 9:16 copy every 10 Hz sample in 0.5–8 s of the clip's smoothed cursor
  (`get_cursor_events {clip, kinds: [path], smoothing: 0.5}`), placed through the copy's clip,
  is on the canvas and inside the canvas's central 60 % of width (the derivation's ±0.21 W
  against ±0.30 W). Clicks are V2's, typing V6's.
- V2 `reframe_clip {follow: cursor, zoom: 2}` (on a 16:9 scratch) and the copy each have an
  action ending on each click's frame with the window centred on the click's clamped point
  (±1e-6).
- V3 With canned panning faces on the media (`canned_framing.write`), the copy's clip `video`
  and `actions` equal the face-free run's, and `reframe_clip {follow: face}` is refused in
  VR-51's sentence.
- V4 After `auto_zoom` on the clip, the copy's clip has no end naming the auto zoom's scale —
  every end's scale is the base's, the framing's own, where a zoom composed in would carry the
  zoom times it — the answer's `cursor` lists it and the summary has VR-52's sentence.
- V5 With the `.fjcursor` deleted, the clip's entry is `not_followed` with VR-51's reason and
  one "Blurred Background" sits on Backgrounds.
- V6 In the copy no framing action starts inside (16 s, 18 s), and one starts at or after 18 s.
- V7 A fresh copy with no canned analysis: select the clip, Clip ▸ Follow Subject…; within
  10 s the sheet's summary (`follow.summary`) carries VR-51's sentence for the clip, no
  "Analyzing" view is seen in the 10 s polled, `cache/analysis/` holds no file for the media,
  and after `cancel_sheet` the project is unchanged with no "Follow Subject" undo step.
- Z1 `grep "Frame Job: "` of the instance's log prints nothing.

`--mutant NAME` (tools/proof/README.md's VR5 section): the named decision broken. `core`
mutants run the core's `reframe_cursor` tests on a copy of `core/`; `app` mutants build a
`tree_copy.py` copy (its `core/` a real copy, so a core edit reaches the app) and run their
rows. CAUGHT exits 1, SURVIVED exits 0, a control that could not be performed exits 2.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import canned_framing  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/vr5-proof"
HOME = WORK / "home"
CALL_BOUND = 400
BUILD_BOUND = 1500
SEC = 600_000
FRAME = 20_000
CLICKS = [(10.0, 1700.0), (14.0, 300.0)]
ROWS = ["V1", "V2", "V3", "V4", "V5", "V6", "V7", "Z1"]
MENU = ["Clip", "Follow Subject…"]
READING = "Reading the analysis…"
LAUNCH = ["-RCDevAnalysisCanned", "YES", "-RCDevFollowAccept", "YES",
          "-FrameJobFollowKind", "subject", "-FrameJobFollowWhereEmpty", "fit"]
NOT_FACES = ("clip {c}'s media has a cursor file, so it follows the cursor, not faces; frame it "
             "with cursor, center, fit or keep")
UNREAD = "its cursor file could not be read, so it is shown whole"
VR52 = "Follows the cursor in 1 clip, their own zooms and pans replaced."

EDIT_REFRAME = "core/src/edit_reframe.rs"
CURSOR = "core/src/reframe_cursor.rs"
PLAN = "app/Sources/VerticalVersion+Plan.swift"
FOLLOW = "app/Sources/FollowSubject.swift"
# name → (rows, [(path, anchor, replacement)], "core" or "app")
MUTANTS = {
    "faces-allowed": (["V3"], [(
        EDIT_REFRAME, "                    if r.follow != FramingFollow::Cursor && cursor {",
        "                    if false && r.follow != FramingFollow::Cursor && cursor {")], "app"),
    "dead-zone-face": (["V1"], [(CURSOR, "    dead_zone_width: 0.20,", "    dead_zone_width: 0.15,")],
                       "core"),
    "clicks-ignored": (["V2"], [(
        CURSOR, "        let next_click = (i.max(handled)..points.len()).find(|&j| points[j].click);",
        "        let next_click = (i.max(handled)..points.len()).find(|_| false);")], "app"),
    "replace-off": (["V4"], [(
        PLAN, "backdrop: backgrounds, replace: follow == .cursor ? true : nil,",
        "backdrop: backgrounds, replace: nil,")], "app"),
    "typing-ignored": (["V6"], [(
        CURSOR, "        if running || p.typing || !outside(target, desired[i]) {",
        "        if running || !outside(target, desired[i]) {")], "core"),
    "analysed-every-target": (["V7"], [(
        FOLLOW, "            snapshot.clip(id).flatMap { snapshot.media(for: $0) }?.cursor == nil\n",
        "            snapshot.clip(id).flatMap { snapshot.media(for: $0) }?.cursor == nil || true\n"
    )], "app"),
}
# A core mutant's rows, as the core tests that stand for them.
CORE_TESTS = {
    "dead-zone-face": "a_step_inside_the_dead_zone_moves_nothing",
    "typing-ignored": "a_typing_stretch_holds_the_window_and_the_move_follows_it",
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, *names):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for name in names:
            check(name, False, f"{type(error).__name__}: {error}")
        return None


def close(a, b, tolerance=1e-6):
    return abs(a - b) <= tolerance


# ---- the fixture ---------------------------------------------------------------------

def movie():
    out = WORK.parent / "vr5-media" / "screen.mov"
    out.parent.mkdir(parents=True, exist_ok=True)
    if not out.exists():
        partial = out.with_suffix(".partial.mov")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        "testsrc=size=1920x1080:rate=30:duration=20", "-c:v", "libx264",
                        "-pix_fmt", "yuv420p", "-g", "30", "-bf", "0", str(partial)],
                       check=True, timeout=600, env=bounded.child_env())
        partial.rename(out)
    return out


def x_at(s):
    """The pinned path's x in movie px at `s` seconds."""
    if s < 8:
        return 400 + 87.5 * s
    if s < 10:
        return 1100.0
    if s < 14:
        return 1700.0
    if s < 16:
        return 300.0
    if s < 18:
        return 300 + 150 * (s - 16)
    return 600.0


def us(seconds):
    return int(round(seconds * 1e6))


def cursor_body(size=(1920, 1080)):
    """The v1 cursor file: the pinned path, the two down clicks and the typed marks."""
    w, h = size
    times = [n * 0.05 for n in range(400)]
    marks = [16 + n * 0.2 for n in range(11)]
    n = len(CLICKS)
    return {
        "format": "framejob-cursor", "version": 1, "in_picture": False, "source": "display",
        "display_id": 1, "source_frame": [0, 0, w * 50, h * 50], "point_size": [w * 50, h * 50],
        "pixels_per_point": 2.0, "content_size": [w, h], "movie_size": [w, h],
        "anchor": "e2", "anchor_host_us": 1000, "cursor_image": "none",
        "moves": {"t": [us(s) for s in times], "x": [int(round(x_at(s) * 50)) for s in times],
                  "y": [540 * 50] * len(times)},
        "images": [], "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {"t": [us(c[0]) for c in CLICKS], "button": [0] * n, "down": [1] * n,
                   "x": [int(c[1] * 50) for c in CLICKS], "y": [540 * 50] * n,
                   "count": [1] * n},
        "scrolls": {"t": [], "x": [], "y": [], "dx": [], "dy": []},
        "geometry": [{"t": 0, "screen_rect": [0, 0, w * 50, h * 50],
                      "content_rect": [0, 0, w * 50, h * 50], "content_scale": 1.0,
                      "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {"t": [], "keys": [], "code": []},
                 "typed": {"t": [us(s) for s in marks]}},
    }


# ---- placement -----------------------------------------------------------------------

def ease(curve, u):
    u = min(1.0, max(0.0, u))
    return {"linear": u, "ease_in": u * u, "ease_out": 1 - (1 - u) * (1 - u),
            "ease_in_out": u * u * (3 - 2 * u)}[curve]


def placement(clip, t):
    """(scale, x, y) at clip tick `t`: the base, each action eased from the value before it
    (`vr2a_proof.py`'s)."""
    video = clip.get("video") or {}
    cur = [video.get("scale", 1.0), video.get("x", 0.0), video.get("y", 0.0)]
    for action in sorted(clip.get("actions", []), key=lambda a: a["start"]):
        end = (action.get("end") or {}).get("video") or {}
        target = [end.get("scale", cur[0]), end.get("x", cur[1]), end.get("y", cur[2])]
        start, length = action["start"], action["duration"]
        if t >= start + length:
            cur = target
        elif t > start:
            e = ease(action.get("curve", "linear"), (t - start) / length)
            cur = [a + (b - a) * e for a, b in zip(cur, target)]
            break
        else:
            break
    return tuple(cur)


def window_centre(clip, t):
    scale, x, y = placement(clip, t)
    return 960 - x / scale, 540 - y / scale


def framing_actions(clip):
    return [a for a in clip.get("actions", [])
            if set(((a.get("end") or {}).get("video") or {})) & {"scale", "x", "y"}]


def arrivals(clip, clamp):
    """Per click: (an action ends on its frame, the window centre there, the clamped point)."""
    out = []
    for seconds, x in CLICKS:
        tick = round(seconds * SEC)
        ends = any(a["start"] + a["duration"] == tick for a in framing_actions(clip))
        centre = window_centre(clip, tick)
        want = (min(max(x, clamp[0]), clamp[1]), 540.0)
        out.append((ends and close(centre[0], want[0]) and close(centre[1], want[1]),
                    f"{seconds} s: an end {ends}, centre ({centre[0]:.6f}, {centre[1]:.6f}), "
                    f"want {want}"))
    return out


# ---- the documents ---------------------------------------------------------------------

class Doc:
    def __init__(self, client, name, faces=None, cursor=True):
        self.client = client
        self.name = name
        self.path = WORK / f"{name}.framejob"
        client.call("new_project", path=str(self.path))
        try:
            self.call("set_canvas", width=1920, height=1080, fps=[30, 1])
        except mcp.ToolError as error:  # a new project's canvas may already be this one
            if "no change" not in str(error):
                raise
        folder = WORK / "media" / name
        folder.mkdir(parents=True, exist_ok=True)
        self.movie = folder / "screen.mov"
        shutil.copyfile(movie(), self.movie)
        self.fjcursor = folder / "screen.fjcursor"
        if cursor:
            self.fjcursor.write_text(json.dumps(cursor_body()))
        self.media = self.call("import_media", path=str(self.movie))["media"]
        row = next(m for m in self.state()["media"] if m["id"] == self.media)
        if cursor and not row.get("cursor"):
            raise RuntimeError(f"import attached no cursor file to {self.movie}")
        if faces is not None:
            fps = row["fps"] if isinstance(row["fps"], list) else [row["fps"]["num"],
                                                                   row["fps"]["den"]]
            canned_framing.write(self.path, self.media, self.movie, row["duration"], fps, faces)
        if not self.state()["tracks"]:
            self.call("add_track")
        track = self.state()["tracks"][0]["id"]
        self.clip = self.call("add_clip", track=track, media=self.media, at=0)["new_clips"][0]
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def vertical(self, tag, **arguments):
        path = WORK / f"{self.name}-{tag}.framejob"
        if path.exists():
            shutil.rmtree(path)
        answer = self.call("make_vertical_version", shape="9:16", path=str(path), **arguments)
        state = self.client.call_with("get_project", {"project": str(path)})["project"]
        return answer, state, path

    def close(self):
        for path in [self.path] + sorted(WORK.glob(f"{self.name}-*.framejob")):
            try:
                self.client.call("close_project", project=str(path), discard=True)
            except mcp.ToolError:
                pass


def clip_of(state, clip):
    return next(c for c in state["clips"] if c["id"] == clip)


def refused(body, sentence):
    try:
        answer = body()
    except mcp.ToolError as error:
        text = str(error)
        return text.endswith(sentence), text
    return False, f"applied: {json.dumps(answer)[:200]}"


# ---- the rows ----------------------------------------------------------------------------

def plain_rows(client):
    doc = Doc(client, "plain")
    answer, copy, path = doc.vertical("tall")
    clip = clip_of(copy, doc.clip)

    def v1():
        got = client.call_with("get_cursor_events", {
            "project": str(path), "clip": doc.clip, "kinds": ["path"], "smoothing": 0.5,
            "from": SEC // 2, "to": 8 * SEC})
        p = got.get("path") or {}
        samples = list(zip(p.get("t") or [], p.get("x") or [], p.get("y") or []))
        width, height = 1080, 1920
        central = inside = 0
        worst = 0.0
        for t, px, py in samples:
            scale, x, y = placement(clip, t)
            cx, cy = width / 2 + x + scale * (px - 960), height / 2 + y + scale * (py - 540)
            inside += 0 <= cx <= width and 0 <= cy <= height
            central += abs(cx - width / 2) <= 0.3 * width
            worst = max(worst, abs(cx - width / 2) / width)
        n = len(samples)
        check("V1", n >= 70 and inside == n and central == n,
              f"{n} samples in 0.5–8 s: on the canvas {inside}, in the central 60 % {central}; "
              f"the farthest {worst:.3f} W from the centre")
    attempt(v1, "V1")

    def v2_copy():
        for ok, detail in arrivals(clip, (303.75, 1616.25)):
            check("V2", ok, f"the copy: {detail}")
    attempt(v2_copy, "V2")

    def v6():
        starts = sorted(a["start"] for a in framing_actions(clip))
        inside = [s for s in starts if 16 * SEC < s < 18 * SEC]
        after = [s for s in starts if s >= 18 * SEC]
        check("V6", not inside and bool(after),
              f"framing actions starting inside (16, 18) s: {[s / SEC for s in inside]}; at or "
              f"after 18 s: {[s / SEC for s in after]}")
    attempt(v6, "V6")
    doc.close()
    return clip


def direct_row(client):
    doc = Doc(client, "direct")
    doc.call("reframe_clip", clip=doc.clip, follow="cursor", zoom=2)
    clip = clip_of(doc.state(), doc.clip)
    for ok, detail in arrivals(clip, (480.0, 1440.0)):
        check("V2", ok, f"reframe_clip zoom 2: {detail}")
    doc.close()


def faces_row(client, plain):
    doc = Doc(client, "faces", faces=canned_framing.pan)
    _, copy, _ = doc.vertical("tall")
    clip = clip_of(copy, doc.clip)
    same = (plain is not None and clip.get("video") == plain.get("video")
            and clip.get("actions") == plain.get("actions"))
    ok, text = refused(lambda: doc.call("reframe_clip", clip=doc.clip, follow="face"),
                       NOT_FACES.format(c=doc.clip))
    check("V3", same and ok, f"the copy's clip equals the face-free run's {same}; "
          f"reframe_clip follow face: {text[-200:]}")
    doc.close()


def zoom_row(client):
    doc = Doc(client, "zoomed")
    doc.call("auto_zoom", clips=[doc.clip])
    source = clip_of(doc.state(), doc.clip)
    scales = {((a.get("end") or {}).get("video") or {}).get("scale")
              for a in source.get("actions", [])} - {None}
    answer, copy, _ = doc.vertical("tall")
    clip = clip_of(copy, doc.clip)
    # Replaced, the zooms are gone: every end's scale is the framing's own, the base's (the
    # cursor's window never changes size). Composed, an end would carry the zoom times it.
    base = (clip.get("video") or {}).get("scale", 1.0)
    ends = [((a.get("end") or {}).get("video") or {}).get("scale") for a in clip.get("actions", [])]
    zoomed = [e for e in ends if e is not None and not close(e, base)]
    listed = answer.get("cursor") == [doc.clip]
    summary = answer.get("summary") or ""
    check("V4", len(scales) > 1 and not zoomed and listed and VR52 in summary,
          f"auto zoom scales {sorted(scales)}; the copy's base scale {base:.6f}, ends at another "
          f"scale {zoomed}; answer cursor {answer.get('cursor')}; VR-52's sentence in the "
          f"summary {VR52 in summary}")
    doc.close()


def unread_row(client):
    doc = Doc(client, "unread")
    doc.fjcursor.unlink()
    answer, copy, _ = doc.vertical("tall")
    entry = next((c for c in answer.get("clips", []) if c["clip"] == doc.clip), {})
    tracks = [t for t in copy["tracks"] if t.get("name") == "Backgrounds"]
    on = [c for c in copy["clips"] if tracks and c["track"] == tracks[0]["id"]]
    blurred = [c for c in on if c.get("name") == "Blurred Background"]
    check("V5", entry.get("treatment") == "not_followed" and entry.get("reason") == UNREAD
          and len(tracks) == 1 and len(on) == 1 and len(blurred) == 1,
          f"entry {entry}; Backgrounds tracks {len(tracks)} holding {len(on)} clip(s), "
          f"{len(blurred)} named Blurred Background")
    doc.close()


def sheet_views(doc, tag):
    (WORK / "sheets").mkdir(parents=True, exist_ok=True)
    try:
        got = doc.call("snapshot_ui", window="sheet", path=str(WORK / "sheets" / f"{tag}.png"))
    except mcp.ToolError:
        return None
    path = got.get("layout_path") if isinstance(got, dict) else None
    if not path:
        return None
    return json.loads(Path(path).read_text()).get("views") or []


def follow_row(client):
    doc = Doc(client, "follow")
    before = doc.state()
    doc.call("set_selection", clips=[doc.clip])
    doc.call("perform_menu_item", path=MENU)
    sentence = f"Clip {doc.clip}: " + NOT_FACES.format(c=doc.clip)
    began = time.monotonic()
    summary = None
    analyzing = False
    while time.monotonic() - began < 10:
        views = sheet_views(doc, "follow")
        analyzing |= any(v.get("text") == "Analyzing" and not v.get("hidden")
                         for v in views or [])
        found = [v for v in views or [] if v.get("id") == "follow.summary" and not v.get("hidden")]
        if found:
            summary = found[0].get("text")
        time.sleep(0.2)
    try:
        doc.call("cancel_sheet")
    except mcp.ToolError:
        pass
    folder = doc.path / "cache" / "analysis"
    files = [str(p.relative_to(folder)) for p in folder.rglob("*")
             if p.is_file() and (p.stem == str(doc.media) or p.parent.name == str(doc.media))
             ] if folder.exists() else []
    after = doc.state()
    try:
        undone = doc.call("undo").get("undone")
        doc.call("redo")
    except mcp.ToolError:
        undone = None
    check("V7", summary is not None and sentence in summary and not analyzing and not files
          and after == before and undone != "Follow Subject",
          f"summary {summary!r}; Analyzing seen {analyzing}; analysis files {files}; unchanged "
          f"{after == before}; undo top {undone!r}")
    doc.close()


def run_rows(client):
    plain = None
    if selected & {"V1", "V2", "V3", "V6"}:
        plain = attempt(lambda: plain_rows(client), "V1", "V2", "V6")
    if "V2" in selected:
        attempt(lambda: direct_row(client), "V2")
    if "V3" in selected:
        attempt(lambda: faces_row(client, plain), "V3")
    if "V4" in selected:
        attempt(lambda: zoom_row(client), "V4")
    if "V5" in selected:
        attempt(lambda: unread_row(client), "V5")
    if "V7" in selected:
        attempt(lambda: follow_row(client), "V7")


def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def run_launch(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), list(LAUNCH),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in sorted(selected - {"Z1"}):
                check(row, False, "the app did not listen")
        else:
            print(f"  instance PID {launched.child.pid}", flush=True)
            run_rows(launched.client)
    finally:
        launched.stop()
    parity(log)


# ---- the mutants ---------------------------------------------------------------------

def edit(root, name):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(root) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def core_mutant(name):
    """The core's `reframe_cursor` tests on a copy of `core/` with the mutant's edits: the
    failing tests' names, or None and the reason the control could not be performed."""
    copy = WORK.parent / "vr5-mutant-core"
    if copy.exists():
        tree_copy.remove_tree(str(copy))
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "core", copy / "core", ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "graphic", copy / "graphic")
    why = edit(copy, name)
    if why:
        return None, why
    env = bounded.child_env({"CARGO_TARGET_DIR": str(WORK.parent / "vr5-mutant-target")})
    run = subprocess.run(["cargo", "test", "--release", "--test", "reframe_cursor"],
                         cwd=copy / "core", capture_output=True, text=True, timeout=BUILD_BOUND,
                         env=env)
    (WORK.parent / f"vr5-mutant-{name}.log").write_text(run.stdout + run.stderr)
    failed = [line.split()[1] for line in run.stdout.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    if run.returncode != 0 and not failed:
        return None, "cargo test did not run the tests (see the log)"
    return failed, None


def mutant_app(name):
    """A `tree_copy.py` copy — for a core edit its `core/` a real copy (CoW, its `target/`
    too), so the edit reaches the copy's app, never the tree's linked one — built as
    `proof_app.config()` chooses."""
    made, reason = tree_copy.make_copy(str(WORK.parent / "vr5-mutant"))
    if made is None:
        return None, reason
    core = Path(made) / "core"
    if core.is_symlink() and any(path.startswith("core/") for path, _, _ in MUTANTS[name][1]):
        core.unlink()
        ran = subprocess.run(["cp", "-cR", str(ROOT / "core"), str(core)], capture_output=True,
                             text=True, timeout=600)
        if ran.returncode != 0:
            return None, f"cp core: {ran.stderr[-300:]}"
    why = edit(made, name)
    if why:
        return None, why
    app, why = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, why)


def run_mutant(name):
    global selected
    rows, _, kind = MUTANTS[name]
    print(f"VR5 — the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    if kind == "core":
        failed, why = core_mutant(name)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        caught = CORE_TESTS[name] in failed
        print(f"failing tests: {failed or 'none'}")
        print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {CORE_TESTS[name]} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    binary, why = mutant_app(name)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    selected = set(rows)
    run_launch(binary)
    if not set(rows) & set(results):
        print(f"mutant {name}: the control could not be performed — its rows were never scored")
        return 2
    caught = [r for r in rows if r in results and not all(ok for ok, _ in results[r])]
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()} | {"Z1"}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    movie()
    if args.mutant:
        return run_mutant(args.mutant)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"VR5 — screen recordings follow the cursor ({proof_app.config()} build)", flush=True)
    run_launch(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
