#!/usr/bin/env python3
"""The rendered-ramp spike — road map "speed-ramps", SR1b (#111, spec §11 SR-7).

Is a ramp's audio, rendered offline by `RampAudioRenderer` (SR-6) and
carried as ONE ×1 audio clip, free of clicks and dropouts and placed on the
ideal map, in export and in playback? Measured through SR1's instrument
(`ramp_spike.py`'s fixtures, Z0, classifiers and probe, whose `render` group
calls the renderer, built `-O`), against rendered and composition controls
and a planted fault, by SR-7's rule (fixed before the run; `results.json`
pins the §11 file's SHA-256). The answers are in `designs/speed-ramps.md`'s
SR1b record. SR1c (SR-9) re-runs arm ON on SR-8's resample-then-pitch-shift
renderer with `--verdict on`, adding the rendered pitch (PR, LG), rendered-only
constant controls (`aux`) and a 15 kHz band render (`band`, BW); its answers
are the SR1c record. SR1d (SR-14) sweeps the lead of SR-13's rate-mode arm
with `--lead-sweep`, then judges it with `--verdict rate`: SR-7's arm ON over
RK1, RK2 and the held-out RK3, SR-9's pitch rows under the rate-mode command
and constant renders of a gliding fixture (`sweep`, RW); its answers are the
SR1d record. SR1e (SR-17) trims a corrected playback tap rather than
zero-padding it (`trim_shift`, `corrected_signal`, `place_corrected`): every
rule reads the samples the tap carried as the signal's extent, and a click
outside them is unobserved, not missed (selftest S22, mutants `trim-off` and
`window-off`); SR1e closed with no measured run (SR-16).

    python3 tools/proof/ramp_spike/render_spike.py [--groups render,plan,export,playback]
        [--variants RV1,RC-off-x1,…] [--remake] [--verdict both|on|rate]
    python3 tools/proof/ramp_spike/render_spike.py --lead-sweep
    python3 tools/proof/ramp_spike/render_spike.py --selftest [--mutant NAME]

Exit 0: every requested row answered (whatever the VERDICT). Exit 1: an
instrument check failed — Z0, a render not answered, R44 not refused as
`unreadable`, RC-off-x1's render not the fixture's own samples, a `C-off-*`
control in export (C-off-x4's click excepted, #334), RF1 not one click at
2 s or passing placement, PT1's tap never called, a variant reading past
19 s of the 20 s fixture, the build, a probe crash or expiry, a read that
failed. Exit 2: not performed (no `ffmpeg`/`ffprobe`, no
`core/target/release/libframejob_core.a`). Under `--selftest --mutant`: 1
caught, 0 survived. Everything written is under
`tools/proof/work/ramp-render-spike/` (gitignored); the fixtures and the
probe binary are SR1's folder's. No app instance, no socket, no MCP, no
network; every child runs under `graphics_spike/bounded.py`.
"""

import argparse
import array
import bisect
import hashlib
import json
import math
import shutil
import statistics
import sys
import time
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ramp_spike as rs  # noqa: E402
from export_offset_proof import click_value, read_ffmpeg, summary  # noqa: E402
from media_less_playback_probe import build_shader  # noqa: E402

ROOT = rs.ROOT
WORK = ROOT / "tools/proof/work/ramp-render-spike"
PROJECTS = WORK / "projects"
RENDERS = WORK / "renders"
RESULTS = WORK / "results.json"
R44_WAV = WORK / "r44.wav"
BAND_WAV = WORK / "band.wav"
BAND_HZ = 15000.0
GLIDE_WAV = WORK / "glide.wav"
LEAD_DIR = WORK / "lead"
RULE_FILE = rs.RULE_FILE

SEC, FRAME, RATE = rs.SEC, rs.FRAME, rs.RATE
SOURCE_IN = rs.SOURCE_IN
GROUPS = ["render", "plan", "export", "playback"]
WALLS = {"render": 900, "plan": 120, "export": 1500, "playback": 2700}
TICKS_PER_FRAME = SEC / RATE  # 12.5

# SR-7's numbers (the rest are SR-5's, read from ramp_spike).
MAP_STEP = 600
DENSE_EDGE_S = 0.050
DENSE_STEP_S = 0.002
DENSE_HALF_S = 0.002
DENSE_SPAN_S = 0.100
DENSE_FACTOR = 4.0
MERGE_S = 0.010
RF1_NEAR_S = 0.005
IDENTITY_TOL = 1e-6
AGREE_MS, AGREE_SPREAD_MS = 1.0, 0.5

# SR-9's numbers.
PITCH_MEDIAN_CENTS = 25.0
PITCH_LAG_RMS_CENTS = 25.0
PITCH_WINDOW_S = 0.040
PITCH_STEP_S = 0.010
PITCH_EDGE_S = 0.050
LAG_FROM_MS, LAG_TO_MS = -100, 300
CENTS_RANGE = 2400.0
# name: (rate, length s), keep pitch on, rendered only.
AUX = {"RC-on-x1": (1.0, 6.0), "RC-on-x3": (3.0, 4.0), "RC-on-x6": (6.0, 2.0),
       "RC-on-x0.2": (0.2, 6.0)}
BAND = {"RB-on-x2": (2.0, 6.0)}
UNSTAGED = ("edit", "aux", "band", "sweep")

# SR-14's numbers.
RATE_CENTS_RANGE = 6000.0  # the rate-mode command: the unit's 1/32…32 bound
CENTS_BOUND = CENTS_RANGE  # the command's clamp; `--verdict rate` sets RATE_CENTS_RANGE
K3 = (True, 2.0, 0.5, "ease_in_out", 1.0, 3.0, 8.0)  # RK3, held out of the lead sweep
# name: (rate, length s), keep pitch on, rendered only from glide.wav.
SWEEP = {"RW-on-x0.9": (0.9, 6.0), "RW-on-x1.1": (1.1, 6.0), "RW-on-x2": (2.0, 6.0)}
GLIDE_LO_HZ, GLIDE_HI_HZ = 220.0, 440.0
GLIDE_FROM_S, GLIDE_TO_S = 2.0, 4.0
LEADS_MS = list(range(0, 101, 2))
LEAD_RAMPS = ["RK1", "RK2"]
LEAD_WALL = 1800

RAMP_OF = {"RV1": "V1", "RV2": "V2", "RV3": "V3", "RK1": "K1", "RK2": "K2"}
OFF_MEMBERS = ["RV1", "RV2", "RV3", "RC-off-x0.25", "RC-off-x0.5", "RC-off-x1", "RC-off-x2",
               "RC-off-x4"]
ON_RAMPS = ["RK1", "RK2"]
RATE_ON_RAMPS = ["RK1", "RK2", "RK3"]
ON_ANCHORS = ["RC-on-x0.5", "RC-on-x0.9", "RC-on-x1.1", "RC-on-x2"]
END_CONTROLS = {"RK1": ("RC-on-x1.1", "RC-on-x2"), "RK2": ("RC-on-x0.9", "RC-on-x0.5"),
                "RK3": ("RC-on-x2", "RC-on-x0.5")}
FRAME_SET = set(OFF_MEMBERS + RATE_ON_RAMPS)
MUTANTS = ["dense-off", "merge-all", "pt1-off", "identity-off", "on-anchor-off"]
MUTANTS += ["pitch-flat", "lag-zero", "on-verdict-off", "pitch-rule-off"]
MUTANTS += ["rk3-off", "sweep-drop-off", "lead-pick-max"]
MUTANTS += ["trim-off", "window-off"]

MUTANT = None


# ---- the variants and their maps ------------------------------------------------


def ease(curve, u):
    return {"linear": u, "ease_in": u * u, "ease_out": 1 - (1 - u) ** 2,
            "ease_in_out": 3 * u * u - 2 * u ** 3}[curve]


def rate_of(ramp, t):
    """S′(t), t in ticks."""
    _, r0, r1, curve, a_s, b_s, _ = ramp
    a, b = a_s * SEC, b_s * SEC
    if t <= a:
        return r0
    if t < b:
        return r0 + (r1 - r0) * ease(curve, (t - a) / (b - a))
    return r1


def control_ramp(keep, rate, length_s):
    return (keep, rate, rate, "linear", 0.0, 0.0, length_s)


def rendered_map(ramp, length, shift_from=None, shift=0):
    clip = list(range(0, length, MAP_STEP)) + [length]
    source = [SOURCE_IN + rs.source_of(ramp, t) + (shift if shift_from is not None and t >= shift_from
                                                   else 0) for t in clip]
    return clip, source


def variants():
    """name → {kind, keep, ramp (the rendered map's), ideal (judged against),
    length, segs/ref (the written video), map, arm, render_only}."""
    out = {}
    for name, base in RAMP_OF.items():
        ramp = rs.RAMPS[base]
        length = round(ramp[6] * SEC)
        segs = rs.ramp_segments(ramp, 1)
        out[name] = {"kind": "ramp", "keep": ramp[0], "ramp": ramp, "ideal": ramp,
                     "length": length, "segs": segs, "ref": segs,
                     "map": rendered_map(ramp, length)}
    length = round(K3[6] * SEC)
    segs = rs.ramp_segments(K3, 1)
    out["RK3"] = {"kind": "ramp", "keep": True, "ramp": K3, "ideal": K3, "length": length,
                  "segs": segs, "ref": segs, "map": rendered_map(K3, length)}
    v1 = out["RV1"]
    out["RF1"] = dict(v1, kind="fault", map=rendered_map(v1["ramp"], v1["length"], rs.F1_FROM,
                                                         rs.F1_SHIFT))
    edit = (False, 1.0, 2.5, "linear", 1.0, 3.0, 8.0)
    out["RV1-edit"] = dict(v1, kind="edit", ramp=edit, ideal=edit,
                           map=rendered_map(edit, v1["length"]))
    for name, (keep, rate, length_s) in rs.CONTROLS.items():
        length = round(length_s * SEC)
        ramp = control_ramp(keep, rate, length_s)
        segs = [rs.seg(0, length, SOURCE_IN, round(length * rate))]
        out["R" + name] = {"kind": "rcontrol", "keep": keep, "ramp": ramp, "ideal": ramp,
                           "length": length, "segs": segs, "ref": segs,
                           "map": rendered_map(ramp, length)}
        out[name] = {"kind": "control", "keep": keep, "ramp": ramp, "ideal": ramp,
                     "length": length, "segs": segs, "ref": segs, "map": None}
    for kind, table in (("aux", AUX), ("band", BAND), ("sweep", SWEEP)):
        for name, (rate, length_s) in table.items():
            length = round(length_s * SEC)
            ramp = control_ramp(True, rate, length_s)
            segs = [rs.seg(0, length, SOURCE_IN, round(length * rate))]
            out[name] = {"kind": kind, "keep": True, "ramp": ramp, "ideal": ramp,
                         "length": length, "segs": segs, "ref": segs,
                         "map": rendered_map(ramp, length)}
    out["RB-on-x2"]["fixtures"] = ["band"]
    for name in SWEEP:
        out[name]["fixtures"] = ["glide"]
    for v in out.values():
        v["rendered"] = v["kind"] in ("ramp", "fault", "edit", "rcontrol", "aux", "band",
                                      "sweep")
    return out


def fixtures_of(v):
    return v.get("fixtures", list(rs.FIXTURE_FILES))


def source_end_ticks(v):
    return max(v["map"][1]) if v["map"] else rs.source_end(v)


# ---- the classifiers (SR-7) -----------------------------------------------------


def dense_scan(x, rate, length_s, d=None):
    """(centres s, D, L): centres every 2 ms over the clip less 50 ms each
    end, D the max |second difference| over c ± 2 ms, L the median D over the
    centres within ±100 ms."""
    d = d if d is not None else rs.second_diff(x)
    centres, k = [], 0
    while DENSE_EDGE_S + k * DENSE_STEP_S <= length_s - DENSE_EDGE_S + 1e-9:
        centres.append(DENSE_EDGE_S + k * DENSE_STEP_S)
        k += 1
    D = [rs.wmax(d, rate, c - DENSE_HALF_S, c + DENSE_HALF_S) for c in centres]
    span = int(round(DENSE_SPAN_S / DENSE_STEP_S))
    L = [statistics.median(D[max(0, i - span):i + span + 1]) for i in range(len(D))]
    return centres, D, L


def click_events(scan, floor=0.0):
    """[(peak s, D, D / threshold)]: the clicking centres (D > max(4·L,
    floor)), merged when within 10 ms of the one before, at their greatest D."""
    centres, D, L = scan
    events = []
    last = None
    for c, dv, lv in zip(centres, D, L):
        thr = max(DENSE_FACTOR * lv, floor)
        if MUTANT == "dense-off" or not dv > thr:
            continue
        ratio = dv / thr if thr > 0 else math.inf
        if events and (MUTANT == "merge-all" or c - last <= MERGE_S + 1e-9):
            if dv > events[-1][1]:
                events[-1] = [c, dv, ratio]
        else:
            events.append([c, dv, ratio])
        last = c
    return [(round(c, 4), dv, ratio) for c, dv, ratio in events]


def expected_ideal(v):
    """[(source tick, expected s, S′)] by the inverse of the ideal map,
    clicks within 2 ms of the clip's edges skipped."""
    ramp, length = v["ideal"], v["length"]
    top = rs.source_of(ramp, length)
    out = []
    for c in rs.CLICKS:
        s = c - SOURCE_IN
        if s < 0 or s > top:
            continue
        t = rs.inverse_of(ramp, s, length) / SEC
        if rs.EDGE_SKIP_S <= t <= length / SEC - rs.EDGE_SKIP_S:
            out.append((c, t, rate_of(ramp, t * SEC)))
    return out


def place_ideal(samples, rate, v, residual_s=0.0, window=None):
    """SR-5's location against the ideal map; `residual_s` is the part of a
    playback correction a whole-sample shift of the signal left over.
    `window` (lo s, hi s), a trimmed tap's extent (SR-17): samples[0] sits at
    lo s, and a click expected outside [lo + EDGE_SKIP_S, hi − EDGE_SKIP_S]
    is unobserved — None in "times", out of "of", counted in "unobserved"."""
    exp = expected_ideal(v)
    times = [t for _, t, _ in exp]
    rates = [r if not v["keep"] else 1.0 for _, _, r in exp]
    spacing = min((b - a for a, b in zip(times, times[1:])), default=1.0) * 1000
    reach = min(rs.REACH_MAX_MS, rs.REACH_SHARE * spacing)
    if window is not None:
        return place_window(samples, rate, times, rates, reach, residual_s, window)
    found = rs.locate_scaled(samples, rate, [t + residual_s for t in times], rates, reach)
    found = [(None if f is None else f - residual_s, r) for f, r in found]
    s = summary(found, times)
    s["found_share"] = s["found"] / s["of"] if s["of"] else 0.0
    s["max_abs_ms"] = max((abs(d) for d in s["diffs"]), default=None)
    s["times"] = [f for f, _ in found]
    s["reach_ms"] = reach
    return s


def place_window(samples, rate, times, rates, reach, residual_s, window):
    """`place_ideal` over a trimmed tap whose samples[0] sits at window[0] s."""
    lo, hi = window
    seen = [MUTANT == "window-off" or lo + rs.EDGE_SKIP_S <= t <= hi - rs.EDGE_SKIP_S
            for t in times]
    obs_t = [t for t, ok in zip(times, seen) if ok]
    obs_r = [r for r, ok in zip(rates, seen) if ok]
    found = rs.locate_scaled(samples, rate, [t - lo + residual_s for t in obs_t], obs_r, reach)
    found = [(None if f is None else f + lo - residual_s, r) for f, r in found]
    s = summary(found, obs_t)
    s["found_share"] = s["found"] / s["of"] if s["of"] else 0.0
    s["max_abs_ms"] = max((abs(d) for d in s["diffs"]), default=None)
    located = iter(f for f, _ in found)
    s["times"] = [next(located) if ok else None for ok in seen]
    s["reach_ms"] = reach
    s["unobserved"] = seen.count(False)
    return s


def anchor_pass(s, c_on):
    """An RC-on control against the same rate's composition control."""
    if MUTANT == "on-anchor-off":
        return True
    if s is None or c_on is None or s["max_abs_ms"] is None or c_on["max_abs_ms"] is None:
        return False
    return (s["found_share"] >= c_on["found_share"] - rs.KEEP_FOUND_SLACK
            and s["max_abs_ms"] <= c_on["max_abs_ms"] + rs.KEEP_DIFF_SLACK_MS)


def pt1(export_s, playback_s):
    """(passes, m1 ms): RC-off-x1's playback tap, ≥ 90 % found and spread ≤
    0.5 ms; m1 its playback median − its export median."""
    if not playback_s or playback_s["median_ms"] is None or not export_s \
            or export_s["median_ms"] is None:
        return False, None
    ok = playback_s["found_share"] >= rs.FOUND_SHARE and playback_s["spread_ms"] <= rs.SPREAD_MS
    m1 = playback_s["median_ms"] - export_s["median_ms"]
    return ok, (0.0 if MUTANT == "pt1-off" else m1)


def coarse_ms(x, rate, v):
    """A tap's whole offset against `v`'s expected clicks, to the nearest
    click peak (|x| > 0.25, ±200 ms): the median, in ms, 0 with none —
    SR2b's method, shared with `ramp_proof.py`'s P1. PT1 aligns RC-off-x1's
    tap by it in whole samples before `pt1` reads the rest, so an offset
    past the 60 ms reach (the host's playback path, #335) is measured; m1
    is the sum."""
    peaks, last = [], None
    for i in range(1, len(x) - 1):
        if abs(x[i]) > 0.25 and abs(x[i]) >= abs(x[i - 1]) and abs(x[i]) >= abs(x[i + 1]):
            if last is None or i - last > rate // 500:
                peaks.append(i / rate)
            last = i
    diffs = []
    for _, t, _ in expected_ideal(v):
        near = min(peaks, key=lambda p: abs(p - t), default=None)
        if near is not None and abs(near - t) <= 0.2:
            diffs.append(near - t)
    return statistics.median(diffs) * 1000 if diffs else 0.0


def shift_signal(x, k):
    """x with every sample moved k samples EARLIER (k < 0: later): the
    corrected time raw − m1 at k = round(m1 · rate / 1000)."""
    n = len(x)
    out = [0.0] * n
    for j in range(max(0, k), min(n, n + k)):
        out[j - k] = x[j]
    return out


def trim_shift(x, k):
    """(samples, first): x corrected k samples EARLIER (k < 0: later) by
    trimming what `shift_signal` would zero-fill (SR-17); corrected sample
    `first + i` is samples[i]."""
    if MUTANT == "trim-off":
        return shift_signal(x, k), 0
    if k == 0:
        return x, 0
    return x[max(0, k):len(x) + min(0, k)], max(0, -k)


def corrected_signal(x, rate, k):
    """(samples, rate, window): a playback tap corrected by k samples, its
    window (first / rate, (first + len) / rate) s, None when k is 0."""
    if k == 0:
        return x, rate, None
    samples, first = trim_shift(x, k)
    return samples, rate, (first / rate, (first + len(samples)) / rate)


def place_corrected(x, rate, v, k, residual_s=0.0):
    """`place_ideal` over a tap corrected by k samples, trimmed (SR-17)."""
    samples, rate, window = corrected_signal(x, rate, k)
    return place_ideal(samples, rate, v, residual_s, window)


def correction(m1_ms, rate):
    """(whole samples k, residual s) for a correction of m1 ms."""
    if not m1_ms:
        return 0, 0.0
    k = int(round(m1_ms * rate / 1000))
    return k, m1_ms / 1000 - k / rate


def agreement(e, p, keep_rule=False):
    """(ok, detail): playback minus export click times, paired."""
    if not e or not p:
        return None, "a placement read is missing"
    diffs = [(b - a) * 1000 for a, b in zip(e["times"], p["times"])
             if a is not None and b is not None]
    if not diffs:
        return False, "no click found on both sides"
    if keep_rule:
        worst = max(abs(d) for d in diffs)
        return worst <= rs.AGREE_KEEP_MS, f"{len(diffs)} pairs, max |diff| {worst:.3f} ms"
    med, spread = statistics.median(diffs), max(diffs) - min(diffs)
    return (abs(med) <= AGREE_MS and spread <= AGREE_SPREAD_MS,
            f"{len(diffs)} pairs, median {med:+.3f} ms, spread {spread:.3f} ms")


def identity(render, fixture, offset, n):
    """(ok, max |diff|): the render against the fixture's samples
    [offset, offset + n)."""
    if len(render) < n or len(fixture) < offset + n:
        return False, None
    worst = max(abs(render[i] - fixture[offset + i]) for i in range(n))
    return (True if MUTANT == "identity-off" else worst <= IDENTITY_TOL), worst


def period_fn(v):
    if v["keep"]:
        return lambda t: 1 / rs.SINE_HZ
    return lambda t: 1 / (rs.SINE_HZ * rate_of(v["ramp"], t * SEC))


# ---- the verdict ----------------------------------------------------------------


def member_failures(name, results, agree, sides=("export", "playback")):
    out = []
    for side in sides:
        rules = results.get(side, {}).get(name)
        if rules is None:
            out.append(f"{name} {side}: not measured")
            continue
        bad = rs.failed_rules(rules, keys=["placement", "click", "dropout", "video"])
        if bad:
            out.append(f"{name} {side}: {', '.join(bad)}")
    if agree.get(name) is not True:
        out.append(f"{name}: agreement" + ("" if agree.get(name) is False else " (unmeasured)"))
    return out


def anchor_failures(name, results, sides=("export", "playback")):
    out = []
    for side in sides:
        rule = results.get(side, {}).get(name, {}).get("placement")
        if not rule or rule.get("ok") is not True:
            out.append(f"{name} {side}: anchor placement"
                       + ("" if rule and rule.get("ok") is False else " (unmeasured)"))
    return out


def arm_failures(arm, results, agree):
    if arm == "off":
        return [f for n in OFF_MEMBERS for f in member_failures(n, results, agree)]
    return ([f for n in ON_RAMPS for f in member_failures(n, results, agree)]
            + [f for n in ON_ANCHORS for f in anchor_failures(n, results)])


def decide(results, agree):
    off, on = arm_failures("off", results, agree), arm_failures("on", results, agree)
    if not off and not on:
        return "GO", "both arms: every ramp and control passes in export and playback, with agreement"
    if not off:
        return "SPLIT", "off GO, on STOP — " + "; ".join(on)
    if not on:
        return "SPLIT", "off STOP, on GO — " + "; ".join(off)
    return "STOP", "; ".join(off + on)


# ---- the pitch (SR-9) -----------------------------------------------------------


def crossings(x, rate):
    """The positive-going zero crossings' times (s), linearly interpolated."""
    out = []
    for n in range(1, len(x)):
        a, b = x[n - 1], x[n]
        if a < 0 <= b:
            out.append((n - 1 + a / (a - b)) / rate)
    return out


def pitch_track(x, rate, length_s):
    """[(window centre s, f Hz)]: 40 ms windows every 10 ms over the clip
    less 50 ms each end; f = (crossings − 1) / (last − first crossing)."""
    times = crossings(x, rate)
    out, k = [], 0
    while True:
        t0 = PITCH_EDGE_S + k * PITCH_STEP_S
        t1 = t0 + PITCH_WINDOW_S
        if t1 > length_s - PITCH_EDGE_S + 1e-9:
            break
        k += 1
        lo, hi = bisect.bisect_left(times, t0), bisect.bisect_left(times, t1)
        if hi - lo < 2:
            continue
        f = (hi - lo - 1) / (times[hi - 1] - times[lo])
        out.append((t0 + PITCH_WINDOW_S / 2, rs.SINE_HZ if MUTANT == "pitch-flat" else f))
    return out


def command_cents(rate):
    """The command c(r): SR-9's ±2400 cents, or SR-14's rate-mode ±6000
    (the unit's 1/32…32 bound) under `--verdict rate`."""
    return min(max(-1200 * math.log2(rate), -CENTS_BOUND), CENTS_BOUND)


def expected_hz(ramp, t_s, lag_s=0.0):
    """f_e: 220 · r(t) · 2^(c(t − lag)/1200), c the clamped command."""
    r = rate_of(ramp, t_s * SEC)
    return rs.SINE_HZ * r * 2 ** (command_cents(rate_of(ramp, (t_s - lag_s) * SEC)) / 1200)


def cents_of(track, ramp, lag_s=0.0):
    return [1200 * math.log2(f / expected_hz(ramp, t, lag_s)) for t, f in track]


def pitch_reading(track, ramp):
    """PR: median f, signed median cents, median and max |cents|."""
    if not track:
        return {"windows": 0, "median_hz": None, "median_cents": None,
                "median_abs_cents": None, "max_abs_cents": None}
    cents = cents_of(track, ramp)
    return {"windows": len(track), "median_hz": statistics.median(f for _, f in track),
            "median_cents": statistics.median(cents),
            "median_abs_cents": statistics.median(abs(c) for c in cents),
            "max_abs_cents": max(abs(c) for c in cents)}


def pitch_lag(track, ramp):
    """(τ s, RMS cents at τ, RMS cents at 0): τ over [−100, 300] ms in 1 ms
    steps minimising the RMS against 220 · r(t) · 2^(c(t − τ)/1200)."""
    def rms(lag_s):
        cents = cents_of(track, ramp, lag_s)
        return math.sqrt(sum(c * c for c in cents) / len(cents))
    at0 = rms(0.0)
    if MUTANT == "lag-zero":
        return 0.0, at0, at0
    best = min((rms(ms / 1000), ms / 1000) for ms in range(LAG_FROM_MS, LAG_TO_MS + 1))
    return best[1], best[0], at0


def band_level_db(x, rate, hz, t0, t1):
    """The level (dB re full-scale amplitude) at `hz` over [t0, t1), by Goertzel."""
    lo, hi = int(round(t0 * rate)), int(round(t1 * rate))
    seg_ = x[lo:hi]
    n = len(seg_)
    coeff = 2 * math.cos(2 * math.pi * hz / rate)
    s1 = s2 = 0.0
    for v in seg_:
        s1, s2 = v + coeff * s1 - s2, s1
    power = s1 * s1 + s2 * s2 - coeff * s1 * s2
    amp = 2 * math.sqrt(max(power, 0.0)) / n if n else 0.0
    return 20 * math.log10(amp) if amp > 0 else -math.inf


def pitch_failures(results, ramps=ON_RAMPS):
    if MUTANT == "pitch-rule-off":
        return []
    out = []
    for name in ramps + ON_ANCHORS:
        pr = results.get("pitch", {}).get(name)
        if not pr or pr.get("median_cents") is None:
            out.append(f"{name}: pitch (unmeasured)")
        elif abs(pr["median_cents"]) > PITCH_MEDIAN_CENTS:
            out.append(f"{name}: pitch")
    for name in ramps:
        lg = results.get("lag", {}).get(name)
        if not lg or lg.get("rms_at_tau") is None:
            out.append(f"{name}: pitch lag (unmeasured)")
        elif lg["rms_at_tau"] > PITCH_LAG_RMS_CENTS:
            out.append(f"{name}: pitch lag")
    return out


def decide_on(results, agree):
    """SR-9: arm ON alone — SR-7's arm ON rule plus the rendered pitch."""
    fails = [f for n in ON_RAMPS for f in member_failures(n, results, agree)]
    if MUTANT != "on-verdict-off":
        fails += [f for n in ON_ANCHORS for f in anchor_failures(n, results)]
    fails += pitch_failures(results)
    if not fails:
        return "GO", ("arm ON: RK1 and RK2 pass placement, click, dropout, video and agreement "
                      "in export and playback, every RC-on anchor passes its placement, and each "
                      "holds its pitch (SR-9)")
    return "STOP", "; ".join(fails)


# ---- SR1d: the rate-mode arm (SR-14) --------------------------------------------


def glide_hz(source_s):
    """glide.wav's frequency at source second `source_s`: 220 Hz to 2 s, an
    exponential sweep to 440 Hz at 4 s, then 440 Hz."""
    if source_s <= GLIDE_FROM_S:
        return GLIDE_LO_HZ
    if source_s >= GLIDE_TO_S:
        return GLIDE_HI_HZ
    u = (source_s - GLIDE_FROM_S) / (GLIDE_TO_S - GLIDE_FROM_S)
    return GLIDE_LO_HZ * (GLIDE_HI_HZ / GLIDE_LO_HZ) ** u


def glide_signal(hz_at, seconds, amp=rs.AMPLITUDE):
    """A phase-continuous sine whose frequency at t s is `hz_at(t)`."""
    out, phase = [], 0.0
    for n in range(int(seconds * RATE)):
        out.append(amp * math.sin(phase))
        phase += 2 * math.pi * hz_at(n / RATE) / RATE
    return out


def write_glide():
    rs.write_wav(GLIDE_WAV, glide_signal(glide_hz, rs.FIXTURE_S))


def sweep_dropouts(x, rate, length_s, r):
    """(ok, events): SR-5's (a) and (b) on a constant ×r render of
    glide.wav, the local period 1 / glide_hz(1 + r·t)."""
    start = SOURCE_IN / SEC
    drops = rs.events(rs.dropouts(x, rate, length_s, lambda t: 1 / glide_hz(start + r * t)))
    return (True if MUTANT == "sweep-drop-off" else not drops), drops


def sweep_failures(results):
    out = []
    for name in SWEEP:
        got = results.get("sweep", {}).get(name)
        if not got or got.get("ok") is None:
            out.append(f"{name}: dropout (unmeasured)")
        elif not got["ok"]:
            out.append(f"{name}: dropout")
    return out


def decide_rate(results, agree):
    """SR-14: arm ON (rate) — SR-7's arm ON over RK1, RK2 and RK3, the
    anchors, SR-9's pitch rows under the rate-mode command, and the sweep."""
    ramps = [n for n in RATE_ON_RAMPS if not (MUTANT == "rk3-off" and n == "RK3")]
    fails = [f for n in ramps for f in member_failures(n, results, agree)]
    fails += [f for n in ON_ANCHORS for f in anchor_failures(n, results)]
    fails += pitch_failures(results, ramps)
    fails += sweep_failures(results)
    if not fails:
        return "GO", ("arm ON (rate): RK1, RK2 and RK3 pass placement, click, dropout, video and "
                      "agreement in export and playback, every RC-on anchor passes its placement, "
                      "each holds its pitch, and no RW render drops out (SR-14)")
    return "STOP", "; ".join(fails)


def pick_lead(rows):
    """L* (ms) or None: among the leads at which every ramp finds every
    click (found == of, of > 0), the one minimising the greater max |diff|,
    a tie going to the smaller lead. `rows`: lead ms → {ramp: (max_abs_ms,
    found, of)}."""
    eligible = []
    for lead, by in rows.items():
        cells = [by.get(n) for n in LEAD_RAMPS]
        if all(c is not None and c[0] is not None and c[2] > 0 and c[1] == c[2] for c in cells):
            eligible.append((max(c[0] for c in cells), lead))
    if not eligible:
        return None
    return (max(eligible) if MUTANT == "lead-pick-max" else min(eligible))[1]


def lead_sweep(binary):
    """SR-14's lead, first: RK1 and RK2 rendered from the clicks fixture at
    every lead in LEADS_MS into `lead/`, placed against the ideal map;
    answers L* in ms, or None."""
    LEAD_DIR.mkdir(parents=True, exist_ok=True)
    everything = variants()
    jobs = []
    for ms in LEADS_MS:
        for name in LEAD_RAMPS:
            v = everything[name]
            jobs.append({"name": f"{name}@L{ms}", "source": str(fixture_path("clicks")),
                         "clip_ticks": v["map"][0], "source_ticks": v["map"][1],
                         "keep_pitch": True, "destination": str(LEAD_DIR / f"{name}@L{ms}.caf"),
                         "lead_frames": round(ms * RATE / 1000)})
    t0 = time.time()
    got, why = rs.run_group(binary, "render", jobs, work=LEAD_DIR, walls={"render": LEAD_WALL})
    rows, missing = {}, []
    for ms in LEADS_MS:
        rows[ms] = {}
        for name in LEAD_RAMPS:
            line = got.get((f"{name}@L{ms}", "render"))
            path = LEAD_DIR / f"{name}@L{ms}.caf"
            x, rate = (read_ffmpeg(path) if line and line.get("ok") and path.exists()
                       else (None, None))
            if not x:
                missing.append(f"{name}@L{ms}")
                rows[ms][name] = (None, 0, 0)
                continue
            s = place_ideal(x, rate, everything[name])
            rows[ms][name] = (s["max_abs_ms"], s["found"], s["of"])
    print(f"lead sweep: {len(jobs) - len(missing)}/{len(jobs)} renders read in "
          f"{time.time() - t0:.0f} s" + (f"; {why}" if why else "")
          + (f"; missing {missing[:4]}" if missing else ""))
    print("| lead ms | frames | " + " | ".join(f"{n} found | {n} max ms" for n in LEAD_RAMPS)
          + " |")
    print("|" + "---|" * (2 + 2 * len(LEAD_RAMPS)))
    for ms in LEADS_MS:
        cells = [str(ms), str(round(ms * RATE / 1000))]
        for name in LEAD_RAMPS:
            m, found, of = rows[ms][name]
            cells += [f"{found}/{of}", "—" if m is None else f"{m:.2f}"]
        print("| " + " | ".join(cells) + " |")
    best = {}
    for name in LEAD_RAMPS:
        own = [(rows[ms][name][0], ms) for ms in LEADS_MS if rows[ms][name][0] is not None
               and rows[ms][name][2] > 0 and rows[ms][name][1] == rows[ms][name][2]]
        best[name] = min(own) if own else None
        print(f"{name}'s own best: " + (f"{best[name][1]} ms, max |diff| {best[name][0]:.2f} ms"
                                        if best[name] else "no lead finds every click"))
    pick = pick_lead(rows)
    if pick is None or missing or why:
        print("STOP — lead: no lead finds every click" if pick is None
              else f"STOP — lead: the sweep is incomplete ({len(missing)} renders missing)")
    else:
        worst = max(rows[pick][n][0] for n in LEAD_RAMPS)
        print(f"L*: {pick} ms = {round(pick * RATE / 1000)} frames, the greater max |diff| "
              f"{worst:.2f} ms")
    (LEAD_DIR / "sweep.json").write_text(json.dumps({
        "commit": rs.commit(), "date": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "host": rs.host(), "leads_ms": LEADS_MS,
        "rows": {str(ms): {n: list(rows[ms][n]) for n in LEAD_RAMPS} for ms in LEADS_MS},
        "own_best": {n: (list(b) if b else None) for n, b in best.items()},
        "pick_ms": None if missing or why else pick}, indent=1))
    return None if missing or why else pick


# ---- the selftest ---------------------------------------------------------------


def train(v, shift_s=0.0, length_s=None):
    length_s = length_s or v["length"] / SEC
    out = [0.0] * int(length_s * RATE)
    h = RATE / 2000
    for _, t, _ in expected_ideal(v):
        c = (t + shift_s) * RATE
        for n in range(int(c - h) - 1, int(c + h) + 2):
            if 0 <= n < len(out):
                out[n] += click_value(n - c, h)
    return out


def selftest():
    rows = []

    def row(name, ok, detail):
        rows.append(ok)
        print(f"{name} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    # S8: clean sines and a glide: the dense scan finds nothing.
    bad = []
    for freq in (220.0, 55.0, 880.0):
        ev = click_events(dense_scan(rs.sine(freq, 2.0), RATE, 2.0))
        if ev:
            bad.append(f"{freq:g} Hz: {len(ev)} events")
    glide = [rs.AMPLITUDE * math.sin(2 * math.pi * (55 * n / RATE + 825 * (n / RATE) ** 2 / 8))
             for n in range(4 * RATE)]
    ev = click_events(dense_scan(glide, RATE, 4.0))
    if ev:
        bad.append(f"glide: {len(ev)} events")
    row("S8", not bad, "clean 220, 55, 880 Hz and a 55→880 Hz glide: "
        + ("no event" if not bad else "; ".join(bad)))

    # S9: 4 ms phase jumps at 1.0 and 1.5 s: exactly two events, there.
    skip = int(0.004 * RATE)
    x = [rs.AMPLITUDE * math.sin(2 * math.pi * rs.SINE_HZ
                                 * (n + skip * (n >= RATE) + skip * (n >= 1.5 * RATE)) / RATE)
         for n in range(2 * RATE)]
    ev = click_events(dense_scan(x, RATE, 2.0))
    at = [t for t, _, _ in ev]
    ok = len(at) == 2 and abs(at[0] - 1.0) <= RF1_NEAR_S and abs(at[1] - 1.5) <= RF1_NEAR_S
    row("S9", ok, f"phase jumps at 1.0 and 1.5 s: events at {at}")

    # S10: a ×1 click train 21 ms early in playback, on time in export.
    v = {"keep": False, "ideal": control_ramp(False, 1.0, 6.0), "length": 6 * SEC}
    export = place_ideal(train(v), RATE, v)
    raw = train(v, -0.021)
    raw_p = place_ideal(raw, RATE, v)
    tap_ok, m1 = pt1(export, raw_p)
    k, residual = correction(m1, RATE)
    corrected = place_ideal(shift_signal(raw, k), RATE, v, residual)
    with_ok, with_detail = agreement(export, corrected)
    without_ok, without_detail = agreement(export, raw_p)
    row("S10", tap_ok and with_ok and not without_ok,
        f"PT1 {'passes' if tap_ok else 'fails'}, m1 {m1:+.3f} ms; corrected: {with_detail} "
        f"({'passes' if with_ok else 'fails'}); raw: {without_detail} "
        f"({'passes' if without_ok else 'fails'})")

    # S11: RF1's shape — 1 ms at ×6 phase advance in a 220 Hz sine.
    x = [rs.AMPLITUDE * math.sin(2 * math.pi * rs.SINE_HZ
                                 * (n + 5 * min(max(n - RATE, 0), RATE // 1000)) / RATE)
         for n in range(2 * RATE)]
    ev = click_events(dense_scan(x, RATE, 2.0))
    ok = len(ev) == 1 and abs(ev[0][0] - 1.0005) <= RF1_NEAR_S
    row("S11", ok, f"1 ms at ×6 from 1.000 s: events at {[t for t, _, _ in ev]}")

    # S12: the ×1 identity, and a render one sample late.
    fixture = rs.sine(rs.SINE_HZ, 3.0)
    offset, n = RATE, RATE
    good, _ = identity(fixture[offset:offset + n], fixture, offset, n)
    late, worst = identity(fixture[offset - 1:offset - 1 + n], fixture, offset, n)
    row("S12", good and not late,
        f"the fixture's own samples {'pass' if good else 'fail'}; one sample late "
        f"(max |diff| {worst:.4f}) {'passes' if late else 'fails'}")

    # S13: RC-on controls 43 ms late against C-on, and the ramps late by the same.
    v = {"keep": True, "ideal": control_ramp(True, 1.0, 6.0), "length": 6 * SEC}
    c_on = place_ideal(train(v), RATE, v)
    late = place_ideal(train(v, 0.043), RATE, v)
    results = {"export": {}, "playback": {}}
    for side in results:
        for name in ON_ANCHORS:
            results[side][name] = {"placement": {"ok": anchor_pass(late, c_on), "summary": late}}
        for name in ON_RAMPS:
            own = rs.keep_place_pass(late, [late, late])
            results[side][name] = {"placement": {"ok": own, "summary": late},
                                   "click": {"ok": True}, "dropout": {"ok": True},
                                   "video": {"ok": True}}
    agree = {n: True for n in ON_RAMPS}
    ramp_ok = all(results[s][n]["placement"]["ok"] for s in results for n in ON_RAMPS)
    fails = arm_failures("on", results, agree)
    row("S13", ramp_ok and bool(fails) and all("anchor" in f for f in fails),
        f"the ramps' own rule {'passes' if ramp_ok else 'fails'}; arm ON "
        + (f"STOP — {len(fails)} anchor failures" if fails else "GO"))

    # S14: the pitch reader on 220 Hz and 220 · 2^(50/1200) Hz sines.
    flat = control_ramp(True, 1.0, 2.0)
    worst = []
    for cents in (0.0, 50.0):
        hz = rs.SINE_HZ * 2 ** (cents / 1200)
        got = cents_of(pitch_track(rs.sine(hz, 2.0), RATE, 2.0), flat)
        worst.append(max(abs(c - cents) for c in got) if got else math.inf)
    row("S14", all(w <= 0.5 for w in worst),
        f"220 Hz and +50 cents read within {worst[0]:.4f} and {worst[1]:.4f} cents")

    # S15: a synthetic RK1 track lagging 40 ms, and a flat 220 Hz track.
    k1 = rs.RAMPS["K1"]
    centres = [t for t, _ in pitch_track(rs.sine(rs.SINE_HZ, 8.0), RATE, 8.0)]
    lagged = [(t, expected_hz(k1, t, 0.040)) for t in centres]
    tau40, _, _ = pitch_lag(lagged, k1)
    tau0, _, _ = pitch_lag([(t, rs.SINE_HZ) for t in centres], k1)
    row("S15", abs(tau40 - 0.040) <= 0.001 + 1e-9 and abs(tau0) <= 0.001 + 1e-9,
        f"a 40 ms lag reads {tau40 * 1000:.0f} ms; a flat track {tau0 * 1000:.0f} ms")

    # S16: decide_on — passing arm-ON results with no OFF member, then one anchor failing.
    def passing():
        res = {"export": {}, "playback": {}, "pitch": {}, "lag": {}}
        for side in ("export", "playback"):
            for name in ON_RAMPS:
                res[side][name] = {k: {"ok": True} for k in
                                   ("placement", "click", "dropout", "video")}
            for name in ON_ANCHORS:
                res[side][name] = {"placement": {"ok": True}}
        for name in ON_RAMPS + ON_ANCHORS:
            res["pitch"][name] = {"median_cents": 0.0}
        for name in ON_RAMPS:
            res["lag"][name] = {"rms_at_tau": 0.0}
        return res
    agree = {n: True for n in ON_RAMPS}
    go, _ = decide_on(passing(), agree)
    bad = passing()
    bad["export"]["RC-on-x2"]["placement"]["ok"] = False
    stop, why = decide_on(bad, agree)
    row("S16", go == "GO" and stop == "STOP" and "RC-on-x2" in why,
        f"passing results: {go}; RC-on-x2's export placement failing: {stop} — {why}")

    # S17: decide_on — an anchor's pitch 100 cents off, RK1's lag RMS 40 cents.
    off = passing()
    off["pitch"]["RC-on-x0.9"]["median_cents"] = 100.0
    v1, why1 = decide_on(off, agree)
    lag = passing()
    lag["lag"]["RK1"]["rms_at_tau"] = 40.0
    v2, why2 = decide_on(lag, agree)
    row("S17", v1 == "STOP" and "RC-on-x0.9: pitch" in why1 and v2 == "STOP"
        and "RK1: pitch lag" in why2, f"100 cents: {v1} — {why1}; lag 40 cents: {v2} — {why2}")

    # S18: decide_rate — passing rate-mode results, then RK3's export placement failing.
    def passing_rate():
        res = {"export": {}, "playback": {}, "pitch": {}, "lag": {}, "sweep": {}}
        for side in ("export", "playback"):
            for name in RATE_ON_RAMPS:
                res[side][name] = {k: {"ok": True} for k in
                                   ("placement", "click", "dropout", "video")}
            for name in ON_ANCHORS:
                res[side][name] = {"placement": {"ok": True}}
        for name in RATE_ON_RAMPS + ON_ANCHORS:
            res["pitch"][name] = {"median_cents": 0.0}
        for name in RATE_ON_RAMPS:
            res["lag"][name] = {"rms_at_tau": 0.0}
        for name in SWEEP:
            res["sweep"][name] = {"ok": True}
        return res
    agree3 = {n: True for n in RATE_ON_RAMPS}
    go, _ = decide_rate(passing_rate(), agree3)
    bad = passing_rate()
    bad["export"]["RK3"]["placement"]["ok"] = False
    stop, why = decide_rate(bad, agree3)
    row("S18", go == "GO" and stop == "STOP" and "RK3" in why,
        f"passing results: {go}; RK3's export placement failing: {stop} — {why}")

    # S19: a ×2 render of glide.wav synthesised clean, then with a 20 ms dip to 0.03.
    clean = glide_signal(lambda t: glide_hz(SOURCE_IN / SEC + 2.0 * t), 6.0)
    ok_clean, ev_clean = sweep_dropouts(clean, RATE, 6.0, 2.0)
    dipped = list(clean)
    for n in range(int(0.9 * RATE), int(0.92 * RATE)):
        dipped[n] *= 0.03 / rs.AMPLITUDE
    ok_dip, ev_dip = sweep_dropouts(dipped, RATE, 6.0, 2.0)
    row("S19", ok_clean and not ev_clean and not ok_dip and len(ev_dip) == 1,
        f"the clean sweep: {len(ev_clean)} dropouts ({'passes' if ok_clean else 'fails'}); "
        f"a 20 ms dip to 0.03 at 0.9 s: {ev_dip} ({'passes' if ok_dip else 'fails'})")

    # S20: pick_lead — the min of the max, ties to the smaller lead, a missed click loses.
    full = {0: {"RK1": (33.5, 71, 71), "RK2": (49.4, 23, 23)},
            50: {"RK1": (11.0, 71, 71), "RK2": (10.5, 23, 23)},
            60: {"RK1": (8.9, 71, 71), "RK2": (2.9, 23, 23)},
            62: {"RK1": (8.9, 71, 71), "RK2": (8.9, 23, 23)},
            70: {"RK1": (2.0, 70, 71), "RK2": (1.0, 23, 23)}}
    none = {0: {"RK1": (5.0, 70, 71), "RK2": (5.0, 23, 23)},
            2: {"RK1": (5.0, 71, 71), "RK2": (None, 0, 0)}}
    got_full, got_none = pick_lead(full), pick_lead(none)
    row("S20", got_full == 60 and got_none is None,
        f"five leads (62 ms ties 60 at 8.9 ms, 70 ms lower but 70/71): {got_full} ms; "
        f"no eligible lead: {got_none}")

    # S21: the rate-mode command expects 220 Hz at ×0.2 and ×6 (SR-9's: 330 Hz at ×6).
    global CENTS_BOUND
    kept_bound = CENTS_BOUND
    try:
        CENTS_BOUND = RATE_CENTS_RANGE
        rate_hz = [expected_hz(control_ramp(True, r, 6.0), 1.0) for r in (0.2, 6.0)]
        CENTS_BOUND = CENTS_RANGE
        sr9_hz = expected_hz(control_ramp(True, 6.0, 6.0), 1.0)
    finally:
        CENTS_BOUND = kept_bound
    row("S21", all(abs(h - rs.SINE_HZ) <= 1e-9 for h in rate_hz) and abs(sr9_hz - 330.0) <= 1e-9,
        f"rate mode: ×0.2 {rate_hz[0]:.6f} Hz, ×6 {rate_hz[1]:.6f} Hz; SR-9's ×6 {sr9_hz:.6f} Hz")

    # S22: SR-17 — a ×2 tap ±86.333 ms off (#335), corrected by trimming, then by padding.
    v = {"keep": True, "kind": "control", "ideal": control_ramp(True, 2.0, 6.0),
         "length": 6 * SEC}
    export = place_ideal(train(v), RATE, v)
    sine = rs.sine(rs.SINE_HZ, 6.0)
    holds, notes = [], []
    for m1 in (-86.333, 86.333):
        k, residual = correction(m1, RATE)
        clicks = train(v, m1 / 1000)
        trimmed = side_rules(v, "S22", "playback",
                             (corrected_signal(clicks, RATE, k), corrected_signal(sine, RATE, k),
                              None, residual), {"place": {}, "dmax": {}})
        p = trimmed["placement"]["summary"]
        worst = p["max_abs_ms"]
        drops = trimmed["dropout"]["events"]
        agree_ok, agree_detail = agreement(export, p)
        trim_ok = (p["of"] > 0 and p["found"] == p["of"] and p.get("unobserved", 0) >= 1
                   and worst is not None and worst <= rs.SPREAD_MS and not drops
                   and agree_ok is True)
        padded = side_rules(v, "S22", "playback",
                            ((shift_signal(clicks, k), RATE, None),
                             (shift_signal(sine, k), RATE, None), None, residual),
                            {"place": {}, "dmax": {}})
        pad_drops = padded["dropout"]["events"]
        holds.append(trim_ok and len(pad_drops) >= 1)
        notes.append(f"m1 {m1:+.3f} ms (k {k}): trimmed {p['found']}/{p['of']}, "
                     f"{p.get('unobserved', 0)} unobserved, max |diff| "
                     + ("—" if worst is None else f"{worst:.3f} ms")
                     + f", {len(drops)} dropouts, agreement {agree_detail} "
                     f"({'passes' if agree_ok else 'fails'}); padded: {len(pad_drops)} dropouts "
                     f"at {[t for t, _ in pad_drops[:3]]}")
    row("S22", all(holds), "; ".join(notes))
    return all(rows), len(rows)


# ---- the runner -----------------------------------------------------------------


def fixture_path(fixture):
    if fixture == "glide":
        return GLIDE_WAV
    return BAND_WAV if fixture == "band" else rs.FIXTURES / rs.FIXTURE_FILES[fixture]


def render_path(name, fixture):
    return RENDERS / f"{name}@{fixture}.caf"


def write_r44():
    with wave.open(str(R44_WAV), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44_100)
        w.writeframes(array.array("h", (int(16000 * math.sin(2 * math.pi * 220 * n / 44_100))
                                        for n in range(44_100))).tobytes())


def write_band():
    rs.write_wav(BAND_WAV, rs.sine(BAND_HZ, rs.FIXTURE_S))


def render_jobs(names, everything):
    jobs = []
    for name in names:
        v = everything[name]
        if not v["rendered"]:
            continue
        for fixture in fixtures_of(v):
            jobs.append({"name": f"{name}@{fixture}", "source": str(fixture_path(fixture)),
                         "clip_ticks": v["map"][0], "source_ticks": v["map"][1],
                         "keep_pitch": v["keep"], "destination": str(render_path(name, fixture))})
    jobs.append({"name": "R44", "source": str(R44_WAV), "clip_ticks": [0, SEC],
                 "source_ticks": [0.0, float(SEC)], "keep_pitch": False,
                 "destination": str(RENDERS / "R44.caf")})
    return jobs


def project_json(v, name, fixture):
    if not v["rendered"]:
        return rs.project_json(v, fixture)
    clips = []
    next_id = 5
    for s in v["segs"]:
        clips.append({
            "id": next_id, "track": 3, "start": s["start"], "duration": s["duration"],
            "source": {"kind": "media", "media": 1, "in": s["in"]}, "speed": s["speed"],
            "enabled": {"video": True, "audio": False}, "video": {}, "audio": {"keep_pitch": False}})
        next_id += 1
    clips.append({"id": next_id, "track": 4, "start": 0, "duration": v["length"],
                  "source": {"kind": "media", "media": 2, "in": 0}, "speed": 1.0,
                  "audio": {"keep_pitch": False}})
    return {
        "version": 26,
        "canvas": {"width": rs.WIDTH, "height": rs.HEIGHT, "fps": [rs.FPS, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": True},
        "media": [{"id": 1, "path": str(fixture_path(fixture)), "kind": "video",
                   "duration": rs.MEDIA_DURATION, "width": rs.WIDTH, "height": rs.HEIGHT,
                   "fps": [rs.FPS, 1], "has_video": True, "has_audio": True},
                  {"id": 2, "path": str(render_path(name, fixture)), "kind": "audio",
                   "duration": v["length"], "has_video": False, "has_audio": True}],
        "tracks": [{"id": 3, "name": "Track 1"}, {"id": 4, "name": "Track 2"}],
        "clips": clips, "markers": [], "next_id": next_id + 1, "nests": [],
    }


def write_package(name, fixture, v):
    package = PROJECTS / f"{name}@{fixture}.framejob"
    shutil.rmtree(package, ignore_errors=True)
    package.mkdir(parents=True)
    (package / "project.json").write_text(json.dumps(project_json(v, name, fixture), indent=1))
    return package


def jobs_for(group, names, everything):
    jobs = []
    for name in names:
        for fixture in rs.FIXTURE_FILES:
            if group == "plan":
                reads = ["plan"]
            elif group == "export":
                reads = ["wav", "prores"] if fixture == "clicks" else ["wav"]
            else:
                reads = ["tap"] + (["frames"] if fixture == "clicks" and name in FRAME_SET else [])
            package = PROJECTS / f"{name}@{fixture}.framejob"
            jobs.append({"name": f"{name}@{fixture}", "fixture": fixture, "reads": reads,
                         "project": str(package if group == "playback"
                                        else package / "project.json"),
                         "length": everything[name]["length"]})
    return jobs


def plan_check(line, v):
    """A rendered variant's plan: the written video segments, and ONE audio
    track holding one ×1 segment [0, length) of the render, pitch `off`."""
    if not v["rendered"]:
        return rs.plan_check(line, v)
    plan = json.loads(Path(line["path"]).read_text())
    problems = []
    vt, at = plan.get("video_tracks", []), plan.get("audio_tracks", [])
    want = [(s["start"], s["duration"], s["in"], s["length"]) for s in v["segs"]]
    got = sorted((s["start"], s["duration"], s["source_in"], s["source_duration"])
                 for t in vt for s in t["segments"])
    if got != want:
        problems.append(f"video: {len(got)} segments, not the {len(want)} written")
    audio = [(s["start"], s["duration"], s["source_in"], s["source_duration"], s.get("pitch"))
             for t in at for s in t["segments"]]
    if audio != [(0, v["length"], 0, v["length"], "off")]:
        problems.append(f"audio: {audio[:3]}, not one ×1 segment of the render")
    return not problems, problems, sorted({str(a[4]) for a in audio})


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--groups", default=",".join(GROUPS))
    parser.add_argument("--variants", default=None)
    parser.add_argument("--remake", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS)
    parser.add_argument("--verdict", choices=["both", "on", "rate"], default="both")
    parser.add_argument("--lead-sweep", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        MUTANT = args.mutant
        ok, n = selftest()
        if MUTANT:
            print(f"mutant {MUTANT}: {'survived' if ok else 'caught'}")
            return 0 if ok else 1
        print(f"selftest: {'all ' + str(n) + ' rows hold' if ok else 'FAILED'}")
        return 0 if ok else 1
    if args.mutant:
        parser.error("--mutant needs --selftest")
    if args.verdict == "rate":
        global CENTS_BOUND
        CENTS_BOUND = RATE_CENTS_RANGE

    groups = [g for g in args.groups.split(",") if g]
    if any(g not in GROUPS for g in groups):
        parser.error(f"--groups takes {','.join(GROUPS)}")
    everything = variants()
    names = list(everything) if not args.variants else args.variants.split(",")
    unknown = [n for n in names if n not in everything]
    if unknown:
        parser.error(f"unknown variants: {unknown}")
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        print("NOT PERFORMED: ffmpeg and ffprobe are needed (the fixtures and the reads)")
        return 2
    if not rs.LIBRARY.exists():
        print(f"NOT PERFORMED: {rs.LIBRARY.relative_to(ROOT)} is missing — `make rust` first")
        return 2
    return run(args, groups, names, everything)


def run(args, groups, names, everything):
    score = rs.Score()
    started = time.time()
    rule_sha = hashlib.sha256(RULE_FILE.read_bytes()).hexdigest()
    info = rs.host()
    score.row("H0", "measured", f"{info['model']}, macOS {info['macos']}, load {info['load']}, "
              f"Frame Job pids {info['framejob_pids'] or 'none'}; rule_sha256 {rule_sha[:16]}…")
    past = [f"{n} ends at {source_end_ticks(everything[n]) / SEC:.3f} s" for n in names
            if source_end_ticks(everything[n]) > rs.SOURCE_LIMIT]
    if past:
        score.row("W0", "FAIL", "a variant reads past 19 s of the 20 s fixture: " + "; ".join(past))
        return 1
    WORK.mkdir(parents=True, exist_ok=True)
    RENDERS.mkdir(parents=True, exist_ok=True)
    try:
        rs.make_fixtures(args.remake)
        ok, detail = rs.z0()
    except rs.Failure as error:
        ok, detail = False, f"the fixtures could not be made or read: {error}"
    score.row("Z0", "ok" if ok else "FAIL", detail)
    if not ok:
        return 1
    rs.PROBE_DIR.mkdir(parents=True, exist_ok=True)
    shader, why = build_shader(str(rs.PROBE_DIR))
    score.row("B1", "ok" if shader else "FAIL", why or f"{Path(shader).name} beside the probe")
    if not shader:
        return 1
    binary, how = rs.build_probe(optimize=True, name="ramp-render-probe")
    score.row("B2", "ok" if binary else "FAIL", f"-O: {how}")
    if not binary:
        return 1
    if args.lead_sweep:
        return 0 if lead_sweep(binary) is not None else 1

    lines = {}
    if "render" in groups:
        write_r44()
        if any(everything[n]["kind"] == "band" for n in names):
            write_band()
        if any(everything[n]["kind"] == "sweep" for n in names):
            write_glide()
        jobs = render_jobs(names, everything)
        t0 = time.time()
        got, why = rs.run_group(binary, "render", jobs, work=WORK, walls=WALLS)
        lines.update(got)
        missing = [j["name"] for j in jobs if (j["name"], "render") not in got]
        failed = [f"{k[0]}: {v.get('error')}" for k, v in got.items()
                  if not v.get("ok") and k[0] != "R44"]
        ok = why is None and not missing and not failed
        score.row("R-render", "ok" if ok else "FAIL",
                  f"{len(got)}/{len(jobs)} renders answered in {time.time() - t0:.0f} s"
                  + (f"; {why}" if why else "") + (f"; missing {missing[:4]}" if missing else "")
                  + (f"; {len(failed)} failed: " + " | ".join(failed[:4]) if failed else ""))
        if not ok:
            score.instrument.append("R-render")
        r44 = got.get(("R44", "render"))
        ok = bool(r44) and r44.get("ok") is False and "unreadable" in str(r44.get("error"))
        score.row("R44", "ok" if ok else "FAIL", "a 44.1 kHz WAV: " + (
            f"refused — {r44.get('error')}" if r44 and not r44.get("ok")
            else "rendered" if r44 else "no answer"))
        if not ok:
            score.instrument.append("R44")

    shutil.rmtree(PROJECTS, ignore_errors=True)
    staged = [n for n in names if everything[n]["kind"] not in UNSTAGED]
    for name in staged:
        for fixture in rs.FIXTURE_FILES:
            write_package(name, fixture, everything[name])
    for group in ("plan", "export", "playback"):
        if group not in groups:
            continue
        t0 = time.time()
        jobs = jobs_for(group, staged, everything)
        got, why = rs.run_group(binary, group, jobs, work=WORK, walls=WALLS)
        lines.update(got)
        wanted = sum(len(j["reads"]) for j in jobs)
        failed = [f"{k[0]} {k[1]}: {v.get('error')}" for k, v in got.items() if not v.get("ok")]
        ok = why is None and len(got) == wanted and not failed
        score.row(f"R-{group}", "ok" if ok else "FAIL",
                  f"{len(got)}/{wanted} reads answered in {time.time() - t0:.0f} s"
                  + (f"; {why}" if why else "")
                  + (f"; {len(failed)} failed: " + " | ".join(failed[:4]) if failed else ""))
        if not ok:
            score.instrument.append(f"R-{group}")
    return score_run(score, groups, names, staged, everything, lines, started, rule_sha, info,
                     args.verdict)


def line_of(lines, name, fixture, read):
    got = lines.get((f"{name}@{fixture}", read))
    return got if got and got.get("ok") else None


def render_samples(name, fixture):
    path = render_path(name, fixture)
    return read_ffmpeg(path) if path.exists() else (None, None)


def side_rules(v, name, side, signals, ctx):
    """SR-7's rule outcomes for one variant on one side: {rule: {...}}.
    `ctx` holds this side's placements and D maxima so far, by name. A
    signal is (x, rate, window); with a window (SR-17) every rule reads the
    trimmed samples as the extent and reports its times + lo."""
    clicks_sig, sine_sig, bars, residual = signals
    out = {}
    length_s = v["length"] / SEC
    if clicks_sig is not None:
        s = place_ideal(clicks_sig[0], clicks_sig[1], v, residual, clicks_sig[2])
        ctx["place"][name] = s
        if not v["keep"]:
            ok = rs.varispeed_pass(s)
            out["placement"] = {"ok": ok, "summary": s}
        elif v["kind"] == "ramp":
            ctrls = [ctx["place"].get(c) for c in END_CONTROLS[name]]
            ok = rs.keep_place_pass(s, ctrls) if all(ctrls) else None
            out["placement"] = {"ok": ok, "summary": s}
        elif v["kind"] == "rcontrol":
            c_on = ctx["place"].get(name[1:])
            out["placement"] = {"ok": anchor_pass(s, c_on) if c_on else None, "summary": s,
                                "anchor": name[1:]}
        else:
            out["placement"] = {"ok": None, "summary": s}
    if sine_sig is not None:
        x, rate, window = sine_sig
        lo = 0.0 if window is None else window[0]
        span = length_s if window is None else window[1] - window[0]
        scan = dense_scan(x, rate, span)
        own = max(scan[1], default=0.0)
        if not v["keep"]:
            floor = 0.0
        elif v["kind"] == "ramp":
            have = [ctx["dmax"].get(c) for c in END_CONTROLS[name]]
            floor = max(have) if all(h is not None for h in have) else None
        else:
            floor = own
            ctx["dmax"][name] = own
        if floor is None:
            out["click"] = {"ok": None, "at": [], "events": []}
        else:
            ev = click_events(scan, floor)
            if window is not None:
                ev = [(round(t + lo, 4), d, r) for t, d, r in ev]
            out["click"] = {"ok": not ev, "at": [t for t, _, _ in ev], "floor": floor,
                            "events": [[t, d, r] for t, d, r in ev[:20]],
                            "worst_ratio": max((r for _, _, r in ev), default=None)}
        if window is None:
            drops = rs.events(rs.dropouts(x, rate, length_s, period_fn(v)))
        else:
            drops = rs.events(rs.dropouts(x, rate, span, lambda t: period_fn(v)(t + lo)))
            drops = [(round(t + lo, 4), kind) for t, kind in drops]
        out["dropout"] = {"ok": not drops, "events": drops[:20], "count": len(drops)}
    if bars is not None:
        wrong = rs.video_wrong(bars, v)
        out["video"] = {"ok": not wrong, "wrong": len(wrong), "of": v["length"] // FRAME,
                        "first": wrong[:5]}
    return out


def pitch_rows(score, names, everything, results, fixture_samples):
    """SR-9's reported rows from the renders themselves: RP, PR, PR-source,
    LG and BW (pitch and its lag are scored by `decide_on`)."""
    keep = [n for n in names if everything[n]["rendered"] and everything[n]["keep"]
            and everything[n]["kind"] not in ("band", "sweep")]
    for name in keep:
        v = everything[name]
        x, rate = render_samples(name, "clicks")
        if x:
            s = place_ideal(x, rate, v)
            results["rp"][name] = s
            score.row(f"RP-{name}", "measured",
                      f"the render's clicks: {s['found']}/{s['of']}, median "
                      + (f"{s['median_ms']:+.3f} ms, max |diff| {s['max_abs_ms']:.2f} ms"
                         if s["median_ms"] is not None else "none found"))
    for name in keep:
        v = everything[name]
        x, rate = render_samples(name, "sine")
        if not x:
            continue
        track = pitch_track(x, rate, v["length"] / SEC)
        pr = pitch_reading(track, v["ideal"])
        results["pitch"][name] = pr
        score.row(f"PR-{name}", "measured",
                  f"{pr['windows']} windows, median {pr['median_hz']:.3f} Hz, median "
                  f"{pr['median_cents']:+.2f} cents, |cents| median {pr['median_abs_cents']:.2f}, "
                  f"max {pr['max_abs_cents']:.2f}" if pr["windows"] else "no window read")
        if name in RATE_ON_RAMPS and track:
            tau, at_tau, at0 = pitch_lag(track, v["ideal"])
            results["lag"][name] = {"tau_s": tau, "rms_at_tau": at_tau, "rms_at_0": at0}
            score.row(f"LG-{name}", "measured",
                      f"τ {tau * 1000:+.0f} ms, RMS {at_tau:.2f} cents at τ, {at0:.2f} at 0")
    if keep:
        x = fixture_samples("sine")
        flat = control_ramp(True, 1.0, 6.0)
        pr = pitch_reading(pitch_track(x[RATE:7 * RATE], RATE, 6.0) if x else [], flat)
        results["pitch_source"] = pr
        score.row("PR-source", "measured",
                  f"the sine fixture over [1 s, 7 s): {pr['windows']} windows, median "
                  f"{pr['median_hz']:.3f} Hz, median {pr['median_cents']:+.3f} cents, max "
                  f"|cents| {pr['max_abs_cents']:.3f}" if pr["windows"]
                  else "the sine fixture over [1 s, 7 s): no window read")
    for name in [n for n in names if everything[n]["kind"] == "band"]:
        x, rate = render_samples(name, "band")
        if not x or not BAND_WAV.exists():
            continue
        src, src_rate = rs.read_channel0(BAND_WAV)
        got = band_level_db(x, rate, BAND_HZ, 1.0, 5.0)
        ref = band_level_db(src, src_rate, BAND_HZ, 1.0, 11.0)
        results["bw"][name] = {"render_db": got, "source_db": ref, "db": got - ref}
        score.row(f"BW-{name}", "measured",
                  f"{BAND_HZ:g} Hz over [1 s, 5 s): {got - ref:+.2f} dB re band.wav over "
                  f"[1 s, 11 s) ({got:.2f} against {ref:.2f} dBFS)")
    for name in [n for n in names if everything[n]["kind"] == "sweep"]:
        v = everything[name]
        x, rate = render_samples(name, "glide")
        if not x:
            continue
        ok, drops = sweep_dropouts(x, rate, v["length"] / SEC, v["ramp"][1])
        results["sweep"][name] = {"ok": ok, "count": len(drops), "events": drops[:20]}
        score.row(name, "ok" if ok else "FAIL",
                  f"glide.wav at ×{v['ramp'][1]:g}: {len(drops)} dropouts"
                  + (f" from {[e[0] for e in drops[:6]]}" if drops else ""))


def fmt_drop(rule):
    return "?" if rule and rule.get("ok") is None else rs.fmt_drop(rule)


def signals_of(lines, name, v, side, shift):
    """(clicks (x, rate, window), sine (x, rate, window), bars, residual s)
    for one side; `shift` = (k, residual) moves a rendered variant's playback
    by m1, trimmed (SR-17). Export's window is None."""
    if side == "export":
        c, s, p = (line_of(lines, name, "clicks", "wav"), line_of(lines, name, "sine", "wav"),
                   line_of(lines, name, "clicks", "prores"))
        return (rs.read_channel0(Path(c["path"])) + (None,) if c else None,
                rs.read_channel0(Path(s["path"])) + (None,) if s else None,
                rs.gray_bars(Path(p["path"])) if p else None, 0.0)
    c, s, f = (line_of(lines, name, "clicks", "tap"), line_of(lines, name, "sine", "tap"),
               line_of(lines, name, "clicks", "frames"))
    k, residual = shift
    out = []
    for got in (c, s):
        if got and got.get("chunks"):
            x, rate = rs.tap_signal(got, v["length"])
            out.append(corrected_signal(x, rate, k))
        else:
            out.append(None)
    return out[0], out[1], (f["bars"] if f else None), residual


def score_run(score, groups, names, staged, everything, lines, started, rule_sha, info,
              verdict_of="both"):
    if "plan" in groups:
        for name in staged:
            ok_all, problems, pitches = True, [], set()
            for fixture in rs.FIXTURE_FILES:
                got = line_of(lines, name, fixture, "plan")
                if got is None:
                    ok_all, problems = False, problems + [f"{fixture}: no plan read"]
                    continue
                ok, why, p = plan_check(got, everything[name])
                ok_all &= ok
                problems += [f"{fixture}: {w}" for w in why]
                pitches |= set(p)
            score.row(f"Q-{name}", "ok" if ok_all else "FAIL",
                      f"{len(everything[name]['segs'])} video segments as written, audio "
                      + ("one ×1 segment of the render" if everything[name]["rendered"]
                         else "as written") + f", pitch {sorted(pitches)}"
                      if ok_all else "; ".join(problems))

    fixtures = {}

    def fixture_samples(fixture):
        if fixture not in fixtures:
            fixtures[fixture] = read_ffmpeg(fixture_path(fixture))[0]
        return fixtures[fixture]

    # The ×1 identity (an instrument check).
    if "RC-off-x1" in names and ("render" in groups or render_path("RC-off-x1", "sine").exists()):
        v = everything["RC-off-x1"]
        n, offset = round(v["length"] / TICKS_PER_FRAME), round(SOURCE_IN / TICKS_PER_FRAME)
        parts, ok_all = [], True
        for fixture in rs.FIXTURE_FILES:
            render, _ = render_samples("RC-off-x1", fixture)
            ok, worst = identity(render, fixture_samples(fixture), offset, n) if render else (
                False, None)
            ok_all &= ok
            parts.append(f"{fixture} max |diff| {worst if worst is None else f'{worst:.2e}'}")
        score.row("ID1", "ok" if ok_all else "FAIL",
                  f"RC-off-x1's render against the fixture over [1 s, 7 s): " + "; ".join(parts))
        if not ok_all:
            score.instrument.append("ID1")

    # Render reports (reported, not scored).
    reports = {}
    for name in names:
        v = everything[name]
        if not v["rendered"]:
            continue
        got = [lines.get((f"{name}@{fx}", "render")) for fx in fixtures_of(v)]
        got = [g for g in got if g and g.get("ok")]
        if not got:
            continue
        audio_s = got[0]["frames"] / RATE
        wall = statistics.mean(g["wall_s"] for g in got)
        rep_ = {"wall_s": wall, "wall_per_audio_s": wall / audio_s, "bytes": got[0]["bytes"],
                "bytes_per_audio_s": got[0]["bytes"] / audio_s, "channels": got[0]["channels"],
                "peak_rss_bytes": max(g["peak_rss_bytes"] for g in got)}
        if v["keep"]:
            map_frames = round((v["map"][1][-1] - v["map"][1][0]) / TICKS_PER_FRAME)
            rep_["lead_frames"] = got[0]["lead_frames"]
            rep_["latency_frames"] = got[0]["latency_frames"]
            rep_["map_frames"] = map_frames
            rep_["pulled_minus_map_frames"] = [g["pulled_frames"] - map_frames for g in got]
        reports[name] = rep_
        score.row(f"RS-{name}", "measured",
                  f"{wall:.3f} s for {audio_s:g} s of audio ({rep_['wall_per_audio_s']:.4f} s/s), "
                  f"{rep_['bytes']} bytes ({rep_['bytes_per_audio_s']:.0f} B/s), peak RSS "
                  f"{rep_['peak_rss_bytes'] / 2**20:.1f} MiB"
                  + (f"; lead {rep_['lead_frames']} frames, latency {rep_['latency_frames']} "
                     f"frames, pulled − map frames {rep_['pulled_minus_map_frames']}"
                     if v["keep"] else ""))
    if "RV1-edit" in names and "RV1" in names:
        a, _ = render_samples("RV1", "sine")
        b, _ = render_samples("RV1-edit", "sine")
        if a and b:
            same = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
            score.row("RE1", "measured",
                      f"RV1-edit (ending ×2.5) rendered in {reports.get('RV1-edit', {}).get('wall_s', 0):.3f} s "
                      f"(RV1 {reports.get('RV1', {}).get('wall_s', 0):.3f} s); its first {same} samples "
                      f"({same / RATE:.4f} s) equal RV1's")
            reports.setdefault("RV1-edit", {})["leading_equal"] = same

    results = {"export": {}, "playback": {}, "pitch": {}, "lag": {}, "rp": {}, "bw": {},
               "sweep": {}}
    pitch_rows(score, names, everything, results, fixture_samples)
    sides = [s for s in ("export", "playback") if s in groups]
    rank = {"control": 0, "rcontrol": 1, "ramp": 2, "fault": 3}
    order = sorted(staged, key=lambda n: (rank[everything[n]["kind"]], n))
    pt1_ok, m1, raw_x1 = None, None, None
    for side in sides:
        ctx = {"place": {}, "dmax": {}}
        shift = (0, 0.0)
        if side == "playback":
            if "RC-off-x1" not in names:
                score.row("PT1", "unmeasured", "RC-off-x1 is not among the variants run")
            else:
                got = lines.get(("RC-off-x1@clicks", "tap"))
                e = results["export"].get("RC-off-x1", {}).get("placement")
                if not got or not got.get("ok") or not got.get("calls"):
                    pt1_ok = False
                    score.row("PT1", "FAIL", "the tap of RC-off-x1 was never called")
                    score.instrument.append("PT1")
                elif not e:
                    score.row("PT1", "unmeasured", "RC-off-x1's export placement was not read")
                else:
                    x, rate = rs.tap_signal(got, everything["RC-off-x1"]["length"])
                    k0 = int(round(coarse_ms(x, rate, everything["RC-off-x1"]) * rate / 1000))
                    raw_x1 = place_corrected(x, rate, everything["RC-off-x1"], k0)
                    pt1_ok, fine = pt1(e["summary"], raw_x1)
                    m1 = None if fine is None else fine + k0 * 1000 / rate
                    score.row("PT1", "ok" if pt1_ok else "measured",
                              f"RC-off-x1's tap ({got.get('calls')} calls, coarse {k0} samples): "
                              f"{raw_x1['found']}/{raw_x1['of']}, median "
                              + (f"{raw_x1['median_ms']:+.3f} ms, spread "
                                 f"{raw_x1['spread_ms']:.3f} ms; m1 {m1:+.3f} ms"
                                 if m1 is not None else "none found")
                              + ("" if pt1_ok else " — rendered playback audio is unmeasured"))
                    if pt1_ok:
                        shift = correction(m1, rate)
        for name in order:
            v = everything[name]
            sig = signals_of(lines, name, v, side, shift if v["rendered"] else (0, 0.0))
            rules = side_rules(v, name, side, sig, ctx)
            if side == "playback" and v["rendered"] and pt1_ok is not True:
                for key in ("placement", "click", "dropout"):
                    if key in rules:
                        rules[key]["ok"] = None
                        rules[key]["unmeasured"] = True
            results[side][name] = rules
            del sig

    # E, P and A rows.
    agree = {}
    for name in staged:
        v = everything[name]
        scored = name in FRAME_SET or v["kind"] == "rcontrol" and v["keep"]
        for side in sides:
            rules = results[side][name]
            detail = " · ".join(
                f"{label} {f(rules.get(k))}" for label, k, f in (
                    ("place", "placement", lambda r: rs.fmt_place(r, v["keep"])),
                    ("click", "click", rs.fmt_click), ("drop", "dropout", fmt_drop),
                    ("video", "video", rs.fmt_video)))
            if v["kind"] == "rcontrol" and v["keep"]:
                detail += f" (anchor {rules.get('placement', {}).get('anchor')}; the rest reported)"
                bad = rs.failed_rules(rules, keys=["placement"])
            else:
                bad = rs.failed_rules(rules, keys=["placement", "click", "dropout", "video"])
            status = "ok" if scored and not bad else "FAIL" if scored else "measured"
            score.row(f"{side[0].upper()}-{name}", status, detail, rules=rs._jsonable(rules))
        if "export" in sides and "playback" in sides:
            e = results["export"][name].get("placement")
            p = results["playback"][name].get("placement")
            if v["rendered"] and pt1_ok is not True:
                agree[name] = None
                score.row(f"A-{name}", "unmeasured", "PT1 did not pass")
                continue
            ok, detail = agreement(e and e["summary"], p and p["summary"],
                                   keep_rule=not v["rendered"] and v["keep"])
            agree[name] = ok
            status = ("measured" if not v["rendered"] or name not in FRAME_SET
                      else "ok" if ok else "FAIL")
            score.row(f"A-{name}", status, detail + ("" if v["rendered"] else " (SR-5's rule)"))

    # Export against render, offset 0 (reported).
    if "export" in sides:
        for name in staged:
            if not everything[name]["rendered"]:
                continue
            parts = []
            for fixture in rs.FIXTURE_FILES:
                got = line_of(lines, name, fixture, "wav")
                render, _ = render_samples(name, fixture)
                if not got or not render:
                    continue
                x, _ = rs.read_channel0(Path(got["path"]))
                n = min(len(x), len(render))
                worst = max((abs(x[i] - render[i]) for i in range(n)), default=None)
                parts.append(f"{fixture} {worst:.2e} over {n}" if worst is not None else fixture)
            if parts:
                score.row(f"XR-{name}", "measured", "export WAV − render, max |diff| at offset 0: "
                          + "; ".join(parts))

    # Reported: PT0 and C-off-x1's raw tap (#335).
    if "playback" in sides:
        for name, rid in (("C-off-x2", "PT0"), ("C-off-x1", "T335")):
            rule = results["playback"].get(name, {}).get("placement")
            if rule:
                s = rule["summary"]
                score.row(rid, "measured", f"{name}'s tap: {s['found']}/{s['of']}, median "
                          + (f"{s['median_ms']:+.3f} ms, spread {s['spread_ms']:.3f} ms"
                             if s["median_ms"] is not None else "none found"))

    # Instrument checks.
    if "export" in sides:
        for name in [n for n in names if n.startswith("C-off-")]:
            r = results["export"][name]
            keys = ("placement", "dropout") if name == "C-off-x4" else (
                "placement", "click", "dropout")
            bad = rs.failed_rules(r, keys=keys)
            if bad:
                score.instrument.append(f"{name}: {', '.join(bad)}")
            if name == "C-off-x4":
                score.row("I334", "measured", f"C-off-x4's export click (#334, never a failure): "
                          f"{rs.fmt_click(r.get('click'))}")
        if "RF1" in names:
            r = results["export"]["RF1"]
            at = r.get("click", {}).get("at") or []
            near = len(at) == 1 and abs(at[0] - rs.F1_FROM / SEC) <= RF1_NEAR_S
            fails = r.get("placement", {}).get("ok") is False
            score.row("F1", "ok" if near and fails else "FAIL",
                      f"RF1 export: {len(at)} click event(s) at {at[:6]}; placement "
                      f"{'fails' if fails else 'passes'}")
            if not (near and fails):
                score.instrument.append("RF1")
    if score.instrument:
        score.row("I0", "FAIL", "instrument checks failed: " + "; ".join(score.instrument))
    else:
        score.row("I0", "ok", "every instrument check that ran holds")

    print()
    head = ("| variant | arm | E place | E click | E drop | E video | P place | P click | P drop | "
            "P video | A | render s/s |")
    table = [head, "|" + "---|" * 12]
    for name in names:
        v = everything[name]
        e, p = results["export"].get(name, {}), results["playback"].get(name, {})
        a = agree.get(name)
        arm = ("off" if name in OFF_MEMBERS else "on" if name in RATE_ON_RAMPS
               else "on (anchor)" if name in ON_ANCHORS else "—")
        rep_ = reports.get(name, {})
        cells = [name, arm, rs.fmt_place(e.get("placement"), v["keep"]), rs.fmt_click(e.get("click")),
                 fmt_drop(e.get("dropout")), rs.fmt_video(e.get("video")),
                 rs.fmt_place(p.get("placement"), v["keep"]), rs.fmt_click(p.get("click")),
                 fmt_drop(p.get("dropout")), rs.fmt_video(p.get("video")),
                 "—" if a is None else ("ok" if a else "✗"),
                 f"{rep_['wall_per_audio_s']:.4f}" if "wall_per_audio_s" in rep_ else "—"]
        table.append("| " + " | ".join(cells) + " |")
    print("\n".join(table))
    verdict, why = (decide_on(results, agree) if verdict_of == "on"
                    else decide_rate(results, agree) if verdict_of == "rate"
                    else decide(results, agree))
    print(f"\nVERDICT: {verdict} — {why}")
    RESULTS.write_text(json.dumps({
        "commit": rs.commit(), "date": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "seconds": round(time.time() - started), "rule_sha256": rule_sha, "host": info,
        "m1_ms": m1, "pt1": pt1_ok, "rows": score.rows, "renders": reports,
        "variants": {n: {"map_breakpoints": len(everything[n]["map"][0]) if everything[n]["map"]
                         else None,
                         "export": rs._jsonable(results["export"].get(n)),
                         "playback": rs._jsonable(results["playback"].get(n)),
                         **{k: rs._jsonable(results[k][n]) for k in ("rp", "pitch", "lag", "bw",
                                                                     "sweep")
                            if n in results[k]}} for n in names},
        "pitch_source": rs._jsonable(results.get("pitch_source")), "verdict_of": verdict_of,
        "table": table, "verdict": {"verdict": verdict, "detail": why},
    }, indent=1))
    return 1 if score.instrument else 0


if __name__ == "__main__":
    sys.exit(main())
