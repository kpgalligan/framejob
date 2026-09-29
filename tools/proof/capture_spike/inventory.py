"""The capture spike's Q2(c) inventory: which menu items reach a sheet, a
modal run loop, or neither — and the checks that hold `inventory.json` to
the tree (road map 11, V1).

`inventory.json` is READ BY HAND, site first: every line the grep below
finds is traced to the menu selectors that reach it, synchronously
(`reached_from`: the action method reaches the site before it returns) or
later (`reached_after`: from a sheet or panel completion, an async hop or an
AppKit delegate callback, with the `via` line and the `gate` that must hold).
Every other live selector is read to `none`, `window` or `framework`.
The grep counts the APP-MODAL `presentError(` (road map 11's V2b) — the
`presentError(_:)` / `NSApp.presentError(_:)` that runs a modal loop — and
not the sheet form `presentError(_:modalFor:…)`, which is not modal.

  I1  every leaf of `buildMainMenu()` (the probe's `menu` mode) has its
      selector in `selectors`, and every row there names a live selector;
  I2  the grep's sites and `sites` are one-to-one, each line holding its token;
      a site is FOUND BY ITS TOKEN, not its line (#166): `resolve` pairs the
      inventory's sites with the grep's, per file and token, in line order,
      whenever the two counts agree, so a line added above a site moves its
      pin instead of failing it; where they disagree each pin stands as
      written. Blind spot: a swap in one file and token (a site removed and
      another added, the counts still agreeing) is absorbed by the pairing
      and I2 reports neither, where the old line pins caught it;
  I3  a `modal` selector cites a line holding a loop token, a `sheet` one a
      sheet token (a cited site read at its resolved line); every cited line
      (`code`, `via`, `gate`) exists; every
      `reached_from` / `reached_after` selector names a row; a selector in the
      `reached_from` of a `runModal` or loop-token site is `modal`
      (`reached_after` never forces a verdict);
  I4  the checker over a copy missing one selector and one site reports
      exactly those two.

`python3 tools/proof/capture_spike/inventory.py --check` is a line of
`make test`: no app, no probe, no build, in a fresh `work/inventory_check/`.

  K1  I2 and I3 over the tree have no problem (I1 needs the probe, so it is
      `v2_menu.py`'s H1); its detail lists the pins found at another line;
  K2  CONTROL: a copy of `app/Sources` with three blank lines put at the top
      of every file that holds a site has no I2 or I3 problem;
  K3  CONTROL: a fresh copy, the inventory's site keys first rewritten
      through `resolve`, then the line of the first rewritten site blanked:
      the checker reports exactly that site under I2.
"""

import argparse
import copy
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SOURCES = os.path.join(ROOT, "app", "Sources")
INVENTORY = os.path.join(HERE, "inventory.json")

SITE = re.compile(r"(presentAsSheet|beginSheetModal|beginSheet|runModal)\s*\(|popUp\(positioning:"
                  r"|nextEvent\(matching:|RunLoop\.\w+\.run\(|CFRunLoopRun\("
                  r"|presentError\((?![^)]*modalFor:)")
SHEET_TOKENS = {"presentAsSheet", "beginSheetModal", "beginSheet"}
LOOP_TOKENS = {"runModal", "popUp", "runLoop", "nextEvent", "presentError"}
TOKEN_TEXT = {"presentAsSheet": "presentAsSheet", "beginSheetModal": "beginSheetModal",
              "beginSheet": "beginSheet", "runModal": "runModal", "popUp": "popUp(positioning:",
              "nextEvent": "nextEvent(matching:", "runLoop": "RunLoop.",
              "presentError": "presentError("}
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
    if text.startswith("presentError"):
        return "presentError"
    return "runLoop"


def grep_sites(sources=SOURCES):
    """{"app/Sources/<f>.swift:<line>": token} for every match on a line with
    no `//` before it. `sources` is the folder read; the keys always name
    `app/Sources/`, so a copy's are read under its own root by `line_of`."""
    sites = {}
    for name in sorted(os.listdir(sources)):
        if not name.endswith(".swift"):
            continue
        with open(os.path.join(sources, name), encoding="utf-8") as f:
            for number, line in enumerate(f, 1):
                match = SITE.search(line)
                if match and "//" not in line[:match.start()]:
                    sites[f"app/Sources/{name}:{number}"] = token_of(match)
    return sites


_lines = {}


def line_of(ref, root=ROOT):
    """The line `ref` names under `root`, or None. The cache is keyed by the
    FULL path, so each root reads its own files."""
    path, number = ref.rsplit(":", 1)
    full = os.path.join(root, path)
    if full not in _lines:
        _lines[full] = open(full, encoding="utf-8").read().split("\n") if os.path.exists(
            full) else None
    lines = _lines[full]
    n = int(number)
    if lines is None or n < 1 or n > len(lines):
        return None
    return lines[n - 1]


def refs(text):
    return [f"{m.group(1)}:{m.group(2)}" for m in REF.finditer(text or "")]


def _line_number(ref):
    return int(ref.rsplit(":", 1)[1])


def resolve(sites, grep):
    """{inventory site ref: current ref}. The inventory's sites are grouped
    by (file, entry `token`) and the grep's by (file, grep token); where a
    group's two counts agree they are paired in line order, and otherwise
    each inventory ref maps to itself."""
    ours, theirs = {}, {}
    for ref, entry in sites.items():
        ours.setdefault((ref.rsplit(":", 1)[0], entry.get("token")), []).append(ref)
    for ref, token in grep.items():
        theirs.setdefault((ref.rsplit(":", 1)[0], token), []).append(ref)
    mapping = {}
    for key, refs_here in ours.items():
        mine = sorted(refs_here, key=_line_number)
        found = sorted(theirs.get(key, []), key=_line_number)
        if len(mine) == len(found):
            mapping.update(zip(mine, found))
        else:
            mapping.update((ref, ref) for ref in mine)
    return mapping


def check(inventory, leaves, grep, root=ROOT):
    """Every problem, as (check, subject, why). `leaves` is the probe's
    list or None when the menu mode gave no answer. `root` is the tree the
    refs are read under."""
    problems = []
    selectors = inventory.get("selectors", {})
    sites = inventory.get("sites", {})
    mapping = resolve(sites, grep)

    def at(ref):
        return line_of(mapping.get(ref, ref), root)

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
    for ref in sorted(set(grep) - set(mapping.values())):
        problems.append(("I2", ref, "grep site missing from inventory"))
    for ref in sorted(r for r in sites if mapping[r] not in grep):
        problems.append(("I2", ref, "inventory site the grep does not find"))
    for ref, entry in sites.items():
        line = at(ref)
        token = entry.get("token")
        now = mapping[ref]
        if line is None or TOKEN_TEXT.get(token, "\0") not in line:
            problems.append(("I2", ref, f"line does not hold its token {token}"))
        elif now in grep and grep[now] != token:
            problems.append(("I2", ref, f"token {token}, the grep says {grep[now]}"))
    # I3
    for sel, row in selectors.items():
        verdict = row.get("verdict")
        if verdict not in VERDICTS:
            problems.append(("I3", sel, f"verdict {verdict!r}"))
        cited = [at(r) or "" for r in row.get("code", [])]
        if verdict == "modal" and not any(
                any(TOKEN_TEXT[t] in c for t in LOOP_TOKENS) for c in cited):
            problems.append(("I3", sel, "modal, but no cited line holds a loop token"))
        if verdict == "sheet" and not any(
                any(TOKEN_TEXT[t] in c for t in SHEET_TOKENS) for c in cited):
            problems.append(("I3", sel, "sheet, but no cited line holds a sheet token"))
        for r in row.get("code", []):
            if not REF.fullmatch(r) or at(r) is None:
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
                if at(r) is None:
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


# ---------------------------------------------------------------------------
# `--check`: I2 and I3 without the probe, and their two CONTROLs.


def _copy_sources(dest):
    """A fresh copy of `app/Sources` at `dest/app/Sources`; answers `dest`."""
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(SOURCES, os.path.join(dest, "app", "Sources"))
    return dest


def _pairs(problems, wanted=("I2", "I3")):
    return [(c, s, why) for c, s, why in problems if c in wanted]


def main(argv=None):
    parser = argparse.ArgumentParser(description="the menu inventory's sheet and modal "
                                                 "sites against app/Sources, by token")
    parser.add_argument("--check", action="store_true",
                        help="K1–K3 in a fresh work/inventory_check/")
    arguments = parser.parse_args(argv)
    if not arguments.check:
        parser.print_help()
        return 2
    work = os.path.join(ROOT, "tools", "proof", "work", "inventory_check")
    rows = []

    def row(ident, ok, detail):
        rows.append(ok)
        print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}")

    try:
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work)
        with open(INVENTORY, encoding="utf-8") as f:
            inventory = json.load(f)
        sites = inventory.get("sites", {})
    except Exception as error:  # an instrument that cannot run is a FAIL
        row("K0", False, f"the inventory or the work folder could not be read: {error!r}")
        print(f"{sum(rows)}/{len(rows)}")
        return 1

    # K1
    try:
        grep = grep_sites()
        found = _pairs(check(inventory, None, grep))
        moved = sorted(f"{k} → {v.rsplit(':', 1)[1]}"
                       for k, v in resolve(sites, grep).items() if k != v)
        row("K1", not found,
            (f"{len(found)} problem(s): " + "; ".join(f"{c} {s}: {why}" for c, s, why in
                                                        found[:6]) if found
             else f"I2 and I3 clean over {len(grep)} grep sites and {len(sites)} pins")
            + (f"; pins found at another line: {', '.join(moved)}" if moved
               else "; every pin at its own line"))
    except Exception as error:
        row("K1", False, f"the check raised {error!r}")

    # K2 (CONTROL)
    try:
        root = _copy_sources(os.path.join(work, "k2"))
        copied = os.path.join(root, "app", "Sources")
        holding = sorted({ref.rsplit(":", 1)[0].rsplit("/", 1)[1] for ref in grep_sites(copied)})
        for name in holding:
            path = os.path.join(copied, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n\n\n" + text)
        found = _pairs(check(inventory, None, grep_sites(copied), root=root))
        row("K2", not found,
            f"CONTROL: three lines put at the top of {len(holding)} files: "
            + (f"{len(found)} problem(s): " + "; ".join(f"{c} {s}: {why}" for c, s, why in
                                                         found[:6]) if found
               else "no I2 or I3 problem"))
    except Exception as error:
        row("K2", False, f"the control raised {error!r}")

    # K3 (CONTROL)
    try:
        root = _copy_sources(os.path.join(work, "k3"))
        copied = os.path.join(root, "app", "Sources")
        mapping = resolve(sites, grep_sites(copied))
        rewritten = copy.deepcopy(inventory)
        rewritten["sites"] = {mapping[ref]: entry for ref, entry in sites.items()}
        first = sorted(rewritten["sites"])[0]
        path, number = first.rsplit(":", 1)
        full = os.path.join(root, path)
        with open(full, encoding="utf-8") as f:
            lines = f.read().split("\n")
        lines[int(number) - 1] = ""
        with open(full, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        reported = {(c, s) for c, s, _ in check(rewritten, None, grep_sites(copied), root=root)
                    if c == "I2"}
        row("K3", reported == {("I2", first)},
            f"CONTROL: {first} blanked; I2 reported {sorted(reported)}")
    except Exception as error:
        row("K3", False, f"the control raised {error!r}")

    print(f"{sum(rows)}/{len(rows)}")
    return 0 if all(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
