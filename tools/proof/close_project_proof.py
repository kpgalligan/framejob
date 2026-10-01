#!/usr/bin/env python3
"""Issue batch B44 — `close_project` and the held-path refusals (#40, spec
§11 #40), and `export_captions`' caption name rule (#43, spec §11 #43),
proved against the running app.

    python3 tools/proof/close_project_proof.py <port> [--log PATH]

`--log` defaults to `/tmp/reelcut-<port>.log`. The app is a Release build
(the rows use the dev tools `snapshot_ui`, `perform_menu_item` and
`cancel_sheet`) on `<port>`, FRESH for each run: every row writes its own
package under `work/close_project/`, wiped at the start.

- **T1** — no `Reelcut: ` line in the log (the startup parity check).
- **K1** — `close_project` declares exactly `{discard, project}`: `discard`
  a boolean, nothing required.
- **C1** — 60 cycles of `new_project {path: c<NN>}` → `close_project
  {project: path}`, each answering that path (compared canonically) and
  `discarded_changes: false` — well past the ~40 open documents an instance
  deadlocks at when nothing closes one.
- **C2** — every `get_project {project: c<NN>}` is refused "No open project
  is at"; `snapshot_ui {}` lists no editor window for any of them; and
  `open_project c00` answers without `already_open` (then is closed).
- **C3** — the process's thread count after C1 is under its count before C1
  plus 64; both printed.
- **D1** — `new_project`, then the autosave guard; `close_project` is refused
  with the exact unsaved-changes sentence, and `get_project` still answers.
- **D2** — the autosave guard again on a second project, then
  `close_project {discard: true}` answers `discarded_changes: true`;
  `get_project` on it is refused, and its `project.json` on disk holds no
  marker at the last attempt's `at`.
- **H1** — a text clip on its own track, `save_project`, then
  `perform_menu_item ["File", "Export…"]` puts up a sheet and `close_project`
  is refused with the exact sheet sentence; after `cancel_sheet`,
  `close_project` answers.
- **S1** — with A and B open, `save_project {project: B, path: A}` and the
  same with `path: <dir>/./<A stem>` are both refused with the exact
  held-path sentence; B's path and A's `project.json` bytes are unchanged.
- **S2** — `new_project {path: A}` is refused with the exact sentence, and
  `snapshot_ui {}`'s editor-window count is unchanged.
- **S3** (control) — `save_project {project: A, path: A}` answers `saved`. It
  runs before S1, so a build that lets S1 write B over A cannot take it.
- **E1** — with a text clip on its own track, `export_captions {path:
  <work>/chart.png}` answers a `path` ending `/chart.png.srt`; that file
  exists and `chart.srt` does not.

**The autosave guard (D1, D2).** `ProjectDocument` autosaves in place, which
clears `unsaved_changes` some seconds after an edit. Each attempt adds a
marker at a fresh `at` (600000, 1200000, 1800000), reads `get_project`, and
calls `close_project` at once only if it answers `unsaved_changes: true`; on
`false` it prints `<ID> retry <n>: autosave landed` and tries again. Three
attempts at most; all three autosaved scores the row a failure.

**A wedged instance.** Every call waits at most 60 s. After the first call
that times out the script makes no more calls, and every row left scores
"fail — instance wedged at <row>".

Rows print as `<ID> pass|fail — <detail>`, then `scores:`. Exit 0 iff no row
failed.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mcp import MCP, ToolError  # noqa: E402

WORK = os.path.join(HERE, "work", "close_project")
ROWS = ["T1", "K1", "C1", "C2", "C3", "D1", "D2", "H1", "S1", "S2", "S3", "E1"]
CYCLES = 60
THREAD_SLACK = 64
GUARD_ATS = [600_000, 1_200_000, 1_800_000]
states = {}


class Wedged(Exception):
    pass


class App:
    """The MCP client with the wedge rule: after the first call that times
    out, every later call raises `Wedged` without touching the instance."""

    def __init__(self, port):
        self.mcp = MCP(port, timeout=60)
        self.row = None
        self.wedged_at = None

    def call(self, tool, arguments):
        if self.wedged_at:
            raise Wedged(self.wedged_at)
        try:
            return self.mcp.call_with(tool, arguments)
        except ToolError:
            raise
        except (socket.timeout, TimeoutError, urllib.error.URLError, OSError) as error:
            self.wedged_at = f"{self.row} ({tool}: {type(error).__name__}: {error})"
            raise Wedged(self.wedged_at)

    def refusal(self, tool, arguments):
        """The tool's error text with the `<tool>: ` prefix `mcp.py` adds
        taken off, or None when the call answered."""
        try:
            self.call(tool, arguments)
        except ToolError as error:
            text = str(error)
            prefix = f"{tool}: "
            return text[len(prefix):] if text.startswith(prefix) else text
        return None


def score(rid, ok, detail):
    states[rid] = "pass" if ok else "fail"
    print(f"{rid} {states[rid]} — {detail}", flush=True)


def canonical(path):
    return os.path.realpath(path) if isinstance(path, str) else path


def package(name):
    return os.path.join(WORK, f"{name}.reelcut")


def listening_pid(port):
    """The pid listening on `port` (`recording_proof.py`'s, copied); `lsof`
    is a READ."""
    try:
        out = subprocess.run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
                             capture_output=True, text=True, timeout=20).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None
    return int(out[0]) if out else None


def thread_count(pid):
    try:
        out = subprocess.run(["ps", "-M", "-p", str(pid)], capture_output=True, text=True,
                             timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    lines = [line for line in out.splitlines() if line.strip()]
    return len(lines) - 1 if lines else None


def editor_windows(app):
    listing = app.call("snapshot_ui", {})
    return [w for w in listing.get("windows", []) if w.get("kind") == "editor"]


def held_sentence(holder, path, tool):
    return (f"Another open project ({holder}) is at {path}, so {tool} did not write there: "
            "close_project closes it, or pass another path.")


def unsaved_sentence(name):
    return (f"{name} has unsaved changes, so close_project left it open: save_project saves "
            "them, or close_project with discard: true closes it and loses them.")


def sheet_sentence(name):
    return (f"{name} has a sheet open on its window, so close_project left it open: finish "
            "or cancel the sheet first.")


def text_clip_project(app, path):
    """A new project at `path` with one text clip on a track of its own."""
    app.call("new_project", {"path": path})
    track = app.call("get_project", {"project": path})["project"]["next_id"]
    app.call("add_track", {"project": path, "name": "Captions"})
    app.call("add_text_clip", {"project": path, "track": track, "at": 0, "duration": 1_200_000,
                               "text": {"content": "Hello"}})


def row_t1(log):
    try:
        with open(log, errors="replace") as f:
            lines = [line.rstrip() for line in f if "Reelcut: " in line]
    except OSError as error:
        score("T1", False, f"the log {log} could not be read: {error}")
        return
    score("T1", not lines, f"{len(lines)} `Reelcut: ` line(s) in {log}"
          + (f": {lines[:3]!r}" if lines else ""))


def row_k1(app):
    app.row = "K1"
    if app.wedged_at:
        raise Wedged(app.wedged_at)
    tool = app.mcp.schemas().get("close_project")
    if tool is None:
        score("K1", False, "the catalog has no close_project")
        return
    schema = tool.get("inputSchema", {})
    properties = schema.get("properties", {})
    kind = properties.get("discard", {}).get("type")
    required = schema.get("required", [])
    score("K1", set(properties) == {"discard", "project"} and kind == "boolean"
          and required == [],
          f"properties {sorted(properties)}; discard {kind!r}; required {required}")


def row_c1_c3(app, pid):
    app.row = "C1"
    before = thread_count(pid) if pid else None
    paths = [package(f"c{n:02d}") for n in range(CYCLES)]
    bad = []
    for path in paths:
        app.call("new_project", {"path": path})
        answer = app.call("close_project", {"project": path})
        if canonical(answer.get("path")) != canonical(path) \
                or answer.get("discarded_changes") is not False or answer.get("ok") is not True:
            bad.append((os.path.basename(path), answer))
    score("C1", not bad, f"{CYCLES} new_project → close_project cycles; {len(bad)} answered "
          f"otherwise{': ' + repr(bad[:2]) if bad else ''}")
    after = thread_count(pid) if pid else None
    ok = before is not None and after is not None and after < before + THREAD_SLACK
    score("C3", ok, f"threads before C1 {before}, after {after} (want < before + "
          f"{THREAD_SLACK}; pid {pid})")
    return paths


def row_c2(app, paths):
    app.row = "C2"
    answered = []
    for path in paths:
        text = app.refusal("get_project", {"project": path})
        if text is None or not text.startswith("No open project is at"):
            answered.append((os.path.basename(path), text))
    wanted = {canonical(p) for p in paths}
    shown = [w.get("project") for w in editor_windows(app)
             if canonical(w.get("project")) in wanted]
    reopened = app.call("open_project", {"path": paths[0]})
    again = "already_open" in reopened
    app.call("close_project", {"project": paths[0]})
    score("C2", not answered and not shown and not again,
          f"get_project answered for {len(answered)} closed path(s)"
          f"{': ' + repr(answered[:2]) if answered else ''}; editor windows still showing "
          f"{len(shown)}; open_project c00 already_open {again}")


def autosave_guard(app, rid, path):
    """Adds a marker at a fresh `at` until `get_project` reports the edit
    unsaved; answers (the name, the `at`, the attempt) or None."""
    for attempt, at in enumerate(GUARD_ATS, 1):
        app.call("add_marker", {"project": path, "at": at})
        state = app.call("get_project", {"project": path})
        if state.get("unsaved_changes") is True:
            return state.get("name"), at, attempt
        print(f"{rid} retry {attempt}: autosave landed", flush=True)
    return None


def row_d1(app):
    app.row = "D1"
    path = package("d1")
    app.call("new_project", {"path": path})
    guarded_state = autosave_guard(app, "D1", path)
    if guarded_state is None:
        score("D1", False, f"all {len(GUARD_ATS)} attempts autosaved before the close")
        return
    name, at, attempt = guarded_state
    text = app.refusal("close_project", {"project": path})
    want = unsaved_sentence(name)
    still = app.refusal("get_project", {"project": path}) is None
    score("D1", text == want and still,
          f"attempt {attempt} (marker at {at}): close_project "
          f"{'answered' if text is None else 'refused ' + repr(text)}; exact sentence "
          f"{text == want}; get_project still answers {still}")


def row_d2(app):
    app.row = "D2"
    path = package("d2")
    app.call("new_project", {"path": path})
    guarded_state = autosave_guard(app, "D2", path)
    if guarded_state is None:
        score("D2", False, f"all {len(GUARD_ATS)} attempts autosaved before the close")
        return
    _, at, attempt = guarded_state
    try:
        answer = app.call("close_project", {"project": path, "discard": True})
    except ToolError as error:
        score("D2", False, f"attempt {attempt}: close_project {{discard: true}} refused: "
              f"{error}")
        return
    gone = app.refusal("get_project", {"project": path})
    with open(os.path.join(path, "project.json")) as f:
        markers = [m.get("at") for m in json.load(f).get("markers", [])]
    ok = answer.get("discarded_changes") is True and gone is not None \
        and gone.startswith("No open project is at") and at not in markers
    score("D2", ok, f"attempt {attempt} (marker at {at}): discarded_changes "
          f"{answer.get('discarded_changes')!r}; get_project refused {gone is not None}; "
          f"markers on disk {markers} (want none at {at})")


def row_h1(app):
    app.row = "H1"
    path = package("h1")
    text_clip_project(app, path)
    app.call("save_project", {"project": path})
    name = app.call("get_project", {"project": path}).get("name")
    menu = app.call("perform_menu_item", {"project": path, "path": ["File", "Export…"]})
    sheet = menu.get("sheet_at_return") if isinstance(menu, dict) else None
    text = app.refusal("close_project", {"project": path})
    want = sheet_sentence(name)
    if text is None:
        score("H1", False, f"sheet at return {sheet!r}; close_project ANSWERED with the "
              "sheet up")
        return
    app.call("cancel_sheet", {"project": path})
    after = app.refusal("close_project", {"project": path})
    score("H1", text == want and after is None,
          f"sheet at return {sheet!r}; refused {text!r}; exact sentence {text == want}; after "
          f"cancel_sheet close_project {'answered' if after is None else 'refused ' + after}")


def row_s_setup(app):
    """A and B open; answers (A, B, A's name). S3 runs first, so a build that
    lets S1 write B over A cannot take the control with it."""
    app.row = "S3"
    a, b = package("a"), package("b")
    app.call("new_project", {"path": a})
    app.call("new_project", {"path": b})
    return a, b, app.call("get_project", {"project": a}).get("name")


def row_s3(app, a):
    app.row = "S3"
    try:
        answer = app.call("save_project", {"project": a, "path": a})
    except ToolError as error:
        score("S3", False, f"save_project {{project: A, path: A}} refused: {error}")
        return
    score("S3", canonical(answer.get("saved")) == canonical(a),
          f"save_project {{project: A, path: A}} saved {answer.get('saved')!r}")


def row_s1(app, a, b, holder):
    app.row = "S1"
    b_before = app.call("get_project", {"project": b}).get("path")
    with open(os.path.join(a, "project.json"), "rb") as f:
        a_bytes = f.read()
    spelled = os.path.join(os.path.dirname(a), ".", "a")
    first = app.refusal("save_project", {"project": b, "path": a})
    second = app.refusal("save_project", {"project": b, "path": spelled})
    want_first = held_sentence(holder, a, "save_project")
    want_second = held_sentence(holder, spelled + ".reelcut", "save_project")
    gone = app.refusal("get_project", {"project": b})
    b_after = app.call("get_project", {"project": b}).get("path") if gone is None else gone
    with open(os.path.join(a, "project.json"), "rb") as f:
        a_same = f.read() == a_bytes
    score("S1", first == want_first and second == want_second and b_after == b_before
          and a_same,
          f"path A: {'answered' if first is None else repr(first)} (exact "
          f"{first == want_first}); path {spelled}: "
          f"{'answered' if second is None else repr(second)} (exact {second == want_second}); "
          f"B's path {b_before!r} → {b_after!r}; A's project.json unchanged {a_same}")


def row_s2(app, a, holder):
    app.row = "S2"
    count = len(editor_windows(app))
    refused = app.refusal("new_project", {"path": a})
    want = held_sentence(holder, a, "new_project")
    after = len(editor_windows(app))
    score("S2", refused == want and after == count,
          f"new_project {{path: A}}: {'answered' if refused is None else repr(refused)} "
          f"(exact {refused == want}); editor windows {count} → {after}")


def row_e1(app):
    app.row = "E1"
    path = package("e1")
    text_clip_project(app, path)
    target = os.path.join(WORK, "chart.png")
    answer = app.call("export_captions", {"project": path, "path": target})
    written = answer.get("path", "")
    kept = os.path.join(WORK, "chart.png.srt")
    stripped = os.path.join(WORK, "chart.srt")
    ok = written.endswith("/chart.png.srt") and os.path.isfile(kept) \
        and not os.path.exists(stripped)
    score("E1", ok, f"path {written!r}; chart.png.srt exists {os.path.isfile(kept)}; "
          f"chart.srt exists {os.path.exists(stripped)}")


def guarded(app, rids, row, *args):
    """A call that throws where a row expected an answer fails the rows it
    had not scored, naming the error, and the run goes on — except a wedge,
    after which no row makes another call."""
    try:
        return row(*args)
    except Wedged as wedge:
        for name in rids.split(","):
            if name not in states:
                score(name, False, f"instance wedged at {wedge}")
    except (ToolError, RuntimeError, KeyError, TypeError, OSError, ValueError,
            AttributeError) as error:
        for name in rids.split(","):
            if name not in states:
                score(name, False, f"stopped by {type(error).__name__}: {error}")
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port", type=int)
    parser.add_argument("--log")
    args = parser.parse_args()
    log = args.log or f"/tmp/reelcut-{args.port}.log"
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)

    row_t1(log)
    app = App(args.port)
    pid = listening_pid(args.port)
    guarded(app, "K1", row_k1, app)
    paths = guarded(app, "C1,C3", row_c1_c3, app, pid)
    if paths:
        guarded(app, "C2", row_c2, app, paths)
    guarded(app, "D1", row_d1, app)
    guarded(app, "D2", row_d2, app)
    guarded(app, "H1", row_h1, app)
    pair = guarded(app, "S3,S1,S2", row_s_setup, app)
    if pair:
        a, b, holder = pair
        guarded(app, "S3", row_s3, app, a)
        guarded(app, "S1", row_s1, app, a, b, holder)
        guarded(app, "S2", row_s2, app, a, holder)
    guarded(app, "E1", row_e1, app)

    for rid in ROWS:
        if rid not in states:
            reason = (f"instance wedged at {app.wedged_at}" if app.wedged_at
                      else "the row was never scored")
            score(rid, False, reason)
    passed = sum(1 for rid in ROWS if states[rid] == "pass")
    failed = len(ROWS) - passed
    print(f"scores: {passed} pass, {failed} fail of {len(ROWS)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
