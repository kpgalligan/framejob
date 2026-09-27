#!/usr/bin/env python3
"""Road map 12, A0 — the stand-in Anthropic Messages API server.

`http.server`, no dependencies, in `assemblyai_fake.py`'s shape. It binds
`127.0.0.1` on port 0, prints `port <n>` as its FIRST stdout line and
flushes, and answers the three routes the assistant helper (Rasterize's
`agent/`, the Anthropic TypeScript SDK's Tool Runner) calls, plus a control
endpoint. `assistant_spike/assistant_spike.py` drives it; A1 reuses it.

    python3 tools/proof/anthropic_fake.py --dir <logdir>

Routes:

* `GET /v1/models/<id>` answers
  `{"type":"model","id","display_name","created_at","max_input_tokens"}`,
  the last from the scenario.
* `POST /v1/messages` (any query string: the SDK's beta calls add
  `?beta=true`) answers the NEXT scripted reply. With `"stream": true` in the
  body it answers server-sent events and then closes the connection:
  `message_start` (usage input 100, output 0, `cache_*` 0); per content
  block a `content_block_start`, ONE `content_block_delta` (`text_delta`,
  or `input_json_delta` carrying the whole input) and a
  `content_block_stop`; then `message_delta` (`stop_reason`, output 10) and
  `message_stop`. Without it, one Message JSON. Past the end of the script
  it answers 400 `invalid_request_error` and records a failure.
* `POST /__control/scenario` replaces the scenario and resets the log:
  `{"replies":[{"content":[Block],"stop_reason"}],"max_input_tokens":1000000}`,
  a Block being `{"type":"text","text"}` or
  `{"type":"tool_use","id","name","input"}`.
* `GET /__control/log` answers
  `{"requests":[{"method","path","headers","body","bytes"}],"failures":[str]}`.

Any other route answers 404 and records a failure.

**R6-9(e), the credential rule, as `assemblyai_fake.py` keeps it.** An
`x-api-key` or `authorization` value is written to the log ONLY when it is
one of the two dummies `proof-key` and `wrong-key` (an `authorization` may
carry either behind `Bearer `). `wrong-key` is answered 401
`authentication_error`. Anything else is answered 401, logged as
`<redacted: not an allow-listed dummy>` and appended to `failures`, and the
value itself is written nowhere: not to the log, not to stdout, not to a
file. A `/v1/` request carrying no credential at all is answered 401 and is
a failure too. The `--dir` folder receives `requests.jsonl`, one logged
(already redacted) request per line.
"""

import argparse
import http.server
import json
import os
import sys
import threading

ALLOWED_KEYS = {"proof-key", "wrong-key"}
REDACTION = "<redacted: not an allow-listed dummy>"
CREDENTIAL_HEADERS = ("x-api-key", "authorization")


def bare(value):
    return value[len("Bearer "):] if value.startswith("Bearer ") else value


class Fake:
    def __init__(self, folder):
        self.folder = folder
        self.lock = threading.Lock()
        self.replies = []
        self.next_reply = 0
        self.max_input_tokens = 1_000_000
        self.requests = []
        self.failures = []

    def reset(self, given):
        with self.lock:
            self.replies = list(given.get("replies") or [])
            self.next_reply = 0
            self.max_input_tokens = given.get("max_input_tokens", 1_000_000)
            self.requests = []
            self.failures = []

    def record(self, entry):
        with self.lock:
            self.requests.append(entry)
            with open(os.path.join(self.folder, "requests.jsonl"), "a") as handle:
                handle.write(json.dumps(entry) + "\n")

    def fail(self, reason):
        with self.lock:
            self.failures.append(reason)

    def take_reply(self):
        with self.lock:
            if self.next_reply >= len(self.replies):
                return None, self.next_reply
            index = self.next_reply
            self.next_reply += 1
            return self.replies[index], index

    def log_body(self):
        with self.lock:
            return {"requests": list(self.requests), "failures": list(self.failures)}


def message_object(reply, index, model):
    return {"id": f"msg_a0_{index + 1}", "type": "message", "role": "assistant",
            "model": model, "content": reply.get("content", []),
            "stop_reason": reply.get("stop_reason"), "stop_sequence": None,
            "usage": {"input_tokens": 100, "output_tokens": 10,
                      "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}


def stream_events(reply, index, model):
    """The SSE events of one scripted reply, in the Messages API's order."""
    start = message_object(reply, index, model)
    start["content"] = []
    start["stop_reason"] = None
    start["usage"] = {"input_tokens": 100, "output_tokens": 0,
                      "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    events = [("message_start", {"type": "message_start", "message": start})]
    for at, block in enumerate(reply.get("content", [])):
        if block.get("type") == "tool_use":
            opening = {"type": "tool_use", "id": block["id"], "name": block["name"],
                       "input": {}}
            delta = {"type": "input_json_delta",
                     "partial_json": json.dumps(block.get("input", {}))}
        else:
            opening = {"type": "text", "text": ""}
            delta = {"type": "text_delta", "text": block.get("text", "")}
        events.append(("content_block_start", {"type": "content_block_start", "index": at,
                                               "content_block": opening}))
        events.append(("content_block_delta", {"type": "content_block_delta", "index": at,
                                               "delta": delta}))
        events.append(("content_block_stop", {"type": "content_block_stop", "index": at}))
    events.append(("message_delta", {"type": "message_delta",
                                     "delta": {"stop_reason": reply.get("stop_reason"),
                                               "stop_sequence": None},
                                     "usage": {"output_tokens": 10}}))
    events.append(("message_stop", {"type": "message_stop"}))
    return events


def make_handler(fake):

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *arguments):
            pass

        def _bytes(self, code, data, kind="application/json"):
            try:
                self.send_response(code)
                self.send_header("content-type", kind)
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except OSError:
                self.close_connection = True

        def _json(self, code, body):
            self._bytes(code, json.dumps(body).encode("utf-8"))

        def _error(self, code, kind, message):
            self._json(code, {"type": "error", "error": {"type": kind, "message": message}})

        def _handle(self, method):
            path = self.path.split("?")[0]
            length = int(self.headers.get("content-length") or 0)
            raw = self.rfile.read(length) if length else b""

            if path.startswith("/__control/"):
                return self._control(method, path, raw)

            headers = {}
            credential = None
            for name, value in self.headers.items():
                name = name.lower()
                if name in CREDENTIAL_HEADERS:
                    if bare(value) in ALLOWED_KEYS:
                        headers[name] = value
                        credential = credential or bare(value)
                    else:
                        headers[name] = REDACTION
                        credential = REDACTION
                else:
                    headers[name] = value
            try:
                body = json.loads(raw) if raw else None
            except ValueError:
                body = raw.decode("utf-8", "replace")
            fake.record({"method": method, "path": self.path, "headers": headers,
                         "body": body, "bytes": len(raw)})

            if credential == REDACTION:
                fake.fail(f"{method} {path}: a credential that is not an allow-listed dummy")
                return self._error(401, "authentication_error", "invalid x-api-key")
            if credential is None:
                fake.fail(f"{method} {path}: no credential")
                return self._error(401, "authentication_error", "no x-api-key")
            if credential == "wrong-key":
                return self._error(401, "authentication_error", "invalid x-api-key")

            if method == "GET" and path.startswith("/v1/models/"):
                model = path[len("/v1/models/"):]
                return self._json(200, {"type": "model", "id": model, "display_name": model,
                                        "created_at": "2026-09-01T00:00:00Z",
                                        "max_input_tokens": fake.max_input_tokens})
            if method == "POST" and path == "/v1/messages":
                return self._messages(body if isinstance(body, dict) else {})
            fake.fail(f"{method} {path}: no such route")
            return self._error(404, "not_found_error", f"no route {method} {path}")

        def _messages(self, body):
            reply, index = fake.take_reply()
            if reply is None:
                fake.fail(f"POST /v1/messages #{index + 1}: past the end of the script")
                return self._error(400, "invalid_request_error",
                                   "the stand-in's script has no reply left")
            model = body.get("model", "claude-opus-5-5")
            if not body.get("stream"):
                return self._json(200, message_object(reply, index, model))
            try:
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.send_header("cache-control", "no-cache")
                self.send_header("connection", "close")
                self.end_headers()
                for name, data in stream_events(reply, index, model):
                    self.wfile.write(f"event: {name}\ndata: {json.dumps(data)}\n\n"
                                     .encode("utf-8"))
                self.wfile.flush()
            except OSError:
                pass
            self.close_connection = True

        def _control(self, method, path, raw):
            if path == "/__control/scenario" and method == "POST":
                try:
                    given = json.loads(raw) if raw else {}
                except ValueError:
                    return self._json(400, {"error": "the scenario is not JSON"})
                fake.reset(given)
                return self._json(200, {"ok": True})
            if path == "/__control/log" and method == "GET":
                return self._json(200, fake.log_body())
            fake.fail(f"{method} {path}: no such control route")
            return self._json(404, {"error": "no control route"})

        def do_GET(self):
            self._handle("GET")

        def do_POST(self):
            self._handle("POST")

        def do_DELETE(self):
            self._handle("DELETE")

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dir", required=True,
                        help="where requests.jsonl is written; created if absent")
    args = parser.parse_args()
    os.makedirs(args.dir, exist_ok=True)
    fake = Fake(os.path.abspath(args.dir))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), make_handler(fake))
    # FIRST line, flushed: the caller reads it to learn the port.
    print(f"port {server.server_address[1]}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
