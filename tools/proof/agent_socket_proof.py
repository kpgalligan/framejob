#!/usr/bin/env python3
"""Road map 14's MC2 and MC4, against the built app: the agent server's Unix
socket, its only listener since MC4 deleted TCP (spec §11 MC-1, MC-2, MC-5,
MC-6; MC1's S1–S10).

Every instance is a `Popen` this script owns, launched with
`-ApplePersistenceIgnoreState YES` and `RC_AGENT_SOCKET` in a
`tempfile.mkdtemp(prefix="rcs-")` folder under `$TMPDIR` (MC1: a path under
`tools/proof/work/` can pass 103 bytes). An instance is ready when its log
holds the socket's line alone. Logs go to
`tools/proof/work/agent-socket/<name>.log`; every other child (the probe's
build, the probe, `osascript`, `lsof`, `ffmpeg`,
`make app`) runs under `graphics_spike/bounded.py`. HTTP over AF_UNIX is
`mcp.UnixHTTPConnection`. Nothing is signalled but this script's own pids,
and nothing under `~/Library/Application Support/Reelcut/` is created,
written or unlinked.

P1  (probe) `AgentServer.socketPlan`: `.bind(default)` for `{}`; `.bind(s)`
    for `{RC_AGENT_SOCKET: s}`; `.bind(default)` for an empty RC_AGENT_SOCKET;
    `.skip("no Application Support folder")` for `{}` with a nil default.
    `agent_socket_probe.swift`, built like `export_cancel_proof.build_probe`
    (Swift sources and the staticlib only) into `work/agent-socket/probe/`.
K0  CONTROL: the scratch path is ≤ 103 bytes, under $TMPDIR, not under the
    person's support folder, and its folder is 0700.
K1  A logs `listening at <path>`; the file is a socket, mode 0600.
K3  `new_project` (a scratch path); `add_marker` over one connection is read
    back by `get_project` over a second, and one added over the second is
    read back over the first.
K4  B at the same path logs `not bound: another instance answers…`; the
    file's dev and ino are unchanged; A still answers over the socket.
K5  SIGKILL A (B is stopped): the leftover refuses `connect`; C binds over it
    and answers.
K6  the proof unlinks C's file and D binds at the path; C quits by a
    pid-targeted quit event (`osascript -l JavaScript`,
    `NSRunningApplication…terminate`), exit awaited ≤ 20 s; D's file keeps its
    inode and answers.
K7  D quits the same way within 20 s; the file is gone.
K8  E's folder is chmod 0755: E logs `not bound` naming 0755; no file exists.
K9  F finds a regular file at its path: F logs `not bound…not a socket`; the
    file's bytes are unchanged.
K11 `lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN` is empty for A (MC4: no TCP
    listener).
K12 (spec §11 MC-5) H, launched with `-RCFFmpegImport ask -RCFFmpegPath
    <which ffmpeg>`, over an `MCP(..., timeout=20)` client: `import_media` of
    a 1 s `testsrc` Matroska (`-c:v mpeg4`, made under H's scratch folder)
    answers `isError` with B73's copy refusal (`MPEG-4 Part 2 video, which
    Reelcut cannot copy out of a WebM or Matroska file`, spec §11 #216-R;
    `Could not read` before the merge with main) and `RCFFmpegImport` in its
    text (the import half); `open_project` of the same file answers `isError`
    within 20 s (the open half). No ffmpeg on the host is a FAIL.
K13 (spec §11 MC-7) Settings' MCP section, on K, with no clipboard
    involved: `new_project` (a scratch path); `perform_menu_item ["Reelcut",
    "Settings…"]`, whose `windows_opened` must include `settings`; then
    `snapshot_ui {window: "settings"}` and its layout dump:
    `settings.mcp.heading` reads "MCP", `settings.mcp.blurb.1` the first
    paragraph's literal, `settings.mcp.helper` the launched bundle's resolved
    `Contents/Helpers/reelcut-mcp` (an executable file of 200 characters or
    fewer, snapshot_ui's text cap), and `settings.mcp.copy` "Copy MCP
    Command"; their frame tops are strictly ordered heading < blurb.1 <
    helper < copy < `settings.assistant.info`; none of those ids has a layout
    problem. The press itself is `settings_layout_probe.py`'s L10.
Z1  no `Reelcut: ` in any log.  Z2  no proof pid alive.

    python3 tools/proof/agent_socket_proof.py [--app PATH]
        [--mutant no-connect-first|no-mode-check|tcp-listener|agent-asks|
                  open-asks|fixed-path]

Any FAIL exits 1; an instrument that cannot run is a FAIL, never a skip, and
no row may SKIP. Every mutant replaces one anchor in a
`tree_copy.make_copy` copy built by its own `make app` and runs every row
against that build: `no-connect-first` (K4 must FAIL), `no-mode-check` (K8),
`tcp-listener` (K11: a POSIX listener on 127.0.0.1:0 after the socket's
`listening at` line), `agent-asks` (K12's import half: `AgentServer+Media`'s
probe passes `mayAsk: true`), `open-asks` (K12's open half: `openProject`
calls `makeDocument` outside `withoutAsking`) and `fixed-path` (K13:
`mcpHelperURL` is `/Applications/Reelcut.app/…`). `lsregister -u` is run on
a copy's built app before its tree is replaced and at the end of its run. A
mutant run exits 0 when its row FAILED (caught), 1 when it passed
(survived), 2 when the control could not be performed.
"""

import argparse
import errno
import json
import os
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/agent-socket"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
PROBE_SOURCE = ROOT / "tools/proof/agent_socket_probe.swift"
SOURCES = ROOT / "app/Sources"
SUPPORT = Path.home() / "Library/Application Support/Reelcut"
MAX_PATH = 103
LAUNCH_BOUND = 60
QUIT_BOUND = 20
K12_BOUND = 20
NEVER_ASKS = "RCFFmpegImport"
# What B73's built-in Matroska copy answers for K12's mpeg4 fixture, before
# the opt-in ffmpeg step a tool call never asks for (spec §11 #216-R, MC-5).
COPY_REFUSAL = "MPEG-4 Part 2 video, which Reelcut cannot copy out of a WebM or Matroska file"
TCP_LISTENER = (
    "        NSLog(\"Reelcut agent socket listening at %@\", path)\n"
    "        let leaked = socket(AF_INET, SOCK_STREAM, 0)\n"
    "        var leakedAddress = sockaddr_in()\n"
    "        leakedAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)\n"
    "        leakedAddress.sin_family = sa_family_t(AF_INET)\n"
    "        leakedAddress.sin_addr.s_addr = inet_addr(\"127.0.0.1\")\n"
    "        leakedAddress.sin_port = 0\n"
    "        _ = withUnsafePointer(to: &leakedAddress) { pointer in\n"
    "            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {\n"
    "                bind(leaked, $0, socklen_t(MemoryLayout<sockaddr_in>.size))\n"
    "            }\n"
    "        }\n"
    "        _ = listen(leaked, 1)\n")
# name → (the row it must fail, the half of it (or None), file in app/Sources,
# before — exactly once, after)
MUTANTS = {
    "no-connect-first": ("K4", None, "AgentServer+Socket.swift",
                         "        let answer = connectErrno(toSocketAt: path)\n",
                         "        let answer = ECONNREFUSED\n"),
    "no-mode-check": ("K8", None, "AgentServer+Socket.swift",
                      "        if folderInfo.st_mode & 0o077 != 0 { return modeSentence(folder, "
                      "folderInfo.st_mode) }\n",
                      ""),
    "tcp-listener": ("K11", None, "AgentServer+Socket.swift",
                     "        NSLog(\"Reelcut agent socket listening at %@\", path)\n",
                     TCP_LISTENER),
    "agent-asks": ("K12", "import", "AgentServer+Media.swift",
                   "        MediaImporter.probe(url: url, mayAsk: false) { result in\n",
                   "        MediaImporter.probe(url: url, mayAsk: true) { result in\n"),
    "open-asks": ("K12", "open", "AgentServer+Project.swift",
                  "        let made = try MediaImporter.withoutAsking {\n"
                  "            try controller.makeDocument(withContentsOf: url, ofType: type)\n"
                  "        }\n",
                  "        let made = try controller.makeDocument(withContentsOf: url, ofType: type)\n"),
    "fixed-path": ("K13", None, "AgentServer+Socket.swift",
                   "        Bundle.main.bundleURL.appendingPathComponent(\"Contents/Helpers/reelcut-mcp\")\n",
                   "        URL(fileURLWithPath: \"/Applications/Reelcut.app/Contents/Helpers/reelcut-mcp\")\n"),
}
ORDER = ["P1", "K0", "K1", "K3", "K4", "K5", "K6", "K7", "K8", "K9", "K11", "K12", "K13",
         "Z1", "Z2"]
rows = {}
skips = {}
halves = {}
INSTANCES = []
SCRATCH = []


def check(name, good, detail=""):
    rows[name] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"  {detail}" if detail else ""),
          flush=True)


# ---- HTTP over the socket ---------------------------------------------------------

def post(path, body, timeout=60):
    """One POST to /mcp over the socket at `path`, on a connection of its own.
    Answers (status, raw body bytes)."""
    connection = mcp.UnixHTTPConnection(path, timeout=timeout)
    try:
        connection.request("POST", "/mcp", body=body, headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream"})
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


def rpc(path, method, params=None, request_id=1, timeout=60):
    body = json.dumps({"jsonrpc": "2.0", "id": request_id, "method": method,
                       "params": params or {}}).encode()
    status, raw = post(path, body, timeout=timeout)
    answer = json.loads(raw)
    if status != 200 or "error" in answer:
        raise RuntimeError(f"{method}: HTTP {status} {answer.get('error')}")
    return answer["result"]


def call(path, tool, arguments):
    result = rpc(path, "tools/call", {"name": tool, "arguments": arguments})
    text = "".join(part.get("text", "") for part in result.get("content", [])
                   if part.get("type") == "text")
    if result.get("isError"):
        raise RuntimeError(f"{tool}: {text}")
    return json.loads(text) if text.strip().startswith(("{", "[")) else text


def answers(path):
    """True when `initialize` over the socket answers as Reelcut."""
    try:
        result = rpc(path, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                          "clientInfo": {"name": "agent-socket-proof",
                                                         "version": "1"}})
        return result.get("serverInfo", {}).get("name") == "reelcut"
    except Exception:
        return False


def connect_errno(path):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.settimeout(5)
        sock.connect(path)
        return 0
    except OSError as error:
        return error.errno
    finally:
        sock.close()


def ident(path):
    """(dev, ino, mode) of `path` by lstat, or None when absent."""
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return None
    return info.st_dev, info.st_ino, info.st_mode


# ---- instances ------------------------------------------------------------------

class Instance:
    """One owned app, by PID, on its own scratch socket."""

    def __init__(self, name, app, sock, extra=()):
        self.name, self.app, self.sock, self.extra = name, app, sock, list(extra)
        self.log = WORK / f"{name}.log"
        self.child = None
        self.socket_line = None

    def start(self):
        self.log.write_text("")
        env = bounded.child_env({"RC_AGENT_SOCKET": self.sock})
        with open(self.log, "a") as out:
            self.child = subprocess.Popen(
                [str(self.app), "-ApplePersistenceIgnoreState", "YES"] + self.extra,
                stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
                env=env)
        INSTANCES.append(self)
        deadline = time.monotonic() + LAUNCH_BOUND
        while time.monotonic() < deadline:
            time.sleep(0.25)
            text = self.log.read_text(errors="replace")
            line = re.search(r"Reelcut agent socket (listening at .*|not bound: .*)", text)
            if line:
                self.socket_line = line.group(1).strip()
                print(f"  {self.name}: PID {self.child.pid}; socket {self.socket_line}",
                      flush=True)
                return True
            if self.child.poll() is not None:
                break
        print(f"  {self.name}: did not come up (rc {self.child.poll()})", flush=True)
        return False

    def alive(self):
        return self.child is not None and self.child.poll() is None

    def signal(self, sig):
        if self.alive():
            os.kill(self.child.pid, sig)
            self.child.wait(timeout=30)

    def quit_event(self):
        """A quit event to THIS pid through NSRunningApplication; answers
        (exited within QUIT_BOUND, seconds, the osascript result)."""
        if not self.alive():
            return False, 0.0, "not running"
        script = ("ObjC.import('AppKit');"
                  f"var app = $.NSRunningApplication.runningApplicationWithProcessIdentifier("
                  f"{self.child.pid});"
                  "app.isNil() ? 'no such app' : String(app.terminate);")
        started = time.monotonic()
        sent = bounded.run(["osascript", "-l", "JavaScript", "-e", script], 30)
        try:
            self.child.wait(timeout=max(0.0, QUIT_BOUND - (time.monotonic() - started)))
            exited = True
        except subprocess.TimeoutExpired:
            exited = False
        said = (sent["stdout"] + sent["stderr"]).strip()
        return exited, round(time.monotonic() - started, 2), f"osascript rc {sent['rc']}: {said}"

    def stop(self):
        if not self.alive():
            return
        self.child.terminate()
        try:
            self.child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.child.kill()
            self.child.wait()


def scratch_folder():
    folder = tempfile.mkdtemp(prefix="rcs-")
    SCRATCH.append(folder)
    return folder


# ---- the probe ------------------------------------------------------------------

def build_probe(sources, probe_dir):
    """`agent_socket_probe.swift` as `main.swift` over every other file in
    `sources` on harness/build.sh's swiftc line, into `probe_dir`; rebuilt
    only when stale. The binary, or None and why."""
    probe_dir.mkdir(parents=True, exist_ok=True)
    binary = probe_dir / "agent_socket_probe"
    entry = probe_dir / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    swift = sorted(path for path in Path(sources).glob("*.swift") if path.name != "main.swift")
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    headers = [ROOT / "app/Bridging/Reelcut-Bridging-Header.h",
               ROOT / "core/include/reelcut_core.h"]
    if binary.exists() and all(path.stat().st_mtime < binary.stat().st_mtime
                               for path in swift + [entry, lib] + headers):
        print(f"  probe: up to date — {binary}", flush=True)
        return binary, ""
    started = time.monotonic()
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    built = bounded.run(
        ["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
         "-module-name", "Reelcut",
         "-import-objc-header", str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
         "-L", str(lib.parent), "-lreelcut_core"]
        + [str(path) for path in swift] + [str(entry), "-o", str(binary)], 900)
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = built["stderr"].strip().splitlines()[-4:]
        return None, f"swiftc rc {built['rc']}: {(errors or tail or ['(no output)'])[:6]}"
    print(f"  probe: built in {time.monotonic() - started:.0f} s — {binary}", flush=True)
    return binary, ""


def row_p1(sources, probe_dir):
    binary, why = build_probe(sources, probe_dir)
    if binary is None:
        check("P1", False, f"the probe did not build: {why}")
        return
    ran = bounded.run([str(binary)], 60)
    try:
        lines = [json.loads(line) for line in ran["stdout"].splitlines() if line.strip()]
    except ValueError:
        lines = []
    by_case = {line.get("case"): line for line in lines}
    meta = by_case.get("default-path", {})
    default, scratch = meta.get("fixed_default"), meta.get("scratch_socket")
    want = {
        "empty": {"plan": "bind", "path": default},
        "socket": {"plan": "bind", "path": scratch},
        "empty-socket": {"plan": "bind", "path": default},
        "nil-default": {"plan": "skip", "reason": "no Application Support folder"},
    }
    wrong = []
    for case, expected in want.items():
        got = {key: value for key, value in by_case.get(case, {}).items() if key != "case"}
        if got != expected:
            wrong.append(f"{case}: {got} (want {expected})")
    good = ran["rc"] == 0 and default is not None and not wrong
    check("P1", good, f"rc {ran['rc']}; " + ("; ".join(wrong) if wrong else
                                            f"{len(want)} cases as planned"))


# ---- K11, K12, K13 ----------------------------------------------------------------

def row_k11(instance):
    """No TCP listener in the launched instance's own pid."""
    if not instance.alive():
        check("K11", False, f"{instance.name} is not running")
        return
    listed = bounded.run(["lsof", "-nP", "-a", "-p", str(instance.child.pid), "-iTCP",
                          "-sTCP:LISTEN"], 30)
    lines = [line for line in listed["stdout"].splitlines() if line.strip()]
    check("K11", not lines and not listed["expired"],
          f"lsof rc {listed['rc']}; {len(lines)} lines {lines[:3]}")


def k12_call(sock, tool, arguments):
    """(isError, text, seconds) of one call over an MCP(…, timeout=K12_BOUND)
    client; an expiry or a transport failure is (None, why, seconds)."""
    started = time.monotonic()
    try:
        client = mcp.MCP(sock, timeout=K12_BOUND)
        result = client._request("tools/call", {"name": tool, "arguments": arguments})
    except Exception as error:  # an expiry is the answer
        return None, f"{type(error).__name__}: {error}", round(time.monotonic() - started, 2)
    text = "".join(part.get("text", "") for part in result.get("content", [])
                   if part.get("type") == "text")
    return bool(result.get("isError")), text, round(time.monotonic() - started, 2)


def row_k12(app):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        check("K12", False, "no ffmpeg on this host: the row needs one installed to be asked about")
        return
    folder = scratch_folder()
    sock = os.path.join(folder, "agent.sock")
    movie = os.path.join(folder, "k12.mkv")
    made = bounded.run([ffmpeg, "-v", "error", "-y", "-f", "lavfi", "-i",
                        "testsrc=duration=1:size=320x240:rate=30", "-c:v", "mpeg4", movie], 120)
    if made["rc"] != 0 or not os.path.exists(movie):
        check("K12", False, f"ffmpeg did not make the Matroska: rc {made['rc']} "
                            f"{made['stderr'].strip()[-300:]}")
        return
    h = Instance("h", app, sock, ["-RCFFmpegImport", "ask", "-RCFFmpegPath", ffmpeg])
    up = h.start()
    if not up or h.socket_line != f"listening at {sock}":
        check("K12", False, f"H did not bind: {h.socket_line!r}")
        h.stop()
        return
    project = os.path.join(folder, "k12.reelcut")
    try:
        call(sock, "new_project", {"path": project})
        error_i, text_i, seconds_i = k12_call(sock, "import_media",
                                              {"project": project, "path": movie})
        import_ok = error_i is True and COPY_REFUSAL in text_i and NEVER_ASKS in text_i
        error_o, text_o, seconds_o = k12_call(sock, "open_project", {"path": movie})
        open_ok = error_o is True and seconds_o <= K12_BOUND
    except Exception as error:  # noqa: BLE001 — the setup's failure is the row's
        check("K12", False, f"setup: {type(error).__name__}: {error}")
        h.stop()
        return
    h.stop()
    halves["import"], halves["open"] = import_ok, open_ok
    check("K12", import_ok and open_ok,
          f"import half {import_ok} (isError {error_i}, {seconds_i} s: {text_i[:240]!r}); "
          f"open half {open_ok} (isError {error_o}, {seconds_o} s: {text_o[:160]!r})")


K13_BLURB = ("An MCP client such as Claude Code uses Reelcut's tools through reelcut-mcp, a "
             "helper inside this app. It reaches Reelcut over a local socket that only programs "
             "you run can open.")
K13_IDS = ["settings.mcp.heading", "settings.mcp.blurb.1", "settings.mcp.helper",
           "settings.mcp.copy", "settings.assistant.info"]


def row_k13(app):
    folder = scratch_folder()
    sock = os.path.join(folder, "agent.sock")
    helper = str(Path(app).resolve().parents[1] / "Helpers/reelcut-mcp")
    executable = os.path.isfile(helper) and os.access(helper, os.X_OK)
    k = Instance("k", app, sock)
    up = k.start()
    try:
        if not up or k.socket_line != f"listening at {sock}":
            check("K13", False, f"K did not bind: {k.socket_line!r}")
            return
        project = call(sock, "new_project", {"path": os.path.join(folder, "k13.reelcut")})["saved"]
        opened = call(sock, "perform_menu_item", {"project": project,
                                                  "path": ["Reelcut", "Settings…"]})
        kinds = [w.get("kind") for w in opened.get("windows_opened", [])]
        answer = call(sock, "snapshot_ui", {"window": "settings",
                                            "path": os.path.join(folder, "k13.png")})
        with open(answer.get("layout_path")) as f:
            layout = json.load(f)
    finally:
        k.stop()
    views = [v for v in layout.get("views", []) if not v.get("hidden")]
    found = {}
    for identifier in K13_IDS:
        match = [v for v in views if v.get("id") == identifier]
        found[identifier] = match[0] if match else None
    text = {i: (v or {}).get("text") for i, v in found.items()}
    tops = [(v or {}).get("frame", [None, None])[1] for v in found.values()]
    ordered = None not in tops and all(a < b for a, b in zip(tops, tops[1:]))
    indices = {v["i"] for v in found.values() if v}
    problems = [p for p in layout.get("problems", []) if p.get("view") in indices]
    good = ("settings" in kinds and executable and len(helper) <= 200
            and text["settings.mcp.heading"] == "MCP"
            and text["settings.mcp.blurb.1"] == K13_BLURB
            and text["settings.mcp.helper"] == helper
            and text["settings.mcp.copy"] == "Copy MCP Command"
            and ordered and not problems)
    check("K13", good,
          f"opened {kinds}; heading {text['settings.mcp.heading']!r}; blurb.1 exact "
          f"{text['settings.mcp.blurb.1'] == K13_BLURB}; helper {text['settings.mcp.helper']!r} "
          f"(want {helper!r}, executable {executable}, {len(helper)} characters); copy "
          f"{text['settings.mcp.copy']!r}; tops {tops} ordered {ordered}; problems {problems[:3]}")


# ---- the K rows -------------------------------------------------------------------

def run_rows(app):
    tmp = os.path.realpath(os.environ.get("TMPDIR") or tempfile.gettempdir())
    shared = scratch_folder()
    path = os.path.join(shared, "agent.sock")
    folder_mode = stat.S_IMODE(os.stat(shared).st_mode)
    real = os.path.realpath(path)
    check("K0", len(path.encode()) <= MAX_PATH and real.startswith(tmp + os.sep)
          and not real.startswith(str(SUPPORT.resolve()) + os.sep) and folder_mode == 0o700,
          f"{path} ({len(path.encode())} bytes), folder {oct(folder_mode)}")
    if not rows["K0"]:
        for name in ORDER[2:13]:
            check(name, False, "not run: K0 failed")
        return

    # K1 — A binds.
    a = Instance("a", app, path)
    up = a.start()
    info = ident(path)
    is_sock = info is not None and stat.S_ISSOCK(info[2])
    mode = stat.S_IMODE(info[2]) if info else None
    check("K1", up and a.socket_line == f"listening at {path}" and is_sock and mode == 0o600,
          f"line {a.socket_line!r}; socket {is_sock}; mode {oct(mode) if mode is not None else None}")

    # K11 — A holds no TCP listener.
    row_k11(a)

    # K3 — an edit over one connection is read back over a second.
    project = str(WORK / f"k3-{os.getpid()}.reelcut")
    shutil.rmtree(project, ignore_errors=True)
    try:
        first, second = mcp.MCP(path, timeout=60), mcp.MCP(path, timeout=60)
        first.call("new_project", path=project)
        first.call_with("add_marker", {"project": project, "at": 600_000, "name": "via-first"})
        seen_second = second.call("get_project", project=project)
        second.call_with("add_marker", {"project": project, "at": 1_200_000,
                                        "name": "via-second"})
        seen_first = first.call("get_project", project=project)

        def names(state):
            return {(m.get("name"), m.get("time"))
                    for m in (state.get("project") or {}).get("markers", [])}
        one = ("via-first", 600_000) in names(seen_second)
        two = ("via-second", 1_200_000) in names(seen_first)
        check("K3", one and two,
              f"the first connection's marker read over the second {one}; the second's read "
              f"over the first {two}")
    except Exception as error:
        check("K3", False, f"{type(error).__name__}: {error}")

    # K4 — B finds A answering and binds none.
    before = ident(path)
    b = Instance("b", app, path)
    b_up = b.start()
    after = ident(path)
    want_line = f"not bound: another instance answers at {path}; this one binds none"
    same = before is not None and after is not None and before[:2] == after[:2]
    a_answers = answers(path)
    check("K4", b_up and b.socket_line == want_line and same and a_answers,
          f"B {b.socket_line!r}; dev/ino unchanged {same}; A answers {a_answers}")

    # K5 — a SIGKILLed A's leftover is refused, and C binds over it.
    a.signal(signal.SIGKILL)
    b.stop()
    left = ident(path)
    refused = connect_errno(path) if left else None
    c = Instance("c", app, path)
    c_up = c.start()
    c_answers = answers(path)
    check("K5", left is not None and stat.S_ISSOCK(left[2])
          and refused == errno.ECONNREFUSED and c_up
          and c.socket_line == f"listening at {path}" and c_answers,
          f"leftover socket {left is not None}; connect errno {refused} (want "
          f"{errno.ECONNREFUSED}, ECONNREFUSED); C {c.socket_line!r}; C answers {c_answers}")

    # K6 — C's file replaced under it; C's quit leaves D's.
    try:
        os.unlink(path)
        unlinked = True
    except OSError:
        unlinked = False
    d = Instance("d", app, path)
    d_up = d.start()
    d_info = ident(path)
    c_exited, c_seconds, c_said = c.quit_event()
    kept = ident(path)
    d_answers = answers(path)
    check("K6", unlinked and d_up and d.socket_line == f"listening at {path}" and c_exited
          and d_info is not None and kept is not None and kept[:2] == d_info[:2] and d_answers,
          f"D {d.socket_line!r}; C exited {c_exited} in {c_seconds} s ({c_said}); D's inode "
          f"kept {kept is not None and d_info is not None and kept[:2] == d_info[:2]}; "
          f"D answers {d_answers}")

    # K7 — D's quit removes its own file.
    d_exited, d_seconds, d_said = d.quit_event()
    gone = ident(path) is None
    check("K7", d_exited and gone, f"D exited {d_exited} in {d_seconds} s ({d_said}); "
          f"file gone {gone}")

    # K8 — a 0755 folder binds nothing.
    open_folder = scratch_folder()
    os.chmod(open_folder, 0o755)
    open_path = os.path.join(open_folder, "agent.sock")
    e = Instance("e", app, open_path)
    e_up = e.start()
    e.stop()
    absent = ident(open_path) is None
    named = (e.socket_line or "").startswith("not bound: ") and "0755" in (e.socket_line or "")
    check("K8", e_up and named and absent, f"E {e.socket_line!r}; no file {absent}")

    # K9 — a regular file at the path is left alone.
    file_folder = scratch_folder()
    file_path = os.path.join(file_folder, "agent.sock")
    payload = b"not a socket\n" + os.urandom(16)
    Path(file_path).write_bytes(payload)
    f = Instance("f", app, file_path)
    f_up = f.start()
    f.stop()
    kept_bytes = Path(file_path).read_bytes() == payload if os.path.exists(file_path) else False
    want_f = f"not bound: {file_path} exists and is not a socket; it is left alone"
    check("K9", f_up and f.socket_line == want_f and kept_bytes,
          f"F {f.socket_line!r}; bytes unchanged {kept_bytes}")

    # K12 — a tool call's import never asks (MC-5).
    try:
        row_k12(app)
    except Exception as error:  # noqa: BLE001
        check("K12", False, f"the row broke: {type(error).__name__}: {error}")

    # K13 — Settings' MCP section (MC-7).
    try:
        row_k13(app)
    except Exception as error:  # noqa: BLE001
        check("K13", False, f"the row broke: {type(error).__name__}: {error}")


def finish_z():
    for instance in INSTANCES:
        instance.stop()
    leaked = [line for instance in INSTANCES if instance.log.exists()
              for line in instance.log.read_text(errors="replace").splitlines()
              if "Reelcut: " in line]
    check("Z1", not leaked, f"{len(INSTANCES)} logs; " + (repr(leaked[:3]) if leaked else
                                                         "no `Reelcut: ` line"))
    alive = []
    for instance in INSTANCES:
        if instance.child is None:
            continue
        try:
            os.kill(instance.child.pid, 0)
            alive.append(instance.child.pid)
        except ProcessLookupError:
            pass
    check("Z2", not alive, f"alive {alive}" if alive else f"{len(INSTANCES)} pids all gone")


# ---- the mutants ------------------------------------------------------------------

def built_app(tree):
    return Path(tree) / "build/Build/Products/Release/Reelcut.app"


def unregister(tree):
    """`lsregister -u` on a copy's built app, when there is one."""
    app = built_app(tree)
    if app.exists():
        done = bounded.run([mcp.LSREGISTER, "-u", str(app)], 60)
        print(f"  lsregister -u {app}: rc {done['rc']}", flush=True)


def build_mutant_app(name):
    """A tree copy with the mutant's anchor replaced once, built by its own
    `make app`: the binary, or None and why."""
    _, _, file, before, after = MUTANTS[name]
    tree = WORK / f"mutant-{name}" / "tree"
    unregister(tree)
    made, reason = tree_copy.make_copy(str(tree))
    if made is None:
        return None, reason
    target = Path(made) / "app/Sources" / file
    text = target.read_text()
    if text.count(before) != 1:
        return None, f"{file} holds {before!r} {text.count(before)} times, not once"
    target.write_text(text.replace(before, after))
    print(f"  mutant {name}: make app in {made}", flush=True)
    built = bounded.run(["make", "app"], 1500, cwd=made)
    binary = built_app(made) / "Contents/MacOS/Reelcut"
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error:" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    return binary, ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    started = time.monotonic()
    WORK.mkdir(parents=True, exist_ok=True)

    app = args.app
    if args.mutant:
        row, half = MUTANTS[args.mutant][:2]
        print(f"agent socket — the {args.mutant} MUTANT ({row}{f' {half} half' if half else ''} "
              f"must FAIL)", flush=True)
        app, why = build_mutant_app(args.mutant)
        if app is None:
            unregister(WORK / f"mutant-{args.mutant}" / "tree")
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"agent socket — {app}", flush=True)

    try:
        row_p1(SOURCES, WORK / "probe")
        if not Path(app).exists():
            for name in ORDER[1:13]:
                check(name, False, f"not run: no app at {app}")
        else:
            run_rows(app)
    except Exception as error:  # an instrument that breaks is a FAIL, not an exit
        check("K?", False, f"the proof broke: {type(error).__name__}: {error}")
    finally:
        finish_z()
        for folder in SCRATCH:
            shutil.rmtree(folder, ignore_errors=True)
        if args.mutant:
            unregister(WORK / f"mutant-{args.mutant}" / "tree")

    seconds = time.monotonic() - started
    if args.mutant:
        row, half = MUTANTS[args.mutant][:2]
        if row not in rows or not rows.get("K0", False) or (half and half not in halves):
            print(f"mutant {args.mutant}: the control could not be performed — "
                  f"{row}{f' ({half} half)' if half else ''} was not scored or K0 failed")
            return 2
        caught = (halves.get(half) is False) if half else (rows[row] is False)
        print(f"mutant {args.mutant}: {row}{f' {half} half' if half else ''} "
              f"{'FAIL — caught' if caught else 'ok — survived'} in {seconds:.0f} s")
        return 0 if caught else 1
    passed = sum(1 for good in rows.values() if good)
    tail = f"; skipped {', '.join(f'{k}: {v}' for k, v in skips.items())}" if skips else ""
    print(f"{passed}/{len(rows)} in {seconds:.0f} s{tail}")
    complete = all(name in rows or name in skips for name in ORDER)
    return 0 if all(rows.values()) and complete and not skips else 1


if __name__ == "__main__":
    sys.exit(main())
