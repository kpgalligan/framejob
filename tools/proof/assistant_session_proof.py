#!/usr/bin/env python3
"""The assistant session, end to end — road map 12 A1, part 3 (spec §11 AI-3,
AI-5, AI-7, AI-8, AI-10, AI-11, AI-13).

Real turns in the built app (`proof_app`'s choice), against `anthropic_fake.py`: the
session in `AssistantSession.swift`, driven over MCP by the dev tools
`assistant_send` / `assistant_answer`, and WITHOUT the MCP server by the
dev-only launch default `-RCDevAssistantSend` / `-RCDevAssistantReport`.

Launch A (a scratch socket, a scratch `-RCSecretFolder` holding the
dummy key, `RC_ASSISTANT_BASE_URL` at the stand-in):
  A0  no `Frame Job: ` line; the dev-tool marker counts len(DEV_TOOLS); the dev
      block is DEV_TOOLS + ["import_media"]
  T1  a scripted add_marker lands on the window's own project (A, with B
      frontmost), answered `finished`; one MCP undo removes it (AI-5, AI-10)
  T2  T1's stand-in log: the model lookup, every POST's model and credential,
      the system's two halves, the tools in catalog order with exactly the
      core tools up front
  R   allow with nothing pending, stop while idle, answer "maybe": refused by
      name, changing nothing
  D   Deny: an export is asked about, declined, writes nothing, and the model
      sees "The person declined: …"
  E   Allow: the export REPLACES a sentinel with a movie
  S   Stop while asking: no file, the question declined by "stop"
  X   the helper killed while asking: a new send is taken within 10 s and
      its marker lands; no file; the app lives
  SX  (issue batch B15, #149; AI-16) Stop reaches a running export: on B, a
      text clip of SX_SECONDS (an un-stopped h264 export of it takes over
      10 s), the export asked about and allowed with `stop_after: 2`:
      finished, `stopped_ms` ≥ 2000 and `waited_ms` − `stopped_ms` ≤ 5000,
      the export's `tool_result` an error "The export was cancelled.", no
      file 1 s later, no stand-in failure
  ST  Stop reaches a running on-device transcribe: on C, a new project,
      `long.wav` placed — ST_COPIES (6) copies of
      `speech_engine_proof.make_fixtures()`'s ten-minute WAV, about 3600 s,
      written into WORK only after the setup transcribe answered — the
      model's `transcribe {place: false}` sent with `stop_after: 2`: finished,
      the `tool_result` an error "The transcription was cancelled.",
      `waited_ms` − `stopped_ms` ≤ 5000. The hour is long so that the time
      bound alone catches a transcribe that ignores Stop: one that runs on
      outlasts the bound on any host where the hour does not finish within
      it (issue batch B38, #179). When a setup `transcribe {place: false}`
      over the pangram, in a project of its own, is refused as not
      installed or not available, ST is a named host SKIP
  K1  `proof-key` in no MCP answer and nowhere in the log
  SX and ST run after X: row X counts exactly one helper child, and they
  open sessions on B and C. K1 runs last so it reads their answers too
  (issue batch B38, #179).
Launch B, W: the same kind of turn with NO MCP server — its scratch socket's
      folder is 0755, so it logs `not bound` — through the launch
      default; the model setting reaches the stand-in (AI-11)
Launch C, K2: AI-13 — the override set and no `-RCSecretFolder`: the session
      is refused for want of a key, the stand-in hears nothing, no helper runs

    python3 tools/proof/assistant_session_proof.py
    python3 tools/proof/assistant_session_proof.py --mutant no-prepare          # W: FAILS
    python3 tools/proof/assistant_session_proof.py --mutant no-export-stop      # SX: FAILS
    python3 tools/proof/assistant_session_proof.py --mutant no-transcribe-stop  # ST: FAILS
    python3 tools/proof/assistant_session_proof.py --mutant key-echo            # K1: FAILS

A mutant copies the tree with `tree_copy.make_copy` into
`work/assistant_session/mutant/tree`, deletes its one line (`MUTANTS`: the
`AgentLane.prepareAtLaunch()` line in main.swift; the export's `onCancel`
line; the transcribe's `onCancel` line), builds it there (`tree_copy.build_app`), and runs its
row against that app — W's report must be `ok: false`, naming AI-3; SX and
ST run in a launch A of the mutant app. `no-transcribe-stop` must fail ST
with `waited_ms − stopped_ms … > 5000` (LATE) among its problems, or the run
exits 2: the fixture ran out within the bound on this host. `key-echo` is a
stand-in control with no build: launch A of the built app, where SX's and
ST's first replies carry a text block holding `proof-key`, which reaches the
dev tools' `text`; W and K2 do not run, and K1 must FAIL. Exit 1 depends only
on the named row FAILing (caught); 0 when it passes (survived). A mutant that
did not build could not perform the control (exit 2), and so (rule R, issue
batch B13) could one whose row was never scored, was a host skip, or was
scored by a caught exception or a failed setup, or (B38) failed without the
text `MUTANTS` requires: `mutant <name>: the control could not be performed
— <why>`, exit 2.

Prints `<ID> ok|FAIL — <detail>` per row, then `n/m`. An instrument that
cannot run is a scored FAIL. Every `App` launch pins the chat settings
(`CHAT_PINS`, AI-20) to their defaults unless its arguments set one. Safety: every child's environment has
`ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY` popped and none sets either; the
only key is the dummy `proof-key`, in a 0600 `anthropic-key` in a 0700
scratch folder; `RC_ASSISTANT_BASE_URL` always names the stand-in. Rule H:
each app runs in its own process group under walls; only this script's apps
are killed, with the helper children each app started (named by ppid and
path before the app goes).
"""

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
from dev_tools import DEV_TOOLS, dev_marker_count  # noqa: E402
from mcp import MCP, remove_scratch, scratch_socket, wait_listening  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_session")
FAKE = os.path.join(HERE, "anthropic_fake.py")
APP_PATH = os.path.relpath(proof_app.bundle(), ROOT)   # the app RC_PROOF_APP chooses
HELPER_SUFFIX = "Contents/Helpers/framejob-agent"
PREPARE = "AgentLane.prepareAtLaunch()"
KEY = "proof-key"
DEFAULT_MODEL = "claude-opus-5-5"
PROOF_MODEL = "claude-proof-model"
CORE_TOOLS = ["get_project", "render_frame", "undo", "redo"]
SEARCH_TOOL = "tool_search_tool_bm25"
WALL_PORT, WALL_MCP, WALL_TURN, WALL_REPORT, WALL_BUILD = 60, 300, 60, 150, 900
SX_SECONDS, WALL_SX, WALL_ST, STOP_AFTER, WALL_STOPPED = 240, 180, 300, 2, 5000
ST_COPIES = 6  # long.wav: six copies of ten.wav, about 3600 s
LATE = "waited_ms − stopped_ms"
ECHO = "key-echo control: " + KEY
# name: (the file in app/Sources or None, the one line deleted or None, the row
# that must FAIL, a text that row's detail must hold or None)
MUTANTS: dict[str, tuple[str | None, str | None, str, str | None]] = {
    "no-prepare": ("main.swift", PREPARE, "W", None),
    "no-export-stop": ("AgentServer+Render.swift",
                       "stop?.onCancel { [weak exporter] in exporter?.cancel() }", "SX", None),
    "no-transcribe-stop": ("AgentServer+Captions.swift",
                           "stop?.onCancel { token.cancel() }", "ST", LATE),
    "key-echo": (None, None, "K1", None),
}
# The person's chat settings (spec §11 AI-20) at their defaults, as launch
# arguments: `App` appends each one whose `-Key` its arguments do not set, so no
# proof launch reads the person's own threshold or clearing switch.
CHAT_PINS = [("-FrameJobAssistantAutoCompact", "YES"),
             ("-FrameJobAssistantAutoCompactTokens", "300000"),
             ("-FrameJobAssistantClearToolResults", "NO")]


def child_env(extra=None):
    """`bounded.child_env` (RC_ASSEMBLYAI_KEY popped) with ANTHROPIC_API_KEY
    popped too; `pop` never binds either value to a name."""
    env = bounded.child_env(extra)
    env.pop("ANTHROPIC_API_KEY", None)
    return env


def kill_group(child, grace=3.0):
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


def http(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method,
                                     headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read() or b"null")
    except urllib.error.HTTPError as error:
        return error.code, None


# ---------------------------------------------------------------------------
# The stand-in, the secret folder and the apps.


class Fake:
    def __init__(self, folder):
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder)
        err = open(os.path.join(folder, "fake.stderr"), "w")
        self.child = subprocess.Popen([sys.executable, FAKE, "--dir", folder],
                                      env=child_env(), stdin=subprocess.DEVNULL,
                                      stdout=subprocess.PIPE, stderr=err, text=True,
                                      start_new_session=True)
        err.close()
        line = self.child.stdout.readline().strip()
        if not line.startswith("port "):
            kill_group(self.child)
            raise RuntimeError(f"the stand-in printed {line!r}, not a port")
        self.base = f"http://127.0.0.1:{int(line.split()[1])}"

    def scenario(self, replies):
        status, _ = http("POST", self.base + "/__control/scenario", {"replies": replies})
        if status != 200:
            raise RuntimeError(f"the scenario post answered {status}")

    def log(self):
        _, body = http("GET", self.base + "/__control/log")
        return body or {"requests": [], "failures": ["the log could not be read"]}

    def stop(self):
        kill_group(self.child)


def secret_folder():
    folder = os.path.join(WORK, "secrets")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    os.chmod(folder, 0o700)
    path = os.path.join(folder, "anthropic-key")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(KEY + "\n")
    return folder


def helper_children(pid):
    """The pids of `pid`'s children running the bundled helper."""
    listing = bounded.run(["ps", "-A", "-o", "pid=,ppid=,comm="], 30, env=child_env())
    found = []
    for line in listing["stdout"].splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and parts[1] == str(pid) and parts[2].endswith(HELPER_SUFFIX):
            found.append(int(parts[0]))
    return found


class App:
    """One Frame Job, in its own process group, logging to work/, on a scratch
    socket (`mcp.scratch_socket`) whose folder is `folder_mode`: 0755 binds
    nothing (MC-2), which is how a launch has no MCP server."""

    def __init__(self, tag, app, arguments, base, folder_mode=0o700):
        self.tag = tag
        self.log_path = os.path.join(WORK, f"app-{tag}.log")
        self.socket_path = scratch_socket()
        os.chmod(os.path.dirname(self.socket_path), folder_mode)
        env = child_env({"RC_ASSISTANT_BASE_URL": base,
                         "RC_AGENT_SOCKET": self.socket_path})
        self.handle = open(self.log_path, "wb")
        arguments = list(arguments) + [part for key, value in CHAT_PINS
                                       if key not in arguments for part in (key, value)]
        self.child = subprocess.Popen(
            [str(proof_app.executable(app)), "-ApplePersistenceIgnoreState", "YES"] + arguments,
            stdout=self.handle, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=env,
            start_new_session=True)
        self.answers = []  # every MCP answer's raw text, for K1
        self.mcp = None

    def log(self):
        try:
            with open(self.log_path, errors="replace") as handle:
                return handle.read()
        except OSError:
            return ""

    def connect(self):
        if not wait_listening(self.log_path, self.socket_path, child=self.child,
                              seconds=WALL_PORT):
            raise RuntimeError(f"app {self.tag} did not listen at {self.socket_path} in "
                               f"{WALL_PORT} s (exit {self.child.poll()})")
        self.mcp = MCP(self.socket_path, timeout=WALL_MCP)

    def call(self, tool, **arguments):
        """(ok, answer): the parsed JSON (or text) of a result, ok False for an
        in-band error, whose answer is its text."""
        result = self.mcp._request("tools/call", {"name": tool, "arguments": arguments})
        text = "".join(p.get("text", "") for p in result.get("content", [])
                       if p.get("type") == "text")
        self.answers.append(text)
        if result.get("isError"):
            return False, text
        try:
            return True, json.loads(text)
        except ValueError:
            return True, text

    def must(self, tool, **arguments):
        ok, answer = self.call(tool, **arguments)
        if not ok:
            raise RuntimeError(f"{tool}: {answer}")
        return answer

    def stop(self):
        helpers = helper_children(self.child.pid) if self.child.poll() is None else []
        kill_group(self.child)
        for pid in helpers:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.handle.close()
        remove_scratch(self.socket_path)


# ---------------------------------------------------------------------------
# Reading answers and the stand-in's log.


def posts(log):
    return [r for r in log.get("requests", [])
            if r.get("method") == "POST" and r.get("path", "").startswith("/v1/messages")]


def credential(request):
    headers = request.get("headers", {})
    value = headers.get("x-api-key") or headers.get("authorization") or ""
    return value[len("Bearer "):] if value.startswith("Bearer ") else value


def system_text(body):
    system = body.get("system")
    if isinstance(system, str):
        return system
    if isinstance(system, list):
        return "".join(b.get("text", "") for b in system if b.get("type") == "text")
    return None


def tool_result_block(body, tool_use_id):
    """The tool_result block for `tool_use_id` in a POST body, as (is_error,
    text), or None."""
    for message in body.get("messages", []):
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if block.get("type") == "tool_result" and block.get("tool_use_id") == tool_use_id:
                inner = block.get("content")
                if isinstance(inner, str):
                    text = inner
                else:
                    text = "".join(b.get("text", "") for b in inner or []
                                   if b.get("type") == "text")
                return bool(block.get("is_error")), text
    return None


def tool_results(answer, name):
    return [e for e in answer.get("events", [])
            if e.get("type") == "tool_result" and e.get("name") == name]


def answers_by(answer, who):
    return [e for e in answer.get("events", [])
            if e.get("type") == "answer" and e.get("by") == who]


def markers(app, project):
    got = app.must("get_project", project=project)
    return [(m.get("time"), m.get("name")) for m in got["project"].get("markers", [])]


def use(tool_id, name, arguments, said=None):
    content = [{"type": "tool_use", "id": tool_id, "name": name, "input": arguments}]
    if isinstance(said, str):
        content.insert(0, {"type": "text", "text": said})
    return {"content": content, "stop_reason": "tool_use"}


def say(text):
    return {"content": [{"type": "text", "text": text}], "stop_reason": "end_turn"}


def brief(answer):
    if not isinstance(answer, dict):
        return repr(answer)[:200]
    return (f"state {answer.get('state')}, text {answer.get('text')!r}, question "
            f"{(answer.get('question') or {}).get('sentence')!r}, "
            f"{len(answer.get('events', []))} events, {answer.get('waited_ms')} ms")


# ---------------------------------------------------------------------------
# Launch A's rows. `ctx` carries A, B and what the rows hand on.


def row_a0(app, ctx):
    complaints = [l for l in app.log().splitlines() if "Frame Job: " in l]
    marker = dev_marker_count(app.log_path)
    names = list(app.mcp.schemas())
    at = names.index(DEV_TOOLS[0]) if DEV_TOOLS[0] in names else len(names)
    block = names[at:at + len(DEV_TOOLS) + 1]
    ctx["catalog"] = names
    ok = not complaints and marker == len(DEV_TOOLS) == 6 and block == DEV_TOOLS + ["import_media"]
    return ok, (f"`Frame Job: ` lines {complaints[:2]}; marker {marker} of {len(DEV_TOOLS)}; "
                f"dev block {block}")


def row_t1(app, fake, ctx):
    a = app.must("new_project", path=os.path.join(ctx["folder"], "A.framejob"))["saved"]
    b = app.must("new_project", path=os.path.join(ctx["folder"], "B.framejob"))["saved"]
    ctx["A"] = a
    ctx["B"] = b
    front = app.must("get_project").get("path")
    fake.scenario([use("toolu_t1", "add_marker", {"at": 1200000, "name": "A1 part 3"}),
                   say("T1: the marker is in.")])
    ok, answer = app.call("assistant_send", project=a, text="Put a marker at two seconds.",
                          timeout=WALL_TURN)
    ctx["t1_log"] = fake.log()
    if not ok:
        return False, f"assistant_send refused: {answer}"
    results = tool_results(answer, "add_marker")
    on_a = ("A1 part 3" in [n for _, n in markers(app, a)])
    on_b = ("A1 part 3" in [n for _, n in markers(app, b)])
    at = [t for t, n in markers(app, a) if n == "A1 part 3"]
    undone = app.must("undo", project=a)
    after = "A1 part 3" in [n for _, n in markers(app, a)]
    good = (front is not None and os.path.samefile(front, b) and answer["state"] == "finished"
            and answer["text"] == "T1: the marker is in." and len(results) == 1
            and results[0].get("is_error") is False and on_a and not on_b and at == [1200000]
            and not after)
    return good, (f"B frontmost {front == b}; {brief(answer)}; add_marker results "
                  f"{[r.get('is_error') for r in results]}; on A {on_a} at {at}, on B {on_b}; "
                  f"undo {str(undone)[:60]!r} → on A {after}")


def row_t2(app, ctx):
    log = ctx.get("t1_log") or {}
    requests = log.get("requests", [])
    sent = posts(log)
    problems = []
    gets = [r["path"] for r in requests if r.get("method") == "GET"]
    if f"/v1/models/{DEFAULT_MODEL}" not in gets:
        problems.append(f"GETs {gets}")
    if not sent:
        return False, "no POST in T1's log"
    for at, request in enumerate(sent):
        body = request.get("body") or {}
        if body.get("model") != DEFAULT_MODEL or credential(request) != KEY:
            problems.append(f"POST {at + 1}: model {body.get('model')!r}, credential "
                            f"{'the dummy' if credential(request) == KEY else 'another'}")
    first = sent[0].get("body") or {}
    system = system_text(first) or ""
    halves = system.split("\n\n")
    if len(halves) != 2 or not all(h.strip() for h in halves):
        problems.append(f"system has {len(halves)} parts")
    tools = first.get("tools", [])
    names = [t.get("name") for t in tools]
    wanted = [SEARCH_TOOL] + [n for n in ctx["catalog"]
                              if n not in ("record_screen", "close_project")  # withheld (AI-7, #40)
                              and n not in DEV_TOOLS]
    if names != wanted:
        extra = sorted(set(names) - set(wanted))
        missing = sorted(set(wanted) - set(names))
        problems.append(f"tools differ: {len(names)} vs {len(wanted)}, extra {extra}, "
                        f"missing {missing}, first {names[:2]}")
    up_front = sorted(t.get("name") for t in tools
                      if t.get("name") != SEARCH_TOOL and "defer_loading" not in t)
    deferred_wrong = [t.get("name") for t in tools
                      if t.get("name") != SEARCH_TOOL and t.get("name") not in CORE_TOOLS
                      and t.get("defer_loading") is not True]
    if up_front != sorted(CORE_TOOLS):
        problems.append(f"up front {up_front}")
    if deferred_wrong:
        problems.append(f"not deferred {deferred_wrong[:5]}")
    if log.get("failures"):
        problems.append(f"failures {log['failures']}")
    detail = (f"{len(sent)} POSTs, GETs {gets}; system halves "
              f"{[len(h) for h in halves]} chars; {len(names)} tools, up front {up_front}")
    return not problems, detail + ("" if not problems else " — " + "; ".join(problems))


def row_r(app, fake, ctx):
    a = ctx["A"]
    before = app.must("get_project", project=a)["project"]
    fake.scenario([])
    tries = [("allow", "No question is pending: allow and deny answer the assistant's "
                       "ask-first question."),
             ("stop", "No turn is running, so there is nothing to stop."),
             ("maybe", 'answer must be allow, deny or stop (got "maybe").')]
    notes, good = [], True
    for value, sentence in tries:
        ok, answer = app.call("assistant_answer", project=a, answer=value, timeout=WALL_TURN)
        right = (not ok) and answer == sentence
        good = good and right
        notes.append(f"{value}: {'refused as written' if right else repr(answer)[:120]}")
    after = app.must("get_project", project=a)["project"]
    quiet = not fake.log().get("requests")
    good = good and before == after and quiet
    return good, "; ".join(notes) + f"; project unchanged {before == after}; stand-in quiet {quiet}"


def export_row(app, fake, ctx, tag, reply, path, expect_sentence, extra=None):
    """Sends a turn whose model asks to export to `path`; answers the send."""
    replies = [use(f"toolu_{tag}", "export", {"preset": "h264", "path": path}), say(reply)]
    fake.scenario(replies + (extra or []))
    ok, answer = app.call("assistant_send", project=ctx["A"],
                          text=f"Export the project ({tag}).", timeout=WALL_TURN)
    if not ok:
        return None, f"assistant_send refused: {answer}"
    question = answer.get("question") or {}
    if answer.get("state") != "asking" or question.get("sentence") != expect_sentence:
        return None, f"send: {brief(answer)}; wanted asking {expect_sentence!r}"
    return answer, None


def row_d(app, fake, ctx):
    app.must("add_text_clip", project=ctx["A"], track=1, at=0, duration=1200000)
    path = os.path.join(ctx["folder"], "D.mp4")
    sentence = f"export writes {path}"
    sent, why = export_row(app, fake, ctx, "d", "D: declined, fine.", path, sentence)
    if sent is None:
        return False, why
    none_after_ask = not os.path.exists(path)
    ok, answer = app.call("assistant_answer", project=ctx["A"], answer="deny",
                          timeout=WALL_TURN)
    if not ok:
        return False, f"deny refused: {answer}"
    log = fake.log()
    sent_posts = posts(log)
    result = tool_result_block(sent_posts[1].get("body") or {}, "toolu_d") \
        if len(sent_posts) > 1 else None
    by = answers_by(answer, "person")
    good = (none_after_ask and answer["state"] == "finished" and not os.path.exists(path)
            and result == (True, f"The person declined: {sentence}.")
            and len(by) == 1 and by[0].get("allowed") is False and not log.get("failures"))
    return good, (f"asked {sentence!r}, no file {none_after_ask}; deny: {brief(answer)}; no "
                  f"file {not os.path.exists(path)}; POST 2 tool_result {result}; answer by "
                  f"person {by}; failures {log.get('failures')}")


def row_e(app, fake, ctx):
    path = os.path.join(ctx["folder"], "E.mp4")
    with open(path, "wb") as handle:
        handle.write(b"sentinel: not a movie\n")
    sent, why = export_row(app, fake, ctx, "e", "E: exported.", path,
                           f"export REPLACES {path}")
    if sent is None:
        return False, why
    ok, answer = app.call("assistant_answer", project=ctx["A"], answer="allow",
                          timeout=WALL_TURN)
    if not ok:
        return False, f"allow refused: {answer}"
    with open(path, "rb") as handle:
        head = handle.read(12)
    sent_posts = posts(fake.log())
    result = tool_result_block(sent_posts[1].get("body") or {}, "toolu_e") \
        if len(sent_posts) > 1 else None
    good = (answer["state"] == "finished" and head[4:8] == b"ftyp"
            and result is not None and result[0] is False)
    return good, (f"allow: {brief(answer)}; bytes 4–8 {head[4:8]!r}; POST 2 tool_result "
                  f"{result and (result[0], result[1][:60])}")


def row_s(app, fake, ctx):
    path = os.path.join(ctx["folder"], "S.mp4")
    sent, why = export_row(app, fake, ctx, "s", "S: stopped.", path, f"export writes {path}",
                           extra=[say("S: a spare reply.")])
    if sent is None:
        return False, why
    ok, answer = app.call("assistant_answer", project=ctx["A"], answer="stop",
                          timeout=WALL_TURN)
    if not ok:
        return False, f"stop refused: {answer}"
    time.sleep(1.0)  # a stopped call that ran would have written by now
    log = fake.log()
    by = answers_by(answer, "stop")
    ctx["s_posts"] = len(posts(log))
    good = (answer["state"] == "finished" and not os.path.exists(path) and len(by) == 1
            and by[0].get("allowed") is False and not log.get("failures"))
    return good, (f"stop: {brief(answer)}; no file {not os.path.exists(path)}; answer by stop "
                  f"{by}; POSTs {ctx['s_posts']} (measured); failures {log.get('failures')}")


def row_x(app, fake, ctx):
    path = os.path.join(ctx["folder"], "X.mp4")
    sent, why = export_row(app, fake, ctx, "x", "X: never said.", path, f"export writes {path}")
    if sent is None:
        return False, why
    helpers = helper_children(app.child.pid)
    if len(helpers) != 1:
        return False, f"{len(helpers)} helper children of the app, not 1: {helpers}"
    os.kill(helpers[0], signal.SIGKILL)
    killed = time.monotonic()
    fake.scenario([use("toolu_x2", "add_marker", {"at": 2400000, "name": "X marker"}),
                   say("X: back again.")])
    refusals, answer = [], None
    while time.monotonic() - killed < 10:
        ok, got = app.call("assistant_send", project=ctx["A"], text="Mark four seconds.",
                           timeout=WALL_TURN)
        if ok:
            answer = got
            break
        refusals.append(got[:80])
        time.sleep(0.25)
    took = time.monotonic() - killed
    if answer is None:
        return False, f"no send taken within 10 s of the kill; refusals {refusals[-2:]}"
    landed = (2400000, "X marker") in markers(app, ctx["A"])
    alive = app.child.poll() is None
    good = answer["state"] == "finished" and landed and not os.path.exists(path) and alive
    return good, (f"killed helper {helpers[0]}; a send taken {took:.1f} s later after "
                  f"{len(refusals)} refusals; {brief(answer)}; marker on A {landed}; no file "
                  f"{not os.path.exists(path)}; app alive {alive}")


def row_k1(app):
    in_answers = [i for i, text in enumerate(app.answers) if KEY in text]
    in_log = KEY in app.log()
    return (not in_answers and not in_log), (f"{len(app.answers)} MCP answers, the key in "
                                              f"{len(in_answers)}; in the log {in_log}")


def stopped_turn(answer, tool, sentence):
    """Problems with a turn Stop cut at `STOP_AFTER` s while `tool` ran."""
    problems = []
    stopped, waited = answer.get("stopped_ms"), answer.get("waited_ms")
    if answer.get("state") != "finished":
        problems.append(f"state {answer.get('state')}")
    if not isinstance(stopped, int) or stopped < STOP_AFTER * 1000:
        problems.append(f"stopped_ms {stopped}")
    elif not isinstance(waited, int) or waited - stopped > WALL_STOPPED:
        problems.append(f"{LATE} {waited} − {stopped} > {WALL_STOPPED}")
    results = tool_results(answer, tool)
    if [(r.get("is_error"), r.get("summary")) for r in results] != [(True, sentence)]:
        problems.append(f"{tool} results {[(r.get('is_error'), r.get('summary')) for r in results]}")
    return problems


def row_sx(app, fake, ctx):
    b = ctx.get("B") or app.must(
        "new_project", path=os.path.join(ctx["folder"], "B.framejob"))["saved"]
    app.must("add_text_clip", project=b, track=1, at=0, duration=SX_SECONDS * 600000)
    path = os.path.join(ctx["folder"], "SX.mp4")
    fake.scenario([use("toolu_sx", "export", {"preset": "h264", "path": path},
                       said=ctx.get("echo")),
                   say("SX: stopped.")])
    ok, sent = app.call("assistant_send", project=b, text="Export the long project (SX).",
                        timeout=WALL_TURN)
    if not ok or sent.get("state") != "asking":
        return False, f"send: {sent if not ok else brief(sent)}; wanted asking"
    ok, answer = app.call("assistant_answer", project=b, answer="allow", stop_after=STOP_AFTER,
                          timeout=WALL_SX)
    if not ok:
        return False, f"allow with stop_after refused: {answer}"
    time.sleep(1.0)  # an export that ran on would still be writing, or have written
    exists = os.path.exists(path)
    log = fake.log()
    problems = stopped_turn(answer, "export", "The export was cancelled.")
    if exists:
        problems.append(f"{path} exists")
    if log.get("failures"):
        problems.append(f"failures {log['failures']}")
    return not problems, (f"a {SX_SECONDS} s text clip (control: un-stopped, its h264 export "
                          f"takes over 10 s); {brief(answer)}, stopped_ms "
                          f"{answer.get('stopped_ms')}; export results "
                          f"{[(r.get('is_error'), r.get('summary')) for r in tool_results(answer, 'export')]}"
                          f"; file 1 s later {exists}"
                          + ("" if not problems else " — " + "; ".join(problems)))


def long_fixture(ten):
    """(path, seconds) of WORK/long.wav: `ten`'s frames written ST_COPIES times,
    in `ten`'s channels, width and rate; reused only when all four match."""
    path = os.path.join(WORK, "long.wav")
    with wave.open(ten, "rb") as source:
        channels, width, rate = source.getnchannels(), source.getsampwidth(), source.getframerate()
        frames = source.getnframes()
        body = source.readframes(frames)
    wanted = ST_COPIES * frames
    if os.path.exists(path):
        try:
            with wave.open(path, "rb") as held:
                same = (held.getnchannels(), held.getsampwidth(), held.getframerate(),
                        held.getnframes()) == (channels, width, rate, wanted)
        except (wave.Error, EOFError, OSError):
            same = False
        if same:
            return path, wanted / rate
    part = path + ".part"
    with wave.open(part, "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(width)
        out.setframerate(rate)
        for _ in range(ST_COPIES):
            out.writeframes(body)
    os.replace(part, path)
    return path, wanted / rate


def row_st(app, fake, ctx):
    import speech_engine_proof  # the fixtures' one maker
    pangram, ten, _, _ = speech_engine_proof.make_fixtures()
    check = app.must("new_project", path=os.path.join(ctx["folder"], "C-check.framejob"))["saved"]
    track = app.must("get_project", project=check)["project"]["tracks"][0]["id"]
    media = app.must("import_media", project=check, path=pangram)["media"]
    app.must("add_clip", project=check, track=track, media=media, at=0)
    ok, setup = app.call("transcribe", project=check, place=False)
    if not ok:
        if "not installed" in setup or "not available" in setup:
            return None, f"on-device transcription on this Mac: {setup[:160]!r}"
        return False, f"the setup transcribe over the pangram failed: {setup[:200]!r}"
    long, seconds = long_fixture(ten)
    c = app.must("new_project", path=os.path.join(ctx["folder"], "C.framejob"))["saved"]
    track = app.must("get_project", project=c)["project"]["tracks"][0]["id"]
    media = app.must("import_media", project=c, path=long)["media"]
    app.must("add_clip", project=c, track=track, media=media, at=0)
    fake.scenario([use("toolu_st", "transcribe", {"place": False}, said=ctx.get("echo")),
                   say("ST: stopped.")])
    ok, answer = app.call("assistant_send", project=c, text="Transcribe it (ST).",
                          stop_after=STOP_AFTER, timeout=WALL_ST)
    if not ok:
        return False, f"assistant_send with stop_after refused: {answer}"
    log = fake.log()
    problems = stopped_turn(answer, "transcribe", "The transcription was cancelled.")
    if log.get("failures"):
        problems.append(f"failures {log['failures']}")
    return not problems, (f"setup over the pangram answered; a {seconds:.0f} s WAV "
                          f"({ST_COPIES} × ten.wav); "
                          f"{brief(answer)}, stopped_ms {answer.get('stopped_ms')}; transcribe "
                          f"results {[(r.get('is_error'), r.get('summary')) for r in tool_results(answer, 'transcribe')]}"
                          + ("" if not problems else " — " + "; ".join(problems)))


# ---------------------------------------------------------------------------
# Launch B (W) and launch C (K2).


def row_w(app_path, fake, secrets):
    folder = os.path.join(WORK, "w")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    report_path = os.path.join(folder, "report.json")
    fake.scenario([use("toolu_w", "add_marker", {"at": 1200000, "name": "W marker"}),
                   say("W: done without a server.")])
    app = App("B", app_path,
              ["-RCSecretFolder", secrets,
               "-RCDevAssistantSend", "Put a marker at two seconds.",
               "-RCDevAssistantReport", report_path,
               "-FrameJobAssistantModel", PROOF_MODEL], fake.base, folder_mode=0o755)
    try:
        deadline = time.monotonic() + WALL_REPORT
        while time.monotonic() < deadline and not os.path.exists(report_path):
            if app.child.poll() is not None:
                break
            time.sleep(0.2)
        log_text = app.log()
        if not os.path.exists(report_path):
            return False, (f"no report within {WALL_REPORT} s (app exit {app.child.poll()}); "
                           f"log tail {log_text[-300:]!r}")
        with open(report_path) as handle:
            report = json.load(handle)
    finally:
        app.stop()
    log = fake.log()
    gets = [r["path"] for r in log.get("requests", []) if r.get("method") == "GET"]
    sent = posts(log)
    results = tool_results(report, "add_marker")
    project = (report.get("get_project") or {}).get("project", {}) \
        if isinstance(report.get("get_project"), dict) else {}
    marks = [(m.get("time"), m.get("name")) for m in project.get("markers", [])]
    posts_ok = bool(sent) and all((r.get("body") or {}).get("model") == PROOF_MODEL
                                  and credential(r) == KEY for r in sent)
    complaints = [l for l in log_text.splitlines() if "Frame Job: " in l]
    listening = "agent socket listening at" in log_text
    good = (report.get("ok") is True and report.get("server_running") is False
            and report.get("state") == "finished" and len(results) == 1
            and results[0].get("is_error") is False and (1200000, "W marker") in marks
            and f"/v1/models/{PROOF_MODEL}" in gets and posts_ok and not log.get("failures")
            and not complaints and not listening)
    return good, (f"report ok {report.get('ok')}, error {report.get('error')!r}, server "
                  f"{report.get('server_running')}, state {report.get('state')}, text "
                  f"{report.get('text')!r}; add_marker results "
                  f"{[r.get('is_error') for r in results]}; marker {(1200000, 'W marker') in marks}; "
                  f"GETs {gets}; {len(sent)} POSTs with {PROOF_MODEL} and the dummy {posts_ok}; "
                  f"failures {log.get('failures')}; `Frame Job: ` {complaints[:1]}; "
                  f"listening {listening}")


def row_k2(app_path, fake):
    app = App("C", app_path, [], fake.base)
    try:
        app.connect()
        fake.scenario([])
        app.must("new_project")
        ok, answer = app.call("assistant_send", text="Anything.", timeout=WALL_TURN)
        time.sleep(0.5)
        helpers = helper_children(app.child.pid)
    finally:
        app.stop()
    heard = fake.log().get("requests", [])
    good = (not ok and answer.startswith("No Anthropic API key is set.") and not heard
            and not helpers)
    return good, (f"assistant_send {'refused' if not ok else 'TAKEN'}: {str(answer)[:90]!r}; "
                  f"stand-in requests {len(heard)}; helper children {helpers}")


# ---------------------------------------------------------------------------
# The mutant.


def build_mutant(name):
    """(app path, None) or (None, reason): the tree copied, the mutant's one
    line deleted from the copy's file, `tree_copy.build_app` run there."""
    file, line, _, _ = MUTANTS[name]
    base = os.path.join(WORK, "mutant")
    tree_copy.remove_tree(base)
    root, reason = tree_copy.make_copy(os.path.join(base, "tree"))
    if root is None:
        return None, reason
    main = os.path.join(root, "app", "Sources", file)
    with open(main) as handle:
        lines = handle.read().splitlines(keepends=True)
    hits = [l for l in lines if l.strip() == line]
    if len(hits) != 1:
        return None, f"{file} has {len(hits)} `{line}` lines, not 1"
    with open(main, "w") as handle:
        handle.write("".join(l for l in lines if l.strip() != line))
    print(f"mutant: {line} deleted from the copy's {file}; building it (up to {WALL_BUILD} s)…",
          flush=True)
    app, reason = tree_copy.build_app(root, WALL_BUILD, env=child_env())
    if app is None:
        return None, reason
    return str(app), None


def mutant_verdict(mutant, results, skipped, details):
    """Rule R for a `--mutant` run over `main`'s `(row_id, ok, instrument)`
    list, its skipped ids and `{row_id: detail}`: 2 when the named row was
    skipped or never scored, any row is an instrument failure, or the named
    row FAILed without the text `MUTANTS` requires in its detail; 1 when the
    named row FAILed (caught); 0 when it passed (survived)."""
    _, _, named, text = MUTANTS[mutant]
    scored = {r: ok for r, ok, _ in results}
    broken = [r for r, _, instrument in results if instrument]
    why = (f"{named} was a host skip" if named in skipped else
           f"{named} was never scored" if named not in scored else
           f"scored as instrument failures: {', '.join(broken)}" if broken else
           f"{named} failed without {text!r} in its detail"
           if not scored[named] and text is not None and text not in details.get(named, "")
           else "")
    if why:
        print(f"mutant {mutant}: the control could not be performed — {why}", flush=True)
        return 2
    if scored[named]:
        print(f"mutant {mutant}: SURVIVED — {named} passed", flush=True)
        return 0
    print(f"mutant {mutant}: caught — {named} failed", flush=True)
    return 1


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="its one row, against a build without its line; must FAIL "
                             "(key-echo builds nothing: launch A of the built app, K1 last)")
    args = parser.parse_args()
    os.makedirs(WORK, exist_ok=True)
    results = []
    skipped = []
    details = {}

    def score(row_id, ok, detail, *, instrument=False):
        details[row_id] = detail
        if ok is None:  # a named host skip, never a pass
            skipped.append(row_id)
            print(f"{row_id} SKIP — host: {detail}", flush=True)
            return
        results.append((row_id, ok, instrument))
        print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    def guarded(row_id, function, *arguments):
        try:
            score(row_id, *function(*arguments))
        except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
            score(row_id, False, f"the instrument could not run: {type(error).__name__}: "
                                 f"{error}", instrument=True)

    fake = None
    try:
        fake = Fake(os.path.join(WORK, "fake"))
        secrets = secret_folder()
        if args.mutant and MUTANTS[args.mutant][0] is not None:
            named = MUTANTS[args.mutant][2]
            app, why = build_mutant(args.mutant)
            if app is None:
                score(named, False, f"the mutant did not build: {why}", instrument=True)
                print(f"0/1\nmutant {args.mutant}: the control could not be performed — "
                      f"the mutant did not build: {why}", flush=True)
                return 2
            if named == "W":
                guarded("W", lambda: (lambda ok, d: (ok, "(no prepareAtLaunch) " + d))
                        (*row_w(app, fake, secrets)))
            else:
                folder = os.path.join(WORK, "mutant-a")
                shutil.rmtree(folder, ignore_errors=True)
                os.makedirs(folder)
                mutant_ctx = {"folder": folder}
                mutant_app = App("A", app, ["-RCSecretFolder", secrets], fake.base)
                try:
                    mutant_app.connect()
                    function = row_sx if named == "SX" else row_st
                    guarded(named, lambda: (lambda ok, d: (ok, f"({args.mutant}) " + d))
                            (*function(mutant_app, fake, mutant_ctx)))
                finally:
                    mutant_app.stop()
        else:
            release = os.path.join(ROOT, APP_PATH)
            folder = os.path.join(WORK, "a")
            shutil.rmtree(folder, ignore_errors=True)
            os.makedirs(folder)
            ctx = {"folder": folder}
            if args.mutant == "key-echo":
                ctx["echo"] = ECHO
            app = App("A", release, ["-RCSecretFolder", secrets], fake.base)
            try:
                app.connect()
                guarded("A0", row_a0, app, ctx)
                guarded("T1", row_t1, app, fake, ctx)
                guarded("T2", row_t2, app, ctx)
                guarded("R", row_r, app, fake, ctx)
                guarded("D", row_d, app, fake, ctx)
                guarded("E", row_e, app, fake, ctx)
                guarded("S", row_s, app, fake, ctx)
                guarded("X", row_x, app, fake, ctx)
                guarded("SX", row_sx, app, fake, ctx)
                guarded("ST", row_st, app, fake, ctx)
                guarded("K1", row_k1, app)
            except Exception as error:  # noqa: BLE001
                for row_id in ("A0", "T1", "T2", "R", "D", "E", "S", "X", "SX", "ST", "K1"):
                    if row_id not in [r for r, _, _ in results] + skipped:
                        score(row_id, False, f"launch A could not run: {error}",
                              instrument=True)
            finally:
                app.stop()
            if not args.mutant:
                guarded("W", row_w, release, fake, secrets)
                guarded("K2", row_k2, release, fake)
    except Exception as error:  # noqa: BLE001
        score("setup", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)
    finally:
        if fake is not None:
            fake.stop()

    passed = sum(1 for _, ok, _ in results if ok)
    print(f"{passed}/{len(results)}" + (f", skipped {', '.join(skipped)}" if skipped else ""),
          flush=True)
    if args.mutant:
        return mutant_verdict(args.mutant, results, skipped, details)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
