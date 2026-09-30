#!/usr/bin/env python3
"""Spend in the UI — road map 13 P4 (spec §11 P-2, P-4, P-5, P-7).

The probe `spend_ui_probe.swift` (over `app/Sources`, `assistant_tab_proof`'s
`build_probe` line, run with `TZ=America/Los_Angeles`):
  M1  the fold over a fixture ledger (September 2026 UTC): both month edges
      in, the seconds either side out, a fractional second in, `dollars` null
      and `true` unpriced, a torn line, `[]` and a bad time unreadable,
      `assemblyai` skipped, blanks ignored = {0.875, 3, 2, 3}
  M2  every Settings sentence and `amount`, exactly
  M3  `month` and `title` at both edges of September 2026 UTC
  C1  the transcript's conversation sum and figures; `.conversationCost`
      before `.usage` on `clear()` and `endConversation`, both reset
  C2  `AssistantView.reload` / `apply` → `assistant.spend`'s text and tooltip
  C3  Settings' pane in a window: no folder, an absent ledger (still absent
      after), a fixture ledger (`Reading…`, then its sentence within 5 s), then
      `AssistantSpend.record` → the sentence unchanged when `record` returns,
      then the new one within 5 s; the note exact
The Release app (`assistant_session_proof`'s `App`, `Fake`, `secret_folder`;
`assistant_tab_proof`'s `Dump` and `open_tab`), a dummy key, the stand-in:
  U0  no `Reelcut: ` line
  U1  a seeded `-RCSpendFolder` ledger (the current UTC month's start + 1 s,
      the previous month's end − 1 s, one unpriced line, one torn line):
      Reelcut ▸ Settings…, `snapshot_ui window: settings` → the month line
      equals this script's own fold and sentence, the note is exact, and
      neither label has a layout problem
  U2  the tab's `assistant.spend` reads "Nothing yet"; a two-reply pane turn
      and a one-reply turn → "$%.4f · Reelcut's estimate" of the tool-view
      dollars; Settings, re-captured (polled up to 5 s), equals the fold of
      the ledger as it now is
  U3  the override with no `-RCSpendFolder`: "This launch keeps no spend
      ledger."; the person's `spend.jsonl` and `anthropic-prices.json` keep
      their existence, size and mtime across this launch and the whole run
      (a concurrent person session can fail this row; rerun)

    python3 tools/proof/spend_ui_proof.py
    python3 tools/proof/spend_ui_proof.py --mutant local-month      # TimeZone.gmt →
                                                                    # TimeZone.current:
                                                                    # M1, M3 FAIL (exit 1)
    python3 tools/proof/spend_ui_proof.py --mutant unknown-as-zero  # an unpriced line
                                                                    # counted as priced:
                                                                    # M1 FAILs (exit 1)

A mutant runs the probe rows only, over a copy of `app/Sources`, and exits 1
when every row it names FAILs (the mutant is caught), 3 when one passed (it
survived, never confused with a clean run's 0) and 2 when its literal is not found exactly once or its probe did
not build (the control could not be performed) — and, by rule R (issue batch
B13), when a row it names was never scored or any row was scored "no row"
(a probe that printed none), which is never counted as caught. Prints `<ID> ok|FAIL —
<detail>` per row, then `n/m`. An instrument that cannot run is a scored
FAIL. No network, no key but the dummy `proof-key`; every child has
`ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY` popped. Rule H: only this
script's processes are killed.
"""

import argparse
import datetime
import json
import math
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import assistant_session_proof as asp  # noqa: E402
import assistant_tab_proof as atp  # noqa: E402
import bounded  # noqa: E402
import spend_proof as sp  # noqa: E402

WORK = os.path.join(HERE, "work", "spend_ui")
asp.WORK = WORK  # App, Fake and the secret folder write under this proof's folder
atp.WORK = WORK  # and so do the layout dumps
RELEASE = os.path.join(ROOT, asp.APP_PATH)
PROBE_SWIFT = os.path.join(HERE, "spend_ui_probe.swift")
PORT_U, PORT_U3 = 4899, 4893
WALL_TURN, WALL_SETTLE = 60, 5
PROBE_ROWS = ["M1", "M2", "M3", "C1", "C2", "C3"]
PROBE_TZ = "America/Los_Angeles"
NOTE = ("Reelcut's own estimate at LiteLLM prices, from its spend ledger. The Anthropic "
        "Console shows what your account was billed.")
NO_LEDGER = "This launch keeps no spend ledger."
SETTINGS = ["Reelcut", "Settings…"]
MUTANTS = {
    # name: (the literal, its replacement, the rows that must FAIL)
    "local-month": ("TimeZone.gmt", "TimeZone.current", ["M1", "M3"]),
    "unknown-as-zero": ("summary.unpriced += 1", "summary.priced += 1", ["M1"]),
}
INSTANT = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z$")


# ---------------------------------------------------------------------------
# The oracle: the UTC month, the fold and the sentence, written apart from the
# Swift they check.


def utc_month(now):
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    end = (start.replace(year=start.year + 1, month=1) if start.month == 12
           else start.replace(month=start.month + 1))
    return start, end


def parse_instant(text):
    if not isinstance(text, str) or not INSTANT.match(text):
        return None
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))


def fold(text, month):
    start, end = month
    dollars, priced, unpriced, unreadable = 0.0, 0, 0, 0
    for line in text.split("\n"):
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            entry = None
        at = parse_instant(entry.get("time")) if isinstance(entry, dict) else None
        if at is None:
            unreadable += 1
            continue
        if entry.get("service") != "anthropic" or not (start <= at < end):
            continue
        value = entry.get("dollars")
        if (isinstance(value, (int, float)) and not isinstance(value, bool)
                and math.isfinite(value) and value >= 0):
            priced += 1
            dollars += value
        else:
            unpriced += 1
    return dollars, priced, unpriced, unreadable


def amount(dollars):
    return "under $0.01" if 0 < dollars < 0.005 else f"${dollars:.2f}"


def sentence(summary, month):
    dollars, priced, unpriced, unreadable = summary
    title = month[0].strftime("%B %Y") + " (UTC)"
    n = priced + unpriced
    responses = f"{n} response" + ("" if n == 1 else "s")
    if n == 0:
        text = f"Nothing recorded in {title}."
    elif unpriced == 0:
        text = f"{title}: {amount(dollars)} over {responses}."
    elif priced == 0:
        text = f"{title}: {responses}; none could be priced."
    else:
        text = (f"{title}: {responses}; {unpriced} could not be priced, the rest came to "
                f"{amount(dollars)}.")
    if unreadable:
        text += f" {unreadable} ledger line{'' if unreadable == 1 else 's'} could not be read."
    return text


def stamp(instant):
    return instant.strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Settings through snapshot_ui.


class SettingsDump:
    """One `snapshot_ui` of the Settings window, with its layout dump."""

    def __init__(self, app, name):
        path = os.path.join(WORK, "dumps", f"{name}.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        answer = app.must("snapshot_ui", window="settings", path=path)
        with open(answer.get("layout_path")) as f:
            layout = json.load(f)
        self.views = layout.get("views", [])
        self.problems = layout.get("problems", [])

    def text(self, identifier):
        texts = [v.get("text") for v in self.views
                 if v.get("id") == identifier and not v.get("hidden")]
        return texts[0] if texts else None

    def problems_on(self, identifiers):
        """The layout problems on the views named, every kind."""
        indices = {v["i"] for v in self.views if v.get("id") in identifiers}
        return [p for p in self.problems if p.get("view") in indices]


def settings_until(app, want, name):
    """Captures Settings until its month line reads `want` or WALL_SETTLE
    passes; answers the last capture."""
    deadline = time.monotonic() + WALL_SETTLE
    while True:
        dump = SettingsDump(app, name)
        if dump.text("settings.assistant.spend") == want or time.monotonic() > deadline:
            return dump
        time.sleep(0.25)


def ledger_text(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


# ---------------------------------------------------------------------------
# The live rows.


def rows_u(fake, secrets, score):
    spend = os.path.join(WORK, "u", "spend")
    shutil.rmtree(os.path.dirname(spend), ignore_errors=True)
    os.makedirs(spend)
    ledger = os.path.join(spend, "spend.jsonl")
    now = datetime.datetime.now(datetime.timezone.utc)
    month = utc_month(now)
    previous_end = month[0] - datetime.timedelta(seconds=1)
    seed = [
        json.dumps({"time": stamp(month[0] + datetime.timedelta(seconds=1)),
                    "service": "anthropic", "dollars": 0.5}),
        json.dumps({"time": stamp(previous_end), "service": "anthropic", "dollars": 100}),
        json.dumps({"time": stamp(month[0] + datetime.timedelta(seconds=2)),
                    "service": "anthropic", "dollars": None}),
        '{"time": "' + stamp(now) + '", "serv',
    ]
    with open(ledger, "w") as f:
        f.write("\n".join(seed) + "\n")
    folder = os.path.join(WORK, "u")
    tab = {"folder": folder, "dumps": []}
    app = asp.App("U", RELEASE, ["-AgentServerEnabled", "YES", "-RCSecretFolder", secrets,
                                 "-RCSpendFolder", spend, "-ReelcutInspectorCollapsed", "NO"],
                  fake.base, port=PORT_U)
    try:
        app.connect()
        complaints = [line for line in app.log().splitlines() if "Reelcut: " in line]
        score("U0", not complaints, f"`Reelcut: ` lines {complaints[:2]}")

        # U1
        try:
            a = atp.open_tab(app, tab)
            opened = app.must("perform_menu_item", project=a, path=SETTINGS)
            want = sentence(fold(ledger_text(ledger), month), month)
            dump = settings_until(app, want, "u1")
            got, note = dump.text("settings.assistant.spend"), dump.text(
                "settings.assistant.spendnote")
            problems = dump.problems_on({"settings.assistant.spend",
                                         "settings.assistant.spendnote"})
            kinds = [w.get("kind") for w in opened.get("windows_opened", [])]
            score("U1", got == want and note == NOTE and not problems,
                  f"Settings… opened {kinds}; month line {got!r}, the oracle {want!r}; note "
                  f"exact {note == NOTE}; layout problems on the two labels {problems[:3]}")
        except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
            score("U1", False, f"the instrument could not run: {type(error).__name__}: {error}")
            score("U2", False, "not run: U1 could not open the tab and Settings")
            return

        # U2
        try:
            before = atp.Dump(app, a, "u2-before").shown_text("assistant.spend")
            fake.scenario([asp.use("toolu_u2", "add_marker", {"at": 1200000, "name": "U2"}),
                           asp.say("U2: the marker is in.")])
            one = app.must("assistant_send", project=a, text="U2 put a marker in.", pane=True,
                           timeout=WALL_TURN)
            fake.scenario([asp.say("U2: again.")])
            two = app.must("assistant_send", project=a, text="U2 again.", pane=True,
                           timeout=WALL_TURN)
            found = sp.costs(one.get("events", [])) + sp.costs(two.get("events", []))
            dollars = [e.get("cost", {}).get("dollars") for e in found]
            priced = all(e.get("cost", {}).get("kind") == "dollars" for e in found)
            want_tab = (f"${sum(dollars):.4f} · Reelcut's estimate" if priced and found
                        else None)
            dump = atp.Dump(app, a, "u2-after")
            tab_text = dump.shown_text("assistant.spend")
            want = sentence(fold(ledger_text(ledger), month), month)
            settings = settings_until(app, want, "u2")
            got = settings.text("settings.assistant.spend")
            score("U2", before == "Nothing yet" and len(found) == 3 and priced
                  and tab_text == want_tab and got == want and not dump.tab_problems(),
                  f"tab before {before!r}; turns {one.get('state')}, {two.get('state')}; "
                  f"tool-view dollars {dollars}; tab after {tab_text!r}, wanted {want_tab!r}; "
                  f"tab problems {dump.tab_problems()[:2]}; Settings {got!r}, the oracle "
                  f"{want!r}")
        except Exception as error:  # noqa: BLE001
            score("U2", False, f"the instrument could not run: {type(error).__name__}: {error}")
    finally:
        app.stop()


def row_u3(fake, secrets, run_before):
    before = sp.person_state()
    app = asp.App("U3", RELEASE, ["-AgentServerEnabled", "YES", "-RCSecretFolder", secrets],
                  fake.base, port=PORT_U3)
    try:
        app.connect()
        complaints = [line for line in app.log().splitlines() if "Reelcut: " in line]
        a = app.must("new_project", path=os.path.join(WORK, "u3.reelcut"))["saved"]
        app.must("perform_menu_item", project=a, path=SETTINGS)
        dump = settings_until(app, NO_LEDGER, "u3")
        got = dump.text("settings.assistant.spend")
    finally:
        app.stop()
    after = sp.person_state()
    good = not complaints and got == NO_LEDGER and after == before and after == run_before
    return good, (f"`Reelcut: ` {complaints[:1]}; month line {got!r}; the person's files before "
                  f"the run {run_before}, before this launch {before}, after {after}")


# ---------------------------------------------------------------------------
# The probe.


def rows_probe(score, sources=None, label=""):
    """Builds and runs the probe over `sources` (app/Sources by default);
    False when it did not build."""
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
    ran = bounded.run([binary, scratch], atp.WALL_RUN, cwd=probe_dir,
                      env=asp.child_env({"TZ": PROBE_TZ}))
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


def mutant_sources(name):
    """(Sources path, None) or (None, reason): app/Sources copied with the
    mutant's literal replaced in AssistantSpendMonth.swift."""
    old, new, _ = MUTANTS[name]
    base = os.path.join(WORK, name)
    shutil.rmtree(base, ignore_errors=True)
    sources = os.path.join(base, "Sources")
    try:
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, "AssistantSpendMonth.swift")
        with open(path) as f:
            text = f.read()
        if text.count(old) != 1:
            return None, (f"`{old}` occurs {text.count(old)} times in "
                          "AssistantSpendMonth.swift, not once")
        with open(path, "w") as f:
            f.write(text.replace(old, new))
    except OSError as error:
        return None, f"the copy could not be made: {error}"
    return sources, None


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="a made-to-fail variant; its named rows must FAIL (exit 1)")
    args = parser.parse_args()
    os.makedirs(WORK, exist_ok=True)
    results = []

    def score(row_id, ok, detail, *, instrument=False):
        results.append((row_id, ok, instrument))
        print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    if args.mutant:
        old, new, named = MUTANTS[args.mutant]
        sources, why = mutant_sources(args.mutant)
        built = sources is not None and rows_probe(score, sources, f"({old} → {new}) ")
        passed = sum(1 for _, ok, _ in results if ok)
        print(f"{passed}/{len(results)}", flush=True)
        if not built:
            print(f"mutant {args.mutant}: the control could not be performed — "
                  + (why if sources is None else "the probe did not build"), flush=True)
            return 2
        scored = {row_id: instrument for row_id, _, instrument in results}
        unscored = [row_id for row_id in named if row_id not in scored]
        broken = [row_id for row_id, instrument in scored.items() if instrument]
        if unscored or broken:
            print(f"mutant {args.mutant}: the control could not be performed — "
                  + "; ".join(([f"never scored: {', '.join(unscored)}"] if unscored else [])
                              + ([f"no row: {', '.join(broken)}"] if broken else [])),
                  flush=True)
            return 2
        failed = {row_id for row_id, ok, _ in results if not ok}
        caught = all(row_id in failed for row_id in named)
        print(f"mutant {args.mutant}: {', '.join(named)} "
              f"{'all FAIL — caught' if caught else 'did not all FAIL — it SURVIVED'}",
              flush=True)
        return 1 if caught else 3

    run_before = sp.person_state()
    rows_probe(score)
    fake = None
    try:
        fake = asp.Fake(os.path.join(WORK, "fake"))
        secrets = asp.secret_folder()
        rows_u(fake, secrets, score)
        try:
            score("U3", *row_u3(fake, secrets, run_before))
        except Exception as error:  # noqa: BLE001
            score("U3", False, f"the instrument could not run: {type(error).__name__}: {error}")
    except Exception as error:  # noqa: BLE001
        score("setup", False, f"the instrument could not run: {type(error).__name__}: {error}")
    finally:
        if fake is not None:
            fake.stop()

    passed = sum(1 for _, ok, _ in results if ok)
    print(f"{passed}/{len(results)}", flush=True)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
