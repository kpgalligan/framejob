#!/usr/bin/env python3
"""The price table against Anthropic's pricing page — road map 13 P1 (spec
§11 P-1: LiteLLM is the feed, the page is the cross-check). NETWORK; not in
`make test`. No key, no paid call: one GET of a public document.

  X0  the page is fetched, the table under `## Model pricing` has its five
      rate headers, and at least one row parses
  X1  claude-opus-5-5 <-> "Claude Opus 5.5" (AI-11's default model)
  X2  claude-fable-5-1 <-> "Claude Fable 5.1" (the priciest model
      `fallbacks: "default"` can bill, designs/adr/roadmap-12-assistant.md)

X1 and X2 compare each of the five rates of agent/prices/anthropic.json's row
with the page's, after `round(…, 6)`; a mismatch is named
`<id> <key>: table <a>, page <b>`.

    python3 tools/proof/prices_crosscheck.py                 # exit 0 iff X0–X2 pass
    python3 tools/proof/prices_crosscheck.py --mutant table  # opus cache_read 0.21 in
                                                             # memory: X1 FAILs (exit 1)
    python3 tools/proof/prices_crosscheck.py --mutant page   # the "Claude Fable 5.1" line
                                                             # deleted: X2 FAILs (exit 1)

An instrument that cannot run is a scored FAIL, never a skip. A mutant run
exits 1 when a row failed (caught) and 0 when none did (it survived); by
rule R (issue batch B13) it exits 2 instead, printing `mutant <name>: the
control could not be performed — <why>`, when any row was scored where its
own comparison did not run — X0's except (the page not fetched), the table
unread, no page rows, X1/X2's except.
"""

import argparse
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import prices  # noqa: E402

PAGE = "https://platform.claude.com/docs/en/about-claude/pricing.md"
TIMEOUT = 60
HEADERS = {  # page column -> table key
    "Base input tokens": "input",
    "5m cache writes": "cache_write_5m",
    "1h cache writes": "cache_write_1h",
    "Cache hits and refreshes": "cache_read",
    "Output tokens": "output",
}
PAIRS = (("X1", "claude-opus-5-5", "Claude Opus 5.5"),
         ("X2", "claude-fable-5-1", "Claude Fable 5.1"))
SUP = re.compile(r"<sup>.*?</sup>")
CELL = re.compile(r"^\$([0-9]+(?:\.[0-9]+)?) / MTok$")


def fetch():
    request = urllib.request.Request(PAGE, headers={"User-Agent": "framejob-prices-crosscheck"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read().decode("utf-8")


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def parse(text):
    """({name: {key: rate}}, problems): the table under `## Model pricing`."""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "## Model pricing")
    except StopIteration:
        return {}, ["no `## Model pricing` heading"]
    section = []
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        section.append(line)
    header_at = next((i for i, l in enumerate(section) if l.lstrip().startswith("|")), None)
    if header_at is None:
        return {}, ["no table under `## Model pricing`"]
    header = cells(section[header_at])
    missing = [h for h in HEADERS if h not in header]
    if missing:
        return {}, [f"headers missing: {missing}"]
    columns = {HEADERS[h]: header.index(h) for h in HEADERS}
    rows, problems = {}, []
    for line in section[header_at + 2:]:
        if not line.lstrip().startswith("|"):
            break
        row = cells(line)
        name = row[0].split(" (", 1)[0].strip()
        rates = {}
        for key, column in columns.items():
            raw = SUP.sub("", row[column]).strip() if column < len(row) else ""
            match = CELL.match(raw)
            if match:
                rates[key] = float(match.group(1))
            else:
                problems.append(f"{name} {key}: cell {raw!r} does not parse")
        rows[name] = rates
    if not rows:
        problems.append("no row parsed")
    return rows, problems


def compare(model, name, table, page):
    row = table["models"].get(model)
    if not isinstance(row, dict):
        return False, f"{model}: the table has no row"
    if name not in page:
        return False, f"{model}: the page has no {name!r} row"
    mismatches, same = [], []
    for key in HEADERS.values():
        a, b = row.get(key), page[name].get(key)
        a = round(a, 6) if isinstance(a, (int, float)) and not isinstance(a, bool) else a
        b = round(b, 6) if isinstance(b, float) else b
        if a is None or b is None or a != b:
            mismatches.append(f"{model} {key}: table {a}, page {b}")
        else:
            same.append(f"{key} {a}")
    if mismatches:
        return False, "; ".join(mismatches)
    return True, f"{model} = {name!r}: " + ", ".join(same)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=["table", "page"],
                        help="a made-to-fail variant; it must end exit 1")
    args = parser.parse_args()
    results = []

    def score(row_id, ok, detail, *, instrument=False):
        results.append((row_id, ok, detail, instrument))
        print(f"{'PASS' if ok else 'FAIL'} {row_id}: {detail}", flush=True)

    page = None
    try:
        text = fetch()
        if args.mutant == "page":
            text = "\n".join(l for l in text.splitlines()
                             if not cells(l)[0].startswith("Claude Fable 5.1")) + "\n"
        page, problems = parse(text)
        # Only the rows X1 and X2 compare can fail X0: a cell that will not
        # parse in some other model's row is reported and ignored.
        names = [name for _, _, name in PAIRS]
        relevant = [p for p in problems
                    if p == "no row parsed" or any(p.startswith(n + " ") for n in names)]
        ignored = len(problems) - len(relevant)
        ok = bool(page) and not relevant
        score("X0", ok, (f"{len(text)} characters; {len(page)} rows parsed"
                         + (f"; {'; '.join(relevant)}" if relevant else "")
                         + (f"; {ignored} unparsed cell(s) in rows not compared, ignored"
                            if ignored else "")))
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        score("X0", False, f"{PAGE}: {type(error).__name__}: {error}", instrument=True)

    table = None
    try:
        table = prices.load()
        if args.mutant == "table":
            table["models"]["claude-opus-5-5"]["cache_read"] = 0.21
    except Exception as error:  # noqa: BLE001
        why = f"the table could not be read: {type(error).__name__}: {error}"
        for row_id, _, _ in PAIRS:
            score(row_id, False, why, instrument=True)
    if table is not None:
        for row_id, model, name in PAIRS:
            if not page:
                score(row_id, False, f"{model}: no page rows to compare against",
                      instrument=True)
                continue
            try:
                label = "(opus cache_read 0.21 in memory) " if (
                    args.mutant == "table" and row_id == "X1") else ""
                label = "(\"Claude Fable 5.1\" line deleted) " if (
                    args.mutant == "page" and row_id == "X2") else label
                ok, detail = compare(model, name, table, page)
                score(row_id, ok, label + detail)
            except Exception as error:  # noqa: BLE001
                score(row_id, False, f"the instrument could not run: "
                                     f"{type(error).__name__}: {error}", instrument=True)

    print(f"table: LiteLLM {table.get('litellm_commit') if table else '?'} "
          f"({table.get('litellm_commit_date') if table else '?'})", flush=True)
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
