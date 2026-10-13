#!/usr/bin/env python3
"""Road map "grading-2", phase G2-2 (spec §11 GR-11) — the colour wheels end to
end over MCP: `set_video {patch: {wheels: {lift|gamma|gain: {x, y, master}}}}`,
the recipe's `wheels`, and the compositor's step 4c.1 behind `wheelsEnabled`
in the layer stage and the adjustment pass, read back as `render_frame` bytes
and one export; then the probe's rows over `app/Sources`.

    python3 tools/proof/wheels_proof.py [--app PATH] [--only L1,G1,...]
    python3 tools/proof/wheels_proof.py capture DIR    # the neutral control, before any product edit
    python3 tools/proof/wheels_proof.py compare DIR    # every row, and N0 against DIR
    python3 tools/proof/wheels_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/wheels/home`, and
every package, fixture and PNG is under `tools/proof/work/wheels/`, removed at
the start and at exit (the control folder DIR is not). No menu item is
performed. Every call is bounded (`CALL_BOUND`), every ffmpeg too (120 s).
Every project is closed (`close_project`, discard).

Fixtures, written by this script (as `tone_proof.py`'s): CARD, a 640×360
grey-128 PNG; RAMP, a 1920×360 PNG whose column x is round(255·x/1919); MOVIE,
a 2 s 640×360 30 fps ffmpeg `testsrc2` H.264 file. Frames are taken at t = 0.5 s
unless a row says otherwise; v is the neutral render's own value at the sample
(8 bits), so every formula is over measured bytes, ±1 a channel. Y′ is Rec. 709
luma of the 8-bit codes. A push "toward h" is `{x: cos h, y: sin h}`, radius 1.

Projects, each 30 fps: C (640×360, CARD), R (1920×360, RAMP), M (640×360, MOVIE,
background black), S (CARD, saved twice for N2), P (two CARD clips on two
tracks, lift masters 0.2 and −0.2, saved for the probe).
- **N0** (`compare DIR` only; scored on Release, printed elsewhere): six
  frames with no wheel — card, card-toned (exposure +1), card-adjusted (an
  adjustment clip at exposure +1 over the card), ramp, ramp-looked (Warm),
  movie — decoded at 16 bits a channel are byte-identical to `capture DIR`'s,
  taken on the untouched tree's Release build.
- **N1** (C): an all-zero wheels patch (all nine keys) answers "made no
  change" and the frame is unchanged.
- **N2** (S): saved neutral, `project.json` holds no `wheels`; saved with lift x
  0.2, the clip's `video.wheels` is exactly `{"lift": {"x": 0.2}}`; both
  files' `version` is the header's `RC_FORMAT_VERSION` (16 when this phase
  wrote it; read off the header since G2-3's 17).
- **L1** (R): lift master 0.5: every 16th column = v + 0.125(255 − v) ±1, and
  255 stays 255.
- **G1** (R): gain master +0.5 = v·1.25, then −0.5 = v·0.75, ±1; 0 stays 0.
- **Y1** (R): gamma master 0.5 = 255(v/255)^(2^−0.5) ±1; 0 and 255 exact.
- **C1** (C): mid-grey (a NEUTRAL pixel; GR-11 claims luma-neutrality only
  there), each wheel at radius 1 toward 0°, 60° … 300°: Y′ within ±1 of the
  neutral's (lift, gain) or ±2 (gamma), every channel the pushed hue holds at
  full rises and every other channel falls.
- **O1** (C): exposure +1, then lift master 0.5 on top: every sample =
  t + 0.125(255 − t) ±1, t the exposure-alone frame's value (4c.1 after 4c:
  175 → 185, where lift first then tone gives about 197). Lift, not gain: gain and
  exposure nearly commute on encoded values (219 against 218), so a gain row
  could not tell the two orders apart.
- **A1** (C): a 1 s action from neutral to lift x 0.6: at 0.5 s every channel
  that moves by 2 or more lies strictly between the neutral value and the
  static lift x 0.6 frame's, and at 1.5 s the frame is the static one's bytes.
- **J1** (C): an adjustment clip with gain master 0.5 over the card renders the
  card graded directly with gain 0.5, ±1 at every sample.
- **X1** (M): lift x 0.5 and gain master 0.5 on the movie: the `prores_422`
  export's frame 15 is within ±8 of `render_frame` at every 16th pixel, and the
  graded frame differs from the neutral by more than 30 somewhere.
- **U1** (C): undo after lift master 0.5 brings the neutral pixels back, redo
  the graded ones.
- **V1** (C): with lift x 0.5 and gain master 0.3 set, `render_frame
  {ungraded: true}` is the neutral bytes (and the plain frame is not).
- **P0** (C): `paste_attributes` of a payload clip whose video holds wheels
  leaves the target's `video.wheels` equal to the payload's.
- **R1** (C): lift x 1.5 and lift {x 0.9, y 0.6} are refused by their two
  sentences and the project is unchanged.
- **P1–P7**: `wheels_probe.swift`, built by `swift_build.build` over
  `app/Sources` (a failed build is a scored FAILURE of all seven), on project P:
  P1 a puck drag over two clips (masters 0.2 / −0.2) is ONE live gesture ended
  "Lift" whose every update sends one `set_video` naming both with a patch of
  exactly `{wheels: {lift: {x, y}}}`; P2 `apply(wheels:)` sets `wheelsEnabled` 1
  for gain master −0.5 alone and 0 for neutral; P3 `LayerUniforms` is 512 bytes
  with `liftX` at 464 and `wheelsEnabled` at 500; P4 `keyedCount` for `{video:
  {wheels: …, x: 3}}` is 1 on Color and 1 on Picture; P5 an ⌥ drag moves the
  puck a tenth of a plain one, and a press on the strip's knob grabs it with no
  write, so a double-click there is the reset alone; and, on a fresh document
  per case (#272), a double-click off the Lift strip's knob is ONE undo step
  back to (0.2, −0.2), a reset after an edit between the clicks is its own
  step (one undo lands on that edit's 0.5), and an identity jump (master −1,
  press at −1) amends no older step (one undo lands on −1); P6 a double-click
  on the disc resets x and y only,
  one step "Lift"; P7 10,000 drags past the rim at even angles each land with
  x² + y² ≤ 1 + 1e-9.
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds no
  `Reelcut: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`
and links the tree's `core/tests`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row on it, the probe built
over the copy's `app/Sources`. A core mutant also runs `cargo test --release
--no-fail-fast --test wheels --test schema_v16 --test ungraded` in the copy's
own `core/` (row CT). MUTANT PASS when every named row FAILED and no other
scored row did:
  wheels-before-tone      step 4c.1 moved before 4c: O1
  gamma-sign              gamma's exponent sign flipped: Y1 C1 (a gamma push
                          lowers the hue's own channels)
  push-not-luma-neutral   the full hue pushed, not its chroma: C1
  flag-ignores-negative   `wheelsEnabled` only for a positive value: G1 C1 P2
                          (C1's 240° push has x and y both negative)
  circle-check-dropped    the x² + y² ≤ 1 refusal gone: R1 CT
  rim-tolerance-dropped   the circle test exact (no 1e-9): CT (wheels.rs's
                          rim and split cases)
  ungraded-misses-wheels  `ungraded` keeps the wheels: V1 CT
  adjust-without-wheels   the adjustment pass has no step 4c.1: J1
  puck-writes-group       a puck write sends the whole wheel: P1
  strip-reset-not-amending  a strip's double-click always its own step
                          (#272): P5 (case a)
  amend-ignores-step      `applyEdit(_:_:amending:)` undoes whatever is last,
                          an edit between the clicks included: P5 (case b)
  amend-without-step      a strip's release keeps its handle even when the
                          gesture made no step: P5 (case c)
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import json
import math
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "core/include/reelcut_core.h"
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402

WORK = ROOT / "tools/proof/work/wheels"
HOME = WORK / "home"
PROBE = ROOT / "tools/proof/wheels_probe.swift"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
T = SEC // 2
CARD_W, CARD_H = 640, 360
RAMP_W, RAMP_H = 1920, 360
GREY = 128
WHEELS = ["lift", "gamma", "gain"]
LUMA = (0.2126, 0.7152, 0.0722)
NEUTRAL = ["card", "card-toned", "card-adjusted", "ramp", "ramp-looked", "movie"]
ROWS = ["N0", "N1", "N2", "L1", "G1", "Y1", "C1", "O1", "A1", "J1", "X1", "U1", "V1", "P0",
        "R1", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "Z1"]
RECORDS = set()
C_ROWS = {"N1", "C1", "O1", "A1", "J1", "U1", "V1", "P0", "R1"}
R_ROWS = {"L1", "G1", "Y1"}
M_ROWS = {"X1"}
P_ROWS = {"P1", "P2", "P3", "P4", "P5", "P6", "P7"}
SHADER = "app/Resources/Shaders/Compositor.metal"
STEP_4C = "        // (4c) Tone (spec §11 GR-2): once per pixel, after the regions' own\n"
STEP_4C1 = ("        // (4c.1) The wheels (spec §11 GR-11): once per pixel, after tone and\n"
            "        // before the look. Behind `wheelsEnabled`, so an unwheeled layer never\n"
            "        // enters it.\n"
            "        if (u.wheelsEnabled > 0.5) {\n"
            "            rgb = gradeWheels(rgb, u);\n"
            "        }\n\n")
ADJUST_4C1 = ("    if (u.wheelsEnabled > 0.5) {\n"
              "        c = gradeWheels(c, u);\n"
              "    }\n")
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "wheels-before-tone": ([
        (SHADER, STEP_4C1, ""),
        (SHADER, STEP_4C, STEP_4C1 + STEP_4C)], ["O1"]),
    "gamma-sign": ([(
        SHADER,
        "    v = pow(max(v, 0.0), exp2(-gamma * kGamma));\n",
        "    v = pow(max(v, 0.0), exp2(gamma * kGamma));\n")], ["Y1", "C1"]),
    "push-not-luma-neutral": ([(
        SHADER,
        "    return master + kWheelPush * length(float2(x, y)) * lookHueChroma(h);\n",
        "    return master + kWheelPush * length(float2(x, y))\n"
        "        * saturate(abs(fmod(h / 60.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0);\n")],
        ["C1"]),
    "flag-ignores-negative": ([(
        "app/Sources/GradeProps.swift",
        "wheelsEnabled = values.contains { $0 != 0 } ? 1 : 0",
        "wheelsEnabled = values.contains { $0 > 0 } ? 1 : 0")], ["G1", "C1", "P2"]),
    "circle-check-dropped": ([(
        "core/src/grade_check.rs",
        "        if wheel.x * wheel.x + wheel.y * wheel.y > 1.0 + WHEEL_RIM_TOLERANCE {\n",
        "        if false {\n")], ["R1", "CT"]),
    "rim-tolerance-dropped": ([(
        "core/src/grade_check.rs",
        "        if wheel.x * wheel.x + wheel.y * wheel.y > 1.0 + WHEEL_RIM_TOLERANCE {\n",
        "        if wheel.x * wheel.x + wheel.y * wheel.y > 1.0 {\n")], ["CT"]),
    "ungraded-misses-wheels": ([(
        "core/src/recipe.rs",
        "        moved.wheels = Wheels::default();\n",
        "")], ["V1", "CT"]),
    "adjust-without-wheels": ([(SHADER, ADJUST_4C1, "")], ["J1"]),
    "puck-writes-group": ([(
        "app/Sources/VideoPane+Wheels.swift",
        "                let moved = ColorWheelPatch(x: x, y: y)\n",
        "                let moved = ColorWheelPatch(x: x, y: y, master: master())\n")],
        ["P1"]),
    "strip-reset-not-amending": ([(
        "app/Sources/VideoPane+Wheels.swift",
        "            binding?.amend(name, ops, step: last.step)\n",
        "            binding?.apply(name, ops)\n")], ["P5"]),
    "amend-ignores-step": ([(
        "app/Sources/ProjectDocument+UndoGroup.swift",
        "        if project === step, !isLiveEditing,",
        "        if true, !isLiveEditing,")], ["P5"]),
    "amend-without-step": ([(
        "app/Sources/VideoPane+Wheels.swift",
        "        if let after = binding?.document?.project, after !== stripStarts[kind] {\n",
        "        if let after = binding?.document?.project {\n")], ["P5"]),
}
rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    record = key in RECORDS
    mark = "  rec  " if record else ("  ok   " if good else "  FAIL ")
    print(mark + name + (f"\n       {detail}" if detail else ""), flush=True)


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

def write_png(path, width, height, value_of_x):
    """An 8-bit RGB PNG, untagged, whose column x is grey `value_of_x(x)`."""
    row = bytes([0]) + b"".join(bytes([value_of_x(x)] * 3) for x in range(width))
    raw = row * height

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return path


def decode(path, width, height, deep=False):
    """`path` (a PNG or a movie's first frame) as RGBA bytes through ffmpeg —
    `rgba64le` when `deep` — or None; bounded."""
    fmt, size = ("rgba64le", 8) if deep else ("rgba", 4)
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-frames:v", "1",
                              "-f", "rawvideo", "-pix_fmt", fmt, "-"], capture_output=True,
                             timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw if len(raw) == width * height * size else None


class Frame:
    """One decoded frame: `raw` RGBA bytes, `width`, and the PNG's path."""

    def __init__(self, path, raw, width):
        self.path, self.raw, self.width = path, raw, width

    def px(self, x, y):
        at = (y * self.width + x) * 4
        return tuple(self.raw[at:at + 3])


def code(value):
    return round(255 * min(max(value, 0.0), 1.0))


def luma(rgb):
    return sum(w * c for w, c in zip(LUMA, rgb))


def close_to(got, want, tolerance=1):
    return all(abs(a - b) <= tolerance for a, b in zip(got, want))


def same_pixels(a, b):
    return a is not None and b is not None and a.raw == b.raw


def full_hue(degrees):
    """The HSV ramp's fully saturated hue (the shader's `lookHueChroma` before
    its luma is taken off)."""
    return tuple(min(max(abs(((degrees / 60 + o) % 6) - 3) - 1, 0.0), 1.0) for o in (0, 4, 2))


def toward(degrees):
    rad = math.radians(degrees)
    return {"x": math.cos(rad), "y": math.sin(rad)}


GRID = [(x, y) for y in range(20, CARD_H, 40) for x in range(20, CARD_W, 40)]


# ---- the documents ------------------------------------------------------------

class Doc:
    """One open project and the calls the rows make on it."""

    def __init__(self, client, path, width, height):
        self.client, self.path, self.width, self.height = client, path, width, height

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def tracks(self):
        return self.project().get("tracks") or []

    def new_track(self):
        before = {t.get("id") for t in self.tracks()}
        self.call("add_track")
        made = [t.get("id") for t in self.tracks() if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def added(self, tool, **arguments):
        """`tool` that places one clip; its id, or None."""
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def place(self, track, media):
        return self.added("add_clip", track=track, media=media, at=0)

    def media(self, path):
        return reply(self.call("import_media", path=str(path))).get("media")

    def clip(self, clip):
        return next((c for c in self.project().get("clips") or [] if c.get("id") == clip), {})

    def wheels(self, clips, **wheels):
        return self.call("set_video", clips=clips, patch={"wheels": wheels})

    def color(self, clips, **keys):
        return self.call("set_video", clips=clips, patch={"color": keys})

    def neutralise(self, clips):
        return self.wheels(clips, **{w: {"x": 0, "y": 0, "master": 0} for w in WHEELS})

    def frame(self, tag, t=T, **options):
        """`render_frame` at `t`, decoded; a Frame, or None."""
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out), **options)
        raw = decode(out, self.width, self.height) if got["ok"] and out.exists() else None
        if raw is None:
            print(f"       render {tag}: {got.get('error', 'no file or a wrong size')}",
                  flush=True)
            return None
        return Frame(out, raw, self.width)


def opened(client, name, width, height, background=None):
    """A new project at `name`, its canvas sized; (Doc, fixture ok)."""
    path = WORK / f"{name}.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path, width, height)
    arguments = {"width": width, "height": height, "fps": [30, 1]}
    if background is not None:
        arguments["background"] = background
    doc.call("set_canvas", **arguments)
    c = doc.project().get("canvas") or {}
    return doc, made["ok"] and c.get("width") == width and c.get("height") == height


def close(client, path):
    return attempt(client, "close_project", {"project": str(path), "discard": True})["ok"]


def fixtures():
    card = write_png(WORK / "card.png", CARD_W, CARD_H, lambda x: GREY)
    ramp = write_png(WORK / "ramp.png", RAMP_W, RAMP_H, lambda x: round(255 * x / (RAMP_W - 1)))
    movie = WORK / "testsrc2.mp4"
    made = bounded.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={CARD_W}x{CARD_H}:rate=30:duration=2",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(movie)], 120)
    return card, ramp, (movie if made["rc"] == 0 and movie.exists() else None)


# ---- N0: the neutral frames ---------------------------------------------------

class Neutral:
    """Where the neutral frames go: `capture` writes them to DIR, `compare`
    holds each against DIR's, a plain run only keeps them."""

    def __init__(self, mode, folder):
        self.mode, self.folder, self.misses, self.seen = mode, folder, [], []

    def take(self, doc, name):
        frame = doc.frame(f"neutral-{name}")
        self.seen.append(name)
        if frame is None:
            self.misses.append(f"{name}: no frame")
            return None
        if self.mode == "capture":
            (self.folder / f"{name}.png").write_bytes(frame.path.read_bytes())
        elif self.mode == "compare":
            want = decode(self.folder / f"{name}.png", doc.width, doc.height, deep=True)
            got = decode(frame.path, doc.width, doc.height, deep=True)
            if want is None or got is None:
                self.misses.append(f"{name}: {'no control' if want is None else 'no decode'}")
            elif want != got:
                differ = sum(1 for i in range(0, len(got), 2) if got[i:i + 2] != want[i:i + 2])
                self.misses.append(f"{name}: {differ} of {len(got) // 2} 16-bit samples differ")
        return frame


# ---- project C: the card -----------------------------------------------------

def run_c(client, card, neutral, state):
    doc, sized = opened(client, "C", CARD_W, CARD_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    clip = doc.place(track, media) if media is not None else None
    base = neutral.take(doc, "card")
    v = base.px(CARD_W // 2, CARD_H // 2)[0] if base is not None else None
    fixture = sized and clip is not None and base is not None and all(
        base.px(x, y) == (v, v, v) for x, y in GRID)
    ids = [clip]
    # The tone and adjustment paths with no wheel (N0's second and third).
    toned = doc.color(ids, exposure=1) if fixture else {"ok": False}
    exposed = neutral.take(doc, "card-toned") if toned["ok"] else None
    doc.color(ids, exposure=0)
    front = doc.new_track() if fixture else None
    adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
        if front is not None else None
    adjusted = doc.color([adjustment], exposure=1) if adjustment else {"ok": False}
    neutral.take(doc, "card-adjusted") if adjusted["ok"] else None
    removed = doc.call("remove_track", track=front, with_clips=True) if front else {"ok": False}
    fixture = fixture and exposed is not None and adjusted["ok"] and removed["ok"]
    state["c_fixture"] = fixture
    print(f"  C: card clip {clip}, neutral value {v} (written {GREY})", flush=True)
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # N1
    zeros = doc.neutralise(ids)
    n1 = doc.frame("n1")
    check("N1 an all-zero wheels patch is an identity (\"made no change\") and the frame is "
          "unchanged", not zeros["ok"] and "made no change" in zeros.get("error", "")
          and same_pixels(n1, base), f"answer {zeros.get('error') or zeros.get('reply')!r}")

    # R1
    before = doc.project()
    over = doc.wheels(ids, lift={"x": 1.5})
    outside = doc.wheels(ids, lift={"x": 0.9, "y": 0.6})
    unchanged = doc.project() == before
    for got in (over, outside):  # a value accepted in error is taken back
        if got["ok"]:
            doc.call("undo")
    want_over = "video.wheels.lift.x must be between -1 and 1, not 1.5"
    want_outside = ("video.wheels.lift must lie inside the unit circle (x² + y² ≤ 1), "
                    "not x 0.9, y 0.6")
    check("R1 lift x 1.5 and lift {x 0.9, y 0.6} are refused by their sentences; the project "
          "is unchanged", not over["ok"] and want_over in over.get("error", "")
          and not outside["ok"] and want_outside in outside.get("error", "") and unchanged,
          f"x {over.get('error') or 'accepted'!r}; circle {outside.get('error') or 'accepted'!r}")

    # C1
    misses = []
    y0 = luma(base.px(CARD_W // 2, CARD_H // 2))
    for wheel, tolerance in (("lift", 1), ("gamma", 2), ("gain", 1)):
        for hue in range(0, 360, 60):
            got = doc.wheels(ids, **{wheel: toward(hue)})
            frame = doc.frame(f"c1-{wheel}-{hue}")
            doc.wheels(ids, **{wheel: {"x": 0, "y": 0}})
            if not got["ok"] or frame is None:
                misses.append(f"{wheel} {hue}°: {got.get('error', 'no frame')}")
                continue
            rgb = frame.px(CARD_W // 2, CARD_H // 2)
            full = full_hue(hue)
            rises = all(rgb[c] > v if full[c] == 1.0 else rgb[c] < v for c in range(3))
            if abs(luma(rgb) - y0) > tolerance or not rises:
                misses.append(f"{wheel} {hue}°: {rgb} Y′ {luma(rgb):.2f} vs {y0:.2f}, "
                              f"rises {rises}")
    check("C1 mid-grey, each wheel pushed to the rim toward 0°…300°: Y′ within ±1 (lift, "
          "gain) / ±2 (gamma), the hue's own channels rise and the others fall", not misses,
          "; ".join(misses[:4]) or "all within")

    # U1
    lifted = doc.wheels(ids, lift={"master": 0.5})
    u_graded = doc.frame("u1-graded")
    undone = doc.call("undo")
    u_neutral = doc.frame("u1-undone")
    redone = doc.call("redo")
    u_redone = doc.frame("u1-redone")
    check("U1 undo after lift master 0.5 brings the neutral pixels back, redo the graded ones",
          lifted["ok"] and undone["ok"] and redone["ok"] and same_pixels(u_neutral, base)
          and same_pixels(u_redone, u_graded) and not same_pixels(u_graded, base),
          f"set {lifted.get('error', 'ok')}; undo {undone.get('error', 'ok')}; redo "
          f"{redone.get('error', 'ok')}; neutral {same_pixels(u_neutral, base)}; graded "
          f"{same_pixels(u_redone, u_graded)}")
    doc.neutralise(ids)

    # V1
    pushed = doc.wheels(ids, lift={"x": 0.5}, gain={"master": 0.3})
    plain = doc.frame("v1-plain")
    ungraded = doc.frame("v1-ungraded", ungraded=True)
    check("V1 render_frame {ungraded: true} with lift x 0.5 and gain 0.3 set is the neutral "
          "bytes, and the plain frame is not", pushed["ok"] and same_pixels(ungraded, base)
          and plain is not None and not same_pixels(plain, base),
          f"set {pushed.get('error', 'ok')}; ungraded {same_pixels(ungraded, base)}; plain "
          f"graded {plain is not None and not same_pixels(plain, base)}")
    doc.neutralise(ids)

    # O1
    up = doc.color(ids, exposure=1)
    tone_only = doc.frame("o1-tone")
    lifted = doc.wheels(ids, lift={"master": 0.5})
    o1 = doc.frame("o1")
    doc.neutralise(ids)
    doc.color(ids, exposure=0)
    miss = None
    if tone_only is None or o1 is None:
        miss = "a frame is missing"
    else:
        for x, y in GRID:
            want = tuple(code(c / 255 + 0.125 * (1 - c / 255)) for c in tone_only.px(x, y))
            if not close_to(o1.px(x, y), want):
                miss = f"({x},{y}) {o1.px(x, y)} vs {want}"
                break
    check("O1 exposure +1 then lift master 0.5: every sample = t + 0.125(255 − t) ±1, t the "
          f"exposure-alone value ({tone_only.px(CARD_W // 2, CARD_H // 2) if tone_only else None}"
          f" → {o1.px(CARD_W // 2, CARD_H // 2) if o1 else None})",
          up["ok"] and lifted["ok"] and miss is None, miss or "all within")

    # J1
    direct_set = doc.wheels(ids, gain={"master": 0.5})
    direct = doc.frame("j1-direct")
    doc.neutralise(ids)
    front = doc.new_track()
    adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
        if front is not None else None
    adjust_set = doc.wheels([adjustment], gain={"master": 0.5}) if adjustment else {"ok": False}
    j1 = doc.frame("j1")
    j_misses = [(x, y, j1.px(x, y), direct.px(x, y)) for x, y in GRID
                if j1 is not None and direct is not None
                and not close_to(j1.px(x, y), direct.px(x, y))]
    check("J1 an adjustment clip with gain 0.5 over the card renders the card graded directly "
          "with gain 0.5, ±1", direct_set["ok"] and adjust_set["ok"] and j1 is not None
          and direct is not None and not j_misses and not same_pixels(direct, base),
          f"direct {direct_set.get('error', 'ok')}; adjustment {adjustment} "
          f"{adjust_set.get('error', 'ok')}; {j_misses[:3] or 'all within'}")
    if front is not None:
        doc.call("remove_track", track=front, with_clips=True)

    # P0
    wheels = {"lift": {"x": 0.3, "y": -0.2, "master": 0.1}, "gain": {"master": -0.4}}
    payload = {"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": SEC, "source": {"kind": "shape"},
        "video": {"wheels": wheels},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}}]}
    pasted = doc.call("paste_attributes", clips=ids, payload=payload)
    carried = (doc.clip(clip).get("video") or {}).get("wheels")
    check("P0 paste_attributes carries the payload's video.wheels onto the clip",
          pasted["ok"] and carried == wheels,
          f"paste {pasted.get('error', 'ok')}; target's wheels {carried}")
    if pasted["ok"]:
        doc.call("undo")

    # A1
    static_set = doc.wheels(ids, lift={"x": 0.6})
    static = doc.frame("a1-static")
    doc.neutralise(ids)
    added = doc.call("add_action", clip=clip, at=0, duration=SEC)
    actions = doc.clip(clip).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = doc.call("set_action_end", clip=clip, action=action,
                     patch={"video": {"wheels": {"lift": {"x": 0.6}}}}) if action else {"ok": False}
    mid = doc.frame("a1-mid", t=SEC // 2)
    end = doc.frame("a1-end", t=SEC + SEC // 2)
    outside_span, moving = [], 0
    if mid is not None and static is not None:
        for x, y in GRID:
            for c, (n, f, m) in enumerate(zip(base.px(x, y), static.px(x, y), mid.px(x, y))):
                if abs(f - n) >= 2:
                    moving += 1
                    if not min(n, f) < m < max(n, f):
                        outside_span.append((x, y, c, n, m, f))
    check(f"A1 a 1 s action from neutral to lift x 0.6: mid-span strictly between at "
          f"{moving} moving channels, and the end is the static frame's bytes",
          static_set["ok"] and added["ok"] and ended["ok"] and moving > 0
          and not outside_span and same_pixels(end, static),
          f"static {static_set.get('error', 'ok')}; add {added.get('error', 'ok')}; end "
          f"{ended.get('error', 'ok')}; outside {outside_span[:3]}; end bytes "
          f"{same_pixels(end, static)}")
    return close(client, doc.path)


# ---- project R: the ramp -----------------------------------------------------

def ramp_check(frame, base, y, want, ends):
    """(every 16th column within ±1 of `want(v)`, and each (x, exact) in
    `ends` exact; the first miss)."""
    if frame is None:
        return False, "the frame is missing"
    for x in range(0, RAMP_W, 16):
        v = base.px(x, y)[0]
        expected = want(v)
        if not close_to(frame.px(x, y), (expected,) * 3):
            return False, f"x {x}: v {v} → {frame.px(x, y)} vs {expected}"
    for x, exact in ends:
        if frame.px(x, y) != (exact,) * 3:
            return False, f"x {x}: {frame.px(x, y)} vs {exact} exactly"
    return True, ""


def run_r(client, ramp, neutral, state):
    doc, sized = opened(client, "R", RAMP_W, RAMP_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(ramp)
    clip = doc.place(track, media) if media is not None else None
    base = neutral.take(doc, "ramp")
    y = RAMP_H // 2
    black, white = 1, RAMP_W - 2
    fixture = (sized and clip is not None and base is not None
               and base.px(black, y) == (0, 0, 0) and base.px(white, y) == (255, 255, 255))
    ids = [clip]
    looked = doc.call("set_video", clips=ids, patch={"look": {"kind": "warm"}}) \
        if fixture else {"ok": False}
    neutral.take(doc, "ramp-looked") if looked["ok"] else None
    doc.call("set_video", clips=ids, patch={"look": None})
    fixture = fixture and looked["ok"]
    state["r_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # L1
    lifted = doc.wheels(ids, lift={"master": 0.5})
    l1 = doc.frame("l1")
    doc.neutralise(ids)
    ok, miss = ramp_check(l1, base, y, lambda v: code(v / 255 + 0.125 * (1 - v / 255)),
                          [(white, 255)])
    check("L1 lift master 0.5: v + 0.125(255 − v) ±1 along the ramp, 255 held",
          lifted["ok"] and ok, f"set {lifted.get('error', 'ok')}; {miss or 'all within'}")

    # G1
    up = doc.wheels(ids, gain={"master": 0.5})
    g_up = doc.frame("g1-up")
    down = doc.wheels(ids, gain={"master": -0.5})
    g_down = doc.frame("g1-down")
    doc.neutralise(ids)
    up_ok, up_miss = ramp_check(g_up, base, y, lambda v: code(v / 255 * 1.25), [(black, 0)])
    down_ok, down_miss = ramp_check(g_down, base, y, lambda v: code(v / 255 * 0.75),
                                    [(black, 0)])
    check("G1 gain master +0.5 = v·1.25 and −0.5 = v·0.75 ±1 along the ramp, 0 held",
          up["ok"] and down["ok"] and up_ok and down_ok,
          f"+0.5 {up.get('error', 'ok')} {up_miss or 'all within'}; −0.5 "
          f"{down.get('error', 'ok')} {down_miss or 'all within'}")

    # Y1
    raised = doc.wheels(ids, gamma={"master": 0.5})
    y1 = doc.frame("y1")
    doc.neutralise(ids)
    exponent = 2 ** -0.5
    ok, miss = ramp_check(y1, base, y, lambda v: code((v / 255) ** exponent),
                          [(black, 0), (white, 255)])
    check("Y1 gamma master 0.5 = 255(v/255)^(2^−0.5) ±1 along the ramp, 0 and 255 exact",
          raised["ok"] and ok, f"set {raised.get('error', 'ok')}; {miss or 'all within'}")
    return close(client, doc.path)


# ---- project M: the movie and an export --------------------------------------

def decoded(movie, n):
    """Frame `n` of `movie` as RGBA bytes at the card size; (None, why)."""
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(movie), "-vf", f"select=eq(n\\,{n})",
             "-fps_mode", "passthrough", "-vframes", "1", "-f", "rawvideo", "-pix_fmt",
             "rgba", "-"], capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"ffmpeg: {error}"
    return (raw, n) if len(raw) == CARD_W * CARD_H * 4 else (None, "no frame decoded")


def run_m(client, movie, neutral, state):
    doc, sized = opened(client, "M", CARD_W, CARD_H, background=[0, 0, 0, 1])
    a_track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(movie)
    clip = doc.place(a_track, media) if media is not None else None
    base = neutral.take(doc, "movie")
    fixture = sized and clip is not None and base is not None
    state["m_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # X1
    up = doc.wheels([clip], lift={"x": 0.5}, gain={"master": 0.5})
    x1 = doc.frame("x1")
    out = WORK / "X1.mov"
    exported = doc.call("export", preset="prores_422", path=str(out), size="document")
    raw, which = decoded(out, 15) if exported["ok"] and out.exists() else (None, "no file")
    samples = [(x, y) for y in range(0, CARD_H, 16) for x in range(0, CARD_W, 16)]
    misses = []
    if raw is not None and x1 is not None:
        exported_frame = Frame(out, raw, CARD_W)
        misses = [(x, y, exported_frame.px(x, y), x1.px(x, y)) for x, y in samples
                  if not close_to(exported_frame.px(x, y), x1.px(x, y), 8)]
    differs = x1 is not None and max(
        max(abs(a - b) for a, b in zip(x1.px(x, y), base.px(x, y))) for x, y in samples) > 30
    check(f"X1 the prores_422 export's frame {which} is within ±8 of render_frame at "
          f"{len(samples)} samples, and the graded frame differs from the neutral by > 30",
          up["ok"] and exported["ok"] and raw is not None and x1 is not None and not misses
          and differs,
          f"set {up.get('error', 'ok')}; export {exported.get('error', 'ok')}; "
          f"{misses[:3] or 'all within'}; differs {differs}")
    return close(client, doc.path)


# ---- project S: what a save writes (N2) --------------------------------------

def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes
    stale at every bump (`e2_proof.py`'s helper)."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


def saved_wheels(path, clip):
    """The package's `version`, `clip`'s `video.wheels` (None when absent) and
    the file's text."""
    text = (Path(path) / "project.json").read_text()
    body = json.loads(text)
    found = next((c for c in body.get("clips", []) if c.get("id") == clip), {})
    return body.get("version"), (found.get("video") or {}).get("wheels"), text


def run_s(client, card, state):
    doc, sized = opened(client, "S", CARD_W, CARD_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    clip = doc.place(track, media) if media is not None else None
    state["s_fixture"] = sized and clip is not None
    plain_path = WORK / "S-plain.reelcut"
    saved = doc.call("save_project", path=str(plain_path))
    doc.path = plain_path
    try:
        plain_version, _, plain_text = saved_wheels(plain_path, clip)
    except (OSError, ValueError):
        plain_version, plain_text = None, "unreadable"
    doc.wheels([clip], lift={"x": 0.2})
    wheeled_path = WORK / "S-wheeled.reelcut"
    resaved = doc.call("save_project", path=str(wheeled_path))
    doc.path = wheeled_path
    try:
        wheeled_version, wheeled, _ = saved_wheels(wheeled_path, clip)
    except (OSError, ValueError):
        wheeled_version, wheeled = None, None
    stray = '"wheels"' in plain_text
    version = format_version()
    check("N2 a neutral save holds no `wheels`; with lift x 0.2 the clip's wheels are exactly "
          f"{{\"lift\": {{\"x\": 0.2}}}}; both at version {version} (the header's)",
          saved["ok"] and resaved["ok"] and not stray and wheeled == {"lift": {"x": 0.2}}
          and plain_version == version and wheeled_version == version,
          f"neutral has wheels {stray}, version {plain_version}; wheeled "
          f"{wheeled}, version {wheeled_version}")
    return close(client, doc.path)


# ---- project P and the probe -------------------------------------------------

def run_p(client, card, state):
    """Two card clips on two tracks at lift masters 0.2 and −0.2, saved for the
    probe; (the package's path, the clip ids), or (None, None)."""
    doc, sized = opened(client, "P", CARD_W, CARD_H)
    a_track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    a = doc.place(a_track, media) if media is not None else None
    b_track = doc.new_track()
    b = doc.place(b_track, media) if media is not None else None
    ok = sized and a is not None and b is not None
    ok = ok and doc.wheels([a], lift={"master": 0.2})["ok"] \
        and doc.wheels([b], lift={"master": -0.2})["ok"]
    path = WORK / "P-saved.reelcut"
    ok = ok and doc.call("save_project", path=str(path))["ok"]
    doc.path = path
    closed = close(client, doc.path)
    state["p_fixture"] = ok
    return (path, [a, b]) if ok and closed else (None, None)


def run_probe(sources, package, clips):
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / "wheels_probe",
                                  defines=["REELCUT_DEV_TOOLS"], timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        for name in sorted(P_ROWS):
            check(f"{name} the probe builds over app/Sources", False,
                  f"{error} {error.diagnostics[:6]}")
        return
    request, answer = folder / "request.json", folder / "answer.json"
    if answer.exists():
        answer.unlink()
    request.write_text(json.dumps({"package": str(package), "clips": clips}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(P_ROWS):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


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
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            return None, f"the copy's core/tests could not be linked: {error}"
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


def core_test(copy):
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "wheels",
                       "--test", "schema_v16", "--test", "ungraded"], 900,
                      cwd=str(copy / "core"))
    lines = (ran["stdout"] + ran["stderr"]).strip().splitlines()
    failed = [line.strip() for line in lines if line.strip().startswith("`--test ")]
    return ran["rc"] == 0 and not ran["expired"], failed or lines[-3:]


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", choices=["capture", "compare"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mode and not args.folder:
        print(f"{args.mode} needs a folder")
        return 2
    folder = (ROOT / args.folder).resolve() if args.folder else None
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if args.mode != "compare":
        selected.discard("N0")
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    if args.mode == "capture":
        folder.mkdir(parents=True, exist_ok=True)
        selected = {"Z1"}
    named = MUTANTS[args.mutant][1] if args.mutant else []
    scored = [name for name in ROWS if name in selected and name not in RECORDS]
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading-2 G2-2 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = app / "Contents/MacOS/Reelcut"
        sources = copy / "app/Sources"
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test wheels "
                  "--test schema_v16 --test ungraded in the copy's core\n       "
                  + " | ".join(last), flush=True)
            scored.append("CT")
    else:
        print(f"grading-2 G2-2 — wheels over MCP ({args.mode or 'run'}, {config} build "
              f"{binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    card, ramp, movie = fixtures()
    if movie is None:
        print("instrument failure: ffmpeg did not make the testsrc2 movie")
        return 2
    neutral = Neutral(args.mode, folder)
    log = WORK / "instance.log"
    state = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed, package, clips = True, None, None
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            capture = args.mode == "capture"
            if capture or "N0" in selected or selected & C_ROWS:
                closed = run_c(launched.client, card, neutral, state) and closed
            if capture or "N0" in selected or selected & R_ROWS:
                closed = run_r(launched.client, ramp, neutral, state) and closed
            if capture or "N0" in selected or selected & M_ROWS:
                closed = run_m(launched.client, movie, neutral, state) and closed
            if "N2" in selected:
                closed = run_s(launched.client, card, state) and closed
            if selected & P_ROWS:
                package, clips = run_p(launched.client, card, state)
                closed = closed and package is not None
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    if selected & P_ROWS:
        if package is None:
            for name in sorted(selected & P_ROWS):
                check(f"{name} project P was made and saved", False)
        else:
            run_probe(sources, package, clips)
    if "N0" in selected:
        missing = [name for name in NEUTRAL if name not in neutral.seen]
        good = not neutral.misses and not missing
        title = (f"N0 the six wheel-less frames are byte-identical (16 bits a channel) to "
                 f"{args.folder}")
        if config == "release" or args.mutant:
            check(title, good, f"misses {neutral.misses}; not taken {missing}")
        else:
            selected.discard("N0")
            scored = [name for name in scored if name != "N0"]
            print(f"  note N0 is scored on Release only; on {config}: "
                  f"{'equal' if good else neutral.misses + missing}", flush=True)
    found = complaints(log)
    fixtures_ok = all(value for key, value in state.items() if key.endswith("fixture"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Reelcut: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; fixtures {state}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    if args.mode == "capture":
        taken = sorted(p.name for p in folder.glob("*.png"))
        good = rows.get("Z1") and taken == sorted(f"{n}.png" for n in NEUTRAL)
        print(f"captured {len(taken)} neutral frames into {args.folder}: {taken}")
        return 0 if good else 1
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
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
