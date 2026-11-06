#!/usr/bin/env python3
"""Docs bugs, batch b5 (#497; spec §11 #497): a folder dropped on the Media tab, or given to
`import_media`, imports the media files directly inside it.

    python3 tools/proof/docs_bugs_b5_proof.py [--only M1,D1,…] [--app PATH] [--base-sources PATH]
                                              [--expect-red] [--mutant NAME]
    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_b5_proof.py \
        --base-sources <a tree at the base>/app/Sources --expect-red
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_b5_proof.py

The built app (`proof_app`'s choice, or `--app`) on a scratch `CFFIXED_USER_HOME` under
`work/docs-bugs-b5/`. `(c)` marks a CONTROL, which passes on the base too; every other row is red on
the frozen base app with `--base-sources` set to the base's `app/Sources`, and `--expect-red` exits 0
only when that holds. The fixtures are made here, so ffmpeg is needed at proof time.

The fixtures: `Shoot/` holds `Clip 2.mov` (A.mov), `Clip 10.mov` (B.mov), `look.cube` (a 2³ LUT),
`still.png`, `Take 3` (Matroska with no extension), `readme.txt`, `.h.mov` (hidden), `Sub/C.mov`,
`Notes.rtfd/` (a package) and `Old.framejob/` (with `C.mov`). `ShootLink` is a link to it, `Shoot.mov/`
an empty folder, `Broken/` holds `A.mov` and `broken.mov` (text), `Docs/` holds `readme.txt`, and
`Locked/` holds `A.mov` and is made unreadable (mode 000) once made; the run gives it back mode 755 at
its end and before it clears the work folder.

- App, `import_media`: M1 on `Shoot`: `imported` is exactly `Clip 2.mov, Clip 10.mov, look.cube,
  still.png, Take 3` in that order (kinds video, video, lut, image, video; `Take 3` with `original`),
  `skipped` holds `readme.txt` "not a media file", `Sub` "a folder" and `Notes.rtfd` "a package", no
  `.h.mov` anywhere, `Old.framejob` not imported and no `C.mov`; media +5; `undo` answers `undone:
  "Add 5 Media Files"` and the media go. M2 after `redo`, `Shoot` again: refused `Nothing in Shoot
  was added. Skipped:` naming "already in the media list"; media unchanged. M3 `Shoot.mov`: exactly
  `Nothing in Shoot.mov was added: it has no files directly inside it.` M4 `ShootLink` in a fresh
  project: the same five. M5 `Broken`: `imported` is `A.mov`; `broken.mov`'s reason starts `Could
  not read broken.mov.` M6 (c) `A.mov`: a `media` integer, no `imported`. M7 `tools/list`'s
  `import_media` says "folder". M9 (c) `Take 3` itself: kind video. M10 (c) `Notes.rtfd` itself:
  `Could not read Notes.rtfd.` M11 `Locked` in a fresh project: exactly `import_media: Nothing in
  Locked was added: it could not be read.`, media unchanged.
- Probe, `docs_bugs_b5_probe.swift` through `swift_build.build()`, with `-RCFFmpegPath
  /nonexistent/ffmpeg`, `ProjectDocument.copyWatch` a no-op for each drop: D1 `Shoot` dropped on the
  Media tab: no sheet, the five added in order, the undo step `Add 5 Media Files`. D2 `Shoot` and
  `C.mov`: no sheet, six added, `C.mov` last. D3 `Broken`: the sheet `Could not read broken.mov.`,
  `A.mov` added. D4 (c) `B.mov` alone: no sheet, one added. D5 `Docs`: no sheet, nothing added. D6
  `Locked`: one sheet `Nothing in Locked was added: it could not be read.`, nothing added, the drop
  performed. PB (c) the general pasteboard's change count is unchanged.
- Z1 (c) `grep "Frame Job: "` on each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a `tree_copy.py` copy, whose app is built and driven
for the named row and Z1 (a D row's probe is built over the copy's `app/Sources`). CAUGHT exits 1,
SURVIVED exits 0, and a control that could not be performed (the copy did not build, an anchor not
found once) exits 2. An instrument that cannot run is a scored failure, never an exit.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
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

WORK = ROOT / "tools/proof/work/docs-bugs-b5"
HOME = WORK / "home"
FILES = WORK / "files"
LOGS = WORK / "logs"
OUT = WORK / "probe"
PROBE = HERE / "docs_bugs_b5_probe.swift"
MEDIA = ROOT / "tools/proof/media"
CALL_BOUND = 300
BUILD_BOUND = 1500
PROBE_BOUND = 300
FIVE = ["Clip 2.mov", "Clip 10.mov", "look.cube", "still.png", "Take 3"]
FIVE_KINDS = ["video", "video", "lut", "image", "video"]

APP_ROWS = ["M1", "M2", "M3", "M4", "M5", "M6", "M7", "M9", "M10", "M11"]
PROBE_ROWS = ["D1", "D2", "D3", "D4", "D5", "D6", "PB"]
ROWS = APP_ROWS + PROBE_ROWS + ["Z1"]
CONTROLS = {"M6", "M9", "M10", "D4", "PB", "Z1"}

FOLDER = "app/Sources/MediaFolder.swift"
AGENT = "app/Sources/AgentServer+MediaFolder.swift"
IMPORT = "app/Sources/ProjectDocument+Import.swift"
# name: (the row it must turn red, the edits).
MUTANTS = {
    "hidden-kept": ("M1", [(FOLDER, "options: [.skipsHiddenFiles]", "options: []")]),
    "not-media-probed": ("D5", [(
        FOLDER, "if MediaImporter.isLUT(url) { return true }", "if true { return true }")]),
    "link-unresolved": ("M4", [(
        FOLDER, "try? url.resolvingSymlinksInPath().resourceValues(", "try? url.resourceValues(")]),
    "package-expanded": ("M10", [(
        FOLDER, "return values?.isDirectory == true && values?.isPackage != true",
        "return values?.isDirectory == true")]),
    "plain-order": ("M1", [(
        FOLDER,
        "a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending",
        "a.lastPathComponent < b.lastPathComponent")]),
    "matroska-unsniffed": ("M1", [(
        FOLDER, "return ContainerRewrap.isMatroska(url)", "return false")]),
    "listed-sent": ("M2", [(AGENT, "if listed.contains(descriptor.path) {", "if false {")]),
    "drop-unexpanded": ("D1", [(
        IMPORT, "let (files, unreadable) = MediaFolder.expand(urls)",
        "let (files, unreadable) = (urls, [MediaFolder.Unreadable]())")]),
    "unreadable-as-empty": ("M11", [(
        FOLDER, "throw Unreadable(folder: folder)",
        "return Listing(folder: folder, files: [], skipped: [])")]),
    "unreadable-unsaid": ("D6", [(
        IMPORT, "for folder in unreadable { present(folder) }",
        "for folder in unreadable { _ = folder }")]),
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


# ---- the fixtures -----------------------------------------------------------------------

def ffmpeg(*arguments):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *arguments], check=True, timeout=120)


def cube(path):
    with open(path, "w") as handle:
        handle.write("LUT_3D_SIZE 2\n")
        for b in (0, 1):
            for g in (0, 1):
                for r in (0, 1):
                    handle.write(f"{r} {g} {b}\n")


def fixtures():
    shoot = FILES / "Shoot"
    for folder in (shoot / "Sub", shoot / "Notes.rtfd", shoot / "Old.framejob",
                   FILES / "Shoot.mov", FILES / "Broken", FILES / "Docs"):
        folder.mkdir(parents=True)
    shutil.copy(MEDIA / "A.mov", shoot / "Clip 2.mov")
    shutil.copy(MEDIA / "B.mov", shoot / "Clip 10.mov")
    cube(shoot / "look.cube")
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x240:rate=1", "-frames:v", "1",
           str(shoot / "still.png"))
    ffmpeg("-i", str(MEDIA / "A.mov"), "-c", "copy", "-f", "matroska", str(shoot / "Take 3"))
    (shoot / "readme.txt").write_text("Notes about the shoot.\n")
    shutil.copy(MEDIA / "A.mov", shoot / ".h.mov")
    shutil.copy(MEDIA / "C.mov", shoot / "Sub" / "C.mov")
    (shoot / "Notes.rtfd" / "TXT.rtf").write_text("{\\rtf1\\ansi Notes.}\n")
    shutil.copy(MEDIA / "C.mov", shoot / "Old.framejob" / "C.mov")
    os.symlink(shoot, FILES / "ShootLink")
    shutil.copy(MEDIA / "A.mov", FILES / "Broken" / "A.mov")
    (FILES / "Broken" / "broken.mov").write_text("This is plain text with a movie's name.\n" * 12)
    (FILES / "Docs" / "readme.txt").write_text("Only words.\n")
    for name in ("A.mov", "B.mov", "C.mov"):
        shutil.copy(MEDIA / name, FILES / name)
    (FILES / "Locked").mkdir()
    shutil.copy(MEDIA / "A.mov", FILES / "Locked" / "A.mov")
    (FILES / "Locked").chmod(0o000)


def unlock():
    """`Locked` readable again, so the work folder can be cleared."""
    locked = FILES / "Locked"
    if locked.exists():
        locked.chmod(0o755)


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

    def __init__(self, client, name):
        self.client = client
        self.path = str(WORK / f"{name}.framejob")
        client.call_with("new_project", {"path": self.path})

    def op(self, tool, **arguments):
        return self.client.call_with(tool, dict(arguments, project=self.path))

    def media(self):
        return self.op("get_project")["project"]["media"]

    def close(self):
        self.op("close_project", discard=True)


def imported(project, name):
    """The answer, or the refusal's sentence."""
    try:
        return project.op("import_media", path=str(FILES / name))
    except mcp.ToolError as error:
        return str(error)


def shown_name(entry):
    """What an `imported` entry is named after: its original, else its own file."""
    return os.path.basename(entry.get("original") or entry.get("path", ""))


def names(answer):
    return [shown_name(e) for e in answer.get("imported", [])] if isinstance(answer, dict) else None


def skips(answer):
    if not isinstance(answer, dict):
        return None
    return {os.path.basename(s["path"]): s["reason"] for s in answer.get("skipped", [])}


# ---- the app rows -----------------------------------------------------------------------

def app_rows(client):
    project = Project(client, "folders")
    state = {"undone": False}

    def m1():
        before = len(project.media())
        answer = imported(project, "Shoot")
        got, skipped = names(answer), skips(answer)
        kinds = [e.get("kind") for e in answer.get("imported", [])] if got is not None else None
        take = answer["imported"][-1] if got else {}
        everything = (got or []) + list((skipped or {}).keys())
        after = len(project.media())
        ok = (got == FIVE and kinds == FIVE_KINDS and "original" in take
              and skipped is not None and skipped.get("readme.txt") == "not a media file"
              and skipped.get("Sub") == "a folder" and skipped.get("Notes.rtfd") == "a package"
              and ".h.mov" not in everything and "Old.framejob" not in (got or [])
              and "C.mov" not in (got or []) and after == before + 5)
        undone = project.op("undo") if got else {}
        state["undone"] = bool(undone)
        gone = len(project.media())
        ok = ok and undone.get("undone") == "Add 5 Media Files" and gone == before
        check("M1", ok, f"imported {got} {kinds}, skipped {skipped}, media {before} → {after}, "
                        f"undo {undone.get('undone')!r} → {gone}"
                        + ("" if got is not None else f"; answer {str(answer)[:200]}"))

    attempt(["M1"], m1)

    def m2():
        if state["undone"]:
            project.op("redo")
        else:
            project.op("import_media", path=str(FILES / "Shoot"))
        before = len(project.media())
        answer = imported(project, "Shoot")
        after = len(project.media())
        ok = (isinstance(answer, str) and "Nothing in Shoot was added. Skipped:" in answer
              and "already in the media list" in answer and after == before)
        check("M2", ok, f"media {before} → {after}, {str(answer)[:240]}")

    attempt(["M2"], m2)

    def m3():
        answer = imported(project, "Shoot.mov")
        want = "import_media: Nothing in Shoot.mov was added: it has no files directly inside it."
        check("M3", answer == want, str(answer)[:240])

    attempt(["M3"], m3)

    def m5():
        answer = imported(project, "Broken")
        skipped = skips(answer) or {}
        ok = (names(answer) == ["A.mov"]
              and skipped.get("broken.mov", "").startswith("Could not read broken.mov."))
        check("M5", ok, f"imported {names(answer)}, skipped {skipped}"
                        + ("" if isinstance(answer, dict) else f"; {str(answer)[:200]}"))

    attempt(["M5"], m5)
    project.close()
    # The controls on a project of their own: `Take 3`'s copy is in the first one's list by now.
    project = Project(client, "controls")

    def m6():
        answer = imported(project, "A.mov")
        ok = isinstance(answer, dict) and isinstance(answer.get("media"), int) \
            and "imported" not in answer
        check("M6", ok, f"media {answer.get('media') if isinstance(answer, dict) else answer!r}")

    attempt(["M6"], m6)

    def m7():
        tool = client.schemas()["import_media"]
        path = tool["inputSchema"]["properties"]["path"]["description"]
        check("M7", "folder" in tool["description"] and "folder" in path,
              f"{tool['description'][-160:]!r}, path {path!r}")

    attempt(["M7"], m7)

    def m9():
        answer = imported(project, "Shoot/Take 3")
        check("M9", isinstance(answer, dict) and answer.get("kind") == "video",
              str(answer.get("kind") if isinstance(answer, dict) else answer)[:200])

    attempt(["M9"], m9)

    def m10():
        answer = imported(project, "Shoot/Notes.rtfd")
        check("M10", isinstance(answer, str) and "Could not read Notes.rtfd." in answer,
              str(answer)[:240])

    attempt(["M10"], m10)
    project.close()

    def m4():
        fresh = Project(client, "link")
        try:
            answer = imported(fresh, "ShootLink")
            check("M4", names(answer) == FIVE, f"imported {names(answer)}"
                  + ("" if isinstance(answer, dict) else f"; {str(answer)[:200]}"))
        finally:
            fresh.close()

    attempt(["M4"], m4)

    def m11():
        fresh = Project(client, "locked")
        try:
            before = len(fresh.media())
            answer = imported(fresh, "Locked")
            after = len(fresh.media())
            want = "import_media: Nothing in Locked was added: it could not be read."
            check("M11", answer == want and after == before,
                  f"media {before} → {after}, {str(answer)[:240]}")
        finally:
            fresh.close()

    attempt(["M11"], m11)


def make_package(client, package):
    """One real empty project saved by the app under test, for the probe to copy per row."""
    client.call_with("new_project", {"path": str(package)})
    client.call_with("save_project", {"project": str(package)})
    client.call_with("close_project", {"project": str(package)})


# ---- the probe --------------------------------------------------------------------------

def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "docs-bugs-b5-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def probe_rows(binary, package):
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    done = subprocess.run([str(binary), str(FILES), str(package), "-RCFFmpegPath",
                           "/nonexistent/ffmpeg"], capture_output=True, text=True, env=env,
                          timeout=PROBE_BOUND, cwd=OUT, stdin=subprocess.DEVNULL)
    rows = {}
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            answer = json.loads(line)
            rows[answer["row"]] = answer
    if done.returncode != 0 or "PB" not in rows:
        raise RuntimeError(f"exit {done.returncode}, rows {sorted(rows)}: {done.stderr[-300:]}")
    if rows["policy"]["tools_found"]:
        raise RuntimeError("the probe found an ffmpeg, though it was told of none")

    def added(row):
        answer = rows[row]
        return [m["name"] for m in answer["media_after"][answer["media_before"]:]]

    def detail(row):
        answer = rows[row]
        return (f"added {added(row)}, alerts {answer['alerts']}, consent "
                f"{[m['message'] for m in answer['modals']]}, undo {answer['undo_name']!r}, "
                f"badge {answer['draggingEntered']}, performed {answer['performDragOperation']}")

    def quiet(row):
        answer = rows[row]
        return (not answer["alerts"] and not answer["modals"] and answer["draggingEntered"]
                and answer["performDragOperation"])

    check("D1", quiet("D1") and added("D1") == FIVE
          and rows["D1"]["undo_name"] == "Add 5 Media Files", detail("D1"))
    check("D2", quiet("D2") and added("D2") == FIVE + ["C.mov"], detail("D2"))
    shown = rows["D3"]["alerts"]
    check("D3", len(shown) == 1 and any("Could not read broken.mov." in t for t in shown[0])
          and added("D3") == ["A.mov"], detail("D3"))
    check("D4", quiet("D4") and added("D4") == ["B.mov"], detail("D4"))
    check("D5", quiet("D5") and added("D5") == [], detail("D5"))
    shown = rows["D6"]["alerts"]
    check("D6", len(shown) == 1
          and any("Nothing in Locked was added: it could not be read." in t for t in shown[0])
          and added("D6") == [] and rows["D6"]["performDragOperation"], detail("D6"))
    check("PB", rows["PB"]["unchanged"], f"unchanged {rows['PB']['unchanged']}")


# ---- the run ----------------------------------------------------------------------------

def run(binary, sources):
    package = WORK / "good.framejob"
    probe, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe, why = build_probe(sources)
        if why:
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
    launched = start(binary, "main")
    try:
        if launched.client is None:
            for row in sorted(selected - {"Z1"}):
                check(row, False, "the app did not listen")
            return
        client = launched.client
        if selected & set(APP_ROWS):
            app_rows(client)
        if probe is not None:
            attempt(sorted(set(PROBE_ROWS)), lambda: make_package(client, package))
    finally:
        launched.stop()
    if probe is not None and package.exists():
        attempt(sorted(set(PROBE_ROWS)), lambda: probe_rows(probe, package))


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made), None


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
        selected = {MUTANTS[args.mutant][0], "Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        unlock()
        tree_copy.remove_tree(str(WORK))
    for folder in (FILES, HOME, LOGS):
        folder.mkdir(parents=True)

    binary = Path(args.app) if args.app else None
    sources = Path(args.base_sources) if args.base_sources else ROOT / "app/Sources"
    if args.mutant:
        print(f"docs bugs b5 — the {args.mutant} MUTANT ({MUTANTS[args.mutant][0]} must FAIL)",
              flush=True)
        made, why = mutate(args.mutant)
        if why is None:
            sources = made / "app/Sources"
            app, why = tree_copy.build_app(made, BUILD_BOUND)
            binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"docs bugs b5 — a folder at an import door ({binary.name})", flush=True)

    try:
        fixtures()
    except (OSError, subprocess.SubprocessError) as error:
        for row in sorted(selected):
            check(row, False, f"the fixtures were not made: {error!r}")
    else:
        run(binary, sources)
        parity()
    finally:
        unlock()

    failed = [name for name in ROWS if name in results and not all(ok for ok, _ in results[name])]
    passed = [name for name in ROWS if name in results and name not in failed]
    print(f"\n{len(passed)}/{len(passed) + len(failed)} rows passed"
          + (f"; failed {failed}" if failed else ""), flush=True)
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        if row not in results:
            print(f"mutant {args.mutant}: the control could not be performed — its row was "
                  f"never scored")
            return 2
        caught = row in failed
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: {row} "
              f"{'failed' if caught else 'passed'}", flush=True)
        return 1 if caught else 0
    if args.expect_red:
        wrong = [r for r in failed if r in CONTROLS] + [r for r in passed if r not in CONTROLS]
        print("expected red, every row not marked (c) failing and every (c) passing: "
              + ("held" if not wrong else f"NOT held for {wrong}"), flush=True)
        return 1 if wrong else 0
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
