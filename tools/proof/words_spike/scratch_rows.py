#!/usr/bin/env python3
"""Road map 8, spike W0 — q7 (the macOS 26 bump) and q6's picture half.

**Nothing here touches the tree.** `q7` rsyncs a copy of the repository into a
scratch directory, moves the five places the deployment target is pinned in
THAT COPY, and builds it. The tree's `project.yml`, `Makefile` and
`tools/proof/harness/build.sh` are never opened for writing, which is what the
run's two `git` checks prove afterwards.

q6's picture half drives the app the copy built — one owned instance, on its
own port, killed by PID. `grep "Frame Job: "` on its log must print nothing
before any claim is read off a pixel.
"""

import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROOF = os.path.normpath(os.path.join(HERE, ".."))
ROOT = os.path.normpath(os.path.join(PROOF, "..", ".."))
CLOUD = os.path.join(PROOF, "cloud_spike")
for folder in (PROOF, CLOUD):
    if folder not in sys.path:
        sys.path.append(folder)

import local_rows                                                    # noqa: E402
import mcp as mcp_client                                             # noqa: E402
import text_rows                                                     # noqa: E402
from speech_rows import run_drained                                  # noqa: E402

SOCKET = mcp_client.scratch_socket()
LOG = mcp_client.log_beside(SOCKET)
OLD_TARGET = "15.0"
NEW_TARGET = "26.0"
OLD_TRIPLE = "arm64-apple-macos15.0"
NEW_TRIPLE = "arm64-apple-macos26.0"
CONTROL_FACE = "NoSuchFont-Black"
FACES = ["Montserrat-ExtraBold", "Montserrat-Black", "Anton-Regular", "BebasNeue-Regular"]


def scratch_root(work):
    named = os.environ.get("RC_WORDS_SPIKE_SCRATCH")
    return os.path.abspath(named) if named else os.path.join(work, "scratch")


def _run(argv, cwd, timeout):
    """`speech_rows.run_drained` with a working directory. `make` spawns
    xcodebuild, which spawns compilers, so the kill is of the whole process
    GROUP and nothing outside it; and a build's output is far more than a pipe
    buffer holds, so the pipes are drained while it runs."""
    result = run_drained(argv, timeout, cwd=cwd)
    return {"rc": result["rc"], "stdout": result["stdout"], "stderr": result["stderr"],
            "blocked": result["blocked"], "s": round(result["ms"] / 1000.0, 1)}


def _warnings(text):
    """Every `warning:` line swiftc printed, as `file:line: text`."""
    rows = []
    for line in (text or "").splitlines():
        found = re.match(r"^(.*?):(\d+):(\d+): warning: (.*)$", line)
        if found:
            rows.append({
                "file": os.path.basename(found.group(1)), "line": int(found.group(2)),
                "text": found.group(4)})
    return rows


def _errors(text):
    return [line for line in (text or "").splitlines() if ": error: " in line]


def _retarget(path, expect, become, lines=None):
    """One file's target pins moved, IN THE COPY. Answers what changed, or a
    refusal naming the line that did not read as expected."""
    with open(path) as handle:
        body = handle.read().splitlines(keepends=True)
    changed = []
    wanted = lines if lines is not None else range(1, len(body) + 1)
    for number in wanted:
        if number < 1 or number > len(body):
            return None, f"{path} has no line {number}"
        line = body[number - 1]
        if expect not in line:
            return None, f"{path}:{number} does not carry {expect!r}: {line.strip()!r}"
        body[number - 1] = line.replace(expect, become)
        changed.append({"line": number, "before": line.strip(),
                        "after": body[number - 1].strip()})
    with open(path, "w") as handle:
        handle.write("".join(body))
    return changed, None


# ---- q7 — what the bump costs ---------------------------------------------

def q7(work, say):
    root = scratch_root(work)
    copy = os.path.join(root, "w0-tree")
    os.makedirs(root, exist_ok=True)
    shutil.rmtree(copy, ignore_errors=True)
    os.makedirs(copy, exist_ok=True)
    rsync = _run(
        ["rsync", "-a", "--exclude", ".git", "--exclude", "build",
         "--exclude", "tools/proof/work", "--exclude", "core/target",
         ROOT + "/", copy + "/"], cwd=ROOT, timeout=600)
    if rsync["rc"] != 0:
        return {"state": "failed", "reason": "the tree could not be copied",
                "measured": {"rsync": rsync["stderr"][-400:]}}
    size = _run(["du", "-sm", copy], cwd=root, timeout=120)["stdout"].split()
    measured = {"copy": copy, "megabytes": int(size[0]) if size and size[0].isdigit() else None}

    # The CONTROL first: the copy still at 15.0 must be the tree's own
    # baseline, 0 errors and 4 warnings. A copy that does not reproduce it is
    # not a measurement of the BUMP.
    control = _run(["make", "typecheck"], cwd=copy, timeout=900)
    control_warnings = _warnings(control["stderr"] + control["stdout"])
    measured["control_typecheck"] = {
        "target": OLD_TRIPLE, "rc": control["rc"], "seconds": control["s"],
        "errors": len(_errors(control["stderr"] + control["stdout"])),
        "warnings": len(control_warnings), "warning_rows": control_warnings,
        "baseline": "0 errors and 4 warnings (the root CLAUDE.md)",
        "matches_baseline": len(control_warnings) == 4
                            and not _errors(control["stderr"] + control["stdout"]),
    }
    say(f"  q7/CONTROL typecheck at {OLD_TARGET}: "
        f"{measured['control_typecheck']['errors']} errors, "
        f"{measured['control_typecheck']['warnings']} warnings "
        f"({control['s']} s)")

    edits = {}
    for path, expect, become, lines in (
        (os.path.join(copy, "project.yml"), OLD_TARGET, NEW_TARGET, [5, 49, 57]),
        (os.path.join(copy, "Makefile"), OLD_TRIPLE, NEW_TRIPLE, [40]),
        (os.path.join(copy, "tools", "proof", "harness", "build.sh"),
         OLD_TRIPLE, NEW_TRIPLE, [50]),
    ):
        changed, error = _retarget(path, expect, become, lines)
        if changed is None:
            return {"state": "failed", "reason": error,
                    "measured": {**measured, "edits": edits}}
        edits[os.path.relpath(path, copy)] = changed
    measured["edits"] = edits

    # The four TTFs and their licences go into the COPY's own Fonts folder
    # before `make app`, so q6's picture half has faces to ask for.
    bundled = []
    if os.path.isdir(text_rows.FONTS):
        for name in sorted(os.listdir(text_rows.FONTS)):
            if name.endswith((".ttf", ".otf", ".txt")):
                shutil.copy2(os.path.join(text_rows.FONTS, name),
                             os.path.join(copy, "app", "Resources", "Fonts", name))
                bundled.append(name)
    measured["fonts_bundled_into_the_copy"] = bundled

    typecheck = _run(["make", "typecheck"], cwd=copy, timeout=900)
    text = typecheck["stderr"] + typecheck["stdout"]
    rows = _warnings(text)
    before = {(r["file"], r["line"], r["text"]) for r in control_warnings}
    measured["typecheck"] = {
        "target": NEW_TRIPLE, "rc": typecheck["rc"], "seconds": typecheck["s"],
        "errors": len(_errors(text)), "error_rows": _errors(text)[:12],
        "warnings": len(rows), "warning_rows": rows,
        "new_warnings": [r for r in rows if (r["file"], r["line"], r["text"]) not in before],
        "warnings_gone": [
            {"file": f, "line": ln, "text": t} for f, ln, t in sorted(before)
            if (f, ln, t) not in {(r["file"], r["line"], r["text"]) for r in rows}],
    }
    say(f"  q7/typecheck at {NEW_TARGET}: {measured['typecheck']['errors']} errors, "
        f"{measured['typecheck']['warnings']} warnings, "
        f"{len(measured['typecheck']['new_warnings'])} of them new ({typecheck['s']} s)")

    app = _run(["env", "-u", "RC_ASSEMBLYAI_KEY", "make", "app"], cwd=copy, timeout=1200)
    app_text = app["stderr"] + app["stdout"]
    binary = os.path.join(
        copy, "build", "Build", "Products", "Release", "Frame Job.app",
        "Contents", "MacOS", "Frame Job")
    measured["make_app"] = {
        "rc": app["rc"], "blocked": app["blocked"], "seconds": app["s"],
        "errors": len(_errors(app_text)), "error_rows": _errors(app_text)[:12],
        "warnings": len(_warnings(app_text)),
        "binary_exists": os.path.exists(binary),
        "tail": app_text[-600:] if app["rc"] not in (0,) else "",
    }
    say(f"  q7/make app at {NEW_TARGET}: rc {app['rc']}, {app['s']} s, "
        f"binary {os.path.exists(binary)}")

    harness = _run([os.path.join(copy, "tools", "proof", "harness", "build.sh"), "--force"],
                   cwd=copy, timeout=600)
    harness_binary = (harness["stdout"] or "").strip().splitlines()[-1:] or [""]
    png = os.path.join(work, "q7", "welcome.png")
    os.makedirs(os.path.dirname(png), exist_ok=True)
    render = {"rc": None, "s": 0.0}
    if harness["rc"] == 0 and os.path.exists(harness_binary[0]):
        render = _run([harness_binary[0], "welcome", png, "light"], cwd=copy, timeout=300)
    measured["harness"] = {
        "rc": harness["rc"], "seconds": harness["s"],
        "binary": harness_binary[0],
        "errors": len(_errors(harness["stderr"])),
        "error_rows": _errors(harness["stderr"])[:8],
        "welcome_render_rc": render["rc"], "welcome_render_seconds": render["s"],
        "welcome_png_bytes": os.path.getsize(png) if os.path.exists(png) else 0,
    }
    say(f"  q7/harness at {NEW_TARGET}: rc {harness['rc']} ({harness['s']} s), "
        f"welcome render rc {render['rc']}, "
        f"{measured['harness']['welcome_png_bytes']} bytes")

    # W1a's own list: every file under `tools/proof/` that pins the old
    # triple, read out of the TREE (not the copy) because that is the list a
    # later phase has to walk.
    pinned = _run(["git", "grep", "-l", OLD_TRIPLE, "--", "tools/proof"],
                  cwd=ROOT, timeout=120)
    files = [line for line in (pinned["stdout"] or "").splitlines() if line.strip()]
    measured["files_pinning_the_old_triple"] = {
        "count": len(files), "files": files,
        "besides_readme": [f for f in files if not f.endswith("README.md")],
    }
    say(f"  q7/W1a: {len(files)} files under tools/proof pin {OLD_TRIPLE}")

    measured["binary"] = binary if os.path.exists(binary) else None
    if not measured["control_typecheck"]["matches_baseline"]:
        return {"state": "failed", "measured": measured,
                "reason": "the scratch copy does not reproduce the tree's own typecheck "
                          "baseline, so nothing measured after it is the bump's"}
    if app["rc"] != 0 or not os.path.exists(binary):
        return {"state": "failed", "measured": measured,
                "reason": f"`make app` at {NEW_TARGET} did not produce a binary"}
    return {"state": "run", "reason": None, "measured": measured}


# ---- q6's picture half ----------------------------------------------------

class Instance:
    """One owned app, by PID, on a scratch socket. Never a pattern kill."""

    def __init__(self, binary, say):
        self.say = say
        self.binary = binary
        self.child = None
        self.port = None

    def start(self):
        if os.path.exists(LOG):
            os.remove(LOG)
        environment = local_rows.child_env()
        environment["RC_AGENT_SOCKET"] = SOCKET
        with open(LOG, "w") as log:
            self.child = subprocess.Popen(
                [self.binary, "-ApplePersistenceIgnoreState", "YES"],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log, env=environment,
                start_new_session=True)
        # The log line is `Frame Job agent socket listening at <path>`.
        if mcp_client.wait_listening(LOG, SOCKET, child=self.child, seconds=60):
            self.port = SOCKET
            return self.port
        return None

    def complaints(self):
        try:
            with open(LOG) as handle:
                # A SUBSTRING, not a prefix: every line carries a
                # timestamp and the process name first.
                return [line.strip() for line in handle if "Frame Job: " in line]
        except OSError:
            return ["the log could not be read"]

    def stop(self):
        if self.child is None:
            return
        self.child.terminate()
        try:
            self.child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.child.kill()
        mcp_client.remove_scratch(SOCKET)


def _digest(path):
    import hashlib
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def q6_picture(work, binary, say):
    if binary is None or not os.path.exists(binary):
        return {"state": "not_run", "measured": {},
                "reason": "q7 built no scratch binary, so there is nothing to photograph"}
    folder = os.path.join(work, "q6", "picture")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder, exist_ok=True)
    instance = Instance(binary, say)
    port = instance.start()
    if port is None:
        instance.stop()
        return {"state": "failed", "measured": {"log": LOG},
                "reason": "the scratch app never named its socket in its log"}
    complaints = instance.complaints()
    measured = {"port": port, "parity_complaints": complaints, "faces": {}}
    if complaints:
        instance.stop()
        return {"state": "failed", "measured": measured,
                "reason": "the scratch app's startup parity check complained, so no "
                          "pixel it draws is evidence"}
    try:
        client = mcp_client.MCP(port)
        # `export`'s schema does NOT enumerate its presets: the ids come from
        # `rc_export_presets`, and the description says "pass a wrong one once
        # and the error lists them all". So the list is ASKED for, once — a
        # measurement rather than a name copied into this file — and it is
        # asked of a project that already has a clip, because an empty
        # timeline is refused BEFORE the preset is looked at.
        schema = client.schemas().get("export", {}).get("inputSchema", {})
        measured["export_preset_enum_in_the_schema"] = (
            (schema.get("properties", {}).get("preset", {}) or {}).get("enum") or [])
        preset = None
        digests = {}
        for face in FACES + [CONTROL_FACE]:
            path = os.path.join(folder, f"{face}.framejob")
            client.call("new_project", path=path)
            client.call("set_canvas", project=path, width=1080, height=1920)
            client.call("add_track", project=path)
            track = client.call(
                "get_project", project=path)["project"]["tracks"][-1]["id"]
            client.call(
                "add_text_clip", project=path, track=track, at=0, duration=3_000_000,
                text={"content": "THIS IS HOW IT LOOKS", "font": face, "size": 81.0})
            if preset is None:
                try:
                    client.call("export", project=path, preset="w0-no-such-preset",
                                path=os.path.join(folder, "none.mov"))
                    measured["export_preset_listing"] = "the wrong preset was accepted"
                except Exception as refusal:                         # noqa: BLE001
                    measured["export_preset_listing"] = str(refusal)
                    listed = re.findall(r"[a-z0-9_]+", str(refusal).split("are:")[-1])
                    measured["export_presets"] = listed
                    preset = next((p for p in listed if not p.startswith("audio")), None)
                    measured["export_preset_used"] = preset
            answer = client.call("render_frame", project=path, t=1_000_000)
            found = re.search(r"Written to (\S+\.png)\.", str(answer))
            if not found:
                measured["faces"][face] = {"error": f"render_frame said {answer}"}
                continue
            png = found.group(1)
            kept = os.path.join(folder, f"{face}.png")
            shutil.copy2(png, kept)
            digests[face] = _digest(kept)
            row = {"png": kept, "sha256": digests[face],
                   "bytes": os.path.getsize(kept)}
            if preset:
                asked = os.path.join(folder, f"{face}.mov")
                # The tool CORRECTS the extension to the preset's own
                # container, so the path it ANSWERS with is the file — never
                # the one that was asked for.
                told = client.call("export", project=path, preset=preset, path=asked)
                movie = (told.get("path") if isinstance(told, dict) else None) or asked
                if not os.path.exists(movie):
                    guess = re.search(r"(/\S+\.(?:mp4|mov|m4v|gif|png))", str(told))
                    movie = guess.group(1) if guess else movie
                row["export"] = {"asked_for": asked, "path": movie,
                                 "bytes": os.path.getsize(movie)
                                 if os.path.exists(movie) else 0}
                frame = os.path.join(folder, f"{face}.export.png")
                ff = local_rows.run_bounded(
                    ["ffmpeg", "-y", "-v", "error", "-ss", "1", "-i", movie,
                     "-frames:v", "1", frame], timeout=300)
                row["export"]["frame_bytes"] = (
                    os.path.getsize(frame) if os.path.exists(frame) else 0)
                row["export"]["frame_sha256"] = (
                    _digest(frame) if os.path.exists(frame) else None)
                row["export"]["ffmpeg_rc"] = ff["rc"]
            measured["faces"][face] = row
            say(f"  q6/picture {face}: {row['bytes']} bytes, "
                f"export frame {row.get('export', {}).get('frame_bytes')}")
        control = digests.get(CONTROL_FACE)
        measured["all_differ_from_control"] = bool(control) and all(
            value != control for face, value in digests.items() if face != CONTROL_FACE)
        measured["all_differ_from_each_other"] = (
            len({v for f, v in digests.items() if f != CONTROL_FACE})
            == len([f for f in digests if f != CONTROL_FACE]))
        measured["export_frames_differ"] = len({
            row.get("export", {}).get("frame_sha256")
            for face, row in measured["faces"].items()
            if face != CONTROL_FACE and row.get("export", {}).get("frame_sha256")}) == len(
                [f for f in measured["faces"] if f != CONTROL_FACE
                 and measured["faces"][f].get("export", {}).get("frame_sha256")])
        measured["host_note"] = (
            "Montserrat, Anton and Bebas Neue are also installed in /Library/Fonts on "
            "this host, so a face resolving here does not prove the BUNDLE is what "
            "resolved it; the registry half of q6 records the same faces read from "
            "the spike's own directory")
        measured["parity_complaints_after"] = instance.complaints()
    except Exception as error:                                       # noqa: BLE001
        measured["error"] = f"{type(error).__name__}: {error}"
        instance.stop()
        return {"state": "failed", "measured": measured,
                "reason": measured["error"]}
    finally:
        instance.stop()
    missing = [face for face in FACES + [CONTROL_FACE] if face not in digests]
    if missing:
        return {"state": "failed", "measured": measured,
                "reason": "render_frame drew no PNG for: " + ", ".join(
                    f"{face} ({measured['faces'].get(face, {}).get('error', 'not reached')})"
                    for face in missing)}
    if not measured.get("all_differ_from_control"):
        return {"state": "failed", "measured": measured,
                "reason": "a bundled face drew the same pixels as the CONTROL name"}
    if not measured.get("all_differ_from_each_other"):
        return {"state": "failed", "measured": measured,
                "reason": "two bundled faces drew the same pixels"}
    if not measured.get("export_frames_differ"):
        return {"state": "failed", "measured": measured,
                "reason": "two bundled faces exported the same frame"}
    return {"state": "run", "reason": None, "measured": measured}
