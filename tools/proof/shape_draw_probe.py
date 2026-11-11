#!/usr/bin/env python3
"""Issue #588, spec §11 PR-16 — what a gradient shape's texture costs at 8 bits
and at 16-bit float, at 1920×1080 and 3840×2160.

    python3 tools/proof/shape_draw_probe.py
    python3 tools/proof/shape_draw_probe.py --mutant deep-call-eight    # T2 must FAIL

Builds `shape_draw_probe.swift` over `app/Sources` with `swift_build.py`'s line
(a probe that will not build is a scored FAILURE, never an exit) and runs it
once under `bounded.run`. The probe calls `LayerRenderers.shape(_:hash:deep:)`
with `raster_dither_proof.py`'s `shape563` gradient: per size two warm-up pairs,
then fifteen pairs of one 8-bit and one float cache miss, the order alternating
pair to pair, the pools purged after each pair. `renderShape` is private, so a
call's time is the Core Graphics draw PLUS the upload (`texture.replace`): what
a gradient animated by an action pays a frame.

Rows:
- **T1** the probe builds over app/Sources and answers one JSON object.
- **T2** every call answered a texture of the asked size, `bgra8Unorm` at
  8 bits and `rgba16Float` deep, fifteen of each a size: the times are of the
  two draws they name.

Printed, NEVER scored (a timing is a measurement, not a bound, and it is not in
`make test`): per size the 8-bit and the float median, least and most in ms, the
ratio of the medians, and the load average before and after the run.

The mutant edits a COPY of the probe's Swift (its anchor asserted to occur
once) so the deep call asks for 8 bits; exit 0 means T2 FAILED in the copy.

Exit 0 when T1 and T2 pass (a mutant: caught), 1 otherwise.
"""

import json
import os
import shutil
import statistics
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
from bounded import run as bounded_run  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/shape-draw-probe"
PROBE = "tools/proof/shape_draw_probe.swift"
DEADLINE = 600
PAIRS = 15
SIZES = [(1920, 1080), (3840, 2160)]
# name: (file, anchor, replacement), the row that must FAIL.
MUTANTS = {
    "deep-call-eight": (PROBE, 'd = timed(shape, hash: "d-\\(width)-\\(pair)", deep: true)',
                        'd = timed(shape, hash: "d-\\(width)-\\(pair)", deep: false)'),
}
MUST_FAIL = {"deep-call-eight": "T2"}

rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def build(entry_source, out):
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(entry_source, entry)
    binary = out / "shape-draw-probe"
    swift = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                   if p.name != "main.swift")
    try:
        swift_build.build(sources=swift + [entry], output=binary, timeout=DEADLINE)
    except swift_build.SwiftBuildFailed as error:
        if error.expired:
            return None, f"the build did not finish within {DEADLINE} s"
        return None, "; ".join(error.diagnostics[:8])
    return binary, ""


def figures(calls):
    times = [call.get("ms") for call in calls if isinstance(call.get("ms"), (int, float))]
    if not times:
        return None
    return statistics.median(times), min(times), max(times)


def probe(entry_source, out):
    binary, problem = build(entry_source, out)
    if binary is None:
        check("T1 the probe builds over app/Sources and answers", False, problem)
        return
    before = os.getloadavg()
    result = bounded_run([str(binary)], DEADLINE)
    after = os.getloadavg()
    try:
        answer = json.loads(result["stdout"])
    except json.JSONDecodeError:
        answer = {}
    check("T1 the probe builds over app/Sources and answers", answer.get("ok") is True,
          "" if answer.get("ok") else
          f"expired {result['expired']}, rc {result['rc']}: {result['stdout'][-300:]}"
          f"{result['stderr'][-300:]} {answer}")
    if answer.get("ok") is not True:
        return
    (out / "answer.json").write_text(json.dumps(answer, indent=1, sort_keys=True))
    sizes = {(s.get("width"), s.get("height")): s for s in answer.get("sizes") or []}
    wrong = []
    for width, height in SIZES:
        size = sizes.get((width, height)) or {}
        for depth, form in (("eight", "bgra8Unorm"), ("deep", "rgba16Float")):
            calls = size.get(depth) or []
            if len(calls) != PAIRS:
                wrong.append(f"{width}×{height} {depth}: {len(calls)} calls")
            wrong.extend(f"{width}×{height} {depth}: {call.get('format')} "
                         f"{call.get('width')}×{call.get('height')}" for call in calls
                         if (call.get("format"), call.get("width"), call.get("height"))
                         != (form, width, height))
    check(f"T2 every call answered a texture of the asked size, bgra8Unorm at 8 bits and "
          f"rgba16Float deep, {PAIRS} of each a size", not wrong and len(sizes) == len(SIZES),
          "; ".join(wrong[:6]))
    for width, height in SIZES:
        size = sizes.get((width, height)) or {}
        eight, deep = figures(size.get("eight") or []), figures(size.get("deep") or [])
        if eight is None or deep is None:
            print(f"  --   {width}×{height}: not timed", flush=True)
            continue
        print(f"  --   {width}×{height} (NOT scored; draw plus upload, a cache miss): 8-bit median "
              f"{eight[0]:.2f} ms ({eight[1]:.2f}–{eight[2]:.2f}), float median {deep[0]:.2f} ms "
              f"({deep[1]:.2f}–{deep[2]:.2f}), ratio float/8-bit {deep[0] / eight[0]:.2f}",
              flush=True)
    print("  --   load average (1, 5, 15 min) before "
          f"{', '.join(f'{v:.2f}' for v in before)}; after {', '.join(f'{v:.2f}' for v in after)}",
          flush=True)


def mutant(name):
    file, before, after = MUTANTS[name]
    text = (ROOT / file).read_text(encoding="utf-8")
    if text.count(before) != 1:
        print(f"mutant {name}: the control could not be performed — the anchor occurs "
              f"{text.count(before)} times in {file}: {before!r}")
        return 2
    with tempfile.TemporaryDirectory(prefix=f"framejob-shape-draw-{name}-") as temp:
        source = Path(temp) / "probe.swift"
        source.write_text(text.replace(before, after), encoding="utf-8")
        print(f"MUTANT {name}: {file}, anchor replaced once, in {source}")
        probe(source, Path(temp) / "out")
    built, row = rows.get("T1", False), MUST_FAIL[name]
    if built and rows.get(row) is False:
        print(f"MUTANT PASS: {name} — {row} FAILED in the copy")
        return 0
    print(f"MUTANT FAILURE: {name} — built {built}, {row} {rows.get(row)}")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#588 — a gradient shape's texture at 8 bits and at 16-bit float (probe)")
    probe(ROOT / PROBE, WORK)
    passed = sum(rows.values())
    print(f"{passed}/2")
    return 0 if len(rows) == 2 and all(rows.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
