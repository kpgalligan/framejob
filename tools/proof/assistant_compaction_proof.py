#!/usr/bin/env python3
"""The assistant's end-of-turn compaction, against the stand-in or the real
API — issue batch B26 (#161; spec §11 AI-9, AI-18).

One built app (`proof_app`'s choice, Debug unless `RC_PROOF_APP=release`; a scratch socket, a dummy
`-RCSecretFolder`, `-RCDevAssistantAutoCompact 1`, the Assistant tab open)
is pointed at the relay of `assistant_prompt_eval.py` (imported), which
forwards to the stand-in (`--rehearse`) or the real API (`--live`). Two turns
go through the tab's composer (`assistant_send` with `pane`):

  T1  "Change the title's text to Hello Frame Job, rename the Shapes track to
      Boxes, and add a marker called Intro at 1 second. Then render the frame
      at 1 second and tell me in one sentence what it shows. For later: the
      outro will start at 4.5 seconds, but don't mark it yet."
  T2  "Now put a marker called Outro where I said the outro starts."

At a threshold of 1 token (AI-18) every turn ends compacted. The rows:

  C0  no `Frame Job: ` line
  C1  turn 1 finished, rendered a frame, and its three edits are placed —
      nothing else changed (`get_project`)
  C2  turn 1 compacted: one `compaction_started` below the shipped 300 000,
      then `compacted`, no `compaction_failed`; the summary POST answered
      200 with stop_reason `compaction` and a summary
  C3  exactly one turn-1 POST carries `compaction`, it is the last, and it is
      `{"type":"summarize","instructions": compaction_instructions}` exactly
  C4  the summary names the title clip, the Shapes track and the Intro
      marker by id, the three edits, the rendered frame and the outro's time
  C5  turn 2 starts from the summary block and places Outro at 4.5 s,
      nothing else changed
  C6  the tab's transcript: no error, no failed compaction, the two person
      entries, and each "Compacting…" directly followed by "Compacted: B →
      about A tokens…" with 0 < A < B, one such pair between T1 and T2
  H   every POST within the bounds the headroom arithmetic assumes
  K   (live) the key's bytes in no file under work/assistant_compaction/,
      the app log or the proofs' ledger

    python3 tools/proof/assistant_compaction_proof.py --rehearse [--wrong] [--cap D] [--month-spent D]
    python3 tools/proof/assistant_compaction_proof.py --live --cap D   # needs the key; spends
    python3 tools/proof/assistant_compaction_proof.py --mutant extra-instruction   # C3 FAILS

`--wrong` scripts the mistakes: C1, C2, C4, C5 and C6 must FAIL, C0, C3 and
H pass. `--month-spent D` seeds the rehearsal's scratch proofs' ledger
(`work/assistant_compaction/rehearsal/spend.jsonl`) so `24.99` refuses every
POST `budget:`. A turn a refused POST touched FAILs its rows naming `cap:` or
`budget:` (C1–C4 for turn 1; C5 and C6 for either turn). `--live` without
`--cap` prints the headroom and exits 2 before launching anything.
`--mutant extra-instruction` builds a tree copy (`tree_copy.make_copy`, into
`work/assistant_compaction/mutant/tree`) whose session appends " Be brief."
to the compaction instructions and runs the right rehearsal against it: rule R — exit 1 when C3 FAILs, 0 when it passes, 2 when the copy,
anchor or build fails, C3 is never scored or any row is an instrument failure.

Safety: the key is read once, by `assistant_prompt_eval.anthropic_key`, and
leaves this process only as the relay's `x-api-key`; the app and helper get
the dummy `proof-key`. A rehearsal or mutant never opens the proofs' ledger.
Rule H: a turn is stopped past 600 s and a build killed past 900 s; only this
script's process groups are killed.
"""

import argparse
import json
import math
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import assistant_prompt_eval as ev  # noqa: E402
import budget  # noqa: E402
import prices  # noqa: E402
import tree_copy  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_compaction")
KNOB = 1
SHIPPED = 300_000
BURN_TO = 71
INTRO_AT = 600_000
OUTRO_AT = 2_700_000
POSTS = 2 * ev.ROUNDS_PER_ROW + 2
SUGGESTED_CAP = 8.00
TURN_SECONDS = 600
WALL_BUILD = 900
MODEL = "claude-opus-5-5"
ANCHOR = '"compaction_instructions": AssistantPrompt.compactionInstructions,'
MUTATED = '"compaction_instructions": AssistantPrompt.compactionInstructions + " Be brief.",'
ROWS = ["C0", "C1", "C2", "C3", "C4", "C5", "C6", "H", "K"]
TURN1_ROWS = ["C1", "C2", "C3", "C4"]
T1 = ("Change the title's text to Hello Frame Job, rename the Shapes track to Boxes, and add a "
      "marker called Intro at 1 second. Then render the frame at 1 second and tell me in one "
      "sentence what it shows. For later: the outro will start at 4.5 seconds, but don't mark "
      "it yet.")
T2 = "Now put a marker called Outro where I said the outro starts."
COMPACTING = "Compacting the conversation ("
COMPACTED = re.compile(r"^Compacted: (\S+) → about (\S+) tokens\. Earlier renders are gone; "
                       r"the assistant re-renders when it needs to look\.$")
DUMP_TEXT = 200  # a layout dump's part text is its first 200 characters (UISnapshotLayout)


RESULTS = []  # (id, state, detail, instrument): state "ok" | "FAIL" | "SKIP"
REFUSED = {"cap": 0, "budget": 0}


# ---------------------------------------------------------------------------
# The arithmetic.


def _per_million(tokens, rate):
    return tokens * ev.RATES[rate] / 1_000_000


def conversation_bound():
    """An estimate of the conversation: one cache write of the bounded body,
    then POSTS − 1 cache reads of it, and OUTPUT_PER_ROUND of output a POST."""
    return (_per_million(ev.body_tokens(), "cache_write")
            + (POSTS - 1) * _per_million(ev.body_tokens(), "cache_read")
            + POSTS * _per_million(ev.OUTPUT_PER_ROUND, "output"))


def cap_floor():
    return ev.worst_post() + conversation_bound()


def expected_line():
    usage = {"input_tokens": 3_000, "cache_creation_input_tokens": 5_000,
             "cache_creation": {"ephemeral_5m_input_tokens": 5_000,
                                "ephemeral_1h_input_tokens": 0},
             "cache_read_input_tokens": 20_000, "output_tokens": 500}
    priced = prices.price(usage, MODEL, ev.TABLE)
    if priced.get("kind") != "dollars":
        return f"expected: an ESTIMATE the table cannot price ({priced})"
    return (f"expected: an ESTIMATE, not a bound — 8 POSTs x (3,000 input + 5,000 5-minute cache "
            f"write + 20,000 cache read + 500 output) at {MODEL}'s table row = "
            f"${8 * priced['dollars']:.2f}; #157 settled E4 at $0.1310 and E5 at $0.1894")


def headroom_lines(cap):
    body = _per_million(ev.body_tokens(), "cache_write")
    reads = (POSTS - 1) * _per_million(ev.body_tokens(), "cache_read")
    output = POSTS * _per_million(ev.OUTPUT_PER_ROUND, "output")
    lines = [
        "rates ($/MTok, an UPPER BOUND, not a quote: each class's dearest in "
        f"agent/prices/anthropic.json of {ev.TABLE.get('litellm_commit_date')}): input "
        f"{ev.RATES['input']:.2f}, cache write {ev.RATES['cache_write']:.2f}, cache read "
        f"{ev.RATES['cache_read']:.2f}, output {ev.RATES['output']:.2f}",
        f"worst POST: {ev.BODY_BYTES_BOUND:,} bytes / 3 = {ev.body_tokens():,.0f} tokens at cache "
        f"write (${body:.2f}) + max_tokens {ev.MAX_TOKENS_BOUND:,} at output "
        f"(${_per_million(ev.MAX_TOKENS_BOUND, 'output'):.2f}) = ${ev.worst_post():.2f}",
        f"conversation bound: {POSTS} POSTs (2 turns x {ev.ROUNDS_PER_ROW} rounds + 2 summaries): "
        f"one cache write (${body:.2f}) + {POSTS - 1} cache reads (${reads:.2f}) + {POSTS} x "
        f"{ev.OUTPUT_PER_ROUND:,} output (${output:.2f}) = ${conversation_bound():.2f}, an "
        "estimate billing every definition byte",
        f"floor: worst POST + the conversation bound = ${cap_floor():.2f}; suggested cap "
        f"${SUGGESTED_CAP:.2f}",
        "budget: $25.00 a calendar month (UTC) for Anthropic, before each POST, in the proofs' "
        "ledger (spec §11 P-6)",
        expected_line(),
    ]
    if cap is None:
        lines.append("cap: none given — --live needs --cap <dollars>, the runner's decision")
        return lines
    left = cap - ev.worst_post()
    covered = max(0.0, left) / conversation_bound()
    lines.append(f"cap ${cap:.4g}: ${left:.2f} past the worst POST, covering {covered:.2f} "
                 "conversation bounds")
    if cap < cap_floor():
        lines.append(f"WARNING: below the floor; POSTs past ${left:.2f} of settled spend will "
                     "fail naming the cap")
    return lines


# ---------------------------------------------------------------------------
# Reading replies.


def compaction_reply(data, content_type):
    """(summary or None, stop_reason or None) of a buffered reply, stream or
    not. A `compaction_delta` ASSIGNS the block's content, as the SDK does."""
    text = (data or b"").decode("utf-8", "replace")
    blocks, stop = {}, None
    if "text/event-stream" in (content_type or ""):
        for line in text.splitlines():
            if not line.startswith("data:"):
                continue
            try:
                event = json.loads(line[5:].strip())
            except ValueError:
                continue
            if not isinstance(event, dict):
                continue
            kind = event.get("type")
            if kind == "content_block_start":
                block = event.get("content_block") or {}
                if block.get("type") == "compaction":
                    blocks[event.get("index")] = block.get("content")
            elif kind == "content_block_delta":
                delta = event.get("delta") or {}
                if delta.get("type") == "compaction_delta" and event.get("index") in blocks:
                    blocks[event.get("index")] = delta.get("content")
            elif kind == "message_delta":
                stop = (event.get("delta") or {}).get("stop_reason") or stop
    else:
        try:
            body = json.loads(text)
        except ValueError:
            body = {}
        if isinstance(body, dict):
            stop = body.get("stop_reason")
            for at, block in enumerate(body.get("content") or []):
                if isinstance(block, dict) and block.get("type") == "compaction":
                    blocks[at] = block.get("content")
    found = [c for c in blocks.values() if isinstance(c, str) and c]
    return (found[0] if found else None), stop


# ---------------------------------------------------------------------------
# The fixture and the stand-in's script.


def build_fixture(app, path):
    """A saved project whose ids all have two digits: the burn, a background
    plate, a Titles track with "Welcome" 0–3000000, a Shapes track with a red
    rectangle 0–6000000, the empty track gone, and the Assistant tab open.
    `next` is the project's `next_id` after the last edit: the Intro marker's
    id, since `set_text`, `set_track` and `render_frame` allocate none."""
    if os.path.exists(path):
        shutil.rmtree(path, ignore_errors=True)
    saved = app.must("new_project", path=path)["saved"]

    def next_id():
        return app.must("get_project", project=saved)["project"]["next_id"]

    # Each pair allocates one id and leaves one empty track, so the stack
    # never nears MAX_TRACKS and no id is reused.
    while next_id() < BURN_TO:
        app.must("add_track", project=saved)
        app.must("remove_empty_tracks", project=saved)
    app.must("add_background", project=saved, color=ev.BACKGROUND, duration=6000000)
    titles = next_id()
    app.must("add_track", project=saved, name="Titles")
    title = next_id()
    app.must("add_text_clip", project=saved, track=titles, at=0, duration=3000000,
             text={"content": "Welcome"})
    shapes = next_id()
    app.must("add_track", project=saved, name="Shapes")
    shape = next_id()
    app.must("add_shape_clip", project=saved, track=shapes, at=0, duration=6000000)
    app.must("set_shape", project=saved, clips=[shape], patch={"fill": [1, 0, 0, 1]})
    app.must("remove_empty_tracks", project=saved)
    following = next_id()
    app.must("perform_menu_item", project=saved, path=["View", "Assistant"])
    app.must("select_inspector_tab", project=saved)
    return {"project": saved, "titles": titles, "title": title, "shapes": shapes,
            "shape": shape, "next": following}


def summary_text(ids, turn):
    text = (f"The title clip {ids['title']} on track {ids['titles']} now reads Hello Frame Job. "
            f"Track {ids['shapes']} (Shapes) was renamed Boxes; it holds the red rectangle clip "
            f"{ids['shape']}. Marker {ids['next']} Intro is at 600000 ticks (1 s). The frame "
            f"rendered at 1 s shows Hello Frame Job over the red rectangle. The outro will start at "
            f"4.5 seconds (2700000 ticks)")
    return text + (", not marked yet." if turn == 1 else f"; marker {ids['next'] + 1} Outro "
                                                         "is there now.")


def compacted_reply(ids, turn):
    return {"content": [{"type": "compaction", "content": summary_text(ids, turn)}],
            "stop_reason": "compaction",
            "iterations": [{"type": "compaction", "input_tokens": 30_000, "output_tokens": 900,
                            "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}]}


def fact_free_reply():
    return {"content": [{"type": "compaction",
                         "content": "The person and the assistant talked about a project."}],
            "stop_reason": "end_turn"}


def script(turn, ids, wrong):
    """The stand-in's replies for one turn: the right calls, or with `wrong`
    the mistakes C1, C2, C4, C5 and C6 must catch."""
    if turn == 1:
        edits = {"content": [
            {"type": "tool_use", "id": "toolu_c1a", "name": "set_text",
             "input": {"clips": [ids["title"]],
                       "patch": {"content": "Hello" if wrong else "Hello Frame Job"}}},
            {"type": "tool_use", "id": "toolu_c1b", "name": "set_track",
             "input": {"track": ids["shapes"], "name": "Boxes"}},
            {"type": "tool_use", "id": "toolu_c1c", "name": "add_marker",
             "input": {"at": INTRO_AT, "name": "Intro"}}], "stop_reason": "tool_use"}
        return [edits, ev.use("toolu_c1d", "render_frame", {"t": INTRO_AT}),
                dict(ev.say("It shows the title over a red rectangle."), input_tokens=30_000),
                fact_free_reply() if wrong else compacted_reply(ids, 1)]
    return [ev.use("toolu_c2a", "add_marker", {"at": 1_800_000 if wrong else OUTRO_AT,
                                               "name": "Outro"}),
            dict(ev.say("Marked the outro."), input_tokens=20_000),
            fact_free_reply() if wrong else compacted_reply(ids, 2)]


# ---------------------------------------------------------------------------
# Scoring.


def score(row_id, ok, detail, skip=False, *, instrument=False):
    state = "SKIP" if skip else ("ok" if ok else "FAIL")
    RESULTS.append((row_id, state, detail, instrument))
    print(f"{row_id} {state} — {detail}", flush=True)


def refusal(relay, turns):
    """(kind, sentence) of the first refused POST in `turns`, budget first."""
    for entry in relay.budget_refusals():
        if entry.get("row") in turns:
            return "budget", entry["why"]
    for entry in relay.refusals():
        if entry.get("row") in turns:
            return "cap", (f"cap: refused at ${entry['spent']:.4f} of ${relay.cap:.4g} "
                           f"(worst ${entry['worst']:.2f})")
    return None


def judged(row_id, relay, turns, function, *arguments):
    """Scores `row_id` from `function`, unless a refused POST in `turns` owns
    its answer; a raised exception is an instrument failure."""
    try:
        ok, detail = function(*arguments)
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        refused = refusal(relay, turns)
        if refused:
            REFUSED[refused[0]] += 1
            return score(row_id, False, f"{refused[1]} (the row could not be judged: "
                                        f"{type(error).__name__}: {error})")
        return score(row_id, False, f"the instrument could not run: {type(error).__name__}: "
                                    f"{error}", instrument=True)
    refused = refusal(relay, turns)
    if refused:
        REFUSED[refused[0]] += 1
        return score(row_id, False, f"{refused[1]} ({detail})")
    score(row_id, ok, detail)


def summary(mutant=None):
    """The count line; exit 0 when nothing failed, else 1 — and under
    `--mutant` (rule R), 1 when C3 FAILs as a verdict, 0 when it passes, 2
    when C3 was never scored, was refused on the cap or the budget, or any
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
        c3 = [r for r in RESULTS if r[0] == "C3"]
        why = ("C3 was never scored" if not c3 else
               f"scored as instrument failures: {', '.join(broken)}" if broken else
               f"C3 was refused before the control ran: {c3[0][2]}"
               if c3[0][2].startswith(("cap:", "budget:")) else "")
        if why:
            print(f"mutant {mutant}: the control could not be performed — {why}", flush=True)
            return 2
        verdict = c3[0][1]
        print(f"mutant {mutant}: C3 {verdict}"
              + (" — the mutant was caught" if verdict == "FAIL" else " — the mutant SURVIVED"),
              flush=True)
        return 1 if verdict == "FAIL" else 0
    return 0 if not failed else 1


# ---------------------------------------------------------------------------
# The conversation.


def send(app, relay, project, turn, text):
    """{"answer", "state", "why", "asked"}: the turn through the tab, stopped
    past TURN_SECONDS, a question left pending answered "stop"."""
    relay.row = f"turn{turn}"
    ok, answer = app.call("assistant_send", project=project, text=text, pane=True,
                          timeout=TURN_SECONDS)
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


def events_of(sent):
    return (sent["answer"] or {}).get("events", []) if sent["answer"] else []


def tools_of(sent):
    return [e.get("name") for e in events_of(sent) if e.get("type") == "tool_call"]


def turn_note(sent):
    note = f"state {sent['state']}"
    if sent["why"]:
        note += f" ({sent['why']})"
    if sent["asked"]:
        note += f"; left asking {sent['asked']!r}, answered \"stop\""
    return note


def exchanges(relay, turn):
    with relay.lock:
        return [x for x in relay.exchanges if x["row"] == f"turn{turn}"]


def track_names(project):
    return {t.get("id"): t.get("name") for t in project.get("tracks") or []}


def row_c1(ctx):
    sent, before, after = ctx["sent1"], ctx["before"], ctx["after1"]
    ids = ctx["ids"]
    tools = tools_of(sent)
    rendered = "render_frame" in tools
    key = ("timeline", ids["title"])
    sig_before, sig_after = ev.clip_signatures(before), ev.clip_signatures(after)
    was, now = sig_before.get(key), sig_after.get(key)
    wanted = was[:4] + ("Hello Frame Job",) if was else None
    others = ({k: v for k, v in sig_before.items() if k != key}
              == {k: v for k, v in sig_after.items() if k != key})
    names_before, names_after = track_names(before), track_names(after)
    renamed = names_after.get(ids["shapes"]) == "Boxes"
    names_kept = ({k: v for k, v in names_before.items() if k != ids["shapes"]}
                  == {k: v for k, v in names_after.items() if k != ids["shapes"]})
    old = {m[0] for m in ev.marker_list(before)}
    new = [m for m in ev.marker_list(after) if m[0] not in old]
    kept = [m for m in ev.marker_list(after) if m[0] in old] == ev.marker_list(before)
    marker = len(new) == 1 and new[0][1:] == (INTRO_AT, "Intro")
    ok = (sent["state"] == "finished" and rendered and now is not None and now == wanted
          and others and renamed and names_kept and marker and kept)
    return ok, (f"{turn_note(sent)}; render_frame called {rendered}; title {now}, wanted "
                f"{wanted}; Shapes track named {names_after.get(ids['shapes'])!r}, other track "
                f"names kept {names_kept}; new markers {new}, others kept {kept}; other clips "
                f"unchanged {others}; tools {tools}")


def row_c2(ctx):
    events = events_of(ctx["sent1"])
    started = [e for e in events if e.get("type") == "compaction_started"]
    done = [e for e in events if e.get("type") == "compacted"]
    failed = [e for e in events if e.get("type") == "compaction_failed"]
    order = [e.get("type") for e in events
             if e.get("type") in ("compaction_started", "compacted", "compaction_failed")]
    used = started[0].get("used") if started else None
    under = isinstance(used, int) and used < SHIPPED
    carrying = [x for x in exchanges(ctx["relay"], 1)
                if (x["request"] or {}).get("compaction") is not None]
    status, stop, summary_ok = None, None, False
    if carrying:
        last = carrying[-1]
        status = last["status"]
        text, stop = compaction_reply(last["reply"], last["content_type"])
        summary_ok = bool(text)
    ok = (len(started) == 1 and under and order == ["compaction_started", "compacted"]
          and not failed and status == 200 and stop == "compaction" and summary_ok)
    return ok, (f"compaction events {order}; used {used} < {SHIPPED:,} {under}; compacted "
                f"{[(e.get('before'), e.get('after')) for e in done]}; failed "
                f"{[e.get('reason') for e in failed]}; summary POST status {status}, stop_reason "
                f"{stop!r}, a summary {summary_ok}")


def row_c3(ctx):
    texts = ctx["texts"]
    if texts is None:
        raise RuntimeError("the probe gave no texts to compare")
    mine = exchanges(ctx["relay"], 1)
    carrying = [i for i, x in enumerate(mine) if "compaction" in (x["request"] or {})]
    wanted = {"type": "summarize", "instructions": texts["compaction_instructions"]}
    got = mine[carrying[0]]["request"]["compaction"] if carrying else None
    last = bool(carrying) and carrying == [len(mine) - 1]
    exact = got == wanted
    detail = (f"{len(mine)} turn-1 POSTs, `compaction` in {carrying}; the last {last}; "
              f"verbatim {exact}")
    if carrying and not exact:
        instructions = got.get("instructions") if isinstance(got, dict) else None
        detail += (f" (type {got.get('type') if isinstance(got, dict) else None!r}, "
                   f"instructions {len(instructions or '')} chars, wanted "
                   f"{len(wanted['instructions'])})")
    return len(carrying) == 1 and last and exact, detail


def turn1_summary(ctx):
    carrying = [x for x in exchanges(ctx["relay"], 1)
                if (x["request"] or {}).get("compaction") is not None]
    if not carrying:
        return None
    return compaction_reply(carrying[-1]["reply"], carrying[-1]["content_type"])[0]


def row_c4(ctx):
    text = ctx["summary1"]
    if text is None:
        return False, "no turn-1 summary came back"
    ids = ctx["ids"]
    old = {m[0] for m in ev.marker_list(ctx["before"])}
    intro = [m[0] for m in ev.marker_list(ctx["after1"])
             if m[0] not in old and m[2] == "Intro"]
    intro_id = intro[0] if len(intro) == 1 else ids["next"]
    checks = [
        (f"title clip id {ids['title']}", re.search(rf"\b{ids['title']}\b", text)),
        (f"Shapes track id {ids['shapes']}", re.search(rf"\b{ids['shapes']}\b", text)),
        (f"Intro marker id {intro_id}", re.search(rf"\b{intro_id}\b", text)),
        ("Hello Frame Job", "hello framejob" in text.lower()),
        ("Boxes", "boxes" in text.lower()),
        ("Intro", "intro" in text.lower()),
        ("the frame", re.search(r"\b(frame|render\w*)\b", text, re.I)),
        ("red", re.search(r"\bred\b", text, re.I)),
        ("the outro's time", re.search(r"4\.5|2,?700,?000", text)),
    ]
    missing = [name for name, found in checks if not found]
    return not missing, (f"summary of {len(text)} chars "
                         f"({os.path.relpath(ctx['summary1_path'], ROOT)}); missing {missing}")


def row_c5(ctx):
    sent, before, after = ctx["sent2"], ctx["after1"], ctx["after2"]
    first = exchanges(ctx["relay"], 2)
    head = None
    if first and first[0]["request"]:
        messages = first[0]["request"].get("messages") or []
        head = messages[0] if messages else None
    blocks = (head or {}).get("content") if isinstance(head, dict) else None
    compacted = [b for b in blocks or [] if isinstance(b, dict) and b.get("type") == "compaction"]
    starts = (isinstance(head, dict) and head.get("role") == "assistant" and len(compacted) >= 1
              and ctx["summary1"] is not None and compacted[0].get("content") == ctx["summary1"])
    old = {m[0] for m in ev.marker_list(before)}
    new = [m for m in ev.marker_list(after) if m[0] not in old]
    kept = [m for m in ev.marker_list(after) if m[0] in old] == ev.marker_list(before)
    clips = ev.clip_signatures(after) == ev.clip_signatures(before)
    names = track_names(after) == track_names(before)
    marker = len(new) == 1 and new[0][1:] == (OUTRO_AT, "Outro")
    ok = sent["state"] == "finished" and starts and marker and kept and clips and names
    return ok, (f"{turn_note(sent)}; turn 2's messages[0] is the assistant's summary block "
                f"{starts} (role {(head or {}).get('role') if isinstance(head, dict) else None!r}, "
                f"{len(compacted)} compaction blocks); new markers {new}, others kept {kept}; "
                f"clips unchanged {clips}; track names unchanged {names}; tools "
                f"{tools_of(sent)}")


def row_c6(ctx, atp):
    dump = atp.Dump(ctx["app"], ctx["ids"]["project"], "c6")
    entries = [(k, t or "") for k, t in dump.entries() if k != "progress"]
    errors = [t for k, t in entries if k == "error"]
    unfinished = [t for k, t in entries if k == "meta" and t.startswith("Compaction didn't finish")]
    person = [t for k, t in entries if k == "person"]
    wanted_person = [T1[:DUMP_TEXT], T2[:DUMP_TEXT]]
    pairs, bad = [], []
    for at, (kind, text) in enumerate(entries):
        if kind != "meta" or not text.startswith(COMPACTING):
            continue
        following = entries[at + 1] if at + 1 < len(entries) else None
        found = COMPACTED.match(following[1]) if following and following[0] == "meta" else None
        digits = [re.sub(r"\D", "", g) for g in found.groups()] if found else []
        if found and all(digits):
            before, after_ = int(digits[0]), int(digits[1])
            if 0 < after_ < before:
                pairs.append(at)
                continue
        bad.append(f"{text[:60]!r} then {(following[1] if following else None)!r:.100}")
    persons = [i for i, (k, _) in enumerate(entries) if k == "person"]
    between = False
    after_t2 = False
    if len(persons) == 2:
        t1, t2 = persons
        between = any(t1 < p < t2 and any(entries[j][0] == "reply" for j in range(t1 + 1, p))
                      for p in pairs)
        after_t2 = any(k == "reply" for k, _ in entries[t2 + 1:])
    ok = (not errors and not unfinished and person == wanted_person and pairs and not bad
          and between and after_t2)
    return ok, (f"{len(entries)} entries (progress ignored); errors {errors[:2]}; unfinished "
                f"compactions {unfinished[:2]}; person entries are T1 and T2 "
                f"{person == wanted_person}; {len(pairs)} Compacting/Compacted pairs, bad "
                f"{bad[:2]}; a pair after a reply between T1 and T2 {between}; a reply after "
                f"T2 {after_t2}; kinds {[k for k, _ in entries]}")


def print_report(ctx, relay, ledger):
    print("per turn (dollars at the price table):", flush=True)
    for turn in (1, 2):
        sent = ctx.get(f"sent{turn}")
        mine = [e for e in relay.entries if e.get("row") == f"turn{turn}"]
        tokens = {}
        for entry in mine:
            for name, value in (entry.get("usage") or {}).items():
                if isinstance(value, int) and not isinstance(value, bool):
                    tokens[name] = tokens.get(name, 0) + value
        cost = sum(e.get("dollars", 0.0) for e in mine)
        print(f"  turn {turn}: {len(mine)} POSTs; tools {tools_of(sent) if sent else []}; "
              f"tokens {tokens}; ${cost:.4f}", flush=True)
    carrying = [x for x in exchanges(relay, 2)
                if (x["request"] or {}).get("compaction") is not None]
    second = compaction_reply(carrying[-1]["reply"], carrying[-1]["content_type"])[0] \
        if carrying else None
    path = os.path.join(WORK, "summary-turn2.txt")
    with open(path, "w") as handle:
        handle.write(second or "")
    print(f"turn-2 summary ({os.path.relpath(path, ROOT)}): {second!r}", flush=True)
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
    print(f"run {relay.run}: ${relay.spent():.4f} settled; ledger {ledger}: ${total:.4f} over "
          "every run", flush=True)


def converse(asp, atp, app_path, secrets, relay, texts, folder, stand_in, wrong, key):
    """Launch, fixture, two turns and the rows C0–C6."""
    try:
        app = asp.App("C", app_path,
                      ["-RCSecretFolder", secrets,
                       "-FrameJobInspectorCollapsed", "NO", "-FrameJobAssistantModel", MODEL,
                       "-RCDevAssistantAutoCompact", str(KNOB)], relay.base)
    except Exception:
        relay.stop()  # the `finally` below is not reached; main scores the setup failure
        raise
    ctx = {"app": app, "relay": relay, "texts": texts}
    try:
        app.connect()
        app.mcp.timeout = TURN_SECONDS + 120
        complaints = [l for l in app.log().splitlines() if "Frame Job: " in l]
        score("C0", not complaints, f"`Frame Job: ` lines {complaints[:2]}")
        ids = build_fixture(app, os.path.join(folder, "C.framejob"))
        ctx["ids"] = ids
        print(f"fixture: {ids}", flush=True)

        def project():
            return app.must("get_project", project=ids["project"])["project"]

        ctx["before"] = project()
        if stand_in is not None:
            stand_in.scenario(script(1, ids, wrong))
        ctx["sent1"] = send(app, relay, ids["project"], 1, T1)
        ctx["after1"] = project()
        ctx["summary1"] = turn1_summary(ctx)
        ctx["summary1_path"] = os.path.join(WORK, "summary-turn1.txt")
        with open(ctx["summary1_path"], "w") as handle:
            handle.write(ctx["summary1"] or "")
        print(f"turn-1 summary: {ctx['summary1']!r}", flush=True)
        if stand_in is not None:
            stand_in.scenario(script(2, ids, wrong))
        ctx["sent2"] = send(app, relay, ids["project"], 2, T2)
        ctx["after2"] = project()

        judged("C1", relay, {"turn1"}, row_c1, ctx)
        judged("C2", relay, {"turn1"}, row_c2, ctx)
        judged("C3", relay, {"turn1"}, row_c3, ctx)
        judged("C4", relay, {"turn1"}, row_c4, ctx)
        judged("C5", relay, {"turn1", "turn2"}, row_c5, ctx)
        judged("C6", relay, {"turn1", "turn2"}, row_c6, ctx, atp)
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        for row_id in ROWS[:7]:
            if row_id not in [r[0] for r in RESULTS]:
                score(row_id, False, f"launch C could not run: {type(error).__name__}: {error}",
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
# The mutant: the session's compaction instructions carry one sentence more.


def build_mutant(asp, child_env):
    base = os.path.join(WORK, "mutant")
    tree_copy.remove_tree(base)
    root, reason = tree_copy.make_copy(os.path.join(base, "tree"))
    if root is None:
        return None, reason
    session = os.path.join(root, "app", "Sources", "AssistantSession.swift")
    with open(session) as handle:
        text = handle.read()
    if text.count(ANCHOR) != 1:
        return None, f"AssistantSession.swift has {text.count(ANCHOR)} `{ANCHOR}`, not 1"
    with open(session, "w") as handle:
        handle.write(text.replace(ANCHOR, MUTATED))
    print(f"mutant: `{ANCHOR}` → `{MUTATED}` in the copy; building it (up to {WALL_BUILD} s)…",
          flush=True)
    app, reason = tree_copy.build_app(root, WALL_BUILD, env=child_env())
    if app is None:
        return None, reason
    return str(app), None


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--rehearse", action="store_true",
                        help="the conversation against the stand-in, scripted")
    parser.add_argument("--live", action="store_true",
                        help="the conversation against the real API; needs --cap and the key")
    parser.add_argument("--mutant", choices=["extra-instruction"],
                        help="the right rehearsal against a build whose compaction instructions "
                             "carry one sentence more; C3 FAILS")
    parser.add_argument("--wrong", action="store_true",
                        help="with --rehearse: script the mistakes")
    parser.add_argument("--cap", type=float, help="the spend cap in dollars, any positive figure")
    parser.add_argument("--month-spent", type=float, dest="month_spent",
                        help="with --rehearse: seed the scratch proofs' ledger with this many "
                             "dollars already spent this month")
    args = parser.parse_args()
    if sum(bool(m) for m in (args.rehearse, args.live, args.mutant)) != 1:
        parser.error("give exactly one of --rehearse, --live and --mutant")
    if args.cap is not None and not (math.isfinite(args.cap) and args.cap > 0):
        parser.error("--cap must be a positive finite figure")
    if args.wrong and not args.rehearse:
        parser.error("--wrong goes with --rehearse")
    if args.month_spent is not None and not args.rehearse:
        parser.error("--month-spent goes with --rehearse")
    if args.month_spent is not None and not (math.isfinite(args.month_spent)
                                             and args.month_spent >= 0):
        parser.error("--month-spent must be a finite figure of 0 or more")

    cap = args.cap if args.cap is not None or args.live else SUGGESTED_CAP
    for line in headroom_lines(cap):
        print(line, flush=True)
    if args.live and args.cap is None:
        print("--live needs an explicit --cap <dollars>: nothing was launched", flush=True)
        return 2

    os.makedirs(WORK, exist_ok=True)
    import assistant_session_proof as asp
    import assistant_tab_proof as atp
    import assistant_prompt_proof as app_
    asp.WORK = WORK  # after atp's import, which sets it to its own folder
    atp.WORK = WORK
    app_.WORK = WORK

    mode = "live" if args.live else ("mutant" if args.mutant else "rehearsal")
    release = os.path.join(ROOT, asp.APP_PATH)
    if args.mutant:
        try:
            release, why = build_mutant(asp, asp.child_env)
        except Exception as error:  # noqa: BLE001 — rule R: a setup that cannot run exits 2
            release, why = None, f"{type(error).__name__}: {error}"
        if release is None:
            score("C3", False, f"the mutant did not build: {why}", instrument=True)
            print(f"0/1\nmutant {args.mutant}: the control could not be performed — the mutant "
                  f"did not build: {why}", flush=True)
            return 2

    key = None
    if args.live:
        key = ev.anthropic_key()
        print(f"Anthropic key (ANTHROPIC_API_KEY or .secrets/anthropic-key): "
              f"{'present' if key else 'absent'}", flush=True)
        if not key:
            for row_id in ROWS:
                score(row_id, True, "host: no key", skip=True)
            return summary()

    texts = None
    try:
        binary, why = app_.build_probe()
        if binary is not None:
            answer, why = app_.run_probe(binary)
            texts = (answer or {}).get("texts")
    except Exception as error:  # noqa: BLE001 — scored below as C3's instrument failure
        why = f"{type(error).__name__}: {error}"
    if texts is None:
        print(f"probe: no texts ({why}); C3 will be an instrument failure", flush=True)

    folder = os.path.join(WORK, mode)
    os.makedirs(folder, exist_ok=True)
    fake = None
    try:
        run_id = ev.run_id()
        if args.live:
            ledger = os.path.join(WORK, "ledger.jsonl")
            spend = budget.SpendLedger(budget.LEDGER, "anthropic", "assistant_compaction_proof",
                                       run_id)
            relay = ev.Relay(ev.LIVE_UPSTREAM, ev.anthropic_key, args.cap, ledger, run_id, spend,
                             keep_exchanges=True)
        else:
            fake = asp.Fake(os.path.join(WORK, "fake"))
            ledger = os.path.join(folder, "ledger.jsonl")
            scratch = os.path.join(folder, "spend.jsonl")
            if os.path.exists(scratch):
                os.remove(scratch)
            spend = budget.SpendLedger(scratch, "anthropic", "assistant_compaction_proof", run_id)
            if args.month_spent is not None:
                seed = spend.reserve(args.month_spent, "seed", gate=False)
                spend.settle(seed, args.month_spent, "seed")
            relay = ev.Relay(fake.base, lambda: ev.PROOF_KEY, cap, ledger, run_id, spend,
                             keep_exchanges=True)
        print(spend.describe(), flush=True)
        secrets = asp.secret_folder()
        posts_before = app_.stand_in_posts()
        ctx = converse(asp, atp, release, secrets, relay, texts, folder, fake,
                       args.wrong, key)
        if fake is not None:
            print(f"the stand-in logged {app_.stand_in_posts() - posts_before} POSTs", flush=True)
        print_report(ctx, relay, ledger)
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
