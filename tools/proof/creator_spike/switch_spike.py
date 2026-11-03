#!/usr/bin/env python3
"""Spike SW-S4 (road map "creator-jobs" SW2a, spec §11 SW-21, SW-27): the
switch's numbers on speech made on the Mac.

`rule.check_rule("SW-S4")` first. Then F-TURNS (`f_turns.py`) and the probe's
`spike` mode (`switch_speaker_probe.swift`, built by
`switch_speaker_probe.build`): each of the six variants is opened as a
document, its caches written by the importer, read once, and planned over the
grid bleed_db {9, 12, 15, 18, 21} × dominance_db {4, 6, 8, 10, 12} ×
floor_margin_db {3, 6, 9}, SW-22's values held at the defaults. A setting
passes when, on every variant, the shot angles equal the manifest's and every
cut is on the frame grid within τ (147.3 ms) of onset − lead, except SW-S4's
named limit (the owner, 2026-11-03): b24_f45's shot 17 (b) may be late by at
most 99,313 ticks (165.5 ms); each cut passed by it is listed as `limited`.

The rule's excerpt arm (S-PC1's five minutes and its `turns.json`) is skipped
by name while `tools/proof/media/creator/S-PC1/` does not exist: owed.

The choice: the drafted setting (15, 8, 6) when it passes, else the passing
setting nearest it in grid steps (L1), ties in grid order. No passing setting
is the rule's STOP: every miss is recorded, and SW-21 or SW-22 (never τ) is
amended before SW2b's code.

Results: tools/proof/work/creator_spike/SW-S4/results.json (`rule.write_results`).

    python3 tools/proof/creator_spike/switch_spike.py
"""

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import rule  # noqa: E402
import switch_speaker_probe as probe  # noqa: E402

ROOT = HERE.parents[2]
EXCERPT = ROOT / "tools/proof/media/creator/S-PC1"
BLEEDS = [9.0, 12.0, 15.0, 18.0, 21.0]
DOMINANCES = [4.0, 6.0, 8.0, 10.0, 12.0]
MARGINS = [3.0, 6.0, 9.0]
DRAFT = (15.0, 8.0, 6.0)


def steps(a, b):
    return (abs(BLEEDS.index(a[0]) - BLEEDS.index(b[0]))
            + abs(DOMINANCES.index(a[1]) - DOMINANCES.index(b[1]))
            + abs(MARGINS.index(a[2]) - MARGINS.index(b[2])))


def main():
    computed, recorded, match = rule.check_rule("SW-S4")
    folder = probe.fturns()
    if folder is None:
        print("SKIPPED SW-S4: F-TURNS needs say's Samantha and Daniel")
        return 2
    binary, problem = probe.build(ROOT / "app/Sources", "spike")
    if binary is None:
        print(f"FAIL the probe builds: {problem}")
        return 1
    scratch = probe.WORK / "spike" / "scratch"
    scratch.mkdir(parents=True, exist_ok=True)
    run = subprocess.run([str(binary), "spike", str(folder), str(scratch)], capture_output=True,
                         text=True, timeout=3600)
    (probe.WORK / "spike" / "spike.log").write_text(run.stdout + run.stderr)
    rows = [json.loads(line[6:]) for line in run.stdout.splitlines() if line.startswith("spike {")]
    if run.returncode != 0 or not rows:
        print("FAIL the spike ran: " + (run.stdout + run.stderr)[-800:])
        return 1
    variants = sorted({row["variant"] for row in rows})
    settings = []
    for bleed in BLEEDS:
        for dominance in DOMINANCES:
            for margin in MARGINS:
                key = (bleed, dominance, margin)
                mine = [row for row in rows if (row["bleed_db"], row["dominance_db"],
                                                row["floor_margin_db"]) == key]
                settings.append({
                    "bleed_db": bleed, "dominance_db": dominance, "floor_margin_db": margin,
                    "pass": len(mine) == len(variants) and all(row["pass"] for row in mine),
                    "variants": {row["variant"]: {"pass": row["pass"], "misses": row["misses"],
                                                  "limited": row["limited"],
                                                  "errors_ms": row["errors_ms"]} for row in mine},
                })
    passing = [s for s in settings if s["pass"]]
    print(f"{len(passing)}/{len(settings)} settings pass on all {len(variants)} variants")
    for s in settings:
        failed = [name for name, v in s["variants"].items() if not v["pass"]]
        print(f"  bleed {s['bleed_db']:g} dominance {s['dominance_db']:g} margin "
              f"{s['floor_margin_db']:g}: {'PASS' if s['pass'] else 'miss ' + ', '.join(failed)}")
    chosen = None
    if passing:
        key = lambda s: (s["bleed_db"], s["dominance_db"], s["floor_margin_db"])  # noqa: E731
        chosen = min(passing, key=lambda s: (steps(key(s), DRAFT), settings.index(s)))
        print(f"CHOSEN bleed_db {chosen['bleed_db']:g}, dominance_db {chosen['dominance_db']:g}, "
              f"floor_margin_db {chosen['floor_margin_db']:g} "
              f"({steps(key(chosen), DRAFT)} grid steps from the draft)")
    else:
        print("STOP: no setting places every synthetic cut within τ")
    print("SKIPPED the excerpt arm: S-PC1 is not in tools/proof/media/creator/ (owed)"
          if not EXCERPT.exists() else "NOTE: S-PC1 exists, but its arm is not built in SW2a")
    path = rule.write_results("SW-S4", {
        "tau_ms": round((38_400 + 30_000 + 20_000) / 600, 3), "grid": {
            "bleed_db": BLEEDS, "dominance_db": DOMINANCES, "floor_margin_db": MARGINS},
        "draft": dict(zip(["bleed_db", "dominance_db", "floor_margin_db"], DRAFT)),
        "variants": variants, "settings": settings,
        "limit": {"variant": "b24_f45", "shot": 17, "angle": "b", "late_ticks": 99_313},
        "passing": len(passing), "chosen": None if chosen is None else {
            k: chosen[k] for k in ("bleed_db", "dominance_db", "floor_margin_db")},
        "excerpt": "skipped: S-PC1 absent, owed" if not EXCERPT.exists() else "not run"})
    print(f"results: {path}")
    return 0 if chosen and match else 1


if __name__ == "__main__":
    sys.exit(main())
