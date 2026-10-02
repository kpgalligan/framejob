#!/usr/bin/env python3
"""Issue batch B10 — `save_project` on a document the app has written
`cache/` into (#138), proved against the running app.

    python3 tools/proof/save_project_proof.py <dir>/agent.sock [--log PATH]

`--log` defaults to `<dir>/reelcut.log`. The app is a Release build at the
socket, FRESH for each run: every row writes its own package under
`work/save_project/` (`v2_snapshot.write_package`'s shape at `"version": 9`,
640×360 at 30 fps, one track, no clips, and NO `cache/`), and a package an
instance already has open would answer `already_open`.

The app creates `cache/` inside a package that has none when the document is
opened, which moves the package's own modification date behind NSDocument's
back. Before #138's fix a plain save was refused as "The file has been
changed by another application", edited or not, and a save to the
document's OWN path ran as Save As onto itself, which re-spelled the
document's path as the caller wrote it (P3). Measured on the baseline build
(B10's G2): P1, P3 and C1 fail; the issue's "locked" refusal did not
reproduce.

- **T1** — no `Reelcut: ` line in the log (the startup parity check).
- **P0** (control) — `cache/` exists after `open_project`.
- **P1** — an unedited `save_project {project}` answers `unsaved_changes:
  false`, and `project.json`'s `version` is the header's `RC_FORMAT_VERSION`.
- **P2** — `add_marker {at: 600000}`, then `save_project {project, path: <own
  path>}` answers; the file holds 1 marker and `get_project`'s `path` is
  unchanged, string for string.
- **P3** — P2 with `path` spelled `<dir>/./<name>.reelcut`.
- **C1** — an edited document's `save_project {project}` leaves 1 marker on
  disk (the issue's case 1 once an edit has dirtied the document; B10's
  design took it for a control, and the baseline fails it).
- **C2** (control) — C1's document saved to a new `copy.reelcut` holds 1
  marker there, and `get_project` names it.
- **C3** (control) — an unedited document saved to its own path (the old
  workaround `screens.py` used).
- **N1** — the conflict the fix must keep: `open_project`, `add_marker` (so
  the document is dirty and NSDocument does not revert it), then `cache/` is
  removed from OUTSIDE the app, which moves the package's date;
  `import_media` of `tools/proof/media/A.mov` recreates `cache/`
  (`generateCaches` → `cacheDirectory`).
  `save_project {project}` must be refused as "changed by another
  application", and `project.json` must hold no marker. `cacheDirectory`
  absorbs a date move only when the date it read before creating `cache/` is
  `fileModificationDate`; with that condition removed N1 fails.

A failed row's detail quotes the tool's error verbatim. Rows print as
`<ID> pass|fail — <detail>`, then `scores:`. Exit 0 iff no row failed.
"""

import argparse
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "capture_spike"))
import v2_snapshot  # noqa: E402
from e1_proof import format_version  # noqa: E402
from mcp import MCP, ToolError, log_beside, target  # noqa: E402

WORK = os.path.join(HERE, "work", "save_project")
CANVAS = {"width": 640, "height": 360, "fps": [30, 1], "background": [0.0, 0.0, 0.0, 1.0],
          "fit_new_clips": True}
MARKER_AT = 600_000
MEDIA = os.path.join(HERE, "media", "A.mov")
ROWS = ["T1", "P0", "P1", "P2", "P3", "C1", "C2", "C3", "N1"]
states = {}


def score(rid, ok, detail):
    states[rid] = "pass" if ok else "fail"
    print(f"{rid} {states[rid]} — {detail}", flush=True)


def package(name):
    """A fresh version-9 package with no `cache/`."""
    path = os.path.join(WORK, f"{name}.reelcut")
    v2_snapshot.write_package(path, dict(CANVAS), [])
    project_json = os.path.join(path, "project.json")
    with open(project_json) as f:
        project = json.load(f)
    project["version"] = 9
    with open(project_json, "w") as f:
        json.dump(project, f, indent=1)
    return path


def on_disk(path):
    with open(os.path.join(path, "project.json")) as f:
        return json.load(f)


def canonical(path):
    return os.path.realpath(path) if isinstance(path, str) else path


def add_marker(mcp, path):
    mcp.call_with("add_marker", {"project": path, "at": MARKER_AT})


def row_t1(log):
    try:
        with open(log, errors="replace") as f:
            lines = [line.rstrip() for line in f if "Reelcut: " in line]
    except OSError as error:
        score("T1", False, f"the log {log} could not be read: {error}")
        return
    score("T1", not lines, f"{len(lines)} `Reelcut: ` line(s) in {log}"
          + (f": {lines[:3]!r}" if lines else ""))


def row_p0(mcp):
    path = package("p0")
    mcp.call_with("open_project", {"path": path})
    cache = os.path.join(path, "cache")
    score("P0", os.path.isdir(cache), f"cache/ exists after open_project: {os.path.isdir(cache)}")


def row_p1(mcp):
    path = package("p1")
    mcp.call_with("open_project", {"path": path})
    try:
        answer = mcp.call_with("save_project", {"project": path})
    except ToolError as error:
        score("P1", False, f"unedited save_project {{project}} refused: {error}")
        return
    unsaved = answer.get("project", {}).get("unsaved_changes")
    version = on_disk(path).get("version")
    want = format_version()
    score("P1", unsaved is False and version == want,
          f"unsaved_changes {unsaved!r}; project.json version {version!r} (want {want})")


def edited_save_to_own_path(mcp, rid, name, spell):
    path = package(name)
    mcp.call_with("open_project", {"path": path})
    add_marker(mcp, path)
    before = mcp.call_with("get_project", {"project": path}).get("path")
    target = spell(path)
    try:
        answer = mcp.call_with("save_project", {"project": path, "path": target})
    except ToolError as error:
        score(rid, False, f"edited save_project {{project, path: {target}}} refused: {error}")
        return
    count = len(on_disk(path).get("markers", []))
    reported = mcp.call_with("get_project", {"project": target}).get("path")
    same = reported == before
    score(rid, count == 1 and same,
          f"saved {answer.get('saved')!r}; {count} marker(s) on disk (want 1); get_project "
          f"path {reported!r}, {before!r} before the save: unchanged {same}")


def row_c1_c2(mcp):
    path = package("c1")
    mcp.call_with("open_project", {"path": path})
    add_marker(mcp, path)
    try:
        mcp.call_with("save_project", {"project": path})
        count = len(on_disk(path).get("markers", []))
        score("C1", count == 1, f"edited save_project {{project}}: {count} marker(s) on disk "
              "(want 1)")
    except ToolError as error:
        score("C1", False, f"edited save_project {{project}} refused: {error}")
    copy = os.path.join(WORK, "copy.reelcut")
    shutil.rmtree(copy, ignore_errors=True)
    try:
        mcp.call_with("save_project", {"project": path, "path": copy})
    except ToolError as error:
        score("C2", False, f"save_project {{project, path: copy.reelcut}} refused: {error}")
        return
    count = len(on_disk(copy).get("markers", [])) if os.path.isdir(copy) else None
    reported = mcp.call_with("get_project", {"project": copy}).get("path")
    named = canonical(reported) == canonical(copy)
    score("C2", count == 1 and named,
          f"copy.reelcut holds {count} marker(s) (want 1); get_project path {reported!r} "
          f"names it: {named}")


def row_c3(mcp):
    path = package("c3")
    mcp.call_with("open_project", {"path": path})
    try:
        answer = mcp.call_with("save_project", {"project": path, "path": path})
    except ToolError as error:
        score("C3", False, f"unedited save_project {{project, path: <own>}} refused: {error}")
        return
    score("C3", True, f"unedited save to its own path answered: saved {answer.get('saved')!r}")


def row_n1(mcp):
    path = package("n1")
    mcp.call_with("open_project", {"path": path})
    add_marker(mcp, path)
    cache = os.path.join(path, "cache")
    shutil.rmtree(cache)
    mcp.call_with("import_media", {"project": path, "path": MEDIA})
    recreated = os.path.isdir(cache)
    try:
        answer = mcp.call_with("save_project", {"project": path})
    except ToolError as error:
        count = len(on_disk(path).get("markers", []))
        conflict = "changed by another application" in str(error)
        score("N1", conflict and count == 0 and recreated,
              f"refused: {error}; {count} marker(s) on disk (want 0); cache/ recreated by "
              f"import_media: {recreated}")
        return
    count = len(on_disk(path).get("markers", []))
    score("N1", False, f"saved {answer.get('saved')!r} over an outside change; {count} "
          f"marker(s) on disk (want 0, and a refusal); cache/ recreated: {recreated}")


def guarded(rids, row, *args):
    """A call that throws where a row expected an answer fails the rows it
    had not scored, naming the error, and the run goes on."""
    try:
        row(*args)
    except (RuntimeError, KeyError, TypeError, OSError, ValueError) as error:
        for name in rids.split(","):
            if name not in states:
                score(name, False, f"stopped by {type(error).__name__}: {error}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--log")
    args = parser.parse_args()
    socket_path = target([sys.argv[0], args.socket or ""])
    log = args.log or log_beside(socket_path)
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)

    mcp = MCP(socket_path, timeout=120)
    row_t1(log)
    guarded("P0", row_p0, mcp)
    guarded("P1", row_p1, mcp)
    guarded("P2", edited_save_to_own_path, mcp, "P2", "p2", lambda path: path)
    guarded("P3", edited_save_to_own_path, mcp, "P3", "p3",
            lambda path: os.path.join(os.path.dirname(path), ".", os.path.basename(path)))
    guarded("C1,C2", row_c1_c2, mcp)
    guarded("C3", row_c3, mcp)
    guarded("N1", row_n1, mcp)

    for rid in ROWS:
        if rid not in states:
            score(rid, False, "the row was never scored")
    passed = sum(1 for rid in ROWS if states[rid] == "pass")
    failed = len(ROWS) - passed
    print(f"scores: {passed} pass, {failed} fail of {len(ROWS)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
