#!/usr/bin/env python3
"""Issue batch B62 (#212): a speed change that takes a clip with sound from
at or below the core's audio ceiling (`ReelSpeed.limits.audioMax`) to above
it asks first, at every UI door that can set a speed, and an agent's answer
names the clips instead — measured through the app's own sources.

    python3 tools/proof/speed_audio_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`speed_audio_probe.swift` is built with `sheet_queue_probe.py`'s swiftc line
over `--sources` and run once, in a process of its own, under
`tools/proof/work/speed-audio/<tree|mutant-NAME>/`, killed at a 240 s wall.
Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

The fixture (fresh per row): an untitled document whose one track holds A
("Alpha", 60 s, sound), B ("Bravo", 90 s, sound), N (no sound), M (audio
turned off) and H (already ×20), its `EditorViewController` the content of a
1440×900 window owned by the document's window controller. Every expected
sentence is built from the batch's literal templates, never from
`SpeedAudioDrop`; a question is answered with `endSheet(_:returnCode:)`.

Rows:
  B0   the probe builds.
  C0   CONTROL: no sheet attached, `windowForSheet` is the window, and the
       core's `audio_max` is reported.
  S1   Speed sheet on [A] at ×20, Apply: the one-clip question is attached to
       the Speed sheet's window; Set Speed gives A ×20, closes the sheet, and
       leaves one step named "Set Speed".
  S2   S1 answered Cancel: the same handle, no step, the Speed sheet still up.
  S3   Speed sheet on [A, B, N] at ×20: "2 clips will be silent at ×20.";
       Set Speed applies all three and one undo puts all three back to ×1.
  S5   CONTROL: an unchanged Apply closes the sheet, asks nothing, no step.
  S4   CONTROL: [A] at exactly the ceiling, [N] ×20, [M] ×20, [H] ×30 each
       apply with no question within 1 s.
  I1   `inspector.onEdit("Set Speed", [set_speed A ×20])`: the question on the
       editor window; Set Speed makes one step.
  I2   I1 answered Cancel: no change and no step.
  I3   Fit to (`VideoPane.fitOps([A], 3 s)`): the question names A's new rate
       as the core's trial answers it; Set Speed applies.
  I5   Fit to over [A, B] (two lengths, two new rates): "2 clips will be
       silent at their new speeds."; Set Speed applies both.
  I4   CONTROL: a `set_audio` volume edit never asks.
  R1   the timeline's live closures with a rate stretch of A above the
       ceiling: while the question is up nothing is live and the document
       holds the base handle; Set Speed gives one step named "Rate Stretch".
  R2   R1 answered Cancel: the base handle, not live, no step.
  R3   CONTROL: a `trim_end` live end never asks, and commits.
  A1   MCP `set_speed` A ×20: `audio_left_out` [A] and the exact
       `audio_note`, no sheet.
  A2   MCP `set_speed` N ×20: neither key.
  A3   MCP `rate_stretch` B above the ceiling: both keys.

Mutants (`--mutant`):
  no-ask          the crossing test's `clip.speed > limits.audioMax` is
                  `false`.
  cancel-applies  `ask` answers true for any return code.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed, an instrument failure included; a build failure is B0's FAIL there.
A `--mutant` run exits 1 when every row the mutant names failed (caught), 0
when one passed (survived), and 2 when the control could not be performed:
the copy's `before` text not found exactly once, the copy did not build, a
named row was not scored, or any scored row is an instrument failure.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/speed-audio"
ROWS = ["B0", "C0", "S1", "S2", "S3", "S5", "S4", "I1", "I2", "I3", "I5", "I4", "R1", "R2",
        "R3", "A1", "A2", "A3"]
WALL = 240

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "no-ask": (["S1", "S2", "S3", "I1", "I2", "I3", "I5", "R1", "R2", "A1", "A3"], [
        ("SpeedAudioDrop.swift", "clip.speed > limits.audioMax", "false")]),
    "cancel-applies": (["S2", "I2", "R2"], [
        ("SpeedAudioDrop.swift", "response == .alertFirstButtonReturn", "true")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `sheet_queue_probe.py`'s swiftc line."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/speed_audio_probe.swift", entry)
    binary = here / "speed-audio-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).stdout.strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = run(["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
                  "-module-name", "Reelcut", "-import-objc-header",
                  str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
                  "-L", str(lib.parent), "-lreelcut_core", *swift, str(entry),
                  "-o", str(binary)])
    if result.returncode:
        lines = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(lines[:8] or [result.stderr[-600:]])
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


def probe(binary, here):
    """The rows the probe answered, or None and why."""
    request = here / "request.json"
    request.write_text(json.dumps({"work": str(here / "rows")}))
    try:
        result = run([str(binary), str(request)], timeout=WALL)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def score(results, row, good, detail, *, instrument=False):
    """Keeps a row's verdict with whether its own comparison ran (rule R)."""
    results[row] = (bool(good) and not instrument, detail, instrument)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
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
    sources = args.sources.resolve()
    if args.mutant:
        why = mutate(sources, args.mutant, here / "Sources")
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        sources = here / "Sources"

    results = {}
    binary, why = build(sources, here)
    score(results, "B0", binary is not None, why or f"built from {sources}",
          instrument=binary is None)
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    not_scored = []
    rest = [row for row in wanted if row != "B0"]
    if rest:
        if binary is None:
            for row in rest:
                score(results, row, False, "not run: the probe did not build", instrument=True)
        else:
            rows, why = probe(binary, here)
            for row in rest:
                answer = next((a for a in rows or [] if a.get("id") == row), None)
                if answer is None:
                    not_scored.append(row)
                    score(results, row, False,
                          f"no row: {why or 'the probe did not answer it'}", instrument=True)
                else:
                    score(results, row, answer["pass"], answer["detail"],
                          instrument=bool(answer.get("instrument")))

    for row in wanted:
        good, detail, _ = results[row]
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
    broken = [row for row in wanted if results[row][2]]
    if broken:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"instrument failure in {', '.join(broken)}")
        return 2
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
