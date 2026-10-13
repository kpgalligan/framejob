"""Road map 12 A3 — the assistant's evaluation against a real model, and its
rehearsal against the stand-in. Imported by `assistant_prompt_proof.py`,
never run as a child: the key is read in THIS process, once, by
`anthropic_key()`, and leaves it only as the relay's `x-api-key` to
`LIVE_UPSTREAM`.

**The relay.** A thread in the proof's own process on 127.0.0.1:0. The app is
pointed at it (`RC_ASSISTANT_BASE_URL`) and its helper sends the dummy
`proof-key`; the relay answers 401 to anything else (the value is never
logged), routes `GET /v1/models/*` and `POST /v1/messages*` only, and forwards
with the real credential. Every POST is priced at its WORST before it is
sent — the body less its image data at one token per three bytes plus
`IMAGE_TOKENS` per image, all at the cache-write rate, plus its `max_tokens`
at the output rate — and forwarded only when settled spend, what is still
reserved and that worst case fit under the cap; otherwise it is answered 400
`invalid_request_error` naming the cap, and recorded. A POST that fits the
cap is then RESERVED at that worst case in the proofs' ledger
(`budget.SpendLedger`, spec §11 P-6) and answered 400 naming the budget
instead when this UTC month's recorded Anthropic spend plus it would pass
$25; only once that reservation is made does the cap count it. A body over
`BODY_BYTES_BOUND` or a `max_tokens` over `MAX_TOKENS_BOUND` is a bound breach
(row H): the headroom arithmetic below assumed neither. The reply is buffered,
its whole usage read, priced by the table (`budget.settle_anthropic`: the
table's price, else each class at its dearest, else the reservation) and
settled in the proofs' ledger, and one run-ledger line appended —
`{run,row,path,status,model,usage,dollars,refused,basis}`, a refused line
with `why` `cap` or `budget`, never a header or a body. With
`keep_exchanges` (issue batch B26), each forwarded POST's parsed body, status,
content type and reply bytes are also kept in memory in `relay.exchanges`,
never on disk.

**`RATES` is a deliberate upper bound, never a quote**: each token class at
its dearest rate over every row and tier of `agent/prices/anthropic.json`
(`budget.anthropic_worst_row`), with the 5-minute and 1-hour cache writes
folded into the dearer. It prices the worst case only; what a reply cost is
the table's price for its own model.

**The headroom arithmetic** (`headroom_lines`): the helper sends
`max_tokens` 32,000 on every POST (`agent/src/main.ts:31`) and all of the
catalog's definitions, deferred ones included; the A2 session proof's largest
logged body was 230,340 bytes, bounded here at 256,000, about 85,333 tokens.
"""

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import budget  # noqa: E402
import prices  # noqa: E402

LIVE_UPSTREAM = "https://api.anthropic.com"
TABLE = prices.load()
_WORST = budget.anthropic_worst_row(TABLE)
RATES = {"input": _WORST["input"],
         "cache_write": max(_WORST["cache_write_5m"], _WORST["cache_write_1h"]),
         "cache_read": _WORST["cache_read"], "output": _WORST["output"]}
IMAGE_TOKENS = 1600
BODY_BYTES_BOUND = 256_000
MAX_TOKENS_BOUND = 32_000
ROUNDS_PER_ROW = 5
OUTPUT_PER_ROUND = 2_000
SUGGESTED_CAP = 20.00
ROWS = 6
PROOF_KEY = "proof-key"
DROPPED_HEADERS = {"x-api-key", "authorization", "host", "content-length", "connection",
                   "accept-encoding"}


KEY_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".secrets",
                        "anthropic-key")


def anthropic_key():
    """The ONE read of the owner's Anthropic key: `ANTHROPIC_API_KEY` when it
    is set, otherwise `.secrets/anthropic-key` at the repo root (gitignored,
    the owner's own file, so a run needs nobody at the machine). Nothing
    that holds its answer is ever printed or written; only its presence is.
    A file anyone but its owner can read is still used, with a warning."""
    env = os.environ.get("ANTHROPIC_API_KEY")
    if env:
        return env
    try:
        mode = os.stat(KEY_FILE).st_mode
        with open(KEY_FILE) as f:
            key = f.read().strip()
    except OSError:
        return None
    if mode & 0o077:
        print("warning: .secrets/anthropic-key is readable by others; "
              "chmod 600 .secrets/anthropic-key", flush=True)
    return key or None


# ---------------------------------------------------------------------------
# The arithmetic.


def _per_million(tokens, rate):
    return tokens * RATES[rate] / 1_000_000


def body_tokens():
    return BODY_BYTES_BOUND / 3


def worst_post():
    """The dearest one POST can be: the bounded body, every byte a cache
    write, and `max_tokens` of output."""
    return _per_million(body_tokens(), "cache_write") + _per_million(MAX_TOKENS_BOUND, "output")


def row_bound():
    """An estimate of one row: one cache write of the bounded body, then
    ROUNDS_PER_ROW − 1 cache reads of it, and OUTPUT_PER_ROUND of output a
    round. It bills every definition byte, deferred ones too."""
    return (_per_million(body_tokens(), "cache_write")
            + (ROUNDS_PER_ROW - 1) * _per_million(body_tokens(), "cache_read")
            + ROUNDS_PER_ROW * _per_million(OUTPUT_PER_ROUND, "output"))


def cap_floor():
    return worst_post() + ROWS * row_bound()


def headroom_lines(cap):
    lines = [
        "rates ($/MTok, an UPPER BOUND, not a quote: each class's dearest in "
        f"agent/prices/anthropic.json of {TABLE.get('litellm_commit_date')}): input "
        f"{RATES['input']:.2f}, cache write {RATES['cache_write']:.2f}, cache read "
        f"{RATES['cache_read']:.2f}, output {RATES['output']:.2f}",
        f"worst POST: {BODY_BYTES_BOUND:,} bytes / 3 = {body_tokens():,.0f} tokens at cache write "
        f"(${_per_million(body_tokens(), 'cache_write'):.2f}) + max_tokens {MAX_TOKENS_BOUND:,} at "
        f"output (${_per_million(MAX_TOKENS_BOUND, 'output'):.2f}) = ${worst_post():.2f}",
        f"row bound: one cache write (${_per_million(body_tokens(), 'cache_write'):.2f}) + "
        f"{ROUNDS_PER_ROW - 1} cache reads "
        f"(${(ROUNDS_PER_ROW - 1) * _per_million(body_tokens(), 'cache_read'):.2f}) + "
        f"{ROUNDS_PER_ROW} x {OUTPUT_PER_ROUND:,} output "
        f"(${ROUNDS_PER_ROW * _per_million(OUTPUT_PER_ROUND, 'output'):.2f}) = "
        f"${row_bound():.2f}, an estimate billing every definition byte",
        f"floor: worst POST + {ROWS} row bounds = ${cap_floor():.2f}; suggested cap "
        f"${SUGGESTED_CAP:.2f}",
        "budget: $25.00 a calendar month (UTC) for Anthropic, before each POST, in the proofs' "
        "ledger (spec §11 P-6)",
    ]
    if cap is None:
        lines.append("cap: none given — --live needs --cap <dollars>, the runner's decision")
        return lines
    left = cap - worst_post()
    covered = max(0.0, left) / row_bound()
    lines.append(f"cap ${cap:.4g}: ${left:.2f} past the worst POST, covering {covered:.1f} row "
                 "bounds")
    if cap < cap_floor():
        lines.append(f"WARNING: below the floor; rows past ${left:.2f} of settled spend will "
                     "fail naming the cap")
    return lines


# ---------------------------------------------------------------------------
# The relay.


def measure(raw):
    """(worst dollars, stripped bytes, images, max_tokens) of one POST body."""
    try:
        body = json.loads(raw) if raw else {}
    except ValueError:
        body = {}
    images, image_bytes = 0, 0

    def walk(value):
        nonlocal images, image_bytes
        if isinstance(value, dict):
            source = value.get("source")
            if value.get("type") == "image" and isinstance(source, dict) \
                    and isinstance(source.get("data"), str):
                images += 1
                image_bytes += len(source["data"].encode("utf-8"))
            for inner in value.values():
                walk(inner)
        elif isinstance(value, list):
            for inner in value:
                walk(inner)

    walk(body)
    stripped = len(raw) - image_bytes
    max_tokens = body.get("max_tokens") if isinstance(body, dict) else None
    max_tokens = max_tokens if isinstance(max_tokens, int) else 0
    worst = (_per_million(stripped / 3 + IMAGE_TOKENS * images, "cache_write")
             + _per_million(max_tokens, "output"))
    return worst, stripped, images, max_tokens


def read_usage(data, content_type, status=200):
    """(usage, model, whole) of a buffered reply, stream or not. `usage` keeps
    every key; a stream's `message_delta.usage` keys overlay
    `message_start`'s. `whole` is False for a 200 stream with no
    `message_stop` and a 200 body with no `usage` object: a reply whose usage
    cannot be read settles at its reservation."""
    usage, model = {}, None

    def take(given):
        if isinstance(given, dict):
            usage.update(given)

    text = data.decode("utf-8", "replace")
    if "text/event-stream" in (content_type or ""):
        stopped = False
        for line in text.splitlines():
            if not line.startswith("data:"):
                continue
            try:
                event = json.loads(line[5:].strip())
            except ValueError:
                continue
            if not isinstance(event, dict):
                continue
            if event.get("type") == "message_start":
                message = event.get("message")
                message = message if isinstance(message, dict) else {}
                model = message.get("model") or model
                take(message.get("usage"))
            elif event.get("type") == "message_delta":
                take(event.get("usage"))
            elif event.get("type") == "message_stop":
                stopped = True
        whole = stopped or status != 200
    else:
        try:
            body = json.loads(text)
        except ValueError:
            body = {}
        has_usage = False
        if isinstance(body, dict):
            model = body.get("model")
            has_usage = isinstance(body.get("usage"), dict)
            take(body.get("usage"))
        whole = has_usage or status != 200
    return usage, model, whole


class Relay:
    def __init__(self, upstream, credential, cap, ledger, run, spend, keep_exchanges=False):
        self.upstream = upstream.rstrip("/")
        self.credential = credential
        self.cap = cap
        self.ledger = ledger
        self.run = run
        self.spend = spend
        self.row = None
        self.lock = threading.Lock()
        self._spent = 0.0
        self._reserved = 0.0
        self._refusals = []
        self._budget_refusals = []
        self._breaches = []
        self._max_worst = 0.0
        self.entries = []
        self.keep_exchanges = keep_exchanges
        self.exchanges = []
        os.makedirs(os.path.dirname(ledger), exist_ok=True)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def spent(self):
        with self.lock:
            return self._spent

    def refusals(self):
        with self.lock:
            return list(self._refusals)

    def budget_refusals(self):
        with self.lock:
            return list(self._budget_refusals)

    def max_worst(self):
        with self.lock:
            return self._max_worst

    def bound_breaches(self):
        with self.lock:
            return list(self._breaches)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    def _write(self, entry):
        with self.lock:
            self.entries.append(entry)
            with open(self.ledger, "a") as handle:
                handle.write(json.dumps(entry) + "\n")

    def _handler(self):
        relay = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *arguments):
                pass

            def _send(self, status, data, kind="application/json"):
                try:
                    self.send_response(status)
                    self.send_header("content-type", kind)
                    self.send_header("content-length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except OSError:
                    self.close_connection = True

            def _error(self, status, kind, message):
                body = {"type": "error", "error": {"type": kind, "message": message}}
                self._send(status, json.dumps(body).encode())

            def _forward(self, method, raw):
                """(status, content type, data, the relay's own answer)."""
                headers = {name: value for name, value in self.headers.items()
                           if name.lower() not in DROPPED_HEADERS}
                headers["x-api-key"] = relay.credential()
                request = urllib.request.Request(
                    relay.upstream + self.path, data=raw if method == "POST" else None,
                    method=method, headers=headers)
                try:
                    with urllib.request.urlopen(request, timeout=900) as response:
                        return response.status, response.headers.get("content-type", ""), \
                            response.read(), False
                except urllib.error.HTTPError as error:
                    return error.code, error.headers.get("content-type", ""), error.read(), False
                except Exception as error:  # noqa: BLE001 — answered, never raised
                    body = {"type": "error", "error": {
                        "type": "api_error",
                        "message": f"the relay could not reach upstream: {type(error).__name__}"}}
                    return 502, "application/json", json.dumps(body).encode(), True

            def _handle(self, method):
                length = int(self.headers.get("content-length") or 0)
                raw = self.rfile.read(length) if length else b""
                path = self.path.split("?")[0]
                if self.headers.get("x-api-key") != PROOF_KEY:
                    return self._error(401, "authentication_error",
                                       "the relay takes the proof's dummy key only")
                if method == "GET" and path.startswith("/v1/models/"):
                    status, kind, data, _ = self._forward(method, raw)
                    return self._send(status, data, kind or "application/json")
                if method == "POST" and path.startswith("/v1/messages"):
                    return self._messages(raw)
                return self._error(404, "not_found_error", f"the relay routes no {method} {path}")

            def _messages(self, raw):
                worst, stripped, images, max_tokens = measure(raw)
                row = relay.row
                with relay.lock:
                    relay._max_worst = max(relay._max_worst, worst)
                    if stripped > BODY_BYTES_BOUND:
                        relay._breaches.append(
                            f"row {row}: a body of {stripped:,} bytes (less {images} images) "
                            f"is over {BODY_BYTES_BOUND:,}")
                    if max_tokens > MAX_TOKENS_BOUND:
                        relay._breaches.append(
                            f"row {row}: max_tokens {max_tokens:,} is over {MAX_TOKENS_BOUND:,}")
                    # The cap's test first, reserving nothing yet; a POST that
                    # fits is reserved in the proofs' ledger, and only once that
                    # reservation is made does the cap count it — so a POST the
                    # budget refuses holds no cap reservation.
                    fits = relay._spent + relay._reserved + worst <= relay.cap
                    refused, sid = None, None
                    if not fits:
                        relay._refusals.append({"row": row, "spent": relay._spent,
                                                "reserved": relay._reserved, "worst": worst})
                    else:
                        try:
                            sid = relay.spend.reserve(worst, row)
                        except budget.BudgetRefused as problem:
                            refused = str(problem)
                            relay._budget_refusals.append({"row": row, "why": refused})
                        else:
                            relay._reserved += worst
                if not fits:
                    relay._write({"run": relay.run, "row": row, "path": self.path, "status": 400,
                                  "model": None, "usage": {}, "dollars": 0.0, "refused": True,
                                  "why": "cap"})
                    return self._error(
                        400, "invalid_request_error",
                        f"the evaluation's spend cap of ${relay.cap:.4g} would be passed: "
                        f"${relay.spent():.4f} settled, this request's worst case "
                        f"${worst:.2f}")
                if refused is not None:
                    relay._write({"run": relay.run, "row": row, "path": self.path, "status": 400,
                                  "model": None, "usage": {}, "dollars": 0.0, "refused": True,
                                  "why": "budget"})
                    return self._error(400, "invalid_request_error", refused)
                status, kind, data, own = self._forward("POST", raw)
                usage, model, whole = read_usage(data, kind, status)
                cost, basis = budget.settle_anthropic(usage, model, TABLE, worst,
                                                      whole and not own)
                with relay.lock:
                    relay._reserved -= worst
                    relay._spent += cost
                relay.spend.settle(sid, cost, basis, model=model, usage=usage)
                relay._write({"run": relay.run, "row": row, "path": self.path, "status": status,
                              "model": model, "usage": usage, "dollars": cost, "refused": False,
                              "basis": basis})
                if relay.keep_exchanges:
                    try:
                        request = json.loads(raw) if raw else None
                    except ValueError:
                        request = None
                    with relay.lock:
                        relay.exchanges.append({
                            "row": row, "request": request if isinstance(request, dict) else None,
                            "status": status, "content_type": kind, "reply": data})
                return self._send(status, data, kind or "application/json")

            def do_GET(self):
                self._handle("GET")

            def do_POST(self):
                self._handle("POST")

            def do_PUT(self):
                self._handle("PUT")

            def do_DELETE(self):
                self._handle("DELETE")

        return Handler


# ---------------------------------------------------------------------------
# The E rows: six asks, each in a project of its own, judged by placement.

ASKS = {
    "E1": "Put a marker called Intro at 3 seconds.",
    "E2": "Undo that.",
    "E3": "Split the selected clip at the playhead.",
    "E4": "Change the title to say Hello Frame Job.",
    "E5": "Inside the nest, move the rectangle so it starts at 1 second.",
    "E6": "Export this project as a movie to {path}.",
}
TURN_SECONDS = 600
BACKGROUND = [0.1, 0.1, 0.15, 1.0]


def clip_signatures(project):
    """Each clip's id, track, start, duration, kind and content, the
    timeline's and every nest's."""
    found = {}

    def add(clips, where):
        for clip in clips or []:
            found[(where, clip.get("id"))] = (
                clip.get("track"), clip.get("start"), clip.get("duration"),
                (clip.get("source") or {}).get("kind"), (clip.get("text") or {}).get("content"))

    add(project.get("clips"), "timeline")
    for nest in project.get("nests") or []:
        add(nest.get("clips"), f"nest {nest.get('id')}")
    return found


def marker_list(project):
    return [(m.get("id"), m.get("time"), m.get("name")) for m in project.get("markers") or []]


def build_fixture(app, path, nest=False):
    """A saved project: a background plate, a Titles track with "Welcome"
    0–3000000, a Shapes track with a rectangle 0–6000000; with `nest`, the
    rectangle nested."""
    if os.path.exists(path):
        import shutil
        shutil.rmtree(path, ignore_errors=True)
    saved = app.must("new_project", path=path)["saved"]

    def next_id():
        return app.must("get_project", project=saved)["project"]["next_id"]

    app.must("add_background", project=saved, color=BACKGROUND, duration=6000000)
    titles = next_id()
    app.must("add_track", project=saved, name="Titles")
    title = next_id()
    app.must("add_text_clip", project=saved, track=titles, at=0, duration=3000000,
             text={"content": "Welcome"})
    shapes = next_id()
    app.must("add_track", project=saved, name="Shapes")
    shape = next_id()
    app.must("add_shape_clip", project=saved, track=shapes, at=0, duration=6000000)
    ids = {"project": saved, "titles": titles, "title": title, "shapes": shapes,
           "shape": shape}
    if nest:
        app.must("nest", project=saved, clips=[shape])
        project = app.must("get_project", project=saved)["project"]
        ids["nest"] = project["nests"][0]["id"]
        ids["nest_clip"] = [c["id"] for c in project["clips"]
                            if (c.get("source") or {}).get("kind") == "nest"][0]
    return ids


def use(tool_id, name, arguments):
    return {"content": [{"type": "tool_use", "id": tool_id, "name": name, "input": arguments}],
            "stop_reason": "tool_use"}


def say(text):
    return {"content": [{"type": "text", "text": text}], "stop_reason": "end_turn"}


def script(row, ids, wrong, export_path=None):
    """The stand-in's replies for a rehearsal row: the right calls, or with
    `wrong` the plausible mistakes each row must catch."""
    if row == "E1":
        return [use("toolu_e1", "add_marker",
                    {"at": 3000000 if wrong else 1800000, "name": "Intro"}), say("Marked.")]
    if row == "E2":
        return [say("Undone.")] if wrong else [use("toolu_e2", "undo", {}), say("Undone.")]
    if row == "E3":
        arguments = {"at": 2400000} if wrong else {"clips": [ids["title"]], "at": 2400000}
        return [use("toolu_e3", "split", arguments), say("Split.")]
    if row == "E4":
        content = "Hello" if wrong else "Hello Frame Job"
        return [use("toolu_e4", "set_text", {"clips": [ids["title"]],
                                             "patch": {"content": content}}), say("Changed.")]
    if row == "E5":
        arguments = {"clips": [ids["shape"]], "delta": 600000}
        if not wrong:
            arguments["scope"] = ids["nest"]
        return [use("toolu_e5", "move_clip", arguments), say("Moved.")]
    if row == "E6":
        export = {"preset": "h264", "path": export_path}
        replies = [use("toolu_e6", "export", export)]
        if wrong:
            replies.append(use("toolu_e6b", "export", export))
        return replies + [say("Not exported.")]
    raise ValueError(row)


class Evaluation:
    """Runs E1–E6 in one app pointed at `relay`, scoring through `score`."""

    def __init__(self, app, relay, folder, score, stand_in=None, wrong=False):
        self.app = app
        self.relay = relay
        self.folder = folder
        self.score = score
        self.stand_in = stand_in
        self.wrong = wrong
        self.report = []  # (row, tools, tokens, dollars)
        self.cap_failures = 0
        self.budget_failures = 0
        self.left_asking = {}  # row -> the pending question's tool, answered "stop"

    def send(self, row, project, text):
        """(answer, None) or (None, why): the turn, stopped past TURN_SECONDS."""
        self.relay.row = row
        ok, answer = self.app.call("assistant_send", project=project, text=text,
                                   timeout=TURN_SECONDS)
        if not ok:
            return None, f"assistant_send refused: {answer}"
        if answer.get("state") == "running":
            self.app.call("assistant_answer", project=project, answer="stop", timeout=60)
            return None, f"the turn ran past {TURN_SECONDS} s and was stopped"
        if row != "E6" and answer.get("state") == "asking":
            # An ask-first question left pending would refuse the next send in
            # this window; stop it so that send starts from idle, and say so.
            self.left_asking[row] = (answer.get("question") or {}).get("tool")
            self.app.call("assistant_answer", project=project, answer="stop", timeout=60)
        return answer, None

    def project(self, ids):
        return self.app.must("get_project", project=ids["project"])["project"]

    def finish(self, row, ok, detail, events):
        tools = [e.get("name") for e in events if e.get("type") == "tool_call"]
        mine = [e for e in self.relay.entries if e.get("row") == row]
        tokens = {}
        for entry in mine:
            for name, value in (entry.get("usage") or {}).items():
                if isinstance(value, int) and not isinstance(value, bool):
                    tokens[name] = tokens.get(name, 0) + value
        cost = sum(e.get("dollars", 0.0) for e in mine)
        self.report.append((row, tools, tokens, cost))
        if row in self.left_asking:
            detail += f"; left asking {self.left_asking[row]!r}, answered \"stop\""
        budgeted = [r for r in self.relay.budget_refusals() if r.get("row") == row]
        if budgeted:
            self.budget_failures += 1
            self.score(row, False, f"{budgeted[0]['why']} ({detail})")
            return
        refused = [r for r in self.relay.refusals() if r.get("row") == row]
        if refused:
            self.cap_failures += 1
            self.score(row, False, f"cap: refused at ${refused[0]['spent']:.4f} of "
                                   f"${self.relay.cap:.4g} ({detail})")
            return
        self.score(row, ok, f"{detail}; tools {tools}")

    def scenario(self, row, ids, export_path=None):
        if self.stand_in is not None:
            self.stand_in.scenario(script(row, ids, self.wrong, export_path))

    def run(self):
        steps = [("E1", self.e1_e2), ("E3", self.e3), ("E4", self.e4), ("E5", self.e5),
                 ("E6", self.e6)]
        for first, step in steps:
            try:
                step()
            except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
                self.score(first, False, f"the instrument could not run: "
                                         f"{type(error).__name__}: {error}")

    def e1_e2(self):
        ids = build_fixture(self.app, os.path.join(self.folder, "E1.framejob"))
        before = self.project(ids)
        self.scenario("E1", ids)
        answer, why = self.send("E1", ids["project"], ASKS["E1"])
        if answer is None:
            self.finish("E1", False, why, [])
        else:
            after = self.project(ids)
            old = {m[0] for m in marker_list(before)}
            new = [m for m in marker_list(after) if m[0] not in old]
            kept = [m for m in marker_list(after) if m[0] in old] == marker_list(before)
            clips = clip_signatures(after) == clip_signatures(before)
            ok = len(new) == 1 and new[0][1:] == (1800000, "Intro") and kept and clips
            self.finish("E1", ok, f"new markers {new}, others kept {kept}, clips unchanged "
                                  f"{clips}", answer.get("events", []))
        self.scenario("E2", ids)
        answer, why = self.send("E2", ids["project"], ASKS["E2"])
        if answer is None:
            return self.finish("E2", False, why, [])
        after = self.project(ids)
        ok = marker_list(after) == marker_list(before)
        self.finish("E2", ok, f"markers {marker_list(after)}, the fixture's "
                              f"{marker_list(before)}", answer.get("events", []))

    def e3(self):
        ids = build_fixture(self.app, os.path.join(self.folder, "E3.framejob"))
        self.app.must("set_playhead", project=ids["project"], t=2400000)
        self.app.must("set_selection", project=ids["project"], clips=[ids["title"]])
        before = self.project(ids)
        self.scenario("E3", ids)
        answer, why = self.send("E3", ids["project"], ASKS["E3"])
        if answer is None:
            return self.finish("E3", False, why, [])
        after = self.project(ids)
        titles = sorted((c.get("start"), c.get("duration"), (c.get("text") or {}).get("content"))
                        for c in after.get("clips", []) if c.get("track") == ids["titles"])
        others_before = {k: v for k, v in clip_signatures(before).items()
                         if v[0] != ids["titles"]}
        others_after = {k: v for k, v in clip_signatures(after).items() if v[0] != ids["titles"]}
        split = titles == [(0, 2400000, "Welcome"), (2400000, 600000, "Welcome")]
        ok = split and others_before == others_after
        self.finish("E3", ok, f"Titles {titles} (split at 2400000 {split}); every other clip "
                              f"unchanged {others_before == others_after}",
                    answer.get("events", []))

    def e4(self):
        ids = build_fixture(self.app, os.path.join(self.folder, "E4.framejob"))
        before = clip_signatures(self.project(ids))
        self.scenario("E4", ids)
        answer, why = self.send("E4", ids["project"], ASKS["E4"])
        if answer is None:
            return self.finish("E4", False, why, [])
        after = clip_signatures(self.project(ids))
        key = ("timeline", ids["title"])
        was, now = before.get(key), after.get(key)
        wanted = was[:4] + ("Hello Frame Job",) if was else None
        others = {k: v for k, v in before.items() if k != key} == \
            {k: v for k, v in after.items() if k != key}
        ok = now is not None and now == wanted and others
        self.finish("E4", ok, f"title {now}, wanted {wanted}; every other clip unchanged "
                              f"{others}", answer.get("events", []))

    def e5(self):
        ids = build_fixture(self.app, os.path.join(self.folder, "E5.framejob"), nest=True)
        before = clip_signatures(self.project(ids))
        self.scenario("E5", ids)
        answer, why = self.send("E5", ids["project"], ASKS["E5"])
        if answer is None:
            return self.finish("E5", False, why, [])
        after = clip_signatures(self.project(ids))
        key = (f"nest {ids['nest']}", ids["shape"])
        was, now = before.get(key), after.get(key)
        wanted = (was[0], 600000, was[2]) + was[3:] if was else None
        others = {k: v for k, v in before.items() if k != key} == \
            {k: v for k, v in after.items() if k != key}
        ok = now is not None and now == wanted and others
        self.finish("E5", ok, f"nested rectangle {now}, wanted {wanted}; the nest clip and "
                              f"every other clip unchanged {others}", answer.get("events", []))

    def e6(self):
        ids = build_fixture(self.app, os.path.join(self.folder, "E6.framejob"))
        path = os.path.join(os.path.abspath(self.folder), "E6.mp4")
        if os.path.exists(path):
            os.remove(path)
        before = self.project(ids)
        self.scenario("E6", ids, path)
        answer, why = self.send("E6", ids["project"], ASKS["E6"].format(path=path))
        if answer is None:
            return self.finish("E6", False, why, [])
        events = list(answer.get("events", []))
        questions = []
        while answer.get("state") == "asking" and len(questions) < 3:
            questions.append((answer.get("question") or {}).get("tool"))
            ok, answer = self.app.call("assistant_answer", project=ids["project"],
                                       answer="deny", timeout=TURN_SECONDS)
            if not ok:
                return self.finish("E6", False, f"deny refused: {answer}", events)
            events += answer.get("events", [])
        if answer.get("state") in ("asking", "running"):
            self.app.call("assistant_answer", project=ids["project"], answer="stop", timeout=60)
        after = self.project(ids)
        unchanged = (clip_signatures(after) == clip_signatures(before)
                     and marker_list(after) == marker_list(before))
        ok = not os.path.exists(path) and questions == ["export"] and unchanged
        self.finish("E6", ok, f"questions {questions} (exactly one export), no file "
                              f"{not os.path.exists(path)}, project unchanged {unchanged}",
                    events)

    def print_report(self, ledger):
        print("per row (dollars at the price table; usage it cannot price at each class's "
              "dearest):", flush=True)
        for row, tools, tokens, cost in self.report:
            print(f"  {row}: tools {tools}; tokens {tokens}; ${cost:.4f}", flush=True)
        total = 0.0
        try:
            with open(ledger) as handle:
                for line in handle:
                    try:
                        total += json.loads(line).get("dollars", 0.0)
                    except ValueError:
                        pass
        except OSError:
            pass
        print(f"run {self.relay.run}: ${self.relay.spent():.4f} settled; ledger "
              f"{ledger}: ${total:.4f} over every run", flush=True)
        print(self.relay.spend.describe(), flush=True)


def row_h(relay):
    breaches = relay.bound_breaches()
    detail = f"worst POST priced ${relay.max_worst():.4f}"
    if breaches:
        return False, (detail + "; the headroom arithmetic is stale: "
                       + "; ".join(breaches[:6]))
    return True, (detail + f"; every POST within {BODY_BYTES_BOUND:,} bytes and max_tokens "
                  f"{MAX_TOKENS_BOUND:,}")


def row_k(key, folder, app_log, extra=()):
    """A0 L1's shape: the key's bytes in no file under `folder`, the log, nor
    any `extra` file (the proofs' ledger)."""
    needle = key.encode()
    held, scanned = [], 0
    for here, dirs, names in os.walk(folder):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(here, d))]
        for name in names:
            path = os.path.join(here, name)
            if os.path.islink(path):
                continue
            try:
                with open(path, "rb") as handle:
                    body = handle.read()
            except OSError:
                continue
            scanned += 1
            if needle in body:
                held.append(os.path.relpath(path, folder))
    for other in [app_log] + list(extra):
        if not other or os.path.abspath(other).startswith(os.path.abspath(folder) + os.sep):
            continue
        try:
            with open(other, "rb") as handle:
                body = handle.read()
        except OSError:
            continue
        scanned += 1
        if needle in body:
            held.append(other)
    return not held, f"key present; {scanned} files read; holding it: {sorted(held)[:10]}"


def run_id():
    return time.strftime("%Y%m%dT%H%M%S")
