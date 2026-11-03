#!/usr/bin/env python3
"""Road map "creator-jobs" SW1 — `copy_pieces`, Clip ▸ Switch Angle ▸ and `switch_angle`
(spec §11 SW-10…SW-16).

    python3 tools/proof/switch_pieces_proof.py [SOCKET] [--only P1,P4,…] [--mutant NAME]
                                               [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the
rows launch their own instance on a scratch `CFFIXED_USER_HOME`. Packages and short media are
made under `tools/proof/work/sw1/` (ffmpeg's `testsrc`/`testsrc2`, 320 × 180 at 30 fps, each
file its own pattern or hue so two angles never draw the same frame). P5's two-hour angle is
generated into `tools/proof/media/creator/sw1/` (SW-16): one encoded minute stream-copied 120
times, never committed. A frame is 20 000 ticks. Every expected number is worked here from the
fixture (a clip's start, its file's `in`), never read back from the code under test.

Rows:
- Z1 `grep "Frame Job: "` of every instance's log prints nothing.
- P1 a 120 s angle at ×0.999 (drift-corrected) copied with `copy_pieces` onto a new track over
  three ranges; with the angle's track hidden, `render_frame` at five times inside them is
  byte-identical to the angle shown alone.
- P2 three program shots copied from Cam A; Clip ▸ Switch Angle ▸ Cam B by `perform_menu_item`
  on the middle one: one new clip of Cam B's file over the same span, `in` the span's start,
  the neighbours unchanged; one undo, named "Switch Angle", gives back `get_project` exactly.
- P3 `switch_angle` the same: the answer's keys in SW-15's order and the same piece; a track
  covering only part of the shot refused naming the first uncovered tick; an angle of two
  abutting files re-picking the shot across their join as two pieces, each from its own file.
- P4 the middle shot with a dissolve on its incoming edge, its outgoing edge and both (curve
  ease_in, audio on, s_curve): every overlap's span, kind, curve, audio and audio shape read
  back equal after `switch_angle`; an angle whose first piece is too short for the incoming
  overlap gives "Switch Angle (transition removed)", `transitions_removed` 1 and no overlap.
  P4d: the next shot C dissolves in from the shot and ramps down to its file's end, so its
  start cannot reach the shot's end: refused in the held-edge sentence, the project unchanged.
- P5 `copy_pieces` of 1,000 ranges of the two-hour angle: the median of five calls ≤ 0.5 s
  (over it, the figure is printed for the guide and a Performance candidate).

`--mutant NAME`: a core mutant edits a copy of `core/` (beside a link to `graphic/`) and runs
`cargo test --release --test copy_pieces`: CAUGHT when a test fails. An app mutant edits a
`tree_copy.py` copy's Swift and runs its rows on the copy's built app. CAUGHT exits 1, SURVIVED
exits 0, a control that could not be performed exits 2.
"""

import argparse
import os
import shutil
import statistics
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
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/sw1"
LONG = ROOT / "tools/proof/media/creator/sw1"
HOME = WORK / "home"
KEEP = {"media", "mutant-target"}
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 600
BUILD_BOUND = 1500
P5_LIMIT = 0.5
ROWS = ["Z1", "P1", "P2", "P3", "P4", "P5"]

PIECES = "core/src/edit_pieces.rs"
PLAN = "app/Sources/SwitchAngle.swift"
MENU = "app/Sources/EditorViewController+SwitchAngle.swift"
# name → (rows or core test prefixes, [(path, anchor, replacement)], "core" or "app")
MUTANTS = {
    "in-without-speed": (["a_clip_at_1_25", "a_ramp"], [(
        PIECES, "            piece.start = from;\n",
        "            piece.start = from;\n"
        "            if let (Source::Media { r#in, .. }, Source::Media { r#in: base, .. }) =\n"
        "                (&mut piece.source, &source.source)\n"
        "            {\n"
        "                *r#in = *base + (from - source.start);\n"
        "            }\n")], "core"),
    "occupancy-removed": (["an_occupied_destination"], [(
        PIECES, "        let holder = self.clips_on_track(track).into_iter().find(|held| {",
        "        let holder = self.clips_on_track(track).into_iter().filter(|_| false)"
        ".find(|held| {")], "core"),
    "link-kept": (["a_copy_of_a_linked_clip"], [(
        PIECES, "            piece.linked = None;\n", "")], "core"),
    "cover-not-required": (["P3"], [(
        PLAN, "        var reached = from\n",
        "        if from < to { return nil }\n        var reached = from\n")], "app"),
    "two-steps": (["P2"], [(
        MENU, "            document.applyEdit(plan.actionName, plan.ops)\n",
        # Two explicit groups: two `applyEdit`s in one menu action coalesce into one
        # undo step (`inUndoGroupIfRegistered`), so they would not be two steps.
        "            document.performGroupedEdit(plan.actionName, Array(plan.ops.prefix(1)))\n"
        "            document.performGroupedEdit(plan.actionName, Array(plan.ops.dropFirst()))\n")],
        "app"),
    "no-trim-back": (["P4"], [
        (PLAN, "        if let a = before, let first = pieces.first {",
         "        if false, let a = before, let first = pieces.first {"),
        (PLAN, "        if let c = after, !pieces.isEmpty {",
         "        if false, let c = after, !pieces.isEmpty {")], "app"),
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


def refused(body):
    """The tool's error text, or None when it applied."""
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


# ---- media -------------------------------------------------------------------------

def encode(out, source, seconds, audio=True):
    argv = ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
            f"{source}=size=320x180:rate=30:duration={seconds}"]
    if audio:
        argv += ["-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}",
                 "-c:a", "aac", "-shortest"]
    argv += ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-g", "30",
             str(out)]
    subprocess.run(argv, check=True, timeout=600, env=bounded.child_env())


def media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    recipes = {
        "a": ("testsrc", 20), "b": ("testsrc2", 20), "c": ("testsrc,hue=h=120", 20),
        "d1": ("testsrc,hue=h=200", 20), "d2": ("testsrc2,hue=h=60", 20),
        "drift": ("testsrc", 120),
    }
    made = {}
    for name, (source, seconds) in recipes.items():
        out = folder / f"{name}.mov"
        if not out.exists():
            if "," in source:
                pattern, extra = source.split(",", 1)
                argv = ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"{pattern}=size=320x180:rate=30:duration={seconds}", "-f", "lavfi",
                        "-i", f"sine=frequency=440:duration={seconds}", "-vf", extra,
                        "-c:a", "aac", "-shortest", "-c:v", "libx264", "-preset", "ultrafast",
                        "-pix_fmt", "yuv420p", "-g", "30", str(out)]
                subprocess.run(argv, check=True, timeout=600, env=bounded.child_env())
            else:
                encode(out, source, seconds)
        made[name] = out
    return made


def two_hours():
    """P5's angle (SW-16): one encoded minute, stream-copied 120 times."""
    LONG.mkdir(parents=True, exist_ok=True)
    out = LONG / "two_hours.mov"
    if out.exists():
        return out
    minute = LONG / "minute.mov"
    encode(minute, "testsrc", 60, audio=False)
    listing = LONG / "list.txt"
    listing.write_text("".join(f"file '{minute}'\n" for _ in range(120)))
    partial = LONG / "two_hours.partial.mov"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i",
                    str(listing), "-c", "copy", str(partial)],
                   check=True, timeout=600, env=bounded.child_env())
    partial.rename(out)
    return out


# ---- a document --------------------------------------------------------------------

class Doc:
    """One saved package on a 320 × 180, 30 fps canvas."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.close()  # one an earlier run left open
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            try:
                self.call("set_canvas", width=320, height=180, fps=[30, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):
                    raise
            self.media = {}
        except Exception:
            self.close()
            raise

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def track(self, name):
        return self.call("add_track", name=name)["new_tracks"][0]

    def place(self, path, track, at=0):
        key = str(path)
        if key not in self.media:
            self.media[key] = self.call("import_media", path=key)["media"]
        return self.call("add_clip", track=track, media=self.media[key], at=at)["new_clips"][0]

    def clip(self, cid, state=None):
        return next(c for c in (state or self.state())["clips"] if c["id"] == cid)

    def on_track(self, track, state=None):
        state = state or self.state()
        return sorted((c for c in state["clips"] if c["track"] == track),
                      key=lambda c: c["start"])

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def doc_row(client, name, body, rows):
    doc = attempt(lambda: Doc(client, name), *rows)
    if doc is None:
        return
    try:
        attempt(lambda: body(doc), *rows)
    finally:
        doc.close()


def end(clip):
    return clip["start"] + clip["duration"]


def source(clip):
    return clip["source"].get("media"), clip["source"].get("in")


class Program:
    """Cam A and Cam B (20 s each, from 0) and a Program track holding three shots copied from
    Cam A over 0–5 s, 5–10 s and 10–15 s; `shots` are their ids in time order."""

    def __init__(self, doc, files):
        self.doc = doc
        self.cam_a = doc.track("Cam A")
        self.cam_b = doc.track("Cam B")
        self.program = doc.track("Program")
        self.a = doc.place(files["a"], self.cam_a)
        self.b = doc.place(files["b"], self.cam_b)
        doc.call("copy_pieces", clip=self.a, track=self.program,
                 ranges=[[0, t(5)], [t(5), t(10)], [t(10), t(15)]])
        self.shots = [c["id"] for c in doc.on_track(self.program)]

    def media_of(self, clip_id, state=None):
        return self.doc.clip(clip_id, state)["source"]["media"]


# ---- P1 ----------------------------------------------------------------------------

def p1(doc, files):
    angle_track = doc.track("Angle")
    angle = doc.place(files["drift"], angle_track)
    doc.call("set_speed", clip=angle, rate=0.999)
    program = doc.track("Program")
    times = [60.5, 61.9, 92.0, 101.0, 109.0]
    alone = []
    for i, s in enumerate(times):
        path = WORK / f"p1-alone-{i}.png"
        doc.call("render_frame", t=t(s), path=str(path))
        alone.append(path.read_bytes())
    doc.call("copy_pieces", clip=angle, track=program,
             ranges=[[t(60), t(62)], [t(90), t(95)], [t(100), t(110)]])
    pieces = doc.on_track(program)
    doc.call("set_track", track=angle_track, hidden=True)
    same = []
    for i, s in enumerate(times):
        path = WORK / f"p1-piece-{i}.png"
        doc.call("render_frame", t=t(s), path=str(path))
        same.append(path.read_bytes() == alone[i])
    check("P1", len(pieces) == 3 and all(same),
          f"{len(pieces)} pieces; byte-identical at {times}: {same}")


# ---- P2 ----------------------------------------------------------------------------

def repicked(prog, before, after, angle_media, cut=(5, 10)):
    """The middle shot replaced by one clip of `angle_media` over its span, `in` the span's
    start (the angle's clip runs from 0 with `in` 0), the other shots unchanged."""
    shots = prog.doc.on_track(prog.program, after)
    first, last = prog.doc.clip(prog.shots[0], before), prog.doc.clip(prog.shots[2], before)
    middle = [c for c in shots if c["id"] not in (first["id"], last["id"])]
    return (len(shots) == 3 and len(middle) == 1 and middle[0]["start"] == t(cut[0])
            and end(middle[0]) == t(cut[1]) and source(middle[0]) == (angle_media, t(cut[0]))
            and prog.doc.clip(first["id"], after) == first
            and prog.doc.clip(last["id"], after) == last), middle


def p2(doc, files):
    prog = Program(doc, files)
    before = doc.state()
    b_media = prog.media_of(prog.b, before)
    doc.call("set_selection", clips=[prog.shots[1]])
    doc.call("perform_menu_item", path=["Clip", "Switch Angle", "Cam B"])
    after = doc.state()
    ok, middle = repicked(prog, before, after, b_media)
    undone = doc.call("undo").get("undone")
    back = doc.state() == before
    check("P2", ok and undone == "Switch Angle" and back,
          f"the shot re-picked from Cam B over 5–10 s {ok} ({[source(c) for c in middle]}); "
          f"one undo named {undone!r} gives back the project {back}")


# ---- P3 ----------------------------------------------------------------------------

def p3(doc, files):
    prog = Program(doc, files)
    before = doc.state()
    shot = prog.shots[1]
    answer = doc.call("switch_angle", clip=shot, angle=prog.cam_b)
    after = doc.state()
    keys = list(answer.keys())
    ok, middle = repicked(prog, before, after, prog.media_of(prog.b, before))
    named = answer.get("step") == "Switch Angle" and answer.get("transitions_removed") == 0 \
        and answer.get("pieces") == [c["id"] for c in middle]
    check("P3", ok and named and keys == ["ok", "step", "pieces", "transitions_removed",
                                          "project"],
          f"re-picked {ok}; keys {keys}; step {answer.get('step')!r}, pieces "
          f"{answer.get('pieces')}")
    doc.call("undo")
    # A track covering only 0–6 s: the shot (5–10 s) is uncovered from 6 s.
    cam_c = doc.track("Cam C")
    partial = doc.place(files["c"], cam_c)
    doc.call("trim_end", clip=partial, to=t(6))
    why = refused(lambda: doc.call("switch_angle", clip=shot, angle=cam_c))
    want = (f"track {cam_c} does not cover clip {shot}: nothing with a picture plays on it at "
            f"tick {t(6)}")
    check("P3", why is not None and want in why and doc.clip(shot) == prog.doc.clip(shot, before),
          f"a partial angle refused: {why!r}")
    # Two abutting files, joined at 7.5 s.
    cam_d = doc.track("Cam D")
    d1 = doc.place(files["d1"], cam_d)
    doc.call("trim_end", clip=d1, to=t(7.5))
    d2 = doc.place(files["d2"], cam_d, at=t(7.5))
    state = doc.state()
    d1_media, d2_media = doc.clip(d1, state)["source"]["media"], \
        doc.clip(d2, state)["source"]["media"]
    answer = doc.call("switch_angle", clip=shot, angle=cam_d)
    after = doc.state()
    pieces = [doc.clip(p, after) for p in answer.get("pieces", [])]
    spans = [(c["start"], end(c), source(c)) for c in pieces]
    want = [(t(5), t(7.5), (d1_media, t(5))), (t(7.5), t(10), (d2_media, 0))]
    check("P3", spans == want, f"across the join: {spans}")


# ---- P4 ----------------------------------------------------------------------------

STYLE = {"curve": "ease_in", "audio": True, "audio_shape": "s_curve"}


def edges(doc, track, state):
    """Every overlap on `track`: (incoming start, outgoing end, kind, curve, audio, shape)."""
    clips = doc.on_track(track, state)
    out = []
    for before, after in zip(clips, clips[1:]):
        if end(before) > after["start"]:
            tr = after.get("transition_in") or {}
            out.append((after["start"], end(before), tr.get("kind", "cross_dissolve"),
                        tr.get("curve", "linear"), tr.get("audio", False),
                        tr.get("audio_shape", "plus_3db")))
    return out


def dissolved(doc, files, which):
    prog = Program(doc, files)
    for index in which:  # 1: into the middle shot, 2: out of it
        clip = prog.shots[index]
        doc.call("add_transition", clip=clip, duration=10 * FRAME)
        doc.call("set_transition_style", clip=clip, **STYLE)
    return prog


def p4_case(client, files, name, which):
    doc = Doc(client, name)
    try:
        prog = dissolved(doc, files, which)
        before = doc.state()
        want = edges(doc, prog.program, before)
        answer = doc.call("switch_angle", clip=prog.shots[1], angle=prog.cam_b)
        got = edges(doc, prog.program, doc.state())
        check("P4", len(want) == len(which) and got == want
              and answer.get("step") == "Switch Angle"
              and answer.get("transitions_removed") == 0,
              f"{name}: overlaps before {want}, after {got}; step {answer.get('step')!r}")
    finally:
        doc.close()


def p4_removed(client, files):
    doc = Doc(client, "p4-removed")
    try:
        prog = dissolved(doc, files, [1])
        shot = doc.clip(prog.shots[1])
        s = shot["start"]
        cam_e = doc.track("Cam E")
        e1 = doc.place(files["b"], cam_e)
        doc.call("trim_end", clip=e1, to=s + 12 * FRAME)
        doc.place(files["c"], cam_e, at=s + 12 * FRAME)
        answer = doc.call("switch_angle", clip=shot["id"], angle=cam_e)
        state = doc.state()
        first = doc.clip(prog.shots[0], state)
        pieces = [doc.clip(p, state) for p in answer.get("pieces", [])]
        ok = (answer.get("step") == "Switch Angle (transition removed)"
              and answer.get("transitions_removed") == 1 and len(pieces) == 2
              and end(first) == s and pieces[0]["start"] == s
              and not pieces[0].get("transition_in")
              and edges(doc, prog.program, state) == [])
        check("P4", ok, f"a 12-frame first piece against a 10-frame dissolve: step "
              f"{answer.get('step')!r}, removed {answer.get('transitions_removed')}, the shot "
              f"before ends at {end(first)} (the span starts at {s}), overlaps "
              f"{edges(doc, prog.program, state)}")
    finally:
        doc.close()


def p4_held(client, files):
    """P4d: C dissolves in from B and ramps down to its file's end."""
    doc = Doc(client, "p4-held")
    try:
        cam_b = doc.track("Cam B")
        program = doc.track("Program")
        doc.place(files["b"], cam_b)
        b = doc.place(files["a"], program)
        doc.call("trim_end", clip=b, to=t(10))
        c = doc.place(files["c"], program, at=t(10))
        doc.call("trim_start", clip=c, to=t(10.5))
        doc.call("move_clip", clips=[c], delta=-t(0.5))
        doc.call("add_transition", clip=c, duration=10 * FRAME)
        doc.call("add_speed_ramp", clip=c, shape="ramp_down", rate=0.5,
                 **{"from": t(4), "to": t(7)})
        doc.call("trim_end", clip=c, to=t(60))
        before = doc.state()
        shot = doc.clip(b, before)
        why = refused(lambda: doc.call("switch_angle", clip=b, angle=cam_b))
        prefix = f"clip {c}'s edge is held at tick "
        tail = f", short of tick {end(shot)}, so clip {b} cannot be re-picked"
        check("P4", why is not None and prefix in why and tail in why
              and doc.state() == before,
              f"P4d: {why!r}; unchanged {doc.state() == before}")
    finally:
        doc.close()


def p4(client, files):
    for name, which in (("p4-in", [1]), ("p4-out", [2]), ("p4-both", [1, 2])):
        attempt(lambda n=name, w=which: p4_case(client, files, n, w), "P4")
    attempt(lambda: p4_removed(client, files), "P4")
    attempt(lambda: p4_held(client, files), "P4")


# ---- P5 ----------------------------------------------------------------------------

def p5(doc):
    angle_track = doc.track("Angle")
    angle = doc.place(two_hours(), angle_track)
    dest = doc.track("Program")
    ranges = [[t(i * 7.2), t(i * 7.2 + 3)] for i in range(1000)]
    times = []
    count = 0
    for run in range(5):
        started = time.perf_counter()
        doc.call("copy_pieces", clip=angle, track=dest, ranges=ranges)
        times.append(time.perf_counter() - started)
        if run == 0:
            count = len(doc.on_track(dest))
        doc.call("undo")
    median = statistics.median(times)
    print(f"  P5 copy_pieces of 1,000 ranges: {', '.join(f'{x:.3f}' for x in times)} s; "
          f"median {median:.3f} s", flush=True)
    check("P5", count == 1000 and median <= P5_LIMIT,
          f"{count} pieces; median of five {median:.3f} s (limit {P5_LIMIT} s)")


# ---- launches ----------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def plain_rows(client, files):
    if "P1" in selected:
        doc_row(client, "p1", lambda d: p1(d, files), ["P1"])
    if "P2" in selected:
        doc_row(client, "p2", lambda d: p2(d, files), ["P2"])
    if "P3" in selected:
        doc_row(client, "p3", lambda d: p3(d, files), ["P3"])
    if "P4" in selected:
        attempt(lambda: p4(client, files), "P4")
    if "P5" in selected:
        doc_row(client, "p5", p5, ["P5"])


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
    run = subprocess.run(["cargo", "test", "--release", "--test", "copy_pieces"],
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
    print(f"SW1 — the {name} MUTANT ({', '.join(named)} must FAIL)", flush=True)
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
    if not with_instance(proof_app.executable(app), "mutant", lambda c: plain_rows(c, files)):
        print(f"mutant {name}: the control could not be performed — the app did not listen")
        return 2
    row = named[0]
    if row not in results:
        print(f"mutant {name}: the control could not be performed — {row} was never scored")
        return 2
    caught = not all(ok for ok, _ in results[row])
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {row} "
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

    print(f"SW1 — copy pieces and Switch Angle ({proof_app.config()} build)", flush=True)
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
            for row in selected - {"Z1"}:
                check(row, False, "the app did not listen")

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
