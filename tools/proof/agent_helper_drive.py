#!/usr/bin/env python3
"""Road map "swift-helper" SA2 — the two helpers, driven: the Bun helper the app ships today and
the Swift helper that replaces it, each run as the app runs it, over the same scripted
conversations on the stand-in API, their events and their requests compared (spec §11 SA-4,
SA-5, SA-6; `designs/swift-helper.md` §9 SA2 and its record in §13).

    python3 tools/proof/agent_helper_drive.py                       # build both, every case (make test)
    python3 tools/proof/agent_helper_drive.py --cases text,tools    # these cases (and what they need)
    python3 tools/proof/agent_helper_drive.py --bun PATH --swift PATH   # helpers already built
    python3 tools/proof/agent_helper_drive.py --list                # the cases, the rows, the mutants
    python3 tools/proof/agent_helper_drive.py --drop ROW            # without one allowed row: exactly
                                                                    # its cases FAIL (exit 1, caught)
    python3 tools/proof/agent_helper_drive.py --rows-needed         # --drop for every row over one run
    python3 tools/proof/agent_helper_drive.py --mutant NAME         # a SWIFT_MUTANTS edit, built on
                                                                    # the persistent mutant tree
    python3 tools/proof/agent_helper_drive.py --mutant drive-same-helper   # both sides Swift: every
                                                                    # row allows nothing

The helpers. B0 builds the Bun helper with `agent/build.sh helper` into
`tools/proof/work/agent_helper_drive/bun-target/` (spend_proof.py's call; no bun is build.sh's own
error and a FAIL, never a skip). B1 is the release helper the app bundles, built by
`tools/agent/build_helper.sh` on the app build's scratch path, `build/agent-swift`
(`agent_helper_build.release`, road map "swift-helper" SA3, spec §11 SA-8): stripped and signed
into `work/agent_helper_drive/swift/`, seconds while its stamp matches. Each case starts each
helper once with
exactly HOME, TMPDIR (scratch folders) and PATH=/usr/bin:/bin, as `AssistantSession` does, writes
the app's lines (sorted keys, compact, `writeResult`'s spliced answers) and reads stdout line by
line. One stand-in (`anthropic_fake.py`) serves the run; each helper's run of a case posts the
case's scenario first, which resets its log. The price feed is this drive's own loopback server,
holding its answer until the drive has read that helper's `context_usage`, so the refresh's
`prices` and the Models lookup's `context_usage` cannot race. Every wait is bounded; a hang, a
crash, an exit other than 0 after stdin closes, or a Swift stderr line without `framejob-agent: `
FAILs the case and the drive goes on. Only children this drive started are signalled.

What a case compares, after the allowed rows below have rewritten what they explain:
- not vacuous: the Swift helper's event types are the case's list, its POSTs and all its requests
  the case's counts, and both runs' stand-in failures the case's list, so two helpers failing
  alike cannot pass;
- the two event streams line for line, as parsed JSON with each object's key order (numbers by
  value, so `1e-07` is `1e-7`, SA-6);
- the requests: the same count, method and path, the headers as a set (`anthropic-beta` as a
  list), every body as parsed JSON with its key order at every level;
- the price cache files the case names, once parsed and as bytes.
A refreshed table's `as_of` (in `prices` and in `cost`) and the cache file's `fetched_at` are clock
readings: each must be an ISO 8601 instant inside this run, and is then compared as `<clock>`.
That is a comparison rule, not a row.

The allowed differences are `ALLOWED`, each row naming its decision and rewriting exactly what it
explains and nothing wider; any other difference fails. Each row declares the cases it serves,
and a run of every case fails a row that explained nothing in one of them ("allows nothing") or
anything in another. `--drop ROW` must FAIL exactly the row's cases, and `--rows-needed` shows that
for every row from one run. No key-order row: neither the bodies nor the events differ in key
order (SA-5's pinned order holds), so key order is compared strictly. SA-4 (b) has no row either:
the 0.128.0 runner already skips the summary after a final reply that ends in tool calls, and both
helpers send nothing and say "no summary came back" (case `cut-reply-tool-call`).

Mutants (`SWIFT_MUTANTS`): an edit of the Swift helper's sources, built by
`agent_helper_build.mutant` on the persistent mutant tree `build/agent-swift-mutant/` (spec §11
SA-8), never in the tree's own `agent/`; then the cases it names run. A mutant is caught only when
every case it names FAILs: `mutant <name>: caught — …`, exit 1; one that passed any SURVIVED,
exit 0; one that did not build could not perform its control, exit 2. The first five make a difference outside
the list; `system-loses-guide`, `not-run-reworded` and `empty-summary-swapped` show that the
`system-breakpoint`, `unrun-calls-answered` and `empty-summary` rows are no wider than their
decisions. `--mutant drive-same-helper` runs the Swift helper on both sides and must fail every
row as "allows nothing".

No network: the API is the stand-in, the feed is on 127.0.0.1, the only keys are the dummies
`proof-key` and `wrong-key`, and every child has ANTHROPIC_API_KEY and RC_ASSEMBLYAI_KEY popped.
Nothing is paid. Exit 0 PASS, 1 FAIL.
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
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(ROOT / "tools" / "agent"))
import agent_helper_build  # noqa: E402
import assistant_helper_proof as ahp  # noqa: E402
import bounded  # noqa: E402

WORK = HERE / "work" / "agent_helper_drive"
AGENT = ROOT / "agent"
SWIFT_HELPER = WORK / "swift" / "framejob-agent"
BUN_TARGET = WORK / "bun-target"
BUN_HELPER = BUN_TARGET / "Frame Job.app" / "Contents" / "Helpers" / "framejob-agent"
REDUCE_CASES = AGENT / "prices" / "reduce_cases.json"
MODEL = "claude-opus-5-5"
KEY = "proof-key"
WALL_BUILD, WALL_EVENT, WALL_EXIT = 900, 30, 10
STDERR_PREFIX = "framejob-agent: "
SIDES = ("bun", "swift")
SWITCH = "drive-same-helper"
MUTANT = None

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
    # Each helper started on the cache file the OTHER wrote in `prices-fetched`: it reads it,
    # reports it before `ready` and prices a turn from it, with no refresh.
    "prices-cached": {
        "requires": "prices-fetched",
        "scenario": {"replies": [reply([text("Priced.")], "end_turn")]},
        "steps": [("configure", {"price_cache": CACHE, "price_feed": FEED}),
                  ("send", "What does this cost?"), ("turn",), ("close",)],
        "expect": expect(HELLO + TURN, 1, 2, feed_gets=0),
    },
}


# ---------------------------------------------------------------------------
# The helpers' builds.


def child_env(extra=None):
    """`bounded.child_env` (RC_ASSEMBLYAI_KEY popped) with ANTHROPIC_API_KEY popped too."""
    env = bounded.child_env(extra)
    env.pop("ANTHROPIC_API_KEY", None)
    return env


def build_bun():
    """(helper path, detail) or (None, why): `agent/build.sh helper` into a scratch target."""
    shutil.rmtree(BUN_TARGET, ignore_errors=True)
    BUN_TARGET.mkdir(parents=True)
    built = bounded.run(["/bin/sh", str(AGENT / "build.sh"), "helper"], WALL_BUILD,
                        env=child_env({"TARGET_BUILD_DIR": str(BUN_TARGET),
                                       "CONTENTS_FOLDER_PATH": "Frame Job.app/Contents"}))
    if built["expired"] or built["rc"] != 0 or not BUN_HELPER.is_file():
        tail = [line for line in (built["stdout"] + built["stderr"]).splitlines() if line.strip()]
        return None, f"build.sh helper exit {built['rc']} (expired {built['expired']}): {tail[-3:]}"
    return BUN_HELPER, f"agent/build.sh helper, {built['seconds']} s"


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
        self.runs = {}  # (case, side) -> run

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


def run_case(name, side, path, ctx):
    case = CASES[name]
    folder = WORK / "runs" / name / side
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    run = {"problems": [], "files": {}, "exit": None}
    if "requires" in case:
        other = "swift" if side == "bun" else "bun"
        made = ctx.runs.get((case["requires"], other), {}).get("files", {}).get("prices.json")
        if made is None:
            run["problems"].append(f"{case['requires']} left no cache file from the {other} helper")
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
    ctx.runs[(name, side)] = run
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


def difference(a, b, path="$"):
    """Where `a` (bun) and `b` (swift) first differ, and how, or None."""
    if same(a, b):
        return None
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            return (f"{path}: keys only in bun {[k for k in a if k not in b]}, "
                    f"only in swift {[k for k in b if k not in a]}")
        for k in a:
            found = difference(a[k], b[k], f"{path}.{k}")
            if found:
                return found
        return f"{path}: key order {list(a)} / {list(b)}"
    if isinstance(a, list) and isinstance(b, list):
        for at, (x, y) in enumerate(zip(a, b)):
            found = difference(x, y, f"{path}[{at}]")
            if found:
                return found
        return f"{path}: length {len(a)} / {len(b)}"
    return f"{path}: {short(a)} / {short(b)}"


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
    """The comparison rule for clock readings (the module doc): `as_of` of a fetched or cached
    source, and a cache file's `fetched_at`, checked and then replaced by `<clock>`."""
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
        run["tables"][name] = table
        run["layouts"][name] = data.replace(stamp.encode(), b"<clock>")
    return problems


class Pair:
    """Copies of one case's two runs, which the allowed rows rewrite in place."""

    def __init__(self, name, bun, swift):
        self.name, self.case = name, CASES[name]
        self.bun, self.swift = copy.deepcopy(bun), copy.deepcopy(swift)
        self.replies = self.case["scenario"].get("replies", [])


def compare(name, bun, swift, rows, ctx):
    """(problems, {row id: the differences it explained}) for one case."""
    pair = Pair(name, bun, swift)
    problems = []
    for side in SIDES:
        run = getattr(pair, side)
        problems += [f"{side}: {p}" for p in run["problems"]]
        problems += [f"{side}: {p}" for p in unclock(run, ctx)]
        if run["exit"] != 0:
            problems.append(f"{side}: exit {run['exit']} after stdin closed")
    for line in pair.swift["stderr"]:
        if not line.startswith(STDERR_PREFIX):
            problems.append(f"swift: a stderr line without {STDERR_PREFIX!r}: {short(line)}")
            break
    wanted = pair.case["expect"]
    types = [e.get("type") for e in swift["events"]]
    if types != wanted["types"]:
        problems.append(f"swift's event types {types} are not the case's {wanted['types']}")
    posts = len([r for r in swift["requests"] if r.get("method") == "POST"])
    if (posts, len(swift["requests"])) != (wanted["posts"], wanted["requests"]):
        problems.append(f"swift sent {posts} POSTs of {len(swift['requests'])} requests, the "
                        f"case expects {wanted['posts']} of {wanted['requests']}")
    for side in SIDES:
        run = getattr(pair, side)
        if run["failures"] != wanted["failures"]:
            problems.append(f"{side}: the stand-in's failures {run['failures']}")
        if wanted["feed_gets"] is not None and run["feed_gets"] != wanted["feed_gets"]:
            problems.append(f"{side}: {run['feed_gets']} price feed GETs, the case expects "
                            f"{wanted['feed_gets']}")
    used = {}
    for row in rows:
        explained = row["apply"](pair)
        if explained:
            used[row["id"]] = explained
    problems += events_differ(pair.bun["events"], pair.swift["events"])
    problems += requests_differ(pair.bun["requests"], pair.swift["requests"])
    problems += files_differ(pair)
    return problems, used


def events_differ(bun, swift):
    for at, (b, s) in enumerate(zip(bun, swift)):
        if not same(b, s):
            return [f"event {at}: {difference(b, s, '$')}; bun {short(b)}, swift {short(s)}"]
    if len(bun) != len(swift):
        side, extra = ("bun", bun[len(swift)]) if len(bun) > len(swift) else ("swift", swift[len(bun)])
        return [f"events: bun {len(bun)}, swift {len(swift)}; {side}'s next {short(extra)}"]
    return []


def headers_of(request):
    headers = dict(request.get("headers") or {})
    if "anthropic-beta" in headers:
        headers["anthropic-beta"] = [b.strip() for b in headers["anthropic-beta"].split(",")]
    return headers


def requests_differ(bun, swift):
    if len(bun) != len(swift):
        return [f"requests: bun {[r.get('method') + ' ' + r.get('path', '') for r in bun]}, "
                f"swift {[r.get('method') + ' ' + r.get('path', '') for r in swift]}"]
    for at, (b, s) in enumerate(zip(bun, swift)):
        if (b.get("method"), b.get("path")) != (s.get("method"), s.get("path")):
            return [f"request {at}: bun {b.get('method')} {b.get('path')}, "
                    f"swift {s.get('method')} {s.get('path')}"]
        hb, hs = headers_of(b), headers_of(s)
        if hb != hs:
            diff = [f"{n}: {short(hb.get(n), 60)} / {short(hs.get(n), 60)}"
                    for n in sorted(set(hb) | set(hs)) if hb.get(n) != hs.get(n)]
            return [f"request {at} {b.get('method')} headers: {'; '.join(diff)}"]
        found = difference(b.get("body"), s.get("body"), "body")
        if found:
            return [f"request {at} {b.get('method')} {b.get('path')}: {found}"]
    return []


def files_differ(pair):
    out = []
    for name in pair.case.get("files", []):
        b, s = pair.bun["layouts"].get(name), pair.swift["layouts"].get(name)
        if b is None or s is None:
            out.append(f"{name}: a table from bun {b is not None}, from swift {s is not None}")
            continue
        found = difference(pair.bun["tables"][name], pair.swift["tables"][name], name)
        if found:
            out.append(f"{name}: {found}")
        elif b != s:
            out.append(f"{name}: the same table in different bytes ({len(b)} / {len(s)})")
    return out


# ---------------------------------------------------------------------------
# The allowed differences. Each row rewrites, in the Pair's copies, exactly the difference its
# decision names, and answers how many it rewrote; whatever is left is compared strictly.

CLIENT_HEADERS = ("user-agent", "x-stainless-arch", "x-stainless-async", "x-stainless-helper",
                  "x-stainless-lang", "x-stainless-os", "x-stainless-package-version",
                  "x-stainless-raw-response", "x-stainless-read-timeout",
                  "x-stainless-retry-count", "x-stainless-runtime", "x-stainless-runtime-version",
                  "x-stainless-timeout", "accept-encoding", "accept-language", "connection",
                  "content-length", "host")
PARSE_PREFIX = "Bad message from the app: "
NOT_OBJECT = PARSE_PREFIX + "expected a JSON object"
NO_KEY = PARSE_PREFIX + "configure needs a string api_key"
EMPTY_SUMMARY = "the summary came back empty"
SDK_CUT = "stream ended without producing a Message with role=assistant"
EVENT_STATUS = {"overloaded_error": 529}


def request_pairs(pair):
    return list(zip(pair.bun["requests"], pair.swift["requests"]))


def bodies(pair):
    return [(b["body"], s["body"]) for b, s in request_pairs(pair)
            if b.get("method") == s.get("method") == "POST"
            and isinstance(b.get("body"), dict) and isinstance(s.get("body"), dict)]


def row_system_breakpoint(pair):
    explained = 0
    for b, s in bodies(pair):
        system = b.get("system")
        block = [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}]
        if isinstance(system, str) and same(s.get("system"), block):
            s["system"] = system
            explained += 1
    return explained


def row_credential(pair):
    explained = 0
    for b, s in request_pairs(pair):
        hb, hs = b["headers"], s["headers"]
        key = hb.get("x-api-key")
        if (key in ("proof-key", "wrong-key") and "authorization" not in hb
                and hs.get("authorization") == f"Bearer {key}" and "x-api-key" not in hs):
            del hs["authorization"]
            hs["x-api-key"] = key
            explained += 1
    return explained


def row_version(pair):
    explained = 0
    for b, s in request_pairs(pair):
        if (b["headers"].get("anthropic-version") == "2023-06-01"
                and s["headers"].get("anthropic-version") == "2026-10-21"):
            s["headers"]["anthropic-version"] = "2023-06-01"
            explained += 1
    return explained


def row_beta_query(pair):
    explained = 0
    for b, s in request_pairs(pair):
        if (b.get("method") == s.get("method") == "POST"
                and b.get("path") == "/v1/messages?beta=true" and s.get("path") == "/v1/messages"):
            s["path"] = b["path"]
            explained += 1
    return explained


def row_client_headers(pair):
    explained = 0
    for b, s in request_pairs(pair):
        hb, hs = b["headers"], s["headers"]
        if any(hb.get(name) != hs.get(name) for name in CLIENT_HEADERS):
            explained += 1
        for name in CLIENT_HEADERS:
            hb.pop(name, None)
            hs.pop(name, None)
    return explained


def scripted_stop(pair, uses):
    """The stop reason of the scripted reply whose tool_use ids are `uses`', or None."""
    ids = [u.get("id") for u in uses]
    for given in pair.replies:
        if [b.get("id") for b in given.get("content", []) if b.get("type") == "tool_use"] == ids:
            return given.get("stop_reason")
    return None


def row_unrun_calls(pair):
    """SA-4 (a): after a final reply that ends in tool calls, Swift's next user message starts
    with one "Not run: …" error result per call, then what Bun sent as that message."""
    explained = 0
    for b, s in bodies(pair):
        bm, sm = b.get("messages"), s.get("messages")
        if not (isinstance(bm, list) and isinstance(sm, list) and len(bm) == len(sm)):
            continue
        for at in range(1, len(bm)):
            before, mine, theirs = bm[at - 1], bm[at], sm[at]
            uses = [c for c in before.get("content", []) if isinstance(c, dict)
                    and c.get("type") == "tool_use"] if before.get("role") == "assistant" else []
            stop = scripted_stop(pair, uses) if uses else None
            if (stop in (None, "tool_use") or mine.get("role") != "user"
                    or not isinstance(mine.get("content"), list)):
                continue
            if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in mine["content"]):
                continue
            answers = [{"type": "tool_result", "tool_use_id": u["id"],
                        "content": f"Not run: the reply stopped with {stop} before this call "
                                   "could run.", "is_error": True} for u in uses]
            got = theirs.get("content")
            if (theirs.get("role") == "user" and isinstance(got, list)
                    and same(got[:len(answers)], answers)
                    and same(got[len(answers):], mine.get("content"))):
                theirs["content"] = copy.deepcopy(mine["content"])
                explained += 1
    return explained


def row_summary_needs_stop(pair):
    """SA-4, success needs both: a summary that holds a compaction block but stopped with another
    reason swaps Bun's history for that block, and leaves Swift's as it was."""
    wrong = [g for g in pair.replies if g.get("stop_reason") != "compaction"
             and any(c.get("type") == "compaction" and isinstance(c.get("content"), str)
                     and c["content"] for c in g.get("content", []))]
    if not wrong:
        return 0
    explained, summarised = 0, None
    for b, s in bodies(pair):
        if "compaction" in b and "compaction" in s:
            summarised = s.get("messages")
            continue
        bm, sm = b.get("messages"), s.get("messages")
        if summarised is None or not (isinstance(bm, list) and isinstance(sm, list) and bm):
            continue
        head = bm[0]
        blocks = [{k: v for k, v in c.items() if k != "encrypted_content"}
                  for c in head.get("content", []) if isinstance(c, dict)]
        if (head.get("role") == "assistant"
                and any(same(blocks, g["content"]) for g in wrong)
                and same(sm[:len(summarised)], summarised)
                and same(sm[len(summarised):], bm[1:])):
            s["messages"] = copy.deepcopy(bm)
            explained += 1
    return explained


def row_empty_summary(pair):
    """SA-4 (c): a `compaction` stop whose block holds null or "" — Bun's `compacted` and its
    `context_usage` against Swift's `compaction_failed` "the summary came back empty"."""
    if not any(g.get("stop_reason") == "compaction"
               and any(c.get("type") == "compaction" and not c.get("content")
                       for c in g.get("content", [])) for g in pair.replies):
        return 0
    explained = 0
    bun, swift = pair.bun["events"], pair.swift["events"]
    for at in range(min(len(bun) - 1, len(swift))):
        failed = swift[at]
        if not same(failed, {"type": "compaction_failed", "reason": EMPTY_SUMMARY}):
            continue
        done, usage = bun[at], bun[at + 1]
        if (done.get("type") == "compacted" and list(done) == ["type", "before", "after"]
                and same(usage, {"type": "context_usage", "used": done["after"],
                                 "limit": usage.get("limit")})):
            swift[at:at + 1] = [copy.deepcopy(done), copy.deepcopy(usage)]
            explained += 1
    return explained


def row_configure_validated(pair):
    """SA-6: `configure` without `api_key` — Swift's one error against Bun's `prices`, `ready`
    and `context_usage` with no limit (its lookup fails with no key and sends nothing)."""
    bun, swift = pair.bun["events"], pair.swift["events"]
    if len(swift) < 1 or len(bun) < 3 or not same(swift[0], {"type": "error", "message": NO_KEY}):
        return 0
    if [e.get("type") for e in bun[:3]] != HELLO or not same(
            bun[2], {"type": "context_usage", "used": 0, "limit": None}):
        return 0
    swift[0:1] = copy.deepcopy(bun[:3])
    return 1


def row_non_object(pair):
    """SA-6: a line that is JSON but not an object — Swift's error against Bun's silence."""
    bun, swift = pair.bun["events"], pair.swift["events"]
    explained = 0
    at = 0
    while at < len(swift):
        if same(swift[at], {"type": "error", "message": NOT_OBJECT}) and not (
                at < len(bun) and same(bun[at], swift[at])):
            del swift[at]
            explained += 1
            continue
        at += 1
    return explained


def row_reset(pair):
    """SA-6: `reset` — Bun's `context_usage` of 0 straight after the turn it ends, against
    Swift's silence; and every later `context_usage` until the next response, Bun's `used` 0
    against the context Swift kept."""
    bun, swift = pair.bun["events"], pair.swift["events"]
    explained = 0
    for at in range(1, len(bun)):
        event = bun[at]
        if not (bun[at - 1].get("type") == "turn_finished" and event.get("type") == "context_usage"
                and event.get("used") == 0):
            continue
        if at < len(swift) and same(swift[at], event):
            continue
        kept = next((e.get("used") for e in reversed(swift[:at])
                     if e.get("type") == "context_usage"), None)
        del bun[at]
        explained += 1
        for later in range(at, min(len(bun), len(swift))):
            if bun[later].get("type") == "message_done":
                break
            if (bun[later].get("type") == swift[later].get("type") == "context_usage"
                    and bun[later].get("used") == 0 and swift[later].get("used") == kept):
                swift[later]["used"] = 0
                explained += 1
        break
    return explained


def row_parser_text(pair):
    """SA-6: a line that is not JSON — both say "Bad message from the app: ", Bun with its JSON
    parser's message and Swift with Foundation's."""
    explained = 0
    for b, s in zip(pair.bun["events"], pair.swift["events"]):
        if (b.get("type") == s.get("type") == "error"
                and str(b.get("message", "")).startswith(PARSE_PREFIX + "JSON Parse error")
                and str(s.get("message", "")).startswith(PARSE_PREFIX)
                and s.get("message") not in (NOT_OBJECT, NO_KEY) and not same(b, s)):
            s["message"] = b["message"]
            explained += 1
    return explained


def row_error_no_status(pair):
    """SA-6: an API error with no status (a failed connection) — Bun's `API error : <m>`
    against Swift's `API error: <m>`, the same message."""
    explained = 0
    for b, s in zip(pair.bun["events"], pair.swift["events"]):
        mine, theirs = str(b.get("message", "")), str(s.get("message", ""))
        if (b.get("type") == s.get("type") == "error" and mine.startswith("API error : ")
                and theirs == "API error: " + mine[len("API error : "):]):
            s["message"] = mine
            explained += 1
    return explained


def row_error_stream_cut(pair):
    """SA-6: a stream cut short — Bun's SDK sentence alone against Swift's `API error: <m>`."""
    if not any(g.get("cut") == "drop" for g in pair.replies):
        return 0
    explained = 0
    for b, s in zip(pair.bun["events"], pair.swift["events"]):
        if (b.get("type") == s.get("type") == "error" and b.get("message") == SDK_CUT
                and str(s.get("message", "")).startswith("API error: ")):
            s["message"] = b["message"]
            explained += 1
    return explained


def row_error_event_status(pair):
    """SA-6: an `error` event mid-stream — Bun's `API error : <m>` against Swift's
    `API error <its type's status>: <m>`."""
    statuses = {g["error"]["message"]: EVENT_STATUS.get(g["error"].get("type"))
                for g in pair.replies if g.get("cut") == "error" and g.get("error")}
    explained = 0
    for b, s in zip(pair.bun["events"], pair.swift["events"]):
        mine = str(b.get("message", ""))
        said = mine[len("API error : "):]
        if (b.get("type") == s.get("type") == "error" and mine.startswith("API error : ")
                and statuses.get(said) is not None
                and s.get("message") == f"API error {statuses[said]}: {said}"):
            s["message"] = mine
            explained += 1
    return explained


def row_cache_layout(pair):
    """SA-6: the price cache — the same table, compact from Swift and indented from Bun."""
    explained = 0
    for name in pair.case.get("files", []):
        b, s = pair.bun["tables"].get(name), pair.swift["tables"].get(name)
        if b is not None and s is not None and same(b, s) and (
                pair.bun["layouts"][name] != pair.swift["layouts"][name]):
            pair.swift["layouts"][name] = pair.bun["layouts"][name]
            explained += 1
    return explained


def with_posts(name):
    return CASES[name]["expect"]["posts"] > 0


def with_requests(name):
    return CASES[name]["expect"]["requests"] > 0


# Row order matters only where a row adds or removes events: those come before the rows that
# compare events at one index.
ALLOWED = [
    {"id": "system-breakpoint", "decision": "SA-5", "apply": row_system_breakpoint,
     "cases": with_posts,
     "lets": "Bun's `system` string against Swift's list of one text block of the same string "
             "carrying `cache_control {type: ephemeral}`"},
    {"id": "credential-header", "decision": "SA-5", "apply": row_credential,
     "cases": with_requests,
     "lets": "`x-api-key: <dummy>` against `authorization: Bearer <the same dummy>`"},
    {"id": "api-version", "decision": "SA-5", "apply": row_version, "cases": with_requests,
     "lets": "`anthropic-version` exactly 2023-06-01 against exactly 2026-10-21"},
    {"id": "beta-query", "decision": "SA-5", "apply": row_beta_query, "cases": with_posts,
     "lets": "a POST to /v1/messages?beta=true against one to /v1/messages"},
    {"id": "client-headers", "decision": "SA-1", "apply": row_client_headers,
     "cases": with_requests,
     "lets": "the headers that name the HTTP client and the SDK, by name: "
             + ", ".join(CLIENT_HEADERS)},
    {"id": "unrun-calls-answered", "decision": "SA-4 (a)", "apply": row_unrun_calls,
     "cases": ("cut-reply-tool-call",),
     "lets": "after a final reply that ends in tool calls, Swift's next user message beginning "
             "with one error result per call, \"Not run: the reply stopped with <its stop "
             "reason> before this call could run.\", then exactly what Bun sent"},
    {"id": "summary-needs-compaction-stop", "decision": "SA-4", "apply": row_summary_needs_stop,
     "cases": ("compaction-wrong-stop-block",),
     "lets": "a summary holding a non-empty compaction block that stopped with another reason: "
             "Bun's later requests starting from that block, Swift's from the conversation the "
             "summary request sent, the rest the same"},
    {"id": "empty-summary", "decision": "SA-4 (c)", "apply": row_empty_summary,
     "cases": ("compaction-empty",),
     "lets": "a `compaction` stop whose block is null or empty: Bun's `compacted` and the "
             "`context_usage` of its `after`, against Swift's `compaction_failed` \"the summary "
             "came back empty\""},
    {"id": "configure-validated", "decision": "SA-6", "apply": row_configure_validated,
     "cases": ("configure-no-key",),
     "lets": "`configure` with no `api_key`: Swift's error \"" + NO_KEY + "\" against Bun's "
             "`prices`, `ready` and `context_usage` with no limit"},
    {"id": "non-object-line", "decision": "SA-6", "apply": row_non_object,
     "cases": ("bad-lines",),
     "lets": "a line that is JSON but not an object: Swift's error \"" + NOT_OBJECT + "\" "
             "against Bun's silence"},
    {"id": "reset-ignored", "decision": "SA-6", "apply": row_reset, "cases": ("bad-lines",),
     "lets": "`reset`: Bun's `context_usage` of 0 against Swift's silence, and later "
             "`context_usage` until the next response, Bun's `used` 0 against the context Swift "
             "kept"},
    {"id": "parser-text", "decision": "SA-6", "apply": row_parser_text, "cases": ("bad-lines",),
     "lets": "a line that is not JSON: \"" + PARSE_PREFIX + "\" and Bun's JSON Parse error "
             "against Swift's parser's own words"},
    {"id": "error-no-status", "decision": "SA-6", "apply": row_error_no_status,
     "cases": ("no-connection",),
     "lets": "an API error with no status: `API error : <m>` against `API error: <m>`"},
    {"id": "error-stream-cut", "decision": "SA-6", "apply": row_error_stream_cut,
     "cases": ("stream-drop",),
     "lets": "a stream cut short: Bun's \"" + SDK_CUT + "\" against Swift's `API error: <m>`"},
    {"id": "error-event-status", "decision": "SA-6", "apply": row_error_event_status,
     "cases": ("stream-error",),
     "lets": "an `error` event mid-stream: `API error : <m>` against `API error <its type's "
             "status>: <m>` (529 for overloaded_error)"},
    {"id": "cache-file-layout", "decision": "SA-6", "apply": row_cache_layout,
     "cases": ("prices-fetched",),
     "lets": "the price cache file: the same table once parsed, indented by Bun and compact from "
             "Swift"},
]


def declared(row, names):
    serves = row["cases"]
    return {n for n in names if (serves(n) if callable(serves) else n in serves)}


# ---------------------------------------------------------------------------
# Mutants: an edit to the Swift helper's sources, and the cases that must FAIL with it.

KIT = "agent/Sources/FrameJobAgentKit/"
SWIFT_MUTANTS = {
    # The tool results in reverse order: a body difference no row explains.
    "tool-results-reversed": (KIT + "Turn.swift", "        return answers.compactMap { $0 }\n",
                              "        return Array(answers.compactMap { $0 }.reversed())\n",
                              ["tools"]),
    # Every tool sent up front (`core` still read, as the suite's warnings are errors).
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
    # The summary request with a clearing edit, which the API refuses beside a compaction.
    "summary-keeps-clearing": (KIT + "Request.swift",
                               "        o[\"compaction\"] = [\"type\": \"summarize\", "
                               "\"instructions\": .string(instructions)]\n",
                               "        o[\"context_management\"] = [\"edits\": "
                               "[[\"type\": .string(Self.clearEditType)]]]\n"
                               "        o[\"compaction\"] = [\"type\": \"summarize\", "
                               "\"instructions\": .string(instructions)]\n",
                               ["compaction"]),
    # The system block without the search guide: `system-breakpoint` must not swallow it.
    "system-loses-guide": (KIT + "Request.swift",
                           "            \"text\": .string(\"\\(configure.system)\\n\\n\\(configure.searchGuide)\"),\n",
                           "            \"text\": .string(configure.system),\n",
                           ["text", "tools"]),
    # Another sentence for an unrun call: `unrun-calls-answered` must not swallow it.
    "not-run-reworded": (KIT + "ToolResults.swift",
                         "         \"content\": .string(\"Not run: the reply stopped with \\(stopReason) "
                         "before this call could run.\"),\n",
                         "         \"content\": .string(\"Not run: stopped with \\(stopReason).\"),\n",
                         ["cut-reply-tool-call"]),
    # An empty summary swapped in, as SA-4 (c) says the runner would: `empty-summary` lets the
    # events through and must not let the swap through.
    "empty-summary-swapped": (KIT + "Compaction.swift",
                              "        guard Self.holdsSummary(reply.message) else {\n",
                              "        guard Self.holdsSummary(reply.message) || true else {\n",
                              ["compaction-empty"]),
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


def drive(names, bun, swift, rows, ctx):
    """Runs and compares each case, printing its line; answers {case: (problems, rows used)}."""
    results = {}
    for name in names:
        started = time.monotonic()
        runs = {side: run_case(name, side, path, ctx)
                for side, path in (("bun", bun), ("swift", swift))}
        problems, used = compare(name, runs["bun"], runs["swift"], rows, ctx)
        results[name] = (problems, used)
        took = time.monotonic() - started
        rows_said = ", ".join(f"{k} {v}" for k, v in used.items()) or "none"
        print(f"{name} {'ok' if not problems else 'FAIL'} — {took:.1f} s; rows: {rows_said}"
              + ("; " + "; ".join(problems) if problems else ""), flush=True)
    return results


def recompare(names, rows, ctx):
    return {name: compare(name, ctx.runs[(name, "bun")], ctx.runs[(name, "swift")], rows, ctx)
            for name in names}


def row_checks(names, results, rows):
    """Each row against the cases it declares: it must have explained something in each of
    them and nothing elsewhere. Answers {"row:<id>": (ok, detail)}."""
    out = {}
    for row in rows:
        want = declared(row, names)
        got = {name for name in names if results[name][1].get(row["id"])}
        total = sum(results[name][1].get(row["id"], 0) for name in names)
        if not want and not got:
            continue  # none of its cases ran
        if want and not got:
            out["row:" + row["id"]] = (False, f"allows nothing: remove it (declared for "
                                              f"{len(want)} cases)")
        elif got != want:
            out["row:" + row["id"]] = (False, f"explained differences in {sorted(got)}, "
                                              f"declared for {sorted(want)}")
        else:
            where = ", ".join(sorted(got)) if len(got) <= 3 else f"{len(got)} cases"
            out["row:" + row["id"]] = (True, f"{row['decision']}: {total} explained, in {where}")
    return out


def listing():
    print("cases:")
    for name, case in CASES.items():
        print(f"  {name}: {len(case['steps'])} steps, {len(case['scenario'].get('replies', []))} "
              f"replies, swift {len(case['expect']['types'])} events, "
              f"{case['expect']['posts']} POSTs")
    print("allowed rows:")
    for row in ALLOWED:
        print(f"  {row['id']} ({row['decision']}): {row['lets']}")
    print("mutants:")
    for name, (file, _, _, cases) in SWIFT_MUTANTS.items():
        print(f"  {name}: {file}; must FAIL {', '.join(cases)}")
    print(f"  {SWITCH}: both sides the Swift helper; every row must allow nothing")


def build_both(args):
    bun = Path(args.bun).resolve() if args.bun else None
    swift = Path(args.swift).resolve() if args.swift else None
    if bun is None:
        bun, why = build_bun()
        print(f"B0 {'ok' if bun else 'FAIL'} — the Bun helper: {why}", flush=True)
    if swift is None:
        swift, why = build_swift()
        print(f"B1 {'ok' if swift else 'FAIL'} — the Swift helper: {why}", flush=True)
    return bun, swift


def plain(args, names):
    bun, swift = build_both(args)
    if bun is None or swift is None:
        print("0/1", flush=True)
        return 1
    if MUTANT == SWITCH:
        bun = swift
    ctx = Context()
    try:
        results = drive(names, bun, swift, ALLOWED, ctx)
    finally:
        ctx.stop()
    checks = {name: (not problems, "") for name, (problems, _) in results.items()}
    for check, (ok, detail) in row_checks(names, results, ALLOWED).items():
        checks[check] = (ok, detail)
        print(f"{check} {'ok' if ok else 'FAIL'} — {detail}", flush=True)
    passed = sum(1 for ok, _ in checks.values() if ok)
    print(f"{passed}/{len(checks)}", flush=True)
    if MUTANT == SWITCH:
        named = ["row:" + row["id"] for row in ALLOWED if declared(row, names)]
        return verdict(SWITCH, named, checks)
    return 0 if passed == len(checks) else 1


def verdict(name, named, checks):
    survived = [check for check in named if checks.get(check, (True, ""))[0]]
    if survived:
        print(f"mutant {name}: SURVIVED — {', '.join(survived)} passed", flush=True)
        return 0
    print(f"mutant {name}: caught — {', '.join(named)} failed", flush=True)
    return 1


def drop(args, names, row_id):
    """Without one row: exactly its declared cases FAIL."""
    row = next(r for r in ALLOWED if r["id"] == row_id)
    want = sorted(declared(row, names))
    if not want:
        print(f"drop {row_id}: the control could not be performed — none of its cases is in "
              f"this run", flush=True)
        return 2
    bun, swift = build_both(args)
    if bun is None or swift is None:
        print(f"drop {row_id}: the control could not be performed — a helper did not build",
              flush=True)
        return 2
    rows = [r for r in ALLOWED if r["id"] != row_id]
    ctx = Context()
    try:
        results = drive(names, bun, swift, rows, ctx)
    finally:
        ctx.stop()
    failed = sorted(name for name, (problems, _) in results.items() if problems)
    if failed == want:
        print(f"drop {row_id}: caught — exactly {', '.join(want)} failed", flush=True)
        return 1
    print(f"drop {row_id}: SURVIVED — failed {failed}, its cases {want}", flush=True)
    return 0


def rows_needed(args, names):
    """One run, then the comparison again without each row: every row's own cases FAIL and no
    other. Exit 0 when that holds for every row."""
    bun, swift = build_both(args)
    if bun is None or swift is None:
        return 1
    ctx = Context()
    try:
        results = drive(names, bun, swift, ALLOWED, ctx)
        base = sorted(name for name, (problems, _) in results.items() if problems)
        good = not base
        if base:
            print(f"with every row, FAIL already: {base}", flush=True)
        for row in ALLOWED:
            want = sorted(declared(row, names))
            again = recompare(names, [r for r in ALLOWED if r is not row], ctx)
            failed = sorted(name for name, (problems, _) in again.items() if problems)
            ok = failed == want
            good &= ok
            print(f"row {row['id']} {'needed' if ok else 'FAIL'} — without it {len(failed)} "
                  f"FAIL: {', '.join(failed) or 'none'}" + ("" if ok else f"; its cases {want}"),
                  flush=True)
    finally:
        ctx.stop()
    return 0 if good else 1


def mutant(args, name):
    """A SWIFT_MUTANTS edit built on the persistent mutant tree, then the named cases."""
    file, anchor, replacement, named = SWIFT_MUTANTS[name]
    bun = Path(args.bun).resolve() if args.bun else None
    if bun is None:
        bun, why = build_bun()
        print(f"B0 {'ok' if bun else 'FAIL'} — the Bun helper: {why}", flush=True)
    swift, why = agent_helper_build.mutant(name, [(file, anchor, replacement)],
                                           WORK / "mutant" / name / "framejob-agent")
    print(f"B1 {'ok' if swift else 'FAIL'} — the mutated Swift helper: {why}", flush=True)
    if bun is None or swift is None:
        print(f"mutant {name}: the control could not be performed — a helper did not build",
              flush=True)
        return 2
    ctx = Context()
    try:
        results = drive(ordered(named), bun, swift, ALLOWED, ctx)
    finally:
        ctx.stop()
    checks = {case: (not results[case][0], "") for case in named}
    return verdict(name, named, checks)


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cases", help="a comma-separated subset of the cases")
    parser.add_argument("--bun", help="a built Bun helper, in place of B0")
    parser.add_argument("--swift", help="a built Swift helper, in place of B1")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--drop", choices=[row["id"] for row in ALLOWED])
    parser.add_argument("--rows-needed", action="store_true")
    parser.add_argument("--mutant", choices=sorted(SWIFT_MUTANTS) + [SWITCH])
    args = parser.parse_args()
    if args.list:
        listing()
        return 0
    WORK.mkdir(parents=True, exist_ok=True)
    unknown = [n for n in (args.cases or "").split(",") if n and n not in CASES]
    if unknown:
        parser.error(f"no case {', '.join(unknown)}")
    names = ordered(args.cases.split(",") if args.cases else list(CASES))
    if args.drop:
        return drop(args, names, args.drop)
    if args.rows_needed:
        return rows_needed(args, names)
    if args.mutant and args.mutant != SWITCH:
        return mutant(args, args.mutant)
    MUTANT = args.mutant
    return plain(args, names)


if __name__ == "__main__":
    sys.exit(main())
