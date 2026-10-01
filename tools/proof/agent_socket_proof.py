#!/usr/bin/env python3
"""Road map 14's MC2, against the built app: the agent server's Unix socket
beside its TCP listener (spec §11 MC-1, MC-2, MC-6; MC1's S1–S10).

Every instance is a `Popen` this script owns, launched with
`-ApplePersistenceIgnoreState YES -AgentServerEnabled YES` and its own
`RC_AGENT_PORT` (`--port` + k), and every one but K10's also gets
`RC_AGENT_SOCKET` in a `tempfile.mkdtemp(prefix="rcs-")` folder under
`$TMPDIR` (MC1: a path under `tools/proof/work/` can pass 103 bytes). Logs go
to `tools/proof/work/agent-socket/<name>-<port>.log`; every other child (the
probe's build, the probe, `osascript`, `make app`) runs under
`graphics_spike/bounded.py`. HTTP over AF_UNIX is a local
`http.client.HTTPConnection` subclass (MC4 moves it into `mcp.py`). Nothing
is signalled but this script's own pids, and nothing under
`~/Library/Application Support/Reelcut/` is created, written or unlinked —
K10 only `lstat`s.

P1  (probe) `AgentServer.socketPlan`: `.bind(default)` for `{}`; `.skip`
    naming RC_AGENT_PORT for `{RC_AGENT_PORT: "4941"}`; `.bind(s)` for the
    port plus socket `s`; `.bind(default)` for an empty RC_AGENT_SOCKET;
    `.skip("no Application Support folder")` for `{}` with a nil default.
    `agent_socket_probe.swift`, built like `export_cancel_proof.build_probe`
    (Swift sources and the staticlib only) into `work/agent-socket/probe/`.
K0  CONTROL: the scratch path is ≤ 103 bytes, under $TMPDIR, not under the
    person's support folder, and its folder is 0700.
K1  A logs `listening at <path>`; the file is a socket, mode 0600.
K2  the raw `tools/list` response body is byte-equal over the socket and TCP.
K3  `new_project` (a scratch path); `add_marker` over the socket is read back
    by `get_project` over TCP, and one over TCP is read back over the socket.
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
K10 run ONLY when P1 is ok: G with RC_AGENT_PORT and no RC_AGENT_SOCKET logs
    `not bound: RC_AGENT_PORT is set…`, and `lstat` of the default `Agent/`
    folder and `agent.sock` answer the same before the launch and after G's
    quit (absent stays absent; present keeps dev and ino).
Z1  no `Reelcut: ` in any log.  Z2  no proof pid alive.

    python3 tools/proof/agent_socket_proof.py [--port 4941] [--app PATH]
        [--mutant no-connect-first|no-mode-check|no-port-rule]

Any FAIL exits 1; an instrument that cannot run is a FAIL, never a skip.
`--mutant no-connect-first` (K4 must FAIL) and `--mutant no-mode-check` (K8
must FAIL) replace one anchor in `AgentServer+Socket.swift` in a
`tree_copy.make_copy` copy built by its own `make app`, and run every row
against that build. `--mutant no-port-rule` (P1 must FAIL) removes the port
arm in a copy of `app/Sources` and builds and runs ONLY the probe — no app is
launched, so the person's socket is never at risk. A mutant run exits 0 when
its row FAILED (caught), 1 when it passed (survived), 2 when the control
could not be performed.
"""

import argparse
import errno
import http.client
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
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/agent-socket"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
PROBE_SOURCE = ROOT / "tools/proof/agent_socket_probe.swift"
SOURCES = ROOT / "app/Sources"
SUPPORT = Path.home() / "Library/Application Support/Reelcut"
MAX_PATH = 103
LAUNCH_BOUND = 60
QUIT_BOUND = 20
PORT_REASON = ("RC_AGENT_PORT is set and RC_AGENT_SOCKET is not; "
               "a port-only launch binds no socket until MC4")
# name → (the row it must fail, file in app/Sources, before — exactly once, after)
MUTANTS = {
    "no-connect-first": ("K4", "AgentServer+Socket.swift",
                         "        let answer = connectErrno(toSocketAt: path)\n",
                         "        let answer = ECONNREFUSED\n"),
    "no-mode-check": ("K8", "AgentServer+Socket.swift",
                      "        if folderInfo.st_mode & 0o077 != 0 { return modeSentence(folder, "
                      "folderInfo.st_mode) }\n",
                      ""),
    "no-port-rule": ("P1", "AgentServer+Socket.swift",
                     "        if environment[\"RC_AGENT_PORT\"] != nil { return .skip(reason: "
                     "portOnlyReason) }\n",
                     ""),
}
ORDER = ["P1", "K0", "K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "K9", "K10", "Z1", "Z2"]
rows = {}
INSTANCES = []
SCRATCH = []


def check(name, good, detail=""):
    rows[name] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"  {detail}" if detail else ""),
          flush=True)


# ---- HTTP over a socket or a port ---------------------------------------------

class UnixHTTPConnection(http.client.HTTPConnection):
    """`http.client` over AF_UNIX: the host is only the Host header."""

    def __init__(self, path, timeout=30):
        super().__init__("localhost", timeout=timeout)
        self.socket_path = path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self.socket_path)
        self.sock = sock


def post(where, body, timeout=60):
    """One POST to /mcp: `where` is a socket path (str) or a TCP port (int).
    Answers (status, raw body bytes)."""
    if isinstance(where, int):
        connection = http.client.HTTPConnection("127.0.0.1", where, timeout=timeout)
    else:
        connection = UnixHTTPConnection(where, timeout=timeout)
    try:
        connection.request("POST", "/mcp", body=body, headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream"})
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


def rpc(where, method, params=None, request_id=1):
    body = json.dumps({"jsonrpc": "2.0", "id": request_id, "method": method,
                       "params": params or {}}).encode()
    status, raw = post(where, body)
    answer = json.loads(raw)
    if status != 200 or "error" in answer:
        raise RuntimeError(f"{method}: HTTP {status} {answer.get('error')}")
    return answer["result"]


def call(where, tool, arguments):
    result = rpc(where, "tools/call", {"name": tool, "arguments": arguments})
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
    """One owned app, by PID, on its own port and (maybe) its own socket."""

    def __init__(self, name, app, port, sock):
        self.name, self.app, self.port, self.sock = name, app, port, sock
        self.log = WORK / f"{name}-{port}.log"
        self.child = None
        self.socket_line = None
        self.tcp_port = None

    def start(self):
        self.log.write_text("")
        env = bounded.child_env({"RC_AGENT_PORT": str(self.port)})
        env.pop("RC_AGENT_SOCKET", None)
        if self.sock is not None:
            env["RC_AGENT_SOCKET"] = self.sock
        with open(self.log, "a") as out:
            self.child = subprocess.Popen(
                [str(self.app), "-ApplePersistenceIgnoreState", "YES",
                 "-AgentServerEnabled", "YES"],
                stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
                env=env)
        INSTANCES.append(self)
        deadline = time.monotonic() + LAUNCH_BOUND
        while time.monotonic() < deadline:
            time.sleep(0.25)
            text = self.log.read_text(errors="replace")
            tcp = re.search(r"listening on http://127\.0\.0\.1:(\d+)/mcp", text)
            line = re.search(r"Reelcut agent socket (listening at .*|not bound: .*)", text)
            if tcp and line:
                self.tcp_port = int(tcp.group(1))
                self.socket_line = line.group(1).strip()
                print(f"  {self.name}: PID {self.child.pid}, port {self.tcp_port}; "
                      f"socket {self.socket_line}", flush=True)
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


def mutant_sources(name):
    """(WORK/mutant-<name>/Sources, "") — app/Sources copied with the
    mutant's anchor replaced exactly once — or (None, why)."""
    _, file, before, after = MUTANTS[name]
    target = WORK / f"mutant-{name}" / "Sources"
    try:
        shutil.rmtree(target, ignore_errors=True)
        target.mkdir(parents=True)
        for path in sorted(SOURCES.glob("*.swift")):
            shutil.copy2(path, target / path.name)
        text = (target / file).read_text()
        if text.count(before) != 1:
            return None, f"{file} holds {before!r} {text.count(before)} times, not once"
        (target / file).write_text(text.replace(before, after))
    except OSError as error:
        return None, f"the copy could not be made: {error}"
    return target, ""


def row_p1(sources, probe_dir):
    """P1; answers the default socket path the probe printed (or None)."""
    binary, why = build_probe(sources, probe_dir)
    if binary is None:
        check("P1", False, f"the probe did not build: {why}")
        return None
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
        "port": {"plan": "skip", "reason": PORT_REASON},
        "port+socket": {"plan": "bind", "path": scratch},
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
    return meta.get("path")


# ---- the K rows -------------------------------------------------------------------

def run_rows(app, port, default_path):
    tmp = os.path.realpath(os.environ.get("TMPDIR") or tempfile.gettempdir())
    shared = scratch_folder()
    path = os.path.join(shared, "agent.sock")
    folder_mode = stat.S_IMODE(os.stat(shared).st_mode)
    real = os.path.realpath(path)
    check("K0", len(path.encode()) <= MAX_PATH and real.startswith(tmp + os.sep)
          and not real.startswith(str(SUPPORT.resolve()) + os.sep) and folder_mode == 0o700,
          f"{path} ({len(path.encode())} bytes), folder {oct(folder_mode)}")
    if not rows["K0"]:
        for name in ORDER[2:12]:
            check(name, False, "not run: K0 failed")
        return

    # K1 — A binds.
    a = Instance("a", app, port, path)
    up = a.start()
    info = ident(path)
    is_sock = info is not None and stat.S_ISSOCK(info[2])
    mode = stat.S_IMODE(info[2]) if info else None
    check("K1", up and a.socket_line == f"listening at {path}" and is_sock and mode == 0o600,
          f"line {a.socket_line!r}; socket {is_sock}; mode {oct(mode) if mode is not None else None}")

    # K2 — the same tools/list bytes.
    body = json.dumps({"jsonrpc": "2.0", "id": 7, "method": "tools/list", "params": {}}).encode()
    try:
        over_socket = post(path, body)
        over_tcp = post(a.tcp_port, body)
        tools = len(json.loads(over_socket[1])["result"]["tools"])
        check("K2", over_socket[0] == over_tcp[0] == 200 and over_socket[1] == over_tcp[1],
              f"{len(over_socket[1])} vs {len(over_tcp[1])} bytes, {tools} tools, "
              f"status {over_socket[0]}/{over_tcp[0]}")
    except Exception as error:
        check("K2", False, f"{type(error).__name__}: {error}")

    # K3 — an edit over one is read back over the other.
    project = str(WORK / f"k3-{os.getpid()}.reelcut")
    shutil.rmtree(project, ignore_errors=True)
    try:
        call(path, "new_project", {"path": project})
        call(path, "add_marker", {"project": project, "at": 600_000, "name": "via-socket"})
        seen_tcp = call(a.tcp_port, "get_project", {"project": project})
        call(a.tcp_port, "add_marker", {"project": project, "at": 1_200_000, "name": "via-tcp"})
        seen_socket = call(path, "get_project", {"project": project})

        def names(state):
            return {(m.get("name"), m.get("time"))
                    for m in (state.get("project") or {}).get("markers", [])}
        first = ("via-socket", 600_000) in names(seen_tcp)
        second = ("via-tcp", 1_200_000) in names(seen_socket)
        check("K3", first and second,
              f"socket's marker read over TCP {first}; TCP's read over the socket {second}")
    except Exception as error:
        check("K3", False, f"{type(error).__name__}: {error}")

    # K4 — B finds A answering and binds none.
    before = ident(path)
    b = Instance("b", app, port + 1, path)
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
    c = Instance("c", app, port + 2, path)
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
    d = Instance("d", app, port + 3, path)
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
    e = Instance("e", app, port + 4, open_path)
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
    f = Instance("f", app, port + 5, file_path)
    f_up = f.start()
    f.stop()
    kept_bytes = Path(file_path).read_bytes() == payload if os.path.exists(file_path) else False
    want_f = f"not bound: {file_path} exists and is not a socket; it is left alone"
    check("K9", f_up and f.socket_line == want_f and kept_bytes,
          f"F {f.socket_line!r}; bytes unchanged {kept_bytes}")

    # K10 — a port-only launch leaves the person's socket path as it was.
    if not rows.get("P1"):
        check("K10", False, "not run: P1 failed")
        return
    if not default_path or Path(default_path) != SUPPORT / "Agent/agent.sock":
        check("K10", False, f"the probe's default path {default_path!r} is not "
              f"{SUPPORT / 'Agent/agent.sock'}")
        return
    agent_dir = str(SUPPORT / "Agent")
    before_dir, before_sock = ident(agent_dir), ident(default_path)
    g = Instance("g", app, port + 6, None)
    g_up = g.start()
    g_exited, g_seconds, g_said = g.quit_event() if g_up else (False, 0.0, "not up")
    g.stop()
    after_dir, after_sock = ident(agent_dir), ident(default_path)

    def same_as(one, two):
        return (one is None and two is None) or (one is not None and two is not None
                                                 and one[:2] == two[:2])
    unchanged = same_as(before_dir, after_dir) and same_as(before_sock, after_sock)
    check("K10", g_up and g.socket_line == f"not bound: {PORT_REASON}" and g_exited
          and unchanged,
          f"G {g.socket_line!r}; exited {g_exited} in {g_seconds} s ({g_said}); Agent/ "
          f"{'absent' if before_dir is None else 'present'} → "
          f"{'absent' if after_dir is None else 'present'}, agent.sock "
          f"{'absent' if before_sock is None else 'present'} → "
          f"{'absent' if after_sock is None else 'present'}; unchanged {unchanged}")


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


def build_mutant_app(name):
    """A tree copy with the mutant's anchor replaced once, built by its own
    `make app`: the binary, or None and why."""
    _, file, before, after = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / f"mutant-{name}" / "tree"))
    if made is None:
        return None, reason
    target = Path(made) / "app/Sources" / file
    text = target.read_text()
    if text.count(before) != 1:
        return None, f"{file} holds {before!r} {text.count(before)} times, not once"
    target.write_text(text.replace(before, after))
    print(f"  mutant {name}: make app in {made}", flush=True)
    built = bounded.run(["make", "app"], 1500, cwd=made)
    binary = Path(made) / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error:" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    return binary, ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=4941)
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    started = time.monotonic()
    WORK.mkdir(parents=True, exist_ok=True)

    if args.mutant == "no-port-rule":
        print("agent socket — the no-port-rule MUTANT (P1 must FAIL; probe only)", flush=True)
        sources, why = mutant_sources(args.mutant)
        if sources is None:
            print(f"mutant no-port-rule: the control could not be performed — {why}")
            return 2
        binary, why = build_probe(sources, WORK / "mutant-no-port-rule" / "probe")
        if binary is None:
            print(f"mutant no-port-rule: the control could not be performed — the probe did "
                  f"not build: {why}")
            return 2
        row_p1(sources, WORK / "mutant-no-port-rule" / "probe")
        caught = rows.get("P1") is False
        print(f"mutant no-port-rule: P1 {'FAIL — caught' if caught else 'ok — survived'} "
              f"in {time.monotonic() - started:.0f} s")
        return 0 if caught else 1

    app = args.app
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        print(f"agent socket — the {args.mutant} MUTANT ({row} must FAIL)", flush=True)
        app, why = build_mutant_app(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"agent socket — {app}", flush=True)

    try:
        default_path = row_p1(SOURCES, WORK / "probe")
        if not Path(app).exists():
            for name in ORDER[1:12]:
                check(name, False, f"not run: no app at {app}")
        else:
            run_rows(app, args.port, default_path)
    except Exception as error:  # an instrument that breaks is a FAIL, not an exit
        check("K?", False, f"the proof broke: {type(error).__name__}: {error}")
    finally:
        finish_z()
        for folder in SCRATCH:
            shutil.rmtree(folder, ignore_errors=True)

    seconds = time.monotonic() - started
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        if row not in rows or not rows.get("K0", False):
            print(f"mutant {args.mutant}: the control could not be performed — "
                  f"{row} was not scored or K0 failed")
            return 2
        caught = rows[row] is False
        print(f"mutant {args.mutant}: {row} {'FAIL — caught' if caught else 'ok — survived'} "
              f"in {seconds:.0f} s")
        return 0 if caught else 1
    passed = sum(1 for good in rows.values() if good)
    print(f"{passed}/{len(rows)} in {seconds:.0f} s")
    return 0 if all(rows.values()) and all(name in rows for name in ORDER) else 1


if __name__ == "__main__":
    sys.exit(main())
