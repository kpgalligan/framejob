#!/usr/bin/env python3
"""Issue batch B14 (#115, #169): the media cache passes' ledger, the save
gate and the peaks retry, measured through the app's own sources; issue
batch B29 (#178.6) added W1.

    python3 tools/proof/cache_pass_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`cache_pass_probe.swift` is built with `swift_build.py`'s line over
`--sources` and run once per scenario, each in a process of its own, over
copies of `tools/proof/media/` under `tools/proof/work/cache-pass/`. Prints
`<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  B0   the probe builds.
  G0   CONTROL, #169 reproduced: a save that lists the package before a
       waveform pass and swaps after it published loses the waveform.
  G1   the same save announced to the ledger: nothing lands in the old
       package, and a valid waveform lands in the swapped-in one.
  G2   an announced save holds the strip's marker; a frame lost in it leaves
       no marker. G2c: the same run without the loss ends with the marker.
  G3   a real ProjectDocument's save waits for a publication being written,
       and its completion ends the save.
  S1a  a pass held inside its strip does not hold a relink's pass.
  S1b  once released, the superseded pass writes nothing.
  S2   a same-URL pass with another Camera Log input supersedes a held pass
       (bounded wait; the held pass writes nothing more once released); a
       third, with the same input again, does not (CONTROL; spec §11 GR-21).
  R1   a waveform pass that failed is retried in the session and lands.
  R2   a pass whose retries all fail ends (no retry loop).
  R3   a pass for another file cancels a pass waiting to retry.
  W1   a bounded wait (`awaitPass`) for a previous pass that ends in 0.3 s
       returns within 5 s and its sleeper ends within 2 s of the return,
       not after `CacheLedger.waitLimit` (#178.6).

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed; a build failure is B0's FAIL there. A `--mutant` run exits 1 when
every row the mutant names failed (caught), 0 when one passed (survived),
and 2 when the control could not be performed: the copy's `before` text not
found exactly once, the copy did not build, or a named row was not scored.
A missing medium exits 2 in either.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/cache-pass"
MEDIA = ROOT / "tools/proof/media"
NEEDED = ("toneA.m4a", "A.mov", "AV.mov")
ROWS = ["B0", "G0", "G1", "G2", "G2c", "G3", "S1a", "S1b", "S2", "R1", "R2", "R3", "W1"]
SCENARIO = {"G0": "G0", "G1": "G1", "G2": "G2", "G2c": "G2c", "G3": "G3",
            "S1a": "S1", "S1b": "S1", "S2": "S2", "R1": "R1", "R2": "R2", "R3": "R3",
            "W1": "W1"}
SCENARIO_WALL = 300

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "unbounded-wait": (["S1a"], [
        ("MediaImporter.swift", "await awaitPass(previous, bounded: bounded)",
         "await awaitPass(previous, bounded: false)")]),
    "frame-check-ignored": (["S1b"], [
        ("MediaImporter.swift", "guard pass?.isCurrent() ?? true else { break frames }",
         "_ = pass?.isCurrent()")]),
    "peaks-entry-ignored": (["S1b"], [
        ("MediaImporter.swift", "guard pass?.isCurrent() ?? true else { return false }",
         "_ = pass?.isCurrent()")]),
    "publish-ignores-saves": (["G1", "G2"], [
        ("MediaCacheLedger.swift", "while let expiry = saveExpiryLocked(directory) {",
         "while let expiry = saveExpiryLocked(directory), false {")]),
    "save-unannounced": (["G3"], [
        ("ProjectDocument+CacheSaves.swift",
         "let save = MediaImporter.CacheLedger.shared.saveBegan(cacheDir: directory)",
         "let save = 0"),
        ("ProjectDocument+CacheSaves.swift",
         "MediaImporter.CacheLedger.shared.saveEnded(cacheDir: directory, save: save)",
         "_ = save")]),
    "no-retry": (["R1"], [
        ("MediaImporter.swift", "await retryPeaks(for: media, url: url, into: cacheDir, pass: pass)",
         "_ = 0")]),
    "unbounded-retry": (["R2"], [
        ("MediaImporter.swift", "for delay in peaksRetryDelays {",
         "for delay in repeatElement(peaksRetryDelays[0], count: Int.max) {")]),
    "no-cancel": (["R3"], [
        ("MediaCacheLedger.swift", "previous.cancel()", "_ = previous")]),
    "no-cancel-sleeper": (["W1"], [
        ("MediaImporter.swift", "sleeper?.cancel()", "_ = sleeper")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/cache_pass_probe.swift", entry)
    binary = here / "cache-pass-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; None and why when a
    `before` text is not found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def scenario(binary, here, media, name):
    """The rows one scenario process answered, or None and why."""
    request = here / f"request-{name}.json"
    request.write_text(json.dumps({"media": str(media), "work": str(here / "rows")}))
    try:
        result = run([str(binary), str(request), name], timeout=SCENARIO_WALL)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {SCENARIO_WALL} s"
    (here / f"stderr-{name}.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    missing = [name for name in NEEDED if not (MEDIA / name).exists()]
    if missing:
        print("instrument failure: missing medium " + ", ".join(missing))
        return 2
    named = MUTANTS[args.mutant][0] if args.mutant else []
    wanted = args.only.split(",") if args.only else (["B0"] + named if args.mutant else ROWS)
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    media = here / "media"
    media.mkdir()
    for name in NEEDED:
        shutil.copy2(MEDIA / name, media / name)
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
    for name in dict.fromkeys(SCENARIO[row] for row in wanted if row != "B0"):
        if binary is None:
            for row in (r for r in wanted if SCENARIO.get(r) == name):
                results[row] = (False, "not run: the probe did not build")
            continue
        rows, why = scenario(binary, here, media, name)
        for row in (r for r in wanted if SCENARIO.get(r) == name):
            answer = next((a for a in rows or [] if a.get("id") == row), None)
            if answer is None:
                not_scored.append(row)
                results[row] = (False, f"no row: {why or 'the scenario did not answer it'}")
            else:
                results[row] = (bool(answer["pass"]), answer["detail"])

    for row in wanted:
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in wanted if results[row][0])
    print(f"scores: {passed}/{len(wanted)}")
    if not args.mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row in not_scored or row not in results]
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
