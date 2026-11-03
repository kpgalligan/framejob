#!/usr/bin/env python3
"""Spike SW-S3's head (road map "creator-jobs" SW8, spec §11 SW-88): mouth
activity on a one-microphone show.

`rule.check_rule("SW-S3")` first. The rule has two halves:

- **Rate:** `faces` at ≥ 4× realtime per angle. Met by CJ-S2's recorded run
  (spec §11 CJ-S2's verdict, the road map's CJ3 record): 10.30× on 1080p30
  and 8.88× on 4K30 at the read's long side 720. SW8 adds no Vision request,
  so nothing here re-measures it.
- **Agreement:** on S-PC2 (two people sharing ONE microphone, a camera on
  each, a lavalier each, with its `turns.json`), the share of the seconds the
  truth labels as one person speaking on which SW-81's label agrees. Skipped
  by name while `tools/proof/media/creator/S-PC2/` does not exist: owed.

The band is the middle one by the owner's answer (2026-11-01: "proceed at
SW-S3's middle band, with SW-82's hedge"), and FaceActivity's floor 0.02 is
provisional until S-PC2 measures it.

Results: tools/proof/work/creator_spike/SW-S3/results.json (`rule.write_results`).

    python3 tools/proof/creator_spike/mouth_spike.py
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import rule  # noqa: E402

ROOT = HERE.parents[2]
SAMPLE = ROOT / "tools/proof/media/creator/S-PC2"
RATE_RULE = 4.0
RECORDED = {"1080p30": 10.30, "4k30": 8.88}  # CJ-S2's recorded realtime at long side 720


def main():
    computed, recorded, match = rule.check_rule("SW-S3")
    rate_met = all(value >= RATE_RULE for value in RECORDED.values())
    print(f"SW-S3 rate: CJ-S2's recorded {RECORDED['1080p30']:.2f}× (1080p30) and "
          f"{RECORDED['4k30']:.2f}× (4K30) against {RATE_RULE}×: "
          f"{'met' if rate_met else 'NOT met'}")
    if SAMPLE.exists():
        agreement = "not run: S-PC2 is present but this head measures no agreement yet"
        print(f"SW-S3 agreement: {agreement}")
    else:
        agreement = "skipped: S-PC2 absent, owed"
        print("SKIPPED the agreement arm: S-PC2 is not in tools/proof/media/creator/ (owed)")
    path = rule.write_results("SW-S3", {
        "rate_rule": RATE_RULE, "rate_recorded": RECORDED, "rate_met": rate_met,
        "agreement": agreement, "band": "middle (the owner's answer, 2026-11-01)",
        "floor": {"value": 0.02, "provisional": True}})
    print(f"results: {path}")
    return 0 if match and rate_met else 1


if __name__ == "__main__":
    sys.exit(main())
