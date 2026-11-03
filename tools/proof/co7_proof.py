#!/usr/bin/env python3
"""Road map "creator-jobs" CO7 — the Layout section, the nest offer and the crop on the person
(spec §11 CO-70…CO-73).

    python3 tools/proof/co7_proof.py [--only P1,P4,…] [--mutant NAME] [--app PATH]

Media are made under `tools/proof/work/co7/media/` as `co6_proof.media()` makes them: ffmpeg's
`testsrc`, 6 s at 30 fps, a 1280 × 720 camera and a 1920 × 1080 screen. Every fixture is a saved
1920 × 1080, 30 fps package: the screen at 0 on the back track, the camera at 0 on a front track
named "Camera", trimmed to [0, 4 s). A frame is 20 000 ticks. The canned packs are
`co2a_probe.swift`'s (`pack` mode), installed by `co2a_proof.install_pack` beside a canned marker
as `co4_proof.py` does: kind `person_left` — 512 × 288, columns 160–223 × rows 72–215 at 255 — so
on the 1280 × 720 camera the centroid is (480, 360) and the focus (−160, 0). A circle's crop is
the 720 square: centred on x 480 it is l 120, r 440; on the source's centre l 280, r 280.

**Probe rows** (`co7_probe.swift`, built through `swift_build.py` with `FRAMEJOB_DEV_TOOLS`; a
probe that will not build is a scored FAIL):
- P1 the Layout section's place (after Transform and Behind Subject, before Crop; absent for two
  clips); Circle + Top Left and Switch at Playhead equal to the editor's `switchCameraLayout`
  with Circle ▸ Top Left's tag on a twin, one undo step "Camera Layout" each; Duration 1.00 a
  600000-tick action; enabled with the playhead off the clip and back; pressed off the clip, no
  change, no undo step, `projectDocumentDidRefuse` carrying "does not play at".
- P4 an editor in an `NSWindow`, the screen zooming at 3 s, the camera selected, the playhead at
  1 s, Side by Side: the sheet up over an unchanged project, the core's sentence and the buttons
  "Nest and Switch" and "Cancel"; Cancel changes nothing; Nest and Switch equals
  `switch_layout {nest: true}` on a twin and one undo "Camera Layout" restores it.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) in one canned launch
(`-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600`, so no job runs beside a canned marker), on
a scratch `CFFIXED_USER_HOME`, each document closed after its row:
- P2 the pack covering the file: Clip ▸ Camera Layout ▸ Circle ▸ Bottom Right at 2 s with the
  camera selected, polled through `get_project` for at most 10 s: the crop centre (480, 360)
  ± 1 px, l 120, r 440. P2b with the marker's coverage [[0, 59]] (half the clip's frames): the
  centre (640, 360). P2c the camera cut out, `analyze_cutout {clips: [camera]}` answers
  `centroid` (480, 360) ± 1e-6.
- P3 no pack: the centre (640, 360).
- P5 `switch_layout` without `focus` on a twin of P2 equals P2's menu project and answers
  `focus` [−160, 0] ± 1e-6; with `focus: [0, 0]` the crop centres.
- P6 P2's fixture with a zoom on the camera from 2.5 s to 3.5 s: `switch_layout {camera,
  layout: side_by_side, at: 2 s, nest: true}` without `focus` answers `focus: null`, its project
  equals the same op with `focus: [0, 0]` on a twin, and the camera's id is inside the new nest.
- Z1 the launch's `grep "Frame Job: "` prints nothing.

`--mutant NAME` edits a copy and runs only its row: `two-steps` a copy of `app/Sources` the probe
is built from; the others a `tree_copy.py` copy built as the proof's configuration. CAUGHT exits
1, SURVIVED exits 0, a control that could not be performed exits 2.
"""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE / "cutout_spike"))
sys.path.insert(0, str(HERE / "creator_spike"))
import bounded  # noqa: E402
import co2a_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co7"
HOME = WORK / "home"
KEEP = {"media"}
SEC = 600_000
FRAMES = 180
CAMERA = (1280, 720)
SCREEN = (1920, 1080)
CALL_BOUND = 600
BUILD_BOUND = 1500
PROBE_WALL = 300
POLL = 10.0
CANNED = ["-RCDevAnalysisCanned", "YES", "-RCDevAnalysisHold", "3600"]
PROBE_ROWS = ["P1", "P4"]
APP_ROWS = ["P2", "P2b", "P2c", "P3", "P5", "P6"]
ROWS = ["Z1"] + PROBE_ROWS + APP_ROWS

FOCUS = "app/Sources/CameraLayoutFocus.swift"
SHEET = "app/Sources/LayoutOfferSheet.swift"
TOOL = "app/Sources/AgentServer+Layout.swift"
COMMAND = "app/Sources/CameraLayoutCommand.swift"
# name → (rows, [(path, anchor, replacement)], "probe" or "app")
MUTANTS = {
    "partial-window": (["P2b"], [(
        FOCUS,
        "        guard CutoutStatus.count(CutoutStatus.intersect(need, coverage)) == frames "
        "else { return nil }\n", "")], "app"),
    "two-steps": (["P4"], [(
        SHEET,
        "            document.performGroupedEdit(CameraLayoutCommand.actionName, [nested])\n",
        "            document.performGroupedEdit(\"Nest\", [.nest(clips: document.editedProject"
        ".snapshot.clips.filter { $0.actions.contains { ActionBands.isZoom($0) } }.map(\\.id))])\n"
        "            document.performGroupedEdit(CameraLayoutCommand.actionName, [nested])\n")],
        "probe"),
    "tool-no-focus": (["P5"], [(
        TOOL,
        "            inputs: focus == nil ? CameraLayoutFocus.inputs(camera: camera.id, in: "
        "document) : nil,\n", "            inputs: nil,\n")], "app"),
    "nest-keeps-focus": (["P6"], [(
        COMMAND, "        return view.snapshot.clip(camera) != nil\n",
        "        return true\n")], "app"),
}

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


def t(seconds):
    return int(round(seconds * SEC))


# ---- media, the probes ---------------------------------------------------------------------

def media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    made = {}
    for name, (w, h) in (("camera", CAMERA), ("screen", SCREEN)):
        out = folder / f"{name}.mov"
        if not out.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                            f"testsrc=size={w}x{h}:rate=30:duration=6", "-c:v", "libx264",
                            "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-g", "30", str(out)],
                           check=True, timeout=600, env=bounded.child_env())
        made[name] = out
    return made


def build_probe(name, entry_source, sources, extra=()):
    """`entry_source` built as `main.swift` over `sources` (and `extra`); the binary, or None
    with the build's diagnostics."""
    out = WORK / f"probe-{name}"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(entry_source, entry)
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    binary = out / name
    try:
        swift_build.build(sources=swift + [str(e) for e in extra] + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "; ".join(error.diagnostics[:6])
    return binary, None


def probe_rows(files, sources):
    binary, why = build_probe("co7-probe", HERE / "co7_probe.swift", sources)
    if binary is None:
        for row in PROBE_ROWS:
            check(row, False, f"the probe did not build: {why}")
        return
    request = WORK / "probe-request.json"
    request.write_text(json.dumps({"work": str(WORK / "probe-work"), "camera": str(files["camera"]),
                                   "screen": str(files["screen"])}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=PROBE_WALL,
                             env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    except subprocess.TimeoutExpired:
        for row in PROBE_ROWS:
            check(row, False, f"the probe gave no answer within {PROBE_WALL} s")
        return
    (WORK / "probe-stderr.txt").write_text(run.stderr)
    lines = [line for line in run.stdout.splitlines() if line.strip().startswith("{")]
    try:
        answers = {r["id"]: r for r in json.loads(lines[-1])["rows"]}
    except (ValueError, KeyError, IndexError):
        answers = {}
    for row in PROBE_ROWS:
        answer = answers.get(row)
        if answer is None:
            check(row, False, f"the probe did not answer it (exit {run.returncode})")
        else:
            check(row, answer["pass"], answer["detail"])


def pack_probe():
    """`co2a_probe.swift` built as `co4_proof.probe_row` builds it, for the canned packs."""
    binary, why = build_probe("co2a-probe", HERE / "co2a_probe.swift", ROOT / "app/Sources",
                              extra=[HERE / "cutout_spike" / "mask_track_writer.swift"])
    if binary is None:
        return why
    co2a_proof.PROBE = binary
    co2a_proof.WORK = WORK
    return None


# ---- a document ----------------------------------------------------------------------------

class Doc:
    """One saved package: the screen on the back track, the camera on a front "Camera" track
    trimmed to [0, 4 s); with `coverage`, a canned `person_left` pack for the camera's media."""

    def __init__(self, client, files, name, coverage=None, zoom=False):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.close()
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            try:
                self.call("set_canvas", width=1920, height=1080, fps=[30, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):
                    raise
            self.call("save_project")
            self.screen, _ = self.place(files["screen"], 0)
            self.camera, self.media = self.place(files["camera"], 1)
            self.call("set_track", track=self.state()["tracks"][1]["id"], name="Camera")
            self.call("trim_end", clip=self.camera, to=t(4))
            if zoom:
                self.call("add_zoom_action", clip=self.camera, at=t(2.5), duration=t(1),
                          region={"x": 0, "y": 0, "width": 640, "height": 360})
            if coverage is not None:
                duration = next(m for m in self.state()["media"]
                                if m["id"] == self.media)["duration"]
                co2a_proof.install_pack(self.path, self.media, files["camera"], duration,
                                        kind="person_left", coverage=coverage, frames=FRAMES)
        except Exception:
            self.close()
            raise

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def place(self, path, index):
        tracks = self.state()["tracks"]
        while len(tracks) <= index:
            self.call("add_track")
            tracks = self.state()["tracks"]
        m = self.call("import_media", path=str(path))["media"]
        clip = self.call("add_clip", track=tracks[index]["id"], media=m, at=0)["new_clips"][0]
        return clip, m

    def action_at(self, at, state=None):
        clip = next(c for c in (state or self.state())["clips"] if c["id"] == self.camera)
        return next((a for a in clip.get("actions", []) if a["start"] == at), None)

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def centre(action):
    """The camera crop's centre in source pixels, from a layout action's end."""
    crop = action["end"]["video"].get("crop") or {}
    l, r = crop.get("l", 0.0), crop.get("r", 0.0)
    top, b = crop.get("t", 0.0), crop.get("b", 0.0)
    return (l + (CAMERA[0] - l - r) / 2, top + (CAMERA[1] - top - b) / 2), (l, r)


def menu_circle(doc):
    """Clip ▸ Camera Layout ▸ Circle ▸ Bottom Right at 2 s with the camera selected, polled
    for its layout action; (centre, (l, r), state)."""
    doc.call("set_playhead", t=t(2))
    doc.call("set_selection", clips=[doc.camera])
    doc.call("perform_menu_item", path=["Clip", "Camera Layout", "Circle", "Bottom Right"])
    deadline = time.monotonic() + POLL
    while True:
        state = doc.state()
        action = doc.action_at(t(2), state)
        if action is not None:
            point, sides = centre(action)
            return point, sides, state
        if time.monotonic() > deadline:
            raise RuntimeError(f"no layout action at 2 s within {POLL} s of the menu item")
        time.sleep(0.25)


def near(point, want, tolerance):
    return all(abs(a - b) <= tolerance for a, b in zip(point, want))


def with_doc(client, files, name, rows, body, **kw):
    doc = attempt(lambda: Doc(client, files, name, **kw), *rows)
    if doc is None:
        return None
    try:
        return attempt(lambda: body(doc), *rows)
    finally:
        doc.close()


# ---- the app rows --------------------------------------------------------------------------

MENU_PROJECT = {}


def p2(doc):
    point, sides, state = menu_circle(doc)
    MENU_PROJECT["state"] = state
    check("P2", near(point, (480, 360), 1) and near(sides, (120, 440), 1),
          f"the crop centre {point}, l and r {sides} (want (480, 360) ± 1, l 120, r 440)")
    if "P2c" in selected:
        doc.call("set_video", clips=[doc.camera], patch={"cutout": {}})
        answer = doc.call("analyze_cutout", clips=[doc.camera])
        row = answer["clips"][0]
        got = row.get("centroid") or {}
        check("P2c", near((got.get("x", 1e9), got.get("y", 1e9)), (480, 360), 1e-6),
              f"analyze_cutout: state {row.get('state')}, centroid {got}")


def p2b(doc):
    point, sides, _ = menu_circle(doc)
    check("P2b", near(point, (640, 360), 1),
          f"half the clip analysed: the crop centre {point}, l and r {sides} (want (640, 360))")


def p3(doc):
    point, sides, _ = menu_circle(doc)
    check("P3", near(point, (640, 360), 1),
          f"no masks: the crop centre {point}, l and r {sides} (want (640, 360))")


def p5(doc):
    answer = doc.call("switch_layout", camera=doc.camera, layout="corner", shape="circle",
                      corner="bottom_right", at=t(2))
    state = doc.state()
    focus = answer.get("focus")
    menu = MENU_PROJECT.get("state")
    equal = menu is not None and state == menu
    focused = isinstance(focus, list) and len(focus) == 2 and near(focus, (-160, 0), 1e-6)
    check("P5", equal and focused,
          f"switch_layout without focus answered focus {focus} (want [-160, 0]); its project "
          f"equal to P2's menu project {equal}" + ("" if menu else " (P2 left none)"))
    doc.call("undo")
    doc.call("switch_layout", camera=doc.camera, layout="corner", shape="circle",
             corner="bottom_right", at=t(2), focus=[0, 0])
    point, sides = centre(doc.action_at(t(2)))
    check("P5", near(point, (640, 360), 1),
          f"focus [0, 0]: the crop centre {point}, l and r {sides} (want (640, 360))")


def p6(client, files):
    def nested_answer(doc):
        answer = doc.call("switch_layout", camera=doc.camera, layout="side_by_side", at=t(2),
                          nest=True)
        return answer, doc.state(), doc.camera

    found = with_doc(client, files, "p6", ["P6"], nested_answer, coverage=[[0, FRAMES - 1]],
                     zoom=True)
    if found is None:
        return
    answer, state, camera = found

    def twin_state(doc):
        doc.call("switch_layout", camera=doc.camera, layout="side_by_side", at=t(2), nest=True,
                 focus=[0, 0])
        return doc.state()

    twin = with_doc(client, files, "p6-twin", ["P6"], twin_state, zoom=True)
    inside = any(c["id"] == camera for n in state.get("nests", []) for c in n["clips"])
    check("P6", answer.get("focus", "absent") is None and state == twin and inside,
          f"nest: true without focus answered focus {answer.get('focus', 'absent')!r} (want "
          f"null); its project equal to focus [0, 0] on a twin {state == twin}; the camera "
          f"inside the new nest {inside}")


def app_rows(client, files):
    if {"P2", "P2c", "P5"} & selected:
        with_doc(client, files, "p2", ["P2", "P2c"], p2, coverage=[[0, FRAMES - 1]])
    if "P2b" in selected:
        with_doc(client, files, "p2b", ["P2b"], p2b, coverage=[[0, 59]])
    if "P3" in selected:
        with_doc(client, files, "p3", ["P3"], p3)
    if "P5" in selected:
        with_doc(client, files, "p5", ["P5"], p5, coverage=[[0, FRAMES - 1]])
    if "P6" in selected:
        attempt(lambda: p6(client, files), "P6")


def with_instance(binary, files):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), CANNED,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in set(APP_ROWS) & selected:
                check(row, False, "the app did not listen")
            return False
        print(f"  instance PID {launched.child.pid} ({' '.join(CANNED)})", flush=True)
        app_rows(launched.client, files)
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return True


# ---- mutants -------------------------------------------------------------------------------

def edited(name, root):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def run_mutant(name, files):
    global selected
    rows, _, kind = MUTANTS[name]
    selected = set(rows)
    print(f"CO7 — the {name} MUTANT ({', '.join(rows)} must FAIL, {proof_app.config()} build)",
          flush=True)
    if kind == "probe":
        copy = WORK / "mutant-sources"
        if copy.exists():
            shutil.rmtree(copy)
        shutil.copytree(ROOT / "app/Sources", copy / "app/Sources")
        why = edited(name, copy)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        probe_rows(files, copy / "app/Sources")
    else:
        selected |= {"Z1"}
        made, why = tree_copy.make_copy(str(WORK / "mutant"))
        why = why or edited(name, Path(made))
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        app, why = tree_copy.build_app(Path(made), BUILD_BOUND)
        if app is None:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        why = pack_probe()
        if why:
            print(f"mutant {name}: the control could not be performed — the pack probe: {why}")
            return 2
        if not with_instance(proof_app.executable(app), files):
            print(f"mutant {name}: the control could not be performed — the app did not listen")
            return 2
    if not all(row in results for row in rows):
        print(f"mutant {name}: the control could not be performed — {rows} never scored")
        return 2
    caught = any(not all(ok for ok, _ in results[row]) for row in rows)
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


# ---- main ----------------------------------------------------------------------------------

def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & set(APP_ROWS):
            selected.add("Z1")
    if WORK.exists():
        for child in WORK.iterdir():
            if child.name not in KEEP:
                tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    files = media()
    if args.mutant:
        return run_mutant(args.mutant, files)

    print(f"CO7 — the Layout section, the nest offer and the crop on the person "
          f"({proof_app.config()} build)", flush=True)
    if selected & set(PROBE_ROWS):
        attempt(lambda: probe_rows(files, ROOT / "app/Sources"), *(selected & set(PROBE_ROWS)))
    if selected & set(APP_ROWS):
        why = pack_probe()
        if why:
            for row in (selected & set(APP_ROWS)) | {"Z1"}:
                check(row, False, f"the pack probe did not build: {why}")
        else:
            binary = Path(args.app) if args.app else proof_app.binary()
            if binary.suffix == ".app":
                binary = proof_app.executable(binary)
            with_instance(binary, files)

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
