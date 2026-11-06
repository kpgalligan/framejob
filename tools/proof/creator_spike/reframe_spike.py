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
`0.005 x 1080 x cos(5.1 t)` down (the picture's width and height). T1's and
T2's cached analyses do not exist yet (`samples/README.md`): skipped by name
and owed.

`--sth1 --socket SOCK` (road map CJ7) imports S-TH1's movie (`sth1.movie()`)
into a scratch project on a running Release Frame Job, reads its `faces` and
`subjects` through `get_media_analysis` in 120 s windows, maps them to the
canned shape (from = the media's size, 3840 x 2160; a 1080 x 1920 target;
boxes clamped, eight a kind) and runs the grid twice under `VR-S2-STH1/`:
S-TH1 alone, then pooled with the six canned inputs; the pooled verdict is
set beside VR-23's shipped (0.15, 0.8, 0.38). Writes
`VR-S2-STH1/results.json`.
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


# ---- S-TH1 (road map CJ7) ------------------------------------------------------

SHIPPED = (0.15, 0.8, 0.38)     # VR-23 as VR-S2's verdict amended it
STH1_WINDOW = 120 * TICKS       # under CJ-34's cap
STH1_TARGET = (1080, 1920)
PER_KIND = 8                    # FramingSubjects: eight boxes a kind


def clamped(box, confidence):
    x0, y0 = max(0.0, box[0]), max(0.0, box[1])
    x1, y1 = min(1.0, box[0] + box[2]), min(1.0, box[1] + box[3])
    if x1 <= x0 or y1 <= y0:
        return None
    return {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "c": confidence or 0.0}


def boxes_of(rows):
    out = [b for b in (clamped(r["box"], r.get("confidence")) for r in rows) if b]
    return out[:PER_KIND]


def analysis(call, media, kind, duration):
    rows = []
    for lo in range(0, duration, STH1_WINDOW):
        arguments = {"media": media, "kind": kind, "from": lo,
                     "to": min(duration, lo + STH1_WINDOW)}
        for _ in range(60):
            try:
                rows += call("get_media_analysis", **arguments)["samples"]
                break
            except Exception as error:  # noqa: BLE001 — the wait's refusal: call again
                if "call again" not in str(error):
                    raise
        else:
            raise SystemExit(f"{kind} {lo}: not finished in 60 calls")
    return rows


def sth1_input(socket):
    """S-TH1's canned input from the app's cached `faces` and `subjects`."""
    sys.path.insert(0, str(HERE.parent))
    import mcp
    import sth1
    movie = sth1.movie()
    client = mcp.MCP(socket)
    package = WORK.parent / "VR-S2-STH1" / "sth1.framejob"
    package.parent.mkdir(parents=True, exist_ok=True)
    if package.exists():
        import shutil
        shutil.rmtree(package)
    client.call("new_project", path=str(package))

    def call(tool, **arguments):
        return client.call_with(tool, dict(arguments, project=str(package)))

    try:
        media = call("import_media", path=str(movie))["media"]
        snapshot = next(m for m in call("get_project")["project"]["media"] if m["id"] == media)
        duration = snapshot["duration"]
        faces = analysis(call, media, "faces", duration)
        subjects = {r["source"]: r for r in analysis(call, media, "subjects", duration)}
    finally:
        try:
            client.call("close_project", project=str(package), discard=True)
        except Exception:  # noqa: BLE001
            pass
    samples = []
    for row in faces:
        other = subjects.get(row["source"])
        if row.get("frame") is None or other is None or other.get("frame") is None:
            continue
        samples.append({"t": row["source"], "faces": boxes_of(row["faces"]),
                        "people": boxes_of(other["people"]),
                        "salient": boxes_of(other["salient"])})
    size = (int(snapshot["width"]), int(snapshot["height"]))
    project = {
        "canvas": {"width": STH1_TARGET[0], "height": STH1_TARGET[1], "fps": [30, 1]},
        "media": [{"id": 1, "path": "/canned/sth1.mov", "kind": "video", "duration": duration,
                   "width": size[0], "height": size[1], "fps": [30, 1], "has_video": True}],
        "tracks": [{"id": 2}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": duration,
                   "source": {"kind": "media", "media": 1, "in": 0}}],
        "next_id": 4,
    }
    doc = {"name": "sth1", "seconds": duration / TICKS, "from": list(size), "zoom": 1.0,
           "project": project, "clip": 3, "samples": samples, "shots": []}
    return doc, {"media_size": list(size), "duration": duration, "faces_rows": len(faces),
                 "samples": len(samples),
                 "with_face": sum(1 for s in samples if s["faces"]),
                 "with_person": sum(1 for s in samples if s["people"])}


def grid(folder, docs):
    canned = folder / "canned"
    canned.mkdir(parents=True, exist_ok=True)
    for old in canned.glob("*.json"):
        old.unlink()
    for doc in docs:
        (canned / f"{doc['name']}.json").write_bytes(json.dumps(doc, sort_keys=True).encode())
    metrics_path = folder / "metrics.json"
    if metrics_path.exists():
        metrics_path.unlink()
    env = dict(os.environ, FRAMEJOB_REFRAME_SPIKE=str(folder))
    done = subprocess.run(["cargo", "test", "--release", "--test", "reframe_spike", "--",
                           "--ignored", "--nocapture"], cwd=rule.ROOT / "core", env=env,
                          capture_output=True, text=True)
    (folder / "cargo.log").write_text(done.stdout + done.stderr)
    if done.returncode != 0 or not metrics_path.exists():
        raise SystemExit(f"FAIL the grid run: exit {done.returncode}, see {folder / 'cargo.log'}")
    return decide(json.loads(metrics_path.read_text()))


def line_of(label, decided):
    verdict = decided["verdict"]
    shipped = next(r for r in decided["rows"] if all(
        same(r[k], v) for k, v in zip(("dead_zone", "speed", "headroom"), SHIPPED)))
    if verdict is None:
        head = f"{label}: STOP at dead zone {decided['fixed_dead_zone']}"
    else:
        head = (f"{label}: arm={decided['arm']} dead_zone={verdict['dead_zone']:g} "
                f"speed={verdict['speed']:g} headroom={verdict['headroom']:g} containment="
                f"{verdict['containment']:.4f} ({verdict['contained']}/{verdict['counted']}) "
                f"moves_per_minute={verdict['moves_per_minute']:.2f}")
    return (head + f"; shipped {SHIPPED}: containment {shipped['containment']:.4f} "
            f"({shipped['contained']}/{shipped['counted']}), {shipped['moves_per_minute']:.2f} "
            f"moves a minute"), shipped


def run_sth1(socket):
    import sth1
    if sth1.movie() is None:
        log(f"SKIP VR-S2 on S-TH1: {sth1.missing_reason()}")
        return 0
    if not socket:
        raise SystemExit("--sth1 needs --socket of a running Release Frame Job")
    rule.check_rule(SPIKE)
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, {host['uptime']}")
    doc, read = sth1_input(socket)
    log(f"S-TH1 input: {read}")
    out = WORK.parent / "VR-S2-STH1"
    alone = grid(out / "alone", [doc])
    pooled_ = grid(out / "pooled", [*inputs(), doc])
    lines, shipped = {}, {}
    for label, decided in (("S-TH1 alone", alone), ("pooled", pooled_)):
        lines[label], shipped[label] = line_of(label, decided)
        log(lines[label])
    verdict = pooled_["verdict"]
    same_as_shipped = verdict is not None and all(
        same(verdict[k], v) for k, v in zip(("dead_zone", "speed", "headroom"), SHIPPED))
    line = (f"VERDICT pooled={'shipped' if same_as_shipped else 'CHANGED'} "
            + (f"({verdict['dead_zone']:g}, {verdict['speed']:g}, {verdict['headroom']:g})"
               if verdict else "STOP") + f" shipped={SHIPPED}")
    results = {**sth1.record(), "read": read, "shipped": SHIPPED,
               "alone": {k: alone.get(k) for k in ("arm", "verdict", "first", "fixed_dead_zone",
                                                  "rows")},
               "pooled": {k: pooled_.get(k) for k in ("arm", "verdict", "first",
                                                     "fixed_dead_zone", "rows")},
               "shipped_rows": shipped, "lines": lines, "verdict_line": line}
    written = rule.write_results(SPIKE, results, folder="VR-S2-STH1")
    log(line)
    log(f"results: {written}")
    return 0


# ---- the run -----------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--sth1", action="store_true")
    parser.add_argument("--socket")
    args = parser.parse_args(argv)
    if args.selftest:
        return 1 if selftest() else 0
    if args.sth1:
        if selftest():
            raise SystemExit("the rule's selftest failed")
        return run_sth1(args.socket)
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
