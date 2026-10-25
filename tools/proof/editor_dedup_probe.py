#!/usr/bin/env python3
"""#364, the editor-side de-duplication: the three modal canvas modes on one
overlay base (`CanvasModeOverlay`) and one teardown (`dismissCanvasMode`),
Nest, Un-nest and Paste selecting what they added through
`selectClips(addedSince:in:)`, and the export rows' LPCM question asked through
one predicate — measured before and after, through the app's own sources.

    python3 tools/proof/editor_dedup_probe.py [--sources DIR] [--mutant NAME] [--only IDS] capture|compare DIR

`editor_dedup_probe.swift` is built with `swift_build.py`'s line over
`--sources` (default `app/Sources`, less `main.swift`) and run once, in a
process of its own, under `tools/proof/work/editor-dedup/`, killed at a 120 s
wall. Its fixture is `e2_chrome.py`'s `project()`/`clip()` JSON, copied: two
4 s shape clips on track 1. No media, no general pasteboard, no menu item
that persists a setting, no instance, no MCP.

`capture DIR` runs it on the tree as it stands (the BASELINE, before the
change) and stores the probe's PNGs and `answer.json` in DIR. `compare DIR`
runs it again and scores every row against DIR: a row passes when its own
absolute check passes AND its record (V1: each PNG) is byte-equal to the
capture's. Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  B0   the probe builds. A failed build is a scored FAIL.
  V1   `cacheDisplay` PNGs, appearance aqua, of `CanvasEyedropperView`,
       `QualifierPickView`, `CanvasRegionView(.zoom, note: duringNote)` and
       `CanvasRegionView(.obscure)`, each at 640×360 (the pill drawn) and at
       160×90 (where it does not fit).
  E1   Esc (keyCode 53) on each constructed view runs `onCancel` once; on the
       region, after a press with `canvasPoint` set, `session` is already nil
       when `onCancel` runs.
  C1   one shape clip selected: `pickChromaKey(nil)` arms, the overlay holds
       first responder; `onPick` at window (−5000, −5000) leaves it armed and
       the project unchanged; a second press disarms — no superview, `onPick`
       and `onCancel` nil, focus on `previewCanvas.overlay`.
  C2   with the eyedropper armed, `armCanvasMode(QualifierPickView(...))`
       leaves one `CanvasModalMode` and the eyedropper's callbacks nil;
       `endQualifierPick()` leaves none and focus on the canvas overlay.
  C3   `insertAdjustmentClip(nil)` with nothing selected selects the new
       clip; `pickQualifier(nil)` then gets C1's arm, miss and disarm checks.
  N1   both clips selected: `nestSelection()` selects the one new clip, a
       nest; `nestSelection()` on the lone nest keeps the selection;
       `unnestSelection()` selects the two new clips.
  X1   `Applies(preset)`'s two bitrate answers for nil and every preset,
       `ExportWriter.audioSettings` for every preset's settings and for eight
       decoded `{codec, container}` settings, as sorted `key=value` lines;
       absolutely, LPCM exactly where the codec is `lpcm` or starts `prores`.

Mutants (`--mutant`, with `compare`), each an edit to a COPY of the sources:
  esc-keeps-session        the region's Esc keeps its session: must fail E1.
  dismiss-keeps-callbacks  `dismissCanvasMode` does not detach: must fail C1, C2.
  pcm-prefix-dropped       the predicate forgets ProRes: must fail X1.
  nest-unselected          Nest does not select what it added: must fail N1.

Exit (rule R, `paste_graphic_probe.py`'s): a plain run exits 0 iff every row
passed and 1 when a row failed. A `--mutant` run exits 1 when every row the
mutant names failed (caught), 0 when one passed (survived), and 2 when the
control could not be performed: a `before` text not found exactly once, the
copy did not build, or a named row was not scored.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/editor-dedup"
ROWS = ["B0", "V1", "E1", "C1", "C2", "C3", "N1", "X1"]
WALL = 120
TICKS = 600_000
CLIP_SECONDS = 4
BLACK = [0.0, 0.0, 0.0, 1.0]
GREY = [0.6, 0.6, 0.6, 1.0]

EYEDROPPER = "EditorViewController+Eyedropper.swift"
ZOOM_REGION = "EditorViewController+ZoomRegion.swift"
EXPORT_VALUES = "ExportValues.swift"
NEST = "EditorViewController+Nest.swift"

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "esc-keeps-session": (["E1"], [
        (ZOOM_REGION, "if event.keyCode == 53 { session = nil }", "if event.keyCode == 53 {}")]),
    "dismiss-keeps-callbacks": (["C1", "C2"], [
        (EYEDROPPER, "        mode.detachCallbacks()\n", "")]),
    "pcm-prefix-dropped": (["X1"], [
        (EXPORT_VALUES, '|| c.hasPrefix("prores")', "|| false")]),
    "nest-unselected": (["N1"], [
        (NEST,
         'document.applyEdit("Nest", .nest(clips: clips))\n'
         "        selectClips(addedSince: before, in: document)\n",
         'document.applyEdit("Nest", .nest(clips: clips))\n')]),
}


# ---------------------------------------------------------------------------
# The fixture: `e2_chrome.py`'s `project()` and `clip()`, copied.


def video_props():
    return {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [], "blend": "normal", "motion": None,
    }


def shape_props(fill):
    return {
        "kind": "rectangle", "width": 640.0, "height": 360.0, "stroke": None,
        "fill": fill, "arrow_start": False, "arrow_end": False, "radius": 0.0,
        "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None,
    }


def clip(cid, start, fill, duration=CLIP_SECONDS * TICKS):
    return {
        "id": cid, "track": 1, "start": start, "duration": duration,
        "source": {"kind": "shape"},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": video_props(), "audio": None, "text": None,
        "shape": shape_props(fill), "actions": [], "transition_in": None,
        "name": None, "label": None,
    }


def project(clips):
    return {
        "version": 8,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1], "background": BLACK,
            "fit_new_clips": True, "timecode_frames": True,
        },
        "media": [],
        "tracks": [{"id": 1, "name": "Track 1", "hidden": False, "muted": False,
                    "locked": False, "solo": False}],
        "clips": clips,
        "markers": [],
        "next_id": max([c["id"] for c in clips] + [1]) + 1,
        "nests": [],
    }


def write_package(here):
    path = here / "dedup.framejob"
    path.mkdir(parents=True, exist_ok=True)
    body = project([clip(2, 0, GREY), clip(3, CLIP_SECONDS * TICKS, GREY)])
    (path / "project.json").write_text(json.dumps(body, indent=2) + "\n")
    return path


# ---------------------------------------------------------------------------


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/editor_dedup_probe.swift", entry)
    binary = here / "editor-dedup-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    lib = ROOT / "core/target/release/libframejob_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `make rust` first"
    try:
        swift_build.build(sources=swift + [entry], output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        if error.expired:
            return None, "swiftc: no answer within 900 s"
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; None, or why when a
    `before` text is not found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before.strip()}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here, package, pngs):
    """(the probe's answer, None), or (None, why)."""
    try:
        result = subprocess.run([str(binary), str(package), str(pngs)], capture_output=True,
                                text=True, timeout=WALL, cwd=here)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        answer = json.loads(result.stdout)
        answer["rows"]
        return answer, None
    except (ValueError, KeyError, TypeError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def against(found, kept, pngs, stored):
    """`compare`'s half of a row: its record (V1: its PNGs) byte-equal to the
    capture's. (ok, why)."""
    if kept is None:
        return False, "the capture has no such row"
    if found["id"] == "V1":
        names = [n for n in found["record"].split("\n") if n]
        if names != [n for n in kept["record"].split("\n") if n]:
            return False, "a different set of PNGs from the capture's"
        differ = [n for n in names
                  if not (stored / n).exists() or (pngs / n).read_bytes() != (stored / n).read_bytes()]
        if differ:
            return False, "PNGs differ from the capture: " + ", ".join(differ)
        return True, f"{len(names)} PNGs byte-equal to the capture"
    if found["record"] != kept["record"]:
        new = found["record"].split("\n")
        old = kept["record"].split("\n")
        first = next((i for i in range(max(len(new), len(old)))
                      if (new[i] if i < len(new) else None) != (old[i] if i < len(old) else None)),
                     0)
        return False, (f"record differs from the capture at line {first + 1}: "
                       f"now `{new[first] if first < len(new) else '∅'}`, "
                       f"captured `{old[first] if first < len(old) else '∅'}`")
    return True, "record byte-equal to the capture"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    parser.add_argument("mode", choices=["capture", "compare"])
    parser.add_argument("dir", type=Path)
    args = parser.parse_args()
    if args.mutant and args.mode != "compare":
        print("a mutant runs under `compare`")
        return 2
    named = MUTANTS[args.mutant][0] if args.mutant else []
    wanted = args.only.split(",") if args.only else (["B0"] + named if args.mutant else ROWS)
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    stored = args.dir.resolve()
    kept_rows = {}
    if args.mode == "compare":
        try:
            kept_rows = {r["id"]: r for r in
                         json.loads((stored / "answer.json").read_text())["rows"]}
        except (OSError, ValueError, KeyError, TypeError) as error:
            print(f"no capture in {stored}: {error}")
            return 2
    here = WORK / (f"mutant-{args.mutant}" if args.mutant else args.mode)
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    pngs = here / "out"
    pngs.mkdir()
    package = write_package(here)
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
    answer = None
    rest = [row for row in wanted if row != "B0"]
    if binary is None:
        for row in rest:
            results[row] = (False, "not run: the probe did not build")
    else:
        answer, why = probe(binary, here, package, pngs)
        rows = (answer or {}).get("rows") or []
        for row in rest:
            found = next((a for a in rows if a.get("id") == row), None)
            if found is None:
                not_scored.append(row)
                results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
                continue
            good, detail = bool(found["pass"]), found["detail"]
            if args.mode == "compare":
                same, how = against(found, kept_rows.get(row), pngs, stored)
                good, detail = good and same, f"{detail} | {how}"
            results[row] = (good, detail)

    if args.mode == "capture" and answer is not None:
        stored.mkdir(parents=True, exist_ok=True)
        for png in pngs.glob("*.png"):
            shutil.copyfile(png, stored / png.name)
        (stored / "answer.json").write_text(
            json.dumps(answer, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
        print(f"captured into {stored}")
    elif answer is not None:
        (here / "answer.json").write_text(
            json.dumps(answer, indent=2, sort_keys=True, ensure_ascii=False) + "\n")

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
