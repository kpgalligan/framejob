#!/usr/bin/env python3
"""Saved-package admission and same-process MCP survival for D7-1.

Owns its Reelcut process. A nonzero exit scores a startup, timeout, crash,
parity or assertion failure; no caller's app process is touched.
"""

import argparse
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(__file__))
from mcp import MCP, ToolError  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
M = 9_000_000_000_000_000
FRAME = 20_000
PARITY = "Reelcut: "


def package(where, name, document):
    path = os.path.join(where, name + ".reelcut")
    os.mkdir(path)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as stream:
        json.dump(document, stream)
    return path


def base():
    return {
        "version": 8,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
        "media": [], "tracks": [{"id": 1, "name": "T"}],
        "clips": [
            {"id": 2, "track": 1, "start": 0, "duration": 2 * FRAME,
             "source": {"kind": "text"}, "video": {},
             "text": {"content": "Survived"}},
            {"id": 3, "track": 1, "start": M - 4 * FRAME,
             "duration": FRAME, "source": {"kind": "shape"},
             "video": {}, "shape": {}},
        ],
        "markers": [], "nests": [], "next_id": 10,
    }


def project(mcp):
    answer = mcp.call_with("get_project", {})
    return answer["project"]


def parity(log_path):
    with open(log_path, encoding="utf-8", errors="replace") as stream:
        lines = stream.read().splitlines()
    complaints = [line for line in lines if PARITY in line]
    if complaints:
        raise AssertionError("startup parity complained: " + " | ".join(complaints))
    return lines


def run(mcp, where):
    invalid = []
    for name, duration in [("int64max", 2**63 - 1), ("pow62", 2**62),
                           ("onee18", 10**18)]:
        p = base()
        p["clips"][0]["duration"] = duration
        invalid.append((name, p, "clip 2.duration", str(duration)))
    p = base()
    p["clips"][1]["start"] = M - FRAME
    p["clips"][1]["duration"] = 2 * FRAME
    invalid.append(("endpoint", p, "clip 3.end", str(M + FRAME)))
    p = base()
    p["nests"] = [{"id": 11, "tracks": [{"id": 12}],
                   "clips": [{"id": 13, "track": 12, "start": 0,
                              "duration": 2**62, "source": {"kind": "text"}}]}]
    p["next_id"] = 14
    invalid.append(("nested", p, "clip 13 in nest 11.duration", str(2**62)))

    for name, document, path, number in invalid:
        original = package(where, name, document)
        with open(os.path.join(original, "project.json"), "rb") as stream:
            before = stream.read()
        try:
            mcp.call("open_project", path=original)
            raise AssertionError(name + " opened unexpectedly")
        except ToolError as error:
            message = str(error)
            assert path in message and number in message, (name, message)
        with open(os.path.join(original, "project.json"), "rb") as stream:
            assert stream.read() == before, name + " was rewritten"
        # An invalid package must not poison the process or the next open.
        control = package(where, "after-" + name, base())
        mcp.call("open_project", path=control)
        assert project(mcp)["clips"][0]["text"]["content"] == "Survived"
        print("ok", name, "named refusal and subsequent valid open")

    valid = base()
    valid["media"] = [{"id": 20, "path": os.path.join(ROOT, "tools", "proof", "media", "A.mov"),
                       "kind": "video", "duration": M, "width": 640, "height": 360,
                       "fps": [30, 1], "has_video": True}]
    valid["clips"].append({"id": 21, "track": 1, "start": M - 2 * FRAME,
                            "duration": FRAME,
                            "source": {"kind": "media", "media": 20, "in": 0},
                            "video": {}})
    valid["nests"] = [{"id": 22, "tracks": [{"id": 23}],
                       "clips": [{"id": 24, "track": 23, "start": 0,
                                  "duration": FRAME,
                                  "source": {"kind": "text"},
                                  "video": {}, "text": {"content": "Nested"}}]}]
    valid["clips"].append({"id": 25, "track": 1, "start": M - FRAME,
                            "duration": FRAME, "source": {"kind": "nest", "project": 22},
                            "video": {}})
    valid["next_id"] = 26
    saved = package(where, "admitted", valid)
    mcp.call("open_project", path=saved)
    assert len(project(mcp)["clips"]) == 4
    for tick in [0, M - 2 * FRAME, M - FRAME]:
        rendered = mcp.call("render_frame", t=tick)
        match = re.search(r"Written to (\S+\.png)\.", rendered)
        assert match and os.path.isfile(match.group(1)), (tick, rendered)
    print("ok admitted media/generated/nested readback and render")

    before = copy.deepcopy(project(mcp))
    mcp.call("move_clip", clips=[3], delta=FRAME)
    after = copy.deepcopy(project(mcp))
    assert after["clips"][1]["start"] == M - 3 * FRAME
    try:
        mcp.call("move_clip", clips=[3], delta=3 * FRAME)
        raise AssertionError("boundary-crossing move applied")
    except ToolError as error:
        assert "clip 3.end" in str(error) and str(M + FRAME) in str(error), error
    assert project(mcp) == after, "rejected edit changed the document"
    assert mcp.call_with("undo", {})["undone"]
    assert project(mcp) == before, "rejected edit added an undo step"
    mcp.call_with("redo", {})
    assert project(mcp) == after
    saved_as = os.path.join(where, "saved-admitted.reelcut")
    mcp.call_with("save_project", {"path": saved_as})
    with open(os.path.join(saved_as, "project.json"), encoding="utf-8") as stream:
        persisted = json.load(stream)
    assert persisted["clips"][1]["start"] == M - 3 * FRAME
    copy_path = os.path.join(where, "reopened.reelcut")
    shutil.copytree(saved_as, copy_path)
    mcp.call("open_project", path=copy_path)
    assert project(mcp)["clips"][1]["start"] == M - 3 * FRAME
    print("ok valid edit, rejected edit, undo/redo, save and reopen")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=5350)
    parser.add_argument("--app", default=os.path.join(ROOT, "build", "Build", "Products",
                                                     "Release", "Reelcut.app"))
    args = parser.parse_args()
    binary = os.path.join(args.app, "Contents", "MacOS", "Reelcut")
    if not os.path.isfile(binary):
        raise AssertionError("matching app binary is missing: " + binary)
    with tempfile.TemporaryDirectory(prefix="reelcut-extreme-") as work:
        log_path = os.path.join(work, "app.log")
        with open(log_path, "w", encoding="utf-8") as log:
            env = os.environ.copy()
            env["RC_AGENT_PORT"] = str(args.port)
            env["RC_ASSEMBLYAI_KEY"] = "proof-key"
            app = subprocess.Popen([binary, "-ApplePersistenceIgnoreState", "YES",
                                    "-AgentServerEnabled", "YES"],
                                   stdout=log, stderr=subprocess.STDOUT, env=env)
            try:
                bound = None
                until = time.monotonic() + 20
                while time.monotonic() < until and app.poll() is None:
                    lines = parity(log_path)
                    for line in lines:
                        found = re.search(r"agent server listening on http://127\.0\.0\.1:(\d+)/mcp", line)
                        if found:
                            bound = int(found.group(1))
                            break
                    if bound is not None:
                        break
                    time.sleep(0.1)
                assert bound is not None, "app did not bind an MCP port"
                assert bound == args.port, f"requested port {args.port}, bound {bound}"
                mcp = MCP(bound, timeout=20)
                run(mcp, work)
                parity(log_path)
                assert app.poll() is None, "app exited during proof"
                print("extreme time proof passed; no parity complaints")
            finally:
                if app.poll() is None:
                    app.terminate()
                    try:
                        app.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        app.kill()
                        app.wait(timeout=5)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # every proof failure is a nonzero score
        print("FAIL extreme time proof:", error, file=sys.stderr)
        sys.exit(1)
