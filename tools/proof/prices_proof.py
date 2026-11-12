#!/usr/bin/env python3
"""The price function — road map 13 P1 (spec §11 P-1, P-2). The last line of
`make test`. No network, no app, no key.

  C:<name>  each case in agent/prices/cases.json, through prices.py
  K         the committed agent/prices/anthropic.json: it parses; format 1,
            the unit, the provider, a 40-hex LiteLLM commit;
            claude-opus-5-5 and claude-fable-5-1 each hold all five base
            rates as finite numbers >= 0; 1000 input tokens on opus price as
            dollars > 0 (pricing.test.ts's `table: committed`, in Python)
  T         the Swift helper's price suites (road map "swift-helper" SA3,
            spec §11 SA-3): `python3 tools/agent/agent_test.py --filter
            'PricingTests|PriceTableTests'` (`make agent-test`'s guard, scratch
            path and warnings as errors, so it shares that build) exits 0, and
            its XCTest lines name each test passed or failed
  A         agreement: `PricingTests.testEveryCaseInCasesJSON` (every case of
            cases.json within 1e-12, each assertion labelled `case <name>`)
            passed with no `case <name>` failure, AND every case has a passing
            C row; prints the case count and cases.json's sha256
  R         update.py's `reduce_table` over agent/prices/reduce_cases.json's
            `litellm` block answers exactly its `models` (the helper's
            reducer answers the same fixture in `PriceTableTests`)

    python3 tools/proof/prices_proof.py                          # exit 0 iff every row passes
    python3 tools/proof/prices_proof.py --mutant py-disagrees    # C prices with cache_read
                                                                 # doubled: the cache-read C
                                                                 # rows and A FAIL (exit 1)
    python3 tools/proof/prices_proof.py --mutant swift-disagrees # T/A with a scratch copy of
                                                                 # agent/prices whose opus-mixed
                                                                 # expects +0.01, handed to the
                                                                 # suite by FJ_AGENT_PRICES: T and
                                                                 # A FAIL naming it (exit 1)
    python3 tools/proof/prices_proof.py --mutant reduce-disagrees  # R with the expected opus
                                                                   # input +1: R FAILs (exit 1)

An instrument that cannot run is a scored FAIL, never a skip. A mutant run
exits 1 when a row failed (caught) and 0 when every row passed (it
survived); by rule R (issue batch B13) it exits 2 instead, printing `mutant
<name>: the control could not be performed — <why>`, when any row was scored
where its own comparison did not run: an instrument that could not run, T
with no XCTest line, A with no cases read or no XCTest line. Every child
runs under a wall in its own process group (graphics_spike/bounded.py) with
`RC_ASSEMBLYAI_KEY` and `ANTHROPIC_API_KEY` popped from its environment.
"""

import argparse
import copy
import hashlib
import json
import math
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import prices  # noqa: E402

ROOT = prices.ROOT
AGENT = os.path.join(ROOT, "agent")
sys.path.insert(0, os.path.join(AGENT, "prices"))

REDUCE_CASES = os.path.join(AGENT, "prices", "reduce_cases.json")
AGENT_TEST = os.path.join(ROOT, "tools", "agent", "agent_test.py")
SUITES = "PricingTests|PriceTableTests"
EVERY_CASE = "PricingTests.testEveryCaseInCasesJSON"
# XCTest's per-test line, and an assertion's `case <name>` label (PricingTests.swift).
TEST_LINE = re.compile(r"Test Case '-\[\w+\.(\w+) (\w+)\]' (passed|failed)")
CASE_FAILED = re.compile(r"error: .* - case ([\w.-]+)\s*$", re.M)
WORK = os.path.join(HERE, "work", "prices")
TOLERANCE = 1e-12
WALL_TEST = 900  # a lane's first run builds Slaude in debug (about two minutes, SA1)
BASE_KEYS = ("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
# The mutants, as `mutant_anchors.py` reads them. `swift-disagrees` is the one with tree text:
# `scratch_prices` finds SWIFT_CASE in a copy of cases.json by this line (it must be there
# once) and changes the dollars beside it in the parsed copy, so there is no replacement
# text. The other two change the loaded table or an expected number in memory.
SWIFT_CASE = "opus-mixed"
MUTANTS = {
    "py-disagrees": None,
    "swift-disagrees": ("agent/prices/cases.json", f'"name": "{SWIFT_CASE}"', None),
    "reduce-disagrees": None,
}


def child_env():
    env = bounded.child_env()
    env.pop("ANTHROPIC_API_KEY", None)
    return env


def mismatch(got, want):
    """Empty when `got` answers `want` (pricing.test.ts's rule), else what differs."""
    if got.get("kind") != want["kind"]:
        return f"kind {got.get('kind')}, expected {want['kind']} ({json.dumps(got)})"
    if want["kind"] == "dollars":
        if not abs(got["dollars"] - want["dollars"]) <= TOLERANCE:
            return f"dollars {got['dollars']!r}, expected {want['dollars']!r}"
        if got["rows"] != want["rows"]:
            return f"rows {got['rows']}, expected {want['rows']}"
    elif got.get("cause") != want["cause"]:
        return f"cause {got.get('cause')} ({got.get('detail')}), expected {want['cause']}"
    return ""


def doubled_cache_read(table):
    """The py-disagrees mutant: every cache_read rate, base and above_200k, doubled."""
    table = copy.deepcopy(table)
    for row in table["models"].values():
        for rates in (row, row.get("above_200k")):
            if isinstance(rates, dict) and "cache_read" in rates:
                rates["cache_read"] = rates["cache_read"] * 2
    return table


def committed():
    table = prices.load()
    problems = []
    if table.get("format") != 1:
        problems.append(f"format {table.get('format')!r}")
    if table.get("unit") != "USD per million tokens":
        problems.append(f"unit {table.get('unit')!r}")
    if table.get("provider") != "anthropic":
        problems.append(f"provider {table.get('provider')!r}")
    commit = table.get("litellm_commit")
    if not (isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit)):
        problems.append(f"litellm_commit {commit!r}")
    for model in ("claude-opus-5-5", "claude-fable-5-1"):
        row = table.get("models", {}).get(model)
        if not isinstance(row, dict):
            problems.append(f"no {model} row")
            continue
        for key in BASE_KEYS:
            rate = row.get(key)
            if (isinstance(rate, bool) or not isinstance(rate, (int, float))
                    or not math.isfinite(rate) or rate < 0):
                problems.append(f"{model} {key} {rate!r}")
    priced = prices.price({"input_tokens": 1000}, "claude-opus-5-5", table)
    if not (priced["kind"] == "dollars" and priced["dollars"] > 0):
        problems.append(f"1000 input tokens on opus price as {priced}")
    if problems:
        return False, "; ".join(problems)
    return True, (f"format 1, {table['unit']}, LiteLLM {commit[:12]} "
                  f"({table.get('litellm_commit_date')}), {len(table['models'])} rows; "
                  f"opus and fable hold all five rates; 1000 input on opus = "
                  f"${priced['dollars']:.6f}")


def xctest(output):
    """({"Class.test": passed} from XCTest's lines, [the `case <name>` labels that failed])."""
    tests = {f"{cls}.{name}": state == "passed" for cls, name, state in TEST_LINE.findall(output)}
    return tests, sorted(set(CASE_FAILED.findall(output)))


def scratch_prices():
    """The swift-disagrees mutant: a whole copy of agent/prices whose cases.json expects
    opus-mixed at its dollars + 0.01, for FJ_AGENT_PRICES. Answers the folder."""
    folder = os.path.join(WORK, "swift-disagrees", "prices")
    shutil.rmtree(os.path.dirname(folder), ignore_errors=True)
    shutil.copytree(os.path.join(AGENT, "prices"), folder,
                    ignore=shutil.ignore_patterns("__pycache__"))
    path = os.path.join(folder, "cases.json")
    with open(path) as f:
        text = f.read()
    _, anchor, _ = MUTANTS["swift-disagrees"]
    if text.count(anchor) != 1:
        raise RuntimeError(f"{anchor} occurs {text.count(anchor)} times in cases.json, not once")
    doc = json.loads(text)
    hits = [c for c in doc["cases"] if c["name"] == SWIFT_CASE]
    hits[0]["expect"]["dollars"] += 0.01
    with open(path, "w") as f:
        json.dump(doc, f, indent=2)
    return folder


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=list(MUTANTS),
                        help="a made-to-fail variant; it must end exit 1")
    args = parser.parse_args()
    results = []  # (id, ok, detail)

    def score(row_id, ok, detail, *, instrument=False):
        results.append((row_id, ok, detail, instrument))
        print(f"{'PASS' if ok else 'FAIL'} {row_id}: {detail}", flush=True)

    # C: the cases through the Python reader.
    c_rows = {}
    names = []
    cases_sha = ""
    try:
        with open(prices.CASES, "rb") as f:
            raw = f.read()
        cases_sha = hashlib.sha256(raw).hexdigest()
        fixture = json.loads(raw)
        table = fixture["table"]
        if args.mutant == "py-disagrees":
            table = doubled_cache_read(table)
        for case in fixture["cases"]:
            names.append(case["name"])
            try:
                got = prices.price(case["usage"], case["model"], table)
                why = mismatch(got, case["expect"])
                ok = not why
                detail = why or (f"${got['dollars']!r} {got['rows']}" if got["kind"] == "dollars"
                                 else f"unknown {got['cause']} ({got['detail']})")
            except Exception as error:  # noqa: BLE001 — a reader that raises is a FAIL
                ok, detail = False, f"raised {type(error).__name__}: {error}"
            c_rows[case["name"]] = ok
            score(f"C:{case['name']}", ok, ("(cache_read doubled) " if args.mutant ==
                                            "py-disagrees" else "") + detail)
    except Exception as error:  # noqa: BLE001
        score("C", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)

    # K: the committed table.
    try:
        score("K", *committed())
    except Exception as error:  # noqa: BLE001
        score("K", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)

    # T: the Swift helper's price suites, through make agent-test's runner.
    tests, cases_failed = None, []
    try:
        env = child_env()
        label = ""
        if args.mutant == "swift-disagrees":
            env["FJ_AGENT_PRICES"] = scratch_prices()
            label = "(FJ_AGENT_PRICES a scratch copy, opus-mixed expects +0.01) "
        ran = bounded.run([sys.executable, AGENT_TEST, "--filter", SUITES], WALL_TEST, env=env)
        output = ran["stdout"] + ran["stderr"]
        tests, cases_failed = xctest(output)
        tests = tests or None
        failing = sorted(name for name, passed in (tests or {}).items() if not passed)
        ok = not ran["expired"] and ran["rc"] == 0 and tests is not None and not failing
        detail = (f"exit {ran['rc']}{' (expired)' if ran['expired'] else ''} in "
                  f"{ran['seconds']} s; "
                  + (f"{len(tests)} tests, failing {failing or 'none'}"
                     + (f", cases {cases_failed}" if cases_failed else "")
                     if tests is not None else "no XCTest line"))
        if ran["rc"] != 0 and tests is None:
            detail += "; " + ([line for line in output.splitlines() if "error" in line]
                              or output.strip().splitlines() or ["(no output)"])[-1][:160]
        score("T", ok, label + detail, instrument=tests is None)
    except Exception as error:  # noqa: BLE001
        score("T", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)

    # A: both readers pass every case.
    if not names:
        score("A", False, "no cases were read", instrument=True)
    elif tests is None:
        score("A", False, "no XCTest line to compare against", instrument=True)
    else:
        every = tests.get(EVERY_CASE)
        swift_bad = [n for n in names if n in cases_failed]
        py_bad = [n for n in names if not c_rows.get(n)]
        ok = every is True and not (swift_bad or py_bad)
        detail = (f"{len(names)} cases, cases.json sha256 {cases_sha}; "
                  + ("both readers pass every case" if ok else
                     f"{EVERY_CASE} {'absent' if every is None else 'passed' if every else 'failed'}; "
                     f"failing in Swift {swift_bad or 'none'}; failing in prices.py "
                     f"{py_bad or 'none'}"))
        score("A", ok, detail)

    # R: update.py's reducer over the fixture the helper's reducer also answers.
    try:
        import update  # inside the row: an unimportable update.py is R's FAIL, not a traceback
        with open(REDUCE_CASES) as f:
            fixture = json.load(f)
        want = fixture["models"]
        label = ""
        if args.mutant == "reduce-disagrees":
            want = copy.deepcopy(want)
            want["claude-opus-5-5"]["input"] += 1
            label = "(expected opus input +1) "
        got = update.reduce_table(fixture["litellm"], "0" * 40, "proof")["models"]
        differs = sorted(m for m in set(got) | set(want) if got.get(m) != want.get(m))
        ok = not differs
        detail = (f"{len(fixture['litellm'])} LiteLLM entries reduce to {len(got)} rows "
                  f"{sorted(got)}" + ("" if ok else "; differing " + "; ".join(
                      f"{m}: got {got.get(m)}, expected {want.get(m)}" for m in differs)))
        score("R", ok, label + detail)
    except Exception as error:  # noqa: BLE001
        score("R", False, f"the instrument could not run: {type(error).__name__}: {error}",
              instrument=True)

    passed = sum(1 for _, ok, _, _ in results if ok)
    print(f"scores: {passed}/{len(results)} pass", flush=True)
    broken = [row_id for row_id, _, _, instrument in results if instrument]
    if args.mutant and broken:
        print(f"mutant {args.mutant}: the control could not be performed — scored as "
              f"instrument failures: {', '.join(broken)}", flush=True)
        return 2
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
