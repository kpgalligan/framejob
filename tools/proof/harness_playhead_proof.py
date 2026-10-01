#!/usr/bin/env python3
"""Issue batch B39 (#198): the offscreen harness's `playheadSec` holds.

    python3 tools/proof/harness_playhead_proof.py
    python3 tools/proof/harness_playhead_proof.py --mutant {no-late-playhead,no-reselect}

Playback's first `report(0)` reaches `EditorViewController.playbackTimeChanged`
after the harness's editor opens and writes `document.playhead = 0`, so a
render asked for at 2 s was taken at 0 (README B32, #188 item 5). The harness
now sets the asked playhead again after its settle turns, through the editor's
own `setPlayhead`, and re-applies `selectAction` after it.

One fixture, `work/harness-playhead/hp.reelcut`: a grey 6 s card, clip 2, with
action A (id 3) over 0.5–1.5 s ending `{video: {opacity: 0.5}}` and action B
(id 4) over 2.0–3.5 s ending `{video: {x: 100}}`. Five renders, dark,
1440 × 862, size 1, the Clip tab, as (select, playhead s, action): `zero`
(−1, 0), `two-a` and `two-b` (−1, 2), `inside` (0, 3, "0") and `outside`
(0, 5, "0"). Time t sits at x = 132 + 42·t pt.

  P0 (control) `two-a` and `two-b` are byte-identical.
  P1  `zero` and `two-a` differ.
  P2  below the timeline bar (y ≥ 598 pt) every changed pixel lies within
      6 pt of x 132 or x 216, and each column holds at least one.
  P3  the toolbar (y < 44 pt) holds changed pixels.
  S0 (control) in `outside`, A's lane sample differs from B's.
  S1  in `inside`, both samples equal `outside`'s at the same points: the
      late playhead's entry into B did not leave B selected.

`--mutant` writes `harness/main.swift` minus its anchor line to
`work/harness-playhead/mutant-<name>/main.swift`, compiles it last after
`app/Sources/*.swift` minus the app's `main.swift` on `build.sh`'s swiftc line,
and follows rule R (README B13): 1 caught, 0 survived, 2 not performed.
"""

import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402
import clip_inspector_proof as ci  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "harness-playhead")
MAIN = os.path.join(HERE, "harness", "main.swift")
BUILD = os.path.join(HERE, "harness", "build.sh")
RENDER_BOUND = 300

ANCHOR_PLAYHEAD = "controller.setPlayhead(Ticks(playheadSeconds * 600_000))"
ANCHOR_RESELECT = ("Harness.applySelectAction(selectActionSpec, to: document, "
                   "refreshing: controller)")
MUTANTS: dict[str, tuple[str, set[str]]] = {
    "no-late-playhead": (ANCHOR_PLAYHEAD, {"P1", "P2", "P3"}),
    "no-reselect": (ANCHOR_RESELECT, {"S1"}),
}
ROWS = ["P0", "P1", "P2", "P3", "S0", "S1"]

# (tag, select, playhead seconds, action)
RENDERS = [("zero", -1, 0, "-"), ("two-a", -1, 2, "-"), ("two-b", -1, 2, "-"),
           ("inside", 0, 3, "0"), ("outside", 0, 5, "0")]
NEEDS = {"P0": ("two-a", "two-b"), "P1": ("zero", "two-a"), "P2": ("zero", "two-a"),
         "P3": ("zero", "two-a"), "S0": ("outside",), "S1": ("inside", "outside")}

BAR_BOTTOM = e2.TIMELINE_Y + e2.BAR_H      # 598
LANE_TOP = e2.STRIP_Y + e2.STRIP_H          # 643
SAMPLE_Y = LANE_TOP + ci.LANE_M - 2         # 653
A_X = e2.CLIP_X0 + 1.5 * e2.ZOOM - 2        # 193
B_X = e2.CLIP_X0 + 3.5 * e2.ZOOM - 2        # 277
COLUMNS = (e2.CLIP_X0, e2.CLIP_X0 + 2 * e2.ZOOM)   # 132, 216
SLOP = 6

RESULTS = []   # (row, ok, instrument)


def check(row, ok, detail="", *, instrument=False):
    RESULTS.append((row, bool(ok), instrument))
    print(f"  {'PASS' if ok else 'FAIL'}: {row}")
    if detail:
        print("      " + detail)


def fixture():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    return e2.write_package("hp", e2.project([
        e2.clip(2, 0, e2.GREY, name="Card", duration=6 * e2.TICKS, actions=[
            ci.action(3, 0.5, 1.5, {"video": {"opacity": 0.5}}),
            ci.action(4, 2.0, 3.5, {"video": {"x": 100.0}})])]))


def swiftc_line(sources, out):
    """`build.sh`'s swiftc flags, verbatim."""
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    return ["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
            "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
            "-import-objc-header",
            os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
            "-L", os.path.join(ROOT, "core", "target", "release"), "-lreelcut_core",
            *sources, "-o", out]


def build(mutant: str | None) -> tuple[str | None, str]:
    """The harness: `build.sh`'s for a plain run, a mutant copy's otherwise.
    Answers (binary, note) or (None, why)."""
    if mutant is None:
        result = subprocess.run([BUILD], capture_output=True, text=True)
        if result.returncode != 0:
            return None, "build.sh failed: " + (result.stdout + result.stderr).strip()[-400:]
        printed = result.stdout.strip().splitlines()
        if not printed:
            return None, "build.sh exited 0 but printed no binary path"
        return printed[-1], result.stderr.strip()
    anchor = MUTANTS[mutant][0]
    with open(MAIN, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    count = sum(1 for line in lines if line.strip() == anchor)
    if count != 1:
        return None, f"the anchor `{anchor}` occurs {count} times in harness/main.swift"
    here = os.path.join(WORK, f"mutant-{mutant}")
    if os.path.exists(here):
        shutil.rmtree(here)
    os.makedirs(here)
    copy = os.path.join(here, "main.swift")
    with open(copy, "w", encoding="utf-8") as handle:
        handle.write("\n".join(line for line in lines if line.strip() != anchor))
    sources_dir = os.path.join(ROOT, "app", "Sources")
    sources = [os.path.join(sources_dir, name) for name in sorted(os.listdir(sources_dir))
               if name.endswith(".swift") and name != "main.swift"]
    binary = os.path.join(here, "harness")
    began = time.time()
    result = subprocess.run(swiftc_line(sources + [copy], binary),
                            capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        return None, "swiftc failed: " + (result.stdout + result.stderr).strip()[-600:]
    resources = os.path.join(ROOT, "app", "Resources")
    shutil.copytree(os.path.join(resources, "Fonts"), os.path.join(here, "Fonts"))
    shutil.copytree(os.path.join(resources, "Models"), os.path.join(here, "Models"))
    shutil.copy(os.path.join(ROOT, "docs", "graphics-api.md"),
                os.path.join(here, "GraphicsAPI.md"))
    shutil.copy(os.path.join(ROOT, "docs", "graphics-api.d.ts"),
                os.path.join(here, "GraphicsAPI.d.ts"))
    return binary, f"built {os.path.relpath(binary, ROOT)} in {time.time() - began:.0f} s"


def render(binary, package, out, select, playhead, action="-") -> tuple[str | None, str | None]:
    args = [binary, package, out, "dark", "1440", "862", str(select), str(playhead), "1",
            "clip", "-", "-", "-", action]
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=RENDER_BOUND)
    except subprocess.TimeoutExpired:
        return None, f"render ran past {RENDER_BOUND} s"
    if result.returncode != 0 or not os.path.exists(out):
        return None, f"exit {result.returncode}: " + (result.stdout + result.stderr).strip()[-400:]
    return out, None


def near_column(x_pt):
    return any(abs(x_pt - c) <= SLOP for c in COLUMNS)


def score(images, failures):
    def blocked(row):
        why = [f"{tag}: {failures[tag]}" for tag in NEEDS[row] if tag in failures]
        if why:
            check(row, False, "not rendered — " + "; ".join(why), instrument=True)
            return True
        return False

    if not blocked("P0"):
        a, b = images["two-a"], images["two-b"]
        same = a.rows == b.rows and (a.width, a.height) == (b.width, b.height)
        check("P0", same, "byte-identical" if same
              else f"{len(e2.changed_pixels(a, b))} px differ between two renders at 2 s")

    if not any([blocked(row) for row in ("P1", "P2", "P3")]):
        zero, two = images["zero"], images["two-a"]
        scale = zero.scale
        diff = e2.changed_pixels(zero, two)
        check("P1", bool(diff), f"{len(diff)} px differ between 0 s and 2 s")
        below = [(x, y) for x, y in diff if y / scale >= BAR_BOTTOM]
        stray = [(x, y) for x, y in below if not near_column(x / scale)]
        held = {c: sum(1 for x, _ in below if abs(x / scale - c) <= SLOP) for c in COLUMNS}
        check("P2", below and not stray and all(held.values()),
              f"{len(below)} px below y {BAR_BOTTOM}; within {SLOP} pt of x "
              + ", ".join(f"{c}: {n}" for c, n in held.items())
              + f"; {len(stray)} elsewhere"
              + (("\n" + e2.describe(e2.clusters(stray), scale, limit=4)) if stray else ""))
        toolbar = [(x, y) for x, y in diff if y / scale < e2.TOOLBAR]
        check("P3", bool(toolbar), f"{len(toolbar)} px in the toolbar (y < {e2.TOOLBAR})")
        rest = [(x, y) for x, y in diff
                if e2.TOOLBAR <= y / scale < BAR_BOTTOM]
        if rest:
            print(f"      not scored: {len(rest)} px between y {e2.TOOLBAR} and "
                  f"{BAR_BOTTOM}")
            print(e2.describe(e2.clusters(rest), scale, limit=6))

    if not blocked("S0"):
        out = images["outside"]
        a, b = ci.px(out, A_X, SAMPLE_Y), ci.px(out, B_X, SAMPLE_Y)
        check("S0", a != b, f"outside: A {a} at ({A_X:g}, {SAMPLE_Y:g}), "
              f"B {b} at ({B_X:g}, {SAMPLE_Y:g})")

    if not blocked("S1"):
        ins, out = images["inside"], images["outside"]
        got = (ci.px(ins, A_X, SAMPLE_Y), ci.px(ins, B_X, SAMPLE_Y))
        want = (ci.px(out, A_X, SAMPLE_Y), ci.px(out, B_X, SAMPLE_Y))
        check("S1", got == want, f"inside: A {got[0]}, B {got[1]}; "
              f"outside: A {want[0]}, B {want[1]}")


def run(mutant):
    package = fixture()
    binary, note = build(mutant)
    if binary is None:
        for row in ROWS:
            check(row, False, note, instrument=True)
        return note
    print(f"harness: {binary}" + (f" ({note})" if note else ""))
    out_dir = os.path.join(WORK, f"mutant-{mutant}" if mutant else "plain")
    os.makedirs(out_dir, exist_ok=True)
    images, failures = {}, {}
    for tag, select, playhead, action in RENDERS:
        path, why = render(binary, package, os.path.join(out_dir, tag + ".png"),
                           select, playhead, action)
        if why:
            failures[tag] = why
        else:
            images[tag] = e2.Image(path)
    score(images, failures)
    return None


def main():
    mutant = None
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant":
        mutant = sys.argv[2]
        if mutant not in MUTANTS:
            print(f"mutant {mutant}: the control could not be performed — no such mutant; "
                  f"one of {sorted(MUTANTS)}")
            return 2
    elif len(sys.argv) != 1:
        print(__doc__)
        return 2
    print("#198 — the harness's playhead holds"
          + (f", MUTANT {mutant}" if mutant else ""))
    why = run(mutant)
    good = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)}")
    if mutant is None:
        return 0 if RESULTS and good == len(RESULTS) else 1
    if why:
        print(f"mutant {mutant}: the control could not be performed — {why}")
        return 2
    instruments = [row for row, ok, inst in RESULTS if inst and not ok]
    if instruments:
        print(f"mutant {mutant}: the control could not be performed — not rendered: "
              f"{', '.join(instruments)}")
        return 2
    named = MUTANTS[mutant][1]
    failed = [row for row, ok, _ in RESULTS if not ok]
    others = [row for row in failed if row not in named]
    if others:
        print(f"mutant {mutant}: the control could not be performed — rows outside "
              f"{', '.join(sorted(named))} failed: {', '.join(others)}")
        return 2
    passed = [row for row in ROWS if row in named and row not in failed]
    if passed:
        print(f"mutant {mutant}: SURVIVED — {', '.join(passed)} passed")
        return 0
    print(f"mutant {mutant}: caught — {', '.join(r for r in ROWS if r in named)} failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
