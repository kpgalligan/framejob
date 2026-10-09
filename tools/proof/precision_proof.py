#!/usr/bin/env python3
"""The precision road map (issue batch B94; spec §11 PR-1..PR-5,
`designs/adr/precision.md`, the phase records `archive/precision.md`) — the
16-bit-float compositor and its exports, over
MCP. Written in PR0, before any product edit, so PR1's controls are captured
on PR0's product.

    python3 tools/proof/precision_proof.py [--app PATH] [--only C0,D1,D2,P1,H1,R1,R2,C1,T1,T2] [--control DIR]
    python3 tools/proof/precision_proof.py capture DIR          # the CONTROL tree
    python3 tools/proof/precision_proof.py compare DIR [--only K1,...,E2]
    python3 tools/proof/precision_proof.py --measure capture|compare DIR   # release-only
    python3 tools/proof/precision_proof.py --measure ab --mutant decode-8bit [--rounds N]  # release-only
    python3 tools/proof/precision_proof.py --mutant NAME [compare DIR]
    python3 tools/proof/precision_proof.py --selftest           # no app

`matte_proof.py`'s shape: it launches the app `proof_app` picks (Debug unless
`RC_PROOF_APP=release`; `--measure` is release-only) on a scratch socket of its
own and stops only that process. The app must be a product of a TREE — a
`build/Build/Products/…` under a folder holding `app/Sources/Compositor.swift`
(this tree, or a mutant's copy) — because `capture` records, and `compare`
and D2 read, the pixel formats of the SOURCES the driven app was built from
(`app_tree`); `--app PATH` or `RC_PROOF_APP` naming an app outside any tree is
refused (exit 2), never read against this tree's formats. The instance runs in a scratch home,
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
  D2  (PR2; a STOP, spec §11 PR-4) D1's project, every source now decoded
      `64RGBAHalf`: its `render_frame` is still an 8-bit PNG.
  R1  (PR2) `render_frame` of the 10-bit ramp on a 1920×1080 canvas is a
      16-bit PNG whose middle row's green holds ≥ 850 distinct values; with
      `--control DIR` the control's (decoded 32BGRA) must hold ≤ 256.
  R2  (PR2) the ramp through `prores_422`: the middle row's luma against
      x/1919 is ≤ 1.0 10-bit steps RMS (`--control DIR` prints the control's).
  C1  (PR2) the H.264 clip at `video.color.brightness` −0.4: every colour
      channel within ±2 of max(0, its brightness-0 render − 102) — a deep
      frame arrives unclamped, and `layerSample`'s `saturate` bounds it.
  T1  (PR3) the 10-bit ramp exported `hevc_10bit`: ffprobe says `hevc`,
      profile `Main 10`, `yuv420p10le`, and an MP4 (major brand `mp42`, not
      QuickTime's `qt  `).
  T2  (PR3) the same ramp's middle-row luma against x/1919: `hevc_10bit` is
      ≤ 2.0 10-bit steps RMS and ≤ ½ of an `hevc` export's RMS of the same
      project in the same run; and its encoder was handed DEEP frames: the
      8-bit staircase's tone (`staircase_tone`: each column's mean code over
      the frame's rows, less a 31-column moving average, at 255 steps across
      the width) is ≤ 0.1 codes, where the `hevc` file's — 8-bit, the control
      that the instrument sees a staircase — is ≥ 0.3. Main 10 handed 8-bit
      frames passes the RMS halves (1.794 against 1.459) but not the tone.
  capture: the tree's `Compositor.swift` formats recorded (`formats`, read
      from `app/Sources`; a capture without them is PR0's, both 32BGRA);
      K1–K6 rendered into DIR; E0 (CONTROL) two `h264` exports of K6's
      clip decoded to `rgb24`, their digests recorded, equal or not; the P1
      figure; the ramp's controls (the middle row's distinct green values in
      `render_frame`, and a `prores_422` export's RMS against x/1919).
  compare (each histogram of differences printed): K1 byte-identical to
      DIR's; K2–K5 (no video) byte-identical when this tree's output format
      is the control's (PR2 against PR1), within ±2 when it is not (PR1
      against PR0); K6 (video) byte-identical when the source format is the
      control's, and when it is not (PR2 against PR1) recorded, not scored
      (spec §11 PR-2's ±1 on video).
  E1 (compare; the orchestrator's ruling after PR0, because E0 showed
      VideoToolbox's H.264 encode is not repeatable — two exports of one
      project differed by up to 124 levels): what `ExportWriter` hands the
      `h264` ENCODER. K6's and K3's scenes are saved as packages and read by
      `precision_encoder_probe.swift`, compiled through `swift_build.build`
      over this tree's `app/Sources` (a mutant's copy under `--mutant`): the
      core's `h264` settings, the composition as an export builds it, one
      frame through an `AVAssetReaderVideoCompositionOutput` in
      `Compositor.outputPixelFormat`, then `ExportWriter.frameForm` and
      `ExportFrames.convert` — or the reader's frame as it is when the form is
      nil. The handed buffer must be 32BGRA and, against DIR's `render_frame`
      PNG of the same scene (the captured tree's 8-bit frame), K6 (opaque, one layer)
      byte-identical and K3 (blended) every channel within ±1, the
      compositor's own ±1 at 16-bit float (K3's row). Across a decode change
      (PR2 against PR1's capture) K6's bound is the largest |Δ| of this
      tree's own K6 render against DIR's (the re-baseline rule's "within
      K6's histogram"), and the handed frame must also be byte-identical to
      that render. A probe that does not
      build is a scored FAILURE. This tree's `h264` export of K6, decoded to
      `rgb24`, is printed beside E0's digests, unscored.
  E2 (compare; PR1's fix pass): the same for the `hevc` (Main) encoder. Fed
      the half-float frame it encoded the precision ramp at 9.04 10-bit steps
      RMS against PR0's 6.46 from 32BGRA (both repeatable over three exports
      each), so `hevc` is rounded to 8 bits as `h264` is.
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
      per-buffer Δ, 64RGBAHalf against 32BGRA) and the frame-time stop
      (1080p's heavy average reaching 8 ms). The memory is printed and
      recorded, not a stop: the owner accepted PR1's measured rise (heavy 4K
      +851.7 MB, spec §11 PR-1) and retired the road map's +532 MB stop. A
      refused `footprint` is a named skip of the memory half.
  --measure ab --mutant decode-8bit (MA, recorded, release-only; PR2's
      review): the heavy 2160p fixture alone, exported on this tree's Release
      app and on a Release build of the `decode-8bit` copy (every source
      32BGRA, nothing else changed), alternated `--rounds` times (default 3)
      so both see the same host load; each export's compositor average and
      worst, the medians, and the deep decode's share (tree median ÷ copy
      median). Scored only on every export measuring.
  --selftest (no app): `app_tree` reads a scratch tree's formats from an app
      under its `build/Build/Products`, refuses an app outside any tree, and
      the default (no `--app`) is this tree's (rows S1–S3).
  Z1  the projects close and the log holds no `Reelcut: ` line.

`--mutant NAME` (PR1; spec B94) builds ONE `tree_copy.make_copy` with each
named anchor asserted to occur exactly once and replaced, by the copy's own
`make app-debug` (`make app` under `RC_PROOF_APP=release`;
`tree_copy.build_app`), and runs only its named rows on the copy — the probe
built from the copy's `app/Sources`:
  h264-deep        `frameForm` answers nil for `h264`: E1 FAILS (compare DIR).
  output-8bit      `Compositor.outputPixelFormat` is 32BGRA: P1 FAILS, and
                   `preview_refresh_probe.py --sources <copy>` scores PF FAILED.
  hevc-deep        `frameForm` answers nil for `hevc`: E2 FAILS (compare DIR).
  hevc-no-profile  the `hevc` Main pin removed AND `hevc` handed the deep
                   frame (`hevc-deep`'s anchor; with the 8-bit frame
                   VideoToolbox writes Main with or without the pin, so the pin
                   alone is an equivalent mutant): H1 FAILS
                   (`hevc_alpha_proof.py --mutant hevc-no-profile` holds B1 to it).
  decode-8bit      (PR2) `Compositor.sourcePixelFormat` is 32BGRA: R1 and R2
                   FAIL.
  no-source-clamp  (PR2) `layerSample`'s `saturate` removed (the clamp landed
                   in PR1; only a deep source reaches it): C1 FAILS.
  hevc10-main      (PR3) `hevc_10bit`'s profile is Main, not Main 10: T1 FAILS.
  hevc10-unmapped  (PR3) `codecType(for:)` drops `"hevc_10bit"`: T1 FAILS.
  hevc10-eightbit  (PR3; carried from PR1's fix pass) `frameForm` answers
                   `.eightBit` for `hevc_10bit` (the `isMain10` arm removed,
                   so `.hevc` decides): T2 FAILS.
  row-before-hevc-alpha  (PR3, core) the `hevc_10bit` row moved before
                   `hevc_alpha` in `export_table.rs`: no app is built; row CT
                   runs `cargo test --release --no-fail-fast --test export
                   --test export_hevc_10bit` in the copy's own `core/`, and
                   FAILS naming `hevc_alpha_sits_directly_after_hevc` and
                   `it_sits_directly_after_hevc_alpha`.
Exit 0 when every named row FAILED (caught), 1 when one passed (survived), 2
when the control could not be performed.
"""

import argparse
import atexit
import hashlib
import json
import math
import os
import re
import tempfile
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
import swift_build  # noqa: E402
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
# An MP4's major brands as AVFoundation and ffmpeg write them; QuickTime's is "qt  ".
MP4_BRANDS = ("mp42", "mp41", "isom")
# T2's 8-bit staircase tone, in 10-bit codes (`staircase_tone`). Measured on
# the ramp (M2 Max, macOS 26.5.1, precision PR3): hevc_10bit 0.014 (floor
# 0.010); hevc_10bit handed 8-bit frames (mutant hevc10-eightbit) 0.536;
# hevc (8-bit Main) 0.758.
TONE_MAX, TONE_SEEN = 0.1, 0.3
# The formats a tree's `Compositor.swift` names; a capture records its own
# (PR2), and a capture without them is PR0's: both 32BGRA.
FORMAT = re.compile(r"static let (output|source)PixelFormat: OSType = (kCVPixelFormatType_\w+)")
PR0_FORMATS = {"output": "kCVPixelFormatType_32BGRA", "source": "kCVPixelFormatType_32BGRA"}
BRIGHTNESS = -0.4
PROBE_SOURCE = ROOT / "tools/proof/precision_encoder_probe.swift"
PROBE_DIR = BASE / "encoder-probe"
BUILD_BOUND = 1500
SETTINGS = "app/Sources/ExporterWriter+Settings.swift"
TABLE = "core/src/export_table.rs"
HEVC10_ROW = ('    Preset {\n        id: "hevc_10bit",\n        name: "HEVC 10-bit (MP4)",\n'
              '        container: Container::Mp4,\n        codec: "hevc_10bit",\n'
              '        video: true,\n        alpha: false,\n        size: None,\n'
              '        fps: None,\n'
              '        avf_preset: Some("AVAssetExportPresetHEVCHighestQuality"),\n    },\n')
HEVC_DEEP = (SETTINGS, "        return codec == .h264 || codec == .hevc ? .eightBit : nil\n",
             "        return codec == .h264 ? .eightBit : nil\n")
MUTANTS = {
    "h264-deep": {"mode": "compare", "rows": ["E1"], "anchors": [
        (SETTINGS, "        return codec == .h264 || codec == .hevc ? .eightBit : nil\n",
         "        return codec == .hevc ? .eightBit : nil\n")]},
    "output-8bit": {"mode": "rows", "rows": ["P1"], "pf": True, "anchors": [
        ("app/Sources/Compositor.swift",
         "    static let outputPixelFormat: OSType = kCVPixelFormatType_64RGBAHalf\n",
         "    static let outputPixelFormat: OSType = kCVPixelFormatType_32BGRA\n")]},
    "hevc-deep": {"mode": "compare", "rows": ["E2"], "anchors": [HEVC_DEEP]},
    # With `hevc`'s frame rounded to 8 bits, VideoToolbox writes Main with or
    # without the pin, so the pin alone removed is an equivalent mutant: this
    # one removes it AND hands `hevc` the deep frame, the input the pin is for.
    "hevc-no-profile": {"mode": "rows", "rows": ["H1"], "anchors": [
        (SETTINGS,
         "            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as "
         "String\n", ""), HEVC_DEEP]},
    # PR2.
    "decode-8bit": {"mode": "rows", "rows": ["R1", "R2"], "anchors": [
        ("app/Sources/Compositor.swift",
         "    static let sourcePixelFormat: OSType = kCVPixelFormatType_64RGBAHalf\n",
         "    static let sourcePixelFormat: OSType = kCVPixelFormatType_32BGRA\n")]},
    "no-source-clamp": {"mode": "rows", "rows": ["C1"], "anchors": [
        ("app/Resources/Shaders/Compositor.metal", "    float4 texel = saturate(source.sample(\n",
         "    float4 texel = (source.sample(\n")]},
    # PR3.
    "hevc10-main": {"mode": "rows", "rows": ["T1"], "anchors": [
        (SETTINGS, "            compression[AVVideoProfileLevelKey] = "
         "kVTProfileLevel_HEVC_Main10_AutoLevel as String\n",
         "            compression[AVVideoProfileLevelKey] = "
         "kVTProfileLevel_HEVC_Main_AutoLevel as String\n")]},
    "hevc10-unmapped": {"mode": "rows", "rows": ["T1"], "anchors": [
        (SETTINGS, '        case "hevc_10bit": return .hevc\n', "")]},
    "hevc10-eightbit": {"mode": "rows", "rows": ["T2"], "anchors": [
        (SETTINGS, "        if isMain10(settings) { return nil }\n", "")]},
    "row-before-hevc-alpha": {"mode": "core", "rows": ["CT"], "anchors": [
        (TABLE, HEVC10_ROW, ""),
        (TABLE, '    Preset {\n        id: "hevc_alpha",\n',
         HEVC10_ROW + '    Preset {\n        id: "hevc_alpha",\n')]},
}
CORE_TESTS = ("hevc_alpha_sits_directly_after_hevc", "it_sits_directly_after_hevc_alpha")
ROWS = ["C0", "D1", "D2", "P1", "H1", "R1", "R2", "C1", "T1", "T2", "Z1"]
CAPTURE_ROWS = ["K", "E0", "P1c", "Rc", "Z1"]
COMPARE_ROWS = ["K1", "K2", "K3", "K4", "K5", "K6", "E1", "E2", "Z1"]
rows = {}
selected = set()
sources_folder = ROOT / "app/Sources"


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


def y10_columns(path, width, height):
    """`path`'s first frame decoded as `yuv420p10le`: (the middle row's luma
    CODES, each column's mean code over rows 8…H−8), or (None, None). The
    ramp is the same on every row, so the column mean averages the encoder's
    block noise away and keeps what every row shares — an 8-bit staircase
    under it, if the encoder was handed 8-bit frames."""
    raw = decode(path, "yuv420p10le")
    if not raw or len(raw) < width * height * 2:
        return None, None
    plane = struct.unpack(f"<{width * height}H", raw[:width * height * 2])
    middle = list(plane[(height // 2) * width:(height // 2 + 1) * width])
    rows = range(8, height - 8)
    means = [sum(plane[y * width + x] for y in rows) / len(rows) for x in range(width)]
    return middle, means


def staircase_tone(means, width):
    """The 8-bit staircase's tone: the column means less their own 31-column
    moving average (detail finer than 31 px is left — an 8-bit staircase's
    sawtooth, a step every 7.5 px on this ramp — and no offset or gentle
    curve, which the average follows), and that residual's amplitude, in
    codes, at the staircase's own frequency (255 steps across W−1 px); with
    the median amplitude over 41 frequencies either side of it (0.09–0.12 and
    0.15–0.18 cycles/px) as its floor. (tone, floor)."""
    errors = [means[x] - sum(means[x - 15:x + 16]) / 31 for x in range(32, width - 32)]

    def amplitude(f):
        re = sum(e * math.cos(2 * math.pi * f * n) for n, e in enumerate(errors))
        im = sum(e * math.sin(2 * math.pi * f * n) for n, e in enumerate(errors))
        return 2 * math.hypot(re, im) / len(errors)
    floor = sorted(amplitude(f) for f in [0.09 + 0.03 * k / 20 for k in range(21)]
                   + [0.15 + 0.03 * k / 19 for k in range(20)])
    return amplitude(255 / (width - 1)), floor[len(floor) // 2]


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


def tree_formats(folder=None):
    """{"output", "source"}: the pixel formats `folder`'s (by default
    `sources_folder`'s) `Compositor.swift` names — the sources of the app
    driven (`app_tree`), this tree's or a mutant copy's."""
    try:
        return dict(FORMAT.findall((Path(folder or sources_folder) / "Compositor.swift")
                                   .read_text()))
    except OSError:
        return {}


def app_tree(binary):
    """The tree whose `app/Sources` built `binary`: the folder above the
    `build/Build/Products` it sits in, when that folder holds
    `app/Sources/Compositor.swift`; else None (an app outside any tree, whose
    formats cannot be read). PR2's review: `--app PATH` once read the WORKING
    tree's formats whatever PATH was."""
    path = Path(os.path.abspath(binary))
    for parent in path.parents:
        if (parent.name, parent.parent.name, parent.parent.parent.name) == (
                "Products", "Build", "build"):
            tree = parent.parent.parent.parent
            return tree if (tree / "app/Sources/Compositor.swift").is_file() else None
    return None


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
    if selected & {"D1", "D2"}:
        doc, t = k_scene(client, "D1", clip)
        png = doc.render(WORK / "d1.png", t)
        check("D1 render_frame of an all-8-bit project (a card and the H.264 clip) is an 8-bit "
              "PNG (spec §11 PR-4)", doc.ok and png_depth(png) == 8,
              f"fixture {doc.why or 'ok'}; bit depth {png_depth(png)}")
        check("D2 (STOP, PR-4) with every source decoded 64RGBAHalf (PR2) the same project's "
              "render_frame is still an 8-bit PNG — a failure stops PR2 and returns PR-4 to the "
              "owner", doc.ok and png_depth(png) == 8,
              f"fixture {doc.why or 'ok'}; bit depth {png_depth(png)}; this tree's formats "
              f"{tree_formats()}")
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
    if selected & {"R1", "R2"}:
        distinct, rms, depth, ok = ramp_controls(client, WORK)
        closed = ok and closed
        ramp = state.get("ramp") or {}
        control = ramp.get("distinct_green")
        check("R1 render_frame of the 10-bit ramp on a 1920×1080 canvas is a 16-bit PNG whose "
              "middle row's green holds ≥ 850 distinct values (the control, decoded 32BGRA, "
              "≤ 256)", depth == 16 and distinct is not None and distinct >= 850
              and (control is None or control <= 256),
              f"bit depth {depth}; {distinct} distinct (control "
              f"{control if control is not None else 'not given (--control DIR)'})")
        check("R2 the ramp through prores_422: the middle row's luma against x/1919 is ≤ 1.0 "
              "10-bit steps RMS", rms is not None and rms <= 1.0,
              f"RMS {rms if rms is None else round(rms, 3)} (control "
              f"{ramp.get('prores_422_rms', 'not given (--control DIR)')})")
    if "C1" in selected:
        closed = run_c1(client, clip) and closed
    if selected & {"T1", "T2"}:
        closed = run_t(client) and closed
    return closed


def run_t(client):
    """T1 and T2 (PR3): the 10-bit ramp exported `hevc_10bit` and `hevc` from
    one project in one run; each file's ffprobe, major brand, middle-row luma
    RMS against x/1919, distinct middle-row codes and staircase tone."""
    doc = Doc(client, "T", 1920, 1080)
    doc.movie(doc.first_track(), ramp_clip())
    got = {}
    for preset in ("hevc_10bit", "hevc"):
        movie = doc.export(preset, WORK / f"t-{preset}.mp4")
        measured = luma_row(movie, 1920, 1080) if movie else None
        codes, means = y10_columns(movie, 1920, 1080) if movie else (None, None)
        got[preset] = {"probe": ffprobe(movie) if movie else {},
                       "brand": major_brand(movie) if movie else None,
                       "rms": rms_steps(measured, [x / 1919 for x in range(1920)])
                       if measured else None,
                       "distinct": len(set(codes[16:-16])) if codes else None,
                       "tone": staircase_tone(means, 1920) if means else (None, None)}
    closed = doc.close()
    ten, eight = got["hevc_10bit"], got["hevc"]
    probe = ten["probe"]
    check("T1 a hevc_10bit export is hevc, Main 10, yuv420p10le, in an MP4",
          doc.ok and probe.get("codec_name") == "hevc" and probe.get("profile") == "Main 10"
          and probe.get("pix_fmt") == "yuv420p10le" and ten["brand"] in MP4_BRANDS,
          f"fixture {doc.why or 'ok'}; {probe}; major brand {ten['brand']!r}")
    a, b = ten["rms"], eight["rms"]
    tone, control = ten["tone"][0], eight["tone"][0]
    fmt = lambda v: None if v is None else round(v, 3)  # noqa: E731
    check("T2 the ramp through hevc_10bit: the middle row's luma against x/1919 is ≤ 2.0 "
          "10-bit steps RMS and ≤ ½ of hevc's in the same run, and the encoder was handed "
          f"deep frames — no 8-bit staircase: its tone ≤ {TONE_MAX} codes, where hevc's "
          f"(8-bit, the control) is ≥ {TONE_SEEN}",
          doc.ok and None not in (a, b, tone, control) and a <= 2.0 and a <= b / 2
          and tone <= TONE_MAX and control >= TONE_SEEN,
          f"hevc_10bit RMS {fmt(a)}; hevc RMS {fmt(b)} (half {fmt(b / 2 if b else None)}); "
          f"staircase tone (amplitude, floor) in codes: hevc_10bit "
          f"{[fmt(v) for v in ten['tone']]}, hevc {[fmt(v) for v in eight['tone']]}; distinct "
          f"10-bit Y codes on the middle row: hevc_10bit {ten['distinct']}, hevc "
          f"{eight['distinct']}; hevc {eight['probe']}, brand {eight['brand']!r}")
    return closed


def run_c1(client, clip):
    """C1: the H.264 clip at brightness −0.4 against max(0, its brightness-0
    render − 102), every colour channel within ±2. A deep-decoded frame
    arrives unclamped (spec §11 PR-2, −0.46…1.47); without `layerSample`'s
    `saturate` a channel above 1.0 reads 1.0 at brightness 0 (the output
    clamps) and above 0.6 at −0.4."""
    doc = Doc(client, "C1")
    made = [c for c in doc.movie(doc.first_track(), clip) if c is not None]
    base = doc.render(WORK / "c1-0.png")
    doc.step("set_video", clips=made, patch={"color": {"brightness": BRIGHTNESS}})
    took = [((c.get("video") or {}).get("color") or {}).get("brightness")
            for c in doc.project().get("clips") or [] if c.get("id") in made]
    dim = doc.render(WORK / "c1-dim.png")
    a, b = rgba(WORK / "c1-0.png"), rgba(WORK / "c1-dim.png")
    closed = doc.close()
    counts, white = {}, 0
    if a and b and len(a) == len(b):
        for i in range(len(a)):
            if i % 4 == 3:
                continue
            white += a[i] == 255
            d = abs(b[i] - max(0, a[i] - 102))
            counts[d] = counts.get(d, 0) + 1
    largest = max(counts) if counts else None
    check("C1 the H.264 clip at brightness −0.4: every colour channel within ±2 of "
          "max(0, its brightness-0 render − 102) — the source clamp holds a deep frame's "
          "values above 1.0", doc.ok and took == [BRIGHTNESS] and largest is not None
          and largest <= 2,
          f"fixture {doc.why or 'ok'}; brightness {took}; depths {png_depth(base)}/"
          f"{png_depth(dim)}; {white} channels read 255 at brightness 0; histogram |Δ|: "
          f"{short(dict(sorted(counts.items())))}")
    return closed


def ffprobe(path):
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt", "-of", "json", str(path)], 60)
    try:
        return (json.loads(ran["stdout"]).get("streams") or [{}])[0]
    except (ValueError, IndexError):
        return {}


def major_brand(path):
    """The file's `ftyp` major brand as ffprobe reads it, or None."""
    ran = bounded.run(["ffprobe", "-v", "error", "-show_entries", "format_tags=major_brand",
                       "-of", "json", str(path)], 60)
    try:
        return ((json.loads(ran["stdout"]).get("format") or {}).get("tags") or {}).get(
            "major_brand")
    except ValueError:
        return None


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
    record, closed = {"formats": tree_formats()}, True
    rendered = []
    for name in ("K1", "K2", "K3", "K4", "K5", "K6"):
        doc, t = k_scene(client, name, clip)
        png = doc.render(where / f"{name}.png", t)
        rendered.append((name, doc.why, digest(png)))
        closed = doc.close() and closed
    check("K CONTROL: K1–K6 rendered into DIR", all(not why and d for _, why, d in rendered)
          and len(record["formats"]) == 2,
          "; ".join(f"{n} {why or 'ok'} {d}" for n, why, d in rendered)
          + f"; this tree's formats {record['formats']}")
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


def against_ffmpeg(clip, renders):
    """Unscored (PR2): each K6 render's colour channels against ffmpeg's own
    decode of the clip's frame at 0.5 s (frame 15; BT.709, limited range,
    `accurate_rnd+full_chroma_int`) — which decode a reference decoder
    is nearer, for spec §11 PR-2's edge differences."""
    ref = decode(clip, "rgba", ["-vf", "select=eq(n\\,15)", "-sws_flags",
                                "bicubic+accurate_rnd+full_chroma_int"])
    if not ref or len(ref) != W * H * 4:
        return "against ffmpeg's decode (unscored): no reference frame"
    parts = []
    for label, data in renders.items():
        if not data or len(data) != len(ref):
            parts.append(f"{label} n/a")
            continue
        deltas = [abs(a - b) for i, (a, b) in enumerate(zip(data, ref)) if i % 4 != 3]
        parts.append(f"{label} mean |Δ| {sum(deltas) / len(deltas):.3f}, "
                     f"≥ 5 on {sum(d >= 5 for d in deltas)}, largest {max(deltas)}")
    return "against ffmpeg's decode (unscored): " + "; ".join(parts)


def run_compare(client, where):
    try:
        record = json.loads((where / "capture.json").read_text())
    except (OSError, ValueError):
        sys.exit(f"no capture at {where}; run `capture` on the control tree first")
    clip, closed = where / "k6.mp4", True
    then, now = record.get("formats") or PR0_FORMATS, tree_formats()
    same_output = then.get("output") == now.get("output")
    same_source = then.get("source") == now.get("source")
    print(f"  formats: control {then}, this tree {now}", flush=True)
    for name in ("K1", "K2", "K3", "K4", "K5", "K6"):
        if name not in selected:
            continue
        doc, t = k_scene(client, name, clip)
        doc.render(WORK / f"{name}.png", t)
        got, want = rgba(WORK / f"{name}.png"), rgba(where / f"{name}.png")
        closed = doc.close() and closed
        counts = histogram(got, want) if got and want else {}
        largest = max(counts) if counts else None
        # K1 is one opaque card: exact always. K2–K5 (no video) are exact
        # when the working depth is the control's (PR2 against PR1), within
        # ±2 across it (PR1 against PR0). K6 (video) is exact when the decode
        # is the control's, and across it (PR2 against PR1) its histogram is
        # recorded, not scored (spec §11 PR-2's ±1 on video).
        rule = ("exact" if name == "K1" or (name != "K6" and same_output)
                or (name == "K6" and same_source) else "recorded" if name == "K6" else "two")
        good = doc.ok and got is not None and want is not None and len(got) == len(want) and (
            got == want if rule == "exact" else rule == "recorded" or largest <= 2)
        extra = ""
        if name == "K6":
            extra = "\n       " + against_ffmpeg(clip, {"this tree": got, "DIR": want})
        check(f"{name} against the control: " + {
            "exact": "byte-identical", "two": "every channel within ±2",
            "recorded": "the histogram recorded (the decode moved, spec §11 PR-2)"}[rule], good,
              f"fixture {doc.why or 'ok'}; histogram |Δ|: channels {short(counts)}{extra}")
    if "E1" in selected:
        closed = run_e1(client, where, clip, record, same_source) and closed
    if "E2" in selected:
        closed = run_e2(client, where, clip, same_source) and closed
    return closed


# ---------------------------------------------------------------------------
# E1 — the h264 encoder's input (the orchestrator's ruling after PR0).


def build_encoder_probe():
    """`precision_encoder_probe.swift` over `sources_folder` (the tree's
    `app/Sources`, or a mutant copy's), beside that tree's `Compositor.metal`
    as `default.metallib` and `Blank.mp4`. (binary, None) or (None, why)."""
    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    entry = PROBE_DIR / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    binary = PROBE_DIR / "precision_encoder_probe"
    try:
        made = swift_build.build(sources=swift_build.app_sources(sources_folder) + [entry],
                                 output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc rc {error.rc if error.rc is not None else 'before running'}: "
                      f"{(error.diagnostics or ['(no output)'])[:6]}")
    print(f"  encoder probe: {'up to date' if made.reused else f'built in {made.seconds:.0f} s'}"
          f" from {sources_folder}", flush=True)
    resources = sources_folder.parent / "Resources"
    shader, air, library = (resources / "Shaders/Compositor.metal", PROBE_DIR / "Compositor.air",
                            PROBE_DIR / "default.metallib")
    library.unlink(missing_ok=True)
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
                       300)
    if step["rc"] == 0:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o", str(library)],
                           300)
    if step["rc"] != 0 or not library.exists():
        return None, f"the shader did not build: {step['stderr'][-400:]}"
    shutil.copy2(resources / "Blank.mp4", PROBE_DIR / "Blank.mp4")
    return binary, None


def handed_frames(client, where, clip, preset, prefix, same_source):
    """K6's and K3's scenes saved, the encoder probe's frames handed to
    `preset`'s encoder against DIR's renders: (good, detail, closed). K6's
    bound is 0 when this tree decodes as the control did; across a decode
    change (PR2 against PR1) it is the largest |Δ| of this tree's own K6
    render against DIR's — the re-baseline rule's "within K6's histogram" —
    and the handed frame must equal that render byte for byte."""
    closed, frames, bounds, own = True, [], {"K6": 0, "K3": 1}, {}
    for name in ("K6", "K3"):
        doc, t = k_scene(client, name, clip)
        if name == "K6" and not same_source:
            doc.render(WORK / f"{prefix}-K6.png", t)
            own = rgba(WORK / f"{prefix}-K6.png")
            want = rgba(where / "K6.png")
            counts = histogram(own, want) if own and want and len(own) == len(want) else {}
            bounds["K6"] = max(counts) if counts else None
        doc.step("save_project")
        frames.append({"tag": name, "package": str(doc.path), "tick": t, "preset": preset,
                       "raw": str(WORK / f"{prefix}-{name}.bgra"), "why": doc.why})
        closed = doc.close() and closed
    binary, why = build_encoder_probe()
    answer = {}
    if binary is not None:
        request, out = WORK / f"{prefix}-request.json", WORK / f"{prefix}-answer.json"
        request.write_text(json.dumps({"frames": frames,
                                       "fonts": str(sources_folder.parent / "Resources/Fonts")}))
        ran = bounded.run([str(binary), str(request), str(out)], 300, cwd=str(PROBE_DIR),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
        try:
            answer = {row["tag"]: row for row in json.loads(out.read_text())["frames"]}
        except (OSError, ValueError, KeyError):
            why = f"no answer (rc {ran['rc']}, expired {ran['expired']}): {ran['stderr'][-300:]}"
    good, lines = binary is not None and bool(answer), []
    for frame in frames:
        name = frame["tag"]
        got = answer.get(name, {})
        want = rgba(where / f"{name}.png")
        handed = None
        if got.get("format") == "BGRA" and got.get("raw") and Path(got["raw"]).exists():
            bgra = Path(got["raw"]).read_bytes()
            handed = bytearray(bgra)
            handed[0::4], handed[2::4] = bgra[2::4], bgra[0::4]
            handed = bytes(handed)
        counts = histogram(handed, want) if handed and want and len(handed) == len(want) else {}
        largest = max(counts) if counts else None
        bound = bounds[name]
        ok = (frame["why"] is None and handed is not None and largest is not None
              and bound is not None and largest <= bound)
        if name == "K6" and not same_source:
            # Across a decode change the handed frame must also be this
            # tree's own 8-bit render exactly: the rounding is the render's.
            mine = histogram(handed, own) if handed and own and len(handed) == len(own) else {}
            ok = ok and mine == {0: len(handed or b"")}
            lines.append(f"K6 handed against this tree's own render (byte-identical): {short(mine)}")
        good = good and ok
        claim = ("byte-identical" if bound == 0 and name == "K6" else
                 f"within ±{bound}" + (" (this tree's K6 render against DIR's)"
                                       if name == "K6" else ""))
        lines.append(f"{name} ({claim}): "
                     f"{'ok' if ok else 'FAIL'}; fixture {frame['why'] or 'ok'}; form "
                     f"{got.get('form')}, handed {got.get('format')} {got.get('width')}×"
                     f"{got.get('height')} at {got.get('time')} s"
                     + (f", error {got['error']}" if got.get("error") else "")
                     + f"; histogram |Δ| against DIR's render: {short(counts)}")
    detail = ((f"probe {why or 'ok'}\n       " if why or binary is None else "")
              + "\n       ".join(lines))
    return good, detail, closed


def run_e1(client, where, clip, record, same_source):
    """E1: the frames handed to the h264 encoder against DIR's renders; the
    encoded K6 file printed, unscored."""
    good, detail, closed = handed_frames(client, where, clip, "h264", "e1", same_source)
    pair, fixture, ok = h264_pair(client, clip, WORK, ("e1",))
    closed = ok and closed
    encoded = pair[0][1]
    a = decode(where / "e0-a.mp4", "rgb24", frames=None)
    unscored = (f"the encoded file (unscored): E1 {digest(encoded)} against E0 "
                f"{record.get('E0', {}).get('a')} / {record.get('E0', {}).get('b')}, "
                f"|Δ| against E0 a {short(histogram(encoded, a)) if encoded and a and len(encoded) == len(a) else 'n/a'}")
    check("E1 the frame ExportWriter hands the h264 encoder is 32BGRA and equals DIR's 8-bit frame "
          "(K6 byte-identical, or across a decode change within K6's own |Δ| and byte-identical "
          "to this tree's render; K3, blended, within ±1 — the compositor's own ±1 at 16-bit "
          "float)",
          good, detail + "\n       " + unscored)
    return closed


def run_e2(client, where, clip, same_source):
    """E2: the frames handed to the hevc (Main) encoder against DIR's renders."""
    good, detail, closed = handed_frames(client, where, clip, "hevc", "e2", same_source)
    check("E2 the frame ExportWriter hands the hevc (Main) encoder is 32BGRA and equals DIR's "
          "8-bit frame (K6 byte-identical, or across a decode change within K6's own |Δ| and "
          "byte-identical to this tree's render; K3, blended, within ±1) — fed half-float frames it "
          "encoded the ramp at 9.04 steps RMS against PR0's 6.46", good, detail)
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


def m1_measure(binary, kind, height, label=""):
    """One M1 export, on an instance of its own so its lifetime
    `phys_footprint_peak` is this fixture's; (its figures, its log)."""
    log = WORK / f"m1-{kind}-{height}{label}.log"
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
        if key == "heavy-1080" and (now.get("average_ms") or 0) >= STOP_MS:
            stops.append(f"heavy 1080p average {now.get('average_ms')} ms ≥ 8 ms")
        print(f"       {line}", flush=True)
    check("M1 measured beside the control (memory printed and recorded; the owner retired the "
          "+532 MB stop, spec §11 PR-1), and no frame-time stop (1080p heavy average < 8 ms)",
          measured and not stops,
          f"stops: {stops or 'none'}")
    return all(f["closed"] for f in figures.values())


def run_ab(tree_binary, copy_binary, rounds):
    """MA (PR2's review, recorded in PR3): the heavy 2160p fixture exported on
    this tree's Release app and on the `decode-8bit` copy's, alternated
    (ABBA…) `rounds` times so both see the same load. The compositor averages,
    their medians and the deep decode's share."""
    runs, logs = {"tree": [], "decode-8bit": []}, []
    for n in range(rounds):
        order = [("tree", tree_binary), ("decode-8bit", copy_binary)]
        for label, binary in (order if n % 2 == 0 else order[::-1]):
            figures, log = m1_measure(binary, "heavy", 2160, f"-{label}-{n}")
            logs.append(log)
            runs[label].append(figures)
            print(f"  round {n + 1} {label}: average {figures.get('average_ms')} ms, worst "
                  f"{figures.get('worst_ms')} ms, export {figures.get('export_s')} s, "
                  f"{figures.get('windows')} windows, fixture {figures['fixture']}", flush=True)
    measured = all(f["fixture"] == "ok" and f["exported"] and f["windows"] > 0
                   for one in runs.values() for f in one)
    median = {k: sorted(f.get("average_ms") or 0 for f in v)[len(v) // 2] for k, v in runs.items()}
    export = {k: sorted(f.get("export_s") or 0 for f in v)[len(v) // 2] for k, v in runs.items()}
    share = (round(median["tree"] / median["decode-8bit"], 3)
             if median["decode-8bit"] else None)
    check("MA the heavy 2160p export's compositor average, this tree (64RGBAHalf sources) "
          "against the decode-8bit copy (32BGRA), alternated on one host load", measured,
          f"medians {median} ms (tree ÷ copy {share}); export medians {export} s; "
          f"averages tree {[f.get('average_ms') for f in runs['tree']]}, copy "
          f"{[f.get('average_ms') for f in runs['decode-8bit']]}")
    return all(f["closed"] for one in runs.values() for f in one), logs


def run_core_mutant(name):
    """A core mutant: the copy's `core/` made its own, the anchors replaced,
    and `cargo test` of the two export files in it (row CT). No app."""
    from hevc_alpha_proof import own_core
    dest = BASE / "mutant"
    made, reason = tree_copy.make_copy(str(dest), agent=False)
    atexit.register(tree_copy.remove_tree, str(dest))
    if made is None:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    copy = Path(made)
    reason = own_core(copy)
    if reason is None:
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            reason = f"the copy's core/tests could not be linked: {error}"
    reason = reason or replace_anchors(copy, name)
    if reason:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "export",
                       "--test", "export_hevc_10bit"], 900, cwd=str(copy / "core"))
    out = ran["stdout"] + ran["stderr"]
    if ran["expired"] or "test result:" not in out:
        print(f"mutant {name}: the control could not be performed — cargo rc {ran['rc']}, "
              f"expired {ran['expired']}: {out[-600:]}")
        return 2
    failed = [t for t in CORE_TESTS if re.search(rf"^test {t} \.\.\. FAILED$", out, re.M)]
    every = re.findall(r"^test (\w+) \.\.\. FAILED$", out, re.M)
    print(("  ok   " if ran["rc"] == 0 else "  FAIL ") + "CT cargo test --test export --test "
          f"export_hevc_10bit in the copy's core\n       failed: {every}", flush=True)
    caught = ran["rc"] != 0 and failed == list(CORE_TESTS)
    print(("MUTANT PASS" if caught else "MUTANT FAILURE") + f": {name} — CT "
          + ("FAILED" if ran["rc"] != 0 else "passed")
          + f"; named tests failed: {failed} (want {list(CORE_TESTS)})")
    return 0 if caught else 1


def selftest():
    """S1–S3: `app_tree` over scratch trees, and main's refusal; no app."""
    results = []

    def row(name, good, detail):
        results.append(bool(good))
        print(("  ok   " if good else "  FAIL ") + name + f"\n       {detail}", flush=True)

    print("precision (B94) — the selftest: which sources an app's formats are read from")
    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        tree = scratch / "tree"
        (tree / "app/Sources").mkdir(parents=True)
        (tree / "app/Sources/Compositor.swift").write_text(
            "    static let outputPixelFormat: OSType = kCVPixelFormatType_TEST_OUT\n"
            "    static let sourcePixelFormat: OSType = kCVPixelFormatType_TEST_SRC\n")
        inside = tree / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
        inside.parent.mkdir(parents=True)
        inside.write_text("")
        found = app_tree(inside)
        formats = tree_formats(found / "app/Sources") if found else {}
        row("S1 an app under a tree's build/Build/Products reads THAT tree's formats",
            found == tree and formats == {"output": "kCVPixelFormatType_TEST_OUT",
                                          "source": "kCVPixelFormatType_TEST_SRC"},
            f"tree {found}; formats {formats}")
        outside = scratch / "elsewhere/Reelcut.app/Contents/MacOS/Reelcut"
        outside.parent.mkdir(parents=True)
        outside.write_text("")
        bare = scratch / "bare/build/Build/Products/Debug/Reelcut.app/Contents/MacOS/Reelcut"
        bare.parent.mkdir(parents=True)
        bare.write_text("")
        ran = bounded.run([sys.executable, str(Path(__file__).resolve()), "--app", str(outside),
                           "--only", "D1"], 120)
        refused = "is not a product of a tree" in ran["stdout"]
        row("S2 an app outside any tree (or under a build folder with no app/Sources) is "
            "refused, exit 2, before any launch",
            app_tree(outside) is None and app_tree(bare) is None and ran["rc"] == 2
            and refused and "instance PID" not in ran["stdout"],
            f"outside {app_tree(outside)}; bare {app_tree(bare)}; main rc {ran['rc']}: "
            f"{ran['stdout'].strip().splitlines()[-1:] if ran['stdout'].strip() else ran['stderr'][-200:]}")
    default = proof_app.binary()
    row("S3 the default app (no --app) is this tree's, so its formats are this tree's",
        app_tree(default) == ROOT, f"{default} → {app_tree(default)}")
    print(f"{sum(results)}/{len(results)}")
    return 0 if all(results) else 1


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


def replace_anchors(copy, name):
    """Every anchor of `name` replaced in `copy`, each found exactly once (in
    order, so a later anchor sees an earlier one's text); None, or why not."""
    for path, anchor, replacement in MUTANTS[name]["anchors"]:
        target = copy / path
        if not target.resolve().is_relative_to(BASE / "mutant"):
            return f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    return None


def build_mutant(name, release_only=None):
    """A copy of the tree with every anchor of `name` replaced (each found
    once), built by `tree_copy.build_app`. (app bundle, copy) or (None, why)."""
    made, reason = tree_copy.make_copy(str(BASE / "mutant"))
    atexit.register(tree_copy.remove_tree, str(BASE / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    reason = replace_anchors(copy, name)
    if reason:
        return None, reason
    print(f"  building the copy ({len(MUTANTS[name]['anchors'])} anchor(s) replaced, each found "
          "once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND, release_only=release_only)
    return (app, copy) if app is not None else (None, reason)


def mutant_pf(copy):
    """`preview_refresh_probe.py --sources <copy>/app/Sources`: whether its PF
    row passed (None when the probe printed no PF line), and the line."""
    ran = bounded.run([sys.executable, str(ROOT / "tools/proof/preview_refresh_probe.py"),
                       "--sources", str(copy / "app/Sources")], 900)
    lines = [line.strip() for line in ran["stdout"].splitlines()
             if line.strip().startswith(("ok   PF", "FAIL PF", "skip PF"))]
    for line in lines:
        if line.startswith("ok   PF"):
            return True, line
        if line.startswith("FAIL PF"):
            return False, line
    return None, (lines or [f"no PF line (rc {ran['rc']}): {ran['stdout'][-300:]}"])[0]


def main_ab(rounds):
    """`--measure ab --mutant decode-8bit`: MA and Z1 (release-only)."""
    global selected
    selected = {"MA", "Z1"}
    tree_binary = Path(proof_app.binary(release_only=RELEASE_ONLY))
    print(f"precision (B94) — --measure ab: the heavy 2160p export, {tree_binary} against a "
          f"Release build of the decode-8bit copy, {rounds} rounds", flush=True)
    if not tree_binary.is_file():
        print(f"instrument failure: no app binary at {tree_binary}")
        return 2
    app, copy = build_mutant("decode-8bit", release_only=RELEASE_ONLY)
    if app is None:
        print(f"instrument failure: the decode-8bit copy did not build — {copy}")
        return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    if prores_clip(2160) is None:
        print("instrument failure: ffmpeg did not make M1's 2160p movie")
        return 2
    try:
        closed, logs = run_ab(tree_binary, app / "Contents/MacOS/Reelcut", rounds)
    except Exception as error:  # a row that could not run is a failure
        print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
        closed, logs = False, []
    found = [line for log in logs for line in complaints(log)]
    check("Z1 CONTROL: the projects close and no log holds a `Reelcut: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    passed = sum(1 for name in ("MA", "Z1") if rows.get(name))
    print(f"{passed}/2")
    return 0 if passed == 2 else 1


def main():
    global selected, sources_folder
    parser = argparse.ArgumentParser()
    parser.add_argument("--app")
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--control", help="a capture DIR whose P1 figure the rows print")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--rounds", type=int, default=3, help="--measure ab's rounds")
    parser.add_argument("mode", nargs="?", choices=("capture", "compare", "ab"))
    parser.add_argument("dir", nargs="?")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    ab = args.mode == "ab"
    if ab and not (args.measure and args.mutant == "decode-8bit" and args.dir is None
                   and not args.only and args.rounds >= 1):
        parser.error("ab is `--measure ab --mutant decode-8bit [--rounds N]`")
    if not ab and ((args.mode is None) != (args.dir is None)
                   or (args.measure and args.mode is None)):
        parser.error("capture and compare take DIR; --measure takes capture or compare DIR")
    mutant = MUTANTS.get(args.mutant)
    if mutant and not ab and (args.measure or args.only or args.mode not in (
            None if mutant["mode"] in ("rows", "core") else "compare",)):
        parser.error(f"--mutant {args.mutant} runs {mutant['mode']}"
                     + (" DIR" if mutant["mode"] == "compare" else "") + " alone")
    if mutant and mutant["mode"] == "core":
        print(f"precision (B94) — the {args.mutant} core MUTANT (CT must FAIL, naming "
              f"{', '.join(CORE_TESTS)})", flush=True)
        return run_core_mutant(args.mutant)
    if ab:
        return main_ab(args.rounds)
    universe = (["M1", "Z1"] if args.measure else CAPTURE_ROWS if args.mode == "capture"
                else COMPARE_ROWS if args.mode == "compare" else ROWS)
    selected = set(universe)
    if mutant:
        selected = set(mutant["rows"]) | {"Z1"}
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()} | {"Z1"}
        unknown = selected - set(universe)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if mutant:
        print(f"precision (B94) — the {args.mutant} MUTANT ({', '.join(mutant['rows'])}"
              f"{', PF' if mutant.get('pf') else ''} must FAIL)", flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        args.app, sources_folder = str(app), copy / "app/Sources"
    binary = Path(args.app or proof_app.binary(
        release_only=RELEASE_ONLY if args.measure else None))
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    tree = app_tree(binary)
    if tree is None:
        print(f"instrument failure: {binary} is not a product of a tree (a build/Build/Products "
              "under a folder holding app/Sources/Compositor.swift), so the formats it was "
              "built from cannot be read")
        return 2
    sources_folder = tree / "app/Sources"
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
    if mutant:
        named = {name: rows.get(name) for name in mutant["rows"]}
        if mutant.get("pf"):
            named["PF"], line = mutant_pf(Path(sources_folder).parents[1])
            print(f"  preview_refresh_probe on the copy: {line}", flush=True)
        if None in named.values() or not rows.get("Z1"):
            print(f"mutant {args.mutant}: the control could not be performed — {named}, "
                  f"Z1 {rows.get('Z1')}")
            return 2
        caught = not any(named.values())
        print(("MUTANT PASS" if caught else "MUTANT FAILURE") + f": {args.mutant} — "
              + ", ".join(f"{k} {'passed' if v else 'FAILED'}" for k, v in named.items()))
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
