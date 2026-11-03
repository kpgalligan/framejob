#!/usr/bin/env python3
"""Road map creator-jobs CO8 — the camera's layout and cutout at record time, the ungranted rows
(spec §11 CO-80…CO-84), measured through the app's own sources. No app, no grant, no media file,
no prompt.

    python3 tools/proof/co8_probe.py [--sources DIR] [--mutant NAME] [--only IDS]

`co8_probe.swift` is built with `swift_build.py`'s line over `--sources` with
`FRAMEJOB_DEV_TOOLS` (it links `libframejob_core.a`, so `make rust` first) and run three times:
`main` (Q1–Q4, Q6, Q7), then `write` and `read` (Q5, two processes). Everything it writes lands
under `tools/proof/work/co8-probe/<tree|mutant-NAME>/`. Prints `<ID> pass|fail — <detail>` per
row, then `scores: N/M`.

Rows:
  B0  the probe builds.
  Q1  `RecorderPanelController.shared`, never shown: "Layout:" with Corner, Rounded Corner,
      Circle, Side by Side and Camera Full (each item's represented object its raw value), then
      "Remove the camera's background when it lands" under it with no label, directly after the
      camera's preview and directly before Microphone; each control's action `controlChanged:` on
      the panel.
  Q2  the two keys absent read corner_square and off; a stale layout reads corner_square; a
      change of either writes it; another control's change keeps them; stored values restore.
  Q3  a display row without Record the camera too: both greyed with their values kept and the
      choice corner_square, off; ticked: both live and the choice the controls'; Microphone Only
      and Camera grey both and give corner_square, off; a countdown greys both.
  Q4  CO-83's sentences, exact: `recordingSourceKind` (voice_over's one sentence with all four,
      screen without camera naming the first of camera_format, camera_layout, camera_cutout,
      camera's list with both before rate, a null not given); `recordingCameraLanding` (the
      defaults, the enum's vocabulary, the place sentences, layout first); `land_recording`'s
      `landRecordingCamera` (camera without movie, the three without camera, the place check
      before the probe).
  Q5  a write run changes the two keys through the panel and saves every value; a read run (a new
      process) restores side_by_side and on and puts every saved value back.
  Q6  two segments in side_by_side, the second with no camera file: segment 1's camera and screen
      each with one one-frame layout action at clip time 0, the screen laid out; segment 2's
      screen with no action and an `add_clip` twin's video.
  Q7  a +3 frame camera offset: the screen keeps its twin's video with ONE one-frame action at 3
      frames, the camera one at 0; a screen that ends before an overrunning previous camera's end:
      the next camera lands at CAM-10 (3)'s corner (x, y, scale) with no action, no throw.

Mutants (spec §11 CO-84): `gate-ignored` (Q3), `cutout-without-camera` (Q4),
`through-whole-recording` (Q6), `throw-on-unplayed-screen` (Q7), `no-through` (Q6).

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row failed; a build
failure is B0's FAIL there. A `--mutant` run exits 1 when every row the mutant names failed
(caught), 0 when one passed (survived), and 2 when the control could not be performed: the
copy's `before` text not found exactly once, the copy did not build, or a named row was not
scored.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/co8-probe"
ROWS = ["B0", "Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7"]
MAIN_ROWS = ["Q1", "Q2", "Q3", "Q4", "Q6", "Q7"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...]) — spec §11 CO-84.
MUTANTS = {
    "gate-ignored": (["Q3"], [
        ("RecorderPanelController+CameraLanding.swift",
         "        choice.cameraLayout = cameraBesideSelected ? cameraLanding.layout : .cornerSquare\n",
         "        choice.cameraLayout = cameraLanding.layout\n")]),
    "cutout-without-camera": (["Q4"], [
        ("AgentServer+RecordingCamera.swift",
         '        let landing = ["camera_layout", "camera_cutout"].filter {\n',
         '        let landing = ["camera_layout"].filter {\n')]),
    "through-whole-recording": (["Q6"], [
        ("RecordingLanding+Camera.swift",
         "            corner: choice.corner, at: at, duration: frame, through: max(shown.end, clip.end))\n",
         "            corner: choice.corner, at: at, duration: frame,\n"
         "            through: container.clips.map(\\.end).max() ?? clip.end)\n")]),
    "throw-on-unplayed-screen": (["Q7"], [
        ("RecordingLanding+Camera.swift",
         "        guard let screen, let shown = container.clips.first(where: { $0.id == screen }),\n"
         "            shown.start <= at, at < shown.end\n",
         "        guard let screen, let shown = container.clips.first(where: { $0.id == screen })\n")]),
    "no-through": (["Q6"], [
        ("RecordingLanding+Camera.swift",
         "            corner: choice.corner, at: at, duration: frame, through: max(shown.end, clip.end))\n",
         "            corner: choice.corner, at: at, duration: frame)\n")]),
}


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/co8_probe.swift", entry)
    binary = here / "co8-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary, defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + ("; ".join(error.diagnostics[:8]) or str(error))
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; None and why when a `before` text is not
    found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before.strip()}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here, mode):
    """The rows one run answered, or None and why."""
    try:
        result = subprocess.run([str(binary), str(here / "files"), mode], capture_output=True,
                                text=True, timeout=WALL)
    except subprocess.TimeoutExpired:
        return None, f"{mode}: no answer within {WALL} s"
    (here / f"stderr-{mode}.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"{mode}: no answer (exit {result.returncode}): {result.stderr[-300:]}"


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
    results["B0"] = (binary is not None, why or f"built from {sources}")
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not "
              f"build")
        return 2
    not_scored = []
    answered = []
    whys = []
    if binary and any(r in MAIN_ROWS for r in wanted):
        rows, why = probe(binary, here, "main")
        answered += rows or []
        whys += [why] if why else []
    if binary and "Q5" in wanted:
        # The read run always follows the write run: it is what puts the values back.
        written, why_w = probe(binary, here, "write")
        read, why_r = probe(binary, here, "read")
        whys += [w for w in (why_w, why_r) if w]
        parts = [r for r in (written or []) + (read or []) if r.get("id") in ("Q5w", "Q5r")]
        if len(parts) == 2:
            answered.append({"id": "Q5", "pass": all(p["pass"] for p in parts),
                             "detail": "; ".join(p["detail"] for p in parts)})
    for row in [r for r in wanted if r != "B0"]:
        answer = next((a for a in answered if a.get("id") == row), None)
        if answer is None:
            not_scored.append(row)
            reason = "; ".join(whys) or (why if binary is None else "the probe did not answer it")
            results[row] = (False, f"no row: {reason}")
        else:
            results[row] = (answer["pass"], answer["detail"])

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
