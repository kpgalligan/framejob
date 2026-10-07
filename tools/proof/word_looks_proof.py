#!/usr/bin/env python3
"""Issue batch B86 phase 1 (#96; spec §11 W-12, W-13, W-14) and phase 3
(#245; W-16) — the three word-caption looks over MCP: a gliding pill, an
in-word fill and a dim in a pause, on instances this script launches.

    python3 tools/proof/word_looks_proof.py [--app PATH] [--only B1,W3]
    python3 tools/proof/word_looks_proof.py --record-baseline [--app PATH]
    python3 tools/proof/word_looks_proof.py --mutant glide-ignored
        (also plate-over-ink, fill-ignored, fill-unsnapped, dim-ignored,
        dim-per-draw, dim-twice, dim-not-composited, backdrop-dims)

Launches the Release build on a scratch socket of its own (`mcp.launch`) and
stops only that process. **Every instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/word-looks/home`. No menu item is
performed. Every call is bounded (120 s; W3's child 300 s). Every picture
claim is read off a `render_frame` PNG — its bytes, or its pixels through
this file's own `decode_png` — and every model claim off `get_project`. The
PNGs stay under `tools/proof/work/word-looks/frames/`.

Canvas 640×360 at 30 fps. The looks fixture has no pop (`active_scale` 1)
and saturated colours on a black canvas, so a pixel names what drew it: the
plate red, spoken ink green, upcoming ink blue.

Rows:
- **H0** (CONTROL): `<home>/Library/Application Support` is a directory.
- **B1**: fixture B's frames have the digests in
  `tools/proof/word_looks_baseline.json`. Fixture B is a hand-written
  version-11 package: one page per shipped word style
  (`CaptionStyle.wordStyle`'s five objects, six keys each), an untimed
  styled page, a plain title and a typewriter, a `word_fade` and a
  `line_rise` title; frames before the first word, at a word start,
  mid-pop, settled, between words and after the last, and frames inside
  each animation's `in` and `out` ramps. No baseline file, or one whose
  `host` is not this host, is a control FAILURE that says to re-record —
  never a pass or a skip.
- **W3**: on a SECOND scratch launch, `words_picture_proof.py <socket>`
  exits 0 (road map 8's R1–R7). Not run under `--mutant`.
- **G1**: three frames into a glide (`word_glide` 0.5) the centre of the
  plate colour's bounding box is at `x1 + easeOut(0.5) × (x2 − x1)` ± 2 px,
  strictly between `x1` and `x2` (the same centre in the two settled
  frames), and the PNG differs from both.
- **G2**: with `glide` false the same instant's frame equals the settled one.
- **G3**: the set of pixels carrying the full-coverage ink value of the
  token the pill is leaving (read from the settled frame) is identical at
  `word_glide` 0 and at 0.5, and not empty.
- **F1**: at fill ¼, ½ and ¾ the active word is active-colour left of one
  edge and upcoming-colour right of it, the edge within 6 px of that
  fraction of the fully filled extent, and increasing. **The edge is on a
  whole pixel** (W-14's device-pixel snap): at ¼ and ¾, where it falls
  inside a letter, the last active-colour column and the first
  upcoming-colour one are ADJACENT, and at no fraction does a pixel of the
  word carry both colours (at ½ the edge is in the gap between two letters,
  so only the second half is asked there).
- **F2**: a `build` page half filled has no ink right of the edge.
- **F3**: a word whose `end` is 2 s after its start is half filled 0.3 s
  in, and its frames 0.6 s and 1.5 s in are byte-identical.
- **D1**: on a 0.5 s pause's plateau the ink's mean distance from the
  background is `1 − pause_dim` of the lit frame's ± 10 %; a ramp frame
  lies between.
- **D2**: a frame in a 0.1 s pause is byte-identical to the lit one.
- **D3**: the dim is ONE opacity over the words and the pill together. On
  a page with a pill under the active word, every pixel that is the active
  ink at full coverage in the lit frame (white, over the red plate) is, on
  the plateau, that ink at `1 − pause_dim` with NO plate showing through
  it — grey, where an opacity applied to each drawing in turn would leave
  it a quarter red — and every pixel that is bare plate is the plate at
  `1 − pause_dim`. Its page has no backdrop, so since phase 3 (spec §11
  W-16) what it reads is the compositor's one multiply of the finished
  bitmap, which cannot be applied per drawing: D3 has no per-draw mutant,
  and `dim-per-draw` is D4's.
- **D4** (phase 3, spec §11 W-16): a BACKDROP never dims, and the words and
  the pill fade together above it. Page `dimplate` is D3's page over an
  opaque yellow backdrop (no ink of the page is yellow). Lit at 0.7 s and
  on the plateau at 1.1 s: every pixel that is the backdrop's (255, 255, 0)
  in the lit frame is (255, 255, 0) ± 1 on the plateau; every lit
  (255, 255, 255) pixel — the active ink, over the plate — is
  (255, 255, 127.5) ± 3; every lit (255, 0, 0) pixel — bare plate — is
  (255, 127.5, 0) ± 3; and none of the three sets is empty. It is one
  backdrop colour on one page.
- **S1**: `set_text` sets and `get_project` reads back `active_pill.glide`,
  `active_fill` and `pause_dim`; `pause_dim` 2 is refused in the core's
  sentence and changes nothing.
- **R1**: `--record-baseline` refuses a tree with uncommitted changes
  under `app/`, `core/` or `graphic/` — shown on a sample status, on a
  status that could not be read, and, when THIS tree has such changes, by
  the recording itself, which answers 2 before it launches anything — and
  the baseline file is byte for byte what it was.
- **Z1** (CONTROL): every project closes, and no launch's log holds a
  `Reelcut: ` line.

`--only ROWS` scores H0, Z1 and the named rows alone.

`--record-baseline` renders fixture B on TWO launches of the build it is
given, refuses to write unless every frame's digest agrees, and writes
`word_looks_baseline.json`: `recorded_from` (`git rev-parse HEAD`), `host`
(`sw_vers -buildVersion` and `uname -m`) and one SHA-256 per frame. **In
batch B86 the recording is the pre-B86 build's**, so B1 holds an existing
project to the picture it had before the three keys. A later re-recording,
on another host, pins the build it is recorded on instead, and
`recorded_from` says which. **It refuses, exit 2, while
`git status --porcelain -- app core graphic` prints anything** (or cannot
be read): `recorded_from` is a commit, and a build of uncommitted sources
is no commit's picture. It says so before launching and writes nothing.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`), replaces
each of the mutant's anchors in the copy's `app/Sources` (in
`LayerRenderersWords.swift` unless the edit names another file; each
asserted to occur once), builds it by the copy's own `make app`, and runs
the rows on it, W3 aside:
  glide-ignored   the plate is never interpolated: G1 must FAIL.
  plate-over-ink  the gliding plate is filled after the base pass: G3 must
                  FAIL.
  fill-ignored    the fill fraction is not read: F1 must FAIL.
  fill-unsnapped  the fill's edge is left where the fraction puts it, off
                  the pixel grid: F1 must FAIL.
  dim-ignored     the dim's amount is always 0 (`dimAmount`): D1 must FAIL.
  dim-per-draw    no transparency layer on a page with a backdrop: the
                  dim's opacity is applied to each drawing in turn (the
                  second edit, in `LayerRenderersText.swift`, lets an opaque
                  ink inherit it): D4 must FAIL — white over the plate
                  reads (255, 191, 127.5).
  dim-twice       `drawText` hands `drawWords` the dim on every page, so a
                  page with no backdrop is dimmed in the bitmap AND by the
                  compositor: D1 must FAIL (the ratio reads about 0.25).
  dim-not-composited
                  the compositor reads the recipe's `opacity`, not
                  `drawnOpacity` (in `Compositor.swift`): D1 must FAIL.
  backdrop-dims   every page's dim is the layer's (`wordDim`'s `onLayer`
                  always true): D4 must FAIL — the backdrop reads
                  (127.5, 127.5, 0).
Exit 0 means the named row FAILED in the copy — caught; 1 that it passed —
survived; 2 that the control could not be performed. A plain run exits 0 iff
every scored row passed; 3 is `mcp.py`'s, a moved default.
"""

import argparse
import atexit
import hashlib
import json
import re
import shutil
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
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/word-looks"
HOME = WORK / "home"
FRAMES = WORK / "frames"
APP = ROOT / "build/Build/Products/Release/Reelcut.app"
BASELINE = ROOT / "tools/proof/word_looks_baseline.json"
HEADER = ROOT / "core/include/reelcut_core.h"
CALL_BOUND = 120
SEC = 600_000
FRAME = 20_000
PAGE = 3 * SEC
ROWS = ["H0", "B1", "W3", "G1", "G2", "G3", "F1", "F2", "F3", "D1", "D2", "D3", "D4", "S1",
        "R1", "Z1"]
LOOK_ROWS = ("G1", "G2", "G3", "F1", "F2", "F3", "D1", "D2", "D3", "D4")
# What a recording is recorded FROM: `--record-baseline` refuses while any
# of these holds an uncommitted change.
SOURCES = ("app", "core", "graphic")
CONTROLS = ("H0", "Z1")
RENDERER = "LayerRenderersWords.swift"
# `dimAmount`'s expression, the one clamp of a dim, and `drawText`'s hand-off.
DIM_AMOUNT = "min(max(dim ?? 0, 0), 1) * min(max(pauseDim, 0), 1)"
DIM_HANDED = "wordDim(of: props, reveal: reveal).onLayer ? nil : reveal.wordDim"
BASE_PASS = (
    "        drawBase(\n"
    "            layout, tokens, word: word, mode: style.mode, spoken: spoken, upcoming: upcoming,\n"
    "            in: context)\n")
PLATE_PASS = (
    "        if let plate = glidingPlate {\n"
    "            drawGlidingPlate(\n"
    "                plate, to: activePieces, from: pieces(of: active - 1, layout, tokens, pad: pad),\n"
    "                glide: glide, size: size, scale: scale, in: context)\n"
    "        }\n")
# name: ([(anchor, replacement) or (anchor, replacement, file), …] applied in
# order — in RENDERER unless the edit names a file — and the row that must fail)
MUTANTS = {
    "glide-ignored": (
        [("let travel = CGFloat(easeOut(min(max(glide ?? 1, 0), 1)))",
          "let travel = CGFloat(easeOut(1))")], "G1"),
    # The two passes swap places: the plate goes down over the base pass.
    "plate-over-ink": ([(PLATE_PASS + BASE_PASS, BASE_PASS + PLATE_PASS)], "G3"),
    "fill-ignored": (
        [("let filled: Double? = fill.map { min(max($0, 0), 1) }",
          "let filled: Double? = nil")], "F1"),
    "fill-unsnapped": (
        [("                    : snappedToDevice(\n"
          "                        piece.left + CGFloat(filled) * (piece.right - piece.left), "
          "y: pill.midY,\n"
          "                        in: context)\n",
          "                    : piece.left + CGFloat(filled) * (piece.right - piece.left)\n")],
        "F1"),
    "dim-ignored": ([(DIM_AMOUNT, "min(max(dim ?? 0, 0), 1) * 0")], "D1"),
    # No layer, and an opaque ink no longer resets the context's alpha: the
    # pill and each token are composited at the dim's opacity one by one.
    # Only a page with a backdrop draws its dim here (spec §11 W-16), so the
    # row is D4.
    "dim-per-draw": (
        [("            context.beginTransparencyLayer(auxiliaryInfo: nil)\n"
          "        }\n"
          "        defer {\n"
          "            if dimmed > 0 {\n"
          "                context.endTransparencyLayer()\n",
          "        }\n"
          "        defer {\n"
          "            if dimmed > 0 {\n"),
         ("        context.setAlpha(CGFloat(alpha))\n"
          "        guard alpha < 1 else {\n",
          "        guard alpha < 1 else {\n", "LayerRenderersText.swift")],
        "D4"),
    # Where the dim is drawn (issue batch B86 phase 3, spec §11 W-16).
    "dim-twice": ([(DIM_HANDED, "reveal.wordDim", "LayerRenderersText.swift")], "D1"),
    "dim-not-composited": (
        [("u.opacity = Float(min(max(layer.drawnOpacity, 0), 1))",
          "u.opacity = Float(min(max(layer.opacity, 0), 1))", "Compositor.swift")], "D1"),
    "backdrop-dims": ([("props.backdrop == nil", "true")], "D4"),
    "dim-on-both": ([("guard dim.onLayer, dim.amount > 0", "guard dim.amount > 0",
                      "CompositorEffects.swift")], "D4"),
}
rows = {}
scored = list(ROWS)


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def wanted(name):
    return name in scored


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


def host():
    """What a frame's bytes depend on besides the build."""
    def first(argv):
        try:
            return subprocess.run(argv, capture_output=True, text=True,
                                  timeout=30).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return "?"
    return f"{first(['sw_vers', '-buildVersion'])} {first(['uname', '-m'])}"


def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


def canon(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


# ---- packages and frames ---------------------------------------------------------

def text_clip(clip, index, text):
    return {"id": clip, "track": 1, "start": index * PAGE, "duration": PAGE,
            "source": {"kind": "text"}, "video": {}, "text": text}


def package(name, version, pages, background):
    """A fresh hand-written package: one track, one 3 s clip per page."""
    path = WORK / f"{name}.reelcut"
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True)
    document = {
        "version": version,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1], "background": background},
        "media": [], "tracks": [{"id": 1, "name": "Words"}],
        "clips": [text_clip(10 + i, i, text) for i, (_, text) in enumerate(pages)],
        "markers": [], "nests": [], "next_id": 100,
    }
    (path / "project.json").write_text(json.dumps(document), encoding="utf-8")
    return path


def frame(client, path, tag, t):
    """`render_frame` at `t`; the PNG's bytes, or None."""
    out = FRAMES / f"{tag}.png"
    if out.exists():
        out.unlink()
    got = attempt(client, "render_frame", {"project": str(path), "t": t, "path": str(out)})
    return out.read_bytes() if got["ok"] and out.exists() else None


def words(*pairs):
    return [{"start": round(a * SEC), "end": round(b * SEC)} for a, b in pairs]


# ---- fixture B: what shipped before B86 ------------------------------------------

FOUR = words((0.2, 0.5), (0.6, 0.9), (1.0, 1.3), (1.4, 1.7))
YELLOW = [1.0, 0.85, 0.0, 1.0]


def old_style(mode="highlight", active=None, scale=1.0, pill=None, spoken=None, upcoming=None):
    """A version-11 `word_style`: the six keys, nothing else."""
    return {"mode": mode, "active_color": active, "active_scale": scale, "active_pill": pill,
            "spoken_color": spoken, "upcoming_color": upcoming}


def shipped(font, case, outline, style, content="the quick brown fox", timings=None):
    text = {"content": content, "font": font, "size": 40, "color": [1.0, 1.0, 1.0, 1.0],
            "case": case, "words": FOUR if timings is None else timings, "word_style": style}
    if outline:
        text["outline"] = {"width": 0.08 * 40, "color": [0.0, 0.0, 0.0, 1.0]}
    return text


def title(kind=None):
    text = {"content": "one two three\nfour five", "size": 40}
    if kind:
        text["animation"] = {"kind": kind, "in": SEC // 2, "out": SEC // 2}
    return text


# `CaptionStyle.wordStyle`'s five objects, with each style's face, case and
# outline (`CaptionStyle.swift`).
FIXTURE_B = [
    ("highlight", shipped("Montserrat-Black", "upper", True,
                          old_style(active=YELLOW, scale=1.12))),
    ("pill", shipped("Montserrat-ExtraBold", "upper", False,
                     old_style(pill={"color": [0.55, 0.27, 0.93, 1.0], "padding": 0.2,
                                     "radius": 0.25}))),
    ("karaoke", shipped("Montserrat-ExtraBold", "as_written", False,
                        old_style(active=YELLOW, spoken=YELLOW,
                                  upcoming=[1.0, 1.0, 1.0, 0.55]))),
    ("build", shipped("Anton-Regular", "upper", True,
                      old_style(mode="build", active=YELLOW, scale=1.15))),
    ("oneword", shipped("BebasNeue-Regular", "upper", True, old_style(scale=1.2),
                        content="fox", timings=words((0.2, 0.5)))),
    ("untimed", shipped("Montserrat-Black", "upper", True,
                        old_style(active=YELLOW, scale=1.12), timings=[])),
    ("title", title()),
    ("typewriter", title("typewriter")),
    ("wordfade", title("word_fade")),
    ("linerise", title("line_rise")),
]
RAMP_IN = 4 * FRAME            # inside a 0.5 s `in`
RAMP_OUT = PAGE - 4 * FRAME    # inside a 0.5 s `out`


def fixture_b_times(name, text):
    """The clip times photographed for one page of fixture B."""
    if "animation" in text:
        return [RAMP_IN, PAGE // 2, RAMP_OUT]
    timed = text.get("words") or []
    if not timed:
        return [SEC // 2]
    start = timed[min(1, len(timed) - 1)]["start"]
    end = timed[min(1, len(timed) - 1)]["end"]
    return [3 * FRAME,            # before the first word
            start,                # at a word start
            start + 2 * FRAME,    # mid-pop (WORD_POP is 0.12 s)
            start + 6 * FRAME,    # settled
            end + FRAME,          # between words (after the last, for one word)
            2 * SEC]              # after the last


def render_fixture_b(client, tag):
    """`{"<page>@<ticks>": sha256}` for fixture B, or None and why."""
    path = package(f"fixture-b-{tag}", 11, FIXTURE_B, [0.2, 0.25, 0.3, 1.0])
    opened = attempt(client, "open_project", {"path": str(path)})
    if not opened["ok"]:
        return None, f"open_project: {opened['error']}"
    digests = {}
    problem = None
    for index, (name, text) in enumerate(FIXTURE_B):
        for t in fixture_b_times(name, text):
            ticks = index * PAGE + t
            data = frame(client, path, f"b-{tag}-{name}-{ticks}", ticks)
            if data is None:
                problem = f"render_frame gave no PNG for {name}@{ticks}"
                break
            digests[f"{name}@{ticks}"] = hashlib.sha256(data).hexdigest()
        if problem:
            break
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    if problem is None and not closed["ok"]:
        problem = f"close_project: {closed['error']}"
    return (None, problem) if problem else (digests, "")


def row_b1(client):
    if not BASELINE.is_file():
        check("B1 CONTROL FAILURE: no baseline", False,
              f"{BASELINE} is missing: re-record it with --record-baseline on the build whose "
              "picture is to be held")
        return
    base = json.loads(BASELINE.read_text())
    here = host()
    if base.get("host") != here:
        check("B1 CONTROL FAILURE: the baseline is another host's", False,
              f"recorded on {base.get('host')!r}, this host is {here!r}: a frame's bytes are one "
              "host's, so re-record with --record-baseline (that pins the build recorded on, "
              "not the pre-B86 picture)")
        return
    now, why = render_fixture_b(client, "now")
    if now is None:
        check("B1 fixture B could not be rendered", False, why)
        return
    was = base.get("frames") or {}
    moved = sorted(key for key in set(was) | set(now) if was.get(key) != now.get(key))
    check(f"B1 fixture B: {len(now)} frames of a version-11 package have the digests recorded "
          f"from {str(base.get('recorded_from'))[:7]}",
          bool(was) and not moved, f"moved: {moved}")


# ---- PNG pixels -------------------------------------------------------------------

def decode_png(data):
    """`(width, height, channels, rows)` of an 8-bit non-interlaced PNG."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError("not a PNG")
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
    if depth != 8 or interlace != 0 or colour not in (2, 6):
        raise RuntimeError(f"a {depth}-bit, colour type {colour}, interlace {interlace} PNG: this "
                           "decoder reads 8-bit RGB or RGBA")
    bpp = 3 if colour == 2 else 4
    raw = zlib.decompress(b"".join(idat))
    stride = width * bpp
    out, prev, pos = [], bytearray(stride), 0
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
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                cur[i] = (cur[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        elif kind != 0:
            raise RuntimeError(f"PNG filter {kind}")
        out.append(bytes(cur))
        prev = cur
    return width, height, bpp, out


class Picture:
    """A decoded frame: `rgb` is `{(x, y): (r, g, b)}` for every pixel that is
    not the background (the top-left pixel's value)."""

    def __init__(self, data):
        self.data = data
        self.width, self.height, bpp, lines = decode_png(data)
        self.background = tuple(lines[0][0:3])
        back = bytes(lines[0][0:bpp])
        self.rgb = {}
        for y, line in enumerate(lines):
            if line == back * self.width:
                continue
            for x in range(self.width):
                pixel = line[x * bpp:x * bpp + 3]
                if pixel != back[:3]:
                    self.rgb[(x, y)] = tuple(pixel)

    def columns(self, test, low=None, high=None):
        """The sorted columns holding a pixel `test` accepts, within low…high."""
        return sorted({x for (x, _), pixel in self.rgb.items()
                       if test(pixel) and (low is None or x >= low)
                       and (high is None or x <= high)})

    def distance(self):
        """The mean distance of a pixel from the background, summed over channels."""
        total = sum(sum(abs(c - b) for c, b in zip(pixel, self.background))
                    for pixel in self.rgb.values())
        return total / (self.width * self.height)


def red(p):
    return p[0] > 200 and p[1] < 60 and p[2] < 60


def green(p):
    return p[1] > 200 and p[0] < 60 and p[2] < 60


def blue(p):
    return p[2] > 200 and p[0] < 60 and p[1] < 60


def ease_out(u):
    return 1 - (1 - u) ** 3


# ---- the looks fixture ------------------------------------------------------------

WHITE = [1.0, 1.0, 1.0, 1.0]
RED = [1.0, 0.0, 0.0, 1.0]
GREEN = [0.0, 1.0, 0.0, 1.0]
BLUE = [0.0, 0.0, 1.0, 1.0]


def look(content, timings, mode="highlight", active=None, pill=None, fill=False, dim=0.0,
         backdrop=None):
    text = {"content": content, "font": "Montserrat-Black", "size": 56, "color": WHITE,
            "words": timings,
            "word_style": {"mode": mode, "active_color": active, "active_scale": 1.0,
                           "active_pill": pill, "spoken_color": GREEN, "upcoming_color": BLUE,
                           "active_fill": fill, "pause_dim": dim}}
    if backdrop is not None:
        text["backdrop"] = backdrop
    return text


def plate(glide):
    return {"color": RED, "padding": 0.2, "radius": 0.25, "glide": glide}


FILL_WORDS = words((0.1, 0.3), (0.4, 0.8), (1.2, 1.4))
LOOKS = [
    ("glide", look("sun moon star sky", FOUR, active=WHITE, pill=plate(True))),
    ("jump", look("sun moon star sky", FOUR, active=WHITE, pill=plate(False))),
    ("fill", look("go MMMMMM on", FILL_WORDS, active=RED, fill=True)),
    ("build", look("go MMMMMM on", FILL_WORDS, mode="build", active=RED, fill=True)),
    ("long", look("go MMMMMM on", words((0.1, 0.3), (0.4, 2.4), (2.6, 2.8)), active=RED,
                  fill=True)),
    # A 0.1 s pause after the first word, a 0.5 s pause after the second.
    ("dim", look("sun moon star sky", words((0.2, 0.5), (0.6, 0.9), (1.4, 1.7), (1.8, 2.1)),
                 active=RED, dim=0.5)),
    # The same pauses with a red pill under white active ink (no glide).
    ("dimpill", look("sun moon star sky",
                     words((0.2, 0.5), (0.6, 0.9), (1.4, 1.7), (1.8, 2.1)),
                     active=WHITE, pill=plate(False), dim=0.5)),
    # `dimpill` over an opaque yellow backdrop, which no ink of the page is.
    ("dimplate", look("sun moon star sky",
                      words((0.2, 0.5), (0.6, 0.9), (1.4, 1.7), (1.8, 2.1)),
                      active=WHITE, pill=plate(False), dim=0.5,
                      backdrop={"color": [1.0, 1.0, 0.0, 1.0], "padding": 12, "radius": 0})),
]
INDEX = {name: index for index, (name, _) in enumerate(LOOKS)}


class Looks:
    def __init__(self, client):
        self.client = client
        self.path = package("looks", format_version(), LOOKS, [0.0, 0.0, 0.0, 1.0])
        self.opened = attempt(client, "open_project", {"path": str(self.path)})

    def png(self, page, seconds):
        """The frame `seconds` into `page`, on the 30 fps grid; bytes or None."""
        ticks = INDEX[page] * PAGE + round(seconds * 30) * FRAME
        return frame(self.client, self.path, f"looks-{page}-{ticks}", ticks)

    def close(self):
        return attempt(self.client, "close_project", {"project": str(self.path), "discard": True})


def pictures(*frames):
    """Each frame decoded, or None when any is missing."""
    if any(f is None for f in frames):
        return None
    return [Picture(f) for f in frames]


def centre(picture, test):
    found = picture.columns(test)
    return (found[0] + found[-1]) / 2 if found else None


def glide_rows(looks):
    # Word 2 starts 0.6 s in: the pill leaves token 0 for token 1 over 0.2 s.
    first = looks.png("glide", 0.5)     # token 0 settled (word 1; `word_glide` null)
    start = looks.png("glide", 0.6)     # `word_glide` 0
    half = looks.png("glide", 0.7)      # `word_glide` 0.5
    second = looks.png("glide", 0.9)    # token 1 settled (`word_glide` 1)
    seen = pictures(first, start, half, second)
    if wanted("G1"):
        if seen is None:
            check("G1 the glide's frames could not be rendered", False)
        else:
            x1, x2, x = centre(seen[0], red), centre(seen[3], red), centre(seen[2], red)
            good = None not in (x1, x2, x)
            expect = x1 + ease_out(0.5) * (x2 - x1) if good else None
            check("G1 three frames into a glide the plate's bounding box is centred at x1 + "
                  "easeOut(0.5) × (x2 − x1) ± 2 px, strictly between, and the PNG differs from "
                  "both settled frames",
                  good and abs(x - expect) <= 2 and min(x1, x2) < x < max(x1, x2)
                  and half != first and half != second,
                  f"x1 {x1}, x2 {x2}, measured {x}, expected {expect}; differs from the first "
                  f"{half != first}, from the second {half != second}")
    if wanted("G2"):
        jump_half = looks.png("jump", 0.7)
        jump_settled = looks.png("jump", 0.9)
        moved = pictures(jump_half, jump_settled)
        x = centre(moved[0], red) if moved else None
        check("G2 with glide false the frame three frames after a word start equals the "
              "settled one, and it draws a plate",
              moved is not None and jump_half == jump_settled and x is not None,
              f"equal {jump_half == jump_settled}; plate centre {x}")
    if wanted("G3"):
        if seen is None:
            check("G3 the glide's frames could not be rendered", False)
        else:
            # Token 0 is the one spoken token while word 2 is active, so every
            # green pixel is its ink; the commonest green value is full coverage.
            counts = {}
            for pixel in seen[3].rgb.values():
                if green(pixel):
                    counts[pixel] = counts.get(pixel, 0) + 1
            ink = max(counts, key=counts.get) if counts else None
            at0 = {where for where, pixel in seen[1].rgb.items() if pixel == ink}
            at5 = {where for where, pixel in seen[2].rgb.items() if pixel == ink}
            settled = {where for where, pixel in seen[3].rgb.items() if pixel == ink}
            check("G3 the pixels carrying the left token's full-coverage ink value are the same "
                  "set at word_glide 0 and 0.5, and not empty",
                  ink is not None and at0 == at5 and len(at0) > 0,
                  f"ink {ink}; {len(at0)} pixels at 0, {len(at5)} at 0.5, {len(settled)} settled; "
                  f"only at 0: {len(at0 - at5)}, only at 0.5: {len(at5 - at0)}")


def edge_of(picture, low, high):
    """The fill edge inside the active word's columns low…high: the last
    active-colour column, the first upcoming-colour one."""
    reds = picture.columns(red, low, high)
    blues = picture.columns(blue, low, high)
    return (reds[-1] if reds else None), (blues[0] if blues else None)


def fill_rows(looks):
    # The active word runs 0.4 s … 0.8 s: twelve frames.
    if wanted("F1"):
        full = looks.png("fill", 0.9)
        parts = [looks.png("fill", 0.4 + n / 30) for n in (3, 6, 9)]
        seen = pictures(full, *parts)
        extent = seen[0].columns(red) if seen else []
        if not extent:
            check("F1 the fill's frames could not be read", False,
                  f"rendered {seen is not None}; the filled word's columns {extent[:2]}")
        else:
            left, right = extent[0], extent[-1]
            lines, edges, good = [], [], True
            for fraction, picture in zip((0.25, 0.5, 0.75), seen[1:]):
                last_red, first_blue = edge_of(picture, left, right)
                expect = left + fraction * (right - left)
                fine = (last_red is not None and first_blue is not None and last_red < first_blue
                        and abs((last_red + first_blue) / 2 - expect) <= 6)
                # The snap: no pixel of the word is part active colour and
                # part upcoming, and inside a letter (¼, ¾) the two runs touch.
                both = sum(1 for (x, _), pixel in picture.rgb.items()
                           if left <= x <= right and pixel[0] > 24 and pixel[2] > 24)
                snug = fraction == 0.5 or (fine and first_blue == last_red + 1)
                good = good and fine and snug and both == 0
                edges.append(last_red)
                lines.append(f"{fraction}: red to {last_red}, blue from {first_blue}, expected "
                             f"{expect:.1f}, {both} pixels of both colours")
            rising = None not in edges and edges[0] < edges[1] < edges[2]
            check("F1 at fill ¼, ½, ¾ the active word is active-colour left of one edge and "
                  "upcoming-colour right of it, within 6 px of the fraction of its filled "
                  "extent, the edge increases, and it is on a whole pixel: the two runs are "
                  "adjacent at ¼ and ¾ and no pixel carries both colours",
                  good and rising, f"extent {left}…{right}; " + "; ".join(lines))
    if wanted("F2"):
        full = looks.png("build", 0.9)
        half = looks.png("build", 0.6)
        seen = pictures(full, half)
        extent = seen[0].columns(red) if seen else []
        if not extent:
            check("F2 the build page's frames could not be read", False,
                  f"rendered {seen is not None}")
        else:
            left, right = extent[0], extent[-1]
            inked = seen[1].columns(lambda pixel: True)
            last = inked[-1] if inked else None
            expect = left + 0.5 * (right - left)
            check("F2 a build page half filled has no ink right of the edge",
                  last is not None and abs(last - expect) <= 6 and last < right - 6,
                  f"extent {left}…{right}; the last inked column {last}, expected {expect:.1f}")
    if wanted("F3"):
        half = looks.png("long", 0.7)
        capped = looks.png("long", 1.0)
        later = looks.png("long", 1.9)
        seen = pictures(half, capped, later)
        extent = seen[1].columns(red) if seen else []
        if not extent:
            check("F3 the long word's frames could not be read", False,
                  f"rendered {seen is not None}")
        else:
            left, right = extent[0], extent[-1]
            last_red, first_blue = edge_of(seen[0], left, right)
            expect = left + 0.5 * (right - left)
            check("F3 a word 2 s long is half filled 0.3 s in, and its frames 0.6 s and 1.5 s "
                  "in are byte-identical",
                  last_red is not None and first_blue is not None
                  and abs((last_red + first_blue) / 2 - expect) <= 6 and capped == later,
                  f"extent {left}…{right}; red to {last_red}, blue from {first_blue}, expected "
                  f"{expect:.1f}; 0.6 s equals 1.5 s {capped == later}")


def dim_rows(looks):
    if wanted("D1"):
        lit = looks.png("dim", 0.7)         # inside word 2
        ramp = looks.png("dim", 0.9 + 1 / 30)   # a frame into the 0.5 s pause
        plateau = looks.png("dim", 1.1)
        seen = pictures(lit, ramp, plateau)
        if seen is None:
            check("D1 the dim's frames could not be rendered", False)
        else:
            full, part, low = (p.distance() for p in seen)
            ratio = low / full if full else None
            check("D1 on a 0.5 s pause's plateau the ink's mean distance from the background "
                  "is 1 − pause_dim (0.5) of the lit frame's ± 10 %, and a ramp frame lies "
                  "between",
                  ratio is not None and abs(ratio - 0.5) <= 0.05 and low < part < full,
                  f"lit {full:.4f}, ramp {part:.4f}, plateau {low:.4f}, ratio {ratio}")
    if wanted("D2"):
        lit = looks.png("dim", 0.3)             # inside word 1
        short = looks.png("dim", 0.5 + 1 / 30)  # inside the 0.1 s pause after it
        check("D2 a frame in a 0.1 s pause is byte-identical to the lit one",
              lit is not None and lit == short,
              f"rendered {lit is not None and short is not None}; equal {lit == short}")
    if wanted("D3"):
        seen = pictures(looks.png("dimpill", 0.7), looks.png("dimpill", 1.1))
        if seen is None:
            check("D3 the pill page's frames could not be rendered", False)
        else:
            lit, low = seen
            # Full-coverage active ink lies over the plate; bare plate is red.
            ink = [where for where, pixel in lit.rgb.items() if pixel == (255, 255, 255)]
            bare = [where for where, pixel in lit.rgb.items() if pixel == (255, 0, 0)]
            half = 255 * (1 - 0.5)
            dimmed = [low.rgb.get(where, low.background) for where in ink]
            plates = [low.rgb.get(where, low.background) for where in bare]
            tint = max((max(p) - min(p) for p in dimmed), default=None)
            off = max((max(abs(c - half) for c in p) for p in dimmed), default=None)
            plate_off = max((max(abs(p[0] - half), p[1], p[2]) for p in plates), default=None)
            check("D3 on a pill page's plateau the active ink over the plate is the lit ink at "
                  "1 − pause_dim (0.5) with no plate showing through it, and the bare plate is "
                  "the plate at 1 − pause_dim: one opacity over the words and the pill together",
                  bool(ink) and bool(bare) and tint <= 3 and off <= 3 and plate_off <= 3,
                  f"{len(ink)} ink pixels over the plate, their widest channel spread {tint} "
                  f"and furthest channel from {half} {off} (an opacity per drawing would "
                  f"spread them by about 64); {len(bare)} bare plate pixels, furthest from "
                  f"({half}, 0, 0) {plate_off}; samples {dimmed[:1]} {plates[:1]}")
    if wanted("D4"):
        seen = pictures(looks.png("dimplate", 0.7), looks.png("dimplate", 1.1))
        if seen is None:
            check("D4 the backdrop page's frames could not be rendered", False)
        else:
            lit, low = seen
            half = 255 * (1 - 0.5)
            # What each lit colour must be on the plateau, and how near.
            expect = (("backdrop", (255, 255, 0), (255, 255, 0), 1),
                      ("ink over the plate", (255, 255, 255), (255, 255, half), 3),
                      ("bare plate", (255, 0, 0), (255, half, 0), 3))
            good, lines = True, []
            for label, was, now, near in expect:
                where = [at for at, pixel in lit.rgb.items() if pixel == was]
                found = [low.rgb.get(at, low.background) for at in where]
                off = max((max(abs(c - e) for c, e in zip(p, now)) for p in found),
                          default=None)
                good = good and bool(where) and off <= near
                lines.append(f"{len(where)} lit {was} pixels ({label}): furthest channel from "
                             f"{now} {off} (within {near}), sample {found[:1]}")
            check("D4 a backdrop never dims, and the words and the pill fade together above "
                  "it: on the plateau every lit backdrop pixel is the backdrop ± 1, the active "
                  "ink over the plate is (255, 255, 127.5) ± 3 and the bare plate "
                  "(255, 127.5, 0) ± 3, none of the three sets empty",
                  good, "; ".join(lines))


def row_s1(client):
    path = WORK / "S.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    project = reply(attempt(client, "get_project", {"project": str(path)})).get("project") or {}
    track = (project.get("tracks") or [{}])[0].get("id")
    added = attempt(client, "add_text_clip", {"project": str(path), "track": track, "at": 0,
                                              "duration": 2 * SEC})
    project = reply(attempt(client, "get_project", {"project": str(path)})).get("project") or {}
    clip = ((project.get("clips") or [{}])[0]).get("id")
    patch = {"content": "one two", "words": words((0.2, 0.5), (0.6, 0.9)),
             "word_style": {"active_pill": {"glide": True}, "active_fill": True,
                            "pause_dim": 0.5}}
    put = attempt(client, "set_text", {"project": str(path), "clips": [clip], "patch": patch})
    was = reply(attempt(client, "get_project", {"project": str(path)})).get("project") or {}
    style = (((was.get("clips") or [{}])[0].get("text") or {}).get("word_style")) or {}
    bad = attempt(client, "set_text", {"project": str(path), "clips": [clip],
                                       "patch": {"word_style": {"pause_dim": 2}}})
    now = reply(attempt(client, "get_project", {"project": str(path)})).get("project") or {}
    sentence = "text.word_style.pause_dim must be between 0 and 1, not 2"
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    check("S1 set_text sets and get_project reads back active_pill.glide, active_fill and "
          "pause_dim; pause_dim 2 is refused in the core's sentence and changes nothing",
          made["ok"] and added["ok"] and put["ok"]
          and (style.get("active_pill") or {}).get("glide") is True
          and style.get("active_fill") is True and style.get("pause_dim") == 0.5
          and (not bad["ok"]) and sentence in bad["error"] and bool(was)
          and canon(now) == canon(was),
          f"set_text {put.get('error', 'ok')}; word_style {canon(style)}; pause_dim 2: "
          f"{bad.get('error', 'APPLIED')!r}; unchanged {canon(now) == canon(was)}")
    return closed


# ---- the recording's own gate -----------------------------------------------------

def source_changes():
    """`git status --porcelain -- app core graphic`, one entry per line it
    prints; None when git could not answer."""
    try:
        ran = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain", "--", *SOURCES],
                             capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if ran.returncode != 0:
        return None
    return [line for line in ran.stdout.splitlines() if line.strip()]


def recording_refusal(changes):
    """Why `--record-baseline` will not write, or None when it may: the
    file's `recorded_from` is a commit, so the sources the build was made
    from must be that commit's."""
    where = ", ".join(f"{name}/" for name in SOURCES)
    if changes is None:
        return (f"`git status --porcelain -- {' '.join(SOURCES)}` could not be read, so nothing "
                "says the build is a commit's: `recorded_from` would be a guess")
    if changes:
        named = "; ".join(line.strip() for line in changes[:3])
        return (f"{len(changes)} uncommitted change(s) under {where} ({named}"
                f"{'; …' if len(changes) > 3 else ''}): the baseline's `recorded_from` names a "
                "commit, and this build is not that commit's picture. Commit or stash them, "
                "`make app`, and record again")
    return None


def row_r1(app):
    sample = recording_refusal([" M app/Sources/LayerRenderersWords.swift"])
    unread = recording_refusal(None)
    clean = recording_refusal([])
    before = BASELINE.read_bytes() if BASELINE.is_file() else None
    changes = source_changes()
    if changes:
        # The recording itself, handed the status just read: it must answer
        # 2 before it launches anything.
        code = record(app, changes)
        shown = f"this tree has {len(changes)} such change(s) and the recording answered {code}"
    else:
        code = 2
        shown = ("this tree has none (or git did not answer), so the recording was not asked: "
                 "the sample status alone shows the refusal")
    after = BASELINE.read_bytes() if BASELINE.is_file() else None
    check("R1 --record-baseline refuses a tree with uncommitted changes under app/, core/ or "
          "graphic/, and one whose status cannot be read, and the baseline file is as it was",
          bool(sample) and bool(unread) and clean is None and code == 2 and before == after,
          f"{shown}; the file unchanged {before == after}; a sample status is refused as: "
          f"{sample}")


# ---- launches ---------------------------------------------------------------------

class Instance:
    def __init__(self, app, label):
        self.log = WORK / f"{label}.log"
        self.launched = mcp.launch(
            str(app / "Contents/MacOS/Reelcut"),
            env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
            log_path=str(self.log), timeout=CALL_BOUND)
        self.client = self.launched.client
        if self.client is not None:
            print(f"  instance PID {self.launched.child.pid} at {self.launched.socket_path} "
                  f"({label})", flush=True)

    def complaints(self):
        try:
            return [line.strip() for line in open(self.log, errors="replace")
                    if "Reelcut: " in line]
        except OSError as error:
            return [f"the log could not be read: {error}"]

    def stop(self):
        self.launched.stop()
        mcp.remove_scratch(self.launched.socket_path)


def run_rows(app, mutant):
    """Every scored row; False when an instance did not come up."""
    closes, complaints = [], []
    main = Instance(app, "main")
    try:
        if main.client is None:
            print(f"instrument failure: the app did not listen at {main.launched.socket_path}")
            return False
        support = HOME / "Library/Application Support"
        check("H0 CONTROL: the scratch home took: <home>/Library/Application Support is a "
              "directory", support.is_dir(), str(support))
        if rows.get("H0"):
            try:
                if wanted("B1"):
                    row_b1(main.client)
                if any(wanted(name) for name in LOOK_ROWS):
                    looks = Looks(main.client)
                    if not looks.opened["ok"]:
                        for name in LOOK_ROWS:
                            if wanted(name):
                                check(f"{name} not run: the looks fixture did not open", False,
                                      looks.opened["error"])
                    else:
                        glide_rows(looks)
                        fill_rows(looks)
                        dim_rows(looks)
                        closes.append(looks.close())
                if wanted("S1"):
                    closes.append(row_s1(main.client))
                if wanted("R1"):
                    row_r1(app)
            except Exception as error:  # a row that could not run is a failure
                closes.append({"ok": False, "error": f"{type(error).__name__}: {error}"})
            complaints += main.complaints()
    finally:
        main.stop()
    if rows.get("H0") and wanted("W3") and mutant is None:
        second = Instance(app, "w3")
        try:
            if second.client is None:
                check("W3 the second instance did not listen", False)
            else:
                ran = bounded.run([sys.executable, str(ROOT / "tools/proof/words_picture_proof.py"),
                                   second.launched.socket_path], 300)
                tail = (ran["stdout"].strip().splitlines() or ["(no output)"])[-1]
                failed = [line.strip() for line in ran["stdout"].splitlines() if "FAIL" in line]
                check("W3 words_picture_proof.py exits 0 on a second scratch launch (road map "
                      "8's R1–R7)", ran["rc"] == 0 and not ran["expired"],
                      f"rc {ran['rc']} (expired {ran['expired']}); last line {tail!r}; {failed}; "
                      f"stderr {ran['stderr'].strip()[-300:]!r}")
                complaints += second.complaints()
        finally:
            second.stop()
    if rows.get("H0"):
        bad = [c.get("error") for c in closes if not c["ok"]]
        check("Z1 CONTROL: every project closes and no launch's log holds a `Reelcut: ` line",
              not bad and not complaints, f"closes {bad}; complaints {complaints}")
    return True


def record(app, changes):
    """`--record-baseline`: fixture B on two launches, written only when they
    agree — and not begun while `changes` (`source_changes()`'s answer) says
    the build is not a commit's."""
    why = recording_refusal(changes)
    if why:
        print(f"  NOT WRITTEN: {why}", flush=True)
        return 2
    takes = []
    for label in ("record-1", "record-2"):
        instance = Instance(app, label)
        try:
            if instance.client is None:
                print(f"instrument failure: the app did not listen ({label})")
                return 2
            digests, why = render_fixture_b(instance.client, label)
            complaints = instance.complaints()
        finally:
            instance.stop()
        if digests is None or complaints:
            print(f"  {label}: not recorded — {why or complaints}")
            return 2
        print(f"  {label}: {len(digests)} frames", flush=True)
        takes.append(digests)
    moved = sorted(key for key in takes[0] if takes[0][key] != takes[1].get(key))
    if moved or set(takes[0]) != set(takes[1]):
        print(f"  NOT WRITTEN: the two launches disagree on {moved}")
        return 1
    head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True,
                          text=True, timeout=30).stdout.strip()
    document = {"recorded_from": head, "host": host(), "frames": takes[0]}
    BASELINE.write_text(json.dumps(document, indent=1, sort_keys=True) + "\n")
    print(f"  wrote {BASELINE}: {len(takes[0])} frames from {head[:7]} on {document['host']}")
    return 0


def remove_scratch():
    """The scratch home and a mutant's tree copy go; the frames stay."""
    for folder in (HOME, WORK / "mutant"):
        if folder.exists():
            tree_copy.remove_tree(str(folder))


def build_mutant(name):
    """A copy of the tree with the mutant's anchor replaced, built by its own
    `make app`. The app bundle, or None and why."""
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    for edit in edits:
        anchor, replacement = edit[0], edit[1]
        name = edit[2] if len(edit) > 2 else RENDERER
        target = copy / "app/Sources" / name
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, (f"the anchor {anchor.splitlines()[0].strip()!r} occurs "
                          f"{text.count(anchor)} times in {name}")
        target.write_text(text.replace(anchor, replacement))
    built = bounded.run(["make", "app"], 1500, cwd=str(copy))
    app = copy / "build/Build/Products/Release/Reelcut.app"
    if built["rc"] != 0 or not (app / "Contents/MacOS/Reelcut").exists():
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error:" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    return app, ""


def main():
    global scored
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--only", help="comma-separated rows; H0 and Z1 always run")
    parser.add_argument("--record-baseline", action="store_true")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.record_baseline and (args.mutant or args.only):
        parser.error("--record-baseline takes --app alone")
    if args.only:
        named = [name.strip() for name in args.only.split(",") if name.strip()]
        unknown = [name for name in named if name not in ROWS]
        if unknown:
            parser.error(f"no such row: {', '.join(unknown)} (rows: {', '.join(ROWS)})")
        scored = [name for name in ROWS if name in named or name in CONTROLS]
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    atexit.register(remove_scratch)
    HOME.mkdir(parents=True)
    FRAMES.mkdir(parents=True)
    app = Path(args.app)
    named = MUTANTS[args.mutant][1] if args.mutant else None
    if args.mutant:
        scored = [name for name in scored if name != "W3"]
        print(f"word looks — the {args.mutant} MUTANT ({named} must FAIL)", flush=True)
        app, why = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    elif args.record_baseline:
        print("B86 phase 1 — recording fixture B's baseline", flush=True)
    else:
        print("B86 phase 1 — the three word-caption looks over MCP", flush=True)
    if not (app / "Contents/MacOS/Reelcut").is_file():
        print(f"instrument failure: no app binary at {app / 'Contents/MacOS/Reelcut'}")
        return 2
    if args.record_baseline:
        return record(app, source_changes())
    if not run_rows(app, args.mutant):
        return 2
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        if named not in rows:
            print(f"mutant {args.mutant}: the control could not be performed — {named} was "
                  "not reached")
            return 2
        caught = rows.get(named) is False
        failed = [name for name in scored if not rows.get(name)]
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — {named} "
              f"{'FAILED' if caught else 'passed'} in the copy (failed: {', '.join(failed)})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
