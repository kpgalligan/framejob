#!/usr/bin/env python3
"""The speed-ramp spike — road map "speed-ramps", SR1 (#111, spec §11 SR-5).

Does a ramp's plan — many abutting constant-rate segments, which is what
`scaleTimeRange` can play — click, drop out, or misplace audio or frames, in
export and in playback? Measured on synthetic fixtures through the app's own
`CompositionBuilder`, `Exporter` and editor player, by `ramp_spike_probe.swift`
compiled AS `main.swift` over `app/Sources`, against constant-rate controls and
a planted fault, by SR-5's rule (fixed before the run; `results.json` pins the
§11 file's SHA-256). The answers are in `archive/speed-ramps.md`'s SR1 record.

    python3 tools/proof/ramp_spike/ramp_spike.py [--groups plan,export,playback]
        [--variants V1-G1,C-off-x2,…] [--remake]
    python3 tools/proof/ramp_spike/ramp_spike.py --selftest [--mutant NAME]

Exit 0: every requested row answered (whatever the VERDICT). Exit 1: an
instrument check failed — Z0, a `C-off-*` control in export, F1, PT0's tap
never called, a variant reading past 19 s of the 20 s fixture, the build, a
probe crash or expiry, a read that failed. Exit 2: not performed (no
`ffmpeg`/`ffprobe`, no `core/target/release/libframejob_core.a`). Under
`--selftest --mutant`: 1 caught, 0 survived. Everything written is under
`tools/proof/work/ramp-spike/` (gitignored). No app instance, no socket, no
MCP, no network; every child runs under `graphics_spike/bounded.py`.
"""

import argparse
import array
import bisect
import hashlib
import itertools
import json
import math
import os
import shutil
import statistics
import sys
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "tools/proof"
SPIKE = HERE / "ramp_spike"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402
from export_offset_proof import click_value, read_ffmpeg, summary, template  # noqa: E402
from media_less_playback_probe import build_shader  # noqa: E402

WORK = HERE / "work/ramp-spike"
FIXTURES = WORK / "fixtures"
PROJECTS = WORK / "projects"
RUNS = WORK / "runs"
PROBE_DIR = WORK / "probe"
RESULTS = WORK / "results.json"
PROBE_SWIFT = SPIKE / "ramp_spike_probe.swift"
BLANK = ROOT / "app/Resources/Blank.mp4"
LIBRARY = ROOT / "core/target/release/libframejob_core.a"
RULE_FILE = ROOT / "designs/spec/11-decisions/speed-ramps.md"

SEC = 600_000
FRAME = 20_000
FPS = 30
RATE = 48_000
WIDTH, HEIGHT = 320, 180
FIXTURE_S = 20
FIXTURE_FRAMES = FIXTURE_S * FPS
MEDIA_DURATION = 12_000_000
SOURCE_IN = 600_000
SOURCE_LIMIT = 19 * SEC
CLICKS = [round((0.1 + 0.2 * n) * SEC) for n in range(100)]  # source ticks
SINE_HZ = 220.0
AMPLITUDE = 0.5
FIXTURE_FILES = {"clicks": "ramp-clicks-v1.mov", "sine": "ramp-sine-v1.mov"}

BUILD_WALL = 900
WALLS = {"plan": 120, "export": 900, "playback": 1800}
GROUPS = ["plan", "export", "playback"]

# SR-5's numbers.
FOUND_SHARE = 0.90
TARGET_MS = 1.0
SPREAD_MS = 0.5
KEEP_FOUND_SLACK = 0.10
KEEP_DIFF_SLACK_MS = 5.0
EDGE_SKIP_S = 0.002
REACH_MAX_MS = 60.0
REACH_SHARE = 0.4
CLICK_HALF_S = 0.002
CLICK_GRID_S = 0.002
CLICK_SPAN_S = 0.100
CLICK_CLEAR_S = 0.005
CLICK_FACTOR = 4.0
FAKE_STEP_S = 1 / 30
DROP_EDGE_S = 0.050
DROP_STEP_S = 0.001
DROP_SPAN_S = 0.050
DROP_FACTOR = 0.7
DROP_FLOOR = 0.02
DROP_RUN_S = 0.001
EXCUSE_TICKS = 2
AGREE_KEEP_MS = 5.0
LEAD_NEAR_S = 0.005  # GO-UNIFORM-LEAD: a dropout "at" the 1 s boundary
F1_FROM = 2 * SEC
F1_SHIFT = 2_400

# name: (keep pitch, from rate, to rate, curve, ramp start s, ramp end s, length s)
RAMPS = {
    "V1": (False, 1.0, 2.0, "linear", 1.0, 3.0, 8.0),
    "V2": (False, 2.0, 0.5, "ease_in_out", 1.0, 4.0, 8.0),
    "V3": (False, 0.25, 4.0, "ease_in", 0.5, 4.5, 6.0),
    "K1": (True, 1.1, 2.0, "linear", 1.0, 3.0, 8.0),
    "K2": (True, 0.9, 0.5, "ease_out", 1.0, 3.0, 8.0),
}
GRAINS = (1, 4, 15)
# name: (keep pitch, rate, length s)
CONTROLS = {
    "C-off-x1": (False, 1.0, 6.0), "C-off-x0.25": (False, 0.25, 6.0),
    "C-off-x0.5": (False, 0.5, 6.0), "C-off-x2": (False, 2.0, 6.0),
    "C-off-x4": (False, 4.0, 4.0),
    "C-on-x0.5": (True, 0.5, 6.0), "C-on-x0.9": (True, 0.9, 6.0),
    "C-on-x1.1": (True, 1.1, 6.0), "C-on-x2": (True, 2.0, 6.0),
}
END_CONTROLS = {"K1": ("C-on-x1.1", "C-on-x2"), "K2": ("C-on-x0.9", "C-on-x0.5")}
VERDICT_SET = [f"{v}-G1" for v in RAMPS]
FRAME_SET = VERDICT_SET + ["V1L", "C-off-x1", "C-off-x2"]
MUTANTS = ["click-off", "dropout-off", "pin-off", "excuse-all", "kwindow-off"]

MUTANT = None


# ---- the map S and the variants -------------------------------------------------


def ease_integral(curve, u):
    """∫₀ᵘ ease(v) dv for `actions.rs`'s four curves."""
    if curve == "linear":
        return u * u / 2
    if curve == "ease_in":
        return u ** 3 / 3
    if curve == "ease_out":
        return u - (1 - (1 - u) ** 3) / 3
    if curve == "ease_in_out":
        return u ** 3 - u ** 4 / 2
    raise ValueError(curve)


def source_of(ramp, t):
    """S(t) in ticks: the source a ramp has read by clip time t (ticks)."""
    _, r0, r1, curve, a_s, b_s, _ = ramp
    a, b = a_s * SEC, b_s * SEC
    if t <= a:
        return r0 * t
    if t < b:
        u = (t - a) / (b - a)
        return r0 * a + (b - a) * (r0 * u + (r1 - r0) * ease_integral(curve, u))
    return r0 * a + (b - a) * (r0 + (r1 - r0) * ease_integral(curve, 1.0)) + r1 * (t - b)


def inverse_of(ramp, s, length):
    """The clip time (ticks) at which the continuous S reaches s."""
    lo, hi = 0.0, float(length)
    for _ in range(80):
        mid = (lo + hi) / 2
        if source_of(ramp, mid) < s:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def seg(start, duration, source_in, length):
    return {"start": start, "duration": duration, "in": source_in, "length": length,
            "speed": length / duration}


def ramp_segments(ramp, grain):
    _, _, _, _, a_s, b_s, length_s = ramp
    a, b, length = round(a_s * SEC), round(b_s * SEC), round(length_s * SEC)
    bounds = [0] if a == 0 else [0, a]
    t = a
    while t + grain * FRAME < b:
        t += grain * FRAME
        bounds.append(t)
    bounds += [b, length]
    ins = [SOURCE_IN + round(source_of(ramp, t)) for t in bounds]
    return [seg(bounds[k], bounds[k + 1] - bounds[k], ins[k], ins[k + 1] - ins[k])
            for k in range(len(bounds) - 1)]


def variants():
    """name → {keep, segs (as written), ref (the expectation's segments),
    length, ramp, kind, controls}."""
    out = {}
    for name, ramp in RAMPS.items():
        for grain in GRAINS:
            segs = ramp_segments(ramp, grain)
            out[f"{name}-G{grain}"] = {
                "keep": ramp[0], "segs": segs, "ref": segs, "length": round(ramp[6] * SEC),
                "ramp": ramp, "kind": "ramp", "controls": END_CONTROLS.get(name)}
    base = out["V1-G1"]
    lead = [dict(s) for s in base["segs"]]
    lead[0] = seg(lead[0]["start"], lead[0]["duration"], lead[0]["in"], lead[0]["length"] + 1)
    out["V1L"] = dict(base, segs=lead, ref=lead, kind="lead")
    fault = [seg(s["start"], s["duration"], s["in"] + (F1_SHIFT if s["start"] >= F1_FROM else 0),
                 s["length"]) for s in base["segs"]]
    out["F1"] = dict(base, segs=fault, ref=base["segs"], kind="fault")
    for name, (keep, rate, length_s) in CONTROLS.items():
        length = round(length_s * SEC)
        segs = [seg(0, length, SOURCE_IN, round(length * rate))]
        out[name] = {"keep": keep, "segs": segs, "ref": segs, "length": length,
                     "ramp": (keep, rate, rate, "linear", 0.0, 0.0, length_s), "kind": "control",
                     "controls": (name, name) if keep else None}
    return out


def source_end(v):
    return max(s["in"] + s["length"] for s in v["segs"])


def segment_at(segs, t):
    """The segment holding clip time t (ticks); the last one past the end."""
    starts = [s["start"] for s in segs]
    return segs[max(0, bisect.bisect_right(starts, t) - 1)]


def expected_clicks(v):
    """[(source tick, expected timeline s, local rate)] by the inverse of the
    reference segments, clicks within 2 ms of the clip's edges skipped."""
    out = []
    length_s = v["length"] / SEC
    for c in CLICKS:
        for s in v["ref"]:
            if s["in"] <= c < s["in"] + s["length"]:
                t = (s["start"] + (c - s["in"]) / s["speed"]) / SEC
                if EDGE_SKIP_S <= t <= length_s - EDGE_SKIP_S:
                    out.append((c, t, s["speed"]))
                break
    return out


def ideal_error_ms(v):
    if v["kind"] == "control":
        return 0.0
    worst = 0.0
    for c, t, _ in expected_clicks(v):
        cont = inverse_of(v["ramp"], c - SOURCE_IN, v["length"]) / SEC
        worst = max(worst, abs(t - cont) * 1000)
    return worst


def expected_frames(v):
    """Per timeline frame k: the set of source frame indices it may show."""
    out = []
    for k in range(v["length"] // FRAME):
        t = k * FRAME
        s = segment_at(v["ref"], t)
        src = s["in"] + (t - s["start"]) * s["speed"]
        m = round(src / FRAME)
        if abs(src - m * FRAME) <= EXCUSE_TICKS or MUTANT == "excuse-all":
            allowed = {m - 1, m} if MUTANT != "excuse-all" else {
                math.floor(src / FRAME) - 1, math.floor(src / FRAME), math.floor(src / FRAME) + 1}
        else:
            allowed = {math.floor(src / FRAME)}
        out.append(allowed)
    return out


def boundaries_s(v):
    return [s["start"] / SEC for s in v["segs"][1:]]


def rate_at(v):
    segs = v["segs"]
    return lambda t: segment_at(segs, t * SEC)["speed"]


def project_json(v, fixture):
    clips = []
    for k, s in enumerate(v["segs"]):
        clips.append({
            "id": 3 + k, "track": 2, "start": s["start"], "duration": s["duration"],
            "source": {"kind": "media", "media": 1, "in": s["in"]}, "speed": s["speed"],
            "video": {}, "audio": {"keep_pitch": v["keep"]}})
    return {
        "version": 26,
        "canvas": {"width": WIDTH, "height": HEIGHT, "fps": [FPS, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": True},
        "media": [{"id": 1, "path": str(FIXTURES / FIXTURE_FILES[fixture]), "kind": "video",
                   "duration": MEDIA_DURATION, "width": WIDTH, "height": HEIGHT,
                   "fps": [FPS, 1], "has_video": True, "has_audio": True}],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": clips, "markers": [], "next_id": 3 + len(clips), "nests": [],
    }


def write_package(name, fixture, v):
    package = PROJECTS / f"{name}@{fixture}.framejob"
    shutil.rmtree(package, ignore_errors=True)
    package.mkdir(parents=True)
    (package / "project.json").write_text(json.dumps(project_json(v, fixture), indent=1))
    return package


# ---- the classifiers (SR-5) -----------------------------------------------------


def second_diff(x):
    d = [0.0] * len(x)
    for n in range(2, len(x)):
        d[n] = abs(x[n] - 2 * x[n - 1] + x[n - 2])
    return d


def wmax(d, rate, lo_s, hi_s):
    a, b = max(0, int(round(lo_s * rate))), min(len(d), int(round(hi_s * rate)) + 1)
    return max(d[a:b]) if b > a else 0.0


def clear_of(edges, c):
    i = bisect.bisect_left(edges, c)
    near = [edges[j] for j in (i - 1, i) if 0 <= j < len(edges)]
    return all(abs(c - e) >= CLICK_CLEAR_S for e in near)


def click_scan(x, rate, bounds, length_s, *, half_s=CLICK_HALF_S, threshold=None, d=None):
    """[(b, D, threshold, clicked)] per boundary ≥ 5 ms inside the clip.
    With `threshold` None it is 4·L, L from 4 ms windows every 2 ms within
    ±100 ms clear of every boundary (the clip's edges count)."""
    d = d if d is not None else second_diff(x)
    edges = sorted(set(bounds) | {0.0, length_s})
    out = []
    for b in bounds:
        if b < CLICK_CLEAR_S or b > length_s - CLICK_CLEAR_S:
            continue
        D = wmax(d, rate, b - half_s, b + half_s)
        if threshold is None:
            stats = []
            for j in range(-50, 51):
                c = b + j * CLICK_GRID_S
                if 2 * CLICK_HALF_S <= c <= length_s - 2 * CLICK_HALF_S and clear_of(edges, c):
                    stats.append(wmax(d, rate, c - CLICK_HALF_S, c + CLICK_HALF_S))
            thr = CLICK_FACTOR * statistics.median(stats) if stats else math.inf
        else:
            thr = threshold
        if MUTANT == "click-off":
            thr = math.inf
        out.append((b, D, thr, D > thr))
    return out


def keep_half_s(w_ms):
    return CLICK_HALF_S if MUTANT == "kwindow-off" else CLICK_HALF_S + w_ms / 1000


def fake_bounds(length_s):
    out, k = [], 1
    while k * FAKE_STEP_S <= length_s - DROP_EDGE_S:
        if k * FAKE_STEP_S >= DROP_EDGE_S:
            out.append(k * FAKE_STEP_S)
        k += 1
    return out


def keep_threshold(controls, w_ms):
    """(threshold, L_c, D_c) from the end-rate controls' sine outputs
    [(x, rate, length_s)]: max(4·L_c, D_c)."""
    stats, worst = [], 0.0
    half = keep_half_s(w_ms)
    for x, rate, length_s in controls:
        d = second_diff(x)
        c = DROP_EDGE_S
        while c <= length_s - DROP_EDGE_S:
            stats.append(wmax(d, rate, c - CLICK_HALF_S, c + CLICK_HALF_S))
            c += CLICK_GRID_S
        for b in fake_bounds(length_s):
            worst = max(worst, wmax(d, rate, b - half, b + half))
    l_c = statistics.median(stats) if stats else math.inf
    return max(CLICK_FACTOR * l_c, worst), l_c, worst


def dropouts(x, rate, length_s, period_s):
    """[(t s, kind)]: (a) one-period RMS < 0.7 × its median within ±50 ms;
    (b) ≥ 1 ms under |x| < 0.02. `period_s(t)` is the local output period."""
    if MUTANT == "dropout-off":
        return []
    lo, hi = int(DROP_EDGE_S * rate), min(len(x), int((length_s - DROP_EDGE_S) * rate))
    if hi <= lo:
        return []
    squares = [0.0] + list(itertools.accumulate(v * v for v in x))
    centres, rms = [], []
    t = DROP_EDGE_S
    while t <= length_s - DROP_EDGE_S:
        n = max(2, int(round(period_s(t) * rate)))
        c = int(round(t * rate))
        a, b = max(0, c - n // 2), min(len(x), c - n // 2 + n)
        if b - a >= 2:
            centres.append(t)
            rms.append(math.sqrt((squares[b] - squares[a]) / (b - a)))
        t += DROP_STEP_S
    span = int(round(DROP_SPAN_S / DROP_STEP_S))
    out = []
    for i, value in enumerate(rms):
        local = rms[max(0, i - span):i + span + 1]
        if value < DROP_FACTOR * statistics.median(local):
            out.append((centres[i], "a"))
    need = max(1, int(round(DROP_RUN_S * rate)))
    run = 0
    for n in range(lo, hi):
        if abs(x[n]) < DROP_FLOOR:
            run += 1
            if run == need:
                out.append(((n - need + 1) / rate, "b"))
        else:
            run = 0
    return sorted(out)


def events(drops, gap_s=0.010):
    """Dropout centres merged into events (start s, kinds)."""
    out = []
    for t, kind in drops:
        if out and t - out[-1][1] <= gap_s:
            out[-1][1] = t
            out[-1][2].add(kind)
        else:
            out.append([t, t, {kind}])
    return [(round(a, 4), "".join(sorted(k))) for a, _, k in out]


def locate_scaled(samples, rate, expected, rates, reach_ms):
    """`export_offset_proof.locate`'s method with the click template's width
    ÷ the local rate (`template(rate / r)`) and the given reach."""
    reach = int(round(reach_ms * rate / 1000))
    fine = max(1, int(round(rate / 1000)))
    n = len(samples)
    out = []
    for t, r in zip(expected, rates):
        values, half, norm = template(rate / r)

        def r_at(c):
            a, b = c - half, c + half + 1
            if a < 0 or b > n:
                return 0.0
            seg_ = samples[a:b]
            energy = math.sqrt(sum(v * v for v in seg_))
            return sum(v * y for v, y in zip(seg_, values)) / (energy * norm) if energy > 0 else 0.0

        centre = int(round(t * rate))
        lo, hi = max(0, centre - reach), min(n, centre + reach + 1)
        if hi <= lo:
            out.append((None, 0.0))
            continue
        coarse = max(range(lo, hi), key=lambda i: abs(samples[i]))
        scores = {c: r_at(c) for c in range(coarse - fine, coarse + fine + 1)}
        best = max(scores, key=scores.get)
        r = scores[best]
        offset = 0.0
        if best - 1 in scores and best + 1 in scores:
            left, right = scores[best - 1], scores[best + 1]
            bend = left - 2 * r + right
            if bend < 0:
                offset = max(-0.5, min(0.5, 0.5 * (left - right) / bend))
        out.append(((best + offset) / rate if r >= 0.5 else None, r))
    return out


def place(samples, rate, v):
    """The located summary of a clicks read, with `found_share`, `max_abs_ms`
    and the found times (s, None where not found)."""
    exp = expected_clicks(v)
    times = [t for _, t, _ in exp]
    rates = [r if not v["keep"] else 1.0 for _, _, r in exp]
    spacing = min((b - a for a, b in zip(times, times[1:])), default=1.0) * 1000
    reach = min(REACH_MAX_MS, REACH_SHARE * spacing)
    found = locate_scaled(samples, rate, times, rates, reach)
    s = summary(found, times)
    s["found_share"] = s["found"] / s["of"] if s["of"] else 0.0
    s["max_abs_ms"] = max((abs(d) for d in s["diffs"]), default=None)
    s["times"] = [f for f, _ in found]
    s["reach_ms"] = reach
    return s


def varispeed_pass(s):
    if MUTANT == "pin-off":
        return True
    return (s is not None and s["median_ms"] is not None and s["found_share"] >= FOUND_SHARE
            and abs(s["median_ms"]) <= TARGET_MS and s["spread_ms"] <= SPREAD_MS)


def keep_place_pass(s, controls):
    if MUTANT == "pin-off":
        return True
    if s is None or s["max_abs_ms"] is None or any(c is None or c["max_abs_ms"] is None
                                                   for c in controls):
        return False
    floor = min(c["found_share"] for c in controls) - KEEP_FOUND_SLACK
    ceiling = max(c["max_abs_ms"] for c in controls) + KEEP_DIFF_SLACK_MS
    return s["found_share"] >= floor and s["max_abs_ms"] <= ceiling


def bits_of(lumas):
    value = 0
    for luma in lumas:
        value = value * 2 + (1 if luma > 128 else 0)
    return value


def video_wrong(bars, v):
    """[(frame k, read, allowed)] for every frame that does not decode to its
    expected source frame (a missing frame reads None)."""
    allowed = expected_frames(v)
    wrong = []
    for k, ok in enumerate(allowed):
        read = bits_of(bars[k]) if k < len(bars) and bars[k] is not None else None
        if read not in ok:
            wrong.append((k, read, sorted(ok)))
    return wrong


# ---- the selftest ---------------------------------------------------------------


def sine(freq, seconds, rate=RATE, amp=AMPLITUDE):
    return [amp * math.sin(2 * math.pi * freq * n / rate) for n in range(int(seconds * rate))]


def selftest():
    rows = []

    def row(name, ok, detail):
        rows.append(ok)
        print(f"{name} {'ok' if ok else 'FAIL'} — {detail}", flush=True)

    # S1: clean sines and a glide, fake boundaries every 33.3 ms.
    bad = []
    for freq in (220.0, 55.0, 880.0):
        x = sine(freq, 2.0)
        fake = fake_bounds(2.0)
        hit = [b for b, _, _, c in click_scan(x, RATE, fake, 2.0) if c]
        drop = dropouts(x, RATE, 2.0, lambda t, f=freq: 1 / f)
        if hit or drop:
            bad.append(f"{freq:g} Hz: {len(hit)} clicks, {len(drop)} dropouts")
    glide = [AMPLITUDE * math.sin(2 * math.pi * (55 * n / RATE + 825 * (n / RATE) ** 2 / 8))
             for n in range(4 * RATE)]
    hit = [b for b, _, _, c in click_scan(glide, RATE, fake_bounds(4.0), 4.0) if c]
    drop = dropouts(glide, RATE, 4.0, lambda t: 1 / (55 + 825 * t / 4))
    if hit or drop:
        bad.append(f"glide: {len(hit)} clicks, {len(drop)} dropouts")
    row("S1", not bad, "clean 220, 55, 880 Hz and a 55→880 Hz glide: "
        + ("no click, no dropout" if not bad else "; ".join(bad)))

    # S2: a 4 ms phase jump at the 1 s boundary — it alone clicks.
    skip = int(0.004 * RATE)
    x = [AMPLITUDE * math.sin(2 * math.pi * SINE_HZ * (n + (skip if n >= RATE else 0)) / RATE)
         for n in range(2 * RATE)]
    scan = click_scan(x, RATE, fake_bounds(2.0), 2.0)
    hit = [round(b, 4) for b, _, _, c in scan if c]
    row("S2", hit == [1.0], f"a 4 ms phase jump at 1 s: clicks at {hit}")

    # S3: 2 ms zero gaps at 220 and 55 Hz (b); 10 ms at 0.3 × at 220 Hz (a).
    bad = []
    for freq in (220.0, 55.0):
        x = sine(freq, 1.0)
        for n in range(int(0.5 * RATE), int(0.502 * RATE)):
            x[n] = 0.0
        found = events(dropouts(x, RATE, 1.0, lambda t, f=freq: 1 / f))
        if not any("b" in k and abs(t - 0.5) < 0.01 for t, k in found):
            bad.append(f"{freq:g} Hz gap: {found}")
    x = sine(SINE_HZ, 1.0)
    for n in range(int(0.5 * RATE), int(0.51 * RATE)):
        x[n] *= 0.3
    found = events(dropouts(x, RATE, 1.0, lambda t: 1 / SINE_HZ))
    if not any("a" in k and abs(t - 0.5) < 0.012 for t, k in found):
        bad.append(f"attenuation: {found}")
    row("S3", not bad, "2 ms gaps at 220 and 55 Hz and a 10 ms stretch at 0.3 ×: "
        + ("each a dropout" if not bad else "; ".join(bad)))

    # S4 / S5: a ×1 click train, shifted 2 ms from 3 s on, and unshifted.
    v = {"keep": False, "segs": [seg(0, 6 * SEC, SOURCE_IN, 6 * SEC)], "length": 6 * SEC}
    v["ref"] = v["segs"]

    def train(shift_from=None):
        out = [0.0] * (6 * RATE)
        h = RATE / 2000
        for _, t, _ in expected_clicks(v):
            c = t * RATE + (0.002 * RATE if shift_from is not None and t >= shift_from else 0)
            for n in range(int(c - h) - 1, int(c + h) + 2):
                if 0 <= n < len(out):
                    out[n] += click_value(n - c, h)
        return out

    shifted = place(train(3.0), RATE, v)
    row("S4", not varispeed_pass(shifted),
        f"shifted 2 ms from 3 s: median {shifted['median_ms']:+.3f} ms, spread "
        f"{shifted['spread_ms']:.3f} ms — placement {'passes' if varispeed_pass(shifted) else 'fails'}")
    clean = place(train(), RATE, v)
    row("S5", varispeed_pass(clean),
        f"unshifted: {clean['found']}/{clean['of']}, median {clean['median_ms']:+.3f} ms, spread "
        f"{clean['spread_ms']:.3f} ms — placement {'passes' if varispeed_pass(clean) else 'fails'}")

    # S6: bars at ×1.5 from 1 s; even frames sit on a multiple (excused).
    v = {"keep": False, "segs": [seg(0, 2 * SEC, SOURCE_IN, 3 * SEC)], "length": 2 * SEC}
    v["ref"] = v["segs"]

    def lumas(value):
        return [255 if value >> (9 - j) & 1 else 0 for j in range(10)]

    truth = [(SOURCE_IN + k * FRAME * 3 // 2) // FRAME for k in range(60)]
    wrong_one = [lumas(i) for i in truth]
    wrong_one[7] = lumas(truth[7] + 1)
    excused = [lumas(i) for i in truth]
    excused[8] = lumas(truth[8] - 1)
    a, b = video_wrong(wrong_one, v), video_wrong(excused, v)
    row("S6", len(a) == 1 and not b,
        f"one wrong frame: {len(a)} wrong; a within-2-ticks frame on its neighbour: {len(b)} wrong")

    # S7: keep pitch on, W = 15 ms, clean controls, a jump 10 ms after 1 s.
    ctrl = sine(SINE_HZ, 2.0)
    thr, _, _ = keep_threshold([(ctrl, RATE, 2.0), (ctrl, RATE, 2.0)], 15.0)
    jump = int(0.004 * RATE)
    at = int(1.010 * RATE)
    x = [AMPLITUDE * math.sin(2 * math.pi * SINE_HZ * (n + (jump if n >= at else 0)) / RATE)
         for n in range(2 * RATE)]
    scan = click_scan(x, RATE, [1.0], 2.0, half_s=keep_half_s(15.0), threshold=thr)
    row("S7", any(c for _, _, _, c in scan),
        f"a phase jump 10 ms after the boundary, ±(2 + 15) ms: "
        f"{'clicks' if any(c for _, _, _, c in scan) else 'no click'}")
    return all(rows), len(rows)


# ---- fixtures -------------------------------------------------------------------


class Failure(RuntimeError):
    pass


def run(argv, seconds=600):
    ran = bounded.run([str(a) for a in argv], seconds)
    if ran["expired"]:
        raise Failure(f"{Path(str(argv[0])).name} ran past {seconds} s and was killed")
    if ran["rc"] != 0:
        raise Failure(f"{Path(str(argv[0])).name} exited {ran['rc']}: "
                      f"{(ran['stderr'] or ran['stdout']).strip()[-300:]}")
    return ran


def bar_frame(index):
    row = bytearray()
    for j in range(10):
        row += (b"\xff" if index >> (9 - j) & 1 else b"\x00") * 32
    return bytes(row) * HEIGHT


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(array.array("h", (max(-32768, min(32767, int(round(v * 32767))))
                                        for v in samples)).tobytes())


def make_fixtures(remake):
    FIXTURES.mkdir(parents=True, exist_ok=True)
    total = FIXTURE_S * RATE
    clicks = [0.0] * total
    h = RATE / 2000
    for c in CLICKS:
        centre = c * RATE / SEC
        for n in range(int(centre - h) - 1, int(centre + h) + 2):
            clicks[n] += click_value(n - centre, h)
    audio = {"clicks": clicks, "sine": sine(SINE_HZ, FIXTURE_S)}
    raw = FIXTURES / "bars.gray"
    for name, file in FIXTURE_FILES.items():
        out = FIXTURES / file
        if out.exists() and not remake:
            continue
        if not raw.exists():
            raw.write_bytes(b"".join(bar_frame(i) for i in range(FIXTURE_FRAMES)))
        wav = FIXTURES / f"{name}.wav"
        write_wav(wav, audio[name])
        run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "gray", "-s",
             f"{WIDTH}x{HEIGHT}", "-r", str(FPS), "-i", raw, "-i", wav, "-map", "0:v", "-map",
             "1:a", "-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le",
             "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
             "-c:a", "pcm_s16le", out])
        wav.unlink()
    raw.unlink(missing_ok=True)


def gray_bars(path):
    """Each video frame's 10 bar lumas (the centre 16 × 16 of each bar)."""
    out = path.with_name(path.name + ".gray")
    run(["ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:v:0", "-f", "rawvideo",
         "-pix_fmt", "gray", "-s", f"{WIDTH}x{HEIGHT}", out])
    data = out.read_bytes()
    out.unlink(missing_ok=True)
    size = WIDTH * HEIGHT
    frames = []
    for f in range(len(data) // size):
        base = f * size
        lumas = []
        for j in range(10):
            total = 0
            for y in range(HEIGHT // 2 - 8, HEIGHT // 2 + 8):
                row = base + y * WIDTH + 32 * j + 8
                total += sum(data[row:row + 16])
            lumas.append(total / 256)
        frames.append(lumas)
    return frames


def z0():
    problems = []
    bars = gray_bars(FIXTURES / FIXTURE_FILES["clicks"])
    wrong = [k for k, b in enumerate(bars) if bits_of(b) != k]
    if len(bars) != FIXTURE_FRAMES or wrong:
        problems.append(f"{len(bars)} frames, {len(wrong)} decode wrong (first {wrong[:5]})")
    samples, rate = read_ffmpeg(FIXTURES / FIXTURE_FILES["clicks"])
    times = [c / SEC for c in CLICKS]
    found = locate_scaled(samples, rate, times, [1.0] * len(times), 60.0)
    s = summary(found, times)
    worst = max((abs(d) for d in s["diffs"]), default=None)
    if s["found"] != len(times) or worst is None or worst > 0.05:
        problems.append(f"clicks {s['found']}/{len(times)}, max |diff| {worst} ms")
    x, rate = read_ffmpeg(FIXTURES / FIXTURE_FILES["sine"])
    hit = [b for b, _, _, c in click_scan(x, rate, fake_bounds(FIXTURE_S), float(FIXTURE_S)) if c]
    if hit:
        problems.append(f"the click rule fires on the sine at {hit[:5]}")
    detail = (f"{len(bars)} frames decode to their index; {s['found']}/{len(times)} clicks, max "
              f"|diff| {worst:.4f} ms; no click at {len(fake_bounds(FIXTURE_S))} fake boundaries"
              if not problems else "; ".join(problems))
    return not problems, detail


# ---- the probe ------------------------------------------------------------------


def build_probe(optimize=False, name="ramp-spike-probe", wmo=False):
    """(binary, None) or (None, why). `optimize` builds `-O` (SR1b's render
    times are measured so, under its own `name`), `wmo` with whole-module
    optimisation (#334's spike, Xcode's Release settings); the defaults are
    SR1's."""
    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    entry = PROBE_DIR / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    blank = PROBE_DIR / "Blank.mp4"
    if not blank.exists():
        shutil.copy2(BLANK, blank)
    binary = PROBE_DIR / name
    try:
        built = swift_build.build(sources=swift_build.app_sources() + [entry], output=binary,
                                  defines=["FRAMEJOB_DEV_TOOLS"], optimize=optimize,
                                  wmo=wmo, timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        return None, "the probe did not build: " + " | ".join(error.diagnostics[:6])
    return binary, ("reused" if built.reused else f"built in {built.seconds:.1f} s")


def run_group(binary, group, jobs, work=WORK, walls=WALLS):
    """({(name, read): line}, None) or (partial, why) on a crash or expiry.
    `work` and `walls` are SR1b's to move; the defaults are SR1's."""
    job_file = work / f"jobs-{group}.json"
    job_file.write_text(json.dumps(jobs, indent=1))
    ran = bounded.run([str(binary), group, str(work), str(job_file)], walls[group],
                      cwd=str(binary.parent))
    (work / f"stderr-{group}.txt").write_text(ran["stderr"] or "")
    lines = {}
    for text in (ran["stdout"] or "").splitlines():
        if not text.startswith("{"):
            continue
        try:
            line = json.loads(text)
        except ValueError:
            continue
        if "name" in line and "read" in line:
            lines[(line["name"], line["read"])] = line
    if ran["expired"]:
        return lines, f"the {group} probe ran past {walls[group]} s and was killed"
    if ran["rc"] != 0:
        return lines, f"the {group} probe exited {ran['rc']}: {(ran['stderr'] or '').strip()[-300:]}"
    return lines, None


def jobs_for(group, names, all_variants):
    jobs = []
    for name in names:
        for fixture in ("clicks", "sine"):
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
                         "length": all_variants[name]["length"]})
    return jobs


# ---- reading what the probe wrote -----------------------------------------------


def read_channel0(path):
    with wave.open(str(path), "rb") as w:
        channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 2:
        values, scale = array.array("h", raw), 32768
    elif width == 4:
        values, scale = array.array("i", raw), 2 ** 31
    elif width == 3:
        values = [int.from_bytes(raw[i:i + 3], "little", signed=True)
                  for i in range(0, len(raw) - 2, 3)]
        scale = 2 ** 23
    else:
        raise Failure(f"{path.name}: {width}-byte samples")
    return [values[i] / scale for i in range(0, len(values), channels)], rate


def tap_signal(line, length):
    """The tap's channel 0 placed on the item's timeline by each buffer's
    source-audio time (a buffer with no valid time follows the one before)."""
    rate = int(round(line["format"]["rate"]))
    data = array.array("f", Path(line["path"]).read_bytes())
    n = int(length * rate / SEC)
    out = [0.0] * n
    pos, cursor = 0, 0
    for ticks, frames in line["chunks"]:
        start = int(round(ticks * rate / SEC)) if ticks is not None else cursor
        for i in range(frames):
            j = start + i
            if 0 <= j < n and pos + i < len(data):
                out[j] = data[pos + i]
        pos += frames
        cursor = start + frames
    return out, rate


# ---- scoring --------------------------------------------------------------------


class Score:
    def __init__(self):
        self.rows = {}
        self.instrument = []

    def row(self, rid, status, detail, **extra):
        self.rows[rid] = dict({"status": status, "detail": detail}, **extra)
        print(f"{rid} {status} — {detail}", flush=True)


def plan_check(line, v):
    plan = json.loads(Path(line["path"]).read_text())
    problems = []
    vt, at = plan.get("video_tracks", []), plan.get("audio_tracks", [])
    if len(vt) != 1 or len(at) != 1:
        problems.append(f"{len(vt)} video and {len(at)} audio composition tracks")
    want = [(s["start"], s["duration"], s["in"], s["length"]) for s in v["segs"]]
    for label, tracks in (("video", vt), ("audio", at)):
        got = sorted((s["start"], s["duration"], s["source_in"], s["source_duration"])
                     for t in tracks for s in t["segments"])
        if got != want:
            first = next((i for i, (a, b) in enumerate(zip(got, want)) if a != b), min(len(got), len(want)))
            problems.append(f"{label}: {len(got)} segments, not the {len(want)} written "
                            f"(first difference at {first})")
    pitches = {s.get("pitch") for t in at for s in t["segments"]}
    if len(pitches) != 1:
        problems.append(f"pitch names {sorted(map(str, pitches))}")
    return not problems, problems, sorted(map(str, pitches))


def side_rules(v, name, side, clicks_sig, sine_sig, bars, controls_place, keep_ctx):
    """The rule outcomes for one variant on one side: {rule: {...}}."""
    out = {}
    if clicks_sig is not None:
        s = place(clicks_sig[0], clicks_sig[1], v)
        if v["keep"]:
            ok = keep_place_pass(s, controls_place) if controls_place else None
        else:
            ok = varispeed_pass(s)
        out["placement"] = {"ok": ok, "summary": s}
    if sine_sig is not None:
        x, rate = sine_sig
        length_s = v["length"] / SEC
        bounds = boundaries_s(v) if v["kind"] != "control" else fake_bounds(length_s)
        d = second_diff(x)
        if v["keep"]:
            if keep_ctx is None:
                scan, ok, extra = [], None, {}
            else:
                thr, w_ms = keep_ctx
                scan = click_scan(x, rate, bounds, length_s, half_s=keep_half_s(w_ms),
                                  threshold=thr, d=d)
                extra = {"threshold": thr, "w_ms": w_ms}
                ok = not any(c for *_, c in scan)
        else:
            scan = click_scan(x, rate, bounds, length_s, d=d)
            ok, extra = not any(c for *_, c in scan), {}
        clicked = [round(b, 4) for b, _, _, c in scan if c]
        out["click"] = dict({"ok": ok, "at": clicked, "boundaries": len(scan),
                             "worst_ratio": max((D / t for _, D, t, _ in scan
                                                 if t not in (0, math.inf)), default=None)},
                            **extra)
        r_at = rate_at(v)
        period = (lambda t: 1 / SINE_HZ) if v["keep"] else (lambda t: 1 / (SINE_HZ * r_at(t)))
        ev = events(dropouts(x, rate, length_s, period))
        out["dropout"] = {"ok": not ev, "events": ev[:20], "count": len(ev)}
    if bars is not None:
        wrong = video_wrong(bars, v)
        out["video"] = {"ok": not wrong, "wrong": len(wrong), "of": v["length"] // FRAME,
                        "first": wrong[:5]}
    return out


def fmt_place(rule, keep):
    if not rule:
        return "—"
    s = rule["summary"]
    mark = "" if rule["ok"] else ("?" if rule["ok"] is None else " ✗")
    if s["median_ms"] is None:
        return f"0/{s['of']}{mark}"
    if keep:
        return f"{s['found']}/{s['of']} max {s['max_abs_ms']:.2f}{mark}"
    return f"{s['median_ms']:+.3f}/{s['spread_ms']:.3f} ({s['found']}/{s['of']}){mark}"


def fmt_click(rule):
    if not rule:
        return "—"
    if rule["ok"] is None:
        return "?"
    return "0" if rule["ok"] else f"{len(rule['at'])} @{','.join(f'{b:g}' for b in rule['at'][:4])} ✗"


def fmt_drop(rule):
    if not rule:
        return "—"
    return "0" if rule["ok"] else f"{rule['count']} @{rule['events'][0][0]:g} ✗"


def fmt_video(rule):
    if not rule:
        return "—"
    return f"0/{rule['of']}" if rule["ok"] else f"{rule['wrong']}/{rule['of']} ✗"


def failed_rules(rules, keys=None):
    """The rules that failed or were not measured, by name."""
    out = []
    if keys is None:
        keys = ["placement", "click", "dropout"] + (["video"] if "video" in rules else [])
    for key in keys:
        rule = rules.get(key)
        if rule is None or rule["ok"] is not True:
            out.append(key + ("" if rule is not None and rule["ok"] is False else " (unmeasured)"))
    return out


def host():
    def out(argv):
        ran = bounded.run(argv, 30)
        return (ran["stdout"] or "").strip()
    return {
        "model": out(["sysctl", "-n", "hw.model"]),
        "macos": out(["sw_vers", "-productVersion"]) + " (" + out(["sw_vers", "-buildVersion"]) + ")",
        "load": [round(x, 2) for x in os.getloadavg()],
        "framejob_pids": [int(p) for p in out(["pgrep", "-f", "MacOS/Frame Job"]).split() if p.isdigit()],
    }


def commit():
    head = (bounded.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], 30)["stdout"] or "").strip()
    dirty = (bounded.run(["git", "-C", str(ROOT), "status", "--porcelain"], 30)["stdout"] or "").strip()
    return head + ("+dirty" if dirty else "")


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--groups", default=",".join(GROUPS))
    parser.add_argument("--variants", default=None)
    parser.add_argument("--remake", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS)
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
    if not LIBRARY.exists():
        print(f"NOT PERFORMED: {LIBRARY.relative_to(ROOT)} is missing — `make rust` first")
        return 2

    score = Score()
    started = time.time()
    rule_sha = hashlib.sha256(RULE_FILE.read_bytes()).hexdigest()
    info = host()
    score.row("H0", "measured", f"{info['model']}, macOS {info['macos']}, load {info['load']}, "
              f"Frame Job pids {info['framejob_pids'] or 'none'}; rule_sha256 {rule_sha[:16]}…")
    score.row("B0", "ok", f"{LIBRARY.relative_to(ROOT)} present")

    past = [f"{n} ends at {source_end(everything[n]) / SEC:.3f} s" for n in names
            if source_end(everything[n]) > SOURCE_LIMIT]
    if past:
        score.row("W0", "FAIL", "a variant reads past 19 s of the 20 s fixture: " + "; ".join(past))
        return 1

    WORK.mkdir(parents=True, exist_ok=True)
    try:
        make_fixtures(args.remake)
        ok, detail = z0()
    except Failure as error:
        ok, detail = False, f"the fixtures could not be made or read: {error}"
    score.row("Z0", "ok" if ok else "FAIL", detail)
    if not ok:
        return 1

    shutil.rmtree(PROJECTS, ignore_errors=True)
    for name in names:
        for fixture in FIXTURE_FILES:
            write_package(name, fixture, everything[name])

    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    shader, why = build_shader(str(PROBE_DIR))
    score.row("B1", "ok" if shader else "FAIL", why or f"{Path(shader).name} beside the probe")
    if not shader:
        return 1
    binary, how = build_probe()
    score.row("B2", "ok" if binary else "FAIL", how)
    if not binary:
        return 1

    shutil.rmtree(RUNS, ignore_errors=True)
    RUNS.mkdir(parents=True)
    lines = {}
    for group in GROUPS:
        if group not in groups:
            continue
        t0 = time.time()
        got, why = run_group(binary, group, jobs_for(group, names, everything))
        lines.update(got)
        wanted = sum(len(j["reads"]) for j in jobs_for(group, names, everything))
        failed = [f"{k[0]} {k[1]}: {v.get('error')}" for k, v in got.items() if not v.get("ok")]
        status = "ok" if why is None and len(got) == wanted and not failed else "FAIL"
        detail = (f"{len(got)}/{wanted} reads answered in {time.time() - t0:.0f} s"
                  + (f"; {why}" if why else "")
                  + (f"; {len(failed)} failed: " + " | ".join(failed[:4]) if failed else ""))
        score.row(f"R-{group}", status, detail)
        if status == "FAIL":
            score.instrument.append(f"R-{group}")

    def line(name, fixture, read):
        got = lines.get((f"{name}@{fixture}", read))
        return got if got and got.get("ok") else None

    # Q: the plan.
    for name in names:
        if "plan" not in groups:
            continue
        ok_all, problems, pitches = True, [], set()
        for fixture in FIXTURE_FILES:
            got = line(name, fixture, "plan")
            if got is None:
                ok_all, problems = False, problems + [f"{fixture}: no plan read"]
                continue
            ok, why, p = plan_check(got, everything[name])
            ok_all &= ok
            problems += [f"{fixture}: {w}" for w in why]
            pitches |= set(p)
        n = len(everything[name]["segs"])
        score.row(f"Q-{name}", "ok" if ok_all else "FAIL",
                  f"{n} segments on one video and one audio track, contiguous as written, "
                  f"pitch {sorted(pitches)}" if ok_all else "; ".join(problems))

    # The signals each side reads, per variant (loaded on demand).
    def signals(name, side):
        v = everything[name]
        if side == "export":
            c, s, p = line(name, "clicks", "wav"), line(name, "sine", "wav"), \
                line(name, "clicks", "prores")
            clicks_sig = read_channel0(Path(c["path"])) if c else None
            sine_sig = read_channel0(Path(s["path"])) if s else None
            bars = gray_bars(Path(p["path"])) if p else None
        else:
            c, s, f = line(name, "clicks", "tap"), line(name, "sine", "tap"), \
                line(name, "clicks", "frames")
            clicks_sig = tap_signal(c, v["length"]) if c and c.get("chunks") else None
            sine_sig = tap_signal(s, v["length"]) if s and s.get("chunks") else None
            bars = f["bars"] if f else None
        return clicks_sig, sine_sig, bars

    results = {"export": {}, "playback": {}}
    sides = [s for s in ("export", "playback") if s in groups]
    order = sorted(names, key=lambda n: (everything[n]["kind"] != "control", n))
    pt0 = None
    for side in sides:
        control_cache = {}
        for name in order:
            v = everything[name]
            clicks_sig, sine_sig, bars = signals(name, side)
            controls_place, keep_ctx = None, None
            if v["keep"] and v["controls"]:
                pair = v["controls"]
                if name in pair:  # a C-on-* control is its own
                    own = place(clicks_sig[0], clicks_sig[1], v) if clicks_sig else None
                    controls_place = [own, own] if own else None
                    ctrl_sines = [sine_sig + (v["length"] / SEC,)] * 2 if sine_sig else None
                else:
                    have = [results[side].get(c) for c in pair]
                    controls_place = ([h["placement"]["summary"] for h in have]
                                      if all(h and "placement" in h for h in have) else None)
                    ctrl_sines = [control_cache.get(c) for c in pair]
                    ctrl_sines = ctrl_sines if all(ctrl_sines) else None
                if controls_place and ctrl_sines:
                    w_ms = max(c["max_abs_ms"] for c in controls_place) + KEEP_DIFF_SLACK_MS
                    thr, l_c, d_c = keep_threshold(ctrl_sines, w_ms)
                    keep_ctx = (thr, w_ms)
            rules = side_rules(v, name, side, clicks_sig, sine_sig, bars, controls_place, keep_ctx)
            if v["kind"] == "control" and v["keep"] and sine_sig:
                control_cache[name] = sine_sig + (v["length"] / SEC,)
            results[side][name] = rules
            del clicks_sig, sine_sig, bars
        if side == "playback":
            got = lines.get(("C-off-x2@clicks", "tap"))
            if "C-off-x2" not in names:
                pt0 = None
                score.row("PT0", "unmeasured", "C-off-x2 is not among the variants run")
            elif not got or not got.get("ok") or not got.get("calls"):
                pt0 = False
                score.row("PT0", "FAIL", "the tap of C-off-x2 was never called"
                          + (f" ({got.get('error')})" if got and got.get("error") else ""))
                score.instrument.append("PT0")
            else:
                rule = results["playback"]["C-off-x2"].get("placement")
                pt0 = bool(rule and rule["ok"])
                s = rule["summary"] if rule else None
                score.row("PT0", "ok" if pt0 else "measured",
                          f"C-off-x2's tap ({got.get('calls')} calls, {got['format']}): "
                          + (f"{s['found']}/{s['of']}, median {s['median_ms']:+.3f} ms, spread "
                             f"{s['spread_ms']:.3f} ms" if s and s["median_ms"] is not None
                             else "no click found")
                          + ("" if pt0 else " — the varispeed pin missed: every P audio row is "
                             "unmeasured"))
            if pt0 is not True:
                for name in names:
                    for key in ("placement", "click", "dropout"):
                        if key in results["playback"][name]:
                            results["playback"][name][key]["ok"] = None
                            results["playback"][name][key]["unmeasured"] = True

    # E, P and A rows.
    agreement = {}
    for name in names:
        v = everything[name]
        reported = v["kind"] == "control" and v["keep"]
        for side in sides:
            rules = results[side][name]
            audio_unmeasured = side == "playback" and pt0 is not True
            keys = ([] if audio_unmeasured else ["placement", "click", "dropout"]) + (
                ["video"] if "video" in rules else [])
            bad = failed_rules(rules, keys=keys)
            detail = " · ".join(
                f"{label} {f(rules.get(k))}" for label, k, f in (
                    ("place", "placement", lambda r: fmt_place(r, v["keep"])),
                    ("click", "click", fmt_click), ("drop", "dropout", fmt_drop),
                    ("video", "video", fmt_video)))
            if audio_unmeasured:
                detail += " (audio unmeasured: PT0 did not pass)"
            status = ("unmeasured" if not keys else "measured" if reported
                      else "ok" if not bad else "FAIL")
            score.row(f"{side[0].upper()}-{name}", status, detail, rules=_jsonable(rules))
        if "export" in sides and "playback" in sides:
            e = results["export"][name].get("placement")
            p = results["playback"][name].get("placement")
            if pt0 is not True or not e or not p:
                agreement[name] = None
                score.row(f"A-{name}", "unmeasured", "PT0 did not pass" if pt0 is not True
                          else "a placement read is missing")
                continue
            diffs = [(b - a) * 1000 for a, b in zip(e["summary"]["times"], p["summary"]["times"])
                     if a is not None and b is not None]
            if not diffs:
                ok, detail = False, "no click found on both sides"
            elif v["keep"]:
                worst = max(abs(d) for d in diffs)
                ok = worst <= AGREE_KEEP_MS
                detail = f"{len(diffs)} pairs, max |diff| {worst:.3f} ms"
            else:
                med, spread = statistics.median(diffs), max(diffs) - min(diffs)
                ok = abs(med) <= TARGET_MS and spread <= SPREAD_MS
                detail = f"{len(diffs)} pairs, median {med:+.3f} ms, spread {spread:.3f} ms"
            agreement[name] = ok
            score.row(f"A-{name}", "measured" if reported else "ok" if ok else "FAIL", detail)

    # Instrument checks.
    if "export" in sides:
        for name in [n for n in names if n.startswith("C-off-")]:
            bad = failed_rules(results["export"][name], keys=("placement", "click", "dropout"))
            if bad:
                score.instrument.append(f"{name}: {', '.join(bad)}")
        if "F1" in names:
            r = results["export"]["F1"]
            at = r.get("click", {}).get("at")
            if at != [F1_FROM / SEC] or r.get("placement", {}).get("ok") is not False:
                others = [b for b in (at or []) if b != F1_FROM / SEC]
                base = set(results["export"].get("V1-G1", {}).get("click", {}).get("at") or [])
                score.instrument.append(
                    f"F1: clicks at 2 s {'yes' if F1_FROM / SEC in (at or []) else 'NO'}, at "
                    f"{len(others)} other boundaries"
                    + (f" ({len(set(others) & base)} of them V1-G1's own clicks)"
                       if "V1-G1" in names else "")
                    + f", placement {'passes' if r.get('placement', {}).get('ok') else 'fails'}")
    if score.instrument:
        score.row("I0", "FAIL", "instrument checks failed: " + "; ".join(score.instrument))
    else:
        checked = [n for n in names if n.startswith("C-off-")]
        score.row("I0", "ok" if "export" in sides else "unmeasured",
                  (f"{len(checked)} C-off-* control(s) pass placement, click and dropout in export; "
                   + ("F1 clicks at 2 s alone and fails placement" if "F1" in names
                      else "F1 not run")) if "export" in sides
                  else "no export group: the controls and F1 were not checked")

    # The table.
    print()
    head = ("| variant | seg | E place | E click | E drop | E video | P place | P click | "
            "P drop | P video | A | ideal ms |")
    print(head)
    print("|" + "---|" * 12)
    table = [head, "|" + "---|" * 12]
    for name in names:
        v = everything[name]
        e = results["export"].get(name, {})
        p = results["playback"].get(name, {})
        a = agreement.get(name)
        cells = [name, str(len(v["segs"])), fmt_place(e.get("placement"), v["keep"]),
                 fmt_click(e.get("click")), fmt_drop(e.get("dropout")), fmt_video(e.get("video")),
                 fmt_place(p.get("placement"), v["keep"]), fmt_click(p.get("click")),
                 fmt_drop(p.get("dropout")), fmt_video(p.get("video")),
                 "—" if a is None else ("ok" if a else "✗"), f"{ideal_error_ms(v):.3f}"]
        text = "| " + " | ".join(cells) + " |"
        print(text)
        table.append(text)

    verdict, why = decide(results, agreement, pt0, names, sides)
    print(f"\nVERDICT: {verdict} — {why}")

    RESULTS.write_text(json.dumps({
        "commit": commit(), "date": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "seconds": round(time.time() - started), "rule_sha256": rule_sha, "host": info,
        "rows": score.rows,
        "variants": {n: {"segments": everything[n]["segs"],
                         "export": _jsonable(results["export"].get(n)),
                         "playback": _jsonable(results["playback"].get(n)),
                         "ideal_error_ms": ideal_error_ms(everything[n])} for n in names},
        "table": table, "verdict": {"verdict": verdict, "detail": why},
    }, indent=1))
    return 1 if score.instrument else 0


def _jsonable(value):
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items() if k != "times" and k != "diffs"} | (
            {"diffs_ms": [round(d, 4) for d in value["diffs"]]} if "diffs" in value else {})
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    if isinstance(value, set):
        return sorted(value)
    if isinstance(value, float) and not math.isfinite(value):
        return None
    return value


def decide(results, agreement, pt0, names, sides):
    """SR-5's verdict."""
    missing = [n for n in VERDICT_SET + ["V1L"] if n not in names]
    if missing or "export" not in sides:
        return "STOP", ("not measured: " + ", ".join(missing + ([] if "export" in sides
                                                                else ["the export group"])))

    def fails(name, side):
        rules = results[side].get(name, {})
        out = failed_rules(rules)
        if side == "playback" and agreement.get(name) is not True:
            out.append("agreement" + ("" if agreement.get(name) is False else " (unmeasured)"))
        return out

    export_bad = {n: fails(n, "export") for n in VERDICT_SET if fails(n, "export")}
    playback_bad = {}
    if pt0 is True and "playback" in sides:
        playback_bad = {n: fails(n, "playback") for n in VERDICT_SET if fails(n, "playback")}

    def named(bad, side):
        return [f"{n} {side}: {', '.join(r)}" for n, r in bad.items()]

    if not export_bad and not playback_bad:
        if pt0 is True:
            return "GO", "every V and K variant at G1 holds in export and playback, with agreement"
        return "GO-EXPORT-ONLY", ("GO's export half holds; PT0 failed, so playback's audio is "
                                  "unmeasured")
    others = {k: v for k, v in export_bad.items() if k != "V1-G1"}
    others_p = {k: v for k, v in playback_bad.items() if k != "V1-G1"}
    if not others and not others_p and pt0 is True:
        lead_only = True
        for side, bad in (("export", export_bad), ("playback", playback_bad)):
            for rule in bad.get("V1-G1", []):
                r = results[side]["V1-G1"].get(rule)
                if rule == "click" and r and r["at"] == [1.0]:
                    continue
                if rule == "dropout" and r and all(abs(t - 1.0) <= LEAD_NEAR_S for t, _ in r["events"]) \
                        and r["count"] == len(r["events"]):
                    continue
                lead_only = False
        lead_fixed = all(results[side]["V1L"].get(rule, {}).get("ok") is True
                         for side, bad in (("export", export_bad), ("playback", playback_bad))
                         for rule in bad.get("V1-G1", []))
        if lead_only and lead_fixed:
            return "GO-UNIFORM-LEAD", ("GO but for V1-G1 at its 1 s boundary ("
                                       + "; ".join(named(export_bad, "export") + named(playback_bad, "playback"))
                                       + "), which V1L passes")
    return "STOP", "; ".join(named(export_bad, "export") + named(playback_bad, "playback")) or \
        "the uniform-lead exception does not apply"


if __name__ == "__main__":
    sys.exit(main())
