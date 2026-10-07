#!/usr/bin/env python3
"""Issue batch B1, against the built app: the export gate follows nests at
any depth (#73), `import_media` waits as long as an ffmpeg conversion may
legitimately run (#67), and an export's Cancel during the loudness
measurement only sets a flag — the measurement's own loop cancels its reader
(#74, spec §11 G-17).

One owned instance on a scratch socket (`mcp.scratch_socket`), launched with
`-ApplePersistenceIgnoreState YES
-RCFFmpegImport always -RCFFmpegPath <work>/standin/ffmpeg`, stopped by PID,
its log at `tools/proof/work/export-cancel/reelcut.log`; nothing else
is ever killed. **The instance runs in a scratch home** (issue batch B82,
#236): `CFFIXED_USER_HOME=<work>/home`, made bare, so the `Rewrapped/` I1's
conversion lands in is `<work>/home/Library/Application Support/Reelcut/
Rewrapped/`; the gate, import and cancel groups all use that one instance.
The M rows' probe (`export_cancel_probe`) keeps the caller's environment.
Nothing outside `tools/proof/work/` and the scratch socket's own temporary
folder (`mcp.scratch_socket`, removed when the instance stops) is written,
except the app's and the probe's own `UserDefaults` domains, which that
batch does not move.
Every child runs under `graphics_spike/bounded.py`. The M rows
run `export_cancel_probe.swift`, an in-process instrument built like
`graphics_proof.py`'s pin probe into `tools/proof/work/export-cancel-probe/`
(through `swift_build.py`, reused when every input is byte-identical to a
cached build's; the line reads `probe: built …` or `probe: up to date …`); a
probe that will not build scores M0–M2 as FAILURES.

G1  (CONTROL) `new_project`; `write_graphic gate` (compiles, 30 frames, one
    rect); `add_graphic_clip gate` at 0; `nest` it; `add_text_clip` right
    after the nest clip; `nest` both. `get_project`: timeline nest clip →
    nest B holding a nest clip → nest A holding the `gate` clip. `export
    h264` succeeds and the file exists.
G2  `write_graphic gate` with a syntax error answers `ok: false`; a sentinel
    file at the path; `export h264` to it is an error starting "The export
    was not started:" naming "gate", and the sentinel's bytes are unchanged.
I1  stand-in `ffprobe` (fixed JSON: one h264 640×360 30/1 stream, 10 s) and
    `ffmpeg` (sleeps 45 s, copies `media/A.mov` to its last argument, then
    touches `standin/ffmpeg.exited`); `import_media` of a 4096-byte
    `slow-<hex>.mkv` answers ok after ≥ 45 s, kind video, 640×360, a `.mov`
    directly inside the scratch home's Rewrapped. When
    `<work>/home/Library/Application Support` is not a directory the scratch
    home did not take: I1 FAILS and no import is made. Cleanup, whatever it
    answered and before the
    instance stops: wait for `ffmpeg.exited` (120 s from the call's start),
    then for no `slow-<hex>-*.partial.mov` (10 s), then delete every
    Rewrapped entry starting `slow-<hex>-` (parent-checked) and the fixture.
    An expired bound fails the row and names the leftovers.
M0  (CONTROL) a 60 s noise WAV (`NOISE_SECONDS`, 300 before issue batch
    B13) imported over MCP onto four tracks with `noise_reduction: 1.0`,
    saved; the probe's uncancelled run is `success` with a measurement
    `window` ≥ `WINDOW_FLOOR` (8.0 s).
M1  `--runs` probe runs, each cancelling `delay` s (uniform in
    [0.2, window/2]) into the measurement: every run rc 0 (a signal or an
    expiry is a crash), `phase_at_cancel` "Measuring loudness…", `outcome`
    `cancelled`, `left` false. Prints the crash count.
M2  every M1 `latency` ≤ `LATENCY_BOUND` (2.0 s; 1.0 s before B13, when two
    full runs printed 0.889 s and 0.790 s).
Z1  `grep "Reelcut: "` over this launch's log prints nothing.

    python3 tools/proof/export_cancel_proof.py [--app PATH]
        [--only gate,import,cancel] [--runs 30] [--mutant NAME]

`--mutant NAME` (implies `--only cancel`; the tree's app still builds the
fixture) builds the probe over a copy of `app/Sources` under
`work/export-cancel-mutants/<name>/` with each of `MUTANTS[name]`'s texts
replaced exactly once, and runs M0–M2 on it: `no-loop-check` removes the
measurement loop's `guard !isCancelled` (M2 must FAIL); `old-cancel` puts
back #74's shape, `cancel()` cancelling the measurement's reader from main
(M1 is its row). Exit 1 when the named row FAILED (caught), 0 when it passed
(survived), and 2 — rule R — when the control could not be performed: the
copy, an anchor, the build, the fixture or M0 failed, or the row was never
scored, printed as `mutant <name>: the control could not be performed —
<why>`. On this fixture `old-cancel` was caught once in issue batch B13 — 1
crash in 30 cancels (AVFoundation's "Cannot remove a listener … for
AssetReader_Failed … that was never added", rc −5), where the tree's own run
had 0 in 30 — which is one run's evidence: a rerun can survive, and a
survivor says nothing about the tree until it is repeated.

The summary line ends with the run's wall time, ` in <N> s`.
"""

import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import time
import uuid
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/export-cancel"
STANDIN = WORK / "standin"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
PROBE_SOURCE = ROOT / "tools/proof/export_cancel_probe.swift"
# Outside WORK, which every run empties, so an up-to-date probe is not rebuilt.
PROBE_DIR = ROOT / "tools/proof/work/export-cancel-probe"
SOURCES = ROOT / "app/Sources"
A_MOV = ROOT / "tools/proof/media/A.mov"
# The instance's scratch home (B82), made bare after WORK is remade.
HOME = WORK / "home"
REWRAPPED = HOME / "Library/Application Support/Reelcut/Rewrapped"
CALL_BOUND = 600
FFMPEG_SLEEP = 45
NOISE_SECONDS = 60
NOISE_TRACKS = 4
WINDOW_FLOOR = 8.0
LATENCY_BOUND = 2.0
MUTANT_WORK = ROOT / "tools/proof/work/export-cancel-mutants"
# name → (the row it must fail, [(file in app/Sources, before — exactly once, after)])
MUTANTS = {
    "no-loop-check": ("M2", [
        ("ExporterLoudness.swift",
         "            guard !isCancelled else {\n"
         "                reader.cancelReading()\n"
         "                return nil\n"
         "            }\n",
         ""),
    ]),
    "old-cancel": ("M1", [
        ("Exporter.swift", "    var measuring = false\n",
         "    var measuring = false\n    var measureReader: AVAssetReader?\n"),
        ("ExporterLoudness.swift", "        measuring = true\n",
         "        measuring = true\n        measureReader = reader\n"),
        ("ExporterLoudness.swift", "            measuring = false\n",
         "            measuring = false\n            measureReader = nil\n"),
        ("Exporter.swift", "setCancelRequested(true)\n        writer?.cancel()\n",
         "setCancelRequested(true)\n        lock.lock()\n        let reader = measureReader\n"
         "        lock.unlock()\n        reader?.cancelReading()\n        writer?.cancel()\n"),
    ]),
}
GROUPS = {"gate": ["G1", "G2"], "import": ["I1"], "cancel": ["M0", "M1", "M2"]}
ORDER = ["G1", "G2", "I1", "M0", "M1", "M2", "Z1"]
rows = {}
instrument_rows = set()

GATE_JS = ("export const meta = { name: \"Gate\", durationInFrames: 30 };\n"
           "export function render(frame, props, ctx) {\n"
           "  return svg(ctx, `<rect x=\"0\" y=\"0\" width=\"200\" height=\"200\" "
           "fill=\"#ff5a36\"/>`);\n}\n")
BROKEN_JS = ("export const meta = { name: ;\n"
             "export function render(frame, props, ctx) {\n"
             "  return svg(ctx, ``);\n}\n")
FFPROBE_JSON = json.dumps({
    "streams": [{"index": 0, "codec_type": "video", "codec_name": "h264", "width": 640,
                 "height": 360, "avg_frame_rate": "30/1"}],
    "format": {"duration": "10.0", "size": "4096"},
})


def check(name, good, detail="", *, instrument=False):
    rows[name.split()[0]] = bool(good)
    if instrument and not good:
        instrument_rows.add(name.split()[0])
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


class Instance:
    """One owned app, by PID, on a scratch socket of its own."""

    def __init__(self, app, log):
        self.app, self.log = app, log
        self.socket = mcp.scratch_socket()
        self.child = None

    def start(self):
        with open(self.log, "a") as out:
            self.child = subprocess.Popen(
                [str(self.app), "-ApplePersistenceIgnoreState", "YES",
                 "-RCFFmpegImport", "always",
                 "-RCFFmpegPath", str(STANDIN / "ffmpeg")],
                stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
                env=bounded.child_env({"RC_AGENT_SOCKET": self.socket,
                                       "CFFIXED_USER_HOME": str(HOME)}))
        if mcp.wait_listening(self.log, self.socket, child=self.child, seconds=60):
            print(f"  instance PID {self.child.pid} at {self.socket}", flush=True)
            return mcp.MCP(self.socket, timeout=CALL_BOUND)
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


def project_of(client, project):
    got = attempt(client, "get_project", {"project": str(project)})
    return got["reply"].get("project") if got["ok"] and isinstance(got["reply"], dict) else None


def tool_message(error, tool):
    prefix = f"{tool}: "
    return error[len(prefix):] if error.startswith(prefix) else error


# ---- the probe --------------------------------------------------------------

def build_probe(sources=None, probe_dir=None):
    """`export_cancel_probe.swift` as `main.swift` over every other file in
    `sources`, through `swift_build.build`, with the app's `Fonts`,
    `Blank.mp4` and a `default.metallib` of `Compositor.metal` beside it, in
    `probe_dir`. Reused when every input is byte-identical to a cached
    build's. The binary, or None and why.
    `None` for either argument means the module's `SOURCES` / `PROBE_DIR`,
    read at call time, so an importer that sets them is heard."""
    sources = SOURCES if sources is None else sources
    probe_dir = PROBE_DIR if probe_dir is None else probe_dir
    probe_dir.mkdir(parents=True, exist_ok=True)
    binary = probe_dir / "export_cancel_probe"
    entry = probe_dir / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    fonts = probe_dir / "Fonts"
    resources = ROOT / "app/Resources"
    if not fonts.is_dir() or (resources / "Fonts").stat().st_mtime > fonts.stat().st_mtime:
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(resources / "Fonts", fonts)
    if not (probe_dir / "Blank.mp4").exists():
        shutil.copy2(resources / "Blank.mp4", probe_dir / "Blank.mp4")
    shader = resources / "Shaders/Compositor.metal"
    metallib, air = probe_dir / "default.metallib", probe_dir / "Compositor.air"
    if not metallib.exists() or shader.stat().st_mtime > metallib.stat().st_mtime:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o",
                            str(air)], 300)
        if step["rc"] == 0:
            step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                                str(metallib)], 300)
        if step["rc"] != 0 or not metallib.exists():
            return None, f"the shader did not build: {step['stderr'][-400:]}"
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, defines=["REELCUT_DEV_TOOLS"], timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc rc {error.rc if error.rc is not None else 'before running'}: "
                      f"{(error.diagnostics or ['(no output)'])[:6]}")
    print(f"  probe: up to date — {binary}" if built.reused
          else f"  probe: built in {built.seconds:.0f} s — {binary}", flush=True)
    return binary, ""


def mutant_sources(name):
    """(MUTANT_WORK/<name>/Sources, "") — `app/Sources/*.swift` copied with
    each of the mutant's `before` texts replaced exactly once — or (None, why)."""
    _, edits = MUTANTS[name]
    target = MUTANT_WORK / name / "Sources"
    try:
        shutil.rmtree(target, ignore_errors=True)
        target.mkdir(parents=True)
        for path in sorted((ROOT / "app/Sources").glob("*.swift")):
            shutil.copy2(path, target / path.name)
        for file, before, after in edits:
            text = (target / file).read_text() if (target / file).exists() else ""
            if text.count(before) != 1:
                return None, f"{file} holds {before!r} {text.count(before)} times, not once"
            (target / file).write_text(text.replace(before, after))
    except OSError as error:
        return None, f"the copy could not be made: {error}"
    return target, ""


def run_probe(binary, package, tag, delay):
    """One probe run: its JSON answer (with `rc` and `expired`), or an error."""
    out = WORK / f"{tag}.m4a"
    got = bounded.run([str(binary), str(package), str(out), f"{delay:.3f}"], 400)
    answer = {}
    try:
        answer = json.loads(got["stdout"].strip().splitlines()[-1])
    except (IndexError, ValueError):
        answer = {"error": f"no answer: {(got['stdout'] + got['stderr'])[-300:]!r}"}
    answer["rc"], answer["expired"] = got["rc"], got["expired"]
    return answer


# ---- G1, G2 -----------------------------------------------------------------

def land(client, project, name, track, at):
    """`add_graphic_clip` polled for at most 5 s while the store sees the
    module land. The new clip, or None and the last sentence."""
    deadline = time.monotonic() + 5
    last = ""
    while time.monotonic() < deadline:
        got = attempt(client, "add_graphic_clip",
                      {"project": str(project), "name": name, "track": track, "at": at})
        if got["ok"]:
            clips = (project_of(client, project) or {}).get("clips", [])
            ours = [c for c in clips if (c.get("graphic") or {}).get("name") == name]
            return (max(ours, key=lambda c: c["id"]) if ours else None), ""
        last = got["error"]
        time.sleep(0.2)
    return None, last


def nest_kind(clip):
    source = clip.get("source") or {}
    return source.get("project") if source.get("kind") == "nest" else None


def run_gate(client):
    pkg = WORK / "gate.reelcut"
    made = attempt(client, "new_project", {"path": str(pkg)})
    wrote = attempt(client, "write_graphic", {"project": str(pkg), "name": "gate",
                                              "source": GATE_JS})
    track = ((project_of(client, pkg) or {}).get("tracks") or [{}])[0].get("id")
    clip, why = land(client, pkg, "gate", track, 0)
    first = attempt(client, "nest", {"project": str(pkg), "clips": [clip["id"]] if clip else []})
    top = (project_of(client, pkg) or {}).get("clips", [])
    inner = [c for c in top if nest_kind(c) is not None]
    text = attempt(client, "add_text_clip", {
        "project": str(pkg), "track": track,
        "at": inner[0]["start"] + inner[0]["duration"] if inner else 0})
    top = (project_of(client, pkg) or {}).get("clips", [])
    texts = [c for c in top if nest_kind(c) is None]
    second = attempt(client, "nest", {"project": str(pkg),
                                      "clips": [c["id"] for c in inner + texts]})
    project = project_of(client, pkg) or {}
    nests = {n["id"]: n for n in project.get("nests", [])}
    top = project.get("clips", [])
    b = nests.get(nest_kind(top[0])) if len(top) == 1 else None
    b_nest = [c for c in (b or {}).get("clips", []) if nest_kind(c) is not None]
    a = nests.get(nest_kind(b_nest[0])) if len(b_nest) == 1 else None
    a_gate = [c for c in (a or {}).get("clips", [])
              if (c.get("graphic") or {}).get("name") == "gate"]
    shape = (len(top) == 1 and b is not None and len(b_nest) == 1
             and len((b or {}).get("clips", [])) == 2 and a is not None and len(a_gate) == 1)
    movie = WORK / "g1.mp4"
    exported = attempt(client, "export", {"project": str(pkg), "preset": "h264",
                                          "path": str(movie)})
    check("G1 (CONTROL) timeline nest clip → nest B holding a nest clip → nest A holding the "
          "compiling `gate` clip; export h264 succeeds and the file exists",
          made["ok"] and wrote["ok"] and (wrote["reply"] or {}).get("ok") is True
          and clip is not None and first["ok"] and text["ok"] and second["ok"] and shape
          and exported["ok"] and movie.exists(),
          f"new {made['ok']}, write {wrote.get('error', 'ok')}, clip {clip is not None} "
          f"{why!r}, nest {first.get('error', 'ok')}, text {text.get('error', 'ok')}, "
          f"nest {second.get('error', 'ok')}, shape {shape} (top {len(top)}, B clips "
          f"{len((b or {}).get('clips', []))}, A gate clips {len(a_gate)}), export "
          f"{exported.get('error', 'ok')}, file {movie.exists()}")

    broken = attempt(client, "write_graphic", {"project": str(pkg), "name": "gate",
                                               "source": BROKEN_JS})
    # The store's set changes when it sees the file; poll get_project's view.
    deadline, seen = time.monotonic() + 5, None
    while time.monotonic() < deadline:
        graphics = (attempt(client, "get_project", {"project": str(pkg)}).get("reply")
                    or {}).get("graphics") or []
        seen = [g.get("ok") for g in graphics if g.get("name") == "gate"]
        if seen == [False]:
            break
        time.sleep(0.2)
    sentinel = WORK / "g2.mp4"
    known = b"B1 sentinel " + os.urandom(64)
    sentinel.write_bytes(known)
    refused = attempt(client, "export", {"project": str(pkg), "preset": "h264",
                                         "path": str(sentinel)})
    message = tool_message(refused.get("error", ""), "export")
    after = sentinel.read_bytes() if sentinel.exists() else None
    check("G2 a `gate` that does not compile, two nests deep: export h264 is refused before "
          "anything is written — \"The export was not started:\" naming \"gate\" — and the "
          "sentinel's bytes are unchanged",
          broken["ok"] and (broken["reply"] or {}).get("ok") is False and seen == [False]
          and not refused["ok"] and message.startswith("The export was not started:")
          and '"gate"' in message and after == known,
          f"write ok={(broken.get('reply') or {}).get('ok')}, store sees {seen}, export "
          f"{refused.get('reply') if refused['ok'] else message!r}, sentinel unchanged "
          f"{after == known}")


# ---- I1 ---------------------------------------------------------------------

def write_standins():
    STANDIN.mkdir(parents=True, exist_ok=True)
    marker = STANDIN / "ffmpeg.exited"
    (STANDIN / "ffprobe").write_text("#!/bin/bash\ncat <<'EOF'\n" + FFPROBE_JSON + "\nEOF\n")
    (STANDIN / "ffmpeg").write_text(
        "#!/bin/bash\n"
        "for a in \"$@\"; do [ \"$a\" = \"-encoders\" ] && exit 0; done\n"
        f"trap 'touch \"{marker}\"' EXIT\n"
        f"sleep {FFMPEG_SLEEP}\n"
        f"cp \"{A_MOV}\" \"${{@: -1}}\"\n")
    for name in ("ffprobe", "ffmpeg"):
        os.chmod(STANDIN / name, 0o755)


def rewrapped_entries(prefix):
    try:
        return sorted(name for name in os.listdir(REWRAPPED) if name.startswith(prefix))
    except OSError:
        return []


def run_import(client):
    support = HOME / "Library/Application Support"
    if not support.is_dir():
        why = ("the instance did not start" if client is None
               else "the scratch home did not take")
        check("I1 the instance's scratch home took", False,
              f"{support} is not a directory: {why}; no import was made")
        return
    marker = STANDIN / "ffmpeg.exited"
    if marker.exists():
        marker.unlink()
    hexed = uuid.uuid4().hex
    stem = f"slow-{hexed}"
    fixture = WORK / f"{stem}.mkv"
    fixture.write_bytes(os.urandom(4096))
    pkg = WORK / "import.reelcut"
    made = attempt(client, "new_project", {"path": str(pkg)})
    started = time.monotonic()
    got = attempt(client, "import_media", {"project": str(pkg), "path": str(fixture)})
    elapsed = time.monotonic() - started
    reply = got.get("reply") if got["ok"] and isinstance(got.get("reply"), dict) else {}
    path = Path(reply.get("path", "")) if reply.get("path") else None
    inside = (path is not None and path.suffix == ".mov"
              and path.resolve().parent == REWRAPPED.resolve()
              and path.name.startswith(stem + "-"))

    # Cleanup, whatever the call answered, before the instance stops.
    expired = []
    deadline = started + 120
    while not marker.exists() and time.monotonic() < deadline:
        time.sleep(0.5)
    if not marker.exists():
        expired.append("ffmpeg.exited never appeared within 120 s of the call")
    partial_deadline = time.monotonic() + 10
    while (any(n.endswith(".partial.mov") for n in rewrapped_entries(stem + "-"))
           and time.monotonic() < partial_deadline):
        time.sleep(0.2)
    if any(n.endswith(".partial.mov") for n in rewrapped_entries(stem + "-")):
        expired.append("a .partial.mov was still in Rewrapped after 10 s")
    for name in rewrapped_entries(stem + "-"):
        entry = REWRAPPED / name
        if entry.resolve().parent == REWRAPPED.resolve():
            try:
                entry.unlink()
            except OSError:
                pass
    left = rewrapped_entries(stem + "-")
    if left:
        expired.append(f"left in Rewrapped: {left}")
    fixture.unlink(missing_ok=True)

    check(f"I1 import_media of a {FFMPEG_SLEEP} s stand-in conversion answers ok after "
          f">= {FFMPEG_SLEEP} s: kind video, 640×360, a .mov directly inside Rewrapped; "
          "cleaned up",
          made["ok"] and got["ok"] and elapsed >= FFMPEG_SLEEP
          and reply.get("kind") == "video" and reply.get("width") == 640
          and reply.get("height") == 360 and inside and not expired,
          f"elapsed {elapsed:.1f} s, answer {reply if got['ok'] else got.get('error')!r}, "
          f"inside Rewrapped {inside}, cleanup {expired or 'clean'}")


# ---- M0–M2 ------------------------------------------------------------------

def write_noise(path, seconds):
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(48000)
        chunk = 48000 * 4
        for _ in range(seconds):
            out.writeframes(os.urandom(chunk))


def build_noise_fixture(client):
    """The M fixture over MCP: the saved package, or None and why."""
    noise = WORK / "noise.wav"
    write_noise(noise, NOISE_SECONDS)
    pkg = WORK / "noise.reelcut"
    steps = [attempt(client, "new_project", {"path": str(pkg)})]
    imported = attempt(client, "import_media", {"project": str(pkg), "path": str(noise)})
    steps.append(imported)
    media = (imported.get("reply") or {}).get("media") if imported["ok"] else None
    for _ in range(NOISE_TRACKS - 1):
        steps.append(attempt(client, "add_track", {"project": str(pkg)}))
    tracks = [t["id"] for t in (project_of(client, pkg) or {}).get("tracks", [])]
    for track in tracks[:NOISE_TRACKS]:
        steps.append(attempt(client, "add_clip", {"project": str(pkg), "track": track,
                                                  "media": media, "at": 0}))
    clips = [c["id"] for c in (project_of(client, pkg) or {}).get("clips", [])]
    steps.append(attempt(client, "set_audio", {"project": str(pkg), "clips": clips,
                                               "patch": {"noise_reduction": 1.0}}))
    steps.append(attempt(client, "save_project", {"project": str(pkg)}))
    failed = [s.get("error") for s in steps if not s["ok"]]
    if failed or len(tracks) < NOISE_TRACKS or len(clips) != NOISE_TRACKS:
        return None, f"fixture: errors {failed}, tracks {len(tracks)}, clips {len(clips)}"
    return pkg, ""


def run_cancel(binary, why, pkg, pkg_why, runs):
    if binary is None or pkg is None:
        reason = why if binary is None else pkg_why
        check("M0 (CONTROL) the uncancelled measurement", False, reason, instrument=True)
        check("M1 cancels during the measurement", False, reason, instrument=True)
        check("M2 cancel latency", False, reason, instrument=True)
        return
    control = run_probe(binary, pkg, "m0", -1)
    window = control.get("window")
    check(f"M0 (CONTROL) {NOISE_SECONDS} s of noise on {NOISE_TRACKS} tracks with noise "
          f"reduction: the uncancelled probe run is success with window >= {WINDOW_FLOOR} s",
          control.get("rc") == 0 and control.get("outcome") == "success"
          and isinstance(window, (int, float)) and window >= WINDOW_FLOOR,
          f"{control}", instrument=True)
    if not (isinstance(window, (int, float)) and window >= 0.5):
        check("M1 cancels during the measurement", False, "no measurement window from M0",
              instrument=True)
        check("M2 cancel latency", False, "no measurement window from M0", instrument=True)
        return
    seed = random.randrange(1 << 30)
    rng = random.Random(seed)
    print(f"  M1 seed {seed}, delay in [0.2, {window / 2:.3f}] s", flush=True)
    answers, crashes, bad = [], 0, []
    for index in range(runs):
        delay = rng.uniform(0.2, window / 2)
        answer = run_probe(binary, pkg, f"m1-{index}", delay)
        answers.append(answer)
        crashed = answer["rc"] != 0 or answer["expired"]
        crashes += crashed
        good = (not crashed and answer.get("phase_at_cancel") == "Measuring loudness…"
                and answer.get("outcome") == "cancelled" and answer.get("left") is False)
        if not good:
            bad.append(index)
        latency = answer.get("latency")
        print(f"    run {index:2d} delay {delay:6.3f} rc {answer['rc']} "
              f"outcome {answer.get('outcome')} phase {answer.get('phase_at_cancel')!r} "
              f"latency {latency if latency is None else round(latency, 3)} "
              f"left {answer.get('left')}" + ("" if good else f"  {answer}"), flush=True)
    print(f"  M1 crashes: {crashes} of {runs}", flush=True)
    check(f"M1 {runs} cancels during the measurement: every run rc 0, cancelled while "
          "\"Measuring loudness…\", no file left",
          not bad and crashes == 0, f"crashes {crashes} of {runs}, failing runs {bad}")
    latencies = [a.get("latency") for a in answers]
    slow = [i for i, value in enumerate(latencies)
            if not isinstance(value, (int, float)) or value > LATENCY_BOUND]
    known = [value for value in latencies if isinstance(value, (int, float))]
    check(f"M2 every M1 cancel completes within {LATENCY_BOUND} s (the loop cancels its own "
          "reader)",
          not slow and len(known) == runs,
          (f"max {max(known):.3f} s, " if known else "")
          + f"over {LATENCY_BOUND} s or missing: {slow}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--only", default="gate,import,cancel")
    parser.add_argument("--runs", type=int, default=30)
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="the probe over a copy of app/Sources with the mutant's texts "
                             "replaced; implies --only cancel; its row must FAIL (exit 1)")
    args = parser.parse_args()
    began = time.monotonic()
    if args.mutant:
        args.only = "cancel"
    groups = [g.strip() for g in args.only.split(",") if g.strip()]
    unknown = [g for g in groups if g not in GROUPS]
    if unknown:
        parser.error(f"unknown group(s) {unknown}; choose from {sorted(GROUPS)}")
    selected = [row for g in groups for row in GROUPS[g]] + ["Z1"]

    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    HOME.mkdir()
    write_standins()

    binary, why = (None, "")
    if args.mutant:
        sources, why = mutant_sources(args.mutant)
        if sources is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why} "
                  f"in {time.monotonic() - began:.0f} s", flush=True)
            sys.exit(2)
        print(f"  mutant {args.mutant}: {len(MUTANTS[args.mutant][1])} text(s) replaced "
              f"once each in {sources}", flush=True)
        binary, why = build_probe(sources, MUTANT_WORK / args.mutant / "probe")
        if binary is None:
            print(f"  probe: did not build — {why}", flush=True)
            print(f"mutant {args.mutant}: the control could not be performed — the probe did "
                  f"not build in {time.monotonic() - began:.0f} s", flush=True)
            sys.exit(2)
    elif "cancel" in groups:
        binary, why = build_probe()
        if binary is None:
            print(f"  probe: did not build — {why}", flush=True)

    log = WORK / "reelcut.log"
    instance = Instance(args.app, log)
    pkg, pkg_why = None, "the instance did not start"
    try:
        client = instance.start()
        if "gate" in groups:
            run_gate(client)
        if "import" in groups:
            run_import(client)
        if "cancel" in groups and client is not None:
            pkg, pkg_why = build_noise_fixture(client)
    finally:
        instance.stop()
    try:
        complaints = [line.strip() for line in open(log) if "Reelcut: " in line]
    except OSError:
        complaints = ["the log could not be read"]
    if "cancel" in groups:
        run_cancel(binary, why, pkg, pkg_why, args.runs)
    check("Z1 grep \"Reelcut: \" over this launch's log prints nothing",
          not complaints and log.exists(), f"{complaints[:5]}")

    missing = [row for row in selected if row not in rows]
    failed = [row for row in ORDER if row in selected and not rows.get(row)]
    wall = time.monotonic() - began
    print(f"\n{len(selected) - len(failed)}/{len(selected)} rows ok"
          + (f"; failed {failed}" if failed else "")
          + (f"; never scored {missing}" if missing else "") + f" in {wall:.0f} s", flush=True)
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        broken = sorted(instrument_rows)
        not_done = (f"{named} was never scored" if named not in rows else
                    f"scored as instrument failures: {', '.join(broken)}" if broken else "")
        if not_done:
            print(f"mutant {args.mutant}: the control could not be performed — {not_done}",
                  flush=True)
            sys.exit(2)
        caught = not rows[named]
        print(f"mutant {args.mutant}: {named} "
              + ("FAILS (expected — caught)" if caught else "PASSES (it survived)"), flush=True)
        sys.exit(1 if caught else 0)
    sys.exit(0 if not failed and not missing else 1)


if __name__ == "__main__":
    main()
