#!/usr/bin/env python3
"""Road map 14 MC1, q3 — a stdio MCP stub server whose tool list changes.

    python3 tools/proof/mc1_spike/stub_mcp.py --mode during-call|unprompted|silent --log <jsonl>

Newline-delimited JSON-RPC on stdin and stdout (the MCP stdio transport);
stdout carries protocol only. Every inbound message is logged to `--log` as
one JSON line `{"dir":"in","t":<monotonic>,"wall":<epoch>,"message":…}`,
and every notification it sends as `{"dir":"out",…}`, so a person reading
the log after a client session (docs/manual-checks.md AC-1, AC-2) sees
whether a second `tools/list` followed the notification.

`initialize` answers with `capabilities: {"tools": {"listChanged": true}}`.
Tools v1 is `[probe_wait]`; v2 is `[probe_wait, probe_new]`.

* `during-call` — a `probe_wait` call sends `notifications/tools/list_changed`,
  switches to v2, waits 5 s, then answers (on its own thread, so a
  `tools/list` sent during the wait is answered at once);
* `unprompted` — 2 s after the first `tools/list` answer it switches to v2
  and notifies;
* `silent` — never notifies and never switches (the control).

Standard library only. It exits at end of input.
"""

import argparse
import json
import sys
import threading
import time

PROTOCOL = "2025-06-18"

PROBE_WAIT = {
    "name": "probe_wait",
    "description": "MC1 spike stub: waits five seconds and answers. Call it first.",
    "inputSchema": {"type": "object", "properties": {}},
}
PROBE_NEW = {
    "name": "probe_new",
    "description": "MC1 spike stub: present only after the tool list changed. Answers at once.",
    "inputSchema": {"type": "object", "properties": {}},
}


class Stub:
    def __init__(self, mode, log_path):
        self.mode = mode
        self.version = 1
        self.out_lock = threading.Lock()
        self.log = open(log_path, "a", buffering=1)
        self.log_lock = threading.Lock()
        self.first_list_answered = False

    def record(self, direction, message):
        with self.log_lock:
            self.log.write(json.dumps({"dir": direction, "t": time.monotonic(),
                                       "wall": time.time(), "message": message}) + "\n")

    def send(self, message):
        with self.out_lock:
            sys.stdout.write(json.dumps(message) + "\n")
            sys.stdout.flush()

    def tools(self):
        return [PROBE_WAIT, PROBE_NEW] if self.version == 2 else [PROBE_WAIT]

    def notify_changed(self):
        self.version = 2
        message = {"jsonrpc": "2.0", "method": "notifications/tools/list_changed"}
        self.record("out", message)
        self.send(message)

    def result(self, ident, result):
        self.send({"jsonrpc": "2.0", "id": ident, "result": result})

    def error(self, ident, code, text):
        self.send({"jsonrpc": "2.0", "id": ident, "error": {"code": code, "message": text}})

    def call(self, ident, name):
        if name == "probe_wait":
            if self.mode == "during-call":
                self.notify_changed()
                time.sleep(5)
            self.result(ident, {"content": [{"type": "text", "text": "probe_wait answered"}],
                                "isError": False})
        elif name == "probe_new" and self.version == 2:
            self.result(ident, {"content": [{"type": "text", "text": "probe_new answered"}],
                                "isError": False})
        else:
            self.result(ident, {"content": [{"type": "text", "text": f"unknown tool: {name}"}],
                                "isError": True})

    def handle(self, message):
        method = message.get("method")
        ident = message.get("id")
        if method is None or ident is None:
            return  # a notification or a response: nothing to answer
        params = message.get("params") or {}
        if method == "initialize":
            requested = params.get("protocolVersion")
            self.result(ident, {
                "protocolVersion": requested if isinstance(requested, str) else PROTOCOL,
                "capabilities": {"tools": {"listChanged": True}},
                "serverInfo": {"name": "mc1-stub", "version": "0.0.1"},
            })
        elif method == "ping":
            self.result(ident, {})
        elif method == "tools/list":
            self.result(ident, {"tools": self.tools()})
            if self.mode == "unprompted" and not self.first_list_answered:
                self.first_list_answered = True
                timer = threading.Timer(2.0, self.notify_changed)
                timer.daemon = True
                timer.start()
        elif method == "tools/call":
            worker = threading.Thread(target=self.call, args=(ident, params.get("name")),
                                      daemon=True)
            worker.start()
        else:
            self.error(ident, -32601, f"method not found: {method}")

    def run(self):
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except ValueError:
                self.record("in", {"unparsed": line})
                self.error(None, -32700, "parse error")
                continue
            self.record("in", message)
            if isinstance(message, dict):
                self.handle(message)
        # Let a pending probe_wait answer before exiting.
        for worker in threading.enumerate():
            if worker is not threading.current_thread() and not isinstance(worker, threading.Timer):
                worker.join(timeout=6)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mode", required=True, choices=["during-call", "unprompted", "silent"])
    parser.add_argument("--log", required=True)
    arguments = parser.parse_args()
    Stub(arguments.mode, arguments.log).run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
