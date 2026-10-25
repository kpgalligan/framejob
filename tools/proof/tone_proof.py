#!/usr/bin/env python3
"""Road map "grading", phase GR2 (spec §11 GR-2) — tone end to end over MCP:
`set_video {patch: {color: {exposure, temperature, tint, highlights,
shadows, whites, blacks, vibrance, fade}}}`, the recipe's `color`, and the
compositor's step 4c behind `toneEnabled`, read back as `render_frame` bytes
and one export; then the probe's rows over `app/Sources`.

    python3 tools/proof/tone_proof.py [--app PATH] [--only E1,A1,...]
    python3 tools/proof/tone_proof.py capture DIR      # the neutral control, before any product edit
    python3 tools/proof/tone_proof.py compare DIR      # every row, and N0 against DIR
    python3 tools/proof/tone_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/tone/home`, and
every package, fixture and PNG is under `tools/proof/work/tone/`, removed at
the start and at exit (the control folder DIR is not). No menu item is
performed. Every call is bounded (`CALL_BOUND`), every ffmpeg too (120 s).
Every project is closed (`close_project`, discard).

Fixtures, written by this script: CARD, a 640×360 grey-128 PNG; RAMP, a
1920×360 PNG whose column x is round(255·x/1919); MOVIE, a 2 s 640×360 30 fps
ffmpeg `testsrc2` H.264 file. Frames are taken at t = 0.5 s unless a row says
otherwise. enc and dec are the sRGB transfer functions (IEC 61966-2-1) and v
the neutral render's own value at the sample, so every formula is over
measured bytes, ±1 a channel.

Projects, each 30 fps: C (640×360, CARD), R (1920×360, RAMP), M (640×360,
MOVIE on track A, background black), P (two CARD clips on two tracks, saved
for the probe), S (CARD, saved twice for N2).
- **N0** (`compare DIR` only; scored on Release, printed elsewhere): the
  neutral frames — card, card-obscured, ramp, movie, movie-obscured, matte —
  decoded at 16 bits a channel are byte-identical to `capture DIR`'s, taken on
  the untouched tree's Release build.
- **N1**: an all-zero tone patch on the neutral card answers "made no change"
  (an identity, no undo step) and the frame is unchanged.
- **N2**: project S saved untoned holds none of the nine keys in its
  `project.json`; saved with exposure 1 and fade 0.5, the clip's `color` keys
  are exactly brightness, contrast, saturation, hue, exposure, fade, in that
  order.
- **E1**: exposure +1 on the card: every sample = round(255·enc(2·dec(v))).
- **E2**: exposure −1 alone: every sample = round(255·enc(dec(v)/2)).
- **W1**: temperature +0.5: R = enc(dec(v)·2^0.15), B = enc(dec(v)·2^−0.15),
  G = v; then tint +0.5: G = enc(dec(v)·2^−0.15), R = B = v.
- **K1** (R): whites +1 keeps code 0 and raises the middle to v·1.15; blacks
  +1 keeps 255 and lifts 0 to 0.15·255.
- **F1** (R): fade 1 takes black to 26 and white to 242.
- **O1** (C): a 200×120 pixelate region, feather 0, on the card at exposure
  +1: inside and outside the region the frame is E1's bytes (tone at 4c, after
  the region's own re-sample).
- **A1** (C): a 1 s action from neutral to exposure +1 at 0 s: the frame at
  0.5 s lies strictly between the neutral value and E1's MEASURED one at every
  sample, and
  the frame at 1.5 s is E1's pixels.
- **R1** (C): exposure 3.5 and fade −0.1 are refused by their sentences and
  the project is unchanged.
- **X1** (M): exposure +1 on the movie: the `prores_422` export's frame 15
  is within ±8 of `render_frame` at every 16th pixel, and the graded frame
  differs from the neutral one by more than 30 somewhere.
- **U1** (C): undo after E1 brings the neutral pixels back, redo E1's.
- **M1** (M): a CARD clip on a front `luma` matte track over the movie; at
  exposure +1 on the matte clip the frame's mean (every 8th pixel) rises by
  more than 10 % over the neutral matte's, and no sample falls by more than 1.
- **B1** (R, RECORD, unscored): the ramp at exposure +1 — distinct levels in
  the middle row, beside the neutral ramp's.
- **P1–P4**: `tone_probe.swift`, built by `swift_build.build` over
  `app/Sources` (a failed build is a scored FAILURE of all four), on project
  P: P1 Light's Temperature field over two clips with exposures +1 and −1
  sends one `set_video` naming both whose patch is exactly
  `{color: {temperature: 0.5}}`; P2 `apply(tone:)` sets `toneEnabled` 1 for
  exposure −1 alone and 0 for neutral; P3 `LayerUniforms` is 528 bytes (512
  until hdr H-2's HLG group, 464 until grading-2 G2-2's wheels group) with
  `exposure` at 416; P4 `keyedCount` for `{video: {color: {exposure: 1}, x: 3}}`
  is 1 on Color and 1 on Picture.
- **Z1** (CONTROL): the projects close and the log holds no `Frame Job: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`
and links the tree's `core/tests`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row on it, the probe built
over the copy's `app/Sources`. A core mutant also runs `cargo test --release
--no-fail-fast --test tone --test schema_v15` in the copy's own `core/` (row
CT). MUTANT PASS when every named row FAILED and no other scored row did:
  exposure-encoded       exposure multiplies ENCODED values: E1 E2
  tone-before-obscure    step 4c moved before 4b: O1
  flag-ignores-negative  `toneEnabled` only for a positive key: E2 P2
  range-check-dropped    exposure's range check gone: R1 CT
  tone-always-written    the nine keys always serialised: N2 CT
  lerp-base-unfilled     the action's base state without the neutral keys: A1 CT
  light-writes-group     a Light row writes the whole colour group: P1
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import json
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402

WORK = ROOT / "tools/proof/work/tone"
HOME = WORK / "home"
PROBE = ROOT / "tools/proof/tone_probe.swift"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
T = SEC // 2
CARD_W, CARD_H = 640, 360
RAMP_W, RAMP_H = 1920, 360
GREY = 128
REGION = (220, 120, 420, 240)       # the obscure region's box on the card, canvas pixels
TONE = ["exposure", "temperature", "tint", "highlights", "shadows", "whites", "blacks",
        "vibrance", "fade"]
FOUR = ["brightness", "contrast", "saturation", "hue"]
NEUTRAL = ["card", "card-obscured", "ramp", "movie", "movie-obscured", "matte"]
ROWS = ["N0", "N1", "N2", "E1", "E2", "W1", "K1", "F1", "O1", "A1", "R1", "X1", "U1", "M1",
        "B1", "P1", "P2", "P3", "P4", "Z1"]
RECORDS = {"B1"}
C_ROWS = {"N1", "E1", "E2", "W1", "O1", "A1", "R1", "U1"}
R_ROWS = {"K1", "F1", "B1"}
M_ROWS = {"X1", "M1"}
P_ROWS = {"P1", "P2", "P3", "P4"}
SHADER = "app/Resources/Shaders/Compositor.metal"
# The layer stage's one call into steps 4c–4d (#363), and the five gated calls
# `gradeSteps` holds, written out at a site's indentation and variable: a mutant replaces
# the call by them in its mutated order or with its step dropped.
LAYER_STEPS = "        rgb = gradeSteps(rgb, u, curves, look, samp);\n"
GRADE_CALLS = {"tone": ("toneEnabled", "gradeTone({v}, u)"),
               "wheels": ("wheelsEnabled", "gradeWheels({v}, u)"),
               "curves": ("curvesEnabled", "gradeCurves({v}, curves, samp)"),
               "hue": ("hueCurvesEnabled",
                       "gradeHueCurves({v}, curves, samp, gradeWeights(u.hlgOutput))"),
               "look": ("lookEnabled", "gradeLook({v}, look, samp, u)")}


def grade_inline(steps, indent="        ", v="rgb"):
    return "".join(f"{indent}if (u.{flag} > 0.5) {{\n{indent}    {v} = {call.format(v=v)};\n"
                   f"{indent}}}\n" for flag, call in (GRADE_CALLS[s] for s in steps))


STEP_4B = "        // (4b) The obscured regions. COLOUR ONLY"
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "exposure-encoded": ([(
        SHADER,
        "    float3 lin = (hlg ? hlgInverseOETF(saturate(rgb)) : gradeDecode(rgb))\n"
        "        * exp2(u.exposure) * gains;\n"
        "    rgb = hlg ? hlgOETF(saturate(lin)) : gradeEncode(lin);\n",
        "    float3 lin = (hlg ? hlgInverseOETF(saturate(rgb)) : gradeDecode(rgb)) * gains;\n"
        "    rgb = clamp((hlg ? hlgOETF(saturate(lin)) : gradeEncode(lin)) * exp2(u.exposure), "
        "0.0, 1.0);\n")], ["E1", "E2"]),
    "tone-before-obscure": ([
        (SHADER, LAYER_STEPS, grade_inline(["wheels", "curves", "hue", "look"])),
        (SHADER, STEP_4B, grade_inline(["tone"]) + "\n" + STEP_4B)], ["O1"]),
    "flag-ignores-negative": ([(
        "app/Sources/GradeProps.swift",
        "toneEnabled = values.contains { $0 != 0 } ? 1 : 0",
        "toneEnabled = values.contains { $0 > 0 } ? 1 : 0")], ["E2", "P2"]),
    "range-check-dropped": ([(
        "core/src/props_check.rs",
        "    in_range(\n        \"video.color.exposure\",\n        c.exposure,\n"
        "        -EXPOSURE_MAX,\n        EXPOSURE_MAX,\n    )?;\n",
        "")], ["R1", "CT"]),
    "tone-always-written": ([(
        "core/src/model_props.rs",
        "fn is_zero(value: &f64) -> bool {\n    *value == 0.0\n}",
        "fn is_zero(_value: &f64) -> bool {\n    false\n}")], ["N2", "CT"]),
    "lerp-base-unfilled": ([(
        "core/src/actions.rs",
        "        fields.insert(\"video\".to_string(), video_json(&base_video));\n",
        "        fields.insert(\"video\".to_string(), to_json(&base_video));\n")],
        ["A1", "CT"]),
    "light-writes-group": ([(
        "app/Sources/VideoPane+Light.swift",
        "                    var patch = ColorPatch()\n",
        "                    var patch = ColorPatch(color())\n")], ["P1"]),
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
        # `export` answers an id since #326; the helper follows it to the file.
        answer = (client.export_with(arguments) if tool == "export"
                  else client.call_with(tool, arguments))
        return {"ok": True, "reply": answer}
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


def dec(c):
    c = min(max(c, 0.0), 1.0)
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def enc(c):
    c = min(max(c, 0.0), 1.0)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def code(value):
    return round(255 * min(max(value, 0.0), 1.0))


def linear(v, gain):
    """The 8-bit code `v` times `gain` in linear light, re-encoded."""
    return code(enc(dec(v / 255) * gain))


def close_to(got, want, tolerance=1):
    return all(abs(a - b) <= tolerance for a, b in zip(got, want))


def compare(frame, points, want, tolerance=1):
    """(every point's rgb within `tolerance` of `want(x, y, neutral rgb)`, the
    first miss). `want` gets the point and answers an rgb triple."""
    if frame is None:
        return False, "the frame is missing"
    for x, y in points:
        expected = want(x, y)
        got = frame.px(x, y)
        if expected is None or not close_to(got, expected, tolerance):
            return False, f"({x},{y}) {got} vs {expected}"
    return True, ""


def same_pixels(a, b):
    return a is not None and b is not None and a.raw == b.raw


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

    def place(self, track, media):
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call("add_clip", track=track, media=media, at=0)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def media(self, path):
        return reply(self.call("import_media", path=str(path))).get("media")

    def clip(self, clip):
        return next((c for c in self.project().get("clips") or [] if c.get("id") == clip), {})

    def color(self, clips, **keys):
        return self.call("set_video", clips=clips, patch={"color": keys})

    def frame(self, tag, t=T):
        """`render_frame` at `t`, decoded; a Frame, or None."""
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out))
        raw = decode(out, self.width, self.height) if got["ok"] and out.exists() else None
        if raw is None:
            print(f"       render {tag}: {got.get('error', 'no file or a wrong size')}",
                  flush=True)
            return None
        return Frame(out, raw, self.width)


def opened(client, name, width, height, background=None):
    """A new project at `name`, its canvas sized; (Doc, fixture ok)."""
    path = WORK / f"{name}.framejob"
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


def obscure_patch(box):
    x0, y0, x1, y1 = box
    return {"obscure": [{"shape": "rect", "x": (x0 + x1) / 2 - CARD_W / 2,
                         "y": (y0 + y1) / 2 - CARD_H / 2, "width": x1 - x0,
                         "height": y1 - y0, "feather": 0, "kind": "pixelate",
                         "amount": 1}]}


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
    state["c_fixture"] = fixture
    print(f"  C: card clip {clip}, neutral value {v} (written {GREY})", flush=True)
    if neutral.mode == "capture" or not fixture:
        if fixture:
            doc.call("set_video", clips=[clip], patch=obscure_patch(REGION))
            neutral.take(doc, "card-obscured")
        return close(client, doc.path) and fixture
    ids = [clip]

    # N1
    zeros = doc.color(ids, **{key: 0 for key in TONE})
    n1 = doc.frame("n1")
    check("N1 an all-zero tone patch is an identity (\"made no change\") and the frame is "
          "unchanged", not zeros["ok"] and "made no change" in zeros.get("error", "")
          and same_pixels(n1, base), f"answer {zeros.get('error') or zeros.get('reply')!r}")

    # R1
    before = doc.project()
    over = doc.color(ids, exposure=3.5)
    under = doc.color(ids, fade=-0.1)
    unchanged = doc.project() == before
    for got in (over, under):  # a value accepted in error is taken back, so no later row
        if got["ok"]:          # starts from it
            doc.call("undo")
    want_over = "video.color.exposure must be between -3 and 3, not 3.5"
    want_under = "video.color.fade must be between 0 and 1, not -0.1"
    check("R1 exposure 3.5 and fade -0.1 are refused by their sentences; the project is "
          "unchanged", not over["ok"] and want_over in over.get("error", "")
          and not under["ok"] and want_under in under.get("error", "")
          and unchanged,
          f"exposure {over.get('error') or 'accepted'!r}; fade "
          f"{under.get('error') or 'accepted'!r}")

    # E1
    up = doc.color(ids, exposure=1)
    e1 = doc.frame("e1")
    e1_value = linear(v, 2.0)
    ok, miss = compare(e1, GRID, lambda x, y: (e1_value,) * 3)
    check(f"E1 exposure +1: every sample = round(255·enc(2·dec({v}/255))) = {e1_value} ±1",
          up["ok"] and ok, f"set {up.get('error', 'ok')}; {miss or 'all within'}")

    # U1
    undone = doc.call("undo")
    u_neutral = doc.frame("u1-undone")
    redone = doc.call("redo")
    u_graded = doc.frame("u1-redone")
    check("U1 undo brings the neutral pixels back, redo E1's",
          undone["ok"] and redone["ok"] and same_pixels(u_neutral, base)
          and same_pixels(u_graded, e1),
          f"undo {undone.get('error', 'ok')}; redo {redone.get('error', 'ok')}; "
          f"neutral {same_pixels(u_neutral, base)}; graded {same_pixels(u_graded, e1)}")

    # E2
    down = doc.color(ids, exposure=-1)
    e2 = doc.frame("e2")
    e2_value = linear(v, 0.5)
    ok, miss = compare(e2, GRID, lambda x, y: (e2_value,) * 3)
    check(f"E2 exposure -1 alone: every sample = round(255·enc(dec({v}/255)/2)) = {e2_value} "
          "±1", down["ok"] and ok, f"set {down.get('error', 'ok')}; {miss or 'all within'}")
    doc.color(ids, exposure=0)

    # W1
    warm = doc.color(ids, temperature=0.5)
    w1 = doc.frame("w1-temperature")
    want_warm = (linear(v, 2 ** 0.15), v, linear(v, 2 ** -0.15))
    warm_ok, warm_miss = compare(w1, GRID, lambda x, y: want_warm)
    doc.color(ids, temperature=0)
    tint = doc.color(ids, tint=0.5)
    w2 = doc.frame("w1-tint")
    want_tint = (v, linear(v, 2 ** -0.15), v)
    tint_ok, tint_miss = compare(w2, GRID, lambda x, y: want_tint)
    doc.color(ids, tint=0)
    check(f"W1 temperature +0.5: R up, B down, G kept {want_warm}; tint +0.5: G down "
          f"{want_tint}", warm["ok"] and tint["ok"] and warm_ok and tint_ok
          and want_warm[0] > v > want_warm[2] and want_tint[1] < v,
          f"temperature {warm.get('error', 'ok')} {warm_miss or 'all within'}; tint "
          f"{tint.get('error', 'ok')} {tint_miss or 'all within'}")

    # O1
    hidden = doc.call("set_video", clips=ids, patch=obscure_patch(REGION))
    neutral.take(doc, "card-obscured")
    o_up = doc.color(ids, exposure=1)
    o1 = doc.frame("o1")
    x0, y0, x1, y1 = REGION
    inside = [(x, y) for x, y in GRID if x0 + 3 <= x < x1 - 3 and y0 + 3 <= y < y1 - 3]
    ok, miss = compare(o1, GRID, lambda x, y: e1.px(x, y) if e1 is not None else None,
                       tolerance=0)
    check(f"O1 a pixelate region on the card at exposure +1: inside ({len(inside)} samples) "
          "and outside it the frame is E1's bytes", hidden["ok"] and o_up["ok"]
          and len(inside) > 0 and ok,
          f"region {hidden.get('error', 'ok')}; exposure {o_up.get('error', 'ok')}; "
          f"{miss or 'all equal'}")
    doc.color(ids, exposure=0)
    doc.call("set_video", clips=ids, patch={"obscure": []})

    # A1
    added = doc.call("add_action", clip=clip, at=0, duration=SEC)
    actions = doc.clip(clip).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = doc.call("set_action_end", clip=clip, action=action,
                     patch={"video": {"color": {"exposure": 1}}}) if action else {"ok": False}
    mid = doc.frame("a1-mid", t=SEC // 2)
    end = doc.frame("a1-end", t=SEC + SEC // 2)
    # Between the neutral value and E1's MEASURED one: what A1 claims is the
    # interpolation, and E1 is the formula's row.
    top = e1.px(CARD_W // 2, CARD_H // 2)[0] if e1 is not None else None
    between = mid is not None and top is not None and all(
        v < mid.px(x, y)[0] < top and len(set(mid.px(x, y))) == 1 for x, y in GRID)
    check("A1 a 1 s action from neutral to exposure +1: mid-span strictly between "
          f"{v} and E1's {top} ({mid.px(CARD_W // 2, CARD_H // 2) if mid else None}), and "
          "its end is E1's pixels", added["ok"] and ended["ok"] and between
          and same_pixels(end, e1),
          f"add {added.get('error', 'ok')}; end {ended.get('error', 'ok')}; end pixels "
          f"{same_pixels(end, e1)}")
    return close(client, doc.path)


# ---- project R: the ramp -----------------------------------------------------

def run_r(client, ramp, neutral, state):
    doc, sized = opened(client, "R", RAMP_W, RAMP_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(ramp)
    clip = doc.place(track, media) if media is not None else None
    base = neutral.take(doc, "ramp")
    y = RAMP_H // 2
    black, mid, white = (1, y), (RAMP_W // 2, y), (RAMP_W - 2, y)
    fixture = (sized and clip is not None and base is not None
               and base.px(*black) == (0, 0, 0) and base.px(*white) == (255, 255, 255))
    state["r_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture
    ids = [clip]
    m = base.px(*mid)[0]

    # K1
    whites = doc.color(ids, whites=1)
    k_w = doc.frame("k1-whites")
    doc.color(ids, whites=0)
    blacks = doc.color(ids, blacks=1)
    k_b = doc.frame("k1-blacks")
    doc.color(ids, blacks=0)
    want_mid, want_lift = code(m / 255 * 1.15), code(0.15)
    ok = (k_w is not None and k_b is not None and whites["ok"] and blacks["ok"]
          and close_to(k_w.px(*black), (0, 0, 0)) and close_to(k_w.px(*mid), (want_mid,) * 3)
          and close_to(k_b.px(*white), (255, 255, 255))
          and close_to(k_b.px(*black), (want_lift,) * 3))
    check(f"K1 whites +1: 0 kept, middle {m} → {want_mid}; blacks +1: 255 kept, 0 → "
          f"{want_lift}", ok,
          f"whites: black {k_w.px(*black) if k_w else None}, middle "
          f"{k_w.px(*mid) if k_w else None}; blacks: white {k_b.px(*white) if k_b else None}, "
          f"black {k_b.px(*black) if k_b else None}")

    # F1
    faded = doc.color(ids, fade=1)
    f1 = doc.frame("f1")
    doc.color(ids, fade=0)
    ok = (faded["ok"] and f1 is not None and close_to(f1.px(*black), (26,) * 3)
          and close_to(f1.px(*white), (242,) * 3))
    check("F1 fade 1: black → 26 ±1, white → 242 ±1", ok,
          f"set {faded.get('error', 'ok')}; black {f1.px(*black) if f1 else None}, white "
          f"{f1.px(*white) if f1 else None}")

    # B1 (a record)
    raised = doc.color(ids, exposure=1)
    b1 = doc.frame("b1")
    doc.color(ids, exposure=0)
    levels = len({b1.px(x, y)[0] for x in range(RAMP_W)}) if b1 else 0
    plain = len({base.px(x, y)[0] for x in range(RAMP_W)})
    check(f"B1 RECORD the ramp at exposure +1: {levels} distinct levels in the middle row "
          f"(neutral {plain})", raised["ok"] and b1 is not None,
          f"set {raised.get('error', 'ok')}")
    return close(client, doc.path)


# ---- project M: the movie, an export, a matte --------------------------------

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


def run_m(client, movie, card, neutral, state):
    doc, sized = opened(client, "M", CARD_W, CARD_H, background=[0, 0, 0, 1])
    a_track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(movie)
    clip = doc.place(a_track, media) if media is not None else None
    base = neutral.take(doc, "movie")
    hidden = doc.call("set_video", clips=[clip], patch=obscure_patch(REGION)) if clip else {}
    neutral.take(doc, "movie-obscured")
    doc.call("set_video", clips=[clip], patch={"obscure": []}) if clip else None
    b_track = doc.new_track()
    card_media = doc.media(card)
    matte_clip = doc.place(b_track, card_media) if card_media is not None else None
    set_matte = doc.call("set_track", track=b_track, matte="luma")
    matted = neutral.take(doc, "matte")
    fixture = (sized and clip is not None and base is not None and hidden.get("ok")
               and matte_clip is not None and set_matte["ok"] and matted is not None)
    state["m_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # M1
    raised = doc.color([matte_clip], exposure=1)
    m1 = doc.frame("m1")
    doc.color([matte_clip], exposure=0)
    points = [(x, y) for y in range(0, CARD_H, 8) for x in range(0, CARD_W, 8)]

    def mean(frame):
        return sum(sum(frame.px(x, y)) for x, y in points) / (3 * len(points))
    fell = [(x, y) for x, y in points if m1 is not None
            and any(g < n - 1 for g, n in zip(m1.px(x, y), matted.px(x, y)))]
    rise = mean(m1) / max(mean(matted), 1e-6) if m1 is not None else 0
    check(f"M1 a luma matte card at exposure +1 shows more of the movie behind: mean "
          f"×{rise:.3f} (> 1.10), no sample falls by more than 1",
          raised["ok"] and m1 is not None and rise > 1.10 and not fell,
          f"set {raised.get('error', 'ok')}; fell at {fell[:3]}")
    doc.call("set_track", track=b_track, matte="none")
    doc.call("remove_track", track=b_track, with_clips=True)

    # X1
    up = doc.color([clip], exposure=1)
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

def color_keys(path, clip):
    """The `color` key order of `clip` in the package's `project.json`, and
    the file's text."""
    text = (Path(path) / "project.json").read_text()
    body = json.loads(text)
    found = next((c for c in body.get("clips", []) if c.get("id") == clip), {})
    return list(((found.get("video") or {}).get("color") or {}).keys()), text


def run_s(client, card, state):
    doc, sized = opened(client, "S", CARD_W, CARD_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    clip = doc.place(track, media) if media is not None else None
    state["s_fixture"] = sized and clip is not None
    plain_path = WORK / "S-plain.framejob"
    saved = doc.call("save_project", path=str(plain_path))
    doc.path = plain_path
    try:
        plain_keys, plain_text = color_keys(plain_path, clip)
    except (OSError, ValueError):
        plain_keys, plain_text = None, ""
    doc.color([clip], exposure=1, fade=0.5)
    toned_path = WORK / "S-toned.framejob"
    resaved = doc.call("save_project", path=str(toned_path))
    doc.path = toned_path
    try:
        toned_keys, _ = color_keys(toned_path, clip)
    except (OSError, ValueError):
        toned_keys = None
    stray = [key for key in TONE if f'"{key}"' in plain_text]
    check("N2 an untoned save holds none of the nine keys; a toned one's color is "
          "brightness, contrast, saturation, hue, exposure, fade",
          saved["ok"] and resaved["ok"] and plain_keys == FOUR and not stray
          and toned_keys == FOUR + ["exposure", "fade"],
          f"untoned {plain_keys} (stray {stray}); toned {toned_keys}")
    return close(client, doc.path)


# ---- project P and the probe -------------------------------------------------

def run_p(client, card, state):
    """Two card clips on two tracks at exposures +1 and −1, saved for the
    probe; the package's path, or None."""
    doc, sized = opened(client, "P", CARD_W, CARD_H)
    a_track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    a = doc.place(a_track, media) if media is not None else None
    b_track = doc.new_track()
    b = doc.place(b_track, media) if media is not None else None
    ok = sized and a is not None and b is not None
    ok = ok and doc.color([a], exposure=1)["ok"] and doc.color([b], exposure=-1)["ok"]
    path = WORK / "P-saved.framejob"
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
                                  output=folder / "tone_probe", defines=["FRAMEJOB_DEV_TOOLS"],
                                  timeout=1200)
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
        return [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
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
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "tone",
                       "--test", "schema_v15"], 900, cwd=str(copy / "core"))
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
        binary = proof_app.executable(binary)
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading GR2 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)", flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = proof_app.executable(app)
        sources = copy / "app/Sources"
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test tone "
                  "--test schema_v15 in the copy's core\n       " + " | ".join(last),
                  flush=True)
            scored.append("CT")
    else:
        print(f"grading GR2 — tone over MCP ({args.mode or 'run'}, {config} build "
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
    closed, package = True, None
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
                closed = run_m(launched.client, movie, card, neutral, state) and closed
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
        title = (f"N0 the six neutral frames are byte-identical (16 bits a channel) to "
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
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Frame Job: ` "
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
