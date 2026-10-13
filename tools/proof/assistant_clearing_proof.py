#!/usr/bin/env python3
"""The assistant's tool-result clearing, against the stand-in or the real API
— issue batch B54 (#208; spec §11 AI-20).

One built app (`proof_app`'s choice, Debug unless `RC_PROOF_APP=release`; on a scratch socket, spec §11 MC-6; a dummy
`-RCSecretFolder`, `-FrameJobAssistantModel claude-opus-5-5`,
`-FrameJobAssistantAutoCompact NO`, `-FrameJobAssistantClearToolResults YES`)
is pointed at `ClearingRelay`, a subclass of `assistant_prompt_eval.py`'s
relay (imported), which forwards to the stand-in (`--rehearse`) or the real
API (`--live`). Two turns go through `assistant_send` without `pane` (CS3's
shape), in a fresh `new_project`:

  turn A  "Add a marker called Alpha at 1 second."
  turn B  "Add a marker called Beta at 2 seconds."

The relay records each body as the APP sent it, then forwards it with ONE
change: `max_tokens` lowered to at most 8,000 (`MAX_TOKENS_CEILING`). The
helper always asks for 32,000, and spec §11 P-6 reserves each POST at its
body's bytes / 3 at the dearest cache-write rate plus `max_tokens` at the
dearest output rate: about $3.17 for a helper body of ~227 KB, so under
`--cap 3` the relay would refuse every POST unchanged. At 8,000 the worst is
about $1.91. On turn B it also replaces `context_management.edits` with
`LOWERED_EDIT` (trigger 1,000 input tokens, keep 1 tool use), so the API can
be seen to clear; the shipped 150,000-token trigger is out of $3's reach.
The rows:

  X0  no `Frame Job: ` line
  X1  every turn-A and turn-B body, as the app sent it, has
      `context_management == {"edits": [CLEAR_EDIT]}` and the
      `context-management-2025-06-27` beta; turn A made at least one POST
  X2  the API accepted it: every turn-A exchange answered 200, the last
      stop_reason `end_turn`, the turn `finished` with no `error` event, and
      exactly one new marker, Alpha at 600000, nothing else changed (each
      reply's `context_management` is reported, not scored)
  X3  the forwarded turn-A bodies differ from the app's only in `max_tokens`
      (the app's value, then `MAX_TOKENS_CEILING`): the rewrite's honesty row
  X4  the lowered trigger on turn B: ok when every forwarded turn-B body
      carries `[LOWERED_EDIT]`, every exchange answered 200, a reply's
      `context_management.applied_edits` holds a `clear_tool_uses_20250919`
      with `cleared_tool_uses >= 1`, the turn's events hold
      `tool_results_cleared` with `tool_uses >= 1`, it `finished` and Beta is
      at 1200000; SKIP `the API does not allow the lowered edit: <message>`
      when turn B's first exchange answered 400 naming `context_management`,
      `trigger`, `keep` or `clear_at_least`; FAIL otherwise
  H   every POST within the bounds the headroom arithmetic assumes
  K   (live) the key's bytes in no file under work/assistant_clearing/, the
      app log or the proofs' ledger

    python3 tools/proof/assistant_clearing_proof.py --rehearse [--refused] [--cap D]
    python3 tools/proof/assistant_clearing_proof.py --mutant clearing-off   # X1 FAILS
    python3 tools/proof/assistant_clearing_proof.py --live --cap D          # needs the key; spends

`--refused` (with `--rehearse`) has the relay answer turn B's POSTs 400
`context_management.edits.0.trigger: rehearsal refusal` without forwarding:
X4 must SKIP. `--mutant clearing-off` launches with
`-FrameJobAssistantClearToolResults NO` and runs the rehearsal: rule R — exit 1
when X1 FAILs, 0 when it passes, 2 when X1 is never scored, was refused on
the cap or the budget, or any row is an instrument failure. A rehearsal or
mutant spends against a scratch ledger (`work/assistant_clearing/<mode>/
spend.jsonl`, deleted first) at `--cap` (default $3.00); a refused POST fails
the rows its turn touches naming `cap:` or `budget:`. `--live` without
`--cap` prints the headroom and exits 2 before launching anything; `--live`
with no key SKIPs every row `host: no key`.

Safety: the key is read once, by `assistant_prompt_eval.anthropic_key`, and
leaves this process only as the relay's `x-api-key`; the app and helper get
the dummy `proof-key`, and every child's environment has the keys popped
(`assistant_session_proof.child_env`). Only `--live` opens the proofs' ledger.
Rule H: a turn is stopped past 300 s; only this script's processes are
killed (`App.stop`).
"""

import argparse
import json
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import assistant_compaction_proof as acp  # noqa: E402
import assistant_prompt_eval as ev  # noqa: E402
import assistant_session_proof as asp  # noqa: E402
import assistant_settings_proof as sp  # noqa: E402  (sets asp.WORK and atp.WORK; main resets)
import assistant_tab_proof as atp  # noqa: E402
import budget  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_clearing")
MODEL = "claude-opus-5-5"
BETA = "context-management-2025-06-27"
CLEAR_EDIT = sp.CLEAR_EDIT
LOWERED_EDIT = {"type": "clear_tool_uses_20250919",
                "trigger": {"type": "input_tokens", "value": 1000},
                "keep": {"type": "tool_uses", "value": 1}}
MAX_TOKENS_CEILING = 8_000
POSTS = 5
SUGGESTED_CAP = 3.00
TURN_SECONDS = 300
ROWS = ["X0", "X1", "X2", "X3", "X4", "H", "K"]
TA = "Add a marker called Alpha at 1 second."
TA_MARKER = (600_000, "Alpha")
TB = "Add a marker called Beta at 2 seconds."
TB_MARKER = (1_200_000, "Beta")
LOWERED_WORDS = ("context_management", "trigger", "keep", "clear_at_least")
REFUSAL = "context_management.edits.0.trigger: rehearsal refusal"

RESULTS = []  # (id, state, detail, instrument): state "ok" | "FAIL" | "SKIP"
REFUSED = {"cap": 0, "budget": 0}


# ---------------------------------------------------------------------------
# The relay: the app's bodies recorded, `max_tokens` lowered, turn B's edit lowered.


class ClearingRelay(ev.Relay):
    def __init__(self, upstream, credential, cap, ledger, run, spend, refuse_lowered=False):
        self.sent = []
        self.refuse_lowered = refuse_lowered
        super().__init__(upstream, credential, cap, ledger, run, spend, keep_exchanges=True)

    def _handler(self):
        relay = self
        base = super()._handler()

        class Handler(base):
            def _messages(self, raw):
                try:
                    body = json.loads(raw) if raw else None
                except ValueError:
                    body = None
                body = body if isinstance(body, dict) else None
                row = relay.row
                with relay.lock:
                    relay.sent.append({"row": row, "sent": body,
                                       "beta": self.headers.get("anthropic-beta", "")})
                if body is None:
                    return super()._messages(raw)
                forwarded = dict(body)
                if isinstance(forwarded.get("max_tokens"), int):
                    forwarded["max_tokens"] = min(forwarded["max_tokens"], MAX_TOKENS_CEILING)
                if row == "turnB" and isinstance(forwarded.get("context_management"), dict):
                    forwarded["context_management"] = dict(forwarded["context_management"],
                                                           edits=[LOWERED_EDIT])
                if relay.refuse_lowered and row == "turnB":
                    reply = json.dumps({"type": "error", "error": {
                        "type": "invalid_request_error", "message": REFUSAL}}).encode()
                    with relay.lock:
                        relay.exchanges.append({"row": row, "request": forwarded, "status": 400,
                                                "content_type": "application/json",
                                                "reply": reply})
                    return self._error(400, "invalid_request_error", REFUSAL)
                return super()._messages(json.dumps(forwarded, separators=(",", ":"),
                                                    ensure_ascii=False).encode("utf-8"))

        return Handler


# ---------------------------------------------------------------------------
# The arithmetic.


def _per_million(tokens, rate):
    return tokens * ev.RATES[rate] / 1_000_000


def worst_post():
    return _per_million(ev.body_tokens(), "cache_write") + _per_million(MAX_TOKENS_CEILING,
                                                                         "output")


def estimate_post():
    return _per_million(ev.body_tokens(), "cache_read") + _per_million(ev.OUTPUT_PER_ROUND,
                                                                        "output")


def cap_floor():
    return worst_post() + (POSTS - 1) * estimate_post()


def headroom_lines(cap):
    lines = [
        "rates ($/MTok, an UPPER BOUND, not a quote: each class's dearest in "
        f"agent/prices/anthropic.json of {ev.TABLE.get('litellm_commit_date')}): input "
        f"{ev.RATES['input']:.2f}, cache write {ev.RATES['cache_write']:.2f}, cache read "
        f"{ev.RATES['cache_read']:.2f}, output {ev.RATES['output']:.2f}",
        f"worst POST: {ev.BODY_BYTES_BOUND:,} bytes / 3 = {ev.body_tokens():,.0f} tokens at cache "
        f"write (${_per_million(ev.body_tokens(), 'cache_write'):.2f}) + max_tokens "
        f"{MAX_TOKENS_CEILING:,} (the relay's ceiling; the helper asks {ev.MAX_TOKENS_BOUND:,}) at "
        f"output (${_per_million(MAX_TOKENS_CEILING, 'output'):.2f}) = ${worst_post():.2f}",
        f"estimate a POST: the body at cache read "
        f"(${_per_million(ev.body_tokens(), 'cache_read'):.2f}) + {ev.OUTPUT_PER_ROUND:,} output "
        f"(${_per_million(ev.OUTPUT_PER_ROUND, 'output'):.2f}) = ${estimate_post():.2f}",
        f"floor: worst POST + {POSTS - 1} estimated POSTs = ${cap_floor():.2f}; suggested cap "
        f"${SUGGESTED_CAP:.2f}",
        "budget: $25.00 a calendar month (UTC) for Anthropic, before each POST, in the proofs' "
        "ledger (spec §11 P-6)",
    ]
    if cap is None:
        lines.append("cap: none given — --live needs --cap <dollars>, the runner's decision")
        return lines
    lines.append(f"cap ${cap:.4g}: ${cap - worst_post():.2f} past the worst POST")
    if cap < cap_floor():
        lines.append(f"WARNING: the cap ${cap:.4g} is below the floor ${cap_floor():.2f}; POSTs "
                     "past it will fail naming the cap")
    return lines


# ---------------------------------------------------------------------------
# Reading replies.


def _events(data, content_type):
    text = (data or b"").decode("utf-8", "replace")
    if "text/event-stream" in (content_type or ""):
        found = []
        for line in text.splitlines():
            if not line.startswith("data:"):
                continue
            try:
                event = json.loads(line[5:].strip())
            except ValueError:
                continue
            if isinstance(event, dict):
                found.append(event)
        return found
    try:
        body = json.loads(text)
    except ValueError:
        return []
    return [body] if isinstance(body, dict) else []


def context_management_of(data, content_type):
    """The last top-level `context_management` on any SSE event, or on the
    Message body."""
    found = None
    for event in _events(data, content_type):
        if isinstance(event.get("context_management"), dict):
            found = event["context_management"]
    return found


def stop_reason_of(data, content_type):
    return acp.compaction_reply(data, content_type)[1]


def error_message_of(data, content_type):
    for event in _events(data, content_type):
        error = event.get("error")
        if isinstance(error, dict) and isinstance(error.get("message"), str):
            return error["message"]
    return None


# ---------------------------------------------------------------------------
# Scoring.


def score(row_id, ok, detail, skip=False, *, instrument=False):
    state = "SKIP" if skip else ("ok" if ok else "FAIL")
    RESULTS.append((row_id, state, detail, instrument))
    print(f"{row_id} {state} — {detail}", flush=True)


def judged(row_id, relay, turns, function, *arguments):
    """Scores `row_id` from `function` ((ok, detail) or (ok, detail, skip)),
    unless a refused POST in `turns` owns its answer; a raised exception is an
    instrument failure."""
    try:
        answer = function(*arguments)
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        refused = acp.refusal(relay, turns)
        if refused:
            REFUSED[refused[0]] += 1
            return score(row_id, False, f"{refused[1]} (the row could not be judged: "
                                        f"{type(error).__name__}: {error})")
        return score(row_id, False, f"the instrument could not run: {type(error).__name__}: "
                                    f"{error}", instrument=True)
    ok, detail = answer[0], answer[1]
    skip = len(answer) > 2 and answer[2]
    refused = acp.refusal(relay, turns)
    if refused:
        REFUSED[refused[0]] += 1
        return score(row_id, False, f"{refused[1]} ({detail})")
    score(row_id, ok, detail, skip)


def summary(mutant=None):
    """The count line; exit 0 when nothing failed, else 1 — and under
    `--mutant` (rule R), 1 when X1 FAILs as a verdict, 0 when it passes, 2
    when X1 was never scored, was refused on the cap or the budget, or any
    row was an instrument failure."""
    scored = [r for r in RESULTS if r[1] != "SKIP"]
    passed = sum(1 for r in scored if r[1] == "ok")
    skipped = len(RESULTS) - len(scored)
    failed = [r[0] for r in scored if r[1] == "FAIL"]
    caps, budgets = REFUSED["cap"], REFUSED["budget"]
    print(f"{passed}/{len(scored)} pass, {skipped} skipped"
          + (f"; failed {failed} ({caps} on the cap, {budgets} on the budget, "
             f"{len(failed) - caps - budgets} otherwise)" if failed else ""), flush=True)
    if mutant:
        broken = [r[0] for r in RESULTS if r[3]]
        x1 = [r for r in RESULTS if r[0] == "X1"]
        why = ("X1 was never scored" if not x1 else
               f"scored as instrument failures: {', '.join(broken)}" if broken else
               f"X1 was refused before the control ran: {x1[0][2]}"
               if x1[0][2].startswith(("cap:", "budget:")) else
               "X1 was skipped" if x1[0][1] == "SKIP" else "")
        if why:
            print(f"mutant {mutant}: the control could not be performed — {why}", flush=True)
            return 2
        verdict = x1[0][1]
        print(f"mutant {mutant}: X1 {verdict}"
              + (" — the mutant was caught" if verdict == "FAIL" else " — the mutant SURVIVED"),
              flush=True)
        return 1 if verdict == "FAIL" else 0
    return 0 if not failed else 1


# ---------------------------------------------------------------------------
# The conversation.


def send(app, relay, project, turn, text):
    """{"answer", "state", "why", "asked"}: the turn through `assistant_send`
    (no pane), stopped past TURN_SECONDS, a question left pending answered
    "stop"."""
    relay.row = f"turn{turn}"
    ok, answer = app.call("assistant_send", project=project, text=text, timeout=TURN_SECONDS)
    if not ok:
        return {"answer": None, "state": None, "why": f"assistant_send refused: {answer}",
                "asked": None}
    state = answer.get("state")
    why, asked = None, None
    if state == "running":
        app.call("assistant_answer", project=project, answer="stop", timeout=60)
        why = f"the turn ran past {TURN_SECONDS} s and was stopped"
    elif state == "asking":
        asked = (answer.get("question") or {}).get("tool")
        app.call("assistant_answer", project=project, answer="stop", timeout=60)
    return {"answer": answer, "state": state, "why": why, "asked": asked}


def sent_of(relay, turn):
    with relay.lock:
        return [x for x in relay.sent if x["row"] == f"turn{turn}"]


def exchanges(relay, turn):
    with relay.lock:
        return [x for x in relay.exchanges if x["row"] == f"turn{turn}"]


def errors_of(sent):
    return [e.get("message") for e in acp.events_of(sent) if e.get("type") == "error"]


def new_markers(before, after):
    old = {m[0] for m in ev.marker_list(before)}
    new = [m for m in ev.marker_list(after) if m[0] not in old]
    kept = [m for m in ev.marker_list(after) if m[0] in old] == ev.marker_list(before)
    return new, kept


def betas(entry):
    return [part.strip() for part in (entry.get("beta") or "").split(",")]


def row_x1(ctx):
    relay = ctx["relay"]
    a, b = sent_of(relay, "A"), sent_of(relay, "B")
    bad = []
    for turn, entries in (("A", a), ("B", b)):
        for at, entry in enumerate(entries):
            body = entry["sent"] or {}
            cm = body.get("context_management")
            beta = BETA in betas(entry)
            if cm != {"edits": [CLEAR_EDIT]} or not beta:
                bad.append(f"turn {turn} POST {at + 1}: context_management {json.dumps(cm)}, "
                           f"beta {beta} ({entry.get('beta')!r})")
    ok = len(a) >= 1 and not bad
    return ok, (f"{len(a)} turn-A and {len(b)} turn-B POSTs as the app sent them; each with "
                f"{{\"edits\": [CLEAR_EDIT]}} and the {BETA} beta {not bad}; not so: {bad[:3]}")


def row_x2(ctx):
    relay, sent = ctx["relay"], ctx["sentA"]
    mine = exchanges(relay, "A")
    statuses = [x["status"] for x in mine]
    stop = stop_reason_of(mine[-1]["reply"], mine[-1]["content_type"]) if mine else None
    managed = [context_management_of(x["reply"], x["content_type"]) for x in mine]
    errors = errors_of(sent)
    new, kept = new_markers(ctx["before"], ctx["afterA"])
    marker = len(new) == 1 and new[0][1:] == TA_MARKER
    clips = ev.clip_signatures(ctx["afterA"]) == ev.clip_signatures(ctx["before"])
    ok = (bool(mine) and all(s == 200 for s in statuses) and stop == "end_turn"
          and sent["state"] == "finished" and not errors and marker and kept and clips)
    return ok, (f"{acp.turn_note(sent)}; turn-A statuses {statuses}; last stop_reason {stop!r}; "
                f"error events {errors[:2]}; new markers {new}, others kept {kept}; clips "
                f"unchanged {clips}; tools {acp.tools_of(sent)}; replies' context_management "
                f"(reported, not scored) {json.dumps(managed)}")


def row_x3(ctx):
    relay = ctx["relay"]
    app_bodies = [x["sent"] for x in sent_of(relay, "A")]
    forwarded = [x["request"] for x in exchanges(relay, "A")]
    notes, ok = [], bool(app_bodies) and len(app_bodies) == len(forwarded)
    for at, (mine, theirs) in enumerate(zip(app_bodies, forwarded)):
        if not isinstance(mine, dict) or not isinstance(theirs, dict):
            ok = False
            notes.append(f"POST {at + 1}: a body that is not an object")
            continue
        asked = mine.get("max_tokens")
        wanted = dict(mine)
        if isinstance(asked, int):
            wanted["max_tokens"] = min(asked, MAX_TOKENS_CEILING)
        differing = sorted(k for k in set(mine) | set(theirs) if mine.get(k) != theirs.get(k))
        same = theirs == wanted
        ok = ok and same and set(differing) <= {"max_tokens"}
        notes.append(f"POST {at + 1}: max_tokens {asked} → {theirs.get('max_tokens')}, keys that "
                     f"differ {differing}, the rest identical {same}")
    return ok, (f"{len(app_bodies)} app bodies, {len(forwarded)} forwarded; "
                + "; ".join(notes))


def row_x4(ctx):
    relay, sent = ctx["relay"], ctx["sentB"]
    mine = exchanges(relay, "B")
    statuses = [x["status"] for x in mine]
    if mine and mine[0]["status"] == 400:
        message = error_message_of(mine[0]["reply"], mine[0]["content_type"]) or ""
        if any(word in message for word in LOWERED_WORDS):
            return False, f"the API does not allow the lowered edit: {message}", True
    lowered = bool(mine) and all(
        (x["request"] or {}).get("context_management") == {"edits": [LOWERED_EDIT]} for x in mine)
    applied = []
    for x in mine:
        for edit in (context_management_of(x["reply"], x["content_type"]) or {}).get(
                "applied_edits") or []:
            if isinstance(edit, dict):
                applied.append(edit)
    cleared = any(e.get("type") == "clear_tool_uses_20250919"
                  and isinstance(e.get("cleared_tool_uses"), int) and e["cleared_tool_uses"] >= 1
                  for e in applied)
    reported = [e for e in acp.events_of(sent) if e.get("type") == "tool_results_cleared"]
    shown = any(isinstance(e.get("tool_uses"), int) and e["tool_uses"] >= 1 for e in reported)
    new, kept = new_markers(ctx["afterA"], ctx["afterB"])
    marker = len(new) == 1 and new[0][1:] == TB_MARKER
    ok = (lowered and all(s == 200 for s in statuses) and cleared and shown
          and sent["state"] == "finished" and marker and kept)
    return ok, (f"{acp.turn_note(sent)}; turn-B statuses {statuses}; every forwarded body "
                f"carries [LOWERED_EDIT] {lowered}; applied edits {json.dumps(applied)}; a "
                f"clear_tool_uses_20250919 with cleared_tool_uses >= 1 {cleared}; "
                f"tool_results_cleared events {reported}; new markers {new}, others kept {kept}; "
                f"error events {errors_of(sent)[:2]}")


def scenario(turn):
    if turn == "A":
        return [ev.use("toolu_xa", "add_marker", {"at": 600000, "name": "Alpha"}),
                ev.say("Added Alpha.")]
    return [ev.use("toolu_xb", "add_marker", {"at": 1200000, "name": "Beta"}),
            dict(ev.say("Added Beta."), context_management={"applied_edits": [
                {"type": "clear_tool_uses_20250919", "cleared_tool_uses": 1,
                 "cleared_input_tokens": 1200}]})]


def print_report(ctx, relay):
    print("per turn (dollars at the price table):", flush=True)
    for turn in ("A", "B"):
        sent = ctx.get(f"sent{turn}")
        mine = [e for e in relay.entries if e.get("row") == f"turn{turn}"]
        cost = sum(e.get("dollars", 0.0) for e in mine)
        print(f"  turn {turn}: {len(mine)} POSTs; tools {acp.tools_of(sent) if sent else []}; "
              f"${cost:.4f}", flush=True)
    print(f"run {relay.run}: ${relay.spent():.4f} settled", flush=True)


def converse(release, relay, folder, stand_in, clearing, key):
    """Launch, a fresh project, two turns and the rows X0–X4, H and K."""
    try:
        app = asp.App("X", release,
                      ["-RCSecretFolder", asp.secret_folder(),
                       "-FrameJobAssistantModel", MODEL, "-FrameJobAssistantAutoCompact", "NO",
                       "-FrameJobAssistantClearToolResults", "YES" if clearing else "NO"],
                      relay.base)
    except Exception:
        relay.stop()  # the `finally` below is not reached; main scores the setup failure
        raise
    ctx = {"app": app, "relay": relay}
    try:
        app.connect()
        app.mcp.timeout = TURN_SECONDS + 120
        path = os.path.join(folder, "X.framejob")
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)
        project = app.must("new_project", path=path)["saved"]

        def read():
            return app.must("get_project", project=project)["project"]

        ctx["before"] = read()
        if stand_in is not None:
            stand_in.scenario(scenario("A"))
        ctx["sentA"] = send(app, relay, project, "A", TA)
        ctx["afterA"] = read()
        if stand_in is not None:
            stand_in.scenario(scenario("B"))
        ctx["sentB"] = send(app, relay, project, "B", TB)
        ctx["afterB"] = read()
        complaints = [line for line in app.log().splitlines() if "Frame Job: " in line]
        score("X0", not complaints, f"`Frame Job: ` lines {complaints[:2]}")
        judged("X1", relay, {"turnA", "turnB"}, row_x1, ctx)
        judged("X2", relay, {"turnA"}, row_x2, ctx)
        judged("X3", relay, {"turnA"}, row_x3, ctx)
        judged("X4", relay, {"turnB"}, row_x4, ctx)
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        for row_id in ROWS[:5]:
            if row_id not in [r[0] for r in RESULTS]:
                score(row_id, False, f"launch X could not run: {type(error).__name__}: {error}",
                      instrument=True)
    finally:
        app.stop()
        relay.stop()
    score("H", *ev.row_h(relay))
    if key is not None:
        score("K", *ev.row_k(key, WORK, app.log_path, extra=[relay.spend.path]))
    else:
        score("K", True, "not asked (--live)", skip=True)
    return ctx


# ---------------------------------------------------------------------------


def main():
    asp.WORK = WORK  # after assistant_settings_proof's import, which sets it to its own folder
    atp.WORK = WORK
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--rehearse", action="store_true",
                        help="the conversation against the stand-in, scripted")
    parser.add_argument("--live", action="store_true",
                        help="the conversation against the real API; needs --cap and the key")
    parser.add_argument("--mutant", choices=["clearing-off"],
                        help="the rehearsal against an app launched with clearing off; X1 FAILS")
    parser.add_argument("--refused", action="store_true",
                        help="with --rehearse: the relay answers turn B 400 naming the trigger; "
                             "X4 SKIPs")
    parser.add_argument("--cap", type=float, help="the spend cap in dollars, any positive figure")
    args = parser.parse_args()
    if sum(bool(m) for m in (args.rehearse, args.live, args.mutant)) != 1:
        parser.error("give exactly one of --rehearse, --live and --mutant")
    if args.cap is not None and not (math.isfinite(args.cap) and args.cap > 0):
        parser.error("--cap must be a positive finite figure")
    if args.refused and not args.rehearse:
        parser.error("--refused goes with --rehearse")

    cap = args.cap if args.cap is not None or args.live else SUGGESTED_CAP
    for line in headroom_lines(cap):
        print(line, flush=True)
    if args.live and args.cap is None:
        print("--live needs an explicit --cap <dollars>: nothing was launched", flush=True)
        return 2

    os.makedirs(WORK, exist_ok=True)
    mode = "live" if args.live else ("mutant" if args.mutant else "rehearsal")
    release = os.path.join(ROOT, asp.APP_PATH)

    key = None
    if args.live:
        key = ev.anthropic_key()
        print(f"Anthropic key (ANTHROPIC_API_KEY or .secrets/anthropic-key): "
              f"{'present' if key else 'absent'}", flush=True)
        if not key:
            for row_id in ROWS:
                score(row_id, True, "host: no key", skip=True)
            return summary()

    folder = os.path.join(WORK, mode)
    os.makedirs(folder, exist_ok=True)
    fake = None
    try:
        run_id = ev.run_id()
        ledger = os.path.join(folder, "ledger.jsonl")
        if args.live:
            spend = budget.SpendLedger(budget.LEDGER, "anthropic", "assistant_clearing_proof",
                                       run_id)
            relay = ClearingRelay(ev.LIVE_UPSTREAM, ev.anthropic_key, args.cap, ledger, run_id,
                                  spend)
        else:
            fake = asp.Fake(os.path.join(WORK, "fake"))
            scratch = os.path.join(folder, "spend.jsonl")
            if os.path.exists(scratch):
                os.remove(scratch)
            spend = budget.SpendLedger(scratch, "anthropic", "assistant_clearing_proof", run_id)
            relay = ClearingRelay(fake.base, lambda: ev.PROOF_KEY, cap, ledger, run_id, spend,
                                  refuse_lowered=args.refused)
        print(spend.describe(), flush=True)
        ctx = converse(release, relay, folder, fake, args.mutant != "clearing-off", key)
        print_report(ctx, relay)
        print(spend.describe(), flush=True)
    except Exception as error:  # noqa: BLE001
        score("setup", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)
    finally:
        if fake is not None:
            fake.stop()
    return summary(mutant=args.mutant)


if __name__ == "__main__":
    sys.exit(main())
