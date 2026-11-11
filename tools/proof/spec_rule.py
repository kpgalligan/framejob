#!/usr/bin/env python3
"""#585 — a spike's rule hash: the spec §11 ENTRIES a run is judged by, found by ID and hashed
entry by entry (spec §11 CAM-2's Amended-by line). No app, no build, stdlib only.

    python3 tools/proof/spec_rule.py                          # the tree (make test)
    python3 tools/proof/spec_rule.py --selftest               # S1..S6 over scratch folders
    python3 tools/proof/spec_rule.py --selftest --mutant NAME # exits 1 naming exactly its rows

A spike that judges by a rule fixed before its run writes `rule_sha256` into its `results.json`,
so the rule a recorded run read is pinned. `pin(name)` answers the three keys a spike spreads into
its results: `rule_sha256`, the SHA-256 of the entries' texts joined in `RULES`' order (so for one
entry it is that entry's own hash); `rule_entries`, each ID's own hash and the file it was found
in; and `rule_method`, `"entries"`.

An ENTRY is the line that starts `- **<ID> — ` (the head `spec_index_proof.py` requires one file
to hold) and every following line up to the next line that is not blank and does not start with a
space; trailing blank lines are left out and each line carries its newline. It is found by
scanning every `*.md` of `designs/spec/11-decisions/` but the README: no file is named anywhere,
so a split of a §11 file, or an amendment to a neighbouring entry, moves no hash, and an amendment
to a judged entry moves it. An ID no file holds, or two heads hold, is refused by name.

`RULES` lists, for each spike and mode, EVERY entry the run's deciders read, not only the one the
run is named for: SR-7 takes its dropout rule, its video rule and Z0 from SR-5 by reference, and
SR-17 is the instrument rule for `render_spike.py`'s corrected playback signals.

Until #585 (2026-11-11) `rule_sha256` was the SHA-256 of the whole §11 file holding the rule
(`speed-ramps.md`, `speed-ramps-2.md` under `--verdict rate`, `camera-recording.md`), as the run
read it. That is what an older `results.json` and the archived records hold; they have no
`rule_method` key, and their values stay as recorded.

The tree check: every ID in `RULES` resolves to one entry (a line per name and ID: the file, the
line count, the hash), and each spike's source CALLS `spec_rule.pin("<name>")` with a string
constant for every `RULES` name of that spike and for nothing else, with no `RULE_FILE` left.
Its output is the same before and after a pure move of an entry between files, but for the file.
"""

import argparse
import ast
import hashlib
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DECISIONS = ROOT / "designs/spec/11-decisions"
PROOF = ROOT / "tools/proof"
SCRATCH = PROOF / "work/spec-rule-selftest"

# What each run is judged by. A name is `<spike>` or `<spike> <mode>`; the spike is in SPIKES.
RULES = {
    "ramp_spike": ("SR-5",),
    "render_spike": ("SR-5", "SR-7", "SR-17"),
    "render_spike --verdict on": ("SR-5", "SR-7", "SR-9", "SR-17"),
    "render_spike --verdict rate": ("SR-5", "SR-7", "SR-9", "SR-14", "SR-17"),
    "camera_spike": ("CAM-2",),
    "camera_spike --format": ("CAM-2", "CAM-3"),
}
SPIKES = {
    "ramp_spike": "ramp_spike/ramp_spike.py",
    "render_spike": "ramp_spike/render_spike.py",
    "camera_spike": "camera_spike/camera_spike.py",
}

# The mutants, as `mutant_anchors.py` reads them: switches on MUTANT, no tree text.
EXPECTED = {
    "stop-at-blank": {"S1"},              # creator_spike/rule.py's rule: two leading spaces
    "whole-file": {"S1", "S2", "S3"},     # the old behaviour: the holding file's bytes
    "head-only": {"S1", "S3"},            # S3's second half: a change past the head line
    "prefix-loose": {"S4"},
    "first-wins": {"S4"},
    "first-entry-only": {"S5"},
    "literal-scan": {"S6"},               # a name anywhere in a string, not a `pin` call
}
MUTANTS = tuple(sorted(EXPECTED))
MUTANT = None


def sha(data):
    return hashlib.sha256(data).hexdigest()


def entry(ident, folder=DECISIONS):
    """`(file name, bytes)` of the one entry `- **<ident> — ` under `folder`."""
    head = f"- **{ident}".encode() if MUTANT == "prefix-loose" else f"- **{ident} — ".encode()
    found = []
    for path in sorted(Path(folder).glob("*.md")):
        if path.name == "README.md":
            continue
        data = path.read_bytes()
        lines = data.split(b"\n")
        for index, line in enumerate(lines):
            if line.startswith(head):
                found.append((path.name, data, lines, index))
    if not found:
        raise SystemExit(f"spec_rule: no entry `- **{ident} — ` in {folder}")
    if len(found) > 1 and MUTANT != "first-wins":
        raise SystemExit(f"spec_rule: {len(found)} entries `- **{ident} — ` in {folder}: "
                         + ", ".join(name for name, *_ in found))
    name, data, lines, index = found[0]
    if MUTANT == "whole-file":
        return name, data
    taken = [lines[index]]
    for line in lines[index + 1:]:
        if MUTANT == "head-only":
            break
        if MUTANT == "stop-at-blank":
            if not line.startswith(b"  "):
                break
        elif line.strip() and not line.startswith(b" "):
            break
        taken.append(line)
    while not taken[-1].strip():
        taken.pop()
    return name, b"".join(line + b"\n" for line in taken)


def pin(name, folder=DECISIONS, rules=None):
    """The keys a spike spreads into its `results.json` for the run `name` of `RULES`."""
    idents = (RULES if rules is None else rules)[name]
    if MUTANT == "first-entry-only":
        idents = idents[:1]
    entries, joined = {}, b""
    for ident in idents:
        file, text = entry(ident, folder)
        entries[ident] = {"file": file, "sha256": sha(text)}
        joined += text
    return {"rule_sha256": sha(joined), "rule_entries": entries, "rule_method": "entries"}


def pinned_names(source):
    """`(names, problems)`: the string constants `source` passes to `spec_rule.pin`."""
    names, problems = [], []
    if MUTANT == "literal-scan":
        literals = {node.value for node in ast.walk(ast.parse(source))
                    if isinstance(node, ast.Constant) and isinstance(node.value, str)}
        return [name for name in RULES if name in literals], problems
    for node in ast.walk(ast.parse(source)):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "pin" and isinstance(node.func.value, ast.Name)
                and node.func.value.id == "spec_rule"):
            continue
        args = node.args
        if (len(args) == 1 and not node.keywords and isinstance(args[0], ast.Constant)
                and isinstance(args[0].value, str)):
            names.append(args[0].value)
        else:
            problems.append(f"line {node.lineno}: spec_rule.pin is not called with one string "
                            "constant")
    return names, problems


def check_spike(spike, source, rules=None):
    """Problems with `spike`'s source: its `pin` calls against its names in `rules`."""
    rules = RULES if rules is None else rules
    wanted = {name for name in rules if name.split(" ")[0] == spike}
    names, problems = pinned_names(source)
    for name in sorted(set(names) - wanted):
        problems.append(f"pins {name!r}, which is not a name of {spike} in RULES")
    for name in sorted(wanted - set(names)):
        problems.append(f"never calls spec_rule.pin({name!r})")
    if "RULE_FILE" in source and MUTANT != "literal-scan":
        problems.append("still names RULE_FILE")
    return problems


def tree():
    failures = 0
    for name, idents in RULES.items():
        answer = pin(name)
        print(f"{name}: rule_sha256 {answer['rule_sha256']}")
        for ident in idents:
            file, text = entry(ident)
            print(f"  {ident}  {file}  {text.count(b"\n")} lines  {sha(text)}")
    for spike, relative in SPIKES.items():
        problems = check_spike(spike, (PROOF / relative).read_text(encoding="utf-8"))
        for problem in problems:
            print(f"FAIL {relative}: {problem}")
        if not problems:
            wanted = sorted(n for n in RULES if n.split(" ")[0] == spike)
            print(f"ok   {relative}: pins {', '.join(wanted)}; no RULE_FILE")
        failures += len(problems)
    unknown = sorted({n.split(" ")[0] for n in RULES} - set(SPIKES))
    for spike in unknown:
        print(f"FAIL RULES names {spike}, which SPIKES does not hold")
    failures += len(unknown)
    print(f"spec_rule: {'ok' if not failures else f'{failures} problem(s)'}")
    return 1 if failures else 0


# ---- the selftest ---------------------------------------------------------------------------

PREFACE = "# A scratch file\n\nA preface in column 0.\n\n"
A_HEAD = "- **ZZ-1 — The first rule.** Its text\n  runs on.\n"
A_TAIL = "  - A bullet.\n\n  An indented paragraph after a blank line (CAM-2's shape).\n"
A = A_HEAD + A_TAIL
B = "- **ZZ-2 — The second rule.** One line\n  and another.\n"
TEN = "- **ZZ-10 — The tenth rule.**\n  Its own text.\n"


def scratch(name, files):
    folder = SCRATCH / name
    folder.mkdir(parents=True)
    for file, text in files.items():
        (folder / file).write_text(text, encoding="utf-8")
    return folder


def refused(call):
    try:
        call()
    except SystemExit as stop:
        return str(stop)
    return None


def selftest_rows():
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    rows = {}

    def row(name, checks):
        bad = [text for ok, text in checks if not ok]
        rows[name] = bad

    def guarded(name, make):
        try:
            row(name, make())
        except (SystemExit, Exception) as error:  # noqa: BLE001 — a row that raised is a red row
            rows[name] = [f"raised {type(error).__name__}: {error}"]

    def s1():
        folder = scratch("s1", {"one.md": PREFACE + A + "\n\n" + B, "README.md": A})
        file, text = entry("ZZ-1", folder)
        return [(file == "one.md", f"found in {file}"),
                (text == A.encode(), f"the entry is {text!r}"),
                (text.endswith(b"(CAM-2's shape).\n"), "the indented paragraph is not its end")]

    def s2():
        middle = scratch("s2-middle", {"one.md": PREFACE + A + "\n" + B})
        last = scratch("s2-last", {"one.md": PREFACE + B + A})
        moved = scratch("s2-moved", {"one.md": PREFACE + B,
                                     "one-1b.md": "# Another head\n\nMoved here.\n\n" + A})
        before = scratch("s2-para", {"one.md": A + "\nA paragraph in column 0.\n\n" + B})
        hashes = [sha(entry("ZZ-1", f)[1]) for f in (middle, last, moved, before)]
        return [(len(set(hashes)) == 1, f"four placements hash {sorted(set(hashes))}"),
                (entry("ZZ-1", moved)[0] == "one-1b.md", "the moved entry's file")]

    def s3():
        base = scratch("s3-base", {"one.md": PREFACE + B + A})
        neighbour = scratch("s3-neighbour", {"one.md": PREFACE + B + A
                                             + "  **Amended by #1**: more.\n"})
        changed = scratch("s3-changed", {"one.md": PREFACE + B.replace("another.", "another!")
                                         + A})
        first = sha(entry("ZZ-2", base)[1])
        return [(sha(entry("ZZ-2", neighbour)[1]) == first, "a neighbour's amendment moved it"),
                (sha(entry("ZZ-2", changed)[1]) != first,
                 "a byte changed in the entry's last line did not move it")]

    def s4():
        folder = scratch("s4", {"one.md": PREFACE + A, "ten.md": TEN, "two.md": PREFACE + B})
        twice = scratch("s4-twice", {"one.md": PREFACE + A, "two.md": PREFACE + A})
        same = scratch("s4-same", {"one.md": PREFACE + A + B + A})
        none, two, one = (refused(lambda: entry("ZZ-3", folder)),
                          refused(lambda: entry("ZZ-1", twice)),
                          refused(lambda: entry("ZZ-1", same)))
        return [(entry("ZZ-1", folder)[0] == "one.md", "ZZ-1 is not found in its own file"),
                (entry("ZZ-10", folder)[0] == "ten.md", "ZZ-10 is not found in its own file"),
                (none is not None and "ZZ-3" in none, f"an ID in no file: {none!r}"),
                (two is not None and "one.md, two.md" in two, f"an ID in two files: {two!r}"),
                (one is not None and "ZZ-1" in one, f"an ID twice in one file: {one!r}")]

    def s5():
        folder = scratch("s5", {"one.md": PREFACE + A, "two.md": PREFACE + B})
        rules = {"one": ("ZZ-1",), "ab": ("ZZ-1", "ZZ-2"), "ba": ("ZZ-2", "ZZ-1")}
        one, ab, ba = (pin(name, folder, rules) for name in ("one", "ab", "ba"))
        a, b = entry("ZZ-1", folder)[1], entry("ZZ-2", folder)[1]
        return [(one["rule_sha256"] == sha(a), "one entry's pin is not its hash"),
                (ab["rule_sha256"] == sha(a + b), "two entries are not joined in order"),
                (ab["rule_sha256"] != ba["rule_sha256"], "order does not matter"),
                (ab["rule_entries"] == {"ZZ-1": {"file": "one.md", "sha256": sha(a)},
                                        "ZZ-2": {"file": "two.md", "sha256": sha(b)}},
                 f"rule_entries is {ab['rule_entries']}"),
                (ab["rule_method"] == "entries", "rule_method")]

    def s6():
        good = ('SPIKE = HERE / "camera_spike"\n'
                'rule = (spec_rule.pin("camera_spike --format") if args.format\n'
                '        else spec_rule.pin("camera_spike"))\n')
        literal = 'SPIKE = HERE / "camera_spike"\nNAMES = ["camera_spike --format"]\n'
        renamed = good.replace('pin("camera_spike --format")', 'pin("ramp_spike")')
        computed = good + "other = spec_rule.pin(NAME)\n"
        left = good + "RULE_FILE = ROOT / 'x.md'\n"
        return [(check_spike("camera_spike", good) == [], f"{check_spike('camera_spike', good)}"),
                (len(check_spike("camera_spike", literal)) == 2, "a bare literal passed for a call"),
                (len(check_spike("camera_spike", renamed)) == 2, "a pin of another spike's name"),
                (len(check_spike("camera_spike", computed)) == 1, "a computed name passed"),
                (check_spike("camera_spike", left) == ["still names RULE_FILE"], "RULE_FILE left")]

    for name, make in (("S1", s1), ("S2", s2), ("S3", s3), ("S4", s4), ("S5", s5), ("S6", s6)):
        guarded(name, make)
    return rows


def selftest(mutant):
    global MUTANT
    MUTANT = mutant
    rows = selftest_rows()
    MUTANT = None
    for name, bad in rows.items():
        print(f"{'ok  ' if not bad else 'FAIL'} {name}" + "".join(f"\n       {text}" for text in bad))
    failed = {name for name, bad in rows.items() if bad}
    if mutant is None:
        print(f"spec_rule --selftest: {len(rows) - len(failed)}/{len(rows)}")
        return 1 if failed else 0
    ok = failed == EXPECTED[mutant]
    print(f"MUTANT {'PASS' if ok else 'FAIL'}: {mutant} failed {sorted(failed)}, expected "
          f"{sorted(EXPECTED[mutant])}")
    # Caught is exit 1; a mutant that fails other rows than its own is exit 2, never a pass.
    return 1 if ok else 2 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS)
    args = parser.parse_args()
    if args.mutant and not args.selftest:
        parser.error("--mutant needs --selftest")
    return selftest(args.mutant) if args.selftest else tree()


if __name__ == "__main__":
    sys.exit(main())
