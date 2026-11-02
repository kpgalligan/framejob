"""Road map "creator-jobs" CO0: the cutout spikes' rules as pure functions.

Stdlib only, no I/O. `cutout_spike.py` measures; these decide. Each function
is the rule's text in `designs/creator-jobs.md` ("Every spike, with its rule",
CO-S1 and CO-S2) applied to the rows the runner hands it:

- `s1_speed_only(rows)` — CO-S1 without S-KEY1 (speed only): Standard is
  person `.balanced` at the first rate of every frame, 15 and 10 a second
  whose median realtime factor at 1080p30 is at least 1.0; none → 10 a second,
  recorded as a risk. Read size, Best, flicker and rotation are owed.
- `s2_track(rows, s1)` — CO-S2's six conditions per (encoding, L), the chunk
  length L (the shortest passing (5) and (6) whose per-chunk fixed cost adds
  under 5 % to analysis time per minute), the encoding (the smaller MB per
  minute of those passing all six) and the compositor class from (2).
- `s2_pack(rows)` — the per-media mask pack on (1), (2), (5), (6).
- `nearest(analysed, t)` — the analysed time nearest `t`, ties to the
  earlier, both in the stream the segment reads: the one expectation every
  registration row is scored against.
- `reversed_time(pts, end, pivot)` — a forward frame's time in the reversed
  stream, `pivot − end` (`ReverseMirror`'s CMTime convention: the frame shown
  from `pts` until `end` is written at `pivot − end`), never `pivot − pts`.

`selftest()` runs one synthetic row per branch and answers the number of
failed rows.
"""

import bisect

RATES = ("every", "15", "10")
LENGTHS = (5, 10, 30)
ENCODINGS = ("hevc", "prores-proxy")
STANDARD = "person-balanced"

REGISTRATION_ALL = True        # (1): every frame, every case
COLOUR_MAX_LEVELS = 1.0        # (2): ≤ 1/255 at every pixel
IOU_MIN = 0.995                # (3)
EDGE_MAD_MAX = 3.0             # (3): levels, inside the 8 px edge band
MB_PER_MIN_MAX = 15.0          # (4): 10^6 bytes per minute of 30 fps source
PLAYBACK_MIN = 0.99            # (5): with masks ≥ 99 % of without
BUILD_MAX_MS = 100.0           # (6): median build, with − without
FIXED_PCT_MAX = 5.0            # L: per-chunk fixed cost, % of analysis time


def nearest(analysed, t):
    """The member of the sorted `analysed` nearest `t`; a tie goes to the
    earlier. Integers or any ordered numbers in one unit."""
    if not analysed:
        raise ValueError("no analysed frame")
    at = bisect.bisect_left(analysed, t)
    if at < len(analysed) and analysed[at] == t:
        return t
    after = analysed[at] if at < len(analysed) else None
    before = analysed[at - 1] if at > 0 else None
    if before is None:
        return after
    if after is None:
        return before
    return before if t - before <= after - t else after


def reversed_time(pts, end, pivot):
    """A forward frame shown from `pts` until `end` lands at `pivot − end` in
    the reversed stream (`ReverseMirror.swift`'s CMTime overload, as
    `ReverseRenderer` writes `pivot − following`)."""
    del pts  # the frame's own start is not the mirrored stamp: its end is
    return pivot - end


def analysed_frames(frames, rate, fps=30):
    """CJ-23's sample rule over a source's frame times (integers, in 1/fps s):
    every frame (rate `every`, capped at 30 a second), or for a rate r the
    first frame at or after each k / r s. Answers sorted frame times."""
    frames = sorted(frames)
    if rate == "every":
        return frames
    r = int(rate)
    picked, k, at = [], 0, 0
    while True:
        # The first frame at or after k / r s, compared exactly: f·r ≥ k·fps.
        while at < len(frames) and frames[at] * r < k * fps:
            at += 1
        if at >= len(frames):
            break
        if not picked or picked[-1] != frames[at]:
            picked.append(frames[at])
        k += 1
    return picked


def ends(frames, track_end):
    """Each frame's end: the next frame's time, the track's end for the last."""
    frames = sorted(frames)
    return {f: (frames[i + 1] if i + 1 < len(frames) else track_end)
            for i, f in enumerate(frames)}


def expected_mask(picture, analysed, reverse=None):
    """The analysed frame whose mask a frame showing `picture` must show.
    `reverse` = (pivot, ends) when the segment reads the reversed stream: the
    picture's time and every analysed time are mirrored by `reversed_time`,
    the nearest taken there (ties to the earlier in the reversed stream), and
    the answer mapped back to the forward frame."""
    if reverse is None:
        return nearest(analysed, picture)
    pivot, end_of = reverse
    mirrored = {reversed_time(a, end_of[a], pivot): a for a in analysed}
    keys = sorted(mirrored)
    return mirrored[nearest(keys, reversed_time(picture, end_of[picture], pivot))]


def s1_speed_only(rows):
    """`rows["<candidate>/<rate>/push_1080/source"]["realtime"]` — the median
    realtime factor. Answers {standard, rate, realtime_1080, risk, …owed}."""
    chosen, factor, risk = None, None, False
    for rate in RATES:
        row = rows.get(f"{STANDARD}/{rate}/push_1080/source") or {}
        value = row.get("realtime")
        if value is not None and value >= 1.0:
            chosen, factor = rate, value
            break
    if chosen is None:
        chosen, risk = "10", True
        factor = (rows.get(f"{STANDARD}/10/push_1080/source") or {}).get("realtime")
    return {"standard": STANDARD, "rate": chosen, "realtime_1080": factor, "risk": risk,
            "read_size": "owed", "best": "owed", "flicker": "owed", "rotation": "owed"}


def fixed_pct(chunk_s, fixed_s, realtime_1080):
    """Per-chunk fixed cost as a PERCENTAGE of analysis time per minute of
    source: 100 × (60 / L) × fixed_s / (60 / realtime)."""
    if not realtime_1080 or fixed_s is None:
        return None
    return 100.0 * (60.0 / chunk_s) * fixed_s / (60.0 / realtime_1080)


def colour_class(colour):
    """(2): the class a composition with a mask track is built with, and its
    pass. `colour` = {plain_sdr, converting_sdr, converting_hlg} max levels
    (None = not measured). The plain class passing keeps `Compositor`; the
    plain class conforming the mask (over 1 level) re-measures SDR with the
    converting class, which then names the class."""
    plain = colour.get("plain_sdr")
    hlg = colour.get("converting_hlg")
    if plain is not None and plain <= COLOUR_MAX_LEVELS:
        cls, sdr = "Compositor", plain
    else:
        cls, sdr = "ConvertingCompositor", colour.get("converting_sdr")
    ok = sdr is not None and sdr <= COLOUR_MAX_LEVELS and hlg is not None \
        and hlg <= COLOUR_MAX_LEVELS
    worst = max(v for v in (sdr, hlg) if v is not None) if (sdr, hlg) != (None, None) else None
    return cls, ok, worst


def conditions(rows, encoding, chunk_s, realtime_1080):
    """(1)…(6) for one (encoding, L); each `{ok, …}`, and the fixed cost."""
    key = f"{encoding}/{chunk_s}"
    reg = rows.get("registration", {}).get(key) or {}
    colour = rows.get("colour", {}).get(encoding) or {}
    codec = rows.get("codec", {}).get(key) or {}
    play = rows.get("playback", {}).get(key) or {}
    build = rows.get("build", {}).get(key) or {}
    fixed = rows.get("fixed_s", {}).get(encoding)
    cls, colour_ok, worst = colour_class(colour)
    out = {
        "1": {"ok": bool(reg.get("rows")) and reg.get("pass") == reg.get("rows"),
              "pass": reg.get("pass"), "rows": reg.get("rows")},
        "2": {"ok": colour_ok, "class": cls, "max": worst},
        "3": {"ok": codec.get("iou") is not None and codec["iou"] >= IOU_MIN
              and codec.get("edge_mad") is not None and codec["edge_mad"] <= EDGE_MAD_MAX,
              "iou": codec.get("iou"), "edge_mad": codec.get("edge_mad")},
        "4": {"ok": codec.get("mb_per_min") is not None
              and codec["mb_per_min"] <= MB_PER_MIN_MAX, "mb_per_min": codec.get("mb_per_min")},
        "5": {"ok": play.get("ratio") is not None and play["ratio"] >= PLAYBACK_MIN,
              "ratio": play.get("ratio")},
        "6": {"ok": build.get("delta_ms") is not None and build["delta_ms"] <= BUILD_MAX_MS,
              "delta_ms": build.get("delta_ms")},
    }
    out["fixed_pct"] = fixed_pct(chunk_s, fixed, realtime_1080)
    return out


def s2_track(rows, s1):
    """CO-S2's rule for the mask track. Answers {route, encoding, chunk_s,
    class, table, …}; route `none` when no encoding passes all six at its L."""
    realtime = (s1 or {}).get("realtime_1080")
    table, picks = {}, {}
    for encoding in ENCODINGS:
        for chunk_s in LENGTHS:
            table[f"{encoding}/{chunk_s}"] = conditions(rows, encoding, chunk_s, realtime)
        # L: the shortest passing (5) and (6) whose fixed cost is under 5 %.
        for chunk_s in LENGTHS:
            row = table[f"{encoding}/{chunk_s}"]
            pct = row["fixed_pct"]
            if row["5"]["ok"] and row["6"]["ok"] and pct is not None and pct < FIXED_PCT_MAX:
                picks[encoding] = chunk_s
                break
    passing = []
    for encoding, chunk_s in picks.items():
        row = table[f"{encoding}/{chunk_s}"]
        if all(row[c]["ok"] for c in "123456"):
            passing.append((row["4"]["mb_per_min"], encoding, chunk_s))
    if not passing:
        return {"route": "none", "encoding": None, "chunk_s": None, "class": None,
                "lengths": picks, "table": table}
    _, encoding, chunk_s = min(passing)
    row = table[f"{encoding}/{chunk_s}"]
    return {"route": "mask-track", "encoding": encoding, "chunk_s": chunk_s,
            "class": row["2"]["class"], "lengths": picks, "table": table,
            "registration": row["1"], "colour_max": row["2"]["max"], "iou": row["3"]["iou"],
            "edge_mad": row["3"]["edge_mad"], "mb_per_min": row["4"]["mb_per_min"],
            "playback": row["5"]["ratio"], "build_ms": row["6"]["delta_ms"],
            "fixed_pct": row["fixed_pct"]}


def s2_pack(rows):
    """The mask pack on (1), (2), (5), (6): `rows["pack"]` = {registration:
    {pass, rows}, colour_max, playback_ratio, build_delta_ms}."""
    pack = rows.get("pack") or {}
    reg = pack.get("registration") or {}
    checks = {
        "1": bool(reg.get("rows")) and reg.get("pass") == reg.get("rows"),
        "2": pack.get("colour_max") is not None and pack["colour_max"] <= COLOUR_MAX_LEVELS,
        "5": pack.get("playback_ratio") is not None and pack["playback_ratio"] >= PLAYBACK_MIN,
        "6": pack.get("build_delta_ms") is not None and pack["build_delta_ms"] <= BUILD_MAX_MS,
    }
    return {"route": "mask-pack" if all(checks.values()) else "neither", "checks": checks,
            **{k: pack.get(k) for k in ("registration", "colour_max", "playback_ratio",
                                         "build_delta_ms")}}


def _passing_rows(chunk_s=10, mb=2.0, delta=20.0, ratio=1.0, colour=None):
    """A synthetic CO-S2 table where every (encoding, L) passes."""
    rows = {"registration": {}, "colour": {}, "codec": {}, "playback": {}, "build": {},
            "fixed_s": {"hevc": 0.01, "prores-proxy": 0.01}}
    for encoding in ENCODINGS:
        rows["colour"][encoding] = colour or {"plain_sdr": 0.0, "converting_sdr": 0.0,
                                              "converting_hlg": 0.0}
        for length in LENGTHS:
            key = f"{encoding}/{length}"
            rows["registration"][key] = {"pass": 44, "rows": 44}
            rows["codec"][key] = {"iou": 0.999, "edge_mad": 1.0,
                                  "mb_per_min": mb if encoding == "hevc" else mb * 5}
            rows["playback"][key] = {"ratio": ratio}
            rows["build"][key] = {"delta_ms": delta}
    del chunk_s
    return rows


def selftest():
    failed, count = [], [0]

    def row(name, ok, detail=""):
        count[0] += 1
        print(f"{'ok  ' if ok else 'FAIL'} {name}{': ' + str(detail) if detail else ''}")
        if not ok:
            failed.append(name)

    # S1 — each rate branch and the risk branch.
    def s1(every, fifteen, ten):
        return s1_speed_only({f"{STANDARD}/every/push_1080/source": {"realtime": every},
                              f"{STANDARD}/15/push_1080/source": {"realtime": fifteen},
                              f"{STANDARD}/10/push_1080/source": {"realtime": ten}})
    got = s1(1.4, 2.8, 4.2)
    row("S1 every frame at 1.4×", got["rate"] == "every" and not got["risk"], got)
    got = s1(0.7, 1.3, 2.0)
    row("S1 15 a second at 1.3×", got["rate"] == "15" and got["realtime_1080"] == 1.3, got)
    got = s1(0.4, 0.8, 1.0)
    row("S1 10 a second at exactly 1.0×", got["rate"] == "10" and not got["risk"], got)
    got = s1(0.2, 0.4, 0.6)
    row("S1 none reaching 1.0× → 10, risk", got["rate"] == "10" and got["risk"]
        and got["realtime_1080"] == 0.6 and got["best"] == "owed", got)

    # nearest — a tie goes to the earlier.
    row("nearest tie → earlier", nearest([0, 2, 4], 1) == 0 and nearest([0, 2, 4], 3) == 2,
        (nearest([0, 2, 4], 1), nearest([0, 2, 4], 3)))
    row("nearest exact and past the ends",
        nearest([0, 2, 4], 2) == 2 and nearest([2, 4], 0) == 2 and nearest([0, 2], 9) == 2)

    # (4) at exactly 15 MB passes.
    rows = _passing_rows(mb=15.0)
    rows["codec"]["prores-proxy/5"]["mb_per_min"] = 80.0
    got = s2_track(rows, {"realtime_1080": 2.0})
    row("(4) at exactly 15 MB per minute passes", got["route"] == "mask-track"
        and got["table"]["hevc/5"]["4"]["ok"], got["table"]["hevc/5"]["4"])

    # L skipped at a ratio between 0.05 and 5: L = 5 s, realtime 2.0, fixed
    # 1.0 s → 100 × 12 × 1 / 30 = 40 % (ratio 0.40), so 5 is skipped.
    rows = _passing_rows()
    rows["fixed_s"] = {"hevc": 1.0, "prores-proxy": 1.0}
    got = s2_track(rows, {"realtime_1080": 2.0})
    pct5 = got["table"]["hevc/5"]["fixed_pct"]
    row("L = 5 skipped at 40 % (a ratio of 0.40)", abs(pct5 - 40.0) < 1e-9
        and got["lengths"].get("hevc") != 5, (pct5, got["lengths"]))
    # With 1.0 s fixed, 10 s gives 20 % and 30 s 6.67 %: no L under 5 %.
    row("no L under 5 % → route none", got["route"] == "none", got["lengths"])
    rows["fixed_s"] = {"hevc": 0.05, "prores-proxy": 0.05}
    got = s2_track(rows, {"realtime_1080": 2.0})
    row("fixed 0.05 s → L = 5 (2 %)", got["chunk_s"] == 5 and got["encoding"] == "hevc",
        (got["chunk_s"], got["encoding"], got["table"]["hevc/5"]["fixed_pct"]))

    # The plain class conforming the mask → ConvertingCompositor.
    rows = _passing_rows(colour={"plain_sdr": 6.0, "converting_sdr": 0.0,
                                 "converting_hlg": 0.5})
    got = s2_track(rows, {"realtime_1080": 2.0})
    row("plain class conforming → ConvertingCompositor",
        got["class"] == "ConvertingCompositor" and got["route"] == "mask-track", got["class"])
    rows = _passing_rows()
    got = s2_track(rows, {"realtime_1080": 2.0})
    row("plain class keeping the mask → Compositor", got["class"] == "Compositor", got["class"])

    # A registration miss fails (1) and the route falls to the other encoding.
    rows = _passing_rows()
    rows["registration"]["hevc/5"] = {"pass": 43, "rows": 44}
    got = s2_track(rows, {"realtime_1080": 2.0})
    row("(1) one miss at hevc/5 → prores-proxy/5", got["encoding"] == "prores-proxy"
        and got["chunk_s"] == 5, (got["encoding"], got["chunk_s"]))

    # reversed_time: frame 0 of a 4,800-frame 30 fps stream lands at frame
    # 4799's slot, 4799/30 s — `pivot − end`, not `pivot − pts` (4800/30, past it).
    got = reversed_time(0, 1, 4800)
    row("reversed_time(frame 0) = slot 4799, not past it", got == 4799 and got != 4800 - 0, got)
    end_of = ends(range(4800), 4800)
    row("reverse every-frame expectation is the picture itself",
        all(expected_mask(p, list(range(4800)), (4800, end_of)) == p for p in (0, 1, 2399, 4799)))
    halves = analysed_frames(range(4800), "15")
    row("15 a second over 30 fps picks the even frames", halves[:4] == [0, 2, 4, 6]
        and len(halves) == 2400, halves[:4])
    dropped = [f for f in range(1200) if f not in (119, 270, 899)]
    picked = analysed_frames(dropped, "15")
    row("15 a second over a dropped frame takes the next", 271 in picked and 270 not in picked
        and 900 in picked, [f for f in picked if 268 <= f <= 272])
    # Reverse at 15 a second: slot j even → tie → the earlier in the reversed stream.
    got = expected_mask(1, halves, (4800, end_of))
    row("reverse at 15 a second: a tie goes to the earlier reversed time", got == 2, got)

    # The pack.
    got = s2_pack({"pack": {"registration": {"pass": 10, "rows": 10}, "colour_max": 0.0,
                            "playback_ratio": 0.995, "build_delta_ms": 40.0}})
    row("pack passing → mask-pack", got["route"] == "mask-pack", got["checks"])
    got = s2_pack({"pack": {"registration": {"pass": 10, "rows": 10}, "colour_max": 0.0,
                            "playback_ratio": 0.98, "build_delta_ms": 40.0}})
    row("pack at 98 % playback → neither", got["route"] == "neither", got["checks"])
    print(f"selftest: {count[0] - len(failed)}/{count[0]}")
    return len(failed)


if __name__ == "__main__":
    import sys
    sys.exit(1 if selftest() else 0)
