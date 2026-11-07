#!/usr/bin/env python3
"""ai-docs r2a — the preview's half-second hold on play (#537) and on every Loop wrap and mid-play
seek (#520), measured.

    python3 tools/proof/ai_docs_r2a_proof.py [--only H1,…] [--trials N] [--app PATH] [--expect-red]

Over MCP on one launch (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a scratch
`CFFIXED_USER_HOME` under `tools/proof/work/ai-docs-r2a/`. It imports `ai_docs_a1_proof.py` as a
module and re-points its folders here, so the instrument is a1's W1–W7 (`Doc`, `loop_doc`,
`loop_on_paused`, `deficits`, `wrap_holds`, `seek_holds`, `poll_holds`) with lines drawn under it.
Media: `tools/proof/media/AV.mov` (5 s, picture and sound) and `vonly.mov`, a 5 s `testsrc` with no
audio stream made with ffmpeg. It prints the default output device first; nothing here changes it.

`play_preview` times its own wall clock and answers the player's own `to`, so a hold is wall time
the player's clock did not advance. D is the start deficit, wall − (to − from) of a 4 s play from 0
starting paused; per-wrap hold = (wall − (to − from) − 2·5 s − D) / 2 over a 13 s Loop play; seek
hold = wall − (seek_from − from) − to − D of a 6 s play with a `seek_to: 0` half-way. lone is one
AV.mov, pair is two with Loop on the first clip (Clip ▸ Motion ▸ Preview). Medians are over
`--trials` (default 5); the controls run 3.

Rows marked [B] are red on the base app (main at eab6adf2). Every line sits above every sound-off
and no-audio control trial the confirm stage read (max 0.089 s, its stalls aside) and below every
reading of round 1's half-fix (no taps, min 0.196 s). **All six are HELD for the owner**: none of
the four candidates the batch built cleared them (the spike table is in `README.md` §"ai-docs
r2a"), so nothing shipped, and each prints its numbers against its line as a MEASURE row. A fix
that clears a row takes it out of `HELD`, and it is scored from then on.
- H1 [B] #537 pair, Loop off: D median ≤ 0.10 s, every `to` ≥ 3.5 s.
- H2 [B] #537 lone, Loop on, starting paused at 0: D median ≤ 0.10 s.
- H3 [B] #520 pair, Loop off: mid-play seek hold median ≤ 0.10 s.
- H4 [B] #520 lone: per-wrap hold median ≤ 0.12 s.
- H5 [B] #520 pair, Loop on the first clip: per-wrap hold median ≤ 0.12 s.
- H6 [B] #520 lone and pair: a 16 s `get_project` poll; at least 2 wraps each, and every run of
  readings at the loop start ≤ 0.15 s.
- C1 MEASURE: lone with `set_enabled {audio: false}`: D, seek holds, per-wrap holds, H6's poll.
- C2 MEASURE: one vonly.mov, the same four.
- M1 control: lone; `loudness_meter {reset: true}`, a 4 s `play_preview` from 0, `loudness_meter`:
  `to_frame − from_frame ≥ 3 × sample_rate` and `integrated_lufs` finite (the taps still meter).
- Z1 the launch's `grep "Frame Job: "` prints nothing.

Exit 0 only when every scored row passes; with `--expect-red`, only when every scored [B] row
fails and every control (M1, Z1) passes.

What this does not measure: the picture or the sound a person sees and hears at a play, a wrap or a
seek (`docs/manual-checks.md` PB-15).
"""

import argparse
import math
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import ai_docs_a1_proof as a1  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402

WORK = ROOT / "tools/proof/work/ai-docs-r2a"
a1.WORK = WORK
a1.HOME = WORK / "home"
a1.MEDIA = WORK / "media"
a1.VONLY = a1.MEDIA / "vonly.mov"
CALL_BOUND = 600
CONTROL_TRIALS = 3

LINES = {"H1": 0.10, "H2": 0.10, "H3": 0.10, "H4": 0.12, "H5": 0.12, "H6": 0.15}
RED_ROWS = ["H1", "H2", "H3", "H4", "H5", "H6"]
# Held for the owner (#537 H1–H2, #520 H3–H6): no candidate the batch built (S1–S4) cleared
# them, so nothing shipped and each is printed against its line, never scored. A fix that clears
# them takes its rows out of this set.
HELD = set(RED_ROWS)
CONTROL_ROWS = ["M1"]
MEASURE_ROWS = {"C1", "C2"} | HELD
ROWS = RED_ROWS + ["C1", "C2"] + CONTROL_ROWS + ["Z1"]

selected = set(ROWS)
results = {}
trials = 5


def check(name, ok, detail=""):
    if name not in selected:
        return
    results[name] = bool(ok)
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f"\n       {detail}" if detail else ""),
          flush=True)


def measure(name, detail):
    if name not in selected:
        return
    print(f"  MEASURE {name}\n       {detail}", flush=True)


def score(name, ok, detail):
    """A [B] row: scored, or, while it is HELD, printed with where it sits against its line."""
    if name in HELD:
        measure(name, f"{detail}; {'within' if ok else 'over'} the line (held, not scored)")
    else:
        check(name, ok, detail)


def med(values):
    return statistics.median(values) if values else float("nan")


def with_trials(n, body):
    """Runs `body` with a1's TRIALS set to n (a1's helpers read it per call)."""
    saved = a1.TRIALS
    a1.TRIALS = n
    try:
        return body()
    finally:
        a1.TRIALS = saved


# ---- the H rows ----------------------------------------------------------------------------


def pair_rows(client):
    doc, (first, _) = a1.loop_doc(client, "pair", a1.AV_MOV, 2)
    off, tos = with_trials(trials, lambda: a1.deficits(doc))
    d_off = med(off)
    score("H1", d_off <= LINES["H1"] and all(t >= 3.5 for t in tos),
          f"Loop off, 4 s from 0 paused: D {a1.fmt(off)}, median {d_off:.3f} s "
          f"(line {LINES['H1']:.2f}); to {a1.fmt(tos)} (floor 3.5)")
    if "H3" in selected:
        holds = with_trials(trials, lambda: a1.seek_holds(doc, d_off))
        score("H3", med(holds) <= LINES["H3"],
              f"seek holds {a1.fmt(holds)}, median {med(holds):.3f} s (line {LINES['H3']:.2f})")
    a1.loop_on_paused(doc, first)
    if "H5" in selected:
        on, _ = with_trials(trials, lambda: a1.deficits(doc))
        holds = with_trials(trials, lambda: a1.wrap_holds(doc, med(on)))
        score("H5", med(holds) <= LINES["H5"],
              f"Loop on: D {a1.fmt(on)}; per-wrap holds {a1.fmt(holds)}, median "
              f"{med(holds):.3f} s (line {LINES['H5']:.2f})")
    poll = a1.poll_holds(doc, first) if "H6" in selected else None
    doc.close()
    return poll


def m1_row(client, doc):
    client.call_with("loudness_meter", {**doc.a, "reset": True})
    _, _, wall, _ = doc.play(4)
    reading = client.call_with("loudness_meter", doc.a)
    frm, to, rate = reading.get("from_frame"), reading.get("to_frame"), reading.get("sample_rate")
    lufs = reading.get("integrated_lufs")
    frames_ok = None not in (frm, to, rate) and to - frm >= 3 * rate
    lufs_ok = isinstance(lufs, (int, float)) and math.isfinite(lufs)
    span = (to - frm) / rate if None not in (frm, to, rate) and rate else float("nan")
    check("M1", frames_ok and lufs_ok,
          f"after a 4 s play (wall {wall:.3f} s): frames [{frm}, {to}) at {rate} Hz "
          f"({span:.3f} s, floor 3 s), integrated {lufs}, resets {reading.get('resets')}, "
          f"last_reset {reading.get('last_reset')}")


def lone_rows(client):
    doc, (lone,) = a1.loop_doc(client, "lone", a1.AV_MOV, 1)
    if "M1" in selected:
        m1_row(client, doc)
    a1.loop_on_paused(doc, lone)
    on, _ = with_trials(trials, lambda: a1.deficits(doc))
    score("H2", med(on) <= LINES["H2"],
          f"Loop on, 4 s from 0 paused: D {a1.fmt(on)}, median {med(on):.3f} s "
          f"(line {LINES['H2']:.2f})")
    if "H4" in selected:
        holds = with_trials(trials, lambda: a1.wrap_holds(doc, med(on)))
        score("H4", med(holds) <= LINES["H4"],
              f"per-wrap holds {a1.fmt(holds)}, median {med(holds):.3f} s "
              f"(line {LINES['H4']:.2f})")
    poll = a1.poll_holds(doc, lone) if "H6" in selected else None
    doc.close()
    return poll


def poll_ok(poll):
    return poll is not None and len(poll[0]) >= 2 and all(v <= LINES["H6"] for v in poll[0])


def control_row(client, row, name, file, mute):
    doc, (clip,) = a1.loop_doc(client, name, file, 1)
    try:
        if mute:
            client.call_with("set_enabled", {**doc.a, "clip": clip, "audio": False})
            time.sleep(1)
        off, tos = with_trials(CONTROL_TRIALS, lambda: a1.deficits(doc))
        seeks = with_trials(CONTROL_TRIALS, lambda: a1.seek_holds(doc, med(off)))
        a1.loop_on_paused(doc, clip)
        on, _ = with_trials(CONTROL_TRIALS, lambda: a1.deficits(doc))
        wraps = with_trials(CONTROL_TRIALS, lambda: a1.wrap_holds(doc, med(on)))
        poll = a1.poll_holds(doc, clip)
        measure(row, f"Loop off: D {a1.fmt(off)} median {med(off):.3f} s (to {a1.fmt(tos)}), "
                     f"seek holds {a1.fmt(seeks)} median {med(seeks):.3f} s; Loop on: D "
                     f"{a1.fmt(on)} median {med(on):.3f} s, per-wrap holds {a1.fmt(wraps)} median "
                     f"{med(wraps):.3f} s; poll runs {a1.fmt(poll[0])} ({poll[1]} readings)")
    except mcp.ToolError as error:
        measure(row, f"refused: {error}")
    finally:
        doc.close()


# ---- the launch ----------------------------------------------------------------------------


def with_instance(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(a1.HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected - {"Z1"} - MEASURE_ROWS:
                check(row, False, "the app did not listen")
            return
        client = launched.client
        print(f"  instance PID {launched.child.pid}", flush=True)
        pair_poll = lone_poll = None
        if {"H1", "H3", "H5", "H6"} & selected:
            pair_poll = pair_rows(client)
        if {"H2", "H4", "H6", "M1"} & selected:
            lone_poll = lone_rows(client)
        if "H6" in selected:
            score("H6", poll_ok(pair_poll) and poll_ok(lone_poll),
                  f"runs at the loop start: pair {a1.fmt(pair_poll[0])} ({pair_poll[1]} "
                  f"readings), lone {a1.fmt(lone_poll[0])} ({lone_poll[1]} readings); line "
                  f"{LINES['H6']:.2f}, at least 2 wraps each")
        if "C1" in selected:
            control_row(client, "C1", "lone-muted", a1.AV_MOV, True)
        if "C2" in selected:
            control_row(client, "C2", "vonly", a1.VONLY, False)
    finally:
        launched.stop()
    lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def main():
    global selected, trials
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--trials", type=int, default=5)
    parser.add_argument("--app")
    parser.add_argument("--expect-red", action="store_true")
    args = parser.parse_args()
    trials = args.trials
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    shutil.rmtree(WORK, ignore_errors=True)
    a1.HOME.mkdir(parents=True)
    a1.make_media()

    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    print(f"ai-docs r2a on {binary}", flush=True)
    print(f"  default output: {a1.output_device()}", flush=True)
    print(f"  trials {trials} (controls {CONTROL_TRIALS}); held, not scored: "
          f"{', '.join(sorted(HELD & selected)) or 'none'}", flush=True)
    try:
        with_instance(binary)
    except (mcp.ToolError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"  the run stopped: {type(error).__name__}: {error}", flush=True)
    scored = sorted(selected - MEASURE_ROWS)
    for row in scored:
        if row not in results:
            results[row] = False
            print(f"  FAIL {row}\n       never scored", flush=True)
    passed = sum(1 for ok in results.values() if ok)
    print(f"\n{passed}/{len(results)} rows passed", flush=True)
    if args.expect_red:
        red = [r for r in RED_ROWS if r in results]  # the scored [B] rows; HELD ones never are
        controls = [r for r in results if r not in RED_ROWS]
        ok = all(not results[r] for r in red) and all(results[r] for r in controls)
        print(f"expect-red: [B] rows red {sum(1 for r in red if not results[r])}/{len(red)}, "
              f"controls green {sum(1 for r in controls if results[r])}/{len(controls)}",
              flush=True)
        return 0 if ok else 1
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
