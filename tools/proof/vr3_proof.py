#!/usr/bin/env python3
"""Road map "creator-jobs" VR3a and VR3b — Make Vertical's step, its copy,
`make_vertical_version` (spec §11 VR-30…VR-37) and File ▸ Make Vertical
Version… (VR-39).

    python3 tools/proof/vr3_proof.py [--only 1,3,8] [--app PATH]

The media is one `testsrc` movie (ffmpeg, 1920 × 1080, 30 fps, 50 s, H.264)
copied once per media, and a `testsrc` still (480 × 270 PNG); the analyses are
canned (`canned_framing.py`, spec §11 CJ-26) in launch 1 and real in launch 2.
Every project is 1920 × 1080 at 30 fps on a magenta background; every placement
is read back through `get_project`, and F (spec §11 VR-34: k = s′/s,
dx = x′ − k·x, dy = y′ − k·y) is solved here from the two projects' placements,
each action eased by `actions::ease`'s four closed forms.

**The fixture** (`src.framejob`, saved, then closed, the offline media's file
removed, and opened again): a white colour plate [0, 2) s (`add_background`); on
the first track a still face A [2, 6), a screen with nothing found B [6, 10), a
still face C [10, 14) with a zoom-and-volume action, a still face D [14, 18)
with a During Drift, a still face E [18, 22) punched in at scale 1.25, the
canned exit F [22, 32), an offline movie G [32, 36), a nest H of a still face
[36, 40), a still face I [40, 44) with an `add_blurred_background` copy; on a
front track a title [2, 6), a picture-in-picture image [6, 10) and a title
whose action moves y from 200 to 0 [10, 14); then a matte pair: a still face J
[44, 48) on its own track with an alpha matte track in front holding a title K.

**Launch 1** (`-RCDevAnalysisCanned YES -RCDevVerticalAccept YES
-FrameJobFollowKind subject -FrameJobFollowWhereEmpty fit`), rows 1–10 and 12:
1. The copies' canvases are 1080 × 1920, 1080 × 1350 and 1080 × 1080; the
   4:5 copy's A passes row 7's corners; the 9:16 copy's picture-in-picture
   placement equals a scratch copy's `set_canvas` + `reframe_clip {keep,
   from_width: 1920, from_height: 1080}`; the untitled 1:1 copy is named
   "src (1:1)" and has unsaved changes.
2. The source's `project.json`, saved again, is byte-identical, and its undo
   top is unchanged.
3. The 9:16 answer's treatments are the expected ones (A, C, D, E, F, I
   followed — D because of its Drift, F with "it is shown whole on a blurred
   copy where no subject is found"; B whole; G, H, J not followed — G with
   "its media file is missing, so it is kept as placed"; K and the three
   front clips kept; the plate re-filled; I's old copy removed); the plate is
   1080 × 1920 at scale 1, centred; I's old copy is gone; `moves_carried`
   equals the count F gives over the framed clips alone, and the y-moving
   title's F differs between its action's ends.
4. Every "Blurred Background" in the copy is on the copy's "Backgrounds"
   track, at index 0, and there are two (B's and F's).
5. The copy's track count is the source's plus at most one.
6. One `undo` in the copy answers "Make Vertical" and gives back the source's
   `get_project` project.
7. The 9:16 copy's `render_frame` corners are never magenta at 40 frames
   across the plate's span and A, B, C, E, F and I.
8. `copy: false` on a scratch copy applies in place: one step "Make Vertical",
   the canvas 1080 × 1920, no window opened; `undo` gives the project back.
9. The copy's `cache/analysis/` holds every file of the source's byte for
   byte; a second run from the source answers `cached` true and the lane's
   queued count is unchanged.
10. A source at 64 tracks answers "Make Vertical was refused at add_track: "
    and the core's sentence, and opens nothing.
12. (VR3b, before the source closes) With `set_scope` into the nest H, File ▸
    Make Vertical Version… (`perform_menu_item`) is refused as disabled and no
    sheet comes up. Out of the nest, the menu (the dev accept presses Make)
    opens exactly one new window within 30 s: its `get_project` is named
    "src (9:16)" with unsaved changes, and its `clips`, `tracks` and `canvas`
    equal row 1's 9:16 tool copy; `undo` in it answers "Make Vertical" and
    gives back the source's project; the source's `project.json`, saved again,
    is byte-identical and its undo top unchanged.

**Launch 2** (`-RCDevAnalysisHold 30 -RCDevVerticalAccept in-place
-FrameJobFollowKind subject -FrameJobFollowWhereEmpty fit`, uncached
projects), rows 11 and 13:
11. `{shape: "9:16", zoom: 5}` answers the core's "zoom must be between 1 and
    4 times fill, not 5" within 5 s with the lane's queued count unchanged; then
    `{shape: "9:16"}` passes the 60 s bound and answers `analyzing` with no
    window opened.
13. (VR3b) A fresh saved project with one 3 s movie clip of its own media copy:
    the menu (the dev accept unticks Make a copy and presses Make) puts up the
    Analyzing sheet within 60 s; `cancel_sheet` (Stop) leaves the window count,
    `get_project` and the undo top unchanged for 5 s; the menu again: the
    Analyzing sheet closes within 300 s, then within 30 s the canvas is
    1080 × 1920 with no window opened, and `undo` answers "Make Vertical" and
    gives the project back.

Z1 is each launch's parity grep.

Every copy is closed with `discard: true`. The mutants (tools/proof/README.md's
VR3a and VR3b sections) are edited into the tree by hand, a Debug app built, the row run
and the file restored.
"""

import argparse
import json
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
from e1_proof import decode_png  # noqa: E402

WORK = ROOT / "tools/proof/work/vr3-proof"
HOME = WORK / "home"
CALL_BOUND = 400
SEC = 600_000
FRAME = 20_000
MAGENTA = (255, 0, 255)
BLURRED = "Blurred Background"
MENU = ["File", "Make Vertical Version…"]
STEP = "Make Vertical"
PINS = ["-FrameJobFollowKind", "subject", "-FrameJobFollowWhereEmpty", "fit"]
ROWS = [str(n) for n in range(1, 14)] + ["Z1"]
LAUNCH_1 = [str(n) for n in range(1, 11)] + ["12"]
LAUNCH_2 = ["11", "13"]

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, name):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        check(name, False, f"{type(error).__name__}: {error}")
        return None


def attempt_rows(body, rows):
    """`attempt` for a body several rows share: a throw fails every row that has
    not answered yet."""
    try:
        return body()
    except Exception as error:  # noqa: BLE001
        for row in rows:
            if row not in results:
                check(row, False, f"{type(error).__name__}: {error}")
        return None


# ---- media ----------------------------------------------------------------------

def make_media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    movie, still = folder / "testsrc.mov", folder / "pip.png"
    for out, args in (
        (movie, ["-f", "lavfi", "-i", "testsrc=size=1920x1080:rate=30", "-t", "50",
                 "-c:v", "libx264", "-pix_fmt", "yuv420p"]),
        (still, ["-f", "lavfi", "-i", "testsrc=size=480x270:rate=1", "-frames:v", "1"]),
    ):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args, str(out)], check=True,
                       timeout=600)
    return movie, still


# ---- placement and F --------------------------------------------------------------

def ease(curve, u):
    u = min(1.0, max(0.0, u))
    return {"linear": u, "ease_in": u * u, "ease_out": 1 - (1 - u) * (1 - u),
            "ease_in_out": u * u * (3 - 2 * u)}[curve]


def placement(clip, t):
    """(scale, x, y) at clip tick `t`: the base, each action eased from the
    value before it (`actions.rs`)."""
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


def framing(before, after, t):
    s, x, y = placement(before, t)
    s2, x2, y2 = placement(after, t)
    k = s2 / s
    return k, x2 - k * x, y2 - k * y


def carries(before, after):
    """The actions in both with the same id and span across which F differs by
    more than 1e-6 between the two ends (VR-27 (f) under compose)."""
    was = {a["id"]: a for a in before.get("actions", [])}
    count = 0
    for action in after.get("actions", []):
        old = was.get(action["id"])
        if not old or old["start"] != action["start"] or old["duration"] != action["duration"]:
            continue
        a = framing(before, after, action["start"])
        b = framing(before, after, action["start"] + action["duration"])
        count += any(abs(p - q) > 1e-6 for p, q in zip(a, b))
    return count


# ---- the documents --------------------------------------------------------------

class Doc:
    def __init__(self, client, path, create=True):
        self.client = client
        self.path = Path(path)
        if create:
            if self.path.exists():
                shutil.rmtree(self.path)
            client.call("new_project", path=str(self.path))
            self.call("set_canvas", width=1920, height=1080, fps=[30, 1],
                      background=[1, 0, 1, 1])
            self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.state()["clips"] if c["id"] == clip)

    def track(self, index=0):
        return self.state()["tracks"][index]["id"]

    def media(self, movie, name, scenario=None):
        copy = WORK / "media" / f"{self.path.stem}-{name}{movie.suffix}"
        if not copy.exists():
            shutil.copyfile(movie, copy)
        media = self.call("import_media", path=str(copy))["media"]
        row = next(m for m in self.state()["media"] if m["id"] == media)
        fps = row["fps"] if isinstance(row["fps"], list) else [row["fps"]["num"],
                                                               row["fps"]["den"]]
        if scenario is not None:
            canned_framing.write(self.path, media, copy, row["duration"], fps, scenario)
        return media, copy

    def clip_of(self, media, at, seconds, track=None):
        track = track if track is not None else self.track()
        clip = self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]
        self.call("trim_end", clip=clip, to=at + seconds * SEC)
        return clip

    def action(self, clip, at, duration, patch):
        action = self.call("add_action", clip=clip, at=at, duration=duration)["new_actions"][0]
        self.call("set_action_end", clip=clip, action=action, patch=patch)
        return action

    def undo_top(self):
        """The undo step's name, or None with nothing to undo."""
        try:
            name = self.call("undo").get("undone")
        except mcp.ToolError:
            return None
        self.call("redo")
        return name

    def vertical(self, **arguments):
        return self.call("make_vertical_version", **arguments)

    def corners(self, t, project=None):
        out = WORK / "frames" / f"{(project or self.path).stem}-{t}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        self.client.call_with("render_frame", {"project": str(project or self.path),
                                               "t": int(t), "path": str(out),
                                               "max_width": 270})
        width, height, depth, channels, rows = decode_png(str(out))
        step = 2 if depth == 16 else 1

        def pixel(x, y):
            row = rows[y]
            at = x * channels * step
            return tuple(row[at + c * step] for c in range(3))
        return [pixel(x, y) for x, y in ((1, 1), (width - 2, 1), (1, height - 2),
                                         (width - 2, height - 2))]

    def close(self):
        close(self.client, self.path)


def close(client, path):
    try:
        client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass


def magenta(pixel):
    return all(abs(a - b) <= 8 for a, b in zip(pixel, MAGENTA))


def windows(client):
    return len(client.call("snapshot_ui").get("windows") or [])


def editors(client):
    """The editor windows open: a sheet, such as a copy's missing-media sheet, is not one."""
    return len([w for w in client.call("snapshot_ui").get("windows") or []
                if w.get("kind") == "editor"])


def sheet_up(doc):
    return ((doc.call("perform_menu_item").get("window") or {}).get("sheet")) is not None


def sheet_views(doc, tag):
    """The attached sheet's layout dump's views, or None with no sheet."""
    (WORK / "sheets").mkdir(parents=True, exist_ok=True)
    try:
        got = doc.call("snapshot_ui", window="sheet", path=str(WORK / "sheets" / f"{tag}.png"))
    except mcp.ToolError:
        return None
    path = got.get("layout_path") if isinstance(got, dict) else None
    if not path:
        return None
    return json.loads(Path(path).read_text()).get("views") or []


def wait_analyzing(doc, tag, bound=60):
    """Whether the attached sheet shows "Analyzing" within `bound` s, and when."""
    began = time.monotonic()
    while time.monotonic() - began < bound:
        views = sheet_views(doc, tag)
        if any(v.get("text") == "Analyzing" and not v.get("hidden") for v in views or []):
            return True, time.monotonic() - began
        time.sleep(0.2)
    return False, time.monotonic() - began


def wait_no_sheet(doc, bound):
    began = time.monotonic()
    while time.monotonic() - began < bound:
        if not sheet_up(doc):
            return True
        time.sleep(0.2)
    return False


def lane_queued(doc):
    return doc.call("analysis_job")["lane_queued"]


def project_of(client, path):
    return client.call_with("get_project", {"project": str(path)})["project"]


def settle(doc, bound=180):
    """Waits until the package's `cache/` listing (path and size) holds still for 3 s, so no
    cache pass is writing while a copy lists it (`DerivedCarry` copies what it listed)."""
    began, last, still = time.monotonic(), None, 0
    while time.monotonic() - began < bound:
        folder = doc.path / "cache"
        try:
            now = sorted((str(p), p.stat().st_size) for p in folder.rglob("*")
                         if p.is_file()) if folder.exists() else []
        except OSError:
            now = None  # a file went while it was listed: still moving
        still = still + 1 if now is not None and now == last else 0
        if still >= 3:
            return
        last = now
        time.sleep(1)
    raise RuntimeError(f"{doc.path.name}: the cache never settled in {bound} s")


def listing(folder):
    """Every file under `folder`: relative path → bytes."""
    folder = Path(folder)
    return {str(p.relative_to(folder)): p.read_bytes()
            for p in sorted(folder.rglob("*")) if p.is_file()} if folder.exists() else {}


# ---- the fixture ------------------------------------------------------------------

def build_fixture(client, movie, still):
    doc = Doc(client, WORK / "src.framejob")
    ids = {}
    face, _ = doc.media(movie, "face", canned_framing.still)
    screen, _ = doc.media(movie, "screen", lambda t: [])
    exit_, _ = doc.media(movie, "exit", canned_framing.exit_and_back)
    offline, offline_file = doc.media(movie, "offline", canned_framing.still)
    pip = doc.call("import_media", path=str(still))["media"]
    ids["A"] = doc.clip_of(face, 2 * SEC, 4)
    ids["B"] = doc.clip_of(screen, 6 * SEC, 4)
    ids["C"] = doc.clip_of(face, 10 * SEC, 4)
    doc.action(ids["C"], SEC, 2 * SEC, {"video": {"scale": 1.5}, "audio": {"volume": 0.5}})
    ids["D"] = doc.clip_of(face, 14 * SEC, 4)
    doc.call("set_video", clips=[ids["D"]],
             patch={"motion": {"during": {"kind": "drift", "amount": 0.5, "period": SEC}}})
    ids["E"] = doc.clip_of(face, 18 * SEC, 4)
    doc.call("set_video", clips=[ids["E"]], patch={"scale": 1.25})
    ids["F"] = doc.clip_of(exit_, 22 * SEC, 10)
    ids["G"] = doc.clip_of(offline, 32 * SEC, 4)
    inner = doc.clip_of(face, 36 * SEC, 4)
    doc.call("nest", clips=[inner])
    ids["H"] = next(c["id"] for c in doc.state()["clips"]
                    if c["source"]["kind"] == "nest")
    ids["I"] = doc.clip_of(face, 40 * SEC, 4)
    before = {c["id"] for c in doc.state()["clips"]}
    doc.call("add_blurred_background", clip=ids["I"])
    ids["Ibd"] = next(c["id"] for c in doc.state()["clips"] if c["id"] not in before)
    before = {c["id"] for c in doc.state()["clips"]}
    doc.call("add_background", color=[1, 1, 1, 1], duration=2 * SEC)
    ids["plate"] = next(c["id"] for c in doc.state()["clips"] if c["id"] not in before)
    front = doc.call("add_track")["new_tracks"][0]
    ids["title"] = doc.call("add_text_clip", track=front, at=2 * SEC, duration=4 * SEC,
                            text="A title")["new_clips"][0]
    ids["pip"] = doc.clip_of(pip, 6 * SEC, 4, track=front)
    doc.call("set_video", clips=[ids["pip"]], patch={"scale": 0.25, "x": 600, "y": 300})
    ids["ytitle"] = doc.call("add_text_clip", track=front, at=10 * SEC, duration=4 * SEC,
                             text="Rising")["new_clips"][0]
    doc.call("set_video", clips=[ids["ytitle"]], patch={"y": 200})
    doc.action(ids["ytitle"], SEC, 2 * SEC, {"video": {"y": 0}})
    target = doc.call("add_track")["new_tracks"][0]
    ids["J"] = doc.clip_of(face, 44 * SEC, 4, track=target)
    matte = doc.call("add_track")["new_tracks"][0]
    doc.call("set_track", track=matte, matte="alpha")
    ids["K"] = doc.call("add_text_clip", track=matte, at=44 * SEC, duration=4 * SEC,
                        text="Matte")["new_clips"][0]
    doc.call("save_project")
    settle(doc)
    doc.close()
    offline_file.unlink()
    client.call("open_project", path=str(doc.path))
    reopened = Doc(client, doc.path, create=False)
    settle(reopened)
    return reopened, ids


EXPECTED = {
    "A": ("followed", None), "B": ("whole", None), "C": ("followed", None),
    "D": ("followed", "moves by its own motion: Drift"),
    "E": ("followed", None),
    "F": ("followed", "it is shown whole on a blurred copy where no subject is found"),
    "G": ("not_followed", "its media file is missing, so it is kept as placed"),
    "H": ("not_followed", "it is a nest, so it is centred"),
    "I": ("followed", None), "Ibd": ("removed", None),
    "J": ("not_followed", "cut by the matte"),
    "K": ("kept", None), "title": ("kept", None), "pip": ("kept", None),
    "ytitle": ("kept", None), "plate": ("refilled", None),
}


# ---- launch 1 -------------------------------------------------------------------

def launch_one(client):
    movie, still = make_media()
    doc, ids = build_fixture(client, movie, still)
    source = doc.state()
    undo_before = doc.undo_top()
    saved = doc.path / "project.json"
    bytes_before = saved.read_bytes()
    tracks_before = len(source["tracks"])
    queued = lane_queued(doc)

    def row2():
        doc.call("save_project")
        same = saved.read_bytes() == bytes_before
        undo_after = doc.undo_top()
        check("2", same and undo_after == undo_before,
              f"project.json byte-identical {same}; undo top {undo_before!r} → {undo_after!r}")

    tall_path = WORK / "tall.framejob"
    portrait_path = WORK / "portrait.framejob"
    try:
        tall = doc.vertical(shape="9:16", path=str(tall_path))
        portrait = doc.vertical(shape="4:5", path=str(portrait_path))
        square = doc.vertical(shape="1:1")
    except mcp.ToolError as error:
        # Every row reads the copies but row 2, which still says what the call did to the
        # source.
        for row in LAUNCH_1:
            if row != "2":
                check(row, False, f"the copies were not made: {error}")
        if "2" in selected:
            attempt(row2, "2")
        doc.close()
        return
    front = client.call("get_project")  # the untitled copy, the front window
    square_name = front.get("name")
    square_unsaved = front.get("unsaved_changes")
    try:
        client.call("close_project", discard=True)
    except mcp.ToolError:
        pass

    tall_state = project_of(client, tall_path)
    by_id = {c["id"]: c for c in tall_state["clips"]}
    source_by_id = {c["id"]: c for c in source["clips"]}

    def row1():
        sizes = [(a.get("canvas") or {}).get("width") for a in (tall, portrait, square)], \
            [(a.get("canvas") or {}).get("height") for a in (tall, portrait, square)]
        canvases = list(zip(*sizes)) == [(1080, 1920), (1080, 1350), (1080, 1080)]
        bad = []
        for n in range(10):
            t = 2 * SEC + FRAME + n * (4 * SEC - 2 * FRAME) // 10
            corners = doc.corners(t, project=portrait_path)
            if any(magenta(c) for c in corners):
                bad.append(t)
        scratch_path = WORK / "scratch-keep.framejob"
        if scratch_path.exists():
            shutil.rmtree(scratch_path)
        shutil.copytree(doc.path, scratch_path)
        client.call("open_project", path=str(scratch_path))
        scratch = Doc(client, scratch_path, create=False)
        scratch.call("set_canvas", width=1080, height=1920, rescale_clips=False)
        scratch.call("reframe_clip", clip=ids["pip"], follow="keep", from_width=1920,
                     from_height=1080)
        kept = scratch.clip(ids["pip"])
        scratch.close()
        copy_pip = by_id.get(ids["pip"]) or {}
        same = kept.get("video") == copy_pip.get("video") and kept.get(
            "actions") == copy_pip.get("actions")
        named = square_name == "src (1:1)" and square_unsaved is True
        check("1", canvases and not bad and same and named,
              f"canvases {list(zip(*sizes))}; 4:5 A magenta at {bad or 'no frame'} of 10; the "
              f"picture-in-picture as keep {same} (copy {copy_pip.get('video', {}).get('x')}, "
              f"{copy_pip.get('video', {}).get('y')}, {copy_pip.get('video', {}).get('scale')}; "
              f"scratch {kept.get('video', {}).get('x')}, {kept.get('video', {}).get('y')}, "
              f"{kept.get('video', {}).get('scale')}); the untitled copy {square_name!r} "
              f"unsaved {square_unsaved}")
    if "1" in selected:
        attempt(row1, "1")

    if "2" in selected:
        attempt(row2, "2")

    def row3():
        treatments = {row["clip"]: (row["treatment"], row.get("reason"))
                      for row in tall.get("clips", [])}
        wrong = []
        for name, (treatment, reason) in EXPECTED.items():
            got = treatments.get(ids[name])
            if (got is None or got[0] != treatment
                    or (reason is None and got[1] is not None)
                    or (reason is not None and (got[1] is None or reason not in got[1]))):
                wrong.append(f"{name} {got}")
        extra = sorted(set(treatments) - {ids[name] for name in EXPECTED})
        if extra:
            wrong.append(f"unlisted clips {extra}")
        plate = by_id.get(ids["plate"]) or {}
        shape, video = plate.get("shape") or {}, plate.get("video") or {}
        plate_ok = (shape.get("width") == 1080 and shape.get("height") == 1920
                    and video.get("scale", 1) == 1 and not video.get("x") and not video.get("y"))
        gone = ids["Ibd"] not in by_id
        framed = [ids[n] for n in "ABCDEFI"] + [ids["H"]]
        expected = sum(carries(source_by_id[c], by_id[c]) for c in framed if c in by_id)
        title_moves = carries(source_by_id[ids["ytitle"]], by_id.get(ids["ytitle"], {})) > 0
        carried = tall.get("moves_carried")
        check("3", not wrong and plate_ok and gone and carried == expected and title_moves,
              f"unexpected {wrong or 'none'}; plate {shape.get('width')} × "
              f"{shape.get('height')} at scale {video.get('scale', 1)}; I's old copy gone "
              f"{gone}; moves_carried {carried} (F over the framed clips {expected}); the "
              f"y-moving title's F moves {title_moves}; summary {tall.get('summary')!r}")
    if "3" in selected:
        attempt(row3, "3")

    def row4():
        background = tall_state["tracks"][0]
        copies = [c for c in tall_state["clips"] if c.get("name") == BLURRED]
        on = {c["track"] for c in copies}
        check("4", background.get("name") == "Backgrounds" and on == {background["id"]}
              and len(copies) == 2,
              f"track 0 {background.get('name')!r}; {len(copies)} blurred copies on tracks "
              f"{sorted(on)}")
    if "4" in selected:
        attempt(row4, "4")

    def row5():
        after = len(tall_state["tracks"])
        check("5", tracks_before <= after <= tracks_before + 1,
              f"{tracks_before} tracks in the source, {after} in the copy")
    if "5" in selected:
        attempt(row5, "5")

    def row6():
        undone = client.call_with("undo", {"project": str(tall_path)}).get("undone")
        back = project_of(client, tall_path)
        same = back == doc.state()
        client.call_with("redo", {"project": str(tall_path)})
        check("6", undone == "Make Vertical" and same,
              f"undo answered {undone!r}; the copy then equals the source {same}")
    if "6" in selected:
        attempt(row6, "6")

    def row7():
        times = [SEC // 2, 3 * SEC // 2]
        spans = [(2, 6), (6, 10), (10, 14), (18, 22), (22, 32), (40, 44)]
        per = 38 // len(spans) + 1
        for lo, hi in spans:
            for n in range(per):
                times.append(lo * SEC + FRAME + n * ((hi - lo) * SEC - 2 * FRAME) // per)
        times = times[:40]
        bad = []
        for t in times:
            corners = doc.corners(t, project=tall_path)
            if any(magenta(c) for c in corners):
                bad.append(t)
        check("7", not bad, f"{len(times)} frames, magenta corners at {bad[:5] or 'none'}")
    if "7" in selected:
        attempt(row7, "7")

    def row9():
        source_files = listing(doc.path / "cache/analysis")
        copy_files = listing(tall_path / "cache/analysis")
        missing = [p for p, data in source_files.items() if copy_files.get(p) != data]
        queued_before = lane_queued(doc)
        again_path = WORK / "again.framejob"
        again = doc.vertical(shape="9:16", path=str(again_path))
        close(client, again_path)
        unqueued = lane_queued(doc) == queued_before == queued
        check("9", source_files and not missing and again.get("cached") is True
              and tall.get("cached") is True and unqueued,
              f"{len(source_files)} analysis files, {len(missing)} not byte-identical in the "
              f"copy ({missing[:3]}); the second run cached {again.get('cached')}; lane queued "
              f"unchanged {unqueued}")
    if "9" in selected:
        attempt(row9, "9")

    def row8():
        scratch_path = WORK / "scratch-inplace.framejob"
        if scratch_path.exists():
            shutil.rmtree(scratch_path)
        shutil.copytree(doc.path, scratch_path)
        client.call("open_project", path=str(scratch_path))
        scratch = Doc(client, scratch_path, create=False)
        before = scratch.state()
        count = windows(client)
        answer = scratch.vertical(shape="9:16", copy=False)
        after = scratch.state()
        opened = windows(client) - count
        undone = scratch.call("undo").get("undone")
        back = scratch.state()
        scratch.close()
        canvas = after.get("canvas") or {}
        check("8", answer.get("ok") and undone == "Make Vertical" and back == before
              and canvas.get("width") == 1080 and canvas.get("height") == 1920
              and opened == 0 and "carried" not in answer,
              f"canvas {canvas.get('width')} × {canvas.get('height')}; undo {undone!r}, back "
              f"to the project {back == before}; {opened} windows opened")
    if "8" in selected:
        attempt(row8, "8")

    def row10():
        many = Doc(client, WORK / "many.framejob")
        media, _ = many.media(movie, "many", canned_framing.still)
        many.clip_of(media, 0, 4)
        while len(many.state()["tracks"]) < 64:
            many.call("add_track")
        count = windows(client)
        try:
            many.vertical(shape="9:16")
            good, why = False, "applied"
        except mcp.ToolError as error:
            why = str(error)
            good = ("Make Vertical was refused at add_track: " in why
                    and "too many tracks" in why)
        opened = windows(client) - count
        many.close()
        check("10", good and opened == 0, f"{why[:160]!r}; {opened} windows opened")
    if "10" in selected:
        attempt(row10, "10")

    if "12" in selected:
        attempt(lambda: menu_row(client, doc, tall_state, bytes_before, undo_before), "12")

    for path in (tall_path, portrait_path):
        close(client, path)
    doc.close()


def menu_row(client, doc, tall_state, bytes_before, undo_before):
    """Row 12: the menu refused inside a nest, then the menu's copy equal to the tool's. The
    source was opened with its offline media's file gone, so its missing-media sheet is put
    away first: a sheet on the window would disable the item for its own reason."""
    if sheet_up(doc):
        doc.call("cancel_sheet")
    nest = doc.state()["nests"][0]["id"]
    doc.call("set_scope", nest=nest)
    try:
        doc.call("perform_menu_item", path=MENU)
        refused, why = False, "performed"
    except mcp.ToolError as error:
        why = str(error)
        refused = "is disabled here" in why
    nested_sheet = sheet_up(doc)
    if nested_sheet:
        try:
            doc.call("cancel_sheet")
        except mcp.ToolError:
            pass
    doc.call("set_scope")
    count = editors(client)
    doc.call("perform_menu_item", path=MENU)
    began, opened = time.monotonic(), 0
    while time.monotonic() - began < 30:
        opened = editors(client) - count
        if opened >= 1:
            time.sleep(1)
            opened = editors(client) - count
            break
        time.sleep(0.25)
    if opened < 1:
        check("12", False, f"in the nest refused {refused} ({why[:120]!r}), a sheet "
              f"{nested_sheet}; no window opened within 30 s")
        return
    front = client.call("get_project")  # the untitled copy, the front window
    made = front.get("project") or {}
    same = {k: made.get(k) == tall_state.get(k) for k in ("clips", "tracks", "canvas")}
    named = front.get("name") == "src (9:16)" and front.get("unsaved_changes") is True
    undone = client.call("undo").get("undone")
    back = client.call("get_project").get("project") == doc.state()
    try:
        client.call("close_project", discard=True)
    except mcp.ToolError:
        pass
    doc.call("save_project")
    source_same = (doc.path / "project.json").read_bytes() == bytes_before
    undo_after = doc.undo_top()
    check("12", refused and not nested_sheet and opened == 1 and all(same.values()) and named
          and undone == STEP and back and source_same and undo_after == undo_before,
          f"in the nest refused {refused} ({why[:120]!r}), a sheet {nested_sheet}; {opened} "
          f"window(s) opened; the copy {front.get('name')!r} unsaved "
          f"{front.get('unsaved_changes')}; equal to the tool's 9:16 copy {same}; undo "
          f"{undone!r}, back to the source {back}; the source's project.json byte-identical "
          f"{source_same}, undo top {undo_before!r} → {undo_after!r}")


# ---- launch 2 -------------------------------------------------------------------

def held_row(client):
    movie, _ = make_media()
    doc = Doc(client, WORK / "held.framejob")
    media, _ = doc.media(movie, "held")
    doc.clip_of(media, 0, 3)
    doc.call("save_project")
    queued = lane_queued(doc)
    count = windows(client)
    began = time.monotonic()
    try:
        doc.vertical(shape="9:16", zoom=5)
        quick_ok, why = False, "applied"
    except mcp.ToolError as error:
        why = str(error)
        quick_ok = "zoom must be between 1 and 4 times fill, not 5" in why
    quick = time.monotonic() - began
    unqueued = lane_queued(doc) == queued
    began = time.monotonic()
    answer = doc.vertical(shape="9:16")
    waited = time.monotonic() - began
    opened = windows(client) - count
    check("11", quick_ok and quick <= 5 and unqueued and answer.get("analyzing") is not None
          and opened == 0,
          f"zoom 5: {why[:100]!r} in {quick:.2f} s, lane queue unchanged {unqueued}; then "
          f"after {waited:.1f} s analyzing {answer.get('analyzing')}, note "
          f"{answer.get('note')!r}; {opened} windows opened")
    doc.close()


def stop_row(client):
    """Row 13: the Analyzing sheet's Stop makes nothing; the menu again applies in place."""
    movie, _ = make_media()
    doc = Doc(client, WORK / "menu.framejob")
    media, _ = doc.media(movie, "menu")
    doc.clip_of(media, 0, 3)
    doc.call("save_project")
    before = doc.state()
    undo_before = doc.undo_top()
    count = windows(client)
    doc.call("perform_menu_item", path=MENU)
    seen, took = wait_analyzing(doc, "stop-1")
    if not seen:
        check("13", False, f"the Analyzing sheet not seen within {took:.0f} s")
        doc.close()
        return
    doc.call("cancel_sheet")
    stayed = True
    for _ in range(5):
        time.sleep(1)
        stayed = stayed and doc.state() == before and windows(client) == count
    stayed = stayed and doc.undo_top() == undo_before and not sheet_up(doc)
    doc.call("perform_menu_item", path=MENU)
    again, took_again = wait_analyzing(doc, "stop-2")
    closed = again and wait_no_sheet(doc, 300)
    canvas = {}
    began = time.monotonic()
    while closed and time.monotonic() - began < 30:
        canvas = doc.state().get("canvas") or {}
        if (canvas.get("width"), canvas.get("height")) == (1080, 1920):
            break
        time.sleep(0.25)
    made = (canvas.get("width"), canvas.get("height")) == (1080, 1920)
    opened = windows(client) - count
    undone = doc.call("undo").get("undone") if made else None
    back = doc.state() == before if made else False
    check("13", stayed and again and closed and made and opened == 0 and undone == STEP
          and back,
          f"Analyzing seen after {took:.1f} s; after Stop unchanged for 5 s {stayed}; again "
          f"Analyzing {again} after {took_again:.1f} s, closed {closed}; canvas "
          f"{canvas.get('width')} × {canvas.get('height')}; {opened} windows opened; undo "
          f"{undone!r}, the project given back {back}")
    doc.close()


def launch_two(client):
    if "11" in selected:
        attempt(lambda: held_row(client), "11")
    if "13" in selected:
        attempt(lambda: stop_row(client), "13")


# ---- launches -------------------------------------------------------------------

def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def run_launch(binary, arguments, label, rows, body):
    log = WORK / f"instance-{label}.log"
    launched = mcp.launch(str(binary), list(arguments),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in rows:
                check(row, False, "the app did not listen")
        else:
            print(f"  {label} instance PID {launched.child.pid}", flush=True)
            body(launched.client)
    finally:
        launched.stop()
    parity(log)


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
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
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"VR3a and VR3b — Make Vertical's step, copy, make_vertical_version and menu "
          f"({proof_app.config()} build)", flush=True)
    if selected & set(LAUNCH_1):
        run_launch(binary, ["-RCDevAnalysisCanned", "YES", "-RCDevVerticalAccept", "YES",
                            *PINS], "canned", LAUNCH_1,
                   lambda client: attempt_rows(lambda: launch_one(client), LAUNCH_1))
    if selected & set(LAUNCH_2):
        run_launch(binary, ["-RCDevAnalysisHold", "30", "-RCDevVerticalAccept", "in-place",
                            *PINS], "held", LAUNCH_2, launch_two)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
