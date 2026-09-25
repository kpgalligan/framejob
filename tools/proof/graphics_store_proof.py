#!/usr/bin/env python3
"""The package's `graphics/` folder against the BUILT app: road map 10's G3a
(§10.6), §9a's G3 item 3 — G0's q7 package rows, run against `graphics/`
itself rather than `media/` as the stand-in.

One owned instance on its own port, launched and stopped by PID, with its log
at `tools/proof/work/graphics-store/reelcut-<port>.log`; nothing else is
ever killed. Every child runs under `graphics_spike/bounded.py`, and every
wait is a bounded poll.

S1  `grep "Reelcut: "` over every launch's log prints nothing;
S2  `new_project {path: P1}` leaves `P1/graphics` ABSENT (G-14);
S3  `mkdir P1/graphics` + `mv x.js` in from outside while open, >= 1 s of
    `get_project` polling, `add_track`, `save_project`: the save is NOT
    refused as "changed by another application" (the store saw the folder
    appear and re-read the package's date), and `x.js` is there, bytes equal;
S4  the instance stopped and relaunched, `open_project`, `add_track`,
    `save_project`: `x.js` present;
S5  `save_project {path: P1b}` (Save As): `P1b/graphics/x.js` present;
S6  `mv y.js` in, `add_track`, then an AUTOSAVE in place (project.json's
    mtime polled for at most 180 s): `x.js` and `y.js` present;
S7  `new_project` with no path makes exactly one new untitled root
    (`<NSTemporaryDirectory()>/Reelcut/*-graphics` — TMPDIR does not move that
    directory, measured), `mv u.js` into it, `save_project {path: P2}`:
    `P2/graphics/u.js` present;
S8  `new_project {path: P3}`, `add_track`, `save_project`: saved, and
    `P3/graphics` still ABSENT;
S9  the instance stopped, `mkdir P3/graphics` + `mv v.js` while closed,
    relaunched, `open_project`, `add_track`, `save_project`: saved, present.

    python3 tools/proof/graphics_store_proof.py [--port 4851] [--app PATH]

Made to fail by hand once (road map 10 §10.6): the whitelist line in
`fileWrapper(ofType:)` commented out and the app rebuilt, S3 reads ABSENT.
"""

import argparse
import glob
import os
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

WORK = ROOT / "tools/proof/work/graphics-store"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
CALL_BOUND = 150
ROWS = [f"S{n}" for n in range(1, 10)]
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


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
                env=bounded.child_env({"RC_AGENT_PORT": str(self.port),
                                       "TMPDIR": str(WORK / "tmp") + "/"}))
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            time.sleep(0.25)
            with open(self.log) as handle:
                handle.seek(offset)
                found = re.search(r"listening on http://127\.0\.0\.1:(\d+)/mcp", handle.read())
            if found:
                bound = int(found.group(1))
                print(f"  instance PID {self.child.pid} on port {bound}", flush=True)
                if bound != self.port:
                    print(f"  (asked for {self.port}; a taken port fell back)", flush=True)
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
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def mv_in(folder, name, text, make_folder=False):
    """Writes OUTSIDE the package, then `mkdir` / `mv` — how another process
    lands a file."""
    outside = WORK / f"outside-{name}"
    outside.write_text(text)
    if make_folder:
        bounded.run(["mkdir", str(folder)], 30)
    return bounded.run(["mv", str(outside), str(Path(folder) / name)], 30)["rc"]


def holds(package, names, texts):
    """Each module present in `<package>/graphics` with the bytes written."""
    out = {}
    for name in names:
        path = Path(package) / "graphics" / name
        out[name] = path.exists() and path.read_text() == texts[name]
    return out


def poll_project(client, package, seconds):
    """`get_project` over at least `seconds`, bounded; the calls made."""
    started = time.monotonic()
    calls = 0
    while time.monotonic() - started < seconds:
        attempt(client, "get_project", {"project": str(package)})
        calls += 1
        time.sleep(0.2)
    return calls


def temp_roots():
    """The untitled roots in the directory the APP's NSTemporaryDirectory()
    answers — `getconf DARWIN_USER_TEMP_DIR`, which TMPDIR does not move."""
    base = bounded.run(["getconf", "DARWIN_USER_TEMP_DIR"], 30)["stdout"].strip()
    return set(glob.glob(os.path.join(base, "Reelcut", "*-graphics")))


def complaints(log):
    try:
        return [line.strip() for line in open(log) if "Reelcut: " in line]
    except OSError:
        return ["the log could not be read"]


def run(app, port):
    log = WORK / f"reelcut-{port}.log"
    p1, p1b, p2, p3 = (WORK / f"{n}.reelcut" for n in ("P1", "P1b", "P2", "P3"))
    texts = {n: f"export function render() {{ return '<svg/>' }} // {n}\n"
             for n in ("x.js", "y.js", "u.js", "v.js")}
    instance = Instance(app, port, log)
    try:
        client = instance.start()
        if client is None:
            check("S2 the app launches", False, "the app never logged its port")
            return log
        made = attempt(client, "new_project", {"path": str(p1)})
        check("S2 new_project {path: P1} leaves P1/graphics ABSENT",
              made["ok"] and p1.exists() and not (p1 / "graphics").exists(), f"{made}")

        rc = mv_in(p1 / "graphics", "x.js", texts["x.js"], make_folder=True)
        polls = poll_project(client, p1, 1.2)
        track = attempt(client, "add_track", {"project": str(p1)})
        saved = attempt(client, "save_project", {"project": str(p1)})
        present = holds(p1, ["x.js"], texts)
        check("S3 graphics/ made from outside while open: the save is not refused, x.js kept",
              rc == 0 and track["ok"] and saved["ok"] and all(present.values()),
              f"mv rc {rc}, {polls} get_project polls, add_track {track['ok']}, "
              f"save {saved}, present {present}")

        instance.stop()
        client = instance.start()
        opened = attempt(client, "open_project", {"path": str(p1)}) if client else {"ok": False}
        track = attempt(client, "add_track", {"project": str(p1)}) if client else {"ok": False}
        saved = attempt(client, "save_project", {"project": str(p1)}) if client else {"ok": False}
        present = holds(p1, ["x.js"], texts)
        check("S4 relaunched, open_project, add_track, save_project: x.js present",
              opened["ok"] and track["ok"] and saved["ok"] and all(present.values()),
              f"open {opened['ok']}, save {saved}, present {present}")

        saved = attempt(client, "save_project", {"project": str(p1), "path": str(p1b)}) \
            if client else {"ok": False}
        present = holds(p1b, ["x.js"], texts)
        check("S5 save_project {path: P1b}: P1b/graphics/x.js present",
              saved["ok"] and all(present.values()), f"save {saved}, present {present}")

        rc = mv_in(p1b / "graphics", "y.js", texts["y.js"])
        project_json = p1b / "project.json"
        before = project_json.stat().st_mtime if project_json.exists() else None
        track = attempt(client, "add_track", {"project": str(p1b)}) if client else {"ok": False}
        started = time.monotonic()
        seen = None
        while time.monotonic() - started < 180:
            time.sleep(1)
            if project_json.exists() and project_json.stat().st_mtime != before:
                seen = round(time.monotonic() - started, 1)
                break
        present = holds(p1b, ["x.js", "y.js"], texts)
        print(f"  S6: the autosave wrote project.json {seen} s after the edit", flush=True)
        check("S6 mv y.js in, add_track, an autosave in place: x.js and y.js present",
              rc == 0 and track["ok"] and seen is not None and all(present.values()),
              f"autosave after {seen} s, present {present}")

        # A fresh instance, so the untitled draft is the only open document
        # and save_project's implicit target is it.
        instance.stop()
        client = instance.start()
        roots_before = temp_roots()
        made = attempt(client, "new_project", {}) if client else {"ok": False}
        new_roots = sorted(temp_roots() - roots_before)
        rc = mv_in(new_roots[0], "u.js", texts["u.js"]) if len(new_roots) == 1 else None
        saved = attempt(client, "save_project", {"path": str(p2)}) if client else {"ok": False}
        present = holds(p2, ["u.js"], texts)
        check("S7 new_project (untitled) makes ONE root; u.js moved into it is carried by the "
              "first save",
              made["ok"] and len(new_roots) == 1 and rc == 0 and saved["ok"]
              and all(present.values()),
              f"new roots {new_roots}, mv rc {rc}, save {saved}, present {present}")

        made = attempt(client, "new_project", {"path": str(p3)}) if client else {"ok": False}
        track = attempt(client, "add_track", {"project": str(p3)}) if client else {"ok": False}
        saved = attempt(client, "save_project", {"project": str(p3)}) if client else {"ok": False}
        check("S8 new_project {path: P3}, add_track, save_project: saved, P3/graphics ABSENT",
              made["ok"] and track["ok"] and saved["ok"] and not (p3 / "graphics").exists(),
              f"save {saved}, graphics {(p3 / 'graphics').exists()}")

        instance.stop()
        rc = mv_in(p3 / "graphics", "v.js", texts["v.js"], make_folder=True)
        client = instance.start()
        opened = attempt(client, "open_project", {"path": str(p3)}) if client else {"ok": False}
        track = attempt(client, "add_track", {"project": str(p3)}) if client else {"ok": False}
        saved = attempt(client, "save_project", {"project": str(p3)}) if client else {"ok": False}
        present = holds(p3, ["v.js"], texts)
        check("S9 graphics/ made while closed; relaunched, open, add_track, save: v.js present",
              rc == 0 and opened["ok"] and track["ok"] and saved["ok"] and all(present.values()),
              f"open {opened['ok']}, save {saved}, present {present}")
    finally:
        instance.stop()
    return log


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4851)
    parser.add_argument("--app", type=Path, default=APP)
    args = parser.parse_args()
    print("G3a — the package's graphics/ folder against the built app (proof)", flush=True)
    if not args.app.exists():
        print(f"  FAIL the app is not built: {args.app}")
        print(f"0/{len(ROWS)}")
        return 1
    shutil.rmtree(WORK, ignore_errors=True)
    (WORK / "tmp").mkdir(parents=True)
    log = run(args.app, args.port)
    found = complaints(log)
    check("S1 grep \"Reelcut: \" over every launch's log prints nothing", found == [],
          f"{found[:5]}")
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
