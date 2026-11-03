#!/usr/bin/env python3
"""Road map "creator-jobs" CU7 — Clip ▸ Auto Zoom… and `auto_zoom` (spec §11 CU-70…CU-77).

    python3 tools/proof/cu7_proof.py [SOCKET] [--only Z1,Z7,…] [--mutant NAME] [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the
plain rows launch their own instance. Z11 always launches its own two, with
`-RCDevAutoZoomAccept YES`. Launches run on a scratch `CFFIXED_USER_HOME`; packages and media
are made under `tools/proof/work/cu7/`. The movies are ffmpeg's `testsrc` (640 × 360 30 fps
20 s, and 2560 × 1440 for 3 s), each with a v1 cursor file beside it written here per
`core/src/cursor_file.rs` (`movie_size` the movie's, 2 px a point, so a file unit is 1/50 px;
`import_media` attaches it, CU-34). Every canvas is 640 × 360 at 30 fps unless said, so a
×2 region is 320 × 180 and its centre is clamped to x ∈ [−160, 160], y ∈ [−90, 90] in Q.

Rows:
- Z0 `grep "Frame Job: "` of every instance's log prints nothing.
- Z1 clicks at 2.0 s (the centre), 3.0 s (inside the inner 60 %), 4.0 s (outside), 12.0 s and
  13.0 s, follow off: in [1.4, 2.0), pan [3.4, 4.0), back [6.5, 7.3), in [11.4, 12.0), back
  [15.5, 16.3) s, two visits; the back's end the clip's base.
- Z2 a click at (5, 5) px: the zoom-in's end is the region clamped at the corner, (−160, −90)
  → scale 2, x 320, y 180.
- Z3 a Speed action ×1→×2 over [0, 0.6 s) (S(0.6 s) = 0.9 s): a click at source 4.9 s is clip
  2.6 s, so in [2.0, 2.6) and back [5.1, 5.9) s.
- Z4 a hand zoom over [1.5, 2.5) s on Z1's file, Replace off: kept, the zoom-in dropped and
  counted, four added.
- Z5 (probe, `cu7_probe.swift`) `ActionBands.isZoom` equals the core's `is_zoom`, read through
  Replace's removals, on twelve ends.
- Z6 after Z1, one `undo` named "Auto Zoom" takes every action off.
- Z7 a clip zoomed by hand and split at 3 s mid-hold, Auto Zoom on the second half: Replace off,
  its zoom back ends at the first half's base (±1e-6); Replace on, its base is reset to it and
  the back still ends there. And with only the second half given, a click 0.2 s after the cut:
  the zoom-in starts at the cut on the second half and the first half gains no action.
- Z8 a visit across a cut (both halves given, the second's base the rest): the second half's
  base is set to the placement in force (≤ 1 px from the first half's), nothing straddles a
  cut, and the zoom back ends at the rest (±1e-6).
- Z9 a clip at half the fit moved left refused with CU-75's sentence; the same screen nested,
  the nest clip placed side by side, planned inside the nest with the nest clip unchanged; a
  screen at 1.2× moved left planned; a 2560 × 1440 movie at scale 1 on a 3840 × 2160 canvas
  planned.
- Z10 a reversed clip refused by name.
- Z11 Clip ▸ Auto Zoom… by `perform_menu_item` on an instance launched with
  `-RCDevAutoZoomAccept YES`: one step "Auto Zoom" whose actions equal `auto_zoom`'s with the
  sheet's values on a copy of the same project — once at the defaults, once with
  `-FrameJobAutoZoomZoom 3 -FrameJobAutoZoomLead 1`.

`--mutant NAME`: the named decision broken. A core mutant edits a copy of `core/` (beside a
link to `graphic/`) and runs `cargo test --release --test auto_zoom` there: CAUGHT when a test
of its row fails. The sheet's mutant edits a `tree_copy.py` copy and runs Z11 on its built
app. CAUGHT exits 1, SURVIVED exits 0, a control that could not be performed exits 2.
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
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/cu7"
HOME = WORK / "home"
KEEP = {"media", "mutant-target"}
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 600
BUILD_BOUND = 1500
PROBE_WALL = 240
EXACT = 1e-6
PLAIN = ["Z1", "Z2", "Z3", "Z4", "Z6", "Z7", "Z8", "Z9", "Z10"]
ACCEPT = ["Z11"]
PROBE = ["Z5"]
ROWS = ["Z0"] + PLAIN + PROBE + ACCEPT
SENTENCE = ("Clip {c} is placed smaller than the canvas; a zoom would fill the canvas. Nest it "
            "(Clip ▸ Nest) and run Auto Zoom inside the nest.")

VISITS = "core/src/cursor_zoom_visits.rs"
PLANNER = "core/src/cursor_zoom.rs"
RUN = "core/src/cursor_zoom_run.rs"
SHEET = "app/Sources/AutoZoomSheetController.swift"
# name → (rows, [(path, anchor, replacement)], "core" or "app")
MUTANTS = {
    "merge-gap-ignored": (["Z1"], [(
        VISITS, "let merge = i > 0 && !closed_by[i - 1] && {",
        "let merge = false && i > 0 && !closed_by[i - 1] && {")], "core"),
    "region-not-clamped": (["Z2"], [(
        VISITS, "    pub(crate) fn clamp(&self, p: (f64, f64)) -> (f64, f64) {\n",
        "    pub(crate) fn clamp(&self, p: (f64, f64)) -> (f64, f64) {\n        return p;\n")],
        "core"),
    "clip-time-without-s": (["Z3"], [(RUN, "if is_ramped(clip) {", "if false && is_ramped(clip) {")],
                            "core"),
    "replace-removes-non-zoom": (["Z4"], [(
        PLANNER, "clip.actions.iter().filter(|a| is_zoom(a))",
        "clip.actions.iter().filter(|a| is_zoom(a) || true)")], "core"),
    "lead-after-click": (["Z1"], [(
        VISITS, "        from: hold_start,\n        to: first.t,\n",
        "        from: first.t,\n        to: first.t + timing.lead,\n")], "core"),
    "later-half-back-null": (["Z7"], [(
        PLANNER, "None if same(placement(clip), rest) => Value::Null,",
        "None if true || same(placement(clip), rest) => Value::Null,")], "core"),
    "straddle-cut": (["Z8"], [
        (RUN, ".find(|c| self.is_given(c) && c.start <= mid && mid < end(c))",
         ".find(|c| self.is_given(c) && c.start <= p.from && p.from < end(c))"),
        (RUN, "        if p.to > end(target) {\n", "        if false && p.to > end(target) {\n"),
        (PLANNER, "duration = duration.min(clip.duration - at);", "")], "core"),
    "placement-check-removed": (["Z9"], [(
        PLANNER, "if rest < project.fit_scale(sw, sh) * (1.0 - PLACED_TOLERANCE) {",
        "if false && rest < project.fit_scale(sw, sh) * (1.0 - PLACED_TOLERANCE) {")], "core"),
    # The plan alone loses Arrive: what Zoom remembers is untouched, so the mutant writes
    # no default.
    "sheet-arrive-not-passed": (["Z11"], [(
        SHEET, "clips, tracks: tracks, project: document.editedProject, settings: settings,",
        "clips, tracks: tracks, project: document.editedProject,\n"
        "                settings: { var s = settings; s.lead = AutoZoomSettings().lead; return s }(),"
    )], "app"),
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


# ---- media and cursor files ----------------------------------------------------

def movies():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    made = {
        "screen.mov": "testsrc=size=640x360:rate=30:duration=20",
        "big.mov": "testsrc=size=2560x1440:rate=30:duration=3",
    }
    for name, source in made.items():
        out = folder / name
        if not out.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", source,
                            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "30", "-bf", "0",
                            str(out)], check=True, timeout=300, env=bounded.child_env())
    return {"screen": folder / "screen.mov", "big": folder / "big.mov"}


def s(seconds):
    """Seconds to whole µs."""
    return int(round(seconds * 1e6))


def t(seconds):
    """Seconds to ticks."""
    return int(round(seconds * SEC))


def cursor_body(clicks, size=(640, 360)):
    """A v1 cursor file: down clicks at (seconds, px x, px y), one move at the centre."""
    w, h = size
    n = len(clicks)
    return {
        "format": "framejob-cursor", "version": 1, "in_picture": False, "source": "display",
        "display_id": 1, "source_frame": [0, 0, w * 50, h * 50], "point_size": [w * 50, h * 50],
        "pixels_per_point": 2.0, "content_size": [w, h], "movie_size": [w, h],
        "anchor": "e2", "anchor_host_us": 1000, "cursor_image": "none",
        "moves": {"t": [0], "x": [w * 25], "y": [h * 25]},
        "images": [], "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {"t": [s(c[0]) for c in clicks], "button": [0] * n, "down": [1] * n,
                   "x": [int(c[1] * 50) for c in clicks], "y": [int(c[2] * 50) for c in clicks],
                   "count": [1] * n},
        "scrolls": {"t": [], "x": [], "y": [], "dx": [], "dy": []},
        "geometry": [{"t": 0, "screen_rect": [0, 0, w * 50, h * 50],
                      "content_rect": [0, 0, w * 50, h * 50], "content_scale": 1.0,
                      "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {"t": [], "keys": [], "code": []}, "typed": {"t": []}},
    }


def recording(files, name, clicks, movie="screen", size=(640, 360)):
    """`<WORK>/rec/<name>/A.mov` with its `A.fjcursor` beside; the movie's path."""
    folder = WORK / "rec" / name
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "A.mov"
    shutil.copyfile(files[movie], path)
    (folder / "A.fjcursor").write_text(json.dumps(cursor_body(clicks, size)))
    return path


Z1_CLICKS = [(2.0, 320, 180), (3.0, 350, 200), (4.0, 560, 180), (12.0, 200, 150),
             (13.0, 210, 160)]


# ---- a document ----------------------------------------------------------------

class Doc:
    """One saved package on a 640 × 360 (or `size`), 30 fps canvas."""

    def __init__(self, client, name, size=(640, 360)):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=size[0], height=size[1], fps=[30, 1])

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def place(self, movie):
        media = self.call("import_media", path=str(movie))["media"]
        tracks = self.state()["tracks"]
        if not tracks:
            self.call("add_track")
            tracks = self.state()["tracks"]
        clip = self.call("add_clip", track=tracks[0]["id"], media=media, at=0)["new_clips"][0]
        row = next(m for m in self.state()["media"] if m["id"] == media)
        assert row.get("cursor"), f"import attached no cursor file to {movie}"
        return clip

    def clip(self, clip_id, state=None):
        state = state or self.state()
        return next(c for c in state["clips"] if c["id"] == clip_id)

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def refusal(body):
    """The tool's sentence, without `mcp.py`'s "<tool>: " prefix; None when it applied."""
    try:
        body()
    except mcp.ToolError as error:
        text = str(error)
        return text.split(": ", 1)[1] if text.startswith("auto_zoom: ") else text
    return None


def spans(answer):
    return [(a["clip"], a["at"], a["duration"], a["kind"]) for a in answer.get("actions", [])]


def end_video(action):
    v = (action.get("end") or {}).get("video") or {}
    return (v.get("scale"), v.get("x"), v.get("y"))


def near(a, b, tol=EXACT):
    return all(x is not None and abs(x - y) <= tol for x, y in zip(a, b))


def base(clip):
    v = clip.get("video") or {}
    return (v.get("scale", 1.0), v.get("x", 0.0), v.get("y", 0.0))


# ---- the plain rows ------------------------------------------------------------

def z1_z6(client, files):
    doc = Doc(client, "z1")
    try:
        clip = doc.place(recording(files, "z1", Z1_CLICKS))
        answer = doc.call("auto_zoom", clip=clip, follow=False)
        want = [(clip, t(1.4), t(0.6), "in"), (clip, t(3.4), t(0.6), "pan"),
                (clip, t(6.5), t(0.8), "back"), (clip, t(11.4), t(0.6), "in"),
                (clip, t(15.5), t(0.8), "back")]
        actions = sorted(doc.clip(clip)["actions"], key=lambda a: a["start"])
        backs = [end_video(a) for a in actions if a["start"] in (t(6.5), t(15.5))]
        check("Z1", spans(answer) == want and answer.get("visits") == 2 and len(actions) == 5
              and all(near(b, (1.0, 0.0, 0.0), 1e-9) for b in backs),
              f"actions {spans(answer)} (want {want}); visits {answer.get('visits')}; "
              f"{len(actions)} in the project; backs end at {backs}")
        undone = doc.call("undo").get("undone")
        left = doc.clip(clip)["actions"]
        check("Z6", undone == "Auto Zoom" and left == [],
              f"undo named {undone!r}; {len(left)} actions left")
    finally:
        doc.close()


def z2(client, files):
    doc = Doc(client, "z2")
    try:
        clip = doc.place(recording(files, "z2", [(2.0, 5, 5)]))
        doc.call("auto_zoom", clip=clip)
        first = min(doc.clip(clip)["actions"], key=lambda a: a["start"])
        got = end_video(first)
        check("Z2", near(got, (2.0, 320.0, 180.0), 1e-9),
              f"the zoom-in ends at {got} (the region at (−160, −90): want (2, 320, 180))")
    finally:
        doc.close()


def z3(client, files):
    doc = Doc(client, "z3")
    try:
        clip = doc.place(recording(files, "z3", [(4.9, 320, 180)]))
        doc.call("trim_end", clip=clip, to=8 * SEC)
        doc.call("add_action", clip=clip, at=0, duration=t(0.6))
        ramp = doc.clip(clip)["actions"][0]["id"]
        doc.call("set_action_end", clip=clip, action=ramp, patch={"speed": 2.0})
        answer = doc.call("auto_zoom", clip=clip, follow=False)
        want = [(clip, t(2.0), t(0.6), "in"), (clip, t(5.1), t(0.8), "back")]
        check("Z3", spans(answer) == want,
              f"actions {spans(answer)} (want {want}: source 4.9 s is clip 2.6 s through S)")
    finally:
        doc.close()


def z4(client, files):
    doc = Doc(client, "z4")
    try:
        clip = doc.place(recording(files, "z4", Z1_CLICKS))
        doc.call("add_zoom_action", clip=clip, at=t(1.5), duration=SEC,
                 region={"x": 0, "y": 0, "width": 320, "height": 180})
        hand = doc.clip(clip)["actions"][0]["id"]
        answer = doc.call("auto_zoom", clip=clip, follow=False)
        ids = [a["id"] for a in doc.clip(clip)["actions"]]
        check("Z4", answer.get("dropped") == 1 and answer.get("added") == 4
              and answer.get("replaced") == 0 and hand in ids and len(ids) == 5,
              f"dropped {answer.get('dropped')}, added {answer.get('added')}, replaced "
              f"{answer.get('replaced')}; the hand zoom kept {hand in ids}; {len(ids)} actions")
    finally:
        doc.close()


def split_doc(client, files, name, clicks, hand=False):
    doc = Doc(client, name)
    clip = doc.place(recording(files, name, clicks))
    if hand:
        doc.call("add_zoom_action", clip=clip, at=SEC, duration=t(0.6),
                 region={"x": 100, "y": 0, "width": 320, "height": 180})
    second = doc.call("split", clips=[clip], at=3 * SEC)["new_clips"][0]
    return doc, clip, second


def z7(client, files):
    clicks = [(8.0, 320, 180)]
    for replace in (False, True):
        doc, first, second = split_doc(client, files, f"z7-{replace}", clicks, hand=True)
        try:
            before = base(doc.clip(second))
            answer = doc.call("auto_zoom", clip=second, follow=False, replace=replace)
            state = doc.state()
            rest = base(doc.clip(first, state))
            back = max(doc.clip(second, state)["actions"], key=lambda a: a["start"])
            after = base(doc.clip(second, state))
            ok = near(end_video(back), rest) and (not replace or near(after, rest, 1e-9))
            check("Z7", ok and before[0] == 2.0,
                  f"replace {replace}: the second half's base {before} → {after}; its zoom back "
                  f"ends at {end_video(back)}, the first half's base {rest}; bases_set "
                  f"{answer.get('bases_set')}")
        finally:
            doc.close()
    doc, first, second = split_doc(client, files, "z7-cut", [(3.2, 320, 180)])
    try:
        answer = doc.call("auto_zoom", clip=second, follow=False)
        state = doc.state()
        first_actions = doc.clip(first, state)["actions"]
        check("Z7", spans(answer)[:1] == [(second, 0, t(0.6), "in")] and first_actions == [],
              f"a click 0.2 s after the cut: {spans(answer)[:1]} (want the zoom-in at the "
              f"cut on {second}); the first half's actions {first_actions}")
    finally:
        doc.close()


def z8(client, files):
    doc = Doc(client, "z8")
    try:
        clip = doc.place(recording(files, "z8", [(4.0, 320, 180), (6.5, 560, 180)]))
        second = doc.call("split", clips=[clip], at=6 * SEC)["new_clips"][0]
        answer = doc.call("auto_zoom", clips=[clip, second], follow=False)
        state = doc.state()
        a, b = doc.clip(clip, state), doc.clip(second, state)
        held = end_video(max(a["actions"], key=lambda x: x["start"]))
        b_base = base(b)
        px = max(abs(held[0] - b_base[0]) * 320, abs(held[1] - b_base[1]),
                 abs(held[2] - b_base[2])) if None not in held else None
        inside = all(x["start"] >= 0 and x["start"] + x["duration"] <= c["duration"]
                     for c in (a, b) for x in c["actions"])
        back = end_video(max(b["actions"], key=lambda x: x["start"]))
        check("Z8", answer.get("bases_set") == 1 and px is not None and px <= 1
              and inside and near(back, base(a)),
              f"bases_set {answer.get('bases_set')}; the first half holds {held}, the second "
              f"starts at {b_base} ({px} px apart); every action inside its clip {inside}; "
              f"the zoom back ends at {back} (rest {base(a)}); {spans(answer)}")
    finally:
        doc.close()


def z9(client, files):
    doc = Doc(client, "z9-side")
    try:
        clip = doc.place(recording(files, "z9-side", [(2.0, 320, 180)]))
        doc.call("set_video", clips=[clip], patch={"scale": 0.5, "x": -160})
        said = refusal(lambda: doc.call("auto_zoom", clip=clip))
        check("Z9", said == SENTENCE.format(c=clip), f"side by side: {said!r}")
    finally:
        doc.close()
    doc = Doc(client, "z9-nest")
    try:
        clip = doc.place(recording(files, "z9-nest", [(2.0, 320, 180)]))
        doc.call("nest", clips=[clip])
        state = doc.state()
        nest = state["nests"][0]["id"]
        holder = next(c for c in state["clips"] if c["source"].get("kind") == "nest")
        doc.call("set_video", clips=[holder["id"]], patch={"scale": 0.5, "x": -160})
        placed = base(doc.clip(holder["id"]))
        doc.call("set_scope", nest=nest)
        answer = doc.call("auto_zoom", clip=clip)
        doc.call("set_scope")
        after = base(doc.clip(holder["id"]))
        check("Z9", answer.get("added", 0) >= 2 and after == placed,
              f"inside the nest: added {answer.get('added')}; the nest clip {placed} → {after}")
    finally:
        doc.close()
    doc = Doc(client, "z9-moved")
    try:
        clip = doc.place(recording(files, "z9-moved", [(2.0, 320, 180)]))
        doc.call("set_video", clips=[clip], patch={"scale": 1.2, "x": -100})
        answer = doc.call("auto_zoom", clip=clip)
        check("Z9", answer.get("added", 0) >= 2, f"1.2× moved left: added {answer.get('added')}")
    finally:
        doc.close()
    doc = Doc(client, "z9-big", size=(3840, 2160))
    try:
        clip = doc.place(recording(files, "z9-big", [(1.0, 1280, 720)], movie="big",
                                   size=(2560, 1440)))
        scale = base(doc.clip(clip))[0]
        answer = doc.call("auto_zoom", clip=clip)
        check("Z9", scale == 1.0 and answer.get("added", 0) >= 1,
              f"2560 × 1440 at scale {scale} on 3840 × 2160: added {answer.get('added')}")
    finally:
        doc.close()


def z10(client, files):
    doc = Doc(client, "z10")
    try:
        clip = doc.place(recording(files, "z10", [(2.0, 320, 180)]))
        doc.call("set_reversed", clip=clip, reversed=True)
        said = refusal(lambda: doc.call("auto_zoom", clip=clip))
        want = f"Clip {clip} plays reversed; Auto Zoom plans only clips that play forward."
        check("Z10", said == want, f"{said!r}")
    finally:
        doc.close()


# ---- Z11 ----------------------------------------------------------------------

def without_ids(actions):
    return sorted(({k: v for k, v in a.items() if k != "id"} for a in actions),
                  key=lambda a: a["start"])


def z11(client, files, tag, values):
    doc = Doc(client, f"z11-{tag}")
    copy = Doc(client, f"z11-{tag}-copy")
    try:
        movie = recording(files, f"z11-{tag}", Z1_CLICKS)
        clip = doc.place(movie)
        twin = copy.place(movie)
        doc.call("set_selection", clips=[clip])
        before = doc.state()
        pressed = doc.call("perform_menu_item", path=["Clip", "Auto Zoom…"])
        began = time.monotonic()
        while time.monotonic() - began < 30 and doc.state() == before:
            time.sleep(0.25)
        menu = without_ids(doc.clip(clip)["actions"])
        undone = doc.call("undo").get("undone")
        back = doc.clip(clip)["actions"] == []
        copy.call("auto_zoom", clip=twin, **values)
        tool = without_ids(copy.clip(twin)["actions"])
        check("Z11", menu and menu == tool and undone == "Auto Zoom" and back,
              f"{tag}: perform_menu_item ok {pressed.get('ok')}; the menu made {len(menu)} "
              f"actions, auto_zoom {values} {len(tool)}, equal {menu == tool}; undo named "
              f"{undone!r}, all gone {back}")
    finally:
        doc.close()
        copy.close()


# ---- the probe -----------------------------------------------------------------

def z5(sources):
    here = WORK / "probe"
    here.mkdir(parents=True, exist_ok=True)
    entry = here / "main.swift"
    shutil.copyfile(HERE / "cu7_probe.swift", entry)
    binary = here / "cu7-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        check("Z5", False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    zoom = {"scale": 2, "x": 0, "y": 0}
    ends = [{"video": zoom}, {"video": {"scale": 2, "x": 0}},
            {"video": {**zoom, "rotation": 5}}, {"video": zoom, "audio": {}},
            {"video": zoom, "audio": {"volume": 0.5}}, {"video": zoom, "text": None},
            {"video": zoom, "graphic": {"props": {}}},
            {"video": zoom, "graphic": {"props": {"size": 1}}}, {"video": zoom, "speed": 1.0},
            {}, {"video": {"x": 0, "y": 0, "scale": 1, "corner_radius": 0, "opacity": 1,
                           "crop": {"l": 0, "t": 0, "r": 0, "b": 0}}},
            {"audio": {"volume": 0}}]
    actions = [{"id": 100 + i, "start": i * SEC, "duration": SEC // 2, "curve": "linear",
                "end": end} for i, end in enumerate(ends)]
    project = {
        "version": 38,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1], "background": [0, 0, 0, 1],
                   "fit_new_clips": True, "timecode_frames": True},
        "media": [{"id": 1, "path": "/proof/cu7/A.mov", "kind": "video", "duration": 20 * SEC,
                   "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                   "cursor": {"path": "/proof/cu7/A.fjcursor", "in_picture": False}}],
        "tracks": [{"id": 2, "name": "Screen"}],
        "clips": [{"id": 10, "track": 2, "start": 0, "duration": 20 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "video": {},
                   "actions": actions}],
        "markers": [], "next_id": 500,
    }
    (here / "project.json").write_text(json.dumps(project))
    (here / "A.fjcursor").write_text(json.dumps(cursor_body([])))
    request = here / "request.json"
    request.write_text(json.dumps({"project": str(here / "project.json"),
                                   "cursor": str(here / "A.fjcursor")}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=PROBE_WALL, env=bounded.child_env(
                                 {"CFFIXED_USER_HOME": str(HOME)}))
        rows = {r["id"]: r for r in json.loads(run.stdout)["rows"]}
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        check("Z5", False, f"the probe gave no answer: {error}")
        return
    got = rows.get("Z5")
    check("Z5", got is not None and got["pass"], (got or {}).get("detail", "no row"))


# ---- launches ------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def plain_rows(client, files):
    if {"Z1", "Z6"} & selected:
        attempt(lambda: z1_z6(client, files), *({"Z1", "Z6"} & selected))
    for name, body in (("Z2", z2), ("Z3", z3), ("Z4", z4), ("Z7", z7), ("Z8", z8),
                       ("Z9", z9), ("Z10", z10)):
        if name in selected:
            attempt(lambda body=body: body(client, files), name)


def with_instance(binary, arguments, tag, body):
    log = WORK / f"instance-{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    try:
        if launched.client is None:
            return False
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)
    return True


def accept_rows(binary, files):
    runs = [("defaults", [], {}),
            ("set", ["-FrameJobAutoZoomZoom", "3", "-FrameJobAutoZoomLead", "1"],
             {"zoom": 3, "lead": 1.0})]
    for tag, extra, values in runs:
        arguments = ["-RCDevAutoZoomAccept", "YES", *extra]
        if not with_instance(binary, arguments, f"accept-{tag}",
                             lambda c, tag=tag, values=values:
                             attempt(lambda: z11(c, files, tag, values), "Z11")):
            check("Z11", False, f"the app did not listen ({tag})")


# ---- mutants -------------------------------------------------------------------

def core_mutant(name):
    """Runs the core's auto_zoom tests on a copy of `core/` with the mutant's edits; the
    failing tests' names, or None and the reason the control could not be performed."""
    copy = WORK / "mutant-core"
    if copy.exists():
        tree_copy.remove_tree(str(copy))
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "core", copy / "core", ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "graphic", copy / "graphic")
    for path, anchor, replacement in MUTANTS[name][1]:
        target = copy / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    env = bounded.child_env({"CARGO_TARGET_DIR": str(WORK / "mutant-target")})
    run = subprocess.run(["cargo", "test", "--release", "--test", "auto_zoom"],
                         cwd=copy / "core", capture_output=True, text=True, timeout=BUILD_BOUND,
                         env=env)
    (WORK / f"mutant-{name}.log").write_text(run.stdout + run.stderr)
    failed = [line.split()[1] for line in run.stdout.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    if run.returncode != 0 and not failed:
        return None, "cargo test did not run the tests (see the log)"
    return failed, None


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, why = tree_copy.build_app(made, BUILD_BOUND)
    if app is None:
        return None, why
    return proof_app.executable(app), None


def run_mutant(name, files):
    rows, _, kind = MUTANTS[name]
    print(f"CU7 — the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    if kind == "core":
        failed, why = core_mutant(name)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        caught = [f for f in failed if any(f.startswith(r.lower() + "_") for r in rows)]
        print(f"failing tests: {failed or 'none'}")
        print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    binary, why = mutant_app(name)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    global selected
    selected = set(rows)
    accept_rows(binary, files)
    named_failed = [r for r in rows if r in results and not all(ok for ok, _ in results[r])]
    if not set(rows) & set(results):
        print(f"mutant {name}: the control could not be performed — its rows were never scored")
        return 2
    print(f"MUTANT {name} {'CAUGHT' if named_failed else 'SURVIVED'}: {', '.join(rows)} "
          f"{'failed' if named_failed else 'passed'}")
    return 1 if named_failed else 0


# ---- main ----------------------------------------------------------------------

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
        selected.add("Z0")
    if WORK.exists():
        for child in WORK.iterdir():
            if child.name not in KEEP:
                tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        files = movies() if MUTANTS[args.mutant][2] == "app" else {}
        return run_mutant(args.mutant, files)

    print(f"CU7 — Auto Zoom ({proof_app.config()} build)", flush=True)
    if "Z5" in selected:
        attempt(lambda: z5(ROOT / "app/Sources"), "Z5")
    if selected & set(PLAIN + ACCEPT):
        files = movies()
        binary = Path(args.app) if args.app else proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        if selected & set(PLAIN):
            if args.socket:
                client = mcp.MCP(args.socket, timeout=CALL_BOUND)
                plain_rows(client, files)
                parity(Path(args.socket).parent / "framejob.log", "the given instance")
            elif not with_instance(binary, [], "plain", lambda c: plain_rows(c, files)):
                for row in selected & set(PLAIN):
                    check(row, False, "the app did not listen (plain)")
        if "Z11" in selected:
            accept_rows(binary, files)

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
