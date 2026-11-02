#!/usr/bin/env python3
"""Road map "creator-jobs" TX2a, spike TX-S2 — the view (decides TX-21).

    python3 tools/proof/transcript_spike/view_spike.py            # measure and judge
    python3 tools/proof/transcript_spike/view_spike.py --measure  # the same (TX2a's T11)

`view_spike.swift`, built from `app/Sources` through `swift_build.build` (-O),
measures candidate (b), `TranscriptView` itself, in a 304 × 800 pt scroll view
in an offscreen window on the main thread, Source Sans 3 registered (its header
lists every measurement). The results, with the rule's `rule_sha256`
(`creator_spike/rule.py`), the OS build, the device and the load average, go to
`tools/proof/work/creator_spike/TX-S2/results.json`; the last capture to
`tools/proof/work/transcript_spike/view.png`.

Rule (the road map's, CJ0a's table holds its hash): take the first of (b), (c),
(a) that meets: first layout ≤ 200 ms; rebuild ≤ 100 ms; highlight ≤ 2 ms;
hit-test ≤ 1 ms; added memory ≤ 1/256 of physical memory; Space and J/K/L reach
`handleEditorKey` with no change to a frozen file. (c) and (a) are built only
if (b) fails. A bound missed by under 20 % is re-run once (three lanes share
the machine), and the re-run decides.

Exit: 0 when (b) meets every bound, 1 when it does not (record the numbers and
STOP, TX2a's spec), 2 when the probe would not build or run.
"""

import argparse
import json
import os
import shutil
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
import bounded  # noqa: E402 — on swift_build's path

SPIKE = "TX-S2"
WORK = ROOT / "tools/proof/work/transcript_spike"
FONTS = ROOT / "app/Resources/Fonts"

# (key, bound, how it is judged): a timing in ms, or the memory share.
BOUNDS = [("first_layout_ms", 200.0), ("rebuild_ms", 100.0), ("highlight_adjacent_ms", 2.0),
          ("highlight_far_ms", 2.0), ("hit_test_ms", 1.0)]


def build():
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "view_spike.swift", entry)
    binary = WORK / "view-spike"
    swift_build.build(sources=[*swift_build.app_sources(), entry], output=binary, optimize=True)
    return binary


def measure(binary):
    answer = WORK / "view-answer.json"
    if answer.exists():
        answer.unlink()
    ran = bounded.run([str(binary), str(FONTS), str(answer), str(WORK / "view.png")], 600,
                      cwd=str(WORK))
    if not answer.exists():
        raise RuntimeError(f"no answer (rc {ran['rc']}): {ran['stderr'][-600:]}")
    return json.loads(answer.read_text())


def judge(answer):
    """[(name, value, bound, ok)] for every bound, and the key rows."""
    timings = answer["timings"]
    out = [(key, timings.get(key), bound, (timings.get(key) or 1e9) <= bound)
           for key, bound in BOUNDS]
    share = timings["physical_memory"] / 256
    out.append(("added_footprint_bytes", timings["added_footprint_bytes"], share,
                timings["added_footprint_bytes"] <= share))
    out.append(("rebuild_anchor_kept", timings.get("rebuild_anchor_kept"), True,
                timings.get("rebuild_anchor_kept") is True))
    out.append(("hit_test_token", timings.get("hit_test_token"), timings.get("hit_test_expected"),
                timings.get("hit_test_token") == timings.get("hit_test_expected")))
    out.append(("paragraphs", timings.get("paragraphs"), 900, timings.get("paragraphs") == 900))
    for row in answer["rows"]:
        out.append((row["name"], row.get("detail", row["ok"]), True, row["ok"] is True))
    return out


def near_miss(judged):
    """A bound missed by under 20 %: worth the one re-run."""
    for name, value, bound, ok in judged:
        if not ok and isinstance(value, (int, float)) and isinstance(bound, (int, float)) \
                and not isinstance(value, bool) and bound and value <= bound * 1.2:
            return True
    return False


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--measure", action="store_true", help="the same run (TX2a's T11)")
    parser.parse_args(argv)
    try:
        binary = build()
    except swift_build.SwiftBuildFailed as error:
        print("\n  ".join([f"view_spike: did not build: {error}"] + list(error.diagnostics[:8])))
        return 2
    runs = []
    try:
        runs.append(measure(binary))
        judged = judge(runs[-1])
        if near_miss(judged):
            print("a bound missed by under 20 %: re-run once", flush=True)
            runs.append(measure(binary))
            judged = judge(runs[-1])
    except (RuntimeError, ValueError, KeyError) as error:
        print(f"view_spike: did not run: {error}")
        return 2
    load = subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True, text=True).stdout
    passed = all(ok for _, _, _, ok in judged)
    results = {"candidate": "b", "runs": runs, "load_average": load.strip(),
               "judged": [{"name": n, "value": v, "bound": b, "ok": ok} for n, v, b, ok in judged],
               "verdict": "b" if passed else "STOP: (b) fails; (c) and (a) not built",
               "png": str(WORK / "view.png")}
    path = rule.write_results(SPIKE, results)
    for name, value, bound, ok in judged:
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {value} (bound {bound})")
    print(f"load average {load.strip()}; results {path}")
    print(f"TX-S2 verdict: {results['verdict']}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
