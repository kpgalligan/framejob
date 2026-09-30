#!/usr/bin/env python3
"""The Assistant tab — road map 12 A2 (spec §11 AI-4, AI-7, AI-8, AI-11,
AI-14).

P — the probe `assistant_tab_probe.swift`, compiled over `app/Sources` minus
`main.swift` on `harness/build.sh`'s swiftc line (`-D REELCUT_DEV_TOOLS`; a
probe that does not build is a scored FAIL on every P row), with the Release
build's helper copied to `<probe dir>/Contents/Helpers/reelcut-agent`, run
with a DUMMY key in a `-RCSecretFolder` of its own,
`-ReelcutInspectorCollapsed NO` and `RC_ASSISTANT_BASE_URL=http://127.0.0.1:9`:
  P1  the transcript's mapping over a scripted event list (runs, every
      sentence, usage, the three answers)
  P2  the context meter's three figures
  P3  showAssistant (View ▸ Assistant's method): the tab, the composer first
      responder
  P4  a question shown: Return in the composer answers nothing (an idle
      Return sending is the control); Allow / Deny `mouseDown` answer once
      each, true then false
  P5  AI-14: a changed selection keeps the Assistant tab (from Media it shows
      Clip: the control); `clipPicked()` shows Clip
  P6  a real session ended by a posted model change (closed, `assistant` nil,
      the note) and by the Clear button (the transcript empty)
  P7  Settings' Assistant pane over MemoryStores and a suite: Save writes,
      empties the field, masks the placeholder and posts `key`; Remove; a
      model commit writes the suite and posts `model`; a commit that leaves
      the model where it was (`""` → claude-opus-5-5, the same text again)
      posts nothing; the pane sits under the Transcription heading
  P8  (#150) the probe run alone under `--close <path>`, against the
      stand-in scripted to ask for `export` to `work/assistant_tab/p8/P8.mp4`:
      the question `export writes <path>`; then `window.close()` with the
      session held strongly — the session closed, `editor.assistant` nil,
      exactly one `answer` after the question, `{allowed: false, by:
      "close"}`, the window's next lane call answered within 10 s, no file;
      and no failure in the stand-in's log

Live A (`-AgentServerEnabled YES`, the dummy `proof-key` in `-RCSecretFolder`,
`RC_ASSISTANT_BASE_URL` at `anthropic_fake.py`, port 4874), every turn through
the tab's own controls (`assistant_send` / `assistant_answer` with `pane`):
  L0  no `Reelcut: ` line
  L1  `perform_menu_item View ▸ Assistant` shows the tab; the inspector dump
      has the composer and Send visible, the no-key pointer and the question
      hidden, and no layout problem inside the tab
  L2  a scripted add_marker turn sent through the composer: finished; the
      dump's entries are the person's line, `add_marker (…`, the reply and
      the turn's cost line, exactly (road map 13 P2: two stand-in replies at
      the bundled table, its date the local date of anthropic.json's
      `litellm_commit_date`, not refreshed for want of a cache); the composer
      is empty; the marker is on the project
  L3  Deny through the pane: the row reads `export writes D`, Send reads
      Stop, and no layout problem inside the tab; then no file, the row
      hidden, `Declined: …`
  L4  Allow through the pane over a sentinel E: `export REPLACES E`, a movie
      written, `Allowed: …`
  L5  Stop through the pane while asking: no file, `Declined (stop): …`
  L6  `pane: true` with the Media tab showing is refused by name, and the
      stand-in hears nothing
  K   `proof-key` in no MCP answer, no layout dump and not the log
Launch B (the override set, no `-RCSecretFolder`: no key, AI-13):
  N1  View ▸ Assistant shows the no-key sentence and Open Settings…, and no
      composer

    python3 tools/proof/assistant_tab_proof.py
    python3 tools/proof/assistant_tab_proof.py --mutant no-forward        # L2 alone: FAILS
    python3 tools/proof/assistant_tab_proof.py --mutant no-close-decline  # P8 alone: FAILS

`no-forward` copies the tree with `tree_copy.make_copy` into
`work/assistant_tab/mutant/tree`, deletes the `session.onEvent =` line from
`EditorViewController+Assistant.swift`, runs `make app` there, and runs L1's
steps and L2 against that app: L2 must FAIL (exit 1; 0 when it survives). A
copy that did not build could not perform the control (exit 2). `no-close-decline` builds the
probe over a copy of `app/Sources` in `work/assistant_tab/mutants/` with
`close()`'s `decline(by: "close")` line removed (`MUTANTS`), and runs P8
alone: P8 must FAIL (exit 1); no build, or no such line, exits 2. Rule R
(issue batch B13): a mutant run whose row was never scored, or that scored
any row by a path where the row's own comparison did not run (the probe
printed no P8 row, an exception caught by `guarded`, the launch or the
setup failing), prints `mutant <name>: the control could not be performed —
<why>` and exits 2, never 1.

Prints `<ID> ok|FAIL — <detail>` per row, then `n/m`; exit 0 only when every
row passes. Safety as `assistant_session_proof.py`: every child's
environment has ANTHROPIC_API_KEY and RC_ASSEMBLYAI_KEY popped; the only keys
are dummies in 0600 files in scratch folders; the helper speaks only to the
stand-in or to a dead loopback port; only this script's processes are killed.
"""

import argparse
import datetime
import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import assistant_session_proof as asp  # noqa: E402
import bounded  # noqa: E402
import prices  # noqa: E402
import tree_copy  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_tab")
asp.WORK = WORK  # its App, Fake and secret folder write under this proof's folder
PROBE_DIR = os.path.join(WORK, "probe")
PROBE_SWIFT = os.path.join(HERE, "assistant_tab_probe.swift")
SOURCES = os.path.join(ROOT, "app", "Sources")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
RELEASE = os.path.join(ROOT, asp.APP_PATH)
HELPER = os.path.join(RELEASE, "Contents", "Helpers", "reelcut-agent")
FORWARD = "session.onEvent ="
PORT_A, PORT_B = 4874, 4877
WALL_BUILD, WALL_RUN, WALL_TURN = 900, 300, 60
PROBE_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7"]
# name: (file in app/Sources, before — exactly once, after, row)
MUTANTS = {"no-close-decline": ("AssistantSession.swift", '        decline(by: "close")\n', "",
                                "P8")}
STOP_TEXT = 'select_inspector_tab {tab: "assistant"} first'


def child_env(extra=None):
    return asp.child_env(extra)


# ---------------------------------------------------------------------------
# P: the probe.


def build_probe(sources=SOURCES, probe_dir=PROBE_DIR):
    """(binary, None) or (None, reason)."""
    os.makedirs(probe_dir, exist_ok=True)
    binary = os.path.join(probe_dir, "assistant_tab_probe")
    entry = os.path.join(probe_dir, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `cd core && cargo build --release` first"
    if not os.path.exists(HELPER):
        return None, f"{HELPER} is missing — run `make app` first"
    helpers = os.path.join(probe_dir, "Contents", "Helpers")
    os.makedirs(helpers, exist_ok=True)
    shutil.copy2(HELPER, os.path.join(helpers, "reelcut-agent"))
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    inputs = swift + [entry, LIB, os.path.join(ROOT, "app", "Bridging",
                                                "Reelcut-Bridging-Header.h"),
                      os.path.join(ROOT, "core", "include", "reelcut_core.h")]
    stamp = os.path.join(probe_dir, "sources.txt")
    listing = "\n".join(swift)
    if (os.path.exists(stamp) and open(stamp).read() == listing and os.path.exists(binary)
            and all(os.path.getmtime(f) < os.path.getmtime(binary) for f in inputs)):
        print(f"probe: {binary} (up to date)", flush=True)
        return binary, None
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60,
                      env=child_env())["stdout"].strip()
    if os.path.exists(binary):
        os.remove(binary)
    print(f"probe: building over {len(swift)} sources (up to {WALL_BUILD} s)…", flush=True)
    started = time.time()
    built = bounded.run(
        ["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
         "-module-name", "Reelcut", "-import-objc-header",
         os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary],
        WALL_BUILD, env=child_env())
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [l for l in built["stderr"].splitlines() if ": error:" in l]
        tail = [l for l in built["stderr"].strip().splitlines()[-4:] if l.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    with open(stamp, "w") as f:
        f.write(listing)
    print(f"probe: built in {time.time() - started:.0f} s", flush=True)
    return binary, None


def probe_secrets():
    folder = os.path.join(WORK, "probe-secrets")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    os.chmod(folder, 0o700)
    descriptor = os.open(os.path.join(folder, "anthropic-key"),
                         os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write("probe-dummy-key\n")
    return folder


def rows_p(score):
    binary, why = build_probe()
    if binary is None:
        for row_id in PROBE_ROWS:
            score(row_id, False, f"the probe did not build: {why}")
        return
    ran = bounded.run([binary, "-RCSecretFolder", probe_secrets(),
                       "-ReelcutInspectorCollapsed", "NO"], WALL_RUN, cwd=PROBE_DIR,
                      env=child_env({"RC_ASSISTANT_BASE_URL": "http://127.0.0.1:9"}))
    answer = None
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            answer = json.loads(line[len("ANSWER "):])
    if answer is None:
        why = (f"no answer (exit {ran['rc']}, expired {ran['expired']}): "
               f"{ran['stderr'].strip()[-300:]}")
    with open(os.path.join(WORK, "probe-answer.json"), "w") as f:
        json.dump(answer, f, indent=1, sort_keys=True)
    got = {r["id"]: r for r in (answer or {}).get("rows", [])}
    for row_id in PROBE_ROWS:
        r = got.get(row_id)
        if r is None:
            score(row_id, False, f"no row: {why if answer is None else 'not answered'}")
        else:
            score(row_id, bool(r["ok"]), r["detail"])


def row_p8(score, fake, secrets, binary=None):
    """P8: the probe under `--close`, against the stand-in (#150)."""
    if binary is None:
        binary, why = build_probe()
        if binary is None:
            score("P8", False, f"the probe did not build: {why}", instrument=True)
            return
    folder = os.path.join(WORK, "p8")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    path = os.path.join(folder, "P8.mp4")
    fake.scenario([asp.use("toolu_p8", "export", {"preset": "h264", "path": path}),
                   asp.say("P8: closed.")])
    ran = bounded.run([binary, "--close", path, "-RCSecretFolder", secrets,
                       "-ReelcutInspectorCollapsed", "NO"], WALL_RUN,
                      cwd=os.path.dirname(binary),
                      env=child_env({"RC_ASSISTANT_BASE_URL": fake.base}))
    answer = None
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            answer = json.loads(line[len("ANSWER "):])
    with open(os.path.join(folder, "probe-answer.json"), "w") as f:
        json.dump(answer, f, indent=1, sort_keys=True)
    r = {r["id"]: r for r in (answer or {}).get("rows", [])}.get("P8")
    failures = fake.log().get("failures", [])
    if r is None:
        score("P8", False, f"no row (exit {ran['rc']}, expired {ran['expired']}): "
                           f"{ran['stderr'].strip()[-300:]}", instrument=True)
    else:
        score("P8", bool(r["ok"]) and not failures,
              f"{r['detail']}; stand-in failures {failures[:2]}")


def mutant_probe(name):
    """(binary, None): the probe built over a copy of app/Sources with the
    mutant's `before` removed once; or (None, reason)."""
    file, before, after, _ = MUTANTS[name]
    base = os.path.join(WORK, "mutants", name)
    sources = os.path.join(base, "Sources")
    shutil.rmtree(sources, ignore_errors=True)
    os.makedirs(sources)
    for entry in sorted(os.listdir(SOURCES)):
        if entry.endswith(".swift"):
            shutil.copy2(os.path.join(SOURCES, entry), os.path.join(sources, entry))
    path = os.path.join(sources, file)
    text = open(path).read() if os.path.exists(path) else ""
    count = text.count(before)
    if count != 1:
        return None, f"{file} holds {before!r} {count} times, not once"
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    return build_probe(sources, os.path.join(base, "probe"))


# ---------------------------------------------------------------------------
# Reading the tab back through snapshot_ui.


class Dump:
    """One `snapshot_ui` of the editor's inspector, with its layout dump."""

    def __init__(self, app, project, name):
        path = os.path.join(WORK, "dumps", f"{name}.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        arguments = {"window": "editor", "view": "inspector", "path": path}
        if project is not None:
            arguments["project"] = project
        answer = app.must("snapshot_ui", **arguments)
        self.layout_path = answer.get("layout_path")
        with open(self.layout_path) as f:
            self.text = f.read()
        layout = json.loads(self.text)
        self.views = layout.get("views", [])
        self.problems = layout.get("problems", [])

    def by_id(self, identifier):
        return [v for v in self.views if v.get("id") == identifier]

    def visible(self, identifier):
        return any(not v.get("hidden") for v in self.by_id(identifier))

    def shown_text(self, identifier):
        texts = [v.get("text") for v in self.by_id(identifier) if not v.get("hidden")]
        return texts[0] if texts else None

    def entries(self):
        return [(v["id"][len("assistant.entry."):], v.get("text"))
                for v in self.views
                if (v.get("id") or "").startswith("assistant.entry.") and not v.get("hidden")]

    def tab_problems(self):
        """Problems on a view inside the `AssistantView`'s subtree."""
        roots = {v["i"] for v in self.views if v.get("class") == "AssistantView"}
        inside = set()
        for v in self.views:
            if v["i"] in roots or v.get("parent") in inside:
                inside.add(v["i"])
        return [p for p in self.problems if p.get("view") in inside]


def bundled_cost_line(replies):
    """The transcript's cost line for `replies` stand-in replies (100 input
    and 10 output tokens each on claude-opus-5-5) at the bundled table, in a
    session with no price cache."""
    table = prices.load()
    usage = {"input_tokens": 100, "output_tokens": 10, "cache_creation_input_tokens": 0,
             "cache_read_input_tokens": 0}
    dollars = replies * prices.price(usage, asp.DEFAULT_MODEL, table)["dollars"]
    instant = table["litellm_commit_date"]
    day = datetime.datetime.fromisoformat(instant.replace("Z", "+00:00")).astimezone()
    return (f"Cost: ${dollars:.4f} · Reelcut's estimate at LiteLLM prices (bundled table of "
            f"{day.strftime('%Y-%m-%d')}; not refreshed: no price cache is configured)")


def fmt_entries(entries):
    return [f"{kind}: {(text or '')[:60]}" for kind, text in entries]


# ---------------------------------------------------------------------------
# Live A.


def open_tab(app, ctx):
    """New project A, then View ▸ Assistant in its window."""
    a = app.must("new_project", path=os.path.join(ctx["folder"], "A.reelcut"))["saved"]
    ctx["A"] = a
    ctx["menu"] = app.must("perform_menu_item", project=a, path=["View", "Assistant"])
    ctx["tab"] = app.must("select_inspector_tab", project=a).get("tab")
    return a


def row_l0(app, ctx):
    complaints = [l for l in app.log().splitlines() if "Reelcut: " in l]
    return not complaints, f"`Reelcut: ` lines {complaints[:2]}"


def row_l1(app, ctx):
    a = open_tab(app, ctx)
    dump = Dump(app, a, "l1")
    ctx["dumps"].append(dump.text)
    wanted = {"composer": dump.visible("assistant.composer"),
              "send": dump.visible("assistant.send"),
              "clear": dump.visible("assistant.clear"),
              "nokey hidden": not dump.visible("assistant.nokey"),
              "question hidden": not dump.visible("assistant.question"),
              "settings hidden": not dump.visible("assistant.settings")}
    problems = dump.tab_problems()
    good = ctx["tab"] == "assistant" and all(wanted.values()) and not problems
    return good, (f"menu answered {str(ctx['menu'])[:80]!r}; tab {ctx['tab']!r}; {wanted}; "
                  f"problems in the tab {problems[:3]}; all problems {len(dump.problems)}")


def row_l2(app, fake, ctx):
    a = ctx["A"]
    text = "Put a marker at two seconds."
    fake.scenario([asp.use("toolu_l2", "add_marker", {"at": 1200000, "name": "L2 marker"}),
                   asp.say("L2: the marker is in.")])
    ok, answer = app.call("assistant_send", project=a, text=text, pane=True, timeout=WALL_TURN)
    if not ok:
        return False, f"assistant_send (pane) refused: {answer}"
    dump = Dump(app, a, "l2")
    ctx["dumps"].append(dump.text)
    entries = dump.entries()
    kinds = [k for k, _ in entries]
    person = [t for k, t in entries if k == "person"]
    meta = [t for k, t in entries if k == "meta"]
    reply = [t for k, t in entries if k == "reply"]
    composer = dump.shown_text("assistant.composer")
    marked = (1200000, "L2 marker") in asp.markers(app, a)
    cost = bundled_cost_line(2)
    good = (answer.get("state") == "finished" and kinds == ["person", "meta", "reply", "meta"]
            and person == [text] and len(meta) == 2 and meta[0].startswith("add_marker (")
            and meta[1] == cost
            and reply == ["L2: the marker is in."] and composer == "" and marked
            and dump.shown_text("assistant.send") == "Send")
    return good, (f"{asp.brief(answer)}; entries {fmt_entries(entries)}; last entry "
                  f"{(entries[-1][1] if entries else None)!r}, wanted {cost!r}; composer "
                  f"{composer!r}; Send reads {dump.shown_text('assistant.send')!r}; marker on "
                  f"A {marked}")


def pane_export(app, fake, ctx, tag, path, sentence, extra=None):
    replies = [asp.use(f"toolu_{tag}", "export", {"preset": "h264", "path": path}),
               asp.say(f"{tag.upper()}: done.")]
    fake.scenario(replies + (extra or []))
    ok, answer = app.call("assistant_send", project=ctx["A"], text=f"Export ({tag}).",
                          pane=True, timeout=WALL_TURN)
    if not ok:
        return None, f"assistant_send (pane) refused: {answer}"
    asked = (answer.get("question") or {}).get("sentence")
    if answer.get("state") != "asking" or asked != sentence:
        return None, f"send: {asp.brief(answer)}; wanted asking {sentence!r}"
    dump = Dump(app, ctx["A"], f"{tag}-asking")
    ctx["dumps"].append(dump.text)
    return dump, None


def answer_pane(app, ctx, value):
    return app.call("assistant_answer", project=ctx["A"], answer=value, pane=True,
                    timeout=WALL_TURN)


def row_l3(app, fake, ctx):
    app.must("add_text_clip", project=ctx["A"], track=1, at=0, duration=1200000)
    path = os.path.join(ctx["folder"], "D.mp4")
    sentence = f"export writes {path}"
    asking, why = pane_export(app, fake, ctx, "l3", path, sentence)
    if asking is None:
        return False, why
    row_text = asking.shown_text("assistant.question")
    stop = asking.shown_text("assistant.send")
    allow = asking.visible("assistant.allow") and asking.visible("assistant.deny")
    problems = asking.tab_problems()
    ok, answer = answer_pane(app, ctx, "deny")
    if not ok:
        return False, f"deny (pane) refused: {answer}"
    after = Dump(app, ctx["A"], "l3-after")
    ctx["dumps"].append(after.text)
    by = asp.answers_by(answer, "person")
    good = (row_text == sentence and stop == "Stop" and allow and not problems
            and answer.get("state") == "finished" and not os.path.exists(path)
            and not after.visible("assistant.question")
            and f"Declined: {sentence}" in [t for k, t in after.entries() if k == "meta"]
            and len(by) == 1 and by[0].get("allowed") is False
            and after.shown_text("assistant.send") == "Send")
    return good, (f"row {row_text!r}, Send {stop!r}, Allow/Deny shown {allow}, problems in "
                  f"the tab while asking {problems[:2]}; deny: "
                  f"{asp.brief(answer)}; no file {not os.path.exists(path)}; row hidden "
                  f"{not after.visible('assistant.question')}; meta "
                  f"{[t for k, t in after.entries() if k == 'meta'][-2:]}")


def row_l4(app, fake, ctx):
    path = os.path.join(ctx["folder"], "E.mp4")
    with open(path, "wb") as handle:
        handle.write(b"sentinel: not a movie\n")
    sentence = f"export REPLACES {path}"
    asking, why = pane_export(app, fake, ctx, "l4", path, sentence)
    if asking is None:
        return False, why
    row_text = asking.shown_text("assistant.question")
    ok, answer = answer_pane(app, ctx, "allow")
    if not ok:
        return False, f"allow (pane) refused: {answer}"
    with open(path, "rb") as handle:
        head = handle.read(12)
    after = Dump(app, ctx["A"], "l4-after")
    ctx["dumps"].append(after.text)
    good = (row_text == sentence and answer.get("state") == "finished"
            and head[4:8] == b"ftyp" and f"Allowed: {sentence}" in
            [t for k, t in after.entries() if k == "meta"])
    return good, (f"row {row_text!r}; allow: {asp.brief(answer)}; bytes 4–8 {head[4:8]!r}; "
                  f"meta {[t for k, t in after.entries() if k == 'meta'][-3:]}")


def row_l5(app, fake, ctx):
    path = os.path.join(ctx["folder"], "S.mp4")
    sentence = f"export writes {path}"
    asking, why = pane_export(app, fake, ctx, "l5", path, sentence,
                              extra=[asp.say("L5: a spare reply.")])
    if asking is None:
        return False, why
    ok, answer = answer_pane(app, ctx, "stop")
    if not ok:
        return False, f"stop (pane) refused: {answer}"
    time.sleep(1.0)  # a stopped call that ran would have written by now
    after = Dump(app, ctx["A"], "l5-after")
    ctx["dumps"].append(after.text)
    good = (answer.get("state") == "finished" and not os.path.exists(path)
            and f"Declined (stop): {sentence}" in [t for k, t in after.entries() if k == "meta"])
    return good, (f"stop: {asp.brief(answer)}; no file {not os.path.exists(path)}; meta "
                  f"{[t for k, t in after.entries() if k == 'meta'][-2:]}")


def row_l6(app, fake, ctx):
    a = ctx["A"]
    app.must("select_inspector_tab", project=a, tab="media")
    fake.scenario([asp.say("L6: never said.")])
    ok, answer = app.call("assistant_send", project=a, text="Anything.", pane=True,
                          timeout=WALL_TURN)
    time.sleep(0.5)
    heard = fake.log().get("requests", [])
    app.must("select_inspector_tab", project=a, tab="assistant")
    good = (not ok) and STOP_TEXT in str(answer) and not heard
    return good, (f"assistant_send (pane) with the Media tab: "
                  f"{'refused' if not ok else 'TAKEN'} {str(answer)[:120]!r}; stand-in "
                  f"requests {len(heard)}")


def row_k(app, ctx):
    in_answers = sum(1 for text in app.answers if asp.KEY in text)
    in_dumps = sum(1 for text in ctx["dumps"] if asp.KEY in text)
    in_log = asp.KEY in app.log()
    good = not in_answers and not in_dumps and not in_log
    return good, (f"{len(app.answers)} MCP answers, the key in {in_answers}; "
                  f"{len(ctx['dumps'])} dumps, in {in_dumps}; in the log {in_log}")


# ---------------------------------------------------------------------------
# Launch B.


def row_n1(fake):
    app = asp.App("B", RELEASE, ["-AgentServerEnabled", "YES",
                                 "-ReelcutInspectorCollapsed", "NO"], fake.base, port=PORT_B)
    try:
        app.connect()
        project = app.must("new_project").get("path")
        app.must("perform_menu_item", path=["View", "Assistant"])
        dump = Dump(app, project, "n1")
    finally:
        app.stop()
    nokey = dump.shown_text("assistant.nokey")
    wanted = {"no-key sentence": nokey == "Add your Anthropic API key in Settings to use the "
                                          "assistant.",
              "Open Settings… visible": dump.visible("assistant.settings"),
              "composer hidden": not dump.visible("assistant.composer"),
              "Send hidden": not dump.visible("assistant.send")}
    return all(wanted.values()), f"{wanted}; no-key text {nokey!r}"


# ---------------------------------------------------------------------------
# The mutant.


def build_mutant():
    base = os.path.join(WORK, "mutant")
    shutil.rmtree(base, ignore_errors=True)
    root, reason = tree_copy.make_copy(os.path.join(base, "tree"))
    if root is None:
        return None, reason
    glue = os.path.join(root, "app", "Sources", "EditorViewController+Assistant.swift")
    with open(glue) as handle:
        lines = handle.read().splitlines(keepends=True)
    hits = [l for l in lines if l.strip().startswith(FORWARD)]
    if len(hits) != 1:
        return None, f"the glue has {len(hits)} `{FORWARD}` lines, not 1"
    with open(glue, "w") as handle:
        handle.write("".join(l for l in lines if not l.strip().startswith(FORWARD)))
    print(f"mutant: `{FORWARD}` deleted from the copy; make app (up to {asp.WALL_BUILD} s)…",
          flush=True)
    built = bounded.run(["make", "app"], asp.WALL_BUILD, cwd=root, env=child_env())
    app = os.path.join(root, asp.APP_PATH)
    if built["expired"] or built["rc"] != 0 or not os.path.exists(os.path.join(app, asp.BINARY)):
        tail = [l for l in (built["stdout"] + built["stderr"]).splitlines() if l.strip()][-3:]
        return None, f"make app exit {built['rc']} (expired {built['expired']}): {tail}"
    print(f"mutant: built in {built['seconds']:.0f} s", flush=True)
    return app, None


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=["no-forward", "no-close-decline"],
                        help="no-forward: L2 alone, against a build without the session's "
                             "event forward; no-close-decline: P8 alone, against a probe "
                             "whose close() declines nothing; each must FAIL")
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

    fake = None
    try:
        fake = asp.Fake(os.path.join(WORK, "fake"))
        secrets = asp.secret_folder()
        folder = os.path.join(WORK, "a")
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder)
        ctx = {"folder": folder, "dumps": []}
        if args.mutant == "no-close-decline":
            binary, why = mutant_probe(args.mutant)
            if binary is None:
                score("P8", False, f"(mutant {args.mutant}) the control could not be "
                                   f"performed: {why}", instrument=True)
                print(f"0/1\nmutant {args.mutant}: the control could not be performed — "
                      f"the probe was not built: {why}", flush=True)
                return 2
            row_p8(lambda row_id, ok, detail, **kw: score(row_id, ok, f"(mutant {args.mutant}) "
                                                                   + detail, **kw),
                   fake, secrets, binary)
        elif args.mutant:
            built, why = build_mutant()
            if built is None:
                score("L2", False, f"the mutant did not build: {why}", instrument=True)
                print(f"0/1\nmutant {args.mutant}: the control could not be performed — "
                      f"the mutant did not build: {why}", flush=True)
                return 2
            app = asp.App("mutant", built, ["-AgentServerEnabled", "YES", "-RCSecretFolder",
                                            secrets, "-ReelcutInspectorCollapsed", "NO"],
                          fake.base, port=PORT_A)
            try:
                app.connect()
                open_tab(app, ctx)
                guarded("L2", lambda: (lambda ok, d: (ok, f"(no `{FORWARD}`) " + d))
                        (*row_l2(app, fake, ctx)))
            finally:
                app.stop()
        else:
            rows_p(score)
            try:
                row_p8(score, fake, secrets)
            except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
                score("P8", False, f"the instrument could not run: {type(error).__name__}: "
                                   f"{error}", instrument=True)
            app = asp.App("A", RELEASE, ["-AgentServerEnabled", "YES", "-RCSecretFolder",
                                         secrets, "-ReelcutInspectorCollapsed", "NO"],
                          fake.base, port=PORT_A)
            live = ("L0", "L1", "L2", "L3", "L4", "L5", "L6", "K")
            try:
                app.connect()
                guarded("L0", row_l0, app, ctx)
                guarded("L1", row_l1, app, ctx)
                guarded("L2", row_l2, app, fake, ctx)
                guarded("L3", row_l3, app, fake, ctx)
                guarded("L4", row_l4, app, fake, ctx)
                guarded("L5", row_l5, app, fake, ctx)
                guarded("L6", row_l6, app, fake, ctx)
                guarded("K", row_k, app, ctx)
            except Exception as error:  # noqa: BLE001
                for row_id in live:
                    if row_id not in [r for r, _, _ in results]:
                        score(row_id, False, f"launch A could not run: {error}",
                              instrument=True)
            finally:
                app.stop()
            guarded("N1", row_n1, fake)
    except Exception as error:  # noqa: BLE001
        score("setup", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)
    finally:
        if fake is not None:
            fake.stop()

    passed = sum(1 for _, ok, _ in results if ok)
    print(f"{passed}/{len(results)}", flush=True)
    if args.mutant:
        why = not_performed({"no-forward": "L2", "no-close-decline": "P8"}[args.mutant],
                            results)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}",
                  flush=True)
            return 2
    return 0 if passed == len(results) else 1


def not_performed(row_id, results):
    """Rule R (issue batch B13): why a mutant run could not perform its
    control — its row never scored, or any row scored as an instrument
    failure — or "" when it could."""
    if row_id not in [r for r, _, _ in results]:
        return f"{row_id} was never scored"
    broken = [r for r, _, instrument in results if instrument]
    return f"scored as instrument failures: {', '.join(broken)}" if broken else ""


if __name__ == "__main__":
    sys.exit(main())
