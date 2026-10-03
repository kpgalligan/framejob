#!/usr/bin/env python3
"""Issue #127 — an export's graphics rasterized ahead on worker threads
(spec §11 G-26, `app/Sources/GraphicPrefetch.swift`), against the built app.

The compositor stays the one writer and the texture key decides, so an
export with the prefetch ON must be the serial path's file, and most of its
graphic rasters must come from the workers. Two owned instances, one after
the other, each on a scratch socket, launched and stopped by PID, logs under
`tools/proof/work/graphics-prefetch/`: OFF with `-ReelcutGraphicPrefetchOff
YES`, ON without. Nothing else is ever killed. Every child runs under
`graphics_spike/bounded.py`.

The fixture F, made over MCP on the OFF instance and saved: a 30 fps canvas
(checked through `get_project`); `heavy` (a moving gradient, a
`feGaussianBlur`, an `<image>` of the imported `red.png` and bundled-font
text, all changing every frame) on two overlapping clips with different
props; `static` (the same SVG every frame); `stepped` (its SVG changes every
2nd frame, `Math.floor(frame / 2)`) — each 4 s from 0 — and a 5 s shape clip
underneath, so the last second has no graphic. Exports are `prores_422`;
movies are compared with `video_configuration_proof.py`'s `same_movie`
(byte-equal after masking the `mvhd`/`tkhd`/`mdhd` times).

S0  CONTROL: two OFF exports of F are masked-equal;
S1  the ON export is masked-equal to S0's;
S2  ON's log line `[reelcut] graphic prefetch: …` for that export: hits > 0
    and hits >= 95% of hits + mismatched + missed;
S3  OFF's log has no `graphic prefetch:` line;
S4  ON, a project whose `throw10` throws at frame 10 beside a heavy clip:
    `export` errors naming "throw10" and "frame 10", no file is at the path,
    and that session's log line appears within 10 s;
S5  the probe (`graphics_prefetch_probe.swift`, built like
    `graphics_proof.build_pin_probe` into `work/graphics-prefetch-probe`),
    off then on over F at 25 fps from tick 140 000: both answer success with
    `fps` [25, 1] and `start` 144 000, the two movies are masked-equal, and
    ON's stderr line has hits > 0 and hits >= 95% of hits + mismatched +
    missed. A probe that will not build is a FAIL;
S6  MEASURED, not scored: OFF and ON wall seconds;
Z1  `grep "Reelcut: "` over every log prints nothing.

    python3 tools/proof/graphics_prefetch_proof.py [--app PATH]
    python3 tools/proof/graphics_prefetch_proof.py --mutant worker-frame-plus-one
    python3 tools/proof/graphics_prefetch_proof.py --mutant unguarded
    python3 tools/proof/graphics_prefetch_proof.py --bench PACKAGE [--preset h264]

A mutant is built in a copy of the tree (`graphics_proof.build_mutant`'s
way, its anchors each exactly once in `GraphicPrefetch.swift`):
`worker-frame-plus-one` makes the worker ask `svg` for `frame + 1`, and is
driven through the fixture and one ON export — S2 must FAIL; `unguarded` is
that plus the texture-key comparison removed from `take`, driven through
one OFF and one ON export — S1 must FAIL. Exit 0 = caught, 1 = survived, 2 =
the control could not be performed.

`--bench PACKAGE` copies PACKAGE under `work/` (the original is never
opened), exports the copy OFF then ON (`--preset`, default h264), and prints
`sysctl -n vm.loadavg` before each, both wall times, ON's log line and the
masked comparison. Scored only: both exports succeed.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row
passes.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import tree_copy  # noqa: E402
from video_configuration_proof import same_movie  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-prefetch"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
PROBE_SOURCE = ROOT / "tools/proof/graphics_prefetch_probe.swift"
# Outside WORK, which every run empties, so an up-to-date probe is not rebuilt.
PROBE_DIR = ROOT / "tools/proof/work/graphics-prefetch-probe"
RED_PNG = ROOT / "graphic/tests/assets/red.png"
CALL_BOUND = 900
BENCH_BOUND = 7200
SECOND = 600_000
ROWS = ["S0", "S1", "S2", "S3", "S4", "S5", "Z1"]
LINE = re.compile(r"graphic prefetch: key (\d+), (\d+) workers, (\d+) frames with graphics, "
                  r"(\d+) hits, (\d+) mismatched, (\d+) missed, (\d+) unused")
FIELDS = ("key", "workers", "frames", "hits", "mismatched", "missed", "unused")

WORKER_SVG = "frame: slot.frame, propsJSON: slot.propsJSON, ctxJSON: slot.ctxJSON,"
KEY_GUARD = ", entry.textureKey == textureKey {"
# name: ([(anchor, replacement)] in GraphicPrefetch.swift, the row it must fail)
MUTANTS = {
    "worker-frame-plus-one": (
        [(WORKER_SVG, WORKER_SVG.replace("frame: slot.frame,", "frame: slot.frame + 1,"))],
        "S2"),
    "unguarded": (
        [(WORKER_SVG, WORKER_SVG.replace("frame: slot.frame,", "frame: slot.frame + 1,")),
         (KEY_GUARD, " {")],
        "S1"),
}

HEAVY_JS = """export const meta = { name: "Heavy", durationInFrames: 120 };
export const schema = {
  title: { type: "string", default: "Heavy" },
  hue: { type: "number", default: 40 },
};
export function render(frame, props, ctx) {
  const w = ctx.width, h = ctx.height;
  return svg(ctx, `<defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1"
        gradientTransform="rotate(${frame * 3} 0.5 0.5)">
      <stop offset="0" stop-color="rgb(${props.hue},40,160)"/>
      <stop offset="${0.3 + (frame % 10) / 20}" stop-color="rgb(250,${(frame * 5) % 255},60)"/>
      <stop offset="1" stop-color="rgb(20,180,${props.hue})"/>
    </linearGradient>
    <filter id="b" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="${12 + (frame % 7)}"/>
    </filter></defs>
    <rect x="0" y="0" width="${w}" height="${h}" fill="url(#g)" opacity="0.55"/>
    <g filter="url(#b)">
      <circle cx="${(frame * 13) % w}" cy="${h / 2}" r="${h / 4}" fill="rgb(${props.hue},200,90)"/>
      <image href="${asset("red.png")}" x="${100 + frame * 6}" y="${120 + frame}"
          width="480" height="480"/>
    </g>
    <text x="${120 + frame * 4}" y="${h - 160}" font-family="'Source Sans 3'"
        font-weight="700" font-size="140" fill="#ffffff">${escapeXml(props.title)} ${frame}</text>`);
}
"""
STATIC_JS = """export const meta = { name: "Static", durationInFrames: 120 };
export function render(frame, props, ctx) {
  return svg(ctx, `<rect x="60" y="60" width="420" height="160" fill="#2d7ff9"/>
    <text x="90" y="170" font-family="'IBM Plex Mono'" font-size="64"
        fill="#ffffff">STATIC</text>`);
}
"""
STEPPED_JS = """export const meta = { name: "Stepped", durationInFrames: 120 };
export function render(frame, props, ctx) {
  const step = Math.floor(frame / 2);
  return svg(ctx, `<rect x="${200 + step * 12}" y="820" width="260" height="120" fill="#ffcc00"/>
    <text x="${220 + step * 12}" y="900" font-family="Anton" font-size="72"
        fill="#101014">${step}</text>`);
}
"""
THROW10_JS = """export const meta = { name: "Throw10", durationInFrames: 120 };
export function render(frame, props, ctx) {
  if (frame === 10) throw new Error("boom at ten");
  return svg(ctx, `<rect x="0" y="0" width="100" height="100" fill="#ff5a36"/>`);
}
"""

rows = {}
logs = []


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'ok' if good else 'FAIL'} — {detail}", flush=True)


class Instance:
    """One owned app, by PID; `off` launches it with the prefetch's switch
    on. Each launch reads only the part of the log it appended."""

    def __init__(self, app, log, off):
        self.app, self.log, self.off = app, log, off
        self.socket = mcp.scratch_socket()
        self.child = None
        logs.append(log)

    def start(self, timeout=CALL_BOUND):
        offset = self.log.stat().st_size if self.log.exists() else 0
        extra = ["-ReelcutGraphicPrefetchOff", "YES"] if self.off else []
        with open(self.log, "a") as out:
            self.child = subprocess.Popen(
                [str(self.app), "-ApplePersistenceIgnoreState", "YES"] + extra,
                stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
                env=bounded.child_env({"RC_AGENT_SOCKET": self.socket}))
        if mcp.wait_listening(self.log, self.socket, child=self.child, seconds=60,
                              offset=offset):
            print(f"  {'OFF' if self.off else 'ON'} instance PID {self.child.pid} at "
                  f"{self.socket}", flush=True)
            return mcp.MCP(self.socket, timeout=timeout)
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
        mcp.remove_scratch(self.socket)


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


def project_of(client, package):
    got = attempt(client, "get_project", {"project": str(package)})
    return got["reply"].get("project", {}) if got["ok"] and isinstance(got["reply"], dict) else {}


def land(client, package, name, track, extra=None):
    """`add_graphic_clip` at 0 for 4 s, polled for at most 5 s while the
    store has not seen the module. (ok, last answer)."""
    deadline = time.monotonic() + 5
    got = {"ok": False, "error": "not tried"}
    while time.monotonic() < deadline:
        got = attempt(client, "add_graphic_clip",
                      dict({"project": str(package), "name": name, "track": track, "at": 0,
                            "duration": 4 * SECOND}, **(extra or {})))
        if got["ok"]:
            return True, ""
        time.sleep(0.2)
    return False, got.get("error", "")


def graphic_project(client, package, modules, clips, tail):
    """A new project at `package`: a 30 fps canvas, red.png imported, each
    module written, one track per clip (front last), each clip 4 s at 0,
    and with `tail` a 5 s shape clip on the bottom track. Saved. (ok,
    detail)."""
    steps, bad = [], []

    def step(label, ok, detail=""):
        steps.append(f"{label} {'ok' if ok else 'FAILED ' + str(detail)}")
        if not ok:
            bad.append(label)

    made = attempt(client, "new_project", {"path": str(package)})
    step("new", made["ok"], made.get("error"))
    attempt(client, "set_canvas", {"project": str(package), "fps": [30, 1]})
    fps = project_of(client, package).get("canvas", {}).get("fps")
    step("30 fps", fps == [30, 1], fps)
    asset = attempt(client, "import_graphic_asset", {"project": str(package),
                                                     "path": str(RED_PNG)})
    step("asset", asset["ok"], asset.get("error"))
    for name, source in modules:
        wrote = attempt(client, "write_graphic", {"project": str(package), "name": name,
                                                  "source": source})
        ok = wrote["ok"] and isinstance(wrote["reply"], dict) and wrote["reply"].get("ok")
        step(f"write {name}", ok, wrote.get("error", wrote.get("reply")))
    for _ in clips:
        attempt(client, "add_track", {"project": str(package)})
    tracks = [t.get("id") for t in project_of(client, package).get("tracks", [])]
    step("tracks", len(tracks) >= len(clips) + 1, tracks)
    if bad:
        return False, "; ".join(steps)
    if tail:
        shaped = attempt(client, "add_shape_clip", {"project": str(package), "track": tracks[0],
                                                    "at": 0, "duration": 5 * SECOND})
        step("tail", shaped["ok"], shaped.get("error"))
    for track, (name, props) in zip(tracks[1:], clips):
        ok, why = land(client, package, name, track, {"props": props} if props else None)
        step(f"clip {name}", ok, why)
    saved = attempt(client, "save_project", {"project": str(package)})
    step("saved", saved["ok"], saved.get("error"))
    return not bad, "; ".join(steps)


def fixture(client, package):
    return graphic_project(
        client, package,
        [("heavy", HEAVY_JS), ("static", STATIC_JS), ("stepped", STEPPED_JS)],
        [("heavy", {"title": "Alpha", "hue": 40}), ("heavy", {"title": "Beta", "hue": 210}),
         ("static", None), ("stepped", None)],
        tail=True)


def log_size(log):
    return log.stat().st_size if log.exists() else 0


def lines_since(log, offset):
    """Every prefetch line appended to `log` after `offset`, as dicts."""
    try:
        with open(log, errors="replace") as handle:
            handle.seek(offset)
            text = handle.read()
    except OSError:
        return []
    return [dict(zip(FIELDS, map(int, m.groups()))) for m in LINE.finditer(text)]


def await_line(log, offset, seconds=10):
    deadline = time.monotonic() + seconds
    while True:
        found = lines_since(log, offset)
        if found or time.monotonic() >= deadline:
            return found[-1] if found else None
        time.sleep(0.25)


def share(line):
    """(hits > 0 and hits >= 95% of the taken, the percentage)."""
    if not line:
        return False, None
    taken = line["hits"] + line["mismatched"] + line["missed"]
    percent = 100.0 * line["hits"] / taken if taken else 0.0
    return line["hits"] > 0 and line["hits"] >= 0.95 * taken, round(percent, 2)


def written(stem):
    """The file an export wrote at `stem` (its extension is the
    container's), or None."""
    found = sorted(stem.parent.glob(stem.name + ".*"))
    return found[0] if found else None


def export(client, package, stem, preset="prores_422"):
    """(ok, error, wall seconds, the file)."""
    for old in stem.parent.glob(stem.name + ".*"):
        old.unlink()
    started = time.monotonic()
    got = attempt(client, "export", {"project": str(package), "preset": preset,
                                     "path": str(stem)})
    seconds = round(time.monotonic() - started, 2)
    return got["ok"], got.get("error", ""), seconds, written(stem)


def opened(client, package):
    return attempt(client, "open_project", {"path": str(package)})["ok"]


def complaints():
    found = []
    for log in logs:
        try:
            found += [line.strip() for line in open(log, errors="replace") if "Reelcut: " in line]
        except OSError:
            found.append(f"{log} could not be read")
    return found


def loadavg():
    return bounded.run(["sysctl", "-n", "vm.loadavg"], 30)["stdout"].strip()


# ---- the probe --------------------------------------------------------------

def build_probe():
    """`graphics_prefetch_probe.swift` as `main.swift` over every other file
    in `app/Sources`, with the app's `Fonts`, `Blank.mp4` and a
    `default.metallib` of `Compositor.metal` beside it —
    `graphics_proof.build_pin_probe`'s build. Rebuilt only when stale. The
    binary, or None and why."""
    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    binary = PROBE_DIR / "graphics_prefetch_probe"
    entry = PROBE_DIR / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    fonts = PROBE_DIR / "Fonts"
    resources = ROOT / "app/Resources"
    if not fonts.is_dir() or (resources / "Fonts").stat().st_mtime > fonts.stat().st_mtime:
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(resources / "Fonts", fonts)
    if not (PROBE_DIR / "Blank.mp4").exists():
        shutil.copy2(resources / "Blank.mp4", PROBE_DIR / "Blank.mp4")
    shader = resources / "Shaders/Compositor.metal"
    metallib, air = PROBE_DIR / "default.metallib", PROBE_DIR / "Compositor.air"
    if not metallib.exists() or shader.stat().st_mtime > metallib.stat().st_mtime:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o",
                            str(air)], 300)
        if step["rc"] == 0:
            step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                                str(metallib)], 300)
        if step["rc"] != 0 or not metallib.exists():
            return None, f"the shader did not build: {step['stderr'][-400:]}"
    sources = sorted(path for path in (ROOT / "app/Sources").glob("*.swift")
                     if path.name != "main.swift")
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if binary.exists() and all(path.stat().st_mtime < binary.stat().st_mtime
                               for path in sources + [entry, lib]):
        return binary, ""
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    built = bounded.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
         "-L", str(lib.parent), "-lreelcut_core"]
        + [str(path) for path in sources] + [str(entry), "-o", str(binary)], 900)
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = built["stderr"].strip().splitlines()[-4:]
        return None, f"swiftc rc {built['rc']}: {(errors or tail or ['(no output)'])[:6]}"
    return binary, ""


def run_probe(binary, package, mode):
    """(the JSON answer, the movie, the stderr prefetch line or None)."""
    movie = WORK / f"s5-{mode}.mov"
    if movie.exists():
        movie.unlink()
    got = bounded.run([str(binary), str(package), str(movie), mode], 900)
    try:
        answer = json.loads(got["stdout"].strip().splitlines()[-1])
    except (IndexError, ValueError):
        answer = {"error": f"rc {got['rc']}, expired {got['expired']}: "
                           f"{(got['stdout'] + got['stderr'])[-400:]}"}
    found = [dict(zip(FIELDS, map(int, m.groups()))) for m in LINE.finditer(got["stderr"])]
    return answer, movie, (found[-1] if found else None)


def run_s5(package):
    binary, why = build_probe()
    if binary is None:
        check("S5", False, f"the probe did not build — {why}")
        return
    off, off_movie, off_line = run_probe(binary, package, "off")
    on, on_movie, on_line = run_probe(binary, package, "on")
    answers_ok = all(a.get("outcome") == "success" and a.get("fps") == [25, 1]
                     and a.get("start") == 144000 for a in (off, on))
    same, detail = (same_movie(str(off_movie), str(on_movie))
                    if off_movie.exists() and on_movie.exists() else (False, "a movie is missing"))
    hits_ok, percent = share(on_line)
    check("S5", answers_ok and same and hits_ok and off_line is None,
          f"probe at 25 fps from 140000: off {off}, on {on}; {detail}; ON line {on_line} "
          f"({percent}% hits); OFF line {off_line}")


# ---- the rows ---------------------------------------------------------------

def run_all(app):
    package = WORK / "F.reelcut"
    off_log, on_log = WORK / "off.log", WORK / "on.log"

    off = Instance(app, off_log, off=True)
    walls = {}
    try:
        client = off.start()
        made, detail = fixture(client, package) if client else (False, "OFF did not launch")
        print(f"  fixture: {made} {detail}", flush=True)
        ok_a, err_a, walls["off"], movie_a = export(client, package, WORK / "s0-a")
        ok_b, err_b, _, movie_b = export(client, package, WORK / "s0-b")
    finally:
        off.stop()
    same, detail = (same_movie(str(movie_a), str(movie_b)) if movie_a and movie_b
                    else (False, f"a: {ok_a} {err_a!r}, b: {ok_b} {err_b!r}"))
    check("S0", made and ok_a and ok_b and same, f"CONTROL two OFF exports: {detail}")

    on = Instance(app, on_log, off=False)
    try:
        client = on.start()
        reopened = opened(client, package)
        offset = log_size(on_log)
        ok_on, err_on, walls["on"], movie_on = export(client, package, WORK / "s1-on")
        line = await_line(on_log, offset)
        same, detail = (same_movie(str(movie_a), str(movie_on)) if movie_a and movie_on
                        else (False, f"on: {ok_on} {err_on!r}"))
        check("S1", reopened and ok_on and same, f"ON against OFF: {detail}")
        hits_ok, percent = share(line)
        check("S2", hits_ok, f"ON's line {line} ({percent}% hits)")
        lines_off = lines_since(off_log, 0)
        check("S3", lines_off == [], f"OFF's prefetch lines {lines_off}")

        throw = WORK / "T.reelcut"
        made_t, detail_t = graphic_project(
            client, throw, [("heavy", HEAVY_JS), ("throw10", THROW10_JS)],
            [("heavy", None), ("throw10", None)], tail=False)
        offset = log_size(on_log)
        ok_t, err_t, _, left = export(client, throw, WORK / "s4-throw")
        stopped = time.monotonic()
        line_t = await_line(on_log, offset, 10)
        waited = round(time.monotonic() - stopped, 2)
        check("S4", made_t and not ok_t and '"throw10"' in err_t and "frame 10" in err_t
              and left is None and line_t is not None,
              f"setup {made_t} {detail_t if not made_t else ''}; export {ok_t} {err_t!r}, "
              f"left {left}, line {line_t} after {waited} s")
    finally:
        on.stop()

    run_s5(package)
    cpus = bounded.run(["sysctl", "-n", "hw.activecpu"], 30)["stdout"].strip()
    print(f"S6 MEASURED — prores_422 of F: OFF {walls.get('off')} s, ON {walls.get('on')} s "
          f"({cpus} active CPUs)", flush=True)
    found = complaints()
    check("Z1", found == [], f"{found[:5]}")


def build_mutant(name):
    """A copy of the tree with each of the mutant's anchors replaced exactly
    once in `GraphicPrefetch.swift`, built by its own `make app`. The binary,
    or None and why."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    target = copy / "app/Sources/GraphicPrefetch.swift"
    text = target.read_text()
    for anchor, replacement in MUTANTS[name][0]:
        if text.count(anchor) != 1:
            return None, f"{anchor!r} occurs {text.count(anchor)} times"
        text = text.replace(anchor, replacement)
    target.write_text(text)
    built = bounded.run(["make", "app"], 1500, cwd=str(copy))
    binary = copy / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error:" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    return binary, ""


def run_mutant(name):
    row = MUTANTS[name][1]
    print(f"graphics prefetch — the {name} MUTANT ({row} must FAIL)", flush=True)
    binary, why = build_mutant(name)
    if binary is None:
        print(f"mutant {name}: the control could not be performed — the copy was not built: "
              f"{why}")
        return 2
    package = WORK / "M.reelcut"
    on_log = WORK / "mutant-on.log"
    movie_off = None
    if name == "unguarded":
        off = Instance(binary, WORK / "mutant-off.log", off=True)
        try:
            client = off.start()
            made, detail = fixture(client, package) if client else (False, "did not launch")
            ok, err, _, movie_off = export(client, package, WORK / "m-off")
        finally:
            off.stop()
        if not (made and ok and movie_off):
            print(f"mutant {name}: the control could not be performed — the OFF fixture or "
                  f"export did not hold: {detail} {err!r}")
            return 2
    on = Instance(binary, on_log, off=False)
    try:
        client = on.start()
        if name == "unguarded":
            made, detail = opened(client, package), "reopen"
        else:
            made, detail = fixture(client, package) if client else (False, "did not launch")
        offset = log_size(on_log)
        ok, err, _, movie_on = export(client, package, WORK / "m-on")
        line = await_line(on_log, offset)
    finally:
        on.stop()
    if not (made and ok and movie_on and line):
        print(f"mutant {name}: the control could not be performed — setup {made} {detail}, "
              f"export {ok} {err!r}, line {line}")
        return 2
    if name == "unguarded":
        same, detail = same_movie(str(movie_off), str(movie_on))
        check("S1", same, f"mutant ON against OFF: {detail}")
    else:
        hits_ok, percent = share(line)
        check("S2", hits_ok, f"mutant ON's line {line} ({percent}% hits)")
    caught = not rows.get(row)
    print(f"the mutant is CAUGHT: {row} FAILED" if caught else "the mutant was NOT caught")
    return 0 if caught else 1


def run_bench(app, source, preset):
    print(f"graphics prefetch — bench of {source} ({preset}), OFF then ON", flush=True)
    if not source.is_dir():
        print(f"bench FAIL — {source} is not a package")
        return 1
    package = WORK / "bench" / source.name
    shutil.copytree(source, package, symlinks=True)
    results = {}
    for mode, off in (("off", True), ("on", False)):
        log = WORK / f"bench-{mode}.log"
        instance = Instance(app, log, off=off)
        try:
            client = instance.start(timeout=BENCH_BOUND)
            ok_open = opened(client, package)
            load = loadavg()
            offset = log_size(log)
            ok, err, wall, movie = export(client, package, WORK / f"bench-{mode}", preset)
            line = await_line(log, offset) if not off else None
        finally:
            instance.stop()
        results[mode] = (ok_open and ok, err, wall, movie, line)
        print(f"  {mode.upper()}: load average before {load}; open {ok_open}, export {ok} "
              f"{err!r}, {wall} s, {movie}", flush=True)
    line = results["on"][4]
    _, percent = share(line)
    print(f"  ON's line: {line} ({percent}% hits)", flush=True)
    cpus = bounded.run(["sysctl", "-n", "hw.activecpu"], 30)["stdout"].strip()
    print(f"  {cpus} active CPUs; OFF {results['off'][2]} s, ON {results['on'][2]} s", flush=True)
    if results["off"][3] and results["on"][3]:
        same, detail = same_movie(str(results["off"][3]), str(results["on"][3]))
        print(f"  masked comparison: {'equal' if same else 'DIFFERENT'} — {detail}", flush=True)
    good = results["off"][0] and results["on"][0]
    print(f"bench {'ok' if good else 'FAIL'} — both exports succeeded: "
          f"OFF {results['off'][0]}, ON {results['on'][0]}")
    return 0 if good else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--bench", type=Path)
    parser.add_argument("--preset", default="h264")
    args = parser.parse_args()
    tree_copy.remove_tree(WORK)
    WORK.mkdir(parents=True)
    if args.mutant:
        return run_mutant(args.mutant)
    if not args.app.exists():
        print(f"the app is not built: {args.app}")
        return 1
    if args.bench:
        return run_bench(args.app, args.bench.expanduser().resolve(), args.preset)
    print("#127 graphics prefetch — an export's graphics rasterized ahead on worker threads, "
          "against the built app (proof)", flush=True)
    run_all(args.app)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
