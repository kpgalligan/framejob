#!/usr/bin/env python3
"""Road map 14 MC1 — the spike: the snapshot, the launch, the client, the socket.

Four questions `archive/roadmap-14.md` (condensed in `designs/adr/roadmap-14-agent-socket.md`) asks before MC2 and MC3 are
built, measured. **The answers are not here**: they are that document's MC1
record. What is here is the instrument that measured them.

  q1  can the build write the catalog snapshot (an Xcode script phase that
      runs the just-linked binary with `-RCWriteCatalog`), in Release and
      Distribution, and what it costs; the runtime fallback's cost;
  q2  what a background launch (`open -n -g`) costs and shows: cold, warm,
      quarantined; focus and windows;
  q3  whether Claude Code refetches on `notifications/tools/list_changed`
      (its docs, quoted) and a stdio stub that sends it (no model call);
  q4  the socket path's length against `sun_path`, and what tiny_http 0.12's
      `Server::http_unix` does with an existing file, a dead server's file,
      a regular file, a replaced file, a POST, `to_ip`, `unblock`.

    python3 tools/proof/mc1_spike/mc1_spike.py                 # all four, then Z1
    python3 tools/proof/mc1_spike/mc1_spike.py --only q4       # a subset; other rows carry forward

Builds happen only in the tree copy `work/mc1_spike/tree` (`tree_copy.py`),
which alone gets `CatalogWriterHook.swift`, the `main.swift` line and the
`project.yml` phase. Every child runs in its own process group under a
wall-clock bound (`graphics_spike/bounded.py`), without `ANTHROPIC_API_KEY`,
`CLAUDECODE` or `CLAUDE_CODE_ENTRYPOINT`. No model call, no API request,
nothing written under `~/Library/Application Support/Frame Job/`, and no
Frame Job process killed whose command line does not hold
`tools/proof/work/mc1_spike/`.

Writes `work/mc1_spike/answers.json`, prints one line per row and a digest.
Exit 0 when no row is `error`; 1 otherwise.
"""

import argparse
import datetime
import html
import http.client
import json
import os
import plistlib
import pwd
import queue
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROOF = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(PROOF, "..", ".."))
sys.path.insert(0, os.path.join(PROOF, "graphics_spike"))
sys.path.insert(0, PROOF)

import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = os.path.join(PROOF, "work", "mc1_spike")
ANSWERS = os.path.join(WORK, "answers.json")
TREE = os.path.join(WORK, "tree")
OWNED = "tools/proof/work/mc1_spike/"
CRATE = os.path.join(HERE, "socket_probe")
SOCKET_PROBE = os.path.join(CRATE, "target", "release", "socket_probe")
WINDOWS_SOURCE = os.path.join(HERE, "windows_probe.swift")
WINDOWS_PROBE = os.path.join(WORK, "windows_probe")
HOOK = os.path.join(HERE, "CatalogWriterHook.swift")
STUB = os.path.join(HERE, "stub_mcp.py")
SEAM = os.path.join(ROOT, "app", "Sources", "AgentServer+DevTools.swift")
RELEASE = os.path.join(TREE, "build", "Build", "Products", "Release", "Frame Job.app")
DIST = os.path.join(TREE, "build", "Build", "Products", "Distribution", "Frame Job.app")
SNAPSHOT = os.path.join("Contents", "Resources", "agent-catalog.json")
DOCS_URL = "https://code.claude.com/docs/en/mcp"

MAIN_ANCHOR = "AgentLane.prepareAtLaunch()"
YML_ANCHOR = 'script: /bin/sh "$PROJECT_DIR/agent/build.sh" helper'
PHASE = r"""      - name: MC1 Spike Write Agent Catalog
        basedOnDependencyAnalysis: false
        script: |
          set -e
          out="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/agent-catalog.json"
          now() { /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
          exe="$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
          start=$(now)
          # The linker leaves it unsigned (-no_adhoc_codesign) and arm64 kills an
          # unsigned exec: ad-hoc sign the executable alone, in place; Xcode's
          # CodeSign step re-signs the bundle after this phase (addendum 4).
          codesign -s - -f "$exe"
          signed=$(now)
          rc=0
          output=$("$exe" -RCWriteCatalog "$out" 2>&1) || rc=$?
          end=$(now)
          echo "MC1 phase cdhash: $(codesign -dv --verbose=4 "$exe" 2>&1 | sed -n 's/^CDHash=//p')"
          echo "MC1 catalog writer output begin"
          if [ -n "$output" ]; then printf '%s\n' "$output"; fi
          echo "MC1 catalog writer output end"
          echo "MC1 catalog sign: $((signed - start)) ms"
          echo "MC1 catalog phase: $((end - start)) ms"
          if [ "$rc" -ne 0 ]; then
            echo "error: MC1 catalog writer exited $rc"
            exit 1
          fi"""
# The Makefile's `dist` recipe's xcodebuild line, run in the copy.
DIST_BUILD = ["xcodebuild", "-project", "FrameJob.xcodeproj", "-scheme", "FrameJob",
              "-configuration", "Distribution", "-derivedDataPath", "build", "build"]

QUESTION_ROWS = {
    "q4": ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "S11"],
    "q1": ["B1", "B2", "B3", "B4", "B5", "B6", "B7", "B7c", "B8", "B9", "B10", "B11", "B12"],
    "q2": ["H0", "L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"],
    "q3": ["C1", "D1", "T1", "T2", "T3"],
}
ORDER = ["q4", "q1", "q2", "q3"]

ROWS = {}
STATE = {}


def env(extra=None):
    """`child_env()` minus the Anthropic key and Claude Code's own markers."""
    result = bounded.child_env(extra)
    for name in ("ANTHROPIC_API_KEY", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"):
        result.pop(name, None)
    return result


def run(argv, seconds, cwd=None, extra=None):
    return bounded.run(argv, seconds, cwd=cwd, env=env(extra))


def row(ident, status, value=None, detail=""):
    assert status in ("answered", "pass", "fail", "skip", "error"), status
    ROWS[ident] = {"status": status, "value": value, "detail": detail}
    shown = json.dumps(value, ensure_ascii=False)
    if len(shown) > 160:
        shown = shown[:157] + "..."
    print(f"{ident:4} {status:8} {shown} — {detail}", flush=True)


def save_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def describe(result):
    if result["expired"]:
        return f"expired after {result['seconds']} s"
    tail = (result["stderr"] or result["stdout"] or "").strip().splitlines()[-3:]
    return f"rc {result['rc']} after {result['seconds']} s: " + " | ".join(tail)


# ---------------------------------------------------------------- q4 socket


def q4():
    home = os.path.expanduser("~")
    suffix = "/Library/Application Support/Frame Job/Agent/agent.sock"
    product = home + suffix
    tmpdir = os.environ.get("TMPDIR") or tempfile.gettempdir()
    tmp_path = os.path.join(tmpdir, "framejob-XXXXXXXX", "agent.sock")
    work_path = os.path.join(ROOT, "tools", "proof", "work", "x" * 12, "agent.sock")
    longest = 103 - len("/Users/") - len(suffix.encode())
    lengths = {
        "product": {"path": product, "bytes": len(product.encode())},
        "longest_user_name_at_103": longest,
        "tmpdir": {"path": tmp_path, "bytes": len(tmp_path.encode())},
        "worktree_work": {"path": work_path, "bytes": len(work_path.encode())},
    }
    fits = {key: lengths[key]["bytes"] <= 103 for key in ("product", "tmpdir", "worktree_work")}
    lengths["fits_103"] = fits
    row("S1", "answered", lengths,
        f"product {lengths['product']['bytes']} B; /Users/<name> fits 103 B up to {longest}-byte "
        f"names; $TMPDIR {lengths['tmpdir']['bytes']} B; worktree work "
        f"{lengths['worktree_work']['bytes']} B")

    built = run(["cargo", "build", "--release", "--offline"], 900, cwd=CRATE)
    if built["rc"] != 0 or not os.path.isfile(SOCKET_PROBE):
        for ident in QUESTION_ROWS["q4"][1:10]:
            row(ident, "error", None, f"socket_probe did not build: {describe(built)}")
    else:
        scratch = tempfile.mkdtemp(prefix="mc1-q4-")
        if len(scratch.encode()) > 90:
            shutil.rmtree(scratch, ignore_errors=True)
            scratch = tempfile.mkdtemp(prefix="mc1-q4-", dir="/tmp")
        mask = os.umask(0o022)
        os.umask(mask)
        try:
            probe = run([SOCKET_PROBE, scratch], 120)
        finally:
            shutil.rmtree(scratch, ignore_errors=True)
        try:
            answer = json.loads(probe["stdout"])
        except ValueError:
            answer = None
        if probe["rc"] != 0 or answer is None:
            for ident in QUESTION_ROWS["q4"][1:10]:
                row(ident, "error", None, f"socket_probe did not answer: {describe(probe)}")
        else:
            score_socket(answer, mask)

    support = os.path.join(home, "Library", "Application Support", "Frame Job")
    agent = os.path.join(support, "Agent")
    try:
        info = os.stat(support)
        try:
            owner = pwd.getpwuid(info.st_uid).pw_name
        except KeyError:
            owner = str(info.st_uid)
        value = {"path": support, "mode": f"{stat.S_IMODE(info.st_mode):04o}", "owner": owner,
                 "owned_by_me": info.st_uid == os.getuid(), "agent_exists": os.path.exists(agent)}
        row("S11", "answered", value,
            f"support folder {value['mode']} owned by {owner}; Agent/ "
            f"{'exists' if value['agent_exists'] else 'absent'} (read only, nothing created)")
    except FileNotFoundError:
        row("S11", "answered", {"path": support, "exists": False,
                                "agent_exists": os.path.exists(agent)},
            "support folder absent (read only, nothing created)")


def score_socket(answer, mask):
    s2 = answer.get("S2", {})
    ok = {key: s2.get(key, {}).get("ok") for key in ("103", "104", "105")}
    row("S2", "answered", s2,
        f"103 B {'binds' if ok['103'] else 'fails'}; 104 B: {s2.get('104', {}).get('error')}; "
        f"105 B: {s2.get('105', {}).get('error')}")
    s3 = dict(answer.get("S3", {}))
    s3["umask"] = f"{mask:03o}"
    row("S3", "answered" if s3.get("ok") else "fail", s3,
        f"fresh bind {'succeeds' if s3.get('ok') else 'fails'}; socket file mode {s3.get('mode')} "
        f"under umask {s3['umask']}; file after drop {s3.get('file_after_drop')}")
    s4 = answer.get("S4", {})
    row("S4", "answered", s4, f"bind over a live server: {s4.get('error')}")
    s5 = answer.get("S5", {})
    if not s5.get("hold_bound"):
        row("S5", "error", s5, "the --hold fixture never bound")
    else:
        row("S5", "answered", s5,
            f"after SIGKILL the file is left ({s5.get('file_left')}); connect: "
            f"{s5.get('connect', {}).get('kind')}; bind: {s5.get('bind_error')}")
    s6 = answer.get("S6", {})
    row("S6", "answered", s6,
        f"bind over a regular file: {s6.get('error')}; file intact {s6.get('file_intact')}")
    s7 = answer.get("S7", {})
    row("S7", "answered", s7,
        f"B's file after A's drop: {s7.get('b_file_exists_after_a_drop')}; B reachable after: "
        f"{s7.get('b_reachable_after_a_drop', {}).get('ok')} "
        f"({s7.get('b_reachable_after_a_drop', {}).get('kind')})")
    s8 = answer.get("S8", {})
    row("S8", "pass" if s8.get("ok") else "fail", s8,
        f"POST over the socket: {s8.get('status_line') or s8.get('error')}")
    s9 = answer.get("S9", {})
    row("S9", "answered", s9, f"server_addr().to_ip() is None: {s9.get('to_ip_is_none')}")
    s10 = answer.get("S10", {})
    row("S10", "pass" if s10.get("returned") else "fail", s10,
        f"unblock() then join returned in {s10.get('ms')} ms")


# ---------------------------------------------------------------- q1 snapshot


def dev_names():
    with open(SEAM, encoding="utf-8") as handle:
        text = handle.read()
    block = re.search(r"private static let devHandlers: \[String: ToolHandler\] = \[(.*?)\n\s*\]",
                      text, re.S)
    if not block:
        return None
    return re.findall(r'^\s*"([a-z_]+)":', block.group(1), re.M)


def phase_figures(text):
    ms = [int(m) for m in re.findall(r"^MC1 catalog phase: (\d+) ms$", text, re.M)]
    outputs = re.findall(r"^MC1 catalog writer output begin$\n(.*?)^MC1 catalog writer output end$",
                         text, re.M | re.S)
    return ms, outputs


def phase_sign(text):
    """(the phase's signing ms, the CDHash the phase's signature had)."""
    sign = re.findall(r"^MC1 catalog sign: (\d+) ms$", text, re.M)
    cdhash = re.findall(r"^MC1 phase cdhash: (\S*)$", text, re.M)
    return (int(sign[0]) if sign else None), (cdhash[-1] if cdhash else None)


def signature(path):
    """`codesign -dv --verbose=4` of `path`, the fields B12 reads."""
    result = run(["codesign", "-dv", "--verbose=4", path], 60)
    text = (result["stderr"] or "") + (result["stdout"] or "")
    field = lambda name: (re.findall(rf"^{name}=(.*)$", text, re.M) or [None])[0]  # noqa: E731
    flags = re.findall(r"flags=0x[0-9a-f]+\(([^)]*)\)", text)
    return {"rc": result["rc"], "cdhash": field("CDHash"), "signature": field("Signature"),
            "flags": flags[0] if flags else None, "info_plist": field("Info.plist entries"),
            "sealed_resources": field("Sealed Resources version"),
            "authority": re.findall(r"^Authority=(.*)$", text, re.M)}


def read_snapshot(bundle):
    """(parsed, raw bytes, problem)."""
    path = os.path.join(bundle, SNAPSHOT)
    try:
        with open(path, "rb") as handle:
            raw = handle.read()
        return json.loads(raw), raw, None
    except (OSError, ValueError) as error:
        return None, None, f"{path}: {error}"


def bundle_version(bundle):
    try:
        with open(os.path.join(bundle, "Contents", "Info.plist"), "rb") as handle:
            return plistlib.load(handle).get("CFBundleShortVersionString")
    except (OSError, plistlib.InvalidFileException):
        return None


def ditto(source, dest):
    tree_copy.remove_tree(os.path.dirname(dest))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    return run(["ditto", source, dest], 300)


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def sorted_dump(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def q1():
    q1_rows = QUESTION_ROWS["q1"]
    dest, reason = tree_copy.make_copy(TREE)
    if dest is None:
        for ident in q1_rows:
            row(ident, "error", None, reason)
        return
    main_path = os.path.join(TREE, "app", "Sources", "main.swift")
    yml_path = os.path.join(TREE, "project.yml")
    with open(main_path, encoding="utf-8") as handle:
        main_lines = handle.read().split("\n")
    with open(yml_path, encoding="utf-8") as handle:
        yml_lines = handle.read().split("\n")
    main_hits = [i for i, line in enumerate(main_lines) if line.strip() == MAIN_ANCHOR]
    yml_hits = [i for i, line in enumerate(yml_lines) if line.strip() == YML_ANCHOR]
    anchors = {"main.swift": len(main_hits), "project.yml": len(yml_hits)}
    if len(main_hits) != 1 or len(yml_hits) != 1:
        row("B1", "fail", anchors, "an anchor is not found exactly once; nothing inserted")
        for ident in q1_rows[1:]:
            row(ident, "error", None, "B1 failed: the copy was not patched")
        return
    main_lines.insert(main_hits[0] + 1, "mc1WriteCatalogIfAsked()")
    yml_lines[yml_hits[0] + 1:yml_hits[0] + 1] = PHASE.split("\n")
    save_text(main_path, "\n".join(main_lines))
    save_text(yml_path, "\n".join(yml_lines))
    shutil.copy2(HOOK, os.path.join(TREE, "app", "Sources", "CatalogWriterHook.swift"))
    row("B1", "pass", anchors, "each anchor found exactly once; hook, main.swift line and phase inserted")

    logs = os.path.join(WORK, "q1")
    os.makedirs(logs, exist_ok=True)
    builds = {}
    for ident, label, argv in (("B2", "make-app-full", ["make", "app"]),
                               ("B3", "make-app-incremental", ["make", "app"]),
                               ("B4", "distribution", DIST_BUILD)):
        result = run(argv, 2400, cwd=TREE)
        text = (result["stdout"] or "") + "\n" + (result["stderr"] or "")
        save_text(os.path.join(logs, f"{label}.log"), text)
        ms, outputs = phase_figures(text)
        sign_ms, cdhash = phase_sign(text)
        ok = result["rc"] == 0 and "** BUILD SUCCEEDED **" in text and len(ms) == 1
        builds[ident] = {"text": text, "outputs": outputs, "ok": ok, "phase_cdhash": cdhash}
        value = {"wall_s": result["seconds"], "phase_ms": ms[0] if ms else None,
                 "sign_ms": sign_ms, "rc": result["rc"], "phase_cdhash": cdhash}
        if ok:
            row(ident, "pass", value, f"{' '.join(argv[:2])}: {result['seconds']} s wall, phase "
                f"{ms[0]} ms (of which the ad-hoc sign {sign_ms} ms)")
        else:
            row(ident, "fail", value,
                f"{' '.join(argv[:2])} did not succeed with one phase line: {describe(result)} "
                f"(log work/mc1_spike/q1/{label}.log)")

    bundles = {"Release": RELEASE, "Distribution": DIST}
    snapshots = {}
    problems = []
    for name, bundle in bundles.items():
        parsed, raw, problem = read_snapshot(bundle)
        if problem:
            problems.append(problem)
            continue
        version = bundle_version(bundle)
        if not (isinstance(parsed, dict) and set(parsed) == {"version", "tools"}
                and isinstance(parsed["tools"], list)):
            problems.append(f"{name}: not {{version, tools}}: keys {sorted(parsed) if isinstance(parsed, dict) else type(parsed).__name__}")
            continue
        if parsed["version"] != version:
            problems.append(f"{name}: version {parsed['version']!r} != bundle {version!r}")
        snapshots[name] = {"parsed": parsed, "raw": raw}
    STATE["snapshots"] = snapshots
    row("B5", "pass" if not problems and len(snapshots) == 2 else "fail",
        {name: {"version": s["parsed"]["version"], "tools": len(s["parsed"]["tools"]),
                "bytes": len(s["raw"])} for name, s in snapshots.items()},
        "; ".join(problems) or "both snapshots parse as {version, tools} at the bundle's version")

    names = dev_names()
    if not names or len(names) != 6:
        row("B6", "error", names, f"devHandlers' six keys not read from {SEAM}")
    elif len(snapshots) != 2:
        row("B6", "fail", names, "a snapshot is missing")
    else:
        release = {tool.get("name") for tool in snapshots["Release"]["parsed"]["tools"]}
        dist = {tool.get("name") for tool in snapshots["Distribution"]["parsed"]["tools"]}
        missing = sorted(set(names) - release)
        leaked = sorted(set(names) & dist)
        row("B6", "pass" if not missing and not leaked else "fail",
            {"dev_tools": names, "missing_from_release": missing, "in_distribution": leaked},
            f"Release names {6 - len(missing)}/6 dev tools, Distribution {len(leaked)}/6")

    verify = {}
    for name, bundle in bundles.items():
        result = run(["codesign", "--verify", "--strict", "--deep", bundle], 120)
        verify[name] = {"rc": result["rc"], "stderr": (result["stderr"] or "").strip()[-300:]}
    row("B7", "pass" if all(v["rc"] == 0 for v in verify.values()) else "fail", verify,
        "codesign --verify --strict --deep on both bundles")

    tampered = os.path.join(WORK, "q1", "b7c", "Frame Job.app")
    copied = ditto(RELEASE, tampered)
    target = os.path.join(tampered, SNAPSHOT)
    if copied["rc"] != 0 or not os.path.isfile(target):
        row("B7c", "error", None, f"the CONTROL's copy failed: {describe(copied)}")
    else:
        with open(target, "rb") as handle:
            data = bytearray(handle.read())
        middle = len(data) // 2
        data[middle] = data[middle] ^ 0x01
        with open(target, "wb") as handle:
            handle.write(bytes(data))
        result = run(["codesign", "--verify", "--strict", "--deep", tampered], 120)
        row("B7c", "pass" if result["rc"] not in (0, None) else "fail",
            {"rc": result["rc"], "stderr": (result["stderr"] or "").strip()[-300:]},
            "CONTROL: one byte of a copied bundle's snapshot changed; codesign must refuse it")

    check = run([sys.executable, os.path.join(PROOF, "dist_check.py"),
                 "--release", RELEASE, "--dist", DIST], 300)
    last = (check["stdout"] or "").strip().splitlines()[-1:] or [""]
    row("B8", "pass" if check["rc"] == 0 else "fail", {"rc": check["rc"], "last": last[0]},
        "dist_check.py on the copy's two bundles")

    fresh = os.path.join(WORK, "q1", "b10", "Frame Job.app")
    copied = ditto(RELEASE, fresh)
    if copied["rc"] != 0 or "Release" not in snapshots:
        row("B10", "error", None, f"no fresh copy or no build snapshot: {describe(copied)}")
    else:
        built = snapshots["Release"]
        runs = []
        for index in range(4):
            out = os.path.join(WORK, "q1", "b10", f"out-{index}.json")
            if os.path.exists(out):
                os.remove(out)
            result = run([str(proof_app.executable(fresh)), "-RCWriteCatalog", out], 120)
            try:
                with open(out, "rb") as handle:
                    raw = handle.read()
                parsed = json.loads(raw)
            except (OSError, ValueError):
                raw, parsed = None, None
            runs.append({"kind": "fresh" if index == 0 else "warm", "wall_s": result["seconds"],
                         "rc": result["rc"], "json_equal": parsed == built["parsed"],
                         "bytes_equal": raw == built["raw"],
                         "sorted_keys_equal": parsed is not None
                         and sorted_dump(parsed) == sorted_dump(built["parsed"]),
                         "framejob_lines": [line for line in (result["stderr"] or "").splitlines()
                                           if "Frame Job: " in line]})
        ok = all(r["rc"] == 0 and r["json_equal"] for r in runs)
        row("B10", "pass" if ok else "fail", runs,
            "fallback: fresh " + str(runs[0]["wall_s"]) + " s, warm "
            + ", ".join(str(r["wall_s"]) for r in runs[1:]) + " s; equal as JSON "
            + str(all(r["json_equal"] for r in runs)) + ", as bytes "
            + str(all(r["bytes_equal"] for r in runs)) + ", with sorted keys "
            + str(all(r["sorted_keys_equal"] for r in runs)))

    found = {}
    missing = []
    for ident, build in builds.items():
        if not build["outputs"]:
            missing.append(ident)
            continue
        found[ident] = [line for out in build["outputs"] for line in out.splitlines()
                        if "Frame Job: " in line]
    if missing:
        row("B11", "error", found, f"no phase output block in {missing}'s log")
    else:
        row("B11", "pass" if not any(found.values()) else "fail", found,
            "no `Frame Job: ` line in any phase's writer output")

    # B12: the product's final signature is Xcode's CodeSign, not the phase's
    # ad-hoc one: another CDHash than the phase printed, the Info.plist bound,
    # resources sealed and the hardened runtime on (the phase signs none).
    finals = {}
    problems = []
    for name, bundle, ident in (("Release", RELEASE, "B3"), ("Distribution", DIST, "B4")):
        final = signature(bundle)
        final["phase_cdhash"] = builds.get(ident, {}).get("phase_cdhash")
        finals[name] = final
        if final["rc"] != 0 or not final["cdhash"]:
            problems.append(f"{name}: unreadable signature")
            continue
        if not final["phase_cdhash"]:
            problems.append(f"{name}: no phase CDHash in {ident}'s log")
        elif final["cdhash"] == final["phase_cdhash"]:
            problems.append(f"{name}: the final CDHash is the phase's")
        if not final["info_plist"] or "not bound" in final["info_plist"]:
            problems.append(f"{name}: Info.plist not bound")
        if not final["sealed_resources"]:
            problems.append(f"{name}: no sealed resources")
        if "runtime" not in (final["flags"] or ""):
            problems.append(f"{name}: no hardened runtime flag")
    row("B12", "pass" if not problems else "fail", finals,
        "; ".join(problems) or "each product's final signature is Xcode's: a new CDHash, Info.plist "
        "bound, resources sealed, runtime on (" + ", ".join(
            f"{n} {f['signature']} flags {f['flags']}" for n, f in finals.items()) + ")")


def score_b9(live_tools, source):
    snapshots = STATE.get("snapshots")
    if snapshots is None:
        parsed, raw, problem = read_snapshot(RELEASE)
        if problem:
            row("B9", "error", None, f"no Release snapshot: {problem}")
            return
        snapshots = {"Release": {"parsed": parsed, "raw": raw}}
    if live_tools is None:
        row("B9", "error", None, f"no live tools/list from {source}")
        return
    snapshot = snapshots["Release"]["parsed"]["tools"]
    equal = snapshot == live_tools
    same_bytes = compact(snapshot) == compact(live_tools)
    same_sorted = sorted_dump(snapshot) == sorted_dump(live_tools)
    row("B9", "pass" if equal else "fail",
        {"json_equal": equal, "compact_bytes_equal": same_bytes,
         "sorted_keys_bytes_equal": same_sorted, "tools": len(live_tools)},
        f"Release snapshot vs {source}'s tools/list: equal as JSON {equal}; compact "
        f"re-serialisation byte-equal {same_bytes}; with sorted keys {same_sorted}")


# ---------------------------------------------------------------- q2 launch


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def post(where, payload, timeout=1.0):
    """One POST to /mcp: `where` is a socket path (an instance since road map
    14's MC4) or a port (L0's control, where nothing listens)."""
    if isinstance(where, str):
        connection = mcp.UnixHTTPConnection(where, timeout=timeout)
    else:
        connection = http.client.HTTPConnection("127.0.0.1", where, timeout=timeout)
    try:
        connection.request("POST", "/mcp", json.dumps(payload),
                           {"Content-Type": "application/json",
                            "Accept": "application/json, text/event-stream"})
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


INITIALIZE = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                         "clientInfo": {"name": "mc1_spike", "version": "0"}}}


def initialized(port):
    try:
        status, body = post(port, INITIALIZE)
        return status == 200 and "result" in json.loads(body)
    except (OSError, ValueError, http.client.HTTPException):
        return False


def poll(port, started, bound, every=0.05, also=None):
    """Monotonic seconds from `started` to the first answered initialize, or
    None at the bound. `also` runs between polls (the pid watcher)."""
    while time.monotonic() - started < bound:
        if initialized(port):
            return round(time.monotonic() - started, 3)
        if also:
            also()
        time.sleep(every)
    return None


def ensure_windows_probe():
    if os.path.isfile(WINDOWS_PROBE) and os.path.getmtime(WINDOWS_PROBE) >= os.path.getmtime(WINDOWS_SOURCE):
        return None
    os.makedirs(WORK, exist_ok=True)
    result = run(["swiftc", "-O", WINDOWS_SOURCE, "-o", WINDOWS_PROBE], 600)
    return None if result["rc"] == 0 else f"windows_probe did not build: {describe(result)}"


def windows(pid):
    result = run([WINDOWS_PROBE, str(pid)], 30)
    try:
        return json.loads(result["stdout"])
    except ValueError:
        return {"error": describe(result)}


def processes():
    result = run(["ps", "-axo", "pid=,command="], 30)
    out = []
    for line in (result["stdout"] or "").splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            out.append((int(parts[0]), parts[1]))
    return out


def owned_pids(bundle):
    executable = str(proof_app.executable(bundle))
    return [pid for pid, command in processes() if executable in command and OWNED in command]


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def stop(pid):
    """SIGTERM to a pid the spike started, SIGKILL after 10 s."""
    commands = dict(processes())
    if OWNED not in commands.get(pid, ""):
        return "not ours: left alone"
    os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if not alive(pid):
            return "SIGTERM"
        time.sleep(0.1)
    os.kill(pid, signal.SIGKILL)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and alive(pid):
        time.sleep(0.1)
    return "SIGKILL"


def onscreen(snapshot):
    return [w for w in snapshot.get("windows", []) if w.get("onscreen")]


def launch(bundle, label, want_tools=False, bound=60.0):
    """One background launch: the time from just before `open` to the first
    answered initialize, the windows at the answer and at +2 s, then SIGTERM."""
    logs = os.path.join(WORK, "q2")
    os.makedirs(logs, exist_ok=True)
    log = os.path.join(logs, f"{label}.log")
    port = mcp.scratch_socket()
    before = windows(0)
    argv = ["open", "-n", "-g", "--env", f"RC_AGENT_SOCKET={port}", "--stderr", log, bundle,
            "--args", "-ApplePersistenceIgnoreState", "YES"]
    opened = {}

    def opener():
        opened.update(run(argv, bound + 10))

    started = time.monotonic()
    thread = threading.Thread(target=opener, daemon=True)
    thread.start()
    seen = {}
    last_look = [0.0]

    def watch():
        if "pid" in seen or time.monotonic() - last_look[0] < 0.5:
            return
        last_look[0] = time.monotonic()
        pids = owned_pids(bundle)
        if pids:
            seen["pid"] = pids[0]
            seen["seconds"] = round(time.monotonic() - started, 3)

    seconds = poll(port, started, bound, also=watch)
    thread.join(timeout=bound + 15)
    pids = owned_pids(bundle)
    if pids and "pid" not in seen:
        seen["pid"] = pids[0]
        seen["seconds"] = round(time.monotonic() - started, 3)
    result = {"label": label, "bundle": bundle, "port": port, "seconds": seconds,
              "open_rc": opened.get("rc"), "open_stderr": (opened.get("stderr") or "").strip()[-300:],
              "process_seen_s": seen.get("seconds"), "pid": seen.get("pid"),
              "front_before": before.get("front_pid"), "console": {
                  "on_console": before.get("on_console"), "locked": before.get("locked")}}
    if seconds is not None and seen.get("pid"):
        pid = seen["pid"]
        at_answer = windows(pid)
        if want_tools:
            try:
                status, body = post(port, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                                    timeout=30)
                result["tools"] = json.loads(body)["result"]["tools"] if status == 200 else None
            except (OSError, ValueError, KeyError, http.client.HTTPException):
                result["tools"] = None
        time.sleep(2)
        later = windows(pid)
        result["front_at_answer"] = at_answer.get("front_pid")
        result["front_at_plus2"] = later.get("front_pid")
        result["onscreen_at_answer"] = onscreen(at_answer)
        result["onscreen_at_plus2"] = onscreen(later)
    for pid in owned_pids(bundle):
        result.setdefault("stopped", []).append({"pid": pid, "how": stop(pid)})
    try:
        with open(log, encoding="utf-8", errors="replace") as handle:
            result["framejob_lines"] = [line for line in handle if "Frame Job: " in line]
    except OSError:
        result["framejob_lines"] = None
    mcp.remove_scratch(port)
    return result


def q2():
    q2_rows = QUESTION_ROWS["q2"]
    problem = ensure_windows_probe()
    if problem or not os.path.isfile(str(proof_app.executable(RELEASE))):
        reason = problem or f"no Release product at {RELEASE}: run q1 first"
        for ident in q2_rows:
            row(ident, "error", None, reason)
        return None

    host = windows(0)
    row("H0", "answered", {"on_console": host.get("on_console"), "locked": host.get("locked"),
                           "front_pid": host.get("front_pid")},
        f"on console {host.get('on_console')}, locked {host.get('locked')}")

    started = time.monotonic()
    control = poll(free_port(), started, 2.0)
    waited = round(time.monotonic() - started, 3)
    row("L0", "pass" if control is None else "fail", {"answered": control, "waited_s": waited},
        "CONTROL: a port nothing listens on expires at the 2 s bound")

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    launches = []
    cold = []
    for index in range(1, 4):
        bundle = os.path.join(WORK, "q2", f"cold-{stamp}-{index}", "Frame Job.app")
        copied = ditto(RELEASE, bundle)
        if copied["rc"] != 0:
            cold.append({"error": describe(copied)})
            continue
        cold.append(launch(bundle, f"cold-{stamp}-{index}"))
    launches += [c for c in cold if "error" not in c]
    figures = [c.get("seconds") for c in cold]
    if any(f is None for f in figures):
        row("L1", "fail", figures, "a cold launch did not answer within 60 s: "
            + "; ".join(str(c.get("error") or c.get("open_stderr")) for c in cold if c.get("seconds") is None))
    else:
        row("L1", "answered", figures,
            f"cold, each on a fresh ditto copy: {figures} s (no `purge`: it needs root)")

    warm_bundle = os.path.join(WORK, "q2", "warm", "Frame Job.app")
    copied = ditto(RELEASE, warm_bundle)
    live = None
    if copied["rc"] != 0:
        row("L2", "error", None, f"the warm copy failed: {describe(copied)}")
    else:
        prime = launch(warm_bundle, f"warm-{stamp}-prime")
        warm = [launch(warm_bundle, f"warm-{stamp}-{index}", want_tools=(index == 1))
                for index in range(1, 4)]
        launches += [prime] + warm
        live = warm[0].get("tools")
        figures = [w.get("seconds") for w in warm]
        row("L2", "fail" if any(f is None for f in figures) else "answered", figures,
            f"warm, three launches of one copy after an unscored priming launch "
            f"({prime.get('seconds')} s): {figures} s")

    quarantined = os.path.join(WORK, "q2", f"quarantine-{stamp}", "Frame Job.app")
    copied = ditto(RELEASE, quarantined)
    if copied["rc"] != 0:
        row("L3", "error", None, f"the quarantined copy failed: {describe(copied)}")
    else:
        flag = f"0081;{int(time.time()):08x};mc1_spike;"
        marked = run(["xattr", "-w", "-r", "com.apple.quarantine", flag, quarantined], 60)
        shown = run(["xattr", "-p", "com.apple.quarantine", quarantined], 30)
        assess = run(["spctl", "--assess", "--type", "execute", "-vv", quarantined], 60)
        result = launch(quarantined, f"quarantine-{stamp}")
        agents = [pid for pid, command in processes() if command.endswith("/CoreServicesUIAgent")
                  or "CoreServicesUIAgent.app/Contents/MacOS/CoreServicesUIAgent" in command]
        agent_windows = {str(pid): onscreen(windows(pid)) for pid in agents}
        value = {"xattr_rc": marked["rc"], "xattr": (shown["stdout"] or "").strip(),
                 "spctl_rc": assess["rc"],
                 "spctl": ((assess["stderr"] or "") + (assess["stdout"] or "")).strip(),
                 "process_appeared": result.get("pid") is not None or bool(result.get("stopped")),
                 "process_seen_s": result.get("process_seen_s"),
                 "answered_s": result.get("seconds"), "open_rc": result.get("open_rc"),
                 "open_stderr": result.get("open_stderr"),
                 "coreservicesuiagent_onscreen_windows": agent_windows,
                 "stopped": result.get("stopped")}
        launches.append(result)
        row("L3", "answered" if marked["rc"] == 0 else "error", value,
            f"spctl rc {assess['rc']}; process appeared {value['process_appeared']}; answered "
            f"{result.get('seconds')} s; CoreServicesUIAgent on-screen windows "
            f"{sum(len(w) for w in agent_windows.values())}")

    measured = [entry for entry in launches if entry.get("seconds") is not None]
    changed = [entry["label"] for entry in measured
               if entry.get("front_at_answer") != entry.get("front_before")
               or entry.get("front_at_plus2") != entry.get("front_before")]
    names = dict(processes())
    fronts = [{"label": e["label"], "framejob_pid": e.get("pid"),
               "before": e.get("front_before"), "at_answer": e.get("front_at_answer"),
               "at_plus2": e.get("front_at_plus2"),
               "framejob_frontmost": e.get("pid") in (e.get("front_at_answer"), e.get("front_at_plus2")),
               "front_commands": {str(p): os.path.basename(names.get(p, "?").split(" -")[0])
                                  for p in {e.get("front_before"), e.get("front_at_answer"),
                                            e.get("front_at_plus2")} if p}}
              for e in measured]
    row("L4", "pass" if measured and not changed else "fail",
        {"launches": len(measured), "front_changed": changed,
         "framejob_ever_frontmost": [f["label"] for f in fronts if f["framejob_frontmost"]],
         "fronts": fronts},
        f"frontmost pid unchanged at the answer and at +2 s in {len(measured) - len(changed)}"
        f"/{len(measured)} launches; Frame Job itself frontmost in "
        f"{sum(1 for f in fronts if f['framejob_frontmost'])}")
    row("L5", "answered",
        [{"label": e["label"], "at_answer": e.get("onscreen_at_answer"),
          "at_plus2": e.get("onscreen_at_plus2")} for e in measured],
        "Frame Job's on-screen windows per launch: "
        + ", ".join(f"{len(e.get('onscreen_at_answer') or [])}/{len(e.get('onscreen_at_plus2') or [])}"
                    for e in measured) + " (at the answer / at +2 s)")
    lines = {e["label"]: e.get("framejob_lines") for e in launches if e.get("framejob_lines")}
    unread = [e["label"] for e in launches if e.get("framejob_lines") is None]
    row("L6", "pass" if not lines and not unread else "fail", {"lines": lines, "unread": unread},
        f"no `Frame Job: ` line in {len(launches)} launch logs" if not lines and not unread
        else "a launch log holds a `Frame Job: ` line or could not be read")
    cold_figures = [c.get("seconds") for c in cold]
    if cold_figures and all(f is not None for f in cold_figures):
        worst = max(cold_figures)
        row("L7", "pass" if 3 * worst <= 60 else "fail",
            {"max_L1_s": worst, "three_times_s": round(3 * worst, 3)},
            f"3 × max(L1) = {round(3 * worst, 3)} s against the 60 s wait")
    else:
        row("L7", "fail", cold_figures, "a cold launch has no figure")
    return live


# ---------------------------------------------------------------- q3 client


class StubClient:
    """The runner as a stdio MCP client of `stub_mcp.py`: its own process
    group, killed at `bound` seconds whatever happens."""

    def __init__(self, mode, log, bound=40.0):
        self.child = subprocess.Popen([sys.executable, STUB, "--mode", mode, "--log", log],
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True, env=env(),
                                      start_new_session=True, bufsize=1)
        self.inbox = queue.Queue()
        self.received = []
        self.sent = []
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.killer = threading.Timer(bound, self.kill)
        self.killer.daemon = True
        self.killer.start()

    def _read(self):
        for line in self.child.stdout:
            try:
                message = json.loads(line)
            except ValueError:
                message = {"unparsed": line}
            self.inbox.put((time.monotonic(), message))

    def kill(self):
        try:
            os.killpg(self.child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def send(self, message):
        self.sent.append(message)
        self.child.stdin.write(json.dumps(message) + "\n")
        self.child.stdin.flush()
        return time.monotonic()

    def wait_for(self, predicate, seconds):
        deadline = time.monotonic() + seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            try:
                stamped = self.inbox.get(timeout=remaining)
            except queue.Empty:
                return None
            self.received.append(stamped)
            if predicate(stamped[1]):
                return stamped

    def request(self, ident, method, params=None, seconds=10):
        message = {"jsonrpc": "2.0", "id": ident, "method": method}
        if params is not None:
            message["params"] = params
        self.send(message)
        return self.wait_for(lambda m: m.get("id") == ident and "method" not in m, seconds)

    def close(self):
        try:
            self.child.stdin.close()
        except OSError:
            pass
        try:
            self.child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.kill()
            self.child.wait()
        self.killer.cancel()
        self.reader.join(timeout=5)


def is_changed(message):
    return message.get("method") == "notifications/tools/list_changed"


def names(stamped):
    try:
        return [tool["name"] for tool in stamped[1]["result"]["tools"]]
    except (TypeError, KeyError):
        return None


def logged_inbound(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return [json.loads(line)["message"] for line in handle
                    if json.loads(line).get("dir") == "in"]
    except (OSError, ValueError):
        return None


def open_session(client):
    reply = client.request(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                             "clientInfo": {"name": "mc1_spike", "version": "0"}})
    client.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    return reply


def q3():
    q3_dir = os.path.join(WORK, "q3")
    os.makedirs(q3_dir, exist_ok=True)

    claude = shutil.which("claude")
    if claude is None:
        row("C1", "skip", None, "host: claude not on PATH")
    else:
        result = run([claude, "--version"], 30)
        version = (result["stdout"] or "").strip()
        row("C1", "answered" if result["rc"] == 0 else "error", version,
            f"`claude --version` ({claude})" if result["rc"] == 0 else describe(result))

    page = os.path.join(q3_dir, "claude-code-mcp.html")
    if os.path.exists(page):
        os.remove(page)
    fetched = run(["curl", "-sL", "--max-time", "30", "-o", page, "-w", "%{http_code}", DOCS_URL], 45)
    code = (fetched["stdout"] or "").strip()
    if fetched["rc"] != 0 or code != "200" or not os.path.isfile(page):
        row("D1", "skip", {"rc": fetched["rc"], "http": code}, "host: no network")
    else:
        with open(page, encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
        visible = re.sub(r"(?is)<(script|style)\b.*?</\1>", " ", raw)
        visible = html.unescape(re.sub(r"(?s)<[^>]+>", " ", visible))
        visible = re.sub(r"\s+", " ", visible.replace("​", " "))
        sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z])", visible)
        quoted = []
        for sentence in sentences:
            sentence = sentence.strip()
            if "list_changed" in sentence and sentence not in quoted:
                quoted.append(sentence)
        row("D1", "answered" if quoted else "fail", {"url": DOCS_URL, "sentences": quoted},
            f"{len(quoted)} sentence(s) of {DOCS_URL} name list_changed" if quoted
            else f"fetched {DOCS_URL} but no sentence names list_changed")

    # T1 — during-call
    log = os.path.join(q3_dir, "t1-stub.jsonl")
    if os.path.exists(log):
        os.remove(log)
    client = StubClient("during-call", log)
    try:
        init = open_session(client)
        caps = (init or (0, {}))[1].get("result", {}).get("capabilities", {})
        first = client.request(2, "tools/list")
        before = len(client.received)
        call = client.request(3, "tools/call", {"name": "probe_wait", "arguments": {}}, seconds=15)
        during = [m for _, m in client.received[before:]]
        notified = [i for i, m in enumerate(during) if is_changed(m)]
        answered = [i for i, m in enumerate(during) if m.get("id") == 3]
        second = client.request(4, "tools/list")
    finally:
        client.close()
    inbound = logged_inbound(log)
    value = {
        "listChanged": caps.get("tools", {}).get("listChanged"),
        "first_list": names(first) if first else None,
        "notified_before_response": bool(notified and answered and notified[0] < answered[0]),
        "call_answered": call is not None,
        "second_list": names(second) if second else None,
        "log_holds_every_inbound": inbound == client.sent,
    }
    ok = (value["listChanged"] is True and value["first_list"] == ["probe_wait"]
          and value["notified_before_response"] and value["call_answered"]
          and value["second_list"] == ["probe_wait", "probe_new"] and value["log_holds_every_inbound"])
    row("T1", "pass" if ok else "fail", value,
        "stub during-call: listChanged, [probe_wait], the notification before the call's answer, "
        "both tools after, every inbound message logged")

    # T2 — unprompted
    log = os.path.join(q3_dir, "t2-stub.jsonl")
    if os.path.exists(log):
        os.remove(log)
    client = StubClient("unprompted", log)
    try:
        open_session(client)
        listed = client.request(2, "tools/list")
        note = client.wait_for(is_changed, 5)
        second = client.request(3, "tools/list") if note else None
    finally:
        client.close()
    delay = round(note[0] - listed[0], 3) if note and listed else None
    value = {"delay_s": delay, "second_list": names(second) if second else None}
    row("T2", "pass" if delay is not None and abs(delay - 2.0) <= 0.5 else "fail", value,
        f"stub unprompted: the notification {delay} s after the first tools/list answer (2 ± 0.5)")

    # T3 — silent (CONTROL)
    log = os.path.join(q3_dir, "t3-stub.jsonl")
    if os.path.exists(log):
        os.remove(log)
    client = StubClient("silent", log)
    try:
        open_session(client)
        client.request(2, "tools/list")
        note = client.wait_for(is_changed, 8)
    finally:
        client.close()
    row("T3", "pass" if note is None else "fail", {"notified": note is not None},
        "CONTROL: stub silent: the detector reports no notification within 8 s")

    # The manual checks' fixture (AC-1, AC-2): a scratch config, never registered anywhere.
    fixture = {"mcpServers": {"mc1-stub": {
        "command": sys.executable,
        "args": [STUB, "--mode", "during-call", "--log", os.path.join(q3_dir, "ac-stub.jsonl")]}}}
    save_text(os.path.join(q3_dir, "ac-mcp.json"), json.dumps(fixture, indent=2) + "\n")


# ---------------------------------------------------------------- the run


def z1():
    result = run(["pgrep", "-fl", "tools/proof/work/mc1_spike"], 30)
    left = (result["stdout"] or "").strip()
    row("Z1", "pass" if not left else "fail", left.splitlines(),
        "no process with tools/proof/work/mc1_spike in its command line" if not left
        else "processes left running")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", default=",".join(ORDER),
                        help="a comma list of q1..q4; the other rows carry forward")
    arguments = parser.parse_args(argv)
    chosen = [q.strip() for q in arguments.only.split(",") if q.strip()]
    unknown = [q for q in chosen if q not in QUESTION_ROWS]
    if unknown:
        parser.error(f"unknown question(s) {unknown}")
    os.makedirs(WORK, exist_ok=True)

    previous = {}
    if os.path.isfile(ANSWERS):
        try:
            with open(ANSWERS, encoding="utf-8") as handle:
                previous = json.load(handle).get("rows", {})
        except (OSError, ValueError):
            previous = {}
    carried = {}
    for question, idents in QUESTION_ROWS.items():
        if question in chosen:
            continue
        for ident in idents:
            if ident in previous and not (ident == "B9" and "q2" in chosen):
                carried[ident] = previous[ident]

    live = None
    for question in ORDER:
        if question not in chosen:
            continue
        print(f"== {question}", flush=True)
        if question == "q4":
            q4()
        elif question == "q1":
            q1()
            if "q2" not in chosen:
                bundle = os.path.join(WORK, "q1", "b9", "Frame Job.app")
                problem = ensure_windows_probe()
                copied = ditto(RELEASE, bundle)
                if problem or copied["rc"] != 0:
                    row("B9", "error", None, problem or describe(copied))
                else:
                    score_b9(launch(bundle, "b9", want_tools=True).get("tools"), "a b9 instance")
        elif question == "q2":
            live = q2()
            score_b9(live, "q2's first warm instance")
        elif question == "q3":
            q3()
    print("== Z1", flush=True)
    z1()

    for ident, entry in carried.items():
        ROWS.setdefault(ident, entry)
    ordered = {}
    for question in ORDER:
        for ident in QUESTION_ROWS[question]:
            if ident in ROWS:
                ordered[ident] = ROWS[ident]
    ordered["Z1"] = ROWS["Z1"]
    answers = {"date": datetime.datetime.now().isoformat(timespec="seconds"),
               "run": chosen, "carried": sorted(carried), "rows": ordered}
    save_text(ANSWERS, json.dumps(answers, indent=2, ensure_ascii=False) + "\n")

    counts = {}
    for entry in ordered.values():
        counts[entry["status"]] = counts.get(entry["status"], 0) + 1
    errors = [ident for ident, entry in ordered.items() if entry["status"] == "error"]
    print("digest: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))
          + f" of {len(ordered)} rows; ran {chosen}; carried {len(carried)}")
    if errors:
        print(f"errors: {errors}")
    print(f"answers: {ANSWERS}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
