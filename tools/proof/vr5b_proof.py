#!/usr/bin/env python3
"""Road map "creator-jobs" VR5b — a screen and its camera re-laid in a vertical version (spec §11
VR-53, VR-54, VR-56).

    python3 tools/proof/vr5b_proof.py [--only R1,R2,…] [--mutant NAME] [--app PATH]

The fixture: two ffmpeg `testsrc` 1920 × 1080 30 fps 30 s movies, the screen on the back track
and the camera on a track in front, a 1920 × 1080 30 fps canvas, and three `switch_layout`
calls on the camera — Corner at 0, Side by Side at 10 s for 1 s `linear`, Camera Full at 20 s.
A REFERENCE is the same two movies placed on a 1080 × 1920 (or 1080 × 1080) canvas and switched
there directly: Corner, Stacked (Side by Side on 1:1), Camera Full. One launch on a scratch
`CFFIXED_USER_HOME`; nothing is analysed.

Rows:
- R1 The 9:16 copy (`make_vertical_version {shape: "9:16", path}`) holds, per role, three
  layout actions (ends naming all six placement keys) at the source's starts, durations and
  curves, each end equal to the 1080 × 1920 reference's (nine numbers within 1e-9), Stacked's
  for Side by Side's.
- R2 The 1:1 copy equals its 1080 × 1080 reference the same way, Side by Side kept.
- R3 In the 9:16 copy no role clip has an action whose end's `video` is exactly {scale, x, y},
  no clip is named "Blurred Background", no track "Backgrounds" is left, both entries are
  `relaid`, and the answer's `cached` is true (nothing was analysed: a re-laid role is never a
  picture to follow).
- R4 The screen split at 25 s (`split`; the half's `in` advanced), then the Side by Side camera
  end's x moved 40 px (`set_action_end`): `reframe_clip {follow: "layout", from_width: 1920,
  from_height: 1080}` is refused in VR-53's sentence naming that action, and the 9:16 copy lists
  the camera, the screen and the split half `not_followed` with the hand-edit reason (the half
  classed `layoutPiece` by `VerticalVersion.sameSource`), none with a framing action.
- R5 `render_frame` at 5 s, 15 s and 25 s of the 9:16 copy equals the reference's, byte for
  byte.
- R6 The 9:16 summary's first line has " Re-lays 3 camera layouts" and the next three lines are
  the three switches (Corner; Side by Side → Stacked; Camera Full); `relaid` holds them with
  their camera, at, from, to and the corner's shape.
- R7 (`vr5b_probe.swift`) `layoutName` of every `menuRows` end the core makes on 1920 × 1080
  and 1080 × 1080, with a 1920 × 1080 and a 1280 × 720 camera, is that row, each
  `isLayoutAction`; a zoom end is not one.
- Z1 `grep "Frame Job: "` of the instance's log prints nothing.

`--mutant NAME` (tools/proof/README.md's VR5b section): the named decision broken. A `core`
mutant runs the named core test on a copy of `core/`; an `app` mutant builds a `tree_copy.py`
copy (its `core/` a real copy when the edit is the core's) and runs its rows. CAUGHT exits 1,
SURVIVED exits 0, a control that could not be performed exits 2.
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

WORK = ROOT / "tools/proof/work/vr5b-proof"
HOME = WORK / "home"
CALL_BOUND = 400
BUILD_BOUND = 1500
SEC = 600_000
FRAME = 20_000
ROWS = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "Z1"]
SIX = {"x", "y", "scale", "crop", "corner_radius", "opacity"}
HAND = "its camera layout was edited by hand, so it is kept as placed"
UNMADE = ("clip {clip}'s layout action {action} at 00:00:10:00 is not a camera layout Frame Job "
          "made on the 1920 × 1080 canvas, so it cannot be re-laid; keep its clips as placed")

RECOGNISE = "core/src/layout_recognise.rs"
REPLAY = "core/src/reframe_layout.rs"
CLASSES = "app/Sources/VerticalVersion.swift"
TWO_B = "        if let laid = layoutRole(of: clip, in: snapshot, order: order) { return laid }\n"
TIMING = "            let (duration, curve) = switch_timing(&timed);"
# name → (rows, [(path, anchor, replacement)], "core" or "app")
MUTANTS = {
    "two-b-after-three": (["R3", "R4"], [
        (CLASSES, TWO_B, ""),
        (CLASSES, "        return .other\n    }\n\n    /// (1)'s partner",
         TWO_B + "        return .other\n    }\n\n    /// (1)'s partner"),
    ], "app"),
    "side-by-side-kept": (["three_switches_replayed_on_each_canvas_equal_the_direct_switches"], [
        (REPLAY, "if tall && choice.layout == CameraLayout::SideBySide {",
         "if false && tall && choice.layout == CameraLayout::SideBySide {")], "core"),
    "tolerance-50": (["R4"], [
        (RECOGNISE, "pub(crate) const RECOGNISE_PX: f64 = 1.0;",
         "pub(crate) const RECOGNISE_PX: f64 = 50.0;")], "app"),
    "duration-default": (["three_switches_replayed_on_each_canvas_equal_the_direct_switches"], [
        (REPLAY, TIMING,
         "            let (_, curve) = switch_timing(&timed);\n"
         "            let duration = DEFAULT_SWITCH;")], "core"),
    "later-unfiltered": (["split_screens_are_re_based_and_another_media_is_left_alone"], [
        (REPLAY, "later: pieces.iter().filter_map(|id| next.clip(*id)).collect(),",
         "later: next.role(kind, next.clip(act.clip)?, act.at, None).later,")], "core"),
    "zoom-keep-rule": (["a_zoom_on_a_corner_screen_keeps_its_point_in_the_picture"], [
        (REPLAY, "                    conjugate(end, &was, &now);",
         "                    let _ = (&was, &now);\n"
         "                    for (k, r) in [(\"x\", w), (\"y\", h), (\"scale\", w.min(h))] {\n"
         "                        if let Some(v) = end.get(k).and_then(Value::as_f64) {\n"
         "                            end.insert(k.into(), Value::from(v * r));\n"
         "                        }\n"
         "                    }")], "core"),
    "timing-camera": (["a_camera_starting_late_keeps_its_cut_and_the_screen_its_glide"], [
        (REPLAY, TIMING,
         "            let (duration, curve) = (timed[0].1.duration, timed[0].1.curve);")],
        "core"),
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


# ---- the fixture ---------------------------------------------------------------------

def movies():
    folder = WORK.parent / "vr5b-media"
    folder.mkdir(parents=True, exist_ok=True)
    made = {}
    for name in ("screen", "camera"):
        out = folder / f"{name}.mov"
        if not out.exists():
            partial = out.with_suffix(".partial.mov")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                            "testsrc=size=1920x1080:rate=30:duration=30", "-c:v", "libx264",
                            "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-g", "30",
                            str(partial)], check=True, timeout=600, env=bounded.child_env())
            partial.rename(out)
        made[name] = out
    return made


class Doc:
    """One saved package: the screen on the back track, the camera in front, three switches."""

    def __init__(self, client, files, name, canvas=(1920, 1080), middle="side_by_side"):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            self.call("set_canvas", width=canvas[0], height=canvas[1], fps=[30, 1])
        except mcp.ToolError as error:
            if "no change" not in str(error):
                raise
        self.screen = self.place(files["screen"], 0)
        self.camera = self.place(files["camera"], 1)
        self.call("switch_layout", camera=self.camera, layout="corner", at=0)
        self.call("switch_layout", camera=self.camera, layout=middle, at=10 * SEC,
                  duration=SEC, curve="linear")
        self.call("switch_layout", camera=self.camera, layout="camera_full", at=20 * SEC)
        self.call("save_project")

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

    def vertical(self, shape, tag):
        path = WORK / f"{self.path.stem}-{tag}.framejob"
        if path.exists():
            shutil.rmtree(path)
        answer = self.call("make_vertical_version", shape=shape, path=str(path))
        state = self.client.call_with("get_project", {"project": str(path)})["project"]
        return answer, state, path

    def close(self):
        for path in [self.path] + sorted(WORK.glob(f"{self.path.stem}-*.framejob")):
            try:
                self.client.call("close_project", project=str(path), discard=True)
            except mcp.ToolError:
                pass


def clip_of(state, clip):
    return next(c for c in state["clips"] if c["id"] == clip)


def layouts(clip):
    """The clip's layout actions, by start."""
    return sorted((a for a in clip.get("actions", [])
                   if SIX <= set(((a.get("end") or {}).get("video") or {}))),
                  key=lambda a: a["start"])


def nine(video):
    crop = video.get("crop") or {}
    return [video["x"], video["y"], video["scale"], crop.get("l", 0), crop.get("t", 0),
            crop.get("r", 0), crop.get("b", 0), video["corner_radius"], video["opacity"]]


def same_roles(copy, ref, source, pairs, row):
    """Per role (copy id, reference id): three layout actions at the source's timing, ends equal
    to the reference's."""
    for got_id, want_id in pairs:
        got = layouts(clip_of(copy, got_id))
        want = layouts(clip_of(ref, want_id))
        was = layouts(clip_of(source, got_id))
        timing = [(a["start"], a["duration"], a.get("curve")) for a in got]
        problems = []
        if len(got) != 3 or len(want) != 3:
            problems.append(f"{len(got)} layout actions, the reference {len(want)}")
        if timing != [(a["start"], a["duration"], a.get("curve")) for a in was]:
            problems.append(f"timing {timing}, the source "
                            f"{[(a['start'], a['duration'], a.get('curve')) for a in was]}")
        for g, w in zip(got, want):
            a, b = nine(g["end"]["video"]), nine(w["end"]["video"])
            if any(abs(x - y) > 1e-9 for x, y in zip(a, b)):
                problems.append(f"at {g['start'] / SEC} s {a} want {b}")
        check(row, not problems, f"clip {got_id}: " + ("; ".join(problems) or
                                                      f"3 layout actions, timing {timing}"))


def zooms(clip):
    return [a for a in clip.get("actions", [])
            if set(((a.get("end") or {}).get("video") or {})) == {"scale", "x", "y"}]


def timecode(canvas, ticks):
    seconds = ticks // SEC
    frames = (ticks % SEC) // FRAME
    if canvas.get("timecode_frames", True):
        return f"00:00:{seconds:02d}:{frames:02d}"
    return f"00:00:{seconds:02d}.{(ticks % SEC) * 1000 // SEC:03d}"


# ---- the rows ----------------------------------------------------------------------------

def layout_rows(client, files):
    source = Doc(client, files, "source")
    tall = Doc(client, files, "ref-tall", canvas=(1080, 1920), middle="stacked")
    square = Doc(client, files, "ref-square", canvas=(1080, 1080))
    try:
        before = source.state()
        answer, copy, path = source.vertical("9:16", "tall")
        ref = tall.state()
        pairs = [(source.screen, tall.screen), (source.camera, tall.camera)]
        attempt(lambda: same_roles(copy, ref, before, pairs, "R1"), "R1")

        def r2():
            _, sq, _ = source.vertical("1:1", "square")
            same_roles(sq, square.state(), before,
                       [(source.screen, square.screen), (source.camera, square.camera)], "R2")
        attempt(r2, "R2")

        def r3():
            roles = [clip_of(copy, source.screen), clip_of(copy, source.camera)]
            zoomed = [c["id"] for c in roles if zooms(c)]
            blurred = [c["id"] for c in copy["clips"] if c.get("name") == "Blurred Background"]
            tracks = [t["name"] for t in copy["tracks"] if t.get("name") == "Backgrounds"]
            entries = {e["clip"]: e["treatment"] for e in answer["clips"]}
            want = {source.screen: "relaid", source.camera: "relaid"}
            ok = (not zoomed and not blurred and not tracks and entries == want
                  and answer.get("cached") is True)
            check("R3", ok, f"zoomed {zoomed}, blurred {blurred}, Backgrounds {tracks}, "
                            f"entries {entries}, cached {answer.get('cached')}")
        attempt(r3, "R3")

        def r5():
            for seconds in (5, 15, 25):
                frames = []
                for project, tag in ((path, "copy"), (tall.path, "ref")):
                    out = WORK / "frames" / f"{tag}-{seconds}.png"
                    out.parent.mkdir(parents=True, exist_ok=True)
                    client.call_with("render_frame", {"project": str(project),
                                                      "t": seconds * SEC, "path": str(out)})
                    frames.append(out.read_bytes())
                check("R5", frames[0] == frames[1],
                      f"{seconds} s: {len(frames[0])} and {len(frames[1])} bytes, "
                      f"{'identical' if frames[0] == frames[1] else 'different'}")
        attempt(r5, "R5")

        def r6():
            canvas = copy["canvas"]
            lines = answer["summary"].split("\n")
            want = [f"Re-laid: Corner at {timecode(canvas, 0)}.",
                    f"Re-laid: Side by Side → Stacked at {timecode(canvas, 10 * SEC)}.",
                    f"Re-laid: Camera Full at {timecode(canvas, 20 * SEC)}."]
            cam = source.camera
            fields = [{"camera": cam, "at": 0, "from": "corner", "to": "corner",
                       "shape": "square"},
                      {"camera": cam, "at": 10 * SEC, "from": "side_by_side", "to": "stacked"},
                      {"camera": cam, "at": 20 * SEC, "from": "camera_full",
                       "to": "camera_full"}]
            ok = (" Re-lays 3 camera layouts for the new canvas." in lines[0]
                  and lines[1:4] == want and answer.get("relaid") == fields)
            check("R6", ok, f"lines {lines[:4]}; relaid {answer.get('relaid')}")
        attempt(r6, "R6")
    finally:
        for doc in (source, tall, square):
            doc.close()


def hand_row(client, files):
    doc = Doc(client, files, "hand")
    try:
        doc.call("split", clips=[doc.screen], at=25 * SEC)
        state = doc.state()
        halves = sorted((c for c in state["clips"] if c["track"] == clip_of(state, doc.screen)
                         ["track"]), key=lambda c: c["start"])
        half = halves[1]
        if half["source"].get("in") != 25 * SEC:
            raise RuntimeError(f"the split half's in is {half['source'].get('in')}")
        action = next(a for a in layouts(clip_of(state, doc.camera)) if a["start"] == 10 * SEC)
        video = dict(action["end"]["video"])
        video["x"] = video["x"] + 40
        doc.call("set_action_end", clip=doc.camera, action=action["id"],
                 patch={"video": video})
        sentence = UNMADE.format(clip=doc.camera, action=action["id"])
        try:
            doc.call("reframe_clip", clip=doc.camera, follow="layout", from_width=1920,
                     from_height=1080)
            check("R4", False, "reframe_clip {follow: layout} applied")
        except mcp.ToolError as error:
            check("R4", str(error).endswith(sentence), f"refused: {str(error)[-200:]}")
        answer, copy, _ = doc.vertical("9:16", "tall")
        entries = {e["clip"]: (e["treatment"], e.get("reason")) for e in answer["clips"]}
        want = {c: ("not_followed", HAND) for c in (doc.screen, doc.camera, half["id"])}
        framed = [c for c in want if zooms(clip_of(copy, c))]
        check("R4", entries == want and not framed,
              f"entries {entries}; with a framing action {framed}")
    finally:
        doc.close()


# ---- the probe ------------------------------------------------------------------------

def probe_row():
    here = WORK / "probe"
    here.mkdir(parents=True, exist_ok=True)
    entry = here / "main.swift"
    shutil.copyfile(HERE / "vr5b_probe.swift", entry)
    binary = here / "vr5b-probe"
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        check("R7", False, "the probe did not build: "
              + ("; ".join(error.diagnostics[:8]) or str(error)))
        return
    run = subprocess.run([str(binary), str(here / "files"), "main"], capture_output=True,
                         text=True, timeout=600)
    (here / "stderr.txt").write_text(run.stderr)
    if run.returncode != 0:
        check("R7", False, f"the probe exited {run.returncode}: {run.stderr[-300:]}")
        return
    for entry in json.loads(run.stdout)["rows"]:
        check(entry["id"], entry["pass"], entry["detail"])


# ---- the launch ----------------------------------------------------------------------

def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def run_launch(binary, files):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in sorted(selected - {"Z1", "R7"}):
                check(row, False, "the app did not listen")
        else:
            print(f"  instance PID {launched.child.pid}", flush=True)
            if selected & {"R1", "R2", "R3", "R5", "R6"}:
                attempt(lambda: layout_rows(launched.client, files), "R1", "R2", "R3", "R5",
                        "R6")
            if "R4" in selected:
                attempt(lambda: hand_row(launched.client, files), "R4")
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
    """The core's VR5b tests on a copy of `core/` with the mutant's edits: the failing tests'
    names, or None and the reason the control could not be performed."""
    copy = WORK.parent / "vr5b-mutant-core"
    if copy.exists():
        tree_copy.remove_tree(str(copy))
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "core", copy / "core", ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "graphic", copy / "graphic")
    why = edit(copy, name)
    if why:
        return None, why
    env = bounded.child_env({"CARGO_TARGET_DIR": str(WORK.parent / "vr5b-mutant-target")})
    run = subprocess.run(["cargo", "test", "--release", "--test", "reframe_layout",
                          "--test", "layout"], cwd=copy / "core", capture_output=True,
                         text=True, timeout=BUILD_BOUND, env=env)
    (WORK.parent / f"vr5b-mutant-{name}.log").write_text(run.stdout + run.stderr)
    failed = [line.split()[1] for line in run.stdout.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    if run.returncode != 0 and not failed:
        return None, "cargo test did not run the tests (see the log)"
    return failed, None


def mutant_app(name):
    """A `tree_copy.py` copy — for a core edit its `core/` a real copy — built as
    `proof_app.config()` chooses."""
    made, reason = tree_copy.make_copy(str(WORK.parent / "vr5b-mutant"))
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


def run_mutant(name, files):
    global selected
    rows, _, kind = MUTANTS[name]
    print(f"VR5b — the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    if kind == "core":
        failed, why = core_mutant(name)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        caught = [t for t in rows if t in failed]
        print(f"failing tests: {failed or 'none'}")
        print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    binary, why = mutant_app(name)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    selected = set(rows)
    run_launch(binary, files)
    if not set(rows) & set(results):
        print(f"mutant {name}: the control could not be performed — its rows were never scored")
        return 2
    caught = [r for r in rows if r in results and not all(ok for ok, _ in results[r])]
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(caught or rows)} "
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
    files = movies()
    if args.mutant:
        return run_mutant(args.mutant, files)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"VR5b — a screen and its camera re-laid in a vertical version "
          f"({proof_app.config()} build)", flush=True)
    if "R7" in selected:
        attempt(probe_row, "R7")
    run_launch(binary, files)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
