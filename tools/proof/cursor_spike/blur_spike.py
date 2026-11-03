#!/usr/bin/env python3
"""Road map "creator-jobs" CU11, spike CU-S5 — motion blur's cost (decides spec §11 CU-110).

    python3 tools/proof/cursor_spike/blur_spike.py [--runs 5] [--frames 60] [--warmup 10]
        [--selftest]

The rule is the road map's (`creator_spike/rule.py` recomputes its hash first; a mismatch
prints `RULE CHANGED CU-S5`, writes nothing and exits 1): ship zoom blur at the largest N in
{16, 8, 4} adding ≤ 4 ms at 1080p and ≤ 8 ms at 4K, one N for preview and export; STOP zoom
blur when N = 4 misses either bound.

`blur_spike.swift` is built as `cursor_layer_proof.py`'s probe rows are: every app source but
`main.swift`, the probe as `main.swift`, `FRAMEJOB_DEV_TOOLS`, then a `default.metallib` of
`Compositor.metal` beside the binary. It draws one full-canvas layer at a 2× zoom's eased
middle once, and N times at the shutter's sub-frame placements into a composite target then
once onto the destination, at 1920×1080 and 3840×2160, and answers each frame's GPU ms.

`added[N]` per size is the median over runs of (the run's median at N − the run's median
drawn once); the runs are the repeat (three lanes share the machine).

Exit 0 whatever the verdict; 1 on a changed rule, a failed build or a probe crash; 2 when
`core/target/release/libframejob_core.a` or `build/codecs/stamp.json` is missing. Writes
`tools/proof/work/creator_spike/CU-S5/results.json`.
"""

import argparse
import json
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = PROOF.parents[1]
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(PROOF / "creator_spike"))
import rule  # noqa: E402
import swift_build  # noqa: E402

SPIKE = "CU-S5"
SIZES = [[1920, 1080], [3840, 2160]]
NS = (16, 8, 4)
LIMITS = {"1920x1080": 4.0, "3840x2160": 8.0}
SHUTTER = 0.5


def decide(added):
    """`added` maps "1920x1080" and "3840x2160" to {N: ms}. The largest N in (16, 8, 4) whose
    added time is within both bounds; else STOP; a missing figure is not measured."""
    for n in NS:
        for size in LIMITS:
            figure = (added.get(size) or {}).get(n)
            if figure is None:
                return None, "VERDICT not measured"
    for n in NS:
        if all(added[size][n] <= limit for size, limit in LIMITS.items()):
            return n, f"zoom blur at N = {n}"
    a, b = added["1920x1080"][4], added["3840x2160"][4]
    return None, f"STOP zoom blur: N = 4 adds {a:.3f} ms at 1080p and {b:.3f} ms at 4K"


def selftest():
    def table(hd, uhd):
        return {"1920x1080": dict(zip(NS, hd)), "3840x2160": dict(zip(NS, uhd))}

    cases = [
        ("16", table((3.9, 2.0, 1.0), (7.9, 4.0, 2.0)), 16),
        ("8", table((4.5, 4.0, 1.0), (7.0, 8.0, 2.0)), 8),
        ("4", table((9.0, 4.1, 4.0), (9.0, 8.5, 8.0)), 4),
        ("STOP", table((9.0, 6.0, 4.5), (9.0, 8.5, 7.0)), None),
        ("not measured", {"1920x1080": {16: 1.0, 8: 1.0, 4: 1.0}, "3840x2160": {16: 1.0, 8: 1.0}},
         None),
    ]
    wrong = []
    for name, added, expected in cases:
        n, verdict = decide(added)
        ok = n == expected
        if name == "STOP":
            ok = ok and verdict.startswith("STOP zoom blur: N = 4 adds 4.500 ms at 1080p")
        if name == "not measured":
            ok = ok and verdict == "VERDICT not measured"
        print(f"{'PASS' if ok else 'FAIL'} {name}: {n} {verdict}")
        if not ok:
            wrong.append(name)
    return 1 if wrong else 0


def build(work):
    entry = work / "main.swift"
    shutil.copyfile(HERE / "blur_spike.swift", entry)
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    binary = work / "blur-spike"
    swift_build.build(sources=sources + [str(entry)], output=binary,
                      defines=["FRAMEJOB_DEV_TOOLS"])
    air, library = work / "Compositor.air", work / "default.metallib"
    shader = ROOT / "app/Resources/Shaders/Compositor.metal"
    for argv in (["metal", "-c", str(shader), "-o", str(air)],
                 ["metallib", str(air), "-o", str(library)]):
        made = subprocess.run(["xcrun", "-sdk", "macosx", *argv], capture_output=True,
                              text=True, timeout=300)
        if made.returncode != 0:
            raise RuntimeError("the shader did not build: " + made.stderr[-300:])
    return binary


def summarise(rows):
    """Per size: `once`, each N's run medians, `added[N]`."""
    sizes = {}
    for row in rows:
        key = f"{row['width']}x{row['height']}"
        entry = sizes.setdefault(key, {"medians": {}})
        entry["medians"][row["n"]] = row["run_medians_ms"]
    added = {}
    for key, entry in sizes.items():
        once = entry["medians"].get(0) or []
        entry["once"] = once
        added[key] = {}
        for n in NS:
            at = entry["medians"].get(n) or []
            entry[str(n)] = at
            pairs = [a - o for a, o in zip(at, once) if a is not None and o is not None]
            if pairs and len(pairs) == len(once) == len(at):
                added[key][n] = statistics.median(pairs)
        entry["added"] = {str(n): v for n, v in added[key].items()}
        del entry["medians"]
    return sizes, added


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--frames", type=int, default=60)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    computed, table, match = rule.check_rule(SPIKE)
    if not match:
        print(f"RULE CHANGED {SPIKE}")
        return 1
    if not swift_build.LIBRARY.exists() or not swift_build.CODEC_STAMP.exists():
        print(f"not performed: {swift_build.LIBRARY} or {swift_build.CODEC_STAMP} is missing")
        return 2
    work = rule.WORK / f"{SPIKE}-build"
    work.mkdir(parents=True, exist_ok=True)
    try:
        binary = build(work)
    except (swift_build.SwiftBuildFailed, RuntimeError) as error:
        detail = getattr(error, "diagnostics", None) or []
        print(f"the probe did not build: {error} {detail[:6]}")
        return 1
    request = work / "request.json"
    request.write_text(json.dumps({"sizes": SIZES, "ns": sorted(NS), "runs": args.runs,
                                   "frames": args.frames, "warmup": args.warmup,
                                   "shutter": SHUTTER}))
    try:
        run = subprocess.run([str(binary), "blur-spike", str(request)], capture_output=True,
                             text=True, timeout=1800, cwd=str(work))
        answer = json.loads(run.stdout)
    except (subprocess.TimeoutExpired, ValueError) as error:
        print(f"the probe failed: {error}")
        return 1
    if run.returncode != 0:
        print(f"the probe exited {run.returncode}: {run.stderr[-400:]}")
        return 1
    sizes, added = summarise(answer.get("rows", []))
    n, verdict = decide(added)
    results = {"sizes": sizes, "n": n, "verdict": verdict, "runs": args.runs,
               "frames": args.frames, "warmup": args.warmup, "shutter": SHUTTER,
               "limits_ms": LIMITS, "problems": answer.get("problems", []),
               "rows": answer.get("rows", [])}
    path = rule.write_results(SPIKE, results)
    for key, entry in sizes.items():
        print(f"{key}: once {['%.3f' % v for v in entry['once'] if v is not None]}; added "
              + ", ".join(f"N={k} {v:.3f} ms" for k, v in entry["added"].items()))
    if answer.get("problems"):
        print("problems: " + "; ".join(answer["problems"][:6]))
    print(f"VERDICT {verdict}")
    print(f"results: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
