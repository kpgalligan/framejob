#!/usr/bin/env python3
"""Issue #375 part 1, spec §11 PR-13: every gradient tiny-skia draws for a
graphic is dithered where it is rounded to 8 bits, by a fixed pattern of
pixel position under half a level (the vendored patch in `graphic/vendor/`);
flat colours, images and text keep their bytes.

    python3 tools/proof/raster_dither_proof.py [--only ROWS] [--control DIR]
    python3 tools/proof/raster_dither_proof.py capture DIR    # the CONTROL tree: every file kept in DIR
    python3 tools/proof/raster_dither_proof.py --mutant NAME  # cargo only, no app

Launches the app `proof_app` picks (Debug unless `RC_PROOF_APP=release`) on
a scratch socket of its own and stops only that process. The instance runs in
a scratch home, `CFFIXED_USER_HOME=tools/proof/work/raster-dither/run/home`;
every package, sheet, frame and export is under `tools/proof/work/
raster-dither/run/`, removed at the start and at exit. No menu item is
performed and no default written. Every call is bounded (`CALL_BOUND`), every
ffmpeg and cargo too. Every project is closed (`close_project`, discard).
This script never records the screen and spends nothing.

Fixtures, written with `write_graphic` into 1920×1080 30 fps projects, each
ignoring `frame` but the moving one:
- `band374`: a full-canvas rect filled by a `radialGradient` (userSpaceOnUse,
  centre 960, 540, r 1100) from `#2A4F3D` to `#0D1512` — #374's span, about
  43 green levels along row 540, x 0–800. `e`, the exact value in levels at
  a pixel centre, is worked out here from that geometry.
- `band374m`: `band374` with its centre drifting, `cx = 960 + 0.5 × frame`,
  on a 5 s clip, so the encoder cannot coast on repeated frames.
- `flat`: solid `#336699` rects (opaque and at fill-opacity 0.6), a
  one-colour `#336699` gradient rect and white Anton text.

Rows:
- **B1** `render_graphic band374` frame 0 at 1920×1080, default `max_width`
  (the cell at scale 1, at the sheet's top left, `GraphicContactSheet.
  layout`). Row 540, x 0–800, G: distinct levels, median and widest run,
  beside the control's. Holds: the median run ≤ ½ the control's; the 50-px
  block means strictly increase; every G in rows 500–580, x 0–800, is in
  [floor(e − 1/16), ceil(e + 1/16)].
- **B2** the same cell, rows 500–580, 16-px column blocks over x 0–800: max
  |mean(G − e)| ≤ 0.1; the control's printed.
- **B3** `render_frame` at 0.5 s of a 1 s `band374` clip covering the
  canvas: B1's and B2's rules.
- **B4a** a `prores_422` export of that project, the frame at 0.5 s decoded
  by ffmpeg to `rgb48le` (16 bits; its `rgb24` conversion of 10-bit ProRes
  adds a dither of its own): the banding RMS — column means of G over rows
  530–550, less a 31-column moving average, RMS over x 32–768 — ≤ ½ the
  control's; the row-540 50-px block means strictly increase.
- **B4b** a `hevc_10bit` export of a 5 s `band374m` clip, the frame at 2.5 s
  decoded to `rgb48le`: banding RMS ≤ 0.15 and under the control's.
- **L1–L3**, printed and NOT scored (spec §11 PR-13's recorded limit: the
  8-bit lossy codecs strip the dither): `h264` and `hevc` at default
  quality of the static clip, and `h264` at `video_bitrate` 16000000 of the
  moving clip, decoded to `rgb24`; banding RMS and file size beside the
  control's. L1 and L2 run with B4a, L3 with B4b.
- **F1** `render_graphic flat`: the decoded RGBA equals the control's, and
  the one-colour rect is exactly (51, 102, 153, 255).
- **F2** `render_frame` of a `flat` clip: the decoded RGBA equals the
  control's.
- **S1** `render_graphic band374` frames [0, 30] with `max_width` 8192: the
  two cells are equal, and equal to B1's cell.
- **Z1** no `Frame Job: ` log line; every project closed.

`capture DIR` runs every row and keeps every file in DIR; its own files are
the control it is scored against, so on the control tree B1, B3, B4a and B4b
are expected to FAIL. Without `--control` (and not `capture`) B1–B4b, F1 and
F2 FAIL: they have nothing to be compared with. B4a and B4b print the
per-pixel noise each codec kept (RMS of G less its column mean, rows
530–550, x 32–768) beside the control's.

`--mutant NAME` follows `image_cache_proof.run_graphic_mutant`: `graphic/`
copied (no `target`) to `work/raster-dither/mutant/` beside an `app`
symlink, each anchor in the vendored crate replaced exactly once, then
`cargo test --release --test dither` with `CARGO_TARGET_DIR=work/
raster-dither-target`. `core-unpatched` copies `core/` too, removes core's
`[patch]` table and runs `cargo test --release --offline --test graphic_ffi
a_gradient_is_dithered`. MUTANT PASS when every named test FAILED.

Exit 0 when every scored row passes (a mutant: caught); 1 when one failed (a
mutant: survived); 2 when the control could not be performed.
"""

import argparse
import array
import atexit
import json
import math
import os
import shutil
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import hdr_proof as hdr  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/raster-dither"
WORK = BASE / "run"
HOME = WORK / "home"
MUTANT_DIR = BASE / "mutant"
TARGET = ROOT / "tools/proof/work/raster-dither-target"
CALL_BOUND = 300
TOOL_BOUND = 120
CARGO_BOUND = 1800
W, H = 1920, 1080
SEC = 600_000
ROWS = ["B1", "B2", "B3", "B4a", "B4b", "F1", "F2", "S1", "Z1"]
# Every file a run keeps, by the row that writes it (L1–L3 are printed only).
FILES = {"B1": "b1-sheet.png", "B3": "b3-frame.png", "B4a": "b4a-prores.mov",
         "B4b": "b4b-hevc10-moving.mp4", "L1": "l1-h264-static.mp4",
         "L2": "l2-hevc-static.mp4", "L3": "l3-h264-16M-moving.mp4",
         "F1": "f1-sheet.png", "F2": "f2-frame.png", "S1": "s1-sheet.png"}
# The limits: (row, title, which project, export arguments, seek seconds).
LIMITS = [("L1", "h264, default quality, static 1 s", "band", {"preset": "h264"}, 0.5),
          ("L2", "hevc, default quality, static 1 s", "band", {"preset": "hevc"}, 0.5),
          ("L3", "h264 at video_bitrate 16000000, moving 5 s", "moving",
           {"preset": "h264", "video_bitrate": 16_000_000}, 2.5)]
INNER, OUTER = (42, 79, 61), (13, 21, 18)    # #2A4F3D at the centre, #0D1512 at r
CX, CY, RADIUS = 960.0, 540.0, 1100.0

BAND_JS = """export const meta = { name: "Band 374", durationInFrames: 60 };
export function render(frame, props, ctx) {
  return svg(ctx, `<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="960"
      cy="540" r="1100"><stop offset="0" stop-color="#2A4F3D"/>
      <stop offset="1" stop-color="#0D1512"/></radialGradient></defs>
    <rect x="0" y="0" width="1920" height="1080" fill="url(#g)"/>`);
}
"""
MOVING_JS = """export const meta = { name: "Band 374 moving", durationInFrames: 150 };
export function render(frame, props, ctx) {
  const cx = 960 + frame * 0.5;
  return svg(ctx, `<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="${cx}"
      cy="540" r="1100"><stop offset="0" stop-color="#2A4F3D"/>
      <stop offset="1" stop-color="#0D1512"/></radialGradient></defs>
    <rect x="0" y="0" width="1920" height="1080" fill="url(#g)"/>`);
}
"""
FLAT_JS = """export const meta = { name: "Flat", durationInFrames: 60 };
export function render(frame, props, ctx) {
  return svg(ctx, `<defs><linearGradient id="one" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#336699"/><stop offset="1" stop-color="#336699"/>
    </linearGradient></defs>
    <rect x="100" y="100" width="400" height="300" fill="#336699"/>
    <rect x="600" y="100" width="400" height="300" fill="#336699" fill-opacity="0.6"/>
    <rect x="1100" y="100" width="400" height="300" fill="url(#one)"/>
    <text x="100" y="800" font-family="Anton" font-size="300" fill="#ffffff">FLAT 375</text>`);
}
"""
ONE_COLOUR_AT = (1300, 250)

VENDOR = "graphic/vendor/tiny-skia/src"
HIGHP = f"{VENDOR}/pipeline/highp.rs"
LOWP = f"{VENDOR}/pipeline/lowp.rs"
GRADIENT = f"{VENDOR}/shaders/gradient.rs"
SHADERS = f"{VENDOR}/shaders/mod.rs"
CLAMP = "    p.{c} = (p.{c} + d).max(f32x8::default()).min(p.a);\n"
PER_CHANNEL = """    let mut dg = [0.0f32; STAGE_WIDTH];
    for (i, v) in dg.iter_mut().enumerate() {
        let h = dither_hash(dither_hash(row ^ (p.dx + i) as u32));
        *v = ((h >> 8) as f32 / 16_777_216.0 - 0.5) * DITHER_SPAN / 255.0;
    }
    p.g = (p.g + f32x8::from(dg)).max(f32x8::default()).min(p.a);
"""
# name: ([(file, anchor, replacement)], the tests that must FAIL)
MUTANTS = {
    "span-full": ([(HIGHP, "const DITHER_SPAN: f32 = 0.875;", "const DITHER_SPAN: f32 = 1.75;")],
                  ["a_colour_on_a_level_stays_exact"]),
    "no-dither": ([(GRADIENT, "        p.push(pipeline::Stage::Dither);\n", "")],
                  ["every_gradient_kind_brackets_its_exact_value",
                   "column_means_follow_the_exact_value"]),
    "rows-only": ([(HIGHP, "    let y = p.dy as u32;\n", "    let y = 0u32;\n")],
                  ["column_means_follow_the_exact_value"]),
    "per-channel": ([(HIGHP, CLAMP.format(c="g"), PER_CHANNEL)],
                    ["one_offset_for_every_channel"]),
    "alpha-dithered": ([(HIGHP, CLAMP.format(c="b"), CLAMP.format(c="b") + "    p.a = p.a + d;\n")],
                       ["alpha_is_not_dithered"]),
    "no-clamp": ([(HIGHP, CLAMP.format(c=c), CLAMP.format(c=c).replace(".min(p.a)", ""))
                  for c in "rgb"], ["alpha_is_not_dithered"]),
    "lowp-kept": ([(LOWP, "    null_fn, // Dither\n", "    dither_pass, // Dither\n"),
                   (LOWP, "pub fn null_fn(_: &mut Pipeline) {\n",
                    "pub fn dither_pass(p: &mut Pipeline) {\n    p.next_stage();\n}\n\n"
                    "pub fn null_fn(_: &mut Pipeline) {\n")],
                  ["every_gradient_kind_brackets_its_exact_value"]),
    "every-paint": ([(SHADERS, "                p.push_uniform_color(color);\n",
                      "                p.push_uniform_color(color);\n"
                      "                p.push(crate::pipeline::Stage::Dither);\n")],
                    ["solid_paints_text_and_images_are_not_dithered"]),
    "core-unpatched": ([], ["a_gradient_is_dithered_through_the_ffi"]),
}
CORE_PATCH = "[patch.crates-io]\n"

rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def attempt(client, tool, arguments):
    try:
        answer = (client.export_with(arguments) if tool == "export"
                  else client.call_with(tool, arguments))
        return {"ok": True, "reply": answer}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


# ---- reading pictures -------------------------------------------------------------

class Picture:
    """A decoded frame: width, height, channels (RGBA or RGB) and its samples
    as stored (`array`); `at` answers 8-bit levels (a 16-bit sample / 257)."""

    def __init__(self, width, height, channels, samples, scale=1.0):
        self.width, self.height, self.channels = width, height, channels
        self.samples, self.scale = samples, scale

    def at(self, x, y, c):
        return self.samples[(y * self.width + x) * self.channels + c] / self.scale

    def g(self, x, y):
        return self.at(x, y, 1)

    def crop(self, x0, y0, width, height):
        """The `width`×`height` block at (x0, y0) as a Picture."""
        out = array.array(self.samples.typecode)
        for y in range(y0, y0 + height):
            start = (y * self.width + x0) * self.channels
            out.extend(self.samples[start:start + width * self.channels])
        return Picture(width, height, self.channels, out, self.scale)


def png_header(path):
    """(width, height, bit depth) off a PNG's IHDR, or None."""
    data = Path(path).read_bytes()[:25]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">IIB", data[16:25])


def ffmpeg_raw(path, pix_fmt, seek=None):
    argv = ["ffmpeg", "-nostdin", "-v", "error"] + (["-ss", seek] if seek else []) + [
        "-i", str(path), "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pix_fmt, "-"]
    try:
        return subprocess.run(argv, capture_output=True, timeout=TOOL_BOUND,
                              env=bounded.child_env()).stdout or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def read_png(path):
    """A PNG as RGBA: an 8-bit one decoded to `rgba`, a 16-bit one to
    `rgba64le` (ffmpeg's 8 → 16-bit conversion is not exact), or None."""
    if path is None or not Path(path).exists():
        return None
    header = png_header(path)
    if header is None:
        return None
    width, height, depth = header
    deep = depth == 16
    raw = ffmpeg_raw(path, "rgba64le" if deep else "rgba")
    if raw is None or len(raw) != width * height * (8 if deep else 4):
        return None
    if not deep:
        return Picture(width, height, 4, array.array("B", raw))
    words = array.array("H")
    words.frombytes(raw)
    if sys.byteorder != "little":
        words.byteswap()
    return Picture(width, height, 4, words, 257.0)


def read_movie(path, seek, deep):
    """The frame at `seek` s of a 1920×1080 movie as rgb48le (`deep`) or
    rgb24, or None."""
    if path is None or not Path(path).exists():
        return None
    raw = ffmpeg_raw(path, "rgb48le" if deep else "rgb24", seek=str(seek))
    if raw is None or len(raw) != W * H * (6 if deep else 3):
        return None
    if not deep:
        return Picture(W, H, 3, array.array("B", raw))
    words = array.array("H")
    words.frombytes(raw)
    if sys.byteorder != "little":
        words.byteswap()
    return Picture(W, H, 3, words, 257.0)


def exact(x, y):
    """`band374`'s exact G in levels at pixel (x, y)'s centre."""
    t = min(math.hypot(x + 0.5 - CX, y + 0.5 - CY) / RADIUS, 1.0)
    return INNER[1] + (OUTER[1] - INNER[1]) * t


# ---- the figures --------------------------------------------------------------------

def runs(picture):
    """Row 540, x 0–800, G rounded to 8-bit levels: (distinct levels, median
    run, widest run)."""
    values = [round(picture.g(x, 540)) for x in range(800)]
    lengths, length = [], 1
    for a, b in zip(values, values[1:]):
        if a == b:
            length += 1
        else:
            lengths.append(length)
            length = 1
    lengths.append(length)
    return len(set(values)), statistics.median(lengths), max(lengths)


def block_means(picture, y=540):
    return [sum(picture.g(x, y) for x in range(x0, x0 + 50)) / 50 for x0 in range(0, 800, 50)]


def increasing(values):
    return all(b > a for a, b in zip(values, values[1:]))


def bracket_misses(picture):
    misses, first = 0, None
    for y in range(500, 581):
        for x in range(800):
            e, v = exact(x, y), picture.g(x, y)
            if not math.floor(e - 1 / 16) - 1e-6 <= v <= math.ceil(e + 1 / 16) + 1e-6:
                misses += 1
                first = first or f"({x}, {y}) G {v:.3f}, e {e:.3f}"
    return misses, first


def block_bias(picture):
    """Rows 500–580, 16-px column blocks over x 0–800: max |mean(G − e)|."""
    worst = 0.0
    for x0 in range(0, 800, 16):
        gaps = [picture.g(x, y) - exact(x, y) for y in range(500, 581) for x in range(x0, x0 + 16)]
        worst = max(worst, abs(sum(gaps) / len(gaps)))
    return worst


def banding(picture):
    """B4's figure: column means of G over rows 530–550, less a 31-column
    moving average, RMS over x 32–768."""
    means = [sum(picture.g(x, y) for y in range(530, 551)) / 21 for x in range(800)]
    gaps = [means[x] - sum(means[x - 15:x + 16]) / 31 for x in range(32, 769)]
    return math.sqrt(sum(g * g for g in gaps) / len(gaps))


def noise(picture):
    """The per-pixel noise kept: RMS of G less its column mean over rows
    530–550, x 32–768."""
    gaps = []
    for x in range(32, 769):
        column = [picture.g(x, y) for y in range(530, 551)]
        mean = sum(column) / len(column)
        gaps.extend(v - mean for v in column)
    return math.sqrt(sum(g * g for g in gaps) / len(gaps))


def movie_figures(path, seek, deep):
    """(banding, noise, row-540 runs, block means, bytes) of a movie, or None."""
    movie = read_movie(path, seek, deep)
    if movie is None:
        return None
    return (banding(movie), noise(movie), runs(movie), block_means(movie),
            Path(path).stat().st_size)


def shown(figures):
    if figures is None:
        return "not read"
    band, kept, (levels, median, widest), _, size = figures
    return (f"banding RMS {band:.4f}, noise kept {kept:.4f}, row 540 {levels} levels, median "
            f"run {median}, widest {widest}, {size} bytes")


def band_rows(row, picture, control, scope):
    """B1 (or B3) and B2's rules over `picture` against `control`."""
    first = row
    if picture is None:
        check(f"{first} {scope}: not read", False)
        if row == "B1":
            check(f"B2 {scope}: not read", False)
        return
    levels, median, widest = runs(picture)
    means = block_means(picture)
    misses, where = bracket_misses(picture)
    then = runs(control) if control else None
    figures = (f"row 540 x 0–800 G: {levels} levels, median run {median}, widest {widest}; "
               f"control: {then[0]} levels, median run {then[1]}, widest {then[2]}"
               if then else f"row 540 x 0–800 G: {levels} levels, median run {median}, widest "
               f"{widest}; no control")
    good = (then is not None and median <= then[1] / 2 and increasing(means) and misses == 0)
    check(f"{first} {scope}: median run ≤ ½ the control's, 50-px block means strictly increase, "
          "every G in rows 500–580 x 0–800 within [floor(e − 1/16), ceil(e + 1/16)]", good,
          f"{figures}\n       block means {[round(m, 2) for m in means]}\n       "
          f"{misses} outside the bracket{f', first {where}' if where else ''}")
    bias = block_bias(picture)
    was = block_bias(control) if control else None
    label = "B2 B1's cell" if row == "B1" else "B3 (B2's rule)"
    check(f"{label}: rows 500–580, 16-px blocks over x 0–800, max |mean(G − e)| ≤ 0.1",
          was is not None and bias <= 0.1,
          f"max |mean(G − e)| {bias:.4f}; control's {f'{was:.4f}' if was is not None else 'none'}")


# ---- the app rows -------------------------------------------------------------------

class Doc:
    def __init__(self, client, name, module, source):
        self.client, self.name, self.module = client, name, module
        self.path = WORK / f"{name}.framejob"
        steps = [attempt(client, "new_project", {"path": str(self.path)})["ok"]]
        self.call("set_canvas", width=W, height=H, fps=[30, 1])
        canvas = self.project().get("canvas") or {}
        steps.append(canvas.get("width") == W and canvas.get("height") == H
                     and canvas.get("fps") == [30, 1])
        wrote = reply(self.call("write_graphic", name=module, source=source))
        steps.append(bool(wrote.get("ok")))
        self.ok = all(steps)
        self.why = None if self.ok else f"project, canvas, write_graphic: {steps} {wrote}"

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def clip(self, seconds=1):
        """A `seconds` clip of the module at 0, covering the canvas."""
        tracks = self.project().get("tracks") or []
        if not tracks:
            self.call("add_track")
            tracks = self.project().get("tracks") or []
        if not tracks:
            return False, "no track"
        deadline, got = time.monotonic() + 5, {"error": "not tried"}
        while time.monotonic() < deadline:
            got = self.call("add_graphic_clip", track=tracks[0]["id"], at=0,
                            duration=seconds * SEC, name=self.module)
            if got["ok"]:
                return True, ""
            time.sleep(0.2)
        return False, got.get("error")

    def sheet(self, file, **extra):
        out = WORK / file
        out.unlink(missing_ok=True)
        got = self.call("render_graphic", name=self.module, width=W, height=H, path=str(out),
                        **extra)
        if not (got["ok"] and out.exists()):
            print(f"       render_graphic {file}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def frame(self, file):
        out = WORK / file
        out.unlink(missing_ok=True)
        got = self.call("render_frame", t=SEC // 2, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       render_frame {file}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def export(self, file, **arguments):
        out = WORK / file
        out.unlink(missing_ok=True)
        got = self.call("export", path=str(out), **arguments)
        if not (got["ok"] and out.exists()):
            print(f"       export {file}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def close(self):
        return attempt(self.client, "close_project", {"project": str(self.path),
                                                       "discard": True})["ok"]


def cell(picture, index=0):
    """Cell `index` of a scale-1 sheet (1920×1080 at x = index × 1928), or None."""
    if picture is None or picture.height < H or picture.width < index * (W + 8) + W:
        return None
    return picture.crop(index * (W + 8), 0, W, H)


def same(a, b):
    return a is not None and b is not None and a.samples == b.samples


def run(client, files):
    closed = True
    band = Doc(client, "band", "band374", BAND_JS)
    if not band.ok:
        print(f"       band project: {band.why}", flush=True)
    if band.ok and selected & {"B1", "B2", "S1"}:
        files["B1"] = band.sheet(FILES["B1"], frames=[0])
    if band.ok and "S1" in selected:
        files["S1"] = band.sheet(FILES["S1"], frames=[0, 30], max_width=8192)
    if band.ok and selected & {"B3", "B4a"}:
        made, why = band.clip()
        if not made:
            print(f"       band clip: {why}", flush=True)
        else:
            if "B3" in selected:
                files["B3"] = band.frame(FILES["B3"])
            if "B4a" in selected:
                files["B4a"] = band.export(FILES["B4a"], preset="prores_422")
                for row, _, project, arguments, _ in LIMITS:
                    if project == "band":
                        files[row] = band.export(FILES[row], **arguments)
    closed = band.close() and closed
    if "B4b" in selected:
        moving = Doc(client, "moving", "band374m", MOVING_JS)
        made, why = moving.clip(5) if moving.ok else (False, moving.why)
        if made:
            files["B4b"] = moving.export(FILES["B4b"], preset="hevc_10bit")
            for row, _, project, arguments, _ in LIMITS:
                if project == "moving":
                    files[row] = moving.export(FILES[row], **arguments)
        else:
            print(f"       moving project: {why}", flush=True)
        closed = moving.close() and closed
    flat = Doc(client, "flat", "flat", FLAT_JS)
    if not flat.ok:
        print(f"       flat project: {flat.why}", flush=True)
    if flat.ok and "F1" in selected:
        files["F1"] = flat.sheet(FILES["F1"], frames=[0])
    if flat.ok and "F2" in selected:
        made, why = flat.clip()
        if made:
            files["F2"] = flat.frame(FILES["F2"])
        else:
            print(f"       flat clip: {why}", flush=True)
    closed = flat.close() and closed
    return closed


def score(files, control):
    """Every row but Z1, over this run's files and the control's (or None)."""
    def theirs(row):
        path = control / FILES[row] if control else None
        return path if path and path.exists() else None

    if selected & {"B1", "B2"}:
        here = cell(read_png(files.get("B1")))
        there = cell(read_png(theirs("B1")))
        band_rows("B1", here, there, "render_graphic band374 frame 0, the cell at scale 1")
    if "B3" in selected:
        band_rows("B3", read_png(files.get("B3")), read_png(theirs("B3")),
                  "render_frame at 0.5 s of a band374 clip")
    if "B4a" in selected:
        here = movie_figures(files.get("B4a"), 0.5, True)
        then = movie_figures(theirs("B4a"), 0.5, True)
        good = (here is not None and then is not None and here[0] <= then[0] / 2
                and increasing(here[3]))
        check("B4a a prores_422 export of the band374 clip, the frame at 0.5 s (16-bit decode): "
              "banding RMS ≤ ½ the control's, row-540 50-px block means strictly increase", good,
              f"{shown(here)}\n       control: {shown(then)}"
              + (f"\n       row-540 block means {[round(m, 2) for m in here[3]]}" if here else ""))
    if "B4b" in selected:
        here = movie_figures(files.get("B4b"), 2.5, True)
        then = movie_figures(theirs("B4b"), 2.5, True)
        good = here is not None and then is not None and here[0] <= 0.15 and here[0] < then[0]
        check("B4b a hevc_10bit export of the 5 s band374m clip, the frame at 2.5 s (16-bit "
              "decode): banding RMS ≤ 0.15 and under the control's", good,
              f"{shown(here)}\n       control: {shown(then)}")
    for row, title, project, _, seek in LIMITS:
        if ("B4a" if project == "band" else "B4b") not in selected:
            continue
        here = movie_figures(files.get(row), seek, False)
        then = movie_figures(theirs(row), seek, False)
        ratio = (f"{here[0] / then[0]:.3f}" if here and then and then[0] else "n/a")
        growth = (f"{100.0 * (here[4] - then[4]) / then[4]:+.1f} %" if here and then else "n/a")
        print(f"  --   {row} (NOT scored; PR-13's limit) {title}, 8-bit decode: {shown(here)}\n"
              f"       control: {shown(then)}\n       banding ratio {ratio}; file {growth}",
              flush=True)
    if "F1" in selected:
        here, there = read_png(files.get("F1")), read_png(theirs("F1"))
        one = tuple(round(here.at(*ONE_COLOUR_AT, c)) for c in range(4)) if here else None
        equal = same(here, there)
        check("F1 render_graphic flat: decoded RGBA equals the control's; the one-colour rect is "
              "exactly (51, 102, 153, 255)", equal and one == (51, 102, 153, 255),
              f"equal to the control's: {equal if there else 'no control'}; one-colour rect "
              f"{one}")
    if "F2" in selected:
        here, there = read_png(files.get("F2")), read_png(theirs("F2"))
        check("F2 render_frame of a flat clip: decoded RGBA equals the control's",
              same(here, there),
              f"read {here is not None}; control {there is not None}")
    if "S1" in selected:
        sheet, first = read_png(files.get("S1")), read_png(files.get("B1"))
        a, b, c = cell(sheet, 0), cell(sheet, 1), cell(first, 0)
        check("S1 render_graphic band374 frames [0, 30], max_width 8192: the two cells equal, and "
              "equal to B1's cell", same(a, b) and same(a, c),
              f"cell 0 == cell 1: {same(a, b)}; cell 0 == B1's: {same(a, c)}")


# ---- the mutants ----------------------------------------------------------------------

def copy_crate(names):
    tree_copy.remove_tree(str(MUTANT_DIR))
    MUTANT_DIR.mkdir(parents=True)
    for name in names:
        shutil.copytree(ROOT / name, MUTANT_DIR / name, ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "app", MUTANT_DIR / "app")


def run_mutant(name):
    edits, named = MUTANTS[name]
    print(f"#375 part 1 — the {name} MUTANT ({' '.join(named)} must FAIL)", flush=True)
    core = name == "core-unpatched"
    copy_crate(["graphic", "core"] if core else ["graphic"])
    if core:
        manifest = MUTANT_DIR / "core/Cargo.toml"
        text = manifest.read_text()
        if text.count(CORE_PATCH) != 1:
            print(f"mutant {name}: the control could not be performed — {CORE_PATCH!r} occurs "
                  f"{text.count(CORE_PATCH)} times in core/Cargo.toml")
            return 2
        manifest.write_text(text[:text.index(CORE_PATCH)].rstrip("\n") + "\n")
        argv = ["cargo", "test", "--release", "--offline", "--test", "graphic_ffi",
                "a_gradient_is_dithered"]
        folder, expected = MUTANT_DIR / "core", "running 1 test"
    else:
        for path, anchor, replacement in edits:
            target = MUTANT_DIR / path
            text = target.read_text()
            if text.count(anchor) != 1:
                print(f"mutant {name}: the control could not be performed — the anchor occurs "
                      f"{text.count(anchor)} times in {path}: {anchor!r}")
                return 2
            target.write_text(text.replace(anchor, replacement))
        argv = ["cargo", "test", "--release", "--test", "dither"]
        folder, expected = MUTANT_DIR / "graphic", "running 7 tests"
    got = bounded.run(argv, CARGO_BOUND, cwd=str(folder),
                      env=bounded.child_env({"CARGO_TARGET_DIR": str(TARGET)}))
    output = got["stdout"] + got["stderr"]
    BASE.mkdir(parents=True, exist_ok=True)
    (BASE / f"mutant-{name}.log").write_text(output)
    if got["expired"] or expected not in output:
        errors = [line for line in output.splitlines() if line.startswith("error")][:5]
        print(f"mutant {name}: the control could not be performed — the tests did not run "
              f"(rc {got['rc']}, expired {got['expired']}): {errors}")
        return 2
    for line in output.splitlines():
        if line.startswith("test ") and " ... " in line:
            print(f"  {line}")
    survived = [test for test in named if f"test {test} ... FAILED" not in output]
    caught = not survived
    print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {name} — {' '.join(named)} "
          f"{'all FAILED' if caught else 'did not all fail'} (survived: "
          f"{', '.join(survived) or 'none'})")
    return 0 if caught else 1


# ---- the run --------------------------------------------------------------------------

def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", choices=["capture"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--control", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=list(MUTANTS))
    args = parser.parse_args()
    if args.mutant:
        return run_mutant(args.mutant)
    if args.mode == "capture" and not args.folder:
        print("capture needs a folder")
        return 2
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    keep = (ROOT / args.folder).resolve() if args.mode == "capture" else None
    control = (ROOT / args.control).resolve() if args.control else None
    if control is not None and not control.is_dir():
        print(f"instrument failure: no control folder at {control}")
        return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    binary = proof_app.binary()
    print(f"#375 part 1 — graphic gradients dithered, spec §11 PR-13 ({args.mode or 'run'}, "
          f"{proof_app.config()} build {binary}; control {control or keep or 'none'})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    log = WORK / "instance.log"
    files = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            closed = run(launched.client, files)
        except Exception as error:  # a row that could not run is a failure
            import traceback
            traceback.print_exc()
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    files = {row: path for row, path in files.items() if path is not None}
    if keep is not None:
        keep.mkdir(parents=True, exist_ok=True)
        for path in files.values():
            shutil.copy2(path, keep / path.name)
        (keep / "capture.json").write_text(json.dumps(
            {"tree": str(ROOT), "config": proof_app.config(),
             "files": sorted(p.name for p in files.values())}, indent=1))
        print(f"  captured {len(files)} files into {keep}", flush=True)
    score(files, keep or control)
    found = hdr.complaints(log)
    check("Z1 every project closed and the log holds no `Frame Job: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(hdr.tail(log)), flush=True)
    scored = [name for name in ROWS if name in rows]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if keep is not None:
        print(f"captured; on this tree FAILED: {[n for n in scored if not rows[n]]}")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
