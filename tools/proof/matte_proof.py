#!/usr/bin/env python3
"""Road map "mattes", phase MT2 (#240; spec §11 MT-1..MT-6) — the matte track
end to end over MCP: `set_track {matte}`, the recipe's `matte` and `mattes`,
and the compositor's matte pass, read back as `render_frame` bytes.

    python3 tools/proof/matte_proof.py [--app PATH] [--only C0,A1,...]
    python3 tools/proof/matte_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/matte/home`,
and every package, movie and PNG is under `tools/proof/work/matte/`, which is
removed at the start and at exit. No menu item is performed. Every call is
bounded (`CALL_BOUND`), every ffmpeg too (120 s).

The canvas is 640×360 at 30 fps and every frame is taken at t = 0.5 s
(300000). A 2 s ffmpeg `testsrc2` movie (640×360, 30 fps) is made in the work
folder. Every claim is a byte comparison of two `render_frame` PNGs, or a
formula over measured bytes, ±1 per channel.

Project P: track A (index 0) holds the movie; track B (in front) a white
200×120 rectangle (no stroke) at the canvas centre, its box x 220–420,
y 120–240. Three references: PLAIN (B over A, ordinary), A-ALONE (B hidden)
and BG (both hidden, the canvas background alone). INSIDE is the box less
3 px, OUTSIDE everything more than 3 px from it.
- **C0** (CONTROL): two renders of PLAIN are byte-equal.
- **A1**: B an `alpha` matte: INSIDE equals A-ALONE, OUTSIDE equals BG.
- **G0**: `get_project` shows track B `matte: "alpha"`; after N0 the track
  has no `matte` key at all.
- **U0**: `undo` brings PLAIN's bytes back and `redo` A1's.
- **P6**: the matte clip's `blend: multiply`, a drop shadow and a reflection
  leave A1's bytes unchanged (MT-4: the core clears them).
- **MM**: a third track C in front of B, an `alpha` matte holding a RED
  rectangle over the box's left half: A1's bytes unchanged, and A1's two
  region claims hold — a matte in front of a matte draws nothing and cuts
  nothing, and B still cuts A.
- **V5**: B's clip trimmed to end at 0.25 s: the frame equals A-ALONE.
- **H0**: B hidden: the frame equals A-ALONE.
- **B0**: A scaled to 0.25 (so B's box shows round it if B drew) and B moved
  to index 0: the frame equals A-ALONE-SMALL (B hidden) — a back-most matte
  draws nothing and A is uncut.
- **A2**: `alpha_inverted`: INSIDE equals BG, OUTSIDE equals A-ALONE.
- **N0**: `matte: "none"` brings PLAIN's bytes back.
- **R0**: `matte: "chroma"` is refused naming the five modes, and the
  project is unchanged.
Project L, its canvas background (0.4, 0.2, 0.1): track 1 a full-canvas card
(0.2, 0.6, 0.9); track 2 a 400×200 black-to-white linear gradient at the
centre. g is a pixel's Rec. 709 luma over 255 in the gradient drawn alone;
CARD and BG are the card alone and the background alone. Sampled every 4 px
along y = 180 inside the gradient's box, and at points outside it.
- **L1**: `luma`: inside, card·g + bg·(1 − g); outside, BG.
- **L2**: `luma_inverted`: inside, card·(1 − g) + bg·g; outside, CARD.
- **L3**: the gradient's track removed and the movie on a new front track,
  a `luma` matte: every sample (every 8 px on 5 rows) is card·g + bg·(1 − g),
  g from the movie drawn alone.
- **Z1** (CONTROL): the log holds no `Reelcut: ` line; its tail is printed.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
anchor makes the copy's `core/` its own through `hevc_alpha_proof.own_core`),
replaces one anchor (asserted to occur exactly once), builds it by the copy's
own `make app-debug` (`make app` under `RC_PROOF_APP=release`;
`tree_copy.build_app`), and runs every row on it. A core mutant also runs
`cargo test --release --test matte` in the copy's own `core/` (row CT, scored
only for the mutant that names it). The rows each must FAIL:
  shader-no-multiply          step 7's multiply removed: A1 A2 L1
  source-drawn                render's `into` skip removed: A1 B0 MM
  resolve-mode-ignored        the resolve reads every mode as alpha: A2 L1 L2 L3
  core-no-prune               a group listed with no `into` layer: V5 H0
  core-matte-behind-matte     the target ignores a matte behind: MM
  core-untargeted-into-null   a matte layer with no target gets `into: null`:
                              B0 MM CT
  core-no-override            the source keeps shadow, reflection, blend: P6
  handler-drops-matte         the handler drops `matte`: A1 G0
Rule R: exit 0 means every named row FAILED in the copy — caught; 1 that one
passed — survived; 2 that the control could not be performed (the copy did
not build or launch, the fixture did not hold, or a row was not reached). A
plain run exits 0 iff every scored row passed.
"""

import argparse
import atexit
import json
import struct
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

WORK = ROOT / "tools/proof/work/matte"
HOME = WORK / "home"
CALL_BOUND = 300
BUILD_BOUND = 1500
WIDTH, HEIGHT = 640, 360
SEC = 600_000
T = SEC // 2
BOX = (220, 120, 420, 240)
MARGIN = 3
ROWS = ["C0", "A1", "G0", "U0", "P6", "MM", "V5", "H0", "B0", "A2", "N0", "R0",
        "L1", "L2", "L3", "Z1"]
P_ROWS = {"C0", "A1", "G0", "U0", "P6", "MM", "V5", "H0", "B0", "A2", "N0", "R0"}
L_ROWS = {"L1", "L2", "L3"}
MODES = ["none", "alpha", "alpha_inverted", "luma", "luma_inverted"]
# name: (file, anchor, replacement, the rows that must fail)
MUTANTS = {
    "shader-no-multiply": (
        "app/Resources/Shaders/Compositor.metal",
        "    alpha *= matte.sample(samp, canvasPixels(",
        "    alpha *= 1.0 + 0.0 * matte.sample(samp, canvasPixels(", ["A1", "A2", "L1"]),
    "source-drawn": (
        "app/Sources/Compositor.swift",
        "            if layer.matte?.into != nil { continue }",
        "            if layer.matte?.into != nil {}", ["A1", "B0", "MM"]),
    "resolve-mode-ignored": (
        "app/Resources/Shaders/Compositor.metal",
        "    int mode = int(u.mode + 0.5);",
        "    int mode = kMatteAlpha;", ["A2", "L1", "L2", "L3"]),
    "core-no-prune": (
        "core/src/recipe_matte.rs",
        "                .any(|r| r.into.as_ref().is_some_and(|(k, _)| k == key))",
        "                .any(|r| r.into.as_ref().is_some_and(|(k, _)| k == key) || true)",
        ["V5", "H0"]),
    "core-matte-behind-matte": (
        "core/src/recipe_matte.rs",
        "    behind.matte.is_none().then_some(behind.id)",
        "    Some(behind.id)", ["MM"]),
    "core-untargeted-into-null": (
        "core/src/recipe_matte.rs",
        "            let into = role.into.as_ref().map(|(k, mode)| id_of(k, *mode));",
        "            let into = role.into.as_ref().filter(|(k, _)| listed(k))"
        ".map(|(k, mode)| id_of(k, *mode));", ["B0", "MM", "CT"]),
    "core-no-override": (
        "core/src/recipe.rs",
        "self.layer(instance, t, &assignment, *drawn_into, matte)",
        "self.layer(instance, t, &assignment, false && *drawn_into, matte)", ["P6"]),
    "handler-drops-matte": (
        "app/Sources/AgentServer+Tracks.swift",
        "solo: solo, matte: matte)",
        "solo: solo, matte: nil)", ["A1", "G0"]),
}
rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


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


class Doc:
    """One open project and the calls the rows make on it."""

    def __init__(self, client, path):
        self.client = client
        self.path = path

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def tracks(self):
        return self.project().get("tracks") or []

    def track(self, track):
        return next((t for t in self.tracks() if t.get("id") == track), {})

    def new_track(self):
        """A track at the front; its id, or None."""
        before = {t.get("id") for t in self.tracks()}
        self.call("add_track")
        made = [t.get("id") for t in self.tracks() if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def place(self, tool, **arguments):
        """One clip added; its id, or None."""
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def matte(self, track, mode):
        return self.call("set_track", track=track, matte=mode)

    def frame(self, tag):
        """`render_frame` at T; (PNG bytes, RGBA bytes) or (None, None)."""
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=T, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            return None, None
        return out.read_bytes(), rgba(out)


def rgba(path):
    """A PNG at `path` as RGBA bytes through ffmpeg, or None — bounded."""
    try:
        width, height = struct.unpack(">II", Path(path).read_bytes()[16:24])
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo",
                              "-pix_fmt", "rgba", "-"], capture_output=True, timeout=120,
                             env=bounded.child_env()).stdout
    except (OSError, struct.error, subprocess.TimeoutExpired):
        return None
    return raw if (width, height) == (WIDTH, HEIGHT) and len(raw) == width * height * 4 \
        else None


def px(raw, x, y):
    at = (y * WIDTH + x) * 4
    return tuple(raw[at:at + 3])


def region(inside):
    """Every pixel of the INSIDE (box less MARGIN) or the OUTSIDE (more than
    MARGIN from the box)."""
    x0, y0, x1, y1 = BOX
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if inside:
                if x0 + MARGIN <= x < x1 - MARGIN and y0 + MARGIN <= y < y1 - MARGIN:
                    yield x, y
            elif not (x0 - MARGIN <= x < x1 + MARGIN and y0 - MARGIN <= y < y1 + MARGIN):
                yield x, y


def matches(got, want, points, tolerance=1):
    """(every point within `tolerance` per channel, the first miss)."""
    if got is None or want is None:
        return False, "a frame is missing"
    for x, y in points:
        a, b = px(got, x, y), px(want, x, y)
        if max(abs(p - q) for p, q in zip(a, b)) > tolerance:
            return False, f"({x},{y}) {a} vs {b}"
    return True, ""


def formula(got, samples, tolerance=1):
    """Each (x, y, expected rgb) within `tolerance`; (ok, first miss, count)."""
    if got is None:
        return False, "the frame is missing", 0
    for x, y, want in samples:
        a = px(got, x, y)
        if max(abs(p - round(q)) for p, q in zip(a, want)) > tolerance:
            return False, f"({x},{y}) {a} vs {tuple(round(q, 2) for q in want)}", len(samples)
    return True, "", len(samples)


def luma(rgb):
    return (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255.0


def mix(a, b, g):
    """a·g + b·(1 − g), per channel."""
    return tuple(p * g + q * (1 - g) for p, q in zip(a, b))


def make_movie():
    movie = WORK / "testsrc2.mp4"
    made = bounded.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={WIDTH}x{HEIGHT}:rate=30:duration=2",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(movie)], 120)
    return movie if made["rc"] == 0 and movie.exists() else None


def canvas(doc, background=None):
    arguments = {"width": WIDTH, "height": HEIGHT, "fps": [30, 1]}
    if background is not None:
        arguments["background"] = background
    doc.call("set_canvas", **arguments)
    c = doc.project().get("canvas") or {}
    return c.get("width") == WIDTH and c.get("height") == HEIGHT and c.get("fps") == [30, 1]


def movie_clip(doc, movie, track):
    media = reply(doc.call("import_media", path=str(movie))).get("media")
    if media is None:
        return None
    return doc.place("add_clip", track=track, media=media, at=0)


def shape(doc, track, patch):
    return doc.place("add_shape_clip", track=track, at=0, duration=2 * SEC,
                     shape=dict({"kind": "rectangle", "stroke": None}, **patch))


def run_p(client, movie, state):
    """Project P's rows. Answers whether the project closed."""
    p = WORK / "P.reelcut"
    made = attempt(client, "new_project", {"path": str(p)})
    doc = Doc(client, p)
    sized = canvas(doc)
    a_track = (doc.tracks() or [{}])[0].get("id")
    a = movie_clip(doc, movie, a_track)
    b_track = doc.new_track()
    b = shape(doc, b_track, {"width": 200, "height": 120, "fill": [1, 1, 1, 1]})
    plain_png, plain = doc.frame("plain")
    again_png, _ = doc.frame("plain-again")
    doc.call("set_track", track=b_track, hidden=True)
    _, alone = doc.frame("a-alone")
    doc.call("set_track", track=a_track, hidden=True)
    _, bg = doc.frame("bg")
    doc.call("set_track", track=a_track, hidden=False)
    doc.call("set_track", track=b_track, hidden=False)
    fixture = (made["ok"] and sized and a is not None and b is not None
               and None not in (plain, alone, bg) and plain != alone)
    state["fixture"] = fixture
    check("C0 CONTROL: the fixture holds and two renders of PLAIN are byte-equal",
          fixture and plain_png is not None and plain_png == again_png,
          f"new {made.get('error', 'ok')}; canvas {sized}; movie clip {a}; shape {b}")
    inside, outside = list(region(True)), list(region(False))

    # A1
    set_alpha = doc.matte(b_track, "alpha")
    m_png, matted = doc.frame("alpha")
    in_ok, in_miss = matches(matted, alone, inside)
    out_ok, out_miss = matches(matted, bg, outside)
    check("A1 alpha: INSIDE is A-ALONE's bytes and OUTSIDE is BG's",
          set_alpha["ok"] and in_ok and out_ok,
          f"set {set_alpha.get('error', 'ok')}; inside {in_miss or 'ok'}; "
          f"outside {out_miss or 'ok'}")

    # G0, first half
    shown = doc.track(b_track).get("matte")

    # U0
    undone = doc.call("undo")
    u_png, _ = doc.frame("undone")
    redone = doc.call("redo")
    r_png, _ = doc.frame("redone")
    check("U0 undo brings PLAIN's bytes back, redo A1's",
          undone["ok"] and redone["ok"] and u_png == plain_png and r_png == m_png
          and m_png is not None,
          f"undo {undone.get('error', 'ok')}; redo {redone.get('error', 'ok')}")

    # P6
    styled = doc.call("set_video", clips=[b], patch={
        "blend": "multiply",
        "shadow": {"color": [0, 0, 0, 1], "opacity": 1, "blur": 0, "distance": 24,
                   "angle": 315},
        "reflection": {"opacity": 1, "height": 1, "gap": 0, "falloff": 0}})
    p6_png, _ = doc.frame("p6")
    p6_undo = doc.call("undo")
    check("P6 the matte clip's multiply, shadow and reflection leave A1's bytes unchanged",
          styled["ok"] and p6_png == m_png and m_png is not None and p6_undo["ok"],
          f"set_video {styled.get('error', 'ok')}; undo {p6_undo.get('error', 'ok')}")

    # MM
    c_track = doc.new_track()
    c = shape(doc, c_track, {"width": 100, "height": 120, "fill": [1, 0, 0, 1]})
    moved = doc.call("set_video", clips=[c], patch={"x": -50}) if c is not None else {}
    c_matte = doc.matte(c_track, "alpha")
    mm_png, mm = doc.frame("mm")
    removed = doc.call("remove_track", track=c_track, with_clips=True)
    in_ok, in_miss = matches(mm, alone, inside)
    out_ok, out_miss = matches(mm, bg, outside)
    check("MM a matte in front of a matte draws nothing and cuts nothing; B still cuts A",
          c is not None and moved.get("ok") and c_matte["ok"] and mm_png == m_png
          and m_png is not None and in_ok and out_ok and removed["ok"],
          f"C {c}; move {moved.get('error', 'ok')}; matte {c_matte.get('error', 'ok')}; "
          f"A1's bytes {mm_png == m_png}; inside {in_miss or 'ok'}; outside "
          f"{out_miss or 'ok'}; remove {removed.get('error', 'ok')}")

    # V5
    trimmed = doc.call("trim_end", clip=b, to=SEC // 4)
    _, v5 = doc.frame("v5")
    v5_undo = doc.call("undo")
    v5_ok, v5_miss = matches(v5, alone, inside + outside, tolerance=0)
    check("V5 the matte clip trimmed away at t: the frame is A-ALONE's bytes",
          trimmed["ok"] and v5_ok and v5_undo["ok"],
          f"trim {trimmed.get('error', 'ok')}; {v5_miss or 'equal'}")

    # H0
    hid = doc.call("set_track", track=b_track, hidden=True)
    _, h0 = doc.frame("h0")
    shown_again = doc.call("set_track", track=b_track, hidden=False)
    h0_ok, h0_miss = matches(h0, alone, inside + outside, tolerance=0)
    check("H0 the matte track hidden: the frame is A-ALONE's bytes",
          hid["ok"] and h0_ok and shown_again["ok"], h0_miss or "equal")

    # B0
    small = doc.call("set_video", clips=[a], patch={"scale": 0.25})
    doc.call("set_track", track=b_track, hidden=True)
    _, alone_small = doc.frame("a-alone-small")
    doc.call("set_track", track=b_track, hidden=False)
    to_back = doc.call("move_track", track=b_track, index=0)
    _, b0 = doc.frame("b0")
    back = doc.call("move_track", track=b_track, index=1)
    big = doc.call("set_video", clips=[a], patch={"scale": 1})
    b0_ok, b0_miss = matches(b0, alone_small, inside + outside, tolerance=0)
    check("B0 a back-most matte draws nothing and A is uncut",
          small["ok"] and to_back["ok"] and back["ok"] and big["ok"] and b0_ok
          and alone_small != alone,
          f"scale {small.get('error', 'ok')}; move {to_back.get('error', 'ok')}; "
          f"{b0_miss or 'equal'}")

    # A2
    inverted = doc.matte(b_track, "alpha_inverted")
    _, a2 = doc.frame("alpha-inverted")
    in_ok, in_miss = matches(a2, bg, inside)
    out_ok, out_miss = matches(a2, alone, outside)
    check("A2 alpha_inverted: INSIDE is BG's bytes and OUTSIDE is A-ALONE's",
          inverted["ok"] and in_ok and out_ok,
          f"set {inverted.get('error', 'ok')}; inside {in_miss or 'ok'}; "
          f"outside {out_miss or 'ok'}")

    # N0, and G0's second half
    off = doc.matte(b_track, "none")
    n0_png, _ = doc.frame("none")
    check("N0 matte none brings PLAIN's bytes back",
          off["ok"] and n0_png == plain_png and plain_png is not None,
          off.get("error", "ok"))
    track_b = doc.track(b_track)
    check("G0 get_project shows matte \"alpha\", and no matte key after none",
          shown == "alpha" and "matte" not in track_b and track_b.get("id") == b_track,
          f"while alpha {shown!r}; after none {json.dumps(track_b)}")

    # R0
    before = doc.project()
    refused = doc.matte(b_track, "chroma")
    error = refused.get("error", "")
    check("R0 matte \"chroma\" is refused naming the five modes; the project is unchanged",
          not refused["ok"] and all(mode in error for mode in MODES)
          and "chroma" in error and doc.project() == before,
          f"answer {error or refused.get('reply')!r}")

    closed = attempt(client, "close_project", {"project": str(p), "discard": True})
    return closed["ok"]


def run_l(client, movie, state):
    """Project L's rows. Answers whether the project closed."""
    path = WORK / "L.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0.4, 0.2, 0.1, 1])
    card_track = (doc.tracks() or [{}])[0].get("id")
    card = shape(doc, card_track, {"width": WIDTH, "height": HEIGHT,
                                   "fill": [0.2, 0.6, 0.9, 1]})
    grad_track = doc.new_track()
    grad = shape(doc, grad_track, {
        "width": 400, "height": 200, "fill": [1, 1, 1, 1],
        "gradient": {"kind": "linear", "angle": 0,
                     "stops": [{"at": 0, "color": [0, 0, 0, 1]},
                               {"at": 1, "color": [1, 1, 1, 1]}]}})
    doc.call("set_track", track=card_track, hidden=True)
    _, gradient = doc.frame("gradient")
    doc.call("set_track", track=grad_track, hidden=True)
    _, bg = doc.frame("l-bg")
    doc.call("set_track", track=card_track, hidden=False)
    _, card_alone = doc.frame("card")
    doc.call("set_track", track=grad_track, hidden=False)
    fixture = (made["ok"] and sized and card is not None and grad is not None
               and None not in (gradient, bg, card_alone))
    state["l_fixture"] = fixture
    if not fixture:
        print(f"       project L's fixture did not hold: new {made.get('error', 'ok')}; "
              f"canvas {sized}; card {card}; gradient {grad}", flush=True)
    # Inside the gradient's box (120–520 × 80–280), less MARGIN, every 4 px on
    # its middle row; outside, a ring of points clear of it.
    inner = [(x, 180) for x in range(120 + MARGIN, 520 - MARGIN, 4)]
    outer = [(40, 40), (60, 180), (600, 180), (320, 20), (320, 340), (110, 300)]
    lumas = {(x, y): luma(px(gradient, x, y)) for x, y in inner} if gradient else {}
    spread = (min(lumas.values()), max(lumas.values())) if lumas else (0, 0)
    ramp = spread[0] < 0.1 and spread[1] > 0.9

    for name, mode in (("L1", "luma"), ("L2", "luma_inverted")):
        set_ = doc.matte(grad_track, mode)
        _, got = doc.frame(mode)
        samples = []
        if fixture:
            for x, y in inner:
                g = lumas[(x, y)] if mode == "luma" else 1 - lumas[(x, y)]
                samples.append((x, y, mix(px(card_alone, x, y), px(bg, x, y), g)))
            for x, y in outer:
                samples.append((x, y, px(bg if mode == "luma" else card_alone, x, y)))
        ok, miss, count = formula(got, samples)
        expected = "card·g + bg·(1 − g)" if mode == "luma" else "card·(1 − g) + bg·g"
        check(f"{name} {mode}: inside, {expected}; outside, "
              f"{'BG' if mode == 'luma' else 'CARD'} (±1)",
              fixture and ramp and set_["ok"] and ok and count > 0,
              f"set {set_.get('error', 'ok')}; g {spread[0]:.3f}…{spread[1]:.3f}; "
              f"{count} samples; {miss or 'all within'}")

    # L3: the movie as the luma matte.
    removed = doc.call("remove_track", track=grad_track, with_clips=True)
    movie_track = doc.new_track()
    clip = movie_clip(doc, movie, movie_track) if movie_track is not None else None
    doc.call("set_track", track=card_track, hidden=True)
    _, movie_alone = doc.frame("movie-alone")
    doc.call("set_track", track=card_track, hidden=False)
    set_ = doc.matte(movie_track, "luma")
    _, got = doc.frame("movie-luma")
    samples = []
    if fixture and movie_alone is not None:
        for y in (20, 100, 180, 260, 340):
            for x in range(4, WIDTH, 8):
                g = luma(px(movie_alone, x, y))
                samples.append((x, y, mix(px(card_alone, x, y), px(bg, x, y), g)))
    ok, miss, count = formula(got, samples)
    check("L3 the movie as a luma matte over the card: card·g + bg·(1 − g), g from the "
          "movie alone (±1)",
          fixture and removed["ok"] and clip is not None and set_["ok"] and ok and count > 0,
          f"remove {removed.get('error', 'ok')}; clip {clip}; set {set_.get('error', 'ok')}; "
          f"{count} samples; {miss or 'all within'}")

    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


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


def launch(binary, log):
    return mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                      log_path=str(log), timeout=CALL_BOUND)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's anchor replaced, built by its own
    `tree_copy.build_app`. (app bundle, copy) or (None, why)."""
    path, anchor, replacement, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if path.startswith("core/"):
        reason = own_core(copy)
        if reason:
            return None, reason
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            return None, f"the copy's core/tests could not be linked: {error}"
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
    return app, copy


def core_test(copy):
    """`cargo test --release --test matte` in the copy's own core: whether it
    passed, and its last lines."""
    ran = bounded.run(["cargo", "test", "--release", "--test", "matte"], 900,
                      cwd=str(copy / "core"))
    lines = (ran["stdout"] + ran["stderr"]).strip().splitlines()
    return ran["rc"] == 0 and not ran["expired"], lines[-3:]


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(proof_app.binary()))
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][3] if args.mutant else []
    scored = [name for name in ROWS if name in selected]
    binary = Path(args.app)
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    if args.mutant:
        print(f"mattes MT2 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = app / "Contents/MacOS/Reelcut"
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test matte in the "
                  "copy's core\n       " + " | ".join(last), flush=True)
            scored.append("CT")
    else:
        print("mattes MT2 — the matte track end to end, over MCP", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    movie = make_movie()
    if movie is None:
        print("instrument failure: ffmpeg did not make the testsrc2 movie")
        return 2
    log = WORK / "instance.log"
    state = {}
    launched = launch(binary, log)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        support = HOME / "Library/Application Support"
        if not support.is_dir():
            print(f"instrument failure: the scratch home did not take ({support})")
            return 2
        try:
            if selected & P_ROWS:
                closed = run_p(launched.client, movie, state) and closed
            if selected & L_ROWS:
                closed = run_l(launched.client, movie, state) and closed
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("Z1 CONTROL: the projects close and the log holds no `Reelcut: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        missing = [name for name in named if name not in rows]
        fixture = state.get("fixture") is not False and state.get("l_fixture") is not False
        if missing or not fixture:
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}, fixture P {state.get('fixture')}, L "
                  f"{state.get('l_fixture')}")
            return 2
        survived = [name for name in named if rows.get(name)]
        failed = [name for name in scored if not rows.get(name)]
        caught = not survived
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if caught else 'did not all fail'} in the "
              f"copy (failed: {', '.join(failed) or 'none'}; survived: "
              f"{', '.join(survived) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
