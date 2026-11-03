#!/usr/bin/env python3
"""Road map "creator-jobs" CO6 — Clip ▸ Camera Layout ▸ and `switch_layout`
(spec §11 CO-60…CO-67).

    python3 tools/proof/co6_proof.py [SOCKET] [--only L1,L6,…] [--mutant NAME] [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the
rows launch their own instance on a scratch `CFFIXED_USER_HOME`. Packages and media are made
under `tools/proof/work/co6/`: ffmpeg's `testsrc`, 20 s at 30 fps, as a 1280 × 720 camera, a
1920 × 1080 screen and a 2560 × 1440 screen. A frame is 20 000 ticks. Every expected
placement is worked here from CO-60's figures (the picture's box on the canvas, then the
offset of its centre), never read back from `layout.rs`.

Rows:
- Z1 `grep "Frame Job: "` of every instance's log prints nothing.
- L1 on 1920 × 1080 and 1080 × 1920, each of the five layouts at 2 s lands one layout action
  on the camera and one on the screen, each end exactly the six keys at CO-60's numbers.
- L2 a switch at the camera's first frame writes the layout as its base and a one-frame
  layout action at 0 whose end equals it.
- L3 the camera cut four times (five clips); a corner switch at the fifth's first frame, then
  side by side on the second at 5 s: the third and fourth take side by side as their base,
  the fifth keeps its corner base and marker.
- L4 two switches on one clip, corner at 2 s and stacked at 6 s: two layout actions, the
  second's end stacked and nothing after it.
- L5 the camera cut at 10 s, a corner switch at 13 s (mid-clip on the second); then side by
  side at 2 s: the second clip's base is side by side and its own action is kept.
- L6 the screen cut at 10 s, the later piece zooming at its 2 s: side by side at 2 s refused
  naming the clip and the zoom; with `nest: true` applied, the zoom inside the nest, and
  `render_frame` at 12.5 s byte-identical to `nest` then `switch_layout` on a twin.
- L7 the camera inside an opacity action at 2 s: refused naming it ("moves (action N)").
- L8 the camera cut at 10 s; corner at 2 s `through` 8 s: the second clip byte-unchanged.
- L9 one undo, named "Camera Layout", gives back `get_project`'s project exactly.
- L10 circle's crop is the 720 square with radius 360; rounded's radius is 8 % of the box's
  shorter side over the scale; a nest-clip camera refuses both.
- L11 (`co6_probe.swift`) `ActionBands.isZoom` is false on every L1 action and each end names
  exactly the six keys.
- L12 `perform_menu_item` Clip ▸ Camera Layout ▸ Circle ▸ Top Left with the camera selected,
  Side by Side with both selected, and Side by Side with none selected (a "Camera" track):
  each equal in `get_project` to `switch_layout` at the playhead after one undo named
  "Camera Layout".
- L13 the 2560 × 1440 screen at its full placement (0.75) with zooms at 8 s and 12 s: Clip ▸
  Camera Layout ▸ Circle ▸ Bottom Right at 3 s applies and both zooms are unchanged; side by
  side at 5 s is refused naming the first zoom, and with `nest: true` the screen is nested.

`--mutant NAME`: a core mutant edits a copy of `core/` (beside a link to `graphic/`) and runs
`cargo test --release --test layout`: CAUGHT when a test fails. `roles-swapped` edits a
`tree_copy.py` copy's `CameraLayout.swift` and runs L12 on its built app. CAUGHT exits 1,
SURVIVED exits 0, a control that could not be performed exits 2.
"""

import argparse
import json
import math
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

WORK = ROOT / "tools/proof/work/co6"
HOME = WORK / "home"
KEEP = {"media", "mutant-target"}
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 600
BUILD_BOUND = 1500
PROBE_WALL = 240
CAMERA = (1280, 720)
SCREEN = (1920, 1080)
WIDE = (2560, 1440)
SIX = {"x", "y", "scale", "crop", "corner_radius", "opacity"}
LAYOUTS = ["corner", "side_by_side", "stacked", "camera_full", "screen_only"]
PLAIN = ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10", "L12", "L13"]
PROBE = ["L11"]
ROWS = ["Z1"] + PLAIN + PROBE

REACH = "core/src/edit_layout_reach.rs"
GEOMETRY = "core/src/layout.rs"
SWITCH = "core/src/edit_layout.rs"
ROLES = "app/Sources/CameraLayout.swift"
# name → (rows or core test prefixes, [(path, anchor, replacement)], "core" or "app")
MUTANTS = {
    "exemption-dropped": (["a_full_placement_screen"], [(
        REACH, "            if exempt(clip, placed) {",
        "            if false && exempt(clip, placed) {")], "core"),
    "reach-stops-at-zoom": (["a_later_zoom_refuses"], [(
        REACH,
        "            for action in owner.actions.iter().filter(|a| is_layout(a)) {\n"
        "                let starts = owner.start.saturating_add(action.start);",
        "            for action in owner.actions.iter().filter(|a| is_layout(a) || moves(a)) {\n"
        "                let starts = if is_layout(action) { owner.start.saturating_add("
        "action.start) } else { owner.start };")], "core"),
    "reach-past-layout": (["the_reach_carries"], [(
        REACH, "                if starts > at && starts < end {",
        "                if false && starts > at && starts < end {")], "core"),
    "reach-first-clip-only": (["the_reach_carries"], [(
        REACH, "        later.sort_by_key(|c| (c.start, c.id));",
        "        later.sort_by_key(|c| (c.start, c.id));\n        later.truncate(1);")], "core"),
    "end-missing-key": (["every_layout_lands"], [(
        GEOMETRY, '            "corner_radius": self.corner_radius,\n', "")], "core"),
    "first-frame-marker-dropped": (["a_first_frame_switch"], [(
        SWITCH,
        "                step!(next, next.add_action(id, 0, Some(frame)));\n"
        "                step!(next, next.set_action_end(id, action, &patch, &[], None));\n",
        "                let _ = (action, &patch);\n")], "core"),
    "through-ignored": (["through_ends_the_reach"], [(
        REACH, "        if let Some(through) = through {",
        "        if let Some(through) = through.filter(|_| false) {")], "core"),
    "circle-radius-uncropped": (["circle_crops"], [(
        GEOMETRY, "                corner_radius: side / 2.0,",
        "                corner_radius: a.max(b) / 2.0,")], "core"),
    "roles-swapped": (["L12"], [(
        ROLES, "a > b ? (selected[0], selected[1])", "a < b ? (selected[0], selected[1])")],
        "app"),
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


def t(seconds):
    """Seconds to ticks."""
    return int(round(seconds * SEC))


# ---- the oracle: CO-60 as boxes on the canvas ------------------------------------

def rounded(value):
    """Half away from zero, as the core and CAM-10 round."""
    return math.copysign(math.floor(abs(value) + 0.5), value)


def placement(x, y, scale, crop=(0.0, 0.0, 0.0, 0.0), radius=0.0, opacity=1.0):
    return {"x": x, "y": y, "scale": scale,
            "crop": dict(zip(("l", "t", "r", "b"), crop)), "corner_radius": radius,
            "opacity": opacity}


def at_rect(canvas, left, top, w, h, scale, radius):
    return placement(rounded(left + w / 2 - canvas[0] / 2), rounded(top + h / 2 - canvas[1] / 2),
                     scale, radius=radius)


def filling(canvas, src, rect, radius, focus=(0.0, 0.0)):
    left, top, bw, bh = rect
    scale = max(bw / src[0], bh / src[1])
    cw, ch = min(bw / scale, src[0]), min(bh / scale, src[1])

    def side(whole, part, f):
        room = (whole - part) / 2
        f = min(max(f, -room), room)
        return room + f, room - f
    l, r = side(src[0], cw, focus[0])
    tt, b = side(src[1], ch, focus[1])
    x = left + bw / 2 - canvas[0] / 2 - scale * (l - r) / 2
    y = top + bh / 2 - canvas[1] / 2 - scale * (tt - b) / 2
    return placement(rounded(x), rounded(y), scale, (l, tt, r, b), radius / scale)


def full(canvas, src):
    big = src[0] > canvas[0] or src[1] > canvas[1]
    return placement(0.0, 0.0, min(canvas[0] / src[0], canvas[1] / src[1]) if big else 1.0)


def oracle(layout, canvas, cam, scr, kept=None, shape="square", corner="bottom_right"):
    """(camera, screen) end placements for `layout`."""
    w, h = canvas
    m = 0.04 * min(w, h)
    panel = 0.02 * min(w, h)
    if layout == "corner":
        bw, bh = w / 4, h / 3
        right, bottom = corner.endswith("right"), corner.startswith("bottom")
        if shape == "circle":
            side = min(cam)
            scale = min(bw, bh) / side
            shown = side * scale
            left = w - 0.05 * w - shown if right else 0.05 * w
            top = h - 0.05 * h - shown if bottom else 0.05 * h
            camera = filling(canvas, cam, (left, top, shown, shown), side / 2 * scale)
        else:
            scale = min(bw / cam[0], bh / cam[1])
            pw, ph = cam[0] * scale, cam[1] * scale
            left = w - 0.05 * w - pw if right else 0.05 * w
            top = h - 0.05 * h - ph if bottom else 0.05 * h
            radius = 0.08 * min(bw, bh) / scale if shape == "rounded" else 0.0
            camera = at_rect(canvas, left, top, pw, ph, scale, radius)
        return camera, full(canvas, scr)
    if layout == "side_by_side":
        inner = w - 3 * m
        bw, bh = inner * 2 / 3, h - 2 * m
        scale = min(bw / scr[0], bh / scr[1])
        pw, ph = scr[0] * scale, scr[1] * scale
        screen = at_rect(canvas, m + (bw - pw) / 2, m + (bh - ph) / 2, pw, ph, scale, panel / scale)
        return filling(canvas, cam, (m + bw + m, m, inner / 3, bh), panel), screen
    if layout == "stacked":
        scale = min((w - 2 * m) / scr[0], (h - 3 * m) * 2 / 3 / scr[1])
        pw, ph = scr[0] * scale, scr[1] * scale
        screen = at_rect(canvas, (w - pw) / 2, m, pw, ph, scale, panel / scale)
        camera = filling(canvas, cam, (m, 2 * m + ph, w - 2 * m, h - 3 * m - ph), panel)
        return camera, screen
    if layout == "camera_full":
        return placement(0.0, 0.0, max(w / cam[0], h / cam[1])), full(canvas, scr)
    if layout == "screen_only":
        camera = dict(kept)
        camera["opacity"] = 0.0
        return camera, full(canvas, scr)
    raise ValueError(layout)


def numbers(p):
    return [p["x"], p["y"], p["scale"], p["crop"]["l"], p["crop"]["t"], p["crop"]["r"],
            p["crop"]["b"], p["corner_radius"], p["opacity"]]


def same(got, want):
    a, b = numbers(got), numbers(want)
    return a[:2] == b[:2] and all(abs(x - y) < 1e-9 for x, y in zip(a[2:], b[2:]))


def six(video):
    """A video group's six placement keys, defaults filled in."""
    crop = video.get("crop") or {}
    return placement(video.get("x", 0.0), video.get("y", 0.0), video.get("scale", 1.0),
                     tuple(crop.get(k, 0.0) for k in ("l", "t", "r", "b")),
                     video.get("corner_radius", 0.0), video.get("opacity", 1.0))


# ---- media and a document ----------------------------------------------------------

def media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    made = {}
    for name, (w, h) in (("camera", CAMERA), ("screen", SCREEN), ("wide", WIDE)):
        out = folder / f"{name}.mov"
        if not out.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                            f"testsrc=size={w}x{h}:rate=30:duration=20", "-c:v", "libx264",
                            "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-g", "30", str(out)],
                           check=True, timeout=600, env=bounded.child_env())
        made[name] = out
    return made


class Doc:
    """One saved package: the screen on the back track, the camera in front of it."""

    def __init__(self, client, files, name, canvas=(1920, 1080), screen="screen"):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.close()  # one an earlier run left open
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            try:
                self.call("set_canvas", width=canvas[0], height=canvas[1], fps=[30, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):  # a new project's own canvas
                    raise
            self.canvas = canvas
            self.screen = self.place(files[screen], 0)
            self.camera = self.place(files["camera"], 1)
        except Exception:
            self.close()
            raise

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def track(self, index):
        tracks = self.state()["tracks"]
        while len(tracks) <= index:
            self.call("add_track")
            tracks = self.state()["tracks"]
        return tracks[index]["id"]

    def place(self, path, index):
        m = self.call("import_media", path=str(path))["media"]
        return self.call("add_clip", track=self.track(index), media=m, at=0)["new_clips"][0]

    def switch(self, **arguments):
        return self.call("switch_layout", **arguments)

    def clip(self, cid, state=None):
        return next(c for c in (state or self.state())["clips"] if c["id"] == cid)

    def on_track(self, index, state=None):
        state = state or self.state()
        track = state["tracks"][index]["id"]
        return sorted((c for c in state["clips"] if c["track"] == track), key=lambda c: c["start"])

    def action_at(self, cid, clip_time, state=None):
        return next(a for a in self.clip(cid, state).get("actions", [])
                    if a["start"] == clip_time)

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def refused(body):
    """The tool's error text, or None when it applied."""
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


def doc_row(client, files, name, body, rows, **kw):
    doc = attempt(lambda: Doc(client, files, name, **kw), *rows)
    if doc is None:
        return
    try:
        attempt(lambda: body(doc), *rows)
    finally:
        doc.close()


# ---- the rows ----------------------------------------------------------------------

PROJECTS = []


def l1(client, files):
    for canvas in ((1920, 1080), (1080, 1920)):
        doc = Doc(client, files, f"l1-{canvas[0]}x{canvas[1]}", canvas=canvas)
        try:
            for layout in LAYOUTS:
                kept = six(doc.clip(doc.camera)["video"])
                doc.switch(camera=doc.camera, layout=layout, at=t(2))
                state = doc.state()
                path = WORK / f"l1-{canvas[0]}x{canvas[1]}-{layout}.json"
                path.write_text(json.dumps(state))
                PROJECTS.append(str(path))
                cam_end = doc.action_at(doc.camera, t(2), state)["end"]
                scr_end = doc.action_at(doc.screen, t(2), state)["end"]
                want_cam, want_scr = oracle(layout, canvas, CAMERA, SCREEN, kept)
                keys = set(cam_end["video"]) == SIX and set(scr_end["video"]) == SIX
                ok = keys and same(six(cam_end["video"]), want_cam) \
                    and same(six(scr_end["video"]), want_scr)
                check("L1", ok, f"{canvas[0]}×{canvas[1]} {layout}: camera "
                      f"{numbers(six(cam_end['video']))} (want {numbers(want_cam)}), screen "
                      f"{numbers(six(scr_end['video']))} (want {numbers(want_scr)}), six keys "
                      f"{keys}")
                undone = doc.call("undo").get("undone")
                assert undone == "Camera Layout", f"undo named {undone!r}"
        finally:
            doc.close()


def l2(doc):
    doc.switch(camera=doc.camera, layout="corner", at=0)
    clip = doc.clip(doc.camera)
    marker = doc.action_at(doc.camera, 0)
    want, _ = oracle("corner", doc.canvas, CAMERA, SCREEN)
    check("L2", marker["duration"] == FRAME and same(six(marker["end"]["video"]),
                                                     six(clip["video"]))
          and same(six(clip["video"]), want),
          f"marker {marker['duration']} ticks, its end {numbers(six(marker['end']['video']))}, "
          f"the base {numbers(six(clip['video']))} (want {numbers(want)})")


def cut_camera(doc, *seconds):
    for s in seconds:
        piece = next(c for c in doc.on_track(1) if c["start"] < t(s) < c["start"] + c["duration"])
        doc.call("split", clips=[piece["id"]], at=t(s))
    return [c["id"] for c in doc.on_track(1)]


def l3(doc):
    ids = cut_camera(doc, 4, 8, 12, 16)
    doc.switch(camera=ids[4], layout="corner", at=t(16))
    fifth = doc.clip(ids[4])
    doc.switch(camera=ids[1], layout="side_by_side", at=t(5))
    state = doc.state()
    want, _ = oracle("side_by_side", doc.canvas, CAMERA, SCREEN)
    carried = [same(six(doc.clip(i, state)["video"]), want) for i in ids[2:4]]
    kept = doc.clip(ids[4], state) == fifth
    check("L3", len(ids) == 5 and all(carried) and kept,
          f"clips {ids}; third and fourth side by side {carried}; fifth unchanged {kept}")


def l4(doc):
    doc.switch(camera=doc.camera, layout="corner", at=t(2))
    doc.switch(camera=doc.camera, layout="stacked", at=t(6))
    actions = doc.clip(doc.camera).get("actions", [])
    want, _ = oracle("stacked", doc.canvas, CAMERA, SCREEN)
    last = max(actions, key=lambda a: a["start"]) if actions else None
    check("L4", len(actions) == 2 and last and last["start"] == t(6)
          and same(six(last["end"]["video"]), want),
          f"{len(actions)} actions; the last at {last and last['start']} ends "
          f"{last and numbers(six(last['end']['video']))}")


def l5(doc):
    ids = cut_camera(doc, 10)
    doc.switch(camera=ids[1], layout="corner", at=t(13))
    own = doc.clip(ids[1]).get("actions", [])
    doc.switch(camera=ids[0], layout="side_by_side", at=t(2))
    second = doc.clip(ids[1])
    want, _ = oracle("side_by_side", doc.canvas, CAMERA, SCREEN)
    check("L5", same(six(second["video"]), want) and second.get("actions", []) == own
          and len(own) == 1,
          f"the second clip's base {numbers(six(second['video']))}; its action kept "
          f"{second.get('actions', []) == own}")


def l6_doc(client, files, name):
    doc = Doc(client, files, name)
    doc.call("split", clips=[doc.screen], at=t(10))
    later = doc.on_track(0)[1]["id"]
    zoom = doc.call("add_zoom_action", clip=later, at=t(2),
                    region={"x": 0, "y": 0, "width": 960, "height": 540})["new_actions"][0]
    return doc, later, zoom


def l6(client, files):
    doc, later, zoom = l6_doc(client, files, "l6")
    twin = None
    try:
        why = refused(lambda: doc.switch(camera=doc.camera, layout="side_by_side", at=t(2)))
        named = why is not None and f"The screen clip {later} at " in why \
            and f"zooms (action {zoom})" in why and "nest the screen's clips" in why
        check("L6", named, f"refused: {why!r}")
        doc.switch(camera=doc.camera, layout="side_by_side", at=t(2), nest=True)
        state = doc.state()
        inside = [c for n in state.get("nests", []) for c in n["clips"] if c["id"] == later]
        zoomed = bool(inside) and any(a["id"] == zoom for a in inside[0].get("actions", []))
        twin, _, _ = l6_doc(client, files, "l6-twin")
        pieces = [c["id"] for c in twin.on_track(0)]
        twin.call("nest", clips=pieces)
        twin.switch(camera=twin.camera, layout="side_by_side", at=t(2))
        a, b = WORK / "l6-nest.png", WORK / "l6-twin.png"
        doc.call("render_frame", t=t(12.5), path=str(a))
        twin.call("render_frame", t=t(12.5), path=str(b))
        identical = a.read_bytes() == b.read_bytes()
        check("L6", zoomed and identical and state == twin.state(),
              f"the zoom inside the nest {zoomed}; render_frame byte-identical to the twin "
              f"{identical}; get_project equal {state == twin.state()}")
    finally:
        doc.close()
        if twin:
            twin.close()


def l7(doc):
    action = doc.call("add_action", clip=doc.camera, at=t(1), duration=t(2))["new_actions"][0]
    doc.call("set_action_end", clip=doc.camera, action=action, patch={"video": {"opacity": 0.5}})
    why = refused(lambda: doc.switch(camera=doc.camera, layout="corner", at=t(2)))
    check("L7", why is not None and f"The camera clip {doc.camera} at " in why
          and f"moves (action {action})" in why, f"refused: {why!r}")


def l8(doc):
    ids = cut_camera(doc, 10)
    before = doc.clip(ids[1])
    doc.switch(camera=ids[0], layout="corner", at=t(2), through=t(8))
    after = doc.clip(ids[1])
    check("L8", json.dumps(after, sort_keys=True) == json.dumps(before, sort_keys=True),
          f"the clip after `through` unchanged {after == before}")


def l9(doc):
    before = doc.state()
    doc.switch(camera=doc.camera, layout="stacked", at=t(2))
    changed = doc.state() != before
    undone = doc.call("undo").get("undone")
    check("L9", changed and undone == "Camera Layout" and doc.state() == before,
          f"changed {changed}; undo named {undone!r}; back {doc.state() == before}")


def l10(doc):
    doc.switch(camera=doc.camera, layout="corner", shape="circle", at=t(2))
    circle = six(doc.action_at(doc.camera, t(2))["end"]["video"])
    doc.call("undo")
    doc.switch(camera=doc.camera, layout="corner", shape="rounded", at=t(2))
    rounded_end = six(doc.action_at(doc.camera, t(2))["end"]["video"])
    doc.call("undo")
    want_circle, _ = oracle("corner", doc.canvas, CAMERA, SCREEN, shape="circle")
    want_rounded, _ = oracle("corner", doc.canvas, CAMERA, SCREEN, shape="rounded")
    square = circle["crop"] == {"l": 280.0, "t": 0.0, "r": 280.0, "b": 0.0} \
        and circle["corner_radius"] == 360.0 and same(circle, want_circle)
    radius = same(rounded_end, want_rounded)
    doc.call("nest", clips=[doc.camera])
    nest = next(c["id"] for c in doc.state()["clips"] if c["source"]["kind"] == "nest")
    refusals = [refused(lambda s=shape: doc.switch(camera=nest, layout="corner", shape=s,
                                                   at=t(2)))
                for shape in ("circle", "rounded")]
    nested = all(r and f"clip {nest} is a nest clip, which cannot draw a rounded corner or a "
                 "circle." in r for r in refusals)
    check("L10", square and radius and nested,
          f"circle {numbers(circle)}; rounded radius {rounded_end['corner_radius']} (want "
          f"{want_rounded['corner_radius']}); nest clip refusals {refusals}")


def menu_twin(doc, path, tool_args, tag):
    """The menu item, its undo, then the tool: equal projects and one named step."""
    before = doc.state()
    doc.call("perform_menu_item", path=path)
    menu = doc.state()
    if menu == before:  # the item changed nothing: no step of its own to undo
        check("L12", False, f"{tag}: the menu item changed nothing")
        return
    undone = doc.call("undo").get("undone")
    back = doc.state() == before
    doc.switch(**tool_args)
    tool = doc.state()
    doc.call("undo")
    check("L12", menu != before and undone == "Camera Layout" and back and menu == tool,
          f"{tag}: changed {menu != before}; undo named {undone!r}, back {back}; equal to "
          f"switch_layout {menu == tool}")


def l12(doc):
    doc.call("set_playhead", t=t(3))
    doc.call("set_selection", clips=[doc.camera])
    menu_twin(doc, ["Clip", "Camera Layout", "Circle", "Top Left"],
              {"camera": doc.camera, "layout": "corner", "shape": "circle",
               "corner": "top_left", "at": t(3)}, "Circle ▸ Top Left, the camera selected")
    doc.call("set_selection", clips=[doc.screen, doc.camera])
    menu_twin(doc, ["Clip", "Camera Layout", "Side by Side"],
              {"camera": doc.camera, "screen": doc.screen, "layout": "side_by_side",
               "at": t(3)}, "Side by Side, both selected")
    doc.call("set_selection", clips=[])
    doc.client.call_with("set_track", {"project": str(doc.path), "track": doc.track(1),
                                       "name": "Camera"})
    menu_twin(doc, ["Clip", "Camera Layout", "Side by Side"],
              {"camera": doc.camera, "layout": "side_by_side", "at": t(3)},
              "Side by Side, none selected, a Camera track")


def l13(doc):
    zooms = [doc.call("add_zoom_action", clip=doc.screen, at=t(s),
                      region={"x": 0, "y": 0, "width": 1280, "height": 720})["new_actions"][0]
             for s in (8, 12)]
    base = six(doc.clip(doc.screen)["video"])
    full_at = same(base, full(doc.canvas, WIDE))
    before = [a for a in doc.clip(doc.screen)["actions"] if a["id"] in zooms]
    doc.call("set_playhead", t=t(3))
    doc.call("set_selection", clips=[doc.camera])
    doc.call("perform_menu_item", path=["Clip", "Camera Layout", "Circle", "Bottom Right"])
    after = doc.clip(doc.screen)["actions"]
    laid = any(a["start"] == t(3) for a in after)
    kept = [a for a in after if a["id"] in zooms] == before
    why = refused(lambda: doc.switch(camera=doc.camera, layout="side_by_side", at=t(5)))
    named = why is not None and f"zooms (action {zooms[0]})" in why
    doc.switch(camera=doc.camera, layout="side_by_side", at=t(5), nest=True)
    nested = bool(doc.state().get("nests"))
    check("L13", full_at and laid and kept and named and nested,
          f"base at full placement {numbers(base)} {full_at}; the circle applied {laid}; zooms "
          f"unchanged {kept}; side by side refused {why!r}; nested {nested}")


# ---- the probe ---------------------------------------------------------------------

def probe_rows(sources):
    here = WORK / "probe"
    here.mkdir(parents=True, exist_ok=True)
    entry = here / "main.swift"
    shutil.copyfile(HERE / "co6_probe.swift", entry)
    binary = here / "co6-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        check("L11", False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    if not PROJECTS:
        check("L11", False, "L1 wrote no project for the probe")
        return
    clips = sorted({c["id"] for p in PROJECTS for c in json.loads(Path(p).read_text())["clips"]})
    request = here / "request.json"
    request.write_text(json.dumps({"projects": PROJECTS, "clips": clips}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=PROBE_WALL, env=bounded.child_env(
                                 {"CFFIXED_USER_HOME": str(HOME)}))
    except subprocess.TimeoutExpired:
        check("L11", False, f"the probe gave no answer within {PROBE_WALL} s")
        return
    (here / "stderr.txt").write_text(run.stderr)
    try:
        rows = {r["id"]: r for r in json.loads(run.stdout)["rows"]}
    except (ValueError, KeyError):
        rows = {}
    answer = rows.get("L11")
    if answer is None:
        check("L11", False, f"the probe did not answer it (exit {run.returncode})")
    else:
        check("L11", answer["pass"], answer["detail"])


# ---- launches ----------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def plain_rows(client, files):
    if {"L1", "L11"} & selected:
        attempt(lambda: l1(client, files), *({"L1", "L11"} & selected))
    for name, body, kw in (("L2", l2, {}), ("L3", l3, {}), ("L4", l4, {}), ("L5", l5, {}),
                           ("L7", l7, {}), ("L8", l8, {}), ("L9", l9, {}), ("L10", l10, {}),
                           ("L12", l12, {}), ("L13", l13, {"screen": "wide"})):
        if name in selected:
            doc_row(client, files, name.lower(), body, [name], **kw)
    if "L6" in selected:
        attempt(lambda: l6(client, files), "L6")


def with_instance(binary, tag, body):
    log = WORK / f"instance-{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), [], env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            return False
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)
    return True


# ---- mutants -----------------------------------------------------------------------

def edited(name, root):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def core_mutant(name):
    copy = WORK / "mutant-core"
    if copy.exists():
        tree_copy.remove_tree(str(copy))
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "core", copy / "core", ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "graphic", copy / "graphic")
    why = edited(name, copy)
    if why:
        return None, why
    env = bounded.child_env({"CARGO_TARGET_DIR": str(WORK / "mutant-target")})
    run = subprocess.run(["cargo", "test", "--release", "--test", "layout"],
                         cwd=copy / "core", capture_output=True, text=True,
                         timeout=BUILD_BOUND, env=env)
    (WORK / f"mutant-{name}.log").write_text(run.stdout + run.stderr)
    failed = [line.split()[1] for line in run.stdout.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    if run.returncode != 0 and not failed:
        return None, "cargo test did not run the tests (see the log)"
    return failed, None


def run_mutant(name):
    global selected
    named, _, kind = MUTANTS[name]
    print(f"CO6 — the {name} MUTANT ({', '.join(named)} must FAIL)", flush=True)
    if kind == "core":
        failed, why = core_mutant(name)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        caught = [f for f in failed if any(f.startswith(p) for p in named)]
        print(f"failing tests: {failed or 'none'}")
        print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(named)} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    selected = set(named) | {"Z1"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"))
    why = why or edited(name, Path(made))
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    app, why = tree_copy.build_app(made, BUILD_BOUND)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    files = media()
    if not with_instance(proof_app.executable(app), "mutant",
                         lambda c: doc_row(c, files, "l12", l12, ["L12"])):
        print(f"mutant {name}: the control could not be performed — the app did not listen")
        return 2
    if "L12" not in results:
        print(f"mutant {name}: the control could not be performed — L12 was never scored")
        return 2
    caught = not all(ok for ok, _ in results["L12"])
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: L12 "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


# ---- main --------------------------------------------------------------------------

def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        for child in WORK.iterdir():
            if child.name not in KEEP:
                tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)

    print(f"CO6 — camera layouts ({proof_app.config()} build)", flush=True)
    files = media()
    if args.socket:
        client = mcp.MCP(args.socket, timeout=CALL_BOUND)
        plain_rows(client, files)
        parity(Path(args.socket).parent / "framejob.log", "the given instance")
    else:
        binary = Path(args.app) if args.app else proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        if not with_instance(binary, "plain", lambda c: plain_rows(c, files)):
            for row in selected & set(PLAIN):
                check(row, False, "the app did not listen")
    if "L11" in selected:
        attempt(lambda: probe_rows(ROOT / "app/Sources"), "L11")

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
