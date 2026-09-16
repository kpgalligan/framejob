"""Road map 2, phase 6 — Looks, driven against the built binary over MCP.

Every absolute claim here is a claim about a BYTE in a PNG, so the fixture is
the first thing this script proves rather than the first thing it assumes.

**Section 0 is scored, not assumed.** Black is the one value every colour
transform fixes — a broken multiply, a stray linearise, a colour-managed
blit all leave 0 at 0 — so nothing in phases 1 to 5 says anything about a
MID-TONE, and every number below is a mid-tone. So the script paints a card
at exactly 128/255, renders it and asserts a corner pixel reads
(128, 128, 128, 255); then 64, 192, 32 and 224, the other four values the
later sections name as literals. **If one of them drifts, the FIXTURE fails
by name** and the blend arithmetic is not blamed for a pipeline that moved
under it.

Every blend expectation below is then written TWICE: once as the FORMULA
over the two cards' MEASURED bytes (`round(a * b / 255)` and its seven
siblings), which is the real claim about the shader, and once as the road
map's LITERAL 64 / 192 / 255. A wrong formula fails both. A pipeline that
drifted by a bit fails only the literal, and the two are told apart by which
line goes red.

**This compositor blends in the ENCODED sRGB space, deliberately.** Nothing
in the pipeline uses an `_srgb` texture format, so the fragment stage
computes on the stored 8-bit values — the same space every other stage
already works in. "A multiply of 50 % grey over 50 % grey is 25 %" is a
statement about ENCODED values and is FALSE in linear light: linearise both
128s, multiply, re-encode, and the answer is about **61**/255, four steps
darker than the 64 this script measures — a small difference, and four times
the ±1 tolerance every check below carries, so the two readings cannot both
pass. A reader who knows colour will see the 64, take it for the wrong
answer and reach for a linearise/encode pair around `blendPremultiplied`,
which would break every number here and look like the proof was wrong. It is
not. The same sentence is in `Compositor.metal`'s order-of-operations
comment and in spec §7.5.

Note also that **128 is not 0.5, and the ±1/255 tolerance every check below
carries is ALREADY SPENT on that**: `round(128 × 128 / 255)` is 64 against
`0.25 × 255` = 63.75, three quarters of a step away. There is no headroom
left for a pipeline that drifts by one, which is the whole reason section 0
exists and runs first.

**The fixture is SHAPE CLIPS.** Two full-canvas rectangles on two tracks,
`stroke: null`, flat fills, canvas 640 × 360, and no media in the blend
checks at all — which is what `video.blend` belonging to the LAYER rather
than to a source kind buys. A shape card is exact by construction, needs no
decoder, and loads nothing asynchronously, so a byte that is wrong is the
compositor's and not a codec's. Shape clips were untrodden ground in
`tools/proof/` when this was written — no earlier script had placed one —
which is the other reason section 0 renders one card and reads its centre
pixel before anything is built on top of it.

Two colour rules the fixture obeys, both measured rather than assumed:

* **Every fill is k/255 for a whole k.** `CGGradient` DITHERS, so a colour
  8 bits cannot hold (0.25 → 63.75) comes back as a ±1 cloud and a
  one-colour gradient is then NOT byte-identical to the flat fill it should
  match. At 64/255 it is, at every angle and for radial too. Section 9
  scores both halves of that, because the trap is invisible until a check
  fails for a reason that has nothing to do with the feature.
* **The plateau, not the ramp, is where a gradient's colours are read.**
  A `CGGradient` is sampled at pixel centres through an interpolation table
  of its own, so a ramp's own ends read within a couple of steps of the stop
  colours and wobble by up to 3/255 between them. Sections 10 and 11 put the
  stops at 0.25 and 0.75 and read the FLAT bands `drawsBeforeStartLocation`
  and `drawsAfterEndLocation` leave outside them, which are exact.

**What is measured, section by section.**

* **0** the fixture: the canvas background and five card values, byte-exact;
  the card uniform; the PNG 8-bit (a 16-bit one would silently change what
  "a byte" means — a ProRes 4444 source produces one).
* **1–3 (B1, B2, B3)** the eight modes at the centre pixel, each against its
  own formula and its own literal; overlay measured with a **192 source over
  a 64 base**, never at 128, because 128/255 = 0.50196 sits on the branch
  knife edge (it takes the screen half and gives 128.498, which rounds
  either way depending on where the comparison is written) and because 96 is
  a number an unblended backdrop cannot produce where 64 is; and the eight
  walked as a CHAIN, since `{"blend": "normal"}` on a never-blended clip is
  the identity and correctly answers "made no change", so a sweep writing
  all eight from one base would fail on its first line.
* **4 (B4)** a blended layer's SHADOW is byte-identical to the same project
  at `normal` while the layer's own pixels differ. What that pins is the
  shadow's own DRAW staying fixed-function source-over on `shadowPipeline`.
  It is NOT a check on `maskState`, and the correction is worth carrying
  here because the phase believed the opposite while it was being written:
  the silhouette pass draws COVERAGE into a texture cleared to transparent
  black, and a blend over THAT reduces to the source exactly — the
  premultiplied formula's `(1 - ab)·src` term carries it through at
  `ab` = 0, for all eight modes — so a build passing the layer's blend
  variant into `encodeShadow` renders every shadow correctly and survived
  every check in this script. `maskState` is DEFENSIVE: it says what the
  mask pass means, and a future formula without that term would make the
  hazard real. Nothing here can tell it from `state`, and this section does
  not claim to.
* **5 (B5)** every frame of a cross-dissolve overlap is byte-identical to
  the same project at `normal`, with the blend on either half — the
  renderer's half of the rule the CORE owns (`recipe.rs::layer` emits
  `"normal"` whenever the layer's transition is non-null). The core's own
  half is a test in `core/tests/evaluate_tests.rs` reading the layer's
  `blend` at a tick inside the overlap, which is the check a renderer-side
  rule could not have had. The model still says `multiply` throughout, and
  that is asserted too: the recipe's blend is what DRAWS and the inspector
  reads the model's, so the two legitimately differ during an overlap.
* **6 (B6)** a blended layer at 50 % OPACITY over an opaque backdrop equals
  `mix(dst, blend(src, dst), 0.5)` ±1 — the opacity MIX, and nothing more.
  It was written to be the check that catches the spike's trap (Metal
  builds a programmable-blend pipeline with fixed-function blending still
  ENABLED, with no error and no warning) and it CANNOT be, which the
  phase's mutation run measured. What decides whether the second blend
  shows is the DESTINATION's alpha and not the layer's: the fragment stage
  returns the FINISHED composite, whose alpha is `as + ab·(1 - as)` = 1
  over any opaque backdrop, so `oneMinusSourceAlpha` is 0 and the second
  blend contributes exactly nothing at every source alpha. The three
  "…and NOT doubled" assertions this section used to carry excluded a value
  no build produces; they are gone rather than left scoring.
* **6b** the check that DOES catch it, and the only one here that reads the
  ALPHA channel: a TRANSLUCENT destination with a source that does not
  cover it, where a second blend lands the alpha 32/255 high while the
  colour moves by two.
* **7 (B7)** the nest refusals, through all three doors: `set_video`, which
  refuses a non-normal value by name and takes `normal` as the identity it
  is; `paste_attributes`, which is WHY the refusal is written that way —
  the group is replaced whole, so refusing every paste that mentioned
  `blend` would fail an all-or-nothing paste of an ordinary look; and
  `set_action_end`, which stores the mode (an end patch validates nothing
  but its shape) and must still DRAW `normal`, since `clamp_video` forces
  it. Beside them the documented limit on the other side — a blend set on a
  clip BEFORE it is nested is carried inside and blends against the whole
  canvas below the nest, because a nest is flattened rather than composited
  offscreen.
* **8** the same arithmetic over a DECODED picture rather than a drawn one,
  which is what says `video.blend` belongs to the LAYER and not to a source
  kind. **Not the `qtrle` card `README.md` gives**: on macOS 26.5.1 an
  RGB-coded `.mov` imports and then fails every `render_frame`, measured, so
  the card here is lossless 4:4:4 H.264 and `CARD_LINE` says why.
* **9–13 (G1–G5)** the gradients, ending with the texture cache: two shape
  descriptions differing ONLY in their gradient must render as two different
  textures in ONE frame. Phase 4's text lesson repeated — a `render_frame`
  builds its own compositor and its own cache, so a two-render comparison
  would prove nothing about a stale key and the two clips have to be in the
  same picture. Two of the geometry checks are there because the obvious
  fixture cannot fail for the decision it is named after: 10 draws one
  STROKED card, because every other gradient here is `stroke: null` and the
  ramp then spans the same rectangle whether it is inset or not; and 11
  reads two points half way out, because the centre, the four edge midpoints
  and the corner all read the same bytes under an inscribed CIRCLE as under
  the inscribed ellipse the section claims.
* **14–16 (C1–C3)** the two background commands. **C3 is the check no frame
  can make**: the blurred copy carries `enabled.audio: false`, and the road
  map's own wording — "byte-identical to the same ops applied by hand" —
  passes with the bug present on BOTH sides. So the project WITH the
  backdrop is exported and compared sample for sample against the same
  project without it, and then the copy's audio is switched back on to show
  what the check is worth: the peak doubles.
* **17 (D)** 6d's oracle — an action `blur 0 → blur 1`, linear, rendered at
  its midpoint is BYTE-identical to a static `blur 0.5` — plus the partial
  filter entry `{"filters": [{"amount": 1}]}`, refused by index now rather
  than silently completed into a blur.
* **18** the catalog at EXACTLY 73, and the schema keys off the written
  file.

**Two things this script cannot prove, said here rather than left to a
reader to discover.** D-1 and D-2 — the two residual defects phase 6 closed
in `InspectorBinding.editedList` — are WRITE-SIDE inspector behaviour and
have no MCP surface at all: over the wire a caller says which of
`set_video` and `set_action_end` it wants, so the redirect the defects live
in is never entered. What is reachable is the mechanism underneath, and
section 17 pins it. And the exact tool count is asserted here because phase
6 is the newest phase: it is the only thing that tells a stale binary on the
port from the build under test, and phases 1 to 5 keep floors so a later
phase's tools never fail an older proof.

**Media.** Nothing is added to `media/`. Section 8's one card is written
into `work/` per run. `ffmpeg` IS needed at proof time, for that card and to
decode C3's two exports to raw PCM.
"""

import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import zlib
from array import array

from mcp import MCP, ToolError

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4823
HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work")

SEC = 600_000
CANVAS = (640, 360)

# The whole catalog after phase 6: 55 ops (`core/src/edit.rs`'s OP_NAMES,
# which phase 6 took from 53 with `add_background` and
# `add_blurred_background`) plus the 18 tools that mirror no op. The EXACT
# count belongs to the NEWEST phase's script, because it is the only thing
# that tells a stale binary on the port from the build under test; phases 1
# to 5 keep floors (63, 65, 68, 70, 71) so a later phase's tools never fail
# an older proof. Phase 9 is where that handover finally cost something:
# `set_scope` is the first tool added since phase 6, so the exact count moved
# to phase 9's script and this one — and phases 7 and 8, which had both
# inherited the number rather than raised it — became floors in the same
# change.
TOOLS = 73

# What this build writes. An older file must still OPEN — that is
# `core/tests/schema_v6.rs`'s claim — but what THIS build saves is version 6,
# and that number moves with every bump.
VERSION = 8

# The one lossless card section 8 decodes, written per run. **It is not the
# `qtrle` line `README.md` gives**, and the substitution is measured rather
# than a preference: on macOS 26.5.1 an RGB-coded `.mov` — `qtrle` and
# `png`-in-`mov` alike — IMPORTS (the probe reads its size, rate and length)
# and then fails every `render_frame` with "No frame at <t>", so a card
# written that way cannot be photographed at all. Lossless 4:4:4 H.264 can:
# `color=c=0x808080` survives the YUV round trip to exactly 128 because grey
# sits on the achromatic axis, where only the range mapping applies and it
# rounds back. Nothing here rests on that number being 128 all the same —
# section 8 MEASURES the card's own byte first and states its expectations
# over what it measured, exactly as section 0 does for the drawn cards.
CARD_LINE = [
    "ffmpeg", "-y", "-v", "error",
    "-f", "lavfi",
    "-i", "color=c=0x808080:size=640x360:rate=30:duration=5,format=yuv444p",
    "-c:v", "libx264", "-qp", "0", "-pix_fmt", "yuv444p",
]

failures = []
checks = 0


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def grey(value):
    """A colour argument for an 8-bit grey. Every fill in this script goes
    through here, because a value 8 bits cannot hold is the one way to make
    section 9's byte comparison fail on correct code (see the docstring)."""
    return [value / 255.0, value / 255.0, value / 255.0, 1.0]


def rgb(r, g, b):
    """The same for a colour whose three channels differ — section 3's, where
    the point is that no two of the eight modes agree."""
    return [r / 255.0, g / 255.0, b / 255.0, 1.0]


# ---- the eight blend formulas, in Python ---------------------------------
#
# Transcribed from `Compositor.metal`'s `blendPremultiplied` contract as the
# CONTRACT states it (§3.2), not from the shader source: the two agreeing is
# the claim being made, so they may not share a line. With both layers opaque
# — `as` = `ab` = 1, which is every card in this fixture — the general
# formula
#
#     rgb = (1 - as)·dst + (1 - ab)·src + as·ab·B(Cs, Cb)
#
# reduces to `B(Cs, Cb)` exactly, and at a partial source alpha with an
# opaque destination it reduces to `mix(dst, B, as)`, which is section 6.
# `add` is plus-lighter and not a separable blend at all, so it is not
# expressed through B.


def blend255(mode, source, dest):
    """One channel of `mode`, both operands opaque, in 0–255 REAL numbers —
    unrounded, so a caller can round once at the end the way the shader
    does."""
    if mode == "add":
        return min(255.0, float(source) + float(dest))
    cs, cb = source / 255.0, dest / 255.0
    if mode == "normal":
        b = cs
    elif mode == "multiply":
        b = cs * cb
    elif mode == "screen":
        b = cs + cb - cs * cb
    elif mode == "overlay":
        # HardLight with the operands swapped: the BASE picks the branch.
        b = 2 * cs * cb if cb <= 0.5 else 1 - 2 * (1 - cs) * (1 - cb)
    elif mode == "darken":
        b = min(cs, cb)
    elif mode == "lighten":
        b = max(cs, cb)
    elif mode == "difference":
        b = abs(cs - cb)
    else:
        raise RuntimeError(f"{mode} is not a blend mode")
    return b * 255.0


def blended(mode, source, dest, opacity=1.0):
    """The whole expected pixel, rounded once — `mix(dst, B, as)` for an
    opaque destination, which is `B` itself at full opacity.

    ALPHA is not a fourth colour channel and does not go through `B`: the
    contract's formula gives it separately as `as + ab·(1 - as)`, which over
    an opaque destination is 1 whatever the source's own alpha is. Running it
    through `B` instead is a real mistake and not a pedantic one —
    `difference` of two opaque layers would predict alpha 0, a transparent
    frame, which is nothing the compositor ever writes."""
    rgb_out = tuple(
        int(round((1 - opacity) * d + opacity * blend255(mode, s, d)))
        for s, d in zip(source[:3], dest[:3]))
    source_alpha = opacity * (source[3] / 255.0 if len(source) > 3 else 1.0)
    dest_alpha = dest[3] / 255.0 if len(dest) > 3 else 1.0
    return rgb_out + (int(round(255 * (source_alpha + dest_alpha * (1 - source_alpha)))),)


def near(measured, wanted, tolerance=1):
    """Whether a pixel matches component by component, alpha included."""
    if measured is None or len(measured) != len(wanted):
        return False
    return all(abs(a - b) <= tolerance for a, b in zip(measured, wanted))


def show(pixel):
    return "none" if pixel is None else "(" + ", ".join(str(v) for v in pixel) + ")"


# ---- PNG, in pure Python -------------------------------------------------
#
# The same decoder `phase2_chrome.py` and `phase3_proof.py` carry: chunks,
# zlib, the five filters. Copied rather than imported because those files are
# SCRIPTS — importing one would run its main — and because a proof that
# measures its own evidence should carry the decoder it trusts.
#
# The 8-bit guard is not paperwork here. `render_frame` writes a PNG at the
# depth the frame needs, and a 10-bit source (ProRes 4444) makes a SIXTEEN-bit
# one — measured — which would silently change what "a byte" means for every
# number in this script. Section 0 scores the depth for that reason.


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
        """Every step-th pixel, as a set — "the card is one flat colour"
        without walking a quarter of a million pixels."""
        return {
            self.pixel(x, y)
            for y in range(0, self.height, step)
            for x in range(0, self.width, step)
        }

    def changed(self, other):
        """Every (x, y) whose bytes differ from `other`'s."""
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


# ---- the project under test ----------------------------------------------


class Session:
    """One project, the shape phases 2 to 5 use.

    `<name>-<pid>.reelcut`, never a fixed name: a `project` path is matched
    against every open document and no tool closes one, so two earlier runs'
    SAVED packages would have the app answering for an old one (measured in
    phase 2). Older runs' under this name go."""

    def __init__(self, mcp, name, canvas=CANVAS, background=(0, 0, 0)):
        self.mcp = mcp
        self.name = name
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=canvas[0], height=canvas[1],
                background=[c / 255.0 for c in background] + [1.0])

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def op_with(self, name, arguments):
        """For a tool whose own ARGUMENT is spelled `name` — `nest`'s."""
        arguments = dict(arguments)
        arguments["project"] = self.path
        return self.mcp.call_with(name, arguments)

    def project(self):
        return self.op("get_project")["project"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def named(self, name):
        found = [c for c in self.project()["clips"] if c.get("name") == name]
        return found[0] if found else None

    def tracks(self):
        """Track ids back-most first, which is the order `get_project` lists
        them in and the order `index` counts in."""
        return [t["id"] for t in self.project()["tracks"]]

    def add_track(self):
        self.op("add_track")
        return self.tracks()[-1]

    def card(self, track, fill, size=CANVAS, at=0, duration=3 * SEC):
        """A flat rectangle with no stroke — the fixture's one drawing."""
        return self.op(
            "add_shape_clip", track=track, at=at, duration=duration,
            shape={
                "kind": "rectangle", "width": size[0], "height": size[1],
                "stroke": None, "fill": fill,
            })["new_clips"][0]

    def png(self, t=SEC):
        """The path of the PNG `render_frame` wrote — the tool answers with a
        sentence naming the file, so it is read out of that."""
        answer = self.op("render_frame", t=int(t))
        found = re.search(r"Written to (\S+\.png)\.", str(answer))
        assert found, f"render_frame said something else: {answer}"
        return found.group(1)

    def frame(self, t=SEC):
        """The rendered frame as a hash — the byte-comparison currency."""
        return digest(self.png(t))

    def image(self, t=SEC):
        return Frame(self.png(t))

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

    def export_wav(self, tag):
        """An audio-only export into `work/`, with the pid on it: half of C3's
        claim is a comparison between two files, and a second run must never
        find the first run's."""
        target = os.path.join(WORK, f"{self.name}-{tag}-{os.getpid()}.wav")
        if os.path.exists(target):
            os.remove(target)
        return self.op("export", preset="audio_wav", path=target)["path"]


def pcm(path):
    """`path` decoded to raw signed 16-bit LE stereo 48 kHz, as bytes — the
    same line phases 2 and 5 decode with."""
    out = os.path.splitext(path)[0] + ".pcm"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-f", "s16le",
         "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", out],
        check=True)
    with open(out, "rb") as handle:
        return handle.read()


def peak(data):
    values = array("h")
    values.frombytes(data)
    return max(abs(v) for v in values) if values else 0


# ---- section 0: the fixture ----------------------------------------------
#
# The one section whose failure means "do not read the rest of this run".


CARD_VALUES = [128, 64, 192, 32, 224]


def fixture_part(mcp):
    print("\n0 — the fixture, scored rather than assumed")
    # The canvas BACKGROUND first, because it is what shows where no layer
    # covers and it reaches the frame by a different road from a card's fill
    # (a clear colour on the render pass, not a texture).
    s = Session(mcp, "phase6-fixture", background=(128, 128, 128))
    track = s.tracks()[0]
    s.card(track, grey(192), size=(100, 100))
    image = s.image()
    check(image.depth == 8,
          f"render_frame writes an 8-bit PNG, so a byte is a byte ({image.depth}-bit)")
    check(image.channels == 4, f"…with four channels ({image.channels})")
    check(image.pixel(0, 0) == (128, 128, 128, 255),
          f"the canvas background at 128/255 reads exactly (128, 128, 128, 255) "
          f"— got {show(image.pixel(0, 0))}")

    # Then each card value the later sections name as a literal. One project
    # per value, one clip in it, read at the centre.
    for value in CARD_VALUES:
        card = Session(mcp, f"phase6-card{value}")
        card.card(card.tracks()[0], grey(value))
        picture = card.image()
        wanted = (value, value, value, 255)
        check(picture.centre() == wanted,
              f"a card filled {value}/255 reads exactly {show(wanted)} "
              f"— got {show(picture.centre())}")
        if value == 128:
            check(picture.sampled() == {wanted},
                  "…and every sampled pixel of it is that same byte, so "
                  "\"the centre pixel\" is the whole card "
                  f"(saw {len(picture.sampled())} distinct values)")


# ---- 6a, the blend modes -------------------------------------------------


def stack(mcp, name, base, source, size=CANVAS):
    """The blend fixture: a full-canvas `base` card on the back track and a
    `source` card on a track in front of it. Answers the session and the
    front clip's id.

    What it does NOT answer is the base card's byte: a full-canvas source
    covers it, so a `centre()` taken after this returns reads the SOURCE
    twice over. Section 1 wants both cards MEASURED and builds its own
    fixture for that reason — a caller here that needs the base's own byte
    has to read it before the second card exists."""
    s = Session(mcp, name)
    s.card(s.tracks()[0], base, size=CANVAS)
    front = s.add_track()
    return s, s.card(front, source, size=size)


def modes_part(mcp):
    print("\n1 — B1: the eight modes at the centre pixel (128 over 128)")
    # The road map's own fixture: one mid grey over another. Six of the eight
    # have a literal there; `overlay` does not and is section 2's, and
    # `normal` is the identity the whole feature is measured against.
    base, source = 128, 128
    literals = {
        "normal": 128, "multiply": 64, "screen": 192, "add": 255,
        "darken": 128, "lighten": 128, "difference": 0,
    }
    # BOTH cards' own bytes, MEASURED, which is what the docstring promises
    # and what this section did not do until the review: `stack()` puts the
    # source card full-canvas in FRONT of the base, so a single read taken
    # after both exist is the SOURCE's byte, twice over, and the base card's
    # was never read at all. So the fixture is built here rather than
    # through `stack()`, and the base is read while it is still alone.
    s = Session(mcp, "phase6-modes")
    s.card(s.tracks()[0], grey(base))
    measured_base = s.image().centre()
    clip = s.card(s.add_track(), grey(source))
    measured_source = s.image().centre()
    check(measured_base == (base,) * 3 + (255,)
          and measured_source == (source,) * 3 + (255,),
          f"the base card ALONE reads {show(measured_base)}, and with `normal` never "
          f"set the front card over it reads {show(measured_source)}")
    order = ["multiply", "screen", "add", "darken", "lighten", "difference", "normal"]
    for mode in order:
        if mode != "normal":
            s.op("set_video", clips=[clip], patch={"blend": mode})
        else:
            # `normal` is reached from `difference`, never from `normal`:
            # setting a clip to what it already is is the identity and
            # answers "made no change" (section 3 scores that separately).
            s.op("set_video", clips=[clip], patch={"blend": "normal"})
        pixel = s.image().centre()
        formula = blended(mode, measured_source, measured_base)
        literal = (literals[mode],) * 3 + (255,)
        check(near(pixel, formula),
              f"{mode}: the frame matches the FORMULA over the measured cards "
              f"— {show(pixel)} against {show(formula)}")
        check(near(pixel, literal),
              f"{mode}: …and the road map's literal {literals[mode]} "
              f"— {show(pixel)} against {show(literal)}")


def overlay_part(mcp):
    print("\n2 — B2: overlay, 192 over 64 (never 128 over 128)")
    # 128/255 = 0.50196 sits ON the branch condition: it takes the screen
    # half and gives 128.498, which rounds either way depending on where the
    # comparison is written. And a 128 source over a 64 base gives 64 —
    # arithmetically right, but 64 is also what an unblended backdrop reads,
    # so the check could not fail. 192 over 64 gives 96, which neither card
    # can produce on its own.
    base, source = 64, 192
    s, clip = stack(mcp, "phase6-overlay", grey(base), grey(source))
    s.op("set_video", clips=[clip], patch={"blend": "overlay"})
    pixel = s.image().centre()
    formula = blended("overlay", (source,) * 3 + (255,), (base,) * 3 + (255,))
    check(near(pixel, formula),
          f"overlay: the frame matches the formula — {show(pixel)} against {show(formula)}")
    check(near(pixel, (96, 96, 96, 255)),
          f"overlay: …and the literal 96 — {show(pixel)}")
    check(pixel[0] not in (base, source),
          f"…and 96 is neither the base ({base}) nor the source ({source}), so an "
          "unblended backdrop could not have produced it")


def chain_part(mcp):
    print("\n3 — B3: the eight as a chain, and `normal` back to the baseline")
    # A colour whose three channels disagree, so that no two modes coincide:
    # with a flat grey, `normal` equals `lighten` (or `darken`) by
    # arithmetic and the sweep can only ever show seven pictures.
    base, source = (64, 224, 96), (192, 32, 160)
    s = Session(mcp, "phase6-chain")
    s.card(s.tracks()[0], rgb(*base))
    front = s.add_track()
    clip = s.card(front, rgb(*source))
    baseline = s.frame()
    check(s.image().centre() == source + (255,),
          f"the front card reads {show(source + (255,))} with the key never set")
    # The identity, which is why this is a chain and not a sweep.
    refusal = s.error("set_video", clips=[clip], patch={"blend": "normal"})
    check(refusal is not None and "made no change" in refusal,
          "`{blend: \"normal\"}` on a never-blended clip is the IDENTITY and answers "
          f"\"made no change\" — got {refusal!r}")
    digests = {"normal": baseline}
    for mode in ["multiply", "screen", "add", "overlay", "darken", "lighten", "difference"]:
        s.op("set_video", clips=[clip], patch={"blend": mode})
        digests[mode] = s.frame()
        check(digests[mode] != baseline, f"{mode} renders a frame the baseline does not")
    check(len(set(digests.values())) == 8,
          f"the eight modes render eight DISTINCT frames (got {len(set(digests.values()))})")
    s.op("set_video", clips=[clip], patch={"blend": "normal"})
    check(s.frame() == baseline,
          "back to `normal` from `difference` is BYTE-identical to the frame taken "
          "before the key was ever set")


def shadow_part(mcp):
    print("\n4 — B4: a blended layer's shadow is not blended")
    # The layer is 200 x 200 so its shadow falls on canvas the layer does
    # NOT cover, and what moves when the blend is switched on is then a fact
    # about the shadow rather than about the layer.
    #
    # What this measures is the shadow's own DRAW staying fixed-function
    # source-over on `shadowPipeline`. It is NOT a check on `maskState`, and
    # the phase's own mutation run is why that is written here rather than
    # the mechanism this comment used to state: a build passing the layer's
    # blend variant (`state`) into `encodeShadow` renders every shadow
    # correctly and survived every check in this script. The silhouette pass
    # draws COVERAGE into a texture cleared to transparent black, and a
    # blend over THAT reduces to the source exactly — the premultiplied
    # formula's `(1 - ab)·src` term carries it through at `ab` = 0, for all
    # eight modes. `maskState` is defensive: it says what the mask pass
    # means, and a future formula without that term would make the hazard
    # real. Nothing below can tell it from `state`, and nothing below says
    # it can.
    s, clip = stack(mcp, "phase6-shadow", grey(192), grey(128), size=(200, 200))
    s.op("set_video", clips=[clip], patch={
        "shadow": {"color": [0, 0, 0, 1], "opacity": 0.8, "blur": 10,
                   "angle": 315, "distance": 30}})
    plain = s.image()
    s.op("set_video", clips=[clip], patch={"blend": "multiply"})
    multiplied = s.image()
    moved = multiplied.changed(plain)
    check(bool(moved), "the blend changes the frame at all")
    # The 200 x 200 layer, centred on a 640 x 360 canvas. The emptiness is
    # FOLDED INTO each check rather than guarding them with `if moved:`,
    # which is how this was written: an empty diff made the two strongest
    # claims in the section vanish from the transcript instead of going red,
    # so the mutant that empties it scored (n - 3)/(n - 2) and the run came
    # back a shorter proof rather than a failing one. `phase6_chrome.py`'s
    # `extent()` forbids exactly that by name — a check that quietly
    # disappears when its diff comes back empty is a check that cannot fail,
    # and a denominator that moves with the result makes two runs
    # incomparable, which is the currency the mutation table is priced in.
    wanted = (220, 80, 419, 279)
    check(bool(moved) and box(moved) == wanted,
          f"every changed pixel is inside the layer's own 200 x 200 box {wanted} "
          f"— got {box(moved) if moved else 'an EMPTY diff: the blend changed nothing'}")
    check(len(moved) == 200 * 200,
          f"…and it is ALL of that box, so the shadow around it did not move "
          f"({len(moved)} of {200 * 200})")
    # Two named pixels, so a failure says which half went wrong.
    check(plain.pixel(440, 300) == multiplied.pixel(440, 300),
          "a pixel in the shadow, outside the layer, is byte-identical "
          f"({show(plain.pixel(440, 300))})")
    check(plain.centre() != multiplied.centre(),
          f"…while the layer's own centre pixel differs "
          f"({show(plain.centre())} → {show(multiplied.centre())})")


def transition_part(mcp):
    print("\n5 — B5: a transition forces `normal`, and the core decides it")
    s = Session(mcp, "phase6-transition")
    s.card(s.tracks()[0], grey(192), duration=5 * SEC)
    front = s.add_track()
    outgoing = s.card(front, grey(128), at=0, duration=2 * SEC)
    incoming = s.card(front, grey(64), at=int(1.5 * SEC), duration=2 * SEC)
    stored = s.clip(incoming)
    check(stored["transition_in"] is not None,
          f"the overlap gave the incoming clip a transition ({stored['transition_in']})")
    # Every frame of the overlap, at the 30 fps grid.
    inside = [int(1.5 * SEC) + k * 20_000 for k in range(15)]
    outside = int(2.5 * SEC)
    before = [s.frame(t) for t in inside]
    after_plain = s.frame(outside)
    for clip, role in ((incoming, "incoming"), (outgoing, "outgoing")):
        s.op("set_video", clips=[clip], patch={"blend": "multiply"})
        check([s.frame(t) for t in inside] == before,
              f"with `multiply` on the {role} half, every one of the {len(inside)} frames "
              "of the overlap is BYTE-identical to the same project at `normal`")
        check(s.clip(clip)["video"]["blend"] == "multiply",
              f"…while the MODEL still says `multiply` for the {role} clip: the recipe's "
              "blend is what draws and the inspector reads the model's, so the two "
              "legitimately differ during an overlap")
        s.op("set_video", clips=[clip], patch={"blend": "normal"})
    # And the non-vacuity: OUTSIDE the overlap the same blend does bite, so
    # the fifteen identities above are not "blend does nothing".
    s.op("set_video", clips=[incoming], patch={"blend": "multiply"})
    check(s.frame(outside) != after_plain,
          "past the end of the overlap the same `multiply` DOES change the frame, so "
          "the frames inside it are the rule and not an inert blend")


def opacity_part(mcp):
    print("\n6 — B6: partial opacity is the MIX, and what it cannot see")
    # This section measures one thing: at 50 % opacity the frame is
    # `mix(dst, blend(src, dst), 0.5)`, the contract's formula at a partial
    # source alpha over an opaque destination.
    #
    # It was written to be the check that catches the spike's trap — a
    # programmable-blend pipeline built with fixed-function blending still
    # ENABLED, which Metal does with no error and no warning — and it CANNOT
    # be. The fragment stage returns the FINISHED composite, whose alpha is
    # `as + ab·(1 - as)`; over the opaque card this fixture puts underneath,
    # that is 1 whatever the source's own alpha is, so `oneMinusSourceAlpha`
    # is 0 and the second blend adds exactly nothing at 0.5 as at 1. The
    # three "…and NOT doubled" assertions that used to stand here excluded a
    # value no build produces, on any mode, at any opacity: they scored
    # three lines a run and could not fail, which is worse than a missing
    # check because the transcript said the guard was there. The mutation
    # run measured it — the mutant survived this section untouched — and
    # they are gone rather than reworded. What decides it is the
    # DESTINATION's alpha: section 6b builds that fixture and reads the
    # alpha channel, and it is the only check in this script that fails when
    # `blending: false` is wrong.
    base, source = 64, 192
    s, clip = stack(mcp, "phase6-opacity", grey(base), grey(source))
    s.op("set_video", clips=[clip], patch={"opacity": 0.5})
    for mode in ["normal", "multiply", "difference"]:
        if mode != "normal":
            s.op("set_video", clips=[clip], patch={"blend": mode})
        pixel = s.image().centre()
        wanted = blended(mode, (source,) * 3 + (255,), (base,) * 3 + (255,), opacity=0.5)
        check(near(pixel, wanted),
              f"{mode} at 50 % opacity is mix(dst, blend(src, dst), 0.5) "
              f"— {show(pixel)} against {show(wanted)}")


def translucent_part(mcp):
    print("\n6b — the destination that ACTUALLY catches the double blend")
    # Section 6 above was written to be this check and CANNOT be, and the
    # reason is already spelled out in `blended`'s own docstring two hundred
    # lines up: the composite's alpha is `as + ab·(1 - as)`, which over an
    # OPAQUE destination is 1 whatever the source's own alpha is. The shader
    # returns the finished pixel, so a fixed-function stage left switched on
    # behind it multiplies the destination by `1 - a_out` — and `1 - 1` is 0.
    # Every fixture in this script above this line puts a full-canvas opaque
    # card underneath, so all of them are blind to it: a mutant built with
    # the `blending: false` guard removed passed every one of them, section 6
    # — written for this job — included. (The score it passed at is not
    # quoted here on purpose. A mutant's verdict is "survived" or "fails
    # these checks by name"; a fraction goes stale the next time this script
    # grows a line, and two of them already had.)
    #
    # What the second blend needs to show is a destination whose alpha is
    # BELOW one AND a source that does not cover it: `a_out` is then under 1,
    # `1 - a_out` is not 0, and `dst · (1 - a_out)` lands on top of a pixel
    # that was already finished. The visible half of that is small; the ALPHA
    # is not, which is what this section reads.
    #
    # Measured on a correct build and on the mutant, with a transparent canvas
    # (so nothing opaque is under the card), a 0.5-grey card at alpha 0.5, and
    # a 0.75-grey card at opacity 0.5 blended over it:
    #
    #     correct   (139, 139, 139, 191)      a_out = 0.5 + 0.5·0.5 = 0.75
    #     doubled   (137, 137, 137, 223)      a_out + ab·(1 - a_out) = 0.875
    #
    # so the colour moves by two and the alpha by thirty-two. The alpha is the
    # discriminator and the colour is not — which is why this reads a channel
    # the rest of the script never looks at.
    s = Session(mcp, "phase6-translucent")
    # The one place in this script that does NOT want an opaque canvas.
    s.op("set_canvas", width=CANVAS[0], height=CANVAS[1], background=[0.0, 0.0, 0.0, 0.0])
    s.card(s.tracks()[0], [0.5, 0.5, 0.5, 0.5])

    # Read BEFORE the front card exists: this is the destination, and its
    # alpha is the whole precondition.
    backdrop = s.image().centre()
    check(backdrop[3] == 128,
          "the backdrop alone is TRANSLUCENT — the precondition the sections "
          f"above all lack ({show(backdrop)})")

    front = s.card(s.add_track(), [0.75, 0.75, 0.75, 1.0])
    s.op("set_video", clips=[front], patch={"opacity": 0.5, "blend": "multiply"})
    pixel = s.image().centre()
    # `as` is the front card's own alpha times its opacity; `ab` the backdrop's.
    source_alpha, dest_alpha = 0.5, backdrop[3] / 255.0
    wanted = int(round(255 * (source_alpha + dest_alpha * (1 - source_alpha))))
    doubled_alpha = source_alpha + dest_alpha * (1 - source_alpha)
    doubled = int(round(255 * (doubled_alpha + dest_alpha * (1 - doubled_alpha))))
    # Within one, and deliberately: with `as` = 0.5 the expectation is
    # `127.5 + ab·255/2`, which lands exactly ON a rounding boundary for an
    # even backdrop byte — the hazard this script's own docstring warns about
    # for the colour channels. It costs nothing here, because the value this
    # check exists to exclude is thirty-two away and not one.
    check(abs(pixel[3] - wanted) <= 1,
          f"a blended layer over it composites to alpha `as + ab·(1 - as)` = {wanted} "
          f"— got {pixel[3]}")
    check(pixel[3] != doubled,
          f"…and NOT {doubled}, which is the alpha the SAME frame reads with "
          "fixed-function blending left enabled on the blend pipeline — the one "
          "check in this script that fails when that line is wrong")


def nest_part(mcp):
    print("\n7 — B7: the nest refusals, through all three doors")
    s = Session(mcp, "phase6-nest")
    s.card(s.tracks()[0], grey(64))
    front = s.add_track()
    clip = s.card(front, grey(192))
    s.op_with("nest", {"clips": [clip]})
    nest = [c for c in s.project()["clips"] if c["source"]["kind"] == "nest"][0]["id"]
    plain = s.image().centre()
    check(plain == (192, 192, 192, 255),
          f"the nest clip draws its content unblended ({show(plain)})")

    refusal = s.error("set_video", clips=[nest], patch={"blend": "multiply"})
    check(refusal is not None and f"clip {nest} shows a nest" in refusal
          and "blend" in refusal,
          f"`set_video {{blend: \"multiply\"}}` on a nest clip is refused BY NAME "
          f"— got {refusal!r}")
    identity = s.error("set_video", clips=[nest], patch={"blend": "normal"})
    check(identity is not None and "made no change" in identity,
          "…while `{blend: \"normal\"}` on one is the identity and answers \"made no "
          f"change\", so `paste_attributes` of an ordinary look still works — got {identity!r}")
    misspelt = s.error("set_video", clips=[nest], patch={"blend": "muliply"})
    check(misspelt is not None and "blend" in misspelt,
          f"a misspelt mode is refused naming the key — got {misspelt!r}")

    # The `set_action_end` back door. An end patch validates nothing but "is
    # it an object", so the mode IS stored — and `clamp_video` forces
    # `BlendMode::Normal` for a nest clip, which closes the recipe,
    # `clip_state` and both export writers at once.
    s.op("add_action", clip=nest, at=0, duration=SEC)
    action = s.clip(nest)["actions"][0]["id"]
    s.op("set_action_end", clip=nest, action=action, patch={"video": {"blend": "multiply"}})
    check(s.clip(nest)["actions"][0]["end"] == {"video": {"blend": "multiply"}},
          "an action's end patch on a nest clip STORES the mode (an end patch validates "
          "nothing but its shape)")
    # And it never DRAWS — read that for exactly what it is, which is a
    # FLOOR and not the clamp's proof. A nest clip contributes no layer of
    # its own: `recipe.rs::frame_recipe` maps over the flattened INNER
    # instances, whose `blend` is their own, and the only thing that folds
    # down from the enclosing nest clip is `Frame::enter`'s
    # x/y/scale/rotation/opacity/crop. So this frame is identical whatever
    # `clamp_video` does, and a comparison with no path to the value cannot
    # be the check that catches its deletion. The clamp is proved where the
    # value is readable — `core/tests/evaluate_tests.rs`'s
    # `a_nest_clip_evaluates_to_normal_however_the_blend_got_there`, over
    # `clip_state` — and there is no MCP surface for the evaluated props at
    # all: `get_project` answers the MODEL and no tool mirrors
    # `rc_project_clip_state`. What is left here is worth its line all the
    # same, because it is the user-visible half: a mode stored through the
    # back door reaches the picture by NEITHER road.
    check(s.image(SEC).centre() == plain,
          "…and the frame at the action's END is byte-identical to the unblended one, "
          f"so the stored mode never draws ({show(s.image(SEC).centre())}) — by both "
          "roads at once, which is why the clamp itself is a CORE test and not this "
          "comparison")

    # `check_blend` is called from BOTH the patch path and the PASTE path, so
    # the second door is walked here too — and it is the whole reason the
    # refusal fires on a non-normal MERGED value rather than on any mention:
    # `paste_attributes` replaces the video group WHOLE, so refusing every
    # paste that carried a `blend` key would fail an all-or-nothing paste of
    # an ordinary look onto a nest clip, for a value that changes nothing.
    paste = Session(mcp, "phase6-nest-paste")
    donor = paste.card(paste.tracks()[0], grey(192))
    paste.op("set_video", clips=[donor], patch={"opacity": 0.5})
    receiver = paste.card(paste.add_track(), grey(64), size=(320, 180))
    paste.op_with("nest", {"clips": [receiver]})
    nested = [c for c in paste.project()["clips"] if c["source"]["kind"] == "nest"][0]["id"]

    def payload_of(clip):
        # The Copy payload's shape (`edit_paste.rs`): the clip verbatim, its
        # `track` a DEPTH from the front.
        stored = paste.clip(clip)
        return {"clips": [dict(stored, track=0)], "media": []}

    paste.op("paste_attributes", clips=[nested], payload=payload_of(donor))
    check(paste.clip(nested)["video"]["opacity"] == 0.5,
          "an ordinary look — one whose `blend` is `normal` — pastes onto a nest clip "
          "and lands")
    paste.op("set_video", clips=[donor], patch={"blend": "multiply", "opacity": 0.25})
    refused = paste.error("paste_attributes", clips=[nested], payload=payload_of(donor))
    check(refused is not None and f"clip {nested} shows a nest" in refused,
          f"…while one carrying a non-normal blend is refused BY NAME — got {refused!r}")
    check(paste.clip(nested)["video"]["opacity"] == 0.5,
          "…and all-or-nothing: the refused paste's OPACITY did not land either "
          f"({paste.clip(nested)['video']['opacity']})")

    # The other side of the same rule, and a documented LIMIT rather than a
    # defect: a blend set BEFORE the clip is nested is carried inside and
    # blends against the whole canvas below the nest, because a nest is
    # flattened rather than composited offscreen.
    inner = Session(mcp, "phase6-nest-inner")
    inner.card(inner.tracks()[0], grey(64))
    top = inner.add_track()
    target = inner.card(top, grey(192))
    inner.op("set_video", clips=[target], patch={"blend": "multiply"})
    before = inner.image().centre()
    inner.op_with("nest", {"clips": [target]})
    check(inner.image().centre() == before,
          "a blend set on a clip BEFORE it is nested keeps drawing inside the nest, "
          f"against the canvas below it ({show(before)}) — the recorded limit, not a bug")


def media_part(mcp):
    print("\n8 — the same arithmetic over a DECODED picture")
    card = os.path.join(WORK, f"phase6-card-{os.getpid()}.mov")
    subprocess.run(CARD_LINE + [card], check=True)
    # The card's OWN byte first, measured — nothing below assumes 128.
    alone = Session(mcp, "phase6-media-alone")
    media = alone.op("import_media", path=card)["media"]
    alone.op("add_clip", track=alone.tracks()[0], media=media, at=0)
    picture = alone.image()
    value = picture.centre()
    check(len(picture.sampled()) == 1,
          f"the decoded card is ONE flat colour ({len(picture.sampled())} sampled values)")
    check(value[3] == 255, f"…and it is opaque ({show(value)})")

    base = 64
    s = Session(mcp, "phase6-media")
    s.card(s.tracks()[0], grey(base))
    front = s.add_track()
    med = s.op("import_media", path=card)["media"]
    clip = s.op("add_clip", track=front, media=med, at=0)["new_clips"][0]
    check(s.image().centre() == value,
          f"over the backdrop, unblended, it still reads {show(value)}")
    for mode in ["multiply", "screen", "difference"]:
        s.op("set_video", clips=[clip], patch={"blend": mode})
        pixel = s.image().centre()
        wanted = blended(mode, value, (base,) * 3 + (255,))
        check(near(pixel, wanted),
              f"{mode} of the decoded card over {base} — {show(pixel)} against "
              f"{show(wanted)}, the formula over the card's MEASURED byte")


# ---- 6b, gradients -------------------------------------------------------


A_STOP, B_STOP = 32, 224


def gradient(kind="linear", angle=0.0, stops=None):
    return {"kind": kind, "angle": angle, "stops": stops or []}


def stop(at, value, components=4):
    colour = grey(value) if components == 4 else grey(value)[:3]
    return {"at": at, "color": colour}


def flat_part(mcp):
    print("\n9 — G1: a one-colour gradient IS the flat fill")
    s = Session(mcp, "phase6-flat")
    clip = s.card(s.tracks()[0], grey(64))
    flat = s.frame()
    for kind, angle in [("linear", 0.0), ("linear", 45.0), ("linear", 137.0),
                        ("radial", 0.0)]:
        s.op("set_shape", clips=[clip], patch={
            "gradient": gradient(kind, angle, [stop(0, 64), stop(1, 64)])})
        check(s.frame() == flat,
              f"a {kind} gradient at {angle:g}° between two identical 64/255 stops is "
              "BYTE-identical to the flat fill — the clip-to-the-path decision's "
              "cleanest consequence")
    # And the trap that makes the rule above worth stating: `CGGradient`
    # DITHERS, so a colour 8 bits cannot hold does NOT come back byte-exact.
    # Asserted as a bound in both directions, so it holds whether or not a
    # later macOS keeps dithering — what must never happen is a difference
    # bigger than one step.
    fraction = [0.25, 0.5, 0.75, 1.0]
    s.op("set_shape", clips=[clip], patch={"gradient": None, "fill": fraction})
    rough = s.image()
    s.op("set_shape", clips=[clip], patch={
        "gradient": gradient("linear", 0.0, [
            {"at": 0, "color": fraction}, {"at": 1, "color": fraction}])})
    dithered = s.image()
    worst = 0
    for x in range(0, 640, 7):
        for y in range(0, 360, 7):
            worst = max(worst, max(abs(a - b) for a, b in
                                   zip(rough.pixel(x, y), dithered.pixel(x, y))))
    check(worst <= 1,
          f"a gradient of a colour 8 bits CANNOT hold (0.25 → 63.75) stays within "
          f"1/255 of the flat fill (worst {worst}) — `CGGradient` dithers, which is "
          "why every fill in this fixture is k/255")


def linear_part(mcp):
    print("\n10 — G2: a linear ramp's geometry")
    # The stops are at 0.25 and 0.75, so `drawsBeforeStartLocation` and
    # `drawsAfterEndLocation` leave a FLAT band of the stop colour over the
    # outer quarter at each end. A plateau is exact where a ramp is not: a
    # `CGGradient` is sampled through an interpolation table of its own and
    # dithered, so its own ends read within a couple of steps and the columns
    # between wobble by up to 3/255.
    s = Session(mcp, "phase6-linear")
    clip = s.card(s.tracks()[0], grey(64))
    s.op("set_shape", clips=[clip], patch={
        "gradient": gradient("linear", 0.0, [stop(0.25, A_STOP), stop(0.75, B_STOP)])})
    picture = s.image()
    row = picture.row(180)
    check(all(v == A_STOP for v in row[:159]),
          f"the whole band left of the first stop is exactly {A_STOP}/255 "
          f"(saw {sorted(set(row[:159]))[:4]})")
    check(all(v == B_STOP for v in row[481:]),
          f"the whole band right of the last stop is exactly {B_STOP}/255 "
          f"(saw {sorted(set(row[481:]))[:4]})")
    check(row[159] == A_STOP and row[168] > A_STOP,
          f"the 0.25 stop lands a QUARTER of the way across the 640-pixel box: "
          f"x = 159 still reads {row[159]} and x = 168 reads {row[168]}")
    middle = (A_STOP + B_STOP) // 2
    check(abs(row[320] - middle) <= 1,
          f"the centre of the box is the mean of the two stops, {middle} "
          f"— got {row[320]}")
    # Monotone over a 16-column stride: the dither can flip two neighbours,
    # never sixteen.
    ramp = range(176, 464)
    climbs = [row[x + 16] > row[x] for x in ramp]
    check(all(climbs),
          f"the ramp rises across every 16-column step between the stops "
          f"({sum(climbs)} of {len(climbs)})")
    # And it runs ACROSS, not down: the same x reads the same value at every
    # y, within the dither's one step.
    spread = max(abs(picture.pixel(x, 20)[0] - picture.pixel(x, 340)[0])
                 for x in range(0, 640, 7))
    check(spread <= 1,
          f"at 0° the value depends on x alone — the top and bottom of a column "
          f"differ by at most {spread}")

    s.op("set_shape", clips=[clip], patch={
        "gradient": gradient("linear", 45.0, [stop(0.25, A_STOP), stop(0.75, B_STOP)])})
    turned = s.image()
    corners = {
        "bottom-left": turned.pixel(0, 359), "top-right": turned.pixel(639, 0),
        "top-left": turned.pixel(0, 0), "bottom-right": turned.pixel(639, 359),
    }
    check(corners["bottom-left"] == (A_STOP,) * 3 + (255,),
          f"at 45° the FIRST stop lands on the bottom-left corner "
          f"({show(corners['bottom-left'])}) — angle 0 is to the right and grows "
          "counter-clockwise on screen, the crate's one convention")
    check(corners["top-right"] == (B_STOP,) * 3 + (255,),
          f"…and the last on the top-right ({show(corners['top-right'])})")
    check(A_STOP < corners["top-left"][0] < B_STOP
          and A_STOP < corners["bottom-right"][0] < B_STOP,
          "…while the other two corners sit inside the ramp "
          f"({corners['top-left'][0]}, {corners['bottom-right'][0]}), so the ramp runs "
          "corner to corner and not edge to edge")

    # The STROKE-INSET box — the one gradient decision nothing in either
    # script exercised until the review. Every gradient fixture here comes
    # from `Session.card`, which writes `stroke: null`, so `renderShape`'s
    # `rect` is the whole texture and the inset it performs is the identity:
    # a mutant handing `paint` `CGRect(origin: .zero, size: size)` instead of
    # that rect changes not one pixel while every fixture is unstroked, and
    # the contract's "span the stroke-inset `rect`, not the full texture"
    # had no evidence behind it at all.
    #
    # A 40-wide stroke insets the box by HALF its width on each side
    # (`insetBy(dx: strokeWidth / 2)`, which is what keeps the stroke inside
    # the box rather than growing the texture), leaving a 600-wide rect from
    # x = 20 to x = 620. The stops are 0.1 and 0.12 — a STEP, not a ramp,
    # because a step's POSITION reads to the pixel where a shallow ramp's
    # value is worth ±3: it lands at 20 + 0.1 × 600 = 80, where the full
    # texture would put it at 0.1 × 640 = 64. The stroke itself covers
    # x < 40 and x ≥ 600, so both numbers fall on visible fill.
    #
    # The mutant's own picture is drawable by this build as it stands, which
    # is how these were falsified rather than argued: with NO stroke the
    # inset IS the identity, so an unstroked card carrying this same
    # gradient is exactly what a full-texture box would draw for the stroked
    # one. Measured — it puts the step at x = 64 and reads 137 at x = 70,
    # which is both checks below red.
    stroked = Session(mcp, "phase6-linear-stroked")
    edge = stroked.card(stroked.tracks()[0], grey(64))
    stroked.op("set_shape", clips=[edge], patch={
        "stroke": {"width": 40, "color": grey(255)},
        "gradient": gradient("linear", 0.0, [stop(0.10, A_STOP), stop(0.12, B_STOP)])})
    inset = stroked.image()
    check(inset.pixel(10, 180) == (255, 255, 255, 255),
          f"the 40-wide stroke is really on the card ({show(inset.pixel(10, 180))}), so "
          "the inset below is a fact about this fixture and not an assumption")
    check(inset.pixel(70, 180) == (A_STOP,) * 3 + (255,),
          f"x = 70 is still the first stop's FLAT band ({show(inset.pixel(70, 180))}) — "
          "over the full texture the step would have passed at 64 and this pixel would "
          "be most of the way up it")
    band = inset.row(180)
    step = next((x for x in range(45, 600) if band[x] != A_STOP), None)
    check(step is not None and 77 <= step <= 83,
          f"the step lands at x = {step}: 20 + 0.1 × 600, the STROKE-INSET box's own "
          "tenth, and not the 64 the whole 640-wide texture would give")
    # The other half of the same call site, recorded rather than dressed up
    # as a check of it. `paint` guards `box.width > 0 && box.height > 0`
    # because a stroke as wide as the box makes `insetBy` hand back a rect
    # with no area — reachable from the wire, since `props_check.rs` bounds
    # `shape.stroke.width` at 0 and nowhere else. Deleting that guard changes
    # nothing visible, and this does not pretend otherwise: the path built
    # from the same rect is degenerate too, so the clip is empty and the
    # flat-fill fallback paints the same nothing. What is worth a scored
    # line is that the renderer answers the case with a FRAME rather than a
    # crash or a refusal, which is the only part of it a proof can see.
    stroked.op("set_shape", clips=[edge], patch={
        "stroke": {"width": CANVAS[1], "color": grey(255)}})
    check(stroked.error("render_frame", t=SEC) is None,
          f"a stroke as wide as the box ({CANVAS[1]}) leaves `insetBy` a rect with no "
          "area, and the frame still renders — the guard behind that is defensive, and "
          "an empty clip and an empty fill draw the same nothing")


def radial_part(mcp):
    print("\n11 — G3: a radial ramp is the box's inscribed ellipse")
    s = Session(mcp, "phase6-radial")
    clip = s.card(s.tracks()[0], grey(64))
    s.op("set_shape", clips=[clip], patch={
        "gradient": gradient("radial", 0.0, [stop(0.0, A_STOP), stop(0.75, B_STOP)])})
    picture = s.image()
    centre = picture.centre()
    check(near(centre, (A_STOP,) * 3 + (255,), tolerance=2),
          f"the first stop is at the CENTRE ({show(centre)} against {A_STOP}) — "
          "within two steps, since a CGGradient is sampled at pixel centres through "
          "a table of its own")
    edges = {
        "left": picture.pixel(0, 180), "right": picture.pixel(639, 180),
        "top": picture.pixel(320, 0), "bottom": picture.pixel(320, 359),
    }
    for where, pixel in sorted(edges.items()):
        check(pixel == (B_STOP,) * 3 + (255,),
              f"the {where} edge MIDPOINT reads the last stop exactly "
              f"({show(pixel)}) — one inscribed ELLIPSE, so a 640 x 360 box reaches "
              "its ramp's end on all four sides and not only two")
    check(picture.pixel(0, 0) == (B_STOP,) * 3 + (255,),
          "…and a corner, outside the ellipse, takes the last stop's colour too "
          f"({show(picture.pixel(0, 0))})")

    # The MID-RAMP probes, which are what tell an inscribed ellipse from an
    # inscribed CIRCLE. The six checks above cannot, and the message they
    # carry ("all four sides and not only two") is true of a circle of
    # radius min(w, h)/2 = 180 as well: it too reads the first stop at the
    # centre and the last at all four edge midpoints and the corner, because
    # every one of those points is past the 0.75 stop under either geometry.
    # Half way out is where they part. Under the ellipse (480, 180) and
    # (320, 270) are BOTH at normalized radius 0.5 — 160 px of a 320
    # half-width, 90 px of a 180 half-height — and read the same value part
    # way up the ramp; under a circle the horizontal one sits at 160/180 =
    # 0.89, past the last stop, and reads B_STOP while the vertical one
    # still reads the middle. That is the phase's headline shape decision —
    # "a circle in a 1600 × 200 banner would leave most of the box
    # ungraded" — and until these two lines nothing in either script could
    # fail for it.
    #
    # The circle cannot be drawn by this build, but its READING can be taken
    # off this very frame, which is how these two were falsified: the
    # pipeline maps a normalized radius to a colour the same way whichever
    # geometry produced the radius, so the colour a circle would put at
    # (480, 180) is the colour the ellipse puts at the pixel whose own
    # normalized radius is that circle's — 0.889, at x = 604. Measured: 224,
    # the last stop, against the 160 below. Both checks go red on it.
    across, down = picture.pixel(480, 180), picture.pixel(320, 270)
    check(near(across, down, tolerance=2),
          f"half way to the RIGHT edge and half way to the BOTTOM read the same value "
          f"({show(across)} against {show(down)}) — one inscribed ELLIPSE, where a "
          "circle would have the first of them past its last stop")
    check(A_STOP + 8 < across[0] < B_STOP - 8,
          f"…and that value is inside the ramp, neither stop ({across[0]}, between "
          f"{A_STOP} and {B_STOP}) — which is the half of it a circle cannot give")


def gradient_rules_part(mcp):
    print("\n12 — G4: what a gradient refuses, and what it takes")
    s = Session(mcp, "phase6-rules")
    clip = s.card(s.tracks()[0], grey(64))
    plain = s.frame()

    one = s.error("set_shape", clips=[clip],
                  patch={"gradient": gradient(stops=[stop(0, A_STOP)])})
    check(one is not None and "at least 2 stops" in one and "not 1" in one,
          f"a ONE-stop gradient is refused by name — got {one!r}")
    nine = s.error("set_shape", clips=[clip], patch={
        "gradient": gradient(stops=[stop(i / 8.0, A_STOP) for i in range(9)])})
    check(nine is not None and "at most 8 stops" in nine and "not 9" in nine,
          f"a NINTH stop is NAMED, not trimmed — got {nine!r}")
    outside = s.error("set_shape", clips=[clip], patch={
        "gradient": gradient(stops=[stop(0, A_STOP), stop(1.5, B_STOP)])})
    check(outside is not None and "shape.gradient.stops[].at" in outside,
          f"an `at` outside 0–1 is refused by its dotted key — got {outside!r}")
    conic = s.error("set_shape", clips=[clip], patch={
        "gradient": gradient("conic", stops=[stop(0, A_STOP), stop(1, B_STOP)])})
    check(conic is not None and "gradient.kind" in conic and "conic" in conic,
          f"a geometry outside the closed enum is refused rather than decoded "
          f"leniently into `linear` — got {conic!r}")
    # The win worth pinning: because `shapePatchArg` is HAND-BUILT, a key
    # misspelt INSIDE `gradient` is refused BY NAME. `shadow` (since M3),
    # `chroma`, an `obscure` region and `animation` all go through the
    # generic decoder, which drops the unknown key in silence and sends every
    # key the caller omitted as its default.
    typo = s.error("set_shape", clips=[clip],
                   patch={"gradient": {"kind": "linear", "stpos": []}})
    check(typo is not None and "stpos" in typo,
          f"a key misspelt inside `gradient` is refused BY NAME — got {typo!r}")
    stop_typo = s.error("set_shape", clips=[clip], patch={
        "gradient": {"stops": [{"at": 0, "colour": grey(A_STOP)},
                               {"at": 1, "color": grey(B_STOP)}]}})
    check(stop_typo is not None and "stops[0]" in stop_typo and "colour" in stop_typo,
          f"…and one misspelt inside a STOP is refused by its index — got {stop_typo!r}")
    check(s.frame() == plain and s.clip(clip)["shape"]["gradient"] is None,
          "…and after six refusals the clip still has no gradient and renders the "
          "frame it started with")

    # `{"gradient": {}}` is the type's own Default, whichever door it came
    # through: black to white, linear, angle 0. That is the feature's first
    # impression (the inspector's Add sends exactly this).
    s.op("set_shape", clips=[clip], patch={"gradient": {}})
    stored = s.clip(clip)["shape"]["gradient"]
    check(stored == {"kind": "linear", "angle": 0,
                     "stops": [{"at": 0, "color": [0, 0, 0, 1]},
                               {"at": 1, "color": [1, 1, 1, 1]}]},
          f"`{{\"gradient\": {{}}}}` is Gradient::default() in full — got "
          f"{json.dumps(stored, sort_keys=True)}")
    default = s.image()
    check(default.pixel(0, 180) == (0, 0, 0, 255)
          and default.pixel(639, 180) == (255, 255, 255, 255),
          "…and it draws black on the left, white on the right "
          f"({show(default.pixel(0, 180))} → {show(default.pixel(639, 180))})")

    # Sorted and unsorted are the same picture. Pinned deliberately: the core
    # does NOT police the order — a refusal there would stop a stop-drag
    # working half way through — and the RENDERER sorts, so a later reader
    # who "fixes" the missing check into a refusal breaks this line.
    s.op("set_shape", clips=[clip], patch={
        "gradient": gradient("linear", 0.0, [stop(0.25, A_STOP), stop(0.75, B_STOP)])})
    ordered = s.frame()
    s.op("set_shape", clips=[clip], patch={
        "gradient": gradient("linear", 0.0, [stop(0.75, B_STOP), stop(0.25, A_STOP)])})
    check(s.frame() == ordered,
          "an UNSORTED stop list is accepted and renders the SORTED ramp, byte for "
          "byte — the core leaves the order alone on purpose and the renderer sorts")

    # A three-component stop colour, which `withOpaqueColors` could not have
    # reached: it recurses into nested dictionaries but not into arrays of
    # them, so this only works because the reader is hand-built.
    s.op("set_shape", clips=[clip], patch={
        "gradient": {"kind": "linear", "angle": 0,
                     "stops": [stop(0.25, A_STOP, components=3),
                               stop(0.75, B_STOP, components=3)]}})
    check(s.frame() == ordered,
          "a THREE-component stop colour is accepted and means the four-component "
          "one, byte for byte")
    identity = s.error("set_shape", clips=[clip], patch={
        "gradient": gradient("linear", 0.0, [stop(0.25, A_STOP), stop(0.75, B_STOP)])})
    check(identity is not None and "made no change" in identity,
          "…and re-sending it WITH the alpha is the identity, which is the same claim "
          f"read off the model rather than off the frame — got {identity!r}")

    # `{gradient: null}` is an exact inverse, because setting one never
    # cleared `fill`.
    s.op("set_shape", clips=[clip], patch={"gradient": None})
    check(s.frame() == plain,
          "`{\"gradient\": null}` restores the flat fill BYTE-identically — setting a "
          "gradient never cleared it")

    # A line has no area and ignores a gradient entirely: stored,
    # range-checked, not drawn. `shape.radius` is the exact precedent.
    line = Session(mcp, "phase6-line")
    pen = line.card(line.tracks()[0], grey(64))
    line.op("set_shape", clips=[pen], patch={
        "kind": "line", "stroke": {"width": 8, "color": [1, 1, 1, 1]}, "fill": None})
    bare = line.frame()
    line.op("set_shape", clips=[pen], patch={
        "gradient": gradient("linear", 0.0, [stop(0, A_STOP), stop(1, B_STOP)])})
    check(line.frame() == bare,
          "a gradient on a `line` changes NOTHING — it has no area to fill")
    check(line.clip(pen)["shape"]["gradient"] is not None,
          "…and it is STORED all the same, so flipping the kind to a rectangle and "
          "back does not lose it")


def cache_part(mcp):
    print("\n13 — G5: the shape texture cache covers the gradient")
    # Phase 4's text lesson, applied to a shape. It has to be ONE frame: a
    # `render_frame` builds its own compositor and therefore its own texture
    # cache, so two renders would prove nothing about a stale key. Two clips
    # whose shape descriptions are identical BUT for the gradient, side by
    # side — if the key did not cover it, the second would be handed the
    # first's texture.
    s = Session(mcp, "phase6-cache")
    left = s.card(s.tracks()[0], grey(128), size=(200, 200))
    right = s.card(s.add_track(), grey(128), size=(200, 200))
    s.op("set_video", clips=[left], patch={"x": -160})
    s.op("set_video", clips=[right], patch={"x": 160})
    s.op("set_shape", clips=[left], patch={
        "gradient": gradient("linear", 0.0, [stop(0, A_STOP), stop(1, A_STOP)])})
    s.op("set_shape", clips=[right], patch={
        "gradient": gradient("linear", 0.0, [stop(0, B_STOP), stop(1, B_STOP)])})
    picture = s.image()
    check(picture.pixel(160, 180) == (A_STOP,) * 3 + (255,),
          f"the left card draws its own gradient ({show(picture.pixel(160, 180))})")
    check(picture.pixel(480, 180) == (B_STOP,) * 3 + (255,),
          f"…and the right card, whose description differs ONLY in its gradient, draws "
          f"a DIFFERENT texture in the same frame ({show(picture.pixel(480, 180))}) — "
          "which is what a cache key narrower than the recipe's hash would fail")


# ---- 6c, the two background commands -------------------------------------


def blurred_part(mcp):
    print("\n14 — C1: Add Blurred Background against the same ops by hand")

    def foreground(name):
        """A TRIMMED clip — the window is the point: re-placing the media
        with `add_clip` would give the whole file and the backdrop would
        show different frames from the clip in front of it."""
        s = Session(mcp, name)
        media = s.op("import_media", path=os.path.join(MEDIA, "AV.mov"))["media"]
        clip = s.op("add_clip", track=s.tracks()[0], media=media, at=0)["new_clips"][0]
        s.op("trim_start", clip=clip, to=1 * SEC)
        s.op("trim_end", clip=clip, to=3 * SEC)
        s.op("move_clip", clips=[clip], delta=-1 * SEC)
        # Shrunk, so the backdrop is visible around it and a frame comparison
        # is about the backdrop rather than about the clip on top of it.
        s.op("set_video", clips=[clip], patch={"scale": 0.5})
        return s, clip, media

    op_side, front, _ = foreground("phase6-blurred")
    before = op_side.frame(SEC // 2)
    op_side.op("add_blurred_background", clip=front)
    made = op_side.frame(SEC // 2)
    check(made != before, "the command changes the frame at all")

    hand, front_b, media_b = foreground("phase6-blurred-hand")
    hand.op("add_track", index=0)
    back = hand.tracks()[0]
    copy = hand.op("add_clip", track=back, media=media_b, at=0)["new_clips"][0]
    hand.op("trim_start", clip=copy, to=1 * SEC)
    hand.op("trim_end", clip=copy, to=3 * SEC)
    hand.op("move_clip", clips=[copy], delta=-1 * SEC)
    hand.op("set_video", clips=[copy], patch={
        "scale": 1.0, "x": 0, "y": 0, "crop": {"l": 0, "t": 0, "r": 0, "b": 0},
        "filters": [{"kind": "blur", "amount": 1.0}]})
    hand.op("set_enabled", clip=copy, audio=False)
    hand.op("set_clip", clips=[copy], patch={"name": "Blurred Background"})
    check(hand.frame(SEC // 2) == made,
          "one op renders BYTE-identically to the eight it composes, applied by hand")

    made_copy = op_side.named("Blurred Background")
    hand_copy = hand.clip(copy)
    check(made_copy is not None, "the copy is named \"Blurred Background\"")
    for key in ["start", "duration", "speed", "enabled", "source", "actions",
                "transition_in", "label", "video", "audio"]:
        check(made_copy.get(key) == hand_copy.get(key),
              f"…and its `{key}` is the hand-built one's "
              f"({json.dumps(made_copy.get(key))[:70]})")
    check(made_copy["enabled"]["audio"] is False,
          "`enabled.audio` on the copy is FALSE — the claim no still frame can make "
          "(section 16 exports it)")
    check(made_copy["source"]["in"] == op_side.clip(front)["source"]["in"],
          "the copy's source WINDOW is the foreground's, so the two play the same "
          f"frames ({made_copy['source']['in']} ticks in)")
    check(made_copy["actions"] == [] and made_copy["transition_in"] is None,
          "…and it carries no actions and no transition")
    check(op_side.tracks()[0] == made_copy["track"],
          "the copy is on a NEW back-most track")
    op_side.op("undo")
    check(op_side.frame(SEC // 2) == before and len(op_side.project()["tracks"]) == 1,
          "…and the whole thing is ONE undo step")

    text = op_side.error("add_blurred_background", clip=9999)
    check(text is not None and "9999" in text,
          f"an unknown clip is refused by id — got {text!r}")
    caption = op_side.op("add_text_clip", track=op_side.tracks()[0],
                         at=4 * SEC, duration=SEC)["new_clips"][0]
    refusal = op_side.error("add_blurred_background", clip=caption)
    check(refusal is not None and "no pixel size" in refusal,
          f"a source with no pixel size is refused by name — got {refusal!r}")


def background_part(mcp):
    print("\n15 — C2: Add Background ▸ Solid Color")
    s = Session(mcp, "phase6-background")
    s.card(s.tracks()[0], grey(128), size=(200, 200), duration=int(2.5 * SEC))
    length = max(c["start"] + c["duration"] for c in s.project()["clips"])
    s.op("add_background")
    project = s.project()
    check(len(project["tracks"]) == 2, "a NEW track was inserted")
    plate = s.named("Background")
    check(plate is not None, "…carrying one clip named \"Background\"")
    check(plate["track"] == s.tracks()[0], "…and it is the BACK-most track")
    check(plate["start"] == 0 and plate["duration"] == length,
          f"the plate runs the timeline's own length, from 0 ({plate['duration']} ticks "
          f"against {length})")
    shape = plate["shape"]
    check(shape is not None and shape["kind"] == "rectangle"
          and (shape["width"], shape["height"]) == CANVAS,
          f"…as a canvas-sized rectangle ({shape['width']} x {shape['height']})")
    check(shape["stroke"] is None and shape["fill"] == [1, 1, 1, 1],
          f"…with no stroke and a WHITE fill ({json.dumps(shape['fill'])}) — the canvas "
          "is already black, so a black plate is a command that appears to do nothing")
    check(plate["video"]["scale"] == 1, "…at scale 1")
    picture = s.image()
    check(picture.pixel(0, 0) == (255, 255, 255, 255),
          f"and the frame's corner is white where the canvas showed through "
          f"({show(picture.pixel(0, 0))})")
    check(picture.centre() == (128, 128, 128, 255),
          f"…while the clip in front of it is untouched ({show(picture.centre())})")
    s.op("undo")
    check(len(s.project()["tracks"]) == 1, "the plate and its track go in ONE undo step")

    media = s.op("import_media", path=os.path.join(MEDIA, "A.mov"))["media"]
    both = s.error("add_background", media=media, color=[1, 0, 0, 1])
    check(both is not None and "not both" in both,
          f"`media` and `color` together is an Err — got {both!r}")
    short = s.error("add_background", duration=1)
    check(short is not None and "at least one frame" in short,
          f"a duration under a frame is refused by name — got {short!r}")


def audio_part(mcp):
    print("\n16 — C3: the blurred backdrop does not double the audio")
    # The check no frame can make, and the one the road map's own wording
    # would have missed: "byte-identical to the same ops applied by hand"
    # passes with the bug present on BOTH sides.
    def build(name, backdrop):
        s = Session(mcp, name)
        media = s.op("import_media", path=os.path.join(MEDIA, "AV.mov"))["media"]
        clip = s.op("add_clip", track=s.tracks()[0], media=media, at=0)["new_clips"][0]
        s.op("trim_end", clip=clip, to=2 * SEC)
        if backdrop:
            s.op("add_blurred_background", clip=clip)
        return s, clip

    plain, _ = build("phase6-audio-plain", False)
    over, _ = build("phase6-audio-over", True)
    without = pcm(plain.export_wav("plain"))
    withal = pcm(over.export_wav("over"))
    check(len(without) == len(withal) and len(without) > 0,
          f"the two exports hold the same number of samples ({len(without) // 4})")
    check(without == withal,
          "a timeline WITH the blurred backdrop exports audio SAMPLE-FOR-SAMPLE equal "
          "to the same timeline without it")
    # And what that identity is worth: switch the copy's audio back on and it
    # is the bug, measured.
    #
    # Assert the switch is OFF before flipping it, and tolerate the identity
    # when it is not. Under a build that leaves `enabled.audio` true on the
    # copy, `set_enabled` is then an identity edit and the core answers
    # "made no change" — which the client raises. That ABORTED the script
    # instead of failing a named claim, so the mutant was detected as a
    # traceback and everything below this line went unrun. A proof that
    # crashes on the bug it is looking for reports less than one that scores.
    copy = over.named("Blurred Background")["id"]
    check(over.clip(copy)["enabled"]["audio"] is False,
          "the blurred copy's `enabled.audio` is OFF, which is what the identity above rests on")
    try:
        over.op("set_enabled", clip=copy, audio=True)
    except ToolError:
        pass  # already on: the mutant, reported by the check above, not by a crash
    doubled = pcm(over.export_wav("doubled"))
    check(doubled != withal,
          "…and with the copy's audio switched back ON the file DIFFERS, so the "
          "identity above is a claim and not a tautology")
    check(peak(doubled) > peak(withal) * 1.9,
          f"…by about 6 dB: the peak goes {peak(withal)} → {peak(doubled)}, which is "
          "the same recording played twice")


# ---- 6d, filters inside an action ---------------------------------------


def actions_part(mcp):
    print("\n17 — D: the 6d oracle, and the partial entry")

    def clip_of(name):
        s = Session(mcp, name)
        media = s.op("import_media", path=os.path.join(MEDIA, "A.mov"))["media"]
        return s, s.op("add_clip", track=s.tracks()[0], media=media, at=0)["new_clips"][0]

    animated, clip = clip_of("phase6-action")
    animated.op("set_video", clips=[clip], patch={"filters": [{"kind": "blur", "amount": 0.0}]})
    animated.op("add_action", clip=clip, at=0, duration=SEC)
    action = animated.clip(clip)["actions"][0]
    check(action["curve"] == "linear",
          f"the action's curve is linear, so its midpoint is half way ({action['curve']})")
    animated.op("set_action_end", clip=clip, action=action["id"],
                patch={"video": {"filters": [{"kind": "blur", "amount": 1.0}]}})

    # Every comparison below is against a static project at the SAME t.
    # `media/A.mov` is `testsrc`, whose picture moves, so two frames of one
    # project a moment apart differ for a reason that has nothing to do with
    # a filter — an oracle written across two times would be measuring the
    # test card's clock.
    static, other = clip_of("phase6-action-static")
    static.op("set_video", clips=[other], patch={"filters": [{"kind": "blur", "amount": 0.5}]})
    half = static.frame(SEC // 2)
    check(animated.frame(SEC // 2) == half,
          "an action `blur 0 → blur 1` rendered at its MIDPOINT is BYTE-identical to a "
          "static `blur 0.5` — the road map's own oracle for the list rule")
    static.op("set_video", clips=[other], patch={"filters": [{"kind": "blur", "amount": 0.0}]})
    zero = static.frame(SEC // 2)
    check(zero != half,
          "…and `blur 0` at the same instant is a different frame, so the oracle is "
          "not two blanks")

    # The list rule's other half, which is what `structural` exists to
    # protect: an end patch of a DIFFERENT length cannot interpolate and
    # switches at the end instead.
    animated.op("set_action_end", clip=clip, action=action["id"], patch={
        "video": {"filters": [{"kind": "blur", "amount": 1.0},
                              {"kind": "sepia", "amount": 1.0}]}})
    check(animated.frame(SEC // 2) == zero,
          "an end patch whose list is LONGER than the base cannot interpolate, so the "
          "midpoint still holds the START state — byte for byte the static `blur 0`")
    static.op("set_video", clips=[other], patch={
        "filters": [{"kind": "blur", "amount": 1.0}, {"kind": "sepia", "amount": 1.0}]})
    check(animated.frame(SEC) == static.frame(SEC),
          "…and it SWITCHES at the end, to exactly the two-filter stack the patch names")

    # The refusal that makes the natural agent spelling loud rather than
    # wrong. `{"filters": [{"amount": 1}]}` is the core's documented idiom for
    # "the same filter, more of it"; over MCP the decoder COMPLETES the
    # missing `kind` from the defaults, so a sepia base would animate and
    # then switch to a blur with the caller told it worked.
    partial = animated.error("set_video", clips=[clip],
                             patch={"filters": [{"amount": 1.0}]})
    check(partial is not None and "patch.filters[0]" in partial
          and "kind and amount" in partial,
          f"a filter entry missing `kind` is refused BY INDEX — got {partial!r}")
    partial_end = animated.error(
        "set_action_end", clip=clip, action=action["id"],
        patch={"video": {"filters": [{"amount": 1.0}]}})
    check(partial_end is not None and "patch.video.filters[0]" in partial_end,
          f"…and so is one inside an action's END patch, where the idiom is most "
          f"tempting — got {partial_end!r}")
    unknown = animated.error("set_video", clips=[clip],
                             patch={"filters": [{"kind": "glow", "amount": 1.0}]})
    check(unknown is not None and "patch.filters[0].kind" in unknown,
          f"a filter kind outside the closed set is refused by index too — got "
          f"{unknown!r}")
    end_blend = animated.error(
        "set_action_end", clip=clip, action=action["id"],
        patch={"video": {"blend": "muliply"}})
    check(end_blend is not None and "patch.video.blend" in end_blend,
          f"and a misspelt blend inside an end patch is refused by its dotted key "
          f"— got {end_blend!r}")


# ---- the catalog and the file --------------------------------------------


def catalog_part(mcp):
    print("\n18 — the catalog, and what this build writes")
    names = mcp.tools()
    check(len(names) >= TOOLS,
          f"the catalog holds phase 6's {TOOLS} tools or more (got {len(names)}) — the "
          "newest phase owns the EXACT count, and phase 9's set_scope is what turned this "
          "one into a floor")
    for tool in ["add_background", "add_blurred_background"]:
        check(tool in names, f"`{tool}` is a tool")

    s = Session(mcp, "phase6-schema")
    clip = s.card(s.tracks()[0], grey(128))
    s.op("set_shape", clips=[clip], patch={
        "gradient": gradient("radial", 30.0, [stop(0, A_STOP), stop(1, B_STOP)])})
    s.op("set_video", clips=[clip], patch={"blend": "screen"})
    text = s.save()
    check(re.search(r'"version"\s*:\s*(\d+)', text).group(1) == str(VERSION),
          f"the saved project.json is version {VERSION}")
    # Read off the WRITTEN TEXT, because a parsed value sorts its keys and
    # the claim is about ORDER: an appended key lands at the END and never in
    # the middle, which is the whole of what the append-only rule rests on.
    video = re.search(r'"video": \{.*?\n      \}', text, re.S)
    check(video is not None and re.findall(r'"(\w+)":', video.group(0))[-1] == "motion",
          "`motion` is the LAST key of the video object, after `blend`")
    shape = re.search(r'"shape": \{.*?\n        "gradient"', text, re.S)
    check(shape is not None,
          "`gradient` is the LAST key of the shape object, after `to`")
    reopened = json.loads(text)
    stored = reopened["clips"][0]["shape"]["gradient"]
    check(stored["kind"] == "radial" and stored["angle"] == 30.0
          and len(stored["stops"]) == 2,
          f"…and it round-trips through the file ({json.dumps(stored)[:90]})")


def main():
    if not shutil.which("ffmpeg"):
        print("ffmpeg is needed: section 8 writes one card with it and section 16 "
              "decodes two exports.")
        return 2
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)
    print(f"phase 6 — Looks, against 127.0.0.1:{PORT}")
    fixture_part(mcp)
    if failures:
        print("\nThe FIXTURE failed. Every number below it is a byte in a PNG, so "
              "nothing else in this script would mean anything; fix the pipeline "
              "first.")
        print(f"\n{checks - len(failures)}/{checks} checks passed")
        return 1
    modes_part(mcp)
    overlay_part(mcp)
    chain_part(mcp)
    shadow_part(mcp)
    transition_part(mcp)
    opacity_part(mcp)
    translucent_part(mcp)
    nest_part(mcp)
    media_part(mcp)
    flat_part(mcp)
    linear_part(mcp)
    radial_part(mcp)
    gradient_rules_part(mcp)
    cache_part(mcp)
    blurred_part(mcp)
    background_part(mcp)
    audio_part(mcp)
    actions_part(mcp)
    catalog_part(mcp)

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
