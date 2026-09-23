"""Road map 5, E2 — motion presets, driven against the built binary over MCP.

    python3 tools/proof/e2_proof.py [port=4825]

`video.motion` holds up to three presets — an arrival, a departure and a
motion for the whole clip — that the CORE turns into placement at render
time, relative to what the clip already is and composing with its actions,
its transitions and each other. The model and every edit see the clip
UN-MOVED; the recipe draws it moving. That seam is what this script measures,
and it is why almost every claim below is a pair: a number read off
`get_project` and a pixel read off `render_frame`.

**`NONE` is the fixture's own control.** Half the rows here say "this frame is
byte-identical to the same clip with no motion at all" — the frame at the end
of an arrival, one whole period of a spin, the middle of a tent. `motion.rs`
earns that by SHORT-CIRCUITING when no slot is running and by writing the
pivot compensation as two terms that cancel to the bit, so the claim is exact
and not "within a pixel". Every `NONE` here is measured the same way: the
clip's motion is cleared, the frame is rendered, and the motion is put back.

**What is measured, section by section.**

* **1** the schema: a version-7 file opens with `motion: null`; a save writes
  version 8 with `motion` the LAST key of the video object; all-null
  normalises back to null; a misspelt key, an unknown kind, a negative
  duration and a zero period are each refused BY NAME; `set_action_end` with
  a motion is refused; and two hand-written version-8 files — an action whose
  `end` carries a motion, and a base `period: 0` — draw the base motion and
  no NaN.
* **2** the slides: off-canvas at the first frame, the arrival's own end
  byte-identical to no motion, and the leading edge where `ease_out` puts it
  — on a plain card, on a ROTATED one (the bounding box) and on a CROPPED
  one, where the pivot is the VISIBLE centre.
* **3** `fade`, `zoom_in` and `pop`: the eased opacity, the scale about the
  visible centre cropped or not, and the overshoot passing 1 and coming back.
* **4** the four continuous presets: a whole spin byte-identical to no
  motion (the `rem_euclid(360)` rule), a quarter of one at 45°, a `shake`
  that reads the PERIOD and not the clip, a `drift` that reads the clip, and
  a `bounce` lifted by exactly `0.08·A·H·|sin|`.
* **5** composition: the tent, an action moving under an arrival, two slots
  multiplying, and a nest scaling every inner layer about its placed centre.
* **6** the model rules: `get_project` un-moved while the frame moves, and
  what a split and a ripple delete leave behind.
* **7** the export path: an `apng` of an in/out range, measured frame by
  frame — an independent measurement, since no precedent compares the image
  sequence writer's frames to `render_frame`'s.

`ffmpeg` is needed at proof time, to take the APNG apart into frames.
"""

import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
MEDIA = os.path.join(HERE, "media")

SEC = 600_000
FRAME = 20_000
CANVAS = (640, 360)
VERSION = 8
# What a save writes: the CURRENT format version, which moved past E2's own
# when road map 8's W1b bumped it to 9. `VERSION` stays E2's, because the
# hand-written fixtures below are version-8 files on purpose.
CURRENT_VERSION = 9

# Floors, not exact counts: since road map 7's D3 the exact numbers belong to
# `op_argument_proof.py` (tools/proof/README.md's handover rule).
TOOLS_FLOOR = 77
OPS_FLOOR = 57

failures = []
skipped = []
checks = 0


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def skip(count, why):
    """A row that could not RUN, printed by name with the checks it would
    have scored — `phase5_chrome.py`'s shape. Verification forbids one on the
    landing run; it exists so a reference tree that will not build reports
    itself instead of reading as eleven failures."""
    global checks
    checks += count
    for _ in range(count):
        failures.append(f"SKIP {why}")
    skipped.append(f"{why} ({count} checks)")
    print(f"  SKIP {why} — {count} checks not taken")


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def grey(value):
    """A colour argument for an 8-bit grey — every fill here is k/255 for a
    whole k, so a byte comparison can never fail on a dithered colour
    (`phase6_proof.py`'s rule)."""
    return [value / 255.0, value / 255.0, value / 255.0, 1.0]



def ease(curve, u):
    u = min(max(u, 0.0), 1.0)
    if curve == "linear":
        return u
    if curve == "ease_in":
        return u * u
    if curve == "ease_out":
        return 1.0 - (1.0 - u) * (1.0 - u)
    if curve == "ease_in_out":
        return u * u * (3.0 - 2.0 * u)
    raise RuntimeError(f"{curve} is not a curve")



# ---- PNG, in pure Python -------------------------------------------------
#
# `phase6_proof.py`'s decoder, copied rather than imported: those files are
# SCRIPTS, importing one would run its main, and a proof that measures its
# own evidence carries the decoder it trusts. The 8-bit guard is not
# paperwork — `render_frame` writes at the depth the frame needs, and a
# 16-bit PNG would silently change what "a byte" means here.


def decode_png(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"{path} is not a PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        raise RuntimeError(
            f"{path}: {depth}-bit or interlaced — this decoder reads 8-bit "
            "non-interlaced PNGs, and every byte comparison here assumes one")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            raise RuntimeError(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, depth, channels, rows


class Frame:
    """One rendered PNG, decoded. Positions are pixel indices."""

    def __init__(self, path):
        self.path = path
        self.width, self.height, self.depth, self.channels, self.rows = decode_png(path)

    def pixel(self, x, y):
        return tuple(self.rows[y][x * self.channels:(x + 1) * self.channels])

    def centre(self):
        return self.pixel(self.width // 2, self.height // 2)

    def row(self, y, channel=0):
        row = self.rows[y]
        return [row[x * self.channels + channel] for x in range(self.width)]

    def column(self, x, channel=0):
        return [row[x * self.channels + channel] for row in self.rows]

    def sampled(self, step=7):
        """Every step-th pixel, as a set — "the frame is one flat colour"
        without walking a quarter of a million pixels."""
        return {
            self.pixel(x, y)
            for y in range(0, self.height, step)
            for x in range(0, self.width, step)
        }

    def changed(self, other):
        out = []
        ch = self.channels
        for y, (ra, rb) in enumerate(zip(self.rows, other.rows)):
            if ra == rb:
                continue
            for x in range(self.width):
                if ra[x * ch:(x + 1) * ch] != rb[x * ch:(x + 1) * ch]:
                    out.append((x, y))
        return out


def box(pixels):
    """(x0, y0, x1, y1) of a list of pixels, inclusive."""
    xs = [x for x, _ in pixels]
    ys = [y for _, y in pixels]
    return min(xs), min(ys), max(xs), max(ys)


def columns(pixels, band=None):
    """The distinct x of a pixel list, ascending (`phase4_proof.py`'s)."""
    if band is None:
        return sorted({x for x, _ in pixels})
    return sorted({x for x, y in pixels if band[0] <= y < band[1]})


def span(values):
    """(first, last, count) of a column list, or the word for an empty one."""
    if not values:
        return "empty"
    return f"{values[0]}…{values[-1]} ({len(values)} columns)"



def as_version(src, dst, version):
    """A byte copy of a saved package whose `project.json` is rewritten as a
    file of `version`: the version number itself, every `transition_in`
    reduced to its version-6 spelling (`{"kind": k}` — `curve` and `audio`
    did not exist), and every `video.motion` deleted (version 8's key).

    This is what a project saved by last month's build actually looks like,
    and it is the only fixture the reference instance can open at all: the
    core refuses a file from the future, so a version-8 package is simply
    rejected there."""
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    path = os.path.join(dst, "project.json")
    with open(path, encoding="utf-8") as handle:
        project = json.load(handle)

    def strip(clips):
        for clip in clips:
            # Version 7 added `curve` and `audio`; version 8 added `motion`.
            # A file is written back only as far as its own version asks, so
            # `as_version(…, 8)` is a byte copy with a different name and
            # nothing is quietly removed from it.
            if version < 7 and isinstance(clip.get("transition_in"), dict):
                clip["transition_in"] = {"kind": clip["transition_in"]["kind"]}
            video = clip.get("video")
            if version < 8 and isinstance(video, dict):
                video.pop("motion", None)
            inner = clip.get("clips")
            if isinstance(inner, list):
                strip(inner)

    strip(project.get("clips", []))
    for nest in project.get("nests", []):
        strip(nest.get("clips", []))
    project["version"] = version
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(project, handle, indent=2)
        handle.write("\n")
    return dst


def canonical(value):
    """A project dumped with sorted keys — the oracle for "undo restored
    everything" and "nothing else moved"."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"))



class Session:
    """One project, `phase6_proof.py`'s shape.

    `<name>-<pid>.reelcut`, never a fixed name: a `project` path is matched
    against every open document and no tool closes one, so two earlier runs'
    SAVED packages would have the app answering for an old one."""

    def __init__(self, mcp, name, canvas=CANVAS, background=(0, 0, 0), open_from=None):
        self.mcp = mcp
        self.name = name
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        if open_from is None:
            mcp.call("new_project", path=self.path)
            self.op("set_canvas", width=canvas[0], height=canvas[1],
                    background=[c / 255.0 for c in background] + [1.0])
        else:
            if os.path.exists(self.path):
                shutil.rmtree(self.path)
            shutil.copytree(open_from, self.path)
            mcp.call("open_project", path=self.path)

    @classmethod
    def opened(cls, mcp, path):
        """An instance's view of a package that already exists at `path` —
        used where the SAME file has to be opened by two builds."""
        session = cls.__new__(cls)
        session.mcp = mcp
        session.name = os.path.basename(path)
        session.path = path
        mcp.call("open_project", path=path)
        return session

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def op_with(self, name, arguments):
        """For a tool whose own ARGUMENT is spelled `name` — `nest`'s."""
        arguments = dict(arguments)
        arguments["project"] = self.path
        return self.mcp.call_with(name, arguments)

    def project(self):
        return self.op("get_project")["project"]

    def duration(self):
        """The timeline's length, as the tool reports it beside the project."""
        return self.op("get_project")["duration"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def add_track(self):
        self.op("add_track")
        return self.tracks()[-1]

    def media(self, name):
        return self.op("import_media", path=os.path.join(MEDIA, name))["media"]

    def place(self, track, media, at):
        return self.op("add_clip", track=track, media=media, at=int(at))["new_clips"][0]

    def card(self, track, fill, size=CANVAS, at=0, duration=3 * SEC):
        """A flat rectangle with no stroke — the fixture's one drawing."""
        return self.op(
            "add_shape_clip", track=track, at=int(at), duration=int(duration),
            shape={
                "kind": "rectangle", "width": size[0], "height": size[1],
                "stroke": None, "fill": fill,
            })["new_clips"][0]

    def png(self, t=SEC):
        answer = self.op("render_frame", t=int(t))
        found = re.search(r"Written to (\S+\.png)\.", str(answer))
        assert found, f"render_frame said something else: {answer}"
        return found.group(1)

    def frame(self, t=SEC):
        return digest(self.png(t))

    def image(self, t=SEC):
        return Frame(self.png(t))

    def settle(self, tool, **kwargs):
        """A call whose result is a STATE, not a change: an op already in that
        state answers "made no change", which is an identity and not a
        failure. Used only where a row wants the state and does not care
        whether it moved (setting `linear` on a file that is already
        linear)."""
        try:
            return self.op(tool, **kwargs)
        except ToolError as error:
            if "made no change" in str(error):
                return None
            raise

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def save(self):
        self.op("save_project")
        with open(os.path.join(self.path, "project.json"), encoding="utf-8") as handle:
            return handle.read()

    def undo(self):
        return self.op("undo")["undone"]

    def export_wav(self, tag):
        """An audio-only export into `work/`, with the pid on it: half of §5's
        claim is a comparison between two files, and a second run must never
        find the first run's."""
        target = os.path.join(WORK, f"{self.name}-{tag}-{os.getpid()}.wav")
        if os.path.exists(target):
            os.remove(target)
        return self.op("export", preset="audio_wav", path=target)["path"]




# ---- the preset arithmetic, in Python ------------------------------------
#
# Transcribed from road map 5 §5b–§5c's RULES, not from `core/src/motion.rs`:
# the two agreeing is the claim, so they may not share a line.


def back_out(u):
    """The overshoot curve `pop` is built on — above 1 from u ≈ 0.37, peaking
    at 1.100 around u ≈ 0.58, back at exactly 1 when u is 1."""
    p = u - 1.0
    return 1.0 + 2.70158 * p * p * p + 1.70158 * p * p


def geometry(sw, sh, crop, scale, rot, x, y):
    """`(hx, hy, px, py)` — the drawn box's half-extents and the base VISIBLE
    centre, `core/tests/motion.rs`'s own `geometry`.

    `c` is the cropped rect's centre in source pixels, `((l − r)/2,
    (t − b)/2)`, turned by R(θ) and scaled; `p = (x, y) + s·R(θ)·c` is where
    the pivot compensation holds the layer whatever the other slots do."""
    l, t, r, b = crop
    cw = max(sw - l - r, 0.0)
    ch = max(sh - t - b, 0.0)
    k = abs(math.cos(math.radians(rot)))
    n = abs(math.sin(math.radians(rot)))
    hx = scale * (cw * k + ch * n) / 2.0
    hy = scale * (cw * n + ch * k) / 2.0
    cx, cy = (l - r) / 2.0 * scale, (t - b) / 2.0 * scale
    rs, rc = math.sin(math.radians(rot)), math.cos(math.radians(rot))
    return hx, hy, x + rc * cx - rs * cy, y + rs * cx + rc * cy


SLIDE_SIDE = {
    # A slide names the edge it comes FROM: `slide_left` moves left, so it
    # enters from the RIGHT.
    "slide_left": "right", "slide_right": "left",
    "slide_up": "bottom", "slide_down": "top",
}


def slide_edge(kind, u, sw, sh, crop, scale, rot, x, y, w, h):
    """The `(dx, dy)` an ARRIVING slide adds at raw progress `u`.

    `S_side` is the offset that puts the layer's near edge exactly on the
    container's far edge, measured from the base visible centre; the fraction
    of the way out to it is `1 − ease_out(u)`."""
    hx, hy, px, py = geometry(sw, sh, crop, scale, rot, x, y)
    side = SLIDE_SIDE[kind]
    if side == "right":
        s = (w / 2.0 + hx - px, 0.0)
    elif side == "left":
        s = (-(w / 2.0 + hx) - px, 0.0)
    elif side == "bottom":
        s = (0.0, h / 2.0 + hy - py)
    else:
        s = (0.0, -(h / 2.0 + hy) - py)
    fraction = 1.0 - ease("ease_out", u)
    return fraction * s[0], fraction * s[1]


def drawn_box(sw, sh, crop, scale, rot, x, y, w, h, delta=(0.0, 0.0),
              base_scale=None, base_rot=None):
    """Where the drawn box's edges land in CANVAS pixels — `(left, top,
    right, bottom)`, the right and bottom exclusive.

    **The half-extents are the DRAWN ones and the centre is the BASE one.**
    That is the pivot rule, and the two differ the moment a crop is involved:
    the core's placement rule pivots on the UNCROPPED anchor, so a zoom about
    it would drag a cropped layer across its own preset, and the moved
    position compensates — `(x, y)′ = (x, y) + s·R(θ)·c − s″·R(θ″)·c + Δ` —
    which holds the VISIBLE centre exactly where it was. At `F = 1`, `φ = 0`
    the two terms are the same expression and cancel to the bit, so a slide
    needs no base at all and passes neither."""
    base_scale = scale if base_scale is None else base_scale
    base_rot = rot if base_rot is None else base_rot
    hx, hy, _, _ = geometry(sw, sh, crop, scale, rot, x, y)
    _, _, px, py = geometry(sw, sh, crop, base_scale, base_rot, x, y)
    cx, cy = w / 2.0 + px + delta[0], h / 2.0 + py + delta[1]
    return cx - hx, cy - hy, cx + hx, cy + hy


# ---- a motion patch ------------------------------------------------------
#
# `MotionProps.dictionary` always writes three keys and a `motion` patch
# REPLACES the whole object, so every patch here carries all three. Writing
# one key would clear the other two, which is the trap the app's own
# per-clip write exists to avoid.


def motion(arrive=None, leave=None, during=None):
    return {"in": arrive, "out": leave, "during": during}


def edge(kind, seconds):
    return {"kind": kind, "duration": int(round(seconds * SEC))}


def slot(kind, amount, seconds):
    return {"kind": kind, "amount": amount, "period": int(round(seconds * SEC))}


def set_motion(session, clip, value):
    return session.op("set_video", clips=[clip], patch={"motion": value})


def none_frame(session, clip, t):
    """The same project with this clip's motion cleared, rendered and put
    back — the control every `== NONE` row is measured against."""
    stored = session.clip(clip)["video"]["motion"]
    session.op("set_video", clips=[clip], patch={"motion": None})
    answer = session.frame(t)
    session.op("set_video", clips=[clip], patch={"motion": stored})
    return answer


# ---- reading a card off a frame ------------------------------------------


INK = 96      # half of the 192 every card is painted, so an antialiased edge
              # does not widen a box and a 0.75 opacity (144) still reads.


def ink_box(image, threshold=INK):
    """`(x0, y0, x1, y1)` of everything drawn over the black backdrop,
    inclusive, or None when the frame is empty."""
    ch = image.channels
    x0 = y0 = x1 = y1 = None
    for y, row in enumerate(image.rows):
        first = last = None
        for x in range(image.width):
            if row[x * ch] >= threshold:
                if first is None:
                    first = x
                last = x
        if first is None:
            continue
        y0 = y if y0 is None else y0
        y1 = y
        x0 = first if x0 is None else min(x0, first)
        x1 = last if x1 is None else max(x1, last)
    return None if y0 is None else (x0, y0, x1, y1)


def ink_width(image, threshold=INK):
    found = ink_box(image, threshold)
    return None if found is None else found[2] - found[0] + 1


def card_session(mcp, name, size=CANVAS, duration=4 * SEC, **props):
    """One grey card on a black backdrop — the whole fixture."""
    session = Session(mcp, name, background=(0, 0, 0))
    track = session.tracks()[0]
    clip = session.card(track, grey(192), size=size, at=0, duration=duration)
    if props:
        session.op("set_video", clips=[clip], patch=props)
    return session, clip


# ---- section 0 -----------------------------------------------------------


def instance_part(mcp, port):
    print("\n0 — the instance")
    schemas = mcp.schemas()
    ops = [n for n, t in schemas.items()
           if "scope" in t.get("inputSchema", {}).get("properties", {})]
    check(len(schemas) >= TOOLS_FLOOR,
          f"at least {TOOLS_FLOOR} tools ({len(schemas)}) — E2 adds none, so this is a "
          "FLOOR and op_argument_proof.py owns the exact count")
    check(len(ops) >= OPS_FLOOR, f"…and at least {OPS_FLOOR} ops ({len(ops)})")
    path = f"/tmp/reelcut-{port}.log"
    bad = []
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as handle:
            bad = [line.rstrip() for line in handle if "Reelcut: " in line]
    check(os.path.exists(path) and not bad,
          f"the parity log is empty ({'; '.join(bad[:2]) if bad else path})")


# ---- section 1: the schema -----------------------------------------------


def schema_part(mcp):
    print("\n1 — the schema: what a file means, what a save writes, what is refused")
    builder, card = card_session(mcp, "e2-v7-src")
    builder.save()
    v7 = as_version(builder.path, os.path.join(WORK, f"e2-v7-{os.getpid()}.reelcut"), 7)
    session = Session.opened(mcp, v7)
    clip = session.project()["clips"][0]["id"]
    check(session.clip(clip)["video"]["motion"] is None,
          "a version-7 file opens with `motion: null` — the key did not exist")

    set_motion(session, clip, motion(arrive=edge("slide_up", 0.5)))
    text = session.save()
    found = re.search(r'"version"\s*:\s*(\d+)', text)
    check(f'"version": {CURRENT_VERSION}' in text,
          f"a motion saves as a version-{CURRENT_VERSION} file "
          f"({found.group(1) if found else 'no version key'})")
    written = json.loads(text)
    keys = list(written["clips"][0]["video"].keys())
    check(keys[-1] == "motion",
          f"…and `motion` is the video object's LAST key ({keys[-3:]})")

    set_motion(session, clip, motion())
    check(session.clip(clip)["video"]["motion"] is None,
          "three nulls normalise back to `null` — one clip, one spelling of no motion")

    set_motion(session, clip, motion(arrive=edge("slide_up", 0.5)))
    for patch, named in [
        ({"motion": {"inn": edge("slide_up", 0.5), "out": None, "during": None}}, "inn"),
        ({"motion": motion(arrive={"kind": "slide_upp", "duration": SEC // 2})}, "slide_upp"),
        ({"motion": motion(arrive={"kind": "slide_up", "duration": -1})},
         "video.motion.in.duration"),
        ({"motion": motion(during={"kind": "pulse", "amount": 0.5, "period": 0})},
         "video.motion.during.period"),
    ]:
        message = session.error("set_video", clips=[clip], patch=patch)
        check(message is not None and named in message,
              f"refused, naming {named!r}: {message!r}")

    action = session.op("add_action", clip=clip, at=SEC, duration=SEC)["new_actions"][0]
    message = session.error(
        "set_action_end", clip=clip, action=action,
        patch={"video": {"motion": motion(arrive=edge("fade", 0.5))}})
    check(message is not None and "not an animation target" in message,
          f"`set_action_end` refuses a motion: {message!r}")

    # --- two files nothing in the app can write ---
    # A card SMALLER than the canvas, so a scale is a measurable box rather
    # than two frames of edge-to-edge grey.
    base, base_clip = card_session(mcp, "e2-endpatch", size=(300, 200))
    set_motion(base, base_clip, motion(during=slot("pulse", 1.0, 1.0)))
    end_action = base.op("add_action", clip=base_clip, at=SEC, duration=SEC)["new_actions"][0]
    base.op("set_action_end", clip=base_clip, action=end_action,
            patch={"video": {"x": 50}})
    base.save()
    plain = as_version(
        base.path, os.path.join(WORK, f"e2-endpatch-plain-{os.getpid()}.reelcut"), VERSION)
    carried = as_version(
        base.path, os.path.join(WORK, f"e2-endpatch-motion-{os.getpid()}.reelcut"), VERSION)
    path = os.path.join(carried, "project.json")
    with open(path, encoding="utf-8") as handle:
        project = json.load(handle)
    # A `video.motion` inside an action's `end` — refused by the op, so only a
    # hand-written file can hold one. `evaluate_clip` must copy the BASE motion
    # back over it.
    # The end patch's motion differs from the base one by a NUMBER and not
    # only by a kind: the action loop interpolates the whole state toward the
    # patched one, and a string it can only take whole, so a difference of
    # kind alone would leave the same picture at every tick and the row would
    # pass against a build with no restore at all (measured).
    project["clips"][0]["actions"][0]["end"]["video"]["motion"] = motion(
        during=slot("pulse", 1.0, 2.0))
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(project, handle, indent=2)
        handle.write("\n")
    mid = 3 * SEC // 2
    plain_session = Session.opened(mcp, plain)
    plain_frame = plain_session.frame(mid)
    carried_frame = Session.opened(mcp, carried).frame(mid)
    check(plain_frame == carried_frame,
          f"an action whose `end` carries a motion draws the BASE motion, byte for byte "
          f"({plain_frame} vs {carried_frame})")
    # The base pulse at 1.5 s of a one-second period is at 1.2×; the end
    # patch's two-second one, half-interpolated, would be at 1.15×. The two
    # are fifteen pixels apart, which is what makes the row above a claim.
    base_width = ink_width(plain_session.image(mid))
    check(base_width is not None and abs(base_width - 300 * 1.2) <= 1,
          f"…which is the BASE pulse's 1.2× and not the end patch's ({base_width} px "
          f"wide, wanted {300 * 1.2:.0f} ± 1)")

    # **The card is placed AWAY from the origin on purpose.** A degenerate
    # `period` makes every arithmetic path NaN, and a NaN reaches the recipe
    # as JSON `null`, which Swift decodes as the FIELD'S DEFAULT — x 0,
    # scale 1. On a card that is already at x 0 and scale 1 that is the same
    # picture, so the guard would be invisible; at x 100 and scale 1.5 it is
    # not.
    zero_src, zero_clip = card_session(
        mcp, "e2-period0-src", size=(300, 200), x=100.0, scale=1.5)
    set_motion(zero_src, zero_clip, motion(during=slot("pulse", 1.0, 1.0)))
    zero_src.save()
    zero = as_version(
        zero_src.path, os.path.join(WORK, f"e2-period-zero-{os.getpid()}.reelcut"), VERSION)
    none = as_version(
        zero_src.path, os.path.join(WORK, f"e2-period-none-{os.getpid()}.reelcut"), VERSION)
    for package, value in [(zero, 0), (none, None)]:
        path = os.path.join(package, "project.json")
        with open(path, encoding="utf-8") as handle:
            project = json.load(handle)
        if value is None:
            project["clips"][0]["video"]["motion"] = None
        else:
            project["clips"][0]["video"]["motion"]["during"]["period"] = value
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(project, handle, indent=2)
            handle.write("\n")
    # Half a period, where the pulse is at its widest — at a WHOLE period it
    # is the identity and the row would pass against a build that ignored
    # `during` altogether.
    half = SEC // 2
    zero_frame = Session.opened(mcp, zero).frame(half)
    none_session = Session.opened(mcp, none)
    none_hash = none_session.frame(half)
    check(zero_frame == none_hash,
          f"a hand-written `period: 0` is INACTIVE and draws no NaN: byte-identical to no "
          f"motion at all ({zero_frame} vs {none_hash})")
    check(zero_src.frame(half) != none_hash,
          "…where the same file with its period intact draws something else")


# ---- section 2: the slides -----------------------------------------------


def slide_part(mcp):
    print("\n2 — the slides: off canvas, arrived, and the leading edge between")
    session, clip = card_session(mcp, "e2-slide")
    set_motion(session, clip, motion(arrive=edge("slide_left", 1.0)))
    first = session.image(0)
    check(first.sampled(step=3) == {(0, 0, 0, 255)},
          f"at the first frame the card is wholly outside the canvas "
          f"({sorted(first.sampled(step=3))[:3]})")
    arrived = session.frame(SEC)
    check(arrived == none_frame(session, clip, SEC),
          f"the frame AT `in` is byte-identical to the same clip with no motion ({arrived})")
    dx, _ = slide_edge("slide_left", 0.5, 640, 360, (0, 0, 0, 0), 1.0, 0.0, 0.0, 0.0, 640, 360)
    found = ink_box(session.image(SEC // 2))
    check(found is not None and abs(found[0] - round(dx)) <= 1,
          f"at u = 0.5 the leading column is where ease_out puts it: {found[0] if found else None}"
          f" (wanted {round(dx)} ± 1)")

    rotated, rclip = card_session(mcp, "e2-slide-rot", size=(300, 200), rotation=30.0)
    set_motion(rotated, rclip, motion(arrive=edge("slide_up", 1.0)))
    delta = slide_edge("slide_up", 0.5, 300, 200, (0, 0, 0, 0), 1.0, 30.0, 0.0, 0.0, 640, 360)
    wanted = drawn_box(300, 200, (0, 0, 0, 0), 1.0, 30.0, 0.0, 0.0, 640, 360, delta)
    found = ink_box(rotated.image(SEC // 2))
    check(found is not None and abs(found[1] - wanted[1]) <= 2,
          f"a ROTATED card slides by its own BOUNDING box: top row {found[1] if found else None}"
          f" (wanted {wanted[1]:.1f} ± 2)")

    crop = (200.0, 0.0, 0.0, 100.0)
    cropped, cclip = card_session(
        mcp, "e2-slide-crop",
        crop={"l": crop[0], "t": crop[1], "r": crop[2], "b": crop[3]})
    set_motion(cropped, cclip, motion(arrive=edge("slide_up", 1.0)))
    delta = slide_edge("slide_up", 0.5, 640, 360, crop, 1.0, 0.0, 0.0, 0.0, 640, 360)
    wanted = drawn_box(640, 360, crop, 1.0, 0.0, 0.0, 0.0, 640, 360, delta)
    found = ink_box(cropped.image(SEC // 2))
    check(found is not None and abs(found[1] - wanted[1]) <= 1,
          f"a CROPPED card slides by its VISIBLE box: top row {found[1] if found else None} "
          f"(wanted {wanted[1]:.1f} ± 1)")
    check(found is not None and abs(found[0] - wanted[0]) <= 1,
          f"…and its left column does not move: {found[0] if found else None} "
          f"(wanted {wanted[0]:.1f} ± 1)")


# ---- section 3: fade, zoom and pop ---------------------------------------


def scale_part(mcp):
    print("\n3 — `fade`, `zoom_in` and `pop`")
    session, clip = card_session(mcp, "e2-fade")
    set_motion(session, clip, motion(arrive=edge("fade", 1.0)))
    pixel = session.image(SEC // 2).centre()
    wanted = round(192 * ease("ease_out", 0.5))
    check(abs(pixel[0] - wanted) <= 1,
          f"`fade` at half its duration draws the EASED opacity: {pixel} (wanted {wanted} ± 1)")

    zoom, zclip = card_session(mcp, "e2-zoom")
    set_motion(zoom, zclip, motion(arrive=edge("zoom_in", 1.0)))
    image = zoom.image(SEC // 2)
    found = ink_box(image)
    factor = 0.6 + 0.4 * ease("ease_out", 0.5)
    wanted = drawn_box(640, 360, (0, 0, 0, 0), factor, 0.0, 0.0, 0.0, 640, 360)
    check(found is not None
          and abs(found[0] - wanted[0]) <= 1 and abs(found[1] - wanted[1]) <= 1
          and abs(found[2] - (wanted[2] - 1)) <= 1 and abs(found[3] - (wanted[3] - 1)) <= 1,
          f"`zoom_in` at u = 0.5 draws the card at {factor:.2f} of its size about its centre: "
          f"{found} (wanted {tuple(round(v) for v in wanted)})")
    check(abs(image.centre()[0] - round(192 * ease("ease_out", 0.5))) <= 1,
          f"…at the eased opacity ({image.centre()})")

    crop = (200.0, 0.0, 0.0, 100.0)
    czoom, cclip = card_session(
        mcp, "e2-zoom-crop",
        crop={"l": crop[0], "t": crop[1], "r": crop[2], "b": crop[3]})
    set_motion(czoom, cclip, motion(arrive=edge("zoom_in", 1.0)))
    found = ink_box(czoom.image(SEC // 2))
    wanted = drawn_box(640, 360, crop, factor, 0.0, 0.0, 0.0, 640, 360, base_scale=1.0)
    centre_now = ((found[0] + found[2] + 1) / 2.0, (found[1] + found[3] + 1) / 2.0)
    centre_want = ((wanted[0] + wanted[2]) / 2.0, (wanted[1] + wanted[3]) / 2.0)
    check(abs(centre_now[0] - centre_want[0]) <= 1 and abs(centre_now[1] - centre_want[1]) <= 1,
          f"…and a CROPPED card zooms about its VISIBLE centre, not its anchor: "
          f"{centre_now} (wanted {centre_want})")
    check(abs((found[2] - found[0] + 1) - (wanted[2] - wanted[0])) <= 1
          and abs((found[3] - found[1] + 1) - (wanted[3] - wanted[1])) <= 1,
          f"…at the same {factor:.2f} ({found[2] - found[0] + 1} × {found[3] - found[1] + 1}, "
          f"wanted {wanted[2] - wanted[0]:.0f} × {wanted[3] - wanted[1]:.0f})")

    pop, pclip = card_session(mcp, "e2-pop", size=(300, 200))
    set_motion(pop, pclip, motion(arrive=edge("pop", 1.0)))
    for seconds in (0.6, 0.8):
        wanted = 300 * back_out(seconds)
        width = ink_width(pop.image(int(seconds * SEC)))
        check(width is not None and abs(width - wanted) <= 1,
              f"`pop` at u = {seconds} is {width} px wide (wanted {wanted:.1f} ± 1 — "
              "over its static size, and coming back)")
    width = ink_width(pop.image(SEC))
    check(width is not None and abs(width - 300) <= 1,
          f"…and lands on exactly its static size at u = 1 ({width})")


# ---- section 4: the four continuous presets ------------------------------


def during_part(mcp):
    print("\n4 — `spin`, `shake`, `drift` and `bounce`")
    spin, sclip = card_session(mcp, "e2-spin", size=(200, 200))
    set_motion(spin, sclip, motion(during=slot("spin", 0.5, 0.8)))
    at_period = spin.frame(4 * SEC // 5)
    check(at_period == none_frame(spin, sclip, 4 * SEC // 5),
          f"one whole period of `spin` is byte-identical to no motion — the rem_euclid(360) "
          f"rule, exact by construction ({at_period})")
    found = ink_box(spin.image(SEC // 10))
    side = 200 * math.sqrt(2.0)
    check(found is not None
          and abs((found[2] - found[0] + 1) - side) <= 2
          and abs((found[3] - found[1] + 1) - side) <= 2,
          f"…and an EIGHTH of one turns the square 45°: bounding box "
          f"{found[2] - found[0] + 1} × {found[3] - found[1] + 1} (wanted {side:.1f} ± 2)")

    # **Where a whole turn that is not EXACTLY no turn actually shows.** A
    # rotation of 360 reaches the compositor as `Float(360·π/180)`, whose
    # `sin` is ~1.7e-7 rather than 0 — far too small to move a pixel by
    # itself. What it moves is a GUARD: `MetalRenderer.partnerBox` answers nil
    # for a partner that is rotated at all, and the outgoing half of a cross
    # dissolve then loses the coverage correction and is drawn at `1 − p`
    # instead of at full alpha (`Compositor.swift`, `Compositor.metal`). So
    # the reduction is measured on the INCOMING clip of a dissolve, which is
    # the case `motion.rs`'s module doc names.
    pair = Session(mcp, "e2-spin-partner", background=(0, 0, 0))
    ptrack = pair.tracks()[0]
    pair.card(ptrack, grey(192), at=0, duration=5 * SEC)
    later = pair.card(ptrack, grey(64), at=3 * SEC, duration=5 * SEC)
    check(pair.clip(later)["transition_in"] is not None,
          "the pair overlaps, so the later card is a dissolve's incoming half")
    set_motion(pair, later, motion(during=slot("spin", 0.5, 0.8)))
    at = 3 * SEC + 4 * SEC // 5        # the incoming clip's own 0.8 s: one period
    spun = pair.frame(at)
    check(spun == none_frame(pair, later, at),
          f"…and one whole period is byte-identical to no motion even where the RENDERER "
          f"reads the layer's rotation — `rem_euclid(360)` makes a whole turn exactly no "
          f"turn ({spun})")

    long_shake, lclip = card_session(mcp, "e2-shake-long", size=(200, 200), duration=60 * SEC)
    short_shake, shclip = card_session(mcp, "e2-shake-short", size=(200, 200), duration=5 * SEC)
    for session, clip in [(long_shake, lclip), (short_shake, shclip)]:
        set_motion(session, clip, motion(during=slot("shake", 0.5, 1.0)))
    at = 11 * SEC // 10
    long_frame, short_frame = long_shake.frame(at), short_shake.frame(at)
    check(long_frame == short_frame,
          f"`shake` reads its PERIOD and not the clip: a 60 s clip and a 5 s one are "
          f"byte-identical at the same clip time ({long_frame})")
    check(long_frame != none_frame(long_shake, lclip, at),
          "…and it is actually shaking there")

    drift, dclip = card_session(mcp, "e2-drift", size=(300, 200), duration=3 * SEC)
    set_motion(drift, dclip, motion(during=slot("drift", 0.5, 1.0)))
    t = 89 * FRAME
    wanted = 300 * (1.0 + 0.24 * 0.5 * t / (3 * SEC))
    width = ink_width(drift.image(t))
    check(width is not None and abs(width - wanted) <= 1,
          f"`drift` reads the CLIP and not the period: {width} px wide at frame 89 "
          f"(wanted {wanted:.1f} ± 1)")

    bounce, bclip = card_session(mcp, "e2-bounce", size=(200, 200))
    set_motion(bounce, bclip, motion(during=slot("bounce", 0.5, 1.0)))
    found = ink_box(bounce.image(SEC // 2))
    lift = 0.08 * 0.5 * 360 * abs(math.sin(math.pi * 0.5))
    wanted = (360 - 200) / 2.0 - lift
    check(found is not None and abs(found[1] - wanted) <= 1,
          f"`bounce` at half a period is lifted by 0.08·A·H: top row "
          f"{found[1] if found else None} (wanted {wanted:.1f} ± 1)")


# ---- section 5: composition ----------------------------------------------


def compose_part(mcp):
    print("\n5 — the tent, an action under an arrival, two slots, and a nest")
    # A four-second card with THREE-second edges: in′ = out′ = 2 s, and both
    # halves land on the 30 fps grid. (A three-second card with 2 s edges
    # would want its half-edges between frames.)
    tent, tclip = card_session(mcp, "e2-tent", size=(300, 200), duration=4 * SEC)
    set_motion(tent, tclip, motion(arrive=edge("fade", 3.0), leave=edge("fade", 3.0)))
    meeting = tent.frame(2 * SEC)
    check(meeting == none_frame(tent, tclip, 2 * SEC),
          f"the tent makes the arrival end on the frame the departure begins, and that frame "
          f"is byte-identical to no motion ({meeting})")
    wanted = round(192 * 0.75)
    for at, what in [(SEC, "arriving"), (3 * SEC, "departing")]:
        pixel = tent.image(at).centre()
        check(abs(pixel[0] - wanted) <= 1,
              f"…and halfway through each scaled edge the opacity is 0.75 ({what}: {pixel}, "
              f"wanted {wanted} ± 1; un-tented it would read "
              f"{round(192 * ease('ease_out', 1 / 3)) if what == 'arriving' else round(192 * (1 - ease('ease_in', 1 / 3)))})")

    acted, aclip = card_session(mcp, "e2-action", size=(300, 200))
    action = acted.op("add_action", clip=aclip, at=0, duration=SEC)["new_actions"][0]
    acted.op("set_action_end", clip=aclip, action=action, patch={"video": {"x": 100}})
    control = ink_box(acted.image(SEC // 2))
    set_motion(acted, aclip, motion(arrive=edge("slide_up", 1.0)))
    found = ink_box(acted.image(SEC // 2))
    check(found is not None and found[0] == control[0],
          f"an action moving `x` goes on moving under an arrival: left column {found[0]} "
          f"= the action-only control's {control[0]}")
    delta = slide_edge("slide_up", 0.5, 300, 200, (0, 0, 0, 0), 1.0, 0.0, 0.0, 0.0, 640, 360)
    wanted_top = (360 - 200) / 2.0 + delta[1]
    check(found is not None and abs(found[1] - wanted_top) <= 1,
          f"…and the arrival adds its own offset on top: top row {found[1]} "
          f"(wanted {wanted_top:.1f} ± 1)")

    both, bclip = card_session(mcp, "e2-both", size=(300, 200))
    set_motion(both, bclip,
               motion(arrive=edge("zoom_in", 1.0), during=slot("pulse", 1.0, 1.0)))
    factor = (0.6 + 0.4 * ease("ease_out", 0.5)) * (
        1.0 + 0.2 * 1.0 * (1.0 - math.cos(2 * math.pi * 0.5)) / 2.0)
    width = ink_width(both.image(SEC // 2))
    check(width is not None and abs(width - 300 * factor) <= 1,
          f"two slots MULTIPLY rather than replace: {width} px wide "
          f"(wanted 300 · {factor:.3f} = {300 * factor:.1f} ± 1)")

    nested = Session(mcp, "e2-nest", background=(0, 0, 0))
    track = nested.tracks()[0]
    inner = nested.card(track, grey(192), size=(200, 200), at=0, duration=4 * SEC)
    nested.op("set_video", clips=[inner], patch={"x": 100})
    nest = nested.op_with("nest", {"clips": [inner]})["new_clips"][0]
    set_motion(nested, nest, motion(arrive=edge("zoom_in", 1.0)))
    image = nested.image(SEC // 2)
    found = ink_box(image)
    scale = 0.6 + 0.4 * ease("ease_out", 0.5)
    check(found is not None and abs((found[2] - found[0] + 1) - 200 * scale) <= 1,
          f"a nest clip's arrival scales every inner layer: {found[2] - found[0] + 1} px wide "
          f"(wanted {200 * scale:.1f} ± 1)")
    centre_x = (found[0] + found[2] + 1) / 2.0
    wanted_x = 320 + scale * 100
    check(abs(centre_x - wanted_x) <= 1,
          f"…about the NEST clip's placed centre, not each layer's: centre x {centre_x} "
          f"(wanted {wanted_x:.1f} ± 1)")
    check(abs(image.centre()[0] - round(192 * ease("ease_out", 0.5))) <= 1,
          f"…and at the nest's own eased opacity ({image.centre()})")


# ---- section 6: the model rules ------------------------------------------


def model_part(mcp):
    print("\n6 — what the MODEL says while the picture moves")
    session, clip = card_session(mcp, "e2-model")
    set_motion(session, clip, motion(arrive=edge("slide_left", 1.0)))
    video = session.clip(clip)["video"]
    moved = session.frame(SEC // 2)
    check(video["x"] == 0 and video["y"] == 0,
          f"`get_project` reports the clip UN-MOVED (x = {video['x']}, y = {video['y']})")
    check(moved != none_frame(session, clip, SEC // 2),
          "…while `render_frame` draws it somewhere else entirely")
    # And an EDIT sees the un-moved clip too, which is the half a render
    # check cannot see: `split_clip` writes the second piece's video props
    # straight out of `evaluate_clip`, so a build that applied the preset
    # THERE instead of in the recipe would bake the moved position into the
    # file — a careless render check would never notice (`motion.rs`'s module
    # doc names this exact mistake).
    session.op("split", clips=[clip], at=SEC // 2)
    halves = sorted(session.project()["clips"], key=lambda c: c["start"])
    check(len(halves) == 2 and all(h["video"]["x"] == 0 and h["video"]["y"] == 0
                                   for h in halves),
          f"…and a split taken MID-ARRIVAL writes two pieces that are still at the "
          f"origin ({[(h['video']['x'], h['video']['y']) for h in halves]})")

    split_session, sclip = card_session(mcp, "e2-split")
    set_motion(split_session, sclip,
               motion(arrive=edge("slide_left", 1.0), leave=edge("fade", 1.0),
                      during=slot("pulse", 0.5, 1.0)))
    split_session.op("split", clips=[sclip], at=3 * SEC // 2)
    pieces = sorted(split_session.project()["clips"], key=lambda c: c["start"])
    first, second = (p["video"]["motion"] for p in pieces)
    check(len(pieces) == 2, f"a split in the middle makes two pieces ({len(pieces)})")
    check(first is not None and first["in"] is not None and first["out"] is None,
          f"the first piece keeps the arrival and loses the departure ({first})")
    check(second is not None and second["in"] is None and second["out"] is not None,
          f"…and the second keeps the departure and loses the arrival ({second})")
    check(first is not None and second is not None
          and first["during"] is not None and second["during"] is not None,
          "…while the DURING is on both, since it belongs to neither end")

    ripple, rclip = card_session(mcp, "e2-ripple", duration=4 * SEC)
    set_motion(ripple, rclip, motion(arrive=edge("slide_left", 1.0), leave=edge("fade", 1.0)))
    ripple.op(
        "ripple_delete_ranges",
        ranges=[[SEC // 2, 7 * SEC // 10], [3 * SEC // 2, 17 * SEC // 10],
                [5 * SEC // 2, 27 * SEC // 10]])
    pieces = sorted(ripple.project()["clips"], key=lambda c: c["start"])
    arrivals = [i for i, p in enumerate(pieces)
                if (p["video"]["motion"] or {}).get("in") is not None]
    departures = [i for i, p in enumerate(pieces)
                  if (p["video"]["motion"] or {}).get("out") is not None]
    check(len(pieces) == 4, f"three ranges cut the clip into four pieces ({len(pieces)})")
    check(arrivals == [0], f"exactly ONE piece arrives, the first ({arrivals})")
    check(departures == [len(pieces) - 1],
          f"…and exactly one departs, the last ({departures})")

    text = Session(mcp, "e2-text", background=(0, 0, 0))
    ttrack = text.tracks()[0]
    tclip = text.op(
        "add_text_clip", track=ttrack, at=0, duration=4 * SEC,
        text={"content": "Hello", "size": 96.0})["new_clips"][0]
    text.op("set_text", clips=[tclip],
            patch={"animation": {"kind": "typewriter", "in": SEC, "out": SEC}})
    before = [text.frame(2 * SEC), text.frame(2 * SEC + 14 * FRAME)]
    text.op("split", clips=[tclip], at=5 * SEC // 2)
    after = [text.frame(2 * SEC), text.frame(2 * SEC + 14 * FRAME)]
    check(before == after,
          f"a split text clip's FIRST half ends fully revealed — the un-reveal went with the "
          f"second half ({before} vs {after})")


# ---- section 7: the export path ------------------------------------------


def export_part(mcp):
    print("\n7 — motion reaches the export path")
    session, clip = card_session(mcp, "e2-export")
    set_motion(session, clip, motion(arrive=edge("slide_left", 1.0)))
    session.op("set_range", start=0, end=SEC)
    target = os.path.join(WORK, f"e2-export-{os.getpid()}.apng")
    if os.path.exists(target):
        os.remove(target)
    written = session.op("export", preset="apng", path=target, range="in_out")["path"]
    frames = os.path.join(WORK, f"e2-export-frames-{os.getpid()}")
    if os.path.exists(frames):
        shutil.rmtree(frames)
    os.makedirs(frames)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", written,
         os.path.join(frames, "frame_%03d.png")], check=True)
    written_frames = sorted(os.listdir(frames))
    check(len(written_frames) >= 13,
          f"the APNG holds {len(written_frames)} frames (the image-sequence writer refuses "
          "past 600, which is why the range is set)")
    # 25 fps is the `apng` preset's own rate (`core/src/export_table.rs`), so
    # frame 13 is t = 12/25 s; the picture is 960 × 540, 1.5× the canvas.
    image = Frame(os.path.join(frames, "frame_013.png"))
    at = 12 / 25.0
    wanted = image.width * (1.0 - ease("ease_out", at))
    found = ink_box(image)
    # The `apng` preset's 960 × 540 is a CAP and not a frame to letterbox
    # into: an image format is written with the picture fitted inside the
    # size, aspect kept and NEVER upscaled (`core/src/export_size.rs`), so a
    # 640 × 360 canvas is written at 640 × 360.
    check((image.width, image.height) == CANVAS,
          f"…at the canvas's own size, the preset's 960 × 540 being a cap and never an "
          f"upscale ({image.width} × {image.height})")
    check(found is not None and abs(found[0] - wanted) <= 2,
          f"frame 13 (t = {at:.2f} s) has the card's leading column at "
          f"{found[0] if found else None} (wanted {wanted:.1f} ± 2)")


def zero_edges_part(mcp):
    print("\n8 — zero In/Out stay stored and inactive until Duration increases")
    session, clip = card_session(mcp, "e2-zero")
    first, last = 0, 4 * SEC - FRAME
    control = (session.frame(first), session.frame(last))
    zero = motion(arrive=edge("fade", 0), leave=edge("fade", 0))
    set_motion(session, clip, zero)
    stored = session.clip(clip)["video"]["motion"]
    check(stored["in"] == zero["in"] and stored["out"] == zero["out"],
          "explicit zero In/Out retain both Fade kinds and durations")
    check((session.frame(first), session.frame(last)) == control,
          "zero In/Out render byte-identically to no motion at first and last frames")
    saved = session.save()
    copy = os.path.join(WORK, f"e2-zero-reopen-{os.getpid()}.reelcut")
    if os.path.exists(copy):
        shutil.rmtree(copy)
    shutil.copytree(session.path, copy)
    reopened = Session.opened(mcp, copy)
    check(reopened.clip(clip)["video"]["motion"] == stored
          and json.loads(saved)["clips"][0]["video"]["motion"] == stored,
          "save and reopen keep configured zero edges unchanged")
    check((reopened.frame(first), reopened.frame(last)) == control,
          "reopened zero edges still render as no motion")

    set_motion(session, clip, motion(arrive=edge("fade", FRAME / SEC)))
    check(session.frame(first) != control[0],
          "one-frame positive Fade In reactivates the first frame")
    session.undo()
    check(session.clip(clip)["video"]["motion"] == stored
          and (session.frame(first), session.frame(last)) == control,
          "one undo restores both stored zeros and inactive rendering")
    set_motion(session, clip, motion(leave=edge("fade", 2 * FRAME / SEC)))
    check(session.frame(last) != control[1],
          "two-frame positive Fade Out changes the last drawn frame")
    session.undo()
    check(session.clip(clip)["video"]["motion"] == stored
          and session.frame(last) == control[1],
          "undo restores zero Out and its unchanged last frame")


# ---- main ----------------------------------------------------------------


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4825
    os.makedirs(WORK, exist_ok=True)
    print(f"E2 — motion presets. Build on {port}.")
    mcp = MCP(port)
    instance_part(mcp, port)
    schema_part(mcp)
    slide_part(mcp)
    scale_part(mcp)
    during_part(mcp)
    compose_part(mcp)
    model_part(mcp)
    export_part(mcp)
    zero_edges_part(mcp)

    print()
    if skipped:
        print("SKIPPED:")
        for line in skipped:
            print(f"  - {line}")
    if failures:
        print(f"{checks - len(failures)}/{checks} checks passed — {len(failures)} FAILED:")
        for line in failures:
            print(f"  - {line}")
        sys.exit(1)
    print(f"{checks}/{checks} checks passed")


if __name__ == "__main__":
    main()
