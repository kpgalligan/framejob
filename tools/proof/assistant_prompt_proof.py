#!/usr/bin/env python3
"""The assistant's prompt texts, live context and evaluation — road map 12
A3 (spec §11 AI-7, AI-9, AI-15).

  F1–F8, M1–M6  the probe (`assistant_prompt_probe.swift`, compiled over
          `app/Sources` minus `main.swift` on `harness/build.sh`'s swiftc line,
          rebuilt only when stale): the texts in `AssistantPrompt.swift`
          checked against the code that decides what they say, and each
          checker made to fail on a mutated copy. F7 also holds every
          `none`/`null` literal to double quotes and the no-scope word to the
          live context block's; F8 holds each ask-first row's reason to a
          write (#158). `--probe` runs these alone:
          no app, no bun — the line `make test` runs.
Launch S (Release app, port 4878, `-AgentServerEnabled YES`, a dummy
`-RCSecretFolder`, `RC_ASSISTANT_BASE_URL` at the stand-in):
  S0  no `Reelcut: ` line
  S1  POST 1's system is `system`, a blank line, `search_guide`
  S2  the live context: in a saved project with the playhead at 2400000 and
      the text clip selected, turn 1's last user text is the exact
      <reelcut_context> block, a newline and the person's text; after the
      playhead moves and the selection empties, turn 2 carries the new block
      and its `messages[0]` is turn 1's (append-only, AI-9)
  S3  a reply of 300000 input tokens makes the next POST, the summary,
      carry `compaction_instructions` verbatim
The evaluation (`assistant_prompt_eval.py`, imported), launch E on port 4880
through the relay:
  E1–E6  six asks, each in a project of its own, judged by `get_project`
          placement only; an E row whose session met the month's budget FAILs
          `budget: …`, one that met the cap `cap: …`
  H   every POST the relay saw was within the bounds the arithmetic assumes
  K   the key's bytes in no file under work/assistant_prompt/ nor the app log

    python3 tools/proof/assistant_prompt_proof.py --probe       # F, M (make test)
    python3 tools/proof/assistant_prompt_proof.py               # F, M, S; E, H, K SKIP
    python3 tools/proof/assistant_prompt_proof.py --rehearse [--wrong] [--cap D] [--month-spent D]
    python3 tools/proof/assistant_prompt_proof.py --live --cap D   # needs the key
    python3 tools/proof/assistant_prompt_proof.py --mutant bare-send   # S2 alone: FAILS

`--rehearse` points the relay at the stand-in with scripted right calls
(`--wrong`: the plausible mistakes, every E row must FAIL); `--cap` SETS the
cap, any positive figure: raising it is the runner's decision. `--live`
without `--cap` prints the headroom arithmetic and exits 2 before launching
anything.

The month's budget (spec §11 P-3, P-6): a keyed `--live` reserves every POST
in the proofs' ledger, `budget.LEDGER`, and nothing else ever opens it. A
rehearsal uses a scratch ledger, `work/assistant_prompt/rehearsal/spend.jsonl`,
deleted first; `--month-spent D` (rehearsal only) seeds it with D dollars
already spent this month, so `--month-spent 24.99` shows every E row refused
`budget:` with nothing sent to the stand-in. `--mutant bare-send` builds a tree copy (`tree_copy.make_copy`, into
`work/assistant_prompt/mutant/tree`) whose `send` writes the bare
text and runs S2 against it (port 4881): it must FAIL (exit 1); a copy that
did not build exits 2.

Safety: every child's environment has `ANTHROPIC_API_KEY`, `RC_ASSEMBLYAI_KEY`
and `RC_AGENT_PORT` popped; the app and helper get only the dummy
`proof-key`. The real key is read once, by `assistant_prompt_eval.anthropic_key`,
and leaves this process only as the relay's `x-api-key` to the live API. Rule
H: only this script's process groups are killed, with the helper children
each app started.
"""

import argparse
import json
import math
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import tree_copy  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_prompt")
PROBE_DIR = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "assistant_prompt_probe.swift")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
WALL_BUILD, WALL_RUN, WALL_TURN = 900, 300, 60
PORT_S, PORT_E, PORT_MUTANT = 4878, 4880, 4881
PROBE_ROWS = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "M1", "M2", "M3", "M4", "M5",
              "M6"]
EVAL_ROWS = ["E1", "E2", "E3", "E4", "E5", "E6", "H", "K"]
SEND = "AssistantPrompt.message(text, document: document)"
TAG = "reelcut_context"


def child_env():
    env = bounded.child_env()
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)  # bounded pops it too; this file does not rely on that
    env.pop("RC_AGENT_PORT", None)
    return env


def run(argv, seconds, cwd=None):
    return bounded.run(argv, seconds, cwd=cwd, env=child_env())


# ---------------------------------------------------------------------------
# The probe, built as `assistant_lane_proof.build_probe` builds its own.


def build_probe():
    """(binary, None) or (None, reason). Rebuilt only when stale."""
    os.makedirs(PROBE_DIR, exist_ok=True)
    binary = os.path.join(PROBE_DIR, "assistant_prompt_probe")
    entry = os.path.join(PROBE_DIR, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    for name in ("Fonts", "Models"):
        src = os.path.join(ROOT, "app", "Resources", name)
        dst = os.path.join(PROBE_DIR, name)
        if not os.path.isdir(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst)
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `cd core && cargo build --release` first"
    swift = sorted(os.path.join(SOURCES, n) for n in os.listdir(SOURCES)
                   if n.endswith(".swift") and n != "main.swift")
    stamp = os.path.join(PROBE_DIR, "sources.txt")
    listing = "\n".join(swift)
    same_set = os.path.exists(stamp) and open(stamp).read() == listing
    if same_set and os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary)
            for f in swift + [entry, LIB, os.path.abspath(__file__),
                              os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
                              os.path.join(ROOT, "core", "include", "reelcut_core.h")]):
        print(f"probe: {binary} (up to date)", flush=True)
        return binary, None
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    if os.path.exists(binary):
        os.remove(binary)
    print(f"probe: building over {len(swift)} sources (up to {WALL_BUILD} s)…", flush=True)
    started = time.time()
    built = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                 "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
                 "-import-objc-header",
                 os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
                 "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary],
                WALL_BUILD)
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [l for l in built["stderr"].splitlines() if ": error:" in l]
        tail = [l for l in built["stderr"].strip().splitlines()[-4:] if l.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    with open(stamp, "w") as f:
        f.write(listing)
    print(f"probe: built in {time.time() - started:.0f} s", flush=True)
    return binary, None


def run_probe(binary):
    runs = os.path.join(WORK, "runs")
    shutil.rmtree(runs, ignore_errors=True)
    os.makedirs(runs, exist_ok=True)
    ran = run([binary, runs], WALL_RUN, cwd=os.path.dirname(binary))
    if ran["expired"]:
        return None, f"the probe ran past {WALL_RUN} s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}"


def probe_rows(score):
    """Scores F and M; answers the texts, or None."""
    binary, why = build_probe()
    if binary is None:
        for row_id in PROBE_ROWS:
            score(row_id, False, f"the probe did not build: {why}")
        return None
    answer, why = run_probe(binary)
    got = {r["id"]: r for r in (answer or {}).get("rows", [])}
    for row_id in PROBE_ROWS:
        r = got.get(row_id)
        if r is None:
            score(row_id, False, f"no row: {why or 'the probe did not answer it'}")
        else:
            score(row_id, bool(r["ok"]), r["detail"])
    if answer is None:
        return None
    with open(os.path.join(WORK, "answer.json"), "w") as f:
        json.dump(answer, f, indent=1, sort_keys=True)
    return answer.get("texts")


# ---------------------------------------------------------------------------
# Launch S.


def last_user_text(body):
    messages = body.get("messages") or []
    if not messages or messages[-1].get("role") != "user":
        return None
    content = messages[-1].get("content")
    if isinstance(content, str):
        return content
    texts = [b.get("text") for b in content or [] if b.get("type") == "text"]
    return texts[-1] if texts else None


def context_block(name, path, scope, playhead, selection):
    return "\n".join([
        f"<{TAG}>",
        f"name: {name}",
        f"path: {path if path else 'none (never saved)'}",
        "scope: " + (f"{scope} (a nest is open: ids and times are its own)" if scope is not None
                     else "none (the timeline is open)"),
        f"playhead: {playhead} ({playhead / 600000:.3f} s)",
        "selection: " + (", ".join(str(i) for i in selection) if selection else "none"),
        f"</{TAG}>",
    ])


def contains_text(value, needle):
    if isinstance(value, str):
        return needle in value
    if isinstance(value, dict):
        return any(contains_text(v, needle) for v in value.values())
    if isinstance(value, list):
        return any(contains_text(v, needle) for v in value)
    return False


def s_setup(asp, app, folder):
    """A saved project with a text clip; answers (project path, clip id)."""
    path = os.path.join(folder, "S.reelcut")
    shutil.rmtree(path, ignore_errors=True)
    saved = app.must("new_project", path=path)["saved"]
    project = app.must("get_project", project=saved)["project"]
    clip = project["next_id"]
    track = project["tracks"][-1]["id"]
    # 6 s, so both playheads S2 sets are inside the project (a playhead is
    # clamped to its end).
    app.must("add_text_clip", project=saved, track=track, at=0, duration=6000000,
             text={"content": "Welcome"})
    return saved, clip


def row_s2(asp, app, fake, ctx):
    saved, clip = ctx["saved"], ctx["clip"]
    app.must("set_playhead", project=saved, t=2400000)
    app.must("set_selection", project=saved, clips=[clip])
    got = app.must("get_project", project=saved)
    block1 = context_block(got["name"], got["path"], None, 2400000, [clip])
    text1 = "What is at the playhead?"
    fake.scenario([asp.say("S: turn one.")])
    ok, answer = app.call("assistant_send", project=saved, text=text1, timeout=WALL_TURN)
    if not ok:
        return False, f"assistant_send refused: {answer}"
    log1 = fake.log()
    first = asp.posts(log1)
    ctx["s1_body"] = (first[0].get("body") or {}) if first else None
    if not first:
        return False, f"no POST in turn 1; {asp.brief(answer)}"
    body1 = first[0].get("body") or {}
    got1 = last_user_text(body1)
    right1 = got1 == block1 + "\n" + text1

    app.must("set_playhead", project=saved, t=4800000)
    app.must("set_selection", project=saved, clips=[])
    block2 = context_block(got["name"], got["path"], None, 4800000, [])
    text2 = "And now?"
    fake.scenario([asp.say("S: turn two.")])
    ok, answer2 = app.call("assistant_send", project=saved, text=text2, timeout=WALL_TURN)
    if not ok:
        return False, f"turn 2's assistant_send refused: {answer2}"
    second = asp.posts(fake.log())
    if not second:
        return False, f"no POST in turn 2; {asp.brief(answer2)}"
    body2 = second[0].get("body") or {}
    got2 = last_user_text(body2)
    right2 = got2 == block2 + "\n" + text2
    same = (body2.get("messages") or [None])[0] == (body1.get("messages") or [None])[0]
    good = right1 and right2 and same and answer["state"] == "finished" \
        and answer2["state"] == "finished"
    return good, (f"turn 1 last user text is the block + text {right1} ({got1!r:.160}); turn 2 "
                  f"{right2} ({got2!r:.160}); turn 2 messages[0] == turn 1's {same}; states "
                  f"{answer['state']}, {answer2['state']}")


def row_s1(asp, texts, ctx):
    body = ctx.get("s1_body")
    if body is None:
        return False, "no POST from S2's turn 1 to read"
    if texts is None:
        return False, "the probe gave no texts to compare"
    system = asp.system_text(body)
    wanted = texts["system"] + "\n\n" + texts["search_guide"]
    return system == wanted, (f"POST 1's system {len(system or '')} chars == system "
                              f"({len(texts['system'])}) + blank line + search_guide "
                              f"({len(texts['search_guide'])}): {system == wanted}")


def row_s3(asp, app, fake, texts, ctx):
    if texts is None:
        return False, "the probe gave no texts to compare"
    fake.scenario([dict(asp.say("S: turn three."), input_tokens=300000),
                   asp.say("S: the summary.")])
    ok, answer = app.call("assistant_send", project=ctx["saved"], text="One more thing.",
                          timeout=WALL_TURN)
    if not ok:
        return False, f"assistant_send refused: {answer}"
    sent = asp.posts(fake.log())
    started = [e for e in answer.get("events", []) if e.get("type") == "compaction_started"]
    carried = len(sent) >= 2 and contains_text(sent[1].get("body"),
                                               texts["compaction_instructions"])
    return carried and bool(started), (f"{len(sent)} POSTs; compaction_started "
                                       f"{bool(started)}; POST 2 carries "
                                       f"compaction_instructions verbatim {carried}")


def launch_s(asp, app_path, port, secrets, fake, texts, score, guarded, only_s2=False):
    folder = os.path.join(WORK, "s")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    app = asp.App("S" if not only_s2 else "mutant", app_path,
                  ["-AgentServerEnabled", "YES", "-RCSecretFolder", secrets], fake.base,
                  port=port)
    ctx = {}
    ids = ["S2"] if only_s2 else ["S0", "S2", "S1", "S3"]
    try:
        app.connect()
        if not only_s2:
            complaints = [l for l in app.log().splitlines() if "Reelcut: " in l]
            score("S0", not complaints, f"`Reelcut: ` lines {complaints[:2]}")
        ctx["saved"], ctx["clip"] = s_setup(asp, app, folder)
        guarded("S2", row_s2, asp, app, fake, ctx)
        if not only_s2:
            guarded("S1", row_s1, asp, texts, ctx)
            guarded("S3", row_s3, asp, app, fake, texts, ctx)
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        for row_id in ids:
            if row_id not in [r for r, _, _ in RESULTS]:
                score(row_id, False, f"launch S could not run: {type(error).__name__}: {error}")
    finally:
        app.stop()


def stand_in_posts():
    """Every POST the stand-in has logged to its `requests.jsonl`, across
    scenarios (a scenario resets only its in-memory log)."""
    count = 0
    try:
        with open(os.path.join(WORK, "fake", "requests.jsonl")) as handle:
            for line in handle:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if entry.get("method") == "POST" and entry.get("path", "").startswith(
                        "/v1/messages"):
                    count += 1
    except OSError:
        pass
    return count


# ---------------------------------------------------------------------------
# The mutant: `send` writes the bare text.


def build_mutant(asp):
    base = os.path.join(WORK, "mutant")
    shutil.rmtree(base, ignore_errors=True)
    root, reason = tree_copy.make_copy(os.path.join(base, "tree"))
    if root is None:
        return None, reason
    session = os.path.join(root, "app", "Sources", "AssistantSession.swift")
    with open(session) as handle:
        text = handle.read()
    if text.count(SEND) != 1:
        return None, f"AssistantSession.swift has {text.count(SEND)} `{SEND}`, not 1"
    with open(session, "w") as handle:
        handle.write(text.replace(SEND, "text"))
    print(f"mutant: `{SEND}` → `text` in the copy; make app (up to {WALL_BUILD} s)…",
          flush=True)
    built = bounded.run(["make", "app"], WALL_BUILD, cwd=root, env=child_env())
    app = os.path.join(root, asp.APP_PATH)
    if built["expired"] or built["rc"] != 0 or not os.path.exists(os.path.join(app, asp.BINARY)):
        tail = [l for l in (built["stdout"] + built["stderr"]).splitlines() if l.strip()][-3:]
        return None, f"make app exit {built['rc']} (expired {built['expired']}): {tail}"
    print(f"mutant: built in {built['seconds']:.0f} s", flush=True)
    return app, None


# ---------------------------------------------------------------------------

RESULTS = []  # (id, state, detail): state "ok" | "FAIL" | "SKIP"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--probe", action="store_true", help="F and M alone (make test)")
    parser.add_argument("--live", action="store_true",
                        help="the evaluation against the real API; needs --cap and the key")
    parser.add_argument("--rehearse", action="store_true",
                        help="the evaluation against the stand-in, scripted")
    parser.add_argument("--wrong", action="store_true",
                        help="with --rehearse: script the mistakes; every E row must FAIL")
    parser.add_argument("--cap", type=float, help="the spend cap in dollars, any positive figure")
    parser.add_argument("--month-spent", type=float, dest="month_spent",
                        help="with --rehearse: seed the scratch proofs' ledger with this many "
                             "dollars already spent this month")
    parser.add_argument("--mutant", choices=["bare-send"],
                        help="S2 alone, against a build whose send writes the bare text; FAILS")
    args = parser.parse_args()
    if args.cap is not None and not (math.isfinite(args.cap) and args.cap > 0):
        parser.error("--cap must be a positive finite figure")
    if args.wrong and not args.rehearse:
        parser.error("--wrong goes with --rehearse")
    if args.month_spent is not None and not args.rehearse:
        parser.error("--month-spent goes with --rehearse")
    if args.month_spent is not None and not (math.isfinite(args.month_spent)
                                             and args.month_spent >= 0):
        parser.error("--month-spent must be a finite figure of 0 or more")

    import assistant_prompt_eval as ev
    import budget

    if args.live or args.rehearse:
        cap = args.cap if args.cap is not None or args.live else ev.SUGGESTED_CAP
        for line in ev.headroom_lines(cap):
            print(line, flush=True)
        if args.live and args.cap is None:
            print("--live needs an explicit --cap <dollars>: nothing was launched", flush=True)
            return 2

    os.makedirs(WORK, exist_ok=True)

    def score(row_id, ok, detail, skip=False):
        state = "SKIP" if skip else ("ok" if ok else "FAIL")
        RESULTS.append((row_id, state, detail))
        print(f"{row_id} {state} — {detail}", flush=True)

    def guarded(row_id, function, *arguments):
        try:
            score(row_id, *function(*arguments))
        except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
            score(row_id, False, f"the instrument could not run: {type(error).__name__}: "
                                 f"{error}")

    if args.probe:
        probe_rows(score)
        return summary(None)

    import assistant_session_proof as asp
    asp.WORK = WORK

    if args.mutant:
        fake = None
        try:
            fake = asp.Fake(os.path.join(WORK, "fake"))
            secrets = asp.secret_folder()
            app, why = build_mutant(asp)
            if app is None:
                score("S2", False, f"the mutant did not build: {why}")
                print(f"0/1\nmutant {args.mutant}: the control could not be performed",
                      flush=True)
                return 2
            launch_s(asp, app, PORT_MUTANT, secrets, fake, None, score, guarded, only_s2=True)
        finally:
            if fake is not None:
                fake.stop()
        return summary(None)

    texts = probe_rows(score)
    release = os.path.join(ROOT, asp.APP_PATH)
    fake = None
    evaluation = None
    try:
        fake = asp.Fake(os.path.join(WORK, "fake"))
        secrets = asp.secret_folder()
        launch_s(asp, release, PORT_S, secrets, fake, texts, score, guarded)

        key = ev.anthropic_key() if args.live else None
        if args.live:
            print(f"Anthropic key (ANTHROPIC_API_KEY or .secrets/anthropic-key): "
                  f"{'present' if key else 'absent'}", flush=True)
        if not (args.live or args.rehearse):
            for row_id in EVAL_ROWS:
                score(row_id, True, "not asked (--live)", skip=True)
        elif args.live and not key:
            for row_id in EVAL_ROWS:
                score(row_id, True, "host: no key", skip=True)
        else:
            run_id = ev.run_id()
            if args.live:
                folder = os.path.join(WORK, "eval")
                ledger = os.path.join(WORK, "ledger.jsonl")
                spend = budget.SpendLedger(budget.LEDGER, "anthropic", "assistant_prompt_proof",
                                           run_id)
                relay = ev.Relay(ev.LIVE_UPSTREAM, ev.anthropic_key, args.cap, ledger, run_id,
                                 spend)
                stand_in = None
            else:
                folder = os.path.join(WORK, "rehearsal")
                ledger = os.path.join(folder, "ledger.jsonl")
                scratch = os.path.join(folder, "spend.jsonl")
                if os.path.exists(scratch):
                    os.remove(scratch)
                spend = budget.SpendLedger(scratch, "anthropic", "assistant_prompt_proof", run_id)
                if args.month_spent is not None:
                    seed = spend.reserve(args.month_spent, "seed", gate=False)
                    spend.settle(seed, args.month_spent, "seed")
                cap = args.cap if args.cap is not None else ev.SUGGESTED_CAP
                relay = ev.Relay(fake.base, lambda: ev.PROOF_KEY, cap, ledger, run_id, spend)
                stand_in = fake
            print(spend.describe(), flush=True)
            for name in os.listdir(folder) if os.path.isdir(folder) else []:
                if name.endswith(".reelcut") or name.endswith(".mp4"):
                    shutil.rmtree(os.path.join(folder, name), ignore_errors=True)
                    if os.path.exists(os.path.join(folder, name)):
                        os.remove(os.path.join(folder, name))
            os.makedirs(folder, exist_ok=True)
            posts_before = stand_in_posts()
            app = asp.App("E", release,
                          ["-AgentServerEnabled", "YES", "-RCSecretFolder", secrets,
                           "-ReelcutAssistantModel", "claude-opus-5-5"], relay.base,
                          port=PORT_E)
            try:
                app.connect()
                app.mcp.timeout = ev.TURN_SECONDS + 120
                evaluation = ev.Evaluation(app, relay, folder, score, stand_in=stand_in,
                                           wrong=args.wrong)
                evaluation.run()
            except Exception as error:  # noqa: BLE001
                for row_id in EVAL_ROWS[:6]:
                    if row_id not in [r for r, _, _ in RESULTS]:
                        score(row_id, False, f"launch E could not run: {type(error).__name__}: "
                                             f"{error}")
            finally:
                app.stop()
                relay.stop()
            if stand_in is not None:
                posted = stand_in_posts() - posts_before
                print(f"the stand-in logged {posted} POSTs during the evaluation", flush=True)
            score("H", *ev.row_h(relay))
            if args.live:
                score("K", *ev.row_k(key, WORK, app.log_path, extra=[spend.path]))
            else:
                score("K", True, "not asked (--live)", skip=True)
            evaluation.print_report(ledger)
    except Exception as error:  # noqa: BLE001
        score("setup", False, f"the instrument could not run: {type(error).__name__}: {error}")
    finally:
        if fake is not None:
            fake.stop()
    return summary(evaluation)


def summary(evaluation):
    scored = [r for r in RESULTS if r[1] != "SKIP"]
    passed = sum(1 for r in scored if r[1] == "ok")
    skipped = len(RESULTS) - len(scored)
    failed = [r[0] for r in scored if r[1] == "FAIL"]
    caps = evaluation.cap_failures if evaluation is not None else 0
    budgets = evaluation.budget_failures if evaluation is not None else 0
    print(f"{passed}/{len(scored)} pass, {skipped} skipped"
          + (f"; failed {failed} ({caps} on the cap, {budgets} on the budget, "
             f"{len(failed) - caps - budgets} otherwise)" if failed else ""), flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
