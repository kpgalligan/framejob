#!/usr/bin/env python3
"""The Welcome lockup's product wordmark and the About panel's copyright (spec §11 NM-16), from
the app brand handoff (`designs/design_handoff_app_brand/`).

    python3 tools/proof/wordmark_proof.py [--sources DIR] [--mutant NAME] [--only IDS]

D1 and T1 read text and build nothing. `wordmark_probe.swift` is built with `swift_build.py`'s
line (without `-D FRAMEJOB_DEV_TOOLS`) over `--sources` and run once under
`tools/proof/work/wordmark/`, killed at a 120 s wall; it shows nothing and reads or writes
nothing on this Mac. Every number a row compares is the handoff README's, written as a literal.
Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  D1  `ProductWordmark+FrameJob.swift` (in `--sources`) holds the handoff's
      `frame-job-wordmark.json`: the same width, and the letters' and the playhead's commands
      and numbers token for token (the Swift copy's line breaks are whitespace).
  T1  `project.yml` sets `NSHumanReadableCopyright` to "Copyright © 2026 Boppa Llewyn.", once.
  B0  the probe builds.
  W1  `WordmarkArtwork.frameJob` parses: width 4844, the playhead's bounds x 2844.7…3064.7 and
      y −960…0 in units, the letters inside the viewBox.
  W2  `ProductWordmarkView` at 44 pt: 213.136 × 50.16 pt, its first baseline 48.4 pt below its
      top and its last 1.76 above its foot, its cap line 17.16 pt below its top, flipped.
  W3  `BrandLockupView` arranges exactly [BrandMarkView(88), ProductWordmarkView], centred, the
      wordmark's cap line 35 pt below the mark's ink (90/824 of 88 pt above the mark view's
      foot) and the lockup 158 pt tall (its height before NM-16), each within 0.5 pt (the stack
      puts frames on a 1 pt grid in this windowless probe), the stack's spacing about 8.
  W4  of the two, only the wordmark is an accessibility element: static text whose label and
      value are "Frame Job".
  W5  drawn at 44 pt in Aqua and Dark Aqua: a point in the F's stem is dark in light and light in
      dark, the playhead's stem is #F4653F within 0.06 in both, a point in the gap is clear.
  W6  the letters' winding rule is nonzero, the glyphs overlap (sampled every 8 units, the
      points where the nonzero and even-odd rules disagree), and at least 90% of those points
      are drawn filled.

Mutants (`--mutant`), each a literal found exactly once in the named file:
  data-corrupt     the letters' first command an unknown letter: must fail D1 and W1.
  baseline-off     the first baseline at the box's height, not its top: must fail W2.
  cap-line-26      the cap line 26 pt below the mark's ink: must fail W3.
  height-shrinks   no space kept below the wordmark, so the lockup is 145 pt: must fail W3.
  both-speak       the mark made an accessibility element too: must fail W4.
  wordmark-silent  the wordmark not an accessibility element: must fail W4.
  coral-letters    the letters drawn in coral: must fail W5.
  even-odd         the letters filled by the even-odd rule: must fail W6.

Exit (rule R): a plain run exits 0 iff every row passed and 1 when a row failed; a build
failure is B0's FAIL there. A `--mutant` run exits 1 when every row the mutant names failed
(caught), 0 when one passed (survived), and 2 when the control could not be performed: the
copy's `before` text not found exactly once, the copy did not build, or a named row was not
scored.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/wordmark"
HANDOFF_JSON = ROOT / "designs/design_handoff_app_brand/frame-job-wordmark.json"
DATA_FILE = "ProductWordmark+FrameJob.swift"
COPYRIGHT = 'NSHumanReadableCopyright: "Copyright © 2026 Boppa Llewyn."'
ROWS = ["D1", "T1", "B0", "W1", "W2", "W3", "W4", "W5", "W6"]
PROBE_ROWS = ["W1", "W2", "W3", "W4", "W5", "W6"]
WALL = 120

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "data-corrupt": (["D1", "W1"], [
        (DATA_FILE,
         "        M 0.0 0.0 L 0.0 -709.7 L 482.2 -709.7",
         "        Q 0.0 0.0 L 0.0 -709.7 L 482.2 -709.7")]),
    "baseline-off": (["W2"], [
        ("ProductWordmark.swift",
         "override var firstBaselineOffsetFromTop: CGFloat { -WordmarkArtwork.top * scale }",
         "override var firstBaselineOffsetFromTop: CGFloat { WordmarkArtwork.height * scale }")]),
    "cap-line-26": (["W3"], [
        ("BrandMark.swift",
         "private static let capLineBelowMarkInk: CGFloat = 35",
         "private static let capLineBelowMarkInk: CGFloat = 26")]),
    "height-shrinks": (["W3"], [
        ("BrandMark.swift",
         "edgeInsets.bottom = max(",
         "_ = max(")]),
    "both-speak": (["W4"], [
        ("BrandMark.swift",
         "markView.setAccessibilityElement(false)",
         "markView.setAccessibilityElement(true)")]),
    "wordmark-silent": (["W4"], [
        ("ProductWordmark.swift",
         "        setAccessibilityElement(true)\n",
         "")]),
    "coral-letters": (["W5"], [
        ("ProductWordmark.swift",
         "[(artwork.letters, textColor), (artwork.motif, DS.coral)]",
         "[(artwork.letters, DS.coral), (artwork.motif, DS.coral)]")]),
    "even-odd": (["W6"], [
        ("ProductWordmark.swift",
         "path.windingRule = .nonZero",
         "path.windingRule = .evenOdd")]),
}

TOKEN = re.compile(r"[A-Za-z]|-?\d+(?:\.\d+)?")


def tokens(path_data):
    """Commands as letters, numbers as floats, so 960 and 960.0 compare equal."""
    return [t if t.isalpha() else float(t) for t in TOKEN.findall(path_data)]


def swift_literal(text, name):
    match = re.search(r"static let " + name + r' = """\n(.*?)\n\s*"""', text, re.S)
    return match.group(1) if match else None


def row_d1(sources):
    path = sources / DATA_FILE
    if not path.exists():
        return False, f"{path} is missing"
    text = path.read_text()
    handoff = json.loads(HANDOFF_JSON.read_text())
    width = re.search(r"static let width: CGFloat = ([\d.]+)", text)
    letters, motif = swift_literal(text, "letters"), swift_literal(text, "motif")
    if not (width and letters and motif):
        return False, "the width, letters or motif literal was not found"
    want_letters, want_motif = tokens(handoff["letters"]), tokens(handoff["motif"]["d"])
    got_letters, got_motif = tokens(letters), tokens(motif)
    width_ok = float(width.group(1)) == float(handoff["viewBox"]["width"])
    first_diff = next((i for i, (a, b) in enumerate(zip(got_letters, want_letters)) if a != b),
                      None)
    good = width_ok and got_letters == want_letters and got_motif == want_motif
    return good, (f"width {width.group(1)} (handoff {handoff['viewBox']['width']}); letters "
                  f"{len(got_letters)} tokens (handoff {len(want_letters)}), first difference "
                  f"at {first_diff}; motif equal {got_motif == want_motif}; motif mode "
                  f"{handoff['motif'].get('mode')}")


def row_t1():
    text = (ROOT / "project.yml").read_text()
    count = text.count(COPYRIGHT)
    return count == 1, f"`{COPYRIGHT}` found {count} time(s) in project.yml (want 1)"


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build`, without the dev-tools flag."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/wordmark_probe.swift", entry)
    binary = here / "wordmark-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; why, when a `before` is not found once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """(the probe's answer, None), or (None, why)."""
    try:
        result = run([str(binary)], timeout=WALL, cwd=here)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
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
    wanted = args.only.split(",") if args.only else (
        sorted(set(["B0"] + named), key=ROWS.index) if args.mutant else ROWS)
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
    if "D1" in wanted:
        results["D1"] = row_d1(sources)
    if "T1" in wanted:
        results["T1"] = row_t1()
    not_scored = []
    probe_wanted = [row for row in wanted if row in PROBE_ROWS]
    if "B0" in wanted or probe_wanted:
        binary, why = build(sources, here)
        results["B0"] = (binary is not None, why or f"built from {sources}")
        if binary is None and args.mutant:
            print(f"B0 fail — {why}")
            print(f"mutant {args.mutant}: the control could not be performed — "
                  "the copy did not build")
            return 2
        if probe_wanted:
            if binary is None:
                for row in probe_wanted:
                    results[row] = (False, "not run: the probe did not build")
            else:
                answer, why = probe(binary, here)
                rows = (answer or {}).get("rows") or []
                for row in probe_wanted:
                    found = next((a for a in rows if a.get("id") == row), None)
                    if found is None:
                        not_scored.append(row)
                        results[row] = (False, f"no row: {why or 'the probe did not answer'}")
                    else:
                        results[row] = (bool(found["pass"]), found["detail"])

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
