#!/usr/bin/env python3
"""Spike VR-S3's head (road map "creator-jobs" VR6a, spec §11 VR-62): face-to-mic agreement.

`rule.check_rule("VR-S3")` first. The rule takes the midpoint between the lowest true-pair
agreement and the highest swapped-pair agreement when they separate; its true pairs need S-PC3
(the owner's two-shot with a microphone each):

- **The S-PC3 arm**: skipped by name while `tools/proof/media/creator/S-PC3/` does not exist —
  owed; when it exists this head does not run it yet (owed), as `mouth_spike.py` does.
- **The still arm**: `face_fixtures.py`'s `subjects_moving.mov` (the two-person cover drifting
  over 1920 × 1080) through `faces_spike.swift run` at the `faces` kind's settings —
  `AnalysisFaces.rate` 10 a second, `longSide` 720, rectangles and landmarks on the Neural
  Engine — each sample's faces clamped into the picture as `FramingSubjects` clamps them, first
  eight kept, with `mouth` = gap ÷ width (finite, width > 0, gap ≥ 0); synthetic turns over the
  clip, A [0, 4 s), B [4, 8 s) … alternating; "true" is face 1 ↔ A and face 2 ↔ B.
  `core/tests/speaker_spike.rs` (ignored, `FRAMEJOB_SPEAKER_SPIKE` naming the folder) answers
  the agreements through `speaker_match`. A still's mouths never move, so this arm is the
  no-speech CONTROL: it cannot supply true pairs, and a control |r| ≥ 0.2 is recorded as such,
  not acted on.

`SPEAKER_AGREEMENT` stays 0.2, provisional, re-measured on S-PC3 (owed).

Results: tools/proof/work/creator_spike/VR-S3/results.json (`rule.write_results`).

    python3 tools/proof/creator_spike/speaker_spike.py
"""

import json
import math
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import face_fixtures  # noqa: E402
import rule  # noqa: E402

ROOT = HERE.parents[2]
SAMPLE = ROOT / "tools/proof/media/creator/S-PC3"
FOLDER = rule.WORK / "VR-S3"
TICKS = 600_000
RATE = 10                # AnalysisFaces.rate
LONG_SIDE = 720          # AnalysisFaces.longSide
DEVICE = "neural_engine"  # AnalysisFaces.rectanglesDevice, landmarksDevice
MAX_BOXES = 8            # FramingSubjects.maxBoxes
TURN = 4                 # seconds per synthetic turn
THRESHOLD = 0.2          # SPEAKER_AGREEMENT, provisional


def boxes(faces):
    """`FramingSubjects.boxes` with the mouth: clamped, the empty dropped, the first eight."""
    out = []
    for f in faces:
        x, y, w, h = f["box"]
        values = [x, y, w, h, f["conf"]]
        if not all(math.isfinite(v) for v in values):
            continue
        x0, y0 = max(0.0, x), max(0.0, y)
        x1, y1 = min(1.0, x + w), min(1.0, y + h)
        if not (x1 > x0 and y1 > y0):
            continue
        box = {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "c": min(1.0, max(0.0, f["conf"]))}
        gap, width = f.get("gap"), f.get("width")
        if gap is not None and width is not None and width > 0 and gap >= 0:
            box["mouth"] = gap / width
        out.append(box)
        if len(out) == MAX_BOXES:
            break
    return out


def still_arm():
    movie = face_fixtures.path("subjects_moving")
    face_fixtures.make()
    binary = face_fixtures.spike_binary()
    run = subprocess.run([str(binary), "run", str(movie), str(LONG_SIDE), str(RATE), DEVICE,
                          DEVICE], capture_output=True, text=True, timeout=7200)
    if run.returncode != 0:
        raise SystemExit(f"faces_spike run: {(run.stderr or run.stdout)[-600:]}")
    answer = json.loads(run.stdout.strip().splitlines()[-1])
    samples = [{"t": round(row["k"] * TICKS / RATE), "faces": boxes(row["faces"])}
               for row in answer["samples"] if row["pts"] >= 0]
    end = round(answer["source_s"] * TICKS)
    turns, n = [], 0
    while n * TURN * TICKS < end:
        turns.append({"from": n * TURN * TICKS, "to": min(end, (n + 1) * TURN * TICKS),
                      "mic": 1 if n % 2 == 0 else 2})
        n += 1
    FOLDER.mkdir(parents=True, exist_ok=True)
    (FOLDER / "input.json").write_text(json.dumps({"samples": samples, "turns": turns,
                                                   "mics": [1, 2]}))
    test = subprocess.run(["cargo", "test", "--release", "--test", "speaker_spike", "--",
                           "--ignored"], cwd=ROOT / "core", capture_output=True, text=True,
                          timeout=3600, env={**os.environ, "FRAMEJOB_SPEAKER_SPIKE": str(FOLDER)})
    if test.returncode != 0:
        raise SystemExit(f"speaker_spike.rs: {(test.stderr or test.stdout)[-600:]}")
    metrics = json.loads((FOLDER / "metrics.json").read_text())
    with_mouth = sum(1 for s in samples for b in s["faces"] if "mouth" in b)
    out = {"movie": str(movie), "samples": len(samples), "boxes_with_mouth": with_mouth,
           "turns": len(turns), "pin": answer.get("pin"), "metrics": metrics}
    if metrics.get("matched"):
        a = metrics["agreement"]
        true_pairs = [a[0][0], a[1][1]]
        swapped = [a[0][1], a[1][0]]
        out.update({"true_pairs": true_pairs, "swapped_pairs": swapped,
                    "control_at_or_over_threshold": [v for v in true_pairs + swapped
                                                     if abs(v) >= THRESHOLD]})
    return out


def main():
    computed, recorded, match = rule.check_rule("VR-S3")
    if SAMPLE.exists():
        pc3 = "not run: S-PC3 is present but this head measures no true pairs yet (owed)"
        print(f"VR-S3 S-PC3 arm: {pc3}")
    else:
        pc3 = "skipped: S-PC3 absent, owed"
        print("SKIPPED the S-PC3 arm: S-PC3 is not in tools/proof/media/creator/ (owed)")
    try:
        still = still_arm()
    except face_fixtures.Missing as missing:
        print(f"FAIL the still arm: {missing} is missing")
        return 1
    if still["metrics"].get("matched"):
        print(f"VR-S3 still arm (the no-speech control): {still['samples']} samples, "
              f"{still['boxes_with_mouth']} boxes with a mouth; true pairs "
              f"{[round(v, 4) for v in still['true_pairs']]}, swapped "
              f"{[round(v, 4) for v in still['swapped_pairs']]}; at or over {THRESHOLD}: "
              f"{[round(v, 4) for v in still['control_at_or_over_threshold']] or 'none'} "
              f"(recorded, not acted on)")
    else:
        print(f"VR-S3 still arm: fewer than two faces matched over {still['samples']} samples "
              f"(recorded)")
    path = rule.write_results("VR-S3", {
        "s_pc3": pc3, "still": still,
        "threshold": {"value": THRESHOLD, "provisional": True,
                      "why": "the rule's midpoint needs S-PC3's true pairs (owed)"}})
    print(f"results: {path}")
    return 0 if match else 1


if __name__ == "__main__":
    sys.exit(main())
