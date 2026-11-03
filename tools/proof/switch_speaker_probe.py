#!/usr/bin/env python3
"""Switch by Speaker's planner probe (road map "creator-jobs" SW2a, spec §11
SW-20…SW-27).

`switch_speaker_probe.swift` compiled with app/Sources through swift_build,
with `app/Resources/Models` copied beside the binary so the product's own
speech pass (Silero VAD) runs, and scored here:

  R1  SW-21 over synthetic microphones: each threshold one step either side of
      its edge (voice 0.5, P − bleed, F + margin, dominance), the nearest-rank
      percentile, and the centred window (an impulse at k moves ℓ at
      k − 4…k + 5 only; clipped at the series' start); `Settings()`'s defaults
      are SW-S4's chosen setting (bleed 15, dominance 8, margin 6).
  R2  SW-22 over synthetic labels: the bridge, min_turn, crosstalk to the wide
      and held, the lead and its snap, a short shot merged into the one before
      (and the first into the one after), opening on the wide, wide_after, the
      hand-off of an uncovered stretch to the wide, and SW-22 (a)'s crosstalk
      bridge (a stretch under 0.5 s between two crosstalk runs joins them,
      whether one run or two; 0.5 s, or 0.6 s over two runs, does not). R1 and
      R2 run at the drafted thresholds (bleed 15, dominance 8, margin 6).
  R3  SW-24: every sentence as one list in order; one angle; the ceiling's N
      and M with 4096 read from RC_MAX_CLIPS.
  R4  SW-20's defaults over snapshots: files are the microphones; with none,
      each camera its own; the wide; two detached cameras give two angles and
      no microphone; a detached camera sound is never a default.
  R5  covering: a two-file angle covers its join; a gap in every angle is
      refused naming it; a short shot its neighbour cannot cover stays; the
      first shot's uncovered start goes to the front-most covering angle.
  R6  F-TURNS (`creator_spike/f_turns.py`, run first): each of six variants
      opened as a ProjectDocument, its caches written by the importer, `read`
      then `plan` at the defaults: the shot angles equal the manifest's and
      every cut is on the frame grid within τ = 147.3 ms of onset − lead,
      except SW-S4's named limit (the owner, 2026-11-03): b24_f45's shot 17
      (b) may be late by at most 99,313 ticks (165.5 ms), and is listed in the
      row's note as limited. Skipped by name when `say -v Samantha` or `say -v Daniel` is missing.

A probe that will not build is a scored failure.

    python3 tools/proof/switch_speaker_probe.py [--only R1,R2]
    python3 tools/proof/switch_speaker_probe.py --mutant NAME   # CAUGHT 1, SURVIVED 0, 2 not run

Seven mutants: bleed-removed (R1), dominance-removed (R1), trailing-window
(R1 alone: R6's τ budgets the half-window's 50 ms by design), merge-into-next
(R2), camera-sound-beside-files (R4), crosstalk-bridge-removed (R2, R6) and
crosstalk-bridge-single-run (R2).

Output under tools/proof/work/switch_speaker/.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/switch_speaker"
FTURNS = ROOT / "tools/proof/media/creator/f_turns"
ROWS = ["R1", "R2", "R3", "R4", "R5", "R6"]

# name: (rows that must FAIL, file, anchor, replacement)
MUTANTS = {
    "bleed-removed": (["R1"], "SpeakerSwitch+Shots.swift",
                      "guard level >= gauge.p - settings.bleedDB,", "guard !level.isNaN,"),
    "dominance-removed": (["R1"], "SpeakerSwitch+Shots.swift",
                          "                active = [top]\n", "                _ = top\n"),
    "trailing-window": (["R1"], "ClipLevelSeries.swift",
                        "static let before = 5, after = 4", "static let before = 9, after = 0"),
    "merge-into-next": (["R2"], "SpeakerSwitch+Shots.swift",
                        "let intoBefore = i > 0 && covers(",
                        "let intoBefore = i > 0 && i + 1 == out.count && covers("),
    "camera-sound-beside-files": (
        ["R4"], "SpeakerSwitch.swift",
        "let microphones = files.isEmpty\n"
        "            ? angles.filter { holds($0) { playsSound($0, in: snapshot) } } : files",
        "let microphones = files + angles.filter { holds($0) { playsSound($0, in: snapshot) } }"),
    "crosstalk-bridge-removed": (
        ["R2", "R6"], "SpeakerSwitch+Shots.swift",
        "            if run.label != .crosstalk, var last = out.last, last.label == .crosstalk,",
        "            if false, run.label != .crosstalk, var last = out.last, last.label == .crosstalk,"),
    "crosstalk-bridge-single-run": (
        ["R2"], "SpeakerSwitch+Shots.swift",
        "                Ticks(runs[next].start - run.start) * stepTicks < bridge",
        "                next == index + 1, Ticks(runs[next].start - run.start) * stepTicks < bridge"),
}


def fturns():
    """The F-TURNS folder, or None when it is skipped by name (no voice)."""
    run = subprocess.run([sys.executable, str(ROOT / "tools/proof/creator_spike/f_turns.py")],
                         capture_output=True, text=True, timeout=1800)
    print(run.stdout.strip())
    if run.returncode == 2:
        return None
    if run.returncode != 0:
        raise RuntimeError("f_turns.py failed: " + (run.stderr or run.stdout)[-800:])
    return FTURNS


def build(sources, name):
    """(binary, problem): the probe built from `sources` into WORK/name."""
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/switch_speaker_probe.swift", entry)
    binary = out / "switch-speaker-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary, optimize=True)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(getattr(error, "diagnostics", [str(error)])[:8])
    # `SileroVAD.bundledURL` falls back to `Models` beside a binary that is
    # not a bundle (audio_ap6_probe.py's copy).
    models = binary.parent / "Models"
    shutil.rmtree(models, ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Models", models)
    return binary, ""


def run_rows(sources, name, folder, only, quiet=False):
    """{row: True/False/'skip'} and the stderr tail; None when it did not build."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    result = subprocess.run(
        [str(binary), "rows", str(folder) if folder else "-", str(scratch), ",".join(only)],
        capture_output=True, text=True, timeout=3600)
    (WORK / name / "probe.log").write_text(result.stdout + result.stderr)
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) is True and parts[0] == "ok"
        elif len(parts) >= 2 and parts[0] == "skip":
            rows[parts[1]] = "skip"
    if not quiet:
        sys.stdout.write(result.stdout)
    if result.returncode != 0:
        for row in only or ROWS:
            rows.setdefault(row, False)
    return rows, result.stderr[-800:]


def score(rows, wanted):
    good = True
    for row in wanted:
        state = rows.get(row)
        if state == "skip":
            print(f"SKIPPED {row}: F-TURNS needs say's Samantha and Daniel")
        elif state is not True:
            print(f"FAIL {row}" + (" (did not run)" if state is None else ""))
            good = False
        else:
            print(f"PASS {row}")
    return good


def mutant(name):
    rows, file, anchor, replacement = MUTANTS[name]
    print(f"SW2a — the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    tree = WORK / f"mutant-{name}" / "Sources"
    shutil.rmtree(tree, ignore_errors=True)
    shutil.copytree(ROOT / "app/Sources", tree)
    path = tree / file
    text = path.read_text()
    if text.count(anchor) != 1:
        print(f"mutant {name}: the control could not be performed — the anchor occurs "
              f"{text.count(anchor)} times in {file}")
        return 2
    path.write_text(text.replace(anchor, replacement))
    folder = fturns() if "R6" in rows else None
    if "R6" in rows and folder is None:
        print(f"mutant {name}: the control could not be performed — F-TURNS skipped")
        return 2
    got, problem = run_rows(tree, f"mutant-{name}", folder, rows, quiet=True)
    if got is None:
        print(f"mutant {name}: the control could not be performed — did not build: {problem}")
        return 2
    failed = [row for row in rows if got.get(row) is False]
    for row in rows:
        print(f"  {row}: {'FAILED' if got.get(row) is False else got.get(row)}")
    caught = len(failed) == len(rows)
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
          f"{'failed' if caught else 'did not all fail'}")
    return 1 if caught else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mutant:
        return mutant(args.mutant)
    only = [row.strip() for row in args.only.split(",") if row.strip()]
    wanted = only or ROWS
    folder = None
    if "R6" in wanted:
        try:
            folder = fturns()
        except Exception as error:  # a fixture that will not build is a failure
            print(f"FAIL R6: {error}")
            return 1
    rows, problem = run_rows(ROOT / "app/Sources", "probe", folder, only)
    if rows is None:
        print(f"FAIL the probe builds: {problem}")
        return 1
    good = score(rows, wanted)
    passed = sum(1 for row in wanted if rows.get(row) is True)
    print(f"\n{passed}/{len(wanted)} rows passed")
    if problem.strip() and not good:
        print("stderr: " + problem)
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
