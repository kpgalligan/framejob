#!/usr/bin/env python3
"""ai-docs batch b2 (#531 #525; spec §11 #531, #525): an export keeps the file it replaces until it
lands, and an Objective-C exception fails one tool call, not the app.

    python3 tools/proof/ai_docs_b2_proof.py [--only K1,E1,…] [--app PATH] [--base-sources PATH]
                                            [--expect-red] [--mutant NAME]
    RC_PROOF_APP=<the frozen base app> python3 tools/proof/ai_docs_b2_proof.py \
        --base-sources <a tree at the base>/app/Sources --expect-red
    RC_PROOF_APP=release python3 tools/proof/ai_docs_b2_proof.py

The built app (`proof_app`'s choice, or `--app`) on a scratch `CFFIXED_USER_HOME` under
`work/ai-docs-b2/`. `(c)` marks a CONTROL, which passes on the base too; every other row is red on
the frozen base app with `--base-sources` set to the base's `app/Sources`, and `--expect-red` exits
0 only when that holds. The fixtures are made here, so ffmpeg (with libx264) is needed at proof
time, and `cc`, `lldb` and `codesign` for the E rows.

- #531 over MCP, a 60 s 1920×1080 H.264+AAC clip, `set_range` 0–20 s, each target made first by a
  `done` export, each row in a folder of its own: K1 `h264`, K2 `gif`, K3 `vp9_webm`:
  `cancel_export` once the job runs with no phase past 0.15: `cancelled`, the file byte-identical,
  the folder only it. F1 an instance with `-RCDevExportFault video@40` (spec §11 #378): `failed`,
  byte-identical, no `.framejob-export-*`. G1 a graphic whose module throws from frame 30 over an
  existing `h264`: `failed` with the graphic sentence, byte-identical. S1 `audio_wav` with `stems:
  tracks` (two tracks) over an existing mix and stems, cancelled past the mix: every file
  byte-identical, the folder unchanged. L1 `h264` over a file locked with `chflags uchg`: `failed`
  with "could not be replaced with the new export", the file byte-identical, no sibling (the swap's
  refusal, and the discard a failed swap leaves). N1 (c) `h264`, `gif`, `vp9_webm`, `audio_wav` with
  stems over existing files: `done`, new digests, no `.framejob-export-*` or `.framejob-replaced-*`.
  C0 (c) a cancel while measuring the whole timeline: byte-identical.
- Probe, `ai_docs_b2_probe.swift` through `swift_build.build()` with `FRAMEJOB_DEV_TOOLS` and a
  `default.metallib` from this tree's shaders, the same source on the base and the fix: P1 the
  Export… progress sheet over an existing file, Cancel `performClick`ed past 3 % "Writing": the
  file byte-identical, no sibling. Q1 queue job A `done`, job B to the same path cancelled while it
  writes: A not `superseded`, during or after, the file A's. Q2 job C to the same path: A not
  `superseded` while C writes, `superseded` once it completes, C's message naming `same.mp4`. A1
  under the inject dylib and lldb: `AgentLane.shared.submit` of `get_project` with arguments
  holding the token answers `isError` with #525's sentence, and the probe lives.
- #525 under `lldb --batch -k bt -k "process kill"` (so an abort raises no crash dialog), with
  `ai_docs_b2_inject.m` built into `work/ai-docs-b2/`: E0 (c) no dylib, `open_project` at a token
  path refused, the app alive. E1 `open_project` with the JSON token (the server thread), E2
  `get_project` with it (the main hop through `route`), E3 `new_project` at a path holding the hop
  token (raised on main inside `onMainWhenIdle` under `AgentServer.newProject`, through
  `refuseHeldPath` → `isOpening` → `canonical`'s `-[NSString stringByExpandingTildeInPath]`; the log
  shows the wrapper's `main thread: 1`): each answers `isError` naming `NSInvalidArgumentException`,
  the app pid lives and the next call answers. E4 (c) with the dylib, calls without either token
  answer. A hardened app (Release) is copied with `ditto` and re-signed ad hoc without `runtime`
  (`--preserve-metadata=entitlements`); `codesign -dv` must show no `runtime`, and the two
  executables must match byte for byte once each copy's signature is removed. The E rows are
  skipped by name only if that fails.
- Z1 (c) `grep "Frame Job: "` on each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a `tree_copy.py` copy of the tree. A mutant of a probe
row builds only the probe from the copy's `app/Sources`; one of an app row builds the copy's app.
CAUGHT exits 1 when every named row failed, SURVIVED exits 0, and a control that could not be
performed (the copy did not build, an anchor not found once) exits 2. An instrument that cannot run
is a scored failure, never an exit.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
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

WORK = ROOT / "tools/proof/work/ai-docs-b2"
HOME = WORK / "home"
FILES = WORK / "files"
LOGS = WORK / "logs"
PACKAGES = WORK / "packages"
OUT = WORK / "probe"
PROBE = HERE / "ai_docs_b2_probe.swift"
INJECT = HERE / "ai_docs_b2_inject.m"
DYLIB = WORK / "inject.dylib"
SHADERS = ROOT / "app/Resources/Shaders"
CALL_BOUND = 300
JOB_BOUND = 900
PROBE_BOUND = 1500
BUILD_BOUND = 1500
LISTEN_BOUND = 180
SEC = 600000
TOKEN = "FRAMEJOB_RAISE_525"
HOP = "FRAMEJOB_RAISE_HOP_525"
EXCEPTION = "NSInvalidArgumentException"
SENTENCE = "failed on an internal exception (NSInvalidArgumentException"
STILL = "Frame Job is still running, but part of the call may have happened."
SIBLING = ".framejob-export-"
REPLACED = ".framejob-replaced-"
GRAPHIC = "The export was stopped at frame"
SWAP = "could not be replaced with the new export"

APP_ROWS = ["K1", "K2", "K3", "G1", "S1", "L1", "N1", "C0"]
FAULT_ROWS = ["F1"]
PROBE_ROWS = ["P1", "Q1", "Q2", "A1"]
E_ROWS = ["E0", "E1", "E2", "E3", "E4"]
ROWS = APP_ROWS + FAULT_ROWS + PROBE_ROWS + E_ROWS + ["Z1"]
CONTROLS = {"N1", "C0", "E0", "E4", "Z1"}

EXPORTER = "app/Sources/Exporter.swift"
STEMS = "app/Sources/ExportStems.swift"
QUEUE = "app/Sources/ExportQueueController.swift"
PROGRESS = "app/Sources/ExportProgressSheetController.swift"
LANE = "app/Sources/AgentLane.swift"
# name: (the rows it must turn red, whether the copy's app is built, the edits).
MUTANTS = {
    "write-in-place": (["K1", "F1"], True, [(
        EXPORTER, "        let temporary = ExportAside.temporary(for: url)\n",
        "        let temporary = url\n        try? FileManager.default.removeItem(at: url)\n")]),
    "keep-temp": (["K2", "L1"], True, [(
        EXPORTER, "        if case .failure = result { ExportAside.discard(writing) }\n", "")]),
    "stem-in-place": (["S1"], True, [(
        STEMS, "        let url = ExportAside.temporary(for: path)\n",
        "        let url = path\n        try? FileManager.default.removeItem(at: path)\n")]),
    "superseded-at-launch": (["Q1"], False, [(
        QUEUE, "        jobs[index].phase = Self.preparing\n",
        "        jobs[index].phase = Self.preparing\n"
        "        for other in jobs.indices where other != index && jobs[other].state == .completed\n"
        "            && jobs[other].destination == job.destination { jobs[other].superseded = true }\n")]),
    "sheet-removes": (["P1"], False, [(
        PROGRESS, "            if case Exporter.ExportError.cancelled = error {\n                dismiss(self)",
        "            if case Exporter.ExportError.cancelled = error {\n"
        "                try? FileManager.default.removeItem(at: destination)\n                dismiss(self)")]),
    "answer-temp": (["Q2"], False, [(
        EXPORTER, "                return destination\n", "                return writing\n")]),
    "no-route-catch": (["E1", "E2"], True, [(
        LANE, "            return executeCatching(tool, argumentsJSON)\n        }\n"
              "        return onMainWhenIdle { executeCatching(tool, argumentsJSON) }",
        "            return server.execute(tool: tool, argumentsJSON: argumentsJSON)\n        }\n"
        "        return onMainWhenIdle { server.execute(tool: tool, argumentsJSON: argumentsJSON) }")]),
    "no-hop-catch": (["E3"], True, [
        (LANE, "Self.gestureInProgress() ? nil : try ObjCException.shielding(body, raised: &raised)",
         "Self.gestureInProgress() ? nil : try body()"),
        (LANE, "            if let raised = raised { raised.raise() }\n", ""),
        (LANE, "            var raised: NSException?\n", "")]),
    "no-submit-catch": (["A1"], False, [(
        LANE, "            let answered = ObjCException.catching {\n"
              "                answer(tool, argumentsJSON, document, cancel, askFirst)\n            }\n",
        "            let answered: Result<String, ObjCRaised> =\n"
        "                .success(answer(tool, argumentsJSON, document, cancel, askFirst))\n")]),
}

results = {}
selected = set(ROWS)
logs = []
pids = []


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def attempt(names, body):
    """`body` when any of `names` is selected; an instrument that raises fails them, never exits."""
    if not selected & set(names):
        return
    try:
        body()
    except Exception as error:  # noqa: BLE001
        for name in names:
            check(name, False, f"the row could not run: {error!r}")


# ---- the fixtures -----------------------------------------------------------------------

def ffmpeg(*arguments):
    subprocess.run(["ffmpeg", "-y", "-v", "error", *arguments], check=True, timeout=300)


def fixtures():
    """A 60 s 1920×1080 H.264+AAC clip and a 60 s tone."""
    ffmpeg("-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30:duration=60",
           "-f", "lavfi", "-i", "sine=frequency=440:duration=60", "-pix_fmt", "yuv420p",
           "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", "-shortest",
           str(FILES / "long60.mov"))
    ffmpeg("-f", "lavfi", "-i", "sine=frequency=660:duration=60", "-c:a", "pcm_s16le",
           str(FILES / "tone60.wav"))


# ---- instances --------------------------------------------------------------------------

def start(binary, label, arguments=()):
    log = LOGS / f"{label}.log"
    logs.append(log)
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), list(arguments), env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    print(f"  {label}: instance PID {launched.child.pid}", flush=True)
    return launched


def parity():
    lines = []
    for log in logs:
        try:
            lines += [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
        except OSError:
            lines.append(f"{log} could not be read")
    check("Z1", bool(logs) and not lines,
          f"grep 'Frame Job: ' over {len(logs)} logs printed {lines[:3] or 'nothing'}")


class Project:
    """One new project in an instance; every call names it."""

    def __init__(self, client, name, media=()):
        self.client = client
        self.path = str(WORK / f"{name}.framejob")
        client.call_with("new_project", {"path": self.path})
        self.media = {str(path): self.op("import_media", path=str(path))["media"] for path in media}

    def op(self, tool, **arguments):
        return self.client.call_with(tool, dict(arguments, project=self.path))

    def tracks(self):
        return [track["id"] for track in self.op("get_project")["project"]["tracks"]]

    def place(self, path, track=None, at=0):
        track = self.tracks()[0] if track is None else track
        return self.op("add_clip", track=track, media=self.media[str(path)],
                       at=round(at * SEC))["new_clips"][0]

    def close(self):
        self.op("close_project", discard=True)


def clip_project(client, name):
    project = Project(client, name, [FILES / "long60.mov"])
    project.place(FILES / "long60.mov")
    project.op("set_range", start=0, end=20 * SEC)
    return project


def folder(row):
    out = WORK / f"out-{row}"
    out.mkdir(parents=True, exist_ok=True)
    return out


def digest(path):
    path = Path(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12] if path.is_file() else None


def listing(place):
    return sorted(entry.name for entry in Path(place).iterdir())


def strays(place):
    return [name for name in listing(place) if name.startswith((SIBLING, REPLACED))]


def follow(client, export_id, bound=JOB_BOUND):
    """The job's last `export_status`, polled every 0.1 s."""
    began = time.monotonic()
    while True:
        status = client.call_with("export_status", {"export_id": export_id})
        if status.get("status") in ("done", "failed", "cancelled"):
            return status
        if time.monotonic() - began > bound:
            client.call_with("cancel_export", {"export_id": export_id})
            return status
        time.sleep(0.1)


def run_export(project, bound=JOB_BOUND, **arguments):
    """("refused", the sentence) from the call, or (the job's last word, its status)."""
    try:
        answer = project.op("export", **arguments)
    except mcp.ToolError as error:
        return "refused", str(error)
    status = follow(project.client, answer["export_id"], bound)
    return status.get("status"), status


def made(project, **arguments):
    """A file an export must write: its path, or a raise the row turns into a failure."""
    word, status = run_export(project, **arguments)
    if word != "done":
        raise RuntimeError(f"the fixture export {arguments} ended {word}: {str(status)[:200]}")
    return status["path"]


def cancel_when(project, wanted, **arguments):
    """A job cancelled at the first status `wanted` accepts: (its last status, the status then)."""
    answer = project.op("export", **arguments)
    client, began, hit = project.client, time.monotonic(), None
    while time.monotonic() - began < JOB_BOUND:
        status = client.call_with("export_status", {"export_id": answer["export_id"]})
        if status.get("status") not in ("queued", "running"):
            break
        if wanted(status):
            client.call_with("cancel_export", {"export_id": answer["export_id"]})
            hit = status
            break
        time.sleep(0.01)
    return follow(client, answer["export_id"]), hit


def measuring(status):
    return status.get("phase") == "Measuring loudness…"


def writing(floor=0.15):
    return lambda status: (status.get("status") == "running" and not status.get("phase")
                           and status.get("progress", 0) > floor)


def reason(status):
    if isinstance(status, dict):
        return str(status.get("reason") or status.get("error") or status.get("message") or "")
    return str(status)


# ---- #531 over MCP ------------------------------------------------------------------------

K_ROWS = {"K1": ("h264", "mp4", [640, 360]), "K2": ("gif", "gif", [240, 136]),
          "K3": ("vp9_webm", "webm", [640, 360])}


def app_rows(client):
    project = clip_project(client, "clips")

    def cancelled_writing(row):
        preset, extension, size = K_ROWS[row]
        place = folder(row)
        path = made(project, preset=preset, path=str(place / f"over.{extension}"), range="in_out",
                    size=size)
        before = digest(path)
        status, hit = cancel_when(project, writing(), preset=preset, path=path, range="in_out",
                                  size=size)
        at = hit and round(hit.get("progress", 0), 3)
        check(row, hit is not None and status.get("status") == "cancelled" and digest(path) == before
              and listing(place) == [Path(path).name],
              f"{preset}: cancelled while writing at {at}, {status.get('status')}; "
              f"{before} → {digest(path)}; folder {listing(place)}")

    for row in K_ROWS:
        attempt([row], lambda row=row: cancelled_writing(row))

    def c0():
        place = folder("C0")
        path = made(project, preset="h264", path=str(place / "over.mp4"), range="in_out",
                    size=[640, 360])
        before = digest(path)
        # The whole 60 s timeline, not the 20 s range: on Release the range's measurement ended
        # between two 10 ms polls (measured), and the whole one is three times as long.
        status, hit = cancel_when(project, measuring, preset="h264", path=path, size=[320, 180])
        check("C0", hit is not None and status.get("status") == "cancelled"
              and digest(path) == before and listing(place) == ["over.mp4"],
              f"cancelled while measuring {hit is not None}, {status.get('status')}; "
              f"{before} → {digest(path)}; folder {listing(place)}")

    attempt(["C0"], c0)

    def l1():
        place = folder("L1")
        path = made(project, preset="h264", path=str(place / "locked.mp4"), range="in_out",
                    size=[640, 360])
        before = digest(path)
        subprocess.run(["chflags", "uchg", path], check=True, timeout=30)
        try:
            word, status = run_export(project, preset="h264", path=path, range="in_out",
                                      size=[320, 180])
        finally:
            subprocess.run(["chflags", "nouchg", path], check=True, timeout=30)
        said = reason(status)
        check("L1", word == "failed" and SWAP in said and "The file there is as it was." in said
              and digest(path) == before and listing(place) == ["locked.mp4"],
              f"over a locked file: {word}, {said[:150]!r}; {before} → {digest(path)}; "
              f"folder {listing(place)}")

    attempt(["L1"], l1)

    def n1():
        place = folder("N1")
        for preset, extension, first, second in (("h264", "mp4", [640, 360], [320, 180]),
                                                 ("gif", "gif", [240, 136], [160, 90]),
                                                 ("vp9_webm", "webm", [640, 360], [320, 180])):
            path = made(project, preset=preset, path=str(place / f"again.{extension}"),
                        range="in_out", size=first)
            old = digest(path)
            word, _ = run_export(project, preset=preset, path=path, range="in_out", size=second)
            check("N1", word == "done" and digest(path) not in (None, old) and not strays(place),
                  f"{preset}: {word}, {old} → {digest(path)}, strays {strays(place)}")

    attempt(["N1"], n1)
    project.close()

    def g1():
        graphic = clip_project(client, "graphic")
        place = folder("G1")
        path = made(graphic, preset="h264", path=str(place / "over.mp4"), range="in_out",
                    size=[640, 360])
        before = digest(path)
        source = ("export const meta = { name: \"Boom\", durationInFrames: 600 };\n"
                  "export function render(frame, props, ctx) {\n"
                  "  if (frame >= 30) throw new Error(\"boom past one second\");\n"
                  "  return svg(ctx, `<rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" "
                  "fill=\"#ff5a36\"/>`);\n}\n")
        graphic.op("write_graphic", name="boom", source=source)
        graphic.op("set_playhead", t=0)
        graphic.op("insert_graphic", name="boom", **{"from": "project"})
        word, status = run_export(graphic, preset="h264", path=path, range="in_out",
                                  size=[640, 360])
        said = reason(status)
        check("G1", word == "failed" and GRAPHIC in said and "boom" in said
              and digest(path) == before and listing(place) == ["over.mp4"],
              f"{word}, {said[:140]!r}; {before} → {digest(path)}; folder {listing(place)}")
        graphic.close()

    attempt(["G1"], g1)

    def stems_project():
        stems = Project(client, "stems", [FILES / "long60.mov", FILES / "tone60.wav"])
        first = stems.tracks()[0]
        stems.op("set_track", track=first, name="Dialogue")
        stems.op("add_track")
        second = [track for track in stems.tracks() if track != first][0]
        stems.op("set_track", track=second, name="Music")
        stems.place(FILES / "long60.mov", track=first)
        stems.place(FILES / "tone60.wav", track=second)
        stems.op("set_range", start=0, end=20 * SEC)
        return stems

    def s1():
        stems = stems_project()
        place = folder("S1")
        mix = made(stems, preset="audio_wav", path=str(place / "Mix.wav"), range="in_out",
                   stems="tracks")
        names = listing(place)
        before = {name: digest(place / name) for name in names}
        # Past the mix: the measurement owns half the bar and the mix a third of the rest.
        status, hit = cancel_when(stems, writing(0.70), preset="audio_wav", path=mix,
                                  stems="tracks")
        after = {name: digest(place / name) for name in listing(place)}
        at = hit and round(hit.get("progress", 0), 3)
        check("S1", hit is not None and status.get("status") == "cancelled" and len(names) == 3
              and after == before,
              f"cancelled past the mix at {at}, {status.get('status')}; before {before}; "
              f"after {after}")
        stems.close()

    attempt(["S1"], s1)

    def n1_stems():
        stems = stems_project()
        place = folder("N1-stems")
        mix = made(stems, preset="audio_wav", path=str(place / "Mix.wav"), range="in_out",
                   stems="tracks")
        before = {name: digest(place / name) for name in listing(place)}
        word, _ = run_export(stems, preset="audio_wav", path=mix, stems="tracks")
        after = {name: digest(place / name) for name in listing(place)}
        check("N1", word == "done" and sorted(after) == sorted(before) and len(before) == 3
              and all(after[name] != before[name] for name in before) and not strays(place),
              f"audio_wav with stems: {word}, {before} → {after}, strays {strays(place)}")
        stems.close()

    attempt(["N1"], n1_stems)


def fault_rows(binary):
    def f1():
        source = WORK / "out-fault-source.mp4"
        if not source.exists():
            raise RuntimeError("no h264 export from the main instance to copy")
        launched = start(binary, "fault", ["-RCDevExportFault", "video@40"])
        pids.append(launched.child.pid)
        try:
            if launched.client is None:
                raise RuntimeError("the app did not listen")
            project = clip_project(launched.client, "fault")
            place = folder("F1")
            path = place / "failing.mp4"
            shutil.copyfile(source, path)
            before = digest(path)
            word, status = run_export(project, preset="h264", path=str(path), range="in_out",
                                      size=[640, 360])
            check("F1", word == "failed" and digest(path) == before
                  and listing(place) == ["failing.mp4"],
                  f"{word}, {reason(status)[:120]!r}; {before} → {digest(path)}; "
                  f"folder {listing(place)}")
            project.close()
        finally:
            launched.stop()

    attempt(["F1"], f1)


def fault_source(client):
    """An `h264` file F1's instance copies, since its own export of one meets the fault."""
    project = clip_project(client, "source")
    path = made(project, preset="h264", path=str(WORK / "out-fault-source.mp4"), range="in_out",
                size=[640, 360])
    project.close()
    return path


def save_package(client):
    project = Project(client, "package", [FILES / "long60.mov"])
    project.place(FILES / "long60.mov")
    project.op("save_project")
    project.op("close_project")
    path = PACKAGES / "long60.framejob"
    shutil.copytree(project.path, path)
    return path


# ---- the probe --------------------------------------------------------------------------

def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    airs = []
    for shader in sorted(SHADERS.glob("*.metal")):
        air = OUT / (shader.stem + ".air")
        step = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
                              capture_output=True, text=True, timeout=300)
        if step.returncode:
            return None, f"metal {shader.name}: {step.stderr[:300]}"
        airs.append(str(air))
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metallib", *airs, "-o",
                           str(OUT / "default.metallib")], capture_output=True, text=True, timeout=300)
    if step.returncode:
        return None, f"metallib: {step.stderr[:300]}"
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "ai-docs-b2-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def rows_of(text):
    rows = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{") and '"row"' in line:
            try:
                answer = json.loads(line)
            except ValueError:
                continue
            rows.setdefault(answer["row"], []).append(answer)
    return rows


def probe(binary, mode, package):
    run = WORK / f"run-{mode}"
    run.mkdir(parents=True, exist_ok=True)
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    done = subprocess.run([str(binary), mode, str(package), str(run)], capture_output=True,
                          text=True, env=env, timeout=PROBE_BOUND, cwd=OUT, stdin=subprocess.DEVNULL)
    rows = rows_of(done.stdout)
    if done.returncode != 0:
        raise RuntimeError(f"{mode}: exit {done.returncode}, rows {sorted(rows)}: "
                           f"{(done.stdout + done.stderr)[-400:]}")
    return rows


def under_lldb(command, log, env, inject):
    """`command` under `lldb --batch`, the dylib in its environment when `inject`: the child."""
    lldb = ["lldb", "--batch"]
    if inject:
        lldb += ["-o", f"settings set target.env-vars DYLD_INSERT_LIBRARIES={DYLIB}"]
    lldb += ["-o", "run", "-k", "bt 40", "-k", "process kill", "--", *command]
    out = open(log, "wb")
    return subprocess.Popen(lldb, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
                            start_new_session=True, env=env)


def probe_rows(binary, package):
    def p1():
        answer = probe(binary, "sheet", package).get("P1", [{}])[0]
        check("P1", "error" not in answer and answer.get("dismissed") and answer.get("same")
              and answer.get("listing") == ["over.mp4"],
              f"cancelled at {answer.get('cancelled_at')}: the file the same {answer.get('same')}, "
              f"there {answer.get('exists')}, folder {answer.get('listing')} "
              f"{answer.get('error', '')}")

    attempt(["P1"], p1)

    def q():
        rows = probe(binary, "queue", package)
        one, two = rows.get("Q1", [{}])[0], rows.get("Q2", [{}])[0]
        check("Q1", one.get("a") == "completed" and one.get("b") == "cancelled"
              and one.get("b_cancelled_while_writing") and not one.get("a_superseded_during_b")
              and not one.get("a_superseded_after_b") and one.get("same")
              and one.get("listing") == ["same.mp4"],
              f"A {one.get('a')}, B {one.get('b')} (cancelled while writing "
              f"{one.get('b_cancelled_while_writing')}); A superseded during B "
              f"{one.get('a_superseded_during_b')}, after {one.get('a_superseded_after_b')}; "
              f"the file A's {one.get('same')}; folder {one.get('listing')}")
        check("Q2", two.get("c") == "completed" and two.get("samples", 0) > 0
              and two.get("a_superseded_while_c_wrote") == [False] and two.get("a_superseded_after_c")
              and "Exported “same.mp4”" in two.get("c_message", "")
              and two.get("listing") == ["same.mp4"],
              f"C {two.get('c')}; A superseded while C wrote {two.get('a_superseded_while_c_wrote')} "
              f"({two.get('samples')} samples), after {two.get('a_superseded_after_c')}; C says "
              f"{two.get('c_message', '')[:60]!r}; folder {two.get('listing')}")

    attempt(["Q1", "Q2"], q)

    def a1():
        run = WORK / "run-submit"
        run.mkdir(parents=True, exist_ok=True)
        log = LOGS / "probe-submit.log"
        env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
        env.pop("DYLD_INSERT_LIBRARIES", None)
        child = under_lldb([str(binary), "submit", str(package), str(run)], log, env, True)
        try:
            child.wait(timeout=PROBE_BOUND)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
        text = log.read_text(errors="replace")
        answer = rows_of(text).get("A1", [{}])[0]
        raw = answer.get("raw", "")
        try:
            parsed = json.loads(raw) if raw else {}
        except ValueError:
            parsed = {}
        said = ((parsed.get("content") or [{}])[0]).get("text", "")
        aborted = "SIGABRT" in text or "uncaught exception" in text
        check("A1", answer.get("answered") and parsed.get("isError") is True
              and f"get_project {SENTENCE}" in said and STILL in said and not aborted,
              f"answered {answer.get('answered')}, isError {parsed.get('isError')}, "
              f"{said[:120]!r}; aborted {aborted}")

    attempt(["A1"], a1)


# ---- #525 under lldb ----------------------------------------------------------------------

def hardened(app):
    shown = subprocess.run(["codesign", "-dv", str(app)], capture_output=True, text=True, timeout=60)
    flags = [line for line in shown.stderr.splitlines() if "flags=" in line]
    return any("runtime" in line for line in flags), flags


def unsigned_bytes(executable, label):
    scratch = Path(tempfile.mkdtemp(prefix=f"b2-{label}-", dir=WORK))
    copy = scratch / "exe"
    shutil.copyfile(executable, copy)
    subprocess.run(["codesign", "--remove-signature", str(copy)], check=True, timeout=60,
                   capture_output=True)
    return hashlib.sha256(copy.read_bytes()).hexdigest()


def e_app(binary):
    """(the executable the E rows drive, None) or (None, why they are skipped)."""
    app = Path(binary).parents[2]
    is_hardened, flags = hardened(app)
    if not is_hardened:
        return binary, None
    copy = WORK / "release-unhardened" / app.name
    copy.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", str(app), str(copy)], check=True, timeout=600)
    signed = subprocess.run(["codesign", "--force", "--sign", "-",
                             "--preserve-metadata=entitlements", str(copy)],
                            capture_output=True, text=True, timeout=600)
    if signed.returncode:
        return None, f"the re-sign failed: {signed.stderr[-300:]}"
    still, after = hardened(copy)
    if still:
        return None, f"the copy still shows runtime: {after}"
    executable = proof_app.executable(copy)
    same = unsigned_bytes(binary, "original") == unsigned_bytes(executable, "copy")
    if not same:
        return None, "the copy's executable differs from the original's once unsigned"
    print(f"  E rows on the re-signed copy {copy} ({flags} → {after}; executables the same "
          f"unsigned)", flush=True)
    return executable, None


class Debugged:
    """One app under `lldb --batch`, on a scratch socket of its own."""

    def __init__(self, binary, label, inject):
        self.socket = os.path.join(tempfile.mkdtemp(prefix="rcb2-"), "agent.sock")
        self.log = LOGS / f"{label}.log"
        logs.append(self.log)
        env = bounded.child_env({"RC_AGENT_SOCKET": self.socket, "CFFIXED_USER_HOME": str(HOME)})
        env.pop("DYLD_INSERT_LIBRARIES", None)
        self.child = under_lldb([str(binary), "-ApplePersistenceIgnoreState", "YES"], self.log,
                                env, inject)
        began = time.monotonic()
        while time.monotonic() - began < LISTEN_BOUND:
            if f"listening at {self.socket}" in self.log.read_text(errors="replace"):
                break
            if self.child.poll() is not None:
                break
            time.sleep(0.5)
        self.pid = mcp.socket_pid(self.socket)
        if self.pid:
            pids.append(self.pid)
        self.client = mcp.MCP(self.socket, timeout=120) if self.pid else None
        print(f"  {label}: lldb PID {self.child.pid}, app PID {self.pid}", flush=True)

    def alive(self):
        if not self.pid:
            return False
        try:
            os.kill(self.pid, 0)
            return True
        except ProcessLookupError:
            return False

    def call(self, tool, arguments):
        """("answered", the dict) | ("error", the message) | ("no answer", why)."""
        try:
            return "answered", self.client.call_with(tool, arguments)
        except mcp.ToolError as error:
            return "error", str(error)
        except Exception as error:  # noqa: BLE001
            return "no answer", f"{type(error).__name__}: {str(error)[:160]}"

    def stop(self):
        if self.alive():
            os.kill(self.pid, 15)
            for _ in range(60):
                if not self.alive():
                    break
                time.sleep(0.5)
            if self.alive():
                os.kill(self.pid, 9)
        if self.child.poll() is None:
            try:
                self.child.wait(timeout=60)
            except subprocess.TimeoutExpired:
                self.child.kill()
                self.child.wait()

    def text(self):
        return self.log.read_text(errors="replace")


def raised_row(row, binary, tool, arguments, also=None):
    """One raising call: answered isError naming the exception, the pid alive, the next call
    answering; `also(log text)` any further condition."""
    app = Debugged(binary, row, inject=True)
    try:
        if app.client is None:
            raise RuntimeError("the app did not listen")
        word, said = app.call(tool, arguments)
        time.sleep(2)
        alive = app.alive()
        after = app.call("list_graphics", {})[0] if alive else "no answer"
    finally:
        app.stop()
    text = app.text()
    extra, extra_ok = ("", True) if also is None else also(text)
    ok = (word == "error" and f"{tool} {SENTENCE}" in said and STILL in said and alive
          and after in ("answered", "error") and extra_ok)
    check(row, ok, f"{tool}: {word}, {str(said)[:150]!r}; alive {alive}; next call {after}"
                   + extra)


def e_rows(binary):
    def e0():
        app = Debugged(binary, "E0", inject=False)
        try:
            if app.client is None:
                raise RuntimeError("the app did not listen")
            word, said = app.call("open_project", {"path": str(WORK / f"{TOKEN}.framejob")})
            after = app.call("list_graphics", {})[0]
            alive = app.alive()
        finally:
            app.stop()
        check("E0", word == "error" and "No file at" in str(said) and alive
              and after in ("answered", "error"),
              f"open_project at a token path, no dylib: {word} {str(said)[:100]!r}; alive {alive}; "
              f"next call {after}")

    attempt(["E0"], e0)

    attempt(["E1"], lambda: raised_row("E1", binary, "open_project",
                                       {"path": str(WORK / f"{TOKEN}.framejob")}))

    def e2():
        app_project = str(WORK / "e2.framejob")
        # get_project names a project path that holds the token; the parse raises first.
        raised_row("E2", binary, "get_project", {"project": f"{app_project}{TOKEN}"})

    attempt(["E2"], e2)

    def hop_seen(text):
        line = [l for l in text.splitlines() if "hop raising on" in l]
        return (f"; hop line {line[0][-60:] if line else None!r}",
                bool(line) and "(main thread: 1)" in line[0])

    attempt(["E3"], lambda: raised_row("E3", binary, "new_project",
                                       {"path": str(WORK / f"{HOP}.framejob")}, hop_seen))

    def e4():
        app = Debugged(binary, "E4", inject=True)
        try:
            if app.client is None:
                raise RuntimeError("the app did not listen")
            path = str(WORK / "e4.framejob")
            made_word = app.call("new_project", {"path": path})[0]
            got_word = app.call("get_project", {"project": path})[0]
            alive = app.alive()
        finally:
            app.stop()
        installed = "framejob-525-inject: installed" in app.text()
        check("E4", made_word == "answered" and got_word == "answered" and alive and installed,
              f"dylib installed {installed}; new_project {made_word}, get_project {got_word}; "
              f"alive {alive}")

    attempt(["E4"], e4)


# ---- the run ----------------------------------------------------------------------------

def run(binary, sources, app_rows_wanted=True):
    probe_binary, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe_binary, why = build_probe(sources)
        if why:
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
    if selected & ({"A1"} | set(E_ROWS)):
        built = subprocess.run(["cc", "-dynamiclib", "-fobjc-arc", "-framework", "Foundation",
                                str(INJECT), "-o", str(DYLIB)], capture_output=True, text=True,
                               timeout=300)
        if built.returncode:
            for row in sorted(selected & ({"A1"} | set(E_ROWS))):
                check(row, False, f"the inject dylib did not build: {built.stderr[-300:]}")
            return
    package = None
    launched = start(binary, "main")
    pids.append(launched.child.pid)
    try:
        if launched.client is None:
            for row in sorted(selected - {"Z1"}):
                check(row, False, "the app did not listen")
            return
        client = launched.client
        if app_rows_wanted and selected & set(APP_ROWS):
            app_rows(client)
        if "F1" in selected:
            attempt(["F1"], lambda: fault_source(client))
        if probe_binary is not None:
            def keep():
                nonlocal package
                package = save_package(client)

            attempt(PROBE_ROWS, keep)
    finally:
        launched.stop()
    if "F1" in selected:
        fault_rows(binary)
    if probe_binary is not None and package is not None:
        probe_rows(probe_binary, package)
    if selected & set(E_ROWS):
        executable, why = e_app(binary)
        if why:
            for row in sorted(selected & set(E_ROWS)):
                check(row, False, f"SKIPPED: {why}")
        else:
            e_rows(executable)


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made_copy, why = tree_copy.make_copy(str(WORK.parent / "ai-docs-b2-mutant"))
    if made_copy is None:
        return None, why
    for path, anchor, replacement in MUTANTS[name][2]:
        target = Path(made_copy) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made_copy), None


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    parser.add_argument("--base-sources")
    parser.add_argument("--expect-red", action="store_true")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    for place in (FILES, HOME, LOGS, PACKAGES):
        place.mkdir(parents=True)

    binary = Path(args.app) if args.app else None
    sources = Path(args.base_sources) if args.base_sources else ROOT / "app/Sources"
    if args.mutant:
        rows, needs_app, _ = MUTANTS[args.mutant]
        print(f"ai-docs b2 — the {args.mutant} MUTANT ({' '.join(rows)} must FAIL)", flush=True)
        copy, why = mutate(args.mutant)
        if why is None:
            sources = copy / "app/Sources"
            if needs_app:
                app, why = tree_copy.build_app(copy, BUILD_BOUND)
                binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"ai-docs b2 — an export keeps its file, an exception fails one call ({binary.name})",
          flush=True)

    try:
        fixtures()
    except (OSError, subprocess.SubprocessError) as error:
        for row in sorted(selected):
            check(row, False, f"the fixtures were not made: {error!r}")
    else:
        run(binary, sources)
        parity()

    failed = [name for name in ROWS if name in results and not all(ok for ok, _ in results[name])]
    passed = [name for name in ROWS if name in results and name not in failed]
    print(f"\n{len(passed)}/{len(passed) + len(failed)} rows passed"
          + (f"; failed {failed}" if failed else ""), flush=True)
    if args.mutant:
        rows = MUTANTS[args.mutant][0]
        missing = [row for row in rows if row not in results]
        if missing:
            print(f"mutant {args.mutant}: the control could not be performed — {missing} never "
                  f"scored")
            return 2
        caught = all(row in failed for row in rows)
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              + ", ".join(f"{row} {'failed' if row in failed else 'passed'}" for row in rows),
              flush=True)
        return 1 if caught else 0
    if args.expect_red:
        wrong = [r for r in failed if r in CONTROLS] + [r for r in passed if r not in CONTROLS]
        print("expected red, every row not marked (c) failing and every (c) passing: "
              + ("held" if not wrong else f"NOT held for {wrong}"), flush=True)
        return 1 if wrong else 0
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
