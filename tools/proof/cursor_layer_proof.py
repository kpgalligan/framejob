#!/usr/bin/env python3
"""Road map "creator-jobs" CU3a1 — `media.cursor`, `video.cursor` and the
recipe's `cursor` key (spec §11 CU-30, CU-32, CU-35, CU-39), every row a
read-back — and CU3a2, the cursor drawn in its clip's layer and the files that
wait for it (CU-33, CU-37): the drawing rows after them.

    python3 tools/proof/cursor_layer_proof.py [--only B0,L1d,…] [--app PATH]

The fixture is a version-37 project over a copy of `media/A.mov` (640×360,
30 fps, 10 s): one clip at 0 for 6 s and one zoom action over [1 s, 3 s)
ending at scale 2, on a 1280×720 canvas.

**Probe rows** (`cursor_layer_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app):
- B0 the probe builds (a failed build is a scored FAIL, and so is every
  probe row after it).
- L1d `ReelProject.from(json:)` of the fixture with `media.cursor` and
  `video.cursor`: `MediaSnapshot.cursor` and `VideoProps.cursor` equal the
  JSON; `MediaDescriptor(media).dictionary["cursor"]` (and its probe's) is the
  JSON object; `VideoPatch(cursor: .some(p))` writes all eight keys, and
  `.some(nil)` an `NSNull`.
- L3r the fixture at five times: every layer's `cursor` null; with
  `media[0].cursor = {path, in_picture: true}` the `recipeJSON` text
  byte-identical at each time; the control, `in_picture: false`, not null.
- L9 base `cursor {smoothing: 0}`, an action over [1 s, 3 s) ending
  `{video: {cursor: {smoothing: 1, hide_idle: 5, scale: 3}}}`, at 0.5, 1.5,
  2.5 and 3.5 s: the key's and `props`' `smoothing` 0 and `hide_idle` null;
  `props.scale` 1, strictly between 1 and 3 twice, then 3; `recipe(at:)`'s
  `layers[0].cursor` decodes the same.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`), one
launch on a scratch `CFFIXED_USER_HOME`:
- Z1 the launch's `grep "Frame Job: "` prints nothing.
- L1 `add_media` with `cursor {path: <work>/A.fjcursor, in_picture: false}` →
  `get_project`'s `media[0].cursor` as given; an unknown cursor key →
  "Unknown cursor key"; `add_clip`, then `set_video {cursor: {scale: 2,
  clicks: "ripple", hide_idle: 3, click_color: "red"}}` → `video.cursor` with
  all eight keys, `click_color` "red"; `click_color: "#ffg"` and `scale: 9` →
  errors carrying CU-30's sentences, `get_project` unchanged.
- L3 the fixture as a package's `project.json`, opened: `project` is the
  fixture with the header's `version` (every key the fixture spells, equal,
  and no `cursor` anywhere); `render_frame` at 3 times; `save_project` to a
  new package, `close_project`, `open_project`: `get_project` equal and the 3
  PNGs byte-identical. "Before and after the bump" is the v37 file read
  through this build; no old build is driven.

**CU3a2's drawing rows.** The fixture (`work/cursor-layer/cu/`): `clean.mov`,
ffmpeg's `testsrc2` at 640×360, 30 fps, 4 s, uncompressed ARGB (`raw `, which
AVFoundation decodes byte-exact); the probe's `cursor.fjcursor`, written through
`CursorFileBody` and read back through `ReelCursor` — format v1 at 1 px a point,
identity geometry, a move every frame at µs ⌊k·10⁶/30⌋ to px (60 + 3k, 50 + k),
two down clicks at k 30 and 75, one image from t 0 — and its `sprite.png`, a
12 × 16 triangle of (120, 30, 100) with transparent pixels, hot spot (1, 1);
`burned.mov`, the clean movie with the sprite burned in by ffmpeg's `overlay`
at the file's positions. A tip is LOCATED: each pixel's coverage, from its
difference to the same render with `show: false` along the sprite's colour,
weights a centroid, less the sprite's centroid offset × the drawn scale.
- L7 (probe) the cost: the compositor's own per-frame seconds
  (`PlaybackTrials`) over 120 frames read through a composition output, `show:
  true` with ripples minus `show: false` with `clicks: none`, the median of
  each, 3 runs, the median difference ≤ 0.3 ms at 1920×1080 and ≤ 1 ms at
  3840×2160 and 5120×2880; and a `MetalRenderer` of the probe's own asked for
  the 120 frames' sprites through `cursorSprite`: `CursorSprites.uploads` 1
  after the first and still 1 after the last.
- L2 a 2× zoom (an action ending scale 2, y 40): the tip at three frames equals
  (★) of the file's source point, ≤ 1 px.
- L4 a Ramp Up (linear 1 → 1.5 over the first second): at three clip frames
  whose S(t) lands on a held move, the tip is the file's point at S, ≤ 1 px;
  a reversed clip at three frames: the file's point at `pivot − at − frame`.
- L5 an HLG canvas: an interior sprite pixel of the 16-bit PNG equals the
  probe's `InputConversions.liftSDR` of the sprite's colour, ≤ 1/255.
- L6 a `prores_4444` export with ripples, decoded by ffmpeg, against
  `render_frame` at three frames (two with a ripple): ≤ 2/255 a channel.
- L8 the clean movie with its file against the burned movie, each with a blur
  filter, a pixelated region over frame 50's pointer, exposure +1 and
  saturation −0.5 (the second in `gradeSample`): ≤ 2/255 at three frames.
- L8r the two movies reversed (both through `ReverseRenderer`, no filter):
  the clean clip's drawn tip on the burned pointer's tip, ≤ 1 px, at three
  frames (positions, not bytes: the reverse is lossy).
- L10 a media whose cursor file is not JSON: `render_frame`'s answer says "The
  cursor of media M is not drawn: …", its PNG byte-identical to `show: false`
  with no ripples, and an `h264` export's `export_status` answers one
  `cursor_warnings` entry naming the media and the path.
- L11 a second launch with `-RCDevCursorLoadHold 2` (Z1 counts its log too):
  the L11 document, saved by the first launch, opened and exported to
  `prores_4444` at once: every one of the 120 frames shows the sprite at the
  file's position.

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/cursor-layer"
HOME = WORK / "home"
HEADER = ROOT / "core/include/framejob_core.h"
MOVIE = ROOT / "tools/proof/media/A.mov"
CALL_BOUND = 300
SEC = 600_000
PROBE_ROWS = ["B0", "L1d", "L3r", "L9", "L7"]
DRAWING_ROWS = ["L2", "L4", "L5", "L6", "L8", "L8r", "L10", "L11"]
APP_ROWS = ["L1", "L3"] + DRAWING_ROWS + ["Z1"]
ROWS = PROBE_ROWS + APP_ROWS
RENDER_TIMES = [SEC // 2, 2 * SEC, 4 * SEC]
SCALE_SENTENCE = "video.cursor.scale must be between 0.25 and 8, not 9"
COLOR_SENTENCE = 'video.cursor.click_color must be a CSS colour (spec §11 G-12), not "#ffg"'

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, never a copy."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


def movie():
    copy = WORK / "media" / "A.mov"
    if not copy.exists():
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MOVIE, copy)
    return copy


def fixture():
    """The version-37 project: A.mov, one clip, one zoom action."""
    return {
        "version": 37,
        "canvas": {"width": 1280, "height": 720, "fps": [30, 1]},
        "media": [{"id": 1, "path": str(movie()), "kind": "video", "duration": 10 * SEC,
                   "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                   "has_audio": False}],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": 6 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "video": {},
                   "actions": [{"id": 4, "start": SEC, "duration": 2 * SEC,
                                "curve": "linear",
                                "end": {"video": {"scale": 2.0, "x": 120.0}}}]}],
        "next_id": 5,
    }


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the probe rows ------------------------------------------------------------

def probe_rows():
    rows = [r for r in PROBE_ROWS if r in selected]
    if not rows:
        return
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "cursor_layer_probe.swift", entry)
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    binary = out / "cursor-layer-probe"
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        detail = "the probe did not build: " + "; ".join(error.diagnostics[:6])
        for row in rows:
            check(row, False, detail)
        return
    # The compositor's library beside the binary, where `MetalRenderer` looks (`Bundle.main`):
    # L7 composes through it.
    air, library = out / "Compositor.air", out / "default.metallib"
    shader = ROOT / "app/Resources/Shaders/Compositor.metal"
    for argv in (["metal", "-c", str(shader), "-o", str(air)],
                 ["metallib", str(air), "-o", str(library)]):
        made = subprocess.run(["xcrun", "-sdk", "macosx", *argv], capture_output=True,
                              text=True, timeout=300)
        if made.returncode != 0:
            for row in rows:
                check(row, False, "the shader did not build: " + made.stderr[-300:])
            return
    shutil.copyfile(ROOT / "app/Resources/Blank.mp4", out / "Blank.mp4")
    check("B0", True, f"built {binary.name} and its default.metallib")
    request = out / "request.json"
    asked = {"fixture": json.dumps(fixture()), "cursor_dir": str(CU)}
    if "L7" in selected:
        asked["l7"] = {"movie": str(CLEAN), "cursor": str(CU / "cursor.fjcursor"), "runs": 3}
    request.write_text(json.dumps(asked))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=1200)
        whole = json.loads(run.stdout)
        answer = whole["rows"]
        FIXTURE.update(whole.get("fixture") or {})
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        for row in rows:
            if row != "B0":
                check(row, False, f"the probe gave no answer: {error}")
        return
    by_id = {r["id"]: r for r in answer}
    for row in rows:
        if row == "B0":
            continue
        got = by_id.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))


# ---- the app rows --------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def frames(self, tag):
        shots = []
        for t in RENDER_TIMES:
            out = WORK / f"{tag}-{t}.png"
            if out.exists():
                out.unlink()
            self.call("render_frame", t=t, path=str(out))
            shots.append(out.read_bytes() if out.exists() else None)
        return shots


def new_doc(client, name):
    path = WORK / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    doc.call("set_canvas", width=1280, height=720, fps=[30, 1])
    doc.call("save_project")
    return doc


def close(client, path):
    try:
        client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass


def error_of(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


def contains(whole, part):
    """Every key `part` spells is in `whole` with an equal value; lists by index."""
    if isinstance(part, dict):
        return isinstance(whole, dict) and all(
            k in whole and contains(whole[k], v) for k, v in part.items())
    if isinstance(part, list):
        return isinstance(whole, list) and len(whole) == len(part) and all(
            contains(w, p) for w, p in zip(whole, part))
    if isinstance(part, (int, float)) and not isinstance(part, bool):
        return isinstance(whole, (int, float)) and not isinstance(whole, bool) and whole == part
    return whole == part


def l1(client):
    doc = new_doc(client, "l1")
    try:
        cursor_file = str(WORK / "A.fjcursor")
        descriptor = {"path": str(movie()), "kind": "video", "duration": 10 * SEC,
                      "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                      "cursor": {"path": cursor_file, "in_picture": False}}
        doc.call("add_media", descriptor=descriptor)
        project = doc.project()
        media = project["media"][0]
        check("L1", media.get("cursor") == {"path": cursor_file, "in_picture": False},
              f"add_media stored media.cursor {media.get('cursor')}")
        stranger = dict(descriptor, path=str(WORK / "other.mov"),
                        cursor={"path": cursor_file, "in_picture": False, "bogus": 1})
        message = error_of(lambda: doc.call("add_media", descriptor=stranger)) or ""
        check("L1", 'Unknown cursor key "bogus"' in message,
              f"an unknown cursor key: {message[:160] or 'no error'}")
        track = doc.project()["tracks"]
        if not track:
            doc.call("add_track")
            track = doc.project()["tracks"]
        doc.call("add_clip", track=track[0]["id"], media=media["id"], at=0)
        clip = doc.project()["clips"][0]["id"]
        doc.call("set_video", clips=[clip], patch={"cursor": {
            "scale": 2, "clicks": "ripple", "hide_idle": 3, "click_color": "red"}})
        before = doc.project()
        stored = before["clips"][0]["video"].get("cursor") or {}
        want = {"show": True, "scale": 2.0, "style": "recorded", "smoothing": 0.0,
                "hide_idle": 3.0, "clicks": "ripple", "click_color": "red", "click_size": 1.0}
        check("L1", stored == want, f"set_video stored video.cursor {stored}")
        for patch, sentence in [({"click_color": "#ffg"}, COLOR_SENTENCE),
                                ({"scale": 9}, SCALE_SENTENCE)]:
            message = error_of(lambda: doc.call("set_video", clips=[clip],
                                                patch={"cursor": patch})) or ""
            check("L1", sentence in message, f"{patch}: {message[:200] or 'no error'}")
        check("L1", doc.project() == before, "get_project unchanged by the two refusals")
    finally:
        close(client, doc.path)


def l3(client):
    made = new_doc(client, "v37")
    close(client, made.path)
    old = fixture()
    (made.path / "project.json").write_text(json.dumps(old, indent=2))
    client.call("open_project", path=str(made.path))
    doc = Doc(client, made.path)
    saved = WORK / "v38.framejob"
    try:
        first = doc.project()
        expected = dict(old, version=format_version())
        check("L3", first.get("version") == format_version() and contains(first, expected)
              and '"cursor"' not in json.dumps(first),
              f"the v37 file opened as version {first.get('version')}, the fixture's every "
              "key equal, no cursor key")
        shots = doc.frames("v37")
        check("L3", all(s for s in shots), f"{sum(1 for s in shots if s)} frames rendered")
        if saved.exists():
            shutil.rmtree(saved)
        doc.call("save_project", path=str(saved))
        close(client, saved)
        close(client, made.path)
        client.call("open_project", path=str(saved))
        again = Doc(client, saved)
        second = again.project()
        check("L3", second == first, "saved, closed and reopened: get_project equal")
        reshots = again.frames("v38")
        same = [a is not None and a == b for a, b in zip(shots, reshots)]
        check("L3", all(same), f"the 3 PNGs byte-identical: {same}")
    finally:
        close(client, saved)
        close(client, made.path)


# ---- CU3a2: the cursor drawn ---------------------------------------------------

FIXTURE = {}
CU = WORK / "cu"
CLEAN = CU / "clean.mov"
BURNED = CU / "burned.mov"
UNREADABLE = CU / "unreadable.fjcursor"
MOVIE_TICKS = 4 * SEC
FRAME = SEC // 30
HOLD_US = 8_333
REVERSE_BOUND = 300
SPRITE_TOLERANCE = 1.0          # px, a located tip against its oracle
PARITY = 2                      # /255, L6 and L8
LIFT_TOLERANCE = 1 / 255        # L5


def ffmpeg(args, seconds=300):
    run = subprocess.run(["ffmpeg", "-v", "error", "-y", *args], capture_output=True,
                         timeout=seconds, env=bounded.child_env())
    if run.returncode != 0:
        raise RuntimeError("ffmpeg: " + run.stderr.decode(errors="replace")[-400:])


def make_clean():
    """testsrc2, 640×360, 30 fps, 4 s, as uncompressed ARGB (`raw `), which AVFoundation
    decodes byte-exact (measured: 0 bytes differ from ffmpeg's decode); RGB24 does not."""
    CU.mkdir(parents=True, exist_ok=True)
    if not CLEAN.exists():
        ffmpeg(["-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=4",
                "-c:v", "rawvideo", "-pix_fmt", "argb", "-tag:v", "raw ", str(CLEAN)])


def make_burned():
    """The clean movie with the sprite burned in by ffmpeg at the file's positions: frame n's
    rect at (60 + 3n − hot_x, 50 + n − hot_y), straight alpha, blended in RGB. The frame is
    counted from its time, round(t · 30): `overlay`'s own `n` was measured to start at 1."""
    hot_x, hot_y = FIXTURE["hot"]
    frame = "floor(t*30+0.5)"
    ffmpeg(["-i", str(CLEAN), "-i", FIXTURE["sprite"], "-filter_complex",
            f"[0:v][1:v]overlay=x={60 - hot_x}+3*{frame}:y={50 - hot_y}+{frame}:eval=frame:"
            "format=rgb,format=argb", "-c:v", "rawvideo", "-pix_fmt", "argb", "-tag:v", "raw ",
            str(BURNED)])


def decode(path, index=0, pix="rgb24", width=640, height=360):
    """Frame `index` of `path` as raw bytes in `pix`, or None; bounded."""
    size = width * height * {"rgb24": 3, "rgba": 4, "rgb48le": 6}[pix]
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"select=eq(n\\,{index})",
             "-fps_mode", "passthrough", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", pix,
             "-"], capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw if len(raw) == size else None


def decode_all(path, pix="rgb24", width=640, height=360):
    """Every frame of `path` as a list of raw frames, or []."""
    size = width * height * {"rgb24": 3, "rgba": 4}[pix]
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", pix, "-"],
            capture_output=True, timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    return [raw[i:i + size] for i in range(0, len(raw) - size + 1, size)]


def file_position(us):
    """The raw path at file µs `us` where the hold rule holds a move (CU-21): the last move
    at or before it, or None inside the 8,333 µs a move glides into the next one."""
    moves = FIXTURE["moves"]
    best = None
    for index, (t, x, y) in enumerate(moves):
        if t > us:
            break
        best = index
    if best is None:
        return None
    if best + 1 < len(moves) and us >= moves[best + 1][0] - HOLD_US:
        return None
    return moves[best][1], moves[best][2]


def ticks_us(ticks):
    return ticks * 1_000_000 / SEC


def tip_from(with_cursor, without, color, scale=1.0, width=640, cut=0.3):
    """The located sprite tip in a render: each pixel's coverage α = the share of
    (colour − background) its difference from `without` carries (clamped, below `cut` 0),
    their α-weighted centroid in continuous pixel coordinates, less the sprite's centroid
    offset from its hot spot × `scale`. None when nothing was covered."""
    if with_cursor is None or without is None:
        return None
    c = color
    total = sx = sy = 0.0
    for i in range(0, len(with_cursor), 3):
        b = without[i:i + 3]
        a = with_cursor[i:i + 3]
        d = [c[0] - b[0], c[1] - b[1], c[2] - b[2]]
        norm = d[0] * d[0] + d[1] * d[1] + d[2] * d[2]
        if norm < 900:
            continue
        alpha = ((a[0] - b[0]) * d[0] + (a[1] - b[1]) * d[1] + (a[2] - b[2]) * d[2]) / norm
        alpha = min(max(alpha, 0.0), 1.0)
        if alpha < cut:
            continue
        p = i // 3
        sx += alpha * (p % width + 0.5)
        sy += alpha * (p // width + 0.5)
        total += alpha
    if total < 4:
        return None
    ox, oy = FIXTURE["centroid"]
    return sx / total - scale * ox, sy / total - scale * oy


def near(a, b, tolerance=SPRITE_TOLERANCE):
    return a is not None and b is not None and abs(a[0] - b[0]) <= tolerance \
        and abs(a[1] - b[1]) <= tolerance


def show(p):
    return None if p is None else f"({p[0]:.2f}, {p[1]:.2f})"


def max_diff(a, b):
    if a is None or b is None or len(a) != len(b):
        return None
    return max(abs(x - y) for x, y in zip(a, b))


class Drawn:
    """A document over one movie for the drawing rows: 640×360 at 30 fps, one clip at 0."""

    def __init__(self, client, name, movie, cursor=None):
        self.client, self.name = client, name
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=640, height=360, fps=[30, 1])
        descriptor = {"path": str(movie), "kind": "video", "duration": MOVIE_TICKS,
                      "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                      "has_audio": False}
        if cursor is not None:
            descriptor["cursor"] = {"path": str(cursor), "in_picture": False}
        self.call("add_media", descriptor=descriptor)
        project = self.project()
        self.media = project["media"][0]["id"]
        if not project["tracks"]:
            self.call("add_track")
            project = self.project()
        self.call("add_clip", track=project["tracks"][0]["id"], media=self.media, at=0)
        self.clip = self.project()["clips"][0]["id"]
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def cursor(self, **props):
        self.call("set_video", clips=[self.clip], patch={"cursor": props})

    def render(self, t, tag, pix="rgb24"):
        """`render_frame` at `t`: (the decoded frame, the answer's text, the PNG's bytes)."""
        out = WORK / f"{self.name}-{tag}-{t}.png"
        if out.exists():
            out.unlink()
        text = self.call("render_frame", t=t, path=str(out))
        if not out.exists():
            return None, text, None
        return decode(out, pix=pix), text, out.read_bytes()

    def tip(self, t, tag, scale=1.0):
        """The located tip at `t`: rendered with the cursor, then with `show: false`."""
        drawn, _, _ = self.render(t, tag + "-on")
        self.cursor(show=False)
        bare, _, _ = self.render(t, tag + "-off")
        self.cursor(show=True)
        return tip_from(drawn, bare, FIXTURE["color"], scale=scale)

    def reverse(self):
        """`set_reversed`, then the wait for its render (`precision_proof.wait_reverse`'s
        rule): the file in `cache/reversed/` with no `.partial` and no sheet attached."""
        self.call("set_reversed", clip=self.clip, reversed=True)
        folder = self.path / "cache" / "reversed"
        deadline = time.monotonic() + REVERSE_BOUND
        while True:
            files = sorted(folder.glob(f"{self.media}-*.mov")) if folder.is_dir() else []
            partial = folder.is_dir() and any(folder.glob(f"{self.media}-*.partial"))
            if files and not partial:
                try:
                    self.call("snapshot_ui", window="sheet",
                              path=str(WORK / f"{self.name}-sheet.png"))
                except mcp.ToolError as error:
                    if "no sheet attached" in str(error):
                        return None
            if time.monotonic() > deadline:
                try:
                    self.call("cancel_sheet")
                except mcp.ToolError:
                    pass
                return f"the reverse did not finish within {REVERSE_BOUND} s"
            time.sleep(0.25)

    def export(self, preset, name):
        out = WORK / name
        if out.exists():
            out.unlink()
        answer = self.client.export_with(
            {"project": str(self.path), "preset": preset, "path": str(out)})
        return out, answer

    def close(self):
        close(self.client, self.path)


def expected_tip(k, scale=1.0, x=0.0, y=0.0):
    """(★) of move k's source point on this 640×360 canvas with no crop or rotation."""
    px, py = FIXTURE["moves"][k][1], FIXTURE["moves"][k][2]
    return 320 + x + scale * (px - 320), 180 + y + scale * (py - 180)


def l2(client):
    """A 2× zoom: the tip's canvas position is (★) of its source position."""
    doc = Drawn(client, "l2", CLEAN, FIXTURE["cursor"])
    try:
        doc.call("add_action", clip=doc.clip, at=SEC // 2, duration=SEC)
        action = doc.project()["clips"][0]["actions"][0]["id"]
        doc.call("set_action_end", clip=doc.clip, action=action,
                 patch={"video": {"scale": 2.0, "x": 0.0, "y": 40.0}})
        for k in (48, 60, 72):
            tip = doc.tip(k * FRAME, f"k{k}", scale=2.0)
            want = expected_tip(k, scale=2.0, y=40.0)
            check("L2", near(tip, want), f"after the 2× zoom at frame {k}: tip {show(tip)}, "
                  f"(★) of ({FIXTURE['moves'][k][1]}, {FIXTURE['moves'][k][2]}) {show(want)}")
    finally:
        doc.close()


def ramp_samples():
    """Clip frames n (on the canvas grid) where the ramp's S lands on a held move: S(t) =
    t + t²/4 s over [0, 1 s) (Ramp Up, linear, 1 → 1.5), then 1.25 s + 1.5 (t − 1 s)."""
    picked = []
    for n in range(3, 58):
        t = n / 30
        s = t + t * t / 4 if t < 1 else 1.25 + 1.5 * (t - 1)
        ticks = round(s * SEC)
        position = file_position(ticks_us(ticks))
        if position is not None:
            picked.append((n, ticks, position))
    return [picked[i] for i in (2, len(picked) // 2, len(picked) - 3)] if len(picked) > 5 else []


def l4(client):
    """A linear ramp at S(clip time), and a reversed clip at `pivot − at − frame`."""
    doc = Drawn(client, "l4-ramp", CLEAN, FIXTURE["cursor"])
    try:
        doc.call("trim_end", clip=doc.clip, to=2 * SEC)
        doc.call("add_speed_ramp", clip=doc.clip, shape="ramp_up", rate=1.5, **{"from": 0},
                 to=SEC, curve="linear")
        samples = ramp_samples()
        check("L4", len(samples) == 3, f"{len(samples)} ramp samples on a held move")
        for n, ticks, position in samples:
            tip = doc.tip(n * FRAME, f"n{n}")
            check("L4", near(tip, position), f"the ramp at clip frame {n}: S {ticks} ticks, "
                  f"the file's {position}, the tip {show(tip)}")
    finally:
        doc.close()
    doc = Drawn(client, "l4-reverse", CLEAN, FIXTURE["cursor"])
    try:
        why = doc.reverse()
        check("L4", why is None, why or "reversed and rendered")
        for n in (15, 45, 90):
            source = MOVIE_TICKS - n * FRAME - FRAME
            k = source // FRAME
            tip = doc.tip(n * FRAME, f"rev{n}")
            want = expected_tip(k)
            check("L4", near(tip, want), f"reversed at clip frame {n}: pivot − at − frame = "
                  f"{source} ticks (move {k}), {show(want)}; the tip {show(tip)}")
    finally:
        doc.close()


def l5(client):
    """HLG: the sprite's pixel is `liftSDR` of the SDR one."""
    doc = Drawn(client, "l5", CLEAN, FIXTURE["cursor"])
    try:
        doc.call("set_canvas", output="hlg")
        k = 40
        hot_x, hot_y = FIXTURE["hot"]
        x = FIXTURE["moves"][k][1] - hot_x + 2
        y = FIXTURE["moves"][k][2] - hot_y + 10
        raw, _, _ = doc.render(k * FRAME, "hlg", pix="rgb48le")
        if raw is None:
            check("L5", False, "no 16-bit frame")
            return
        at = (y * 640 + x) * 6
        got = [int.from_bytes(raw[at + 2 * i:at + 2 * i + 2], "little") / 65535 for i in range(3)]
        want = FIXTURE["lifted"]
        worst = max(abs(a - b) for a, b in zip(got, want))
        check("L5", worst <= LIFT_TOLERANCE,
              f"the sprite's pixel ({x}, {y}) at frame {k} {[round(v, 4) for v in got]}, "
              f"liftSDR of {FIXTURE['color']} {[round(v, 4) for v in want]}: "
              f"{worst * 255:.3f}/255 (≤ 1)")
    finally:
        doc.close()


def l6(client):
    """A `prores_4444` export decoded by ffmpeg against `render_frame` at three times."""
    doc = Drawn(client, "l6", CLEAN, FIXTURE["cursor"])
    try:
        doc.cursor(clicks="ripple")
        movie, answer = doc.export("prores_4444", "l6.mov")
        check("L6", movie.exists(), f"exported {movie.name}: {sorted(answer)[:8]}")
        for k in (10, 33, 80):
            frame, _, _ = doc.render(k * FRAME, "l6")
            exported = decode(movie, index=k)
            worst = max_diff(frame, exported)
            check("L6", worst is not None and worst <= PARITY,
                  f"frame {k}{' (a ripple)' if k in (33, 80) else ''}: the export against "
                  f"render_frame, worst {worst}/255 (≤ {PARITY})")
    finally:
        doc.close()


L8_PATCH = {
    "filters": [{"kind": "blur", "amount": 0.3}],
    # Over frame 50's pointer, whose rect is (209, 99)–(221, 115): centred at (215, 107),
    # (−105, −73) from the source's centre, 40 px square.
    "obscure": [{"shape": "rect", "x": -105.0, "y": -73.0, "width": 40.0, "height": 40.0,
                 "feather": 0.0, "kind": "pixelate", "amount": 0.4}],
    "color": {"exposure": 1.0, "saturation": -0.5},
}


def l8(client):
    """Parity with a burned pointer, through a blur, an obscure region and a grade."""
    clean = Drawn(client, "l8-clean", CLEAN, FIXTURE["cursor"])
    burned = Drawn(client, "l8-burned", BURNED)
    try:
        for doc in (clean, burned):
            doc.call("set_video", clips=[doc.clip], patch=L8_PATCH)
        for k in (20, 50, 90):
            a, _, _ = clean.render(k * FRAME, "l8")
            b, _, _ = burned.render(k * FRAME, "l8")
            worst = max_diff(a, b)
            check("L8", worst is not None and worst <= PARITY,
                  f"frame {k}: the clean movie and its file against the burned movie, blur 0.3, "
                  f"a pixelated region over frame 50's pointer, exposure +1 and saturation "
                  f"−0.5: worst {worst}/255 (≤ {PARITY})")
    finally:
        clean.close()
        burned.close()


def l8r(client):
    """The same two movies reversed: the clean clip's drawn tip on the burned pointer's."""
    clean = Drawn(client, "l8r-clean", CLEAN, FIXTURE["cursor"])
    burned = Drawn(client, "l8r-burned", BURNED)
    try:
        whys = [clean.reverse(), burned.reverse()]
        check("L8r", not any(whys), "; ".join(w for w in whys if w) or "both reversed")
        for n in (20, 55, 95):
            t = n * FRAME
            drawn, _, _ = clean.render(t, "l8r-on")
            clean.cursor(show=False)
            bare, _, _ = clean.render(t, "l8r-off")
            clean.cursor(show=True)
            pointer, _, _ = burned.render(t, "l8r")
            mine = tip_from(drawn, bare, FIXTURE["color"])
            theirs = tip_from(pointer, bare, FIXTURE["color"])
            check("L8r", near(mine, theirs), f"reversed at clip frame {n}: the drawn tip "
                  f"{show(mine)}, the burned pointer's {show(theirs)}")
    finally:
        clean.close()
        burned.close()


def l10(client):
    """An unreadable cursor file: warned by `export_status` and `render_frame`, the frame
    byte-identical to `show: false` with no ripples."""
    UNREADABLE.write_text("this is not a cursor file\n")
    doc = Drawn(client, "l10", CLEAN, UNREADABLE)
    try:
        doc.cursor(clicks="ripple")
        _, text, warned = doc.render(SEC, "l10-file")
        sentence = f"The cursor of media {doc.media} is not drawn: "
        check("L10", sentence in (text or ""), f"render_frame says: {(text or '')[-220:]}")
        doc.cursor(show=False, clicks="none")
        _, _, bare = doc.render(SEC, "l10-off")
        check("L10", warned is not None and warned == bare,
              "the frame byte-identical to show: false with no ripples")
        doc.cursor(show=True, clicks="ripple")
        _, answer = doc.export("h264", "l10.mp4")
        warnings = answer.get("cursor_warnings") or []
        named = [w for w in warnings if w.get("media") == doc.media
                 and w.get("path") == str(UNREADABLE) and w.get("message")]
        check("L10", answer.get("status") == "done" and len(named) == 1,
              f"export_status done, cursor_warnings {warnings}")
    finally:
        doc.close()


def interior(frame, k, color, tolerance=12):
    """Whether three interior sprite pixels at move k hold the sprite's colour."""
    hot_x, hot_y = FIXTURE["hot"]
    x0 = FIXTURE["moves"][k][1] - hot_x
    y0 = FIXTURE["moves"][k][2] - hot_y
    for col, row in ((2, 10), (3, 12), (5, 14)):
        at = ((y0 + row) * 640 + x0 + col) * 3
        if any(abs(frame[at + i] - color[i]) > tolerance for i in range(3)):
            return False
    return True


def l11_prepare(client):
    """The L11 document, made and saved in the first launch: opened fresh in the second, no
    track of it is loaded yet."""
    doc = Drawn(client, "l11", CLEAN, FIXTURE["cursor"])
    doc.call("save_project")
    doc.close()
    return doc.path


def l11(client, path):
    """With every load held 2 s, an export started at once draws the sprite in every frame."""
    client.call("open_project", path=str(path))
    doc = Drawn.__new__(Drawn)
    doc.client, doc.name, doc.path = client, "l11", path
    try:
        movie, _ = doc.export("prores_4444", "l11.mov")
        frames = decode_all(movie)
        drawn = [k for k, frame in enumerate(frames) if interior(frame, k, FIXTURE["color"])]
        check("L11", len(frames) == 120 and len(drawn) == 120,
              f"{len(drawn)} of {len(frames)} exported frames show the sprite at the file's "
              f"position (first without: {next((k for k in range(len(frames)) if k not in drawn), None)})")
    finally:
        close(client, path)


def app_rows(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected & set(APP_ROWS):
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        drawing = [(name, body) for name, body in
                   [("L2", l2), ("L4", l4), ("L5", l5), ("L6", l6), ("L8", l8), ("L8r", l8r),
                    ("L10", l10)]]
        bodies = [("L1", l1), ("L3", l3)] + drawing
        held = None
        for name, body in bodies:
            if name not in selected:
                continue
            if name in DRAWING_ROWS and not FIXTURE.get("cursor"):
                check(name, False, f"no fixture: {FIXTURE.get('problems') or 'the probe wrote none'}")
                continue
            try:
                body(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                check(name, False, f"{type(error).__name__}: {error}")
        if "L11" in selected:
            try:
                held = l11_prepare(launched.client) if FIXTURE.get("cursor") else None
            except Exception as error:  # noqa: BLE001
                check("L11", False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
    logs = [log]
    if held is not None:
        logs.append(WORK / "instance-held.log")
        second = mcp.launch(str(binary), ["-RCDevCursorLoadHold", "2"],
                            env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                            log_path=str(logs[-1]), timeout=CALL_BOUND)
        try:
            if second.client is None:
                check("L11", False, "the held launch did not listen")
            else:
                l11(second.client, held)
        except Exception as error:  # noqa: BLE001
            check("L11", False, f"{type(error).__name__}: {error}")
        finally:
            second.stop()
    lines = []
    for path in logs:
        try:
            lines += [line.strip() for line in open(path, errors="replace")
                      if "Frame Job: " in line]
        except OSError:
            lines.append(f"{path} could not be read")
    check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'} "
          f"({len(logs)} launch{'es' if len(logs) > 1 else ''})")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & ({"L1", "L3"} | set(DRAWING_ROWS)):
            selected.add("Z1")
        if selected & (set(DRAWING_ROWS) | {"L7"}):
            selected.add("B0")
    remove_work()
    HOME.mkdir(parents=True)
    print(f"CU3a1 and CU3a2 — the cursor in the model and the recipe, then drawn "
          f"({proof_app.config()} build)", flush=True)
    if selected & (set(DRAWING_ROWS) | {"L7"}):
        try:
            make_clean()
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
            print(f"  the clean movie was not made: {error}", flush=True)
    probe_rows()
    if FIXTURE.get("sprite") and selected & {"L8", "L8r"}:
        try:
            make_burned()
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
            print(f"  the burned movie was not made: {error}", flush=True)
    if selected & set(APP_ROWS):
        binary = Path(args.app) if args.app else proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
