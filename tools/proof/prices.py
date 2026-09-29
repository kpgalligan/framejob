"""The proofs' reader of the price table (road map 13 P1, spec §11 P-1, P-2).

`agent/prices/anthropic.json` is LiteLLM's Anthropic rows in US dollars per
million tokens; `make prices` is its only writer, and nothing here re-derives
a rate. `price` is `agent/src/pricing.ts`'s `price` in Python, step for step:
the same checks in the same order, the same arithmetic in the same order, and
the same answers — `{"kind": "dollars", "dollars", "rows"}` or
`{"kind": "unknown", "cause", "detail"}`. Both readers run every case in
`agent/prices/cases.json` (`prices_proof.py`, a line of `make test`).
It never raises and never answers NaN, whatever JSON value `usage` is.

    import prices
    table = prices.load()
    prices.price(response["usage"], response["model"], table)

Standard library only.
"""

import json
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TABLE = os.path.join(ROOT, "agent", "prices", "anthropic.json")
CASES = os.path.join(ROOT, "agent", "prices", "cases.json")

TIER_THRESHOLD = 200_000
DATED = re.compile(r"-[0-9]{8}\Z")  # ASCII digits and the true end, as pricing.ts
# The order a class's cost is added in; pricing.ts uses the same.
CLASSES = (("input", "input"), ("cache_write_5m", "write5m"), ("cache_write_1h", "write1h"),
           ("cache_read", "read"), ("output", "output"))


def load(path=TABLE):
    with open(path) as f:
        return json.load(f)


def match_model(model, table):
    """The table key a response's model id prices at: the exact id, or the
    id less a trailing `-YYYYMMDD` when that is a key; nothing else."""
    models = table["models"]
    if model in models:
        return model
    if DATED.search(model):
        bare = model[:-9]
        if bare in models:
            return bare
    return None


def _unknown(cause, detail):
    return {"kind": "unknown", "cause": cause, "detail": detail}


def _count(obj, key):
    """Absent or null is 0; else a non-negative integer (an `int` that is not
    a `bool`, or an integral float), else None."""
    value = obj.get(key)
    if value is None:
        return 0
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        try:
            float(value)  # JSON.parse would read a larger literal as Infinity
        except OverflowError:
            return None
        return value if value >= 0 else None
    if isinstance(value, float):
        if math.isfinite(value) and value.is_integer() and value >= 0:
            return value
        return None
    return None


def _counts(entry):
    names = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
             "output_tokens")
    values = []
    for name in names:
        value = _count(entry, name)
        if value is None:
            return f"{name} is not a non-negative integer"
        values.append(value)
    tokens_in, creation, read, output = values
    write5m, write1h = creation, 0
    split = entry.get("cache_creation")
    if isinstance(split, dict):
        five = _count(split, "ephemeral_5m_input_tokens")
        hour = _count(split, "ephemeral_1h_input_tokens")
        if five is None:
            return "cache_creation.ephemeral_5m_input_tokens is not a non-negative integer"
        if hour is None:
            return "cache_creation.ephemeral_1h_input_tokens is not a non-negative integer"
        write5m, write1h = five, hour
    return {"input": tokens_in, "write5m": write5m, "write1h": write1h, "read": read,
            "output": output, "total": float(tokens_in) + float(creation) + float(read)}


def _usable(rate):
    if isinstance(rate, bool) or not isinstance(rate, (int, float)):
        return False
    try:
        rate = float(rate)
    except OverflowError:
        return False
    return math.isfinite(rate) and rate >= 0


def _allowed(usage, key, ok):
    value = usage.get(key)
    return value is None or (isinstance(value, str) and value == ok)


def price(usage, model, table):
    # 1. The shapes.
    if not isinstance(usage, dict):
        return _unknown("usage", "usage is not an object")
    if not isinstance(model, str) or model == "":
        return _unknown("model", "no model id")

    # 2. Modes the table has no rate for.
    for key, ok in (("speed", "standard"), ("service_tier", "standard"),
                    ("inference_geo", "global")):
        if not _allowed(usage, key, ok):
            return _unknown(key, f"{key} {json.dumps(usage.get(key))} is not priced")

    # 3. The entries.
    iterations = usage.get("iterations")
    if iterations is not None and not isinstance(iterations, list):
        return _unknown("usage", "iterations is not an array")
    entries = []
    if isinstance(iterations, list) and iterations:
        for i, element in enumerate(iterations):
            if not isinstance(element, dict):
                return _unknown("usage", f"iterations[{i}] is not an object")
            named = element.get("model")
            entries.append((element, named if isinstance(named, str) and named else model))
    else:
        entries.append((usage, model))

    # 4. The counts.
    tallies = []
    for i, (value, _) in enumerate(entries):
        answer = _counts(value)
        if isinstance(answer, str):
            return _unknown("usage", f"iterations[{i}].{answer}" if len(entries) > 1 else answer)
        tallies.append(answer)

    # 5. The rows.
    keys = []
    for _, entry_model in entries:
        key = match_model(entry_model, table)
        if key is None:
            return _unknown("model", f"{entry_model} is not in the price table")
        keys.append(key)

    # 6. The tier and the rates.
    rates = []
    for key, tally in zip(keys, tallies):
        row = table["models"][key]
        if not isinstance(row, dict):
            return _unknown("rate", f"{key} has no rates")
        above = row.get("above_200k")
        tiered = isinstance(above, dict) and tally["total"] > TIER_THRESHOLD
        chosen = above if tiered else row
        for rate_key, count_key in CLASSES:
            if tally[count_key] > 0 and not _usable(chosen.get(rate_key)):
                tier = "above_200k " if tiered else ""
                return _unknown("rate", f"{key} has no {tier}{rate_key} rate")
        rates.append(chosen)

    # 7. The arithmetic.
    dollars = 0
    for tally, chosen in zip(tallies, rates):
        s = 0
        for rate_key, count_key in CLASSES:
            tokens = tally[count_key]
            if tokens == 0:
                continue
            s += float(tokens) * float(chosen[rate_key])  # doubles, as pricing.ts
        dollars += s / 1_000_000
    rows = []
    for key in keys:
        if key not in rows:
            rows.append(key)
    return {"kind": "dollars", "dollars": float(dollars), "rows": rows}
