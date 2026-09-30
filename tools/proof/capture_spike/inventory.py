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
  I2  the grep's sites and `sites` are one-to-one, each line holding its token
      and lying in its entry's `func`; a site is FOUND BY ITS TOKEN AND ITS
      ENCLOSING FUNCTION, not its line (#166, #168): `resolve` pairs the
      inventory's sites with the grep's per (file, token, func) — `func` the
      nearest `func NAME` or `init(` declaration at or above the line — in
      line order, whenever the two counts agree, so a line added above a
      site moves its pin instead of failing it; where they disagree each pin
      stands as written. A site removed and another added in one file and
      token no longer balance unless both are in one function, so a swap
      across functions is reported (K4);
  I3  every citation is checked for content (#168). A citation is a SITE ref,
      `app/Sources/<F>.swift:<N>` naming a key of `sites` (read at its
      resolved line), or an ANCHORED ref, ``app/Sources/<F>.swift `<anchor>` ``,
      whose anchor is a piece of the line meant and occurs exactly once in
      `<F>`. Each `code` item is exactly one citation; `note`, `via`, `gate`
      and `other_caller` hold citations in prose; any other `<F>.swift:<N>`
      is a problem, as is a line citation that is not a site, an anchor
      missing or not unique, and a `reached_after` whose `via` cites nothing.
      A `modal` selector cites a line holding a loop token, a `sheet` one a
      sheet token; every `reached_from` / `reached_after` selector names a
      row; a selector in the `reached_from` of a `runModal` or loop-token
      site is `modal` (`reached_after` never forces a verdict);
  I4  the checker over a copy missing one selector and one site reports
      exactly those two.

`python3 tools/proof/capture_spike/inventory.py --check` is a line of
`make test`: no app, no probe, no build, in a fresh `work/inventory_check/`.

  K1  I2 and I3 over the tree have no problem (I1 needs the probe, so it is
      `v2_menu.py`'s H1); its detail lists the pins found at another line;
  K2  CONTROL: a copy of `app/Sources` with three blank lines put at the top
      of every file that holds a site or is cited by an anchor has no I2 or
      I3 problem;
  K3  CONTROL: a fresh copy, the inventory's site keys first rewritten
      through `resolve`, then the line of the first rewritten site blanked:
      the checker reports exactly that site under I2;
  K4  CONTROL: a fresh copy, the keys rewritten, the first site's line
      blanked and `func b13Swap() { <that line> }` appended as the file's
      last line — a swap in one file and token: I2 reports exactly that site
      (its line does not hold its token) and the appended line (a grep site
      missing from the inventory);
  K5  CONTROL: the first anchored `code` citation (selectors sorted) with an
      invisible U+2063 appended to its anchor: `check` reports exactly that
      selector under I3 beyond the tree's own problems.

Every control that writes into its copy calls `_forget(root)` after its last
write and before its `check`, because `line_of` caches each file it reads.
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
FUNC = re.compile(r"\bfunc\s+([A-Za-z_]\w*)|(?:^|\s)(init)\s*[?!]?\s*[(<]")
CITE = re.compile(r"(app/Sources/[\w+]+\.swift)(?::(\d+)| `([^`\n]+)`)")
BARE = re.compile(r"(?<![\w/+])[\w+]+\.swift:\d+")
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


def _forget(root):
    """Evict every `_lines` entry whose path is under `root`: a control that
    wrote into its copy reads the files again."""
    prefix = os.path.join(os.path.abspath(root), "")
    for full in [k for k in _lines if k.startswith(prefix)]:
        del _lines[full]


def _file_lines(path, root=ROOT):
    """Every line of `path` (under `root`) through `line_of`'s cache, or None."""
    line_of(f"{path}:1", root)
    return _lines.get(os.path.join(root, path))


def enclosing_func(ref, root=ROOT):
    """The name of the nearest line at or above `ref`'s that does not start
    `//` and matches `FUNC` (`init` for an initializer); "" if none."""
    path, number = ref.rsplit(":", 1)
    for n in range(int(number), 0, -1):
        line = line_of(f"{path}:{n}", root)
        if line is None or line.strip().startswith("//"):
            continue
        match = FUNC.search(line)
        if match:
            return match.group(1) or match.group(2)
    return ""


def citations(text):
    """(path, line, anchor) per `CITE` match in `text`: a site ref has a line
    and no anchor, an anchored ref an anchor and no line."""
    return [(m.group(1), int(m.group(2)) if m.group(2) else None, m.group(3))
            for m in CITE.finditer(text or "")]


def _line_number(ref):
    return int(ref.rsplit(":", 1)[1])


def resolve(sites, grep, root=ROOT):
    """{inventory site ref: current ref}. The inventory's sites are grouped
    by (file, entry `token`, entry `func`) and the grep's by (file, grep
    token, `enclosing_func` under `root`); where a group's two counts agree
    they are paired in line order, and otherwise each inventory ref maps to
    itself."""
    ours, theirs = {}, {}
    for ref, entry in sites.items():
        ours.setdefault((ref.rsplit(":", 1)[0], entry.get("token"), entry.get("func")),
                        []).append(ref)
    for ref, token in grep.items():
        theirs.setdefault((ref.rsplit(":", 1)[0], token, enclosing_func(ref, root)),
                          []).append(ref)
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
    mapping = resolve(sites, grep, root)

    def at(ref):
        return line_of(mapping.get(ref, ref), root)

    def cited(path, number, anchor):
        """(the line a citation means or None, why not): a site ref at its
        resolved line, an anchored ref at the one line holding its anchor."""
        if number is not None:
            ref = f"{path}:{number}"
            if ref not in sites:
                return None, f"line citation {ref} is not a site"
            line = at(ref)
            return line, "" if line is not None else f"cited line {ref} does not exist"
        lines = _file_lines(path, root)
        if lines is None:
            return None, f"anchor file {path} is missing"
        count = "\n".join(lines).count(anchor)
        if count != 1:
            return None, f"anchor `{anchor}` occurs {count} times in {path}, not once"
        return next(line for line in lines if anchor in line), ""

    def prose(subject, text):
        """Every citation in `text` resolves; no bare `<F>.swift:<N>` outside one."""
        spans = [m.span() for m in CITE.finditer(text or "")]
        for m in BARE.finditer(text or ""):
            if not any(a <= m.start() and m.end() <= b for a, b in spans):
                problems.append(("I3", subject, f"bare citation {m.group(0)}"))
        for path, number, anchor in citations(text):
            _, why = cited(path, number, anchor)
            if why:
                problems.append(("I3", subject, why))

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
        func = entry.get("func")
        if not isinstance(func, str):
            problems.append(("I2", ref, f"func {func!r} is not a string"))
        elif line is not None and enclosing_func(now, root) != func:
            problems.append(("I2", ref, f"in func {enclosing_func(now, root)!r}, not {func!r}"))
    # I3
    for sel, row in selectors.items():
        verdict = row.get("verdict")
        if verdict not in VERDICTS:
            problems.append(("I3", sel, f"verdict {verdict!r}"))
        lines = []
        for item in row.get("code", []):
            match = CITE.fullmatch(item)
            if not match:
                problems.append(("I3", sel, f"code item {item!r} is not one citation"))
                continue
            line, _ = cited(match.group(1), int(match.group(2)) if match.group(2) else None,
                            match.group(3))
            lines.append(line or "")
        if verdict == "modal" and not any(
                any(TOKEN_TEXT[t] in c for t in LOOP_TOKENS) for c in lines):
            problems.append(("I3", sel, "modal, but no cited line holds a loop token"))
        if verdict == "sheet" and not any(
                any(TOKEN_TEXT[t] in c for t in SHEET_TOKENS) for c in lines):
            problems.append(("I3", sel, "sheet, but no cited line holds a sheet token"))
        for item in row.get("code", []):
            prose(sel, item)
        prose(sel, row.get("note"))
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
            prose(ref, after.get("via"))
            prose(ref, after.get("gate"))
            if not citations(after.get("via")):
                problems.append(("I3", ref, "reached_after has no via citation"))
        prose(ref, entry.get("other_caller"))
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


def _anchored_files(inventory):
    """Every `app/Sources/<F>.swift` an anchored citation names."""
    texts = []
    for row in inventory.get("selectors", {}).values():
        texts += list(row.get("code", [])) + [row.get("note") or ""]
    for entry in inventory.get("sites", {}).values():
        texts.append(entry.get("other_caller") or "")
        for after in entry.get("reached_after", []):
            texts += [after.get("via") or "", after.get("gate") or ""]
    return {path for text in texts for path, _, anchor in citations(text) if anchor}


def _rewritten(inventory, sites, copied, root):
    """The inventory with its site keys rewritten through `resolve` over the
    copy (read before any write into it)."""
    mapping = resolve(sites, grep_sites(copied), root)
    rewritten = copy.deepcopy(inventory)
    rewritten["sites"] = {mapping[ref]: entry for ref, entry in sites.items()}
    return rewritten


def main(argv=None):
    parser = argparse.ArgumentParser(description="the menu inventory's sites, found by token "
                                                 "and enclosing function, and its other "
                                                 "citations, found by anchor, against "
                                                 "app/Sources")
    parser.add_argument("--check", action="store_true",
                        help="K1–K5 in a fresh work/inventory_check/")
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
        holding = sorted({ref.rsplit(":", 1)[0].rsplit("/", 1)[1] for ref in grep_sites(copied)}
                         | {path.rsplit("/", 1)[1] for path in _anchored_files(inventory)})
        for name in holding:
            path = os.path.join(copied, name)
            if not os.path.exists(path):
                continue
            with open(path, encoding="utf-8") as f:
                text = f.read()
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n\n\n" + text)
        _forget(root)
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
        rewritten = _rewritten(inventory, sites, copied, root)
        first = sorted(rewritten["sites"])[0]
        path, number = first.rsplit(":", 1)
        full = os.path.join(root, path)
        with open(full, encoding="utf-8") as f:
            lines = f.read().split("\n")
        lines[int(number) - 1] = ""
        with open(full, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        _forget(root)
        reported = {(c, s) for c, s, _ in check(rewritten, None, grep_sites(copied), root=root)
                    if c == "I2"}
        row("K3", reported == {("I2", first)},
            f"CONTROL: {first} blanked; I2 reported {sorted(reported)}")
    except Exception as error:
        row("K3", False, f"the control raised {error!r}")

    # K4 (CONTROL): a swap in one file and token, across functions.
    try:
        root = _copy_sources(os.path.join(work, "k4"))
        copied = os.path.join(root, "app", "Sources")
        rewritten = _rewritten(inventory, sites, copied, root)
        first = sorted(rewritten["sites"])[0]
        path, number = first.rsplit(":", 1)
        full = os.path.join(root, path)
        with open(full, encoding="utf-8") as f:
            lines = f.read().split("\n")
        moved_text = lines[int(number) - 1].strip()
        lines[int(number) - 1] = ""
        swap = f"func b13Swap() {{ {moved_text} }}"
        if lines and lines[-1] == "":
            lines[-1:] = [swap, ""]
            appended = f"{path}:{len(lines) - 1}"
        else:
            lines.append(swap)
            appended = f"{path}:{len(lines)}"
        with open(full, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        _forget(root)
        found = [(s, why) for c, s, why in check(rewritten, None, grep_sites(copied), root=root)
                 if c == "I2"]
        subjects = {s for s, _ in found}
        first_whys = [why for s, why in found if s == first]
        appended_whys = [why for s, why in found if s == appended]
        ok = (subjects == {first, appended}
              and any(why.startswith("line does not hold its token") for why in first_whys)
              and appended_whys == ["grep site missing from inventory"])
        row("K4", ok, f"CONTROL: {first} blanked and its line appended as {appended} in "
                      f"`func b13Swap`; I2 reported "
                      + ("; ".join(f"({s}, {why})" for s, why in sorted(found)) or "nothing"))
    except Exception as error:
        row("K4", False, f"the control raised {error!r}")

    # K5 (CONTROL): an anchor that no longer occurs.
    try:
        target = None
        for sel in sorted(inventory.get("selectors", {})):
            for index, item in enumerate(inventory["selectors"][sel].get("code", [])):
                match = CITE.fullmatch(item)
                if match and match.group(3):
                    target = (sel, index, match)
                    break
            if target:
                break
        if target is None:
            row("K5", False, "CONTROL: no anchored `code` citation to alter")
        else:
            sel, index, match = target
            altered = copy.deepcopy(inventory)
            altered["selectors"][sel]["code"][index] = f"{match.group(1)} `{match.group(3)}\u2063`"
            baseline = {(c, s) for c, s, _ in check(inventory, None, grep)}
            found = {(c, s) for c, s, _ in check(altered, None, grep)} - baseline
            row("K5", found == {("I3", sel)},
                f"CONTROL: {sel}'s anchor `{match.group(3)}` given a U+2063; the checker "
                f"reported {sorted(found)} beyond the tree's own")
    except Exception as error:
        row("K5", False, f"the control raised {error!r}")

    print(f"{sum(rows)}/{len(rows)}")
    return 0 if all(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
