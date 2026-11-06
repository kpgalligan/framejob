#!/usr/bin/env python3
"""Road map "creator-jobs" CJ3, spike CJ-S2 — Vision on video (decides CJ-30
and CJ-32).

    python3 tools/proof/creator_spike/faces_spike.py              # the run, on AC
    python3 tools/proof/creator_spike/faces_spike.py --selftest   # the deciders only
    python3 tools/proof/creator_spike/faces_spike.py --sth1       # rules 3 and 6 on S-TH1 (CJ7)

The inputs are the face fixtures (`face_fixtures.py`); S-TH1…S-TH4 do not
exist yet, so their rows (rule 3's S-TH1 recall, rule 5's log and HLG
samples, rule 6's face share) skip by name and are owed. The probe is
`faces_spike.swift` (its `run` mode: the app's reader, a fresh request per
analysed frame on a fresh handler, each request pinned with
`AnalysisVision.pin` and its readback answered per stage).

- **Rule 1, per request**, at 10 a second and long side 1280 on
  `faces_moving.mov`: three runs on each of the CPU, the GPU and the Neural
  Engine — the rectangles request alone, then the landmarks request on each
  device behind the rectangles on their chosen device — each run's digest of
  that request's stored fields, its seconds and its pin readback;
  `faces_deciders.device_rule` (a device counts only when every stage reads
  back that device; the dropped ones listed with their readbacks). The CPU
  branch is tested against rule 2's 3× (the CPU's own runs' factor).
- **Rule 3**: recall on `faces_small.mov` at 720, 1280, 1920 and native on
  rule 1's devices (rectangles alone: landmarks find no box).
- **Rule 2**: decode + rectangles + landmarks at rule 3's size on rule 1's
  devices, three runs each on `faces_moving.mov` (1080p30) and
  `faces_moving_4k.mov` (4K30), medians; at 10 a second, then 5, then 2.5.
- **Rule 4**: at the chosen rate on 1080p30, the median landmarks seconds
  against the median rectangles seconds.
- **Rule 5**: no log or HLG sample → converted, owed.

Writes `tools/proof/work/creator_spike/CJ-S2/results.json` (`rule.write_results`)
and prints one `VERDICT` line.

**`--sth1`** (road map CJ7) runs rule 3 and rule 6 on S-TH1 (`sth1.py`),
rectangles alone on CJ-32's device (`neural_engine`) at 10 a second:
recall at 720, 1280, 1920 and native, the truth any face box on every sample
where `sth1.face_present` holds (one person), decided by `size_rule` on
S-TH1 and on `faces_small.mov`'s recorded recall (1.0000 at every size, CJ3's
record); rule 6, the share of 0–60 s samples with at least one face, at each
size (720 is CJ-32's). Writes `CJ-S2-STH1/results.json`; the earlier
`CJ-S2/results.json` is untouched.
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(HERE))
import face_fixtures  # noqa: E402
import faces_deciders as deciders  # noqa: E402
import rule  # noqa: E402
import sth1  # noqa: E402

RUNS = 3
TICKS = 600_000


def log(message):
    print(message, flush=True)


def load():
    return subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True,
                          text=True).stdout.strip()


def run(binary, movie, side, rate, rect, landmarks):
    started = time.monotonic()
    done = subprocess.run([str(binary), "run", str(movie), str(side), str(rate), rect,
                           landmarks], capture_output=True, text=True, timeout=7200)
    if done.returncode != 0:
        raise SystemExit(f"faces_spike run {Path(movie).name} {side} {rate} {rect} {landmarks}: "
                         f"{(done.stderr or done.stdout)[-600:]}")
    answer = json.loads(done.stdout.strip().splitlines()[-1])
    answer["_seconds"] = round(time.monotonic() - started, 2)
    answer["load"] = load()
    return answer


def summary(answer):
    return {k: answer[k] for k in ("pin", "sha256", "seconds", "realtime", "read", "load")}


def rule1(binary, movie):
    rect_rows, rect_runs = {}, {}
    for device in deciders.DEVICES:
        runs = [run(binary, movie, 1280, 10, device, "none") for _ in range(RUNS)]
        rect_runs[device] = [summary(r) for r in runs]
        rect_rows[device] = {"sha256": [r["sha256"]["rectangles"] for r in runs],
                             "seconds": [r["seconds"]["rectangles"] for r in runs],
                             "readback": [r["pin"]["rectangles"]["joined"] for r in runs]}
        for n, r in enumerate(runs):
            log(f"rule 1 rectangles {device} run {n + 1}: {r['seconds']['rectangles']:.2f} s "
                f"{r['realtime']:.2f}× sha256 {r['sha256']['rectangles'][:16]}… readback "
                f"{r['pin']['rectangles']['joined']} {r['pin']['rectangles']['stages']} "
                f"load {r['load']}")
    cpu_rt = deciders.median([r["realtime"] for r in rect_runs["cpu"]])
    rect = deciders.device_rule(rect_rows, cpu_realtime=cpu_rt)
    log(f"rule 1 rectangles: {rect}")
    if rect["device"] is None:
        raise SystemExit("no device reads back pinned for the rectangles request")
    lm_rows, lm_runs = {}, {}
    for device in deciders.DEVICES:
        runs = [run(binary, movie, 1280, 10, rect["device"], device) for _ in range(RUNS)]
        lm_runs[device] = [summary(r) for r in runs]
        lm_rows[device] = {"sha256": [r["sha256"]["landmarks"] for r in runs],
                           "seconds": [r["seconds"]["landmarks"] for r in runs],
                           "readback": [r["pin"]["landmarks"]["joined"] for r in runs]}
        for n, r in enumerate(runs):
            log(f"rule 1 landmarks {device} run {n + 1}: {r['seconds']['landmarks']:.2f} s "
                f"{r['realtime']:.2f}× sha256 {r['sha256']['landmarks'][:16]}… readback "
                f"{r['pin']['landmarks']['joined']} {r['pin']['landmarks']['stages']} "
                f"load {r['load']}")
    cpu_rt = deciders.median([r["realtime"] for r in lm_runs["cpu"]])
    landmarks = deciders.device_rule(lm_rows, cpu_realtime=cpu_rt)
    log(f"rule 1 landmarks: {landmarks}")
    if landmarks["device"] is None:
        raise SystemExit("no device reads back pinned for the landmarks request")
    return ({"rectangles": rect, "landmarks": landmarks},
            {"rectangles": rect_runs, "landmarks": lm_runs})


def sample_recall(answer, record, name):
    pairs = []
    for row in answer["samples"]:
        if row["pts"] < 0:
            continue
        truth = face_fixtures.truth(name, row["pts"] / TICKS, record)[0]
        pairs.append((truth, [f["box"] for f in row["faces"]]))
    return deciders.recall(pairs), len(pairs)


def rule3(binary, record, devices):
    movie = face_fixtures.path("faces_small")
    recall, rows = {}, {}
    for side in (*deciders.SIZES, "native"):
        answer = run(binary, movie, side, 10, devices["rectangles"], "none")
        recall[side], count = sample_recall(answer, record, "faces_small")
        rows[str(side)] = {"recall": recall[side], "samples": count, "read": answer["read"],
                           "seconds": answer["seconds"]}
        log(f"rule 3 faces_small at {side} (read {answer['read']}): recall {recall[side]:.4f} "
            f"over {count} samples")
    return deciders.size_rule(recall), rows


def rule2(binary, size, devices):
    realtime, rows = {}, {}
    for rate in deciders.RATES:
        realtime[rate] = {}
        for label, name in (("1080", "faces_moving"), ("4k", "faces_moving_4k")):
            runs = [run(binary, face_fixtures.path(name), size, rate, devices["rectangles"],
                         devices["landmarks"]) for _ in range(RUNS)]
            realtime[rate][label] = deciders.median([r["realtime"] for r in runs])
            rows[f"{rate}/{label}"] = [summary(r) for r in runs]
            factors = ", ".join(f"{r['realtime']:.2f}" for r in runs)
            log(f"rule 2 {name} at {size}, {rate}/s: {factors}× (median "
                f"{realtime[rate][label]:.2f}×) loads {[r['load'] for r in runs]}")
        verdict = deciders.rate_rule(realtime)
        if verdict["rate"] is not None and verdict["rate"] in realtime:
            return verdict, realtime, rows
    return deciders.rate_rule(realtime), realtime, rows


# CJ3's record: rule 3 on faces_small.mov, recall 1.0000 over 600 samples at every size.
FACES_SMALL_RECALL = {720: 1.0, 1280: 1.0, 1920: 1.0, "native": 1.0}
CJ32_DEVICE = "neural_engine"


def sth1_rows(answer):
    """(t, [found boxes]) per sample of a run on S-TH1."""
    return [(row["pts"] / TICKS, [f["box"] for f in row["faces"]])
            for row in answer["samples"] if row["pts"] >= 0]


def sth1_recall(rows):
    present = [found for t, found in rows if sth1.face_present(t)]
    return (sum(1 for found in present if found) / len(present) if present else None,
            len(present))


def sth1_share(rows, span):
    window = [found for t, found in rows if span[0] <= t < span[1]]
    return (sum(1 for found in window if found) / len(window) if window else None, len(window))


def run_sth1():
    movie = sth1.movie()
    if movie is None:
        log(f"SKIP CJ-S2 rules 3 and 6 on S-TH1: {sth1.missing_reason()}")
        return 0
    rule.check_rule("CJ-S2")
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, {host['uptime']}")
    binary = face_fixtures.spike_binary()
    recall, rows, share = {}, {}, {}
    for side in (*deciders.SIZES, "native"):
        answer = run(binary, movie, side, 10, CJ32_DEVICE, "none")
        found = sth1_rows(answer)
        recall[side], count = sth1_recall(found)
        share[str(side)] = {"0_60": sth1_share(found, (0.0, 60.0)),
                            "facing_0_60": sth1_share(found, sth1.FACING_0_60)}
        rows[str(side)] = {"recall": recall[side], "samples": count, "read": answer["read"],
                           "seconds": answer["seconds"], "realtime": answer["realtime"],
                           "pin": answer["pin"]["rectangles"]["joined"], "load": answer["load"],
                           "sha256": answer["sha256"]["rectangles"],
                           "samples_with_face": sum(1 for _, f in found if f),
                           "samples_all": len(found)}
        log(f"rule 3 S-TH1 at {side} (read {answer['read']}, pin "
            f"{rows[str(side)]['pin']}, {answer['seconds']['rectangles']:.1f} s rectangles, "
            f"{answer['realtime']:.2f}x): recall {recall[side]:.4f} over {count} samples; "
            f"rule 6 0-60 s {share[str(side)]['0_60'][0]:.4f} of {share[str(side)]['0_60'][1]}, "
            f"facing span {sth1.FACING_0_60} {share[str(side)]['facing_0_60'][0]:.4f} of "
            f"{share[str(side)]['facing_0_60'][1]} (load {answer['load']})")
    on_sth1 = deciders.size_rule(recall)
    on_small = deciders.size_rule(FACES_SMALL_RECALL)
    order = [*deciders.SIZES, "native"]
    size = max(on_sth1["size"], on_small["size"], key=order.index)
    face_share = share["720"]["0_60"][0]
    rule6 = "pass" if face_share >= 0.95 else "STOP"
    line = (f"VERDICT size={size} (S-TH1 {on_sth1['size']}, floor {on_sth1['floor']:.4f}; "
            f"faces_small {on_small['size']}) shipped=720 rule6={rule6} "
            f"face_share_0_60={face_share:.4f} (at 720)")
    results = {**sth1.record(), "device": CJ32_DEVICE, "rate": 10,
               "recall": {str(k): v for k, v in recall.items()}, "rows": rows,
               "size_sth1": on_sth1, "size_faces_small": on_small, "size": size,
               "face_share": share, "rule6": rule6, "verdict_line": line}
    written = rule.write_results("CJ-S2", results, folder="CJ-S2-STH1")
    log(line)
    log(f"results: {written}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--sth1", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return 1 if deciders.selftest() else 0
    if args.sth1:
        return run_sth1()
    if deciders.selftest():
        raise SystemExit("the deciders' selftest failed")
    rule.check_rule("CJ-S2")
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, {host['uptime']}")
    try:
        record = face_fixtures.make()
    except face_fixtures.Missing as missing:
        print(f"FAIL fixtures: {missing} is missing")
        return 1
    binary = face_fixtures.spike_binary()
    devices_verdict, device_runs = rule1(binary, face_fixtures.path("faces_moving"))
    devices = {k: v["device"] for k, v in devices_verdict.items()}
    size_verdict, size_rows = rule3(binary, record, devices)
    size = size_verdict["size"]
    rate_verdict, realtime, rate_rows = rule2(binary, size, devices)
    rate = rate_verdict["rate"]
    rect_s = deciders.median([r["seconds"]["rectangles"] for r in rate_rows[f"{rate}/1080"]])
    lm_s = deciders.median([r["seconds"]["landmarks"] for r in rate_rows[f"{rate}/1080"]])
    lm_verdict = deciders.landmarks_rule(rect_s, lm_s)
    log(f"rule 4: landmarks {lm_s:.2f} s against rectangles {rect_s:.2f} s: {lm_verdict}")
    reader = deciders.reader_rule([])
    owed = ["S-TH1 missing: rule 3's S-TH1 recall, rule 6's face share and F5 owed",
            "S-TH2…S-TH4 missing: rule 5's log and HLG rows owed (converted with none)",
            "rule 6 skipped: no S-TH1"]
    for line in owed:
        log(f"SKIP {line}")
    dropped = ";".join(f"{req}:" + ",".join(f"{d['device']}={'+'.join(d['readback'])}"
                                            for d in v["dropped"])
                       for req, v in devices_verdict.items() if v["dropped"]) or "none"
    line = (f"VERDICT rate={rate} size={size} landmarks={'yes' if lm_verdict['landmarks'] else 'no'}"
            f" rectangles={devices['rectangles']}(branch {devices_verdict['rectangles']['branch']})"
            f" landmarks_device={devices['landmarks']}"
            f"(branch {devices_verdict['landmarks']['branch']}) reader={reader['reader']}"
            f" compare={devices_verdict['rectangles']['compare']} dropped={dropped}"
            f" realtime_1080={realtime[rate]['1080']:.2f} realtime_4k={realtime[rate]['4k']:.2f}")
    results = {"devices": devices_verdict, "device_runs": device_runs, "size": size_verdict,
               "size_rows": size_rows, "rate": rate_verdict,
               "realtime": {str(k): v for k, v in realtime.items()}, "rate_rows": rate_rows,
               "landmarks": lm_verdict, "reader": reader, "owed": owed, "verdict_line": line,
               "fixtures": {k: v["sha256"] for k, v in record["fixtures"].items()},
               "cover_sha256": record["cover_sha256"]}
    written = rule.write_results("CJ-S2", results)
    log(line)
    log(f"results: {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
