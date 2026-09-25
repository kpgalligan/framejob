#!/usr/bin/env python3
"""A graphic clip DRAWN, against the built app: road map 10's G3b (§10.6).

One owned instance on its own port, launched and stopped by PID, with its log
at `tools/proof/work/graphics/reelcut-<port>.log`; nothing else is ever
killed. Every child runs under `graphics_spike/bounded.py`, and every wait is
a bounded poll. The modules are written OUTSIDE a package and `mv`d into its
`graphics/` from the shell (`write_graphic` is G4's). `bar.js` is this
script's own: one rect at x = frame × 4, 100 wide, 100 + 20 × len(title)
tall, filled with `props.color` — no fonts, and no `meta` size, so its raster
is the 1920 × 1080 canvas and maps 1:1. Frame N is N × 20000 ticks.

P1  `add_graphic_clip {name: "bar", track, at: 0}` (polled for at most 5 s
    while the store sees the module land) → `get_project` shows
    `graphic.name == "bar"` and duration 2 400 000 (meta's 120 frames);
P2  frame 30, where the rect covers x ∈ [120, 220): the EDGE pixels
    (122,50) == (255,90,54) and (222,50) == (0,0,0) pin the frame number
    (both flip at frame 31); (50,50) is black; a CONTROL: frame 31 differs;
P3  `move_clip` by 17 frames: frame 47 byte-identical to P2's frame 30; undo;
S1  `split` at frame 40: frame 41 byte-identical before and after; undo;
R1  `set_graphic {props: {title: "B"}}` changes frame 30; `{props: {nope:
    1}}` is refused naming `props.nope`; ONE undo restores P2's bytes;
H1  a `bar.js` whose colour default is #2d7ff9 `mv`d in: within 5 s pixel
    (170,50) == (45,127,249);
L1  `set_graphic {props: {color: "#2d7ff9"}}`, then a `bar.js` whose schema
    has no `color` (and whose rect is 120 wide, so its landing is visible at
    (230,50)): the stale stored prop still draws, (170,50) == (45,127,249);
F1  `lower-third` on its own project: frame 30 pixel (100,900) ==
    (255,90,54), the accent bar (fonts through the bundled library).
    MEASURED, not scored: mismatching pixels and the max channel delta
    against `graphics_ffi_probe.py`'s frame-30 BGRA over black;
K1  save, stop, relaunch, `open_project`: frame 30 byte-identical;
K2  `save_project {path: P1b}`: `P1b/graphics/bar.js` present, frame 30
    identical;
T1  `set_canvas {fps: [30000, 1001]}`: frame 30 at tick 600 600
    byte-identical to the 30 fps canvas's frame 30;
K3  an untitled `new_project`, `bar.js` moved into its new
    `<DARWIN_USER_TEMP_DIR>/Reelcut/*-graphics` root, a clip added,
    `save_project {path: P2}`, relaunch, `open_project`: frame 30 identical;
A1  a transparent canvas plus `callout`, exported as `prores_4444`, decoded
    at 2 s with ffmpeg: alpha 0 at (0,0) and 255 at (1300,432), the stroke;
Z1  `grep "Reelcut: "` over every launch's log prints nothing.

    python3 tools/proof/graphics_proof.py [--port 4879] [--app PATH]
    python3 tools/proof/graphics_proof.py --mutant frame-plus-one

The mutant is built from a COPY of `app/` (with `core/` linked, not copied)
with one anchor in `LayerRenderersGraphic.swift`, asserted to occur exactly
once, replaced so the module is asked for `frame + 1`; the copy is built by
xcodegen and xcodebuild into its own directory and driven through P1 and P2.
Exit 0 means P2 FAILED in the mutant, which is the pass; a mutant that does
not build is a FAILURE. The rows past P2 are relative and a uniform +1 moves
both sides of them, so they are not expected to fail.
"""

import argparse
import glob
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
FIXTURES = ROOT / "graphic/tests/graphics"
FFI_BGRA = ROOT / "tools/proof/work/graphics-ffi-probe/lower-third-30.bgra"
CALL_BOUND = 300
FRAME = 20000
RED, BLUE, BLACK = (255, 90, 54), (45, 127, 249), (0, 0, 0)
ROWS = ["P1", "P2", "P3", "S1", "R1", "H1", "L1", "F1", "K1", "K2", "T1", "K3", "A1", "Z1"]
ANCHOR = "frame: frame, propsJSON: propsJSON, ctxJSON: ctxJSON,"
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def bar(color="#ff5a36", with_color=True, width=100):
    """This script's module. JS template `${…}` is spelled with `@{…}` here
    and swapped at the end, so no Python brace is doubled."""
    schema = 'title: { type: "string", default: "Jane" }'
    if with_color:
        schema += f', color: {{ type: "color", default: "{color}" }}'
    body = ('<rect x="@{frame * 4}" y="0" width="' + str(width) + '" '
            'height="@{100 + props.title.length * 20}" fill="@{props.color}"/>')
    return ("export const meta = { name: \"Bar\", durationInFrames: 120 };\n"
            "export const schema = { " + schema + " };\n"
            "export function render(frame, props, ctx) {\n"
            "  return svg(ctx, `" + body + "`);\n"
            "}\n").replace("@{", "${")


class Instance:
    """One owned app, by PID, on its own port; each launch reads only the part
    of the log it appended."""

    def __init__(self, app, port, log):
        self.app, self.port, self.log = app, port, log
        self.child = None

    def start(self):
        offset = self.log.stat().st_size if self.log.exists() else 0
        with open(self.log, "a") as out:
            self.child = subprocess.Popen(
                [str(self.app), "-ApplePersistenceIgnoreState", "YES",
                 "-AgentServerEnabled", "YES"],
                stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
                env=bounded.child_env({"RC_AGENT_PORT": str(self.port)}))
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            time.sleep(0.25)
            with open(self.log) as handle:
                handle.seek(offset)
                found = re.search(r"listening on http://127\.0\.0\.1:(\d+)/mcp", handle.read())
            if found:
                bound = int(found.group(1))
                print(f"  instance PID {self.child.pid} on port {bound}", flush=True)
                return mcp.MCP(bound, timeout=CALL_BOUND)
        return None

    def stop(self):
        if self.child is None:
            return
        self.child.terminate()
        try:
            self.child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.child.kill()
            self.child.wait()
        self.child = None


def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    if client is None:
        return {"ok": False, "error": "no instance"}
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def with_project(project, arguments):
    return dict(arguments, project=str(project)) if project else dict(arguments)


def mv_in(folder, name, text, make_folder=False):
    """Writes OUTSIDE the package, then `mkdir` / `mv` — how another process
    lands a file."""
    outside = WORK / f"outside-{name}"
    outside.write_text(text)
    if make_folder:
        bounded.run(["mkdir", "-p", str(folder)], 30)
    return bounded.run(["mv", str(outside), str(Path(folder) / name)], 30)["rc"]


def temp_roots():
    """The untitled roots under `getconf DARWIN_USER_TEMP_DIR`, which TMPDIR
    does not move (G3a measured it)."""
    base = bounded.run(["getconf", "DARWIN_USER_TEMP_DIR"], 30)["stdout"].strip()
    return set(glob.glob(os.path.join(base, "Reelcut", "*-graphics")))


def complaints(log):
    try:
        return [line.strip() for line in open(log) if "Reelcut: " in line]
    except OSError:
        return ["the log could not be read"]


def project_of(client, project):
    got = attempt(client, "get_project", with_project(project, {}))
    return got["reply"]["project"] if got["ok"] else None


def land(client, project, name, track, at):
    """`add_graphic_clip` polled for at most 5 s — a refusal is an answer
    while the store has not seen the module. The new clip, or None and the
    last sentence."""
    deadline = time.monotonic() + 5
    last = ""
    while time.monotonic() < deadline:
        got = attempt(client, "add_graphic_clip",
                      with_project(project, {"name": name, "track": track, "at": at}))
        if got["ok"]:
            clips = (project_of(client, project) or {}).get("clips", [])
            ours = [c for c in clips if (c.get("graphic") or {}).get("name") == name]
            return (max(ours, key=lambda c: c["id"]) if ours else None), ""
        last = got["error"]
        time.sleep(0.2)
    return None, last


def render(client, project, t, tag):
    """`render_frame` at tick `t` into `work/<tag>.png`; its bytes, or None."""
    path = WORK / f"{tag}.png"
    if path.exists():
        path.unlink()
    got = attempt(client, "render_frame", with_project(project, {"t": t, "path": str(path)}))
    if not got["ok"] or not path.exists():
        print(f"  render {tag}: {got.get('error', 'no file')}", flush=True)
        return None
    return path.read_bytes()


def decode_png(data, upto=None):
    """`e1_proof.py`'s 8-bit non-interlaced PNG reader, stopping after row
    `upto` — a pixel near the top needs only the rows above it, which keeps a
    bounded poll from spending its bound on decoding. (width, channels, rows)."""
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
        raise RuntimeError("an 8-bit non-interlaced PNG is the only kind read here")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    out, prev, pos = [], bytearray(stride), 0
    for _ in range(height if upto is None else min(height, upto + 1)):
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
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            raise RuntimeError(f"unknown PNG filter {kind}")
        out.append(bytes(cur))
        prev = cur
    return width, channels, out


def pixel(data, x, y):
    if data is None:
        return None
    _, channels, found = decode_png(data, upto=y)
    row = found[y]
    return tuple(row[x * channels:x * channels + 3])


def poll_pixel(client, project, x, y, want, tag):
    """`render_frame` at frame 30 until (x, y) is `want`, for at most 5 s."""
    deadline = time.monotonic() + 5
    seen = None
    while time.monotonic() < deadline:
        seen = pixel(render(client, project, 30 * FRAME, tag), x, y)
        if seen == want:
            return seen
        time.sleep(0.2)
    return seen


def run_p1_p2(client, p1):
    """P1 and P2 — the rows the mutant is driven through too. The clip, the
    track and frame 30's bytes."""
    made = attempt(client, "new_project", {"path": str(p1)})
    rc = mv_in(p1 / "graphics", "bar.js", bar(), make_folder=True)
    project = project_of(client, p1) or {}
    track = (project.get("tracks") or [{}])[0].get("id")
    clip, why = land(client, p1, "bar", track, 0)
    check("P1 add_graphic_clip {name: bar} lands the stored graphic, 120 frames long",
          made["ok"] and rc == 0 and clip is not None
          and clip["graphic"]["name"] == "bar" and clip["duration"] == 2_400_000,
          f"new {made['ok']}, mv rc {rc}, clip {clip}, last refusal {why!r}")
    f30 = render(client, p1, 30 * FRAME, "p2-f30")
    f31 = render(client, p1, 31 * FRAME, "p2-f31")
    edge_in, edge_out, left = pixel(f30, 122, 50), pixel(f30, 222, 50), pixel(f30, 50, 50)
    check("P2 frame 30: (122,50) is the bar's red and (222,50) black — the frame number, "
          "pinned at both edges; (50,50) black; CONTROL: frame 31 differs",
          edge_in == RED and edge_out == BLACK and left == BLACK
          and f31 is not None and f31 != f30,
          f"(122,50) {edge_in}, (222,50) {edge_out}, (50,50) {left}, "
          f"frame 31 differs {f31 is not None and f31 != f30}")
    return clip, track, f30


def run(app, port):
    log = WORK / f"reelcut-{port}.log"
    p1, p1b, p2, pf, pa = (WORK / f"{n}.reelcut" for n in ("P1", "P1b", "P2", "F", "A"))
    instance = Instance(app, port, log)
    try:
        client = instance.start()
        if client is None:
            check("P1 the app launches", False, "the app never logged its port")
            return log
        clip, track, f30 = run_p1_p2(client, p1)
        cid = clip["id"] if clip else 0

        moved = attempt(client, "move_clip", {"project": str(p1), "clips": [cid],
                                              "delta": 17 * FRAME})
        f47 = render(client, p1, 47 * FRAME, "p3-f47")
        undone = attempt(client, "undo", {"project": str(p1)})
        check("P3 move_clip by 17 frames: frame 47 byte-identical to frame 30",
              moved["ok"] and undone["ok"] and f47 is not None and f47 == f30,
              f"move {moved['ok']}, identical {f47 == f30}")

        before = render(client, p1, 41 * FRAME, "s1-before")
        split = attempt(client, "split", {"project": str(p1), "clips": [cid], "at": 40 * FRAME})
        after = render(client, p1, 41 * FRAME, "s1-after")
        halves = [c for c in (project_of(client, p1) or {}).get("clips", [])
                  if (c.get("graphic") or {}).get("name") == "bar"]
        attempt(client, "undo", {"project": str(p1)})
        check("S1 split at frame 40: frame 41 byte-identical before and after",
              split["ok"] and len(halves) == 2 and before is not None and before == after,
              f"split {split}, halves {len(halves)}, identical {before == after}")

        titled = attempt(client, "set_graphic", {"project": str(p1), "clips": [cid],
                                                 "patch": {"props": {"title": "B"}}})
        changed = render(client, p1, 30 * FRAME, "r1-b")
        refused = attempt(client, "set_graphic", {"project": str(p1), "clips": [cid],
                                                  "patch": {"props": {"nope": 1}}})
        attempt(client, "undo", {"project": str(p1)})
        restored = render(client, p1, 30 * FRAME, "r1-undone")
        check("R1 props {title: B} changes frame 30; {nope: 1} is refused naming props.nope; "
              "one undo restores P2's bytes",
              titled["ok"] and changed is not None and changed != f30
              and not refused["ok"] and "props.nope" in refused["error"]
              and restored == f30,
              f"title {titled['ok']}, changed {changed != f30}, refusal "
              f"{refused.get('error', refused)!r}, restored {restored == f30}")

        rc = mv_in(p1 / "graphics", "bar.js", bar(color="#2d7ff9"))
        seen = poll_pixel(client, p1, 170, 50, BLUE, "h1")
        check("H1 a bar.js whose colour default is #2d7ff9, mv'd in: within 5 s (170,50) is "
              "that blue", rc == 0 and seen == BLUE, f"mv rc {rc}, (170,50) {seen}")

        coloured = attempt(client, "set_graphic", {"project": str(p1), "clips": [cid],
                                                   "patch": {"props": {"color": "#2d7ff9"}}})
        rc = mv_in(p1 / "graphics", "bar.js", bar(with_color=False, width=120))
        landed = poll_pixel(client, p1, 230, 50, BLUE, "l1")
        still = pixel(render(client, p1, 30 * FRAME, "l1-final"), 170, 50)
        check("L1 the stored color survives a schema that dropped it: (170,50) is blue once the "
              "120-wide module has landed at (230,50)",
              coloured["ok"] and rc == 0 and landed == BLUE and still == BLUE,
              f"set {coloured['ok']}, mv rc {rc}, (230,50) {landed}, (170,50) {still}")

        run_f1(client, pf)

        k1_ref = render(client, p1, 30 * FRAME, "k1-before")
        saved = attempt(client, "save_project", {"project": str(p1)})
        instance.stop()
        client = instance.start()
        opened = attempt(client, "open_project", {"path": str(p1)})
        k1_after = render(client, p1, 30 * FRAME, "k1-after")
        check("K1 saved, relaunched, open_project: frame 30 byte-identical",
              saved["ok"] and opened["ok"] and k1_ref is not None and k1_after == k1_ref,
              f"save {saved['ok']}, open {opened['ok']}, identical {k1_after == k1_ref}")

        saved = attempt(client, "save_project", {"project": str(p1), "path": str(p1b)})
        k2 = render(client, p1b, 30 * FRAME, "k2")
        present = (p1b / "graphics" / "bar.js").exists()
        check("K2 save_project {path: P1b}: P1b/graphics/bar.js present, frame 30 identical",
              saved["ok"] and present and k2 == k1_ref,
              f"save {saved}, present {present}, identical {k2 == k1_ref}")

        rate = attempt(client, "set_canvas", {"project": str(p1b), "fps": [30000, 1001]})
        t1 = render(client, p1b, 30 * 20020, "t1")
        check("T1 at 29.97 fps frame 30 is tick 600600, byte-identical to 30 fps frame 30",
              rate["ok"] and t1 is not None and t1 == k1_ref,
              f"set_canvas {rate}, identical {t1 == k1_ref}")

        # A fresh instance, so the untitled draft is the only open document
        # and every call's implicit target is it.
        instance.stop()
        client = instance.start()
        roots = temp_roots()
        made = attempt(client, "new_project", {})
        new_roots = sorted(temp_roots() - roots)
        rc = mv_in(new_roots[0], "bar.js", bar()) if len(new_roots) == 1 else None
        track3 = ((project_of(client, None) or {}).get("tracks") or [{}])[0].get("id")
        clip3, why = land(client, None, "bar", track3, 0)
        k3_ref = render(client, None, 30 * FRAME, "k3-before")
        saved = attempt(client, "save_project", {"path": str(p2)})
        present = (p2 / "graphics" / "bar.js").exists()
        instance.stop()
        client = instance.start()
        opened = attempt(client, "open_project", {"path": str(p2)})
        k3 = render(client, p2, 30 * FRAME, "k3-after")
        check("K3 an untitled project's graphic, saved for the first time and reopened: frame "
              "30 identical",
              made["ok"] and len(new_roots) == 1 and rc == 0 and clip3 is not None
              and saved["ok"] and present and opened["ok"] and k3_ref is not None
              and k3 == k3_ref,
              f"new roots {new_roots}, mv rc {rc}, clip {clip3 is not None} {why!r}, "
              f"save {saved}, present {present}, identical {k3 == k3_ref}")

        run_a1(client, pa)
    finally:
        instance.stop()
    return log


def run_f1(client, pf):
    made = attempt(client, "new_project", {"path": str(pf)})
    rc = mv_in(pf / "graphics", "lower-third.js", (FIXTURES / "lower-third.js").read_text(),
               make_folder=True)
    track = ((project_of(client, pf) or {}).get("tracks") or [{}])[0].get("id")
    clip, why = land(client, pf, "lower-third", track, 0)
    frame = render(client, pf, 30 * FRAME, "f1")
    accent = pixel(frame, 100, 900)
    check("F1 lower-third frame 30: (100,900) is the accent bar's (255,90,54)",
          made["ok"] and rc == 0 and clip is not None and accent == RED,
          f"mv rc {rc}, clip {clip is not None} {why!r}, (100,900) {accent}")
    if frame is None or not FFI_BGRA.exists():
        print(f"  F1 measured: no comparison — {FFI_BGRA} absent (run graphics_ffi_probe.py)",
              flush=True)
        return
    width, channels, found = decode_png(frame)
    bgra = FFI_BGRA.read_bytes()
    mismatched, worst = 0, 0
    for y, row in enumerate(found):
        for x in range(width):
            i, j = x * channels, (y * width + x) * 4
            delta = max(abs(row[i] - bgra[j + 2]), abs(row[i + 1] - bgra[j + 1]),
                        abs(row[i + 2] - bgra[j]))
            if delta:
                mismatched += 1
                worst = max(worst, delta)
    print(f"  F1 measured (not scored): {mismatched} of {width * len(found)} pixels differ "
          f"from the FFI probe's frame-30 BGRA over black; max channel delta {worst}",
          flush=True)


def run_a1(client, pa):
    made = attempt(client, "new_project", {"path": str(pa)})
    rc = mv_in(pa / "graphics", "callout.js", (FIXTURES / "callout.js").read_text(),
               make_folder=True)
    clear = attempt(client, "set_canvas", {"project": str(pa), "background": [0, 0, 0, 0]})
    track = ((project_of(client, pa) or {}).get("tracks") or [{}])[0].get("id")
    clip, why = land(client, pa, "callout", track, 0)
    movie = WORK / "a1.mov"
    exported = attempt(client, "export", {"project": str(pa), "preset": "prores_4444",
                                          "path": str(movie)})
    # Binary output, so not `bounded.run` (a text-mode child); bounded all the same.
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", "2", "-i", str(movie),
                              "-vframes", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
                             capture_output=True, timeout=120,
                             env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        raw = b""
    corner = centre = None
    if len(raw) == 1920 * 1080 * 4:
        corner, centre = raw[3], raw[(432 * 1920 + 1300) * 4 + 3]
    check("A1 transparent canvas + callout as prores_4444, at 2 s: alpha 0 at (0,0), 255 on "
          "the stroke at (1300,432)",
          made["ok"] and rc == 0 and clear["ok"] and clip is not None and exported["ok"]
          and corner == 0 and centre == 255,
          f"clip {clip is not None} {why!r}, export {exported.get('error', 'ok')}, "
          f"decoded {len(raw)} bytes, alpha {corner} / {centre}")


def build_mutant():
    """A COPY of `app/` and `project.yml` with `core/` linked, the anchor
    replaced, built by xcodegen and xcodebuild. The binary, or None and why."""
    copy = WORK / "mutant"
    shutil.rmtree(copy, ignore_errors=True)
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "app", copy / "app")
    shutil.copy(ROOT / "project.yml", copy / "project.yml")
    os.symlink(ROOT / "core", copy / "core")
    target = copy / "app/Sources/LayerRenderersGraphic.swift"
    text = target.read_text()
    if text.count(ANCHOR) != 1:
        return None, f"the anchor occurs {text.count(ANCHOR)} times"
    target.write_text(text.replace(ANCHOR, ANCHOR.replace("frame: frame,", "frame: frame + 1,")))
    generated = bounded.run(["xcodegen", "generate"], 300, cwd=str(copy))
    if generated["rc"] != 0:
        return None, f"xcodegen: {generated['stderr'][-400:]}"
    built = bounded.run(["xcodebuild", "-project", "Reelcut.xcodeproj", "-scheme", "Reelcut",
                         "-configuration", "Release", "-derivedDataPath", "build", "build"],
                        1200, cwd=str(copy))
    binary = copy / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
    if built["rc"] != 0 or not binary.exists():
        return None, f"xcodebuild rc {built['rc']}: {built['stdout'][-600:]}"
    return binary, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4879)
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=["frame-plus-one"])
    args = parser.parse_args()
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    if args.mutant:
        print("G3b graphics — the frame-plus-one MUTANT (P2 must FAIL)", flush=True)
        binary, why = build_mutant()
        if binary is None:
            print(f"  FAIL the mutant builds — {why}")
            return 1
        instance = Instance(binary, args.port, WORK / f"reelcut-{args.port}.log")
        try:
            client = instance.start()
            if client is None:
                print("  FAIL the mutant launches")
                return 1
            run_p1_p2(client, WORK / "M.reelcut")
        finally:
            instance.stop()
        verdict = rows.get("P1") and not rows.get("P2")
        print("the mutant is CAUGHT: P1 held and P2 failed" if verdict
              else "the mutant was NOT caught")
        return 0 if verdict else 1
    print("G3b graphics — a graphic clip drawn, against the built app (proof)", flush=True)
    if not args.app.exists():
        print(f"  FAIL the app is not built: {args.app}")
        print(f"0/{len(ROWS)}")
        return 1
    log = run(args.app, args.port)
    found = complaints(log)
    check("Z1 grep \"Reelcut: \" over every launch's log prints nothing", found == [],
          f"{found[:5]}")
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
