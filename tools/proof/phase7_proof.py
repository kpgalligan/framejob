"""Road map 2, phase 7 — Output, driven against the built binary over MCP.

Phase 7 is four things a script over the wire can reach — the frame writer
behind File ▸ Save Frame…, the ProRes 4444 row and its alpha, the timecode
burn-in, and the two arguments the export tool grew — and two things it
cannot: the remembered export settings and the export queue, which have no
MCP surface at all and are `phase7_chrome.py`'s probes. Adding a tool so
that a proof could exist would be the proof deciding the product's API
(`tools/proof/README.md` settled that for phase 5's meter, and phase 7
inherits it).

**Section 1 is the most breakable thing in the phase and it runs first.**
Five earlier scripts (phases 1, 2, 3, 4 and 6) read a rendered frame's path
out of `render_frame`'s answer with

    r"Written to (\\S+\\.png)\\."

and every PNG comparison this project makes hangs off that one expression.
Phase 7 rewrote that handler — the write moved into `FrameWriter`, the
sentence grew a burn-in clause and a flatten note, and the tool learned two
new arguments — so the FIRST claim here is that a path-less, format-less
call still writes a PNG and still ends its sentence exactly as it did. The
regex below is that expression spelled verbatim rather than adapted: a
proof of a contract that quietly relaxes the contract is not a proof.

**Section 2 measures `render_frame`'s two SPELLINGS, and the limit is worth
naming because the section's old title over-claimed it.** A path-less call
and a `path` + `format` one write byte-identical PNGs at one instant, plain
and burnt, and the plain pair differs from the burnt pair so the identity is
not two identical calls agreeing about nothing — a build whose path/format
branch changed the picture would fail it. What is NOT measured, here or in
`phase7_chrome.py`, is that File ▸ Save Frame… writes the same bytes:
`renderAndWriteFrame` is private, a save panel cannot be driven over MCP or
offscreen, and no proof in this tree can press a menu item. That identity is
STRUCTURAL — one `FrameWriter.writeFrame`, reached by both callers — which is
exactly why phase 7a put the write in a value type with no AppKit in it, and
a construction is the only thing that can carry it.

**Two instruments are new in this file and section 0 scores them before
anything leans on them.** Neither existed in `tools/proof/` before phase 7,
because until the ProRes 4444 row and the burn-in there was no claim to make
about a written MOVIE's pixels — phases 2, 3, 5 and 6 decode exports to PCM
and phases 1 to 6 read PNGs, and neither reaches a video frame in a file. So
this script carries

* an **`ffprobe -select_streams v`** reader, for the codec, the profile and
  the pixel format of a written file; and
* an **`ffmpeg -i <file> -vframes 1 -f rawvideo -pix_fmt rgba`** decoder,
  which is the only way a claim about an exported frame's ALPHA can be made
  at all.

Section 0 runs both over files ffmpeg itself writes to this script's order —
an opaque ProRes 4444 and a fully transparent one, 32 × 32 — so that "the
decoder can see an alpha of 0" and "…and it can also see one of 255" are
scored facts about the instrument rather than assumptions inside a product
claim. A decoder that always answered 255 would make every alpha check in
section 3 pass against a build with no alpha at all; one that always
answered 0 would make them all pass against a build that wrote nothing.

**What the alpha claims are made ON, and why.** `alpha` in the resolved
export settings is a per-row CAPABILITY — true for `prores_4444`,
`hevc_alpha` and `apng` and false for the other seven — and it has **no MCP
surface**: the core
emits it (`export.rs`), `ExportSettings` decodes it, the sheet's summary
prints it, and the `export` tool's result does not echo it. So what this
script measures is not the flag but the capability where it bites, in the
FILE: a `prores_4444` of a transparent canvas carries a real alpha plane, its
`prores_422` sibling in the SAME container does not (which is the core's own
argument for `alpha` being a `Preset` field rather than a `Container`
question, measured rather than repeated), an `h264` of the same timeline
composites onto black, an `apng` holds a PARTIAL alpha and a `gif` does not.
The flag's own value per row is `core/tests/export.rs`'s.

Four traps in section 3, each measured on this machine:

* **`pix_fmt` is asked `startswith("yuva")`, never compared for equality.**
  A file WRITTEN `yuva444p10le` is REPORTED `yuva444p12le`: the decoder's
  output format is not the encoder's input format. An equality against
  either spelling is a check that fails on a correct build the day
  ffmpeg's ProRes decoder picks a different depth. The test cannot see the
  third alpha row at all: an HEVC-with-alpha file reports `yuv420p`, as a
  plain HEVC file does, so that row's alpha is read off the decoded frame
  by `hevc_alpha_proof.py` (spec §11 G-33 (f)).
* **A `gif` reports `pix_fmt=bgra`**, which reads as "carries alpha" and is
  not what the row's capability means. GIF is palettised: ONE index is
  nominated transparent, a pixel is either that index or fully opaque, and
  there is no partial value to store. So the APNG/GIF claim is made on the
  decoded PIXELS of a 50 %-opacity card — the APNG holds 128, the GIF holds
  only 0 and 255 — and never on the format name.
* **Alpha is read at the DOCUMENT'S OWN SHAPE, and this build refuses any
  other.** Exported at a size whose aspect differs from the document's,
  `AVVideoScalingModeResizeAspect` pads, and the padding path does not merely
  lose the alpha channel — it INVERTS the answer. Measured through the file
  on a build predating the guard: at 640 × 480 out of a 640 × 360 document
  the colour is centred with 60-row bars while the alpha map sits 60 rows
  higher, so the opaque region and the drawn card do not overlap at all.
  `Exporter.Failure.alphaAspectMismatch` refuses that combination by name
  now, and section 3 scores the refusal, scores that the SAME size is
  accepted for `h264` (so it is the alpha row's rule and not a size rule),
  and scores that a same-shape resize — 720p out of 640 × 360 — keeps the
  alpha it started with.
* **Pixels are compared only where alpha == 255.** ProRes 4444 carries the
  compositor's PREMULTIPLIED values through unchanged and ffmpeg reports
  them as straight (a red card at 50 % opacity decodes `(129, 0, 0, 129)`),
  while ImageIO un-premultiplies on the way into an APNG or a PNG (the same
  card decodes `(255, 0, 0, 128)`). Both readings describe one picture, and
  the two disagree at every translucent or antialiased pixel — so a
  cross-export comparison is legitimate only where alpha is 255, where
  premultiplied and straight are the same number.

**The fixture is SHAPE CARDS, and never a ProRes source.** `decode_png`
raises UNCAUGHT on anything but an 8-bit PNG, and a ProRes clip on the
timeline makes `render_frame` write a SIXTEEN-bit one — which would take the
whole run down with a traceback instead of a failing check. Phase 6 learned
that; this is the phase where a ProRes file is lying around to be tempted
by.

**The burn-in is measured against the core's own two constants** —
`BURN_IN_Y_FRACTION` 0.44 and `BURN_IN_SIZE_FRACTION` 0.03
(`core/src/recipe_text.rs`) — and at TWO canvas heights, which is the whole
point of the pair: a build that placed the layer at a fixed pixel offset
passes at 640 × 360 and fails at 640 × 720. The claim is not "the changed
pixels lie in their own bounding box", which is a tautology, but "every
changed pixel lies inside a rectangle PREDICTED from those constants, and
every pixel outside it is byte-identical".

**And section 5 measures the limb a build could get wrong while every movie
export looked right.** GIF and APNG never go through `ExportWriter`:
`ImageSequenceWriter` calls `Exporter.renderFrame` per frame, which registers
its own recipe key, so plumbing the option only through the export's key
leaves every GIF and APNG silently un-burnt. The APNG comparison is the
pixel-exact one — that writer does no lossy coding, so a burnt APNG differs
from a plain one in EXACTLY the pixels a burnt `render_frame` differs from a
plain one in, byte for byte — and the H.264 pair is the same claim through a
lossy encoder, where only the band can be asserted.

**The catalog stays at 73.** Phase 7 adds no op and no tool: it adds
arguments to two tools that already existed. The exact count is asserted
here because phase 7 is the newest phase and the exact count is what tells a
stale binary on the port from the build under test — phase 6's assertion
reads the same number and needs no edit, which is the first time that
handover has cost nothing.

**Media.** Nothing is added to `media/` and nothing is read from it. Every
fixture is drawn from shape cards; section 0's two instrument files are
written into `work/` per run. `ffmpeg` and `ffprobe` are both needed at
proof time.
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

from mcp import MCP, ToolError, target

SOCKET = target(sys.argv)
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")

SEC = 600_000
CANVAS = (640, 360)

# The whole catalog after phase 7 — unchanged from phase 6's. Phase 7 adds
# no op and no tool: `render_frame` and `export` each grew arguments, which
# the startup parity check cannot see and section 5 reads off `tools/list`
# instead. The EXACT count belongs to the newest phase's script (README), and
# phase 9's `set_scope` took it: this is a floor now, as phase 6's and phase
# 8's are, so a later phase's tools cannot fail an older proof.
TOOLS = 73

# `AgentServer+Render.swift`'s sentence, read the way five earlier scripts
# read it. Spelled verbatim from `phase1_proof.py` and its four siblings
# rather than adapted: this is the contract, not a convenience.
FRAME_SENTENCE = re.compile(r"Written to (\S+\.png)\.")

# Anything this script writes that is NOT a PNG comes back through the same
# sentence with a different extension on it.
ANY_WRITTEN = re.compile(r"Written to (\S+)\.$")

# `core/src/recipe_text.rs`. The burn-in's box centre sits this fraction of
# the canvas height BELOW the canvas centre, and its font is this fraction of
# the canvas height, rounded. Both are fractions rather than pixels, which is
# what section 4 measures at two canvas sizes.
BURN_IN_Y_FRACTION = 0.44
BURN_IN_SIZE_FRACTION = 0.03

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


def section(name, run, *args):
    """One section, isolated. A section that raises scores ONE failure and
    the run goes on.

    This is not tidiness. A proof is only worth what its mutation run says,
    and a mutant that makes one section throw — a sentence that no longer
    matches `FRAME_SENTENCE`, an export the writer refuses — would otherwise
    abort the process and leave every later section UNRUN, which reads as a
    weaker detection than it is (phase 4's catalog mutation is the worked
    example: sixteen failures and an abort, and the abort hid nothing only
    because somebody counted it by hand). A crash is a worse detection than
    a failure."""
    global checks
    print(f"\n{name}")
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — the point is to keep scoring
        checks += 1
        what = f"section {name.split(' ')[0]} ran to the end (raised {error!r})"
        print(f"  FAIL {what}")
        failures.append(what)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def show(pixel):
    return "none" if pixel is None else "(" + ", ".join(str(v) for v in pixel) + ")"


# ---- PNG, in pure Python -------------------------------------------------
#
# The decoder phases 2, 3 and 6 carry, copied rather than imported for their
# reason: those files are SCRIPTS, importing one would run its main, and a
# proof that measures its own evidence should carry the decoder it trusts.
#
# The 8-bit guard is why this script's fixture is shape cards: `render_frame`
# writes a PNG at the depth the frame needs, and a ProRes clip on the
# timeline makes a SIXTEEN-bit one — measured — which would raise here rather
# than fail a check.


def decode_png(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"{path} is not a PNG")
    pos, idat, header, chunks = 8, [], None, []
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        chunks.append(kind.decode("ascii", "replace"))
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
    return width, height, depth, channels, rows, chunks


class Frame:
    """One rendered PNG, decoded. Positions are pixel indices."""

    def __init__(self, path):
        self.path = path
        (self.width, self.height, self.depth, self.channels, self.rows,
         self.chunks) = decode_png(path)

    def pixel(self, x, y):
        return tuple(self.rows[y][x * self.channels:(x + 1) * self.channels])

    def centre(self):
        return self.pixel(self.width // 2, self.height // 2)

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


# ---- the two new instruments ---------------------------------------------
#
# Scored in section 0 before anything rests on them, phase 6's section-0
# lesson applied to a tool rather than to a fixture: an instrument that
# cannot see what a check asks it about turns every check that uses it into a
# check that cannot fail.


def probe_video(path):
    """The first video stream's codec, profile and pixel format.

    `-select_streams v` and not `v:0`: an audio-only file then answers with
    NO stream rather than with an error, which is a fact a caller may want to
    assert. The answer is a dict of strings, or None where the file holds no
    video at all."""
    answer = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
         "stream=codec_name,profile,pix_fmt,width,height", "-of", "json", path],
        capture_output=True, text=True, check=True).stdout
    streams = json.loads(answer).get("streams", [])
    return streams[0] if streams else None


class Raster:
    """One frame of a written file, decoded to straight 8-bit RGBA.

    `-vframes 1` is the FIRST frame, which is the frame every claim here is
    about: a burn-in reads the time it is drawn at, and comparing two files'
    first frames compares one instant. The size comes off the file itself
    rather than from the caller, because an export at an image row's cap is
    not the document's size (a GIF of a 640 × 360 timeline is 480 × 270) and
    an off-by-one width silently reads the picture diagonally."""

    def __init__(self, path):
        stream = probe_video(path)
        if stream is None:
            raise RuntimeError(f"{path} holds no video stream to decode")
        self.path = path
        self.width, self.height = int(stream["width"]), int(stream["height"])
        self.data = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path, "-vframes", "1", "-f", "rawvideo",
             "-pix_fmt", "rgba", "-"],
            capture_output=True, check=True).stdout
        wanted = self.width * self.height * 4
        if len(self.data) != wanted:
            raise RuntimeError(
                f"{path}: decoded {len(self.data)} bytes, wanted {wanted} — the "
                "rawvideo decoder did not answer one whole frame")

    def pixel(self, x, y):
        i = (y * self.width + x) * 4
        return tuple(self.data[i:i + 4])

    def centre(self):
        return self.pixel(self.width // 2, self.height // 2)

    def alphas(self):
        """Every distinct alpha in the frame — the GIF/APNG claim's whole
        instrument, since "carries an alpha CHANNEL" is the question of
        whether a value between 0 and 255 can exist at all."""
        return set(self.data[3::4])

    def opaque_count(self):
        return sum(1 for a in self.data[3::4] if a == 255)

    def changed(self, other):
        """Every (x, y) whose RGBA differs from `other`'s, both frames being
        the same size."""
        if (self.width, self.height) != (other.width, other.height):
            raise RuntimeError("two rasters of different sizes cannot be compared")
        out = []
        a, b = self.data, other.data
        for i in range(0, len(a), 4):
            if a[i:i + 4] != b[i:i + 4]:
                pixel = i // 4
                out.append((pixel % self.width, pixel // self.width))
        return out


# ---- the project under test ----------------------------------------------


class Session:
    """One project, the shape phases 2 to 6 use.

    `<name>-<pid>.framejob`, never a fixed name: a `project` path is matched
    against every open document and no tool closes one, so two earlier runs'
    SAVED packages would have the app answering for an old one (measured in
    phase 2). Older runs' under this name go."""

    def __init__(self, mcp, name, canvas=CANVAS, background=(0, 0, 0, 255), **canvas_args):
        self.mcp = mcp
        self.name = name
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.framejob", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.canvas = canvas
        self.op("set_canvas", width=canvas[0], height=canvas[1],
                background=[c / 255.0 for c in background], **canvas_args)

    def op(self, name, **kwargs):
        if name == "export":  # an id since #326; the helper follows it to the file
            return self.mcp.export(project=self.path, **kwargs)
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def card(self, fill, size=None, at=0, duration=5 * SEC, track=None, opacity=None):
        """A flat rectangle with no stroke — the fixture's one drawing, and
        the reason there is no media anywhere in this script: a shape card is
        exact by construction, needs no decoder and loads nothing
        asynchronously, so a byte that is wrong belongs to the compositor and
        not to a codec."""
        clip = self.op(
            "add_shape_clip", track=track if track is not None else self.tracks()[0],
            at=at, duration=duration,
            shape={
                "kind": "rectangle", "width": (size or self.canvas)[0],
                "height": (size or self.canvas)[1], "stroke": None, "fill": fill,
            })["new_clips"][0]
        if opacity is not None:
            self.op("set_video", clips=[clip], patch={"opacity": opacity})
        return clip

    # -- frames

    def answer(self, t=SEC, **kwargs):
        """`render_frame`'s whole sentence, unparsed."""
        return str(self.op("render_frame", t=int(t), **kwargs))

    def png(self, t=SEC, **kwargs):
        """The path of the PNG `render_frame` wrote, read out of its answer
        with the expression five earlier scripts use."""
        answer = self.answer(t, **kwargs)
        found = FRAME_SENTENCE.search(answer)
        if not found:
            raise RuntimeError(f"render_frame said something else: {answer}")
        return found.group(1)

    def written(self, t=SEC, **kwargs):
        """The path of whatever `render_frame` wrote, whatever its
        extension — the general form of `png`, for the two lossy rows."""
        answer = self.answer(t, **kwargs).strip()
        found = ANY_WRITTEN.search(answer)
        if not found:
            raise RuntimeError(f"render_frame named no file: {answer}")
        return found.group(1)

    def image(self, t=SEC, **kwargs):
        return Frame(self.png(t, **kwargs))

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    # -- files

    def export(self, preset, tag, extension, **kwargs):
        """An export into `work/` with the pid on it: half the claims here
        are comparisons between two files, and a second run must never find
        the first run's. Answers the tool's whole result."""
        target = os.path.join(WORK, f"{self.name}-{tag}-{os.getpid()}.{extension}")
        if os.path.exists(target):
            os.remove(target)
        return self.op("export", preset=preset, path=target, **kwargs)

    def raster(self, preset, tag, extension, **kwargs):
        """That export's first frame, decoded."""
        return Raster(self.export(preset, tag, extension, **kwargs)["path"])


# ---- section 0: the instruments ------------------------------------------


def instruments_part(mcp):
    # ffmpeg writes these, not Frame Job. The point is to score what the
    # reader and the decoder can SEE before either is pointed at a file the
    # app wrote — an alpha-blind decoder would make every claim in section 3
    # pass against a build with no alpha in it at all.
    opaque = os.path.join(WORK, f"phase7-instrument-opaque-{os.getpid()}.mov")
    clear = os.path.join(WORK, f"phase7-instrument-clear-{os.getpid()}.mov")
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
         "-i", "color=c=red:size=32x32:rate=25:duration=1,format=rgba",
         "-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le", opaque],
        check=True)
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
         "-i", "color=c=black@0.0:size=32x32:rate=25:duration=1,format=rgba",
         "-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le", clear],
        check=True)

    stream = probe_video(opaque)
    check(stream is not None and stream.get("codec_name") == "prores",
          f"the ffprobe reader answers codec_name for a video stream — {stream}")
    check(stream is not None and "4444" in str(stream.get("profile")),
          f"…and the profile, which is what tells the two ProRes rows apart "
          f"({stream.get('profile') if stream else None})")
    # The pixel format is asked STARTSWITH, here and everywhere below: this
    # file was WRITTEN yuva444p10le and is REPORTED yuva444p12le, because the
    # decoder's output format is not the encoder's input format.
    check(stream is not None and str(stream.get("pix_fmt")).startswith("yuva"),
          f"…and a pixel format that starts \"yuva\" for a file written "
          f"yuva444p10le, which ffmpeg reports as {stream.get('pix_fmt') if stream else None} "
          "— which is why nothing here compares that string for equality")

    lit = Raster(opaque)
    check((lit.width, lit.height) == (32, 32) and len(lit.data) == 32 * 32 * 4,
          f"the rawvideo decoder answers one whole 32×32 RGBA frame "
          f"({lit.width}×{lit.height}, {len(lit.data)} bytes)")
    check(lit.pixel(16, 16)[3] == 255,
          f"…reading an OPAQUE pixel as alpha 255 — {show(lit.pixel(16, 16))}")
    dark = Raster(clear)
    check(dark.pixel(16, 16)[3] == 0,
          f"…and a fully transparent one as alpha 0 — {show(dark.pixel(16, 16))}. "
          "Both directions, because a decoder stuck at either value would make "
          "every alpha claim below pass against a build with no alpha in it")
    check(lit.alphas() == {255} and dark.alphas() == {0},
          f"…and the two files disagree about every pixel's alpha, so the reading is the "
          f"FILE's and not the decoder's own default ({sorted(lit.alphas())} against "
          f"{sorted(dark.alphas())})")


# ---- section 1: the sentence contract ------------------------------------


def sentence_part(mcp):
    s = Session(mcp, "phase7-sentence")
    s.card([1.0, 1.0, 1.0, 1.0])

    answer = s.answer(SEC)
    found = FRAME_SENTENCE.search(answer)
    check(found is not None,
          "a path-less, format-less render_frame still matches the expression phases 1, 2, "
          f"3, 4 and 6 read the path with — {answer!r}")
    if not found:
        # Nothing below this can be read; the rest of the run still can.
        return
    path = found.group(1)
    check(answer.strip().endswith(f"Written to {path}."),
          "…and that sentence is the LAST one in the block, so a clause added to the tool "
          "goes BEFORE it and not after")
    check(os.path.exists(path) and open(path, "rb").read(8) == b"\x89PNG\r\n\x1a\n",
          f"…naming a file that exists and is a PNG by its magic ({os.path.basename(path)})")
    picture = Frame(path)
    check(picture.depth == 8 and picture.channels == 4,
          f"…8-bit with four channels, which is what every byte comparison in "
          f"tools/proof assumes ({picture.depth}-bit, {picture.channels} channels)")
    check((picture.width, picture.height) == CANVAS,
          f"…at the canvas's own size ({picture.width}×{picture.height})")
    # The PNG's properties dictionary is nil and `FrameWriter` says it must
    # stay nil. **What this check guards is a NON-EMPTY dictionary**, and that
    # is measured rather than assumed: the phase mutated the writer to
    # `[kCGImagePropertyDPIWidth: 144]` and the chunk list grew a `pHYs`. It
    # cannot guard `[:]` — an empty dictionary and no dictionary write
    # byte-identical PNGs on macOS 26.5.1 (same sha256, same 5330 bytes, same
    # chunk list, across two processes), so no byte comparison in this project
    # could see the difference. `phase7_chrome.py`'s structural read of
    # `destinationProperties != nil` is the assertion that catches that one.
    # The colour chunk is spec §11 PR-11's BT.709 label (issue batch B102): an
    # `iCCP` profile, `kCGColorSpaceCoreMedia709`, where this frame carried an
    # `sRGB` chunk before it.
    check(picture.chunks == ["IHDR", "iCCP", "eXIf", "IDAT", "IEND"],
          f"…and its chunks are exactly what a NIL properties dictionary writes "
          f"(measured on macOS 26.5.1: {picture.chunks})")

    burnt = s.answer(SEC, burn_in_timecode=True)
    burnt_found = FRAME_SENTENCE.search(burnt)
    check(burnt_found is not None and burnt.strip().endswith(
        f"Written to {burnt_found.group(1)}."),
        "a BURNT frame's sentence still ends the same way — the burn-in clause is one of "
        f"the things that had to go before it — {burnt!r}")
    check("timecode burnt in" in burnt,
          "…and it says so, so a caller can tell the two apart without decoding the file")

    # The `.png` in that expression is the DEFAULT's, and the default is what
    # five scripts depend on: a caller that asks for another container gets
    # another extension, in the temporary directory too.
    jpeg = s.written(SEC, format="jpeg")
    check(jpeg.endswith(".jpg") and os.path.dirname(jpeg) != WORK,
          f"a path-less call that ASKS for jpeg writes a .jpg into the temporary directory, "
          f"so the .png the expression pins belongs to the default alone ({jpeg})")
    check(FRAME_SENTENCE.search(s.answer(SEC, format="jpeg")) is None,
          "…and such a call does NOT match the expression, which is what makes the first "
          "check above a claim about the default rather than about the regex")


# ---- section 2: render_frame's two spellings, and the containers ---------


def writer_part(mcp):
    s = Session(mcp, "phase7-writer")
    s.card([1.0, 1.0, 1.0, 1.0])

    # **What is measured here is `render_frame`'s TWO SPELLINGS** — path-less
    # into the temporary directory, and `path` + `format` — writing byte-identical
    # PNGs at one instant, plain and burnt. It would catch a build whose
    # path/format branch changed the picture (a stray `max_width`, a dropped
    # `RecipeOptions` on one arm), and it is worth its place for that.
    #
    # It is NOT a comparison of Save Frame's bytes with `render_frame`'s, and
    # nothing in either script is: `renderAndWriteFrame` is private, a save
    # panel cannot be driven over MCP or offscreen, and no proof can press a
    # menu item. That identity is STRUCTURAL — both callers reach the one
    # `FrameWriter.writeFrame`, which is the whole reason phase 7a put the write in
    # a value type with no AppKit in it (`FrameWriter.swift`'s own doc,
    # `AgentServer+Render.swift`, and road map 2's phase-7a paragraph all say
    # so). True by construction, and a construction is what has to carry it.
    loose = s.png(SEC)
    named = os.path.join(WORK, f"phase7-explicit-{os.getpid()}.png")
    aimed = s.png(SEC, path=named, format="png")
    check(digest(loose) == digest(aimed),
          f"a PNG asked for by path and format is BYTE-identical to the path-less one at the "
          f"same t ({digest(loose)} against {digest(aimed)})")
    burnt_loose = s.png(SEC, burn_in_timecode=True)
    burnt_named = s.png(SEC, path=os.path.join(WORK, f"phase7-explicit-burnt-{os.getpid()}.png"),
                        format="png", burn_in_timecode=True)
    check(digest(burnt_loose) == digest(burnt_named),
          "…and so is a BURNT one, so the option reaches both spellings of the call "
          f"({digest(burnt_loose)} against {digest(burnt_named)})")
    check(digest(loose) != digest(burnt_loose),
          "…while the burnt pair is not the plain pair, so that identity is not two "
          "identical calls agreeing about nothing")

    # `destinationURL` replaces a known extension rather than appending to
    # it — the doubled name the whole mechanism exists to prevent, and the
    # reason the five image containers joined `replaceableExtensions`.
    stem = os.path.join(WORK, f"phase7-shot-{os.getpid()}")
    for stale in (f"{stem}.jpg", f"{stem}.png", f"{stem}.jpg.png"):
        if os.path.exists(stale):
            os.remove(stale)
    wrote = s.written(SEC, path=f"{stem}.jpg", format="png")
    check(wrote == f"{stem}.png",
          f"{{path: \"shot.jpg\", format: \"png\"}} writes shot.png — the extension is "
          f"REPLACED ({os.path.basename(wrote)})")
    check(not os.path.exists(f"{stem}.jpg.png") and not os.path.exists(f"{stem}.jpg"),
          "…and neither shot.jpg.png nor shot.jpg exists, so nothing was written twice or "
          "under the caller's own spelling")
    unknown = s.written(SEC, path=f"{stem}.tiff")
    check(unknown == f"{stem}.tiff.png",
          f"an extension this app never writes is part of the NAME and the container's is "
          f"APPENDED — {os.path.basename(unknown)}, which is that set's own rule and not an "
          "oversight")

    # The refusals, each BY NAME.
    bad = s.error("render_frame", t=SEC, format="tiff")
    check(bad is not None and "png, jpeg, heic" in bad and "tiff" in bad,
          f"a format outside the three is refused, listing them and naming what was sent "
          f"— {bad!r}")
    missing = s.error("render_frame", t=SEC,
                      path=os.path.join(WORK, "phase7-no-such-folder", "x.png"))
    check(missing is not None and "no folder" in missing
          and "phase7-no-such-folder" in missing,
          f"a folder that does not exist is refused by name rather than created — {missing!r}")
    empty = s.error("render_frame", t=SEC, path="")
    check(empty is not None and "must name a file" in empty,
          f"an empty path is refused rather than read as absent — {empty!r}")

    # The three containers are three real files, read by their own magic
    # rather than by the extension this script asked for.
    jpeg_path = s.written(SEC, path=os.path.join(WORK, f"phase7-real-{os.getpid()}.jpg"),
                          format="jpeg")
    heic_path = s.written(SEC, path=os.path.join(WORK, f"phase7-real-{os.getpid()}.heic"),
                          format="heic")
    with open(jpeg_path, "rb") as handle:
        jpeg_magic = handle.read(3)
    with open(heic_path, "rb") as handle:
        heic_magic = handle.read(12)
    check(jpeg_magic == b"\xff\xd8\xff",
          f"the jpeg row writes a real JPEG (SOI {jpeg_magic.hex()})")
    check(heic_magic[4:8] == b"ftyp" and b"heic" in heic_magic,
          f"the heic row writes a real HEIC (brand {heic_magic[4:12]!r}) — `UTType.heic` and "
          "not public.heif, which this Mac's ImageIO does not offer")

    # The FLATTEN, measured where it can fail. A fully transparent canvas
    # would come out black whether it was composited onto black or merely had
    # its alpha dropped, so the fixture is a card at 50 % opacity: the
    # compositor holds it premultiplied at 128, a flatten onto black keeps
    # 128, and un-premultiplying and dropping the alpha instead gives 255.
    half = Session(mcp, "phase7-flatten", background=(0, 0, 0, 0))
    half.card([1.0, 1.0, 1.0, 1.0], size=(200, 120), opacity=0.5)
    picture = half.image(100)
    check(picture.centre() == (255, 255, 255, 128),
          f"a 50 % white card on a TRANSPARENT canvas is written to PNG straight, alpha kept "
          f"— {show(picture.centre())}")
    check(picture.pixel(0, 0) == (0, 0, 0, 0),
          f"…with the canvas around it fully transparent — {show(picture.pixel(0, 0))}")
    flat = Raster(half.written(100, path=os.path.join(WORK, f"phase7-flat-{os.getpid()}.jpg"),
                               format="jpeg"))
    middle = flat.centre()
    check(all(abs(c - 128) <= 3 for c in middle[:3]) and middle[3] == 255,
          f"…and the JPEG of the same frame is COMPOSITED onto black, so that card reads 128 "
          f"— {show(middle)}. 255 would be the alpha merely dropped, which is a different "
          "picture from the one on screen")
    kept = Raster(half.written(100, path=os.path.join(WORK, f"phase7-flat-{os.getpid()}.heic"),
                               format="heic"))
    check(all(c >= 250 for c in kept.centre()[:3]),
          f"…while the HEIC is NOT flattened — the same card reads {show(kept.centre())}, the "
          "straight colour. The flatten belongs to JPEG alone. (ffmpeg's HEIC decode does not "
          "surface the alpha channel, so what is asserted here is the flatten's absence)")
    note = half.answer(100, path=os.path.join(WORK, f"phase7-flat-{os.getpid()}.jpg"),
                       format="jpeg")
    check("no alpha channel" in note and "flattened onto black" in note,
          f"…and the jpeg answer SAYS so, in the one sentence FrameWriter keeps — {note!r}")
    check("no alpha channel" not in half.answer(100, format="png"),
          "…which a png answer does not carry, since nothing was thrown away")


# ---- section 3: ProRes 4444, and the alpha capability --------------------


def alpha_part(mcp):
    # One card, two canvases: the SAME timeline over a transparent background
    # and over an opaque one. Everything below is measured on files written
    # from these two.
    clear = Session(mcp, "phase7-alpha-clear", background=(0, 0, 0, 0))
    clear.card([1.0, 0.0, 0.0, 1.0], size=(200, 120))
    solid = Session(mcp, "phase7-alpha-solid", background=(0, 0, 0, 255))
    solid.card([1.0, 0.0, 0.0, 1.0], size=(200, 120))

    written = clear.export("prores_4444", "clear", "mov")
    stream = probe_video(written["path"])
    check(stream is not None and stream.get("codec_name") == "prores",
          f"a prores_4444 export is a ProRes file ({stream.get('codec_name') if stream else None})")
    check(stream is not None and "4444" in str(stream.get("profile")),
          f"…of the 4444 profile ({stream.get('profile') if stream else None})")
    check(stream is not None and str(stream.get("pix_fmt")).startswith("yuva"),
          f"…in a pixel format that starts \"yuva\", i.e. one carrying an alpha plane — "
          f"{stream.get('pix_fmt') if stream else None}. Asked STARTSWITH and never for "
          "equality: a file written yuva444p10le is reported yuva444p12le")
    check(stream is not None and (int(stream["width"]), int(stream["height"])) == CANVAS,
          "…at the document's own size, which is where every alpha reading below is taken")

    picture = Raster(written["path"])
    check(picture.pixel(0, 0)[3] == 0,
          f"the canvas corner of that file decodes fully TRANSPARENT — "
          f"{show(picture.pixel(0, 0))}")
    check(picture.centre()[3] == 255 and picture.centre()[0] > 200,
          f"…while the card at the centre is opaque red — {show(picture.centre())}")
    check(picture.opaque_count() == 200 * 120,
          f"…and exactly the card's 200 × 120 pixels are opaque, so the alpha map IS the "
          f"drawing rather than a constant ({picture.opaque_count()} of "
          f"{picture.width * picture.height})")

    # The pixels themselves, compared only where alpha is 255 — see the
    # docstring: ProRes carries the compositor's premultiplied values through
    # and ffmpeg reports them straight, so a translucent pixel legitimately
    # differs between two exports of one picture.
    opaque_file = Raster(solid.export("prores_4444", "solid", "mov")["path"])
    everywhere = picture.changed(opaque_file)
    disagreeing = [(x, y) for (x, y) in everywhere if picture.pixel(x, y)[3] == 255]
    check(not disagreeing,
          f"the CARD is byte-identical between the transparent-canvas export and the "
          f"opaque-canvas one, at every pixel where alpha is 255 ({len(disagreeing)} of "
          f"{picture.opaque_count()} differ)")
    check(len(everywhere) == picture.width * picture.height - 200 * 120,
          f"…and they differ at every OTHER pixel, so that identity is a claim about the "
          f"picture and not two identical files ({len(everywhere)} differ)")

    # `alpha` is a PRESET field and not a Container question, which is the
    # core's own argument (`export_table.rs`). Here it is measured: the same
    # container, the other ProRes row, no alpha plane at all.
    sibling = probe_video(clear.export("prores_422", "422", "mov")["path"])
    check(sibling is not None and sibling.get("codec_name") == "prores"
          and not str(sibling.get("pix_fmt")).startswith("yuva"),
          f"prores_422 — the SAME .mov container — writes no alpha plane "
          f"({sibling.get('pix_fmt') if sibling else None}), which is why the capability "
          "belongs to the row and not to the container")
    flat = Raster(clear.export("h264", "h264", "mp4")["path"])
    check(flat.alphas() == {255},
          f"an h264 of the same transparent timeline has no alpha at all "
          f"({sorted(flat.alphas())})")
    check(flat.pixel(0, 0)[:3] == (0, 0, 0),
          f"…and composites the transparent canvas onto BLACK — {show(flat.pixel(0, 0))}")

    # The capability is the ENCODING's and knows nothing about the project:
    # the opaque-canvas project writes an alpha plane too, and it is simply
    # opaque everywhere.
    check(str(probe_video(
        solid.export("prores_4444", "solid2", "mov")["path"]).get("pix_fmt")).startswith("yuva"),
        "an OPAQUE project exported prores_4444 still writes an alpha plane — the capability "
        "is a fact about the encoding, never about the canvas")
    check(Raster(solid.export("prores_4444", "solid3", "mov")["path"]).alphas() == {255},
          "…and every pixel of it is opaque, which is the other half of the same sentence")

    # APNG keeps alpha; GIF does not. Both show a transparent pixel, so the
    # claim is about a PARTIAL one, measured on a 50 % card.
    faint = Session(mcp, "phase7-alpha-faint", background=(0, 0, 0, 0))
    faint.card([1.0, 0.0, 0.0, 1.0], size=(200, 120), duration=SEC, opacity=0.5)
    apng = faint.raster("apng", "apng", "png")
    check(apng.pixel(0, 0)[3] == 0,
          f"an apng of a transparent canvas decodes with its corner transparent — "
          f"{show(apng.pixel(0, 0))}")
    check(apng.centre()[3] not in (0, 255) and abs(apng.centre()[3] - 128) <= 2,
          f"…and its 50 % card holds a PARTIAL alpha — {show(apng.centre())}. That is the "
          "whole of \"apng carries an alpha channel\"")
    gif = faint.raster("gif", "gif", "gif")
    check(gif.alphas().issubset({0, 255}) and gif.alphas() == {0, 255},
          f"a gif of the same timeline holds only 0 and 255 — one transparent palette index, "
          f"no partial value ({sorted(gif.alphas())}) — so APNG keeps alpha and GIF does not")
    check(gif.centre()[3] == 255,
          f"…and the 50 % card comes out fully opaque there — {show(gif.centre())}. Note the "
          "gif's own pix_fmt reads bgra, which is why this claim is made on the PIXELS")

    # The SHAPE rule, which is why every reading above is taken at the
    # document's own size. Padding a transparent picture does not merely lose
    # the alpha channel — measured on a build without this guard, it inverts
    # it, the bars opaque and the picture clear — so the combination is
    # refused rather than written wrong.
    padded = os.path.join(WORK, f"phase7-alpha-clear-letterbox-{os.getpid()}.mov")
    if os.path.exists(padded):
        os.remove(padded)
    refused = clear.error("export", preset="prores_4444", path=padded, size=[640, 480])
    check(refused is not None and "640 × 360" in refused and "640 × 480" in refused
          and "alpha" in refused,
          f"prores_4444 at a size of ANOTHER SHAPE is refused, naming both shapes — {refused!r}")
    check(not os.path.exists(padded),
          "…and no file is left behind, so the refusal is not a half-written export")
    same_size = probe_video(clear.export("h264", "h264-480", "mp4", size=[640, 480])["path"])
    check(same_size is not None
          and (int(same_size["width"]), int(same_size["height"])) == (640, 480),
          f"…while h264 takes that very size and letterboxes it ({same_size}), so the rule "
          "belongs to the alpha-carrying row and is not a rule about sizes")
    resized = Raster(clear.export("prores_4444", "720p", "mov", size="720p")["path"])
    check((resized.width, resized.height) == (1280, 720),
          f"a resize that KEEPS the shape is allowed ({resized.width}×{resized.height})")
    check(resized.pixel(0, 0)[3] == 0 and resized.centre()[3] == 255,
          f"…and keeps the alpha through the scaler — corner {show(resized.pixel(0, 0))}, "
          f"card {show(resized.centre())}")
    fitted = probe_video(clear.export("apng", "apng-square", "png", size=[300, 300])["path"])
    check(fitted is not None and (int(fitted["width"]), int(fitted["height"])) == (300, 169),
          f"and an IMAGE row asked for a square fits the document's shape inside it by itself "
          f"({fitted['width'] if fitted else None}×{fitted['height'] if fitted else None}), so "
          "only a movie row's hand-typed Custom size can reach that refusal at all")


# ---- section 4: the burn-in, in the frame --------------------------------


def predicted_band(width, height):
    """Where the burn-in may land, from the core's two constants alone.

    Three font sizes either side of the box centre and a quarter of the width
    either side of the middle — generous, because the ink is the glyphs and
    the backdrop rather than the box the core places, and tight enough that
    every wrong fraction lands outside it. The point of computing it is that
    "the changed pixels are inside their own bounding box" is a tautology and
    this is not."""
    size = round(height * BURN_IN_SIZE_FRACTION)
    centre_y = height / 2 + BURN_IN_Y_FRACTION * height
    return (width / 2 - width / 4, centre_y - 3 * size,
            width / 2 + width / 4, centre_y + 3 * size)


def burn_in_part(mcp):
    for canvas in [(640, 360), (640, 720)]:
        s = Session(mcp, f"phase7-burn-{canvas[1]}", canvas=canvas, timecode_frames=True)
        s.card([1.0, 1.0, 1.0, 1.0])
        plain, burnt = s.image(SEC), s.image(SEC, burn_in_timecode=True)
        changed = plain.changed(burnt)
        check(bool(changed), f"{canvas[0]}×{canvas[1]}: a burnt frame differs from a plain one")
        if not changed:
            continue
        x0, y0, x1, y1 = box(changed)
        band = predicted_band(*canvas)
        inside = all(band[0] <= x <= band[2] and band[1] <= y <= band[3] for x, y in changed)
        check(inside,
              f"{canvas[0]}×{canvas[1]}: every changed pixel lies inside the band the core's "
              f"own constants predict — y {band[1]:.0f}…{band[3]:.0f}, x {band[0]:.0f}…"
              f"{band[2]:.0f}; measured ({x0}, {y0})–({x1}, {y1})")
        wanted_y = canvas[1] / 2 + BURN_IN_Y_FRACTION * canvas[1]
        check(abs((y0 + y1) / 2 - wanted_y) <= 3,
              f"{canvas[0]}×{canvas[1]}: …centred on {wanted_y:.1f} px, which is "
              f"BURN_IN_Y_FRACTION {BURN_IN_Y_FRACTION} of the canvas height BELOW the canvas "
              f"centre and not a pixel offset — measured {(y0 + y1) / 2:.1f}")
        check(abs((x0 + x1) / 2 - canvas[0] / 2) <= 3,
              f"{canvas[0]}×{canvas[1]}: …and horizontally centred — measured "
              f"{(x0 + x1) / 2:.1f} against {canvas[0] / 2:.1f}")
        check((y1 - y0 + 1) <= 0.2 * canvas[1] and (x1 - x0 + 1) <= 0.4 * canvas[0],
              f"{canvas[0]}×{canvas[1]}: …and it is a caption-sized plate rather than a wash "
              f"over the picture ({x1 - x0 + 1} × {y1 - y0 + 1} px)")
        if canvas[1] == 360:
            small = (x1 - x0 + 1, y1 - y0 + 1)
        else:
            check((x1 - x0 + 1) > small[0] and (y1 - y0 + 1) > small[1],
                  f"…and the same string on a canvas twice as tall is drawn BIGGER "
                  f"({x1 - x0 + 1} × {y1 - y0 + 1} against {small[0]} × {small[1]}), which is "
                  f"BURN_IN_SIZE_FRACTION {BURN_IN_SIZE_FRACTION} of the height rather than a "
                  "point size")

    # The un-optioned frame. Byte-identity with a PRE-PHASE build is what
    # phases 1 to 6 re-running unchanged says — they render path-less frames
    # and compare bytes, and the orchestrator ran all eleven against this
    # binary. What is reachable here is the other half: the argument absent
    # and the argument false are one picture, so nothing was appended to a
    # recipe that did not ask for it.
    s = Session(mcp, "phase7-burn-default", timecode_frames=True)
    s.card([1.0, 1.0, 1.0, 1.0])
    check(digest(s.png(SEC)) == digest(s.png(SEC, burn_in_timecode=False)),
          "an absent burn_in_timecode and an explicit false render byte-identically")
    check(digest(s.png(SEC)) != digest(s.png(SEC, burn_in_timecode=True)),
          "…and a true one does not, so that identity is not two calls doing nothing")

    for tool, extra in [("render_frame", {"t": SEC}),
                        ("export", {"preset": "h264",
                                    "path": os.path.join(WORK, "phase7-never-written.mp4")})]:
        refused = s.error(tool, burn_in_timecode="yes", **extra)
        check(refused is not None and "burn_in_timecode" in refused
              and "true or false" in refused,
              f"{tool} refuses a burn_in_timecode of \"yes\" BY NAME rather than reading it "
              f"as truthy — {refused!r}")

    # The CONTENT. No OCR: what is asserted is that the picture changes
    # exactly where the timecode string changes and nowhere else.
    band = predicted_band(*CANVAS)
    one = s.image(SEC, burn_in_timecode=True)
    same_frame = s.image(SEC + 1, burn_in_timecode=True)
    next_frame = s.image(SEC + 20_000, burn_in_timecode=True)
    check(one.rows == same_frame.rows,
          "two ticks inside ONE frame of a 30 fps document burn the same picture — the layer "
          "carries a timecode and not a tick")
    moved = one.changed(next_frame)
    check(bool(moved) and all(band[0] <= x <= band[2] and band[1] <= y <= band[3]
                              for x, y in moved),
          f"…and the NEXT frame differs, only inside the burn-in's band ({len(moved)} pixels)")

    slower = Session(mcp, "phase7-burn-25", fps=[25, 1], timecode_frames=True)
    slower.card([1.0, 1.0, 1.0, 1.0])
    check(digest(s.png(0, burn_in_timecode=True)) == digest(slower.png(0, burn_in_timecode=True)),
          "at t = 0 a 25 fps document and a 30 fps one burn the same picture — 00:00:00:00 "
          "either way")
    rates = s.image(SEC // 2, burn_in_timecode=True).changed(
        slower.image(SEC // 2, burn_in_timecode=True))
    check(bool(rates) and all(band[0] <= x <= band[2] and band[1] <= y <= band[3]
                              for x, y in rates),
          f"…and at half a second they differ, inside the band and nowhere else — frame 15 "
          f"against frame 12, so the layer reads the DOCUMENT's rate ({len(rates)} pixels)")

    millis = Session(mcp, "phase7-burn-millis", timecode_frames=False)
    millis.card([1.0, 1.0, 1.0, 1.0])
    spelling = s.image(0, burn_in_timecode=True).changed(millis.image(0, burn_in_timecode=True))
    check(bool(spelling) and all(band[0] <= x <= band[2] and band[1] <= y <= band[3]
                                 for x, y in spelling),
          f"a document that spells times HH:MM:SS.mmm burns a different string at t = 0, where "
          f"the frame count is 0 either way — so only the SPELLING can differ, and "
          f"canvas.timecode_frames is honoured ({len(spelling)} pixels)")


# ---- section 5: the burn-in in the file, and the export tool -------------


def export_part(mcp):
    s = Session(mcp, "phase7-export", timecode_frames=True)
    s.card([1.0, 1.0, 1.0, 1.0], duration=SEC)

    plain = s.export("h264", "plain", "mp4")
    burnt = s.export("h264", "burnt", "mp4", burn_in_timecode=True)
    check(plain["burn_in_timecode"] is False and burnt["burn_in_timecode"] is True,
          "the export result echoes burn_in_timecode both ways, so a caller can tell the "
          "two files apart without decoding either. The echo is read off the handler's own "
          "decoded argument, so what it proves is that the argument was READ and not "
          "dropped in argument reading — the pixel checks below are what say the writer "
          "used it")
    band = predicted_band(*CANVAS)
    movie = Raster(burnt["path"]).changed(Raster(plain["path"]))
    check(bool(movie) and all(band[0] <= x <= band[2] and band[1] <= y <= band[3]
                              for x, y in movie),
          f"an H.264 export's first frame is burnt, inside the band and nowhere else "
          f"({len(movie)} pixels — a lossy encoder, so the count is its own and not the "
          "frame's)")

    # The limb a build could get wrong while every movie export looked right.
    # GIF and APNG never touch `ExportWriter`: `ImageSequenceWriter` calls
    # `Exporter.renderFrame` per frame with its own recipe key, so an option
    # plumbed only through the export's key leaves both silently un-burnt.
    apng_plain = Raster(s.export("apng", "apng-plain", "png")["path"])
    apng_burnt = Raster(s.export("apng", "apng-burnt", "png", burn_in_timecode=True)["path"])
    image_row = apng_burnt.changed(apng_plain)
    check(bool(image_row),
          f"an APNG export — the IMAGE-SEQUENCE writer, which never goes through ExportWriter "
          f"— is burnt too ({len(image_row)} pixels)")
    frames = s.image(0).changed(s.image(0, burn_in_timecode=True))
    check(set(image_row) == set(frames),
          f"…and it is burnt in EXACTLY the pixels render_frame's own pair differs in, byte "
          f"for byte: {len(image_row)} against {len(frames)}. That writer does no lossy "
          "coding, so the two paths can be compared pixel for pixel and are")

    gif_plain = Raster(s.export("gif", "gif-plain", "gif")["path"])
    gif_burnt = Raster(s.export("gif", "gif-burnt", "gif", burn_in_timecode=True)["path"])
    gif_changed = gif_burnt.changed(gif_plain)
    gif_band = predicted_band(gif_plain.width, gif_plain.height)
    check(bool(gif_changed) and all(gif_band[0] <= x <= gif_band[2]
                                    and gif_band[1] <= y <= gif_band[3]
                                    for x, y in gif_changed),
          f"a GIF export is burnt as well, at the same fraction of ITS own "
          f"{gif_plain.width}×{gif_plain.height} frame — the row's cap, not the document's "
          f"size ({len(gif_changed)} pixels)")

    # `replaceableExtensions` gained the image containers, which fixes a
    # pre-existing bug: `{path: "x.gif", preset: "apng"}` used to write
    # x.gif.png.
    doubled = s.export("apng", "doubled", "gif")
    check(doubled["path"].endswith(".png") and not doubled["path"].endswith(".gif.png"),
          f"{{path: \"x.gif\", preset: \"apng\"}} writes x.png — the doubled x.gif.png this "
          f"build's replaceableExtensions fixed ({os.path.basename(doubled['path'])})")
    other_way = s.export("gif", "otherway", "png")
    check(other_way["path"].endswith(".gif") and not other_way["path"].endswith(".png.gif"),
          f"…and the other way round, {{path: \"x.png\", preset: \"gif\"}} writes x.gif "
          f"({os.path.basename(other_way['path'])})")
    kept = s.export("gif", "kept", "gif")
    check(kept["path"].endswith("-kept-%d.gif" % os.getpid()),
          f"…while a path whose extension already matches is left exactly alone "
          f"({os.path.basename(kept['path'])})")


# ---- the catalog ---------------------------------------------------------


def catalog_part(mcp):
    names = mcp.tools()
    check(len(names) >= TOOLS,
          f"the catalog holds phase 7's {TOOLS} tools or more (got {len(names)}) — phase 7 "
          "adds no op and no tool, so it inherited the count rather than raising it, and "
          "phase 9's set_scope is what turned the assertion into a floor")

    schemas = mcp.schemas()

    def schema_of(name):
        """One tool's schema, or a stand-in that fails every check below
        rather than aborting — phase 5's idiom, for its reason."""
        found = schemas.get(name)
        if found is None:
            return {"properties": {}, "required": ["(no such tool)"], "description": ""}
        return found["inputSchema"]

    frame = schema_of("render_frame")
    check({"path", "format", "burn_in_timecode"} <= set(frame["properties"]),
          f"render_frame declares path, format and burn_in_timecode: "
          f"{sorted(frame['properties'])}")
    fmt = frame["properties"].get("format", {})
    check(fmt.get("type") == "string" and fmt.get("enum") == ["png", "jpeg", "heic"],
          f"…with format a closed enum of the three containers ({fmt.get('enum')}), read off "
          "FrameWriter's own cases rather than restated")
    check("flattened onto black" in str(fmt.get("description")),
          "…and its description carries the flatten sentence, so a caller reading the catalog "
          "meets it before the file exists")
    for tool in ("render_frame", "export"):
        burn = schema_of(tool)["properties"].get("burn_in_timecode", {})
        check(burn.get("type") == "boolean" and "PROJECT time" in str(burn.get("description")),
              f"{tool} declares burn_in_timecode a boolean, and says it shows PROJECT time "
              "even in a file written from the in/out range — the reading somebody would "
              "otherwise file as a bug")


def main():
    for binary in ("ffmpeg", "ffprobe"):
        if not shutil.which(binary):
            print(f"{binary} is needed: section 0 builds this script's two new instruments "
                  "with it and sections 3 and 5 read written files through them.")
            return 2
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(SOCKET)
    print(f"phase 7 — Output, against {SOCKET}")

    section("0 — the two new instruments, scored before anything leans on them",
            instruments_part, mcp)
    if failures:
        print("\nThe INSTRUMENTS failed. Every claim about a written file below is read "
              "through them, so nothing else in this run would mean anything.")
        print(f"\n{checks - len(failures)}/{checks} checks passed")
        return 1
    section("1 — the sentence contract: what five earlier scripts read", sentence_part, mcp)
    section("2 — render_frame's two spellings, and the three containers", writer_part, mcp)
    section("3 — ProRes 4444, and the alpha capability in the file", alpha_part, mcp)
    section("4 — the burn-in, measured against the core's two fractions", burn_in_part, mcp)
    section("5 — the burn-in in the file, and the export tool's new surface",
            export_part, mcp)
    section("6 — the catalog and the two tools' schemas", catalog_part, mcp)

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
