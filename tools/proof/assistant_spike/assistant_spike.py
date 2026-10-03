#!/usr/bin/env python3
"""The assistant spike — road map 12, A0: the questions A1 cannot be designed
without, measured. No product code: the helper, its build step and a hook
exist only in a COPY of the tree under `work/assistant_spike/tree/`.

  B  the copy: Rasterize's `agent/` (renamed), the hook, the build step;
     `make app`, the Distribution build, the drag probe's build
  H  the helper signed as Rasterize signs it, in a Release and a
     Distribution bundle, launched under the hardened runtime — and the
     control that it needs its one entitlement
  C  the catalog's size: `catalogJSON()`, the first request, the tokens and
     the tool-search choice
  F  the stand-in's credential rule (R6-9(e))
  T  a scripted turn through the stand-in Messages server
  E  `export` onto a fresh path and onto an existing file
  D  an agent edit during a timeline drag (the drag probe)
  L  `ANTHROPIC_API_KEY` written nowhere

    python3 tools/proof/assistant_spike/assistant_spike.py [--only B,H,C,F,T,E,D,L]
                                                           [--rasterize ~/devel/rasterize]

Prints one line per row, `scores:` and `digest:`; writes
`work/assistant_spike/answers.json`. Exit 0: every row has a state and no
instrument or control row failed; 1: one did; 2: a row has no state.

Every child runs under `graphics_spike/bounded.py` (or, for a child the
runner talks to, a `Popen` in its own session) with THIS file's
`child_env()`, which pops `ANTHROPIC_API_KEY` as well as the AssemblyAI key;
only groups this runner started are ever killed. `ANTHROPIC_API_KEY` is read
in one function, `anthropic_key()`, and only its presence is printed.
"""

import argparse
import datetime
import difflib
import glob
import hashlib
import json
import os
import plistlib
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROOF = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(PROOF, "..", ".."))
sys.path.insert(0, os.path.join(PROOF, "graphics_spike"))
sys.path.insert(0, PROOF)
import bounded  # noqa: E402
import mcp  # noqa: E402
import tree_copy  # noqa: E402

WORK = os.path.join(PROOF, "work", "assistant_spike")
TREE = os.path.join(WORK, "tree")
RUNS = os.path.join(WORK, "runs")
PROBE = os.path.join(WORK, "probe")
ANSWERS = os.path.join(WORK, "answers.json")
FAKE = os.path.join(PROOF, "anthropic_fake.py")
HOOK = os.path.join(HERE, "AssistantSpikeHook.swift")
DRAG = os.path.join(HERE, "drag_probe.swift")
ROADMAP = os.path.join(ROOT, "archive", "reelcut-roadmap-12.md")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
PRODUCTS = os.path.join(TREE, "build", "Build", "Products")
APPS = {"r": os.path.join(PRODUCTS, "Release", "Reelcut.app"),
        "d": os.path.join(PRODUCTS, "Distribution", "Reelcut.app")}
HELPER = os.path.join("Contents", "Helpers", "reelcut-agent")
TICKS = 600_000
MODEL = "claude-opus-5-5"
SCRIPTED_TEXT = "A0 stand-in: the marker is in."
REDACTION = "<redacted: not an allow-listed dummy>"

# Rule H's walls, seconds.
WALL_BUILD, WALL_BUN, WALL_LAUNCH, WALL_TURN = 1500, 300, 60, 90
WALL_EXPORT, WALL_PROBE_BUILD, WALL_PROBE_RUN = 300, 900, 180

# (ID, group, kind, what a pass means)
ROWS = [
    ("B1", "B", "I", "Rasterize's agent/ is copied"),
    ("B2", "B", "A", "bun install --frozen-lockfile passes after the rename"),
    ("B3", "B", "I", "the tree copy is made, every anchor found exactly once"),
    ("B4", "B", "I", "the copy's make app produces its binary"),
    ("B5", "B", "I", "the copy's Distribution xcodebuild produces its binary"),
    ("B6", "B", "I", "the drag probe builds"),
    ("H1r", "H", "A", "the Release helper is signed runtime + exactly allow-jit"),
    ("H1d", "H", "A", "the Distribution helper is signed runtime + exactly allow-jit"),
    ("H2r", "H", "A", "the Release app verifies strictly, runtime, exactly audio-input"),
    ("H2d", "H", "A", "the Distribution app verifies strictly, runtime, exactly audio-input"),
    ("H2t", "H", "A", "the tree's own build/ Release and Distribution apps carry the copy's entitlements"),
    ("H3", "H", "C", "the tree's dist_check.py scores full marks on the copy's two builds"),
    ("H4r", "H", "A", "the Release copy binds, parity is clean, its helper answers ready"),
    ("H4d", "H", "A", "the Distribution copy binds, parity is clean, its helper answers ready"),
    ("H5", "H", "C", "the H1r helper, launched by the runner, reaches ready within 20 s"),
    ("H6", "H", "A", "re-signed with no entitlements, the helper does not reach ready in 20 s"),
    ("C1r", "C", "A", "the Release catalogJSON() size"),
    ("C1d", "C", "A", "the Distribution catalogJSON() size"),
    ("C2", "C", "A", "run d's first POST: body, tools, tools array"),
    ("C3", "C", "A", "the assistant catalog's tokens and the tool-search choice"),
    ("F1", "F", "C", "a non-dummy credential is refused, a failure, and written nowhere"),
    ("T1r", "T", "A", "run r's stand-in log: 1 models GET, 2 messages POSTs, dummy only"),
    ("T1d", "T", "A", "run d's stand-in log: 1 models GET, 2 messages POSTs, dummy only"),
    ("T2r", "T", "A", "run r's hook: tool_request, tool_result, text, turn_finished"),
    ("T2d", "T", "A", "run d's hook: tool_request, tool_result, text, turn_finished"),
    ("T3r", "T", "A", "run r's project holds the marker"),
    ("T3d", "T", "A", "run d's project holds the marker"),
    ("E1", "E", "C", "export to a fresh path writes a movie"),
    ("E2", "E", "A", "export onto an existing file replaces it without asking"),
    ("D1", "D", "C", "add_marker with no gesture lands"),
    ("D2", "D", "A", "add_marker made mid-drag survives the drag"),
    ("L1", "L", "C", "ANTHROPIC_API_KEY's bytes are in no file the spike or build wrote"),
]
GROUPS = "BHCFTEDL"


# ---------------------------------------------------------------------------
# Keys and children.


def child_env(extra=None):
    """`bounded.child_env(extra)` with `ANTHROPIC_API_KEY` popped as well:
    every child gets exactly this, passed explicitly. `pop` never binds the
    value to a name."""
    env = bounded.child_env(extra)
    env.pop("ANTHROPIC_API_KEY", None)
    return env


def anthropic_key():
    """The ONE read of `ANTHROPIC_API_KEY` (C3's count and L1's search).
    Nothing that holds its answer is ever printed or written."""
    return os.environ.get("ANTHROPIC_API_KEY") or None


def run(argv, seconds, cwd=None, extra=None):
    return bounded.run(argv, seconds, cwd=cwd, env=child_env(extra))


def kill_group(child, grace=5.0):
    if child is None or child.poll() is not None:
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            return
        try:
            child.wait(timeout=grace)
            return
        except subprocess.TimeoutExpired:
            continue


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def sha256_file(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


# ---------------------------------------------------------------------------
# B — the copy and its builds.


def rasterize_facts(rasterize):
    agent = os.path.join(rasterize, "agent")
    head = run(["git", "-C", rasterize, "rev-parse", "HEAD"], 60)
    dirty = run(["git", "-C", rasterize, "status", "--porcelain", "--", "agent"], 60)
    sources = {os.path.basename(p): sha256_file(p)
               for p in sorted(glob.glob(os.path.join(agent, "src", "*.ts")))}
    lock = open(os.path.join(agent, "bun.lock")).read() if os.path.exists(
        os.path.join(agent, "bun.lock")) else ""
    sdk = re.search(r'"@anthropic-ai/sdk": \["@anthropic-ai/sdk@([^"]+)"', lock)
    bun = run(["bun", "--version"], 60)
    return {"head": head["stdout"].strip(), "head_rc": head["rc"],
            "agent_dirty": bool(dirty["stdout"].strip()), "agent_status_rc": dirty["rc"],
            "src_sha256": sources, "sdk": sdk.group(1) if sdk else None,
            "bun": bun["stdout"].strip() or bun["stderr"].strip()[-120:]}


def replace_once(text, old, new, anchors, label):
    count = text.count(old)
    anchors[label] = count
    return text.replace(old, new) if count == 1 else text


def make_tree(rasterize):
    """The copy, `tree_copy.make_copy(TREE, agent=False)`, made fresh every
    run with its `build/`: a kept `build/` fails the next build, because
    xcodegen rewrites `app/Reelcut.entitlements` and Xcode refuses an
    entitlements file "modified during the build". Answers (anchors,
    agent_copied, error)."""
    anchors = {}
    made, reason = tree_copy.make_copy(TREE, agent=False)
    if made is None:
        return anchors, False, reason
    try:
        # agent/: Rasterize's files, renamed.
        source = os.path.join(rasterize, "agent")
        agent = os.path.join(TREE, "agent")
        os.makedirs(os.path.join(agent, "src"))
        for one in ("package.json", "bun.lock", "tsconfig.json", "entitlements.plist",
                    os.path.join("src", "main.ts"), os.path.join("src", "protocol.ts")):
            shutil.copy2(os.path.join(source, one), os.path.join(agent, one))
        agent_copied = True
        package = open(os.path.join(agent, "package.json")).read()
        package = replace_once(package, '"name": "rasterize-agent"', '"name": "reelcut-agent"',
                               anchors, "package.json name")
        package = replace_once(package, "--outfile ../build/agent/rasterize-agent",
                               "--outfile ../build/agent/reelcut-agent", anchors,
                               "package.json outfile")
        open(os.path.join(agent, "package.json"), "w").write(package)
        lock = open(os.path.join(agent, "bun.lock")).read()
        lock = replace_once(lock, '"name": "rasterize-agent",', '"name": "reelcut-agent",',
                            anchors, "bun.lock root workspace")
        open(os.path.join(agent, "bun.lock"), "w").write(lock)

        # The hook and its one call.
        shutil.copy2(HOOK, os.path.join(TREE, "app", "Sources", "AssistantSpikeHook.swift"))
        delegate_path = os.path.join(TREE, "app", "Sources", "AppDelegate.swift")
        delegate = open(delegate_path).read()
        block = ("        if UserDefaults.standard.bool(forKey: AgentServer.enabledDefaultsKey) {\n"
                 "            startAgentServer()\n"
                 "        }\n")
        delegate = replace_once(delegate, block,
                                block + "        AssistantSpikeHook.startIfAsked()\n",
                                anchors, "AppDelegate enabledDefaultsKey block")
        open(delegate_path, "w").write(delegate)

        # The build step: Rasterize's project.yml:173-190, renamed.
        lines = open(os.path.join(rasterize, "project.yml")).read().split("\n")
        step_lines = lines[172:190]
        anchors["rasterize project.yml:173 is the step"] = int(
            step_lines[0].strip() == "- name: Build Agent Helper")
        anchors["rasterize project.yml:190 is its last line"] = int(
            step_lines[-1].strip().startswith("--sign"))
        step = "\n".join(step_lines)
        anchors["step's rasterize-agent spellings (2)"] = int(step.count("rasterize-agent") == 2)
        step = step.replace("rasterize-agent", "reelcut-agent")
        yml_path = os.path.join(TREE, "project.yml")
        yml = open(yml_path).read()
        # The copy's own agent step goes first, so Rasterize's is the one.
        start = "      # The assistant's agent helper (agent/, spec §11 AI-1): compiled with\n"
        end = '        script: /bin/sh "$PROJECT_DIR/agent/build.sh" helper\n'
        at = yml.find(start)
        until = yml.find(end, at) if at >= 0 else -1
        if at >= 0 and until >= 0:
            yml = replace_once(yml, yml[at:until + len(end)], "", anchors,
                               "project.yml's own Build Agent Helper item")
        else:
            anchors["project.yml's own Build Agent Helper item"] = 0
        yml = replace_once(yml, "\nschemes:\n", "\n" + step + "\n\nschemes:\n", anchors,
                           "project.yml schemes:")
        # `schemes:` must follow the last postBuildScripts item for the step
        # to be the last item.
        anchors["project.yml step follows Copy Graphic Templates"] = int(
            yml.find("name: Copy Graphic Templates") < yml.find("name: Build Agent Helper"))
        anchors["one Build Agent Helper step"] = int(yml.count("name: Build Agent Helper") == 1)
        open(yml_path, "w").write(yml)
    except (OSError, IndexError) as error:
        return anchors, locals().get("agent_copied", False), f"{type(error).__name__}: {error}"
    return anchors, True, None


def bun_install():
    agent = os.path.join(TREE, "agent")
    lock_path = os.path.join(agent, "bun.lock")
    before = open(lock_path).read()
    frozen = run(["bun", "install", "--frozen-lockfile"], WALL_BUN, cwd=agent)
    record = {"frozen_rc": frozen["rc"], "frozen_seconds": frozen["seconds"],
              "frozen_expired": frozen["expired"],
              "frozen_tail": (frozen["stderr"] + frozen["stdout"]).strip()[-400:]}
    if frozen["rc"] == 0:
        return True, record
    plain = run(["bun", "install"], WALL_BUN, cwd=agent)
    after = open(lock_path).read()
    record.update(plain_rc=plain["rc"], plain_seconds=plain["seconds"],
                  lock_diff=list(difflib.unified_diff(before.splitlines(), after.splitlines(),
                                                      "bun.lock (renamed)", "bun.lock (after)",
                                                      lineterm=""))[:80])
    return False, record


def error_lines(result):
    text = result["stdout"] + "\n" + result["stderr"]
    errors = [line.strip() for line in text.splitlines() if "error:" in line]
    return errors[:8] or [line for line in text.strip().splitlines()[-6:]]


def build_app(kind):
    """`make app` (r) or the Makefile's Distribution line (d), in the copy."""
    app = APPS[kind]
    tree_copy.remove_tree(app)
    if kind == "r":
        argv = ["make", "app"]
    else:
        argv = ["xcodebuild", "-project", "Reelcut.xcodeproj", "-scheme", "Reelcut",
                "-configuration", "Distribution", "-derivedDataPath", "build", "build"]
    print(f"build {kind}: {' '.join(argv)} (up to {WALL_BUILD} s)…", flush=True)
    built = run(argv, WALL_BUILD, cwd=TREE)
    binary = os.path.join(app, "Contents", "MacOS", "Reelcut")
    ok = built["rc"] == 0 and os.path.exists(binary)
    record = {"argv": argv, "rc": built["rc"], "seconds": built["seconds"],
              "expired": built["expired"], "binary": os.path.exists(binary)}
    if not ok:
        record["errors"] = error_lines(built)
    print(f"build {kind}: rc {built['rc']} in {built['seconds']:.0f} s", flush=True)
    return ok, record


def build_probe():
    os.makedirs(PROBE, exist_ok=True)
    entry = os.path.join(PROBE, "main.swift")
    shutil.copyfile(DRAG, entry)
    binary = os.path.join(PROBE, "drag_probe")
    if os.path.exists(binary):
        os.remove(binary)
    if not os.path.exists(LIB):
        return None, {"error": f"{LIB} is missing — run `cd core && cargo build --release`"}
    sources = os.path.join(ROOT, "app", "Sources")
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    argv = (["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
             "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
             "-import-objc-header", os.path.join(ROOT, "app", "Bridging",
                                                  "Reelcut-Bridging-Header.h"),
             "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary])
    print(f"probe: building (up to {WALL_PROBE_BUILD} s)…", flush=True)
    built = run(argv, WALL_PROBE_BUILD)
    record = {"rc": built["rc"], "seconds": built["seconds"], "expired": built["expired"],
              "sources": len(swift)}
    if built["rc"] != 0 or not os.path.exists(binary):
        record["errors"] = [l for l in built["stderr"].splitlines() if ": error:" in l][:8]
        return None, record
    fonts = os.path.join(PROBE, "Fonts")
    shutil.rmtree(fonts, ignore_errors=True)
    shutil.copytree(os.path.join(ROOT, "app", "Resources", "Fonts"), fonts)
    print(f"probe: built in {built['seconds']:.0f} s", flush=True)
    return binary, record


# ---------------------------------------------------------------------------
# H — signatures and launches.


def codesign_facts(path):
    shown = run(["codesign", "-dv", path], 60)
    flags = re.search(r"flags=0x[0-9a-f]+\(([^)]*)\)", shown["stderr"])
    ents = run(["codesign", "-d", "--entitlements", "-", "--xml", path], 60)
    entitlements = None
    raw = ents["stdout"].strip()
    if ents["rc"] == 0:
        if not raw:
            entitlements = {}
        else:
            try:
                start = raw.find("<?xml")
                entitlements = plistlib.loads(raw[start if start >= 0 else 0:].encode())
            except Exception as error:  # noqa: BLE001 — recorded, not raised
                entitlements = {"<unreadable>": str(error)}
    return {"rc": shown["rc"], "flags": flags.group(1).split(",") if flags else [],
            "entitlements": entitlements,
            "size": os.path.getsize(path) if os.path.exists(path) else None}


def helper_row(kind):
    helper = os.path.join(APPS[kind], HELPER)
    if not os.path.exists(helper):
        return "fail", f"no helper at {os.path.relpath(helper, WORK)}", {}
    facts = codesign_facts(helper)
    ok = ("runtime" in facts["flags"]
          and facts["entitlements"] == {"com.apple.security.cs.allow-jit": True})
    return ("pass" if ok else "fail",
            f"{facts['size']} bytes ({facts['size'] / 1e6:.1f} MB); flags "
            f"{','.join(facts['flags'])}; entitlements {facts['entitlements']}", facts)


def app_signature_row(kind):
    app = APPS[kind]
    if not os.path.exists(app):
        return "fail", "no app", {}
    verify = run(["codesign", "--verify", "--strict", "--deep", app], 120)
    facts = codesign_facts(app)
    facts["verify_rc"] = verify["rc"]
    facts["verify_stderr"] = verify["stderr"].strip()[-300:]
    ok = (verify["rc"] == 0 and "runtime" in facts["flags"]
          and facts["entitlements"] == {"com.apple.security.device.audio-input": True})
    return ("pass" if ok else "fail",
            f"verify --strict --deep rc {verify['rc']}; flags {','.join(facts['flags'])}; "
            f"entitlements {facts['entitlements']}", facts)


TREE_APPS = {"r": os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app"),
             "d": os.path.join(ROOT, "build", "Build", "Products", "Distribution",
                               "Reelcut.app")}


def tree_signature_row(built):
    """Whether H2's entitlements predate the spike: the tree's OWN build/
    products (never built by this runner; it only reads them) against the
    copy's. A tree without both products is a skip, not an answer."""
    measured = {}
    for kind in ("r", "d"):
        app = TREE_APPS[kind]
        binary = os.path.join(app, "Contents", "MacOS", "Reelcut")
        if not os.path.exists(binary):
            return "skip", f"host: no tree build at {app}", {"missing": app}
        measured[kind] = {
            "tree": codesign_facts(app)["entitlements"],
            "tree_binary_mtime": datetime.datetime.fromtimestamp(
                os.path.getmtime(binary)).isoformat(timespec="seconds"),
            "copy": codesign_facts(APPS[kind])["entitlements"] if built[kind] else None}
    same = all(m["copy"] is not None and m["tree"] == m["copy"] for m in measured.values())
    return ("pass" if same else "fail",
            "; ".join(f"{k}: tree {sorted((m['tree'] or {}).keys())} (binary "
                      f"{m['tree_binary_mtime']}), copy {sorted((m['copy'] or {}).keys())}"
                      for k, m in measured.items()), measured)


def launch_helper_bare(path, seconds=20):
    """The helper with the three-variable environment and a configure (the
    dummy key, `api_base http://127.0.0.1:9`). Answers (reached ready,
    measurement)."""
    env = {"HOME": os.environ.get("HOME", ""),
           "TMPDIR": os.environ.get("TMPDIR", "/tmp/"), "PATH": "/usr/bin:/bin"}
    started = time.monotonic()
    try:
        child = subprocess.Popen([path], env=env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 start_new_session=True)
    except OSError as error:
        return False, {"error": f"{type(error).__name__}: {error}"}
    lines, errors = [], []

    def read(stream, into):
        for line in stream:
            into.append(line.decode("utf-8", "replace").rstrip("\n"))
    readers = [threading.Thread(target=read, args=(child.stdout, lines), daemon=True),
               threading.Thread(target=read, args=(child.stderr, errors), daemon=True)]
    for reader in readers:
        reader.start()
    configure = {"type": "configure", "api_key": "proof-key", "model": MODEL,
                 "system": "Reelcut A0 spike.", "tools": [],
                 "api_base": "http://127.0.0.1:9",
                 "settings": {"auto_compact_tokens": None, "clear_tool_results": False}}
    try:
        child.stdin.write((json.dumps(configure) + "\n").encode())
        child.stdin.flush()
    except OSError:
        pass
    ready = False
    ready_seconds = None
    while time.monotonic() - started < seconds:
        if any('"type":"ready"' in l.replace(" ", "") for l in lines):
            ready = True
            ready_seconds = round(time.monotonic() - started, 3)
            break
        if child.poll() is not None:
            time.sleep(0.2)
            ready = any('"type":"ready"' in l.replace(" ", "") for l in lines)
            break
        time.sleep(0.05)
    exited = child.poll()
    kill_group(child, grace=2.0)
    for reader in readers:
        reader.join(timeout=2)
    return ready, {"ready": ready, "ready_seconds": ready_seconds,
                   "exit_status": exited, "first_stderr": errors[0] if errors else None,
                   "stdout_lines": lines[:5]}


# ---------------------------------------------------------------------------
# The runs: the copy app, the stand-in, the hook, a scripted turn.


def t_scenario(project_path):
    return {"max_input_tokens": 1_000_000, "replies": [
        {"content": [{"type": "tool_use", "id": "toolu_a0_1", "name": "add_marker",
                      "input": {"project": project_path, "at": 1_200_000,
                                "name": "A0 spike"}}],
         "stop_reason": "tool_use"},
        {"content": [{"type": "text", "text": SCRIPTED_TEXT}], "stop_reason": "end_turn"}]}


def start_fake(folder):
    os.makedirs(folder, exist_ok=True)
    err = open(os.path.join(folder, "fake.stderr"), "w")
    child = subprocess.Popen([sys.executable, FAKE, "--dir", folder], env=child_env(),
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=err,
                             text=True, start_new_session=True)
    err.close()
    line = child.stdout.readline().strip()
    if not line.startswith("port "):
        kill_group(child)
        raise RuntimeError(f"the stand-in printed {line!r}, not a port")
    return child, int(line.split()[1])


def http(method, url, body=None, headers=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method,
                                     headers=dict({"content-type": "application/json"},
                                                  **(headers or {})))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def read_jsonl(path):
    out = []
    if not os.path.exists(path):
        return out
    for line in open(path, errors="replace"):
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except ValueError:
                out.append({"event": "unparsable", "line": line[:200]})
    return out


def helper_processes(path, parent=None):
    """Pids whose command line matches `path`; with `parent`, only that
    pid's direct children. The cleanup uses the second form, so it can only
    ever touch a helper the app THIS runner started launched."""
    argv = ["pgrep"] + (["-P", str(parent)] if parent is not None else []) + ["-f", path]
    found = run(argv, 30)
    return [int(p) for p in found["stdout"].split()]


def one_run(kind):
    """A whole run against the copy's `kind` build. Answers a dict of
    measurements; never raises."""
    app = APPS[kind]
    folder = os.path.join(RUNS, kind)
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    project_path = os.path.join(folder, "a0.reelcut")
    hook_log = os.path.join(folder, "hook.jsonl")
    record = {"folder": folder, "project": project_path}
    binary = os.path.join(app, "Contents", "MacOS", "Reelcut")
    if not os.path.exists(binary):
        record["error"] = "no app binary"
        return record
    fake, child, sock = None, None, None
    try:
        # (1) the stand-in, and the T scenario before anything can ask.
        fake, fake_port = start_fake(os.path.join(folder, "fake"))
        base = f"http://127.0.0.1:{fake_port}"
        status, _ = http("POST", base + "/__control/scenario", t_scenario(project_path))
        record["scenario_status"] = status
        # (2) the app, with screens.py's argv and a fresh secret folder.
        secrets = os.path.join(folder, "secrets")
        os.makedirs(secrets)
        sock = mcp.scratch_socket()
        argv = [binary, "-ApplePersistenceIgnoreState", "YES",
                "-RCSecretFolder", secrets, "-RCAssemblyAIEndpoint", "http://127.0.0.1:9",
                "-NSRecentDocumentsLimit", "0", "-RCAssistantSpikeLog", hook_log]
        env = child_env({"RC_AGENT_SOCKET": sock, "RC_ASSISTANT_BASE_URL": base})
        log_path = os.path.join(folder, "app.log")
        handle = open(log_path, "w")
        child = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=handle,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        handle.close()
        # (3) the bound socket.
        listening = mcp.wait_listening(log_path, sock, child=child, seconds=WALL_LAUNCH)
        bound = sock if listening else None
        record["bound"] = bound
        if bound is None:
            record["error"] = f"no socket within {WALL_LAUNCH} s (exit {child.poll()})"
            return record
        client = mcp.MCP(bound, timeout=WALL_EXPORT)
        # (4) the project the hook waits for.
        created = client.call("new_project", path=project_path)
        record["new_project"] = isinstance(created, dict) and "saved" in created
        # (5) the hook's end.
        deadline = time.monotonic() + 60 + WALL_TURN + 15
        events = []
        while time.monotonic() < deadline:
            events = read_jsonl(hook_log)
            if any(e.get("event") in ("done", "timeout", "launch_failed", "catalog_failed")
                   for e in events):
                break
            time.sleep(0.25)
        time.sleep(0.5)
        record["hook"] = read_jsonl(hook_log)
        # T3.
        state = client.call("get_project", project=project_path)
        project = state.get("project", {}) if isinstance(state, dict) else {}
        record["markers"] = project.get("markers", [])
        # E (run r only).
        if kind == "r":
            record["export"] = exports(client, folder, project_path)
        record["app_log_parity"] = [l for l in open(log_path, errors="replace")
                                    if "Reelcut: " in l]
        status, raw = http("GET", base + "/__control/log")
        record["fake_log"] = json.loads(raw) if status == 200 else {"status": status}
    except Exception as error:  # noqa: BLE001 — a run's failure is its rows' failure
        record["error"] = f"{type(error).__name__}: {error}"
    finally:
        helper_path = os.path.join(app, HELPER)
        # The app's own helpers, named BEFORE the app goes: once it is gone
        # they are reparented to launchd and nothing ties them to this run.
        # A helper-path process that is not the app's child is recorded and
        # never signalled.
        ours = helper_processes(helper_path, parent=child.pid) if child is not None else []
        record["helpers_ours"] = ours
        kill_group(child)
        kill_group(fake)
        mcp.remove_scratch(sock)
        time.sleep(1.0)
        running = set(helper_processes(helper_path))
        left = [pid for pid in ours if pid in running]
        record["helpers_left"] = left
        record["helpers_foreign"] = sorted(running - set(ours))
        for pid in left:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if left:
            time.sleep(0.5)
        still = set(helper_processes(helper_path))
        record["helpers_after_kill"] = [pid for pid in ours if pid in still]
    return record


def exports(client, folder, project_path):
    out = {}
    try:
        client.call("add_text_clip", project=project_path, track=1, at=0,
                    duration=1_200_000)
        fresh = os.path.join(folder, "e1.mp4")
        started = time.monotonic()
        result = client.call("export", project=project_path, preset="h264", path=fresh)
        out["e1_seconds"] = round(time.monotonic() - started, 1)
        out["e1_result"] = result if isinstance(result, dict) else str(result)[:400]
        head = open(fresh, "rb").read(12) if os.path.exists(fresh) else b""
        out["e1_ftyp"] = head[4:8] == b"ftyp"
        out["e1_bytes"] = os.path.getsize(fresh) if os.path.exists(fresh) else None
    except Exception as error:  # noqa: BLE001
        out["e1_error"] = f"{type(error).__name__}: {error}"
    try:
        existing = os.path.join(folder, "e2.mp4")
        with open(existing, "wb") as f:
            f.write(b"A0-SENTINEL\n")
        try:
            result = client.call("export", project=project_path, preset="h264", path=existing)
            out["e2_error"] = False
        except mcp.ToolError as error:
            result = str(error)
            out["e2_error"] = True
        text = json.dumps(result) if isinstance(result, dict) else str(result)
        out["e2_result_text"] = text[:600]
        body = open(existing, "rb").read() if os.path.exists(existing) else b""
        out["e2_still_sentinel"] = body == b"A0-SENTINEL\n"
        out["e2_ftyp"] = body[4:8] == b"ftyp"
        out["e2_bytes"] = len(body)
    except Exception as error:  # noqa: BLE001
        out["e2_exception"] = f"{type(error).__name__}: {error}"
    return out


# ---------------------------------------------------------------------------
# Scoring the runs.


def hook_row(kind, runrec):
    if runrec is None:
        return "fail", "the run did not happen", {}
    hook = runrec.get("hook", [])
    ready = any(e.get("event") == "from_helper" and isinstance(e.get("message"), dict)
                and e["message"].get("type") == "ready" for e in hook)
    ok = (runrec.get("bound") is not None and not runrec.get("app_log_parity")
          and ready)
    events = [e.get("event") for e in hook if e.get("event") != "from_helper"]
    return ("pass" if ok else "fail",
            f"port {runrec.get('bound')}; parity lines {len(runrec.get('app_log_parity', []))}; "
            f"helper ready {ready}; hook events {events}"
            + (f"; error {runrec['error']}" if runrec.get("error") else ""),
            {"bound": runrec.get("bound"), "parity": runrec.get("app_log_parity", []),
             "ready": ready, "events": events})


def catalog_row(runrec):
    if runrec is None:
        return "fail", "the run did not happen", {}
    for e in runrec.get("hook", []):
        if e.get("event") == "catalog":
            return ("pass", f"catalogJSON() {e['bytes']} bytes, {e['tools']} tools",
                    {"bytes": e["bytes"], "tools": e["tools"]})
    return "fail", "the hook logged no catalog", {}


def messages_posts(runrec):
    requests = (runrec or {}).get("fake_log", {}).get("requests", [])
    return [r for r in requests
            if r.get("method") == "POST" and r.get("path", "").split("?")[0] == "/v1/messages"]


def t1_row(runrec):
    if runrec is None or "fake_log" not in runrec:
        return "fail", "no stand-in log" + (f": {runrec.get('error')}" if runrec else ""), {}
    log = runrec["fake_log"]
    requests = log.get("requests", [])
    gets = [r for r in requests if r.get("method") == "GET"
            and r.get("path", "").split("?")[0] == f"/v1/models/{MODEL}"]
    posts = messages_posts(runrec)
    credentials = sorted({r["headers"].get(h) for r in requests
                          for h in ("x-api-key", "authorization") if h in r.get("headers", {})})
    ok = (len(gets) == 1 and len(posts) == 2 and credentials == ["proof-key"]
          and not log.get("failures") and len(requests) == 3)
    return ("pass" if ok else "fail",
            f"{len(requests)} requests: {len(gets)} GET /v1/models/{MODEL}, {len(posts)} "
            f"POST /v1/messages ({', '.join(r['path'] for r in posts)}); credentials "
            f"{credentials}; failures {log.get('failures')}",
            {"requests": len(requests), "gets": len(gets), "posts": len(posts),
             "credentials": credentials, "failures": log.get("failures")})


def t2_row(runrec):
    if runrec is None:
        return "fail", "the run did not happen", {}
    messages = [e["message"] for e in runrec.get("hook", [])
                if e.get("event") == "from_helper" and isinstance(e.get("message"), dict)]
    types = [m.get("type") for m in messages]

    def first(predicate, after=-1):
        for i, m in enumerate(messages):
            if i > after and predicate(m):
                return i
        return None
    a = first(lambda m: m.get("type") == "tool_request" and m.get("name") == "add_marker")
    b = first(lambda m: m.get("type") == "tool_result" and m.get("is_error") is False,
              a if a is not None else 10**9)
    text = "".join(m.get("text", "") for m in messages[(b or 0):]
                   if m.get("type") == "text_delta") if b is not None else ""
    c = first(lambda m: m.get("type") == "turn_finished", b if b is not None else 10**9)
    posts = messages_posts(runrec)
    carried = False
    if len(posts) >= 2 and isinstance(posts[1].get("body"), dict):
        for message in posts[1]["body"].get("messages", []):
            content = message.get("content")
            if isinstance(content, list):
                carried = carried or any(
                    isinstance(block, dict) and block.get("type") == "tool_result"
                    and block.get("tool_use_id") == "toolu_a0_1" for block in content)
    ok = a is not None and b is not None and c is not None and text == SCRIPTED_TEXT and carried
    summary = next((m.get("summary") for m in messages if m.get("type") == "tool_result"), None)
    return ("pass" if ok else "fail",
            f"tool_request at {a}, tool_result is_error false at {b}, text "
            f"{text!r}, turn_finished at {c}; second POST carries toolu_a0_1's tool_result "
            f"{carried}; helper events {types}",
            {"order": [a, b, c], "text": text, "carried": carried, "types": types,
             "tool_result_summary": (summary or "")[:300]})


def t3_row(runrec):
    if runrec is None:
        return "fail", "the run did not happen", {}
    markers = runrec.get("markers", [])
    hit = [m for m in markers if m.get("time") == 1_200_000 and m.get("name") == "A0 spike"]
    return ("pass" if hit else "fail", f"markers {markers}", {"markers": markers})


def c2_measure(runrec):
    posts = messages_posts(runrec)
    if not posts or not isinstance(posts[0].get("body"), dict):
        return None
    body = posts[0]["body"]
    tools = body.get("tools", [])
    compact = json.dumps(tools, separators=(",", ":"), ensure_ascii=False).encode()
    deferred = sum(1 for t in tools if t.get("defer_loading"))
    return {"body_bytes": posts[0]["bytes"], "tools": len(tools),
            "tools_bytes": len(compact), "deferred": deferred,
            "not_deferred": [t.get("name") for t in tools if not t.get("defer_loading")],
            "tools_list": tools}


def c3(c2):
    """The assistant catalog's tokens, counted with the key or estimated."""
    tools = [dict((k, v) for k, v in t.items() if k != "defer_loading")
             for t in c2["tools_list"]
             if not str(t.get("type", "")).startswith("tool_search_tool")
             and t.get("name") != "record_screen"]
    size = len(json.dumps(tools, separators=(",", ":"), ensure_ascii=False).encode())
    record = {"tools": len(tools), "bytes": size, "key": "absent"}
    key = anthropic_key()
    if key:
        record["key"] = "present"

        def count(with_tools):
            body = {"model": MODEL, "messages": [{"role": "user", "content": "A0"}]}
            if with_tools:
                body["tools"] = tools
            status, raw = http("POST", "https://api.anthropic.com/v1/messages/count_tokens",
                               body, {"x-api-key": key, "anthropic-version": "2023-06-01"},
                               timeout=60)
            if status != 200:
                return None, status
            return json.loads(raw).get("input_tokens"), status
        try:
            with_t, s1 = count(True)
            without, s2 = count(False)
            record["count_status"] = [s1, s2]
            if with_t is not None and without is not None:
                record["tokens"] = with_t - without
        except Exception as error:  # noqa: BLE001 — the message holds no header
            record["count_status"] = type(error).__name__
    if "tokens" in record:
        tokens = record["tokens"]
        choice = "all tools up front" if tokens <= 10000 else "tool search with a core set"
        record["choice"] = choice
        return record, f"{tokens} tokens counted ({len(tools)} tools, {size} bytes): {choice}"
    low, high = size / 4, size / 2.5
    record["estimate"] = [round(low), round(high)]
    if high <= 10000:
        choice = "all tools up front"
    elif low > 10000:
        choice = "tool search with a core set"
    else:
        choice = "undecided"
    record["choice"] = choice
    why = f"key {record['key']}" + (f", count status {record['count_status']}"
                                   if "count_status" in record else "")
    return record, (f"ESTIMATE [{round(low)}, {round(high)}] tokens ({why}; {len(tools)} tools, "
                    f"{size} bytes): {choice}")


# ---------------------------------------------------------------------------
# F — the credential rule on an instance of its own.


def f1():
    folder = os.path.join(WORK, "f1")
    shutil.rmtree(folder, ignore_errors=True)
    fake = None
    marker = "a0-not-a-dummy"
    try:
        fake, port = start_fake(folder)
        base = f"http://127.0.0.1:{port}"
        http("POST", base + "/__control/scenario", {"replies": []})
        status, _ = http("POST", base + "/v1/messages",
                         {"model": MODEL, "max_tokens": 1, "messages": []},
                         {"x-api-key": marker, "anthropic-version": "2023-06-01"})
        _, raw = http("GET", base + "/__control/log")
        log = json.loads(raw)
    except Exception as error:  # noqa: BLE001
        return "fail", f"{type(error).__name__}: {error}", {}
    finally:
        kill_group(fake)
    held = [os.path.relpath(p, folder) for p in glob.glob(os.path.join(folder, "**"),
                                                          recursive=True)
            if os.path.isfile(p) and marker.encode() in open(p, "rb").read()]
    logged = [r["headers"].get("x-api-key") for r in log.get("requests", [])]
    ok = (status == 401 and len(log.get("failures", [])) == 1 and logged == [REDACTION]
          and marker not in raw.decode() and not held)
    return ("pass" if ok else "fail",
            f"status {status}; failures {len(log.get('failures', []))}; logged x-api-key "
            f"{logged}; value in the log {marker in raw.decode()}; files holding it {held}",
            {"status": status, "failures": log.get("failures"), "logged": logged,
             "held": held})


# ---------------------------------------------------------------------------
# D — the drag probe.


def run_probe(binary):
    out = os.path.join(WORK, "probe-out")
    os.makedirs(out, exist_ok=True)
    ran = run([binary, out], WALL_PROBE_RUN, cwd=PROBE)
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            try:
                return json.loads(line[len("ANSWER "):]), None
            except ValueError as error:
                return None, f"unreadable ANSWER: {error}"
    return None, (f"expired after {WALL_PROBE_RUN} s" if ran["expired"]
                  else f"exit {ran['rc']}: {ran['stderr'].strip()[-300:]}")


# ---------------------------------------------------------------------------
# L — the key written nowhere.


def l1():
    key = anthropic_key()
    if not key:
        return "skip", "host: no key", {"key": "absent"}
    needle = key.encode()
    places = [os.path.join(TREE, "build"), os.path.join(TREE, "Reelcut.xcodeproj"), WORK]
    held, scanned = [], 0
    for place in places:
        for here, dirs, names in os.walk(place):
            # The copy's own symlinks (core, graphic, docs) lead into the tree.
            dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(here, d))]
            for name in names:
                path = os.path.join(here, name)
                if os.path.islink(path):
                    continue
                try:
                    body = open(path, "rb").read()
                except OSError:
                    continue
                scanned += 1
                if needle in body:
                    held.append(os.path.relpath(path, ROOT))
    scanned += 1
    if needle in open(ROADMAP, "rb").read():
        held.append(os.path.relpath(ROADMAP, ROOT))
    held = sorted(set(held))
    return ("pass" if not held else "fail",
            f"key present; {scanned} files read; holding it: {held[:10]}",
            {"key": "present", "scanned": scanned, "held": held})


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default=",".join(GROUPS))
    parser.add_argument("--rasterize", default=os.path.expanduser("~/devel/rasterize"))
    options = parser.parse_args()
    only = {g.strip() for g in options.only.split(",") if g.strip()}
    rasterize = os.path.abspath(os.path.expanduser(options.rasterize))
    previous = {}
    if os.path.exists(ANSWERS):
        try:
            previous = json.load(open(ANSWERS))
        except ValueError:
            previous = {}
    os.makedirs(WORK, exist_ok=True)
    today = datetime.date.today().isoformat()
    xcode = run(["xcodebuild", "-version"], 60)["stdout"].split("\n")
    host = {"macos": run(["sw_vers", "-productVersion"], 60)["stdout"].strip(),
            "macos_build": run(["sw_vers", "-buildVersion"], 60)["stdout"].strip(),
            "xcode": " ".join(x.strip() for x in xcode if x.strip()),
            "date": today, "anthropic_key": "present" if anthropic_key() else "absent"}
    print(f"host: macOS {host['macos']} ({host['macos_build']}), {host['xcode']}, "
          f"ANTHROPIC_API_KEY {host['anthropic_key']}", flush=True)

    results = {}

    def put(rid, state, reason, measured=None):
        results[rid] = {"state": state, "reason": reason, "measured": measured or {},
                        "date": today}

    needs_build = bool(only & set("BHCTEL"))
    needs_probe = bool(only & set("BD"))
    built = {"r": False, "d": False}
    facts = None
    if needs_build:
        # B1, B3.
        facts = rasterize_facts(rasterize)
        host["rasterize"] = {k: facts[k] for k in ("head", "agent_dirty", "sdk", "bun")}
        anchors, copied, error = make_tree(rasterize)
        put("B1", "pass" if copied and facts["head_rc"] == 0 else "fail",
            f"Rasterize {facts['head'][:12]} (agent/ dirty {facts['agent_dirty']}); SDK "
            f"{facts['sdk']}; bun {facts['bun']}; src sha256 "
            + ", ".join(f"{k} {v[:12]}" for k, v in facts["src_sha256"].items()),
            facts)
        bad = {k: v for k, v in anchors.items() if v != 1}
        put("B3", "pass" if error is None and not bad and anchors else "fail",
            (f"{len(anchors)} anchors, each once" if not bad else f"anchors not once: {bad}")
            + (f"; {error}" if error else ""), {"anchors": anchors})
        # B2.
        if error is None:
            frozen, record = bun_install()
            put("B2", "pass" if frozen else "fail",
                (f"--frozen-lockfile rc 0 in {record['frozen_seconds']:.1f} s" if frozen else
                 f"--frozen-lockfile rc {record['frozen_rc']}; plain install rc "
                 f"{record.get('plain_rc')}; lock diff {len(record.get('lock_diff', []))} lines"),
                record)
        else:
            put("B2", "fail", "the copy was not made", {})
        # B4, B5.
        for kind, rid in (("r", "B4"), ("d", "B5")):
            if error is not None:
                put(rid, "fail", "the copy was not made", {})
                continue
            ok, record = build_app(kind)
            built[kind] = ok
            put(rid, "pass" if ok else "fail",
                f"rc {record['rc']} in {record['seconds']:.0f} s; binary {record['binary']}"
                + (f"; {record.get('errors')}" if not ok else ""), record)

    probe_binary = None
    if needs_probe:
        probe_binary, record = build_probe()
        put("B6", "pass" if probe_binary else "fail",
            (f"built in {record.get('seconds', 0):.0f} s over {record.get('sources')} sources"
             if probe_binary else f"did not build: {record}"), record)

    if needs_build and "H" in only:
        for kind in ("r", "d"):
            state, reason, measured = helper_row(kind) if built[kind] else (
                "fail", "the build failed", {})
            put(f"H1{kind}", state, reason, measured)
            state, reason, measured = app_signature_row(kind) if built[kind] else (
                "fail", "the build failed", {})
            put(f"H2{kind}", state, reason, measured)
        state, reason, measured = tree_signature_row(built)
        put("H2t", state, reason, measured)
        if built["r"] and built["d"]:
            checked = run([sys.executable, os.path.join(ROOT, "tools", "proof", "dist_check.py"),
                           "--release", APPS["r"], "--dist", APPS["d"]], 120)
            score = re.search(r"dist_check: (\d+)/(\d+)", checked["stdout"])
            passed = int(score.group(1)) if score else None
            total = int(score.group(2)) if score else None
            put("H3", "pass" if score and passed == total and checked["rc"] == 0 else "fail",
                f"dist_check {passed}/{total}, rc {checked['rc']}",
                {"stdout": checked["stdout"][-800:]})
        else:
            put("H3", "fail", "a build failed", {})
        helper_r = os.path.join(APPS["r"], HELPER)
        if built["r"] and os.path.exists(helper_r):
            ready, measured = launch_helper_bare(helper_r)
            put("H5", "pass" if ready else "fail",
                f"ready {ready} in {measured.get('ready_seconds')} s; exit "
                f"{measured.get('exit_status')}; first stderr {measured.get('first_stderr')!r}",
                measured)
            bare_dir = os.path.join(WORK, "h6")
            shutil.rmtree(bare_dir, ignore_errors=True)
            os.makedirs(bare_dir)
            bare = os.path.join(bare_dir, "reelcut-agent")
            shutil.copy2(helper_r, bare)
            signed = run(["codesign", "--force", "--options", "runtime", "--sign", "-", bare], 60)
            facts6 = codesign_facts(bare)
            ready6, measured6 = launch_helper_bare(bare)
            measured6.update(sign_rc=signed["rc"], flags=facts6["flags"],
                             entitlements=facts6["entitlements"])
            ok6 = (not ready6 and signed["rc"] == 0 and "runtime" in facts6["flags"]
                   and not facts6["entitlements"])
            put("H6", "pass" if ok6 else "fail",
                f"re-signed rc {signed['rc']} (flags {','.join(facts6['flags'])}, entitlements "
                f"{facts6['entitlements']}); ready {ready6}; exit status "
                f"{measured6.get('exit_status')}; first stderr "
                f"{measured6.get('first_stderr')!r}", measured6)
        else:
            put("H5", "fail", "no Release helper", {})
            put("H6", "fail", "no Release helper", {})

    runs = {}
    if needs_build and only & set("HCTE"):
        for kind in ("r", "d"):
            if not built[kind]:
                runs[kind] = None
                continue
            print(f"run {kind}…", flush=True)
            runs[kind] = one_run(kind)
            rec = runs[kind]
            print(f"run {kind}: port {rec.get('bound')}, hook "
                  f"{[e.get('event') for e in rec.get('hook', []) if e.get('event') != 'from_helper']}"
                  + (f", error {rec['error']}" if rec.get("error") else ""), flush=True)
        with open(os.path.join(WORK, "runs.json"), "w") as f:
            json.dump(runs, f, indent=1, default=str)
        for kind in ("r", "d"):
            rec = runs[kind]
            leftover = (rec or {}).get("helpers_after_kill")
            if "H" in only:
                state, reason, measured = hook_row(kind, rec)
                if leftover:
                    state, reason = "fail", reason + f"; helpers still running {leftover}"
                put(f"H4{kind}", state, reason, measured)
            if "C" in only:
                state, reason, measured = catalog_row(rec)
                put(f"C1{kind}", state, reason, measured)
            if "T" in only:
                for rid, fn in (("T1", t1_row), ("T2", t2_row), ("T3", t3_row)):
                    state, reason, measured = fn(rec)
                    put(f"{rid}{kind}", state, reason, measured)
        if "C" in only:
            c2 = c2_measure(runs.get("d"))
            if c2 is None:
                put("C2", "fail", "run d's stand-in log has no first POST body", {})
                put("C3", "fail", "no C2", {})
            else:
                put("C2", "pass",
                    f"first POST {c2['body_bytes']} bytes; {c2['tools']} tools "
                    f"({c2['deferred']} defer_loading; not deferred {c2['not_deferred']}); "
                    f"tools array {c2['tools_bytes']} bytes",
                    {k: v for k, v in c2.items() if k != "tools_list"})
                record, reason = c3(c2)
                put("C3", "pass", reason, record)
        if "E" in only:
            export = (runs.get("r") or {}).get("export")
            if not export:
                put("E1", "fail", "run r made no export", {})
                put("E2", "fail", "run r made no export", {})
            else:
                put("E1", "pass" if export.get("e1_ftyp") else "fail",
                    f"ftyp at byte 4 {export.get('e1_ftyp')}; {export.get('e1_bytes')} bytes in "
                    f"{export.get('e1_seconds')} s" + (f"; {export['e1_error']}"
                                                       if export.get("e1_error") else ""),
                    export)
                replaced = bool(export.get("e2_ftyp")) and not export.get("e2_still_sentinel")
                put("E2", "pass" if replaced else "fail",
                    f"replaced {replaced} (ftyp {export.get('e2_ftyp')}, still sentinel "
                    f"{export.get('e2_still_sentinel')}, {export.get('e2_bytes')} bytes), "
                    f"nobody asked; tool error {export.get('e2_error')}; result "
                    f"{export.get('e2_result_text', export.get('e2_exception', ''))[:240]}",
                    export)

    if "F" in only:
        state, reason, measured = f1()
        put("F1", state, reason, measured)

    if "D" in only:
        if probe_binary is None:
            put("D1", "fail", "the probe did not build", {})
            put("D2", "fail", "the probe did not build", {})
        else:
            answer, why = run_probe(probe_binary)
            if answer is None:
                put("D1", "fail", f"the probe gave no answer: {why}", {})
                put("D2", "fail", f"the probe gave no answer: {why}", {})
            else:
                by_id = {r["id"]: r for r in answer.get("rows", [])}
                for rid in ("D1", "D2"):
                    r = by_id.get(rid)
                    if r is None:
                        put(rid, "fail", "row missing from the probe's answer", {})
                    else:
                        put(rid, "pass" if r["ok"] else "fail", r["detail"],
                            answer.get("measure", {}))

    if "L" in only:
        state, reason, measured = l1()
        put("L1", state, reason, measured)

    # Rows this run did not measure carry forward, with their dates.
    for rid, *_ in ROWS:
        if rid not in results and rid in previous.get("rows", {}):
            results[rid] = previous["rows"][rid]

    print()
    counts = {"pass": 0, "fail": 0, "skip": 0}
    missing = []
    for rid, _group, kind, _text in ROWS:
        row = results.get(rid)
        if row is None or row.get("state") not in counts:
            missing.append(rid)
            continue
        counts[row["state"]] += 1
        carried = "" if row.get("date") == today else f" [carried from {row.get('date')}]"
        print(f"{rid} {row['state']} {kind} — {row['reason']}{carried}")
    digest = hashlib.sha256("".join(
        f"{rid}={results[rid]['state']}\n" for rid in sorted(results)
        if rid not in missing).encode()).hexdigest()
    print(f"\nscores: {counts['pass']} pass, {counts['fail']} fail, {counts['skip']} skip of "
          f"{len(ROWS)}")
    print(f"digest: {digest}")

    record = {"host": host if needs_build else dict(previous.get("host", {}), **host),
              "rows": results, "digest": digest, "only": sorted(only)}
    with open(ANSWERS, "w") as f:
        json.dump(record, f, indent=1, sort_keys=True, ensure_ascii=False, default=str)

    if missing:
        print(f"SPIKE INCOMPLETE: {', '.join(missing)}")
        sys.exit(2)
    broken = [rid for rid, _g, kind, _t in ROWS
              if kind in ("I", "C") and results[rid]["state"] == "fail"]
    sys.exit(1 if broken else 0)


if __name__ == "__main__":
    main()
