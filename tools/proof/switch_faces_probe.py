#!/usr/bin/env python3
"""Switch by Speaker's faces mode probe (road map "creator-jobs" SW8, spec §11
SW-81…SW-84, SW-87).

`switch_faces_probe.swift` compiled with app/Sources through swift_build and
scored here. Every row is pure: no document, no file, no app.

  P1  the largest face and the opening: the larger face second in CJ-31's
      order is the person; equal areas take the first; a NaN gap, a width of
      0, pts −1 and no face each give nil.
  P2  `activities`: the exact population std at half 2 (10 a second) and
      half 1 (5 a second), the edges clipped, fewer than two values nil.
  P3  `label`: no speech is nobody despite activity; top exactly 1.5× the
      next is the person, 1.49× crosstalk; top == the floor 0.02 crosstalk,
      just above the person; a single valid angle the person; all nil nobody;
      the constants.
  P4  SW-83's defaults (one microphone with two or three angles: the faces
      mode, no wide); `withoutWide`'s three cases, the named-wide pairing
      planning as before SW8; a mixed shared microphone still refused in
      SW-24's sentence; `plan` over synthetic series — the wide, each turn
      − lead snapped, crosstalk to the wide, a turn under min_turn starting
      nothing, the wide's own faces not contesting.
  P5  the pending and no-face refusals in order, no shared-microphone refusal
      in the faces mode, none for an unread angle.
  P6  `source(atClip:)` trimmed, at speed 2 and reversed, round-tripping
      through `clipTime(ofSource:)`; `faceSeries`' later-starting clip, its
      nearest sample, nil past the media's end and off every clip.

A probe that will not build is a scored failure.

    python3 tools/proof/switch_faces_probe.py [--only P1,P3]
    python3 tools/proof/switch_faces_probe.py --mutant NAME   # CAUGHT 1, SURVIVED 0, 2 not run

Four mutants: ratio-removed (P3), voice-gate-removed (P3), first-face (P1),
wide-in-contest (P4).

Output under tools/proof/work/switch_faces/.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/switch_faces"
ROWS = ["P1", "P2", "P3", "P4", "P5", "P6"]

# name: (rows that must FAIL, file, anchor, replacement)
MUTANTS = {
    "ratio-removed": (["P3"], "FaceActivity.swift",
                      "return top.value >= ratio * next && top.value > floor ? ",
                      "return top.value > floor ? "),
    "voice-gate-removed": (["P3"], "FaceActivity.swift",
                           "        guard speech else { return .nobody }\n",
                           "        _ = speech\n"),
    "first-face": (["P1"], "FaceActivity.swift",
                   "guard sample.pts >= 0, let face = largest(sample.faces) else { return nil }",
                   "guard sample.pts >= 0, let face = sample.faces.first else { return nil }"),
    "wide-in-contest": (["P4"], "SpeakerSwitch+Faces.swift",
                        "        let contest = speakers.compactMap(\\.angle)\n",
                        "        let contest = (speakers.compactMap(\\.angle)"
                        " + [input.pairing.wide].compactMap { $0 })\n"),
}


def build(sources, name):
    """(binary, problem): the probe built from `sources` into WORK/name."""
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/switch_faces_probe.swift", entry)
    binary = out / "switch-faces-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary, optimize=True)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(getattr(error, "diagnostics", [str(error)])[:8])
    return binary, ""


def run_rows(sources, name, only, quiet=False):
    """{row: True/False} and the stderr tail; None when it did not build."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem
    result = subprocess.run([str(binary), "rows", ",".join(only)],
                            capture_output=True, text=True, timeout=600)
    (WORK / name / "probe.log").write_text(result.stdout + result.stderr)
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) is True and parts[0] == "ok"
    if not quiet:
        sys.stdout.write(result.stdout)
    if result.returncode != 0:
        for row in only or ROWS:
            rows[row] = False
    return rows, result.stderr[-800:]


def mutant(name):
    rows, file, anchor, replacement = MUTANTS[name]
    print(f"SW8 — the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
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
    got, problem = run_rows(tree, f"mutant-{name}", rows, quiet=True)
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
    rows, problem = run_rows(ROOT / "app/Sources", "probe", only)
    if rows is None:
        print(f"FAIL the probe builds: {problem}")
        return 1
    good = True
    for row in wanted:
        state = rows.get(row)
        if state is not True:
            print(f"FAIL {row}" + (" (did not run)" if state is None else ""))
            good = False
        else:
            print(f"PASS {row}")
    passed = sum(1 for row in wanted if rows.get(row) is True)
    print(f"\n{passed}/{len(wanted)} rows passed")
    if problem.strip() and not good:
        print("stderr: " + problem)
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
