"""Road map "creator-jobs" FC3, spike FC-S1's rule as pure functions (verdict
FC-30), with `--selftest` rows (`python3 sound_deciders.py --selftest`).

- `group_rule`: a group is first-class when one threshold t ∈ {0.3 … 0.8},
  chosen on the odd-numbered labelled events (the best recall there that
  calls at most one window per 10 minutes of the speech-only and music
  inputs; ties to the higher t) and applied unchanged to the even-numbered
  ones, finds ≥ 70 % of them (a window ≥ t starting within ±1 s of the
  onset) and calls at most one per 10 minutes; fewer than 10 held-out
  events is weak by rule, and no events at all is weak.
- `window_rule`: the best laughter recall among the windows at ≥ 60× real
  time, ties to 1.5 s; when none reaches 60×, the fastest is kept (the one
  nearest the bar) and its figure recorded. The rule's text says "the
  slowest acceptable"; this branch keeps the fastest, and it has not arisen
  (every window ran far above 60× in both of FC-S1's runs).
- `agreement` (the owner's amendment, option (a), 2026-11-02): for every
  group, every input and every window length, each RISING crossing of 0.5
  (a window ≥ 0.5 after one < 0.5, or none) on one analyzer's side is
  matched when the other side has a rising crossing of the same group
  within one hop of its start time, OR the other side's value in either of
  the two windows the crossing lies between (the crossing's own, at t, and
  the one before, at t − hop) is within ±`VALUE_TOLERANCE` (0.1) of 0.5 —
  a tolerated crossing, listed. A None on the other side is not tolerated.
  It runs both ways; the stream analyzer agrees only when nothing is left
  unmatched. FC-S1's rule text ("event times agree … within one hop")
  stands; this defines its test.
- `agreement_strict`: attempt 1's metric, crossings only, kept for the
  record.

A window list is `[(start_seconds, value_or_None), …]` in time order.
"""

import sys

THRESHOLDS = (0.3, 0.4, 0.5, 0.6, 0.7, 0.8)
RECALL_BAR = 0.7
FALSE_PER_10_MIN = 1.0
HELD_OUT_MIN = 10
REALTIME_BAR = 60.0
ONSET_SLACK = 1.0
CROSSING = 0.5
PREFERRED_WINDOW = 1.5
VALUE_TOLERANCE = 0.1


def crossings(windows, level):
    """The start times of the rising crossings of `level`: a window ≥ level
    after one < level, or after none (a None value is below)."""
    out, below = [], True
    for start, value in windows:
        above = value is not None and value >= level
        if above and below:
            out.append(start)
        below = not above
    return out


def found(windows, onset, t):
    return any(value is not None and value >= t and abs(start - onset) <= ONSET_SLACK
               for start, value in windows)


def recall(windows, onsets, t):
    if not onsets:
        return None
    return sum(1 for onset in onsets if found(windows, onset, t)) / len(onsets)


def false_rate(negatives, t):
    """Rising crossings of t per 10 minutes over the speech-only and music
    inputs, `[(windows, seconds), …]`; None when there is no input."""
    seconds = sum(s for _, s in negatives)
    if seconds <= 0:
        return None
    calls = sum(len(crossings(w, t)) for w, _ in negatives)
    return calls * 600.0 / seconds


def group_rule(windows, onsets, negatives):
    """`onsets` the labelled event onsets in order (event 1 first)."""
    odd = onsets[0::2]
    even = onsets[1::2]
    if not onsets:
        return {"class": "weak", "why": "no labelled events", "threshold": None}
    best = None
    for t in THRESHOLDS:
        rate = false_rate(negatives, t)
        if rate is None or rate > FALSE_PER_10_MIN:
            continue
        r = recall(windows, odd, t)
        if best is None or r >= best[1]:
            best = (t, r)
    if best is None:
        return {"class": "weak", "why": "no threshold keeps false calls ≤ 1 per 10 min",
                "threshold": None}
    t = best[0]
    held = recall(windows, even, t)
    rate = false_rate(negatives, t)
    out = {"threshold": t, "odd_recall": best[1], "even_recall": held, "false_per_10_min": rate,
           "held_out": len(even)}
    if len(even) < HELD_OUT_MIN:
        out.update({"class": "weak", "why": f"{len(even)} held-out events (< {HELD_OUT_MIN})"})
    elif held is not None and held >= RECALL_BAR and rate <= FALSE_PER_10_MIN:
        out.update({"class": "first", "why": "recall and false calls within the rule"})
    else:
        out.update({"class": "weak", "why": "held-out recall under 70 %"})
    return out


def window_rule(realtime, laughter_recall):
    """`realtime` and `laughter_recall` keyed by window seconds (recall None
    without S-EV)."""
    fast = [w for w in realtime if realtime[w] >= REALTIME_BAR]
    if not fast:
        w = max(realtime, key=lambda k: realtime[k])
        return {"window": w, "branch": "none at 60x: the fastest kept", "realtime": realtime[w]}

    def score(w):
        r = laughter_recall.get(w)
        return -1.0 if r is None else r

    top = max(score(w) for w in fast)
    tied = [w for w in fast if score(w) == top]
    w = PREFERRED_WINDOW if PREFERRED_WINDOW in tied else min(tied)
    return {"window": w, "branch": "best laughter recall at ≥ 60x, ties to 1.5 s",
            "realtime": realtime[w], "tied": sorted(tied)}


def value_at(windows, t, hop):
    """The value of the window whose start is within hop/2 of `t`; None when
    there is none or it has no result."""
    for start, value in windows:
        if abs(start - t) <= hop / 2 + 1e-9:
            return value
    return None


def tolerated_by(their_windows, t, hop):
    """The other side's values at t − hop and t, and whether either is within
    the tolerance of the crossing level."""
    pair = [value_at(their_windows, t - hop, hop), value_at(their_windows, t, hop)]
    near = any(v is not None and abs(v - CROSSING) <= VALUE_TOLERANCE + 1e-9 for v in pair)
    return near, pair


def matched(ours, theirs, hop, their_windows=None):
    """(unmatched, tolerated): each crossing time in `ours` with no crossing
    in `theirs` within one hop is tolerated when `their_windows` is given and
    its value at t or t − hop is within the tolerance, else unmatched."""
    unmatched, tolerated = [], []
    for t in ours:
        if any(abs(t - u) <= hop + 1e-9 for u in theirs):
            continue
        if their_windows is not None:
            near, pair = tolerated_by(their_windows, t, hop)
            if near:
                tolerated.append({"at": t, "other": pair})
                continue
        unmatched.append(t)
    return unmatched, tolerated


def agreement(file_groups, stream_groups, hop):
    """`*_groups`: {group: windows}; answers (agrees, unmatched rows,
    tolerated rows), the amended metric."""
    misses, tolerated = [], []
    for group in sorted(set(file_groups) | set(stream_groups)):
        fw, sw = file_groups.get(group, []), stream_groups.get(group, [])
        f, s = crossings(fw, CROSSING), crossings(sw, CROSSING)
        for side, ours, theirs, their_windows in (("file", f, s, sw), ("stream", s, f, fw)):
            left, kept = matched(ours, theirs, hop, their_windows)
            misses.extend({"group": group, "side": side, "at": t} for t in left)
            tolerated.extend({"group": group, "side": side, **row} for row in kept)
    return not misses, misses, tolerated


def agreement_strict(file_groups, stream_groups, hop):
    """Attempt 1's metric: crossings within one hop only; (agrees, misses)."""
    misses = []
    for group in sorted(set(file_groups) | set(stream_groups)):
        f = crossings(file_groups.get(group, []), CROSSING)
        s = crossings(stream_groups.get(group, []), CROSSING)
        for t in matched(f, s, hop)[0]:
            misses.append({"group": group, "side": "file", "at": t})
        for t in matched(s, f, hop)[0]:
            misses.append({"group": group, "side": "stream", "at": t})
    return not misses, misses


def selftest():
    failed = []

    def row(name, ok):
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
        if not ok:
            failed.append(name)

    w = [(0.0, 0.1), (0.75, 0.6), (1.5, 0.7), (2.25, 0.2), (3.0, None), (3.75, 0.9)]
    row("crossings: a rise after a low and after a None", crossings(w, 0.5) == [0.75, 3.75])
    row("crossings: the first window above is a rise", crossings([(0.0, 0.9)], 0.5) == [0.0])
    hop = 0.75
    file_g = {"speech": [(0.0, 0.1), (0.75, 0.8), (1.5, 0.1), (3.0, 0.9)]}
    stream_g = {"speech": [(0.0, 0.1), (0.75, 0.1), (1.5, 0.8), (2.25, 0.1), (3.75, 0.9)]}
    ok, misses, _ = agreement(file_g, stream_g, hop)
    row("agreement: crossings one hop apart agree", ok and not misses)
    lone = {"speech": [(0.0, 0.1), (0.75, 0.8), (1.5, 0.1), (3.0, 0.9)],
            "music": [(0.0, 0.9)]}
    far = {"speech": [(0.0, 0.1), (0.75, 0.1), (1.5, 0.1), (2.25, 0.9), (3.0, 0.1), (4.5, 0.9)]}
    ok, misses, _ = agreement(lone, far, hop)
    sides = sorted((m["group"], m["side"], m["at"]) for m in misses)
    row("agreement: a crossing with no partner and one two hops off disagree",
        not ok and ("music", "file", 0.0) in sides and ("speech", "file", 0.75) in sides
        and ("speech", "stream", 4.5) in sides)
    # The owner's amendment: a ±0.1 value tolerance.
    ours = {"music": [(0.0, 0.1), (0.75, 0.6), (1.5, 0.1)]}
    near = {"music": [(0.0, 0.1), (0.75, 0.45), (1.5, 0.1)]}
    ok, misses, tol = agreement(ours, near, hop)
    row("tolerance: the other side 0.45 in the crossing's window, no crossing → tolerated",
        ok and not misses and tol == [{"group": "music", "side": "file", "at": 0.75,
                                       "other": [0.1, 0.45]}])
    row("tolerance: the strict metric does not tolerate it",
        agreement_strict(ours, near, hop)[0] is False)
    hop1 = 0.5
    file25 = {"speech": [(24.5, 0.807), (25.0, 0.501), (25.5, 0.731), (26.0, 0.024)]}
    stream25 = {"speech": [(24.5, 0.802), (25.0, 0.498), (25.5, 0.742), (26.0, 0.021)]}
    ok, misses, tol = agreement(file25, stream25, hop1)
    row("tolerance: 25.5's shape (stream 0.498 → 0.742 crosses; file 0.501 → 0.731 "
        "does not) is tolerated through the window before",
        ok and not misses and tol == [{"group": "speech", "side": "stream", "at": 25.5,
                                       "other": [0.501, 0.731]}])
    far35 = {"music": [(0.0, 0.1), (0.75, 0.35), (1.5, 0.35)]}
    ours35 = {"music": [(0.0, 0.1), (0.75, 0.35), (1.5, 0.7)]}
    ok, misses, tol = agreement(ours35, far35, hop)
    row("tolerance: the other side 0.35 in both windows → unmatched",
        not ok and misses == [{"group": "music", "side": "file", "at": 1.5}] and not tol)
    gap = {"music": [(0.0, 0.1), (1.5, 0.1)]}
    ok, misses, tol = agreement(ours, gap, hop)
    row("tolerance: a None on the other side is not tolerated",
        not ok and misses == [{"group": "music", "side": "file", "at": 0.75}] and not tol
        and value_at(gap["music"], 0.75, hop) is None)
    events = [float(10 * i) for i in range(1, 21)]
    windows = [(e + 0.3, 0.65) for e in events]
    negatives = [([(float(s), 0.2) for s in range(0, 600)], 600.0)]
    verdict = group_rule(windows, events, negatives)
    row("group: 20 events found at 0.6, no false calls → first-class at 0.6",
        verdict["class"] == "first" and verdict["threshold"] == 0.6)
    verdict = group_rule(windows[:12], events[:12], negatives)
    row("group: 6 held-out events → weak by rule",
        verdict["class"] == "weak" and verdict["held_out"] == 6)
    noisy = [([(float(s), 0.95 if s % 100 == 0 else 0.1) for s in range(0, 600)], 600.0)]
    verdict = group_rule(windows, events, noisy)
    row("group: six calls per 10 min at every t → weak", verdict["class"] == "weak")
    row("group: no events → weak", group_rule([], [], negatives)["class"] == "weak")
    rt = {1.0: 120.0, 1.5: 130.0, 3.0: 200.0}
    row("window: no recall, all fast → 1.5 s", window_rule(rt, {})["window"] == 1.5)
    row("window: the best recall wins",
        window_rule(rt, {1.0: 0.9, 1.5: 0.8, 3.0: 0.7})["window"] == 1.0)
    row("window: a slow window is not kept",
        window_rule({1.0: 30.0, 1.5: 70.0, 3.0: 80.0}, {1.0: 0.9, 1.5: 0.5})["window"] == 1.5)
    row("window: none at 60x → the fastest",
        window_rule({1.0: 30.0, 1.5: 40.0, 3.0: 50.0}, {})["window"] == 3.0)
    print(f"sound_deciders selftest: {'FAIL ' + ', '.join(failed) if failed else 'PASS'}")
    return bool(failed)


if __name__ == "__main__":
    sys.exit(1 if selftest() else 0)
