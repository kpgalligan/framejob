#!/usr/bin/env python3
"""Docs bugs, batch a4 (#473 #472 #478 #490 #495; spec §11 #472, #478, #495): menu items that
promise what their edit refuses.

    python3 tools/proof/docs_bugs_a4_proof.py [--only F1,M1,…] [--app PATH] [--base-sources PATH]
                                              [--expect-red] [--mutant NAME]
    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_a4_proof.py \
        --base-sources <a tree at the base>/app/Sources --expect-red
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_a4_proof.py

The built app (`proof_app`'s choice, or `--app`) on a scratch `CFFIXED_USER_HOME` under
`work/docs-bugs-a4/`. `(c)` marks a CONTROL, which passes on the base too; every other row is red on
the frozen base app with `--base-sources` set to the base's `app/Sources`, and `--expect-red` exits 0
only when that holds. The media is `media/A.mov` (video only) and `media/toneA.m4a` (audio only).
A menu item's state is `perform_menu_item` with no path, which asks each item's validator.

- Freeze Frame (#473), the playhead at 1 s, a video clip at 0.5 s, a sound clip and a text clip at
  0: F1 the text clip selected: Clip ▸ Freeze Frame disabled. F2 the sound clip: disabled. F3 the
  text and the video selected, the text first by start: performing it applies with no sheet, Undo
  reads "Undo Freeze Frame", and a still is on the video's track. F4 (c) the video alone and F5 (c)
  the video with its picture off: enabled, and each applies. F6 (c) the video, the playhead at
  0.2 s: disabled.
- Markers (#472): M1 Mark ▸ Add Marker twice on one frame: the second puts up no sheet, one marker,
  Undo unchanged, the editor's texts hold "Refused: marker N is already at T ticks; two markers may
  not share a frame". M2 `add_marker` at that tick answers "Add Marker was refused at add_marker:
  …". M3 `set_marker` with a `time` on it: "Marker was refused at set_marker: …". M4 (c) a free tick applies.
- Remove Track (#490), nothing selected: T1 one track holding a clip: Track ▸ Remove Track
  disabled. T3 one empty track: disabled. T2 (c) two tracks, the front one holding the clip:
  enabled, and the alert asks; `cancel_sheet` answers it.
- Probe, `docs_bugs_a4_probe.swift` through `swift_build.build()`, the same source on the base and
  the fix: N1 the panel `.starting`, not launched, the recorder idle: `validateMenuItem` titles File
  ▸ New Recording… "Stop Recording". N2 (c) `.starting`, launched, the recorder `.arming`: "Stop
  Recording". N3 (c) idle: "New Recording…". N4 (c) `.starting`, not launched, then
  `newRecording(nil)`: idle, with the abandoned note. N5 (c) the recorder `.recording`, the panel
  idle: "Stop Recording". P1 the Document tab's Rate popup drawn on a 59.94 project differs from
  the same popup on a 24 project; P2 48 against 24, the same; P3 (c) 30 against 24 differs. P5 on a
  59.94 project with a 30 fps clip, the popup's item past Match First Clip (Custom) picked: the
  rate stays 59.94.
- Z1 (c) `grep "Frame Job: "` on each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a `tree_copy.py` copy. A mutant of app rows builds
the copy's app and drives it; one of probe rows only builds the probe over the copy's sources and
makes its packages with the tree's app. `marker-err` is a core mutant: its copy gets a real `core/`.
CAUGHT exits 1 when every named row failed, SURVIVED exits 0, and a control that could not be
performed (the copy did not build, an anchor not found once) exits 2. An instrument that cannot
run is a scored failure, never an exit.
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

WORK = ROOT / "tools/proof/work/docs-bugs-a4"
HOME = WORK / "home"
LOGS = WORK / "logs"
OUT = WORK / "probe"
MEDIA = HERE / "media"
VIDEO = MEDIA / "A.mov"
TONE = MEDIA / "toneA.m4a"
PROBE = HERE / "docs_bugs_a4_probe.swift"
CALL_BOUND = 300
BUILD_BOUND = 1500
PROBE_BOUND = 400
SEC = 600000
TAKEN = re.compile(r"marker \d+ is already at \d+ ticks; two markers may not share a frame$")

FREEZE_ROWS = ["F1", "F2", "F3", "F4", "F5", "F6"]
MARKER_ROWS = ["M1", "M2", "M3", "M4"]
TRACK_ROWS = ["T1", "T2", "T3"]
PROBE_ROWS = ["N1", "N2", "N3", "N4", "N5", "P1", "P2", "P3", "P5"]
ROWS = FREEZE_ROWS + MARKER_ROWS + TRACK_ROWS + PROBE_ROWS + ["Z1"]
CONTROLS = {"F4", "F5", "F6", "M4", "T2", "N2", "N3", "N4", "N5", "P3", "Z1"}

TIMELINE = "app/Sources/EditorViewController+Timeline.swift"
TRACK = "core/src/edit_track.rs"
PANE = "app/Sources/DocumentPane.swift"
DELEGATE = "app/Sources/AppDelegate.swift"
# name: (the rows it must turn red, the edits).
MUTANTS = {
    "freeze-any": (["F1", "F2"], [(
        TIMELINE, "            return !freezableUnderPlayhead.isEmpty\n",
        "            return !clipsUnderPlayhead.isEmpty\n")]),
    "freeze-no-video": (["F2"], [(
        TIMELINE, "clipsUnderPlayhead.filter { $0.source.hasSourceBound && $0.video != nil }",
        "clipsUnderPlayhead.filter { $0.source.hasSourceBound }")]),
    "freeze-first": (["F3"], [(
        TIMELINE, "let clip = freezableUnderPlayhead.first else {",
        "let clip = clipsUnderPlayhead.first else {")]),
    "marker-err": (["M1", "M2"], [(
        TRACK, "            return Ok(marker_taken(existing.id, at));\n",
        "            return Err(format!(\"marker {} is already at {at} ticks\", existing.id));\n")]),
    "track-any": (["T1"], [(
        TIMELINE,
        "            return currentTrack != nil && document.editedProject.snapshot.tracks.count > 1\n",
        "            return currentTrack != nil\n")]),
    "rate-24": (["P1", "P2"], [(PANE, "                    ?? items.count - 1\n",
                                "                    ?? 0\n")]),
    "custom-matches": (["P5"], [(
        PANE, "} else if index == rates.count, let fps = self?.firstClipRate() {",
        "} else if let fps = self?.firstClipRate() {")]),
    "title-recorder": (["N1"], [(
        DELEGATE,
        "            item.title = Self.newRecordingStops ? \"Stop Recording\" : \"New Recording…\"\n",
        "            item.title = ScreenRecorder.shared.isRecording ? \"Stop Recording\" : "
        "\"New Recording…\"\n")]),
}

results = {}
selected = set(ROWS)
logs = []


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


# ---- instances --------------------------------------------------------------------------

def start(binary, label):
    log = LOGS / f"{label}.log"
    logs.append(log)
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), [], env=env, log_path=str(log), timeout=CALL_BOUND)
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

    def __init__(self, client, name):
        self.client = client
        self.folder = WORK / f"out-{name}"
        self.folder.mkdir(parents=True, exist_ok=True)
        self.path = str(WORK / f"{name}.framejob")
        client.call_with("new_project", {"path": self.path})
        self.media = {}

    def op(self, tool, **arguments):
        return self.client.call_with(tool, dict(arguments, project=self.path))

    def state(self):
        return self.op("get_project")["project"]

    def tracks(self):
        return [track["id"] for track in self.state()["tracks"]]

    def place(self, path, track=None, at=0.0):
        if str(path) not in self.media:
            self.media[str(path)] = self.op("import_media", path=str(path))["media"]
        track = self.tracks()[0] if track is None else track
        return self.op("add_clip", track=track, media=self.media[str(path)],
                       at=round(at * SEC))["new_clips"][0]

    def items(self):
        """The main menu as this window validates it: {"A > B": item}."""
        return {" > ".join(item["path"]): item for item in self.op("perform_menu_item")["items"]}

    def enabled(self, name):
        item = self.items().get(name)
        return None if item is None else item.get("enabled")

    def undo_title(self):
        return next((name for name in self.items() if name.startswith("Edit > Undo")), None)

    def perform(self, *path):
        """The item performed, and any sheet it left read and answered: (answer, sheet texts)."""
        answer = self.op("perform_menu_item", path=list(path))
        texts = None
        if answer.get("sheet") or answer.get("sheet_at_return"):
            texts = self.texts("sheet")
            self.op("cancel_sheet")
        return answer, texts

    def texts(self, window):
        picture = self.folder / f"{window}-{time.monotonic_ns()}.png"
        shot = self.op("snapshot_ui", window=window, path=str(picture))
        layout = shot.get("layout_path") or str(picture.with_suffix(".layout.json"))
        with open(layout) as handle:
            return [view.get("text") for view in json.load(handle)["views"]
                    if view.get("text") and not view.get("hidden")]

    def close(self):
        self.op("close_project", discard=True)


def at(project, seconds, clips):
    project.op("set_selection", clips=clips)
    project.op("set_playhead", t=round(seconds * SEC))
    time.sleep(0.3)


# ---- #473 -------------------------------------------------------------------------------

def freeze_rows(client):
    project = Project(client, "freeze")
    back = project.tracks()[0]
    project.op("add_track", index=1)
    project.op("add_track", index=2)
    _, middle, front = project.tracks()
    video = project.place(VIDEO, back, 0.5)
    tone = project.place(TONE, middle, 0)
    text = project.op("add_text_clip", track=front, at=0, duration=4 * SEC,
                      text="Title")["new_clips"][0]
    name = "Clip > Freeze Frame"

    def disabled(row, clips, seconds=1.0):
        at(project, seconds, clips)
        state = project.enabled(name)
        check(row, state is False, f"clips {clips} at {seconds} s: Freeze Frame enabled {state}")

    attempt(["F1"], lambda: disabled("F1", [text]))
    attempt(["F2"], lambda: disabled("F2", [tone]))
    attempt(["F6"], lambda: disabled("F6", [video], 0.2))

    def applies(row, clips):
        at(project, 1.0, clips)
        state = project.enabled(name)
        before = project.state()["clips"]
        answer, sheet = project.perform("Clip", "Freeze Frame")
        clips_after = project.state()["clips"]
        stills = [clip["id"] for clip in clips_after if clip.get("track") == back
                  and (clip.get("source") or {}).get("kind") == "still"]
        undo = project.undo_title()
        ok = (sheet is None and not answer.get("sheet_at_return") and bool(stills)
              and undo == "Edit > Undo Freeze Frame" and clips_after != before and state is True)
        check(row, ok, f"clips {clips}: enabled {state}, sheet {sheet}, stills on the video's "
                       f"track {stills}, {undo!r}")
        if clips_after != before:
            project.op("undo")

    attempt(["F3"], lambda: applies("F3", [text, video]))
    attempt(["F4"], lambda: applies("F4", [video]))

    def f5():
        project.op("set_enabled", clip=video, video=False)
        applies("F5", [video])

    attempt(["F5"], f5)
    project.close()


# ---- #472 -------------------------------------------------------------------------------

def marker_rows(client):
    project = Project(client, "markers")
    project.place(VIDEO)
    at(project, 1.0, [])
    first = project.op("perform_menu_item", path=["Mark", "Add Marker"])
    markers = project.state()["markers"]
    if len(markers) != 1:
        raise RuntimeError(f"the first Add Marker left {markers}: {first}")
    holder, tick = markers[0]["id"], markers[0]["time"]
    want = f"marker {holder} is already at {tick} ticks; two markers may not share a frame"

    def m1():
        undo = project.undo_title()
        answer = project.op("perform_menu_item", path=["Mark", "Add Marker"])
        foot = project.texts("editor") if not answer.get("sheet") else []
        sheet = None
        if answer.get("sheet") or answer.get("sheet_at_return"):
            sheet = project.texts("sheet")
            project.op("cancel_sheet")
        after = project.state()["markers"]
        said = next((line for line in foot if line.startswith("Refused: ")), None)
        ok = (answer.get("sheet_at_return") is False and sheet is None and len(after) == 1
              and project.undo_title() == undo and said == f"Refused: {want}")
        check("M1", ok, f"sheet_at_return {answer.get('sheet_at_return')}, sheet {sheet}, "
                        f"markers {len(after)}, {undo!r}, foot {said!r}")

    attempt(["M1"], m1)

    def refused(row, tool, action, **arguments):
        try:
            answer = project.op(tool, **arguments)
            said = f"applied: {answer}"
        except mcp.ToolError as error:
            said = str(error)
        # mcp.ToolError's text leads with the tool's name.
        check(row, said == f"{tool}: {action} was refused at {tool}: {want}", said[:200])

    attempt(["M2"], lambda: refused("M2", "add_marker", "Add Marker", at=tick))

    def m3():
        other = project.op("add_marker", at=tick + 2 * SEC)
        marker = [m["id"] for m in project.state()["markers"] if m["id"] != holder][0]
        refused("M3", "set_marker", "Marker", marker=marker, time=tick)
        check("M4", other.get("ok") is True, f"add_marker at a free tick: {str(other)[:120]}")

    attempt(["M3", "M4"], m3)
    project.close()


# ---- #490 -------------------------------------------------------------------------------

def track_rows(client):
    name = "Track > Remove Track"

    def t1():
        project = Project(client, "one-track")
        project.place(VIDEO)
        at(project, 1.0, [])
        state = project.enabled(name)
        check("T1", state is False, f"one track holding a clip: Remove Track enabled {state}")
        project.close()

    attempt(["T1"], t1)

    def t3():
        project = Project(client, "one-empty-track")
        state = project.enabled(name)
        check("T3", state is False, f"one empty track: Remove Track enabled {state}")
        project.close()

    attempt(["T3"], t3)

    def t2():
        project = Project(client, "two-tracks")
        project.op("add_track", index=1)
        front = project.tracks()[-1]
        project.place(VIDEO, front)
        at(project, 1.0, [])
        state = project.enabled(name)
        answer, sheet = project.perform("Track", "Remove Track")
        sheet = sheet or []
        asks = (len(sheet) == 4 and sheet[0].startswith("Remove “") and sheet[0].endswith("”?")
                and sheet[1] == "The track still holds 1 clip, which will be removed with it."
                and set(sheet[2:]) == {"Cancel", "Remove"})
        tracks = project.tracks()
        check("T2", state is True and asks and len(tracks) == 2,
              f"enabled {state}, the alert {sheet}, tracks after Cancel {tracks}")
        project.close()

    attempt(["T2"], t2)


# ---- the probe --------------------------------------------------------------------------

def save_packages(client):
    """The probe's packages, made and saved by the app: {name: path}."""
    packages = {}
    for name, fps in (("r24", [24, 1]), ("r5994", [60000, 1001]), ("r48", [48, 1]),
                      ("r30", [30, 1]), ("r5994clip", [60000, 1001])):
        project = Project(client, f"package-{name}")
        if name == "r5994clip":
            project.place(VIDEO)
        if project.state()["canvas"]["fps"] != fps:  # a new project is 30 fps already
            project.op("set_canvas", fps=fps)
        got = project.state()["canvas"]["fps"]
        project.op("save_project")
        packages[name] = project.path
        project.op("close_project")
        print(f"  package {name}: fps {got or fps}", flush=True)
    return packages


def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "docs-bugs-a4-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def digest(path):
    return Path(path).read_bytes() if path and Path(path).is_file() else None


def probe_rows(binary, packages):
    fixtures = OUT / "fixtures.json"
    fixtures.write_text(json.dumps(packages))
    scratch = OUT / "scratch"
    scratch.mkdir(parents=True, exist_ok=True)
    rows_wanted = ",".join(sorted(selected & set(PROBE_ROWS)))
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    done = subprocess.run([str(binary), str(fixtures), str(scratch), rows_wanted],
                          capture_output=True, text=True, env=env, timeout=PROBE_BOUND, cwd=OUT,
                          stdin=subprocess.DEVNULL)
    rows = {}
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            answer = json.loads(line)
            rows[answer["row"]] = answer
    if done.returncode != 0 or "done" not in rows:
        raise RuntimeError(f"exit {done.returncode}, rows {sorted(rows)}: {done.stderr[-300:]}")

    def title(row, want):
        answer = rows.get(row, {})
        check(row, answer.get("title") == want and answer.get("enabled") is True,
              f"{answer.get('title')!r}, enabled {answer.get('enabled')}, "
              f"{ {k: v for k, v in answer.items() if k not in ('row', 'title', 'enabled')} }")

    if "N1" in selected:
        title("N1", "Stop Recording")
    if "N2" in selected:
        title("N2", "Stop Recording")
    if "N3" in selected:
        title("N3", "New Recording…")
    if "N4" in selected:
        answer = rows.get("N4", {})
        check("N4", answer.get("phase") == "idle" and answer.get("note") == answer.get("abandoned")
              and answer.get("visible") is False, f"{answer}")
    if "N5" in selected:
        title("N5", "Stop Recording")
    for row, want_differs in (("P1", True), ("P2", True), ("P3", True)):
        if row not in selected:
            continue
        answer = rows.get(row, {})
        rate, base = answer.get("rate", {}), answer.get("r24", {})
        a, b = digest(rate.get("png")), digest(base.get("png"))
        check(row, a is not None and b is not None and (a != b) == want_differs,
              f"fps {rate.get('fps')} against {base.get('fps')}: the PNGs differ "
              f"{a != b if a and b else None} ({rate.get('failed') or rate.get('png')})")
    if "P5" in selected:
        answer = rows.get("P5", {})
        check("P5", answer.get("before") == [60000, 1001] and answer.get("after") == [60000, 1001],
              f"tag {answer.get('tag')}: fps {answer.get('before')} → {answer.get('after')}, "
              f"clips {answer.get('clips')}")


# ---- the run ----------------------------------------------------------------------------

def run(binary, sources, package_app=None):
    """The app rows on `binary`; the probe built over `sources`, its packages made by
    `package_app` (else `binary`)."""
    probe, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe, why = build_probe(sources)
        if why:
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
    app_rows = selected & set(FREEZE_ROWS + MARKER_ROWS + TRACK_ROWS)
    packages = None
    if app_rows or probe is not None:
        launched = start(package_app if (package_app and not app_rows) else binary, "main")
        try:
            if launched.client is None:
                for row in sorted(selected - {"Z1"}):
                    check(row, False, "the app did not listen")
                return
            client = launched.client
            if selected & set(FREEZE_ROWS):
                attempt(FREEZE_ROWS, lambda: freeze_rows(client))
            if selected & set(MARKER_ROWS):
                attempt(MARKER_ROWS, lambda: marker_rows(client))
            if selected & set(TRACK_ROWS):
                attempt(TRACK_ROWS, lambda: track_rows(client))
            if probe is not None:
                def keep():
                    nonlocal packages
                    packages = save_packages(client)

                attempt(PROBE_ROWS, keep)
        finally:
            launched.stop()
    if probe is not None and packages is not None:
        attempt(sorted(selected & set(PROBE_ROWS)), lambda: probe_rows(probe, packages))


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made_copy, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made_copy is None:
        return None, reason
    edits = MUTANTS[name][1]
    if any(path.startswith("core/") for path, _, _ in edits):
        # A tree_copy copy's `core` is a link to the tree's: the copy gets its own, its target
        # copied on write, so the edit stays in the copy.
        link = Path(made_copy) / "core"
        if link.is_symlink():
            link.unlink()
        subprocess.run(["cp", "-cR", str(ROOT / "core"), str(link)], check=True)
    for path, anchor, replacement in edits:
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
    for folder in (HOME, LOGS):
        folder.mkdir(parents=True)

    binary = Path(args.app) if args.app else None
    sources = Path(args.base_sources) if args.base_sources else ROOT / "app/Sources"
    package_app = None
    if args.mutant:
        named = " ".join(MUTANTS[args.mutant][0])
        print(f"docs bugs a4 — the {args.mutant} MUTANT ({named} must FAIL)", flush=True)
        copy, why = mutate(args.mutant)
        if why is None:
            sources = copy / "app/Sources"
            if set(MUTANTS[args.mutant][0]) <= set(PROBE_ROWS):
                package_app = proof_app.binary()
                binary = package_app
            else:
                app, why = tree_copy.build_app(copy, BUILD_BOUND)
                binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"docs bugs a4 — menu items that promise what their edit refuses ({binary.name})",
          flush=True)

    run(binary, sources, package_app)
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
