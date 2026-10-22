#!/usr/bin/env python3
"""Clean-up round 3, batch A (#327): the timeline height and the inspector
width are saved only from a divider drag (`PaneSplitView.isDraggingDivider`,
`EditorViewController.savePaneSize`), never from a window resize, the
editor's own restore or ⌥⌘I — measured through the app's own sources.

    python3 tools/proof/pane_size_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`pane_size_probe.swift` is built with `swift_build.py`'s line over
`--sources` as `main.swift` and run once, in a process of its own, under
`tools/proof/work/pane-size/`, killed at a 120 s wall. No media. Its
`UserDefaults.standard` is the executable's own domain, `pane_size_probe`,
never the owner's (spec §11 V-5, #238): the probe removes the two size keys
from it first, and this driver removes the domain
(`proof_defaults.remove_domain`) after the probe exits. Prints
`<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  B0   the probe builds.
  R0   after the editor's restore and its layout turns, neither
       `FrameJobTimelineHeight` nor `FrameJobInspectorWidth` is set.
  W1   the window's content resized to 1440×900, then 1100×700: neither key
       is set. RECORD: whether those resize notifications carried
       `NSSplitViewDividerIndex` (NSSplitView.h: since macOS 12 the key is
       posted "during resize and layout events as well", which is why the
       key's presence is not the test).
  H1   ⌥⌘I (`toggleInspector`) twice: neither size key is set.
  D1   a drag of the main split's divider 60 pt up (a leftMouseDown at the
       divider's centre handed to `mouseDown(with:)`, a leftMouseDragged and
       a leftMouseUp posted behind it): the timeline's height changed, the
       height key equals its new height ± 0.5 pt, the width key is absent,
       and `isDraggingDivider` is false after.
  D2   the same on the upper split's divider 40 pt left: the inspector's
       width changed, the width key equals it ± 0.5 pt, and the height key
       still holds D1's value. (After W1 the inspector sits below its 280 pt
       minimum, measured, and the drag's clamp lands it at 279, so the row
       asks for a change rather than exactly 40 pt.)
  O1   (driver) `proof_defaults.snapshot` of `com.kgalligan.FrameJob` and
       `com.kgalligan.FrameJob.debug` before and after the run: no key moved.

Mutants (`--mutant`, each on a copy of `--sources`):
  save-any-resize  the drag guard dropped: must fail W1. (R0 passes under it,
                   measured: the restore's resizes all land inside
                   `isAdjustingPanes` or before `didRestorePanes`, the
                   guard that was already there; H1 then fails only on
                   what W1 wrote, ⌥⌘I posting no resize notification in
                   this fixture, so neither is named.)
  flag-never-set   `mouseDown` leaves the flag false: must fail D1, D2.
  panes-swapped    main's drag saves the width: must fail D1.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row
failed; a build failure is B0's FAIL there. A `--mutant` run exits 1 when
every row the mutant names failed (caught), 0 when one passed (survived),
and 2 when the control could not be performed: the copy's `before` text not
found exactly once, the copy did not build, or a named row was not scored.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import proof_defaults
import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/pane-size"
DOMAIN = "pane_size_probe"
OWNER_DOMAINS = (proof_defaults.APP_DOMAIN, proof_defaults.APP_DOMAIN + ".debug")
PROBE_ROWS = ["R0", "W1", "H1", "D1", "D2"]
ROWS = ["B0"] + PROBE_ROWS + ["O1"]
WALL = 120
PANES = "EditorViewController+Panes.swift"

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "save-any-resize": (["W1"], [
        (PANES,
         "guard let split = notification.object as? PaneSplitView, split.isDraggingDivider\n",
         "guard let split = notification.object as? PaneSplitView\n")]),
    "flag-never-set": (["D1", "D2"], [
        (PANES, "        isDraggingDivider = true\n", "        isDraggingDivider = false\n")]),
    "panes-swapped": (["D1"], [
        (PANES, "        if split === main, timeline.bounds.height > 1 {\n",
         "        if split === upper, timeline.bounds.height > 1 {\n"),
        (PANES, "        } else if split === upper, !inspector.isHidden",
         "        } else if split === main, !inspector.isHidden")]),
}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`, the binary named
    for the defaults domain it writes."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/pane_size_probe.swift", entry)
    binary = here / DOMAIN
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
            return f"{file}: `{before.strip()}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """(the probe's answer, None), or (None, why). The probe's own domain is
    removed after it exits, whatever it answered."""
    try:
        result = run([str(binary)], timeout=WALL, cwd=here)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    finally:
        left = proof_defaults.remove_domain(DOMAIN)
        if left:
            print(f"defaults: {DOMAIN} not removed — {left}")
    (here / "stderr.txt").write_text(result.stderr)
    try:
        answer = json.loads(result.stdout)
        answer["rows"]
        return answer, None
    except (ValueError, KeyError, TypeError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


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
    before = {domain: proof_defaults.snapshot(domain) for domain in OWNER_DOMAINS}
    binary, why = build(sources, here)
    results["B0"] = (binary is not None, why or f"built from {sources}")
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    not_scored = []
    rest = [row for row in wanted if row in PROBE_ROWS]
    if rest:
        if binary is None:
            for row in rest:
                results[row] = (False, "not run: the probe did not build")
        else:
            answer, why = probe(binary, here)
            rows = (answer or {}).get("rows") or []
            for row in rest:
                found = next((a for a in rows if a.get("id") == row), None)
                if found is None:
                    not_scored.append(row)
                    results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
                else:
                    results[row] = (bool(found["pass"]), found["detail"])
    if "O1" in wanted:
        after = {domain: proof_defaults.snapshot(domain) for domain in OWNER_DOMAINS}
        unread = [d for d in OWNER_DOMAINS if before[d] is None or after[d] is None]
        moved = {d: proof_defaults.moved(before[d], after[d]) for d in OWNER_DOMAINS}
        results["O1"] = (
            not unread and not any(moved.values()),
            f"unreadable: {', '.join(unread)}" if unread else "; ".join(
                f"{d}: {len(before[d])} keys, moved {moved[d] or 'none'}" for d in OWNER_DOMAINS))

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
