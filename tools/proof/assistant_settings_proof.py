#!/usr/bin/env python3
"""The assistant's chat settings — issue batch B48, #151 (spec §11 AI-20,
amending AI-9 and AI-18).

The probe `assistant_settings_probe.swift` (over `app/Sources`,
`assistant_tab_proof`'s `build_probe` line), run with the stand-in's dummy
`proof-key` in `-RCSecretFolder` (`assistant_session_proof.secret_folder`),
`-ReelcutInspectorCollapsed NO` and `RC_ASSISTANT_BASE_URL` at the stand-in:
  CS1  `AssistantChatSettings` over a fresh suite (defaults, the range's
       ends either side, null when off, round-trip), `settingsJSON(defaults:
       suite)` over stored (false, 40,000, true) = {null, true}, and the pane
       over the suite: "40,000" stores and posts `settings` once, the same
       again nothing, "10000" beeps back writing nothing, each box posts once,
       never `key` or `model`, `sync()` shows the stored three; and the
       probe's `clearTriggerTokens` equals `CLEAR_TRIGGER_TOKENS` in
       `agent/src/main.ts`
  CS2  a real editor's session: turn 1 (50,000 input tokens) no compaction;
       the pane on `.standard` commits "40,000" and clearing on — posted
       ["settings","settings"], the same session, not closed, the transcript
       unchanged; turn 2 (50,000) compacts once at 40,000 ≤ used < 300,000;
       the compaction box off; turn 3 (950,000) no compaction. The stand-in:
       exactly 4 POSTs, no failures; POST 1 without `context_management` and
       without the `context-management-2025-06-27` beta; POSTs 2 and 4 with
       `context_management.edits[0]` the clear edit (trigger 150,000 input
       tokens, keep 5 tool uses, at least 50,000) and the beta; POST 3 with
       `compaction`, POST 4 without
The Release app (`assistant_session_proof`'s `App`, a scratch socket), launched with
`-ReelcutAssistantAutoCompact NO -ReelcutAssistantClearToolResults YES
-RCDevAssistantAutoCompact 1`:
  CS3  `new_project`, then `assistant_send` against a reply and a compaction
       reply: `finished` with `compaction_started` and `compacted` (the knob
       wins over the switch, AI-18 as amended); 2 POSTs, the first with the
       clear edit and the beta, the second with `compaction`; no `Reelcut: `
       line and no stand-in failure

    python3 tools/proof/assistant_settings_proof.py
    python3 tools/proof/assistant_settings_proof.py --mutant fixed-settings      # CS1 FAILS
    python3 tools/proof/assistant_settings_proof.py --mutant no-live-settings    # CS2 FAILS
    python3 tools/proof/assistant_settings_proof.py --mutant settings-ends       # CS2 FAILS
    python3 tools/proof/assistant_settings_proof.py --mutant fixed-settings-app  # CS3 FAILS

`fixed-settings`, `no-live-settings` and `settings-ends` build the probe over a
copy of `app/Sources` with one literal replaced in the file `MUTANTS` names
(`settingsJSON` reads `AssistantChatSettings()`; the editor's settings arm
writes nothing to the session; the arm never taken, so a settings change ends
the conversation) and run CS1 and CS2; `fixed-settings-app` makes
`fixed-settings`' edit in a `tree_copy.make_copy` tree, runs `make app` there
and runs CS3 against it. The named row must FAIL: exit 1 (caught), 0 when it
passes (survived). A literal not found exactly once, a build that failed, or
(rule R, issue batch B13) a named row never scored or scored by a path where
its own comparison did not run, prints `mutant <name>: the control could not
be performed — <why>` and exits 2.

Prints `<ID> ok|FAIL — <detail>` per row, then `n/m`; exit 0 only when every
row passes. An instrument that cannot run is a scored FAIL. No network, no key
but the dummy `proof-key`; every child has `ANTHROPIC_API_KEY` and
`RC_ASSEMBLYAI_KEY` popped. Rule H: only this script's processes are killed.
"""

import argparse
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import assistant_session_proof as asp  # noqa: E402
import assistant_tab_proof as atp  # noqa: E402
import bounded  # noqa: E402
import tree_copy  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_settings")
asp.WORK = WORK  # App, Fake and the secret folder write under this proof's folder
atp.WORK = WORK
RELEASE = os.path.join(ROOT, asp.APP_PATH)
PROBE_SWIFT = os.path.join(HERE, "assistant_settings_probe.swift")
MAIN_TS = os.path.join(ROOT, "agent", "src", "main.ts")
WALL_RUN, WALL_TURN = 300, 60
PROBE_ROWS = ["CS1", "CS2"]
BETA = "context-management-2025-06-27"
CLEAR_EDIT = {"type": "clear_tool_uses_20250919",
              "trigger": {"type": "input_tokens", "value": 150000},
              "keep": {"type": "tool_uses", "value": 5},
              "clear_at_least": {"type": "input_tokens", "value": 50000}}
FIXED = ("AssistantConfiguration.swift", "AssistantChatSettings.load(from: defaults)",
         "AssistantChatSettings()")
MUTANTS = {
    # name: (file in app/Sources, before — exactly once, after, the row that must FAIL)
    "fixed-settings": (*FIXED, "CS1"),
    "no-live-settings": ("EditorViewController+Assistant.swift",
                         "assistant?.updateSettings(AssistantConfiguration.settingsJSON())",
                         "_ = AssistantConfiguration.settingsJSON()", "CS2"),
    "settings-ends": ("EditorViewController+Assistant.swift", 'if change == "settings" {',
                      'if change == "never" {', "CS2"),
}
TREE_MUTANTS = {"fixed-settings-app": (*FIXED, "CS3")}


def compaction_reply(text):
    """`assistant_compaction_proof.compacted_reply`'s shape."""
    return {"content": [{"type": "compaction", "content": text}],
            "stop_reason": "compaction",
            "iterations": [{"type": "compaction", "input_tokens": 30_000, "output_tokens": 900,
                            "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}]}


def clear_trigger_in_main_ts():
    with open(MAIN_TS) as f:
        found = re.search(r"const CLEAR_TRIGGER_TOKENS = ([\d_]+);", f.read())
    return int(found.group(1).replace("_", "")) if found else None


def beta_header(post):
    headers = {k.lower(): v for k, v in post.get("headers", {}).items()}
    return headers.get("anthropic-beta", "")


def clear_edit(post):
    body = post.get("body") if isinstance(post.get("body"), dict) else {}
    edits = (body.get("context_management") or {}).get("edits") or []
    return edits[0] if edits else None


def has_clear(post):
    return clear_edit(post) == CLEAR_EDIT and BETA in beta_header(post)


def lacks_clear(post):
    body = post.get("body") if isinstance(post.get("body"), dict) else {}
    return "context_management" not in body and BETA not in beta_header(post)


def has_compaction(post):
    body = post.get("body") if isinstance(post.get("body"), dict) else {}
    return body.get("compaction") is not None


def post_brief(post):
    return (f"context_management {json.dumps(clear_edit(post))}, beta "
            f"{BETA in beta_header(post)}, compaction {has_compaction(post)}")


# ---------------------------------------------------------------------------
# CS1 and CS2: the probe.


def rows_probe(score, fake, secrets, sources=None, label=""):
    """Builds and runs the probe over `sources` (app/Sources by default)
    against the stand-in, and scores CS1 and CS2."""
    probe_dir = os.path.join(WORK, "probe") if sources is None else os.path.join(
        os.path.dirname(sources), "probe")
    atp.PROBE_DIR = probe_dir
    atp.PROBE_SWIFT = PROBE_SWIFT
    atp.SOURCES = sources or os.path.join(ROOT, "app", "Sources")
    binary, why = atp.build_probe(atp.SOURCES, probe_dir)
    if binary is None:
        for row_id in PROBE_ROWS:
            score(row_id, False, f"the probe did not build: {why}", instrument=True)
        return
    fake.scenario([dict(asp.say("CS2: one."), input_tokens=50_000),
                   dict(asp.say("CS2: two."), input_tokens=50_000),
                   compaction_reply("CS2: the conversation so far, summarised."),
                   dict(asp.say("CS2: three."), input_tokens=950_000)])
    ran = bounded.run([binary, "-RCSecretFolder", secrets, "-ReelcutInspectorCollapsed", "NO"],
                      WALL_RUN, cwd=probe_dir,
                      env=asp.child_env({"RC_ASSISTANT_BASE_URL": fake.base}))
    answer = None
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            answer = json.loads(line[len("ANSWER "):])
    with open(os.path.join(probe_dir, "probe-answer.json"), "w") as f:
        json.dump(answer, f, indent=1, sort_keys=True)
    got = {r["id"]: r for r in (answer or {}).get("rows", [])}
    log = fake.log()
    failures = log.get("failures", [])
    posts = asp.posts(log)

    r = got.get("CS1")
    if r is None:
        score("CS1", False, f"no row (exit {ran['rc']}, expired {ran['expired']}): "
                            f"{ran['stderr'].strip()[-300:]}", instrument=True)
    else:
        probe_trigger = (answer or {}).get("clearTriggerTokens")
        helper_trigger = clear_trigger_in_main_ts()
        same = probe_trigger is not None and probe_trigger == helper_trigger
        score("CS1", bool(r["ok"]) and same,
              f"{label}{r['detail']}; clearTriggerTokens {probe_trigger}, main.ts "
              f"CLEAR_TRIGGER_TOKENS {helper_trigger} (equal {same})")

    r = got.get("CS2")
    if r is None:
        score("CS2", False, f"no row (exit {ran['rc']}, expired {ran['expired']}): "
                            f"{ran['stderr'].strip()[-300:]}", instrument=True)
        return
    stand_in = (len(posts) == 4 and not failures and lacks_clear(posts[0])
                and has_clear(posts[1]) and has_clear(posts[3])
                and has_compaction(posts[2]) and not has_compaction(posts[3]))
    briefs = "; ".join(f"POST {i + 1}: {post_brief(p)}" for i, p in enumerate(posts))
    score("CS2", bool(r["ok"]) and stand_in,
          f"{label}{r['detail']}; the stand-in: {len(posts)} POSTs ({briefs}); failures "
          f"{failures[:2]}")


# ---------------------------------------------------------------------------
# CS3: the Release app.


def row_cs3(app_path, fake, secrets, tag="CS3"):
    folder = os.path.join(WORK, "cs3")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    fake.scenario([asp.say("CS3: done."),
                   compaction_reply("CS3: the conversation so far, summarised.")])
    app = asp.App(tag, app_path,
                  ["-RCSecretFolder", secrets,
                   "-ReelcutAssistantAutoCompact", "NO", "-ReelcutAssistantClearToolResults",
                   "YES", "-RCDevAssistantAutoCompact", "1"], fake.base)
    try:
        app.connect()
        a = app.must("new_project", path=os.path.join(folder, "CS3.reelcut"))["saved"]
        answer = app.must("assistant_send", project=a, text="CS3 one turn.", timeout=WALL_TURN)
        complaints = [line for line in app.log().splitlines() if "Reelcut: " in line]
    finally:
        app.stop()
    events = answer.get("events", []) if isinstance(answer, dict) else []
    order = [e.get("type") for e in events
             if e.get("type") in ("compaction_started", "compacted", "compaction_failed")]
    log = fake.log()
    failures = log.get("failures", [])
    posts = asp.posts(log)
    ok = (isinstance(answer, dict) and answer.get("state") == "finished"
          and order == ["compaction_started", "compacted"] and len(posts) == 2
          and has_clear(posts[0]) and has_compaction(posts[1]) and not complaints
          and not failures)
    briefs = "; ".join(f"POST {i + 1}: {post_brief(p)}" for i, p in enumerate(posts))
    return ok, (f"{asp.brief(answer)}; compaction events {order}; {len(posts)} POSTs "
                f"({briefs}); `Reelcut: ` lines {complaints[:2]}; stand-in failures "
                f"{failures[:2]}")


# ---------------------------------------------------------------------------
# Mutants.


def mutant_sources(name):
    """(Sources path, None) or (None, reason): app/Sources copied with the
    mutant's `before` replaced once in its file."""
    file, before, after, _ = MUTANTS[name]
    base = os.path.join(WORK, "mutants", name)
    sources = os.path.join(base, "Sources")
    shutil.rmtree(sources, ignore_errors=True)
    os.makedirs(sources)
    for entry in sorted(os.listdir(os.path.join(ROOT, "app", "Sources"))):
        if entry.endswith(".swift"):
            shutil.copy2(os.path.join(ROOT, "app", "Sources", entry),
                         os.path.join(sources, entry))
    path = os.path.join(sources, file)
    text = open(path).read() if os.path.exists(path) else ""
    if text.count(before) != 1:
        return None, f"{file} holds {before!r} {text.count(before)} times, not once"
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    return sources, None


def build_tree_mutant(name):
    """(app, None): `make app` over a tree copy with the mutant applied; or
    (None, reason)."""
    file, before, after, _ = TREE_MUTANTS[name]
    base = os.path.join(WORK, "mutant")
    tree_copy.remove_tree(base)
    root, reason = tree_copy.make_copy(os.path.join(base, "tree"))
    if root is None:
        return None, reason
    path = os.path.join(root, "app", "Sources", file)
    text = open(path).read() if os.path.exists(path) else ""
    if text.count(before) != 1:
        return None, f"{file} holds {before!r} {text.count(before)} times, not once"
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    print(f"mutant: {name} applied to the copy's {file}; make app (up to {asp.WALL_BUILD} s)…",
          flush=True)
    built = bounded.run(["make", "app"], asp.WALL_BUILD, cwd=root, env=asp.child_env())
    app = os.path.join(root, asp.APP_PATH)
    if built["expired"] or built["rc"] != 0 or not os.path.exists(os.path.join(app, asp.BINARY)):
        tail = [l for l in (built["stdout"] + built["stderr"]).splitlines() if l.strip()][-3:]
        return None, f"make app exit {built['rc']} (expired {built['expired']}): {tail}"
    print(f"mutant: built in {built['seconds']:.0f} s", flush=True)
    return app, None


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=sorted([*MUTANTS, *TREE_MUTANTS]),
                        help="a made-to-fail variant; its named row must FAIL (exit 1)")
    args = parser.parse_args()
    os.makedirs(WORK, exist_ok=True)
    results = []

    def score(row_id, ok, detail, *, instrument=False):
        results.append((row_id, ok, instrument))
        print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    named, why = None, None
    fake = None
    try:
        fake = asp.Fake(os.path.join(WORK, "fake"))
        secrets = asp.secret_folder()
        if args.mutant in MUTANTS:
            file, before, after, named = MUTANTS[args.mutant]
            sources, why = mutant_sources(args.mutant)
            if sources is not None:
                rows_probe(score, fake, secrets, sources, f"(mutant {args.mutant}) ")
        elif args.mutant in TREE_MUTANTS:
            named = TREE_MUTANTS[args.mutant][3]
            built, why = build_tree_mutant(args.mutant)
            if built is not None:
                try:
                    ok, detail = row_cs3(built, fake, secrets, tag=f"mutant-{args.mutant}")
                    score("CS3", ok, f"(mutant {args.mutant}) {detail}")
                except Exception as error:  # noqa: BLE001
                    score("CS3", False, f"the instrument could not run: "
                                        f"{type(error).__name__}: {error}", instrument=True)
        else:
            rows_probe(score, fake, secrets)
            try:
                score("CS3", *row_cs3(RELEASE, fake, secrets))
            except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
                score("CS3", False, f"the instrument could not run: {type(error).__name__}: "
                                    f"{error}", instrument=True)
    except Exception as error:  # noqa: BLE001
        score("setup", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)
    finally:
        if fake is not None:
            fake.stop()

    passed = sum(1 for _, ok, _ in results if ok)
    print(f"{passed}/{len(results)}", flush=True)
    if not args.mutant:
        return 0 if passed == len(results) else 1
    if why:
        print(f"mutant {args.mutant}: the control could not be performed — {why}", flush=True)
        return 2
    scored = [r for r, _, _ in results]
    broken = [r for r, _, instrument in results if instrument]
    if named not in scored or broken:
        reason = (f"{named} was never scored" if named not in scored
                  else f"scored as instrument failures: {', '.join(broken)}")
        print(f"mutant {args.mutant}: the control could not be performed — {reason}",
              flush=True)
        return 2
    caught = any(r == named and not ok for r, ok, _ in results)
    print(f"mutant {args.mutant}: {named} {'FAILS — caught' if caught else 'passed — it SURVIVED'}",
          flush=True)
    return 1 if caught else 0


if __name__ == "__main__":
    sys.exit(main())
