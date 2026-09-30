#!/usr/bin/env python3
"""The helper prices every response — road map 13 P2 (spec §11 P-2, P-4, P-5).

The Release helper, driven over stdio against `anthropic_fake.py` and a local
price feed (`assistant_helper_proof`'s `Helper` and `configure`):
  H1  no cache: `prices` bundled, `as_of` anthropic.json's commit date, the
      problem "no price cache is configured"; one `cost` per POST, equal to
      prices.py's answer at the bundled table
  H2  fetch: one GET, the cache written; sent only after the `prices` event
      (fetched), the reply costs $0.001 (the feed's opus input is $8/MTok)
  H3  the same cache: `prices` cached, as of the cache's `fetched_at`, no GET
  H4  the cache aged 25 h and the feed dead: cached, with a `fetching` problem,
      the cache unchanged
  H5  a feed without claude-fable-5-1: bundled, the problem names it, no cache
  H6  `http://example.invalid/`: refused by name, no cache
  H7  compaction: the `cost` count equals the POST count
  H8  `claude-proof-model`: `cost` unknown, cause `model`
  H9  the turn's prices: over a feed that holds its answer, a two-reply turn's
      first `cost` is bundled; the GET is released and `prices` (fetched)
      arrives; the tool call is answered and the turn's second `cost` is still
      bundled; the next turn's `cost` is fetched
The Release app (`assistant_session_proof`'s `App`, `Fake`, `secret_folder`;
`assistant_tab_proof`'s `Dump` and `open_tab`):
  L0  no `Reelcut: ` line
  L1  `-RCSpendFolder` scratch and `-RCPriceFeed` local: a priming turn, the
      cache file within 10 s, then a two-reply pane turn whose events carry
      `cost` in its tool view and `claude-opus-5-5` nowhere; one ledger line
      per `cost` across both turns with the listed keys only, no `proof-key`
      and no message text; the last transcript entry is exactly
      `Cost: $0.0020 · Reelcut's estimate at LiteLLM prices (fetched <day>)`
  L2  the override with no `-RCSpendFolder`: bundled with the problem, the
      feed hears nothing, and the person's `spend.jsonl` and
      `anthropic-prices.json` keep their existence, size and mtime (a
      concurrent person session can fail this row; rerun)
The probe `spend_probe.swift` (over `app/Sources`, `build_probe`'s line):
  S1..S5  the line formats and `day`, the transcript's sum and resets, the
      ledger whitelist, `record`, P-5's table

    python3 tools/proof/spend_proof.py
    python3 tools/proof/spend_proof.py --mutant stale-refresh    # H2, H3 on a scratch agent/
                                                                # with REFRESH_AFTER_MS = 0:
                                                                # H3 FAILs (exit 1)
    python3 tools/proof/spend_proof.py --mutant unknown-as-zero  # S rows over a Sources copy
                                                                # rendering unknown as $0.0000:
                                                                # S1 FAILs (exit 1)

A mutant whose instrument did not build could not perform its control
(exit 2); so, by rule R (issue batch B13), could one whose named row (H3,
S1) was never scored, or that scored any row where its own comparison did
not run (a probe that printed no row, an exception caught by `guarded`, a
failed setup): `mutant <name>: the control could not be performed — <why>`,
exit 2. A caught mutant exits 1, a surviving one 0. Prints `<ID> ok|FAIL — <detail>` per row, then `n/m`. An
instrument that cannot run is a scored FAIL. No network: the feed is an
in-process `http.server` on 127.0.0.1:0, the API is the stand-in, and every
child has `ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY` popped. The only key is
the dummy `proof-key`. Rule H: only this script's processes are killed.
"""

import argparse
import copy
import datetime
import http.server
import json
import os
import shutil
import socket
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import assistant_helper_proof as ahp  # noqa: E402
import assistant_session_proof as asp  # noqa: E402
import assistant_tab_proof as atp  # noqa: E402
import bounded  # noqa: E402
import prices  # noqa: E402

WORK = os.path.join(HERE, "work", "spend")
asp.WORK = WORK  # App, Fake and the secret folder write under this proof's folder
atp.WORK = WORK  # and so do the layout dumps
AGENT = os.path.join(ROOT, "agent")
RELEASE = os.path.join(ROOT, asp.APP_PATH)
HELPER = os.path.join(RELEASE, "Contents", "Helpers", "reelcut-agent")
REDUCE_CASES = os.path.join(AGENT, "prices", "reduce_cases.json")
PROBE_SWIFT = os.path.join(HERE, "spend_probe.swift")
PERSON = os.path.expanduser("~/Library/Application Support/Reelcut")
MODEL = "claude-opus-5-5"
PROOF_MODEL = "claude-proof-model"
NO_CACHE = "no price cache is configured"
LEDGER_KEYS = {"time", "service", "model", "usage", "dollars", "unknown", "rows", "prices"}
PORT_L1, PORT_L2 = 4897, 4898
WALL_READY, WALL_TURN, WALL_CACHE, WALL_BUILD = 20, 60, 10, 900
TOLERANCE = 1e-12
PROBE_ROWS = ["S1", "S2", "S3", "S4", "S5"]


def child_env(extra=None):
    return asp.child_env(extra)


def local_day(instant):
    """`AssistantTurnCost.day`: the local date of an ISO 8601 instant, else its
    first 10 characters."""
    try:
        parsed = datetime.datetime.fromisoformat(instant.replace("Z", "+00:00"))
    except ValueError:
        return instant[:10]
    return parsed.astimezone().strftime("%Y-%m-%d")


# ---------------------------------------------------------------------------
# The local price feed.


class Feed:
    """`http.server` on 127.0.0.1:0: `/litellm.json` (the fixture's LiteLLM
    block, opus input at 8e-06), `/no-fable.json` (the same without fable) and
    `/held.json` (the first, answered only once `release()` is called)."""

    def __init__(self):
        with open(REDUCE_CASES) as f:
            litellm = json.load(f)["litellm"]
        litellm = copy.deepcopy(litellm)
        litellm["claude-opus-5-5"]["input_cost_per_token"] = 8e-06
        without = copy.deepcopy(litellm)
        del without["claude-fable-5-1"]
        self.bodies = {"/litellm.json": json.dumps(litellm).encode(),
                       "/no-fable.json": json.dumps(without).encode()}
        self.held = threading.Event()
        self.lock = threading.Lock()
        self.gets = {}
        feed = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *arguments):
                pass

            def do_GET(self):
                path = self.path.split("?")[0]
                with feed.lock:
                    feed.gets[path] = feed.gets.get(path, 0) + 1
                if path == "/held.json":
                    feed.held.wait(120)
                    body = feed.bodies["/litellm.json"]
                else:
                    body = feed.bodies.get(path)
                if body is None:
                    self.send_response(404)
                    self.send_header("content-length", "0")
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def url(self, path):
        return self.base + path

    def count(self, path=None):
        with self.lock:
            return sum(self.gets.values()) if path is None else self.gets.get(path, 0)

    def release(self):
        self.held.set()

    def stop(self):
        self.held.set()
        self.server.shutdown()
        self.server.server_close()


def dead_url():
    """A loopback URL nothing listens on."""
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return f"http://127.0.0.1:{port}/litellm.json"


# ---------------------------------------------------------------------------
# The helper rows.


def folder(name):
    path = os.path.join(WORK, "h", name)
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    return path


def start(helper_path, fake, replies, **fields):
    """A helper configured against the stand-in; answers (helper, the index
    of `prices`, the index of `ready`)."""
    fake.scenario(replies)
    helper = ahp.Helper(helper_path)
    base = {"core_tools": [], "search_guide": "", "compaction_instructions": ""}
    base.update(fields)
    helper.send(ahp.configure(fake.base, **base))
    ready = helper.wait_for("ready", WALL_READY)
    return helper, ready


def wait_prices(helper, seconds=WALL_READY):
    at = helper.wait_for("prices", seconds)
    return None if at is None else helper.events[at]


def turn(helper, text, after=None):
    """Sends `text`; answers the events from the send to its turn_finished."""
    start_at = len(helper.events) if after is None else after
    helper.send({"type": "send", "text": text})
    done = helper.wait_for("turn_finished", WALL_TURN, after=start_at)
    end = len(helper.events) if done is None else done + 1
    return helper.events[start_at:end], done is not None


def costs(events):
    return [e for e in events if e.get("type") == "cost"]


def priced_as(event, table):
    """Empty when the event's cost is prices.py's answer at `table`."""
    want = prices.price(event.get("usage"), event.get("model"), table)
    got = event.get("cost") or {}
    if got.get("kind") != want["kind"]:
        return f"kind {got.get('kind')}, prices.py {want['kind']}"
    if want["kind"] == "dollars":
        if not abs(got.get("dollars", -1) - want["dollars"]) <= TOLERANCE:
            return f"dollars {got.get('dollars')}, prices.py {want['dollars']}"
        if got.get("rows") != want["rows"]:
            return f"rows {got.get('rows')}, prices.py {want['rows']}"
    elif got.get("cause") != want["cause"]:
        return f"cause {got.get('cause')}, prices.py {want['cause']}"
    return ""


def finish(helper):
    try:
        helper.close()
    finally:
        helper.kill()


def row_h1(helper_path, fake, feed, ctx):
    table = prices.load()
    helper, ready = start(helper_path, fake, [asp.say("H1: one."), asp.say("H1: two.")])
    try:
        at = helper.find("prices")
        source = helper.events[at]["source"] if at is not None else None
        before_ready = at is not None and ready is not None and at < ready
        events, done = turn(helper, "H1 one.")
        more, done2 = turn(helper, "H1 two.")
    finally:
        finish(helper)
    sent = asp.posts(fake.log())
    found = costs(events + more)
    wrong = [priced_as(e, table) for e in found if priced_as(e, table)]
    good = (source == {"kind": "bundled", "as_of": table["litellm_commit_date"],
                       "problem": NO_CACHE}
            and before_ready and done and done2 and len(found) == len(sent) == 2 and not wrong
            and all(e["prices"] == source for e in found)
            and all(abs(e["cost"].get("dollars", -1) - 0.0006) <= TOLERANCE for e in found))
    return good, (f"prices {source} before ready {before_ready}; {len(sent)} POSTs, "
                  f"{len(found)} costs {[e['cost'].get('dollars') for e in found]}; "
                  f"prices.py disagrees {wrong or 'nowhere'}")


def row_h2(helper_path, fake, feed, ctx):
    cache = os.path.join(folder("h2"), "spend", "anthropic-prices.json")
    ctx["cache"] = cache
    url = feed.url("/litellm.json")
    gets = feed.count(url[len(feed.base):])
    helper, ready = start(helper_path, fake, [asp.say("H2.")], price_cache=cache, price_feed=url)
    try:
        event = wait_prices(helper)
        source = event and event["source"]
        written = os.path.exists(cache)
        events, done = turn(helper, "H2.")
    finally:
        finish(helper)
    fetched = feed.count("/litellm.json") - gets
    table = prices.load(cache) if written else None
    found = costs(events)
    wrong = [priced_as(e, table) for e in found if table and priced_as(e, table)]
    good = (ready is not None and source is not None and source.get("kind") == "fetched"
            and "problem" not in source and fetched == 1 and written
            and table.get("source") == url and table.get("fetched_at") == source.get("as_of")
            and done and len(found) == 1 and not wrong
            and abs(found[0]["cost"].get("dollars", -1) - 0.001) <= TOLERANCE
            and found[0]["prices"] == source)
    return good, (f"prices {source}; {fetched} GET; cache written {written} (source "
                  f"{table and table.get('source')}, fetched_at "
                  f"{table and table.get('fetched_at')}); costs "
                  f"{[(e['cost'].get('dollars'), e['prices'].get('kind')) for e in found]}; "
                  f"prices.py disagrees {wrong or 'nowhere'}")


def row_h3(helper_path, fake, feed, ctx):
    cache = ctx.get("cache")
    if not cache or not os.path.exists(cache):
        return False, "H2 left no cache"
    fetched_at = prices.load(cache).get("fetched_at")
    before = feed.count()
    helper, ready = start(helper_path, fake, [], price_cache=cache,
                          price_feed=feed.url("/litellm.json"))
    try:
        at = helper.find("prices")
        source = helper.events[at]["source"] if at is not None else None
        before_ready = at is not None and ready is not None and at < ready
        time.sleep(1.0)  # a refresh, were one started, would have asked by now
        again = [e for e in helper.events[(at or 0) + 1:] if e.get("type") == "prices"]
    finally:
        finish(helper)
    gets = feed.count() - before
    good = (source == {"kind": "cached", "as_of": fetched_at} and before_ready and gets == 0
            and not again)
    return good, (f"prices {source} before ready {before_ready}; GETs {gets}; later prices "
                  f"events {again}")


def row_h4(helper_path, fake, feed, ctx):
    cache = ctx.get("cache")
    if not cache or not os.path.exists(cache):
        return False, "H2 left no cache"
    table = prices.load(cache)
    aged = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=25))
    table["fetched_at"] = aged.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    with open(cache, "w") as f:
        json.dump(table, f)
    with open(cache, "rb") as f:
        bytes_before = f.read()
    url = dead_url()
    helper, ready = start(helper_path, fake, [], price_cache=cache, price_feed=url)
    try:
        event = wait_prices(helper)
        source = event and event["source"]
    finally:
        finish(helper)
    with open(cache, "rb") as f:
        unchanged = f.read() == bytes_before
    good = (source is not None and source.get("kind") == "cached"
            and source.get("as_of") == table["fetched_at"]
            and (source.get("problem") or "").startswith(f"fetching {url}: ") and unchanged)
    return good, f"prices {source}; the cache unchanged {unchanged}"


def row_h5(helper_path, fake, feed, ctx):
    cache = os.path.join(folder("h5"), "anthropic-prices.json")
    url = feed.url("/no-fable.json")
    helper, ready = start(helper_path, fake, [], price_cache=cache, price_feed=url)
    try:
        event = wait_prices(helper)
        source = event and event["source"]
    finally:
        finish(helper)
    written = os.path.exists(cache)
    good = (source is not None and source.get("kind") == "bundled"
            and source.get("problem", "").startswith(f"{url} was rejected: ")
            and "claude-fable-5-1" in source.get("problem", "") and not written
            and feed.count("/no-fable.json") >= 1)
    return good, f"prices {source}; cache written {written}"


def row_h6(helper_path, fake, feed, ctx):
    cache = os.path.join(folder("h6"), "anthropic-prices.json")
    url = "http://example.invalid/"
    helper, ready = start(helper_path, fake, [], price_cache=cache, price_feed=url)
    try:
        event = wait_prices(helper)
        source = event and event["source"]
    finally:
        finish(helper)
    written = os.path.exists(cache)
    want = f"the price feed {url} is neither https nor a loopback http URL"
    good = (source is not None and source.get("kind") == "bundled"
            and source.get("problem") == want and not written)
    return good, f"prices {source}; cache written {written}"


def row_h7(helper_path, fake, feed, ctx):
    replies = [asp.say("H7: the reply."), asp.say("H7: the summary."), asp.say("H7: again."),
               asp.say("H7: a spare.")]
    helper, ready = start(helper_path, fake, replies,
                          settings={"auto_compact_tokens": 1, "clear_tool_results": False})
    notes = []
    try:
        events, done = turn(helper, "H7 one.")
        started = [e for e in events if e.get("type") == "compaction_started"]
        notes.append(f"turn 1 finished {done}, compaction_started {len(started)}")
        if done and started and len(asp.posts(fake.log())) < 2:
            more, again = turn(helper, "H7 two.")
            events += more
            notes.append(f"a second send was needed; finished {again}")
    finally:
        finish(helper)
    sent = asp.posts(fake.log())
    found = costs(events)
    order = [e.get("type") for e in events
             if e.get("type") in ("cost", "message_done", "compacted", "compaction_failed")]
    summary_priced = any(order[i] == "cost" and order[i + 1] in ("compacted", "compaction_failed")
                         for i in range(len(order) - 1))
    good = bool(started) and len(sent) >= 2 and len(found) == len(sent) and summary_priced
    return good, ("; ".join(notes) + f"; {len(sent)} POSTs, {len(found)} costs; order {order}")


def row_h8(helper_path, fake, feed, ctx):
    helper, ready = start(helper_path, fake, [asp.say("H8.")], model=PROOF_MODEL)
    try:
        events, done = turn(helper, "H8.")
    finally:
        finish(helper)
    found = costs(events)
    got = [e.get("cost") for e in found]
    good = (done and len(found) == 1 and got[0].get("kind") == "unknown"
            and got[0].get("cause") == "model" and found[0].get("model") == PROOF_MODEL)
    return good, f"costs {got}"


def row_h9(helper_path, fake, feed, ctx):
    cache = os.path.join(folder("h9"), "anthropic-prices.json")
    url = feed.url("/held.json")
    schema = {"type": "object", "properties": {"at": {"type": "integer"},
                                               "name": {"type": "string"}}}
    replies = [asp.use("toolu_h9", "add_marker", {"at": 1200000, "name": "H9"}),
               asp.say("H9: done."), asp.say("H9: next turn.")]
    helper, ready = start(helper_path, fake, replies, price_cache=cache, price_feed=url,
                          tools=[{"name": "add_marker", "description": "H9 add_marker",
                                  "inputSchema": schema}], core_tools=["add_marker"])
    notes = []
    try:
        begin = len(helper.events)
        helper.send({"type": "send", "text": "H9 one."})
        first = helper.wait_for("cost", WALL_TURN, after=begin)
        request = helper.wait_for("tool_request", WALL_TURN, after=begin)
        if first is None or request is None:
            return False, f"no first cost ({first}) or tool_request ({request})"
        first_kind = helper.events[first]["prices"].get("kind")
        held = feed.count("/held.json")
        feed.release()
        event = wait_prices(helper)
        settled = event and event["source"]
        call_id = helper.events[request]["call_id"]
        helper.send({"type": "tool_result", "call_id": call_id,
                     "result": {"content": [{"type": "text", "text": "H9 marker added."}]}})
        done = helper.wait_for("turn_finished", WALL_TURN, after=begin)
        turn_one = costs(helper.events[begin:(done + 1) if done is not None else None])
        notes.append(f"first cost {first_kind} with {held} GET held; prices {settled}; turn "
                     f"one's costs {[e['prices'].get('kind') for e in turn_one]}")
        after = len(helper.events)
        events, done2 = turn(helper, "H9 two.", after=after)
        turn_two = costs(events)
        notes.append(f"turn two's costs "
                     f"{[(e['prices'].get('kind'), e['cost'].get('dollars')) for e in turn_two]}")
    finally:
        finish(helper)
    good = (first_kind == "bundled" and held == 1 and settled is not None
            and settled.get("kind") == "fetched" and done is not None and len(turn_one) == 2
            and all(e["prices"].get("kind") == "bundled" for e in turn_one)
            and done2 and len(turn_two) == 1 and turn_two[0]["prices"].get("kind") == "fetched"
            and abs(turn_two[0]["cost"].get("dollars", -1) - 0.001) <= TOLERANCE)
    return good, "; ".join(notes)


H_ROWS = [("H1", row_h1), ("H2", row_h2), ("H3", row_h3), ("H4", row_h4), ("H5", row_h5),
          ("H6", row_h6), ("H7", row_h7), ("H8", row_h8), ("H9", row_h9)]


# ---------------------------------------------------------------------------
# The app rows.


def person_state():
    """(exists, size, mtime) of the person's two spend files."""
    state = {}
    for name in ("spend.jsonl", "anthropic-prices.json"):
        path = os.path.join(PERSON, name)
        try:
            st = os.stat(path)
            state[name] = (True, st.st_size, st.st_mtime_ns)
        except FileNotFoundError:
            state[name] = (False, None, None)
    return state


def row_l1(fake, feed, secrets, score):
    spend = os.path.join(WORK, "l1", "spend", "folder")
    shutil.rmtree(os.path.dirname(os.path.dirname(spend)), ignore_errors=True)
    os.makedirs(os.path.dirname(spend))
    url = feed.url("/litellm.json")
    ctx = {"folder": os.path.join(WORK, "l1"), "dumps": []}
    app = asp.App("L1", RELEASE, ["-AgentServerEnabled", "YES", "-RCSecretFolder", secrets,
                                  "-RCSpendFolder", spend, "-RCPriceFeed", url,
                                  "-ReelcutInspectorCollapsed", "NO"], fake.base, port=PORT_L1)
    try:
        app.connect()
        complaints = [line for line in app.log().splitlines() if "Reelcut: " in line]
        score("L0", not complaints, f"`Reelcut: ` lines {complaints[:2]}")
        a = atp.open_tab(app, ctx)
        fake.scenario([asp.say("L1: priming.")])
        priming = app.must("assistant_send", project=a, text="L1 priming.",
                           timeout=WALL_TURN)
        cache = os.path.join(spend, "anthropic-prices.json")
        deadline = time.monotonic() + WALL_CACHE
        while time.monotonic() < deadline and not os.path.exists(cache):
            time.sleep(0.1)
        if not os.path.exists(cache):
            return False, f"no {cache} within {WALL_CACHE} s; priming {asp.brief(priming)}"
        fetched_at = prices.load(cache).get("fetched_at", "")
        fake.scenario([asp.use("toolu_l1", "add_marker", {"at": 1200000, "name": "L1 marker"}),
                       asp.say("L1: the marker is in.")])
        measured = app.must("assistant_send", project=a, text="L1 put a marker in.",
                            pane=True, timeout=WALL_TURN)
        dump = atp.Dump(app, a, "l1")
        entries = dump.entries()
    finally:
        app.stop()
    views = costs(measured.get("events", []))
    all_costs = costs(priming.get("events", [])) + views
    shapes = sorted({tuple(sorted(v.keys())) for v in views})
    leaks = MODEL in json.dumps(measured) or MODEL in json.dumps(priming)
    ledger_path = os.path.join(spend, "spend.jsonl")
    try:
        with open(ledger_path) as f:
            text = f.read()
    except OSError as error:
        text = ""
        return False, f"no ledger: {error}"
    lines = [json.loads(line) for line in text.splitlines() if line.strip()]
    stranger_keys = sorted({k for line in lines for k in line if k not in LEDGER_KEYS})
    content = [t for t in ("L1 priming.", "L1: priming.", "L1 put a marker in.",
                           "L1: the marker is in.", asp.KEY) if t in text]
    usage = {"input_tokens": 100, "output_tokens": 10, "cache_creation_input_tokens": 0,
             "cache_read_input_tokens": 0}
    dollars = 2 * prices.price(usage, MODEL, prices.load(cache))["dollars"]
    want = (f"Cost: ${dollars:.4f} · Reelcut's estimate at LiteLLM prices "
            f"(fetched {local_day(fetched_at)})")
    last = entries[-1] if entries else None
    good = (measured.get("state") == "finished" and len(views) == 2
            and shapes == [("cost", "prices", "type")] and not leaks
            and len(lines) == len(all_costs) and not stranger_keys and not content
            and last == ("meta", want))
    return good, (f"priming {priming.get('state')}, measured {asp.brief(measured)}; tool-view "
                  f"costs {[v.get('cost') for v in views]} shapes {shapes}; {MODEL} in the "
                  f"answers {leaks}; {len(lines)} ledger lines for {len(all_costs)} costs, "
                  f"stranger keys {stranger_keys}, content {content}; last entry {last!r}; "
                  f"wanted {want!r}")


def row_l2(fake, feed, secrets):
    before = person_state()
    gets = feed.count()
    app = asp.App("L2", RELEASE, ["-AgentServerEnabled", "YES", "-RCSecretFolder", secrets,
                                  "-RCPriceFeed", feed.url("/litellm.json")], fake.base,
                  port=PORT_L2)
    try:
        app.connect()
        complaints = [line for line in app.log().splitlines() if "Reelcut: " in line]
        a = app.must("new_project", path=os.path.join(WORK, "l2.reelcut"))["saved"]
        fake.scenario([asp.say("L2.")])
        answer = app.must("assistant_send", project=a, text="L2.", timeout=WALL_TURN)
        time.sleep(1.0)
    finally:
        app.stop()
    found = costs(answer.get("events", []))
    table = prices.load()
    heard = feed.count() - gets
    after = person_state()
    good = (not complaints and len(found) == 1
            and found[0].get("prices") == {"kind": "bundled", "as_of": table["litellm_commit_date"],
                                           "problem": NO_CACHE}
            and heard == 0 and after == before)
    return good, (f"`Reelcut: ` {complaints[:1]}; costs {found}; feed GETs {heard}; person's "
                  f"files before {before}, after {after}")


# ---------------------------------------------------------------------------
# The probe.


def rows_s(score, sources=None, label=""):
    """Builds and runs the probe over `sources` (app/Sources by default)."""
    probe_dir = os.path.join(WORK, "probe" if sources is None else "mutant-probe")
    atp.PROBE_DIR = probe_dir
    atp.PROBE_SWIFT = PROBE_SWIFT
    atp.SOURCES = sources or os.path.join(ROOT, "app", "Sources")
    # Passed, not left to the defaults: `build_probe`'s defaults were bound
    # when assistant_tab_proof was imported, so the two assignments above do
    # not reach them (issue batch B13).
    binary, why = atp.build_probe(atp.SOURCES, probe_dir)
    if binary is None:
        for row_id in PROBE_ROWS:
            score(row_id, False, f"the probe did not build: {why}", instrument=True)
        return False
    scratch = os.path.join(WORK, "probe-scratch")
    shutil.rmtree(scratch, ignore_errors=True)
    os.makedirs(scratch)
    ran = bounded.run([binary, scratch], atp.WALL_RUN, cwd=probe_dir, env=child_env())
    answer = None
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            answer = json.loads(line[len("ANSWER "):])
    got = {r["id"]: r for r in (answer or {}).get("rows", [])}
    for row_id in PROBE_ROWS:
        r = got.get(row_id)
        if r is None:
            score(row_id, False, f"no row (exit {ran['rc']}, expired {ran['expired']}): "
                                 f"{ran['stderr'].strip()[-300:]}", instrument=True)
        else:
            score(row_id, bool(r["ok"]), label + r["detail"])
    return True


# ---------------------------------------------------------------------------
# The mutants.


def stale_helper():
    """(helper path, None) or (None, reason): a scratch agent/ with
    REFRESH_AFTER_MS = 0, built by its own build.sh into a scratch bundle."""
    base = os.path.join(WORK, "stale-refresh")
    shutil.rmtree(base, ignore_errors=True)
    scratch = os.path.join(base, "agent")
    shutil.copytree(AGENT, scratch, ignore=shutil.ignore_patterns("node_modules"))
    path = os.path.join(scratch, "src", "priceTable.ts")
    with open(path) as f:
        text = f.read()
    old = "REFRESH_AFTER_MS = 86_400_000"
    if text.count(old) != 1:
        return None, f"`{old}` occurs {text.count(old)} times in priceTable.ts, not once"
    with open(path, "w") as f:
        f.write(text.replace(old, "REFRESH_AFTER_MS = 0"))
    target = os.path.join(base, "target")
    os.makedirs(target)
    built = bounded.run(["/bin/sh", os.path.join(scratch, "build.sh"), "helper"], WALL_BUILD,
                        env=child_env({"TARGET_BUILD_DIR": target,
                                       "CONTENTS_FOLDER_PATH": "Reelcut.app/Contents"}))
    helper = os.path.join(target, "Reelcut.app", "Contents", "Helpers", "reelcut-agent")
    if built["expired"] or built["rc"] != 0 or not os.path.exists(helper):
        tail = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                if line.strip()][-3:]
        return None, f"build.sh helper exit {built['rc']} (expired {built['expired']}): {tail}"
    return helper, None


def unknown_as_zero_sources():
    """(Sources path, None) or (None, reason): app/Sources copied, the cost
    line's unknown amount replaced by $0.0000."""
    base = os.path.join(WORK, "unknown-as-zero")
    shutil.rmtree(base, ignore_errors=True)
    sources = os.path.join(base, "Sources")
    shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
    path = os.path.join(sources, "AssistantSpend.swift")
    with open(path) as f:
        text = f.read()
    old = 'amount = "unknown (\\(firstUnknown))"'
    if text.count(old) != 1:
        return None, f"`{old}` occurs {text.count(old)} times in AssistantSpend.swift, not once"
    with open(path, "w") as f:
        f.write(text.replace(old, 'amount = "$0.0000"'))
    return sources, None


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=["stale-refresh", "unknown-as-zero"],
                        help="a made-to-fail variant; its named row must FAIL (exit 1)")
    args = parser.parse_args()
    os.makedirs(WORK, exist_ok=True)
    results = []

    def score(row_id, ok, detail, *, instrument=False):
        results.append((row_id, ok, instrument))
        print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    def guarded(row_id, function, *arguments):
        try:
            score(row_id, *function(*arguments))
        except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
            score(row_id, False, f"the instrument could not run: {type(error).__name__}: "
                                 f"{error}", instrument=True)

    if args.mutant == "unknown-as-zero":
        try:
            sources, why = unknown_as_zero_sources()
        except OSError as error:  # a copy that could not be made performs no control
            sources, why = None, f"the copy could not be made: {type(error).__name__}: {error}"
        built = sources is not None and rows_s(score, sources, "(unknown rendered as $0.0000) ")
        if not built:
            if sources is None:
                score("S1", False, why, instrument=True)
            print(f"mutant {args.mutant}: the control could not be performed — "
                  + (why if sources is None else "the probe did not build"), flush=True)
            return 2
    else:
        fake = feed = None
        try:
            fake = asp.Fake(os.path.join(WORK, "fake"))
            feed = Feed()
            ctx = {}
            if args.mutant == "stale-refresh":
                helper, why = stale_helper()
                if helper is None:
                    score("H3", False, f"the mutant did not build: {why}", instrument=True)
                    print(f"mutant {args.mutant}: the control could not be performed — "
                          f"the mutant did not build: {why}", flush=True)
                    return 2
                for row_id, function in H_ROWS[1:3]:
                    guarded(row_id, lambda f=function: (lambda ok, d: (
                        ok, "(REFRESH_AFTER_MS = 0) " + d))(*f(helper, fake, feed, ctx)))
            else:
                for row_id, function in H_ROWS:
                    guarded(row_id, function, HELPER, fake, feed, ctx)
                secrets = asp.secret_folder()
                guarded("L1", row_l1, fake, feed, secrets, score)
                guarded("L2", row_l2, fake, feed, secrets)
                rows_s(score)
        except Exception as error:  # noqa: BLE001
            score("setup", False, f"the instrument could not run: {type(error).__name__}: "
                                  f"{error}", instrument=True)
        finally:
            if fake is not None:
                fake.stop()
            if feed is not None:
                feed.stop()

    passed = sum(1 for _, ok, _ in results if ok)
    print(f"{passed}/{len(results)}", flush=True)
    if args.mutant:
        named = {"stale-refresh": "H3", "unknown-as-zero": "S1"}[args.mutant]
        broken = [r for r, _, instrument in results if instrument]
        why = (f"{named} was never scored" if named not in [r for r, _, _ in results] else
               f"scored as instrument failures: {', '.join(broken)}" if broken else "")
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}",
                  flush=True)
            return 2
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
