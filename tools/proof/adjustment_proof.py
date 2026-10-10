#!/usr/bin/env python3
"""Road map "grading", phase GR4a (spec §11 GR-6) — adjustment clips end to
end over MCP: `add_adjustment_clip`, the recipe's `{"kind":"adjustment"}`
layer and the compositor's eighth pipeline (`reelcut_adjust_fragment`,
blending OFF, reading the destination), read back as `render_frame` bytes and
exports; and every refusal in its own sentence.

    python3 tools/proof/adjustment_proof.py [--app PATH] [--only G1,M1,...]
    python3 tools/proof/adjustment_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/adjustment/home`,
and every package, PNG and export is under `tools/proof/work/adjustment/`,
removed at the start and at exit. No menu item is performed. Every call is
bounded (`CALL_BOUND`), every ffmpeg too (120 s). Every project is closed
(`close_project`, discard).

Project A, 640 × 360 at 30 fps, background (0.1, 0.1, 0.1), every clip 2 s
from 0, five tracks back to front: T1 a grey 0.5 300 × 240 rectangle centred
on the left half; T2 a (0.2, 0.4, 0.6) one on the right half; T3 the
adjustment clip; TM an empty track (M1's matte); T4 a 100 × 100
(0.9, 0.3, 0.3) square at the centre, in front. No stroke anywhere. The
background shows above, below and between T1 and T2. Frames are taken at
t = 0.5 s unless a row says otherwise; v is the neutral frame's own value at
a sample, enc and dec the sRGB transfer functions, so every formula is over
measured bytes, ±1 a channel unless a row says otherwise.
- **N1**: adding T3 (fresh, neutral) leaves the frame's bytes unchanged.
- **G1**: brightness +0.2 on T3: every T1, T2 and background sample is
  round(255·(v/255 + 0.2)), and every T4 sample equals N1's.
- **U1**: `render_frame {ungraded: true}` of G1's project equals N1's bytes.
- **G2**: exposure +1 alone: every T1 sample is round(255·enc(2·dec(v/255))).
- **F1**: invert at 1 alone: every T1, T2 and background sample is 255 − v.
- **O1**: brightness +0.2 at opacity 0.5: every T1, T2 and background sample
  is round(255·(v/255 + 0.1)).
- **O2**: brightness +0.2 with base opacity 0 and a 1 s action ending at
  opacity 1: at 0.5 s every such sample is round(255·(v/255 + 0.1)) ±2.
- **M1**: TM holds an opaque 200 × 200 window (canvas x 40…240, y 80…280) and
  is made an `alpha` matte, so it cuts T3: brightness +0.2 grades the T1
  samples 4 px inside the window and leaves those 4 px outside it at N1's.
- **Q1**: M1's project as `prores_422` at [320, 180]: inside and outside
  samples within ±8 of M1's formula (the Preview Quality path: a destination
  smaller than the canvas).
- **M2**: T3's own track made an `alpha` matte (T3 at brightness +0.2): the
  frame's bytes equal N1's base, the project without T3.
- **E1–E5**: G1's project as `h264`, `hevc`, `hevc_10bit`, `prores_422` and
  `gif` (size `document`): the decoded middle frame within ±8 of G1's
  `render_frame` at every sample, alpha 255.
- **C1**: from G1, a split of T3 at 1 s, a trim of its second half to end at
  20 s, and a paste of the first half at 30 s each still grade the same: the
  frames at 0.5 s and 1.5 s are G1's bytes after the split and the trim, and
  at 30.5 s (the pasted clip over the background alone) every sample is G1's
  background value.
Project TR, 640 × 360, a transparent canvas: T1 a grey 0.5 rectangle over
the left half at opacity 0.5, T2 the adjustment clip at brightness +0.2.
- **A1**: `render_frame`'s PNG: where the neutral frame's alpha a is above 0,
  the alpha is unchanged (±1) and the colour, compared PREMULTIPLIED (the PNG
  is written from 8-bit premultiplied pixels, so a straight value at a = 128
  moves in steps of two), is round(255·(v/255 + 0.2)·a/255) (±1); where a is
  0, it stays 0.
- **E6–E8**: TR as `hevc_alpha`, `prores_4444` and `apng`: the decoded middle
  frame's alpha within ±2 of `render_frame`'s, and its colour within ±8 where
  that alpha is above 0. `hevc_alpha` is skipped by name when the export
  answers "This Mac cannot export with the “hevc_alpha” preset."
Project RR: on track 1 a shape [0, 2 s) and the adjustment clip [2 s, 4 s),
a hard cut; on track 2 a shape nested into nest N.
- **R1–R7**: GR-6's sentences in its order, each the exact tail of the MCP
  answer (after `<tool>: ` for an error, after `<tool>: <step> was refused at
  <op>: ` for a refusal): R1 `nest` of the shape and the adjustment clip;
  R2 a `paste` of the adjustment clip into scope N; R3 `add_adjustment_clip`
  on N's own track in scope N; R4 `add_transition`, `set_transition {kind}` and
  `set_transition_style {curve}`; R5 `trim_end` of the shape to 2.5 s; R6
  `set_video` with a blur filter; R7 `set_video` with blend `multiply`. And
  the project is unchanged and `undo` still names the same last step.
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds
  no `Reelcut: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`),
applies its edits (each anchor asserted to occur exactly once), builds it by
the copy's own `make app-debug` (`make app` under `RC_PROOF_APP=release`)
and runs every row on it. MUTANT PASS when every named row FAILED and no
other scored row did:
  blending-on            the adjust pipeline blends: A1
  ignores-matte          the pass's weight drops the coverage: M1 Q1
  ignores-opacity        the pass's weight drops the opacity: O1 O2
  front-graded           adjustment layers drawn after every other: G1
  matte-track-not-inert  the recipe keeps an adjustment clip on a matte track: M2
  nest-allowed           `nest` takes an adjustment clip: R1
  overlap-allowed        the overlap rule's adjustment clause gone: R5
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import json
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
from hevc_alpha_proof import own_core  # noqa: E402

WORK = ROOT / "tools/proof/work/adjustment"
HOME = WORK / "home"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
T = SEC // 2
W, H = 640, 360
ROWS = ["N1", "G1", "U1", "G2", "F1", "O1", "O2", "M1", "Q1", "M2", "E1", "E2", "E3", "E4",
        "E5", "C1", "A1", "E6", "E7", "E8", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "Z1"]
A_ROWS = {"N1", "G1", "U1", "G2", "F1", "O1", "O2", "M1", "Q1", "M2", "E1", "E2", "E3", "E4",
          "E5", "C1"}
TR_ROWS = {"A1", "E6", "E7", "E8"}
R_ROWS = {"R1", "R2", "R3", "R4", "R5", "R6", "R7"}
OPAQUE = [("E1", "h264", "mp4"), ("E2", "hevc", "mp4"), ("E3", "hevc_10bit", "mp4"),
          ("E4", "prores_422", "mov"), ("E5", "gif", "gif")]
CLEAR = [("E6", "hevc_alpha", "mov"), ("E7", "prores_4444", "mov"), ("E8", "apng", "png")]
UNAVAILABLE = "This Mac cannot export with the “hevc_alpha” preset."
# Samples: on T1 (outside T4), on T2 (outside T4), on the background, on T4.
T1 = [(60, 100), (160, 100), (60, 260), (160, 260), (250, 280)]
T2 = [(400, 100), (560, 100), (400, 260), (560, 260), (600, 200)]
BG = [(20, 20), (320, 20), (620, 340), (320, 340), (320, 100)]
T4 = [(320, 180), (290, 150), (350, 210)]
GRADED = T1 + T2 + BG
WINDOW = (40, 80, 240, 280)          # M1's matte window, canvas pixels
INSIDE = [(44, 84), (236, 276), (140, 180), (44, 276), (236, 84)]
OUTSIDE = [(36, 180), (244, 180), (140, 76), (140, 284)]
# Q1's samples at full size (halved for the 320 × 180 file): inside the
# window, and outside it on T1, T2 and the background, away from every edge.
Q_INSIDE = [(140, 180), (80, 120), (200, 240)]
Q_OUTSIDE = [(280, 100), (480, 260), (20, 20), (560, 340)]
SHADER = "app/Resources/Shaders/Compositor.metal"
WEIGHT = "    float w = saturate(u.opacity * matte.sample(samp, local).r);\n"
NEST_REFUSAL = ("        // An adjustment clip grades the top level only (spec §11 GR-6).\n"
                "        if let Some(found) = selected.iter().find(|c| is_adjustment(c)) {\n"
                "            return Ok(Outcome::Refused(adjustment_cannot_nest(found.id)));\n"
                "        }\n")
OVERLAP_CLAUSE = ("                    // No overlap may hold an adjustment clip (spec §11\n"
                  "                    // GR-6): it cannot take the transition an overlap is.\n"
                  "                    if let Some(why) = adjustment_overlap(a, b) {\n"
                  "                        return Err(why);\n"
                  "                    }\n")
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "blending-on": ([(
        "app/Sources/Compositor+Adjustment.swift",
        'label: "Reelcut adjustment", vertex: vertex, fragment: fragment, blending: false))',
        'label: "Reelcut adjustment", vertex: vertex, fragment: fragment, blending: true))')],
        ["A1"]),
    "ignores-matte": ([(SHADER, WEIGHT, "    float w = saturate(u.opacity);\n")], ["M1", "Q1"]),
    "ignores-opacity": ([(SHADER, WEIGHT,
                          "    float w = saturate(matte.sample(samp, local).r);\n")],
                        ["O1", "O2"]),
    "front-graded": ([(
        "app/Sources/Compositor.swift",
        "        let canvasLayers = layers.filter { $0.matte?.into == nil }\n",
        "        let canvasLayers = layers.filter { $0.matte?.into == nil && !$0.isAdjustment }\n"
        "            + layers.filter { $0.matte?.into == nil && $0.isAdjustment }\n")], ["G1"]),
    "matte-track-not-inert": ([(
        "core/src/recipe.rs",
        ".filter(|i| i.covers(t) && !self.inert_adjustment(i))",
        ".filter(|i| i.covers(t))")], ["M2"]),
    "nest-allowed": ([("core/src/edit_nest.rs", NEST_REFUSAL, "")], ["R1"]),
    "overlap-allowed": ([("core/src/transition.rs", OVERLAP_CLAUSE, "")], ["R5"]),
}
rows = {}
skipped = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    mark = "  ok   " if good else "  FAIL "
    print(mark + name + (f"\n       {detail}" if detail else ""), flush=True)


def skip(name, why):
    key = name.split()[0]
    if key not in selected:
        return
    skipped[key] = why
    print(f"  skip {name} — {why}", flush=True)


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


# ---- pixels -------------------------------------------------------------------

def dec(c):
    c = min(max(c, 0.0), 1.0)
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def enc(c):
    c = min(max(c, 0.0), 1.0)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def code(value):
    return round(255 * min(max(value, 0.0), 1.0))


def lifted(v, amount):
    return code(v / 255 + amount)


def close_to(got, want, tolerance=1):
    return all(abs(a - b) <= tolerance for a, b in zip(got, want))


def frames(path):
    """The number of video frames ffprobe counts in `path`, or 0; bounded."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-count_frames", "-select_streams",
                              "v:0", "-show_entries", "stream=nb_read_frames", "-of",
                              "csv=p=0", str(path)], capture_output=True, text=True,
                             timeout=120, env=bounded.child_env()).stdout
        return int(out.strip().split(",")[0])
    except (OSError, subprocess.TimeoutExpired, ValueError, IndexError):
        return 0


def decode(path, width, height, index=0):
    """Frame `index` of `path` (a PNG, a movie or an animation) as straight
    8-bit RGBA bytes through ffmpeg, or None; bounded."""
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"select=eq(n\\,{index})",
             "-fps_mode", "passthrough", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt",
             "rgba", "-"], capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw if len(raw) == width * height * 4 else None


class Frame:
    """One decoded frame: straight RGBA bytes, `width`, and its file."""

    def __init__(self, path, raw, width):
        self.path, self.raw, self.width = path, raw, width

    def px(self, x, y):
        at = (y * self.width + x) * 4
        return tuple(self.raw[at:at + 3])

    def alpha(self, x, y):
        return self.raw[(y * self.width + x) * 4 + 3]


def same(a, b):
    return a is not None and b is not None and a.raw == b.raw


def compare(frame, points, want, tolerance=1):
    """(every point's rgb within `tolerance` of `want(x, y)`, the first miss)."""
    if frame is None:
        return False, "the frame is missing"
    for x, y in points:
        expected = want(x, y)
        got = frame.px(x, y)
        if expected is None or not close_to(got, expected, tolerance):
            return False, f"({x},{y}) {got} vs {expected}"
    return True, ""


# ---- the documents ------------------------------------------------------------

class Doc:
    """One open project and the calls the rows make on it."""

    def __init__(self, client, path):
        self.client, self.path = client, path

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def clips(self):
        return self.project().get("clips") or []

    def clip(self, clip):
        return next((c for c in self.clips() if c.get("id") == clip), {})

    def new_track(self):
        before = {t.get("id") for t in self.project().get("tracks") or []}
        self.call("add_track")
        made = [t.get("id") for t in self.project().get("tracks") or []
                if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def added(self, tool, **arguments):
        """`tool` that places one clip; its id, or None."""
        before = {c["id"] for c in self.clips()}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.clips() if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def rectangle(self, track, width, height, fill, x=0, y=0, opacity=None):
        clip = self.added("add_shape_clip", track=track, at=0, duration=2 * SEC,
                          shape={"kind": "rectangle", "width": width, "height": height,
                                 "stroke": None, "fill": fill})
        if clip is None:
            return None
        patch = {key: value for key, value in (("x", x), ("y", y), ("opacity", opacity))
                 if value not in (None, 0)}
        if not patch:  # an all-default patch is an identity, which answers as an error
            return clip
        return clip if self.call("set_video", clips=[clip], patch=patch)["ok"] else None

    def video(self, clip, **patch):
        return self.call("set_video", clips=[clip], patch=patch)

    def frame(self, tag, t=T, **options):
        """`render_frame` at `t`, decoded; a Frame, or None."""
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out), **options)
        raw = decode(out, W, H) if got["ok"] and out.exists() else None
        if raw is None:
            print(f"       render {tag}: {got.get('error', 'no file or a wrong size')}",
                  flush=True)
            return None
        return Frame(out, raw, W)

    def export(self, tag, preset, extension, size="document"):
        """`export`; (the answer, the path)."""
        out = WORK / f"{tag}-{preset}.{extension}"
        if out.exists():
            out.unlink()
        got = self.call("export", preset=preset, path=str(out), size=size)
        return got, out


def opened(client, name, background):
    """A new 640 × 360 project at `name`; (Doc, its first track's id)."""
    path = WORK / f"{name}.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    doc.call("set_canvas", width=W, height=H, fps=[30, 1], background=background)
    canvas = doc.project().get("canvas") or {}
    track = ((doc.project().get("tracks") or [{}])[0]).get("id")
    good = made["ok"] and canvas.get("width") == W and canvas.get("height") == H
    return doc, (track if good else None)


def close(client, path):
    return attempt(client, "close_project", {"project": str(path), "discard": True})["ok"]


def middle(path, width, height):
    """The middle frame of an export, decoded; (Frame or None, its index)."""
    count = frames(path)
    index = count // 2
    raw = decode(path, width, height, index) if count else None
    return (Frame(path, raw, width) if raw is not None else None), index


# ---- project A ---------------------------------------------------------------

def build_a(client):
    doc, t1 = opened(client, "A", [0.1, 0.1, 0.1, 1])
    if t1 is None:
        return doc, None
    ids = {"T1": t1}
    ids["T2"] = doc.new_track()
    ids["T3"] = doc.new_track()
    ids["TM"] = doc.new_track()
    ids["T4"] = doc.new_track()
    if None in ids.values():
        return doc, None
    ids["c1"] = doc.rectangle(ids["T1"], 300, 240, [0.5, 0.5, 0.5, 1], x=-160)
    ids["c2"] = doc.rectangle(ids["T2"], 300, 240, [0.2, 0.4, 0.6, 1], x=160)
    ids["c4"] = doc.rectangle(ids["T4"], 100, 100, [0.9, 0.3, 0.3, 1])
    return doc, (ids if None not in ids.values() else None)


def run_a(client, state):
    doc, ids = build_a(client)
    base = doc.frame("base") if ids else None
    state["a_fixture"] = ids is not None and base is not None
    if not state["a_fixture"]:
        return close(client, doc.path) and False
    v = base.px

    # N1
    adj = doc.added("add_adjustment_clip", track=ids["T3"], at=0, duration=2 * SEC)
    n1 = doc.frame("n1")
    source = doc.clip(adj).get("source")
    check("N1 a fresh adjustment clip on T3 leaves the frame's bytes unchanged",
          adj is not None and source == {"kind": "adjustment"} and same(n1, base),
          f"clip {adj} source {source}; equal {same(n1, base)}")
    state["a_fixture"] = adj is not None
    if adj is None:
        return close(client, doc.path) and False

    # G1
    set_g1 = doc.video(adj, color={"brightness": 0.2})
    g1 = doc.frame("g1")
    graded_ok, graded_miss = compare(g1, GRADED, lambda x, y: tuple(lifted(c, 0.2) for c in v(x, y)))
    front_ok, front_miss = compare(g1, T4, lambda x, y: v(x, y), tolerance=0)
    check("G1 brightness +0.2: T1, T2 and background samples at v + 0.2 (±1); T4's equal N1's",
          set_g1["ok"] and graded_ok and front_ok,
          f"set {set_g1.get('error', 'ok')}; behind {graded_miss or 'all within'}; front "
          f"{front_miss or 'all equal'}")

    # U1
    u1 = doc.frame("u1", ungraded=True)
    check("U1 render_frame {ungraded: true} of G1's project equals N1's bytes",
          same(u1, n1), f"equal {same(u1, n1)}")

    # E1–E5: G1's project, exported
    for name, preset, extension in OPAQUE:
        got, out = doc.export(name, preset, extension)
        frame, index = middle(out, W, H) if got["ok"] and out.exists() else (None, None)
        points = GRADED + T4
        ok, miss = compare(frame, points, lambda x, y: g1.px(x, y) if g1 else None, 8)
        opaque = frame is not None and all(frame.alpha(x, y) == 255 for x, y in points)
        check(f"{name} {preset}: the middle frame ({index}) is within ±8 of G1's render_frame "
              f"at {len(points)} samples, alpha 255",
              got["ok"] and ok and opaque,
              f"export {got.get('error', 'ok')}; {miss or 'all within'}; opaque {opaque}")

    # G2
    doc.video(adj, color={"brightness": 0})
    set_g2 = doc.video(adj, color={"exposure": 1})
    g2 = doc.frame("g2")
    ok, miss = compare(g2, T1, lambda x, y: tuple(code(enc(2 * dec(c / 255))) for c in v(x, y)))
    check("G2 exposure +1: T1 samples at round(255·enc(2·dec(v))) (±1)",
          set_g2["ok"] and ok, f"set {set_g2.get('error', 'ok')}; {miss or 'all within'}")
    doc.video(adj, color={"exposure": 0})

    # F1
    set_f1 = doc.video(adj, filters=[{"kind": "invert", "amount": 1}])
    f1 = doc.frame("f1")
    ok, miss = compare(f1, GRADED, lambda x, y: tuple(255 - c for c in v(x, y)))
    check("F1 invert at 1: T1, T2 and background samples at 255 − v (±1)",
          set_f1["ok"] and ok, f"set {set_f1.get('error', 'ok')}; {miss or 'all within'}")
    doc.video(adj, filters=[])

    # O1
    set_o1 = doc.video(adj, color={"brightness": 0.2}, opacity=0.5)
    o1 = doc.frame("o1")
    ok, miss = compare(o1, GRADED, lambda x, y: tuple(lifted(c, 0.1) for c in v(x, y)))
    check("O1 brightness +0.2 at opacity 0.5: halfway, v + 0.1 (±1)",
          set_o1["ok"] and ok, f"set {set_o1.get('error', 'ok')}; {miss or 'all within'}")

    # O2
    doc.video(adj, opacity=0)
    added = doc.call("add_action", clip=adj, at=0, duration=SEC)
    actions = doc.clip(adj).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = (doc.call("set_action_end", clip=adj, action=action,
                      patch={"video": {"opacity": 1}}) if action else {"ok": False})
    o2 = doc.frame("o2", t=SEC // 2)
    ok, miss = compare(o2, GRADED, lambda x, y: tuple(lifted(c, 0.1) for c in v(x, y)), 2)
    check("O2 an opacity action from 0 to 1 is halfway at its midpoint: v + 0.1 (±2)",
          added["ok"] and ended["ok"] and ok,
          f"add {added.get('error', 'ok')}; end {ended.get('error', 'ok')}; "
          f"{miss or 'all within'}")
    if action:
        doc.call("remove_action", clip=adj, action=action)
    doc.video(adj, opacity=1)

    # M1 and Q1
    x0, y0, x1, y1 = WINDOW
    window = doc.rectangle(ids["TM"], x1 - x0, y1 - y0, [1, 1, 1, 1],
                           x=(x0 + x1) / 2 - W / 2, y=(y0 + y1) / 2 - H / 2)
    matted = doc.call("set_track", track=ids["TM"], matte="alpha")
    m1 = doc.frame("m1")
    in_ok, in_miss = compare(m1, INSIDE, lambda x, y: tuple(lifted(c, 0.2) for c in v(x, y)))
    out_ok, out_miss = compare(m1, OUTSIDE, lambda x, y: v(x, y), tolerance=0)
    check("M1 an alpha matte window in front of T3: graded 4 px inside it, N1's bytes 4 px "
          "outside", window is not None and matted["ok"] and in_ok and out_ok,
          f"window {window}; matte {matted.get('error', 'ok')}; inside "
          f"{in_miss or 'all within'}; outside {out_miss or 'all equal'}")
    got, out = doc.export("Q1", "prores_422", "mov", size=[320, 180])
    q1, index = middle(out, 320, 180) if got["ok"] and out.exists() else (None, None)
    misses = []
    for (x, y), graded in [(p, True) for p in Q_INSIDE] + [(p, False) for p in Q_OUTSIDE]:
        want = tuple(lifted(c, 0.2) for c in v(x, y)) if graded else v(x, y)
        found = q1.px(x // 2, y // 2) if q1 else None
        if found is None or not close_to(found, want, 8):
            misses.append(((x, y), found, want))
    check("Q1 M1's project as prores_422 at [320, 180]: inside and outside the window within "
          "±8 of the formula", got["ok"] and q1 is not None and not misses,
          f"export {got.get('error', 'ok')}; frame {index}; {misses[:3] or 'all within'}")
    doc.call("set_track", track=ids["TM"], matte="none")
    if window is not None:
        doc.call("delete", clips=[window])

    # M2
    on_matte = doc.call("set_track", track=ids["T3"], matte="alpha")
    m2 = doc.frame("m2")
    check("M2 T3's own track made a matte: the frame equals the project without T3",
          on_matte["ok"] and same(m2, base),
          f"matte {on_matte.get('error', 'ok')}; equal {same(m2, base)}")
    doc.call("set_track", track=ids["T3"], matte="none")

    # C1
    again = doc.frame("c1-g1")
    split = doc.call("split", clips=[adj], at=SEC)
    halves = sorted((c for c in doc.clips() if c.get("source") == {"kind": "adjustment"}),
                    key=lambda c: c["start"])
    c_split = (doc.frame("c1-split-a"), doc.frame("c1-split-b", t=SEC + T))
    second = halves[1]["id"] if len(halves) == 2 else None
    trimmed = doc.call("trim_end", clip=second, to=20 * SEC) if second else {"ok": False}
    c_trim = doc.frame("c1-trim", t=SEC + T)
    first = dict(halves[0]) if halves else {}
    first["track"] = 0
    pasted = doc.call("paste", at=30 * SEC, track=ids["T3"],
                      payload={"clips": [first], "media": []}) if halves else {"ok": False}
    c_paste = doc.frame("c1-paste", t=30 * SEC + T)
    background = g1.px(*BG[0]) if g1 else None
    paste_ok, paste_miss = compare(c_paste, GRADED + T4, lambda x, y: background, 0)
    check("C1 a split, a trim to 20 s and a paste each still grade the same",
          same(again, g1) and split["ok"] and len(halves) == 2 and same(c_split[0], g1)
          and same(c_split[1], g1) and trimmed["ok"] and same(c_trim, g1) and pasted["ok"]
          and paste_ok,
          f"G1 again {same(again, g1)}; split {split.get('error', 'ok')} "
          f"{[same(f, g1) for f in c_split]}; trim {trimmed.get('error', 'ok')} "
          f"{same(c_trim, g1)}; paste {pasted.get('error', 'ok')} {paste_miss or 'all equal'}")
    return close(client, doc.path)


# ---- project TR: a transparent canvas ---------------------------------------

def run_tr(client, state):
    doc, track = opened(client, "TR", [0, 0, 0, 0])
    left = doc.rectangle(track, 320, 360, [0.5, 0.5, 0.5, 1], x=-160, opacity=0.5) \
        if track else None
    t2 = doc.new_track() if track else None
    base = doc.frame("tr-base")
    adj = doc.added("add_adjustment_clip", track=t2, at=0, duration=2 * SEC) if t2 else None
    graded = doc.video(adj, color={"brightness": 0.2}) if adj else {"ok": False}
    points = [(x, y) for y in range(20, H, 40) for x in range(20, W, 40)]
    state["tr_fixture"] = (left is not None and adj is not None and graded["ok"]
                           and base is not None
                           and 100 < base.alpha(60, 180) < 160 and base.alpha(600, 180) == 0)
    if not state["tr_fixture"]:
        return close(client, doc.path) and False
    a1 = doc.frame("a1")
    misses = []
    for x, y in points:
        alpha = base.alpha(x, y)
        got_alpha = a1.alpha(x, y) if a1 else None
        if got_alpha is None or abs(got_alpha - alpha) > 1:
            misses.append(((x, y), "alpha", got_alpha, alpha))
        elif alpha > 0:
            # Compared PREMULTIPLIED: the PNG is written from 8-bit
            # premultiplied pixels, so at alpha 128 a straight value moves
            # in steps of two.
            want = tuple(code((c / 255 + 0.2) * alpha / 255) for c in base.px(x, y))
            got = tuple(round(c * got_alpha / 255) for c in a1.px(x, y))
            if not close_to(got, want):
                misses.append(((x, y), "colour", got, want))
    check("A1 over a transparent canvas: alpha unchanged (±1), the premultiplied colour graded "
          f"where alpha > 0 (±1), at {len(points)} samples", a1 is not None and not misses,
          f"{misses[:3] or 'all within'}; left alpha {base.alpha(60, 180)}")

    for name, preset, extension in CLEAR:
        got, out = doc.export(name, preset, extension)
        if not got["ok"] and got.get("error", "").endswith(UNAVAILABLE):
            skip(f"{name} {preset}", f"this host has no encoder: {UNAVAILABLE}")
            continue
        frame, index = middle(out, W, H) if got["ok"] and out.exists() else (None, None)
        misses = []
        for x, y in points:
            if frame is None or a1 is None:
                misses.append("no frame")
                break
            if abs(frame.alpha(x, y) - a1.alpha(x, y)) > 2:
                misses.append(((x, y), "alpha", frame.alpha(x, y), a1.alpha(x, y)))
            elif a1.alpha(x, y) > 0 and not close_to(frame.px(x, y), a1.px(x, y), 8):
                misses.append(((x, y), "colour", frame.px(x, y), a1.px(x, y)))
        check(f"{name} {preset}: the middle frame ({index}) has render_frame's alpha (±2) and "
              "colour where alpha > 0 (±8)", got["ok"] and not misses,
              f"export {got.get('error', 'ok')}; {misses[:3] or 'all within'}")
    return close(client, doc.path)


# ---- project RR: the refusals ------------------------------------------------

def last_step(doc):
    """The name `undo` walks past, put back by `redo`; or None."""
    undone = reply(doc.call("undo")).get("undone")
    doc.call("redo")
    return undone


def run_rr(client, state):
    doc, track = opened(client, "RR", [0, 0, 0, 1])
    shape = doc.rectangle(track, 100, 100, [1, 1, 1, 1]) if track else None
    adj = doc.added("add_adjustment_clip", track=track, at=2 * SEC, duration=2 * SEC) \
        if shape else None
    t2 = doc.new_track() if adj else None
    inner = doc.rectangle(t2, 100, 100, [1, 1, 1, 1]) if t2 else None
    nested = doc.call("nest", clips=[inner]) if inner else {"ok": False}
    nests = doc.project().get("nests") or []
    nest = nests[0].get("id") if len(nests) == 1 else None
    inside = ((nests[0].get("tracks") or [{}])[0].get("id")) if len(nests) == 1 else None
    state["rr_fixture"] = None not in (shape, adj, nest) and nested["ok"]
    if not state["rr_fixture"]:
        return close(client, doc.path) and False
    before = doc.project()
    step = last_step(doc)
    payload = dict(doc.clip(adj), track=0)
    next_id = before.get("next_id")
    transition = (f"clip {adj} is an adjustment clip and cannot take a transition; fade it "
                  "with opacity instead")
    cases = [
        ("R1", [("nest", {"clips": [shape, adj]})],
         f"clip {adj} is an adjustment clip, and an adjustment clip cannot go inside a nest"),
        ("R2", [("paste", {"at": 10 * SEC, "payload": {"clips": [payload], "media": []},
                           "scope": nest})],
         f"clip {next_id} in nest {nest} is an adjustment clip, and an adjustment clip cannot "
         "be inside a nest"),
        ("R3", [("add_adjustment_clip", {"track": inside, "at": 0, "scope": nest})],
         f"add_adjustment_clip has no meaning inside nest {nest}"),
        ("R4", [("add_transition", {"clip": adj, "duration": SEC // 2}),
                ("set_transition", {"clip": adj, "kind": "cross_dissolve"}),
                ("set_transition_style", {"clip": adj, "curve": "ease_in"})], transition),
        ("R5", [("trim_end", {"clip": shape, "to": 2 * SEC + T})],
         f"clips {shape} and {adj} would overlap, and clip {adj} is an adjustment clip, which "
         "cannot take a transition; fade it with opacity instead"),
        ("R6", [("set_video", {"clips": [adj], "patch": {"filters": [
            {"kind": "blur", "amount": 0.5}]}})],
         f"clip {adj} is an adjustment clip and cannot take the blur filter"),
        ("R7", [("set_video", {"clips": [adj], "patch": {"blend": "multiply"}})],
         f"clip {adj} is an adjustment clip and cannot take a blend mode"),
    ]
    for name, calls, sentence in cases:
        answers = []
        for tool, arguments in calls:
            got = doc.call(tool, **arguments)
            answers.append((tool, got))
            if got["ok"]:  # an edit accepted in error is taken back, so no later row starts from it
                doc.call("undo")
        # The sentence is the answer's whole tail: after `<tool>: ` for an
        # error, after `<tool>: <step> was refused at <op>: ` for a refusal.
        exact = all(not got["ok"] and got.get("error", "").endswith(f": {sentence}")
                    for tool, got in answers)
        unchanged = doc.project() == before and last_step(doc) == step
        check(f"{name} {' / '.join(tool for tool, _ in calls)}: \"{sentence}\"; the project "
              "and the undo history unchanged", exact and unchanged,
              "; ".join(f"{tool} {got.get('error') or 'APPLIED'!r}" for tool, got in answers)
              + f"; unchanged {unchanged} (last step {step!r})")
    return close(client, doc.path)


# ---- the run ------------------------------------------------------------------

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


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's edits, built by its own
    `tree_copy.build_app`. (app bundle, copy) or (None, why)."""
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if any(path.startswith("core/") for path, _, _ in edits):
        reason = own_core(copy)
        if reason:
            return None, reason
    for path, anchor, replacement in edits:
        target = copy / path
        if not target.resolve().is_relative_to(WORK):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    print(f"  building the copy ({len(edits)} edit(s), each anchor found once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND)
    if app is None:
        return None, reason
    return app, copy


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()} | {"Z1"}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][1] if args.mutant else []
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    config = proof_app.config()
    if args.mutant:
        print(f"grading GR4a — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = app / "Contents/MacOS/Reelcut"
    else:
        print(f"grading GR4a — adjustment clips over MCP ({config} build {binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    log = WORK / "instance.log"
    state = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            if selected & A_ROWS:
                closed = run_a(launched.client, state) and closed
            if selected & TR_ROWS:
                closed = run_tr(launched.client, state) and closed
            if selected & R_ROWS:
                closed = run_rr(launched.client, state) and closed
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    fixtures_ok = all(state.values())
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Reelcut: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; fixtures {state}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    scored = [name for name in ROWS if name in selected and name not in skipped]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}" + (f", skipped {sorted(skipped)}" if skipped else ""))
    if args.mutant:
        missing = [name for name in named if name not in rows]
        if missing or not fixtures_ok:
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}, fixtures {state}")
            return 2
        survived = [name for name in named if rows.get(name)]
        others = [name for name in scored if not rows.get(name) and name not in named]
        caught = not survived and not others
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'} in the "
              f"copy (survived: {', '.join(survived) or 'none'}; other rows failed: "
              f"{', '.join(others) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
