"""A minimal MCP streamable-HTTP client over the app's Unix socket, enough to
drive Reelcut's agent, and the one launcher the proofs share.

Road map 14's MC4 deleted the TCP listener: an instance is reached ONLY at
the socket `RC_AGENT_SOCKET` names, and a proof never binds the person's own
(`~/Library/Application Support/Reelcut/Agent/agent.sock`, spec §11 MC-6).
`scratch_socket()` makes a `0700` folder under `$TMPDIR` for one instance,
`launch()` starts a binary on it and waits for the socket's log line, and
`remove_scratch()` deletes the folder afterwards."""

import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

MAX_SOCKET_PATH = 103
LSREGISTER = ("/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
              "LaunchServices.framework/Versions/A/Support/lsregister")


class UnixHTTPConnection(http.client.HTTPConnection):
    """`http.client` over AF_UNIX: the host is only the Host header."""

    def __init__(self, socket_path, timeout=600):
        super().__init__("localhost", timeout=timeout)
        self.socket_path = socket_path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self.socket_path)
        self.sock = sock


class MCP:
    def __init__(self, socket_path, path="/mcp", timeout=600):
        """`socket_path` is the instance's `RC_AGENT_SOCKET`. `timeout` is
        the per-request ceiling in seconds. 600 is what every script before
        road map 3 waited (and still waits: the default is unchanged);
        `recording_proof.py` passes its own, because a `record_screen`
        blocks for the whole recording plus its finish and a hang has to be
        told apart from a long take."""
        if isinstance(socket_path, int):
            raise TypeError(
                f"MCP takes the instance's socket path, not the port {socket_path}: road map "
                "14's MC4 deleted the TCP listener (launch with RC_AGENT_SOCKET and pass it)")
        self.socket_path = str(socket_path)
        self.path = path
        self.session = None
        self.next_id = 0
        self.timeout = timeout
        self._request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "reelcut-proof", "version": "1"},
            },
        )
        self._notify("notifications/initialized")

    def _connection(self):
        """The connection one request goes over: the instance's socket."""
        return UnixHTTPConnection(self.socket_path, timeout=self.timeout)

    def _post(self, body, notify=False):
        data = json.dumps(body).encode()
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        connection = self._connection()
        try:
            connection.request("POST", self.path, body=data, headers=headers)
            response = connection.getresponse()
            sid = response.getheader("Mcp-Session-Id")
            if sid:
                self.session = sid
            raw = response.read().decode()
            status = response.status
        finally:
            connection.close()
        if status >= 400:
            raise RuntimeError(f"HTTP {status} at {self.socket_path}: {raw[:300]}")
        if notify or not raw.strip():
            return None
        # SSE frames or a bare JSON body.
        for line in raw.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        return json.loads(raw)

    def _request(self, method, params):
        self.next_id += 1
        answer = self._post(
            {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params}
        )
        if answer is None:
            raise RuntimeError(f"{method}: no answer")
        if "error" in answer:
            raise RuntimeError(f"{method}: {answer['error']}")
        return answer["result"]

    def _notify(self, method, params=None):
        self._post({"jsonrpc": "2.0", "method": method, "params": params or {}}, notify=True)

    def tools(self):
        return list(self.schemas())

    def schemas(self):
        """Every tool `tools/list` reports, WHOLE — name, description and
        inputSchema — keyed by name, in the catalog's own order.

        `tools()` above answers names only, so seven scripts used to reach
        into `_request` for the rest; this is the one accessor they share
        (road map 7's D3·5). A dict rather than the raw array because every
        caller but one wanted `{name: tool}` anyway, and `.values()` is the
        array back in catalog order."""
        return {tool["name"]: tool for tool in self._request("tools/list", {})["tools"]}

    def call(self, name, **arguments):
        """Call a tool with keyword arguments. A tool ARGUMENT spelled `name`
        (`add_track`, `set_track`, `add_marker`, `set_marker`, `nest`)
        collides with this parameter — send those through `call_with`."""
        return self.call_with(name, arguments)

    def call_with(self, tool, arguments):
        """Call `tool` with `arguments` as a dict, whatever its keys are."""
        result = self._request("tools/call", {"name": tool, "arguments": arguments})
        text = "".join(
            part.get("text", "") for part in result.get("content", []) if part.get("type") == "text"
        )
        if result.get("isError"):
            raise ToolError(f"{tool}: {text}")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


class ToolError(RuntimeError):
    pass


# ---- scratch sockets -------------------------------------------------------------

def scratch_socket(prefix="rc-"):
    """`<a fresh 0700 folder under $TMPDIR>/agent.sock`. Raises ValueError
    (removing the folder) when the path passes macOS's 103 bytes."""
    folder = tempfile.mkdtemp(prefix=prefix)
    os.chmod(folder, 0o700)
    path = os.path.join(folder, "agent.sock")
    if len(path.encode()) > MAX_SOCKET_PATH:
        shutil.rmtree(folder, ignore_errors=True)
        raise ValueError(f"{path} is {len(path.encode())} bytes; a socket path may be "
                         f"{MAX_SOCKET_PATH}")
    return path


def remove_scratch(socket_path):
    """Deletes the socket's folder, only when it is under the temp dir."""
    if not socket_path:
        return
    folder = os.path.realpath(os.path.dirname(str(socket_path)))
    temp = os.path.realpath(tempfile.gettempdir())
    if folder.startswith(temp + os.sep):
        shutil.rmtree(folder, ignore_errors=True)


def log_beside(socket_path):
    """`<the socket's folder>/reelcut.log`."""
    return os.path.join(os.path.dirname(str(socket_path)), "reelcut.log")


def wait_listening(log_path, socket_path, child=None, seconds=60, offset=0):
    """True once the log, read from byte `offset`, holds `Reelcut agent
    socket listening at <socket_path>`; False on a `not bound` line, when
    `child` exits, or at the deadline."""
    want = f"Reelcut agent socket listening at {socket_path}"
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with open(log_path, "rb") as log:
                log.seek(offset)
                text = log.read().decode(errors="replace")
        except OSError:
            text = ""
        for line in text.splitlines():
            if line.rstrip().endswith(want):
                return True
            if "Reelcut agent socket not bound: " in line:
                return False
        if child is not None and child.poll() is not None:
            return False
        time.sleep(0.2)
    return False


def socket_pid(socket_path):
    """The pid holding the listening socket at `socket_path` (`lsof -U`,
    read only), or None."""
    names = {str(socket_path), os.path.realpath(str(socket_path))}
    try:
        listed = subprocess.run(["lsof", "-nP", "-U", "-Fpn"], capture_output=True, text=True,
                                timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    pid = None
    for line in listed.stdout.splitlines():
        if line.startswith("p"):
            pid = int(line[1:])
        elif line.startswith("n") and line[1:] in names and pid is not None:
            return pid
    return None


def target(argv, index=1, env_fallback=True):
    """`argv[index]`, else `$RC_AGENT_SOCKET`; failing both, a usage exit."""
    if len(argv) > index and argv[index]:
        return argv[index]
    if env_fallback and os.environ.get("RC_AGENT_SOCKET"):
        return os.environ["RC_AGENT_SOCKET"]
    script = os.path.basename(argv[0]) if argv else "the proof"
    raise SystemExit(
        f"usage: pass the running instance's socket path (python3 {script} <dir>/agent.sock), "
        "the RC_AGENT_SOCKET it was launched with" + ("" if not env_fallback else
                                                     ", or set RC_AGENT_SOCKET"))


# ---- the launcher ----------------------------------------------------------------

class Launched:
    """One instance `launch` started: its child, socket, log and client."""

    def __init__(self, child, socket_path, log_path, client):
        self.child = child
        self.socket_path = socket_path
        self.log_path = log_path
        self.client = client

    def stop(self, grace=30):
        """Terminates this child alone, then kills it after `grace`."""
        if self.child is None or self.child.poll() is not None:
            return
        self.child.terminate()
        try:
            self.child.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            self.child.kill()
            self.child.wait()


def _child_env():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "graphics_spike"))
    import bounded  # noqa: E402

    return bounded.child_env()


def launch(binary, arguments=(), env=None, socket_path=None, log_path=None, seconds=60,
           timeout=600):
    """Starts `binary -ApplePersistenceIgnoreState YES *arguments` on a
    scratch socket (or `socket_path`), in its own session, logging to
    `log_path` (else beside the socket), and waits up to `seconds` for its
    listening line. `client` is an `MCP` with `timeout`, or None when the
    instance did not come up."""
    socket_path = str(socket_path or scratch_socket())
    log_path = str(log_path or log_beside(socket_path))
    environment = dict(env) if env is not None else _child_env()
    environment["RC_AGENT_SOCKET"] = socket_path
    offset = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    with open(log_path, "ab") as out:
        child = subprocess.Popen(
            [str(binary), "-ApplePersistenceIgnoreState", "YES", *arguments],
            stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
            start_new_session=True, env=environment)
    client = None
    if wait_listening(log_path, socket_path, child=child, seconds=seconds, offset=offset):
        client = MCP(socket_path, timeout=timeout)
    return Launched(child, socket_path, log_path, client)
