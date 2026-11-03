"""Road map "creator-jobs" VR1: spike VR-S1's rules, and CJ-S2's rules 1 and 3
as VR1 re-runs them for the `subjects` requests, as pure functions.

Stdlib only, no I/O. `subjects_spike.py` measures; these decide. Each function
is the rule's text in `designs/creator-jobs.md` ("Every spike, with its rule",
VR-S1 and CJ-S2) applied to the rows the runner hands it:

- `device_rule(rows)` — CJ-S2 rule 1 for ONE Vision request, unchanged:
  `faces_deciders.device_rule` (a device counts only when every run's every
  stage reads back that device; the fastest whose three digests are equal).
- `rate_rule(realtime)` — VR-S1 rule 1: `faces`' rate (10 a second) if decode
  plus both requests, at `faces`' frame size (720), run at least 4× real time
  on 1080p30 AND on 4K30; else every other `faces` sample (5 a second).
- `size_rule(recall)` — CJ-S2 rule 3 as the spec reads it for VR1: 720 when
  person recall at 720 is at least 98 % of recall at native size on
  `faces_small.mov`; else 1440 (VR-S1 rule 2's size). Rule 2 itself (S-TH1)
  is owed.
- `identical_rule(runs)` — VR-S1 rule 3: three runs on the pinned devices give
  byte-identical files, here the two requests' digests of every run; else
  `stop` (the owner is asked, with the digests).
- `contains(box, point)`, `centre(box)`, `centre_recall(pairs)` — a person box
  containing the truth face's centre (V1's measure), and the share of samples
  with one.

`selftest()` runs one synthetic row per branch and answers the number of
failed rows.
"""

import faces_deciders

DEVICES = faces_deciders.DEVICES
median = faces_deciders.median
device_rule = faces_deciders.device_rule

FACES_RATE = 10         # AnalysisFaces.rate (CJ-30)
FACES_SIZE = 720        # AnalysisFaces.longSide (CJ-30)
BIG_SIZE = 1440         # VR-S1 rule 2's other size
BAR = 4.0               # VR-S1 rule 1, on 1080p30 and on 4K30
RECALL_SHARE = 0.98     # CJ-S2 rule 3


def rate_rule(realtime):
    """`realtime` = {"1080": median factor, "4k": median factor}. Answers
    {rate, every_other, met}."""
    met = (realtime.get("1080") is not None and realtime.get("4k") is not None
           and realtime["1080"] >= BAR and realtime["4k"] >= BAR)
    rate = FACES_RATE if met else FACES_RATE / 2
    return {"rate": rate, "every_other": not met, "met": met}


def size_rule(recall):
    """`recall` = {720: r, "native": r}. Answers {size, floor}."""
    floor = RECALL_SHARE * recall["native"]
    small = recall.get(FACES_SIZE)
    return {"size": FACES_SIZE if small is not None and small >= floor else BIG_SIZE,
            "floor": floor}


def identical_rule(runs):
    """`runs` = [{"people": digest, "salient": digest}] (three). Answers
    {identical, stop, digests}."""
    same = len(runs) >= 3 and all(
        len({r[key] for r in runs}) == 1 for key in ("people", "salient"))
    return {"identical": same, "stop": not same,
            "digests": {key: [r[key] for r in runs] for key in ("people", "salient")}}


def centre(box):
    return (box[0] + box[2] / 2, box[1] + box[3] / 2)


def contains(box, point):
    """[x, y, w, h] holds the point (edges included)."""
    return box[0] <= point[0] <= box[0] + box[2] and box[1] <= point[1] <= box[1] + box[3]


def centre_recall(pairs):
    """`pairs` = [(truth face box, [person boxes])]: (hits, samples, share)."""
    if not pairs:
        return 0, 0, None
    hits = sum(1 for truth, found in pairs if any(contains(f, centre(truth)) for f in found))
    return hits, len(pairs), hits / len(pairs)


def selftest():
    failures = []

    def row(name, ok, detail=""):
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}")
        if not ok:
            failures.append(name)

    v = rate_rule({"1080": 4.0, "4k": 4.0})
    row("R1 both at exactly 4×: faces' rate", v["rate"] == 10 and not v["every_other"], str(v))
    v = rate_rule({"1080": 9.0, "4k": 3.99})
    row("R2 4K short: every other sample", v["rate"] == 5 and v["every_other"], str(v))
    v = rate_rule({"1080": 3.99, "4k": 9.0})
    row("R3 1080 short: every other sample", v["rate"] == 5, str(v))
    v = rate_rule({"1080": 9.0})
    row("R4 4K unmeasured: every other sample", v["rate"] == 5, str(v))

    v = size_rule({720: 0.98, "native": 1.0})
    row("S1 720 at exactly 98 %", v["size"] == 720, str(v))
    v = size_rule({720: 0.97, "native": 1.0})
    row("S2 720 short: 1440", v["size"] == 1440, str(v))
    v = size_rule({720: 0.0, "native": 0.0})
    row("S3 nothing found at either: 720", v["size"] == 720, str(v))

    same = [{"people": "a", "salient": "b"}] * 3
    row("I1 three equal runs", identical_rule(same)["identical"])
    v = identical_rule([{"people": "a", "salient": "b"}, {"people": "a", "salient": "c"},
                        {"people": "a", "salient": "b"}])
    row("I2 one salient digest differs: stop", v["stop"], str(v))
    v = identical_rule([{"people": "a", "salient": "b"}] * 2)
    row("I3 two runs only: stop", v["stop"], str(v))

    row("C1 a box holds its centre point", contains([0.1, 0.1, 0.2, 0.2], (0.2, 0.2)))
    row("C2 an edge counts", contains([0.1, 0.1, 0.2, 0.2], (0.3, 0.3)))
    row("C3 outside", not contains([0.1, 0.1, 0.2, 0.2], (0.31, 0.2)))
    hits, n, share = centre_recall([([0.4, 0.4, 0.2, 0.2], [[0, 0, 1, 1]]),
                                    ([0.4, 0.4, 0.2, 0.2], [[0, 0, 0.3, 0.3]]),
                                    ([0.4, 0.4, 0.2, 0.2], [])])
    row("C4 recall over three samples", (hits, n) == (1, 3) and abs(share - 1 / 3) < 1e-12,
        str((hits, n, share)))

    print(f"faces_deciders' device rows (CJ-S2 rule 1, reused):")
    failed = faces_deciders.selftest()
    if failed:
        failures.append(f"faces_deciders {failed}")
    print(f"selftest: {len(failures)} failed")
    return len(failures)
