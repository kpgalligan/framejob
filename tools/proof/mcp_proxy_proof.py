#!/usr/bin/env python3
"""Road map 14's MC3, against the built app: `framejob-mcp`, the bundled stdio
MCP server (spec §11 MC-3, MC-4, MC-6), driven as a client drives it, over its
stdin and stdout.

The app `proof_app.bundle()` chooses (`--app`; Debug unless `RC_PROOF_APP=release`) is
`ditto`ed to `work/mcp-proxy/<run>/Frame Job.app` and every proxy is that copy's
`Contents/Helpers/framejob-mcp`, so the bundle a proxy launches is the copy; the copy is removed at the end unless Z1 finds an
instance of it alive. Every socket is in its own
`tempfile.mkdtemp(prefix="rcm-")` under `$TMPDIR`, passed as `RC_AGENT_SOCKET`
(MC1: a path under `tools/proof/work/` can pass 103 bytes). An instance is any
pid `pgrep -f <copy>/Contents/MacOS/Frame Job` prints, and those are the only
pids ever signalled (SIGTERM, SIGKILL after 10 s); "N instances" counts the
pids new since the row began. Children run without `ANTHROPIC_API_KEY`,
`RC_ASSEMBLYAI_KEY`, `CLAUDECODE` or `CLAUDE_CODE_ENTRYPOINT`, under
`graphics_spike/bounded.py` where they are not interactive. Nothing under
`~/Library/Application Support/Frame Job/` is created, written or unlinked —
Z2 only `lstat`s — nothing is registered with Claude Code or Claude Desktop,
and no model is called.

X0  CONTROL: each socket path is ≤ 103 bytes, under $TMPDIR, not under the
    person's support folder.
X1  no instance: `initialize` (the negotiated version, `listChanged: true`,
    the bundle's version), `ping`, `tools/list` = the snapshot's `tools` as
    JSON; 3 s later no instance and no socket file.
X2  `tools/call get_project` with no instance: one instance appears, the
    answer is the app's (not a proxy sentence), the socket exists, and
    `<socket folder>/framejob-launch.log` exists.
X3  the proxy's forwarded `tools/list`, and the proof's own HTTP-over-AF_UNIX
    `tools/list`, each equal the snapshot's `tools` as JSON values.
X4  two proxies on a fresh socket, each `tools/call get_project` released
    together: both answer; exactly one instance.
X5  SIGKILL X2's instance mid-session; the same proxy's next `tools/call`
    launches exactly one new instance and answers.
X6  a 0755 scratch folder with `RC_MCP_LAUNCH_WAIT=5`: the call answers
    isError with the timeout sentence naming the copy, the socket and `5 s`,
    within 5–15 s; a second call on the same proxy answers isError with the
    stranded sentence within 2 s and starts no second instance (the one it
    started is then stopped).
X7  a stub (`socketserver.UnixStreamServer`, one request at a time; a
    connection closed before a request is ignored) holding `tools/call` 5 s:
    a `ping` sent 0.5 s in is answered before the call and within 1 s.
X7b the stub holding proxy A's `tools/call` 10 s: proxy B's `tools/list`
    sent 0.5 s in answers the snapshot's `tools` within 4.5–7 s.
X8  a stub, `tools/list` first served from the snapshot (the stub started
    after): a `tools/call` is followed by `notifications/tools/list_changed`
    when the stub lists other tools; CONTROL: none within 3 s when the stub
    lists the snapshot's tools with every object's keys reversed.
X9  every stdout line of every proxy parses as JSON-RPC 2.0.
X10 no `Frame Job: ` in any launch log.
Z1  no instance alive.  Z2  `lstat` of `~/Library/Application
    Support/Frame Job/Agent`, `…/agent.sock` and `…/agent.launch.lock` is
    identical before and after.

It also writes `work/mcp-proxy/ac-mcp.json`, `docs/manual-checks.md` AC-3's
fixture: an `mcpServers.framejob` entry whose command is the chosen app's
`Contents/Helpers/framejob-mcp` (the TREE's Release under `RC_PROOF_APP=release`,
as AC-3 runs it), with no env.

    python3 tools/proof/mcp_proxy_proof.py [--app PATH]
        [--mutant launch-on-list|no-lock]

Any FAIL exits 1; a row that cannot run is a FAIL, never a skip. A mutant
copies `mcp-proxy/` (no `target/`) and `core/src/mcp_versions.rs` into
`work/mcp-proxy/mutant-<name>/`, keeping their relative paths, replaces one
anchor found exactly once in `mcp-proxy/src/`, builds it with `cargo build
--release --offline`, puts the binary in a fresh bundle copy signed
`--options runtime` ad hoc, re-signs the copy ad hoc keeping its entitlements
and flags, and runs every row: `launch-on-list` (X1 must FAIL) launches on
`tools/list`, and `no-lock` (X4 must FAIL) drops the launch lock. A mutant run
exits 0 when its row FAILED (caught), 1 when it passed (survived), 2 when the
control could not be performed.
"""

import argparse
import http.client
import json
import os
import plistlib
import queue
import shutil
import signal
import socket
import socketserver
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import tree_copy  # noqa: E402
from mcp import LSREGISTER  # noqa: E402
import proof_app  # noqa: E402

WORK = ROOT / "tools/proof/work/mcp-proxy"
APP = proof_app.bundle()
SUPPORT = Path.home() / "Library/Application Support/Frame Job"
PERSON_PATHS = [SUPPORT / "Agent", SUPPORT / "Agent/agent.sock",
                SUPPORT / "Agent/agent.launch.lock"]
PROXY_RELATIVE = "Contents/Helpers/framejob-mcp"
SNAPSHOT_RELATIVE = "Contents/Resources/agent-catalog.json"
MAX_PATH = 103
CALL_BOUND = 90
DROP = ("ANTHROPIC_API_KEY", "RC_ASSEMBLYAI_KEY", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT",
        "RC_AGENT_SOCKET", "RC_MCP_LAUNCH_WAIT")
# How a proxy-side failure of a call begins (mcp-proxy/src): an answer that
# begins with none of these is the app's.
PROXY_SENTENCES = ("Frame Job did not answer at ", "could not connect to Frame Job",
                   "framejob-mcp is not inside", "/usr/bin/open ", "could not run /usr/bin/open",
                   "Frame Job answered HTTP", "Frame Job answered the call with no body",
                   "could not make ", "could not open ", "could not lock ",
                   "could not write to Frame Job", "could not read Frame Job's answer",
                   "Frame Job's answer at ", "HOME is not set")
# name → (the row it must fail, file in mcp-proxy/src, before — exactly once, after)
MUTANTS = {
    "launch-on-list": ("X1", "session.rs",
                       "        let answers = socket::reach(&path) == Reach::Answers;\n",
                       "        let answers = bundle::own_bundle()\n"
                       "            .and_then(|b| launch::ensure_running(&b, &path))\n"
                       "            .is_ok();\n"),
    "no-lock": ("X4", "launch.rs",
                "    lock.lock()\n"
                "        .map_err(|e| format!(\"could not lock {}: {e}\", lock_path.display()))?;\n",
                "    let _ = &lock;\n"),
}
ORDER = ["X0", "X1", "X2", "X3", "X4", "X5", "X6", "X7", "X7b", "X8", "X9", "X10", "Z1", "Z2"]
rows = {}
PROXIES = []
SCRATCH = []
STUBS = []


def check(name, good, detail=""):
    rows[name] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"  {detail}" if detail else ""),
          flush=True)


def child_env(extra=None):
    env = dict(os.environ)
    for key in DROP:
        env.pop(key, None)
    env.update(extra or {})
    return env


# ---- instances ----------------------------------------------------------------

class Copy:
    """The bundle copy this run drives, and its instances by pgrep."""

    def __init__(self, app):
        self.app = Path(app)
        self.real = os.path.realpath(self.app)
        self.exe = str(proof_app.executable(self.app))
        self.proxy = str(self.app / PROXY_RELATIVE)
        snapshot = json.loads((self.app / SNAPSHOT_RELATIVE).read_text())
        self.tools = snapshot["tools"]
        self.snapshot_version = snapshot["version"]
        with open(self.app / "Contents/Info.plist", "rb") as handle:
            self.version = plistlib.load(handle)["CFBundleShortVersionString"]

    def pids(self):
        found = bounded.run(["pgrep", "-f", self.exe], 30, env=child_env())
        return {int(pid) for pid in found["stdout"].split() if pid.strip().isdigit()}

    def stop(self, pids):
        """SIGTERM each, SIGKILL after 10 s; only pids pgrep named for the copy."""
        pids = set(pids) & self.pids()
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and (pids & self.pids()):
            time.sleep(0.2)
        for pid in pids & self.pids():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and (pids & self.pids()):
            time.sleep(0.2)

    def stop_all(self):
        self.stop(self.pids())


def scratch_folder(mode=None):
    folder = tempfile.mkdtemp(prefix="rcm-")
    SCRATCH.append(folder)
    if mode is not None:
        os.chmod(folder, mode)
    return folder


# ---- a proxy, driven over stdin and stdout -------------------------------------

class Proxy:
    """One `framejob-mcp` child: every stdout line is kept with its monotonic
    stamp, parsed or not, for X9."""

    def __init__(self, exe, sock, extra=None):
        self.sock = sock
        self.child = subprocess.Popen(
            [exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True, env=child_env(dict(extra or {}, RC_AGENT_SOCKET=sock)))
        self.lines = []          # (stamp, raw line)
        self.messages = queue.Queue()
        self.stderr = []
        self.seen = []           # messages taken while waiting for another
        self.next_id = 1
        self.lock = threading.Lock()
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._read_err, daemon=True).start()
        PROXIES.append(self)

    def _read(self):
        for raw in self.child.stdout:
            stamp = time.monotonic()
            text = raw.decode("utf-8", "replace").rstrip("\n")
            self.lines.append((stamp, text))
            try:
                message = json.loads(text)
            except ValueError:
                continue
            self.messages.put((stamp, message))

    def _read_err(self):
        for raw in self.child.stderr:
            self.stderr.append(raw.decode("utf-8", "replace").rstrip("\n"))

    def send(self, message):
        with self.lock:
            self.child.stdin.write((json.dumps(message) + "\n").encode())
            self.child.stdin.flush()
        return time.monotonic()

    def request(self, method, params=None):
        with self.lock:
            request_id = self.next_id
            self.next_id += 1
        sent = self.send({"jsonrpc": "2.0", "id": request_id, "method": method,
                          "params": params or {}})
        return request_id, sent

    def take(self, want, timeout):
        """The next message `want(message)` accepts within `timeout`, as
        (stamp, message), or (None, None); the others are kept in `seen`."""
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return None, None
            try:
                stamp, message = self.messages.get(timeout=left)
            except queue.Empty:
                return None, None
            if want(message):
                return stamp, message
            self.seen.append((stamp, message))

    def answer(self, request_id, timeout):
        for index, (stamp, message) in enumerate(self.seen):
            if message.get("id") == request_id and "method" not in message:
                del self.seen[index]
                return stamp, message
        return self.take(lambda m: m.get("id") == request_id and "method" not in m, timeout)

    def notification(self, method, timeout):
        for index, (stamp, message) in enumerate(self.seen):
            if message.get("method") == method and "id" not in message:
                del self.seen[index]
                return stamp, message
        return self.take(lambda m: m.get("method") == method and "id" not in m, timeout)

    def initialize(self):
        request_id, _ = self.request("initialize", {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "mcp-proxy-proof", "version": "1"}})
        _, answer = self.answer(request_id, 10)
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return answer

    def close(self):
        try:
            self.child.stdin.close()
        except OSError:
            pass
        try:
            self.child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(self.child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.child.wait()


def call_text(message):
    """(isError, the joined text) of a tools/call answer, or (None, why)."""
    if message is None:
        return None, "no answer"
    result = message.get("result")
    if not isinstance(result, dict):
        return None, f"not a result: {json.dumps(message)[:200]}"
    text = "".join(part.get("text", "") for part in result.get("content", [])
                   if isinstance(part, dict) and part.get("type") == "text")
    return bool(result.get("isError")), text


def apps_answer(message):
    """True when a tools/call answer is the app's: a result whose text begins
    with no proxy sentence."""
    is_error, text = call_text(message)
    if is_error is None:
        return False
    return not text.startswith(PROXY_SENTENCES)


# ---- HTTP over AF_UNIX ----------------------------------------------------------

class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout=30):
        super().__init__("localhost", timeout=timeout)
        self.socket_path = path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self.socket_path)
        self.sock = sock


def socket_tools(path):
    connection = UnixHTTPConnection(path)
    try:
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}})
        connection.request("POST", "/mcp", body=body, headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream"})
        response = connection.getresponse()
        return json.loads(response.read())["result"]["tools"]
    finally:
        connection.close()


# ---- the stub -------------------------------------------------------------------

def reversed_json(value):
    """`value` as JSON text with every object's keys in reverse sorted order."""
    if isinstance(value, dict):
        keys = sorted(value, reverse=True)
        return "{" + ",".join(json.dumps(k) + ":" + reversed_json(value[k]) for k in keys) + "}"
    if isinstance(value, list):
        return "[" + ",".join(reversed_json(item) for item in value) + "]"
    return json.dumps(value)


class Stub:
    """A stub agent server on a socket: one request at a time, as the app's
    is; a connection closed before a request is ignored. `tools_text` is the
    raw JSON text of the `tools` it lists; a `tools/call` is held `hold` s."""

    def __init__(self, path, tools_text, hold=0.0):
        stub = self

        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                try:
                    stub.serve(self.rfile, self.wfile)
                except OSError:
                    pass

        self.tools_text = tools_text
        self.hold = hold
        self.server = socketserver.UnixStreamServer(path, Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        STUBS.append(self)

    def serve(self, rfile, wfile):
        line = rfile.readline()
        if not line.strip():
            return
        length = 0
        while True:
            header = rfile.readline()
            if not header or header in (b"\r\n", b"\n"):
                break
            name, _, value = header.decode("latin-1").partition(":")
            if name.strip().lower() == "content-length":
                length = int(value.strip())
        message = json.loads(rfile.read(length) or b"null")
        method = message.get("method") if isinstance(message, dict) else None
        request_id = json.dumps(message.get("id") if isinstance(message, dict) else None)
        if method == "tools/list":
            body = f'{{"jsonrpc":"2.0","id":{request_id},"result":{{"tools":{self.tools_text}}}}}'
        elif method == "tools/call":
            time.sleep(self.hold)
            body = (f'{{"jsonrpc":"2.0","id":{request_id},"result":{{"content":[{{"type":"text",'
                    f'"text":"from the stub"}}],"isError":false}}}}')
        else:
            body = (f'{{"jsonrpc":"2.0","id":{request_id},"error":{{"code":-32601,'
                    f'"message":"stub"}}}}')
        data = body.encode()
        wfile.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                    + f"Content-Length: {len(data)}\r\nConnection: close\r\n\r\n".encode()
                    + data)
        wfile.flush()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


# ---- the rows -------------------------------------------------------------------

def ident(path):
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return None
    return (info.st_dev, info.st_ino, info.st_mode, info.st_mtime_ns)


def run_rows(copy):
    tmp = os.path.realpath(os.environ.get("TMPDIR") or tempfile.gettempdir())
    folders = {name: scratch_folder() for name in ("x1", "x2", "x4", "x7", "x7b", "x8", "x8c")}
    folders["x6"] = scratch_folder(0o755)
    socks = {name: os.path.join(folder, "agent.sock") for name, folder in folders.items()}
    bad = []
    for name, path in socks.items():
        real = os.path.realpath(os.path.dirname(path))
        if (len(path.encode()) > MAX_PATH or not real.startswith(tmp + os.sep)
                or real.startswith(str(SUPPORT.resolve()) + os.sep)):
            bad.append(f"{name}: {path} ({len(path.encode())} bytes)")
    check("X0", not bad, "; ".join(bad) if bad else
          f"{len(socks)} sockets, longest {max(len(p.encode()) for p in socks.values())} "
          f"bytes, all under {tmp}")
    if bad:
        for name in ORDER[1:9]:
            check(name, False, "not run: X0 failed")
        return

    # X1 — nothing launches for initialize, ping or tools/list.
    before = copy.pids()
    p1 = Proxy(copy.proxy, socks["x1"])
    init = p1.initialize() or {}
    result = init.get("result") or {}
    ping_id, _ = p1.request("ping")
    _, ping = p1.answer(ping_id, 10)
    list_id, _ = p1.request("tools/list")
    _, listed = p1.answer(list_id, 90)
    time.sleep(3)
    new = copy.pids() - before
    exists = os.path.lexists(socks["x1"])
    tools = ((listed or {}).get("result") or {}).get("tools")
    good = (result.get("protocolVersion") == "2025-06-18"
            and (result.get("capabilities") or {}).get("tools", {}).get("listChanged") is True
            and result.get("serverInfo") == {"name": "framejob", "version": copy.version}
            and (ping or {}).get("result") == {} and tools == copy.tools
            and not new and not exists)
    check("X1", good, f"initialize {result.get('protocolVersion')} listChanged "
          f"{(result.get('capabilities') or {}).get('tools')} serverInfo "
          f"{result.get('serverInfo')}; ping {(ping or {}).get('result')}; tools/list "
          f"{len(tools) if isinstance(tools, list) else tools} tools, = snapshot "
          f"{tools == copy.tools}; new instances {sorted(new)}; socket file {exists}")
    p1.close()
    copy.stop(new)

    # X2 — the first tools/call launches one instance and answers.
    before = copy.pids()
    p2 = Proxy(copy.proxy, socks["x2"])
    p2.initialize()
    list_id, _ = p2.request("tools/list")
    p2.answer(list_id, 10)
    call_id, sent = p2.request("tools/call", {"name": "get_project", "arguments": {}})
    stamp, called = p2.answer(call_id, CALL_BOUND)
    time.sleep(1)
    x2_pids = copy.pids() - before
    log = os.path.join(folders["x2"], "framejob-launch.log")
    is_error, text = call_text(called)
    took = round(stamp - sent, 2) if stamp else None
    is_socket = os.path.exists(socks["x2"]) and stat.S_ISSOCK(os.lstat(socks["x2"]).st_mode)
    check("X2", len(x2_pids) == 1 and apps_answer(called) and is_socket and os.path.exists(log),
          f"new instances {sorted(x2_pids)}; answered in {took} s, isError {is_error}: "
          f"{text[:120]!r}; socket {is_socket}; launch log {os.path.exists(log)}")

    # X3 — the live list equals the snapshot, through the proxy and directly.
    list_id, _ = p2.request("tools/list")
    _, listed = p2.answer(list_id, 30)
    through = ((listed or {}).get("result") or {}).get("tools")
    try:
        direct = socket_tools(socks["x2"])
        direct_note = f"{len(direct)} tools"
    except Exception as error:
        direct, direct_note = None, f"{type(error).__name__}: {error}"
    check("X3", through == copy.tools and direct == copy.tools,
          f"through the proxy = snapshot {through == copy.tools}; over the socket "
          f"({direct_note}) = snapshot {direct == copy.tools}")

    # X4 — two proxies released together launch one instance.
    before = copy.pids()
    p4a, p4b = Proxy(copy.proxy, socks["x4"]), Proxy(copy.proxy, socks["x4"])
    p4a.initialize()
    p4b.initialize()
    released = threading.Barrier(2)
    ids = {}

    def fire(name, proxy):
        released.wait()
        ids[name] = proxy.request("tools/call", {"name": "get_project", "arguments": {}})[0]
    threads = [threading.Thread(target=fire, args=(n, p)) for n, p in (("a", p4a), ("b", p4b))]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    _, a = p4a.answer(ids["a"], CALL_BOUND)
    _, b = p4b.answer(ids["b"], CALL_BOUND)
    time.sleep(3)
    x4_pids = copy.pids() - before
    check("X4", apps_answer(a) and apps_answer(b) and len(x4_pids) == 1,
          f"A {call_text(a)[1][:60]!r}; B {call_text(b)[1][:60]!r}; new instances "
          f"{sorted(x4_pids)}")
    p4a.close()
    p4b.close()
    copy.stop(x4_pids)

    # X5 — X2's instance killed; the same proxy relaunches one and answers.
    for pid in x2_pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and (x2_pids & copy.pids()):
        time.sleep(0.2)
    before = copy.pids()
    call_id, _ = p2.request("tools/call", {"name": "get_project", "arguments": {}})
    _, called = p2.answer(call_id, CALL_BOUND)
    time.sleep(1)
    x5_pids = copy.pids() - before
    check("X5", not (x2_pids & copy.pids()) and apps_answer(called) and len(x5_pids) == 1,
          f"X2's {sorted(x2_pids)} gone {not (x2_pids & copy.pids())}; answer "
          f"{call_text(called)[1][:80]!r}; new instances {sorted(x5_pids)}")

    # X6 — a launch that never binds strands the session.
    before = copy.pids()
    p6 = Proxy(copy.proxy, socks["x6"], {"RC_MCP_LAUNCH_WAIT": "5"})
    p6.initialize()
    call_id, sent = p6.request("tools/call", {"name": "get_project", "arguments": {}})
    stamp, first = p6.answer(call_id, 30)
    first_s = (stamp - sent) if stamp else None
    after_first = copy.pids() - before
    call_id, sent = p6.request("tools/call", {"name": "get_project", "arguments": {}})
    stamp, second = p6.answer(call_id, 10)
    second_s = (stamp - sent) if stamp else None
    time.sleep(2)
    x6_pids = copy.pids() - before
    timeout = (f"Frame Job did not answer at {socks['x6']} within 5 s of launching "
               f"{copy.real}")
    stranded = (f"{timeout}; that instance may still be running, so this session will not "
                f"launch another — quit it and check {folders['x6']}")
    e1, t1 = call_text(first)
    e2, t2 = call_text(second)
    check("X6", e1 is True and t1 == timeout and first_s is not None and 5 <= first_s <= 15
          and e2 is True and t2 == stranded and second_s is not None and second_s <= 2
          and len(after_first) == 1 and x6_pids == after_first,
          f"first in {first_s and round(first_s, 2)} s, isError {e1}, timeout sentence "
          f"{t1 == timeout} ({t1[:90]!r}); second in {second_s and round(second_s, 2)} s, "
          f"isError {e2}, stranded sentence {t2 == stranded}; instances {sorted(after_first)} "
          f"then {sorted(x6_pids)}")
    p6.close()
    copy.stop(x6_pids)

    # X7 — a ping is answered while a call is held.
    stub7 = Stub(socks["x7"], json.dumps(copy.tools), hold=5)
    p7 = Proxy(copy.proxy, socks["x7"])
    p7.initialize()
    call_id, _ = p7.request("tools/call", {"name": "get_project", "arguments": {}})
    time.sleep(0.5)
    ping_id, ping_sent = p7.request("ping")
    ping_stamp, ping = p7.answer(ping_id, 2)
    call_stamp, called = p7.answer(call_id, 15)
    before_call = bool(ping_stamp and call_stamp and ping_stamp < call_stamp)
    ping_s = round(ping_stamp - ping_sent, 3) if ping_stamp else None
    check("X7", ping is not None and called is not None and before_call
          and ping_s is not None and ping_s <= 1,
          f"ping answered in {ping_s} s; before the call {before_call}; the call answered "
          f"{called is not None}")
    p7.close()
    stub7.close()

    # X7b — another client's held call does not hold tools/list past 5 s.
    stub7b = Stub(socks["x7b"], json.dumps([{"name": "stub_only",
                                              "inputSchema": {"type": "object"}}]), hold=10)
    pa, pb = Proxy(copy.proxy, socks["x7b"]), Proxy(copy.proxy, socks["x7b"])
    pa.initialize()
    pb.initialize()
    call_id, _ = pa.request("tools/call", {"name": "get_project", "arguments": {}})
    time.sleep(0.5)
    list_id, list_sent = pb.request("tools/list")
    list_stamp, listed = pb.answer(list_id, 15)
    took = (list_stamp - list_sent) if list_stamp else None
    tools = ((listed or {}).get("result") or {}).get("tools")
    check("X7b", tools == copy.tools and took is not None and 4.5 <= took <= 7,
          f"B's tools/list in {took and round(took, 2)} s, = snapshot {tools == copy.tools}")
    pa.answer(call_id, 15)
    pa.close()
    pb.close()
    stub7b.close()

    # X8 — list_changed after a call when the live list differs; CONTROL by key order.
    try:
        row_x8(copy, socks)
    except OSError as error:  # a stub that cannot bind is X8's failure, not the run's
        check("X8", False, f"{type(error).__name__}: {error}")
    p2.close()

    # X9 — stdout is protocol only.
    bad_lines = []
    count = 0
    for proxy in PROXIES:
        for _, text in proxy.lines:
            count += 1
            try:
                message = json.loads(text)
                good = isinstance(message, dict) and message.get("jsonrpc") == "2.0"
            except ValueError:
                good = False
            if not good:
                bad_lines.append(text[:80])
    check("X9", count > 0 and not bad_lines,
          f"{count} lines from {len(PROXIES)} proxies; bad {bad_lines[:3]}")

    # X10 — no parity complaint in any launch log.
    logs = [os.path.join(folder, "framejob-launch.log") for folder in folders.values()]
    logs = [log for log in logs if os.path.exists(log)]
    leaked = [line for log in logs for line in Path(log).read_text(errors="replace").splitlines()
              if "Frame Job: " in line]
    check("X10", logs and not leaked, f"{len(logs)} launch logs; "
          + (repr(leaked[:3]) if leaked else "no `Frame Job: ` line"))


def row_x8(copy, socks):
    """X8: a list from the snapshot, then a stub; list_changed only for a real change."""
    p8 = Proxy(copy.proxy, socks["x8"])
    p8.initialize()
    list_id, _ = p8.request("tools/list")
    _, listed = p8.answer(list_id, 10)
    from_snapshot = ((listed or {}).get("result") or {}).get("tools") == copy.tools
    other = copy.tools + [{"name": "probe_new", "inputSchema": {"type": "object"}}]
    stub8 = Stub(socks["x8"], json.dumps(other))
    call_id, _ = p8.request("tools/call", {"name": "get_project", "arguments": {}})
    call_stamp, called = p8.answer(call_id, 15)
    note_stamp, note = p8.notification("notifications/tools/list_changed", 5)
    changed = (from_snapshot and called is not None and note is not None
               and note_stamp > call_stamp)
    p8.close()
    stub8.close()
    p8c = Proxy(copy.proxy, socks["x8c"])
    p8c.initialize()
    list_id, _ = p8c.request("tools/list")
    _, listed = p8c.answer(list_id, 10)
    control_snapshot = ((listed or {}).get("result") or {}).get("tools") == copy.tools
    text = reversed_json(copy.tools)
    stub8c = Stub(socks["x8c"], text)
    call_id, _ = p8c.request("tools/call", {"name": "get_project", "arguments": {}})
    _, control_called = p8c.answer(call_id, 15)
    _, control_note = p8c.notification("notifications/tools/list_changed", 3)
    reordered = text != json.dumps(copy.tools, separators=(",", ":"))
    check("X8", changed and control_snapshot and control_called is not None
          and control_note is None and reordered,
          f"list from the snapshot {from_snapshot}; list_changed after the call "
          f"{note is not None}; CONTROL: from the snapshot {control_snapshot}, keys "
          f"reordered {reordered}, list_changed {control_note is not None}")
    p8c.close()
    stub8c.close()


def write_ac_fixture():
    command = str(APP / PROXY_RELATIVE)
    fixture = {"mcpServers": {"framejob": {"command": command, "args": []}}}
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "ac-mcp.json").write_text(json.dumps(fixture, indent=2) + "\n")


def make_copy(app, run):
    """`ditto` the app to work/mcp-proxy/<run>/<its own name>.app, whose
    executable follows that name; the path or None and why."""
    try:
        proof_app.require_fresh(proof_app.executable(Path(app)))
    except proof_app.StaleApp as error:
        return None, str(error)
    target = WORK / run / Path(app).name
    tree_copy.remove_tree(target.parent)
    target.parent.mkdir(parents=True)
    done = bounded.run(["ditto", str(app), str(target)], 300, env=child_env())
    if done["rc"] != 0:
        return None, f"ditto rc {done['rc']}: {done['stderr'].strip()[:300]}"
    return target, ""


def build_mutant(name, run, app):
    """The mutant's binary in a fresh bundle copy: the copy, or None and why."""
    _, file, before, after = MUTANTS[name]
    base = WORK / f"mutant-{name}"
    tree_copy.remove_tree(base)
    try:
        shutil.copytree(ROOT / "mcp-proxy", base / "mcp-proxy",
                        ignore=shutil.ignore_patterns("target"))
        (base / "core/src").mkdir(parents=True)
        shutil.copy2(ROOT / "core/src/mcp_versions.rs", base / "core/src/mcp_versions.rs")
        sources = sorted((base / "mcp-proxy/src").glob("*.rs"))
        found = sum(path.read_text().count(before) for path in sources)
        if found != 1:
            return None, f"the anchor is in mcp-proxy/src {found} times, not once"
        target = base / "mcp-proxy/src" / file
        text = target.read_text()
        if text.count(before) != 1:
            return None, f"the anchor is not in {file}"
        target.write_text(text.replace(before, after))
    except OSError as error:
        return None, f"the copy could not be made: {error}"
    print(f"  mutant {name}: cargo build --release --offline in {base / 'mcp-proxy'}",
          flush=True)
    built = bounded.run(["cargo", "build", "--release", "--offline"], 900,
                        cwd=str(base / "mcp-proxy"), env=child_env())
    binary = base / "mcp-proxy/target/release/framejob-mcp"
    if built["rc"] != 0 or not binary.exists():
        return None, f"cargo rc {built['rc']}: {built['stderr'].strip()[-600:]}"
    copy, why = make_copy(app, run)
    if copy is None:
        return None, why
    proxy = copy / PROXY_RELATIVE
    shutil.copyfile(binary, proxy)
    os.chmod(proxy, 0o755)
    for argv in (["codesign", "--force", "--options", "runtime", "-s", "-", str(proxy)],
                 ["codesign", "--force", "-s", "-", "--preserve-metadata=entitlements,flags",
                  str(copy)]):
        signed = bounded.run(argv, 300, env=child_env())
        if signed["rc"] != 0:
            return None, f"{' '.join(argv)} rc {signed['rc']}: {signed['stderr'].strip()[:300]}"
    return copy, ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    started = time.monotonic()
    WORK.mkdir(parents=True, exist_ok=True)
    run = time.strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"
    person_before = [ident(path) for path in PERSON_PATHS]

    if args.mutant:
        row = MUTANTS[args.mutant][0]
        print(f"mcp proxy — the {args.mutant} MUTANT ({row} must FAIL)", flush=True)
        copy_path, why = build_mutant(args.mutant, run, args.app)
    else:
        print(f"mcp proxy — {args.app}", flush=True)
        copy_path, why = make_copy(args.app, run)
    write_ac_fixture()
    if copy_path is None:
        if args.mutant:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        check("X0", False, f"no bundle copy: {why}")
        copy = None
    else:
        try:
            copy = Copy(copy_path)
            print(f"  copy: {copy.app} ({len(copy.tools)} snapshot tools, version "
                  f"{copy.version})", flush=True)
        except (OSError, ValueError, KeyError) as error:
            check("X0", False, f"the copy's snapshot or Info.plist: {error}")
            copy = None

    try:
        if copy is not None:
            run_rows(copy)
    except Exception as error:  # an instrument that breaks is a FAIL, not an exit
        check("X?", False, f"the proof broke: {type(error).__name__}: {error}")
    finally:
        for proxy in PROXIES:
            proxy.close()
        for stub in STUBS:
            try:
                stub.close()
            except OSError:
                pass
        if copy is not None:
            copy.stop_all()
            alive = copy.pids()
            check("Z1", not alive, f"alive {sorted(alive)}" if alive else
                  "no instance of the copy")
        else:
            alive = set()
            check("Z1", False, "no copy")
        if not alive:  # a copy is a whole app; one with a live instance is left to inspect
            # `open` registered the copy with LaunchServices, which would
            # otherwise keep a Frame Job.app at a deleted path in its database.
            if copy is not None:
                bounded.run([LSREGISTER, "-u", str(copy.app)], 60, env=child_env())
            shutil.rmtree(WORK / run, ignore_errors=True)
        person_after = [ident(path) for path in PERSON_PATHS]
        check("Z2", person_before == person_after,
              "; ".join(f"{path.name}: {'absent' if b is None else 'present'} → "
                        f"{'absent' if a is None else 'present'}"
                        + ("" if a == b else " CHANGED")
                        for path, b, a in zip(PERSON_PATHS, person_before, person_after)))
        for folder in SCRATCH:
            shutil.rmtree(folder, ignore_errors=True)
        for name in ORDER:
            if name not in rows:
                check(name, False, "not scored")

    seconds = time.monotonic() - started
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        if not rows.get("X0", False):
            print(f"mutant {args.mutant}: the control could not be performed — X0 failed")
            return 2
        caught = rows.get(row) is False
        print(f"mutant {args.mutant}: {row} {'FAIL — caught' if caught else 'ok — survived'} "
              f"in {seconds:.0f} s")
        return 0 if caught else 1
    passed = sum(1 for good in rows.values() if good)
    print(f"{passed}/{len(rows)} in {seconds:.0f} s")
    return 0 if all(rows.values()) and all(name in rows for name in ORDER) else 1


if __name__ == "__main__":
    sys.exit(main())
