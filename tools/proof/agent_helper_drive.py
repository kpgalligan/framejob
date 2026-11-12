#!/usr/bin/env python3
"""Road map "swift-helper" SA2 and SA4 — the Swift helper, driven as the app runs it over
scripted conversations on the stand-in API, and held to its recordings: every event and every
request, key order included (spec §11 SA-4, SA-5, SA-6, SA-13; `archive/swift-helper.md` §9 SA2
and SA4 and their records in §13, condensed in `designs/adr/swift-helper.md`).

    python3 tools/proof/agent_helper_drive.py                       # every case (make test)
    python3 tools/proof/agent_helper_drive.py --cases text,tools    # these cases (and what they need)
    python3 tools/proof/agent_helper_drive.py --swift PATH          # a helper already built
    python3 tools/proof/agent_helper_drive.py --list                # the cases, mutants and controls
    python3 tools/proof/agent_helper_drive.py --mutant NAME         # a SWIFT_MUTANTS edit, built on
                                                                    # the persistent mutant tree
    python3 tools/proof/agent_helper_drive.py --control NAME        # a run or a recording altered in
                                                                    # memory (CONTROLS)
    python3 tools/proof/agent_helper_drive.py --record              # rewrite the recordings

The helper. B1 is the release helper the app bundles, built by `tools/agent/build_helper.sh` on the
app build's scratch path, `build/agent-swift` (`agent_helper_build.release`, spec §11 SA-8):
stripped and signed into `work/agent_helper_drive/swift/`, seconds while its stamp matches. Each
case starts it once with exactly HOME, TMPDIR (scratch folders) and PATH=/usr/bin:/bin, as
`AssistantSession` does, writes the app's lines (sorted keys, compact, `writeResult`'s spliced
answers) and reads stdout line by line. One stand-in (`anthropic_fake.py`) serves the run; each
case posts its scenario first, which resets its log. The price feed is this drive's own loopback
server, holding its answer until the drive has read the helper's `context_usage`, so the
refresh's `prices` and the Models lookup's `context_usage` cannot race. Every wait is bounded; a
hang, a crash, an exit other than 0 after stdin closes, or a stderr line without
`framejob-agent: ` FAILs the case and the drive goes on. Only children this drive started are
signalled.

What a case checks:
- its `expect`, so the run is not vacuous: the event types are the case's list, the POSTs and all
  the requests the case's counts, the stand-in's failures the case's list, the feed's GETs the
  case's count;
- its recording, `tools/proof/agent_helper_recorded/<case>.json` (spec §11 SA-13): the event
  stream line for line, as parsed JSON with each object's key order (numbers by value, so
  `1e-07` is `1e-7`, SA-6); every request's method, path, headers, body (parsed JSON with its key
  order at every level) and byte count; and the cache files the case names, their table once
  parsed and their bytes.
Three comparison rules put the same placeholders in the run and the recording, and nothing else
does. A fetched or cached table's `as_of` (in `prices` and in `cost`) and a cache file's
`fetched_at` are clock readings: each must be an ISO 8601 instant inside this run, and is then
`<clock>`. A cache file's `source` must be this run's feed, whose port is chosen per run, and is
then `<feed>`. BY_PRESENCE's headers, which the host, URLSession and the toolchain set, are held
by presence only, as `<by presence>`; a request's headers are a set, in no order. A case with no
recording FAILs, and the `recordings` row FAILs a recording with no case.

`--record` writes each case's recording from this run, in that form, and prints each case `new`,
`same` or `changed` with the paths that moved. It refuses, writing nothing and exiting 2, with
`--mutant` or `--control`, and when any case of the run fails a check other than its recording.
`make test` never passes it. Spec §11 SA-13 says which re-records need no new decision (a `make
prices` refresh, a Slaude re-pin): any other change to a recording lands with its own SA- entry.

The recordings were written by the last run of SA2's two-helper drive that passed whole, from its
Swift side, before SA4 deleted the Bun helper; so each holds a stream equal to the Bun helper's
but for SA2's sixteen allowed differences (its record in road map §13).

Mutants (`SWIFT_MUTANTS`): an edit of the helper's sources, built by `agent_helper_build.mutant`
on the persistent mutant tree `build/agent-swift-mutant/` (spec §11 SA-8), never in the tree's
own `agent/`; then the cases it names run. A mutant is caught only when every case it names
FAILs: `mutant <name>: caught — …`, exit 1; one that passed any SURVIVED, exit 0; one that did not
build could not perform its control, exit 2. Five of the eight change only a request body, which
only the recordings hold.

Controls (`CONTROLS`): one case run on the tree's helper with its run or its recording altered in
memory, to show each comparison rule is as narrow as it says. `control <name>: held — …`, exit 0,
when the case FAILed or passed as the control expects; `NOT held`, exit 1; exit 2 when it could not
be performed.

No network: the API is the stand-in, the feed is on 127.0.0.1, the only keys are the dummies
`proof-key` and `wrong-key`; the helper's environment is HOME, TMPDIR and PATH alone, and every
build child has ANTHROPIC_API_KEY and RC_ASSEMBLYAI_KEY popped (`agent_helper_build`). Nothing is
paid. Exit 0 PASS, 1 FAIL.
"""

import argparse
import copy
import datetime
import http.server
import json
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools" / "agent"))
import agent_helper_build  # noqa: E402
import assistant_helper_proof as ahp  # noqa: E402

WORK = HERE / "work" / "agent_helper_drive"
AGENT = ROOT / "agent"
SWIFT_HELPER = WORK / "swift" / "framejob-agent"
REDUCE_CASES = AGENT / "prices" / "reduce_cases.json"
MODEL = "claude-opus-5-5"
KEY = "proof-key"
WALL_EVENT, WALL_EXIT = 30, 10
STDERR_PREFIX = "framejob-agent: "
RECORDED = HERE / "agent_helper_recorded"
# The headers a recording holds by presence only (spec §11 SA-13): the stand-in's port, and what
# URLSession, the OS and the toolchain set, which another Mac or Xcode may change.
BY_PRESENCE = ("host", "accept-language", "accept-encoding", "connection", "x-stainless-arch",
               "x-stainless-os", "x-stainless-runtime-version")
PRESENT = "<by presence>"
SIDES = ("recorded", "this run")

# ---------------------------------------------------------------------------
# What the app sends: a small catalog, a system prompt and a search guide.

SYSTEM = "You edit the open Frame Job project for the person. «Quotes», é and a\nsecond line."
GUIDE = "Tool search finds: render_frame, list_graphics, get_media_analysis."
INSTRUCTIONS = "Keep the project's name and the person's last request."
CATALOG = [
    {"name": "get_project", "description": "Answers the open project as JSON.",
     "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
    {"name": "set_playhead", "description": "Moves the playhead.",
     "inputSchema": {"type": "object", "required": ["seconds"],
                     "properties": {"seconds": {"type": "number", "minimum": 0,
                                                "description": "Where, in seconds."}}}},
    {"name": "render_frame", "description": "Renders the frame at a time to a PNG.",
     "inputSchema": {"type": "object", "properties": {"at": {"type": "number"},
                                                      "width": {"type": "integer"}}}},
    {"name": "list_graphics", "description": "Lists the project's graphics.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "get_media_analysis", "description": "Answers a media's cached analysis.",
     "inputSchema": {"type": "object", "required": ["media", "kind"],
                     "properties": {"media": {"type": "string"},
                                    "kind": {"type": "string", "enum": ["faces", "shots"]}}}},
]
CORE = ["get_project", "set_playhead"]
SETTINGS = {"auto_compact_tokens": 300000, "clear_tool_results": False}
COMPACT_AT = {"auto_compact_tokens": 1000, "clear_tool_results": False}

# Placeholders a case's `configure` overrides are resolved from, per run.
CACHE, FEED, CLOSED, ABSENT = "<cache>", "<feed>", "<closed>", "<absent>"

# Tool answers, as the app's dispatcher writes them (`writeResult` splices them verbatim).
TEXT = '{"content":[{"type":"text","text":"{\\"name\\":\\"Demo\\",\\"clips\\":2}"}]}'
IMAGE = ('{"content":[{"type":"image","data":"iVBORw0KGgoAAAANSUhEUg==","mimeType":"image/png"},'
         '{"type":"text","text":"The frame at 1.5 s."}]}')
REFUSED = '{"content":[{"type":"text","text":"set_playhead was refused: past the end."}],"isError":true}'
NULL = "null"
EMPTY = '{"content":[]}'
CANCELLED = '{"content":[{"type":"text","text":"Cancelled by the user."}],"isError":true}'


def text(words):
    return {"type": "text", "text": words}


def tool(ident, name, arguments):
    return {"type": "tool_use", "id": ident, "name": name, "input": arguments}


def thinking(words, signature):
    return {"type": "thinking", "thinking": words, "signature": signature}


def compaction(summary):
    return {"type": "compaction", "content": summary}


def reply(content, stop, **extra):
    return dict({"content": content, "stop_reason": stop}, **extra)


def iterations(before, summary):
    zero = {"cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    return [dict({"type": "compaction", "input_tokens": before, "output_tokens": summary}, **zero)]


def settings(limit, clearing):
    return {"type": "settings", "settings": {"auto_compact_tokens": limit,
                                             "clear_tool_results": clearing}}


def expect(types, posts, requests, failures=(), feed_gets=None):
    return {"types": list(types), "posts": posts, "requests": requests,
            "failures": list(failures), "feed_gets": feed_gets}


# Event-type runs the expectations are written from.
HELLO = ["prices", "ready", "context_usage"]
ROUND = ["message_done", "cost", "context_usage"]
TURN = ["turn_started", "text_delta"] + ROUND + ["turn_finished"]
SUMMARISED = ["compaction_started", "cost", "compacted", "context_usage", "turn_finished"]
UNSUMMARISED = ["compaction_started", "cost", "compaction_failed", "turn_finished"]
FAILED = ["turn_started", "error", "turn_finished"]
CUT = ["turn_started", "text_delta", "cost", "error", "turn_finished"]

LONG = 5000  # input tokens of a reply that puts the context past a limit of 1000

# ---------------------------------------------------------------------------
# The cases. Each: the stand-in's scenario, the app's steps, and what the Swift helper must do.
#
# Steps: ("configure", overrides) writes `configure` and waits for its `ready` and then the
# `context_usage` its Models lookup ends with; ("message", obj) writes one message (a tuple
# ("configure", overrides) is a configure written without waiting); ("raw", s) writes one line as
# it is; ("send", s); ("wait", type) waits for the next event of that type; ("wait_any", types)
# for the next of any of them; ("cancel_on", type) waits for it and writes `cancel`; ("answer",
# [(k, result), …]) waits for that many new `tool_request`s and answers the k-th of them in the
# order given, each once the last answer's `tool_result` event came back; ("turn",) waits for
# `turn_finished`; ("release_feed",) lets the held price feed answer; ("close",) closes stdin and
# waits for the exit.

CASES = {
    "handshake": {
        "scenario": {"replies": []},
        "steps": [("configure", {}), ("close",)],
        "expect": expect(HELLO, 0, 1),
    },
    "text": {
        "scenario": {"replies": [reply([text("Hello from the stand-in.")], "end_turn")]},
        "steps": [("configure", {}), ("send", "Say hello. «Quoted» é"), ("turn",), ("close",)],
        "expect": expect(HELLO + TURN, 1, 2),
    },
    "thinking": {
        "scenario": {"replies": [
            reply([thinking("Reading the timeline first.", "sig-one"), text("Two clips.")],
                  "end_turn"),
            reply([text("Done.")], "end_turn")]},
        "steps": [("configure", {}), ("send", "How many clips?"), ("turn",),
                  ("send", "Thanks."), ("turn",), ("close",)],
        "expect": expect(HELLO + ["turn_started", "progress_delta", "text_delta"] + ROUND
                         + ["turn_finished"] + TURN, 2, 3),
    },
    "tools": {
        "scenario": {"replies": [
            reply([text("Looking."), tool("toolu_1", "get_project", {}),
                   tool("toolu_2", "render_frame", {"at": 1.5, "width": 640}),
                   tool("toolu_3", "set_playhead", {"seconds": 99}),
                   tool("toolu_4", "get_media_analysis", {"media": "m1", "kind": "faces"}),
                   tool("toolu_5", "list_graphics", {}),
                   tool("toolu_6", "not_a_tool", {"x": 1})], "tool_use"),
            reply([text("All done.")], "end_turn")]},
        "steps": [("configure", {}), ("send", "Look at the project."),
                  ("answer", [(4, EMPTY), (3, NULL), (2, REFUSED), (1, IMAGE), (0, TEXT)]),
                  ("turn",), ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta"] + ROUND
                         + ["tool_call", "tool_request"] * 5 + ["tool_result"] * 5
                         + ["text_delta"] + ROUND + ["turn_finished"], 2, 3),
    },
    "two-turns": {
        "scenario": {"replies": [
            reply([text("One.")], "end_turn"),
            reply([text("Two.")], "end_turn", context_management={"applied_edits": [
                {"type": "clear_tool_uses_20250919", "cleared_tool_uses": 1,
                 "cleared_input_tokens": 1200}]})]},
        "steps": [("configure", {}), ("send", "First."), ("turn",),
                  ("message", settings(300000, True)), ("send", "Second."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + TURN + ["turn_started", "text_delta"] + ROUND
                         + ["tool_results_cleared", "turn_finished"], 2, 3),
    },
    "settings-mid-turn": {
        "scenario": {"replies": [
            reply([tool("toolu_1", "get_project", {})], "tool_use"),
            reply([text("Done.")], "end_turn", input_tokens=LONG),
            reply([compaction("The person asked for the project; it has two clips.")],
                  "compaction", iterations=iterations(LONG, 42)),
            reply([text("Next.")], "end_turn")]},
        "steps": [("configure", {}), ("send", "Do it."), ("wait", "tool_request"),
                  ("message", settings(1000, True)), ("answer", [(0, TEXT)]), ("turn",),
                  ("send", "And then?"), ("turn",), ("close",)],
        "expect": expect(HELLO + ["turn_started"] + ROUND
                         + ["tool_call", "tool_request", "tool_result", "text_delta"] + ROUND
                         + SUMMARISED + TURN, 4, 5),
    },
    "compaction": {
        "scenario": {"replies": [
            reply([text("A long answer.")], "end_turn", input_tokens=LONG),
            reply([compaction("Summary one.")], "compaction", iterations=iterations(LONG, 40)),
            reply([text("After the summary.")], "end_turn")]},
        "steps": [("configure", {"settings": {"auto_compact_tokens": 1000,
                                              "clear_tool_results": True}}),
                  ("send", "Talk at length."), ("turn",), ("send", "Go on."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta"] + ROUND + SUMMARISED + TURN, 3, 4),
    },
    "compaction-wrong-stop": {
        "scenario": {"replies": [
            reply([text("A long answer.")], "end_turn", input_tokens=LONG),
            reply([text("No summary here.")], "end_turn"),
            reply([text("After.")], "end_turn")]},
        "steps": [("configure", {"settings": COMPACT_AT}),
                  ("send", "Talk at length."), ("turn",), ("send", "Go on."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta"] + ROUND
                         + ["compaction_started", "text_delta", "cost", "compaction_failed",
                            "turn_finished"] + TURN, 3, 4),
    },
    "compaction-wrong-stop-block": {
        "scenario": {"replies": [
            reply([text("A long answer.")], "end_turn", input_tokens=LONG),
            reply([compaction("A summary that stopped wrong.")], "end_turn"),
            reply([text("After.")], "end_turn")]},
        "steps": [("configure", {"settings": COMPACT_AT}),
                  ("send", "Talk at length."), ("turn",), ("send", "Go on."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta"] + ROUND + UNSUMMARISED + TURN,
                         3, 4),
    },
    "compaction-empty": {
        "scenario": {"replies": [
            reply([text("A long answer.")], "end_turn", input_tokens=LONG),
            reply([compaction(None)], "compaction", iterations=iterations(LONG, 0)),
            reply([text("After.")], "end_turn")]},
        "steps": [("configure", {"settings": COMPACT_AT}),
                  ("send", "Talk at length."), ("turn",), ("send", "Go on."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta"] + ROUND + UNSUMMARISED + TURN,
                         3, 4),
    },
    "cut-reply-tool-call": {
        "scenario": {"replies": [
            reply([text("Starting."), tool("toolu_1", "get_project", {}),
                   tool("toolu_2", "list_graphics", {})], "max_tokens", input_tokens=LONG),
            reply([text("Resumed.")], "end_turn")]},
        "steps": [("configure", {"settings": COMPACT_AT}),
                  ("send", "Do two things."), ("turn",), ("send", "Go on."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta"] + ROUND
                         + ["compaction_started", "compaction_failed", "error", "turn_finished"]
                         + TURN, 2, 3),
    },
    "stop-sentences": {
        "scenario": {"replies": [
            reply([text("Cut at the limit")], "max_tokens"),
            reply([text("No.")], "refusal"),
            reply([text("Cut by the window")], "model_context_window_exceeded")]},
        "steps": [("configure", {}), ("send", "One."), ("turn",), ("send", "Two."), ("turn",),
                  ("send", "Three."), ("turn",), ("close",)],
        "expect": expect(HELLO + (["turn_started", "text_delta"] + ROUND
                                  + ["error", "turn_finished"]) * 3, 3, 4),
    },
    "pause-turn": {
        "scenario": {"replies": [reply([text("Thinking it over.")], "pause_turn"),
                                 reply([text("Finished.")], "end_turn")]},
        "steps": [("configure", {}), ("send", "Take your time."), ("turn",), ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta"] + ROUND + ["text_delta"] + ROUND
                         + ["turn_finished"], 2, 3),
    },
    "round-cap": {
        "scenario": {"replies": [reply([tool(f"toolu_r{n}", "get_project", {})], "tool_use")
                                 for n in range(1, 31)]},
        "steps": ([("configure", {}), ("send", "Keep going.")]
                  + [("answer", [(0, TEXT)])] * 30 + [("turn",), ("close",)]),
        "expect": expect(HELLO + ["turn_started"]
                         + (ROUND + ["tool_call", "tool_request", "tool_result"]) * 30
                         + ["turn_finished"], 30, 31),
    },
    "cancel-stream": {
        "scenario": {"replies": [reply([text("Partial words")], "end_turn", cut="stall"),
                                 reply([text("Fresh.")], "end_turn")]},
        "steps": [("configure", {}), ("send", "Start."), ("cancel_on", "text_delta"),
                  ("turn",), ("send", "Again."), ("turn",), ("close",)],
        "expect": expect(HELLO + ["turn_started", "text_delta", "cost", "turn_finished"] + TURN,
                         2, 3),
    },
    "cancel-tools": {
        "scenario": {"replies": [reply([tool("toolu_1", "get_project", {})], "tool_use"),
                                 reply([text("Fresh.")], "end_turn")]},
        "steps": [("configure", {}), ("send", "Start."), ("cancel_on", "tool_request"),
                  ("answer", [(0, CANCELLED)]), ("turn",), ("send", "Again."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + ["turn_started"] + ROUND
                         + ["tool_call", "tool_request", "tool_result", "turn_finished"] + TURN,
                         2, 3),
    },
    "stream-drop": {
        "scenario": {"replies": [reply([text("Cut")], "end_turn", cut="drop")]},
        "steps": [("configure", {}), ("send", "Start."), ("turn",), ("close",)],
        "expect": expect(HELLO + CUT, 1, 2),
    },
    "stream-error": {
        "scenario": {"replies": [reply([text("Half")], "end_turn", cut="error",
                                       error={"type": "overloaded_error",
                                              "message": "Overloaded"})]},
        "steps": [("configure", {}), ("send", "Start."), ("turn",), ("close",)],
        "expect": expect(HELLO + CUT, 1, 2),
    },
    "retry": {
        "scenario": {"replies": [{"http_error": {"status": 529, "type": "overloaded_error",
                                                 "message": "Overloaded",
                                                 "retry_after_ms": 10}}] * 4},
        "steps": [("configure", {}), ("send", "Start."), ("turn",), ("close",)],
        "expect": expect(HELLO + FAILED, 4, 5),
    },
    "past-script": {
        "scenario": {"replies": []},
        "steps": [("configure", {}), ("send", "Start."), ("turn",), ("close",)],
        "expect": expect(HELLO + FAILED, 1, 2,
                         failures=["POST /v1/messages #1: past the end of the script"]),
    },
    "wrong-key": {
        "scenario": {"replies": [reply([text("Never sent.")], "end_turn")]},
        "steps": [("configure", {"api_key": "wrong-key"}), ("send", "Start."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + FAILED, 1, 2),
    },
    "no-connection": {
        "scenario": {"replies": []},
        "steps": [("configure", {"api_base": CLOSED}), ("send", "Start."), ("turn",),
                  ("close",)],
        "expect": expect(HELLO + FAILED, 0, 0),
    },
    "refusals": {
        "scenario": {"replies": [reply([text("Slow words")], "end_turn", cut="stall")]},
        "steps": [("send", "Too early."), ("wait", "error"), ("configure", {}),
                  ("send", "Hello."), ("wait", "text_delta"), ("send", "Again."),
                  ("wait", "error"), ("message", {"type": "cancel"}), ("turn",), ("close",)],
        "expect": expect(["error"] + HELLO + ["turn_started", "text_delta", "error", "cost",
                                              "turn_finished"], 1, 2),
    },
    "bad-lines": {
        "scenario": {"replies": [reply([text("Hi.")], "end_turn")]},
        # Each line the helpers may answer with silence is followed by a configure, whose
        # `prices` / `ready` / `context_usage` mark where its answer, if any, ended.
        "steps": [("configure", {}), ("raw", ""), ("raw", "{not json"), ("wait", "error"),
                  ("raw", "[1]"), ("configure", {}), ("raw", '{"type":"mystery"}'),
                  ("configure", {}), ("send", "Hello."), ("turn",),
                  ("raw", '{"type":"reset"}'), ("configure", {}), ("close",)],
        "expect": expect(HELLO + ["error", "error"] + HELLO * 2 + TURN + HELLO, 1, 5),
    },
    "configure-no-key": {
        "scenario": {"replies": []},
        "steps": [("message", ("configure", {"api_key": ABSENT})),
                  ("wait_any", ["error", "context_usage"]), ("configure", {}), ("close",)],
        "expect": expect(["error"] + HELLO, 0, 1),
    },
    "prices-fetched": {
        "scenario": {"replies": []},
        "steps": [("message", ("configure", {"price_cache": CACHE, "price_feed": FEED})),
                  ("wait", "ready"), ("wait", "context_usage"), ("release_feed",),
                  ("wait", "prices"), ("close",)],
        "files": ["prices.json"],
        "expect": expect(["ready", "context_usage", "prices"], 0, 1, feed_gets=1),
    },
    # The helper started on the cache file it wrote in `prices-fetched`: it reads it, reports
    # it before `ready` and prices a turn from it, with no refresh. (SA2 started each helper on
    # the other's; reading the TypeScript helper's indented layout is PriceTableTests' now.)
    "prices-cached": {
        "requires": "prices-fetched",
        "scenario": {"replies": [reply([text("Priced.")], "end_turn")]},
        "steps": [("configure", {"price_cache": CACHE, "price_feed": FEED}),
                  ("send", "What does this cost?"), ("turn",), ("close",)],
        "expect": expect(HELLO + TURN, 1, 2, feed_gets=0),
    },
}


# ---------------------------------------------------------------------------
# The helper's build.


def build_swift():
    """(helper path, detail) or (None, why): the release helper the app bundles, built by the
    app's own script (spec §11 SA-8)."""
    return agent_helper_build.release(SWIFT_HELPER)


# ---------------------------------------------------------------------------
# One helper process, as the app runs it.


class Helper:
    """The helper in its own session with exactly HOME, TMPDIR and PATH=/usr/bin:/bin, HOME and
    TMPDIR scratch folders; stdout read line by line on a thread."""

    def __init__(self, path, folder):
        home, tmp = folder / "home", folder / "tmp"
        home.mkdir(parents=True)
        tmp.mkdir(parents=True)
        env = {"HOME": str(home), "TMPDIR": str(tmp) + "/", "PATH": "/usr/bin:/bin"}
        self.lines, self.stderr, self.eof = [], [], False
        self.cond = threading.Condition()
        self.child = subprocess.Popen([str(path)], env=env, cwd=str(folder),
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, start_new_session=True)
        self.readers = [threading.Thread(target=self._out, daemon=True),
                        threading.Thread(target=self._err, daemon=True)]
        for reader in self.readers:
            reader.start()

    def _out(self):
        for raw in self.child.stdout:
            line = raw[:-1] if raw.endswith(b"\n") else raw
            with self.cond:
                self.lines.append(line.decode("utf-8", "replace"))
                self.cond.notify_all()
        with self.cond:
            self.eof = True
            self.cond.notify_all()

    def _err(self):
        for raw in self.child.stderr:
            self.stderr.append(raw.decode("utf-8", "replace").rstrip("\n"))

    def events(self):
        out = []
        for line in list(self.lines):
            try:
                out.append(json.loads(line))
            except ValueError:
                out.append({"type": "<not JSON>", "line": line})
        return out

    def write(self, line):
        try:
            self.child.stdin.write((line + "\n").encode("utf-8"))
            self.child.stdin.flush()
            return True
        except OSError:
            return False

    def wait(self, test, seconds=WALL_EVENT):
        """`test(events)`'s first answer other than None, or None at the wall or once stdout has
        ended without one."""
        deadline = time.monotonic() + seconds
        with self.cond:
            while True:
                found = test(self.events())
                if found is not None or self.eof:
                    return found
                left = deadline - time.monotonic()
                if left <= 0:
                    return None
                self.cond.wait(min(left, 0.5))

    def close(self):
        try:
            self.child.stdin.close()
        except OSError:
            pass
        try:
            status = self.child.wait(timeout=WALL_EXIT)
        except subprocess.TimeoutExpired:
            return None
        for reader in self.readers:
            reader.join(timeout=2)
        return status

    def kill(self):
        ahp.kill_group(self.child)
        for reader in self.readers:
            reader.join(timeout=2)


def line_of(message):
    """A message as the app writes it: sorted keys, compact (`AssistantSession.write`, SA-5)."""
    return json.dumps(message, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


# ---------------------------------------------------------------------------
# The stand-in and the price feed.


class Feed:
    """`/litellm.json` on 127.0.0.1:0: reduce_cases.json's LiteLLM block with opus input at
    8e-06, answered only once `release()` is called; `arm()` holds it again for the next run."""

    def __init__(self):
        with open(REDUCE_CASES) as f:
            litellm = copy.deepcopy(json.load(f)["litellm"])
        litellm["claude-opus-5-5"]["input_cost_per_token"] = 8e-06
        self.body = json.dumps(litellm).encode()
        self.released = threading.Event()
        self.lock = threading.Lock()
        self.gets = 0
        feed = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *arguments):
                pass

            def do_GET(self):
                with feed.lock:
                    feed.gets += 1
                feed.released.wait(60)
                self.send_response(200)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(feed.body)))
                self.end_headers()
                self.wfile.write(feed.body)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/litellm.json"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def arm(self):
        with self.lock:
            self.gets = 0
        self.released.clear()

    def release(self):
        self.released.set()

    def stop(self):
        self.released.set()
        self.server.shutdown()
        self.server.server_close()


def closed_url():
    """A loopback base URL nothing listens on."""
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return f"http://127.0.0.1:{port}"


class Context:
    def __init__(self):
        self.fake, self.base = ahp.start_fake(str(WORK / "fake"))
        self.feed = Feed()
        self.closed = closed_url()
        self.started = datetime.datetime.now(datetime.timezone.utc)
        self.runs = {}  # case -> run

    def stop(self):
        self.feed.stop()
        ahp.kill_group(self.fake)


# ---------------------------------------------------------------------------
# One case over one helper.


def configure_message(ctx, folder, overrides):
    message = {"type": "configure", "api_key": KEY, "model": MODEL, "system": SYSTEM,
               "tools": CATALOG, "core_tools": CORE, "search_guide": GUIDE,
               "compaction_instructions": INSTRUCTIONS, "api_base": ctx.base,
               "settings": dict(SETTINGS)}
    for key, value in overrides.items():
        if isinstance(value, str):
            value = {CACHE: str(folder / "spend" / "prices.json"), FEED: ctx.feed.url,
                     CLOSED: ctx.closed}.get(value, value)
        if value == ABSENT:
            message.pop(key, None)
        else:
            message[key] = value
    return message


def find_next(kinds, start):
    kinds = {kinds} if isinstance(kinds, str) else set(kinds)

    def test(events):
        for at in range(start, len(events)):
            if events[at].get("type") in kinds:
                return at
        return None
    return test


def count_at_least(kind, total):
    def test(events):
        found = [at for at, e in enumerate(events) if e.get("type") == kind]
        return found[:total] if len(found) >= total else None
    return test


def perform(step, helper, state, ctx, folder):
    """One step; answers None, or why it could not be performed."""
    kind = step[0]
    if kind == "configure":
        if not helper.write(line_of(configure_message(ctx, folder, step[1]))):
            return "stdin closed"
        ready = helper.wait(find_next("ready", state["cursor"]))
        if ready is None:
            return "no ready"
        usage = helper.wait(find_next("context_usage", ready + 1))
        if usage is None:
            return "no context_usage after ready"
        state["cursor"] = usage + 1
        return None
    if kind == "message":
        message = step[1]
        if isinstance(message, tuple):
            message = configure_message(ctx, folder, message[1])
        return None if helper.write(line_of(message)) else "stdin closed"
    if kind == "raw":
        return None if helper.write(step[1]) else "stdin closed"
    if kind == "send":
        return None if helper.write(line_of({"type": "send", "text": step[1]})) else "stdin closed"
    if kind in ("wait", "wait_any", "cancel_on", "turn"):
        wanted = "turn_finished" if kind == "turn" else step[1]
        at = helper.wait(find_next(wanted, state["cursor"]))
        if at is None:
            return f"no {wanted}"
        state["cursor"] = at + 1
        if kind == "cancel_on":
            return None if helper.write(line_of({"type": "cancel"})) else "stdin closed"
        return None
    if kind == "answer":
        given = step[1]
        asked = helper.wait(count_at_least("tool_request", state["asked"] + len(given)))
        if asked is None:
            return f"fewer than {state['asked'] + len(given)} tool_requests"
        events = helper.events()
        requests = [events[at] for at in asked[state["asked"]:]]
        for k, result in given:
            before = len([e for e in helper.events() if e.get("type") == "tool_result"])
            call_id = json.dumps(requests[k].get("call_id"))
            if not helper.write(f'{{"type":"tool_result","call_id":{call_id},"result":{result}}}'):
                return "stdin closed"
            if helper.wait(count_at_least("tool_result", before + 1)) is None:
                return f"no tool_result event after answering request {k}"
        state["asked"] += len(given)
        return None
    if kind == "release_feed":
        ctx.feed.release()
        return None
    if kind == "close":
        state["exit"] = helper.close()
        state["closed"] = True
        return None if state["exit"] is not None else f"no exit within {WALL_EXIT} s"
    return f"no such step {kind!r}"


def run_case(name, path, ctx):
    case = CASES[name]
    folder = WORK / "runs" / name
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    run = {"problems": [], "files": {}, "exit": None}
    if "requires" in case:
        made = ctx.runs.get(case["requires"], {}).get("files", {}).get("prices.json")
        if made is None:
            run["problems"].append(f"{case['requires']} left no cache file")
        else:
            (folder / "spend").mkdir(parents=True)
            (folder / "spend" / "prices.json").write_bytes(made)
    ctx.feed.arm()
    status, _ = ahp.http("POST", ctx.base + "/__control/scenario", case["scenario"])
    if status != 200:
        run["problems"].append(f"the stand-in refused the scenario ({status})")
    helper = Helper(path, folder)
    state = {"cursor": 0, "asked": 0, "exit": None, "closed": False}
    try:
        for at, step in enumerate(case["steps"]):
            why = perform(step, helper, state, ctx, folder)
            if why is not None:
                run["problems"].append(f"step {at} {step[0]}: {why}")
                break
        if not state["closed"]:
            state["exit"] = helper.close()
    finally:
        helper.kill()
    run["exit"] = state["exit"]
    run["events"] = helper.events()
    run["stderr"] = list(helper.stderr)
    run["feed_gets"] = ctx.feed.gets
    _, log = ahp.http("GET", ctx.base + "/__control/log")
    log = log or {}
    run["requests"] = log.get("requests", [])
    run["failures"] = log.get("failures", [])
    for file in case.get("files", []):
        path_ = folder / "spend" / file
        if path_.is_file():
            run["files"][file] = path_.read_bytes()
    ctx.runs[name] = run
    return run


# ---------------------------------------------------------------------------
# The comparison.


def same(a, b):
    """Equal as parsed JSON with every object's key order: numbers by value (1e-07 is 1e-7,
    spec §11 SA-6), a bool never a number."""
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return list(a) == list(b) and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b


def short(value, limit=160):
    out = repr(value) if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return out if len(out) <= limit else out[:limit - 1] + "…"


def difference(a, b, path="$", sides=SIDES):
    """Where `a` (the first side) and `b` (the second) first differ, and how, or None."""
    return next(iter(differences(a, b, path, sides)), None)


def differences(a, b, path="$", sides=SIDES):
    """Every place `a` and `b` differ, in order: a key set, a key order, a length or a value."""
    if same(a, b):
        return []
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            return [f"{path}: keys only in {sides[0]} {[k for k in a if k not in b]}, "
                    f"only in {sides[1]} {[k for k in b if k not in a]}"]
        out = []
        for k in a:
            out += differences(a[k], b[k], f"{path}.{k}", sides)
        return out or [f"{path}: key order {list(a)} / {list(b)}"]
    if isinstance(a, list) and isinstance(b, list):
        out = []
        for at, (x, y) in enumerate(zip(a, b)):
            out += differences(x, y, f"{path}[{at}]", sides)
        if len(a) != len(b):
            out.append(f"{path}: length {len(a)} / {len(b)}")
        return out
    return [f"{path}: {short(a)} / {short(b)}"]


def is_clock(value, ctx):
    """An ISO 8601 instant inside this drive's run."""
    if not isinstance(value, str):
        return False
    try:
        at = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    if at.tzinfo is None:
        return False
    now = datetime.datetime.now(datetime.timezone.utc)
    slack = datetime.timedelta(seconds=2)
    return ctx.started - slack <= at <= now + slack


def unclock(run, ctx):
    """The comparison rules for clock readings and the feed (the module doc): `as_of` of a
    fetched or cached source, and a cache file's `fetched_at`, checked and then replaced by
    `<clock>`; a cache file's `source`, checked and then replaced by `<feed>`."""
    problems = []

    def source(value, where):
        if isinstance(value, dict) and value.get("kind") in ("fetched", "cached"):
            if is_clock(value.get("as_of"), ctx):
                value["as_of"] = "<clock>"
            else:
                problems.append(f"{where}'s as_of {short(value.get('as_of'))} is not a time in this run")

    for at, event in enumerate(run["events"]):
        if event.get("type") == "prices":
            source(event.get("source"), f"event {at}")
        if event.get("type") == "cost":
            source(event.get("prices"), f"event {at}")
    run["tables"], run["layouts"] = {}, {}
    for name, data in run["files"].items():
        try:
            table = json.loads(data)
        except ValueError:
            problems.append(f"{name} is not JSON")
            continue
        if not (isinstance(table, dict) and isinstance(table.get("models"), dict)
                and table["models"]):
            problems.append(f"{name} holds no price table")
            continue
        stamp = table.get("fetched_at")
        if not is_clock(stamp, ctx):
            problems.append(f"{name}'s fetched_at {short(stamp)} is not a time in this run")
            continue
        table["fetched_at"] = "<clock>"
        layout = data.replace(stamp.encode(), b"<clock>")
        # The table's source is the URL it was fetched from: this drive's own feed, on a port
        # chosen per run (spec §11 SA-13). Checked, then `<feed>`.
        url = table.get("source")
        if url != ctx.feed.url or layout.count(url.encode()) != 1:
            problems.append(f"{name}'s source {short(url)} is not this run's feed once")
            continue
        table["source"] = "<feed>"
        run["tables"][name] = table
        run["layouts"][name] = layout.replace(url.encode(), b"<feed>")
    return problems


def compare(name, run, ctx):
    """(problems, the run as a recording holds it) for one case: everything but the recording."""
    case = CASES[name]
    run = copy.deepcopy(run)
    problems = list(run["problems"]) + unclock(run, ctx)
    if run["exit"] != 0:
        problems.append(f"exit {run['exit']} after stdin closed")
    for line in run["stderr"]:
        if not line.startswith(STDERR_PREFIX):
            problems.append(f"a stderr line without {STDERR_PREFIX!r}: {short(line)}")
            break
    wanted = case["expect"]
    types = [e.get("type") for e in run["events"]]
    if types != wanted["types"]:
        problems.append(f"event types {types} are not the case's {wanted['types']}")
    posts = len([r for r in run["requests"] if r.get("method") == "POST"])
    if (posts, len(run["requests"])) != (wanted["posts"], wanted["requests"]):
        problems.append(f"{posts} POSTs of {len(run['requests'])} requests, the case expects "
                        f"{wanted['posts']} of {wanted['requests']}")
    if run["failures"] != wanted["failures"]:
        problems.append(f"the stand-in's failures {run['failures']}")
    if wanted["feed_gets"] is not None and run["feed_gets"] != wanted["feed_gets"]:
        problems.append(f"{run['feed_gets']} price feed GETs, the case expects "
                        f"{wanted['feed_gets']}")
    for file in case.get("files", []):
        if file not in run["files"]:
            problems.append(f"no {file} was written")
    return problems, recorded_form(run)


def events_differ(first, second, sides=SIDES):
    one, two = sides
    for at, (a, b) in enumerate(zip(first, second)):
        if not same(a, b):
            return [f"event {at}: {difference(a, b, '$', sides)}; {one} {short(a)}, "
                    f"{two} {short(b)}"]
    if len(first) != len(second):
        side, extra = ((one, first[len(second)]) if len(first) > len(second)
                       else (two, second[len(first)]))
        return [f"events: {one} {len(first)}, {two} {len(second)}; {side}'s next {short(extra)}"]
    return []


# ---------------------------------------------------------------------------
# The recordings (spec §11 SA-13).


def recorded_form(run):
    """A run, once `unclock` has put `<clock>` in it, as a recording holds it: its events, every
    request with BY_PRESENCE's headers `<by presence>` and the headers sorted by name (a set, in
    no order), and each cache file's table and bytes."""
    requests = []
    for request in run["requests"]:
        headers = request.get("headers") or {}
        requests.append({"method": request.get("method"), "path": request.get("path"),
                         "headers": {name: PRESENT if name in BY_PRESENCE else headers[name]
                                     for name in sorted(headers)},
                         "body": copy.deepcopy(request.get("body")),
                         "bytes": request.get("bytes")})
    files = {name: {"table": copy.deepcopy(table),
                    "bytes": run["layouts"][name].decode("utf-8", "replace")}
             for name, table in run.get("tables", {}).items()}
    return {"events": copy.deepcopy(run["events"]), "requests": requests, "files": files}


def recording_path(name):
    return RECORDED / f"{name}.json"


def read_recording(name):
    """The case's recording, or None when it has none."""
    path = recording_path(name)
    if not path.is_file():
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def recording_bytes(name, seen):
    document = {"case": name, "events": seen["events"], "requests": seen["requests"],
                "files": seen["files"]}
    return (json.dumps(document, indent=1, ensure_ascii=False) + "\n").encode("utf-8")


def against(name, seen, recorded):
    """How a run, in its recorded form, differs from the case's recording: [] when it does not."""
    if recorded is None:
        return [f"no recording {recording_path(name).relative_to(ROOT)}: write it with --record"]
    sides = SIDES
    out = [f"against the recording, {p}" for p in
           events_differ(recorded.get("events", []), seen["events"], sides)]
    mine, theirs = recorded.get("requests", []), seen["requests"]
    if len(mine) != len(theirs):
        out.append(f"against the recording, requests: recorded "
                   f"{[str(r.get('method')) + ' ' + str(r.get('path')) for r in mine]}, this run "
                   f"{[str(r.get('method')) + ' ' + str(r.get('path')) for r in theirs]}")
    # Per request, the first difference: the body before the headers, so a changed body is named
    # by what changed in it rather than by its content-length.
    for at, (r, s) in enumerate(zip(mine, theirs)):
        if (r.get("method"), r.get("path")) != (s.get("method"), s.get("path")):
            out.append(f"against the recording, request {at}: recorded {r.get('method')} "
                       f"{r.get('path')}, this run {s.get('method')} {s.get('path')}")
            break
        found = difference(r.get("body"), s.get("body"), "body", sides)
        if found:
            out.append(f"against the recording, request {at} {r.get('method')} {r.get('path')}: "
                       f"{found}")
            break
        if r.get("headers") != s.get("headers"):
            hr, hs = r.get("headers") or {}, s.get("headers") or {}
            diff = [f"{n}: {short(hr.get(n), 60)} / {short(hs.get(n), 60)}"
                    for n in sorted(set(hr) | set(hs)) if hr.get(n) != hs.get(n)]
            out.append(f"against the recording, request {at} headers: {'; '.join(diff)}")
            break
        if r.get("bytes") != s.get("bytes"):
            out.append(f"against the recording, request {at}: {r.get('bytes')} / "
                       f"{s.get('bytes')} bytes")
            break
    files = recorded.get("files", {})
    if sorted(files) != sorted(seen["files"]):
        out.append(f"against the recording, cache files: recorded {sorted(files)}, this run "
                   f"{sorted(seen['files'])}")
    for file in sorted(set(files) & set(seen["files"])):
        found = difference(files[file].get("table"), seen["files"][file]["table"], file, sides)
        if found:
            out.append(f"against the recording, {found}")
        elif files[file].get("bytes") != seen["files"][file]["bytes"]:
            out.append(f"against the recording, {file}: the same table in other bytes")
    return out


def recordings_row():
    """`recordings`: one recording per case, and none for a case the drive does not have."""
    held = sorted(path.stem for path in RECORDED.glob("*.json")) if RECORDED.is_dir() else []
    stray = [name for name in held if name not in CASES]
    missing = [name for name in CASES if name not in held]
    if stray:
        return False, f"a recording with no case: {', '.join(stray)} (remove it)"
    if missing:
        return False, f"no recording for {', '.join(missing)}"
    return True, f"{len(held)} recordings, one per case"


def record(names, seen_by_case):
    """Writes each case's recording; prints `new`, `same` or `changed` with the paths that moved."""
    RECORDED.mkdir(parents=True, exist_ok=True)
    for name in names:
        seen = seen_by_case[name]
        old = read_recording(name)
        data = recording_bytes(name, seen)
        if old is None:
            said = "new"
        else:
            moved = []
            for key in ("events", "requests", "files"):
                moved += differences(old.get(key), json.loads(data)[key], key)
            if moved:
                said = (f"changed: {'; '.join(moved[:8])}"
                        + (f"; and {len(moved) - 8} more" if len(moved) > 8 else ""))
            elif recording_path(name).read_bytes() != data:
                said = "changed: the same content in other bytes"
            else:
                said = "same"
        recording_path(name).write_bytes(data)
        print(f"recorded {name}: {said}", flush=True)


# ---------------------------------------------------------------------------
# Mutants: an edit to the Swift helper's sources, and the cases that must FAIL with it.

KIT = "agent/Sources/FrameJobAgentKit/"
SWIFT_MUTANTS = {
    # The tool results in reverse order: a body difference only the recording holds.
    "tool-results-reversed": (KIT + "Turn.swift", "        return answers.compactMap { $0 }\n",
                              "        return Array(answers.compactMap { $0 }.reversed())\n",
                              ["tools"]),
    # Every tool sent up front (`core` still read, as the suite's warnings are errors): a body
    # difference.
    "no-defer-loading": (KIT + "Request.swift",
                         "            if !core.contains(tool.name) { o[\"defer_loading\"] = true }\n",
                         "            _ = core\n", ["text", "tools", "compaction", "retry"]),
    # A response's price before its `message_done`.
    "cost-before-done": (KIT + "Turn.swift",
                         "                emit(.messageDone(stopReason: reply.message[\"stop_reason\"] ?? .null, "
                         "usage: reply.message[\"usage\"]))\n"
                         "                emitCost(reply.message, turn, partial: false)\n",
                         "                emitCost(reply.message, turn, partial: false)\n"
                         "                emit(.messageDone(stopReason: reply.message[\"stop_reason\"] ?? .null, "
                         "usage: reply.message[\"usage\"]))\n",
                         ["text", "tools"]),
    # Slaude's default retries, where the contract's are three.
    "two-retries": (KIT + "ClientFactory.swift", "    public static let maxRetries = 3\n",
                    "    public static let maxRetries = 2\n", ["retry"]),
    # The summary request with a clearing edit, which the API refuses beside a compaction: a
    # body difference.
    "summary-keeps-clearing": (KIT + "Request.swift",
                               "        o[\"compaction\"] = [\"type\": \"summarize\", "
                               "\"instructions\": .string(instructions)]\n",
                               "        o[\"context_management\"] = [\"edits\": "
                               "[[\"type\": .string(Self.clearEditType)]]]\n"
                               "        o[\"compaction\"] = [\"type\": \"summarize\", "
                               "\"instructions\": .string(instructions)]\n",
                               ["compaction"]),
    # The system block without the search guide: a body difference (SA2's `system-breakpoint`
    # row was shown no wider than SA-5 by it).
    "system-loses-guide": (KIT + "Request.swift",
                           "            \"text\": .string(\"\\(configure.system)\\n\\n\\(configure.searchGuide)\"),\n",
                           "            \"text\": .string(configure.system),\n",
                           ["text", "tools"]),
    # Another sentence for an unrun call: a body difference (SA2's `unrun-calls-answered`).
    "not-run-reworded": (KIT + "ToolResults.swift",
                         "         \"content\": .string(\"Not run: the reply stopped with \\(stopReason) "
                         "before this call could run.\"),\n",
                         "         \"content\": .string(\"Not run: stopped with \\(stopReason).\"),\n",
                         ["cut-reply-tool-call"]),
    # An empty summary swapped in, as SA-4 (c) says the TypeScript runner would: the events and
    # the next request change.
    "empty-summary-swapped": (KIT + "Compaction.swift",
                              "        guard Self.holdsSummary(reply.message) else {\n",
                              "        guard Self.holdsSummary(reply.message) || true else {\n",
                              ["compaction-empty"]),
}


# ---------------------------------------------------------------------------
# Controls: one case with its run or its recording altered in memory, and whether it must FAIL.
# Their names stay out of every identifier holding MUTANT, so `mutant_anchors.py` reads only
# SWIFT_MUTANTS.


def what(how):
    """An alteration's docstring on one line, without its full stop."""
    return " ".join(how.__doc__.split()).rstrip(".")


def first_of(items, test):
    return next((item for item in items if test(item)), None)


def alter_cost(run, recorded):
    """The recording's first `cost` charging twice the dollars."""
    cost = first_of(recorded["events"], lambda e: e.get("type") == "cost")
    cost["cost"]["dollars"] = cost["cost"]["dollars"] * 2


def alter_header(run, recorded):
    """The recording's POST holding the TypeScript SDK's API version."""
    post = first_of(recorded["requests"], lambda r: r.get("method") == "POST")
    post["headers"]["anthropic-version"] = "2023-06-01"


def alter_key_order(run, recorded):
    """The recording's POST body with its top-level keys in reverse order, the same values."""
    post = first_of(recorded["requests"], lambda r: r.get("method") == "POST")
    post["body"] = dict(reversed(list(post["body"].items())))


def drop_host_header(run, recorded):
    """The recording's first request without a header held by presence."""
    del recorded["requests"][0]["headers"]["host"]


def move_host_headers(run, recorded):
    """The run's first request with other values for the headers held by presence, and its
    headers in reverse order."""
    request = run["requests"][0]
    headers = dict(request["headers"], **{"host": "203.0.113.9:1",
                                         "accept-language": "fr-FR,fr;q=0.9",
                                         "x-stainless-runtime-version": "9.9"})
    request["headers"] = dict(reversed(list(headers.items())))


def move_feed(run, recorded):
    """The run's cache file naming another feed than this run's."""
    data = run["files"]["prices.json"]
    url = json.loads(data)["source"]
    run["files"]["prices.json"] = data.replace(url.encode(), b"http://127.0.0.1:1/litellm.json")


# name: (the case, the alteration, whether the case must FAIL)
CONTROLS = {
    "recorded-event-field": ("text", alter_cost, True),
    "recorded-header": ("text", alter_header, True),
    "recorded-key-order": ("text", alter_key_order, True),
    "recorded-host-header-missing": ("text", drop_host_header, True),
    "recorded-host-header-value": ("text", move_host_headers, False),
    "feed-elsewhere": ("prices-fetched", move_feed, True),
}


# ---------------------------------------------------------------------------
# Driving.


def ordered(names):
    out = []
    for name in names:
        need = CASES[name].get("requires")
        if need and need not in out:
            out.append(need)
        if name not in out:
            out.append(name)
    return out


def drive(names, swift, ctx, held=True, alter=None):
    """Runs each case and checks it, and when `held` holds it to its recording, printing its
    line; answers {case: (problems, the run as a recording holds it)}. `alter`: (case,
    function) applied to that case's run and recording before they are compared."""
    results = {}
    for name in names:
        started = time.monotonic()
        run = run_case(name, swift, ctx)
        recorded = read_recording(name) if held else None
        if alter is not None and alter[0] == name:
            run, recorded = copy.deepcopy(run), copy.deepcopy(recorded)
            alter[1](run, recorded)
        problems, seen = compare(name, run, ctx)
        if held:
            problems += against(name, seen, recorded)
        results[name] = (problems, seen)
        took = time.monotonic() - started
        print(f"{name} {'ok' if not problems else 'FAIL'} — {took:.1f} s"
              + ("; " + "; ".join(problems) if problems else ""), flush=True)
    return results


def listing():
    print("cases:")
    for name, case in CASES.items():
        print(f"  {name}: {len(case['steps'])} steps, {len(case['scenario'].get('replies', []))} "
              f"replies, {len(case['expect']['types'])} events, {case['expect']['posts']} POSTs")
    print("mutants:")
    for name, (file, _, _, cases) in SWIFT_MUTANTS.items():
        print(f"  {name}: {file}; must FAIL {', '.join(cases)}")
    print("controls:")
    for name, (case, how, fails) in CONTROLS.items():
        print(f"  {name}: {case}, {what(how)}; must {'FAIL' if fails else 'pass'}")


def built(args):
    if args.swift:
        return Path(args.swift).resolve()
    swift, why = build_swift()
    print(f"B1 {'ok' if swift else 'FAIL'} — the Swift helper: {why}", flush=True)
    return swift


def plain(args, names):
    swift = built(args)
    if swift is None:
        print("0/1", flush=True)
        return 1
    ctx = Context()
    try:
        results = drive(names, swift, ctx, held=not args.record)
    finally:
        ctx.stop()
    checks = {name: not problems for name, (problems, _) in results.items()}
    if not args.record:
        ok, detail = recordings_row()
        checks["recordings"] = ok
        print(f"recordings {'ok' if ok else 'FAIL'} — {detail}", flush=True)
    passed = sum(1 for ok in checks.values() if ok)
    print(f"{passed}/{len(checks)}", flush=True)
    if args.record:
        if passed != len(checks):
            print("record: refused — a case of this run failed, so nothing was written",
                  flush=True)
            return 2
        record(names, {name: seen for name, (_, seen) in results.items()})
    return 0 if passed == len(checks) else 1


def verdict(name, named, checks):
    survived = [check for check in named if checks.get(check, True)]
    if survived:
        print(f"mutant {name}: SURVIVED — {', '.join(survived)} passed", flush=True)
        return 0
    print(f"mutant {name}: caught — {', '.join(named)} failed", flush=True)
    return 1


def mutant(args, name):
    """A SWIFT_MUTANTS edit built on the persistent mutant tree, then the named cases."""
    file, anchor, replacement, named = SWIFT_MUTANTS[name]
    swift, why = agent_helper_build.mutant(name, [(file, anchor, replacement)],
                                           WORK / "mutant" / name / "framejob-agent")
    print(f"B1 {'ok' if swift else 'FAIL'} — the mutated Swift helper: {why}", flush=True)
    if swift is None:
        print(f"mutant {name}: the control could not be performed — the helper did not build",
              flush=True)
        return 2
    ctx = Context()
    try:
        results = drive(ordered(named), swift, ctx)
    finally:
        ctx.stop()
    return verdict(name, named, {case: not results[case][0] for case in named})


def control(args, name):
    """One case on the tree's helper, its run or its recording altered: it FAILs or passes as
    the control says."""
    case, how, fails = CONTROLS[name]
    if read_recording(case) is None:
        print(f"control {name}: could not be performed — {case} has no recording", flush=True)
        return 2
    swift = built(args)
    if swift is None:
        print(f"control {name}: could not be performed — the helper did not build", flush=True)
        return 2
    ctx = Context()
    try:
        try:
            results = drive(ordered([case]), swift, ctx, alter=(case, how))
        except (KeyError, IndexError, TypeError, AttributeError, ValueError) as error:
            print(f"control {name}: could not be performed — {error!r}", flush=True)
            return 2
    finally:
        ctx.stop()
    problems = results[case][0]
    held = bool(problems) == fails
    said = (f"{case} FAILed: {problems[0]}" if problems else f"{case} passed")
    print(f"control {name}: {'held' if held else 'NOT held'} — {what(how)}; {said}",
          flush=True)
    return 0 if held else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cases", help="a comma-separated subset of the cases")
    parser.add_argument("--swift", help="a built Swift helper, in place of B1")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--mutant", choices=sorted(SWIFT_MUTANTS))
    parser.add_argument("--control", choices=sorted(CONTROLS))
    parser.add_argument("--record", action="store_true",
                        help="rewrite the recordings from this run (spec §11 SA-13)")
    args = parser.parse_args()
    if args.list:
        listing()
        return 0
    WORK.mkdir(parents=True, exist_ok=True)
    unknown = [n for n in (args.cases or "").split(",") if n and n not in CASES]
    if unknown:
        parser.error(f"no case {', '.join(unknown)}")
    if args.record and (args.mutant or args.control):
        print("record: refused — a recording is written only from a plain run, never with "
              "--mutant or --control", flush=True)
        return 2
    if args.mutant:
        return mutant(args, args.mutant)
    if args.control:
        return control(args, args.control)
    return plain(args, ordered(args.cases.split(",") if args.cases else list(CASES)))


if __name__ == "__main__":
    sys.exit(main())
