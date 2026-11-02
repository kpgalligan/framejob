"""Road map "creator-jobs" CJ3: spike CJ-S2's rules 1–5 as pure functions.

Stdlib only, no I/O. `faces_spike.py` measures; these decide. Each function
is the rule's text in `designs/creator-jobs.md` ("Every spike, with its rule",
CJ-S2) applied to the rows the runner hands it:

- `device_rule(rows)` — rule 1 for ONE Vision request: a device is a
  candidate only when every run's pin readback, on every stage, is that
  device (no `auto`, no `unavailable`, no other device); each other device is
  dropped and listed with its readback. Of the candidates, the fastest (least
  median seconds of the request) whose three runs' digests are identical
  (branch 1); else the CPU when it is a candidate and meets rule 2's bar for
  10 a second on 1080p30 (`CPU_BAR`, branch 2); else the fastest candidate,
  every proof then comparing against the cache only (branch 3).
- `rate_rule(realtime)` — rule 2: 10 a second if decode + rectangles +
  landmarks run at least 3× real time on 1080p30 and 1.5× on 4K30; else the
  same bars at 5; else 2.5.
- `size_rule(recall)` — rule 3: the smallest long side of 720, 1280 and 1920
  whose face recall is at least 98 % of recall at native size; none → native.
- `landmarks_rule(rect_s, landmarks_s)` — rule 4: landmarks stay in `faces`
  when they cost at most 2× rectangles alone.
- `reader_rule(samples)` — rule 5: converted, unless on every log or HLG
  sample raw recall is at least 98 % of converted recall AND the converted
  reader costs more than 1.5× the direct one; with no such sample, converted.
- `overlaps(a, b)`, `recall(pairs)` — a found box overlapping a truth box
  (a positive area in common), and the share of samples with one.

`selftest()` runs one synthetic row per branch and answers the number of
failed rows.
"""

DEVICES = ("cpu", "gpu", "neural_engine")
CPU_BAR = 3.0           # rule 1's CPU branch: rule 2's bar for 10 a second on 1080p30
BAR_1080 = 3.0          # rule 2
BAR_4K = 1.5            # rule 2
RATES = (10, 5, 2.5)    # rule 2, in order
SIZES = (720, 1280, 1920)   # rule 3
RECALL_SHARE = 0.98     # rule 3, rule 5
LANDMARKS_MAX = 2.0     # rule 4
READER_COST = 1.5       # rule 5


def median(values):
    values = sorted(v for v in values if v is not None)
    n = len(values)
    if n == 0:
        return None
    return values[n // 2] if n % 2 else (values[n // 2 - 1] + values[n // 2]) / 2


def device_rule(rows, cpu_realtime=None):
    """`rows[device]` = {"sha256": [digests], "seconds": [the request's
    seconds], "readback": [each run's joined readback]}; `cpu_realtime` the
    CPU's median real-time factor at 10 a second on 1080p30. Answers {device,
    branch, candidates, dropped [{device, readback}], identical, seconds,
    compare}."""
    candidates, dropped, identical, seconds = [], [], {}, {}
    for device in DEVICES:
        row = rows.get(device) or {}
        readback = row.get("readback") or []
        if len(readback) < 3 or any(r != device for r in readback):
            dropped.append({"device": device, "readback": sorted(set(readback)) or ["none"]})
            continue
        shas = row.get("sha256") or []
        identical[device] = len(shas) >= 3 and len(set(shas)) == 1
        seconds[device] = median(row.get("seconds") or [])
        if seconds[device] is not None:
            candidates.append(device)
    same = [d for d in candidates if identical[d]]
    if same:
        device, branch = min(same, key=lambda d: seconds[d]), 1
    elif "cpu" in candidates and cpu_realtime is not None and cpu_realtime >= CPU_BAR:
        device, branch = "cpu", 2
    elif candidates:
        device, branch = min(candidates, key=lambda d: seconds[d]), 3
    else:
        device, branch = None, 3
    return {"device": device, "branch": branch, "candidates": candidates, "dropped": dropped,
            "identical": identical, "seconds": seconds,
            "compare": "cache_only" if branch == 3 else "cross_run"}


def rate_rule(realtime):
    """`realtime[rate]` = {"1080": factor, "4k": factor} (a rate absent: not
    measured). Answers {rate, met: {rate: bool}}; None when a rate that
    decides was not measured."""
    met = {}
    for rate in RATES[:-1]:
        row = realtime.get(rate)
        if row is None or row.get("1080") is None or row.get("4k") is None:
            return {"rate": None, "met": met, "unmeasured": rate}
        met[rate] = row["1080"] >= BAR_1080 and row["4k"] >= BAR_4K
        if met[rate]:
            return {"rate": rate, "met": met}
    return {"rate": RATES[-1], "met": met}


def size_rule(recall):
    """`recall` = {720: r, 1280: r, 1920: r, "native": r}. Answers {size,
    floor}; size an int of SIZES or "native"."""
    floor = RECALL_SHARE * recall["native"]
    for size in SIZES:
        if recall.get(size) is not None and recall[size] >= floor:
            return {"size": size, "floor": floor}
    return {"size": "native", "floor": floor}


def landmarks_rule(rect_s, landmarks_s):
    return {"landmarks": landmarks_s <= LANDMARKS_MAX * rect_s,
            "ratio": landmarks_s / rect_s if rect_s else None}


def reader_rule(samples):
    """`samples` = [{"raw_recall", "converted_recall", "cost"}] per log or
    HLG sample (`cost` the converted reader's per-frame cost over the direct
    one's). Answers {reader, owed}."""
    if not samples:
        return {"reader": "converted", "owed": True}
    raw = all(s["raw_recall"] >= RECALL_SHARE * s["converted_recall"] for s in samples) and \
        all(s["cost"] > READER_COST for s in samples)
    return {"reader": "raw" if raw else "converted", "owed": False}


def overlaps(a, b):
    """Two [x, y, w, h] boxes share a positive area."""
    w = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    h = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    return w > 0 and h > 0


def recall(pairs):
    """`pairs` = [(truth box, [found boxes])] over samples where a face is
    known present: the share with a found box overlapping the truth."""
    if not pairs:
        return None
    hit = sum(1 for truth, found in pairs if any(overlaps(truth, f) for f in found))
    return hit / len(pairs)


def selftest():
    failures = []

    def row(name, ok, detail=""):
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}")
        if not ok:
            failures.append(name)

    def runs(device, sha, secs, readback=None):
        return {"sha256": sha, "seconds": secs, "readback": readback or [device] * 3}

    base = {"cpu": runs("cpu", ["a"] * 3, [9, 9, 9]), "gpu": runs("gpu", ["b"] * 3, [3, 3, 3]),
            "neural_engine": runs("neural_engine", ["c"] * 3, [4, 4, 4])}
    v = device_rule(base)
    row("D1 branch 1: the fastest identical", v["device"] == "gpu" and v["branch"] == 1, str(v))
    shaky = dict(base, gpu=runs("gpu", ["b", "x", "b"], [3, 3, 3]))
    v = device_rule(shaky)
    row("D2 branch 1 skips a device whose runs differ", v["device"] == "neural_engine"
        and v["branch"] == 1, str(v))
    dropped = dict(base, gpu=runs("gpu", ["b"] * 3, [1, 1, 1], ["auto"] * 3))
    v = device_rule(dropped)
    row("D3 a device whose readback is not that device is dropped",
        v["device"] == "neural_engine" and v["dropped"] == [{"device": "gpu",
                                                             "readback": ["auto"]}], str(v))
    mixed = dict(base, gpu=runs("gpu", ["b"] * 3, [1, 1, 1], ["gpu", "cpu+gpu", "gpu"]))
    v = device_rule(mixed)
    row("D4 one run's mixed readback drops the device", "gpu" not in v["candidates"], str(v))
    none_same = {d: runs(d, ["p", "q", "r"], [s] * 3) for d, s in
                 (("cpu", 9), ("gpu", 3), ("neural_engine", 4))}
    v = device_rule(none_same, cpu_realtime=3.2)
    row("D5 branch 2: none identical, the CPU meets 3×", v["device"] == "cpu" and v["branch"] == 2,
        str(v))
    v = device_rule(none_same, cpu_realtime=2.9)
    row("D6 branch 3: none identical, the CPU short: the fastest, cache only",
        v["device"] == "gpu" and v["branch"] == 3 and v["compare"] == "cache_only", str(v))
    v = device_rule({d: runs(d, ["a"] * 3, [1] * 3, ["unavailable"] * 3) for d in DEVICES})
    row("D7 no candidate at all", v["device"] is None and len(v["dropped"]) == 3, str(v))

    v = rate_rule({10: {"1080": 3.0, "4k": 1.5}})
    row("R1 10 at exactly the bars", v["rate"] == 10, str(v))
    v = rate_rule({10: {"1080": 3.1, "4k": 1.4}, 5: {"1080": 6, "4k": 2.9}})
    row("R2 4K short at 10: 5", v["rate"] == 5, str(v))
    v = rate_rule({10: {"1080": 2.0, "4k": 1.0}, 5: {"1080": 2.9, "4k": 2.0}})
    row("R3 short at 5: 2.5", v["rate"] == 2.5, str(v))
    v = rate_rule({10: {"1080": 2.0, "4k": 1.0}})
    row("R4 5 unmeasured: undecided", v["rate"] is None and v["unmeasured"] == 5, str(v))

    v = size_rule({720: 0.98, 1280: 1.0, 1920: 1.0, "native": 1.0})
    row("S1 720 at exactly 98 %", v["size"] == 720, str(v))
    v = size_rule({720: 0.97, 1280: 0.99, 1920: 1.0, "native": 1.0})
    row("S2 720 short: 1280", v["size"] == 1280, str(v))
    v = size_rule({720: 0.5, 1280: 0.6, 1920: 0.7, "native": 1.0})
    row("S3 none: native", v["size"] == "native", str(v))

    row("L1 landmarks at exactly 2× stay", landmarks_rule(2.0, 4.0)["landmarks"])
    row("L2 landmarks past 2× move", not landmarks_rule(2.0, 4.01)["landmarks"])

    row("V1 no log or HLG sample: converted, owed", reader_rule([]) == {"reader": "converted",
                                                                        "owed": True})
    row("V2 raw recall close and converted dear: raw",
        reader_rule([{"raw_recall": 0.98, "converted_recall": 1.0, "cost": 1.6}])["reader"]
        == "raw")
    row("V3 converted cheap: converted",
        reader_rule([{"raw_recall": 1.0, "converted_recall": 1.0, "cost": 1.5}])["reader"]
        == "converted")
    row("V4 raw recall short: converted",
        reader_rule([{"raw_recall": 0.9, "converted_recall": 1.0, "cost": 3}])["reader"]
        == "converted")

    row("O1 overlap", overlaps([0, 0, 0.5, 0.5], [0.4, 0.4, 0.5, 0.5]))
    row("O2 touching is not overlap", not overlaps([0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5]))
    row("O3 recall", recall([([0, 0, 1, 1], [[0.5, 0.5, 0.1, 0.1]]), ([0, 0, 0.1, 0.1], [])])
        == 0.5)
    print(f"selftest: {len(failures)} failed")
    return len(failures)
