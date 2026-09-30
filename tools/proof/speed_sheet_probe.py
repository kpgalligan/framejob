#!/usr/bin/env python3
"""Issue batch B20 (#109): the Speed sheet names each clip a slowed selection
gives a transition, and its length, read off the trial handle (spec §11 D4-6).

    python3 tools/proof/speed_sheet_probe.py [--sources DIR] [--mutant NAME]

`speed_sheet_probe.swift` is built with `harness/build.sh`'s swiftc line
(`-D REELCUT_DEV_TOOLS`, the bridging header, `-lreelcut_core`) over
`--sources` into `tools/proof/work/speed-sheet/`, and run once. It drives the
real sheet — `SpeedSheetController(document:clips:)`, its view loaded, the
rate set in its own field and `controlTextDidEndEditing(_:)` called — over
`source_mirror_probe.py` §5's fixture, and answers the readout's lines. Prints
`<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  B0  the probe builds.
  P0  CONTROL: [A] at ×1 — one line, the summary as it always read.
  P1  [A] at ×0.5 — line 2 exactly `clip <B> gains a 0.67 s cross dissolve`.
  P2  [C] at ×0.5, refused by the overlap rule — one line.
  P3  [A, C] at ×0.5 — line 1 `2 clips · …`, then exactly P1's line.
  P4  CONTROL: A already at ×0.5 (B already has its dissolve), then [A] at
      ×0.4 — the summary's two lengths differ, one line (a transition that
      only lengthens is not named).
  P5  B given a wipe first (no overlap yet), then [A] at ×0.5 — line 2
      exactly `clip <B> gains a 0.67 s wipe`.
  H1  the hint is the new text.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed; a build failure is B0's FAIL there. A `--mutant` run exits 1 when
every row the mutant names failed (caught), 0 when one passed (survived),
and 2 when the control could not be performed: the copy's `before` text not
found exactly once, the copy did not build, or a named row was not scored.
An answer that is not a JSON object, or that lacks `clips.B` or
`P5clips.B`, is no answer (issue batch B28): every row but B0 fails as
`no row: the answer lacks …` and is not scored, so a plain run exits 1 and
a `--mutant` run 2.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/speed-sheet"
ROWS = ["B0", "P0", "P1", "P2", "P3", "P4", "P5", "H1"]
BUILD_WALL = 600
RUN_WALL = 120
SUMMARY_X1 = "1 clip · 00:00:01:20 → 00:00:01:20"
HINT = ("Faster clips can leave gaps; slower clips can overlap. Later clips stay in place. "
        "A clip an allowed overlap reaches gains a transition, named below. If an overlap is "
        "not allowed, that clip stays unchanged; other selected clips can still change.")

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "no-gain-lines": (["P1", "P3", "P5"], [
        ("SpeedSheetController.swift",
         "return ([summary] + gains.map(gainLine)).joined(separator: \"\\n\")",
         "return ([summary] + gains.map(gainLine).prefix(0)).joined(separator: \"\\n\")")]),
    "minted-only": (["P5"], [
        ("SpeedSheetController.swift",
         "let had = effective(id, in: before)",
         "let had = effective(id, in: before) || before.clip(id)?.transitionIn != nil")]),
}


def run(command, timeout):
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def build(sources, here):
    """(binary, None) or (None, why)."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/speed_sheet_probe.swift", entry)
    binary = here / "speed-sheet-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60).stdout.strip()
        result = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                      "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
                      "-import-objc-header",
                      str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
                      "-L", str(lib.parent), "-lreelcut_core", *swift, str(entry),
                      "-o", str(binary)], BUILD_WALL)
    except subprocess.TimeoutExpired:
        return None, f"swiftc did not finish within {BUILD_WALL} s"
    if result.returncode:
        lines = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(lines[:8] or [result.stderr[-600:]])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; the reason when a
    `before` text is not found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def answer_gaps(answer):
    """The members of `clips.B` and `P5clips.B` the answer lacks — each
    path's parent must be an object holding the key; a non-object answer
    lacks both."""
    gaps = []
    for path in ("clips.B", "P5clips.B"):
        parent, key = path.split(".")
        holder = answer.get(parent) if isinstance(answer, dict) else None
        if not (isinstance(holder, dict) and key in holder):
            gaps.append(path)
    return gaps


def judge(answer):
    """{row: (ok, detail)} for every row but B0."""
    results = {}
    b = answer["clips"]["B"]
    gain = f"clip {b} gains a 0.67 s cross dissolve"

    def lines(row):
        got = answer.get(row) or {}
        return got.get("lines"), got.get("error")

    def verdict(row, test, want):
        got, error = lines(row)
        if got is None:
            results[row] = (False, f"no readout: {error}")
        else:
            results[row] = (test(got), f"{json.dumps(got, ensure_ascii=False)}; want {want}")

    verdict("P0", lambda got: got == [SUMMARY_X1], json.dumps([SUMMARY_X1], ensure_ascii=False))
    verdict("P1", lambda got: len(got) == 2 and got[1] == gain, f"line 2 {gain!r}")
    verdict("P2", lambda got: len(got) == 1, "one line")
    verdict("P3", lambda got: len(got) == 2 and got[0].startswith("2 clips · ") and got[1] == gain,
            f"'2 clips · …', then {gain!r}")

    def lengths_differ(got):
        if len(got) != 1 or " · " not in got[0] or " → " not in got[0]:
            return False
        before, after = got[0].split(" · ", 1)[1].split(" → ")
        return before != after
    verdict("P4", lengths_differ, "one line whose two lengths differ")
    wipe = f"clip {answer['P5clips']['B']} gains a 0.67 s wipe"
    verdict("P5", lambda got: len(got) == 2 and got[1] == wipe, f"line 2 {wipe!r}")
    hint = (answer.get("H1") or {}).get("hint")
    results["H1"] = (hint == HINT, f"{hint!r}" + ("" if hint == HINT else f"; want {HINT!r}"))
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    named = MUTANTS[args.mutant][0] if args.mutant else []
    here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = args.sources.resolve()
    if args.mutant:
        why = mutate(sources, args.mutant, here / "Sources")
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        sources = here / "Sources"

    results = {}
    binary, why = build(sources, here)
    results["B0"] = (binary is not None, why or f"built from {sources}")
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    not_scored = []
    if binary is None:
        for row in ROWS[1:]:
            results[row] = (False, "not run: the probe did not build")
    else:
        answer, why = None, None
        try:
            ran = run([str(binary)], RUN_WALL)
            (here / "stderr.txt").write_text(ran.stderr)
            answer = json.loads(ran.stdout)
            if not isinstance(answer, dict):
                why, answer = "the answer lacks " + ", ".join(answer_gaps(answer)), None
            elif "error" in answer:
                why, answer = f"the probe stopped: {answer['error']}", None
            if answer is not None and (gaps := answer_gaps(answer)):
                why, answer = "the answer lacks " + ", ".join(gaps), None
        except subprocess.TimeoutExpired:
            why = f"no answer within {RUN_WALL} s"
        except ValueError:
            why = f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}"
        if answer is None:
            not_scored = ROWS[1:]
            for row in ROWS[1:]:
                results[row] = (False, f"no row: {why}")
        else:
            results.update(judge(answer))

    for row in ROWS:
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in ROWS if results[row][0])
    print(f"scores: {passed}/{len(ROWS)}")
    if not args.mutant:
        return 0 if passed == len(ROWS) else 1
    lost = [row for row in named if row in not_scored]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) not scored: {', '.join(lost)}")
        return 2
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
