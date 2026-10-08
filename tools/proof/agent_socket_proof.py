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
`tree_copy.build_app`) runs under `graphics_spike/bounded.py`. HTTP over AF_UNIX is
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
K14 (#224) a quit with an agent call in flight, by the same pid-targeted
    quit event as K6 and K7 (`NSRunningApplication.terminate`: an Apple
    event, no activation, no window). M: `new_project`, one 1920×1080
    rectangle lasting 600 s, `save_project`; CONTROL C1: `get_project`'s
    `unsaved_changes` is false, so no save sheet can appear (when it is not,
    the row FAILs and M is stopped by SIGTERM, never by a quit event). Over a
    raw AF_UNIX socket, one HTTP/1.1 `POST /mcp` (`Connection: close`) of
    `tools/call export {preset: "h264"}`; 2 s later, CONTROL C2: `select`
    shows nothing to read, so the call is still in flight. Then the quit
    event: M exits within 20 s, its socket file is gone, and the raw
    connection reads 0 bytes and closes by EOF or a reset (not a 10 s
    timeout) — a clean failure, never a half answer.
K15 (spec §11 #231, issue batch B81) a quit with an `open_project` READ in
    flight, by K14's quit event. N is launched with
    `CFFIXED_USER_HOME=<work>/k15-home`, a fresh folder with no `Library`,
    so its copy lands in a scratch `Rewrapped/` and never in the owner's.
    CONTROL C0: once N has bound, `<k15-home>/Library/Application Support`
    exists (else the row FAILs, N is stopped by SIGTERM and no call is
    made). The fixture is `agent_open_proof.make_fixture`'s `big.webm`
    (`--k15-megabytes`, default 512) under `<work>/k15/`. A quit sender is
    armed BEFORE the call: one bounded `osascript -l JavaScript` that polls
    for a trigger file every 10 ms and then sends K14's `terminate`, so the
    quit costs no osascript start-up once the copy is seen. Then a raw `POST`
    of `open_project {big.webm}`; the scratch `Rewrapped/` is polled every
    10 ms, and on its `.partial.mov`: CONTROL C2, the connection has nothing
    to read, then the trigger. Pass: N exits within 20 s, its socket file is
    gone, the connection reads 0 bytes and closes by EOF or a reset, and
    `Rewrapped/` holds exactly `big-<16 hex>.partial.mov` (#228-P O8). Then
    N2, on the same scratch home: `open_project {big.webm}` answers a media
    path `…/big-<16 hex>.mov` that is on disk, with no partial left; the
    project is closed (`close_project {discard: true}`: a WebM opens as an
    untitled project with unsaved changes, and a quit's document review
    would put a save sheet up) and N2 quits by the same event. A call that
    answered before the quit is a FAIL that names `--k15-megabytes`. Both
    folders are removed when the row ends.
Z1  no `Reelcut: ` in any log.  Z2  no proof pid alive.

    python3 tools/proof/agent_socket_proof.py [--app PATH] [--k15-megabytes N]
        [--mutant no-connect-first|no-mode-check|tcp-listener|agent-asks|
                  open-asks|fixed-path|waits-for-call|no-controller]

Any FAIL exits 1; an instrument that cannot run is a FAIL, never a skip, and
no row may SKIP. Every mutant replaces one anchor in a
`tree_copy.make_copy` copy built by `tree_copy.build_app` and runs every row
against that build: `no-connect-first` (K4 must FAIL), `no-mode-check` (K8),
`tcp-listener` (K11: a POSIX listener on 127.0.0.1:0 after the socket's
`listening at` line), `agent-asks` (K12's import half: `AgentServer+Media`'s
probe passes `mayAsk: true`), `open-asks` (K12's open half: `openProject`
calls `makeDocument` outside `withoutAsking`) and `fixed-path` (K13:
`mcpHelperURL` is `/Applications/Reelcut.app/…`) and `waits-for-call` (K14
AND K15: `applicationWillTerminate` joins a `get_project` served on a
background thread before it unbinds, so main waits on the lane lock the
in-flight export or open holds, while that call's completion waits for main;
K6 and K7 fail too, as expected. It is `async` plus a semaphore, never
`DispatchQueue.global().sync`: GCD runs a `sync` block inline on the calling
thread, so `serve` would see the main thread and skip the lock) and
`no-controller` (Z1: `main.swift` installs no `ProjectDocumentController`,
so the launch logs the `Reelcut: ` complaint, spec §11 #234). `lsregister -u`
is run on a copy's built app before its tree is replaced and at the end of
its run. A mutant run exits 0 when every row it names FAILED (caught), 1
when one passed (survived), 2 when the control could not be performed.
"""

import argparse
import errno
import json
import os
import re
import select
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
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/agent-socket"
APP = proof_app.binary()
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
# name → (the row it must fail, or a tuple of rows that must ALL fail; the
# half of it (or None); file in app/Sources; before — exactly once; after)
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
    # Step B of `openProject`, unchanged since B79 moved the type into
    # `known` (the anchor had not matched since; re-anchored by B81).
    "open-asks": ("K12", "open", "AgentServer+Project.swift",
                  "        let made = try MediaImporter.withoutAsking {\n"
                  "            try controller.makeDocument(withContentsOf: url, ofType: known.type)\n"
                  "        }\n",
                  "        let made = try controller.makeDocument("
                  "withContentsOf: url, ofType: known.type)\n"),
    "fixed-path": ("K13", None, "AgentServer+Socket.swift",
                   "        Bundle.main.bundleURL.appendingPathComponent(\"Contents/Helpers/reelcut-mcp\")\n",
                   "        URL(fileURLWithPath: \"/Applications/Reelcut.app/Contents/Helpers/reelcut-mcp\")\n"),
    # A join: main waits while a real background thread waits on the lane
    # lock, which the in-flight export holds; the export's completion is
    # delivered on main (Exporter.swift), so the quit cannot complete. Not
    # `DispatchQueue.global().sync`: GCD runs that block inline on main, and
    # `serve` skips the lock on main (AgentLane.swift).
    "waits-for-call": (("K14", "K15"), None, "AppDelegate.swift",
                       "        AgentServer.shared.unbindSocket()\n",
                       "        let held = DispatchSemaphore(value: 0)\n"
                       "        DispatchQueue.global().async { _ = AgentLane.shared.serve("
                       "tool: \"get_project\", argumentsJSON: \"{}\"); held.signal() }\n"
                       "        held.wait()\n"
                       "        AgentServer.shared.unbindSocket()\n"),
    # No `ProjectDocumentController` is made, so the shared controller is
    # AppKit's own and the launch complains (spec §11 #234).
    "no-controller": ("Z1", None, "main.swift",
                      "ProjectDocumentController.install()\n", ""),
}
ORDER = ["P1", "K0", "K1", "K3", "K4", "K5", "K6", "K7", "K8", "K9", "K11", "K12", "K13",
         "K14", "K15", "Z1", "Z2"]
# The rows that need the app and K0: every K row after K0.
APP_ROWS = [name for name in ORDER if name.startswith("K") and name != "K0"]
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


def call(path, tool, arguments, timeout=60):
    result = rpc(path, "tools/call", {"name": tool, "arguments": arguments}, timeout=timeout)
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
    """One owned app, by PID, on its own scratch socket. `env` is added to
    the child's environment (K15's scratch home)."""

    def __init__(self, name, app, sock, extra=(), env=None):
        self.name, self.app, self.sock, self.extra = name, app, sock, list(extra)
        self.env = dict(env or {})
        self.log = WORK / f"{name}.log"
        self.child = None
        self.socket_line = None

    def start(self):
        self.log.write_text("")
        env = bounded.child_env({**self.env, "RC_AGENT_SOCKET": self.sock})
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

    def quit_script(self):
        """JavaScript for `osascript`: a quit event to THIS pid through
        NSRunningApplication, answering what `terminate` said."""
        return ("ObjC.import('AppKit');"
                f"var app = $.NSRunningApplication.runningApplicationWithProcessIdentifier("
                f"{self.child.pid});"
                "app.isNil() ? 'no such app' : String(app.terminate);")

    def quit_event(self):
        """A quit event to THIS pid through NSRunningApplication; answers
        (exited within QUIT_BOUND, seconds, the osascript result)."""
        if not self.alive():
            return False, 0.0, "not running"
        script = self.quit_script()
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
    `sources` through `swift_build.build`, into `probe_dir`; reused when
    every input is byte-identical to a cached build's. The binary, or None
    and why."""
    probe_dir.mkdir(parents=True, exist_ok=True)
    binary = probe_dir / "agent_socket_probe"
    entry = probe_dir / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, defines=["REELCUT_DEV_TOOLS"], timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc rc {error.rc if error.rc is not None else 'before running'}: "
                      f"{(error.diagnostics or ['(no output)'])[:6]}")
    print(f"  probe: up to date — {binary}" if built.reused
          else f"  probe: built in {built.seconds:.0f} s — {binary}", flush=True)
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


K14_SECONDS = 600
K14_SEC = 600_000
K14_READ_BOUND = 10


def row_k14(app):
    """A quit event with an `export` in flight over a raw socket."""
    folder = scratch_folder()
    sock = os.path.join(folder, "agent.sock")
    m = Instance("m", app, sock)
    up = m.start()
    raw = None
    try:
        if not up or m.socket_line != f"listening at {sock}":
            check("K14", False, f"M did not bind: {m.socket_line!r}")
            return
        project = call(sock, "new_project", {"path": os.path.join(folder, "k14.reelcut")})["saved"]
        tracks = call(sock, "get_project", {"project": project})["project"].get("tracks", [])
        if not tracks:
            call(sock, "add_track", {"project": project})
            tracks = call(sock, "get_project", {"project": project})["project"]["tracks"]
        call(sock, "add_shape_clip", {
            "project": project, "track": tracks[0]["id"], "at": 0,
            "duration": K14_SECONDS * K14_SEC,
            "shape": {"kind": "rectangle", "width": 1920, "height": 1080, "stroke": None,
                      "fill": [192 / 255.0, 192 / 255.0, 192 / 255.0, 1.0]}})
        call(sock, "save_project", {"project": project})
        unsaved = call(sock, "get_project", {"project": project}).get("unsaved_changes")
        if unsaved is not False:
            check("K14", False, f"CONTROL C1: unsaved_changes {unsaved!r} after save_project "
                                f"(M is stopped by SIGTERM, not a quit event)")
            return
        body = json.dumps({"jsonrpc": "2.0", "id": 14, "method": "tools/call", "params": {
            "name": "export", "arguments": {"project": project, "preset": "h264",
                                            "path": os.path.join(folder, "k14.mov")}}}).encode()
        raw = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        raw.settimeout(10)
        raw.connect(sock)
        raw.sendall(b"POST /mcp HTTP/1.1\r\nHost: localhost\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Accept: application/json, text/event-stream\r\n"
                    b"Connection: close\r\n"
                    + f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        time.sleep(2)
        readable, _, _ = select.select([raw], [], [], 0)
        if readable:
            check("K14", False, "CONTROL C2: the export's connection had bytes to read 2 s "
                                "after it was sent — the call was not in flight at the quit")
            return
        exited, seconds, said = m.quit_event()
        received, close = 0, "timeout"
        raw.settimeout(K14_READ_BOUND)
        try:
            while True:
                chunk = raw.recv(65536)
                if not chunk:
                    close = "EOF"
                    break
                received += len(chunk)
        except ConnectionResetError:
            close = "reset"
        except socket.timeout:
            close = "timeout"
        gone = ident(sock) is None
        check("K14", exited and gone and received == 0 and close in ("EOF", "reset"),
              f"C1 saved; C2 in flight; M exited {exited} in {seconds} s ({said}); socket file "
              f"gone {gone}; {received} bytes received; closed by {close}")
    finally:
        if raw is not None:
            raw.close()
        m.stop()


K15_MEGABYTES = 512
K15_ARM_BOUND = 30
K15_PARTIAL_BOUND = 120
K15_SENDER_BOUND = 300
K15_OPEN_BOUND = 300
K15_PARTIAL = re.compile(r"^big-[0-9a-f]{16}\.partial\.mov$")
K15_MOVIE = re.compile(r"^big-[0-9a-f]{16}\.mov$")


def k15_sender(instance, armed, trigger):
    """The quit sender, armed before the call: one bounded `osascript` that
    writes `armed`, polls for `trigger` every 10 ms and then sends
    `instance` K14's quit event. A `bounded.Background`."""
    script = ("ObjC.import('AppKit');"
              f"var app = $.NSRunningApplication.runningApplicationWithProcessIdentifier("
              f"{instance.child.pid});"
              "var files = $.NSFileManager.defaultManager;"
              f"files.createFileAtPathContentsAttributes({json.dumps(str(armed))}, $(), $());"
              "var said = 'no trigger';"
              f"for (var i = 0; i < {K15_SENDER_BOUND * 100}; i++) {{"
              f"  if (files.fileExistsAtPath({json.dumps(str(trigger))})) {{"
              "    said = app.isNil() ? 'no such app' : String(app.terminate);"
              "    break;"
              "  }"
              "  $.NSThread.sleepForTimeInterval(0.01);"
              "}"
              "said;")
    return bounded.Background(["osascript", "-l", "JavaScript", "-e", script],
                              K15_SENDER_BOUND + 30)


def row_k15(app, megabytes):
    """A quit event with an `open_project` read in flight (spec §11 #231)."""
    import agent_open_proof  # the fixture's one maker
    home, fixtures = WORK / "k15-home", WORK / "k15"
    for folder in (home, fixtures):
        shutil.rmtree(folder, ignore_errors=True)
        folder.mkdir(parents=True)
    support = home / "Library/Application Support"
    rewrapped = support / "Reelcut/Rewrapped"
    scratch = {"CFFIXED_USER_HOME": str(home)}
    sock = os.path.join(scratch_folder(), "agent.sock")
    n = Instance("n", app, sock, env=scratch)
    raw = sender = n2 = None
    try:
        up = n.start()
        if not up or n.socket_line != f"listening at {sock}":
            check("K15", False, f"N did not bind: {n.socket_line!r}")
            return
        if not support.is_dir():
            check("K15", False, f"CONTROL C0: {support} does not exist after N bound, so the "
                                f"scratch home did not take (N is stopped by SIGTERM; no call "
                                f"was made)")
            return
        fixture, why = agent_open_proof.make_fixture(megabytes, str(fixtures))
        if fixture is None:
            check("K15", False, f"the fixture was not made: {why}")
            return
        size = os.path.getsize(fixture) / (1024 * 1024)
        armed, trigger = fixtures / "armed", fixtures / "quit-now"
        sender = k15_sender(n, armed, trigger)
        deadline = time.monotonic() + K15_ARM_BOUND
        while not armed.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        if not armed.exists():
            check("K15", False, f"the quit sender was not armed within {K15_ARM_BOUND} s")
            return
        body = json.dumps({"jsonrpc": "2.0", "id": 15, "method": "tools/call", "params": {
            "name": "open_project", "arguments": {"path": fixture}}}).encode()
        raw = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        raw.settimeout(10)
        raw.connect(sock)
        raw.sendall(b"POST /mcp HTTP/1.1\r\nHost: localhost\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Accept: application/json, text/event-stream\r\n"
                    b"Connection: close\r\n"
                    + f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        sent = time.monotonic()
        seen, early = None, False
        while time.monotonic() - sent < K15_PARTIAL_BOUND:
            names = os.listdir(rewrapped) if rewrapped.is_dir() else []
            if any(name.endswith(".partial.mov") for name in names):
                seen = round(time.monotonic() - sent, 3)
                break
            if select.select([raw], [], [], 0)[0]:
                early = True
                break
            time.sleep(0.01)
        if seen is None:
            check("K15", False,
                  (f"the call answered before a .partial.mov was seen in {rewrapped}" if early
                   else f"no .partial.mov in {rewrapped} within {K15_PARTIAL_BOUND} s")
                  + f" (a {size:.1f} MiB fixture; --k15-megabytes {megabytes})")
            return
        if select.select([raw], [], [], 0)[0]:
            check("K15", False, f"CONTROL C2: the call's connection had bytes to read when its "
                                f".partial.mov was seen — it answered before the quit: raise "
                                f"--k15-megabytes (now {megabytes})")
            return
        trigger.write_text("quit\n")
        started = time.monotonic()
        try:
            n.child.wait(timeout=QUIT_BOUND)
            exited = True
        except subprocess.TimeoutExpired:
            exited = False
        seconds = round(time.monotonic() - started, 2)
        received, close = 0, "timeout"
        raw.settimeout(K14_READ_BOUND)
        try:
            while True:
                chunk = raw.recv(65536)
                if not chunk:
                    close = "EOF"
                    break
                received += len(chunk)
        except ConnectionResetError:
            close = "reset"
        except socket.timeout:
            close = "timeout"
        gone = ident(sock) is None
        left = sorted(os.listdir(rewrapped)) if rewrapped.is_dir() else []
        partial_only = len(left) == 1 and bool(K15_PARTIAL.match(left[0]))
        # The trigger is written, so the sender ends on its own within its
        # next poll: its answer is read whether or not N exited.
        said, sender = sender.finish(), None
        quit_half = exited and gone and received == 0 and close in ("EOF", "reset") and partial_only
        answered = (f"; the call ANSWERED before the quit ({received} bytes): raise "
                    f"--k15-megabytes (now {megabytes})") if received else ""
        detail = (f"C0 the scratch home took; a {size:.1f} MiB fixture; the .partial.mov seen "
                  f"{seen} s into the call; C2 in flight; N exited {exited} in {seconds} s "
                  f"(osascript rc {said['rc']}: "
                  f"{' '.join(line for _, line in said['lines'])}); socket file gone {gone}; "
                  f"{received} bytes received; closed by {close}; Rewrapped/ holds {left}"
                  f"{answered}")
        if not quit_half:
            check("K15", False, detail)
            return

        # N2, on the same scratch home: the next open copies again and
        # removes the partial the quit left (#228-P O8).
        sock2 = os.path.join(scratch_folder(), "agent.sock")
        n2 = Instance("n2", app, sock2, env=scratch)
        up2 = n2.start()
        if not up2 or n2.socket_line != f"listening at {sock2}":
            check("K15", False, detail + f"; N2 did not bind: {n2.socket_line!r}")
            return
        opened = call(sock2, "open_project", {"path": fixture}, timeout=K15_OPEN_BOUND)
        media = call(sock2, "get_project", {"project": fixture})["project"]["media"]
        path = media[0]["path"] if media else ""
        after = sorted(os.listdir(rewrapped))
        named = (os.path.realpath(os.path.dirname(path)) == os.path.realpath(rewrapped)
                 and bool(K15_MOVIE.match(os.path.basename(path))))
        # A WebM opens as an untitled project with unsaved changes, and a
        # quit's document review would put a save sheet up and never exit:
        # the project is closed first, so no sheet can appear (K14's C1).
        closed = call(sock2, "close_project", {"project": fixture, "discard": True})
        n2_exited, n2_seconds, n2_said = n2.quit_event()
        check("K15", "project" in opened and len(media) == 1 and named and os.path.exists(path)
              and after == [os.path.basename(path)] and closed.get("ok") is True and n2_exited,
              detail + f". Then N2 on the same home: open_project answers keys {sorted(opened)}; "
              f"media {len(media)}, path {path!r} (in the scratch Rewrapped/, named: {named}), "
              f"on disk {os.path.exists(path)}; Rewrapped/ holds {after}; close_project "
              f"{{discard: true}} ok {closed.get('ok')}; N2 exited {n2_exited} in {n2_seconds} s "
              f"({n2_said})")
    finally:
        if raw is not None:
            raw.close()
        n.stop()
        if n2 is not None:
            n2.stop()
        if sender is not None:
            # The trigger never came: end the sender now (its own group; a
            # group that has already gone answers either error).
            try:
                os.killpg(sender.child.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            sender.finish()
        for folder in (home, fixtures):
            shutil.rmtree(folder, ignore_errors=True)


# ---- the K rows -------------------------------------------------------------------

def run_rows(app, megabytes=K15_MEGABYTES):
    tmp = os.path.realpath(os.environ.get("TMPDIR") or tempfile.gettempdir())
    shared = scratch_folder()
    path = os.path.join(shared, "agent.sock")
    folder_mode = stat.S_IMODE(os.stat(shared).st_mode)
    real = os.path.realpath(path)
    check("K0", len(path.encode()) <= MAX_PATH and real.startswith(tmp + os.sep)
          and not real.startswith(str(SUPPORT.resolve()) + os.sep) and folder_mode == 0o700,
          f"{path} ({len(path.encode())} bytes), folder {oct(folder_mode)}")
    if not rows["K0"]:
        for name in APP_ROWS:
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

    # K14 — a quit with an agent call in flight (#224).
    try:
        row_k14(app)
    except Exception as error:  # noqa: BLE001
        check("K14", False, f"the row broke: {type(error).__name__}: {error}")

    # K15 — a quit with an open_project read in flight (#231).
    try:
        row_k15(app, megabytes)
    except Exception as error:  # noqa: BLE001
        check("K15", False, f"the row broke: {type(error).__name__}: {error}")


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
    return proof_app.bundle(tree)


def unregister(tree):
    """`lsregister -u` on a copy's built app, when there is one."""
    app = built_app(tree)
    if app.exists():
        done = bounded.run([mcp.LSREGISTER, "-u", str(app)], 60)
        print(f"  lsregister -u {app}: rc {done['rc']}", flush=True)


def build_mutant_app(name):
    """A tree copy with the mutant's anchor replaced once, built by its own
    `tree_copy.build_app`: the binary, or None and why."""
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
    print(f"  mutant {name}: building {made}", flush=True)
    app, reason = tree_copy.build_app(made, 1500)
    if app is None:
        return None, reason
    return app / "Contents/MacOS/Reelcut", ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--k15-megabytes", type=int, default=K15_MEGABYTES,
                        help="K15's fixture's least size, in MiB")
    args = parser.parse_args()
    started = time.monotonic()
    WORK.mkdir(parents=True, exist_ok=True)

    app = args.app
    if args.mutant:
        row, half = MUTANTS[args.mutant][:2]
        targets = row if isinstance(row, tuple) else (row,)
        named = " and ".join(targets)
        print(f"agent socket — the {args.mutant} MUTANT ({named}{f' {half} half' if half else ''} "
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
            for name in ["K0"] + APP_ROWS:
                check(name, False, f"not run: no app at {app}")
        else:
            run_rows(app, args.k15_megabytes)
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
        targets = row if isinstance(row, tuple) else (row,)
        named = " and ".join(targets)
        if (any(name not in rows for name in targets) or not rows.get("K0", False)
                or (half and half not in halves)):
            print(f"mutant {args.mutant}: the control could not be performed — "
                  f"{named}{f' ({half} half)' if half else ''} was not scored or K0 failed")
            return 2
        caught = (halves.get(half) is False) if half else all(
            rows[name] is False for name in targets)
        passed = ", ".join(name for name in targets if rows[name])
        verdict = "FAIL — caught" if caught else "ok — survived"
        if not caught and not half:
            verdict += f" ({passed} passed)"
        print(f"mutant {args.mutant}: {named}{f' {half} half' if half else ''} "
              f"{verdict} in {seconds:.0f} s")
        return 0 if caught else 1
    passed = sum(1 for good in rows.values() if good)
    tail = f"; skipped {', '.join(f'{k}: {v}' for k, v in skips.items())}" if skips else ""
    print(f"{passed}/{len(rows)} in {seconds:.0f} s{tail}")
    complete = all(name in rows or name in skips for name in ORDER)
    return 0 if all(rows.values()) and complete and not skips else 1


if __name__ == "__main__":
    sys.exit(main())
