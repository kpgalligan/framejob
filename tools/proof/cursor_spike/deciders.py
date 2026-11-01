"""The cursor spikes' rules — road map "creator-jobs" CU0b (CU-S1…CU-S4, spec §11 CJ-7).

Pure functions only: the rule hash (R0), the four deciders, the two CU-S3 coordinate
conversions and the verdict lines. Nothing here reads a file, runs a child or imports the
runner; `cursor_spike.py` hands each decider its rows and sets `MUTANT` for the selftest.

A row is a dict: measured (`{tier, at, …measures}`), `{"skipped": reason}` or
`{"absent": reason}` (a row the rule makes conditional and the host lacks, which is not a
skip). A listener row (A1–A3) may be a list of runs; only a run from the scratch bundle
holding exactly the grant the field names is evidence. A field answers `owed` when a row it
reads is skipped before its value is settled; a later row it never reaches does not count.
"""

import hashlib
import math
import statistics

MUTANT = None

# CJ0a's record, "Spike rules fixed" (recomputed at b2eccc35: all four match).
PINNED = {
    "CU-S1": "9508e82d119466262ed5fa48b7b3a6502b12022fa65b63ac0a35badfee23886c",
    "CU-S2": "15d61ec5374d3465b7f8a2f7c652ed6d78b099d0c2c5642946d8c87b3919c851",
    "CU-S3": "9ffadf0b9897880826cdddc0820ddc93bb0a2337bdf27e73b51c6fa41372ea5c",
    "CU-S4": "0fe71118ada7d67c52790943eb6cd5cf0c8b160377df3a72df207d54db47e208",
}

OWED = "owed"
STOP = "STOP"

# CU-S1's thresholds.
POLL_US = 20.0              # a poll costs ≤ 20 µs median
DELIVERY = 0.99             # ≥ 99 % of 200 events
TRIALS_PASS = 9             # ≥ 9 of 10 trials
IMAGE_MS = 1.0              # median cost × 10 Hz ≤ 1 % of one core (≤ 1 ms a call)
IOU_PASS = 0.9
CLOCK_WINDOW_MS = (0.0, 20.0)
CLOCK_SHARE = 0.99
EVENT_CLOCKS = ("ns", "mach", "uptime")
HIDDEN_SIGNALS = ("current_system_nil", "image_hash")  # CGCursorIsVisible alone never decides
# CU-S2's.
TIP_PX = 1.5
MAPPINGS = ("M1", "M2", "M3")
ANCHORS = ("E2", "E1", "DisplayTime")
E1_LIMIT_MS = 25.0
# CU-S3's.
DIRTY_PT = 64.0
BURSTS = 10
# CU-S4's.
JSON_MB = 25.0              # MB = 10^6 bytes
PARSE_MS = 300.0
STATE_US = 20.0
PREPARE_MS = 1000.0

SOURCES = {  # CU-S2's source rows: id → (kind, odd, person)
    "display-nominal": ("display", False, False),
    "display-best": ("display", False, False),
    "display-second": ("display", False, False),
    "window-moved": ("window", False, False),
    "window-odd": ("window", True, False),
    "window-picked": ("window", False, True),
}
CONFIGS = ("picture", "separate")


def s2_row(source, config):
    return f"S2.{source}.{config}"


FIELD_ROWS = {
    "CU-S1": {
        "positions": ["A4.cost", "A4.warps", "A4.real"],
        "clicks": ["A1", "A3.clicks"],
        "keys": ["A2.input-monitoring", "A3.keys.input-monitoring"],
        "cursor_image": ["A5"],
        "hidden": ["A9.helper", "A9.textedit"],
        "image_fallback": ["A5", "A10"],
        "event_clock": ["A6"],
        "secure": ["A7"],
        "relaunch": ["A8", "A11"],
        "grant_api": ["A8", "A11"],
        "listed": ["A8", "A11"],
    },
    "CU-S2": {
        "mapping_display": [s2_row(s, "picture") for s, v in SOURCES.items() if v[0] == "display"],
        "mapping_window": [s2_row(s, "picture") for s, v in SOURCES.items() if v[0] == "window"],
        "separate": [s2_row(s, "separate") for s in SOURCES],
        "anchor": [s2_row(s, c) for s in SOURCES for c in CONFIGS],
        "e1_still_p95_ms": [f"S2.still.{k}" for k in range(1, 11)],
    },
    "CU-S3": {"dirty": [f"S3.burst.{k}" for k in range(1, BURSTS + 1)]},
    "CU-S4": {"body": ["S4.json", "S4.binary"], "smoothing": ["S4.json", "S4.binary"]},
}

FIELD_ORDER = {
    "CU-S1": ["positions", "clicks", "keys", "cursor_image", "hidden", "image_fallback",
              "event_clock", "secure", "relaunch", "grant_api", "listed"],
    "CU-S2": ["mapping_display", "mapping_window", "separate", "anchor", "e1_still_p95_ms"],
    "CU-S3": ["dirty", "bursts_within"],
    "CU-S4": ["body", "smoothing", "json_mb", "parse_ms", "state_us", "prepare_ms"],
}


# ---- R0: the rule hash ------------------------------------------------------------------

def rule_entry(roadmap_text, spike_id):
    """CJ-7's entry: the line `- **<ID> —` and every following line that begins with two
    spaces, each with its newline. None when the road map has no such line."""
    lines = roadmap_text.splitlines(keepends=True)
    head = f"- **{spike_id} —"
    for i, line in enumerate(lines):
        if line.startswith(head):
            entry = [line]
            for follow in lines[i + 1:]:
                if not follow.startswith("  "):
                    break
                entry.append(follow)
            return "".join(entry)
    return None


def rule_sha256(roadmap_text, spike_id):
    entry = rule_entry(roadmap_text, spike_id)
    return None if entry is None else hashlib.sha256(entry.encode("utf-8")).hexdigest()


def changed_rules(roadmap_text, spikes=tuple(PINNED)):
    """The spikes whose rule no longer hashes to its pinned value (R0's `RULE CHANGED`)."""
    if MUTANT == "rule-unchecked":
        return []
    return [s for s in spikes if rule_sha256(roadmap_text, s) != PINNED[s]]


# ---- reading rows -----------------------------------------------------------------------

class _Owed(Exception):
    pass


def is_skipped(row):
    return row is None or (isinstance(row, dict) and "skipped" in row)


def is_absent(row):
    return isinstance(row, dict) and "absent" in row


def _read(rows, rid):
    """The measured row, or None when absent; raises _Owed on a skipped row."""
    row = rows.get(rid)
    if is_absent(row):
        return None
    if is_skipped(row):
        if MUTANT == "skipped-as-measured":
            return row or {}
        raise _Owed(rid)
    return row


def _listener(rows, rid, grant):
    """The first run of `rid` from the scratch bundle holding exactly `grant`, read as a row.
    A terminal-run listener inherits the terminal's grants and never decides."""
    row = rows.get(rid)
    runs = row if isinstance(row, list) else [row]
    for run in runs:
        if run is None or is_skipped(run) or is_absent(run):
            continue
        listener = run.get("listener") or {}
        launched = listener.get("launch") == "bundle" or MUTANT == "inherited-grant-counted"
        if launched and listener.get("grant") == grant:
            return run
    return _read({rid: {"skipped": f"no scratch-bundle run holding {grant}"}}, rid)


def p95(values):
    """Nearest-rank p95; None for no values."""
    vals = sorted(v for v in values if isinstance(v, (int, float)) and not isinstance(v, bool))
    if not vals:
        return None
    return vals[max(0, math.ceil(0.95 * len(vals)) - 1)]


def delivers(run, share=None):
    """Every window's own events delivered at ≥ 99 % (Frame Job's own windows included)."""
    share = share if share is not None else (0.95 if MUTANT == "clicks-95" else DELIVERY)
    windows = (run or {}).get("windows") or {}
    if not windows:
        return False
    for counts in windows.values():
        sent, got = counts.get("sent") or 0, counts.get("delivered") or 0
        if sent <= 0 or got < share * sent:
            return False
    return True


# ---- CU-S1 ------------------------------------------------------------------------------

def _positions(rows):
    cost = _read(rows, "A4.cost")
    if cost is None or cost.get("median_us") is None or cost["median_us"] > POLL_US:
        return "events"
    warps = _read(rows, "A4.warps")
    if not (warps or {}).get("seen"):
        return "events"
    real = _read(rows, "A4.real")
    return "poll" if (real or {}).get("seen") else "events"


def _clicks(rows):
    if delivers(_listener(rows, "A1", "none")):
        return "tap"
    if delivers(_listener(rows, "A3.clicks", "none")):
        return "monitor"
    return STOP


def _keys(rows):
    if delivers(_listener(rows, "A2.input-monitoring", "input-monitoring")):
        return "tap"
    if delivers(_listener(rows, "A3.keys.input-monitoring", "input-monitoring")):
        return "monitor"
    if MUTANT == "keys-accessibility-ok":
        for rid, answer in (("A2.accessibility", "tap"), ("A3.keys.accessibility", "monitor")):
            try:
                if delivers(_listener(rows, rid, "accessibility")):
                    return answer
            except _Owed:
                pass
    return STOP


def _a5_passes(a5):
    a5 = a5 or {}
    ibeam = sum(bool(x) for x in a5.get("ibeam") or [])
    hand = sum(bool(x) for x in a5.get("hand") or [])
    cost = a5.get("median_ms")
    return ibeam >= TRIALS_PASS and hand >= TRIALS_PASS and cost is not None and cost <= IMAGE_MS


def _cursor_image(rows):
    return "current-system" if _a5_passes(_read(rows, "A5")) else "none"


def _telling(row):
    """The signals that tell hidden from shown in ≥ 9 of the row's trials."""
    told = []
    for signal in HIDDEN_SIGNALS:
        hits = sum(1 for t in (row or {}).get("trials") or []
                   if (t.get("hidden") or {}).get(signal) != (t.get("shown") or {}).get(signal))
        if hits >= TRIALS_PASS:
            told.append(signal)
    return told


def _hidden(rows):
    helper = _telling(_read(rows, "A9.helper"))
    if not helper:
        return "not-recorded"
    textedit = _telling(_read(rows, "A9.textedit"))
    return "recorded" if set(helper) & set(textedit) else "not-recorded"


def _image_fallback(rows):
    if _a5_passes(_read(rows, "A5")):
        return "arrow"
    a10 = _read(rows, "A10") or {}
    good = sum(1 for v in a10.get("iou") or [] if v is not None and v >= IOU_PASS)
    return "a10" if good >= TRIALS_PASS else "arrow"


def _event_clock(rows):
    a6 = _read(rows, "A6") or {}
    lo, hi = CLOCK_WINDOW_MS
    for clock in EVENT_CLOCKS:
        deltas = (a6.get("deltas_ms") or {}).get(clock) or []
        if deltas and sum(1 for d in deltas if lo <= d <= hi) >= CLOCK_SHARE * len(deltas):
            return clock
    return "none"


def _secure(rows):
    a7 = _read(rows, "A7") or {}
    return "withheld" if (a7.get("delivered") or 0) == 0 else "delivered"


def _grant(rows):
    """(relaunch, grant_api, listed) from A8 then A11."""
    _read(rows, "A8")
    a11 = _read(rows, "A11") or {}
    order = ("iohid", "cg") if MUTANT == "grant-iohid-first" else ("cg", "iohid")
    shown = [api for api in order
             if (a11.get(api) or {}).get("prompt") and (a11.get(api) or {}).get("listed")]
    api = shown[0] if shown else "cg"
    relaunch = "not-needed" if (a11.get(api) or {}).get("after_tap_delivered") else "needed"
    return relaunch, api, "yes" if shown else "no"


def _field(fn, rows):
    try:
        return fn(rows)
    except _Owed:
        return OWED


def decide_s1(rows):
    fields = {
        "positions": _field(_positions, rows),
        "clicks": _field(_clicks, rows),
        "keys": _field(_keys, rows),
        "cursor_image": _field(_cursor_image, rows),
        "hidden": _field(_hidden, rows),
        "image_fallback": _field(_image_fallback, rows),
        "event_clock": _field(_event_clock, rows),
        "secure": _field(_secure, rows),
    }
    grant = _field(_grant, rows)
    fields["relaunch"], fields["grant_api"], fields["listed"] = (
        (OWED, OWED, OWED) if grant == OWED else grant)
    return fields


# ---- CU-S2 ------------------------------------------------------------------------------

def _first_passing(rows, ids, candidates, ok):
    """The first candidate that passes every measured row: `owed` when a row is skipped and the
    candidate has not failed a measured one; None when every candidate fails."""
    measured, skipped = [], False
    for rid in ids:
        row = rows.get(rid)
        if is_absent(row):
            continue
        if is_skipped(row) and MUTANT != "skipped-as-measured":
            skipped = True
            continue
        row = row or {}
        if MUTANT == "odd-window-ignored" and row.get("odd"):
            continue
        measured.append(row)
    for candidate in candidates:
        if any(not ok(row, candidate) for row in measured):
            continue
        return OWED if skipped else candidate
    return None


def _tip_ok(row, mapping):
    worst = p95((row.get("tip_err_px") or {}).get(mapping) or [])
    return worst is not None and worst <= TIP_PX


def _time_ok(row, anchor):
    errors = [abs(e) for e in (row.get("time_err_ms") or {}).get(anchor) or [] if e is not None]
    worst, frame = p95(errors), row.get("frame_ms")
    return worst is not None and frame is not None and worst <= frame


def decide_s2(rows):
    ids = FIELD_ROWS["CU-S2"]
    mapping = {}
    for kind in ("display", "window"):
        found = _first_passing(rows, ids[f"mapping_{kind}"], MAPPINGS, _tip_ok)
        mapping[kind] = STOP if found is None else found
    verdicts = []
    for kind in ("display", "window"):
        chosen = mapping[kind]
        if chosen == OWED:
            verdicts.append(OWED)
        elif chosen == STOP:
            verdicts.append("fail")
        else:
            separate_ids = [s2_row(s, "separate") for s, v in SOURCES.items() if v[0] == kind]
            got = _first_passing(rows, separate_ids, (chosen,), _tip_ok)
            verdicts.append("fail" if got is None else ("pass" if got == chosen else OWED))
    separate = "fail" if "fail" in verdicts else (OWED if OWED in verdicts else "pass")
    anchor = _first_passing(rows, ids["anchor"], ANCHORS, _time_ok)
    still = []
    for rid in ids["e1_still_p95_ms"]:
        row = rows.get(rid)
        if is_skipped(row) and MUTANT != "skipped-as-measured":
            still = None
            break
        if row and row.get("e1_err_ms") is not None:
            still.append(abs(row["e1_err_ms"]))
    e1 = OWED if still is None or not still else round(p95(still), 1)
    return {"mapping_display": mapping["display"], "mapping_window": mapping["window"],
            "separate": separate, "anchor": "none" if anchor is None else anchor,
            "e1_still_p95_ms": e1}


# ---- CU-S3 ------------------------------------------------------------------------------

def dirty_centre_pt(box_px, px_per_pt, display_origin_tl):
    """A dirty box in the stream's output pixels (origin top-left of the captured display) →
    its centre in global top-left points: ÷ px_per_pt (the configured pixel width ÷ the
    display's point width), then + the display's origin in global top-left points."""
    x, y, w, h = box_px
    return ((x + w / 2) / px_per_pt + display_origin_tl[0],
            (y + h / 2) / px_per_pt + display_origin_tl[1])


def caret_centre_pt(rect_cocoa, primary_height_pt):
    """`firstRect(forCharacterRange:actualRange:)`'s Cocoa global rect (origin bottom-left of
    the primary display) → its centre in global top-left points: y_tl = primary − (y + h)."""
    x, y, w, h = rect_cocoa
    top = y if MUTANT == "caret-unflipped" else primary_height_pt - (y + h)
    return (x + w / 2, top + h / 2)


def burst_distance(burst):
    """The distance in points between a burst's median dirty-box centre and its caret's
    centre; None when the burst saw no dirty box."""
    boxes = burst.get("dirty_boxes_px") or []
    if not boxes:
        return None
    cx = statistics.median(b[0] + b[2] / 2 for b in boxes)
    cy = statistics.median(b[1] + b[3] / 2 for b in boxes)
    dx, dy = dirty_centre_pt((cx, cy, 0, 0), burst["px_per_pt"], burst["display_frame_tl"])
    kx, ky = caret_centre_pt(burst["caret_rect_cocoa"], burst["primary_height_pt"])
    return math.hypot(dx - kx, dy - ky)


def decide_s3(rows):
    bound = 128.0 if MUTANT == "dirty-128" else DIRTY_PT
    within = misses = 0
    skipped = False
    for rid in FIELD_ROWS["CU-S3"]["dirty"]:
        row = rows.get(rid)
        if is_skipped(row) and MUTANT != "skipped-as-measured":
            skipped = True
            continue
        distance = burst_distance(row or {})
        if distance is not None and distance <= bound:
            within += 1
        else:
            misses += 1
    # Settled by the measured bursts alone (≥ 9 within, or more than one miss); else owed.
    if within >= TRIALS_PASS:
        dirty = "stored"
    elif misses > BURSTS - TRIALS_PASS or not skipped:
        dirty = "not-stored"
    else:
        dirty = OWED
    return {"dirty": dirty, "bursts_within": f"{within}/{BURSTS}"}


# ---- CU-S4 ------------------------------------------------------------------------------

def decide_s4(rows):
    js, binary = rows["S4.json"], rows["S4.binary"]
    mb = js["bytes"] / 1e6
    parse = statistics.median(js["parse_ms"])
    state = js["state_us_prepared_median"]
    tests = (mb <= JSON_MB, parse <= PARSE_MS, state <= STATE_US)
    body = "json" if (any(tests) if MUTANT == "body-or" else all(tests)) else "binary"
    prepare = statistics.median((js if body == "json" else binary)["prepare_ms"])
    return {"body": body, "smoothing": "whole-file" if prepare <= PREPARE_MS else "per-60s-window",
            "json_mb": round(mb, 2), "parse_ms": round(parse, 1), "state_us": round(state, 2),
            "prepare_ms": round(prepare, 1)}


# ---- the verdict lines ------------------------------------------------------------------

DECIDERS = {"CU-S1": decide_s1, "CU-S2": decide_s2, "CU-S3": decide_s3, "CU-S4": decide_s4}


def verdict_line(fields, spike=None):
    """`VERDICT k=v …` in the rule's field order (the spike's when named, else the dict's)."""
    order = FIELD_ORDER.get(spike) or list(fields)
    return "VERDICT " + " ".join(f"{k}={fields[k]}" for k in order if k in fields)


def stops(spike, fields):
    """The fields whose answer is put to the owner: a STOP, or CU-S2's `anchor=none`."""
    out = [k for k, v in fields.items() if v == STOP]
    if spike == "CU-S2" and fields.get("anchor") == "none":
        out.append("anchor")
    return out
