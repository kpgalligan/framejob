#!/usr/bin/env python3
"""Issue #127 G6 phase 3 — the graphic rasters' one memory budget and the
frames a document keeps (spec §11 G-37, `app/Sources/GraphicPrefetch.swift`,
`GraphicPrefetch+Memory.swift`), against the built app, measured with the dev
tools `graphic_memory` (`AgentServer+GraphicMemory.swift`) and `play_preview`.

A raster is a function of its texture key, so a kept raster must be the serial
path's pixels; the budget is a quarter of physical memory, less under memory
pressure, and the kept frames never exceed the room the held rasters leave.
Three owned instances, one after the other, each on a scratch socket, launched
and stopped by PID, logs under `tools/proof/work/graphic-memory/`: SERIAL
(`-FrameJobGraphicPrefetchOff YES -FrameJobGraphicKeepOff YES`), KEEP (no
switches) and KEEP-SERIAL (`-FrameJobGraphicPrefetchOff YES`), switches in the
argument domain only; every instance, the bench's included, runs with
Background render off (`-FrameJobBackgroundRender NO`, `pp.Instance`'s
default, spec §11 G-38 (e)), so no row counts frames a paused pass drew. Nothing else is ever killed. Every child runs under
`graphics_spike/bounded.py`; the launch, the plays and the log reading are
`playback_prefetch_proof.py`'s (`pp`) and `graphics_prefetch_proof.py`'s
(`gp`).

Fixtures, made over MCP on SERIAL and saved under `work/`: H is `gp.fixture()`
(30 fps, two `heavy` clips, `static` and `stepped`, each 4 s from 0, over a
5 s shape clip); L is `pp.light_project()` (one 5 s shape clip). A timing
figure is scored only in a CONTROL row (the rule, written before the rows).

M0  CONTROL: L from 0 for 3 s, composed_ratio >= 0.9 on SERIAL and on KEEP;
M1  KEEP's first `graphic_memory {}`: physical_bytes is `sysctl -n hw.memsize`,
    budget_bytes is that over 4, 8 or 0 by the answer's own pressure,
    held_bytes is 0;
M2  KEEP: H from 0 for 3 s, its playback line awaited; then kept_frames > 0,
    kept_bytes > 0, held_bytes == 0;
M3  KEEP: H from 0 for 3 s again; its line has kept > 0 and kept_hits rose;
M4  KEEP-SERIAL: H from 0 for 3 s twice; the second play's kept_hits rose
    (no session: the kept frames answer `take` alone). Both composed_ratios
    printed as MEASURED;
M5  H's digests, each side the union of plays from 0, 1 and 2 frames
    (`pp.digests_agree`), KEEP after M3 against SERIAL: at least 10 common
    ticks, every common digest equal;
M6  KEEP, paused: `set_playhead` at frames 3..8 of H, 0.3 s apart; kept_hits
    rose;
M7  KEEP: `{pressure: "warning"}` answers budget physical / 8 and kept_bytes
    <= budget; `{pressure: "critical"}` budget 0 and kept_frames 0; H from 0
    for 2 s under critical: its line has 0 frames with graphics, and
    kept_frames is 0 after; `{pressure: "normal"}` answers physical / 4;
M8  KEEP: H from 0 for 2 s (kept_frames > 0 after), then `close_project` H;
    within 5 s kept_frames == 0;
M9  SERIAL, after its H plays: kept_frames == 0 and kept_hits == 0;
M10 M2's answer: held_peak_entries > 4 x workers + workers x 4 (workers from
    M2's line; H draws 4 graphic layers a frame) and held_peak_entries <= 1024
    (one session runs at a time here). The lower bound is the most a slot
    limit of 4 x workers can hold: a claim reserves nothing, so every worker
    can claim just under the limit and then insert its frame's layers. At
    4 x workers alone the `slot-limit` mutant passed (74 entries on Release,
    2026-10-21);
M11 every `graphic_memory` answer read (M1..M10): kept_bytes <= max(0,
    budget_bytes - held_bytes) and held_bytes >= 0;
Z1  `grep "Frame Job: "` over every log prints nothing.

    python3 tools/proof/graphic_memory_proof.py [--app PATH]
    python3 tools/proof/graphic_memory_proof.py --mutant NAME
    python3 tools/proof/graphic_memory_proof.py --bench PACKAGE --from T --seconds S

A mutant is built in a copy of the tree under this proof's own `work/`
(`pp.build_mutant`'s way, each anchor exactly once in its file) and driven
through every row; it must fail its row: `kept-any-texture` (the kept lookup
answers the key's most recent raster, whatever the texture key) → M5,
`no-compositor-keep` (`LayerRenderersGraphic`'s `keep` call removed) → M4,
`no-pressure-trim` (`setPressure`'s trim) → M7, `budget-ignored` (`claim`'s
`heldTotal >= budgetBytes`) → M7, `slot-limit` (`claim` also waits at
`4 × session.workerCount` slots) → M10, `kept-outlives-window`
(`invalidate`'s and `stopGraphicStore`'s `dropKept` removed, `deinit`'s
`endKeeping` back to `stop`) → M8, `keep-switch-ignored` (`beginKeeping`'s
switch) → M9. Exit 0 = caught, 1 = survived, 2 = the control (M0) could not
be performed.

`--bench PACKAGE` runs two cells at Full (`-FrameJobPreviewQuality 0`):
KEEP-OFF (`-FrameJobGraphicKeepOff YES`) and KEEP. Each copies PACKAGE under
`work/graphic-memory-bench/` (the original is never opened), opens the copy
and plays from `--from` for `--seconds` twice, printing per play `pmset -g`'s
powermode line, `sysctl -n vm.loadavg`, the answer, the playback line,
`graphic_memory` and `ps -o rss=`. Scored only on every play answering.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row
passes.
"""

import argparse
import re
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_prefetch_proof as gp  # noqa: E402
import playback_prefetch_proof as pp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/graphic-memory"
BENCH_WORK = ROOT / "tools/proof/work/graphic-memory-bench"
APP = proof_app.binary()
SECOND = pp.SECOND
FRAME = pp.FRAME
ROWS = ["M0", "M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10", "M11", "Z1"]
CONTROLS = ("M0",)
ENTRY_CEILING = 1024
H_LAYERS = 4  # H's graphic layers a frame: two `heavy`, `static`, `stepped`
KEPT = re.compile(pp.PLAY.pattern + r", (\d+) kept")
KEPT_FIELDS = pp.PLAY_FIELDS + ("kept",)

PREFETCH = "app/Sources/GraphicPrefetch.swift"
MEMORY = "app/Sources/GraphicPrefetch+Memory.swift"
RENDERER = "app/Sources/LayerRenderersGraphic.swift"
PLAYBACK = "app/Sources/Playback.swift"
DOCUMENT = "app/Sources/ProjectDocument+Graphics.swift"
# name: ([(file, anchor, replacement)], the row it must fail)
MUTANTS = {
    "kept-any-texture": (
        [(MEMORY,
          "guard let frame = frames[Name(key: key, textureKey: textureKey)] else { return nil }",
          "guard let frame = frames.values.filter({ $0.name.key == key })"
          ".max(by: { $0.stamp < $1.stamp }) else { return nil }")], "M5"),
    "no-compositor-keep": (
        [(RENDERER,
          "            GraphicPrefetch.shared.keep(recipeKey, textureKey: key, raster: raster)\n",
          "")], "M4"),
    "no-pressure-trim": (
        [(MEMORY,
          "        kept.trim(toFit: budgetBytes - heldTotal)\n        condition.broadcast()\n",
          "        condition.broadcast()\n")], "M7"),
    "budget-ignored": ([(PREFETCH, "heldTotal >= budgetBytes || ", "")], "M7"),
    "slot-limit": (
        [(PREFETCH, "session.slots.count >= Self.entryCeiling",
          "session.slots.count >= min(Self.entryCeiling, 4 * session.workerCount)")], "M10"),
    "kept-outlives-window": (
        [(PLAYBACK, "        GraphicPrefetch.shared.dropKept(recipeKey)\n", ""),
         (DOCUMENT, "        GraphicPrefetch.shared.dropKept(recipeKey)\n", ""),
         (PLAYBACK, "GraphicPrefetch.shared.endKeeping(recipeKey)",
          "GraphicPrefetch.shared.stop(recipeKey)")], "M8"),
    "keep-switch-ignored": (
        [(MEMORY,
          "        guard !UserDefaults.standard.bool(forKey: Self.keepOffDefaultsKey) "
          "else { return }\n", "")], "M9"),
}

rows = {}
answers = []


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'ok' if good else 'FAIL'} — {detail}", flush=True)


def memory(client, **arguments):
    """`graphic_memory`'s answer, kept for M11, or {"error": …}."""
    got = gp.attempt(client, "graphic_memory", arguments)
    answer = got["reply"] if got["ok"] and isinstance(got["reply"], dict) \
        else {"error": got.get("error", got.get("reply"))}
    answers.append(answer)
    return answer


def field(answer, key):
    """`answer[key]`, or None when the answer is an error or lacks it."""
    return answer.get(key) if isinstance(answer, dict) and "error" not in answer else None


def rose(before, after):
    a, b = field(before, "kept_hits"), field(after, "kept_hits")
    return a is not None and b is not None and b > a


def kept_lines(log, offset):
    """Every playback session's line appended after `offset`, with its kept
    count, as dicts."""
    try:
        with open(log, errors="replace") as handle:
            handle.seek(offset)
            text = handle.read()
    except OSError:
        return []
    return [dict(zip(KEPT_FIELDS, map(int, m.groups()))) for m in KEPT.finditer(text)]


def await_kept(log, offset, start, seconds=10):
    """The last playback line from `start` (any when None) appended after
    `offset`, waited for up to `seconds`; None when none came."""
    deadline = time.monotonic() + seconds
    while True:
        found = [line for line in kept_lines(log, offset)
                 if start is None or line["start"] == start]
        if found or time.monotonic() >= deadline:
            return found[-1] if found else None
        time.sleep(0.25)


def physical():
    text = bounded.run(["sysctl", "-n", "hw.memsize"], 30)["stdout"].strip()
    return int(text) if text.isdigit() else None


def budget_of(total, pressure):
    return {"normal": total // 4, "warning": total // 8, "critical": 0}.get(pressure)


def short(answer):
    if not isinstance(answer, dict) or "error" in answer:
        return f"{answer}"
    keys = ("budget_bytes", "pressure", "held_bytes", "held_peak_bytes", "held_peak_entries",
            "kept_bytes", "kept_frames", "kept_hits")
    return "{" + ", ".join(f"{k} {answer[k]}" for k in keys if k in answer) + "}"


# ---- the rows ---------------------------------------------------------------

def run_all(app):
    heavy, light = WORK / "H.framejob", WORK / "L.framejob"
    serial_log, keep_log, keep_serial_log = (WORK / "serial.log", WORK / "keep.log",
                                             WORK / "keep-serial.log")
    plays = {}
    total = physical()

    serial = pp.Instance(app, serial_log, off=True)
    try:
        client = serial.start()
        made_h, detail_h = gp.fixture(client, heavy) if client else (False, "SERIAL did not launch")
        made_l, detail_l = pp.light_project(client, light) if client else (False, "")
        print(f"  fixture H: {made_h} {detail_h}\n  fixture L: {made_l} {detail_l}", flush=True)
        plays["serial-L"] = pp.play(client, light, 0, 3)
        plays["serial-H-digests"] = [pp.play(client, heavy, start, 3, digests=True)
                                     for start in (0, FRAME, 2 * FRAME)]
        after = memory(client)
        check("M9", made_h and all("error" not in one for one in plays["serial-H-digests"])
              and field(after, "kept_frames") == 0 and field(after, "kept_hits") == 0,
              f"SERIAL after its H plays {short(after)}")
    finally:
        serial.stop()

    keep = pp.Instance(app, keep_log, off=False, keep_off=False)
    try:
        client = keep.start()
        opened = gp.opened(client, light) and gp.opened(client, heavy)
        print(f"  KEEP reopened both: {opened}", flush=True)
        plays["keep-L"] = pp.play(client, light, 0, 3)
        good = all((pp.ratio(plays[side]) or 0) >= 0.9 for side in ("serial-L", "keep-L"))
        check("M0", made_l and good, f"CONTROL L at rate 1: SERIAL {pp.brief(plays['serial-L'])}, "
              f"KEEP {pp.brief(plays['keep-L'])}")

        first = memory(client)
        budget = field(first, "budget_bytes")
        check("M1", total is not None and field(first, "physical_bytes") == total
              and budget is not None and budget == budget_of(total, field(first, "pressure"))
              and field(first, "held_bytes") == 0,
              f"hw.memsize {total}; physical_bytes {field(first, 'physical_bytes')}; "
              f"{short(first)}")

        offset = gp.log_size(keep_log)
        plays["keep-H-1"] = pp.play(client, heavy, 0, 3)
        line2 = await_kept(keep_log, offset, 0)
        m2 = memory(client)
        check("M2", "error" not in plays["keep-H-1"] and line2 is not None
              and (field(m2, "kept_frames") or 0) > 0 and (field(m2, "kept_bytes") or 0) > 0
              and field(m2, "held_bytes") == 0,
              f"KEEP H {pp.brief(plays['keep-H-1'])}; line {line2}; {short(m2)}")

        offset = gp.log_size(keep_log)
        plays["keep-H-2"] = pp.play(client, heavy, 0, 3)
        line3 = await_kept(keep_log, offset, 0)
        m3 = memory(client)
        check("M3", "error" not in plays["keep-H-2"] and line3 is not None
              and line3["kept"] > 0 and rose(m2, m3),
              f"KEEP H again {pp.brief(plays['keep-H-2'])}; line {line3}; {short(m3)}")

        plays["keep-H-digests"] = [pp.play(client, heavy, start, 3, digests=True)
                                   for start in (0, FRAME, 2 * FRAME)]

        before = memory(client)
        scrub = []
        for frame in range(3, 9):
            got = gp.attempt(client, "set_playhead", {"project": str(heavy), "t": frame * FRAME})
            scrub.append(got["ok"] or got.get("error"))
            time.sleep(0.3)
        time.sleep(0.5)
        m6 = memory(client)
        check("M6", all(ok is True for ok in scrub) and rose(before, m6),
              f"set_playhead {scrub}; before {short(before)}; after {short(m6)}")

        warning = memory(client, pressure="warning")
        critical = memory(client, pressure="critical")
        offset = gp.log_size(keep_log)
        plays["keep-H-critical"] = pp.play(client, heavy, 0, 2)
        line7 = await_kept(keep_log, offset, 0)
        after_critical = memory(client)
        normal = memory(client, pressure="normal")
        good = (total is not None
                and field(warning, "budget_bytes") == total // 8
                and field(warning, "kept_bytes") is not None
                and field(warning, "kept_bytes") <= total // 8
                and field(critical, "budget_bytes") == 0 and field(critical, "kept_frames") == 0
                and "error" not in plays["keep-H-critical"] and line7 is not None
                and line7["frames"] == 0 and field(after_critical, "kept_frames") == 0
                and field(normal, "budget_bytes") == total // 4)
        check("M7", good, f"warning {short(warning)}; critical {short(critical)}; H under "
              f"critical {pp.brief(plays['keep-H-critical'])}, line {line7}, after "
              f"{short(after_critical)}; normal {short(normal)}")

        plays["keep-H-close"] = pp.play(client, heavy, 0, 2)
        filled = memory(client)
        closed = gp.attempt(client, "close_project", {"project": str(heavy), "discard": True})
        deadline = time.monotonic() + 5
        emptied = memory(client)
        while field(emptied, "kept_frames") != 0 and time.monotonic() < deadline:
            time.sleep(0.5)
            emptied = memory(client)
        check("M8", "error" not in plays["keep-H-close"]
              and (field(filled, "kept_frames") or 0) > 0 and closed["ok"]
              and field(emptied, "kept_frames") == 0,
              f"after the play {short(filled)}; close {closed['ok'] or closed.get('error')}; "
              f"then {short(emptied)}")

        workers = line2["workers"] if line2 else None
        peak = field(m2, "held_peak_entries")
        floor = 4 * workers + workers * H_LAYERS if workers is not None else None
        check("M10", floor is not None and peak is not None and floor < peak <= ENTRY_CEILING,
              f"M2's held_peak_entries {peak}; a 4 x {workers}-slot limit holds at most {floor} "
              f"(4 x workers + workers x {H_LAYERS} layers); ceiling {ENTRY_CEILING}")
    finally:
        keep.stop()

    keep_serial = pp.Instance(app, keep_serial_log, off=True, keep_off=False)
    try:
        client = keep_serial.start()
        print(f"  KEEP-SERIAL reopened H: {gp.opened(client, heavy)}", flush=True)
        start = memory(client)
        plays["keep-serial-H-1"] = pp.play(client, heavy, 0, 3)
        between = memory(client)
        plays["keep-serial-H-2"] = pp.play(client, heavy, 0, 3)
        end = memory(client)
        check("M4", all("error" not in plays[k] for k in ("keep-serial-H-1", "keep-serial-H-2"))
              and rose(between, end),
              f"start {short(start)}; after the first {short(between)}; after the second "
              f"{short(end)}")
        print(f"M4 MEASURED — KEEP-SERIAL H from 0 for 3 s: first "
              f"{pp.brief(plays['keep-serial-H-1'])}; second "
              f"{pp.brief(plays['keep-serial-H-2'])}", flush=True)
    finally:
        keep_serial.stop()

    good, detail = pp.digests_agree(plays["serial-H-digests"], plays["keep-H-digests"])
    check("M5", made_h and good, f"H, SERIAL against KEEP: {detail}")

    bad = [short(a) for a in answers
           if field(a, "kept_bytes") is None or field(a, "held_bytes") is None
           or field(a, "budget_bytes") is None or field(a, "held_bytes") < 0
           or field(a, "kept_bytes") > max(0, field(a, "budget_bytes") - field(a, "held_bytes"))]
    check("M11", answers and not bad, f"{len(answers)} answers; breaking {bad[:4]}")
    found = gp.complaints()
    check("Z1", found == [], f"{found[:5]}")


def build_mutant(name):
    """A copy of the tree with each of the mutant's anchors replaced exactly
    once in its file, built by `tree_copy.build_app`. The binary, or None and
    why."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    for path, anchor, replacement in MUTANTS[name][0]:
        target = copy / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"{anchor!r} occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(copy, 1500)
    if app is None:
        return None, reason
    return proof_app.executable(app), ""


def run_mutant(name):
    row = MUTANTS[name][1]
    print(f"graphic memory — the {name} MUTANT ({row} must FAIL)", flush=True)
    binary, why = build_mutant(name)
    if binary is None:
        print(f"mutant {name}: the control could not be performed — the copy was not built: "
              f"{why}")
        return 2
    run_all(binary)
    failed = [r for r in CONTROLS if not rows.get(r)]
    if failed:
        print(f"mutant {name}: the control could not be performed — {failed} failed")
        return 2
    caught = not rows.get(row)
    print(f"the mutant is CAUGHT: {row} FAILED" if caught else "the mutant was NOT caught")
    return 0 if caught else 1


# ---- the bench --------------------------------------------------------------

def run_bench(app, source, start, seconds):
    print(f"graphic memory — bench of {source}, from {start} for {seconds} s twice, "
          f"KEEP-OFF and KEEP at Full", flush=True)
    if not source.is_dir():
        print(f"bench FAIL — {source} is not a package")
        return 1
    tree_copy.remove_tree(BENCH_WORK)
    BENCH_WORK.mkdir(parents=True)
    answered = {}
    for cell, keep_off in (("keep-off", True), ("keep", False)):
        package = BENCH_WORK / cell / source.name
        shutil.copytree(source, package, symlinks=True)
        log = BENCH_WORK / f"bench-{cell}.log"
        instance = pp.Instance(app, log, off=False, keep_off=keep_off,
                               extra=["-FrameJobPreviewQuality", "0"])
        try:
            client = instance.start(timeout=gp.BENCH_BOUND)
            ok_open = gp.opened(client, package)
            print(f"  {cell}: open {ok_open}", flush=True)
            for lap in (1, 2):
                print(f"  {cell} play {lap}: {pp.powermode()}; load average before "
                      f"{gp.loadavg()}", flush=True)
                offset = gp.log_size(log)
                answer = pp.play(client, package, start, seconds)
                line = await_kept(log, offset, None)
                state = memory(client)
                size = pp.rss(instance.child.pid) if instance.child else "?"
                answered[f"{cell}-{lap}"] = (ok_open and isinstance(answer, dict)
                                             and "error" not in answer)
                print(f"  {cell} play {lap}: {pp.brief(answer)}\n"
                      f"    playback line {line}\n    graphic_memory {short(state)}\n"
                      f"    rss {size} KiB after", flush=True)
        finally:
            instance.stop()
    good = all(answered.values())
    print(f"bench {'ok' if good else 'FAIL'} — every play answered: {answered}")
    return 0 if good else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--bench", type=Path)
    parser.add_argument("--from", dest="start", type=int, default=0)
    parser.add_argument("--seconds", type=float, default=10)
    args = parser.parse_args()
    tree_copy.remove_tree(WORK)
    WORK.mkdir(parents=True)
    if args.mutant:
        return run_mutant(args.mutant)
    if not args.app.exists():
        print(f"the app is not built: {args.app}")
        return 1
    if args.bench:
        return run_bench(args.app, args.bench.expanduser().resolve(), args.start, args.seconds)
    print("#127 G6 phase 3 — one memory budget and kept graphic frames, against the built app "
          "(proof)", flush=True)
    run_all(args.app)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
