"""A minimal MCP streamable-HTTP client over the app's Unix socket, enough to
drive Frame Job's agent, and the one launcher the proofs share.

Road map 14's MC4 deleted the TCP listener: an instance is reached ONLY at
the socket `RC_AGENT_SOCKET` names, and a proof never binds the person's own
(`~/Library/Application Support/Frame Job/Agent/agent.sock`, spec §11 MC-6).
`scratch_socket()` makes a `0700` folder under `$TMPDIR` for one instance,
`launch()` starts a binary on it and waits for the socket's log line, and
`remove_scratch()` deletes the folder afterwards.

**Which app, and how fresh** (issue batch B88). `launch()` refuses a built
product older than its tree's inputs (`proof_app.require_fresh`), and
`MCP()` refuses an instance of one started before an input changed
(`proof_app.require_running_fresh`, once per socket and pid, on
`socket_pid`'s answer; with no pid it says so on stderr and does not
refuse). Both raise `proof_app.StaleApp`, naming the file, its time and the
`make` target.

**The defaults guard** (issue batch B83, #238). No environment moves
`UserDefaults`, so every instance a proof drives shares its bundle's
defaults domain with the owner. The guarded domain is the bundle under
test's: `com.kgalligan.FrameJob` for Release, `com.kgalligan.FrameJob.debug`
for Debug (`make app-debug`, spec §11 V-5). A record per socket path holds
that domain's key names against salted digests (`proof_defaults.snapshot`,
`defaults export` only) and the other Frame Job pids sharing it:
`scratch_socket()` records `proof_app.domain()`, the app `RC_PROOF_APP`
chooses, `launch()` re-records the binary's own and owns its child, and
`MCP()` records a socket it was handed. A socket `scratch_socket()` made and
`MCP()` then finds held by an instance of ANOTHER bundle (a script that
started the app itself on it) is re-homed to that bundle's domain, said on
stderr (`_rehome`); a write before that connect is not seen. The record and
the compare both read the domain with no `CFFIXED_USER_HOME` in `defaults`'
environment (`proof_defaults.read_env`): under one naming a folder that does not exist
`defaults export` answers no key, so a script run under a scratch home not
made yet at the record, or removed before the compare, would otherwise be
told every key of the domain moved (issue batch B84; `defaults_proof.py`
H1, H2). `remove_scratch()` compares, and one
`atexit` handler compares every record still held. A moved key outside
AppKit's `NS*`/`Apple*` families prints `mcp: DEFAULTS MOVED in <domain>:
<names> (other Frame Job pids: <list|none>)` on stderr; when no other Frame Job
shares the domain the script ENDS with status `DEFAULTS_EXIT` and those
lines last, and when one does it only prints. A value is never printed.
`defaults_proof.py` is its proof. A handed socket whose file is there and
whose pid `lsof` cannot name is said on stderr, and a moved key is then only
printed unless `lsof` names the pid at the compare. A handed pid whose
bundle identifier cannot be read is said on stderr too: it is owned, and its
record guards the app's domain. A guard body that raised says so on stderr. A domain that cannot be
read is said on stderr. Not reached: a script killed by a signal or leaving
by `os._exit`."""

import atexit
import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.append(_HERE)
import proof_app  # noqa: E402
import proof_defaults  # noqa: E402

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
        _guard_handed(self.socket_path)
        _require_running_fresh(self.socket_path)
        self.path = path
        self.session = None
        self.next_id = 0
        self.timeout = timeout
        self._request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "framejob-proof", "version": "1"},
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

    # ---- export, through the Export Queue (spec §11 #326) ----------------------

    def wait_export(self, export_id, seconds=None, interval=0.2):
        """Poll `export_status` until the job `export` queued is over: `done`
        answers the status (every key `export` answered before #326), and
        `failed` or `cancelled` raises `ToolError("export: <reason>")`, so a
        caller sees the failure the blocking `export` used to raise. Past
        `seconds` the job is cancelled and a `ToolError` names its status.
        `seconds` defaults to this client's own `timeout` (600 unless the
        script built it with its own), the bound the blocking `export` call
        was held to before #326, so a script with a longer bound keeps it."""
        if seconds is None:
            seconds = self.timeout
        deadline = time.monotonic() + seconds
        while True:
            status = self.call("export_status", export_id=export_id)
            word = status.get("status")
            if word == "done":
                return status
            if word in ("failed", "cancelled"):
                raise ToolError(f"export: {status.get('reason', '')}")
            if time.monotonic() >= deadline:
                try:
                    self.call("cancel_export", export_id=export_id)
                except ToolError:
                    pass
                raise ToolError(f"export: {export_id} still {word} after {seconds} s")
            time.sleep(interval)

    def export_with(self, arguments, seconds=None):
        """`export` as the proofs knew it: a refusal raises, and the answer is
        the finished file's. An answer with no `export_id` is a pre-#326
        build's, whose `export` blocked to the file, and is returned as is
        with no `export_status` call; otherwise the job is followed through
        `wait_export` (`seconds` None is the client's own `timeout`)."""
        answer = self.call_with("export", arguments)
        if not isinstance(answer, dict) or "export_id" not in answer:
            return answer
        return self.wait_export(answer["export_id"], seconds=seconds)

    def export(self, **arguments):
        """`export_with` with keyword arguments."""
        return self.export_with(arguments)


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
    _record(path, proof_app.domain())
    return path


def remove_scratch(socket_path):
    """Deletes the socket's folder, only when it is under the temp dir."""
    if not socket_path:
        return
    record = _GUARDED.pop(str(socket_path), None)
    if record is not None:
        _finish(str(socket_path), record)
    folder = os.path.realpath(os.path.dirname(str(socket_path)))
    temp = os.path.realpath(tempfile.gettempdir())
    if folder.startswith(temp + os.sep):
        shutil.rmtree(folder, ignore_errors=True)


def log_beside(socket_path):
    """`<the socket's folder>/framejob.log`."""
    return os.path.join(os.path.dirname(str(socket_path)), "framejob.log")


def wait_listening(log_path, socket_path, child=None, seconds=60, offset=0):
    """True once the log, read from byte `offset`, holds `Frame Job agent
    socket listening at <socket_path>`; False on a `not bound` line, when
    `child` exits, or at the deadline. A build of a tree from before rename R1
    (`grading_verdict.py`'s main tree) says the same under its old name."""
    names = ("Frame Job", "Reelcut")
    wants = tuple(f"{name} agent socket listening at {socket_path}" for name in names)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with open(log_path, "rb") as log:
                log.seek(offset)
                text = log.read().decode(errors="replace")
        except OSError:
            text = ""
        for line in text.splitlines():
            if line.rstrip().endswith(wants):
                return True
            if any(f"{name} agent socket not bound: " in line for name in names):
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


# ---- the defaults guard ----------------------------------------------------------

DEFAULTS_EXIT = 3
DEFAULTS_MOVED = []     # (domain, owner-visible names, other sharing pids)
_GUARDED = {}           # socket path -> {"domain", "before", "then", "own"}
_OWN_PIDS = set()       # every pid a record of this process has owned


def _say(text):
    """One line on stderr; never raises."""
    try:
        sys.stderr.write(text + "\n")
        sys.stderr.flush()
    except Exception:
        pass


def _off(what, error):
    _say(f"mcp: the defaults guard is off for {what}: {type(error).__name__}")


def _holder(socket_path):
    """`socket_pid` for the guard: None for anything it raises, so an `lsof`
    answer that cannot be read costs neither a record nor a found move."""
    try:
        return socket_pid(socket_path)
    except Exception:
        return None


def _sharing(domain):
    """`sharing_pids` for the guard: [] for anything it raises. With no pid
    to blame, a moved key then ends the script instead of only printing."""
    try:
        return proof_defaults.sharing_pids(domain)
    except Exception:
        return []


def _record(socket_path, domain, own=()):
    """Starts guarding `domain` for `socket_path`, replacing any record."""
    try:
        own = {pid for pid in own if pid is not None}
        _OWN_PIDS.update(own)
        before = proof_defaults.snapshot(domain)
        _GUARDED[str(socket_path)] = {
            "domain": domain, "before": before, "then": set(_sharing(domain)), "own": own}
        if before is None:
            _say(_unread(domain, socket_path, "at the record"))
    except Exception as error:  # the guard never raises into a proof, and says when it is off
        _off(socket_path, error)


def _own(socket_path, pid):
    record = _GUARDED.get(str(socket_path))
    if record is not None and pid is not None:
        record["own"].add(pid)
        _OWN_PIDS.add(pid)


_FRESH_CHECKED = set()  # (socket path, pid) whose instance proof_app has checked


def _require_running_fresh(socket_path):
    """`proof_app.require_running_fresh` on the pid holding the socket, once
    per (socket, pid); raises `proof_app.StaleApp`. With no pid, one stderr
    line and no refusal."""
    pid = socket_pid(socket_path)
    if pid is None:
        _say(f"mcp: no pid holds {socket_path}; the instance's freshness is not checked")
    elif (socket_path, pid) not in _FRESH_CHECKED:
        proof_app.require_running_fresh(pid)
        _FRESH_CHECKED.add((socket_path, pid))


def _pid_domain(pid):
    """The bundle identifier of the executable `ps` names for `pid`, else None."""
    try:
        named = subprocess.run(["ps", "-p", str(pid), "-o", "comm="],
                               capture_output=True, text=True, timeout=30)
        executable = named.stdout.strip()
        return proof_defaults.bundle_domain(executable) if executable else None
    except Exception:
        return None


def _rehome(socket_path, pid, domain):
    """Moves a `scratch_socket()` record to the bundle domain of the pid that
    holds the socket, owning it: the instance a script started itself."""
    old = _GUARDED[socket_path]["domain"]
    _say(f"mcp: the defaults guard moved {socket_path} from {old} to {domain}, the bundle of pid "
         f"{pid}; a write before this connect is not seen")
    _record(socket_path, domain, own=[pid])


def _guard_handed(socket_path):
    """Records a socket with no record: the domain of the executable holding
    it, else the app's, that pid owned. When the socket's file is there and
    `lsof` names no pid for it, asked twice, that is said on stderr: the
    record then guards the app's domain and cannot tell the handed instance
    from another Frame Job, so a moved key is only printed unless `lsof` names
    the pid at the compare. A pid whose bundle identifier cannot be read is
    said too: the record then guards the app's domain. A record that owns no
    pid (one `scratch_socket()` made) is re-homed (`_rehome`) when the
    holder's bundle domain can be read and differs from it."""
    try:
        record = _GUARDED.get(socket_path)
        if record is not None:
            if not record["own"]:
                pid = _holder(socket_path)
                domain = _pid_domain(pid) if pid is not None else None
                if domain is not None and domain != record["domain"]:
                    _rehome(socket_path, pid, domain)
            return
        pid = _holder(socket_path)
        if pid is None and os.path.exists(socket_path):
            time.sleep(0.5)
            pid = _holder(socket_path)
        domain = None
        if pid is not None:
            domain = _pid_domain(pid)
            if domain is None:
                _say(f"mcp: the defaults guard could not read the bundle identifier of pid {pid} "
                     f"holding {socket_path}; it guards {proof_defaults.APP_DOMAIN}, which is "
                     "that instance's domain only if it is the real build")
        elif os.path.exists(socket_path):
            _say(f"mcp: the defaults guard found no pid holding {socket_path}; it guards "
                 f"{proof_defaults.APP_DOMAIN} and cannot tell this instance from another "
                 "Frame Job, so a moved key is only printed unless `lsof` names it at the compare")
        _record(socket_path, domain or proof_defaults.APP_DOMAIN, own=[pid])
    except Exception as error:
        _off(socket_path, error)


def defaults_moved(socket_path):
    """Every moved key NAME of that socket's guarded domain since its record
    was made; [] when the socket is not guarded."""
    record = _GUARDED.get(str(socket_path))
    if record is None:
        return []
    try:
        return proof_defaults.moved(record["before"],
                                    proof_defaults.snapshot(record["domain"]))
    except Exception:
        return []


def _moved_line(domain, names, others):
    return (f"mcp: DEFAULTS MOVED in {domain}: {', '.join(names)} (other Frame Job pids: "
            f"{', '.join(str(pid) for pid in others) or 'none'})")


def _unread(domain, socket_path, when):
    return (f"mcp: the defaults guard could not read {domain} {when} (`defaults export` did "
            f"not answer); it cannot see a moved key for {socket_path}")


def _finish(socket_path, record):
    """Compares `record`'s domain now. An owner-visible moved key is appended
    to `DEFAULTS_MOVED` and printed on stderr, and no `Exception` after the
    compare can drop it."""
    try:
        after = proof_defaults.snapshot(record["domain"])
        names = proof_defaults.owner_visible(proof_defaults.moved(record["before"], after))
    except Exception as error:
        _off(socket_path, error)
        return
    if after is None and record["before"] is not None:
        _say(_unread(record["domain"], socket_path, "at the compare"))
    if not names:
        return
    others = set(record["then"]) | set(_sharing(record["domain"]))
    others -= _OWN_PIDS | set(record["own"])
    others.discard(_holder(socket_path))
    entry = (record["domain"], names, sorted(others))
    DEFAULTS_MOVED.append(entry)
    _say(_moved_line(*entry))


def _exit_failed(lines):
    """Flushes stdout, writes `lines` to stderr and ends the process with
    `DEFAULTS_EXIT`, so they are the output's last and the status is 3 (a
    `SystemExit` raised in an `atexit` handler would leave the status 0)."""
    try:
        sys.stdout.flush()
    except Exception:
        pass
    try:
        sys.stderr.write("".join(line + "\n" for line in lines))
        sys.stderr.flush()
    except Exception:
        pass
    os._exit(DEFAULTS_EXIT)


def _defaults_at_exit():
    """Registered at import, so it runs after any handler a script registers
    later: finishes every record still held, then fails the script when a
    moved key has no other Frame Job to be blamed on."""
    for socket_path in list(_GUARDED):
        try:
            _finish(socket_path, _GUARDED.pop(socket_path))
        except Exception as error:
            _off(socket_path, error)
    try:
        lines = [_moved_line(*entry) for entry in DEFAULTS_MOVED if not entry[2]]
    except Exception as error:
        _off("its exit handler", error)
        return
    if lines:
        _exit_failed(lines)


atexit.register(_defaults_at_exit)


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
    instance did not come up. A built product older than its inputs is
    refused first (`proof_app.StaleApp`), and nothing is started."""
    proof_app.require_fresh(binary)
    socket_path = str(socket_path or scratch_socket())
    log_path = str(log_path or log_beside(socket_path))
    environment = dict(env) if env is not None else _child_env()
    environment["RC_AGENT_SOCKET"] = socket_path
    offset = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    earlier = _GUARDED.pop(socket_path, None)
    if earlier is not None and earlier["own"]:
        _finish(socket_path, earlier)      # a relaunch on the same socket loses nothing
    _record(socket_path, proof_defaults.bundle_domain(binary) or proof_defaults.APP_DOMAIN)
    with open(log_path, "ab") as out:
        child = subprocess.Popen(
            [str(binary), "-ApplePersistenceIgnoreState", "YES", *arguments],
            stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
            start_new_session=True, env=environment)
    _own(socket_path, child.pid)
    client = None
    if wait_listening(log_path, socket_path, child=child, seconds=seconds, offset=offset):
        try:
            client = MCP(socket_path, timeout=timeout)
        except proof_app.StaleApp:
            Launched(child, socket_path, log_path, None).stop()
            raise
    return Launched(child, socket_path, log_path, client)
