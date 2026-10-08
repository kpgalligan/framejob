#!/usr/bin/env python3
"""Issue batch B87 phase 2 (#239; spec §11 G-34) — an action that animates a
graphic clip's props, over MCP: `set_action_end`'s door fills `schema` from
the clip's module, and the evaluated props reach `render_frame`, a
`prores_422` export (the prefetch on and off) and undo.

    python3 tools/proof/graphic_prop_action_proof.py [--app PATH]
    python3 tools/proof/graphic_prop_action_proof.py --mutant recipe-stored-props
    python3 tools/proof/graphic_prop_action_proof.py --mutant handler-no-schema

Launches the Release build on scratch sockets of its own, one instance at a
time, and stops only those processes. **Every instance runs in a scratch
home**, `CFFIXED_USER_HOME=tools/proof/work/graphic-prop-action/home`, and
every package and movie is under `tools/proof/work/graphic-prop-action/`,
which is removed at the start and at exit. No menu item is performed. Every
call is bounded (`CALL_BOUND`), every ffmpeg decode too (120 s).

The module, `ramp`, draws one rectangle from its props: `x` (number,
default 64, 0–1000), `fill` (color, default #ff0000) and `mode` (string,
default "A"; "B" makes the rectangle 300 tall instead of 100). Its v2 lowers
`x`'s max to 100 and adds `h` (number, default 10, 0–50); its v3 does not
compile. The canvas is 640×360 at 30 fps; the graphic clip runs 0–2 s and
its action 0.5–1.5 s, linear. Ticks: mid 600000 (frame 30), 620000, end−1
880000, end 900000. Background is the frame's own pixel (5,5).

Instance 1 (the prefetch on, the default), project P:
- **H0** (CONTROL): `<home>/Library/Application Support` is a directory.
- **T0** (CONTROL): `set_action_end` publishes no `schema`, and a call with
  `schema: {}` is refused by the argument gate ("set_action_end does not
  take schema."), the `mcp.ToolError` prefix `set_action_end: ` stripped.
- **F0**: the fixture — canvas read back, ramp v1 `ok`, the clip, its
  action, a linear curve, and a frame at mid before any end is set.
- **A1**: `set_action_end {graphic: {props: {x: 129, fill: "#0000ff",
  mode: "B"}}}` lands; the end's `graphic` is those props with `kinds`
  number / color / string, and the clip's props hold the three defaults
  (each start written into the clip).
- **B1**: at mid the edge is at x = 96.5 — (80,60) background where the
  still frame had red, (150,60) the blend #800080, (96,60) the half-covered
  column; the frame one tick of 20000 later differs (CONTROL).
- **S1**: the string switches at the END: (150,200) is background at
  880000 and blue at 900000.
- **U1**: `undo` answers "Action End" and restores the project and the mid
  frame's bytes; `redo` brings the animated frame's bytes back.
- **C1**: the mid and end frames are byte-equal to a STILL control clip
  (project Q) holding the evaluated values {x: 96.5, fill: #800080, mode:
  A} and, by `set_graphic`, the end values.
- **E0** (CONTROL): Q.mov's decoded frames 10 and 30 are byte-equal: the
  encoder is stable for identical input frames.
- **E1**: P-on.mov's frame 30 is byte-equal to Q.mov's frame 30, and
  differs from its own frame 10 (CONTROL); (150,60) is near the blend and
  (80,60) near background, ±6. The byte comparison rests on ProRes 422
  being INTRA-frame: a frame's bytes depend only on its own picture, which
  E0 shows for this encoder. A PNG is never compared with a ProRes frame
  (lossy 4:2:2 YUV).
- **R1**: a shape clip's action refuses a graphic end exactly "clip <id>
  is not a graphic clip"; the project is unchanged.
- **R2**: after ramp v2 is written, `{x: 129}` is refused by v2's max
  ("between 0 and 100") and `{h: 40}` lands with `kinds.h` "number" and the
  clip gaining `h: 10` — the CURRENT revision's schema was sent.
- **R3**: after a v3 that does not compile, a value is refused ("needs its
  module's schema to animate, and none came with the op") and `{mode: null}`
  still removes `mode` from the end's props and kinds.
- **N1**: v2 written again, the graphic clip nested; with `scope` = the
  nest's id, `{x: 30}` on the nested clip's action lands and the nest's
  clip shows `props.x` 30 and `kinds.x` "number".
Instance 2 (`-ReelcutGraphicPrefetchOff YES`, a launch argument, so the
volatile argument domain): P saved and copied before P-on.mov was written,
opened and exported as P-off.mov.
- **F1**: P-on.mov and P-off.mov are the same movie (creation times
  masked, `video_configuration_proof.same_movie`).
- **F2**: the ONE `graphic prefetch:` line instance 1 logged between the
  start of the P-on export and the start of the Q export says hits > 0 and
  mismatched 0; instance 2's log holds no such line.
- **Z1** (CONTROL): neither log holds a `Reelcut: ` line; the tail of each
  log (the instances' stdout and stderr) is printed.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
anchor makes the copy's `core/` its own through `hevc_alpha_proof.own_core`),
replaces one anchor (asserted to occur exactly once), builds it by the
copy's own `make app`, and runs instance 1's rows on it (instance 2, F1 and
F2 are skipped):
  recipe-stored-props  the recipe publishes the STORED props, not the
                       evaluated ones: C1 must FAIL.
  handler-no-schema    the handler sends no schema: A1 must FAIL.
Rule R: exit 0 means the named row FAILED in the copy — caught; 1 that it
passed — survived; 2 that the control could not be performed (the copy did
not build or launch, or the row was not reached). A plain run exits 0 iff
every row passed.
"""

import argparse
import atexit
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
from graphics_prefetch_proof import LINE, FIELDS, await_line, log_size  # noqa: E402
from graphics_proof import near, pixel  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402
from video_configuration_proof import same_movie  # noqa: E402

WORK = ROOT / "tools/proof/work/graphic-prop-action"
HOME = WORK / "home"
APP = proof_app.bundle()
CALL_BOUND = 300
BUILD_BOUND = 1500
WIDTH, HEIGHT = 640, 360
MID, NEXT, END_LESS_ONE, END = 600_000, 620_000, 880_000, 900_000
ROWS = ["H0", "T0", "F0", "A1", "B1", "S1", "U1", "C1", "E0", "E1", "R1", "R2", "R3", "N1",
        "F1", "F2", "Z1"]
MUTANT_ROWS = [name for name in ROWS if name not in ("F1", "F2")]
PREFIX = "set_action_end: "
# name: (file, anchor, replacement, the row that must fail)
MUTANTS = {
    "recipe-stored-props": (
        "core/src/recipe_graphic.rs",
        "        |evaluated| evaluated.props.clone(),",
        "        |_| graphic.props.clone(),", "C1"),
    "handler-no-schema": (
        "app/Sources/AgentServer+Actions.swift",
        "off: off, schema: schema)",
        "off: off, schema: nil)", "A1"),
}
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def module(version):
    """`ramp` v1, v2 (x's max 100, a new `h`) or v3 (does not compile)."""
    if version == 3:
        return "export const meta = { name: \"Ramp\", durationInFrames: 60 \n"
    x_max = 1000 if version == 1 else 100
    extra = "" if version == 1 else "  h: { type: \"number\", default: 10, min: 0, max: 50 },\n"
    return ("export const meta = { name: \"Ramp\", durationInFrames: 60 };\n"
            "export const schema = {\n"
            f"  x: {{ type: \"number\", default: 64, min: 0, max: {x_max} }},\n"
            "  fill: { type: \"color\", default: \"#ff0000\" },\n"
            "  mode: { type: \"string\", default: \"A\" },\n"
            + extra +
            "};\n"
            "export function render(frame, props, ctx) {\n"
            "  return svg(ctx, `<rect x=\"${props.x}\" y=\"20\" width=\"200\" "
            "height=\"${props.mode === \"B\" ? 300 : 100}\" fill=\"${props.fill}\"/>`);\n"
            "}\n")


def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    if client is None:
        return {"ok": False, "error": "no instance"}
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


def said(got, sentence):
    """Refused with exactly this sentence, after `mcp.ToolError`'s prefix."""
    return (not got["ok"]) and got["error"] == PREFIX + sentence


def canon(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def project_of(client, path):
    return reply(attempt(client, "get_project", {"project": str(path)})).get("project") or {}


def clip_of(project, clip):
    return next((c for c in project.get("clips") or [] if c.get("id") == clip), {})


def action_of(clip, action):
    return next((a for a in clip.get("actions") or [] if a.get("id") == action), {})


def end_graphic(project, clip, action):
    return (action_of(clip_of(project, clip), action).get("end") or {}).get("graphic") or {}


def place(client, path, tool, arguments):
    """One clip added; its id, or None."""
    before = {c["id"] for c in project_of(client, path).get("clips") or []}
    got = attempt(client, tool, dict(arguments, project=str(path)))
    new = [c["id"] for c in project_of(client, path).get("clips") or [] if c["id"] not in before]
    return new[0] if got["ok"] and len(new) == 1 else None


def add_action(client, path, clip, at, duration):
    got = attempt(client, "add_action", {"project": str(path), "clip": clip, "at": at,
                                         "duration": duration})
    added = reply(got).get("new_actions") or []
    return added[0] if len(added) == 1 else None


def set_end(client, path, clip, action, props, scope=None):
    arguments = {"project": str(path), "clip": clip, "action": action,
                 "patch": {"graphic": {"props": props}}}
    if scope is not None:
        arguments["scope"] = scope
    return attempt(client, "set_action_end", arguments)


def frame(client, path, tag, t):
    """`render_frame` at `t`; the PNG's bytes, or None."""
    out = WORK / f"{tag}.png"
    if out.exists():
        out.unlink()
    got = attempt(client, "render_frame", {"project": str(path), "t": t, "path": str(out)})
    return out.read_bytes() if got["ok"] and out.exists() else None


def wrote(client, path, version):
    got = attempt(client, "write_graphic", {"project": str(path), "name": "ramp",
                                            "source": module(version)})
    return reply(got).get("ok"), got.get("error", "ok")


def canvas(client, path):
    """Sets 640×360 at 30 fps; whether it reads back."""
    set_ = attempt(client, "set_canvas", {"project": str(path), "width": WIDTH,
                                          "height": HEIGHT, "fps": [30, 1]})
    c = project_of(client, path).get("canvas") or {}
    return set_["ok"] and c.get("width") == WIDTH and c.get("height") == HEIGHT \
        and c.get("fps") == [30, 1]


def export(client, path, movie):
    if movie.exists():
        movie.unlink()
    got = attempt(client, "export", {"project": str(path), "preset": "prores_422",
                                     "path": str(movie)})
    return got["ok"] and movie.exists(), got.get("error", "ok")


def movie_frame(movie, n):
    """Decoded frame `n` of `movie` as rgb24 bytes, or b"" — bounded."""
    try:
        return subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(movie), "-vf", f"select=eq(n\\,{n})",
             "-fps_mode", "passthrough", "-vframes", "1", "-f", "rawvideo",
             "-pix_fmt", "rgb24", "-"],
            capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return b""


def movie_pixel(raw, x, y):
    at = (y * WIDTH + x) * 3
    return tuple(raw[at:at + 3]) if len(raw) == WIDTH * HEIGHT * 3 else None


def prefetch_lines(log, start, stop):
    """Every prefetch line `log` gained between two offsets, as dicts."""
    try:
        with open(log, errors="replace") as handle:
            handle.seek(start)
            text = handle.read(max(0, stop - start))
    except OSError:
        return []
    return [dict(zip(FIELDS, map(int, m.groups()))) for m in LINE.finditer(text)]


def tail(log, count=4):
    try:
        lines = [line.rstrip() for line in open(log, errors="replace")]
    except OSError:
        return [f"{log} could not be read"]
    return lines[-count:] or ["(empty)"]


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Reelcut: " in line]
    except OSError:
        return [f"{log} could not be read"]


def run_p(client, log, state):
    """Instance 1's rows. Answers whether every project it opened closed."""
    p = WORK / "P.reelcut"
    q = WORK / "Q.reelcut"
    made = attempt(client, "new_project", {"path": str(p)})

    # T0 — the gate (CONTROL)
    published = ((client.schemas().get("set_action_end") or {}).get("inputSchema") or {})
    gated = attempt(client, "set_action_end", {"project": str(p), "clip": 1, "action": 1,
                                                "patch": {}, "schema": {}})
    error = gated.get("error", "")
    stripped = error[len(PREFIX):] if error.startswith(PREFIX) else error
    check("T0 CONTROL: set_action_end publishes no schema, and the gate refuses one by name",
          "schema" not in (published.get("properties") or {}) and not gated["ok"]
          and stripped.startswith("set_action_end does not take schema."),
          f"properties {sorted((published.get('properties') or {}).keys())}; answer {error!r}")

    # F0 — the fixture
    sized = canvas(client, p)
    v1, v1_error = wrote(client, p, 1)
    track = (project_of(client, p).get("tracks") or [{}])[0].get("id")
    g = place(client, p, "add_graphic_clip", {"name": "ramp", "track": track, "at": 0,
                                              "duration": 1_200_000})
    action = add_action(client, p, g, 300_000, 600_000) if g is not None else None
    curved = attempt(client, "set_action", {"project": str(p), "clip": g, "action": action,
                                            "curve": "linear"})
    # The default curve may already be linear: "made no change" is that answer.
    linear = action_of(clip_of(project_of(client, p), g), action).get("curve") == "linear"
    base_mid = frame(client, p, "base-mid", MID)
    fixture = (made["ok"] and sized and v1 is True and None not in (g, action)
               and linear and base_mid is not None)
    check("F0 fixture: 640×360 at 30 fps, ramp v1 ok, the graphic clip, its action 0.5–1.5 s "
          "linear, and the still mid frame",
          fixture, f"new {made.get('error', 'ok')}; canvas {sized}; v1 {v1} {v1_error}; clip "
          f"{g}; action {action}; curve {curved.get('error', 'ok')}, linear {linear}; frame "
          f"{None if base_mid is None else len(base_mid)}")
    if not fixture:
        for name in ("A1", "B1", "S1", "U1", "C1", "E0", "E1", "R1", "R2", "R3", "N1"):
            check(f"{name} not run: the fixture could not be built", False)
        closed = attempt(client, "close_project", {"project": str(p), "discard": True})
        return closed["ok"]

    # A1 — the door fills the schema, so the end lands
    before_a1 = project_of(client, p)
    got = set_end(client, p, g, action, {"x": 129, "fill": "#0000ff", "mode": "B"})
    now = project_of(client, p)
    end = end_graphic(now, g, action)
    props = (clip_of(now, g).get("graphic") or {}).get("props")
    check("A1 set_action_end with graphic props lands: the end holds the props and their "
          "kinds, and the clip's props hold the three defaults",
          got["ok"] and end == {"props": {"x": 129, "fill": "#0000ff", "mode": "B"},
                                "kinds": {"x": "number", "fill": "color", "mode": "string"}}
          and props == {"x": 64, "fill": "#ff0000", "mode": "A"},
          f"answer {got.get('error', 'ok')}; end {canon(end)}; clip props {canon(props)}")

    # B1 — the picture halfway through
    mid = frame(client, p, "mid", MID)
    mid1 = frame(client, p, "mid1", NEXT)
    background = pixel(mid, 5, 5)
    left, centre, column = pixel(mid, 80, 60), pixel(mid, 150, 60), pixel(mid, 96, 60)
    was_left = pixel(base_mid, 80, 60)
    check("B1 at mid the edge is at x = 96.5 and the fill is the blend #800080; the frame "
          "20000 ticks later differs (CONTROL)",
          mid is not None and mid1 is not None and mid != base_mid and mid != mid1
          and near(left, background, 2) and near(was_left, (255, 0, 0), 2)
          and near(centre, (128, 0, 128), 2)
          and not near(column, background, 2) and not near(column, (128, 0, 128), 2),
          f"background {background}; (80,60) {left} (still {was_left}); (150,60) {centre}; "
          f"(96,60) {column}; mid≠still {mid != base_mid}; mid≠next {mid != mid1}")

    # S1 — the string switches at the end
    endm1 = frame(client, p, "end-less-one", END_LESS_ONE)
    at_end = frame(client, p, "end", END)
    low_before, low_after = pixel(endm1, 150, 200), pixel(at_end, 150, 200)
    check("S1 mode switches at the END: (150,200) is background at 880000 and blue at 900000",
          near(low_before, background, 2) and near(low_after, (0, 0, 255), 2),
          f"880000 {low_before}; 900000 {low_after}")

    # U1 — undo and redo
    undone = attempt(client, "undo", {"project": str(p)})
    back = project_of(client, p)
    back_mid = frame(client, p, "undone-mid", MID)
    redone = attempt(client, "redo", {"project": str(p)})
    again_mid = frame(client, p, "redone-mid", MID)
    check("U1 undo answers \"Action End\", restores the project and the still mid frame's "
          "bytes; redo restores the animated frame's bytes",
          reply(undone).get("undone") == "Action End" and canon(back) == canon(before_a1)
          and back_mid == base_mid and redone["ok"] and again_mid == mid,
          f"undo {undone.get('error', reply(undone).get('undone'))}; restored "
          f"{canon(back) == canon(before_a1)}; frame {back_mid == base_mid}; redo "
          f"{redone.get('error', 'ok')}; frame {again_mid == mid}")

    # P saved and copied for instance 2, then exported here with the prefetch on
    saved = attempt(client, "save_project", {"project": str(p)})
    copied = False
    if saved["ok"]:
        shutil.copytree(p, WORK / "P-off.reelcut")
        copied = True
    state["p_start"] = log_size(log)
    state["p_on"], state["p_on_error"] = export(client, p, WORK / "P-on.mov")
    state["p_awaited"] = await_line(log, state["p_start"], seconds=30)
    state["p_stop"] = log_size(log)
    state["copied"] = copied and saved["ok"]
    print(f"  P saved {saved.get('error', 'ok')}, copied {copied}; P-on.mov "
          f"{state['p_on']} {state['p_on_error']}", flush=True)

    # The still control, Q
    q_made = attempt(client, "new_project", {"path": str(q)})
    q_sized = canvas(client, q)
    q_v1, _ = wrote(client, q, 1)
    q_track = (project_of(client, q).get("tracks") or [{}])[0].get("id")
    still = place(client, q, "add_graphic_clip",
                  {"name": "ramp", "track": q_track, "at": 0, "duration": 1_200_000,
                   "props": {"x": 96.5, "fill": "#800080", "mode": "A"}})
    c_mid = frame(client, q, "c-mid", MID)
    patched = attempt(client, "set_graphic", {"project": str(q), "clips": [still],
                                              "patch": {"props": {"x": 129, "fill": "#0000ff",
                                                                  "mode": "B"}}})
    c_end = frame(client, q, "c-end", END)
    q_undone = attempt(client, "undo", {"project": str(q)})
    q_movie, q_error = export(client, q, WORK / "Q.mov")
    q_closed = attempt(client, "close_project", {"project": str(q), "discard": True})
    state["q_fixture"] = bool(q_made["ok"] and q_sized and q_v1 is True and still is not None
                              and patched["ok"] and q_undone["ok"]
                              and c_mid is not None and c_end is not None)

    # C1 — the animated frames are the still control's
    check("C1 the mid and end frames are byte-equal to a still clip at the evaluated values",
          q_made["ok"] and q_sized and q_v1 is True and still is not None
          and patched["ok"] and q_undone["ok"]
          and mid is not None and mid == c_mid and at_end is not None and at_end == c_end,
          f"Q made {q_made.get('error', 'ok')}, canvas {q_sized}, v1 {q_v1}, clip {still}, "
          f"set_graphic {patched.get('error', 'ok')}, undo {q_undone.get('error', 'ok')}; mid "
          f"equal {mid == c_mid}; end equal {at_end == c_end}")

    # E0 / E1 — the exports
    q10, q30 = (movie_frame(WORK / "Q.mov", 10), movie_frame(WORK / "Q.mov", 30)) \
        if q_movie else (b"", b"")
    size = WIDTH * HEIGHT * 3
    check("E0 CONTROL: Q.mov's frames 10 and 30 (one still picture) decode byte-equal: the "
          "encoder is stable for identical input frames",
          len(q10) == size and q10 == q30,
          f"Q.mov {q_movie} {q_error}; frames {len(q10)} / {len(q30)} bytes, equal {q10 == q30}")
    p10, p30 = (movie_frame(WORK / "P-on.mov", 10), movie_frame(WORK / "P-on.mov", 30)) \
        if state["p_on"] else (b"", b"")
    centre_m, left_m = movie_pixel(p30, 150, 60), movie_pixel(p30, 80, 60)
    check("E1 P-on.mov's frame 30 is byte-equal to the still control's (ProRes 422 is "
          "intra-frame), differs from its frame 10 (CONTROL); (150,60) near #800080 and "
          "(80,60) near background, ±6",
          len(p30) == size and p30 == q30 and p30 != p10
          and near(centre_m, (128, 0, 128)) and near(left_m, background),
          f"P-on.mov {state['p_on']} {state['p_on_error']}; frame 30 = Q's {p30 == q30}; "
          f"≠ its frame 10 {p30 != p10}; (150,60) {centre_m}; (80,60) {left_m}")

    # R1 — another clip's action
    shape = place(client, p, "add_shape_clip", {"track": track, "at": 1_500_000,
                                                "duration": 600_000})
    shape_action = add_action(client, p, shape, 0, 300_000) if shape is not None else None
    was = project_of(client, p)
    got = set_end(client, p, shape, shape_action, {"x": 50})
    check("R1 a shape clip's action refuses a graphic end in the core's sentence; nothing "
          "changes",
          None not in (shape, shape_action)
          and said(got, f"clip {shape} is not a graphic clip")
          and canon(project_of(client, p)) == canon(was),
          f"shape {shape}, action {shape_action}; answer {got.get('error', 'APPLIED')!r}")

    # R2 — the CURRENT revision's schema
    v2, v2_error = wrote(client, p, 2)
    was = project_of(client, p)
    over = set_end(client, p, g, action, {"x": 129})
    unchanged = canon(project_of(client, p)) == canon(was)
    added = set_end(client, p, g, action, {"h": 40})
    now = project_of(client, p)
    end = end_graphic(now, g, action)
    props = (clip_of(now, g).get("graphic") or {}).get("props") or {}
    check("R2 after ramp v2: x 129 is refused by v2's max and nothing changes; h 40 lands, "
          "kinds.h number, the clip gains h 10",
          v2 is True
          and said(over, "graphic.props.x must be between 0 and 100, not 129") and unchanged
          and added["ok"] and (end.get("props") or {}).get("h") == 40
          and (end.get("kinds") or {}).get("h") == "number" and props.get("h") == 10,
          f"v2 {v2} {v2_error}; x {over.get('error', 'APPLIED')!r}, unchanged {unchanged}; h "
          f"{added.get('error', 'ok')}; end {canon(end)}; clip props {canon(props)}")

    # R3 — a module that does not compile
    v3 = reply(attempt(client, "write_graphic", {"project": str(p), "name": "ramp",
                                                 "source": module(3)})).get("ok")
    was = project_of(client, p)
    value = set_end(client, p, g, action, {"x": 50})
    unchanged = canon(project_of(client, p)) == canon(was)
    removed = set_end(client, p, g, action, {"mode": None})
    end = end_graphic(project_of(client, p), g, action)
    check("R3 after a v3 that does not compile: a value is refused (no schema came) and "
          "nothing changes; a null still removes mode from props and kinds",
          v3 is False
          and said(value, "graphic.props.x needs its module's schema to animate, and none "
                          "came with the op") and unchanged
          and removed["ok"] and "mode" not in (end.get("props") or {"mode": 0})
          and "mode" not in (end.get("kinds") or {"mode": 0}),
          f"v3 ok {v3}; x {value.get('error', 'APPLIED')!r}, unchanged {unchanged}; null "
          f"{removed.get('error', 'ok')}; end {canon(end)}")

    # N1 — a clip inside a nest, addressed by scope
    v2_again, _ = wrote(client, p, 2)
    nested = attempt(client, "nest", {"project": str(p), "clips": [g]})
    nest = ((project_of(client, p).get("nests") or [{}])[0])
    inner = next((c for c in nest.get("clips") or [] if c.get("graphic")), {})
    inner_action = ((inner.get("actions") or [{}])[0]).get("id")
    got = set_end(client, p, inner.get("id"), inner_action, {"x": 30}, scope=nest.get("id"))
    nest_after = ((project_of(client, p).get("nests") or [{}])[0])
    end = (action_of(clip_of(nest_after, inner.get("id")), inner_action).get("end") or {}) \
        .get("graphic") or {}
    check("N1 with scope = the nest, the nested graphic clip's end takes x 30 with its kind",
          v2_again is True and nested["ok"] and inner_action is not None and got["ok"]
          and (end.get("props") or {}).get("x") == 30
          and (end.get("kinds") or {}).get("x") == "number",
          f"v2 {v2_again}; nest {nested.get('error', 'ok')} id {nest.get('id')}; inner clip "
          f"{inner.get('id')} action {inner_action}; answer {got.get('error', 'ok')}; end "
          f"{canon(end)}")

    closed = attempt(client, "close_project", {"project": str(p), "discard": True})
    return closed["ok"] and q_closed["ok"]


def launch(binary, log, off):
    arguments = ["-ReelcutGraphicPrefetchOff", "YES"] if off else []
    return mcp.launch(str(binary), arguments,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                      log_path=str(log), timeout=CALL_BOUND)


def stop(launched):
    launched.stop()
    mcp.remove_scratch(launched.socket_path)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's anchor replaced, built by its own
    `make app`. The app bundle, or None and why."""
    path, anchor, replacement, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if path.startswith("core/"):
        reason = own_core(copy)
        if reason:
            return None, reason
    target = copy / path
    if not target.resolve().is_relative_to(WORK):
        return None, f"{path} in the copy is the tree's own file"
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
    target.write_text(text.replace(anchor, replacement))
    print("  building the copy (one anchor replaced, found once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND)
    if app is None:
        return None, reason
    return app, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    app = Path(args.app)
    named = MUTANTS[args.mutant][3] if args.mutant else None
    scored = MUTANT_ROWS if args.mutant else ROWS
    if args.mutant:
        print(f"graphic prop actions — the {args.mutant} MUTANT ({named} must FAIL)", flush=True)
        app, why = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print("B87 phase 2 — an action animates a graphic's props, over MCP", flush=True)
    binary = app / "Contents/MacOS/Reelcut"
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    on_log, off_log = WORK / "on.log", WORK / "off.log"
    state = {}
    launched = launch(binary, on_log, off=False)
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance 1 PID {launched.child.pid} at {launched.socket_path}", flush=True)
        support = HOME / "Library/Application Support"
        check("H0 CONTROL: the scratch home took: <home>/Library/Application Support is a "
              "directory", support.is_dir(), str(support))
        closed = False
        if rows.get("H0"):
            try:
                closed = run_p(launched.client, on_log, state)
            except Exception as error:  # a row that could not run is a failure
                print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
    finally:
        stop(launched)
    off_movie = WORK / "P-off.mov"
    if not args.mutant and rows.get("H0"):
        second = launch(binary, off_log, off=True)
        try:
            client = second.client
            if client is not None:
                print(f"  instance 2 (prefetch OFF) PID {second.child.pid} at "
                      f"{second.socket_path}", flush=True)
            package = WORK / "P-off.reelcut"
            opened = attempt(client, "open_project", {"path": str(package)})
            off_ok, off_error = export(client, package, off_movie) if opened["ok"] \
                else (False, opened.get("error"))
            off_closed = attempt(client, "close_project", {"project": str(package),
                                                           "discard": True})
        finally:
            stop(second)
        on_movie = WORK / "P-on.mov"
        same, detail = (same_movie(str(on_movie), str(off_movie))
                        if on_movie.exists() and off_movie.exists()
                        else (False, "a movie is missing"))
        check("F1 the export with the prefetch on equals the export with it off",
              state.get("copied") and off_ok and off_closed["ok"] and same,
              f"open {opened.get('error', 'ok')}; P-off.mov {off_ok} {off_error}; close "
              f"{off_closed.get('error', 'ok')}; {detail}")
        lines = prefetch_lines(on_log, state.get("p_start", 0), state.get("p_stop", 0))
        off_lines = prefetch_lines(off_log, 0, log_size(off_log))
        check("F2 the P-on export logged one prefetch line with hits > 0 and mismatched 0; "
              "the prefetch-off instance logged none",
              len(lines) == 1 and lines[0]["hits"] > 0 and lines[0]["mismatched"] == 0
              and not off_lines,
              f"P-on lines {lines}; awaited {state.get('p_awaited')}; OFF lines {off_lines}")
    found = complaints(on_log) + (complaints(off_log) if off_log.exists() else [])
    if rows.get("H0"):
        check("Z1 CONTROL: the projects close and no log holds a `Reelcut: ` line",
              closed and not found, f"closed {closed}; complaints {found}")
    for log in (on_log, off_log):
        if log.exists():
            print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        if named not in rows:
            print(f"mutant {args.mutant}: the control could not be performed — {named} was "
                  "not reached")
            return 2
        # A row marked False because its fixture was never built is not a
        # catch: the control could not be performed (rule R's exit 2).
        if rows.get("F0") is not True or (named == "C1" and not state.get("q_fixture")):
            print(f"mutant {args.mutant}: the control could not be performed — the fixture "
                  f"(F0 {rows.get('F0')}, still control Q {state.get('q_fixture')}) did "
                  "not hold, so a failed row is not a catch")
            return 2
        caught = rows.get(named) is False
        failed = [name for name in scored if not rows.get(name)]
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — {named} "
              f"{'FAILED' if caught else 'passed'} in the copy (failed: {', '.join(failed)})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
