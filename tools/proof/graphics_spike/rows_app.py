"""q7 of road map 10 §3: the package, with the UNCHANGED app.

The app at c874069 whitelists only `project.json`, `cache/` and `media/` in
`fileWrapper(ofType:)` (`ProjectDocument.swift:659-677`), so a `graphics/`
folder cannot survive a save today. `media/` is the STAND-IN: it goes
through the same lazy `directoryWrapper` a `graphics/` line would call, and
the app reads it at open only to re-anchor MISSING media by name, so a
stray `.js` there is inert. `graphics/` is run once as the CONTROL,
expected ABSENT after the save.

One owned instance on port 4843, by PID; nothing else is ever killed."""

import hashlib
import os
import re
import shutil
import subprocess
import sys
import time

import bounded
from rows_build import APP_BINARY, git_check
from rows_local import REPO, SPIKE, WORK

sys.path.insert(0, os.path.join(REPO, "tools", "proof"))
import mcp  # noqa: E402

PORT = 4843
LOG = os.path.join(WORK, "reelcut-4843.log")
Q7 = os.path.join(WORK, "q7")
CALL_BOUND = 60


class Instance:
    """One owned app, by PID, on its own port; the log is appended across
    launches, and each launch reads only what it appended."""

    def __init__(self, say):
        self.say = say
        self.child = None
        self.port = None

    def start(self):
        offset = os.path.getsize(LOG) if os.path.exists(LOG) else 0
        with open(LOG, "a") as log:
            self.child = subprocess.Popen(
                [APP_BINARY, "-ApplePersistenceIgnoreState", "YES", "-AgentServerEnabled", "YES"],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                env=bounded.child_env({"RC_AGENT_PORT": str(PORT)}), start_new_session=True)
        deadline = time.time() + 60
        while time.time() < deadline:
            time.sleep(0.5)
            with open(LOG) as handle:
                handle.seek(offset)
                found = re.search(r"listening on http://127\.0\.0\.1:(\d+)/mcp", handle.read())
            if found:
                self.port = int(found.group(1))
                self.say(f"  q7: instance PID {self.child.pid} on port {self.port}")
                return mcp.MCP(self.port, timeout=CALL_BOUND)
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


def complaints():
    try:
        with open(LOG) as handle:
            return [line.strip() for line in handle if "Reelcut: " in line]
    except OSError:
        return ["the log could not be read"]


def attempt(client, tool, arguments):
    """One MCP call; an error is an answer, and so is an expiry."""
    started = time.monotonic()
    try:
        reply = client.call_with(tool, arguments)
        return {"ok": True, "reply": reply,
                "seconds": round(time.monotonic() - started, 3)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error), "seconds": round(time.monotonic() - started, 3)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "expired": True, "error": f"{type(error).__name__}: {error}",
                "seconds": round(time.monotonic() - started, 3)}


def mv_in(folder, name, text):
    """Writes OUTSIDE the package, then `mv` — how another process lands a file."""
    os.makedirs(folder, exist_ok=True)
    outside = os.path.join(Q7, f"outside-{name}")
    with open(outside, "w") as handle:
        handle.write(text)
    return bounded.run(["mv", outside, os.path.join(folder, name)], 30)["rc"]


def present(package, folder, names):
    return {name: os.path.exists(os.path.join(package, folder, name)) for name in names}


def watch_row(say):
    """(c): the directory source on a plain folder, four kinds of write."""
    watcher = os.path.join(Q7, "q7_watch")
    built = bounded.run(["xcrun", "swiftc", "-O", "-target", "arm64-apple-macos26.0",
                         os.path.join(SPIKE, "q7_watch.swift"), "-o", watcher], 600)
    if built["rc"] != 0:
        return {"state": "failed", "stderr": built["stderr"][-2000:]}
    folder = os.path.join(Q7, "watched")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    child = bounded.Background([watcher, folder, "12"], 20)
    time.sleep(1.0)
    steps = []

    def step(name, action):
        steps.append((name, time.time()))
        action()
        time.sleep(1.5)

    target = os.path.join(folder, "x.js")
    step("mv_in_from_outside", lambda: mv_in(folder, "x.js", "export const a = 1;\n"))

    def editor_save():
        with open(target + ".tmp", "w") as handle:
            handle.write("export const a = 2;\n")
        os.rename(target + ".tmp", target)
    step("tmp_then_rename_over", editor_save)

    def in_place():
        with open(target, "w") as handle:  # O_TRUNC on the existing inode
            handle.write("export const a = 3;\n")
    step("in_place_truncate", in_place)
    step("rm", lambda: os.remove(target))
    answer = child.finish()
    events = []
    for stamp, line in answer["lines"]:
        found = re.search(r'"t":([0-9.]+),"mask":\[([^\]]*)\]', line)
        if found:
            events.append((float(found.group(1)), found.group(2).replace('"', "").split(",")))
    rows = {}
    for index, (name, begun) in enumerate(steps):
        until = steps[index + 1][1] if index + 1 < len(steps) else float("inf")
        rows[name] = [mask for t, mask in events if begun <= t < until]
    say(f"  q7(c): {rows}")
    return {"state": "run", "events_by_step": rows, "watcher_rc": answer["rc"],
            "expired": answer["expired"], "raw_lines": [l for _, l in answer["lines"]]}


def q7(say):
    check = git_check()
    measured = {"git_check": check}
    if not check["clean"]:
        return {"state": "failed", "reason": "tree not at c874069", "measured": measured}
    app = bounded.run(["make", "app"], 600, cwd=REPO)
    measured["make_app"] = {"rc": app["rc"], "seconds": app["seconds"], "expired": app["expired"]}
    if app["rc"] != 0 or not os.path.exists(APP_BINARY):
        return {"state": "failed", "reason": "make app failed", "measured": measured}
    with open(APP_BINARY, "rb") as handle:
        measured["binary_sha256"] = hashlib.sha256(handle.read()).hexdigest()
    shutil.rmtree(Q7, ignore_errors=True)
    os.makedirs(Q7)
    if os.path.exists(LOG):
        os.remove(LOG)
    p1, p2, p3 = (os.path.join(Q7, f"{n}.reelcut") for n in ("P1", "P2", "P3"))
    instance = Instance(say)
    try:
        client = instance.start()
        if client is None:
            return {"state": "failed", "reason": "the app never logged its port", "measured": measured}
        measured["created"] = {"P1": attempt(client, "new_project", {"path": p1}),
                               "P3": attempt(client, "new_project", {"path": p3})}
        instance.stop()
        mv_in(os.path.join(p1, "media"), "x.js", "export const x = 1;\n")
        mv_in(os.path.join(p3, "graphics"), "x.js", "export const x = 1;\n")
        client = instance.start()
        if client is None:
            return {"state": "failed", "reason": "the app never logged its port on relaunch",
                    "measured": measured}
        # (a): the file landed while the app was closed; open, edit, save.
        a = {"open": attempt(client, "open_project", {"path": p1}),
             "add_track": attempt(client, "add_track", {"project": p1}),
             "save": attempt(client, "save_project", {"project": p1})}
        a["present"] = present(p1, "media", ["x.js"])
        measured["a"] = a
        say(f"  q7(a): x.js after save {a['present']}")
        # (a2): into the EXISTING folder while open; edit, save.
        a2 = {"mv_rc": mv_in(os.path.join(p1, "media"), "y.js", "export const y = 1;\n"),
              "add_track": attempt(client, "add_track", {"project": p1}),
              "save": attempt(client, "save_project", {"project": p1})}
        a2["present"] = present(p1, "media", ["x.js", "y.js"])
        measured["a2"] = a2
        say(f"  q7(a2): {a2['present']}, save {a2['save']}")
        # (a-auto): an edit, then wait for an autosave in place.
        project_json = os.path.join(p1, "project.json")
        before = os.path.getmtime(project_json)
        auto = {"mv_rc": mv_in(os.path.join(p1, "media"), "z.js", "export const z = 1;\n"),
                "add_track": attempt(client, "add_track", {"project": p1})}
        started = time.monotonic()
        seen = None
        while time.monotonic() - started < 180:
            time.sleep(2)
            if os.path.getmtime(project_json) != before:
                seen = round(time.monotonic() - started, 1)
                break
        auto["autosave_seconds"] = seen
        auto["present"] = present(p1, "media", ["x.js", "y.js", "z.js"])
        if seen is None:
            auto["state"] = "not_run"
            auto["reason"] = "no autosave wrote project.json within 180 s of the edit"
        measured["a_auto"] = auto
        say(f"  q7(a-auto): autosave after {seen} s, {auto['present']}")
        # (ctrl): the CONTROL — `graphics/` is not in the whitelist.
        ctrl = {"open": attempt(client, "open_project", {"path": p3}),
                "add_track": attempt(client, "add_track", {"project": p3}),
                "save": attempt(client, "save_project", {"project": p3})}
        ctrl["present"] = present(p3, "graphics", ["x.js"])
        ctrl["folder_present"] = os.path.isdir(os.path.join(p3, "graphics"))
        measured["ctrl"] = ctrl
        say(f"  q7(ctrl, CONTROL): graphics/x.js after save {ctrl['present']}")
        # (b): the package's OWN mtime moves while open (mkdir inside it).
        b = {"create": attempt(client, "new_project", {"path": p2})}
        package_before = os.path.getmtime(p2)
        b["mv_rc"] = mv_in(os.path.join(p2, "media"), "w.js", "export const w = 1;\n")
        b["package_mtime_moved"] = os.path.getmtime(p2) != package_before
        b["add_track"] = attempt(client, "add_track", {"project": p2})
        b["save"] = attempt(client, "save_project", {"project": p2})
        b["present"] = present(p2, "media", ["w.js"])
        measured["b"] = b
        say(f"  q7(b): save {b['save']}")
    finally:
        instance.stop()
    measured["c"] = watch_row(say)
    measured["log_complaints"] = complaints()
    measured["log"] = os.path.relpath(LOG, REPO)
    return {"state": "run", "reason": None, "measured": measured}
