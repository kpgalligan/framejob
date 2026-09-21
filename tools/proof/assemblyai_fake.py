#!/usr/bin/env python3
"""Road map 6, C1 §5i — the stand-in AssemblyAI server, whole.

`http.server`, no dependencies. It binds `127.0.0.1` on port 0, prints
`port <n>` as its FIRST stdout line and flushes, and speaks the five calls of
§5c plus a control endpoint. `cloud_captions_probe.py` drives it over a socket
here; pipeline 3 drives it through the built app.

    python3 tools/proof/assemblyai_fake.py --dir <logdir>

**What was reused from `cloud_spike/fake.py`** (C0's in-process fake): the
handler skeleton and its three `do_*` forwards, `_json`, the lower-cased
header log, `redirect_next`, and the transcript table with its `polls` count.
NOT its 404-after-delete — C0's q6 MEASURED that a real deleted transcript
answers **200** with `audio_url: "http://deleted_by_user"` and
`text: "Deleted by user."`, and a second DELETE answers 200 too, so this fake
answers what the service answered.

**The `words` value after a delete is this fake's own choice, and it is
`null`.** `work/cloud_spike/answers.json`'s `get_after_delete` body was
recorded cut at 300 bytes, and the cut lands inside a `"wor…` KEY: the key is
measured present and its value was never recorded. `null` is chosen because
it is the value that exercises the client's "a completed body with no words
ARRAY is `.malformed`, never an empty transcript" rule.

**R6-9(e), the credential rule.** An `authorization` value is written to the
log ONLY when it is one of the two dummies `proof-key` and `wrong-key`.
Anything else is logged as `<redacted: not an allow-listed dummy>`, answered
401, appended to `failures` — a scored failure of whatever run sent it — and
the value itself is written nowhere, not to the log, not to stdout, not to a
file. That is what makes a proof safe to run on a machine where the person
has a real key.

Measured answers this fake reproduces (road map 6 §3):

* `audio_duration` is the audio's seconds rounded UP (q1), taken from the
  uploaded body itself — the WAV `data` chunk's size or the FLAC
  STREAMINFO's total-samples field — or from the scenario's `audio_seconds`.
* A `language_code` the service does not support is a **400 at SUBMISSION**
  (q5), with its sentence verbatim.
* A deleted transcript answers 200, not 404 (q6).

The scenario, replaced whole by `POST /__control/scenario` (which also resets
the counters):

    words                        the array to serve, serialised ONCE
    polls_before_complete        how many GETs answer `processing` first
    never_complete               every GET answers `processing`
    transcript_error             a string: the transcript ends in `error`
    fail                         [{route, status, times}] — times -1 is always
    slow_upload                  {chunk, delay_ms} — the body read in pieces
    redirect_next                a Location for the next request, once
    unsupported_language_codes   default ["xx"]
    speech_model_used            default "universal-3-5-pro"
    language_code                default "en_us"
    language_confidence          default 0.99
    audio_seconds                overrides the measured duration

`GET /__control/log` answers `{"requests": [...], "failures": [...]}`;
`GET /__control/words` answers the exact bytes this fake serves as `words`.
"""

import argparse
import http.server
import json
import math
import os
import struct
import sys
import threading
import uuid

# R6-9(e). Two dummies and nothing else. A value off this list is never
# written anywhere — that is the whole point of the list.
ALLOWED_KEYS = {"proof-key", "wrong-key"}
REDACTION = "<redacted: not an allow-listed dummy>"

# C0 q5's sentence, verbatim.
LANGUAGE_REFUSAL = ("Language code {code} is not supported. See "
                    "https://www.assemblyai.com/docs/concepts/supported-languages.")

DEFAULT_WORDS = [
    {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
    {"text": "there", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None},
]

ROUTES = ("upload", "submit", "poll", "delete", "verify")


def wav_seconds(data):
    """Seconds of 16 kHz mono 16-bit PCM in a RIFF WAV, from the `data`
    chunk's own size — never from the file's length, which carries the
    header."""
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return None
    at = 12
    rate, channels, bits = 16000, 1, 16
    while at + 8 <= len(data):
        name = data[at:at + 4]
        size = struct.unpack_from("<I", data, at + 4)[0]
        body = at + 8
        if name == b"fmt " and body + 16 <= len(data):
            channels = struct.unpack_from("<H", data, body + 2)[0] or 1
            rate = struct.unpack_from("<I", data, body + 4)[0] or 16000
            bits = struct.unpack_from("<H", data, body + 14)[0] or 16
        if name == b"data":
            frame = max(1, channels * (bits // 8))
            return min(size, len(data) - body) / frame / rate
        at = body + size + (size & 1)
    return None


def flac_seconds(data):
    """Seconds from a FLAC STREAMINFO block: the 36-bit total-sample count
    over the 20-bit sample rate, both in the 34 bytes after the block
    header."""
    if len(data) < 42 or data[:4] != b"fLaC":
        return None
    body = data[8:42]
    bits = int.from_bytes(body, "big")
    # STREAMINFO layout: 16+16+24+24 bits, then rate(20) channels(3)
    # depth(5) samples(36).
    rate = (bits >> (34 * 8 - 80 - 20)) & 0xFFFFF
    samples = (bits >> (34 * 8 - 80 - 20 - 3 - 5 - 36)) & 0xFFFFFFFFF
    if not rate or not samples:
        return None
    return samples / rate


class Scenario:
    def __init__(self):
        self.reset({})

    def reset(self, given):
        self.words = given.get("words", DEFAULT_WORDS)
        # Serialised ONCE, here, so what `GET /__control/words` answers and
        # what a poll serves are the same bytes by construction rather than
        # by two encoders agreeing.
        self.words_bytes = json.dumps(self.words).encode("utf-8")
        self.polls_before_complete = int(given.get("polls_before_complete", 0))
        self.never_complete = bool(given.get("never_complete", False))
        self.transcript_error = given.get("transcript_error")
        self.fail = [dict(row) for row in given.get("fail", [])]
        self.slow_upload = given.get("slow_upload")
        self.redirect_next = given.get("redirect_next")
        self.unsupported = list(given.get("unsupported_language_codes", ["xx"]))
        self.speech_model_used = given.get("speech_model_used", "universal-3-5-pro")
        self.language_code = given.get("language_code", "en_us")
        self.language_confidence = given.get("language_confidence", 0.99)
        self.audio_seconds = given.get("audio_seconds")

    def take_failure(self, route):
        """The status this route must answer this time, or None. A row with
        `times: -1` never runs out."""
        for row in self.fail:
            if row.get("route") != route:
                continue
            times = int(row.get("times", 1))
            if times == 0:
                continue
            if times > 0:
                row["times"] = times - 1
            return int(row.get("status", 500))
        return None


class Fake:
    def __init__(self, folder):
        self.folder = folder
        self.lock = threading.Lock()
        self.scenario = Scenario()
        self.requests = []
        self.failures = []
        self.transcripts = {}
        self.deleted = set()
        self.uploads = {}
        self.upload_count = 0
        self._server = None

    # -- the log ---------------------------------------------------------

    def record(self, entry):
        with self.lock:
            self.requests.append(entry)

    def fail(self, reason):
        with self.lock:
            self.failures.append(reason)

    def log_body(self):
        with self.lock:
            return {"requests": list(self.requests), "failures": list(self.failures)}

    def reset(self, given):
        with self.lock:
            self.scenario.reset(given)
            self.requests = []
            self.failures = []
            self.transcripts = {}
            self.deleted = set()
            self.uploads = {}
            self.upload_count = 0

    # -- what a transcript answers ---------------------------------------

    def body(self, tid, status):
        row = self.transcripts[tid]
        answer = {
            "id": tid,
            "status": status,
            "audio_url": row["audio_url"],
            "speech_model_used": self.scenario.speech_model_used,
            "language_code": row["request"].get("language_code")
            or self.scenario.language_code,
            "language_confidence": self.scenario.language_confidence,
            "audio_duration": row["audio_duration"],
        }
        if status == "error":
            answer["error"] = self.scenario.transcript_error
        return answer

    def completed_bytes(self, tid):
        """A completed body with the scenario's `words` spliced in as BYTES,
        so what the client reads is what `GET /__control/words` answers."""
        head = json.dumps(self.body(tid, "completed"))[:-1].encode("utf-8")
        text = " ".join(str(w.get("text", "")) for w in self.scenario.words)
        return (head + b',"text":' + json.dumps(text).encode("utf-8")
                + b',"words":' + self.scenario.words_bytes + b"}")

    def deleted_bytes(self, tid):
        """q6's sentinel. `words` is `null` — this fake's own choice, argued
        in the header."""
        answer = self.body(tid, "completed")
        answer["audio_url"] = "http://deleted_by_user"
        answer["text"] = "Deleted by user."
        answer["words"] = None
        return json.dumps(answer).encode("utf-8")


def make_handler(fake):

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *arguments):
            pass

        # -- replies ------------------------------------------------------

        def _bytes(self, code, data, kind="application/json"):
            # A cancelled upload leaves a socket nobody is reading; answering
            # into it is not this fake's problem to report.
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

        # -- reading a body ------------------------------------------------

        def _read_body(self, entry):
            """The whole body, or, for an upload under `slow_upload`, as much
            of it as arrives before the socket goes away. An upload's bytes
            land in a file beside the log and the entry says how many were
            received and whether the body completed — which is what a
            cancelled upload is MEASURED by."""
            length = int(self.headers.get("content-length") or 0)
            entry["content_length"] = length
            # Set BEFORE the first read and updated per chunk, so a reader
            # asking while the body is still arriving — or while a cancelled
            # one never finishes arriving — sees a number rather than a nil.
            entry["received"] = 0
            entry["complete"] = False
            slow = fake.scenario.slow_upload
            if not slow:
                body = self.rfile.read(length) if length else b""
                entry["received"] = len(body)
                entry["complete"] = len(body) == length
                return body
            chunk = int(slow.get("chunk", 65536))
            delay = float(slow.get("delay_ms", 10)) / 1000.0
            got = bytearray()
            while len(got) < length:
                want = min(chunk, length - len(got))
                try:
                    piece = self.rfile.read(want)
                except OSError:
                    break
                if not piece:
                    break
                got += piece
                entry["received"] = len(got)
                if len(got) < length:
                    threading.Event().wait(delay)
            entry["received"] = len(got)
            entry["complete"] = len(got) == length
            return bytes(got)

        # -- dispatch ------------------------------------------------------

        def _handle(self, method):
            path = self.path.split("?")[0]
            headers = {}
            for name, value in self.headers.items():
                name = name.lower()
                if name == "authorization":
                    if value in ALLOWED_KEYS:
                        headers[name] = value
                    else:
                        headers[name] = REDACTION
                else:
                    headers[name] = value
            entry = {"method": method, "path": self.path, "headers": headers}

            if path.startswith("/__control/"):
                return self._control(method, path, entry)

            # Logged as soon as the HEADERS are parsed, and mutated in place
            # as the body arrives: an upload the client CANCELS mid-body never
            # reaches the end of this method, and a request that was made and
            # abandoned is exactly what row 16 has to be able to see.
            fake.record(entry)
            body = self._read_body(entry)
            if path == "/v2/upload" and method == "POST":
                entry["bytes"] = len(body)
                fake.upload_count += 1
                name = f"upload-{fake.upload_count}.bin"
                where = os.path.join(fake.folder, name)
                with open(where, "wb") as f:
                    f.write(body)
                entry["file"] = where
            else:
                try:
                    entry["json"] = json.loads(body) if body else None
                except ValueError:
                    entry["json"] = None

            # R6-9(e): a key that is not an allow-listed dummy is refused and
            # scored, and nothing of it was written above.
            given = self.headers.get("authorization")
            if given is not None and given not in ALLOWED_KEYS:
                fake.fail(f"{method} {path} carried an authorization value that is not an "
                          f"allow-listed dummy")
                return self._json(401, {"error": "Authentication error, API token missing/invalid"})

            if fake.scenario.redirect_next:
                where = fake.scenario.redirect_next
                fake.scenario.redirect_next = None
                self.send_response(302)
                self.send_header("location", where)
                self.send_header("content-length", "0")
                self.end_headers()
                return None

            route = self._route(method, path)
            if route is None:
                return self._json(404, {"error": "no route"})
            forced = fake.scenario.take_failure(route)
            if forced is not None:
                return self._json(forced, {"error": f"forced {forced} on {route}"})

            if route == "upload":
                return self._upload(body, entry)
            if route == "submit":
                return self._submit(entry.get("json") or {})
            if route == "verify":
                return self._json(200, {"transcripts": [
                    {"id": tid} for tid in fake.transcripts if tid not in fake.deleted]})
            tid = path.rsplit("/", 1)[1]
            if tid not in fake.transcripts:
                return self._json(404, {"error": "not found"})
            if route == "delete":
                fake.deleted.add(tid)
                return self._bytes(200, fake.deleted_bytes(tid))
            return self._poll(tid)

        def _route(self, method, path):
            if method == "POST" and path == "/v2/upload":
                return "upload"
            if method == "POST" and path == "/v2/transcript":
                return "submit"
            if method == "GET" and path == "/v2/transcript":
                return "verify"
            if path.startswith("/v2/transcript/"):
                return "delete" if method == "DELETE" else "poll"
            return None

        # -- the five calls -------------------------------------------------

        def _upload(self, body, entry):
            url = f"https://cdn.example.invalid/upload/{uuid.uuid4().hex}"
            seconds = fake.scenario.audio_seconds
            if seconds is None:
                seconds = wav_seconds(body)
            if seconds is None:
                seconds = flac_seconds(body)
            fake.uploads[url] = seconds
            entry["measured_seconds"] = seconds
            return self._json(200, {"upload_url": url})

        def _submit(self, request):
            code = request.get("language_code")
            if code is not None and code in fake.scenario.unsupported:
                # q5: refused AT SUBMISSION, with the service's own sentence.
                return self._json(400, {"error": LANGUAGE_REFUSAL.format(code=code)})
            seconds = fake.uploads.get(request.get("audio_url"))
            if seconds is None:
                seconds = fake.scenario.audio_seconds or 0
            tid = f"t_{uuid.uuid4().hex[:12]}"
            fake.transcripts[tid] = {
                "id": tid,
                "audio_url": request.get("audio_url"),
                "request": request,
                "polls": 0,
                # q1: `audio_duration` rounds UP.
                "audio_duration": int(math.ceil(seconds)),
            }
            return self._json(200, fake.body(tid, "queued"))

        def _poll(self, tid):
            if tid in fake.deleted:
                return self._bytes(200, fake.deleted_bytes(tid))
            fake.transcripts[tid]["polls"] += 1
            if fake.scenario.transcript_error:
                return self._json(200, fake.body(tid, "error"))
            if fake.scenario.never_complete:
                return self._json(200, fake.body(tid, "processing"))
            if fake.transcripts[tid]["polls"] <= fake.scenario.polls_before_complete:
                return self._json(200, fake.body(tid, "processing"))
            return self._bytes(200, fake.completed_bytes(tid))

        # -- the control endpoint -------------------------------------------

        def _control(self, method, path, entry):
            if path == "/__control/scenario" and method == "POST":
                length = int(self.headers.get("content-length") or 0)
                raw = self.rfile.read(length) if length else b"{}"
                try:
                    given = json.loads(raw) if raw else {}
                except ValueError:
                    return self._json(400, {"error": "the scenario is not JSON"})
                fake.reset(given)
                return self._json(200, {"ok": True})
            if path == "/__control/log" and method == "GET":
                return self._json(200, fake.log_body())
            if path == "/__control/words" and method == "GET":
                return self._bytes(200, fake.scenario.words_bytes)
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
                        help="where the uploads land; created if absent")
    args = parser.parse_args()
    os.makedirs(args.dir, exist_ok=True)
    fake = Fake(os.path.abspath(args.dir))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), make_handler(fake))
    fake._server = server
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
