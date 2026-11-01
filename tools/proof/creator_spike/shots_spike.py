#!/usr/bin/env python3
"""Road map "creator-jobs" CJ2a, spike CJ-S4 — the shot signature (decides
CJ-24).

    python3 tools/proof/creator_spike/shots_spike.py [--socket SOCK]

The rule is the road map's (`rule.py` recomputes its `rule_sha256` against
CJ0a's table first). Inputs: the shots fixture (`analysis_fixtures.shots`),
its VFR twin, the no-cut input (S-TH1 under `tools/proof/media/creator/S-TH1/`,
else ten minutes of the moving still, S-TH1 then owed) and the flattened
40-clip export (`analysis_fixtures.flattened`, made over `--socket` when it is
missing). `shots_spike.swift` scores every frame of each with both candidate
signatures (and the SAD fallback); this script applies the rule:

- for each signature and each T in 0.02…1.98 (step 0.02): recall on the
  flattened export (a true cut found at its exact frame) and false cuts on the
  no-cut input, both at m = 4;
- the signature and T with the highest recall among those with at most one
  false cut per ten minutes of the no-cut input; several T at that recall
  take the median of them (this script's tie-break);
- m the largest of 4, 6, 8 and 12 that loses no true cut on the fixture;
- the fixture's dissolve and flash, the VFR twin, and `dissolve_patterns.mov`
  (a dissolve between test patterns) are scored at the chosen T and m and
  reported, not part of the rule;
- PASS at recall ≥ 98 %; otherwise the 64 × 36 SAD joins as a second signal
  (a frame is a cut by either) and the run repeats; if that fails, the
  measured recall is what CJ-24 states.

The cut rule is CJ2a's (spec §11 CJ-24): frame i is a cut when d1(i) ≥ T;
d2(n(i)) ≥ T, n(i) the next frame after i, passing when no frame lies in
i+1…i+m+1 or at the media's end; and d1(i) is the largest d1 over i−m…i+m
(empty indices 0), ties to the earlier.

Writes `tools/proof/work/creator_spike/CJ-S4/results.json`.
"""

import argparse
import json
import os
import shutil
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = PROOF.parents[1]
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(HERE))
import analysis_fixtures as fixtures  # noqa: E402
import rule  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/creator_spike/CJ-S4"
STH1 = ROOT / "tools/proof/media/creator/S-TH1"
SIGNATURES = {"luma": ("l1", "l2"), "colour": ("c1", "c2"), "sad": ("s1", "s2")}
THRESHOLDS = [round(0.02 * n, 2) for n in range(1, 100)]
MS = [4, 6, 8, 12]


def build():
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "shots_spike.swift", entry)
    binary = WORK / "shots-spike"
    swift_build.build(sources=[entry], output=binary, optimize=True)
    return binary


def score(binary, movie):
    out = WORK / f"{movie.stem}.json"
    if out.exists() and out.stat().st_mtime > max(movie.stat().st_mtime,
                                                  binary.stat().st_mtime):
        return json.loads(out.read_text())
    import subprocess
    rate = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                           "stream=r_frame_rate", "-of", "csv=p=0", str(movie)],
                          capture_output=True, text=True).stdout.strip()
    num, _, den = rate.partition("/")
    fps = float(num) / float(den or 1)
    run = subprocess.run([str(binary), str(movie), str(out), str(fps)], capture_output=True,
                         text=True, timeout=3600)
    if run.returncode != 0:
        raise SystemExit(f"shots_spike failed on {movie}: {run.stderr[-600:]}")
    return json.loads(out.read_text())


def grid(answer, keys):
    """Per index 0…last: (has, d1, d2) for the signal `keys` (one, or a list
    combined by max after scaling each by its own threshold — see `either`)."""
    last = max(f["k"] for f in answer["frames"])
    has = [False] * (last + 1)
    d1 = [0.0] * (last + 1)
    d2 = [0.0] * (last + 1)
    for f in answer["frames"]:
        k = f["k"]
        has[k], d1[k], d2[k] = True, f[keys[0]], f[keys[1]]
    return has, d1, d2


def cuts(has, d1, d2, threshold, m):
    count = len(has)
    found = []
    for i in range(count):
        if not has[i] or d1[i] < threshold:
            continue
        n = next((j for j in range(i + 1, min(count, i + m + 2)) if has[j]), None)
        if n is not None and d2[n] < threshold:
            continue
        best = True
        for j in range(max(0, i - m), min(count, i + m + 1)):
            if j == i:
                continue
            other = d1[j] if has[j] else 0.0
            if (j < i and other >= d1[i]) or (j > i and other > d1[i]):
                best = False
                break
        if best:
            found.append(i)
    return found


def either(a, b, ta, tb):
    """Two signals as one: each distance over its own threshold, the larger
    taken, so the threshold is 1."""
    has = a[0]
    d1 = [max(x / ta, y / tb) for x, y in zip(a[1], b[1])]
    d2 = [max(x / ta, y / tb) for x, y in zip(a[2], b[2])]
    return has, d1, d2


def recall(found, truth):
    hits = len(set(found) & set(truth))
    return hits / len(truth) if truth else 1.0


def no_cut_input(force):
    clips = sorted(STH1.glob("*.mov")) + sorted(STH1.glob("*.mp4")) if STH1.exists() else []
    if clips:
        return clips[0], "S-TH1", None
    return fixtures.moving_still(10, force), "moving_still (10 min)", "S-TH1 is missing: owed"


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    rule.check_rule("CJ-S4")
    shots = fixtures.shots()
    vfr = fixtures.vfr_twin()
    still, still_name, owed = no_cut_input(args.force)
    flat = fixtures.OUT / "flattened.mp4"
    record = fixtures.OUT / "flattened.json"
    if not (flat.exists() and record.exists()):
        if not args.socket:
            raise SystemExit("the flattened export is missing: pass --socket of a running "
                             "Frame Job to make it")
        sys.path.insert(0, str(PROOF))
        import mcp  # noqa: E402
        fixtures.flattened(mcp.MCP(args.socket))
    flat_truth = json.loads(record.read_text())["cuts"]
    binary = build()
    patterns = fixtures.dissolve_patterns()
    answers = {name: score(binary, path) for name, path in
               (("shots", shots), ("vfr", vfr), ("still", still), ("flattened", flat),
                ("patterns", patterns))}
    still_minutes = len(answers["still"]["frames"]) / answers["still"]["fps"] / 60
    allowed = still_minutes / 10  # one false cut per ten minutes

    table = []
    for name in ("luma", "colour"):
        keys = SIGNATURES[name]
        flat_grid = grid(answers["flattened"], keys)
        still_grid = grid(answers["still"], keys)
        for threshold in THRESHOLDS:
            r = recall(cuts(*flat_grid, threshold, 4), flat_truth)
            false = len(cuts(*still_grid, threshold, 4))
            table.append({"signature": name, "T": threshold, "recall": r,
                          "false_no_cut": false})

    def choose(rows):
        ok = [row for row in rows if row["false_no_cut"] <= allowed]
        if not ok:
            return None
        top = max(row["recall"] for row in ok)
        best = [row for row in ok if row["recall"] == top]
        by_sig = {}
        for row in best:
            by_sig.setdefault(row["signature"], []).append(row["T"])
        # the signature with the most T at the top recall (the widest margin),
        # then the median of its T
        name = max(by_sig, key=lambda s: (len(by_sig[s]), s == "colour"))
        ts = sorted(by_sig[name])
        return name, ts[len(ts) // 2], top, ts

    chosen = choose(table)
    verdict = {}
    if chosen is None:
        raise SystemExit("no signature and T meets the false-cut cap; extend the sweep")
    name, threshold, top, band = chosen
    keys = SIGNATURES[name]
    fixture_grid = grid(answers["shots"], keys)
    m_ok = [m for m in MS if set(fixtures.SHOTS_CUTS) <= set(cuts(*fixture_grid, threshold, m))]
    m = max(m_ok) if m_ok else None
    used = m or 4
    final_recall = recall(cuts(*grid(answers["flattened"], keys), threshold, used), flat_truth)
    sad_arm = None
    if final_recall < 0.98:
        # The SAD fallback: either signal, each over its own threshold.
        sad_rows = []
        for ts in THRESHOLDS[:50]:
            g = either(grid(answers["flattened"], keys), grid(answers["flattened"],
                       SIGNATURES["sad"]), threshold, ts)
            s = either(grid(answers["still"], keys), grid(answers["still"], SIGNATURES["sad"]),
                       threshold, ts)
            sad_rows.append({"T_sad": ts, "recall": recall(cuts(*g, 1.0, used), flat_truth),
                             "false_no_cut": len(cuts(*s, 1.0, used))})
        sad_arm = sad_rows
    fixture_found = cuts(*fixture_grid, threshold, used)
    vfr_found = cuts(*grid(answers["vfr"], keys), threshold, used)
    d1 = fixture_grid[1]
    verdict = {
        "signature": name, "T": threshold, "m": m, "m_passing": m_ok, "T_band_at_top": band,
        "recall_flattened_m4": top, "recall_flattened": final_recall,
        "passes": final_recall >= 0.98, "flattened_cuts": len(flat_truth),
        "false_no_cut_allowed": allowed, "no_cut_input": still_name, "no_cut_minutes":
        round(still_minutes, 2), "owed": owed,
        "fixture_truth": fixtures.SHOTS_CUTS, "fixture_found": fixture_found,
        "fixture_flash": {"frame": fixtures.FLASH, "d1": d1[fixtures.FLASH],
                          "d1_next": d1[fixtures.FLASH + 1]},
        "fixture_dissolve_max_d1": max(d1[fixtures.DISSOLVE[0]:fixtures.DISSOLVE[1] + 1]),
        "vfr_found": vfr_found,
        "vfr_flash": {"d1": grid(answers["vfr"], keys)[1][fixtures.FLASH],
                      "d1_next": grid(answers["vfr"], keys)[1][fixtures.FLASH + 1]},
        "patterns_dissolve_max_d1": max(grid(answers["patterns"], keys)[1][60:91]),
        "patterns_found": cuts(*grid(answers["patterns"], keys), threshold, used),
        "fixture_cut_d1": {str(c): d1[c] for c in fixtures.SHOTS_CUTS},
        "sad_arm": sad_arm,
    }
    for other in ("luma", "colour"):
        rows = [row for row in table if row["signature"] == other]
        ok = [row for row in rows if row["false_no_cut"] <= allowed]
        verdict[f"{other}_best_recall"] = max((row["recall"] for row in ok), default=None)
    path = rule.write_results("CJ-S4", {"verdict": verdict, "sweep": table,
                                        "inputs": {k: str(v) for k, v in (("shots", shots),
                                                   ("vfr", vfr), ("still", still),
                                                   ("flattened", flat))}})
    print(json.dumps(verdict, indent=1))
    print(f"results: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
