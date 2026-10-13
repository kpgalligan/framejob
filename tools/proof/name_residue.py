#!/usr/bin/env python3
"""Rename R1 (spec §11 NM-8) — no line or path spells the old name that is not
allowed to.

    python3 tools/proof/name_residue.py                       # exit 0 clean, 1 offences
    python3 tools/proof/name_residue.py --selftest
    python3 tools/proof/name_residue.py --mutant ge-count|no-untracked

Every line of every tracked or untracked-unignored file that matches the old
name case-insensitively (`git grep -n -I -i --untracked`), and every such path
(`git ls-files -co --exclude-standard`), is an offence unless it is allowed:

* a path under `HISTORY` — kept whole;
* a line that one of `KEPT_PATTERNS` matches — an issue citation, an archived
  file's name, or an outside path that is real until the owner's renames;
* a file in `COUNTED` whose matching lines, less those `KEPT_PATTERNS` already
  allows, number EXACTLY its pinned count — one over or one under fails.

An offence prints one line: `<path>:<n>: <text>`, `<path>: <found> lines,
COUNTED pins <pinned>`, or `<path>: path holds the old name`. Standard library
only. The road map is `archive/rename.md`; its condensed record `designs/adr/rename.md`.

**The selftest** builds a scratch git repository under
`tools/proof/work/name_residue/` and scores: S0 (CONTROL) a clean tree passes;
S1 a stray line in a tracked file fails; S2 a stray line in an untracked file
fails; S3 a counted file one line over fails; S4 one line under fails; S5 a
tracked path holding the name fails; S6 (CONTROL) a `HISTORY` path and a
`KEPT_PATTERNS` line pass. A `--mutant` runs the selftest and must fail
exactly its row: `ge-count` (the pin a ceiling: a counted file passes at or
under it) S4;
`no-untracked` (untracked files not read) S2.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
WORK = os.path.join(ROOT, "tools", "proof", "work", "name_residue")
NAME = "reelcut"

# Kept whole: history (spec §11 NM-1), the rename's road map and ADR among it.
HISTORY = (
    "archive/",
    "designs/adr/",
    "designs/design_handoff_reelcut/",
    "designs/design_handoff_reelcut_sharp/",
    "designs/design_handoff_clip_inspector/",
    "designs/clip_inspector_brief/",
    ".dupscan/",
)

# A line one of these matches is allowed in any file: issue citations redirect since
# the repository's rename (2026-10-13), archived files keep their names, and the two
# outside paths are where spec §11's append-only text recorded a past worktree, a past
# run's file or a litecode brief.
KEPT_PATTERNS = (
    r"kpgalligan/reelcut#\d+",
    r"archive/reelcut-[\w.-]+\.md",
    r"\.claude/litecode/reelcut/",
    r"devel/reelcut[\w-]*",
)

# Files that must keep some old spellings, each at its exact count of matching lines
# not already allowed by KEPT_PATTERNS. Each comment says why and which phase ends it.
COUNTED = {
    # -- Permanent: spec §11's decision text is append-only, and its index's decision rows
    # keep each decision's own words (NM-1); the index's Files table says today's names.
    "designs/spec/11-decisions/README.md": 18,
    "designs/spec/11-decisions/agent-connection.md": 18,
    "designs/spec/11-decisions/assistant.md": 11,
    "designs/spec/11-decisions/chrome-inspector-keys.md": 2,
    "designs/spec/11-decisions/cloud-captions.md": 11,
    "designs/spec/11-decisions/deepening.md": 18,
    "designs/spec/11-decisions/dev-tools.md": 10,
    "designs/spec/11-decisions/foundations.md": 2,
    "designs/spec/11-decisions/grading-2.md": 2,
    "designs/spec/11-decisions/grading-3.md": 12,
    "designs/spec/11-decisions/grading.md": 16,
    "designs/spec/11-decisions/graphics.md": 13,
    "designs/spec/11-decisions/precision.md": 3,
    "designs/spec/11-decisions/pricing.md": 12,
    "designs/spec/11-decisions/publishing.md": 5,
    "designs/spec/11-decisions/recording.md": 24,
    "designs/spec/11-decisions/rename.md": 15,
    "designs/spec/11-decisions/word-captions.md": 6,
    # -- Permanent: a pointer to a path that keeps the old name (NM-1): the two design
    # handoff folders, the spec's single file in git history, and the proof README's
    # recorded results (its dated runs, result tables, quoted output and old-tree builds).
    "designs/spec/03-window-layout.md": 2,
    "designs/spec/README.md": 1,
    "tools/proof/README.md": 200,
    # -- Root CLAUDE.md: lines 43 and 45 name the design handoff folders (permanent, NM-1),
    # line 260 the old proofs' ledger folder `budget.py` guards (permanent, NM-7).
    "CLAUDE.md": 3,
    # -- Permanent: the old generated paths stay ignored (every tree built before R1 holds them).
    ".gitignore": 2,
    # -- Permanent: tools that must name the old spelling to refuse it, find it, build or
    # compare a tree from before R1, read the old ledger folder (NM-6, NM-7, NM-8), or
    # name a design handoff's folder, which keeps its name (NM-1).
    "tools/proof/assistant_spike/README.md": 1,
    "tools/proof/budget.py": 1,
    "tools/proof/budget_proof.py": 2,
    "tools/proof/cloud_captions_probe.py": 3,
    "tools/proof/grading_spike/grading_spike.py": 2,
    "tools/proof/grading_verdict.py": 7,
    "tools/proof/harness/main.swift": 2,
    "tools/proof/matte_spike/matte_spike.py": 1,
    "tools/proof/mcp.py": 1,
    "tools/proof/name_residue.py": 6,
    "tools/proof/phase5_chrome.py": 1,
    "tools/proof/phase8_chrome.py": 1,
    "tools/proof/proof_defaults.py": 25,
    "tools/proof/reference_build.py": 5,
    "tools/proof/reference_build_selftest.py": 8,
    "tools/proof/sharp_chrome.py": 1,
    "tools/proof/stale_registrations.py": 4,
    # -- Permanent: a spike README's line quoting a past run's output (a recorded log name
    # or input path).
    "tools/proof/graphics_spike/README.md": 1,
    "tools/proof/silence_spike/README.md": 1,
}

MUTANT = None


def _git(root, *arguments):
    done = subprocess.run(["git", "-C", root, *arguments], capture_output=True, text=True,
                          errors="replace", timeout=120)
    if done.returncode not in (0, 1):
        raise RuntimeError(f"git {' '.join(arguments)} exited {done.returncode}: "
                           f"{done.stderr.strip()[-300:]}")
    return done.stdout


def _historic(path, history):
    return any(path == one or (one.endswith("/") and path.startswith(one)) for one in history)


def residue(root: str, *, history=HISTORY, kept=KEPT_PATTERNS, counted=COUNTED) -> list[str]:
    """The offences under `root`, one string each; empty means the tree passes."""
    grep = ["grep", "-n", "-I", "-i"]
    if MUTANT != "no-untracked":
        grep.append("--untracked")
    found = {}
    for line in _git(root, *grep, "-e", NAME, "--").splitlines():
        path, number, text = line.split(":", 2)
        if _historic(path, history):
            continue
        if any(re.search(pattern, text, re.I) for pattern in kept):
            continue
        found.setdefault(path, []).append((int(number), text))
    offences = []
    for path in sorted(set(found) | set(counted)):
        lines = found.get(path, [])
        if path in counted:
            pinned = counted[path]
            ok = pinned >= len(lines) if MUTANT == "ge-count" else len(lines) == pinned
            if not ok:
                offences.append(f"{path}: {len(lines)} lines, COUNTED pins {pinned}")
            continue
        offences += [f"{path}:{number}: {text.strip()}" for number, text in lines]
    listed = ["ls-files", "-c", "--exclude-standard"]
    if MUTANT != "no-untracked":
        listed.insert(2, "-o")
    for path in sorted(set(_git(root, *listed).splitlines())):
        if NAME in path.lower() and not _historic(path, history):
            offences.append(f"{path}: path holds the old name")
    return offences


# ---- the selftest ----------------------------------------------------------------

def _write(root, path, text):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as handle:
        handle.write(text)


def _scratch(name, files, tracked=True):
    """A scratch repository holding `files`, committed when `tracked`."""
    root = os.path.join(WORK, name)
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(root)
    subprocess.run(["git", "init", "-q", root], check=True, timeout=60)
    _write(root, "clean.txt", "Frame Job\n")
    for path, text in files.items():
        _write(root, path, text)
    if tracked:
        subprocess.run(["git", "-C", root, "add", "-A"], check=True, timeout=60)
    return root


def selftest(mutant: str | None = None) -> int:
    global MUTANT
    MUTANT = mutant
    results = []
    old, Old = NAME, NAME.capitalize()
    history, kept = ("history/",), (r"issues/reelcut#\d+",)
    counted = {"counted.txt": 2}
    two = f"{Old} one\nmiddle\n{old} two\n"

    def row(name, ok, detail):
        results.append((name, bool(ok)))
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)

    def check(name, root, want_clean, what):
        try:
            found = residue(root, history=history, kept=kept, counted=counted)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            row(name, False, f"{what}: the check could not run: {error}")
            return
        row(name, (not found) == want_clean, f"{what}: {found or 'clean'}")

    shutil.rmtree(WORK, ignore_errors=True)
    check("S0", _scratch("s0", {"counted.txt": two}), True,
          "CONTROL: a counted file at its pin, the rest clean")
    check("S1", _scratch("s1", {"counted.txt": two, "a.txt": f"the {Old} app\n"}), False,
          "a stray line in a tracked file")
    root = _scratch("s2", {"counted.txt": two})
    _write(root, "loose.txt", f"a {old} line\n")
    check("S2", root, False, "a stray line in an untracked file")
    check("S3", _scratch("s3", {"counted.txt": two + f"{old} three\n"}), False,
          "a counted file one line over its pin")
    check("S4", _scratch("s4", {"counted.txt": f"{Old} one\n"}), False,
          "a counted file one line under its pin")
    check("S5", _scratch("s5", {"counted.txt": two, f"{old}-notes/a.txt": "nothing\n"}), False,
          "a tracked path holding the name")
    check("S6", _scratch("s6", {"counted.txt": two, f"history/{old}-x/a.txt": f"{Old}\n",
                                "b.txt": f"see issues/{old}#12\n"}), True,
          "CONTROL: a HISTORY path and a KEPT_PATTERNS line pass")
    shutil.rmtree(WORK, ignore_errors=True)
    failed = {name for name, ok in results if not ok}
    print(f"{len(results) - len(failed)}/{len(results)} rows pass")
    expected = {"ge-count": {"S4"}, "no-untracked": {"S2"}}
    if mutant:
        ok = failed == expected[mutant]
        print(f"MUTANT {'PASS' if ok else 'FAIL'}: {mutant} failed {sorted(failed)}, expected "
              f"{sorted(expected[mutant])}")
        return 0 if ok else 1
    print("PASS" if not failed else "FAIL")
    return 0 if not failed else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description="rename R1: the old name's residue (NM-8)")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=("ge-count", "no-untracked"))
    arguments = parser.parse_args(argv)
    if arguments.selftest or arguments.mutant:
        return selftest(arguments.mutant)
    try:
        offences = residue(ROOT)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"name_residue: the check could not run: {error}")
        return 1
    for offence in offences:
        print(offence)
    return 1 if offences else 0


if __name__ == "__main__":
    sys.exit(main())
