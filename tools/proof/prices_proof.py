#!/usr/bin/env python3
"""The price function — road map 13 P1 (spec §11 P-1, P-2). The last line of
`make test`. No network, no app, no key.

  C:<name>  each case in agent/prices/cases.json, through prices.py
  K         the committed agent/prices/anthropic.json: it parses; format 1,
            the unit, the provider, a 40-hex LiteLLM commit;
            claude-opus-5-5 and claude-fable-5-1 each hold all five base
            rates as finite numbers >= 0; 1000 input tokens on opus price as
            dollars > 0 (pricing.test.ts's `table: committed`, in Python)
  T         `/bin/sh agent/build.sh test` (bun test, JUnit into
            build/agent/bun-test.xml, deleted first) exits 0
  A         agreement: every case name has a passing `case: <name>` testcase
            in the JUnit report AND a passing C row; prints the case count
            and cases.json's sha256
  R         update.py's `reduce_table` over agent/prices/reduce_cases.json's
            `litellm` block answers exactly its `models` (road map 13 P2: the
            helper's `reduceLiteLLM` answers the same fixture in bun test)

    python3 tools/proof/prices_proof.py                          # exit 0 iff every row passes
    python3 tools/proof/prices_proof.py --mutant py-disagrees    # C prices with cache_read
                                                                 # doubled: the cache-read C
                                                                 # rows and A FAIL (exit 1)
    python3 tools/proof/prices_proof.py --mutant ts-disagrees    # T/A on a scratch agent/ whose
                                                                 # opus-mixed expects +0.01:
                                                                 # T and A FAIL naming it (exit 1)
    python3 tools/proof/prices_proof.py --mutant reduce-disagrees  # R with the expected opus
                                                                   # input +1: R FAILs (exit 1)

An instrument that cannot run is a scored FAIL, never a skip. Every child
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
import xml.etree.ElementTree as ElementTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import prices  # noqa: E402

ROOT = prices.ROOT
AGENT = os.path.join(ROOT, "agent")
sys.path.insert(0, os.path.join(AGENT, "prices"))

REDUCE_CASES = os.path.join(AGENT, "prices", "reduce_cases.json")
JUNIT = os.path.join(ROOT, "build", "agent", "bun-test.xml")
WORK = os.path.join(HERE, "work", "prices")
TOLERANCE = 1e-12
WALL_TEST = 300
BASE_KEYS = ("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")


def child_env():
    env = bounded.child_env()
    env.pop("ANTHROPIC_API_KEY", None)
    return env


def run(argv, seconds, cwd=None):
    return bounded.run(argv, seconds, cwd=cwd, env=child_env())


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


def junit_cases(path):
    """{testcase name: passed} from bun's JUnit report."""
    answer = {}
    for case in ElementTree.parse(path).getroot().iter("testcase"):
        bad = [child for child in case if child.tag in ("failure", "error", "skipped")]
        answer[case.get("name")] = not bad
    return answer


def scratch_agent():
    """The ts-disagrees mutant: a scratch agent/ (node_modules ignored) whose
    cases.json expects opus-mixed at its dollars + 0.01. Answers (build.sh, junit)."""
    base = os.path.join(WORK, "ts-disagrees")
    shutil.rmtree(base, ignore_errors=True)
    scratch = os.path.join(base, "agent")
    shutil.copytree(AGENT, scratch, ignore=shutil.ignore_patterns("node_modules"))
    path = os.path.join(scratch, "prices", "cases.json")
    with open(path) as f:
        doc = json.load(f)
    hits = [c for c in doc["cases"] if c["name"] == "opus-mixed"]
    if len(hits) != 1:
        raise RuntimeError(f"{len(hits)} opus-mixed cases in cases.json, not 1")
    hits[0]["expect"]["dollars"] += 0.01
    with open(path, "w") as f:
        json.dump(doc, f, indent=2)
    return (os.path.join(scratch, "build.sh"),
            os.path.join(base, "build", "agent", "bun-test.xml"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=["py-disagrees", "ts-disagrees", "reduce-disagrees"],
                        help="a made-to-fail variant; it must end exit 1")
    args = parser.parse_args()
    results = []  # (id, ok, detail)

    def score(row_id, ok, detail):
        results.append((row_id, ok, detail))
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
        score("C", False, f"the instrument could not run: {type(error).__name__}: {error}")

    # K: the committed table.
    try:
        score("K", *committed())
    except Exception as error:  # noqa: BLE001
        score("K", False, f"the instrument could not run: {type(error).__name__}: {error}")

    # T: bun test, through build.sh.
    tests = None
    try:
        script, junit = os.path.join(AGENT, "build.sh"), JUNIT
        label = ""
        if args.mutant == "ts-disagrees":
            script, junit = scratch_agent()
            label = "(scratch agent/, opus-mixed expects +0.01) "
        if os.path.exists(junit):
            os.remove(junit)
        ran = run(["/bin/sh", script, "test"], WALL_TEST)
        failing = []
        if os.path.exists(junit):
            tests = junit_cases(junit)
            failing = sorted(name for name, passed in tests.items() if not passed)
        ok = not ran["expired"] and ran["rc"] == 0
        detail = (f"exit {ran['rc']}{' (expired)' if ran['expired'] else ''} in "
                  f"{ran['seconds']} s; "
                  + (f"{len(tests)} testcases, failing {failing or 'none'}" if tests is not None
                     else "no JUnit report"))
        if ran["rc"] != 0 and tests is None:
            detail += "; " + (ran["stderr"].strip().splitlines() or ["(no stderr)"])[-1][:160]
        score("T", ok, label + detail)
    except Exception as error:  # noqa: BLE001
        score("T", False, f"the instrument could not run: {type(error).__name__}: {error}")

    # A: both readers pass every case.
    if not names:
        score("A", False, "no cases were read")
    elif tests is None:
        score("A", False, "no JUnit report to compare against")
    else:
        missing = [n for n in names if f"case: {n}" not in tests]
        ts_bad = [n for n in names if tests.get(f"case: {n}") is False]
        py_bad = [n for n in names if not c_rows.get(n)]
        ok = not (missing or ts_bad or py_bad)
        detail = (f"{len(names)} cases, cases.json sha256 {cases_sha}; "
                  + ("both readers pass every case" if ok else
                     f"absent from bun {missing or 'none'}; failing in bun {ts_bad or 'none'}; "
                     f"failing in prices.py {py_bad or 'none'}"))
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
        score("R", False, f"the instrument could not run: {type(error).__name__}: {error}")

    passed = sum(1 for _, ok, _ in results if ok)
    print(f"scores: {passed}/{len(results)} pass", flush=True)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
