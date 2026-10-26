#!/usr/bin/env python3
"""#341 (spec §11 SR-27): a speed or ramp edit of a clip with sound re-times
the caption clips over it in the same undo step, at every door — measured
through the app's own sources.

    python3 tools/proof/caption_retime_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`caption_retime_probe.swift` is built with `swift_build.py`'s line over
`--sources` and run once, in a process of its own, under
`tools/proof/work/caption-retime/<tree|mutant-NAME>/`, killed at a 240 s wall.
Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

The fixture (fresh per row): an untitled 30 fps document with one 60 s media
file with sound, its `EditorViewController` the content of a 1440×900 window
owned by the document's window controller; each row adds its own clips,
tracks and captions. Every expected place is a literal oracle (a constant
rate's halving or doubling, or a linear ramp's closed-form map) snapped by the
core's `ReelTime.snapToFrame`, never read from `CaptionRetime`.

Rows:
  B0  the probe builds.
  M1  `set_speed` ×2: three abutting subtitles, the first at the clip's start
      (it keeps its start, its end moves earlier), land at S + snap((t − S)/2).
  M2  ×0.5: the third caption is cut back to abut the next clip's caption, the
      fourth (its new start inside that caption) is removed.
  M3  linear Ramp Up ×2 over the whole clip: c′ = D(√(1 + 2c/D) − 1), snapped.
  M4  linear Ramp Down ×0.5: two past-out subtitles removed; a straddling word
      page cut to its two kept words and "alpha bravo".
  M6  `set_speed` ×12: a 5-frame word page whose snapped ends coincide is
      removed and listed; its neighbours are re-timed.
  M7  `set_speed` ×2: a page whose start snaps later (10000 → 20000) writes
      its first word at 0, not −10000 (which the core would snap to −20000);
      a page whose first word was already said (W-3, negative) keeps it
      negative.
  M8  `set_speed` ×0.5 with a `move_clip` of a later caption in the same
      edit: a re-timed caption is cut back at that caption's place AFTER the
      edit.
  M5  CONTROLS, each left untouched with an empty plan: a straddling caption,
      a "Titles" track, a Captions track holding a shape, a locked Captions
      track, a detached picture clip's `set_speed`, a zoom action's
      `set_action`.
  D1  the Speed sheet at ×0.5: one step "Set Speed and Re-time Captions"; one
      undo restores every caption.
  D2  the inspector's commit of `set_action_end {speed}`.
  D3  the timeline's live rate stretch: unchanged during the drag, re-timed at
      its end, "Rate Stretch and Re-time Captions".
  D4  the Clip tab lane's band drag (the inspector's live closures).
  D5  ⌫ Remove Action on a Ramp Up: re-timed, the past-out one removed.
  D6  a ×20 Speed sheet asks; Cancel leaves the captions and makes no step.
  D7  a ×20 Speed sheet asks; a caption moved while the question is up; Set
      Speed re-plans on the moved document: re-timed from its new place.
  D8  D7 through the timeline's live rate stretch to ×20.
  A1  MCP `set_speed` ×2: `captions_retimed`, no `captions_removed`.
  A2  MCP `add_speed_ramp` Ramp Down: `captions_removed` and `captions_retimed`.
  A3  MCP zoom `set_action`: neither key.

Mutants (`--mutant`):
  overlap-not-inside  a caption belongs to a clip it merely overlaps → M5
  no-cutback          no cut-back → M2
  keep-past-out       a past-out subtitle stays where it was → M4
  no-word-cut         a page keeps every word → M4
  speaks-any          a clip with its audio off speaks → M5
  locked-too          a locked Captions track qualifies → M5
  ascending-later     later moves run ascending → M2, D1
  stub-movers-only    only captions whose start moves are stubbed → M1, M3
  keep-zero-length    a caption whose snapped end equals its start is kept → M6
  agent-unwired       the agent's plan is always empty → A1, A2
  no-word-clamp       a word time is never clamped at 0 → M7
  clamp-all           every word time, an already-said one too, is clamped → M7
  fixed-from-before   cut back at a fixed caption's place BEFORE the edit → M8
  stale-sheet-plan    the Speed sheet's Set Speed applies the stale plan → D7
  stale-live-plan     the live gesture's Set Speed applies the stale plan → D8

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

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/caption-retime"
ROWS = ["B0", "M1", "M2", "M3", "M4", "M6", "M7", "M8", "M5", "D1", "D2", "D3", "D4", "D5",
        "D6", "D7", "D8", "A1", "A2", "A3"]
WALL = 240
F = "CaptionRetime.swift"

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "overlap-not-inside": (["M5"], [
        (F, "owner.start <= caption.start && end <= owner.start + owner.duration",
         "owner.start < end && caption.start < owner.start + owner.duration")]),
    "no-cutback": (["M2"], [
        (F, "let kept = cutBack(placed, on: before, after: now, frame: frame)",
         "let kept = placed")]),
    "keep-past-out": (["M4"], [
        (F, "guard source(end) > low, source(caption.start) < high else { return nil }",
         "guard source(end) > low, source(caption.start) < high else {\n"
         "                return Placement(start: caption.start, end: end, words: nil, "
         "content: nil)\n            }")]),
    "no-word-cut": (["M4"], [
        (F, "words.prefix { source(caption.start + $0.start) < high }.count", "words.count")]),
    "speaks-any": (["M5"], [
        (F, "== true && clip.enabled.audio", "== true || clip.enabled.audio")]),
    "locked-too": (["M5"], [
        (F, "guard !track.locked, CaptionLayout", "guard CaptionLayout")]),
    "ascending-later": (["M2", "D1"], [
        (F, ".sorted { $0.from > $1.from }", ".sorted { $0.from < $1.from }")]),
    "stub-movers-only": (["M1", "M3"], [
        (F, "$0.place.start != $0.from || $0.place.end != $0.to", "$0.place.start != $0.from")]),
    "keep-zero-length": (["M6"], [
        (F, "guard finish > start else { return nil }", "guard finish >= start else { return nil }")]),
    "agent-unwired": (["A1", "A2"], [
        ("AgentServer+CaptionRetime.swift",
         "return CaptionRetime.plan(ops, on: container ?? document.project)",
         "_ = container\n        return .none")]),
    "no-word-clamp": (["M7"], [(F, "t >= 0 ? max(r, 0) : r", "r")]),
    "clamp-all": (["M7"], [(F, "t >= 0 ? max(r, 0) : r", "max(r, 0)")]),
    "fixed-from-before": (["M8"], [
        (F, "let fixed = now.clips.filter", "let fixed = before.clips.filter")]),
    "stale-sheet-plan": (["D7"], [
        ("SpeedAudioDrop.swift", "document.project === handle", "true")]),
    "stale-live-plan": (["D8"], [
        ("EditorViewController+SpeedAudio.swift", "document.project === base", "true")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/caption_retime_probe.swift", entry)
    binary = here / "caption-retime-probe"
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
