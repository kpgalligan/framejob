#!/usr/bin/env python3
"""Road map "creator-jobs" VR2a1, spike VR-S2 — the planner's first numbers
(decides VR-22's headroom and VR-23's dead zone and speed, spec §11 VR-23).

    python3 tools/proof/creator_spike/reframe_spike.py              # the run, on AC
    python3 tools/proof/creator_spike/reframe_spike.py --selftest   # the rule only

It writes six canned inputs to `tools/proof/work/creator_spike/VR-S2/canned/`
(each a project JSON, the clip and its subjects), runs the core's ignored test
`core/tests/reframe_spike.rs` over them (`cargo test --release --test
reframe_spike -- --ignored --nocapture`, `FRAMEJOB_REFRAME_SPIKE` naming the
folder), which plans the 27 settings and writes `metrics.json`, then applies
the rule VR-23 fixed before the run and writes `results.json`
(`rule.write_results`) with one `VERDICT` line.

Every input: a 1080 x 1920 target at 30 fps from a 1920 x 1080 source (the
clip at scale 1, x = y = 0, no crop, forward x1 from 0) at zoom 1; samples
every 100 ms; a face box 0.08 x 0.14 of the picture at confidence 0.9; no
randomness. The still input's jitter is `0.005 x 1920 x sin(7.3 t)` across and
`0.005 x 1080 x cos(5.1 t)` down (the picture's width and height). S-TH1's,
T1's and T2's cached analyses do not exist yet (`samples/README.md`): skipped
by name and owed.
"""

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import rule  # noqa: E402

SPIKE = "VR-S2"
WORK = rule.WORK / SPIKE
TICKS = 600_000
STEP = TICKS // 10
FRAME = TICKS // 30
SOURCE = (1920, 1080)
TARGET = (1080, 1920)
FACE = (0.08, 0.14)
DEFAULT = (0.10, 0.5, 0.38)
DEAD_ZONES = (0.06, 0.10, 0.15)
FIRST_CAP, SECOND_CAP, FLOOR = 6.0, 8.0, 0.97


def log(message):
    print(message, flush=True)


# ---- the canned inputs -----------------------------------------------------

def face(cx, cy, scale=1.0):
    w, h = FACE[0] * scale, FACE[1] * scale
    return {"x": cx / SOURCE[0] - w / 2, "y": cy / SOURCE[1] - h / 2, "w": w, "h": h, "c": 0.9}


def canned(name, seconds, faces_at, shots=()):
    """`faces_at(t)` answers the face boxes at t seconds."""
    samples = []
    for n in range(seconds * 10):
        t = n / 10
        samples.append({"t": n * STEP, "faces": faces_at(t), "people": [], "salient": []})
    duration = seconds * TICKS
    project = {
        "canvas": {"width": TARGET[0], "height": TARGET[1], "fps": [30, 1]},
        "media": [{"id": 1, "path": f"/canned/{name}.mov", "kind": "video", "duration": duration,
                   "width": SOURCE[0], "height": SOURCE[1], "fps": [30, 1], "has_video": True}],
        "tracks": [{"id": 2}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": duration,
                   "source": {"kind": "media", "media": 1, "in": 0}}],
        "next_id": 4,
    }
    return {"name": name, "seconds": seconds, "from": list(SOURCE), "zoom": 1.0,
            "project": project, "clip": 3, "samples": samples, "shots": list(shots)}


def inputs():
    still = lambda x: (lambda t: [face(x, 432)])  # noqa: E731
    return [
        canned("a-pan", 20, lambda t: [face(400 + (1520 - 400) * t / 20, 432)]),
        canned("b-exit", 10, lambda t: ([face(960, 432)] if t < 4 else
                                         [] if t < 6 else [face(1100, 432)])),
        canned("c-two-faces", 20, lambda t: ([face(760, 432, math.sqrt(1.2)), face(1160, 432)]
                                             if t < 10 else
                                             [face(260, 432, math.sqrt(1.2)), face(1660, 432)])),
        canned("d-still", 60, lambda t: [face(960 + 0.005 * SOURCE[0] * math.sin(7.3 * t),
                                              432 + 0.005 * SOURCE[1] * math.cos(5.1 * t))]),
        canned("e-cuts", 30, lambda t: still(0.3 * SOURCE[0] if t < 10 else
                                             0.7 * SOURCE[0] if t < 20 else
                                             0.5 * SOURCE[0])(t),
               shots=(300 * FRAME, 600 * FRAME)),
        canned("f-card", 20, lambda t: []),
    ]


def write_inputs():
    folder = WORK / "canned"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.json"):
        old.unlink()
    digests = {}
    for doc in inputs():
        data = json.dumps(doc, sort_keys=True).encode()
        (folder / f"{doc['name']}.json").write_bytes(data)
        digests[doc["name"]] = hashlib.sha256(data).hexdigest()
    return digests


# ---- the rule (spec §11 VR-23) -----------------------------------------------

def pooled(setting):
    rows = setting["inputs"].values()
    counted = sum(r["counted"] for r in rows)
    contained = sum(r["contained"] for r in rows)
    moves = sum(r["moves"] for r in rows)
    minutes = sum(r["minutes"] for r in rows)
    return {"dead_zone": setting["dead_zone"], "speed": setting["speed"],
            "headroom": setting["headroom"], "counted": counted, "contained": contained,
            "containment": contained / counted if counted else 0.0, "moves": moves,
            "moves_per_minute": moves / minutes if minutes else 0.0}


def same(a, b):
    return abs(a - b) < 1e-9


def shared(row):
    """How many of (dead zone, speed, headroom) are the default's."""
    return sum(same(row[k], v) for k, v in zip(("dead_zone", "speed", "headroom"), DEFAULT))


def choose(rows, cap, dead_zone=None):
    """The highest containment at no more than `cap` moves a minute (at
    `dead_zone` when given); ties to fewer moves, then to the default — the
    setting sharing the most of its values, which is the default itself when
    it is among them — then to grid order."""
    keep = [(n, r) for n, r in enumerate(rows) if r["moves_per_minute"] <= cap + 1e-12
            and (dead_zone is None or same(r["dead_zone"], dead_zone))]
    if not keep:
        return None
    return min(keep, key=lambda nr: (-nr[1]["containment"], nr[1]["moves"],
                                     -shared(nr[1]), nr[0]))[1]


def step_below(dead_zone):
    index = min(range(len(DEAD_ZONES)), key=lambda i: abs(DEAD_ZONES[i] - dead_zone))
    return DEAD_ZONES[max(0, index - 1)]


def decide(metrics):
    rows = [pooled(s) for s in metrics["settings"]]
    first = choose(rows, FIRST_CAP)
    if first is not None and first["containment"] >= FLOOR:
        return {"arm": "first", "verdict": first, "rows": rows, "first": first}
    fixed = step_below(first["dead_zone"] if first is not None else DEFAULT[0])
    second = choose(rows, SECOND_CAP, fixed)
    return {"arm": "second" if second is not None else "stop", "verdict": second,
            "rows": rows, "first": first, "fixed_dead_zone": fixed}


def synthetic(table):
    """`table`: (dead zone, speed, headroom, contained of 100, moves in 1 min)."""
    return {"settings": [{"dead_zone": dz, "speed": sp, "headroom": hr,
                          "inputs": {"x": {"counted": 100, "contained": c, "moves": m,
                                           "minutes": 1.0}}}
                         for dz, sp, hr, c, m in table]}


def selftest():
    rows = [
        # The first arm: (0.15, 0.3, 0.33) is 98 % at 5 a minute.
        ("first arm", synthetic([(0.06, 0.5, 0.38, 99, 9), (0.15, 0.3, 0.33, 98, 5),
                                 (0.10, 0.5, 0.38, 97, 6)]),
         "first", (0.15, 0.3, 0.33)),
        # A tie at 98 % and 5 moves goes to the default.
        ("tie to the default", synthetic([(0.15, 0.3, 0.33, 98, 5), (0.10, 0.5, 0.38, 98, 5)]),
         "first", (0.10, 0.5, 0.38)),
        # A tie without the default goes to the most of its values: 0.38.
        ("tie toward the default", synthetic([(0.15, 0.8, 0.33, 98, 5),
                                              (0.15, 0.8, 0.38, 98, 5),
                                              (0.15, 0.8, 0.42, 98, 5)]),
         "first", (0.15, 0.8, 0.38)),
        # No setting at 6 or under: from 0.10, the dead zone 0.06 at 8.
        ("8-moves arm, none at 6", synthetic([(0.06, 0.5, 0.38, 90, 8), (0.06, 0.3, 0.38, 95, 9),
                                              (0.10, 0.5, 0.38, 99, 7)]),
         "second", (0.06, 0.5, 0.38)),
        # The winner under 97 %: one step below its 0.15, 0.10, at 8.
        ("8-moves arm, winner under 97 %", synthetic([(0.15, 0.5, 0.38, 96, 4),
                                                       (0.10, 0.8, 0.42, 93, 8),
                                                       (0.10, 0.3, 0.42, 99, 9)]),
         "second", (0.10, 0.8, 0.42)),
        # Nothing at the fixed dead zone (0.06) at 8 or under: STOP.
        ("STOP arm", synthetic([(0.06, 0.5, 0.38, 99, 9), (0.10, 0.5, 0.38, 99, 7)]),
         "stop", None),
    ]
    failed = 0
    for name, metrics, arm, chosen in rows:
        got = decide(metrics)
        verdict = got["verdict"]
        triple = (None if verdict is None else
                  (verdict["dead_zone"], verdict["speed"], verdict["headroom"]))
        ok = got["arm"] == arm and triple == chosen
        failed += not ok
        log(f"{'PASS' if ok else 'FAIL'} selftest {name}: arm {got['arm']} verdict {triple}")
    return failed


# ---- the run -----------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return 1 if selftest() else 0
    if selftest():
        raise SystemExit("the rule's selftest failed")
    rule.check_rule(SPIKE)
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, {host['uptime']}")
    if not host["ac_power"]:
        log("FAIL not on AC power")
        return 1
    digests = write_inputs()
    metrics_path = WORK / "metrics.json"
    if metrics_path.exists():
        metrics_path.unlink()
    env = dict(os.environ, FRAMEJOB_REFRAME_SPIKE=str(WORK))
    done = subprocess.run(["cargo", "test", "--release", "--test", "reframe_spike", "--",
                           "--ignored", "--nocapture"], cwd=rule.ROOT / "core", env=env,
                          capture_output=True, text=True)
    (WORK / "cargo.log").write_text(done.stdout + done.stderr)
    if done.returncode != 0 or not metrics_path.exists():
        log(f"FAIL the grid run: exit {done.returncode}, see {WORK / 'cargo.log'}")
        return 1
    metrics = json.loads(metrics_path.read_text())
    decided = decide(metrics)
    for row in decided["rows"]:
        log(f"dead zone {row['dead_zone']:.2f} speed {row['speed']:.1f} headroom "
            f"{row['headroom']:.2f}: containment {row['contained']}/{row['counted']} = "
            f"{row['containment']:.4f}, {row['moves']} moves, "
            f"{row['moves_per_minute']:.2f} a minute")
    owed = ["S-TH1's cached faces and subjects: not yet (samples/README.md)",
            "T1's and T2's cached analyses: not yet (the trials have not run)"]
    for line in owed:
        log(f"SKIP {line}")
    verdict = decided["verdict"]
    if verdict is None:
        line = (f"VERDICT STOP: no setting at dead zone {decided['fixed_dead_zone']} is at "
                f"{SECOND_CAP:g} moves a minute or under; FRAMING_TUNING stays "
                f"{DEFAULT}; put to the owner")
    else:
        line = (f"VERDICT arm={decided['arm']} dead_zone={verdict['dead_zone']:g} "
                f"dead_zone_height={0.8 * verdict['dead_zone']:g} speed={verdict['speed']:g} "
                f"headroom={verdict['headroom']:g} containment={verdict['containment']:.4f} "
                f"({verdict['contained']}/{verdict['counted']}) moves={verdict['moves']} "
                f"moves_per_minute={verdict['moves_per_minute']:.2f}")
    per_input = None
    if verdict is not None:
        for setting in metrics["settings"]:
            if all(same(setting[k], verdict[k]) for k in ("dead_zone", "speed", "headroom")):
                per_input = setting["inputs"]
    results = {"arm": decided["arm"], "verdict": verdict, "first": decided.get("first"),
               "fixed_dead_zone": decided.get("fixed_dead_zone"), "pooled": decided["rows"],
               "verdict_inputs": per_input, "owed": owed, "verdict_line": line,
               "canned_sha256": digests}
    written = rule.write_results(SPIKE, results)
    log(line)
    log(f"results: {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
