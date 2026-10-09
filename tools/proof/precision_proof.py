#!/usr/bin/env python3
"""The precision road map (issue batch B94; spec §11 PR-1..PR-5,
`designs/precision.md`) — the 16-bit-float compositor and its exports, over
MCP. Written in PR0, before any product edit, so PR1's controls are captured
on PR0's product.

    python3 tools/proof/precision_proof.py [--app PATH] [--only C0,D1,P1,H1] [--control DIR]
    python3 tools/proof/precision_proof.py capture DIR          # the CONTROL tree
    python3 tools/proof/precision_proof.py compare DIR [--only K1,...,E1]
    python3 tools/proof/precision_proof.py --measure capture|compare DIR   # release-only

`matte_proof.py`'s shape: it launches the app `proof_app` picks (Debug unless
`RC_PROOF_APP=release`; `--measure` is release-only) on a scratch socket of its
own and stops only that process. The instance runs in a scratch home,
`CFFIXED_USER_HOME=tools/proof/work/precision/run/home`; every package, PNG
and movie of a run is under `tools/proof/work/precision/run/`, removed at the
start and at exit. DIR (a capture) is kept. No menu item is performed, no
default is written: `--measure` passes `-ReelcutCompositorTiming YES` as a
launch argument. Every call is bounded (`CALL_BOUND`), every ffmpeg too.

The ffmpeg fixtures, made once under `tools/proof/work/precision/media/`:
the spike's 10-bit ProRes 422 HQ ramp (`make_media.sh`'s RAMP line, every
10-bit code 64..940 across 1920 px, 1 s), a 640×360 1 s H.264 `testsrc2`
(copied into DIR by `capture`, so `compare` reads the same bytes) and 2 s
ProRes 422 `testsrc2` movies at 1080p and 2160p (M1's).

The scenes, on a 640×360, 30 fps canvas, black background, read at 0.5 s
(K4 at 1.25 s), after the spike's S1–S5:
  K1 a full card (0.2, 0.6, 0.9); K2 K1 and a title; K3 K1, a full
  black→white gradient at 50 %, the title and a yellow `multiply` overlay;
  K4 red then green full cards nested, the nest clip split at 1 s and a
  0.5 s linear `cross_dissolve` made from the first half's tail (a ROUTED
  dissolve, spec §11 MT-8), mid-way; K5 six layers (K3's four, a red ellipse
  at 60 % and a blue `screen` rectangle at 80 %); K6 the H.264 clip alone.

Rows (`ID ok|FAIL — detail`, then `n/m`; exit 0 iff every scored row passes):
  C0  two renders of K3 are byte-equal.
  D1  `render_frame` of an all-8-bit project (K1's card and the H.264 clip)
      is an 8-bit PNG (spec §11 PR-4).
  P1  a full-canvas black→white gradient at opacity 0.5 over black,
      1920×1080, exported `prores_422`: the middle row's luma (ffmpeg
      `gray16le`, columns 16…W−16) against 0.5·g/255, g the gradient's 8-bit
      value from `render_frame` at opacity 1, RMS ≤ 1.0 10-bit steps. An 8-bit
      canvas measures about 1.4 or more; `capture` records the control's.
  H1  an `hevc` export of K6's clip: ffprobe `profile` Main, `pix_fmt` yuv420p.
  capture: K1–K6 rendered into DIR; E0 (CONTROL) two `h264` exports of K6's
      clip decoded to `rgb24`, their digests recorded, equal or not; the P1
      figure; the ramp's controls (the middle row's distinct green values in
      `render_frame`, and a `prores_422` export's RMS against x/1919).
  compare: K1 and K6 byte-identical to DIR's; K2–K5 every channel within ±2
      (the histogram of differences printed); E1 this tree's `h264` export of
      DIR's K6 clip, decoded the same way: byte-identical to E0's when E0's
      pair was equal, else every channel within the pair's own largest
      difference.
  --measure (M1, recorded, release-only): `prores_422` exports of a TYPICAL
      fixture (2 video tracks and a title) and a HEAVY one (4 video tracks,
      2 mattes, a routed dissolve, a shadow), each 8 s of the 2 s movie
      looped, at 1080p and 2160p, each on an instance of its own: the
      compositor timing log's average and worst over the export's 120-frame
      windows, and the memory — `phys_footprint` sampled every 0.5 s during
      the export (`footprint -p <pid>`), and the instance's lifetime
      `phys_footprint_peak` read after it, which is the figure compared (an
      export of 8 s takes 0.6–2.7 s, so a few samples miss its peak).
      `compare` prints PR0's beside, the implied extra buffers (Δpeak ÷ the
      per-buffer Δ, 64RGBAHalf against 32BGRA) and the PR1 stops (1080p's
      heavy average reaching 8 ms; the heavy 4K peak more than +532 MB). A
      refused `footprint` is a named skip of the memory half.
  Z1  the projects close and the log holds no `Reelcut: ` line.

PR1 adds `--mutant NAME` on `tree_copy.build_app` with its six anchors, and
PR2/PR3 their rows (spec B94, `designs/precision.md`).
"""

import argparse
import atexit
import hashlib
import json
import math
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/precision"
WORK = BASE / "run"
HOME = WORK / "home"
MEDIA = BASE / "media"
CALL_BOUND = 600
SEC = 600_000
T = SEC // 2
W, H = 640, 360
RELEASE_ONLY = "M1 measures the compositor's frame times and the app's memory"
TAG = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
RAMP = ("color=c=black:size=1920x1080:rate=30:duration=1,format=yuv422p10le,"
        "geq=lum='64+X*876/1919':cb=512:cr=512")
CARD = [0.2, 0.6, 0.9, 1]
GRADIENT = {"kind": "linear", "angle": 0, "stops": [{"at": 0, "color": [0, 0, 0, 1]},
                                                    {"at": 1, "color": [1, 1, 1, 1]}]}
TIMING = re.compile(r"\[reelcut\] compositor: ([\d.]+) ms average, ([\d.]+) ms worst")
# 3840×2160 IOSurface sizes the spike measured (S-precision.md §7): one
# 64RGBAHalf buffer less one 32BGRA buffer.
PER_BUFFER = {2160: 66_355_264 - 33_177_664, 1080: (66_355_264 - 33_177_664) // 4}
STOP_MS = 8.0
STOP_BYTES = 532_000_000
ROWS = ["C0", "D1", "P1", "H1", "Z1"]
CAPTURE_ROWS = ["K", "E0", "P1c", "Rc", "Z1"]
COMPARE_ROWS = ["K1", "K2", "K3", "K4", "K5", "K6", "E1", "Z1"]
rows = {}
selected = set()


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def skip(name, reason):
    print(f"  skip {name} — {reason}", flush=True)


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


class Doc:
    """One open project at `path` and the calls the rows make on it."""

    made = 0

    def __init__(self, client, name, width=W, height=H):
        Doc.made += 1
        self.client, self.path = client, WORK / f"{Doc.made:02d}-{name}.reelcut"
        self.width, self.height = width, height
        self.ok, self.why = True, None
        self.note("new_project", attempt(client, "new_project", {"path": str(self.path)}))
        sized = self.call("set_canvas", width=width, height=height, fps=[30, 1],
                          background=[0, 0, 0, 1])
        if "made no change" not in sized.get("error", ""):   # a new project's own canvas
            self.note("set_canvas", sized)

    def note(self, tool, got):
        """Records the first failed step: `ok` false and `why` its tool and error."""
        if not got["ok"] and self.ok:
            self.ok, self.why = False, f"{tool}: {got.get('error', '')[:300]}"
        return got

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def first_track(self):
        return (self.project().get("tracks") or [{}])[0].get("id")

    def new_track(self):
        before = {t.get("id") for t in self.project().get("tracks") or []}
        self.call("add_track")
        made = [t.get("id") for t in self.project().get("tracks") or []
                if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def place(self, tool, **arguments):
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not (got["ok"] and len(new) == 1):
            self.note(tool, got if not got["ok"] else {"ok": False, "error": f"{len(new)} new"})
            return None
        return new[0]

    def step(self, tool, **arguments):
        return self.note(tool, self.call(tool, **arguments))

    def shape(self, track, patch, at=0, duration=2 * SEC, video=None):
        made = self.place("add_shape_clip", track=track, at=at, duration=duration,
                          shape=dict({"kind": "rectangle", "stroke": None,
                                      "width": self.width, "height": self.height}, **patch))
        if made is not None and video:
            self.step("set_video", clips=[made], patch=video)
        return made

    def title(self, track, duration=2 * SEC):
        return self.place("add_text_clip", track=track, at=0, duration=duration,
                          text={"content": "Precision"})

    def movie(self, track, path, repeats=1, seconds=1):
        """`path` imported once per project, then placed `repeats` times back to back."""
        self.media = getattr(self, "media", {})
        if path not in self.media:
            got = self.call("import_media", path=str(path))
            self.media[path] = reply(got).get("media")
            if self.media[path] is None:
                self.note("import_media", got if not got["ok"] else {"ok": False, "error": "no id"})
        media = self.media[path]
        if media is None:
            return []
        return [self.place("add_clip", track=track, media=media, at=i * seconds * SEC)
                for i in range(repeats)]

    def render(self, out, t=T):
        """`render_frame` at `t` into `out`; the PNG's bytes, or None."""
        out = Path(out)
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       render {out.name}: {got.get('error', 'no file')}", flush=True)
            return None
        return out.read_bytes()

    def export(self, preset, out, **extra):
        out = Path(out)
        if out.exists():
            out.unlink()
        got = self.call("export", preset=preset, path=str(out), size="document", **extra)
        if not (got["ok"] and out.exists()):
            print(f"       export {out.name}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def close(self):
        return attempt(self.client, "close_project",
                       {"project": str(self.path), "discard": True})["ok"]


# ---------------------------------------------------------------------------
# Fixtures and decoding.


def ffmpeg_make(out, argv):
    if out.exists():
        return out
    MEDIA.mkdir(parents=True, exist_ok=True)
    made = bounded.run(["ffmpeg", "-v", "error", "-y", *argv, str(out)], 600)
    return out if made["rc"] == 0 and out.exists() else None


def h264_clip():
    return ffmpeg_make(MEDIA / "testsrc2_640.mp4", [
        "-f", "lavfi", "-i", f"testsrc2=size={W}x{H}:rate=30:duration=1",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", *TAG])


def ramp_clip():
    return ffmpeg_make(MEDIA / "ramp10_prores422hq.mov", [
        "-f", "lavfi", "-i", RAMP, "-c:v", "prores_ks", "-profile:v", "3",
        "-pix_fmt", "yuv422p10le", *TAG])


def prores_clip(height):
    width = height * 16 // 9
    return ffmpeg_make(MEDIA / f"prores422_{height}.mov", [
        "-f", "lavfi", "-i", f"testsrc2=size={width}x{height}:rate=30:duration=2",
        "-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le", *TAG])


def decode(path, pix_fmt, extra=(), frames=1):
    """The raw `pix_fmt` bytes of `path`'s first `frames` frames (all with
    `frames=None`), or None — bounded."""
    argv = ["ffmpeg", "-v", "error", "-i", str(path), *extra]
    if frames is not None:
        argv += ["-frames:v", str(frames)]
    try:
        raw = subprocess.run(argv + ["-f", "rawvideo", "-pix_fmt", pix_fmt, "-"],
                             capture_output=True, timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw or None


def png_depth(data):
    """A PNG's IHDR bit depth, or None."""
    return data[24] if data and data[:8] == b"\x89PNG\r\n\x1a\n" else None


def rgba(path, width=W, height=H):
    raw = decode(path, "rgba")
    return raw if raw and len(raw) == width * height * 4 else None


def luma_row(path, width, height):
    """The middle row of `path`'s first frame as `gray16le` fractions of full
    scale (`ramp_error.py`'s reading)."""
    raw = decode(path, "gray16le", ["-vf", f"crop={width}:2:0:{height // 2}"])
    if not raw or len(raw) < width * 2:
        return None
    return [v / 65535 for v in struct.unpack(f"<{width}H", raw[:width * 2])]


def rms_steps(measured, ideal):
    """RMS of (measured − ideal) in 10-bit steps over columns 16…W−16."""
    errors = [(m - i) * 1023 for m, i in list(zip(measured, ideal))[16:len(ideal) - 16]]
    return math.sqrt(sum(e * e for e in errors) / len(errors))


def histogram(a, b):
    """{|difference|: channel count} over two equal-length byte strings."""
    if a == b:
        return {0: len(a)}
    counts = {}
    for x, y in zip(a, b):
        d = abs(x - y)
        counts[d] = counts.get(d, 0) + 1
    return dict(sorted(counts.items()))


def short(counts):
    """A histogram for a line: |Δ| 0–5 by count, then the rest summed with its largest."""
    head = {d: n for d, n in counts.items() if d <= 5}
    rest = {d: n for d, n in counts.items() if d > 5}
    return f"{head}" + (f" + {sum(rest.values())} more up to {max(rest)}" if rest else "")


def digest(data):
    return hashlib.sha256(data).hexdigest()[:16] if data else None


# ---------------------------------------------------------------------------
# The scenes.


def k_scene(client, name, clip):
    """Scene `name` (K1–K6, or D1's card and clip) built in a new project;
    (doc, render time)."""
    doc = Doc(client, name)
    t1 = doc.first_track()
    if name == "K6":
        doc.movie(t1, clip)
        return doc, T
    if name == "K4":
        red = doc.shape(t1, {"fill": [1, 0, 0, 1]}, at=0, duration=SEC)
        green = doc.shape(t1, {"fill": [0, 1, 0, 1]}, at=SEC, duration=SEC)
        doc.step("nest", clips=[red, green])
        nests = lambda: sorted((c["start"], c["duration"], c["id"])  # noqa: E731
                               for c in doc.project().get("clips") or []
                               if (c.get("source") or {}).get("kind") == "nest")
        first = nests()[0][2] if len(nests()) == 1 else None
        doc.step("split", clips=[first], at=SEC)
        halves = nests()
        second = halves[1][2] if len(halves) == 2 else None
        doc.step("add_transition", clip=second, kind="cross_dissolve", duration=SEC // 2,
                 align="after")
        doc.step("set_transition_style", clip=second, curve="linear")
        if [h[:2] for h in nests()] != [(0, SEC + SEC // 2), (SEC, SEC)]:
            doc.note("halves", {"ok": False, "error": f"{nests()}"})
        return doc, SEC + SEC // 4
    doc.shape(t1, {"fill": CARD})
    if name == "D1":
        doc.movie(doc.new_track(), clip)
        return doc, T
    if name in ("K3", "K5"):
        doc.shape(doc.new_track(), {"fill": [1, 1, 1, 1], "gradient": GRADIENT},
                  video={"opacity": 0.5})
    if name == "K5":
        doc.shape(doc.new_track(), {"kind": "ellipse", "fill": [1, 0, 0, 1], "width": 300,
                                    "height": 200}, video={"opacity": 0.6, "x": -80})
    if name in ("K2", "K3", "K5"):
        doc.title(doc.new_track())
    if name in ("K3", "K5"):
        doc.shape(doc.new_track(), {"fill": [1, 0.8, 0.3, 1], "width": 320, "height": 180},
                  video={"blend": "multiply", "x": 80, "y": 40})
    if name == "K5":
        doc.shape(doc.new_track(), {"fill": [0.2, 0.3, 1, 1], "width": 200, "height": 300},
                  video={"blend": "screen", "opacity": 0.8, "x": 150})
    return doc, T


def p1_figure(client, out_dir):
    """P1's measurement: (RMS in 10-bit steps, detail) or (None, why)."""
    doc = Doc(client, "P1", 1920, 1080)
    grad = doc.shape(doc.first_track(), {"fill": [1, 1, 1, 1], "gradient": GRADIENT})
    full = doc.render(out_dir / "p1-opacity1.png")
    doc.step("set_video", clips=[grad], patch={"opacity": 0.5})
    movie = doc.export("prores_422", out_dir / "p1.mov")
    ok = doc.ok and full is not None and movie is not None and png_depth(full) == 8
    closed = doc.close()
    if not ok:
        return None, (f"fixture {doc.why or 'ok'}; render depth {png_depth(full)}; "
                      f"export {movie}"), closed
    raw = rgba(out_dir / "p1-opacity1.png", 1920, 1080)
    measured = luma_row(movie, 1920, 1080)
    if raw is None or measured is None:
        return None, "the render or the export did not decode", closed
    g = [raw[(540 * 1920 + x) * 4 + 1] for x in range(1920)]
    figure = rms_steps(measured, [0.5 * v / 255 for v in g])
    return figure, f"g {min(g)}…{max(g)}", closed


def ramp_controls(client, out_dir):
    """The ramp's figures: (distinct green values on the render's middle row,
    the prores_422 export's RMS against x/1919, the PNG's depth)."""
    doc = Doc(client, "ramp", 1920, 1080)
    doc.movie(doc.first_track(), ramp_clip())
    png = doc.render(out_dir / "ramp.png")
    movie = doc.export("prores_422", out_dir / "ramp.mov")
    closed = doc.close()
    distinct = rms = None
    if png is not None:
        raw = decode(out_dir / "ramp.png", "rgb48le")
        if raw and len(raw) == 1920 * 1080 * 6:
            row = raw[540 * 1920 * 6:541 * 1920 * 6]
            distinct = len({row[x * 6 + 2:x * 6 + 4] for x in range(1920)})
    if movie is not None:
        measured = luma_row(movie, 1920, 1080)
        rms = rms_steps(measured, [x / 1919 for x in range(1920)]) if measured else None
    return distinct, rms, png_depth(png), closed


# ---------------------------------------------------------------------------
# The modes.


def run_rows(client, state):
    clip = h264_clip()
    closed = True
    if "C0" in selected:
        doc, t = k_scene(client, "K3", clip)
        a, b = doc.render(WORK / "c0-a.png", t), doc.render(WORK / "c0-b.png", t)
        check("C0 CONTROL: two renders of K3 are byte-equal", doc.ok and a is not None
              and a == b, f"fixture {doc.why or 'ok'}; {digest(a)} vs {digest(b)}")
        closed = doc.close() and closed
    if "D1" in selected:
        doc, t = k_scene(client, "D1", clip)
        png = doc.render(WORK / "d1.png", t)
        check("D1 render_frame of an all-8-bit project (a card and the H.264 clip) is an 8-bit "
              "PNG (spec §11 PR-4)", doc.ok and png_depth(png) == 8,
              f"fixture {doc.why or 'ok'}; bit depth {png_depth(png)}")
        closed = doc.close() and closed
    if "P1" in selected:
        figure, detail, ok = p1_figure(client, WORK)
        closed = ok and closed
        control = state.get("P1", "not given (--control DIR)")
        check("P1 a 50 % gradient over black through prores_422: the middle row's luma "
              "against 0.5·g/255 is ≤ 1.0 10-bit steps RMS",
              figure is not None and figure <= 1.0,
              f"RMS {figure if figure is None else round(figure, 3)} (control {control}); "
              f"{detail}")
    if "H1" in selected:
        doc, _ = k_scene(client, "K6", clip)
        movie = doc.export("hevc", WORK / "h1.mp4")
        probe = ffprobe(movie) if movie else {}
        check("H1 an hevc export is Main, yuv420p", doc.ok and probe.get("profile") == "Main"
              and probe.get("pix_fmt") == "yuv420p", f"fixture {doc.why or 'ok'}; {probe}")
        closed = doc.close() and closed
    return closed


def ffprobe(path):
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt", "-of", "json", str(path)], 60)
    try:
        return (json.loads(ran["stdout"]).get("streams") or [{}])[0]
    except (ValueError, IndexError):
        return {}


def h264_pair(client, clip, out_dir, names):
    """`h264` exports of K6's scene over `clip`, one per name in `names`, each
    decoded to rgb24 (every frame); [(path, raw)]."""
    doc, _ = k_scene(client, "K6", clip)
    made = []
    for name in names:
        movie = doc.export("h264", out_dir / f"{name}.mp4")
        made.append((movie, decode(movie, "rgb24", frames=None) if movie else None))
    return made, doc.ok, doc.close()


def run_capture(client, where):
    where.mkdir(parents=True, exist_ok=True)
    clip = h264_clip()
    if clip is None:
        check("K CONTROL: the fixtures", False, "ffmpeg did not make the H.264 clip")
        return False
    shutil.copy2(clip, where / "k6.mp4")
    clip = where / "k6.mp4"
    record, closed = {}, True
    rendered = []
    for name in ("K1", "K2", "K3", "K4", "K5", "K6"):
        doc, t = k_scene(client, name, clip)
        png = doc.render(where / f"{name}.png", t)
        rendered.append((name, doc.why, digest(png)))
        closed = doc.close() and closed
    check("K CONTROL: K1–K6 rendered into DIR", all(not why and d for _, why, d in rendered),
          "; ".join(f"{n} {why or 'ok'} {d}" for n, why, d in rendered))
    pair, fixture, ok = h264_pair(client, clip, where, ("e0-a", "e0-b"))
    closed = ok and closed
    (_, a), (_, b) = pair
    record["E0"] = {"a": digest(a), "b": digest(b), "equal": a is not None and a == b,
                    "bytes": len(a or b"")}
    largest = max(histogram(a, b)) if a and b and len(a) == len(b) else None
    record["E0"]["largest"] = largest
    check("E0 CONTROL: two h264 exports of K6's clip decoded to rgb24, digests recorded",
          fixture and a is not None and b is not None and len(a) == len(b),
          f"{record['E0']}")
    figure, detail, ok = p1_figure(client, where)
    closed = ok and closed
    record["P1"] = None if figure is None else round(figure, 3)
    check("P1c CONTROL: P1's figure on this tree recorded", figure is not None,
          f"RMS {record['P1']} 10-bit steps; {detail}")
    distinct, rms, depth, ok = ramp_controls(client, where)
    closed = ok and closed
    record["ramp"] = {"distinct_green": distinct, "prores_422_rms": None if rms is None
                      else round(rms, 3), "png_depth": depth}
    check("Rc CONTROL: the ramp's render and prores_422 export recorded",
          distinct is not None and rms is not None, f"{record['ramp']}")
    (where / "capture.json").write_text(json.dumps(record, indent=1, sort_keys=True))
    return closed


def run_compare(client, where):
    try:
        record = json.loads((where / "capture.json").read_text())
    except (OSError, ValueError):
        sys.exit(f"no capture at {where}; run `capture` on the control tree first")
    clip, closed = where / "k6.mp4", True
    for name in ("K1", "K2", "K3", "K4", "K5", "K6"):
        if name not in selected:
            continue
        doc, t = k_scene(client, name, clip)
        doc.render(WORK / f"{name}.png", t)
        got, want = rgba(WORK / f"{name}.png"), rgba(where / f"{name}.png")
        closed = doc.close() and closed
        counts = histogram(got, want) if got and want else {}
        largest = max(counts) if counts else None
        exact = name in ("K1", "K6")
        good = doc.ok and got is not None and want is not None and (
            got == want if exact else largest <= 2)
        check(f"{name} against the control: "
              + ("byte-identical" if exact else "every channel within ±2"), good,
              f"fixture {doc.why or 'ok'}; histogram |Δ|: channels {short(counts)}")
    if "E1" in selected:
        pair, fixture, ok = h264_pair(client, clip, WORK, ("e1",))
        closed = ok and closed
        got = pair[0][1]
        e0 = record.get("E0", {})
        a = decode(where / "e0-a.mp4", "rgb24", frames=None)
        if e0.get("equal"):
            good = got is not None and got == a
            rule = "byte-identical to E0's"
        else:
            bound = e0.get("largest")
            good = got is not None and a is not None and len(got) == len(a) \
                and bound is not None and max(histogram(got, a)) <= bound
            rule = f"every channel within E0's own largest difference ({bound})"
        counts = histogram(got, a) if got and a and len(got) == len(a) else {}
        check(f"E1 this tree's h264 export of DIR's K6 clip, decoded to rgb24: {rule}",
              fixture and good, f"E0 {e0}; E1 {digest(got)}; histogram against E0 a {short(counts)}")
    return closed


# ---------------------------------------------------------------------------
# M1 (--measure).


def footprint(pid):
    """(phys_footprint, phys_footprint_peak) in bytes, or None when refused."""
    ran = bounded.run(["footprint", "-f", "bytes", "-p", str(pid)], 30)
    now = re.search(r"phys_footprint: (\d+) B", ran["stdout"])
    peak = re.search(r"phys_footprint_peak: (\d+) B", ran["stdout"])
    return (int(now.group(1)), int(peak.group(1))) if now and peak else None


def m1_fixture(client, kind, height):
    """M1's TYPICAL or HEAVY project at `height`, 8 s of the 2 s movie looped."""
    width = height * 16 // 9
    doc = Doc(client, f"m1-{kind}-{height}", width, height)
    movie, title_track = prores_clip(height), None
    v1 = doc.first_track()
    loop = doc.movie(v1, movie, repeats=4, seconds=2)
    small = {"scale": 0.5, "x": width / 4, "y": -height / 4}
    if kind == "typical":
        for clip in doc.movie(doc.new_track(), movie, repeats=4, seconds=2):
            doc.step("set_video", clips=[clip], patch=small)
        title_track = doc.new_track()
    else:
        # A routed dissolve (spec §11 MT-8): v1's four clips nested, the nest
        # clip split at 4 s, a 1 s cross dissolve from the first half's tail.
        doc.step("nest", clips=loop)
        nest = [c["id"] for c in doc.project().get("clips") or []
                if (c.get("source") or {}).get("kind") == "nest"]
        if len(nest) == 1:
            doc.step("split", clips=nest, at=4 * SEC)
            halves = sorted((c["start"], c["id"]) for c in doc.project().get("clips") or []
                            if (c.get("source") or {}).get("kind") == "nest")
            if len(halves) == 2:
                doc.step("add_transition", clip=halves[1][1], kind="cross_dissolve",
                         duration=SEC, align="after")
        for n, (patch, matte) in enumerate((
                (dict(small, shadow={"color": [0, 0, 0, 1], "opacity": 0.8, "blur": 10,
                                     "distance": 20, "angle": 315}), "alpha"),
                ({"scale": 0.5, "x": -width / 4, "y": height / 4}, "luma"),
                ({"scale": 0.35}, None))):
            track = doc.new_track()
            for clip in doc.movie(track, movie, repeats=4, seconds=2):
                doc.step("set_video", clips=[clip], patch=patch)
            if matte:
                window = doc.new_track()
                fill = {"fill": [1, 1, 1, 1], "width": width // 2, "height": height // 2}
                if matte == "luma":
                    fill["gradient"] = GRADIENT
                doc.shape(window, fill, duration=8 * SEC, video={"x": patch["x"],
                                                                 "y": patch["y"]})
                doc.step("set_track", track=window, matte=matte)
        title_track = doc.new_track()
    doc.title(title_track, duration=8 * SEC)
    return doc


def m1_measure(binary, kind, height):
    """One M1 export, on an instance of its own so its lifetime
    `phys_footprint_peak` is this fixture's; (its figures, its log)."""
    log = WORK / f"m1-{kind}-{height}.log"
    launched = mcp.launch(str(binary), ["-ReelcutCompositorTiming", "YES"],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            return {"fixture": f"the app did not listen at {launched.socket_path}",
                    "exported": False, "windows": 0, "closed": False}, log
        return m1_export(launched, kind, height), log
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)


def m1_export(launched, kind, height):
    client, pid, log = launched.client, launched.child.pid, Path(launched.log_path)
    doc = m1_fixture(client, kind, height)
    figures = {"fixture": doc.why or "ok"}
    before = footprint(pid)
    offset = log.stat().st_size
    out = WORK / f"m1-{kind}-{height}.mov"
    result = {}
    worker = threading.Thread(target=lambda: result.update(movie=doc.export("prores_422", out)))
    started = time.monotonic()
    worker.start()
    samples = []
    while worker.is_alive():
        tick = time.monotonic()
        sample = footprint(pid)
        if sample:
            samples.append(sample[0])
        worker.join(max(0.0, 0.5 - (time.monotonic() - tick)))
    figures["export_s"] = round(time.monotonic() - started, 2)
    figures["exported"] = result.get("movie") is not None
    after = footprint(pid)
    with open(log, errors="replace") as handle:
        handle.seek(offset)
        windows = [(float(a), float(w)) for a, w in TIMING.findall(handle.read())]
    figures["windows"] = len(windows)
    if windows:
        figures["average_ms"] = round(sum(a for a, _ in windows) / len(windows), 3)
        figures["worst_ms"] = max(w for _, w in windows)
    if before is None or after is None:
        figures["footprint"] = "refused"
    else:
        # The instance's lifetime peak, read after the export: an export is
        # shorter than a few 0.5 s samples, so the samples alone miss it.
        figures["before_bytes"] = before[0]
        figures["peak_bytes"] = after[1]
        figures["sampled_peak_bytes"] = max(samples) if samples else None
        figures["samples"] = len(samples)
    if out.exists():
        out.unlink()
    figures["closed"] = doc.close()
    return figures


def run_measure(binary, mode, where, logs):
    where.mkdir(parents=True, exist_ok=True)
    figures = {}
    for kind in ("typical", "heavy"):
        for height in (1080, 2160):
            figures[f"{kind}-{height}"], log = m1_measure(binary, kind, height)
            logs.append(log)
            print(f"  {kind} {height}p: {figures[f'{kind}-{height}']}", flush=True)
    measured = all(f["fixture"] == "ok" and f["exported"] and f["windows"] > 0
                   for f in figures.values())
    refused = any(f.get("footprint") == "refused" for f in figures.values())
    if refused:
        skip("M1 memory", "`footprint -p` was refused on this host")
    path = where / "measure.json"
    if mode == "capture":
        path.write_text(json.dumps(figures, indent=1, sort_keys=True))
        check("M1 CONTROL: timing and footprint recorded for both fixtures at both sizes",
              measured, f"written to {path}")
        return all(f["closed"] for f in figures.values())
    try:
        control = json.loads(path.read_text())
    except (OSError, ValueError):
        sys.exit(f"no measure capture at {where}; run `--measure capture` on the control tree")
    stops = []
    for key, now in figures.items():
        then = control.get(key, {})
        height = int(key.split("-")[1])
        line = (f"{key}: average {then.get('average_ms')} → {now.get('average_ms')} ms, worst "
                f"{then.get('worst_ms')} → {now.get('worst_ms')} ms")
        if "peak_bytes" in now and "peak_bytes" in then:
            delta = now["peak_bytes"] - then["peak_bytes"]
            line += (f"; peak {then['peak_bytes'] / 1e6:.1f} → {now['peak_bytes'] / 1e6:.1f} MB "
                     f"(Δ {delta / 1e6:+.1f} MB, {delta / PER_BUFFER[height]:+.1f} buffers)")
            if key == "heavy-2160" and delta > STOP_BYTES:
                stops.append(f"heavy 4K peak +{delta / 1e6:.1f} MB > +532 MB")
        if key == "heavy-1080" and (now.get("average_ms") or 0) >= STOP_MS:
            stops.append(f"heavy 1080p average {now.get('average_ms')} ms ≥ 8 ms")
        print(f"       {line}", flush=True)
    check("M1 measured beside the control, and no PR1 stop (1080p heavy average < 8 ms; heavy "
          "4K peak ≤ +532 MB over the control's)", measured and not stops,
          f"stops: {stops or 'none'}")
    return all(f["closed"] for f in figures.values())


# ---------------------------------------------------------------------------


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Reelcut: " in line]
    except OSError:
        return [f"{log} could not be read"]


def tail(log, count=4):
    try:
        lines = [line.rstrip() for line in open(log, errors="replace")]
    except OSError:
        return [f"{log} could not be read"]
    return lines[-count:] or ["(empty)"]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--app")
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--control", help="a capture DIR whose P1 figure the rows print")
    parser.add_argument("mode", nargs="?", choices=("capture", "compare"))
    parser.add_argument("dir", nargs="?")
    args = parser.parse_args()
    if (args.mode is None) != (args.dir is None) or (args.measure and args.mode is None):
        parser.error("capture and compare take DIR; --measure takes capture or compare DIR")
    universe = (["M1", "Z1"] if args.measure else CAPTURE_ROWS if args.mode == "capture"
                else COMPARE_ROWS if args.mode == "compare" else ROWS)
    selected = set(universe)
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()} | {"Z1"}
        unknown = selected - set(universe)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    binary = Path(args.app or proof_app.binary(
        release_only=RELEASE_ONLY if args.measure else None))
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    where = Path(args.dir).resolve() if args.dir else None
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    for maker in (h264_clip, ramp_clip):
        if maker() is None:
            print(f"instrument failure: ffmpeg did not make {maker.__name__}'s movie")
            return 2
    if args.measure and None in (prores_clip(1080), prores_clip(2160)):
        print("instrument failure: ffmpeg did not make M1's ProRes movies")
        return 2
    print(f"precision (B94) — {('--measure ' if args.measure else '') + (args.mode or 'rows')}"
          f" on {binary}", flush=True)
    if args.measure:
        logs = []
        try:
            closed = run_measure(binary, args.mode, where, logs)
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
        found = [line for log in logs for line in complaints(log)]
        check("Z1 CONTROL: the projects close and no log holds a `Reelcut: ` line",
              closed and not found, f"closed {closed}; complaints {found}")
        passed = sum(1 for name in ("M1", "Z1") if rows.get(name))
        print(f"{passed}/2")
        return 0 if passed == 2 else 1
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        state = {}
        if args.control:
            try:
                state = json.loads((Path(args.control) / "capture.json").read_text())
            except (OSError, ValueError):
                print(f"  no capture.json in {args.control}; P1 prints no control", flush=True)
        try:
            if args.mode == "capture":
                closed = run_capture(launched.client, where)
            elif args.mode == "compare":
                closed = run_compare(launched.client, where)
            else:
                closed = run_rows(launched.client, state)
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
    scored = [name for name in universe if name in selected]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
