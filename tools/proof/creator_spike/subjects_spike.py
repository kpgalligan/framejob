#!/usr/bin/env python3
"""Road map "creator-jobs" VR1, spike VR-S1 — people and saliency on video
(decides VR-11; with CJ-S2's rules 1 and 3 re-run for the `subjects` requests).

    python3 tools/proof/creator_spike/subjects_spike.py              # the run, on AC
    python3 tools/proof/creator_spike/subjects_spike.py --selftest   # the deciders only

The inputs are the face fixtures (`face_fixtures.py`: `faces_moving.mov`,
`faces_moving_4k.mov`, `faces_small.mov`, `subjects_moving.mov`); S-TH1 and
S-TH4 do not exist yet, so VR-S1 rules 2, 4 and 5 and CJ-S2 rule 5 skip by name
and are owed. The probe is `subjects_spike.swift` (its `run` mode: the app's
reader, a fresh person request — revision 2, `upperBodyOnly` true, spec §11
VR-4 as VR-10 amends it — and a fresh saliency request per analysed frame on
one fresh handler, each pinned with `AnalysisVision.pin`).

- **CJ-S2 rule 1, per request**, at 10 a second and long side 720 on
  `faces_moving.mov`: three runs of each request alone on each of the CPU, the
  GPU and the Neural Engine, its digest, Vision seconds and pin readback;
  `subjects_deciders.device_rule`.
- **Size** (CJ-S2 rule 3 as VR1 reads it): person recall on `faces_small.mov`
  at 720 and native, on rule 1's devices; 720 unless 720 is under 98 % of
  native, then 1440.
- **VR-S1 rule 1**: decode + both requests at the size, three runs each on
  `faces_moving.mov` (1080p30) and `faces_moving_4k.mov` (4K30), medians; both
  at least 4× → 10 a second, else every other `faces` sample.
- **VR-S1 rule 3**: three runs of both requests on the pinned devices at the
  rate and size, on `faces_moving.mov`: every digest equal, else STOP.
- **Person recall** (V1's measure, a person box containing the truth face's
  centre) on `faces_moving.mov` and on `subjects_moving.mov`'s two men, in
  upper-body mode and, as a comparison row (`whole`), whole-body mode.

Writes `tools/proof/work/creator_spike/VR-S1/results.json`
(`rule.write_results`) and prints one `VERDICT` line.

**`--sth1 [--addon-dir DIR]`** (road map CJ7) runs VR-S1 rules 2 and 4 on
S-TH1 (`sth1.py`), both requests on VR-11's Neural Engine at 10 a second,
upper body (VR-4 as VR-10 amends it):
- rule 2: person recall (any person box) on every `sth1.face_present` sample
  at 720 and at 1440; 1440 if 720's is more than 1 point under;
- rule 4's turned-away half: the share of `look_away` samples with a person
  box on `IMG_0181.MOV`;
- rule 4's side-on half on the add-on (`sth1.addon(DIR)`): `faces_spike`'s
  probe at 720 on the Neural Engine finds the profile stretch
  (`sth1.profile_span`, |yaw| ≥ π/4 − 0.01 or no face), autorotated `fps=1`
  frames from 3 s before to 3 s after it are written for reading, and the
  share is the person-box share over the stretch's samples. With no add-on
  the half skips by name, owed on S-TH1's side-on add-on.
Rule 4's verdict pools both halves when both ran, else the turned-away half
alone, labelled. Writes `VR-S1-STH1/results.json`.
"""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(HERE))
import face_fixtures  # noqa: E402
import rule  # noqa: E402
import sth1  # noqa: E402
import subjects_deciders as deciders  # noqa: E402
import swift_build  # noqa: E402

RUNS = 3
TICKS = 600_000
WORK = rule.WORK / "subjects"


def log(message):
    print(message, flush=True)


def load():
    return subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True,
                          text=True).stdout.strip()


def binary():
    """`subjects_spike.swift` over `app/Sources`, optimised."""
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "subjects_spike.swift", entry)
    out = WORK / "subjects-spike"
    swift_build.build(sources=[*swift_build.app_sources(), entry], output=out, optimize=True)
    return out


def run(probe, movie, side, rate, people, salient, whole=False):
    started = time.monotonic()
    argv = [str(probe), "run", str(movie), str(side), str(rate), people, salient]
    if whole:
        argv.append("whole")
    done = subprocess.run(argv, capture_output=True, text=True, timeout=7200)
    if done.returncode != 0:
        raise SystemExit(f"subjects_spike {' '.join(argv[1:])}: "
                         f"{(done.stderr or done.stdout)[-600:]}")
    answer = json.loads(done.stdout.strip().splitlines()[-1])
    answer["_seconds"] = round(time.monotonic() - started, 2)
    answer["load"] = load()
    return answer


def summary(answer):
    return {k: answer[k] for k in ("pin", "sha256", "seconds", "realtime", "read", "load",
                                   "upper_body_only")}


def rule1(probe, movie):
    verdicts, all_runs = {}, {}
    for request in ("people", "salient"):
        rows, kept = {}, {}
        for device in deciders.DEVICES:
            pair = (device, "none") if request == "people" else ("none", device)
            runs = [run(probe, movie, deciders.FACES_SIZE, deciders.FACES_RATE, *pair)
                    for _ in range(RUNS)]
            kept[device] = [summary(r) for r in runs]
            rows[device] = {"sha256": [r["sha256"][request] for r in runs],
                            "seconds": [r["seconds"]["vision"] for r in runs],
                            "readback": [r["pin"][request]["joined"] for r in runs],
                            "realtime": [r["realtime"] for r in runs]}
            for n, r in enumerate(runs):
                log(f"rule 1 {request} {device} run {n + 1}: {r['seconds']['vision']:.2f} s "
                    f"{r['realtime']:.2f}× sha256 {r['sha256'][request][:16]}… readback "
                    f"{r['pin'][request]['joined']} {r['pin'][request]['stages']} "
                    f"load {r['load']}")
        cpu_rt = deciders.median(rows["cpu"]["realtime"])
        verdicts[request] = deciders.device_rule(rows, cpu_realtime=cpu_rt)
        all_runs[request] = kept
        log(f"rule 1 {request}: {verdicts[request]}")
        if verdicts[request]["device"] is None:
            raise SystemExit(f"no device reads back pinned for the {request} request")
    return verdicts, all_runs


def recall_of(answer, record, name, face):
    """V1's measure over the samples that read a frame: (hits, samples, share)."""
    pairs = []
    for row in answer["samples"]:
        if row["pts"] < 0:
            continue
        truth = face_fixtures.truth(name, row["pts"] / TICKS, record)[face]
        pairs.append((truth, [p["box"] for p in row["people"]]))
    return deciders.centre_recall(pairs)


def size(probe, record, devices):
    movie = face_fixtures.path("faces_small")
    recall, rows = {}, {}
    for side in (deciders.FACES_SIZE, "native"):
        answer = run(probe, movie, side, deciders.FACES_RATE, devices["people"],
                     devices["salient"])
        hits, n, share = recall_of(answer, record, "faces_small", 0)
        recall[side] = share
        rows[str(side)] = {"hits": hits, "samples": n, "recall": share, "read": answer["read"]}
        log(f"size faces_small at {side} (read {answer['read']}): person recall {hits}/{n} "
            f"= {share}")
    return deciders.size_rule(recall), rows


def rate(probe, side, devices):
    realtime, rows, kept = {}, {}, {}
    for label, name in (("1080", "faces_moving"), ("4k", "faces_moving_4k")):
        runs = [run(probe, face_fixtures.path(name), side, deciders.FACES_RATE,
                    devices["people"], devices["salient"]) for _ in range(RUNS)]
        realtime[label] = deciders.median([r["realtime"] for r in runs])
        rows[label] = [summary(r) for r in runs]
        kept[label] = runs
        factors = ", ".join(f"{r['realtime']:.2f}" for r in runs)
        log(f"VR-S1 rule 1 {name} at {side}, 10/s: {factors}× (median {realtime[label]:.2f}×) "
            f"loads {[r['load'] for r in runs]}")
    return deciders.rate_rule(realtime), realtime, rows, kept


PEOPLE_SHARE = 0.90     # VR-S1 rule 4
VR11_DEVICE = "neural_engine"


def people_rows(answer):
    """(t, person found) per sample that read a frame."""
    return [(row["pts"] / TICKS, bool(row["people"])) for row in answer["samples"]
            if row["pts"] >= 0]


def share(rows, keep):
    kept = [found for t, found in rows if keep(t)]
    return {"hits": sum(kept), "samples": len(kept),
            "share": sum(kept) / len(kept) if kept else None}


def side_on(probe, addon):
    """Rule 4's side-on half on the add-on, or (None, reason)."""
    import faces_spike
    faces = faces_spike.run(face_fixtures.spike_binary(), addon, deciders.FACES_SIZE,
                            deciders.FACES_RATE, VR11_DEVICE, "none")
    samples = [{"t": row["pts"] / TICKS, "faces": [{"yaw": f.get("yaw")} for f in row["faces"]]}
               for row in faces["samples"] if row["pts"] >= 0]
    yaws = {"frontal": sum(1 for s in samples if any(
                f["yaw"] is not None and abs(f["yaw"]) < sth1.PROFILE_YAW for f in s["faces"])),
            "no_face": sum(1 for s in samples if not s["faces"]), "samples": len(samples)}
    span = sth1.profile_span(samples)
    if span is None:
        return None, f"no profile stretch found in {addon.name}", {"yaw_counts": yaws}
    frames = rule.WORK / "sth1_addon_frames"
    frames.mkdir(parents=True, exist_ok=True)
    start = max(0.0, span[0] - 3)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{start:.2f}", "-i", str(addon),
                    "-t", f"{span[1] + 3 - start:.2f}", "-vf", "fps=1,scale=480:-2",
                    str(frames / "a%03d.jpg")], check=True)
    answer = run(probe, addon, deciders.FACES_SIZE, deciders.FACES_RATE, VR11_DEVICE,
                 VR11_DEVICE)
    row = share(people_rows(answer), lambda t: span[0] <= t <= span[1])
    log(f"rule 4 side-on: {addon.name}, profile span {span[0]:.1f}–{span[1]:.1f} s "
        f"(no face, or every face |yaw| >= {sth1.PROFILE_YAW:.4f}); yaw counts {yaws}; frames "
        f"{start:.1f}–{span[1] + 3:.1f} s in {frames}; person {row['hits']}/{row['samples']}")
    return row, None, {"file": addon.name, "span": span, "yaw_counts": yaws,
                       "frames": str(frames), "frames_from": start}


def run_sth1(addon_dir):
    movie = sth1.movie()
    if movie is None:
        log(f"SKIP VR-S1 rules 2 and 4 on S-TH1: {sth1.missing_reason()}")
        return 0
    rule.check_rule("VR-S1")
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, {host['uptime']}")
    probe = binary()
    runs, recall = {}, {}
    for side in (deciders.FACES_SIZE, deciders.BIG_SIZE):
        answer = run(probe, movie, side, deciders.FACES_RATE, VR11_DEVICE, VR11_DEVICE)
        rows = people_rows(answer)
        recall[side] = share(rows, sth1.face_present)
        runs[side] = {"summary": summary(answer), "recall": recall[side],
                      "look_away": share(rows, lambda t: sth1.in_beat(t, "look_away")),
                      "beats": {name: share(rows, lambda t, n=name: sth1.in_beat(t, n))
                                for name in sth1.BEATS},
                      "absent": {name: share(rows, lambda t, s=span: s[0] <= t <= s[1])
                                 for name, span in sth1.ABSENT.items()}}
        log(f"rule 2 S-TH1 at {side} (read {answer['read']}, {answer['realtime']:.2f}x, pins "
            f"{answer['pin']['people']['joined']}/{answer['pin']['salient']['joined']}, load "
            f"{answer['load']}): person recall {recall[side]['hits']}/{recall[side]['samples']}"
            f" = {recall[side]['share']:.4f}; beats {runs[side]['beats']}; absent "
            f"{runs[side]['absent']}")
    small, big = recall[deciders.FACES_SIZE]["share"], recall[deciders.BIG_SIZE]["share"]
    size = deciders.BIG_SIZE if big - small > 0.01 else deciders.FACES_SIZE
    turned = runs[deciders.FACES_SIZE]["look_away"]
    try:
        addon = sth1.addon(addon_dir)
    except SystemExit as ambiguous:
        addon, skip = None, str(ambiguous)
    else:
        skip = None if addon else "owed on S-TH1's side-on add-on"
    side_row, side_info = None, {}
    if addon is not None:
        side_row, skip, side_info = side_on(probe, addon)
    if skip:
        log(f"SKIP rule 4 side-on: {skip}")
    if side_row is not None:
        hits, n = turned["hits"] + side_row["hits"], turned["samples"] + side_row["samples"]
        pooled, basis = hits / n, "pooled turned-away and side-on"
    else:
        pooled, basis = turned["share"], "turned-away alone (side-on owed)"
    rule4 = "people stay" if pooled >= PEOPLE_SHARE else "STOP"
    line = (f"VERDICT size={size} shipped=720 recall_720={small:.4f} recall_1440={big:.4f} "
            f"rule4={rule4} share={pooled:.4f} ({basis}) turned_away={turned['hits']}/"
            f"{turned['samples']} side_on="
            + (f"{side_row['hits']}/{side_row['samples']}" if side_row else "skipped"))
    results = {**sth1.record(), "device": VR11_DEVICE, "rate": deciders.FACES_RATE,
               "runs": {str(k): v for k, v in runs.items()}, "size": size,
               "turned_away": turned, "side_on": side_row, "side_on_info": side_info,
               "side_on_skip": skip, "rule4": rule4, "rule4_share": pooled,
               "rule4_basis": basis, "verdict_line": line}
    written = rule.write_results("VR-S1", results, folder="VR-S1-STH1")
    log(line)
    log(f"results: {written}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--sth1", action="store_true")
    parser.add_argument("--addon-dir")
    args = parser.parse_args(argv)
    if args.selftest:
        return 1 if deciders.selftest() else 0
    if args.sth1:
        return run_sth1(args.addon_dir)
    if deciders.selftest():
        raise SystemExit("the deciders' selftest failed")
    rule.check_rule("VR-S1")
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, {host['uptime']}")
    try:
        record = face_fixtures.make()
    except face_fixtures.Missing as missing:
        print(f"FAIL fixtures: {missing} is missing")
        return 1
    probe = binary()
    devices_verdict, device_runs = rule1(probe, face_fixtures.path("faces_moving"))
    devices = {k: v["device"] for k, v in devices_verdict.items()}
    size_verdict, size_rows = size(probe, record, devices)
    side = size_verdict["size"]
    rate_verdict, realtime, rate_rows, rate_runs = rate(probe, side, devices)
    chosen = rate_verdict["rate"]
    if chosen == deciders.FACES_RATE:
        same_runs = rate_runs["1080"]
    else:
        same_runs = [run(probe, face_fixtures.path("faces_moving"), side, chosen,
                         devices["people"], devices["salient"]) for _ in range(RUNS)]
    same = deciders.identical_rule([r["sha256"] for r in same_runs])
    log(f"VR-S1 rule 3 at {chosen}/s, {side}: {same}")
    recall = {}
    upper = same_runs[0]
    hits, n, share = recall_of(upper, record, "faces_moving", 0)
    recall["faces_moving/upper"] = {"hits": hits, "samples": n, "recall": share}
    whole = run(probe, face_fixtures.path("faces_moving"), side, chosen, devices["people"],
                "none", whole=True)
    hits, n, share = recall_of(whole, record, "faces_moving", 0)
    recall["faces_moving/whole"] = {"hits": hits, "samples": n, "recall": share}
    for mode in ("upper", "whole"):
        answer = run(probe, face_fixtures.path("subjects_moving"), side, chosen,
                     devices["people"], "none", whole=mode == "whole")
        for face, label in ((0, "back"), (1, "front")):
            hits, n, share = recall_of(answer, record, "subjects_moving", face)
            recall[f"subjects_moving/{label}/{mode}"] = {"hits": hits, "samples": n,
                                                         "recall": share}
    for key, row in recall.items():
        log(f"person recall {key}: {row['hits']}/{row['samples']} = {row['recall']:.4f}")
    owed = ["VR-S1 rule 2 owed: no S-TH1 (the size is CJ-S2 rule 3's re-run on faces_small)",
            "VR-S1 rule 4 owed: no S-TH1 turned-away and side-on beats (people stay)",
            "VR-S1 rule 5 and CJ-S2 rule 5 owed: no S-TH4 or log sample (converted)",
            "V10 (S-TH4 person recall) owed"]
    for line in owed:
        log(f"SKIP {line}")
    line = (f"VERDICT rate={chosen:g} every_other={'yes' if rate_verdict['every_other'] else 'no'}"
            f" size={side} people={devices['people']}"
            f"(branch {devices_verdict['people']['branch']})"
            f" salient={devices['salient']}(branch {devices_verdict['salient']['branch']})"
            f" identical={'yes' if same['identical'] else 'NO-STOP'} reader=converted"
            f" realtime_1080={realtime['1080']:.2f} realtime_4k={realtime['4k']:.2f}"
            f" recall_faces_moving={recall['faces_moving/upper']['recall']:.4f}")
    results = {"devices": devices_verdict, "device_runs": device_runs, "size": size_verdict,
               "size_rows": size_rows, "rate": rate_verdict, "realtime": realtime,
               "rate_rows": rate_rows, "identical": same,
               "identical_runs": [summary(r) for r in same_runs], "recall": recall,
               "owed": owed, "verdict_line": line,
               "fixtures": {k: v["sha256"] for k, v in record["fixtures"].items()},
               "cover_sha256": record["cover_sha256"]}
    written = rule.write_results("VR-S1", results)
    log(line)
    log(f"results: {written}")
    return 1 if same["stop"] else 0


if __name__ == "__main__":
    sys.exit(main())
