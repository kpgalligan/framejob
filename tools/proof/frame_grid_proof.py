#!/usr/bin/env python3
"""Owned-app stored frame-grid proof for canvas, paste, attributes and unnest."""

import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from mcp import MCP, remove_scratch, scratch_socket, wait_listening  # noqa: E402
import proof_app  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def text_clip(clip_id, track, start, duration):
    return {"id": clip_id, "track": track, "start": start, "duration": duration,
            "source": {"kind": "text"},
            "video": {"motion": {"in": {"kind": "fade", "duration": 10_000},
                                 "out": {"kind": "fade", "duration": 12_500}}},
            "text": {"content": "Keep", "animation": {
                "kind": "typewriter", "in": 20_000, "out": 60_000}},
            "audio": {"fade_in": 10_001}}


def original():
    return {"version": 8,
            "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
            "media": [], "tracks": [{"id": 1, "name": "T"}],
            "clips": [text_clip(2, 1, 20_000, 60_000),
                      {"id": 4, "track": 1, "start": 200_000, "duration": 100_000,
                       "source": {"kind": "nest", "project": 10}, "video": {}}],
            "nests": [{"id": 10, "width": 640, "height": 360,
                       "tracks": [{"id": 11, "name": "Inside"}],
                       "clips": [text_clip(12, 11, 20_000, 60_000)]}],
            "markers": [{"id": 20, "time": 12_500, "name": "First"}],
            "next_id": 50}


def package(where, name, value):
    path = os.path.join(where, name + ".framejob")
    os.mkdir(path)
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as stream:
        json.dump(value, stream)
    return path


def project(mcp):
    return mcp.call_with("get_project", {})["project"]


def check_parity(log_path):
    with open(log_path, encoding="utf-8", errors="replace") as stream:
        lines = stream.read().splitlines()
    complaints = [line for line in lines if "Frame Job: " in line]
    assert not complaints, "startup parity complained: " + " | ".join(complaints)
    return lines


def changed_with_undo(mcp, name, arguments, expected):
    before = copy.deepcopy(project(mcp))
    mcp.call_with(name, arguments)
    after = copy.deepcopy(project(mcp))
    assert after != before, name + " was an identity"
    expected(after)
    assert mcp.call_with("undo", {})["undone"], name + " did not make an undo step"
    assert project(mcp) == before, name + " undo did not restore the whole project"
    mcp.call_with("redo", {})
    assert project(mcp) == after, name + " redo did not restore the whole project"
    print("ok", name, "exact timing and complete undo/redo")


def run(mcp, where):
    source = package(where, "source", original())
    mcp.call("open_project", path=source)

    def canvas(v):
        assert v["canvas"]["fps"] == [24, 1]
        top, inner = v["clips"][0], v["nests"][0]["clips"][0]
        for c in (top, inner):
            assert (c["start"], c["duration"]) == (25_000, 50_000), c
            assert c["video"]["motion"]["in"]["duration"] == 0, c
            assert c["video"]["motion"]["out"]["duration"] == 25_000
            assert c["text"]["animation"]["in"] == 25_000
            assert c["text"]["animation"]["out"] == 50_000
            assert c["audio"]["fade_in"] == 10_001
        assert v["markers"][0]["time"] == 25_000

    changed_with_undo(mcp, "set_canvas", {"fps": [24, 1]}, canvas)

    payload = {"clips": [{"id": 70, "track": 0, "start": 0,
                           "duration": 60_000,
                           "source": {"kind": "nest", "project": 72}, "video": {}}],
               "nests": [{"id": 72, "width": 640, "height": 360,
                          "tracks": [{"id": 73, "name": "Imported"}],
                          "clips": [text_clip(74, 73, 20_000, 60_000)]}]}

    def pasted(v):
        clip = next(c for c in v["clips"] if c["id"] not in (2, 4))
        assert (clip["start"], clip["duration"]) == (400_000, 50_000), clip
        inner = next(n for n in v["nests"] if n["id"] != 10)["clips"][0]
        assert (inner["start"], inner["duration"]) == (25_000, 50_000), inner
        assert inner["video"]["motion"]["out"]["duration"] == 25_000
        assert inner["text"]["animation"]["out"] == 50_000
        assert inner["audio"]["fade_in"] == 10_001

    changed_with_undo(mcp, "paste", {"at": 400_000, "payload": payload}, pasted)

    copied = text_clip(80, 0, 0, 60_000)
    copied["video"]["motion"]["in"]["duration"] = 12_500
    copied["text"]["animation"]["out"] = 12_500
    copied["audio"]["fade_in"] = 12_501

    def attributes(v):
        c = next(c for c in v["clips"] if c["id"] == 2)
        assert (c["start"], c["duration"]) == (25_000, 50_000)
        assert c["video"]["motion"]["in"]["duration"] == 25_000
        assert c["text"]["animation"]["out"] == 25_000
        assert c["text"]["content"] == "Keep"
        assert c["audio"]["fade_in"] == 12_501

    changed_with_undo(mcp, "paste_attributes",
                      {"clips": [2], "payload": {"clips": [copied]}}, attributes)

    def opened(v):
        assert not any(c["id"] == 4 for c in v["clips"])
        c = next(c for c in v["clips"] if c["id"] not in (2, 4)
                 and c["source"]["kind"] == "text")
        assert (c["start"], c["duration"]) == (225_000, 50_000), c
        assert c["video"]["motion"]["out"]["duration"] == 25_000
        assert c["text"]["animation"]["out"] == 50_000

    changed_with_undo(mcp, "unnest", {"clip": 4}, opened)

    after = project(mcp)
    saved = os.path.join(where, "saved.framejob")
    mcp.call_with("save_project", {"path": saved})
    with open(os.path.join(saved, "project.json"), encoding="utf-8") as stream:
        persisted = json.load(stream)
    assert persisted["canvas"]["fps"] == [24, 1]
    reopened = os.path.join(where, "reopened.framejob")
    shutil.copytree(saved, reopened)
    mcp.call("open_project", path=reopened)
    assert project(mcp) == after, "reopen lost normalized times"
    print("ok save/reopen retains the complete normalized project")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(proof_app.bundle()))
    args = parser.parse_args()
    binary = str(proof_app.executable(args.app))
    assert os.path.isfile(binary), "matching app binary is missing: " + binary
    with tempfile.TemporaryDirectory(prefix="framejob-frame-grid-") as work:
        log_path = os.path.join(work, "app.log")
        socket_path = scratch_socket()
        with open(log_path, "w", encoding="utf-8") as log:
            env = os.environ.copy()
            env["RC_AGENT_SOCKET"] = socket_path
            env["RC_ASSEMBLYAI_KEY"] = "proof-key"
            app = subprocess.Popen([binary, "-ApplePersistenceIgnoreState", "YES"],
                                   stdout=log, stderr=subprocess.STDOUT, env=env)
            try:
                bound = wait_listening(log_path, socket_path, child=app, seconds=20)
                check_parity(log_path)
                assert bound, f"app did not listen at {socket_path}"
                run(MCP(socket_path, timeout=20), work)
                check_parity(log_path)
                assert app.poll() is None, "app exited during proof"
                print("frame grid proof passed; no parity complaints")
            finally:
                if app.poll() is None:
                    app.terminate()
                    try:
                        app.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        app.kill()
                        app.wait(timeout=5)
                remove_scratch(socket_path)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("FAIL frame grid proof:", error, file=sys.stderr)
        sys.exit(1)
