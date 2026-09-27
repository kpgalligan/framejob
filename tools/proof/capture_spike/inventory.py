"""The capture spike's Q2(c) inventory: which menu items reach a sheet, a
modal run loop, or neither — and the checks that hold `inventory.json` to
the tree (road map 11, V1).

`inventory.json` is READ BY HAND, site first: every line the grep below
finds is traced to the menu selectors that reach it, synchronously
(`reached_from`: the action method reaches the site before it returns) or
later (`reached_after`: from a sheet or panel completion, an async hop or an
AppKit delegate callback, with the `via` line and the `gate` that must hold).
Every other live selector is read to `none`, `window` or `framework`.

  I1  every leaf of `buildMainMenu()` (the probe's `menu` mode) has its
      selector in `selectors`, and every row there names a live selector;
  I2  the grep's sites and `sites` are one-to-one, each line holding its token;
  I3  a `modal` selector cites a line holding a loop token, a `sheet` one a
      sheet token; every cited line (`code`, `via`, `gate`) exists; every
      `reached_from` / `reached_after` selector names a row; a selector in the
      `reached_from` of a `runModal` or loop-token site is `modal`
      (`reached_after` never forces a verdict);
  I4  the checker over a copy missing one selector and one site reports
      exactly those two.
"""

import copy
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SOURCES = os.path.join(ROOT, "app", "Sources")
INVENTORY = os.path.join(HERE, "inventory.json")

SITE = re.compile(r"(presentAsSheet|beginSheetModal|beginSheet|runModal)\s*\(|popUp\(positioning:"
                  r"|nextEvent\(matching:|RunLoop\.\w+\.run\(|CFRunLoopRun\(")
SHEET_TOKENS = {"presentAsSheet", "beginSheetModal", "beginSheet"}
LOOP_TOKENS = {"runModal", "popUp", "runLoop", "nextEvent"}
TOKEN_TEXT = {"presentAsSheet": "presentAsSheet", "beginSheetModal": "beginSheetModal",
              "beginSheet": "beginSheet", "runModal": "runModal", "popUp": "popUp(positioning:",
              "nextEvent": "nextEvent(matching:", "runLoop": "RunLoop."}
REF = re.compile(r"(app/Sources/[\w+]+\.swift):(\d+)")
VERDICTS = {"none", "sheet", "window", "modal", "framework"}


def token_of(match):
    word = match.group(1)
    if word:
        return word
    text = match.group(0)
    if text.startswith("popUp"):
        return "popUp"
    if text.startswith("nextEvent"):
        return "nextEvent"
    return "runLoop"


def grep_sites():
    """{"app/Sources/<f>.swift:<line>": token} for every match on a line with
    no `//` before it."""
    sites = {}
    for name in sorted(os.listdir(SOURCES)):
        if not name.endswith(".swift"):
            continue
        with open(os.path.join(SOURCES, name), encoding="utf-8") as f:
            for number, line in enumerate(f, 1):
                match = SITE.search(line)
                if match and "//" not in line[:match.start()]:
                    sites[f"app/Sources/{name}:{number}"] = token_of(match)
    return sites


_lines = {}


def line_of(ref):
    path, number = ref.rsplit(":", 1)
    if path not in _lines:
        full = os.path.join(ROOT, path)
        _lines[path] = open(full, encoding="utf-8").read().split("\n") if os.path.exists(
            full) else None
    lines = _lines[path]
    n = int(number)
    if lines is None or n < 1 or n > len(lines):
        return None
    return lines[n - 1]


def refs(text):
    return [f"{m.group(1)}:{m.group(2)}" for m in REF.finditer(text or "")]


def check(inventory, leaves, grep):
    """Every problem, as (check, subject, why). `leaves` is the probe's
    list or None when the menu mode gave no answer."""
    problems = []
    selectors = inventory.get("selectors", {})
    sites = inventory.get("sites", {})
    # I1
    if leaves is None:
        problems.append(("I1", "menu", "the probe's menu mode gave no leaves"))
    else:
        live = {leaf["selector"] for leaf in leaves if leaf.get("selector")}
        for s in sorted(live - set(selectors)):
            problems.append(("I1", s, "menu selector missing from inventory"))
        for s in sorted(set(selectors) - live):
            problems.append(("I1", s, "inventory row names no live selector"))
    # I2
    for ref in sorted(set(grep) - set(sites)):
        problems.append(("I2", ref, "grep site missing from inventory"))
    for ref in sorted(set(sites) - set(grep)):
        problems.append(("I2", ref, "inventory site the grep does not find"))
    for ref, entry in sites.items():
        line = line_of(ref)
        token = entry.get("token")
        if line is None or TOKEN_TEXT.get(token, "\0") not in line:
            problems.append(("I2", ref, f"line does not hold its token {token}"))
        elif ref in grep and grep[ref] != token:
            problems.append(("I2", ref, f"token {token}, the grep says {grep[ref]}"))
    # I3
    for sel, row in selectors.items():
        verdict = row.get("verdict")
        if verdict not in VERDICTS:
            problems.append(("I3", sel, f"verdict {verdict!r}"))
        cited = [line_of(r) or "" for r in row.get("code", [])]
        if verdict == "modal" and not any(
                any(TOKEN_TEXT[t] in c for t in LOOP_TOKENS) for c in cited):
            problems.append(("I3", sel, "modal, but no cited line holds a loop token"))
        if verdict == "sheet" and not any(
                any(TOKEN_TEXT[t] in c for t in SHEET_TOKENS) for c in cited):
            problems.append(("I3", sel, "sheet, but no cited line holds a sheet token"))
        for r in row.get("code", []):
            if not REF.fullmatch(r) or line_of(r) is None:
                problems.append(("I3", sel, f"cited line {r} does not exist"))
    for ref, entry in sites.items():
        for sel in entry.get("reached_from", []):
            if sel not in selectors:
                problems.append(("I3", ref, f"reached_from {sel} names no row"))
            elif entry.get("token") in LOOP_TOKENS and selectors[sel].get("verdict") != "modal":
                problems.append(("I3", sel, f"reaches {entry.get('token')} at {ref} "
                                            "synchronously but is not modal"))
        for after in entry.get("reached_after", []):
            if after.get("selector") not in selectors:
                problems.append(("I3", ref, f"reached_after {after.get('selector')} names no row"))
            for r in refs(after.get("via")) + refs(after.get("gate")):
                if line_of(r) is None:
                    problems.append(("I3", ref, f"cited line {r} does not exist"))
            if not refs(after.get("via")):
                problems.append(("I3", ref, "reached_after has no via line"))
    return problems


def i4(inventory, leaves, grep):
    """The checker over a copy missing one selector no site references and
    one site: exactly those two reported."""
    referenced = set()
    for entry in inventory.get("sites", {}).values():
        referenced.update(entry.get("reached_from", []))
        referenced.update(a.get("selector") for a in entry.get("reached_after", []))
    spare = sorted(s for s in inventory.get("selectors", {}) if s not in referenced)
    site = sorted(inventory.get("sites", {}))
    if not spare or not site or leaves is None:
        return False, "no selector or site to remove (or no leaves)", {}
    mutant = copy.deepcopy(inventory)
    del mutant["selectors"][spare[0]]
    del mutant["sites"][site[0]]
    baseline = {(c, s) for c, s, _ in check(inventory, leaves, grep)}
    found = {(c, s) for c, s, _ in check(mutant, leaves, grep)} - baseline
    want = {("I1", spare[0]), ("I2", site[0])}
    return found == want, (f"removed {spare[0]} and {site[0]}; the checker reported "
                           f"{sorted(found)}"), {"removed": [spare[0], site[0]],
                                                  "reported": sorted(found)}


def table(inventory, leaves):
    """One row per menu leaf: path, selector, verdict, code, after."""
    selectors = inventory.get("selectors", {})
    after = {}
    for ref, entry in inventory.get("sites", {}).items():
        for a in entry.get("reached_after", []):
            after.setdefault(a.get("selector"), []).append(
                {"site": ref, "via": a.get("via", ""), "gate": a.get("gate", "")})
    rows = []
    for leaf in leaves or []:
        sel = leaf.get("selector")
        row = selectors.get(sel, {})
        rows.append({"path": leaf["path"], "selector": sel, "verdict": row.get("verdict", "?"),
                     "code": row.get("code", []), "after": after.get(sel, [])})
    return rows


def run(leaves):
    """The I1–I4 results: {id: (ok, reason, measured)}, the grep counts and
    the menu table."""
    with open(INVENTORY, encoding="utf-8") as f:
        inventory = json.load(f)
    grep = grep_sites()
    problems = check(inventory, leaves, grep)
    counts = {}
    for token in grep.values():
        counts[token] = counts.get(token, 0) + 1
    out = {}
    for rid in ("I1", "I2", "I3"):
        mine = [p for p in problems if p[0] == rid]
        measured = {"problems": [f"{s}: {why}" for _, s, why in mine]}
        if rid == "I1":
            measured["leaves"] = len(leaves or [])
            measured["selectors"] = len(inventory.get("selectors", {}))
            live = {leaf["selector"] for leaf in leaves or [] if leaf.get("selector")}
            measured["live_selectors"] = len(live)
            measured["no_action"] = [leaf["path"] for leaf in leaves or []
                                     if not leaf.get("selector")]
        if rid == "I2":
            measured["grep_sites"] = len(grep)
            measured["inventory_sites"] = len(inventory.get("sites", {}))
            measured["counts"] = counts
        if rid == "I3":
            verdicts = {}
            for row in inventory.get("selectors", {}).values():
                verdicts[row.get("verdict")] = verdicts.get(row.get("verdict"), 0) + 1
            measured["verdicts"] = verdicts
        reason = (f"{len(mine)} problem(s)" + (": " + "; ".join(measured["problems"][:4])
                                                  if mine else ""))
        if rid == "I1":
            reason += (f"; {measured['leaves']} leaves, {measured['live_selectors']} live "
                       f"selectors, {measured['selectors']} rows")
        if rid == "I2":
            reason += f"; {len(grep)} sites: " + ", ".join(
                f"{k} {v}" for k, v in sorted(counts.items()))
        if rid == "I3":
            reason += "; verdicts " + ", ".join(
                f"{k} {v}" for k, v in sorted(measured["verdicts"].items()))
        out[rid] = (not mine and (rid != "I1" or leaves is not None), reason, measured)
    ok, reason, measured = i4(inventory, leaves, grep)
    out["I4"] = (ok, reason, measured)
    return out, table(inventory, leaves)


def print_table(rows):
    print("\nQ2(c) — menu path → selector → verdict → code → after")
    for row in rows:
        after = "; ".join(f"{a['site']} via {a['via']}" + (f" if {a['gate']}" if a['gate'] else "")
                          for a in row["after"])
        print(f"  {' ▸ '.join(row['path'])} — {row['selector']} — {row['verdict']}"
              + (f" — {', '.join(row['code'])}" if row["code"] else "")
              + (f" — after: {after}" if after else ""))
