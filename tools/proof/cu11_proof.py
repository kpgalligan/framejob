#!/usr/bin/env python3
"""Road map "creator-jobs" CU11 — motion blur (spec §11 CU-110…CU-119).

    python3 tools/proof/cu11_proof.py [capture DIR | compare DIR] [--only K1,Z1] [--app PATH]

Over MCP on one launch (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a scratch
`CFFIXED_USER_HOME`, each document closed after its row.

**Modes.** `capture DIR` builds MB4's fixture in DIR (a version-41 package and its media) and
writes `DIR/mb4.json` — the sha-256 of three `render_frame` PNGs and the per-frame md5 of a
1 s `prores_4444` export — and scores nothing else; it is run once on a Release build of
CU11b's toll commit, before any product edit (CU-119). `compare DIR` runs every row and MB4
against that capture. With no mode, every row but MB4.

CU11a's rows:
- K1 `set_video`'s `motion_blur` (CU-113, CU-111): on a new project, `add_media` an image
  descriptor (a 64 × 48 PNG the proof writes) and `add_clip`; `{motion_blur: 0.5}` reads back
  0.5 through `get_project`; `{motion_blur: 1.5}` is an error carrying "video.motion_blur must
  be between 0 and 1, not 1.5" and leaves the project unchanged; `{motion_blur: 0}` removes the
  key; the clip `nest`ed, the nest clip's `{motion_blur: 0.5}` is refused "clip N shows a nest
  and cannot take motion blur: set it on the clips inside"; an `add_adjustment_clip`'s is refused
  "clip N is an adjustment clip and cannot take motion blur".
- Z1 every launch's `grep "Frame Job: "` prints nothing.

CU11b's rows (spec §11 CU-119). A picture row reads 16-bit `render_frame` PNGs through ffmpeg's
`rgba64le` and compares in 16-bit units at ±257 (1/255) per channel per pixel. An SDR frame of
8-bit sources is written 8-bit, which quantises each of the 16 sharp renders on its own (MB1
missed by 1.12/255 so), so every picture fixture holds a 16-bit still — the checker itself, or
a 2 × 2 dot far off the canvas — and `render_frame` reads the frame deep (PR-9's
`DeepStillFrame`). A canvas is 320 × 180 at 30 fps; t is 0.5 s; o_k = round(((2k + 1 −
16)/32)·0.5·20,000), k = 0…15, rounded half away from zero as the core's `shutter_offsets`
rounds. The reference is the mean of 16 sharp renders (motion_blur 0), each AT t with what
sample k reads at t + o_k: `render_frame` draws the canvas's frame grid only (a sub-frame t
draws its frame), so the zoom's action is removed and the clip's base scale set to the
action's scale at t + o_k (`ease_in_out` is u²(3 − 2u), `actions.rs`), and the cursor file is
swapped (`set_media_cursor`) for one whose moves are o_k earlier.
- MB1 a 320 × 180 black-and-white 16-px checker image clip under an `ease_in_out` action over
  [0, 1 s) ending at scale 2, `motion_blur` 0.5: `render_frame` at t equals the reference, and
  (the control) differs from the sharp frame at t by more than 8/255 somewhere.
- MB1b MB1 over an opaque 0.2-grey plate (`add_background`) with `blend: add`, the checker's
  greys 6554 and 45875 of 65535 (0.1 and 0.7), so no plate-plus-clip sum passes 1 and `add`'s clamp never
  acts: only there is the averaged picture added once the mean of the sharp `add` renders.
- MB2 an unmoving image clip, and MB5's fixture at 1.5 s (the pointer at rest): `motion_blur`
  0.5 and 0 give byte-identical PNGs.
- MB3 MB1's project (its own copy) exported as `prores_4444`: frame 15 (ffmpeg `rgb48le`) within ±8/255 of
  `render_frame` at t, and (the control) more than 24/255 from the sharp frame somewhere.
- MB5 a `color=` movie (raw ARGB) whose cursor file moves the pointer at 600 px/s along y = 90
  from 0.3 s to 0.75 s (a move every 8,300 µs, 249 file units each, so the path is exactly
  linear), `cursor {smoothing: 0, clicks: "none", style: "arrow"}`, no action: at t
  `motion_blur` 0.5 equals the reference. MB6 MB5 plus MB1's zoom action.
- K2 `auto_zoom` (follow off) on cu7's click fixture (`cu7_proof.cursor_body` of its Z1
  clicks over a 640 × 360 `testsrc` movie, canvas 640 × 360): the clip's `motion_blur` 0.5 and
  `blurred` 1; a clip already at 0.3 kept at 0.3 with `blurred` 0; `motion_blur: 0` sets none;
  `motion_blur: 1.5` refused "Motion_blur is 1.5; it runs 0–1.".
- K3 `snapshot_ui` of the editor with the clip selected and Clip ▸ Picture shown: a "Motion
  Blur" row below "Blend" in the layout dump.
- K4 Clip ▸ Auto Zoom… by `perform_menu_item` on a launch with `-RCDevAutoZoomAccept YES`: the
  clip's `motion_blur` 0.5; on a launch adding `-FrameJobAutoZoomMotionBlur NO`, zoom actions
  and no `motion_blur`.
- MB4 (`compare` only) the capture's package opened by this build: its three `render_frame`
  PNGs and its 1 s `prores_4444` export's per-frame md5 byte-identical to the capture's. The
  package (320 × 180, 30 fps, 1 s): a grey plate on the back track; a `testsrc2` movie (raw
  ARGB) with its cursor file (two clicks) drawing ripples, `blend: screen`, a reflection, at
  scale 0.6 under a zoom action; an image clip with a drop shadow. Written by this build, its
  `project.json`'s `version` set to 41 (it carries no key of 42 or 43).

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import cu7_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

WORK = ROOT / "tools/proof/work/cu11"
HOME = WORK / "home"
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 300
PNG_W, PNG_H = 64, 48
W, H = 320, 180

APP_ROWS = ["K1", "MB1", "MB1b", "MB2", "MB3", "MB5", "MB6", "K2", "K3"]
ACCEPT_ROWS = ["K4"]
ROWS = APP_ROWS + ACCEPT_ROWS + ["MB4", "Z1"]
T = SEC // 2
SAMPLES = 16
SHUTTER = 0.5
TOLERANCE = 257                 # 1/255 in 16-bit units
MB3_TOLERANCE = 8 * 257
CONTROL = 8 * 257               # MB1's sharp frame differs by more than this somewhere
MB3_CONTROL = 24 * 257

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, *names):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for name in names:
            check(name, False, f"{type(error).__name__}: {error}")
        return None


def png(path, width, height, pixel, deep=False):
    """An RGB PNG at `path`, `pixel(x, y)` the (r, g, b) of each pixel: 8-bit, or with `deep`
    16-bit (each value 0…65535, big-endian)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if deep:
        rows = b"".join(
            b"\x00" + b"".join(struct.pack(">H", v) for x in range(width) for v in pixel(x, y))
            for y in range(height))
    else:
        rows = b"".join(
            b"\x00" + bytes(v for x in range(width) for v in pixel(x, y))
            for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 16 if deep else 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    return path


def picture():
    """A 64×48 PNG: a red-to-blue ramp across, green down."""
    return png(WORK / "media" / "picture.png", PNG_W, PNG_H,
               lambda x, y: (x * 255 // (PNG_W - 1), y * 255 // (PNG_H - 1),
                             255 - x * 255 // (PNG_W - 1)))


def ffmpeg(args, seconds=300):
    run = subprocess.run(["ffmpeg", "-v", "error", "-y", *args], capture_output=True,
                         timeout=seconds, env=bounded.child_env())
    if run.returncode != 0:
        raise RuntimeError("ffmpeg: " + run.stderr.decode(errors="replace")[-400:])


def raw_movie(path, source):
    """`source` (an ffmpeg lavfi graph) as uncompressed ARGB tagged `raw `, which AVFoundation
    decodes byte-exact (`cursor_layer_proof.make_clean`)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        ffmpeg(["-f", "lavfi", "-i", source, "-c:v", "rawvideo", "-pix_fmt", "argb",
                "-tag:v", "raw ", str(path)])
    return path


def framemd5(movie):
    """The per-frame md5 of `movie`'s video, in order, or []."""
    try:
        text = subprocess.run(["ffmpeg", "-v", "error", "-i", str(movie), "-map", "0:v",
                               "-f", "framemd5", "-"], capture_output=True, text=True,
                              timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    return [line.rsplit(",", 1)[1].strip() for line in text.splitlines()
            if line and not line.startswith("#")]


class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    @classmethod
    def new(cls, client, path, size=(W, H)):
        path = Path(path)
        if path.exists():
            shutil.rmtree(path)
        client.call("new_project", path=str(path))
        doc = cls(client, path)
        doc.call("set_canvas", width=size[0], height=size[1], fps=[30, 1])
        return doc

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def added(self, tool, **arguments):
        """The id of the one clip `tool` adds."""
        before = {c["id"] for c in self.project()["clips"]}
        self.call(tool, **arguments)
        return next(c["id"] for c in self.project()["clips"] if c["id"] not in before)

    def track(self, front=True):
        """A new track at the front (the back with `front` False); its id."""
        before = {t["id"] for t in self.project()["tracks"]}
        if front:
            self.call("add_track")
        else:
            self.call("add_track", index=0)
        return next(t["id"] for t in self.project()["tracks"] if t["id"] not in before)

    def image(self, path, width, height):
        """`add_media` of a PNG and an `add_clip` of it on a new front track, 1 s long."""
        before = {m["id"] for m in self.project()["media"]}
        self.call("add_media", descriptor={
            "path": str(path), "kind": "image", "width": width, "height": height})
        media = next(m["id"] for m in self.project()["media"] if m["id"] not in before)
        clip = self.added("add_clip", track=self.track(), media=media, at=0)
        self.call("trim_end", clip=clip, to=SEC)
        return clip

    def movie(self, path):
        """`import_media` of a movie (its cursor file beside attaches) on a new front track."""
        media = self.call("import_media", path=str(path))["media"]
        return self.added("add_clip", track=self.track(), media=media, at=0)

    def render(self, t, out):
        out = Path(out)
        if out.exists():
            out.unlink()
        self.call("render_frame", t=t, path=str(out))
        return out if out.exists() else None

    def export(self, preset, out):
        out = Path(out)
        if out.exists():
            out.unlink()
        self.client.export_with({"project": str(self.path), "preset": preset, "path": str(out)})
        return out if out.exists() else None

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def error_of(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


# ---- CU11a ---------------------------------------------------------------------

def k1(client):
    path = WORK / "k1.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    try:
        doc.call("add_media", descriptor={
            "path": str(picture()), "kind": "image", "width": PNG_W, "height": PNG_H})
        media = next(m["id"] for m in doc.project()["media"] if m["kind"] == "image")
        tracks = doc.project()["tracks"]
        if not tracks:
            doc.call("add_track")
            tracks = doc.project()["tracks"]
        track = tracks[0]["id"]
        clip = doc.added("add_clip", track=track, media=media, at=0)

        doc.call("set_video", clips=[clip], patch={"motion_blur": 0.5})
        stored = (doc.clip(clip).get("video") or {}).get("motion_blur")
        check("K1", stored == 0.5, f"set 0.5: get_project reads {stored}")

        before = doc.project()
        message = error_of(lambda: doc.call(
            "set_video", clips=[clip], patch={"motion_blur": 1.5}))
        sentence = "video.motion_blur must be between 0 and 1, not 1.5"
        check("K1", message is not None and sentence in message, f"1.5: {message}")
        check("K1", doc.project() == before, "1.5 leaves the project unchanged")

        doc.call("set_video", clips=[clip], patch={"motion_blur": 0})
        video = doc.clip(clip).get("video") or {}
        check("K1", "motion_blur" not in video, f"0 removes the key: video {video}")

        doc.call("add_track")
        upper = next(t["id"] for t in doc.project()["tracks"] if t["id"] != track)
        adjustment = doc.added("add_adjustment_clip", track=upper, at=0, duration=SEC)
        message = error_of(lambda: doc.call(
            "set_video", clips=[adjustment], patch={"motion_blur": 0.5}))
        sentence = f"clip {adjustment} is an adjustment clip and cannot take motion blur"
        check("K1", message is not None and sentence in message, f"adjustment: {message}")

        doc.call("nest", clips=[clip])
        nest = next(c["id"] for c in doc.project()["clips"]
                    if c["source"]["kind"] == "nest")
        message = error_of(lambda: doc.call(
            "set_video", clips=[nest], patch={"motion_blur": 0.5}))
        sentence = (f"clip {nest} shows a nest and cannot take motion blur: "
                    "set it on the clips inside")
        check("K1", message is not None and sentence in message, f"nest: {message}")
    finally:
        doc.close()


# ---- pictures ------------------------------------------------------------------

def raw(path, pix, extra=()):
    try:
        return subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), *extra,
                               "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pix, "-"],
                              capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return b""


def samples16(data, deep):
    """Raw ffmpeg bytes as a list of 16-bit levels (8-bit ones ×257)."""
    if deep:
        return list(struct.unpack(f"<{len(data) // 2}H", data))
    return [v * 257 for v in data]


def frame16(path):
    """A `render_frame` PNG as RGBA in 16-bit units, or None."""
    if path is None:
        return None
    depth = Path(path).read_bytes()[24]
    deep = depth == 16
    data = raw(path, "rgba64le" if deep else "rgba")
    if len(data) != W * H * 4 * (2 if deep else 1):
        return None
    return samples16(data, deep)


def movie_frame16(path, index):
    """Frame `index` of a movie as RGB in 16-bit units (`rgb48le`), or None."""
    data = raw(path, "rgb48le", ["-vf", f"select=eq(n\\,{index})", "-fps_mode", "passthrough"])
    if len(data) != W * H * 6:
        return None
    return samples16(data, True)


def rgb_of(rgba):
    return [v for i, v in enumerate(rgba) if i % 4 != 3]


def mean(pictures):
    n = len(pictures)
    return [sum(values) / n for values in zip(*pictures)]


def worst(a, b):
    """The largest per-channel difference, and where (pixel index)."""
    if a is None or b is None or len(a) != len(b):
        return None, None
    best, at = 0.0, None
    for i, (x, y) in enumerate(zip(a, b)):
        d = abs(x - y)
        if d > best:
            best, at = d, i
    return best, at


def offsets():
    """The core's centred sub-frame offsets for MB's shutter (`shutter_offsets`)."""
    span = SHUTTER * FRAME
    out = []
    for k in range(SAMPLES):
        v = (2 * k + 1 - SAMPLES) / (2 * SAMPLES) * span
        out.append(int(abs(v) + 0.5) * (1 if v >= 0 else -1))
    return out


def levels(value):
    return f"{value / 257:.2f}/255" if value is not None else "none"


def checker(path, dark, light, size=16):
    """A W × H 16-bit grey checker of `size`-px squares, `dark` and `light` 0…65535. 16-bit, so
    the frame it is in is read deep and `render_frame` writes a 16-bit PNG (PR-9's
    `DeepStillFrame`): an 8-bit frame quantises each of the 16 sharp renders on its own."""
    return png(path, W, H, lambda x, y: (dark,) * 3 if ((x // size) + (y // size)) % 2 == 0
               else (light,) * 3, deep=True)


def deep_dot(doc):
    """A 2 × 2 16-bit still far off the canvas, never moving: in the frame, it makes
    `render_frame` read the frame deep and write a 16-bit PNG, and draws nothing."""
    path = png(WORK / "media" / "dot.png", 2, 2, lambda x, y: (65535, 0, 0), deep=True)
    clip = doc.image(path, 2, 2)
    doc.call("set_video", clips=[clip], patch={"x": 2000.0, "y": 2000.0})
    return clip


def smoothstep(u):
    """`ease_in_out` (`actions.rs`'s `ease`): u²(3 − 2u)."""
    return u * u * (3.0 - 2.0 * u)


def zoom_scale(t):
    """MB1's action's scale at project tick `t`: 1 → 2 over [0, 1 s), `ease_in_out`."""
    u = min(max(t / SEC, 0.0), 1.0)
    return 1.0 + smoothstep(u)


class Picture(Doc):
    """A 320 × 180, 30 fps document for the picture rows."""

    def zoom(self, clip):
        """MB1's action: [0, 1 s), `ease_in_out`, ending at scale 2; its id."""
        self.call("add_action", clip=clip, at=0, duration=SEC)
        action = self.clip(clip)["actions"][0]["id"]
        self.call("set_action", clip=clip, action=action, curve="ease_in_out")
        self.call("set_action_end", clip=clip, action=action, patch={"video": {"scale": 2.0}})
        return action

    def blur(self, clip, value):
        self.call("set_video", clips=[clip], patch={"motion_blur": value})

    def shot(self, t, tag):
        return self.render(t, WORK / f"{self.path.stem}-{tag}-{t}.png")

    def blurred_and_sharp(self, clip, tag):
        """(the frame at T with `motion_blur` 0.5, the frame at T with 0); the clip left at 0."""
        self.blur(clip, SHUTTER)
        blurred = frame16(self.shot(T, f"{tag}-blurred"))
        self.blur(clip, 0)
        return blurred, frame16(self.shot(T, f"{tag}-sharp-t"))

    def reference(self, clip, tag, action=None, pointer=None):
        """The mean of the 16 sharp frames, each drawn at T with what the shutter's sample k
        reads at T + offset k: render_frame draws the canvas's frame grid only (it reads the
        composition at a frame), so a sub-frame time is drawn as its placement — `action`
        removed and the clip's base scale set to the action's scale there — and its pointer —
        the media's cursor file swapped for one whose moves are `offset` earlier. None when a
        render failed."""
        if action is not None:
            self.call("remove_action", clip=clip, action=action)
        sharp = []
        for k, o in enumerate(offsets()):
            if action is not None:
                self.call("set_video", clips=[clip], patch={"scale": zoom_scale(T + o)})
            if pointer is not None:
                media, folder = pointer
                path = folder / f"pointer-{k}.fjcursor"
                path.write_text(json.dumps(moving_cursor(shift_ticks=o)))
                self.call("set_media_cursor", media=media,
                          cursor={"path": str(path), "in_picture": False})
            sharp.append(frame16(self.shot(T, f"{tag}-sample{k}")))
        if any(s is None for s in sharp):
            return None
        return mean(sharp)


def score_mean(name, blurred, reference, what):
    gap, where = worst(blurred, reference)
    check(name, gap is not None and gap <= TOLERANCE,
          f"{what}: blurred against the mean of {SAMPLES} sharp renders, worst {levels(gap)} "
          f"at pixel {None if where is None else where // 4} (≤ 1/255)")
    return gap


def control(name, blurred, sharp, bound, what):
    gap, _ = worst(blurred, sharp)
    check(name, gap is not None and gap > bound,
          f"control: {what} differs by {levels(gap)} (> {bound // 257}/255)")


def mb1(client):
    doc = Picture.new(client, WORK / "mb1.framejob")
    try:
        clip = doc.image(checker(WORK / "media" / "checker.png", 0, 65535), W, H)
        action = doc.zoom(clip)
        blurred, sharp = doc.blurred_and_sharp(clip, "mb1")
        reference = doc.reference(clip, "mb1", action=action)
        score_mean("MB1", blurred, reference, "a 2× ease_in_out zoom at 0.5 s")
        control("MB1", blurred, sharp, CONTROL, "the sharp frame at 0.5 s")
    finally:
        doc.close()


def mb1b(client):
    doc = Picture.new(client, WORK / "mb1b.framejob")
    try:
        doc.call("add_background", color=[0.2, 0.2, 0.2, 1.0], duration=SEC)
        clip = doc.image(checker(WORK / "media" / "greys.png", 6554, 45875), W, H)
        doc.call("set_video", clips=[clip], patch={"blend": "add"})
        action = doc.zoom(clip)
        blurred, _ = doc.blurred_and_sharp(clip, "mb1b")
        reference = doc.reference(clip, "mb1b", action=action)
        score_mean("MB1b", blurred, reference, "the zoom with blend add over a 0.2-grey plate")
    finally:
        doc.close()


def mb2(client):
    doc = Picture.new(client, WORK / "mb2.framejob")
    try:
        clip = doc.image(checker(WORK / "media" / "checker.png", 0, 65535), W, H)
        doc.blur(clip, SHUTTER)
        on = doc.shot(T, "on")
        doc.blur(clip, 0)
        off = doc.shot(T, "off")
        same = on is not None and off is not None and on.read_bytes() == off.read_bytes()
        check("MB2", same, f"an unmoving clip: blur 0.5 and 0 byte-identical {same}")
    finally:
        doc.close()


def mb3(client):
    doc = Picture.new(client, WORK / "mb3.framejob")
    try:
        clip = doc.image(checker(WORK / "media" / "checker.png", 0, 65535), W, H)
        doc.zoom(clip)
        blurred, sharp = doc.blurred_and_sharp(clip, "mb3")
        doc.blur(clip, SHUTTER)
        movie = doc.export("prores_4444", WORK / "mb3.mov")
        exported = movie_frame16(movie, 15) if movie else None
        gap, _ = worst(exported, rgb_of(blurred) if blurred else None)
        check("MB3", gap is not None and gap <= MB3_TOLERANCE,
              f"prores_4444 frame 15 against render_frame at 0.5 s, worst {levels(gap)} "
              f"(≤ 8/255)")
        control("MB3", exported, rgb_of(sharp) if sharp else None, MB3_CONTROL,
                "the export's frame 15 against the sharp frame")
    finally:
        doc.close()


# MB5's pointer: 600 px/s along y = 90 px, from 0.3 s to 0.75 s, a move every 8,300 µs of 249
# file units (2 px a point: a unit is 1/50 px), so the path is exactly linear.
MOVE_FROM_US, MOVE_STEP_US, MOVE_STEP_UNITS, MOVES = 300_000, 8_300, 249, 55


def moving_cursor(shift_ticks=0):
    """MB5's cursor file; with `shift_ticks`, every move that much earlier (to the µs), so at
    T it reads where the unshifted file reads at T + shift."""
    shift_us = round(shift_ticks * 1_000_000 / SEC)
    body = cu7_proof.cursor_body([], size=(W, H))
    body["moves"] = {"t": [MOVE_FROM_US + i * MOVE_STEP_US - shift_us for i in range(MOVES)],
                     "x": [20 * 50 + i * MOVE_STEP_UNITS for i in range(MOVES)],
                     "y": [90 * 50] * MOVES}
    return body


def pointer_doc(client, name):
    folder = WORK / "media" / name
    movie = raw_movie(folder / "pointer.mov", f"color=c=0x336699:size={W}x{H}:rate=30:duration=2")
    (folder / "pointer.fjcursor").write_text(json.dumps(moving_cursor()))
    doc = Picture.new(client, WORK / f"{name}.framejob")
    deep_dot(doc)
    clip = doc.movie(movie)
    doc.call("set_video", clips=[clip], patch={
        "cursor": {"smoothing": 0, "clicks": "none", "style": "arrow"}})
    media = doc.clip(clip)["source"]["media"]
    return doc, clip, (media, folder)


def mb5(client):
    doc, clip, pointer = pointer_doc(client, "mb5")
    try:
        if "MB2" in selected:
            doc.blur(clip, SHUTTER)
            on = doc.shot(3 * T, "rest-on")
            doc.blur(clip, 0)
            off = doc.shot(3 * T, "rest-off")
            same = on is not None and off is not None and on.read_bytes() == off.read_bytes()
            check("MB2", same,
                  f"the pointer at rest at 1.5 s: blur 0.5 and 0 byte-identical {same}")
        if "MB5" in selected:
            blurred, sharp = doc.blurred_and_sharp(clip, "mb5")
            reference = doc.reference(clip, "mb5", pointer=pointer)
            score_mean("MB5", blurred, reference, "a pointer at 600 px/s, no action")
            control("MB5", blurred, sharp, CONTROL, "the sharp frame at 0.5 s")
    finally:
        doc.close()


def mb6(client):
    doc, clip, pointer = pointer_doc(client, "mb6")
    try:
        action = doc.zoom(clip)
        blurred, _ = doc.blurred_and_sharp(clip, "mb6")
        reference = doc.reference(clip, "mb6", action=action, pointer=pointer)
        score_mean("MB6", blurred, reference, "the pointer under the 2× zoom")
    finally:
        doc.close()


# ---- K2–K4: Auto Zoom and the Transform row --------------------------------------

def screen_movie():
    out = WORK / "media" / "screen.mov"
    if not out.exists():
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        "testsrc=size=640x360:rate=30:duration=20", "-c:v", "libx264",
                        "-pix_fmt", "yuv420p", "-g", "30", "-bf", "0", str(out)],
                       check=True, timeout=300, env=bounded.child_env())
    return out


def recording(name):
    folder = WORK / "rec" / name
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "A.mov"
    shutil.copyfile(screen_movie(), path)
    (folder / "A.fjcursor").write_text(json.dumps(cu7_proof.cursor_body(cu7_proof.Z1_CLICKS)))
    return path


def zoom_doc(client, name):
    doc = Doc.new(client, WORK / f"{name}.framejob", size=(640, 360))
    return doc, doc.movie(recording(name))


def video_of(doc, clip):
    return doc.clip(clip).get("video") or {}


def k2(client):
    doc, clip = zoom_doc(client, "k2")
    try:
        answer = doc.call("auto_zoom", clip=clip, follow=False)
        stored = video_of(doc, clip).get("motion_blur")
        check("K2", stored == 0.5 and answer.get("blurred") == 1 and answer.get("added", 0) > 0,
              f"the default: motion_blur {stored}, blurred {answer.get('blurred')}, "
              f"{answer.get('added')} zooms")
        doc.call("undo")
        doc.call("set_video", clips=[clip], patch={"motion_blur": 0.3})
        answer = doc.call("auto_zoom", clip=clip, follow=False)
        stored = video_of(doc, clip).get("motion_blur")
        check("K2", stored == 0.3 and answer.get("blurred") == 0,
              f"a clip at 0.3: motion_blur {stored}, blurred {answer.get('blurred')}")
        doc.call("undo")
        doc.call("undo")
        answer = doc.call("auto_zoom", clip=clip, follow=False, motion_blur=0)
        video = video_of(doc, clip)
        check("K2", "motion_blur" not in video and answer.get("blurred") == 0
              and answer.get("added", 0) > 0,
              f"motion_blur 0: key {video.get('motion_blur')}, blurred {answer.get('blurred')}")
        doc.call("undo")
        before = doc.project()
        message = error_of(lambda: doc.call("auto_zoom", clip=clip, motion_blur=1.5))
        sentence = "Motion_blur is 1.5; it runs 0–1."
        check("K2", message is not None and sentence in message and doc.project() == before,
              f"1.5: {message}")
    finally:
        doc.close()


def k3(client):
    doc = Picture.new(client, WORK / "k3.framejob")
    try:
        clip = doc.image(checker(WORK / "media" / "checker.png", 0, 65535), W, H)
        doc.call("set_selection", clips=[clip])
        client.call("select_inspector_tab", tab="clip", sub_tab="picture",
                    section="video.transform")
        shot = doc.call("snapshot_ui", window="editor", path=str(WORK / "k3.png"))
        with open(shot.get("layout_path") or "") as handle:
            views = json.load(handle)["views"]
        shown = [v for v in views if not v.get("hidden")]
        names = [v.get("text") for v in shown]

        def y_of(text):
            frame = next((v.get("frame") for v in shown if v.get("text") == text), None)
            return frame[1] if frame else None

        blend, blur = y_of("Blend"), y_of("Motion Blur")
        below = blend is not None and blur is not None and (
            names.index("Motion Blur") > names.index("Blend"))
        check("K3", below, f"the layout dump: Blend at y {blend}, Motion Blur at y {blur}, "
              f"after it in order {below}")
    finally:
        doc.close()


def k4(client, tag, want):
    doc, clip = zoom_doc(client, f"k4-{tag}")
    try:
        doc.call("set_selection", clips=[clip])
        before = doc.project()
        doc.call("perform_menu_item", path=["Clip", "Auto Zoom…"])
        began = time.monotonic()
        while time.monotonic() - began < 30 and doc.project() == before:
            time.sleep(0.25)
        actions = doc.clip(clip)["actions"]
        stored = video_of(doc, clip).get("motion_blur")
        check("K4", bool(actions) and stored == want,
              f"{tag}: {len(actions)} actions, motion_blur {stored} (want {want})")
    finally:
        doc.close()


# ---- MB4: old projects ---------------------------------------------------------

MB4_TIMES = [5 * FRAME, 15 * FRAME, 25 * FRAME]
MB4_CLICKS = [(0.3, 160, 90), (0.6, 100, 60)]


def mb4_build(client, folder):
    """MB4's package in `folder`: built, saved, closed, its `version` set to 41."""
    media = folder / "media"
    movie = raw_movie(media / "screen.mov", f"testsrc2=size={W}x{H}:rate=30:duration=2")
    (media / "screen.fjcursor").write_text(
        json.dumps(cu7_proof.cursor_body(MB4_CLICKS, size=(W, H))))
    plate = png(media / "plate.png", 32, 32, lambda x, y: (200, 60, 90))
    doc = Doc.new(client, folder / "mb4.framejob")
    try:
        doc.call("add_background", color=[0.2, 0.3, 0.4, 1.0], duration=SEC)
        screen = doc.movie(movie)
        doc.call("trim_end", clip=screen, to=SEC)
        doc.call("set_video", clips=[screen], patch={
            "scale": 0.6, "blend": "screen",
            "reflection": {"opacity": 0.4, "height": 0.5, "gap": 4, "falloff": 0.8},
            "cursor": {"clicks": "ripple"}})
        doc.call("add_action", clip=screen, at=0, duration=SEC)
        action = doc.clip(screen)["actions"][0]["id"]
        doc.call("set_action", clip=screen, action=action, curve="ease_in_out")
        doc.call("set_action_end", clip=screen, action=action,
                 patch={"video": {"scale": 0.9, "x": 20.0, "y": -10.0}})
        badge = doc.image(plate, 32, 32)
        doc.call("set_video", clips=[badge], patch={
            "scale": 1.5, "x": 100.0, "y": 50.0,
            "shadow": {"color": [0, 0, 0, 1], "opacity": 0.8, "blur": 4, "angle": 45,
                       "distance": 6}})
        doc.call("save_project")
    finally:
        doc.close()
    project = folder / "mb4.framejob" / "project.json"
    body = json.loads(project.read_text())
    text = json.dumps(body)
    for key in ("motion_blur", "hide_silent"):
        if f'"{key}"' in text:
            raise RuntimeError(f"the fixture carries {key}, a key newer than version 41")
    body["version"] = 41
    project.write_text(json.dumps(body, indent=2))
    return folder / "mb4.framejob"


def mb4_measure(client, package, tag):
    """The three PNGs' sha-256 and the export's per-frame md5 of `package`, opened."""
    client.call("open_project", path=str(package))
    doc = Doc(client, package)
    try:
        version = doc.project().get("version")
        shots = []
        for t in MB4_TIMES:
            out = doc.render(t, WORK / f"mb4-{tag}-{t}.png")
            shots.append(hashlib.sha256(out.read_bytes()).hexdigest() if out else None)
        movie = doc.export("prores_4444", WORK / f"mb4-{tag}.mov")
        frames = framemd5(movie) if movie else []
        return {"opened_version": version, "png_sha256": shots, "export_framemd5": frames}
    finally:
        doc.close()


def capture(client, folder):
    folder.mkdir(parents=True, exist_ok=True)
    package = mb4_build(client, folder)
    measured = mb4_measure(client, package, "capture")
    (folder / "mb4.json").write_text(json.dumps(measured, indent=2))
    ok = all(measured["png_sha256"]) and len(measured["export_framemd5"]) == 30
    print(f"  {'ok  ' if ok else 'FAIL'} capture: {len(measured['export_framemd5'])} export "
          f"frames, PNGs {measured['png_sha256']}, opened as version "
          f"{measured['opened_version']} → {folder / 'mb4.json'}", flush=True)
    return ok


def mb4(client, folder):
    captured = json.loads((folder / "mb4.json").read_text())
    copy = WORK / "mb4.framejob"
    if copy.exists():
        shutil.rmtree(copy)
    shutil.copytree(folder / "mb4.framejob", copy)
    measured = mb4_measure(client, copy, "compare")
    for k, (was, now) in enumerate(zip(captured["png_sha256"], measured["png_sha256"])):
        check("MB4", was is not None and was == now,
              f"render_frame at frame {MB4_TIMES[k] // FRAME}: {now} (capture {was})")
    was, now = captured["export_framemd5"], measured["export_framemd5"]
    same = sum(1 for a, b in zip(was, now) if a == b)
    check("MB4", len(was) == 30 and was == now,
          f"prores_4444: {same} of {len(was)} frames' md5 equal ({len(now)} now)")


# ---- launches ------------------------------------------------------------------

def launch(binary, arguments, tag, body):
    """`body(client)` on a fresh launch; Z1 over its log."""
    log = WORK / f"instance-{tag}.log"
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            return False
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace")
                     if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return True


def app_rows(binary, folder):
    def body(client):
        if "K1" in selected:
            attempt(lambda: k1(client), "K1")
        for name, row, rows in (("MB1", mb1, ["MB1"]), ("MB1b", mb1b, ["MB1b"]),
                                ("MB2", mb2, ["MB2"]), ("MB3", mb3, ["MB3"]),
                                ("MB5", mb5, ["MB5", "MB2"]), ("MB6", mb6, ["MB6"]),
                                ("K2", k2, ["K2"]), ("K3", k3, ["K3"])):
            if name in selected or (name == "MB5" and "MB2" in selected):
                attempt(lambda row=row: row(client), *[r for r in rows if r in selected])
        if "MB4" in selected and folder is not None:
            attempt(lambda: mb4(client, folder), "MB4")

    if set(APP_ROWS + ["MB4"]) & selected and not launch(binary, [], "plain", body):
        for name in selected:
            check(name, False, "the app did not listen")
    if "K4" in selected:
        for tag, extra, want in (("on", [], 0.5),
                                 ("off", ["-FrameJobAutoZoomMotionBlur", "NO"], None)):
            arguments = ["-RCDevAutoZoomAccept", "YES", *extra]
            if not launch(binary, arguments, f"accept-{tag}",
                          lambda c, tag=tag, want=want: attempt(lambda: k4(c, tag, want), "K4")):
                check("K4", False, f"the app did not listen ({tag})")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", choices=["capture", "compare"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mode and not args.folder:
        print(f"{args.mode} needs a folder")
        return 2
    folder = Path(args.folder).resolve() if args.folder else None
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if args.mode != "compare":
        selected.discard("MB4")
    selected |= {"Z1"}
    if WORK.exists():
        shutil.rmtree(WORK)
    HOME.mkdir(parents=True)
    print(f"CU11 — motion blur ({proof_app.config()} build)", flush=True)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    if args.mode == "capture":
        if folder.exists():
            shutil.rmtree(folder)
        made = []
        launch(binary, [], "capture", lambda client: made.append(capture(client, folder)))
        failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
        good = bool(made) and made[0] and not failed
        print(f"\ncapture: {'done' if good else 'FAILED'}")
        return 0 if good else 1
    app_rows(binary, folder)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
