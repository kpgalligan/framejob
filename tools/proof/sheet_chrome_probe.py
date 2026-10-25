#!/usr/bin/env python3
"""#359: the six progress sheets (Export, Reverse, Consolidate, Transcribe,
AudioSync, Rewrap), their chrome now built from `Sheets.swift`'s shared
pieces, paint and lay out exactly as a baseline tree's hand-typed chrome.

    python3 tools/proof/sheet_chrome_probe.py --baseline REV

`git archive REV app/Sources` is extracted into
`tools/proof/work/sheet-chrome/baseline/`. `sheet_chrome_probe.swift` is
built as `main.swift` over that tree and over the working tree's
`app/Sources`, each to its own output path, through
`swift_build.build(defines=["FRAMEJOB_DEV_TOOLS"])`; the core is unchanged,
so both link the one staticlib. Each binary runs once per look (`light`,
`dark`), each run building the six sheets' views without presenting them
and capturing each with `UISnapshot.pass` (a PNG) and
`UISnapshotLayout.report` (a JSON layout dump).

Rows:
  B0   both builds succeed (a build failure is a scored FAIL, never an exit).
  C0   CONTROL: each run produced all six captures, and the Export sheet's
       light and dark PNGs differ, in both builds.
  C1   CONTROL: the baseline tree's `Sheets.swift` does not contain
       `func styleSheetProgressBar`, the working tree's does, and the two
       binaries' SHA-256 digests differ.
  X1-X6  one per sheet (export, reverse, consolidate, transcribe, audiosync,
       rewrap): in both looks the two builds' layout reports are equal and
       `v2_snapshot.differing` finds no pixel between their PNGs (of equal
       size). When B0, C0 or C1 fails, X1-X6 are scored FAIL naming it.

Exit (rule R): 0 iff every row passed, else 1.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build
import v2_snapshot

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/sheet-chrome"
SHEETS = ["export", "reverse", "consolidate", "transcribe", "audiosync", "rewrap"]
LOOKS = ["light", "dark"]
WALL = 120
MARK = "func styleSheetProgressBar"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def build(sources, here):
    """(binary, None) or (None, why)."""
    here.mkdir(parents=True, exist_ok=True)
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/sheet_chrome_probe.swift", entry)
    binary = here / "sheet-chrome-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, f"app source set incomplete in {sources}"
    try:
        swift_build.build(sources=swift + [entry], output=binary, defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(list(error.diagnostics)[:8] or [str(error)])
    return binary, None


def run(binary, look, out):
    """None, or why the run did not answer."""
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    try:
        result = subprocess.run([str(binary), look, str(out)], capture_output=True, text=True,
                                timeout=WALL)
    except subprocess.TimeoutExpired:
        return f"no answer within {WALL} s"
    (out / f"stderr-{look}.txt").write_text(result.stderr)
    if result.returncode != 0:
        return f"exit {result.returncode}: {result.stderr[-300:]}"
    return None


def captures(out, look):
    """The sheets a run captured, and its failures."""
    try:
        answer = json.loads((out / f"answer-{look}.json").read_text())
    except (OSError, ValueError):
        return [], {"answer": "no answer file"}
    have = [s for s in answer.get("captured", [])
            if (out / f"{s}-{look}.png").exists() and (out / f"{s}-{look}.json").exists()]
    return have, answer.get("failed", {})


def compare(base_out, tree_out, sheet, look):
    """(same, detail) for one sheet in one look."""
    png_a, png_b = base_out / f"{sheet}-{look}.png", tree_out / f"{sheet}-{look}.png"
    report_a = json.loads((base_out / f"{sheet}-{look}.json").read_text())
    report_b = json.loads((tree_out / f"{sheet}-{look}.json").read_text())
    same_report = report_a == report_b
    a, b = v2_snapshot.decode_png(png_a), v2_snapshot.decode_png(png_b)
    same_size = a[:2] == b[:2] and a[3] == b[3]
    diff = v2_snapshot.differing(a, b) if same_size else None
    same = same_report and same_size and not diff
    pixels = ("size " + f"{a[0]}x{a[1]} vs {b[0]}x{b[1]}") if not same_size else (
        f"{len(diff)} differing pixel(s)")
    views = f"{len(report_a.get('views', []))}/{len(report_b.get('views', []))} views"
    return same, f"{look}: report equal {same_report} ({views}), {pixels}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, help="the git revision to compare against")
    args = parser.parse_args()

    rows = {}
    base_dir = WORK / "baseline"
    tree_dir = WORK / "tree"
    for folder in (base_dir, tree_dir):
        if folder.exists():
            shutil.rmtree(folder)
    base_dir.mkdir(parents=True)
    tree_dir.mkdir(parents=True)

    archive = subprocess.run(["git", "-C", str(ROOT), "archive", args.baseline, "app/Sources"],
                             capture_output=True)
    base_sources = base_dir / "app/Sources"
    why_archive = None
    if archive.returncode != 0:
        why_archive = f"git archive {args.baseline}: {archive.stderr.decode()[-300:]}"
    else:
        untar = subprocess.run(["tar", "-x", "-C", str(base_dir)], input=archive.stdout,
                               capture_output=True)
        if untar.returncode != 0:
            why_archive = f"tar: {untar.stderr.decode()[-300:]}"
    tree_sources = ROOT / "app/Sources"

    base_bin, why_base = (None, why_archive) if why_archive else build(
        base_sources, base_dir / "build")
    tree_bin, why_tree = build(tree_sources, tree_dir / "build")
    rows["B0"] = (base_bin is not None and tree_bin is not None,
                  f"baseline {args.baseline}: {why_base or 'built'}; working tree: "
                  f"{why_tree or 'built'}")

    # C0: every run answers all six captures; Export's looks differ, in both builds.
    outs = {}
    c0_lines, c0_ok = [], rows["B0"][0]
    if rows["B0"][0]:
        for name, binary in (("baseline", base_bin), ("tree", tree_bin)):
            for look in LOOKS:
                out = (base_dir if name == "baseline" else tree_dir) / f"run-{look}"
                outs[(name, look)] = out
                why = run(binary, look, out)
                have, failed = captures(out, look) if why is None else ([], {"run": why})
                missing = [s for s in SHEETS if s not in have]
                c0_ok = c0_ok and not missing
                c0_lines.append(f"{name} {look}: {len(have)}/6"
                                + (f" missing {missing} {failed}" if missing else ""))
            light = outs[(name, "light")] / "export-light.png"
            dark = outs[(name, "dark")] / "export-dark.png"
            if light.exists() and dark.exists():
                a, b = v2_snapshot.decode_png(light), v2_snapshot.decode_png(dark)
                differ = a[:2] != b[:2] or bool(v2_snapshot.differing(a, b))
            else:
                differ = False
            c0_ok = c0_ok and differ
            c0_lines.append(f"{name} Export light and dark differ: {differ}")
    else:
        c0_lines.append("not run: B0 failed")
    rows["C0"] = (c0_ok, "; ".join(c0_lines))

    # C1: the two builds come from two different trees.
    base_sheets = base_sources / "Sheets.swift"
    tree_sheets = tree_sources / "Sheets.swift"
    base_has = base_sheets.exists() and MARK in base_sheets.read_text()
    tree_has = tree_sheets.exists() and MARK in tree_sheets.read_text()
    digests = (sha(base_bin), sha(tree_bin)) if base_bin and tree_bin else (None, None)
    distinct = digests[0] is not None and digests[0] != digests[1]
    rows["C1"] = (base_sheets.exists() and not base_has and tree_has and distinct,
                  f"baseline Sheets.swift holds `{MARK}`: {base_has} (exists "
                  f"{base_sheets.exists()}); working tree's: {tree_has}; binary digests "
                  f"{(digests[0] or '-')[:12]} / {(digests[1] or '-')[:12]}, differ {distinct}")

    blocked = [row for row in ("B0", "C0", "C1") if not rows[row][0]]
    for index, sheet in enumerate(SHEETS, start=1):
        row = f"X{index}"
        if blocked:
            rows[row] = (False, f"{sheet}: not compared — {', '.join(blocked)} failed")
            continue
        verdicts = [compare(outs[("baseline", look)], outs[("tree", look)], sheet, look)
                    for look in LOOKS]
        rows[row] = (all(v[0] for v in verdicts),
                     f"{sheet}: " + "; ".join(v[1] for v in verdicts))

    order = ["B0", "C0", "C1"] + [f"X{i}" for i in range(1, len(SHEETS) + 1)]
    for row in order:
        good, detail = rows[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in order if rows[row][0])
    print(f"scores: {passed}/{len(order)}")
    return 0 if passed == len(order) else 1


if __name__ == "__main__":
    sys.exit(main())
