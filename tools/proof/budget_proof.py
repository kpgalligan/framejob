#!/usr/bin/env python3
"""Road map 13 P3 — the proofs' ledger and the monthly budgets (spec §11 P-3,
P-6): `budget.py`, the relay's use of it in `assistant_prompt_eval.py`, and
`LiveLedger` in `cloud_live_ledger.py`. No network, no app, no key: every
ledger here is a scratch file under `work/budget/` (made fresh), and row N
proves the real one, `budget.LEDGER`, was not created or changed.

  P   the budgets are the owner's $25 / $5; `LEDGER` is absolute and outside
      the repo; worst POST ≤ the floor ≤ `SUGGESTED_CAP` ≤ $25
  F1  the fold over a seeded file: last month's $30 counts nothing; this
      month's reserve 2 settled 0.5, open reserve 1, refused 9, orphan settle
      0.25 → $1.75; AssemblyAI's 4 settled 4 → $4.00
  F2  an absent file is $0; a line that is not JSON refuses naming the line,
      and `reserve` appends nothing
  G1  at $24.00, a $1.00 reservation passes (the edge) and $0.01 is refused
      `budget:` with exactly one `refused` line; `gate=False` still records
  G2  $25 recorded last month does not count this month (an injected clock)
  G3  a nested folder is created; the file is 0600
  W   `anthropic_worst_row` over a fixture (two rows, one tiered) is the
      per-class maximum; no committed rate exceeds it
  S1–S4  `settle_anthropic`: a known model at the table; an unknown model (and
      a fast request) at the worst row; an unknown-model iteration at the worst
      row; a malformed count and a reply that is not whole at the reservation
  U1  `read_usage` keeps every key, overlays `message_delta`, and a stream
      with no `message_stop` or a body with no `usage` is not whole
  U2  `Evaluation.finish` totals only integer usage values
  R1–R4  the relay over the stand-in: forwarded and settled $0.0006 at the
      table; two POSTs refused by the budget with no cap reservation leaked;
      a cap refusal writes no proofs'-ledger line; a dead upstream settles
      at the reservation
  A1  `assemblyai_rates()` reads `AssemblyAIRates`; a copy without the
      `static let perHour` line is a ValueError
  A2  `cloud_live_ledger`'s budget CONTROL holds
  A3  `LiveLedger` settles `billed` and `no_upload`; the month total is their sum
  N   `budget.LEDGER`'s existence, size and mtime unchanged

    python3 tools/proof/budget_proof.py                          # every row ok (make test)
    python3 tools/proof/budget_proof.py --mutant no-budget       # P G1 R2 A2 FAIL, exit 1
    python3 tools/proof/budget_proof.py --mutant unknown-as-zero # W S2 S3 FAIL, exit 1

`no-budget` sets both budgets to infinity in memory; `unknown-as-zero`
replaces `budget.anthropic_worst_row` with all-zero rates after import.
Prints `<ID> ok|FAIL — detail`, then `n/m`; an instrument that cannot run is
a FAIL.
"""

import argparse
import datetime
import json
import math
import os
import shutil
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "cloud_spike"))

WORK = os.path.join(HERE, "work", "budget")
UTC = datetime.timezone.utc
SEPTEMBER = datetime.datetime(2026, 9, 15, 12, 0, 0, tzinfo=UTC)
AUGUST = datetime.datetime(2026, 8, 31, 23, 59, 0, tzinfo=UTC)
ROWS = ["P", "F1", "F2", "G1", "G2", "G3", "W", "S1", "S2", "S3", "S4", "U1", "U2",
        "R1", "R2", "R3", "R4", "A1", "A2", "A3", "N"]
RESULTS = []


def score(row, ok, detail):
    state = "ok" if ok else "FAIL"
    RESULTS.append((row, state))
    print(f"{row} {state} — {detail}", flush=True)


def guarded(row, function, *arguments):
    try:
        score(row, *function(*arguments))
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        score(row, False, f"the instrument could not run: {type(error).__name__}: {error}")


def at(when):
    return lambda: when


def lines_of(path):
    if not os.path.exists(path):
        return []
    with open(path) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def kinds(path, kind):
    return [e for e in lines_of(path) if e.get("kind") == kind]


def scratch(*parts):
    path = os.path.join(WORK, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        os.remove(path)
    return path


def snapshot(path):
    try:
        info = os.stat(path)
        return True, info.st_size, info.st_mtime_ns
    except OSError:
        return False, None, None


def independent_worst(table):
    """The per-class maximum over every row and tier, written here without
    `budget.py`, so a broken `anthropic_worst_row` cannot agree with itself."""
    worst = {}
    for row in table["models"].values():
        for tier in (row, row.get("above_200k") or {}):
            for key in ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output"):
                rate = tier.get(key)
                if isinstance(rate, (int, float)) and not isinstance(rate, bool):
                    worst[key] = max(worst.get(key, 0.0), float(rate))
    return worst


# ---------------------------------------------------------------------------
# The rows.


def row_p(budget, ev):
    floor = (ev.worst_post(), ev.cap_floor(), ev.SUGGESTED_CAP)
    absolute = os.path.isabs(budget.LEDGER)
    outside = not os.path.abspath(budget.LEDGER).startswith(ROOT + os.sep)
    budgets = budget.BUDGETS == {"anthropic": 25.00, "assemblyai": 5.00}
    ordered = floor[0] <= floor[1] <= floor[2] <= 25.00
    return budgets and absolute and outside and ordered, (
        f"BUDGETS {budget.BUDGETS}; LEDGER {budget.LEDGER} absolute {absolute}, outside the "
        f"repo {outside}; worst POST ${floor[0]:.2f} ≤ floor ${floor[1]:.2f} ≤ suggested cap "
        f"${floor[2]:.2f} ≤ $25 {ordered}")


def seed_lines(path, entries):
    with open(path, "w") as handle:
        for entry in entries:
            handle.write(json.dumps(dict({"format": 1}, **entry)) + "\n")


def row_f1(budget):
    path = scratch("f1", "spend.jsonl")
    sep, aug = "2026-09-10T10:00:00Z", "2026-08-20T10:00:00Z"
    common = {"proof": "p", "run": "r"}
    seed_lines(path, [
        dict(at=aug, service="anthropic", kind="reserve", id="old", row="x", worst=30.0, **common),
        dict(at=aug, service="anthropic", kind="settle", id="old", dollars=30.0, basis="table"),
        dict(at=sep, service="anthropic", kind="reserve", id="a", row="x", worst=2.0, **common),
        dict(at=sep, service="anthropic", kind="settle", id="a", dollars=0.5, basis="table"),
        dict(at=sep, service="anthropic", kind="reserve", id="b", row="x", worst=1.0, **common),
        dict(at=sep, service="anthropic", kind="refused", id="c", row="x", worst=9.0,
             month_total=1.5, budget=25.0, **common),
        dict(at=sep, service="anthropic", kind="settle", id="orphan", dollars=0.25,
             basis="table"),
        dict(at=sep, service="assemblyai", kind="reserve", id="d", row="x", worst=4.0, **common),
        dict(at=sep, service="assemblyai", kind="settle", id="d", dollars=4.0, basis="billed",
             seconds=1),
    ])
    anthropic = budget.SpendLedger(path, "anthropic", "budget_proof", "f1", now=at(SEPTEMBER))
    assemblyai = budget.SpendLedger(path, "assemblyai", "budget_proof", "f1",
                                    now=at(SEPTEMBER))
    got = (anthropic.month_total(), assemblyai.month_total())
    ok = abs(got[0] - 1.75) < 1e-9 and abs(got[1] - 4.0) < 1e-9
    return ok, f"anthropic ${got[0]:.4f} (want 1.75), assemblyai ${got[1]:.4f} (want 4.00)"


def row_f2(budget):
    path = scratch("f2", "spend.jsonl")
    spend = budget.SpendLedger(path, "anthropic", "budget_proof", "f2", now=at(SEPTEMBER))
    absent = spend.month_total()
    seed_lines(path, [dict(at="2026-09-10T10:00:00Z", service="anthropic", kind="reserve",
                           id="a", proof="p", run="r", row="x", worst=1.0)])
    with open(path, "a") as handle:
        handle.write("not json\n")  # line 2
    size = os.path.getsize(path)
    try:
        spend.month_total()
        read = None
    except budget.BudgetRefused as refused:
        read = str(refused)
    try:
        spend.reserve(0.01, "f2")
        reserved = None
    except budget.BudgetRefused as refused:
        reserved = str(refused)
    unchanged = os.path.getsize(path) == size
    ok = (absent == 0.0 and read is not None and read.startswith("budget: ")
          and "line 2" in read and reserved is not None and unchanged)
    return ok, (f"absent ${absent}; the fold: {read!r:.200}; reserve refused "
                f"{reserved is not None}; the file unchanged {unchanged}")


def row_g1(budget):
    path = scratch("g1", "spend.jsonl")
    spend = budget.SpendLedger(path, "anthropic", "budget_proof", "g1", now=at(SEPTEMBER))
    seed = spend.reserve(24.00, "seed", gate=False)
    spend.settle(seed, 24.00, "seed")
    try:
        spend.reserve(1.00, "edge")
        edge = True
    except budget.BudgetRefused:
        edge = False
    try:
        spend.reserve(0.01, "past")
        past = None
    except budget.BudgetRefused as refused:
        past = str(refused)
    refused_lines = len(kinds(path, "refused"))
    before = len(kinds(path, "reserve"))
    spend.reserve(5.00, "recorded", gate=False)
    recorded = len(kinds(path, "reserve")) - before
    ok = (edge and past is not None and past.startswith("budget: ") and refused_lines == 1
          and recorded == 1)
    return ok, (f"$1.00 at $24.00 passes {edge}; $0.01 at $25.00: {past!r:.220}; refused "
                f"lines {refused_lines}; gate=False recorded {recorded}")


def row_g2(budget):
    path = scratch("g2", "spend.jsonl")
    clock = {"now": AUGUST}
    spend = budget.SpendLedger(path, "anthropic", "budget_proof", "g2",
                               now=lambda: clock["now"])
    seed = spend.reserve(25.00, "august", gate=False)
    spend.settle(seed, 25.00, "seed")
    august = (spend.month(), spend.month_total())
    clock["now"] = SEPTEMBER
    september = (spend.month(), spend.month_total(), spend.refusal(1.00))
    ok = (august == ("2026-08", 25.0) and september[:2] == ("2026-09", 0.0)
          and september[2] is None)
    return ok, f"August {august}; September {september}"


def row_g3(budget):
    base = os.path.join(WORK, "g3")
    shutil.rmtree(base, ignore_errors=True)
    path = os.path.join(base, "a", "b", "spend.jsonl")
    spend = budget.SpendLedger(path, "anthropic", "budget_proof", "g3", now=at(SEPTEMBER))
    spend.reserve(0.01, "g3")
    mode = os.stat(path).st_mode & 0o777
    folder = os.stat(os.path.dirname(path)).st_mode & 0o777
    return mode == 0o600 and folder == 0o700, (f"file {oct(mode)} (want 0o600), its folder "
                                              f"{oct(folder)} (want 0o700)")


def row_w(budget, prices):
    fixture = {"models": {
        "a": {"input": 1.0, "cache_write_5m": 2.0, "cache_write_1h": 3.0, "cache_read": 0.1,
              "output": 5.0},
        "b": {"input": 2.0, "cache_write_5m": 1.0, "cache_write_1h": 2.0, "cache_read": 0.2,
              "output": 4.0,
              "above_200k": {"input": 4.0, "cache_write_5m": 2.5, "cache_write_1h": 2.0,
                             "cache_read": 0.05, "output": 6.0}}}}
    want = {"input": 4.0, "cache_write_5m": 2.5, "cache_write_1h": 3.0, "cache_read": 0.2,
            "output": 6.0}
    got = budget.anthropic_worst_row(fixture)
    table = prices.load()
    worst = budget.anthropic_worst_row(table)
    over = []
    for name, row in table["models"].items():
        for tier in (row, row.get("above_200k") or {}):
            for key, rate in tier.items():
                if key in worst and rate > worst[key]:
                    over.append(f"{name} {key} {rate} > {worst[key]}")
    ok = got == want and not over and worst == independent_worst(table)
    return ok, f"fixture {got}; the committed table's {worst}; over it {over[:3]}"


def row_s1(budget, prices):
    table = prices.load()
    usage = {"input_tokens": 1000, "output_tokens": 100}
    want = prices.price(usage, "claude-opus-5-5", table)["dollars"]
    got = budget.settle_anthropic(usage, "claude-opus-5-5", table, 9.0, True)
    return got == (want, "table"), f"{got} (want ({want}, 'table'))"


def row_s2(budget, prices):
    table = prices.load()
    worst = independent_worst(table)
    usage = {"input_tokens": 1000, "cache_creation_input_tokens": 2000,
             "cache_read_input_tokens": 3000, "output_tokens": 100}
    want = (1000 * worst["input"] + 2000 * worst["cache_write_5m"]
            + 3000 * worst["cache_read"] + 100 * worst["output"]) / 1_000_000
    unknown = budget.settle_anthropic(usage, "claude-unpriced-9", table, 9.0, True)
    fast = budget.settle_anthropic(dict(usage, speed="fast"), "claude-opus-5-5", table, 9.0, True)
    ok = (unknown[1] == "worst" and abs(unknown[0] - want) < 1e-12
          and fast[1] == "worst" and abs(fast[0] - want) < 1e-12)
    return ok, f"unknown model {unknown}, fast {fast} (want ({want}, 'worst'))"


def row_s3(budget, prices):
    table = prices.load()
    worst = independent_worst(table)
    usage = {"input_tokens": 200, "output_tokens": 20, "iterations": [
        {"model": "claude-opus-5-5", "input_tokens": 100, "output_tokens": 10},
        {"model": "claude-unpriced-9", "input_tokens": 200, "output_tokens": 20}]}
    want = ((100 * worst["input"] + 10 * worst["output"]) / 1_000_000
            + (200 * worst["input"] + 20 * worst["output"]) / 1_000_000)
    got = budget.settle_anthropic(usage, "claude-opus-5-5", table, 9.0, True)
    ok = got[1] == "worst" and abs(got[0] - want) < 1e-12
    return ok, f"{got} (want ({want}, 'worst'))"


def row_s4(budget, prices):
    table = prices.load()
    malformed = budget.settle_anthropic({"input_tokens": -1}, "claude-opus-5-5", table, 1.25,
                                        True)
    torn = budget.settle_anthropic({"input_tokens": 100}, "claude-opus-5-5", table, 1.25, False)
    ok = malformed == (1.25, "reserved") and torn == (1.25, "reserved")
    return ok, f"a malformed count {malformed}; not whole {torn} (want (1.25, 'reserved'))"


def stream(events):
    return "".join(f"event: {e['type']}\ndata: {json.dumps(e)}\n\n" for e in events).encode()


def row_u1(ev):
    start = {"type": "message_start", "message": {"model": "claude-opus-5-5", "usage": {
        "input_tokens": 100, "output_tokens": 1, "service_tier": "standard",
        "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}}}}
    delta = {"type": "message_delta", "usage": {"output_tokens": 10}}
    whole = ev.read_usage(stream([start, delta, {"type": "message_stop"}]), "text/event-stream")
    cut = ev.read_usage(stream([start, delta]), "text/event-stream")
    body = ev.read_usage(json.dumps({"model": "claude-opus-5-5", "usage": {
        "input_tokens": 5, "output_tokens": 2}}).encode(), "application/json")
    bare = ev.read_usage(json.dumps({"model": "claude-opus-5-5"}).encode(), "application/json")
    usage = whole[0]
    ok = (usage.get("output_tokens") == 10 and usage.get("input_tokens") == 100
          and usage.get("service_tier") == "standard"
          and isinstance(usage.get("cache_creation"), dict)
          and whole[1] == "claude-opus-5-5" and whole[2] is True and cut[2] is False
          and body == ({"input_tokens": 5, "output_tokens": 2}, "claude-opus-5-5", True)
          and bare[2] is False)
    return ok, (f"stream {whole}; no message_stop whole {cut[2]}; JSON {body}; no usage "
                f"whole {bare[2]}")


class StubRelay:
    def __init__(self, entries):
        self.entries = entries
        self.cap = 1.0

    def refusals(self):
        return []

    def budget_refusals(self):
        return []


def row_u2(ev):
    usage = {"input_tokens": 100, "output_tokens": 10, "service_tier": "standard",
             "cache_creation": {"ephemeral_5m_input_tokens": 0}, "x": True}
    scored = []
    evaluation = ev.Evaluation(None, StubRelay([{"row": "E1", "usage": usage,
                                                 "dollars": 0.0006}]),
                               WORK, lambda row, ok, detail: scored.append((row, ok)))
    evaluation.finish("E1", True, "d", [])
    tokens = evaluation.report[0][2]
    ok = tokens == {"input_tokens": 100, "output_tokens": 10} and scored == [("E1", True)]
    return ok, f"tokens {tokens}; scored {scored}"


# ---------------------------------------------------------------------------
# R: the relay over the stand-in.


def post(base, body):
    raw = json.dumps(body).encode()
    request = urllib.request.Request(base + "/v1/messages", data=raw, method="POST",
                                     headers={"content-type": "application/json",
                                              "x-api-key": "proof-key"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read(), raw
    except urllib.error.HTTPError as error:
        return error.code, error.read(), raw


def stand_in_posts(fake):
    return len([r for r in fake.log().get("requests", [])
                if r.get("method") == "POST" and r.get("path", "").startswith("/v1/messages")])


def message(budget_word):
    return {"model": "claude-opus-5-5", "max_tokens": 1000, "stream": True,
            "messages": [{"role": "user", "content": f"R: {budget_word}"}]}


def error_text(data):
    try:
        return json.loads(data)["error"]["message"]
    except (ValueError, KeyError, TypeError):
        return data[:200]


def relay_for(budget, ev, upstream, cap, name, seeded=None):
    spend = budget.SpendLedger(scratch(name, "spend.jsonl"), "anthropic", "budget_proof", name,
                               now=at(SEPTEMBER))
    if seeded is not None:
        seed = spend.reserve(seeded, "seed", gate=False)
        spend.settle(seed, seeded, "seed")
    relay = ev.Relay(upstream, lambda: ev.PROOF_KEY, cap, scratch(name, "ledger.jsonl"), name,
                     spend)
    relay.row = name
    return relay, spend


def row_r1(budget, ev, fake):
    relay, spend = relay_for(budget, ev, fake.base, 10.0, "R1")
    try:
        before = stand_in_posts(fake)
        status, data, raw = post(relay.base, message("forward"))
        worst = ev.measure(raw)[0]
        forwarded = stand_in_posts(fake) - before
    finally:
        relay.stop()
    reserves, settles = kinds(spend.path, "reserve"), kinds(spend.path, "settle")
    ok = (status == 200 and forwarded == 1 and len(reserves) == 1 and len(settles) == 1
          and abs(reserves[0]["worst"] - worst) < 1e-12
          and abs(settles[0]["dollars"] - 0.0006) < 1e-12 and settles[0]["basis"] == "table"
          and settles[0]["id"] == reserves[0]["id"] and settles[0].get("model")
          == "claude-opus-5-5")
    return ok, (f"status {status}, {forwarded} forwarded; reserved "
                f"{[r['worst'] for r in reserves]} (measure ${worst:.6f}); settled "
                f"{[(s['dollars'], s['basis'], s.get('usage')) for s in settles]}")


def row_r2(budget, ev, fake):
    worst = ev.measure(json.dumps(message("refused")).encode())[0]
    relay, spend = relay_for(budget, ev, fake.base, 1.5 * worst, "R2", seeded=24.999)
    try:
        before = stand_in_posts(fake)
        answers = [post(relay.base, message("refused")) for _ in range(2)]
        sent = stand_in_posts(fake) - before
        leaked = relay._reserved
        caps, budgets = relay.refusals(), relay.budget_refusals()
    finally:
        relay.stop()
    texts = [error_text(data) for _, data, _ in answers]
    refused_lines = len(kinds(spend.path, "refused"))
    ok = (all(status == 400 for status, _, _ in answers)
          and all(str(t).startswith("budget: ") for t in texts) and sent == 0
          and refused_lines == 2 and len(budgets) == 2 and not caps and leaked == 0)
    return ok, (f"statuses {[a[0] for a in answers]}; {texts[0]!r:.160}; stand-in POSTs {sent}; "
                f"refused lines {refused_lines}; budget refusals {len(budgets)}, cap refusals "
                f"{len(caps)}; cap reservation left ${leaked}")


def row_r3(budget, ev, fake):
    worst = ev.measure(json.dumps(message("cap")).encode())[0]
    relay, spend = relay_for(budget, ev, fake.base, worst / 2, "R3")
    try:
        before = stand_in_posts(fake)
        status, data, _ = post(relay.base, message("cap"))
        sent = stand_in_posts(fake) - before
        caps, budgets = relay.refusals(), relay.budget_refusals()
    finally:
        relay.stop()
    text = error_text(data)
    lines = lines_of(spend.path)
    ok = (status == 400 and "spend cap" in str(text) and sent == 0 and not lines
          and len(caps) == 1 and not budgets)
    return ok, (f"status {status}: {text!r:.140}; stand-in POSTs {sent}; proofs'-ledger lines "
                f"{len(lines)}; cap refusals {len(caps)}, budget refusals {len(budgets)}")


def row_r4(budget, ev):
    relay, spend = relay_for(budget, ev, "http://127.0.0.1:9", 10.0, "R4")
    try:
        status, data, raw = post(relay.base, message("dead"))
    finally:
        relay.stop()
    worst = ev.measure(raw)[0]
    reserves, settles = kinds(spend.path, "reserve"), kinds(spend.path, "settle")
    ok = (status == 502 and len(reserves) == 1 and len(settles) == 1
          and abs(settles[0]["dollars"] - reserves[0]["worst"]) < 1e-12
          and abs(reserves[0]["worst"] - worst) < 1e-12 and settles[0]["basis"] == "reserved")
    return ok, (f"status {status}; reserved {[r['worst'] for r in reserves]}; settled "
                f"{[(s['dollars'], s['basis']) for s in settles]}")


# ---------------------------------------------------------------------------
# A: AssemblyAI.


def row_a1(budget):
    import aai
    rates = budget.assemblyai_rates()
    finite = all(isinstance(rates[k], float) and math.isfinite(rates[k]) and rates[k] > 0
                 for k in ("per_hour", "speakers_per_hour"))
    copy = scratch("a1", "CloudEstimate.swift")
    with open(budget.CLOUD_ESTIMATE) as handle:
        source = handle.read().split("\n")
    kept = [line for line in source if not line.strip().startswith("static let perHour")]
    with open(copy, "w") as handle:
        handle.write("\n".join(kept))
    uses = sum(line.count("AssemblyAIRates.perHour") for line in kept)
    try:
        budget.assemblyai_rates(copy)
        mutant = "no error"
    except ValueError as error:
        mutant = f"ValueError: {error}"
    ok = (finite and rates["per_hour"] == aai.RATE_PER_HOUR and len(source) - len(kept) == 1
          and uses >= 2 and mutant.startswith("ValueError"))
    return ok, (f"{rates}; aai.RATE_PER_HOUR {aai.RATE_PER_HOUR}; the copy less its one "
                f"declaration line ({uses} use sites kept): {mutant}")


class StubProof:
    def __init__(self):
        self.rows = []

    def check(self, name, ok, detail=""):
        self.rows.append((name, bool(ok), detail))


def row_a2(ledger_module):
    proof = StubProof()
    ledger_module.controls(proof)
    mine = [r for r in proof.rows if "a gated reservation is refused" in r[0]]
    if len(mine) != 1:
        return False, f"{len(mine)} budget CONTROLs among {len(proof.rows)} controls"
    return mine[0][1], f"{mine[0][0]}: {mine[0][2]}"


def row_a3(budget, ledger_module):
    from aai import Scrubber
    spend = budget.SpendLedger(scratch("a3", "spend.jsonl"), "assemblyai", "budget_proof", "a3",
                               now=at(SEPTEMBER))
    live = ledger_module.LiveLedger(scratch("a3", "ledger.json"), Scrubber([]), spend)
    billed = live.reserve("20", "round-trip", 11)
    live.billed(billed, 11)
    unsent = live.reserve("21", "cached", 11)
    live.closed(unsent, "no_upload")
    settles = [(s["dollars"], s["basis"], s.get("seconds")) for s in kinds(spend.path, "settle")]
    want = budget.assemblyai_dollars(11)
    total = spend.month_total()
    ok = (settles == [(want, "billed", 11), (0.0, "no_upload", 0)]
          and abs(total - want) < 1e-12 and len(kinds(spend.path, "reserve")) == 2)
    return ok, f"settles {settles}; month total ${total:.6f} (want ${want:.6f})"


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=["no-budget", "unknown-as-zero"],
                        help="break one thing in memory; the rows it guards must FAIL")
    args = parser.parse_args()

    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    try:
        import budget
        import prices
        import assistant_prompt_eval as ev
        import cloud_live_ledger
        import assistant_session_proof as asp
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        for row in ROWS:
            score(row, False, f"an import failed: {type(error).__name__}: {error}")
        return summary()
    real = snapshot(budget.LEDGER)

    if args.mutant == "no-budget":
        for service in budget.BUDGETS:
            budget.BUDGETS[service] = math.inf
        print("mutant no-budget: both budgets are infinite", flush=True)
    elif args.mutant == "unknown-as-zero":
        budget.anthropic_worst_row = lambda table: {
            k: 0.0 for k in ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output")}
        print("mutant unknown-as-zero: anthropic_worst_row answers zeros", flush=True)

    guarded("P", row_p, budget, ev)
    guarded("F1", row_f1, budget)
    guarded("F2", row_f2, budget)
    guarded("G1", row_g1, budget)
    guarded("G2", row_g2, budget)
    guarded("G3", row_g3, budget)
    guarded("W", row_w, budget, prices)
    guarded("S1", row_s1, budget, prices)
    guarded("S2", row_s2, budget, prices)
    guarded("S3", row_s3, budget, prices)
    guarded("S4", row_s4, budget, prices)
    guarded("U1", row_u1, ev)
    guarded("U2", row_u2, ev)

    fake = None
    try:
        fake = asp.Fake(os.path.join(WORK, "fake"))
        fake.scenario([asp.say("R1: forwarded.")])
        guarded("R1", row_r1, budget, ev, fake)
        guarded("R2", row_r2, budget, ev, fake)
        guarded("R3", row_r3, budget, ev, fake)
    except Exception as error:  # noqa: BLE001
        for row in ("R1", "R2", "R3"):
            if row not in [r for r, _ in RESULTS]:
                score(row, False, f"the stand-in could not run: {type(error).__name__}: {error}")
    finally:
        if fake is not None:
            fake.stop()
    guarded("R4", row_r4, budget, ev)

    guarded("A1", row_a1, budget)
    guarded("A2", row_a2, cloud_live_ledger)
    guarded("A3", row_a3, budget, cloud_live_ledger)

    after = snapshot(budget.LEDGER)
    score("N", real == after, f"{budget.LEDGER}: (exists, size, mtime_ns) {real} before, "
                              f"{after} after")
    return summary()


def summary():
    passed = sum(1 for _, state in RESULTS if state == "ok")
    failed = [row for row, state in RESULTS if state != "ok"]
    print(f"{passed}/{len(RESULTS)}" + (f"; failed {failed}" if failed else ""), flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
