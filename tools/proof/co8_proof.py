#!/usr/bin/env python3
"""Road map "creator-jobs" CO8 — the camera's layout and cutout at record time (spec §11
CO-80…CO-84), over MCP.

    python3 tools/proof/co8_proof.py [SOCKET] [--only R1,R2,…] [--mutant NAME] [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the rows
launch their own instance on a scratch `CFFIXED_USER_HOME`. Packages and media are made under
`tools/proof/work/co8/`: a 1920 × 1080 30 fps `testsrc` screen movie (20 s, no sound), a 640 × 360
camera movie (8 s) and 20 s of silent voice. Every recording is landed by the dev tool
`land_recording` — `door: "tool"`, `record_screen`'s landing, unless a row says the panel's — into a
fresh saved package; `land_recording`'s panel door builds its own choice, so the two
`FrameJobRecording…` landing keys never reach it.

Rows:
- Z0 `grep "Frame Job: "` of every instance's log prints nothing.
- R1 the default landing (both doors): the camera's x, y, scale are CAM-10 (3)'s arithmetic,
  computed here, its crop, corner_radius and opacity the defaults; the screen's video equals an
  `add_clip` twin's; each role clip has exactly one layout action, at clip time 0 and one frame
  long, whose end equals its base's six keys.
- R1b `camera_offset` of 2 frames: the camera as in R1; the screen's base the twin's, with one
  layout action at clip time 2 frames, one frame long.
- R2 each of the five layouts: the camera's and the screen's base and actions equal a twin landed
  by default and then given `switch_layout {camera, screen, layout, shape, at, duration: one
  frame, through}` by hand.
- R3 `camera_cutout: true`: the answer's `camera_cutout.clips` the camera clip; undo answers
  "Remove Background" and then "Add Recording"; `video.cutout` set on the camera clip only. The
  panel door: the same two steps.
- R4 every CO-83 sentence, exact, through `record_screen` (refused before any grant) and through
  `land_recording`; the project unchanged.
- R6 a landing into a document whose front track holds a clip after the playhead (pre-set with
  `set_video {scale: 0.5, x: 100}`) leaves that clip byte-identical.
- R7 with `canvas.fit_new_clips` false (a 1280 × 720 canvas), the screen's props equal an
  `add_clip` twin's.

`--mutant NAME` edits a `tree_copy.py` copy, builds its app and runs the mutant's rows on it:
`cutout-in-landing` (the cutout folded into the landing's step; R3), `default-rounded` (the tool's
default layout `corner_rounded`; R1) and `no-frame-duration` (the switch sent without `duration`;
R1b). CAUGHT exits 1, SURVIVED exits 0, a control that could not be performed exits 2.
"""

import argparse
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
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co8"
HOME = WORK / "home"
KEEP = {"media"}
CALL_BOUND = 600
BUILD_BOUND = 1500
SECOND = 600_000
FRAME = 20_000
SCREEN = (1920, 1080)
CAMERA = (640, 360)
ROWS = ["Z0", "R1", "R1b", "R2", "R3", "R4", "R6", "R7"]
LAYOUTS = {
    "corner_square": {"layout": "corner", "shape": "square"},
    "corner_rounded": {"layout": "corner", "shape": "rounded"},
    "corner_circle": {"layout": "corner", "shape": "circle"},
    "side_by_side": {"layout": "side_by_side"},
    "camera_full": {"layout": "camera_full"},
}
SENTENCES = {
    "voice": "With source voice_over, camera_layout cannot be given — a voice-over records the "
             "microphone alone.",
    "screen_layout": "With source screen, camera_layout needs camera — name the camera to record "
                     "beside the screen.",
    "screen_cutout": "With source screen, camera_cutout needs camera — name the camera to record "
                     "beside the screen.",
    "camera": "With source camera, camera_layout, camera_cutout cannot be given — a camera "
              "recording records the camera alone, at the camera's own format.",
    "layout_place": "camera_layout lays out the landed camera clips, so it needs place: true.",
    "cutout_place": "camera_cutout: true removes the landed camera clips' background, so it needs "
                    "place: true.",
    "movie": "camera cannot be given without movie — a camera lands beside the screen segment's "
             "movie.",
    "without": " cannot be given without camera — it applies to the camera's clips.",
}

CAMERA_FILE = "app/Sources/RecordingLanding+Camera.swift"
ARGS_FILE = "app/Sources/AgentServer+RecordingCamera.swift"
# name → (rows, [(path, anchor, replacement)])
MUTANTS = {
    "cutout-in-landing": (["R3"], [(
        CAMERA_FILE,
        "                to: &attempt, ops: &attemptOps)\n            trial = attempt\n",
        "                to: &attempt, ops: &attemptOps)\n"
        "            if result.choice.cameraCutout {\n"
        "                let cut = ReelOp.setVideo(\n"
        "                    clips: [placed.id], patch: VideoPatch(cutout: .some(CutoutProps())))\n"
        "                if let next = try attempt.applying(cut.scoped(scope)).project {\n"
        "                    attempt = next\n"
        "                    attemptOps.append(cut)\n"
        "                }\n"
        "            }\n"
        "            trial = attempt\n")]),
    "default-rounded": (["R1"], [(
        ARGS_FILE, "        return (layout ?? .cornerSquare, cutout)\n",
        "        return (layout ?? .cornerRounded, cutout)\n")]),
    "no-frame-duration": (["R1b"], [(
        CAMERA_FILE,
        "            corner: choice.corner, at: at, duration: frame, through: max(shown.end, clip.end))\n",
        "            corner: choice.corner, at: at, through: max(shown.end, clip.end))\n")]),
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


# ---- media ---------------------------------------------------------------------

def media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    made = {
        "screen.mov": ["-f", "lavfi", "-i",
                       f"testsrc=size={SCREEN[0]}x{SCREEN[1]}:rate=30:duration=20",
                       "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
                       "-g", "30", "-bf", "0"],
        "camera.mov": ["-f", "lavfi", "-i",
                       f"testsrc2=size={CAMERA[0]}x{CAMERA[1]}:rate=30:duration=8",
                       "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
                       "-g", "30", "-bf", "0"],
        "other.mov": ["-f", "lavfi", "-i", "testsrc=size=1280x720:rate=30:duration=4",
                      "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p"],
        "silence.m4a": ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "20",
                        "-c:a", "aac"],
    }
    for name, args in made.items():
        out = folder / name
        if not out.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", *args, str(out)], check=True,
                           timeout=300, env=bounded.child_env())
    return {name.split(".")[0]: folder / name for name in made}


def recording(files, tag):
    """One recording's files, copied per landing so each media path is its own."""
    folder = WORK / "rec" / tag
    folder.mkdir(parents=True, exist_ok=True)
    movie, camera = folder / "A.mov", folder / "A (Camera).mov"
    voice = folder / "A (Microphone).m4a"
    for source, dest in ((files["screen"], movie), (files["camera"], camera),
                         (files["silence"], voice)):
        if not dest.exists():
            shutil.copyfile(source, dest)
    return {"movie": str(movie), "camera": str(camera), "voice": [str(voice)]}


# ---- a document ----------------------------------------------------------------

class Doc:
    """One saved package on a 30 fps canvas."""

    def __init__(self, client, name, canvas=SCREEN, fit=True):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.close()
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        canvas_args = {"width": canvas[0], "height": canvas[1], "fps": [30, 1]}
        if not fit:
            canvas_args["fit_new_clips"] = False
        try:
            self.call("set_canvas", **canvas_args)
        except mcp.ToolError as error:
            if "made no change" not in str(error):
                raise
        self.canvas = canvas

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def undo_names(self, n):
        return [self.call("undo").get("undone") for _ in range(n)]

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def clip_of(state, path):
    ids = {m["id"] for m in state["media"] if m.get("path") == path}
    found = [c for c in state["clips"] if (c.get("source") or {}).get("media") in ids]
    return found[0] if len(found) == 1 else None


def twin_video(client, files, name, canvas=SCREEN, fit=True):
    """The `video` an `add_clip` of the screen movie gets on a fresh project."""
    doc = Doc(client, name, canvas, fit)
    try:
        m = doc.call("import_media", path=str(files["screen"]))["media"]
        tracks = doc.state()["tracks"]
        if not tracks:
            doc.call("add_track")
            tracks = doc.state()["tracks"]
        cid = doc.call("add_clip", track=tracks[-1]["id"], media=m, at=0)["new_clips"][0]
        return next(c for c in doc.state()["clips"] if c["id"] == cid).get("video")
    finally:
        doc.close()


def six(video):
    """A video group's six placement keys, defaults filled in."""
    crop = video.get("crop") or {}
    return [video.get("x", 0.0), video.get("y", 0.0), video.get("scale", 1.0),
            *[crop.get(k, 0.0) for k in ("l", "t", "r", "b")],
            video.get("corner_radius", 0.0), video.get("opacity", 1.0)]


def same(a, b):
    return all(abs(x - y) < 1e-9 for x, y in zip(a, b)) and len(a) == len(b)


def corner(canvas, source):
    """CAM-10 (3)'s corner, written out from the decision's own formula: x, y, scale."""
    (cw, ch), (sw, sh) = canvas, source
    s = min(max(min(0.25 * cw / sw, ch / (3 * sh)), 0.01), 10)
    return [round(cw / 2 - 0.05 * cw - sw * s / 2), round(ch / 2 - 0.05 * ch - sh * s / 2), s]


def stripped(actions):
    """Actions without their ids, for a comparison across two packages."""
    return [{k: v for k, v in a.items() if k != "id"} for a in actions or []]


def one_action(c, at):
    acts = c.get("actions") or []
    return (len(acts) == 1 and acts[0]["start"] == at and acts[0]["duration"] == FRAME,
            [(a["start"], a["duration"]) for a in acts])


def land(client, files, name, door="tool", canvas=SCREEN, fit=True, before=None, **extra):
    """A fresh package with the recording landed; (doc, answer, state, rec), the doc open."""
    doc = Doc(client, name, canvas, fit)
    if before:
        before(doc)
    rec = recording(files, name)
    args = dict(rec, **extra)
    if door == "panel":
        args["door"] = "panel"
    answer = doc.call("land_recording", **args)
    return doc, answer, doc.state(), rec


# ---- rows ----------------------------------------------------------------------

def r1(client, files):
    twin = twin_video(client, files, "r1-twin")
    for door in ("tool", "panel"):
        doc, _, state, rec = land(client, files, f"r1-{door}", door=door)
        try:
            cam, scr = clip_of(state, rec["camera"]), clip_of(state, rec["movie"])
            want = corner(SCREEN, CAMERA)
            cv = (cam or {}).get("video") or {}
            placed = cam is not None and [cv.get("x"), cv.get("y")] == want[:2] \
                and abs(cv.get("scale", 0) - want[2]) < 1e-12 \
                and same(six(cv)[3:], [0, 0, 0, 0, 0, 1])
            cam_one, cam_acts = one_action(cam or {}, 0)
            scr_one, scr_acts = one_action(scr or {}, 0)
            ends = cam_one and scr_one and all(
                same(six(c["actions"][0]["end"].get("video") or {}), six(c.get("video") or {}))
                for c in (cam, scr))
            check("R1", placed and (scr or {}).get("video") == twin and cam_one and scr_one
                  and ends,
                  f"{door}: camera {six(cv)} (want x, y, scale {want}); screen video "
                  f"{(scr or {}).get('video')} (twin {twin}); actions camera {cam_acts}, screen "
                  f"{scr_acts}; ends equal the bases {ends}")
        finally:
            doc.close()


def r1b(client, files):
    twin = twin_video(client, files, "r1b-twin")
    doc, _, state, rec = land(client, files, "r1b", camera_offset=2 * FRAME)
    try:
        cam, scr = clip_of(state, rec["camera"]), clip_of(state, rec["movie"])
        want = corner(SCREEN, CAMERA)
        cv = (cam or {}).get("video") or {}
        placed = cam is not None and [cv.get("x"), cv.get("y")] == want[:2] \
            and abs(cv.get("scale", 0) - want[2]) < 1e-12 \
            and cam["start"] - scr["start"] == 2 * FRAME
        cam_one, cam_acts = one_action(cam or {}, 0)
        scr_one, scr_acts = one_action(scr or {}, 2 * FRAME)
        check("R1b", placed and cam_one and scr_one and (scr or {}).get("video") == twin,
              f"camera at +{(cam or {}).get('start', 0) - (scr or {}).get('start', 0)} ticks, "
              f"{six(cv)}; actions camera {cam_acts}, screen {scr_acts}; screen video twin's "
              f"{(scr or {}).get('video') == twin}")
    finally:
        doc.close()


def r2(client, files):
    for layout, spelled in LAYOUTS.items():
        doc, _, state, rec = land(client, files, f"r2-{layout}", camera_layout=layout)
        try:
            cam, scr = clip_of(state, rec["camera"]), clip_of(state, rec["movie"])
        finally:
            doc.close()
        twin, _, tstate, trec = land(client, files, f"r2-{layout}-twin")
        try:
            tcam, tscr = clip_of(tstate, trec["camera"]), clip_of(tstate, trec["movie"])
            twin.call("switch_layout", camera=tcam["id"], screen=tscr["id"], at=tcam["start"],
                      duration=FRAME, through=max(tscr["start"] + tscr["duration"],
                                                  tcam["start"] + tcam["duration"]),
                      **spelled)
            tstate = twin.state()
            tcam, tscr = clip_of(tstate, trec["camera"]), clip_of(tstate, trec["movie"])
        finally:
            twin.close()
        equal = all(a is not None and b is not None and a.get("video") == b.get("video")
                    and stripped(a.get("actions")) == stripped(b.get("actions"))
                    for a, b in ((cam, tcam), (scr, tscr)))
        check("R2", equal,
              f"{layout}: camera {six((cam or {}).get('video') or {})} vs "
              f"{six((tcam or {}).get('video') or {})}, screen "
              f"{six((scr or {}).get('video') or {})} vs {six((tscr or {}).get('video') or {})}; "
              f"equal {equal}")


def r3(client, files):
    for door in ("tool", "panel"):
        doc, answer, state, rec = land(client, files, f"r3-{door}", door=door,
                                       camera_cutout=True)
        try:
            cam, scr = clip_of(state, rec["camera"]), clip_of(state, rec["movie"])
            cut = [c["id"] for c in state["clips"] if (c.get("video") or {}).get("cutout")]
            names = doc.undo_names(2)
            told = door == "panel" or (answer.get("camera_cutout") or {}).get("clips") == \
                [(cam or {}).get("id")]
            check("R3", cam is not None and cut == [cam["id"]] and scr is not None
                  and names == ["Remove Background", "Add Recording"] and told,
                  f"{door}: cut-out clips {cut} (camera {(cam or {}).get('id')}); undo {names}; "
                  f"answer {answer.get('camera_cutout')} / {answer.get('camera_cutout_error')}")
        finally:
            doc.close()


def refusal(body):
    try:
        body()
    except mcp.ToolError as error:
        text = str(error)
        return text.split(": ", 1)[1] if ": " in text else text
    return None


def r4(client, files):
    doc = Doc(client, "r4")
    try:
        before = doc.state()
        rec = recording(files, "r4")
        rows = [
            ("record_screen voice_over", "voice",
             lambda: doc.call("record_screen", seconds=1, source="voice_over",
                              camera_layout="side_by_side")),
            ("record_screen screen layout", "screen_layout",
             lambda: doc.call("record_screen", seconds=1, camera_layout="side_by_side")),
            ("record_screen screen cutout", "screen_cutout",
             lambda: doc.call("record_screen", seconds=1, camera_cutout=True)),
            ("record_screen camera", "camera",
             lambda: doc.call("record_screen", seconds=1, source="camera",
                              camera_layout="camera_full", camera_cutout=True)),
            ("record_screen layout place false", "layout_place",
             lambda: doc.call("record_screen", seconds=1, camera="probe camera", place=False,
                              camera_layout="camera_full")),
            ("record_screen cutout place false", "cutout_place",
             lambda: doc.call("record_screen", seconds=1, camera="probe camera", place=False,
                              camera_cutout=True)),
            ("land_recording camera without movie", "movie",
             lambda: doc.call("land_recording", voice=rec["voice"], camera=rec["camera"])),
            ("land_recording layout place false", "layout_place",
             lambda: doc.call("land_recording", place=False, camera_layout="side_by_side", **rec)),
            ("land_recording cutout place false", "cutout_place",
             lambda: doc.call("land_recording", place=False, camera_cutout=True, **rec)),
        ]
        for arg, value in (("camera_offset", 2), ("camera_layout", "camera_full"),
                           ("camera_cutout", True)):
            rows.append((f"land_recording {arg} without camera", arg,
                         lambda arg=arg, value=value: doc.call(
                             "land_recording", movie=rec["movie"], voice=rec["voice"],
                             **{arg: value})))
        for name, want, body in rows:
            said = refusal(body)
            expected = SENTENCES.get(want) or (want + SENTENCES["without"])
            check("R4", said == expected, f"{name}: {said!r}")
        unknown = refusal(lambda: doc.call("record_screen", seconds=1, camera="probe camera",
                                           camera_layout="stacked"))
        check("R4", bool(unknown) and "camera_layout" in unknown and "corner_square" in unknown,
              f"record_screen camera_layout stacked: {unknown!r}")
        check("R4", doc.state() == before, "the project unchanged by the refusals")
    finally:
        doc.close()


def r6(client, files):
    placed = {}

    def before(doc):
        tracks = doc.state()["tracks"]
        if not tracks:
            doc.call("add_track")
            tracks = doc.state()["tracks"]
        m = doc.call("import_media", path=str(files["other"]))["media"]
        cid = doc.call("add_clip", track=tracks[-1]["id"], media=m, at=25 * SECOND)["new_clips"][0]
        doc.call("set_video", clips=[cid], patch={"scale": 0.5, "x": 100})
        doc.call("set_playhead", t=0)
        placed["id"] = cid
        placed["clip"] = next(c for c in doc.state()["clips"] if c["id"] == cid)

    doc, _, state, rec = land(client, files, "r6", before=before, camera_layout="side_by_side")
    try:
        after = next((c for c in state["clips"] if c["id"] == placed["id"]), None)
        scr = clip_of(state, rec["movie"])
        front = scr is not None and scr["track"] == placed["clip"]["track"]
        check("R6", after == placed["clip"] and front,
              f"the earlier clip {placed['clip'].get('video')} → {(after or {}).get('video')}, "
              f"identical {after == placed['clip']}; the screen on its track {front}")
    finally:
        doc.close()


def r7(client, files):
    canvas = (1280, 720)
    twin = twin_video(client, files, "r7-twin", canvas, fit=False)
    doc, _, state, rec = land(client, files, "r7", canvas=canvas, fit=False)
    try:
        scr = clip_of(state, rec["movie"])
        fit = state.get("canvas", {}).get("fit_new_clips")
        check("R7", fit is False and (scr or {}).get("video") == twin,
              f"fit_new_clips {fit}; screen {(scr or {}).get('video')} (twin {twin})")
    finally:
        doc.close()


BODIES = [("R1", r1), ("R1b", r1b), ("R2", r2), ("R3", r3), ("R4", r4), ("R6", r6), ("R7", r7)]


def rows(client, files):
    for name, body in BODIES:
        if name in selected:
            attempt(lambda body=body: body(client, files), name)


# ---- launches ------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


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


# ---- mutants -------------------------------------------------------------------

def edited(name, root):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def run_mutant(name):
    global selected
    named, _ = MUTANTS[name]
    print(f"CO8 — the {name} MUTANT ({', '.join(named)} must FAIL)", flush=True)
    selected = set(named) | {"Z0"}
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
    if not with_instance(proof_app.executable(app), "mutant", lambda c: rows(c, files)):
        print(f"mutant {name}: the control could not be performed — the app did not listen")
        return 2
    if not set(named) & set(results):
        print(f"mutant {name}: the control could not be performed — its rows were never scored")
        return 2
    caught = [r for r in named if r in results and not all(ok for ok, _ in results[r])]
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(named)} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


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
        return run_mutant(args.mutant)

    print(f"CO8 — the camera's layout and cutout at record time ({proof_app.config()} build)",
          flush=True)
    files = media()
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    if args.socket:
        client = mcp.MCP(args.socket, timeout=CALL_BOUND)
        rows(client, files)
        parity(Path(args.socket).parent / "framejob.log", "the given instance")
    elif not with_instance(binary, "plain", lambda c: rows(c, files)):
        for row in selected - {"Z0"}:
            check(row, False, "the app did not listen")

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
