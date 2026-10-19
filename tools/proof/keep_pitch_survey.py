#!/usr/bin/env python3
"""#299 phase 1 — every pitch-keeping method macOS offers, measured at real
speed changes on the RECORDER fixture and judged by spec §11 SY-40's rule,
written before the first run. No app: it builds `export_offset_probe.swift`
(`export_offset_proof.build_probe`) and runs its group `T` over
`audio_sync_proof`'s fixtures dir.

    python3 tools/proof/keep_pitch_survey.py

The probe's T1 reads the export's mix (`readMix`) of the recorder at frame
206, in 0, at each rate of RATES with keep pitch on and the algorithm set to
`spectral` and to `timeDomain`, and the CONTROL with keep pitch off (the
product's varispeed with SY-24's lead); T2 renders the recorder's 48 kHz copy
offline through `AVAudioUnitTimePitch` (`timepitch`) and the older
AUTimePitch (`autimepitch`) and reads the CAF from a composition at frame 206.
Every read is a 48 kHz mono `.f32` of the timeline from 0; each is taken to
16 kHz by ffmpeg (`-f f32le -ar 48000 -ac 1 -i … -ar 16000 -ac 1 -f s16le`),
reduced to `audio_sync_proof.envelope`'s 1 ms buckets and measured by
`export_offset_proof.stretched_lag` (reach ±200 ms) against the recorder's own
envelope on 15 media windows: SWEEP ([12 s, 22 s) … [142 s, 152 s)) and
R_WINDOWS' [128 s, 138 s). The correlations run in a process pool.

Each (method, rate) is classed over its 15 windows, the first that applies
(SY-40): `lost` (any r < 0.8 or a lag on the ±200 ms edge), `on time` (every
|lag| ≤ 1.0 ms), `constant` (max − min ≤ 1.0 ms), `bounded` (max − min ≤
10.0 ms), `drifts`. A method is adoptable at 1.0 ms when every rate is `on
time` or `constant`, at 5.0 ms when every rate is at worst `bounded`. The
control must be `on time` at every rate, else the run is a failed instrument.
A read whose error starts `unavailable:` (a unit the system lacks) takes its
method out of the comparison.

Prints a line per (method, rate) — early and late lag and r (R_WINDOWS), the
sweep's min / median / max lag, max − min over the 15 windows, the
least-squares slope in ms per minute of timeline, the least r, the class and,
for T2, `latency_s`, `render_s` and `copy_bytes` — then each method's verdict
and the spread of its per-rate medians, and last `VERDICT: …`. Writes
`tools/proof/work/keep-pitch/survey.json` (its runs removed at the start).
Exit 0 iff every read but an `unavailable:` one completed and the control
held.
"""

import array
import json
import os
import shutil
import statistics
import subprocess
import sys
import wave
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/proof"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
from audio_sync_proof import envelope, fixtures  # noqa: E402
from export_offset_proof import (  # noqa: E402
    R_WINDOWS, build_probe, clear_rate_copies, stretched_lag)

WORK = HERE / "work/keep-pitch"
RUNS = WORK / "runs"
ENVELOPES = WORK / "envelopes"
RUN_WALL = 3600
RATES = [0.5, 0.9, 0.99, 1.01, 1.1, 1.5, 2.0]
SWEEP = [(lo, lo + 10_000) for lo in range(12_000, 142_001, 10_000)]
WINDOWS = SWEEP + [R_WINDOWS[1]]
EARLY, LATE = R_WINDOWS
REACH = 200
ON_TIME_MS = 1.0
CONSTANT_MS = 1.0
BOUNDED_MS = 10.0
LEAST_R = 0.8
METHODS = ["spectral", "timeDomain", "timepitch", "autimepitch"]
CONTROL = "off"
TICKS_PER_MS = 600


def method_of(entry):
    """The method a manifest entry reads, from its stage and variant."""
    variant = entry["variant"]
    if entry["stage"] == "render":
        return variant.split("+", 1)[1]
    if variant.endswith("-off"):
        return CONTROL
    return variant.split("+alg-", 1)[1]


def read_envelope(f32, out):
    """The .f32 (48 kHz mono) at 16 kHz through ffmpeg, as 1 ms envelope
    buckets written to `out` (float32)."""
    s16 = out.with_suffix(".s16")
    ran = bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", "48000", "-ac", "1",
                       "-i", str(f32), "-ar", "16000", "-ac", "1", "-f", "s16le", str(s16)], 600)
    if ran["expired"] or ran["rc"] != 0:
        raise RuntimeError(f"ffmpeg on {f32.name}: {ran['stderr'].strip()[-300:]}")
    data = array.array("h", s16.read_bytes())
    s16.unlink()
    env = envelope([v / 32768 for v in data])
    out.write_bytes(array.array("f", env).tobytes())


_loaded = {}


def load(path):
    """An envelope file as a list, the worker keeping the last few it read
    (a read's windows arrive together)."""
    if path not in _loaded:
        if len(_loaded) >= 4:
            _loaded.pop(next(iter(_loaded)))
        _loaded[path] = array.array("f", Path(path).read_bytes()).tolist()
    return _loaded[path]


def correlate(task):
    """One window of one read: (key, window index, lag ms, r)."""
    key, env_path, media_path, start_ms, speed, index = task
    lo, hi = WINDOWS[index]
    lag, r = stretched_lag(load(env_path), load(media_path), start_ms, 0.0, speed, lo, hi, REACH)
    return key, index, lag, r


def slope(start_ms, speed, lags):
    """Least squares of lag (ms) against the window's timeline centre
    (minutes): ms per minute."""
    xs = [(start_ms + (lo + hi) / 2 / speed) / 60_000 for lo, hi in WINDOWS]
    mx, my = statistics.fmean(xs), statistics.fmean(lags)
    var = sum((x - mx) ** 2 for x in xs)
    return sum((x - mx) * (y - my) for x, y in zip(xs, lags)) / var if var else 0.0


def classify(lags, rs):
    if any(r < LEAST_R for r in rs) or any(abs(lag) >= REACH for lag in lags):
        return "lost"
    if all(abs(lag) <= ON_TIME_MS for lag in lags):
        return "on time"
    spread = max(lags) - min(lags)
    if spread <= CONSTANT_MS:
        return "constant"
    if spread <= BOUNDED_MS:
        return "bounded"
    return "drifts"


def main():
    shutil.rmtree(RUNS, ignore_errors=True)
    shutil.rmtree(ENVELOPES, ignore_errors=True)
    RUNS.mkdir(parents=True)
    ENVELOPES.mkdir(parents=True)
    recorder = Path(fixtures()["recorder"])
    clear_rate_copies()

    binary, why = build_probe()
    if binary is None:
        print(f"FAIL — {why}")
        return 1
    ran = bounded.run([str(binary), str(RUNS), str(recorder.parent), "T"], RUN_WALL,
                      cwd=str(binary.parent))
    (RUNS / "stderr.txt").write_text(ran["stderr"])
    answer = next((line for line in ran["stdout"].splitlines() if line.startswith("ANSWER ")),
                  None)
    if ran["expired"] or answer is None:
        print(f"FAIL — the probe {'ran past %d s' % RUN_WALL if ran['expired'] else 'gave no answer'}"
              f" (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}")
        return 1
    print(f"probe: {answer[len('ANSWER '):]} ({ran['seconds']:.0f} s)")
    manifest = json.loads((RUNS / "manifest.json").read_text())

    with wave.open(str(recorder)) as w:
        assert w.getframerate() == 16_000 and w.getnchannels() == 1 and w.getsampwidth() == 2
        media = array.array("h", w.readframes(w.getnframes()))
    media_path = ENVELOPES / "recorder.env"
    media_path.write_bytes(array.array("f", envelope([v / 32768 for v in media])).tobytes())

    reads, failures, unavailable = {}, [], set()
    for entry in manifest:
        method, rate = method_of(entry), round(float(entry["speed"]), 6)  # JSON writes 2.0 as 2
        key = f"{method}@{rate}"
        if not entry.get("ok"):
            error = str(entry.get("error"))
            if error.startswith("unavailable:"):
                unavailable.add(method)
                print(f"{key}: unavailable — {error}")
            else:
                failures.append(f"{key}: {error}")
            continue
        env_path = ENVELOPES / f"{entry['stage']}-{entry['variant']}.env"
        try:
            read_envelope(Path(entry["path"]), env_path)
        except (OSError, RuntimeError) as error:
            failures.append(f"{key}: {error}")
            continue
        reads[key] = {"method": method, "rate": rate, "entry": entry, "env": str(env_path),
                      "start_ms": entry["start_ticks"] / TICKS_PER_MS}
    for method in METHODS + [CONTROL]:
        for rate in RATES:
            key = f"{method}@{rate}"
            if key not in reads and method not in unavailable and not any(
                    f.startswith(key + ":") for f in failures):
                failures.append(f"{key}: no read in the manifest")

    tasks = [(key, read["env"], str(media_path), read["start_ms"], read["rate"], i)
             for key, read in reads.items() for i in range(len(WINDOWS))]
    with ProcessPoolExecutor(max_workers=os.cpu_count()) as pool:
        for key, index, lag, r in pool.map(correlate, tasks, chunksize=1):
            reads[key].setdefault("windows", [None] * len(WINDOWS))[index] = (lag, r)

    table = {}
    for key, read in reads.items():
        lags = [lag for lag, _ in read["windows"]]
        rs = [r for _, r in read["windows"]]
        sweep = lags[:len(SWEEP)]
        row = {
            "method": read["method"], "rate": read["rate"],
            "early": read["windows"][WINDOWS.index(EARLY)],
            "late": read["windows"][WINDOWS.index(LATE)],
            "sweep_min": min(sweep), "sweep_median": statistics.median(sweep),
            "sweep_max": max(sweep), "median": statistics.median(lags),
            "spread": max(lags) - min(lags),
            "slope_ms_per_min": slope(read["start_ms"], read["rate"], lags),
            "least_r": min(rs), "class": classify(lags, rs),
            "windows": [{"window_ms": list(w), "lag_ms": lag, "r": r}
                        for w, (lag, r) in zip(WINDOWS, read["windows"])],
        }
        for extra in ("latency_s", "render_s", "copy_bytes"):
            if extra in read["entry"]:
                row[extra] = read["entry"][extra]
        table[key] = row

    print("method       rate  early lag (r)        late lag (r)         sweep min/median/max"
          "          max−min  ms/min    least r  class")
    for method in [CONTROL] + METHODS:
        for rate in RATES:
            row = table.get(f"{method}@{rate}")
            if row is None:
                continue
            line = (f"{method:<12} ×{rate:<4} {row['early'][0]:+9.3f} ({row['early'][1]:.3f})"
                    f"  {row['late'][0]:+9.3f} ({row['late'][1]:.3f})"
                    f"  {row['sweep_min']:+8.3f} / {row['sweep_median']:+8.3f} / "
                    f"{row['sweep_max']:+8.3f}  {row['spread']:7.3f}  "
                    f"{row['slope_ms_per_min']:+7.3f}  {row['least_r']:.3f}    {row['class']}")
            if "render_s" in row:
                line += (f"; latency_s {row['latency_s']:.6f}, render_s {row['render_s']:.2f},"
                         f" copy_bytes {row['copy_bytes']}")
            print(line)

    control = [table.get(f"{CONTROL}@{rate}") for rate in RATES]
    control_held = all(row is not None and row["class"] == "on time" for row in control)
    print(f"control ({CONTROL}): " + ("on time at every rate" if control_held else
                                      "NOT on time at every rate — a failed instrument"))
    verdicts = {}
    for method in METHODS:
        rows = [table.get(f"{method}@{rate}") for rate in RATES]
        if method in unavailable:
            verdicts[method] = "unavailable"
        elif any(row is None for row in rows):
            verdicts[method] = "incomplete"
        elif all(row["class"] in ("on time", "constant") for row in rows):
            verdicts[method] = "adoptable at 1.0 ms"
        elif all(row["class"] in ("on time", "constant", "bounded") for row in rows):
            verdicts[method] = "adoptable at 5.0 ms"
        else:
            worst = [f"×{row['rate']} {row['class']}" for row in rows
                     if row["class"] in ("lost", "drifts")]
            verdicts[method] = "not adoptable (" + ", ".join(worst) + ")"
        print(f"method {method}: {verdicts[method]}")
    for method in METHODS:
        medians = [table[f"{method}@{rate}"]["median"] for rate in RATES
                   if f"{method}@{rate}" in table]
        if medians:
            print(f"method {method}: per-rate medians {min(medians):+.3f} … {max(medians):+.3f} ms,"
                  f" spread {max(medians) - min(medians):.3f} ms")
    for failure in failures:
        print(f"FAILED READ {failure}")
    best = [m for m in METHODS if verdicts[m] == "adoptable at 1.0 ms"]
    good = [m for m in METHODS if verdicts[m] == "adoptable at 5.0 ms"]
    verdict = (", ".join(best) + " adoptable at 1.0 ms" if best else
               ", ".join(good) + " adoptable at 5.0 ms" if good else "none adoptable")

    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "survey.json").write_text(json.dumps({
        "rates": RATES, "windows_ms": [list(w) for w in WINDOWS], "reach_ms": REACH,
        "rows": table, "verdicts": verdicts, "unavailable": sorted(unavailable),
        "failures": failures, "control_held": control_held, "verdict": verdict,
    }, indent=2, sort_keys=True))
    print(f"VERDICT: {verdict}")
    return 0 if not failures and control_held else 1


if __name__ == "__main__":
    sys.exit(main())
