#!/usr/bin/env python3
"""Issue batch B70 (#220) — the spec indexes' Lines cells against `wc -l`,
and a row for every spec file. No app, no build, stdlib only.

`designs/spec/README.md` and `designs/spec/11-decisions/README.md` each carry
a table whose rows read `` | [`<name>`](<link>) | <cell> | … ``. A FILE row's
cell is that file's line count (the number of newline bytes, what `wc -l`
prints). The FOLDER row (`11-decisions/`, linking its README) reads
`<N> in <M> files`: N is the summed line count of every `*.md` in the folder,
its README included, and M is how many there are. Every link must exist;
every `*.md` in `designs/spec/` but the README has exactly one row there,
every subdirectory has a folder row, and every `*.md` in `11-decisions/` but
its README has exactly one row in that README.

    python3 tools/proof/spec_index_proof.py             # the tree (make test)
    python3 tools/proof/spec_index_proof.py --selftest  # CONTROL + M1..M4

`--selftest` copies `designs/spec` to `tools/proof/work/spec_index/` (fresh)
and requires the copy to show 0 problems (CONTROL), then four mutants, each on
a fresh copy, to show exactly one problem naming its row: M1 the `07.6` row's
cell +1, M2 the `11-decisions/` folder cell's N +1, M3 the `deepening.md` cell
+1, M4 a new empty `zz-unindexed.md` beside the spec's files. Exit 0 when all
five hold, 1 otherwise.
"""

import argparse
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPEC = os.path.join(ROOT, "designs", "spec")
WORK = os.path.join(ROOT, "tools", "proof", "work", "spec_index")
DECISIONS = "11-decisions"

ROW = re.compile(r"^\| \[`(?P<name>[^`]+)`\]\((?P<link>[^)]+)\) \| (?P<cell>[^|]+?) \|")
FOLDER_CELL = re.compile(r"^(\d+) in (\d+) files$")


def count_lines(path: str) -> int:
    with open(path, "rb") as handle:
        return handle.read().count(b"\n")


def index_rows(readme: str) -> list[tuple[str, str, str]]:
    rows = []
    for line in readme.splitlines():
        match = ROW.match(line)
        if match:
            rows.append((match["name"], match["link"], match["cell"].strip()))
    return rows


def markdown_files(folder: str) -> list[str]:
    return sorted(name for name in os.listdir(folder)
                  if name.endswith(".md") and os.path.isfile(os.path.join(folder, name)))


def check_index(spec_dir: str, folder: str, label: str, report: list) -> None:
    """One index (`<folder>/README.md`): its rows' cells and links, and a row
    for every `*.md` beside it and (for the top index) every subdirectory.
    Appends `(ok, text)` per check to `report`."""
    readme_path = os.path.join(folder, "README.md")
    with open(readme_path, encoding="utf-8") as handle:
        rows = index_rows(handle.read())
    named = {}
    for name, link, cell in rows:
        named.setdefault(name, []).append(link)
        target = os.path.join(folder, link)
        if not os.path.exists(target):
            report.append((False, f"{label}: {name} links {link}, which does not exist"))
            continue
        report.append((True, f"{label}: {name} links {link}"))
        if name.endswith("/"):
            sub = os.path.join(folder, name.rstrip("/"))
            if link != f"{name}README.md":
                report.append((False, f"{label}: {name} links {link}, not {name}README.md"))
                continue
            files = markdown_files(sub)
            total = sum(count_lines(os.path.join(sub, f)) for f in files)
            match = FOLDER_CELL.match(cell)
            if not match:
                report.append((False, f"{label}: {name} reads {cell!r}, not '<N> in <M> files'"
                                      f" (wc -l {total} in {len(files)} files)"))
            elif (int(match[1]), int(match[2])) != (total, len(files)):
                report.append((False, f"{label}: {name} reads {cell}, wc -l {total} in {len(files)} files"))
            else:
                report.append((True, f"{label}: {name} reads {cell}"))
        else:
            actual = count_lines(target)
            if not cell.isdigit():
                report.append((False, f"{label}: {name} reads {cell!r}, not a number (wc -l {actual})"))
            elif int(cell) != actual:
                report.append((False, f"{label}: {name} reads {cell}, wc -l {actual}"))
            else:
                report.append((True, f"{label}: {name} reads {cell}"))
    for name in markdown_files(folder):
        if name == "README.md":
            continue
        count = len(named.get(name, []))
        if count == 0:
            report.append((False, f"{label}: {name} has no row"))
        elif count > 1:
            report.append((False, f"{label}: {name} has {count} rows"))
        else:
            report.append((True, f"{label}: {name} has one row"))
    if folder == spec_dir:
        for entry in sorted(os.listdir(folder)):
            if os.path.isdir(os.path.join(folder, entry)):
                ok = f"{entry}/" in named
                report.append((ok, f"{label}: {entry}/ " + ("has a folder row" if ok else "has no folder row")))


def run_checks(spec_dir: str) -> list:
    report = []
    check_index(spec_dir, spec_dir, "designs/spec/README.md", report)
    sub = os.path.join(spec_dir, DECISIONS)
    sub_label = f"designs/spec/{DECISIONS}/README.md"
    if os.path.isfile(os.path.join(sub, "README.md")):
        check_index(spec_dir, sub, sub_label, report)
    else:
        report.append((False, f"{sub_label}: missing"))
    return report


def check(spec_dir: str) -> tuple[int, list[str]]:
    report = run_checks(spec_dir)
    return len(report), [text for ok, text in report if not ok]


def fresh_copy() -> str:
    if os.path.exists(WORK):
        shutil.rmtree(WORK)
    os.makedirs(WORK)
    copy = os.path.join(WORK, "spec")
    shutil.copytree(SPEC, copy)
    return copy


def bump_cell(readme: str, name: str, folder: bool = False) -> None:
    with open(readme, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    hits = 0
    for i, line in enumerate(lines):
        match = ROW.match(line)
        if not match or match["name"] != name:
            continue
        cell = match["cell"]
        if folder:
            n, m = FOLDER_CELL.match(cell.strip()).groups()
            new = f"{int(n) + 1} in {m} files"
        else:
            new = str(int(cell.strip()) + 1)
        start, end = match.span("cell")
        lines[i] = line[:start] + new + line[end:]
        hits += 1
    if hits != 1:
        raise RuntimeError(f"{name}: {hits} rows in {readme}")
    with open(readme, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


def selftest() -> int:
    held = 0
    try:
        copy = fresh_copy()
        _, problems = check(copy)
        ok = not problems
        held += ok
        print(f"  {'ok  ' if ok else 'FAIL'} CONTROL: the copy shows 0 problems"
              + ("" if ok else f" — {problems}"))
    except Exception as error:  # an instrument that cannot run is a FAIL
        print(f"  FAIL CONTROL: {type(error).__name__}: {error}")

    def m1(copy):
        bump_cell(os.path.join(copy, "README.md"), "07.6-playback-update-rules.md")

    def m2(copy):
        bump_cell(os.path.join(copy, "README.md"), f"{DECISIONS}/", folder=True)

    def m3(copy):
        bump_cell(os.path.join(copy, DECISIONS, "README.md"), "deepening.md")

    def m4(copy):
        open(os.path.join(copy, "zz-unindexed.md"), "w").close()

    mutants = [
        ("M1", "the 07.6 row's cell +1", m1, "07.6-playback-update-rules.md"),
        ("M2", "the 11-decisions/ folder cell's N +1", m2, f"{DECISIONS}/"),
        ("M3", "the deepening.md cell +1", m3, "deepening.md"),
        ("M4", "a new empty zz-unindexed.md", m4, "zz-unindexed.md"),
    ]
    for ident, what, mutate, row in mutants:
        try:
            copy = fresh_copy()
            mutate(copy)
            _, problems = check(copy)
            ok = len(problems) == 1 and row in problems[0]
            held += ok
            print(f"  {'ok  ' if ok else 'FAIL'} {ident}: {what} — "
                  + (f"caught: {problems[0]}" if ok else f"problems {problems}"))
        except Exception as error:
            print(f"  FAIL {ident}: {type(error).__name__}: {error}")
    print(f"{held}/5 selftest cases held")
    return 0 if held == 5 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    report = run_checks(SPEC)
    for ok, text in report:
        print(f"  {'ok  ' if ok else 'FAIL'} {text}")
    problems = [text for ok, text in report if not ok]
    print(f"{len(report) - len(problems)}/{len(report)} checks passed")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
