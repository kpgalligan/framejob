#!/usr/bin/env python3
"""Road map 6, spike C0 — the in-process stand-in the selftest drives.

Not C1's `assemblyai_fake.py` (that one is out of scope here): this one exists
so the spike's own code path — upload, submit, poll, fetch, delete, list — can
be run end to end for free, with `SELFTEST_KEY`, before a single paid call.
It speaks the five routes and keeps a log the selftest reads back, and it can
be told to misbehave in the two ways that would otherwise be untestable:

* `redirect_next` — the next request, GET or POST, answers 302 with that
  `Location`. The selftest points it at a SECOND fake and asserts the second
  one's log stays empty: no redirect is followed, so the `authorization`
  header never reaches it.
* `drop_submit_reply` — the transcript is created and the socket is closed
  unanswered. That is the lost submit road map 6 §3's recovery is for.

`foreign` seeds the list route with entries carrying other `audio_url`s, so
the selftest can prove `find_own` returns none of them.
"""

import http.server
import json
import threading
import uuid


class Fake:
    def __init__(self):
        self.log = []
        self.words = [
            {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
            {"text": "there", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None},
        ]
        self.polls_before_complete = 1
        self.foreign = []
        self.redirect_next = None
        self.drop_submit_reply = False
        self.transcripts = {}
        self.deleted = set()
        self.uploads = []
        self._server = None

    def start(self):
        fake = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *arguments):
                pass

            def _json(self, code, body):
                data = json.dumps(body).encode("utf-8")
                self.send_response(code)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _handle(self, method):
                length = int(self.headers.get("content-length") or 0)
                body = self.rfile.read(length) if length else b""
                try:
                    parsed = json.loads(body) if body else None
                except ValueError:
                    parsed = None
                fake.log.append({
                    "method": method,
                    "path": self.path,
                    "headers": {k.lower(): v for k, v in self.headers.items()},
                    "bytes": len(body),
                    "json": parsed,
                })
                if fake.redirect_next:
                    where, fake.redirect_next = fake.redirect_next, None
                    self.send_response(302)
                    self.send_header("location", where)
                    self.send_header("content-length", "0")
                    self.end_headers()
                    return
                path = self.path.split("?")[0]
                if method == "POST" and path == "/v2/upload":
                    url = f"https://cdn.example.invalid/upload/{uuid.uuid4().hex}"
                    fake.uploads.append({"url": url, "bytes": len(body)})
                    return self._json(200, {"upload_url": url})
                if method == "POST" and path == "/v2/transcript":
                    tid = f"t_{uuid.uuid4().hex[:12]}"
                    fake.transcripts[tid] = {
                        "id": tid,
                        "audio_url": (parsed or {}).get("audio_url"),
                        "request": parsed or {},
                        "polls": 0,
                    }
                    if fake.drop_submit_reply:
                        self.close_connection = True
                        try:
                            self.connection.close()
                        except OSError:
                            pass
                        return
                    return self._json(200, fake.body(tid, "queued"))
                if method == "GET" and path == "/v2/transcript":
                    live = [{"id": t["id"], "audio_url": t["audio_url"]}
                            for t in fake.transcripts.values() if t["id"] not in fake.deleted]
                    return self._json(200, {"transcripts": list(fake.foreign) + live})
                if path.startswith("/v2/transcript/"):
                    tid = path.rsplit("/", 1)[1]
                    if tid not in fake.transcripts or tid in fake.deleted:
                        return self._json(404, {"error": "not found"})
                    if method == "DELETE":
                        fake.deleted.add(tid)
                        return self._json(200, fake.body(tid, "completed", deleted=True))
                    fake.transcripts[tid]["polls"] += 1
                    done = fake.transcripts[tid]["polls"] > fake.polls_before_complete
                    return self._json(200, fake.body(tid, "completed" if done else "processing"))
                return self._json(404, {"error": "no route"})

            def do_GET(self):
                self._handle("GET")

            def do_POST(self):
                self._handle("POST")

            def do_DELETE(self):
                self._handle("DELETE")

        self._server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self._server.serve_forever, daemon=True).start()
        return f"http://127.0.0.1:{self._server.server_address[1]}"

    def body(self, tid, status, deleted=False):
        row = self.transcripts[tid]
        answer = {
            "id": tid,
            "status": status,
            "audio_url": row["audio_url"],
            "speech_model_used": "universal-3-5-pro",
            "language_code": "en_us",
            "language_confidence": 0.99,
            "audio_duration": 11,
        }
        if status == "completed":
            answer["words"] = [] if deleted else list(self.words)
            answer["text"] = " ".join(w["text"] for w in self.words)
        return answer

    def stop(self):
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
            self._server = None
