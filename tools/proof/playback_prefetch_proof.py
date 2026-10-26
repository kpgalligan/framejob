#!/usr/bin/env python3
"""Issue #127 G6 phase 2 — preview playback's graphics rasterized ahead on
worker threads (spec §11 G-36, `app/Sources/GraphicPrefetch.swift`,
`Playback+Prefetch.swift`), against the built app, measured with the dev tool
`play_preview` (`AgentServer+PlayPreview.swift`).

The compositor stays the one writer and the texture key decides, so every
preview frame with the prefetch ON must be the serial path's pixels, and a
playing transport must start, follow and stop a session on the document's own
key. Two owned instances, one after the other, each on a scratch socket,
launched and stopped by PID, logs under `tools/proof/work/playback-prefetch/`:
OFF with `-FrameJobGraphicPrefetchOff YES`, ON without. Nothing else is ever
killed. Every child runs under `graphics_spike/bounded.py`; the launch,
`fixture()` and the log reading are `graphics_prefetch_proof.py`'s. Every
instance, the bench's included, also gets `-FrameJobGraphicKeepOff YES` (spec
§11 G-37 (e)), so no row and no bench cell is served from a document's kept
frames and each keeps phase 2's meaning; `graphic_memory_proof.py` measures
the kept frames. Every instance also gets `-FrameJobBackgroundRender NO`
(spec §11 G-38 (e)) unless it is made with `background=True` (only
`background_render_proof.py` passes it), so no paused document draws in the
background beside a row.

Fixtures, made over MCP on the OFF instance and saved under `work/`: H is
`graphics_prefetch_proof.fixture()`'s F (30 fps, two `heavy` clips, `static`
and `stepped`, each 4 s from 0, over a 5 s shape clip); L is a 30 fps project
holding one 5 s shape clip. Every play is preceded by `set_playhead`. A timing
ratio is scored only in the CONTROL rows (the rule, written before the rows).

P0  CONTROL, on each instance: L from 0 for 3 s, composed_ratio >= 0.9;
P1  OFF: H from 0 for 3 s answers, and OFF's log has no `graphic prefetch:`
    line;
P2  ON: H from 0 for 3 s; within 10 s a line ending `playback from 0, N
    skipped`, with hits > 0 and mismatched == 0;
P3  MEASURED, not scored: OFF and ON composed_ratio and compose_ms for H;
P4  ON: L's play, run before any H play, leaves no playback line within 10 s;
P5  ON: H from 600000 for 2 s; a further line `playback from 600000`;
P6  ON: H from 0 at rate 4 for 1 s; that line has skipped > 0;
P7  CONTROL: L from 0 for 3 s with digests, OFF against ON; at least 10
    common ticks, every common digest equal;
P8  P7 for H, each side's digests the union of three plays, from 0, 1 and
    2 frames (the serial path composes about one H frame in four, a loaded
    host fewer on either side, and which ones varies), every tick two plays
    of one side share agreeing; too few common ticks is reported apart
    from a digest that differs;
P9  ON: H from 0 for 2 s with seek_to 1800000; within 10 s a further line
    `playback from 1800000`;
P10 ON: H from 1200000 for 2 s with seek_to 0, a seek BEHIND the play; within
    10 s a line `playback from 0` with hits > 0 (the old position's requests
    still in flight do not move the new session's floor). A real-world row
    with no mutant: with `reach`'s range guard and the seek session's arming
    taken out, it passed twice on Release, because this play seldom has an
    old request served between the seek and AVFoundation's cancel (the
    stranded floor was seen once, in an `unguarded` run of a build without
    the arming: 0 hits, 86 skipped). P12–P14 hand the seek's session such a
    request deterministically (#329);
P11 ON, its last play: a loop lap. `set_selection` on H's first `heavy` clip,
    then `perform_menu_item ["Clip", "Motion", "Preview"]` (the in/out range
    set to the clip, Loop on, playing from its start), 6 s, then
    `play_preview {seconds: 0.5}` to pause; at least two `playback from 0`
    lines since, the last (the lap after the loop's return) with hits > 0.
    A real-world row: `no-range-guard` (`reach`'s `ticks < session.endTicks`
    taken out) passed it twice on Release (the lap 169 and 156 hits) —
    presumably because the old position's requests are served below the
    loop's end, inside the range, where the arming alone holds them off
    (not measured); P13 is that guard's row (#329);
P12 ON: H from 1200000 for 2 s with seek_to 0 and `stale_ticks [2700000]`,
    reported in the seek's own step, before the session is armed; within
    10 s a line `playback from 0` with hits > 0 and skipped < 75, and
    stale_reached [2700000] (the arming holds off a stale request inside
    the range). Hits alone do not catch a followed stale request: the
    frames the workers claimed before it still hit (10 in the first
    `follows-stale` run); its floor at frame 135 makes the workers skip at
    least 136 − workers frames;
P13 ON: P12 with `stale_ticks [6000000]` and `stale_armed: true`, reported
    once a frame in the seek's first 4 frames was composed; within 10 s a
    line `playback from 0` with hits > 0 and skipped < 75 (half of H's 150
    frames; the rule set before the run), and stale_reached [6000000] (far
    past H's 5 s end: the range's end holds off a request past it once the
    session is armed);
P14 ON: H from 1200000 for 2 s with seek_to 600000 and `stale_ticks [0,
    2700000]`, unarmed; within 10 s a line `playback from 600000` with
    hits > 0 and skipped < 75 (P12's reason; the floor would be frame 105),
    and stale_reached [0, 2700000] (the range's start holds off
    a request before it, which would otherwise arm the session for the
    second);
Z1  `grep "Frame Job: "` over every log prints nothing.

    python3 tools/proof/playback_prefetch_proof.py [--app PATH]
    python3 tools/proof/playback_prefetch_proof.py --mutant NAME
    python3 tools/proof/playback_prefetch_proof.py --bench PACKAGE --from T --seconds S

A mutant is built in a copy of the tree (`graphics_prefetch_proof.build_mutant`'s
way, each anchor exactly once in its file) and driven through every row; it
must fail its row: `worker-frame-plus-one` → P2, `unguarded` (that plus the
texture-key guard) → P8, `no-stop-on-pause` (`syncPrefetch`'s `stop`) → P2,
`no-graphic-gate` (`drawsGraphics` not consulted) → P4, `no-follow` (`reach`'s
floor raise) → P6, `seek-reads-player` (`startSeek` starts from `currentTime`)
→ P9, `no-arming` (`reach` arms a seek's session at its first request) →
P11, `follows-stale` (`reach`'s range guard `true`, and `no-arming`'s edit)
→ P12, `no-range-guard` (the guard's `ticks < session.endTicks` taken out)
→ P13, `no-start-guard` (its `ticks >= session.startTicks` taken out) →
P14. Exit 0 = caught, 1 = survived, 2 = the control (P0, P7) could not be
performed.

`--bench PACKAGE` launches one owned instance per cell — OFF and ON, each at
Full and at Quarter (`-FrameJobPreviewQuality 0` / `2`, launch arguments in
the argument domain; nothing persists) — copies PACKAGE under
`work/playback-prefetch-bench/` for each (the original is never opened), opens
the copy, `set_playhead` to `--from`, then `play_preview` for `--seconds`. It
prints `pmset -g`'s powermode line and `sysctl -n vm.loadavg` before each play,
`ps -o rss=` after it, the answer and ON's playback line. Scored only on each
play answering.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row
passes.
"""

import argparse
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_prefetch_proof as gp  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/playback-prefetch"
BENCH_WORK = ROOT / "tools/proof/work/playback-prefetch-bench"
APP = proof_app.binary()
SECOND = 600_000
ROWS = ["P0", "P1", "P2", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11", "P12", "P13", "P14",
        "Z1"]
CONTROLS = ("P0", "P7")
PLAY = re.compile(gp.LINE.pattern + r", playback from (\d+), (\d+) skipped")
PLAY_FIELDS = gp.FIELDS + ("start", "skipped")

PREFETCH = "app/Sources/GraphicPrefetch.swift"
SYNC = "app/Sources/Playback+Prefetch.swift"
PLAYBACK = "app/Sources/Playback.swift"
WORKER_PLUS_ONE = (PREFETCH, gp.WORKER_SVG,
                   gp.WORKER_SVG.replace("frame: slot.frame,", "frame: slot.frame + 1,"))
NO_ARMING = (PREFETCH, "            guard index < Self.armFrames else { return }\n", "")
RANGE_GUARD = "            ticks >= session.startTicks, ticks < session.endTicks\n"
# name: ([(file, anchor, replacement)], the row it must fail)
MUTANTS = {
    "worker-frame-plus-one": ([WORKER_PLUS_ONE], "P2"),
    "unguarded": ([WORKER_PLUS_ONE, (PREFETCH, gp.KEY_GUARD, " {")], "P8"),
    "no-stop-on-pause": (
        [(SYNC, "        GraphicPrefetch.shared.stop(recipeKey)\n", "")], "P2"),
    "no-graphic-gate": ([(SYNC, "let built, drawsGraphics", "let built")], "P4"),
    "no-follow": ([(PREFETCH, "session.floor = index", "_ = index")], "P6"),
    "seek-reads-player": (
        [(PLAYBACK, "syncPrefetch(from: clamped,", "syncPrefetch(from: currentTime,")], "P9"),
    "no-arming": ([NO_ARMING], "P11"),
    "no-range-guard": ([(PREFETCH, RANGE_GUARD, "            ticks >= session.startTicks\n")],
                       "P13"),
    "no-start-guard": ([(PREFETCH, RANGE_GUARD, "            ticks < session.endTicks\n")], "P14"),
    "follows-stale": ([(PREFETCH, RANGE_GUARD, "            true\n"), NO_ARMING], "P12"),
}
FRAME = SECOND // 30

rows = {}


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'ok' if good else 'FAIL'} — {detail}", flush=True)


class Instance(gp.Instance):
    """`graphics_prefetch_proof.Instance` with launch arguments of its own
    (the bench's Preview Quality), in the argument domain only, and
    `-FrameJobGraphicKeepOff YES` unless `keep_off` is False
    (`graphic_memory_proof.py` and `background_render_proof.py` pass False),
    and `-FrameJobBackgroundRender NO` unless `background` is True."""

    def __init__(self, app, log, off, extra=(), keep_off=True, background=False):
        super().__init__(app, log, off)
        self.extra = list(extra)
        self.keep_off = keep_off
        self.background = background

    def start(self, timeout=gp.CALL_BOUND):
        offset = self.log.stat().st_size if self.log.exists() else 0
        extra = (["-FrameJobGraphicPrefetchOff", "YES"] if self.off else []) \
            + (["-FrameJobGraphicKeepOff", "YES"] if self.keep_off else []) \
            + ([] if self.background else ["-FrameJobBackgroundRender", "NO"]) + self.extra
        with open(self.log, "a") as out:
            self.child = subprocess.Popen(
                [str(self.app), "-ApplePersistenceIgnoreState", "YES"] + extra,
                stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
                env=bounded.child_env({"RC_AGENT_SOCKET": self.socket}))
        if mcp.wait_listening(self.log, self.socket, child=self.child, seconds=60,
                              offset=offset):
            print(f"  {'OFF' if self.off else 'ON'} instance PID {self.child.pid} at "
                  f"{self.socket} {' '.join(self.extra)}", flush=True)
            return mcp.MCP(self.socket, timeout=timeout)
        return None


def play(client, package, start, seconds, **extra):
    """`set_playhead` to `start`, then `play_preview`; a preview still
    building its item is asked again for up to 15 s. The answer, or
    {"error": …}."""
    deadline = time.monotonic() + 15
    while True:
        gp.attempt(client, "set_playhead", {"project": str(package), "t": start})
        got = gp.attempt(client, "play_preview",
                         dict({"project": str(package), "seconds": seconds}, **extra))
        if got["ok"]:
            return got["reply"]
        if "nothing to play" not in got["error"] or time.monotonic() >= deadline:
            return {"error": got["error"]}
        time.sleep(0.5)


def playback_lines(log, offset):
    """Every playback session's line appended after `offset`, as dicts."""
    try:
        with open(log, errors="replace") as handle:
            handle.seek(offset)
            text = handle.read()
    except OSError:
        return []
    return [dict(zip(PLAY_FIELDS, map(int, m.groups()))) for m in PLAY.finditer(text)]


def await_playback(log, offset, start, seconds=10):
    """The last playback line from `start` (any start when None) appended
    after `offset`, waited for up to `seconds`; None when none came."""
    deadline = time.monotonic() + seconds
    while True:
        found = [line for line in playback_lines(log, offset)
                 if start is None or line["start"] == start]
        if found or time.monotonic() >= deadline:
            return found[-1] if found else None
        time.sleep(0.25)


def ratio(answer):
    return answer.get("composed_ratio") if isinstance(answer, dict) else None


def brief(answer):
    if not isinstance(answer, dict) or "error" in answer:
        return f"{answer}"
    keys = ("from", "to", "rate", "wall_seconds", "frames_expected", "frames_composed",
            "composed_ratio", "compose_ms", "seek_from", "stale_reached")
    return "{" + ", ".join(f"{k} {answer[k]}" for k in keys if k in answer) + "}"


def merged(answers):
    """One side's digests: `answers` is one answer or a list of them, merged
    into (tick → digest, the ticks two of them disagree on), or (None, None)
    when one has none."""
    answers = answers if isinstance(answers, list) else [answers]
    tables = [one.get("digests") if isinstance(one, dict) else None for one in answers]
    if not all(isinstance(t, dict) for t in tables):
        return None, None
    table, torn = {}, []
    for one in tables:
        for tick, digest in one.items():
            if table.setdefault(tick, digest) != digest:
                torn.append(tick)
    return table, torn


def digests_agree(off, on):
    """(at least 10 common ticks and every common digest equal, detail).
    Each side is one answer or a list of them, merged; a tick two plays of
    one side disagree on fails too."""
    a, torn_a = merged(off)
    b, torn_b = merged(on)
    if a is None or b is None:
        return False, f"OFF {[brief(one) for one in off] if isinstance(off, list) else brief(off)}, " \
            f"ON {[brief(one) for one in on] if isinstance(on, list) else brief(on)}"
    plays = [len(side) if isinstance(side, list) else 1 for side in (off, on)]
    common = sorted(set(a) & set(b), key=int)
    differ = [t for t in common if a[t] != b[t]]
    reasons = ([f"only {len(common)} common ticks (10 needed)"] if len(common) < 10 else []) \
        + ([f"{len(differ)} common digests differ {differ[:4]}"] if differ else []) \
        + ([f"OFF's plays differ at {len(torn_a)} ticks {torn_a[:4]}"] if torn_a else []) \
        + ([f"ON's plays differ at {len(torn_b)} ticks {torn_b[:4]}"] if torn_b else [])
    return (not reasons,
            f"{len(common)} common ticks of {len(a)} OFF (from {plays[0]} plays) and "
            f"{len(b)} ON (from {plays[1]}); " + ("; ".join(reasons) or "every common digest equal"))


def first_clip(client, package, name):
    """The id of the first clip `get_project` lists drawing graphic `name`,
    or None."""
    for clip in gp.project_of(client, package).get("clips", []):
        if isinstance(clip, dict) and (clip.get("graphic") or {}).get("name") == name:
            return clip.get("id")
    return None


def loop_lap(client, package, log):
    """P11's play: the first `heavy` clip selected, Clip ▸ Motion ▸ Preview,
    6 s, then a 0.5 s `play_preview` to pause. (every `playback from 0` line
    since, detail)."""
    offset = gp.log_size(log)
    clip = first_clip(client, package, "heavy")
    chose = gp.attempt(client, "set_selection", {"project": str(package), "clips": [clip]})
    menu = gp.attempt(client, "perform_menu_item",
                      {"project": str(package), "path": ["Clip", "Motion", "Preview"]})
    time.sleep(6)
    paused = gp.attempt(client, "play_preview", {"project": str(package), "seconds": 0.5})
    deadline = time.monotonic() + 10
    while True:
        laps = [line for line in playback_lines(log, offset) if line["start"] == 0]
        if len(laps) >= 2 or time.monotonic() >= deadline:
            break
        time.sleep(0.25)
    steps = [f"clip {clip}", f"selection {chose['ok'] or chose.get('error')}",
             f"menu {menu['ok'] or menu.get('error')}",
             f"pause {brief(paused['reply']) if paused['ok'] else paused.get('error')}"]
    return laps, "; ".join(steps)


def light_project(client, package):
    """L: a new 30 fps project holding one 5 s shape clip, saved."""
    return gp.graphic_project(client, package, [], [], tail=True)


# ---- the rows ---------------------------------------------------------------

def run_all(app):
    heavy, light = WORK / "H.framejob", WORK / "L.framejob"
    off_log, on_log = WORK / "off.log", WORK / "on.log"
    plays = {}

    off = Instance(app, off_log, off=True)
    try:
        client = off.start()
        made_h, detail_h = gp.fixture(client, heavy) if client else (False, "OFF did not launch")
        made_l, detail_l = light_project(client, light) if client else (False, "")
        print(f"  fixture H: {made_h} {detail_h}\n  fixture L: {made_l} {detail_l}", flush=True)
        plays["off-L"] = play(client, light, 0, 3)
        plays["off-H"] = play(client, heavy, 0, 3)
        plays["off-L-digests"] = play(client, light, 0, 3, digests=True)
        plays["off-H-digests"] = [play(client, heavy, start, 3, digests=True)
                                  for start in (0, FRAME, 2 * FRAME)]
    finally:
        off.stop()
    off_lines = gp.lines_since(off_log, 0)
    check("P1", made_h and "error" not in plays["off-H"] and off_lines == [],
          f"OFF H {brief(plays['off-H'])}; OFF's prefetch lines {off_lines}")

    on = Instance(app, on_log, off=False)
    try:
        client = on.start()
        opened = gp.opened(client, light) and gp.opened(client, heavy)
        print(f"  ON reopened both: {opened}", flush=True)

        offset = gp.log_size(on_log)
        plays["on-L"] = play(client, light, 0, 3)
        time.sleep(10)
        stray = gp.lines_since(on_log, offset)
        check("P4", made_l and "error" not in plays["on-L"] and stray == [],
              f"ON L {brief(plays['on-L'])}; prefetch lines within 10 s {stray}")

        good = all((ratio(plays[side]) or 0) >= 0.9 for side in ("off-L", "on-L"))
        check("P0", made_l and good,
              f"CONTROL L at rate 1: OFF {brief(plays['off-L'])}, ON {brief(plays['on-L'])}")

        offset = gp.log_size(on_log)
        plays["on-H"] = play(client, heavy, 0, 3)
        line = await_playback(on_log, offset, 0)
        check("P2", "error" not in plays["on-H"] and line is not None and line["hits"] > 0
              and line["mismatched"] == 0, f"ON H {brief(plays['on-H'])}; line {line}")
        print(f"P3 MEASURED — H from 0 for 3 s: OFF {brief(plays['off-H'])}; "
              f"ON {brief(plays['on-H'])}", flush=True)

        offset = gp.log_size(on_log)
        plays["on-H-600000"] = play(client, heavy, SECOND, 2)
        line = await_playback(on_log, offset, SECOND)
        check("P5", "error" not in plays["on-H-600000"] and line is not None,
              f"ON H from 600000 {brief(plays['on-H-600000'])}; line {line}")

        offset = gp.log_size(on_log)
        plays["on-H-rate4"] = play(client, heavy, 0, 1, rate=4)
        line = await_playback(on_log, offset, 0)
        check("P6", "error" not in plays["on-H-rate4"] and line is not None
              and line["skipped"] > 0, f"ON H at rate 4 {brief(plays['on-H-rate4'])}; line {line}")

        offset = gp.log_size(on_log)
        plays["on-H-seek"] = play(client, heavy, 0, 2, seek_to=3 * SECOND)
        line = await_playback(on_log, offset, 3 * SECOND)
        check("P9", "error" not in plays["on-H-seek"] and line is not None,
              f"ON H seek_to 1800000 {brief(plays['on-H-seek'])}; line {line}; every line "
              f"since {gp.lines_since(on_log, offset)}")

        offset = gp.log_size(on_log)
        plays["on-H-behind"] = play(client, heavy, 2 * SECOND, 2, seek_to=0)
        line = await_playback(on_log, offset, 0)
        check("P10", "error" not in plays["on-H-behind"] and line is not None
              and line["hits"] > 0,
              f"ON H from 1200000 seek_to 0 {brief(plays['on-H-behind'])}; line {line}; every "
              f"line since {gp.lines_since(on_log, offset)}")

        offset = gp.log_size(on_log)
        plays["on-H-stale"] = play(client, heavy, 2 * SECOND, 2, seek_to=0,
                                   stale_ticks=[2_700_000])
        line = await_playback(on_log, offset, 0)
        check("P12", "error" not in plays["on-H-stale"] and line is not None
              and line["hits"] > 0 and line["skipped"] < 75
              and plays["on-H-stale"].get("stale_reached") == [2_700_000],
              f"ON H from 1200000 seek_to 0, stale 2700000 unarmed "
              f"{brief(plays['on-H-stale'])}; line {line} (skipped under 75 needed); every line "
              f"since "
              f"{gp.lines_since(on_log, offset)}")

        offset = gp.log_size(on_log)
        plays["on-H-past-end"] = play(client, heavy, 2 * SECOND, 2, seek_to=0,
                                      stale_ticks=[10 * SECOND], stale_armed=True)
        line = await_playback(on_log, offset, 0)
        check("P13", "error" not in plays["on-H-past-end"] and line is not None
              and line["hits"] > 0 and line["skipped"] < 75
              and plays["on-H-past-end"].get("stale_reached") == [10 * SECOND],
              f"ON H from 1200000 seek_to 0, stale 6000000 armed "
              f"{brief(plays['on-H-past-end'])}; line {line} (skipped under 75 needed); every "
              f"line since {gp.lines_since(on_log, offset)}")

        offset = gp.log_size(on_log)
        plays["on-H-before-start"] = play(client, heavy, 2 * SECOND, 2, seek_to=SECOND,
                                          stale_ticks=[0, 2_700_000])
        line = await_playback(on_log, offset, SECOND)
        check("P14", "error" not in plays["on-H-before-start"] and line is not None
              and line["hits"] > 0 and line["skipped"] < 75
              and plays["on-H-before-start"].get("stale_reached") == [0, 2_700_000],
              f"ON H from 1200000 seek_to 600000, stale 0 and 2700000 unarmed "
              f"{brief(plays['on-H-before-start'])}; line {line} (skipped under 75 needed); "
              f"every line since "
              f"{gp.lines_since(on_log, offset)}")

        plays["on-L-digests"] = play(client, light, 0, 3, digests=True)
        plays["on-H-digests"] = [play(client, heavy, start, 3, digests=True)
                                 for start in (0, FRAME, 2 * FRAME)]

        laps, detail = loop_lap(client, heavy, on_log)
        check("P11", len(laps) >= 2 and laps[-1]["hits"] > 0,
              f"{detail}; `playback from 0` lines {laps}")
    finally:
        on.stop()

    good, detail = digests_agree(plays["off-L-digests"], plays["on-L-digests"])
    check("P7", made_l and good, f"CONTROL L: {detail}")
    good, detail = digests_agree(plays["off-H-digests"], plays["on-H-digests"])
    check("P8", made_h and good, f"H: {detail}")
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
    print(f"playback prefetch — the {name} MUTANT ({row} must FAIL)", flush=True)
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

def powermode():
    lines = bounded.run(["pmset", "-g"], 30)["stdout"].splitlines()
    found = [line.strip() for line in lines if "powermode" in line]
    return found[0] if found else "(no powermode line)"


def rss(pid):
    return bounded.run(["ps", "-o", "rss=", "-p", str(pid)], 30)["stdout"].strip()


def run_bench(app, source, start, seconds):
    print(f"playback prefetch — bench of {source}, from {start} for {seconds} s, "
          f"OFF and ON at Full and Quarter", flush=True)
    if not source.is_dir():
        print(f"bench FAIL — {source} is not a package")
        return 1
    tree_copy.remove_tree(BENCH_WORK)
    BENCH_WORK.mkdir(parents=True)
    answered = {}
    for mode, off in (("off", True), ("on", False)):
        for quality, value in (("full", "0"), ("quarter", "2")):
            cell = f"{mode}-{quality}"
            package = BENCH_WORK / cell / source.name
            shutil.copytree(source, package, symlinks=True)
            log = BENCH_WORK / f"bench-{cell}.log"
            instance = Instance(app, log, off=off, extra=["-FrameJobPreviewQuality", value])
            try:
                client = instance.start(timeout=gp.BENCH_BOUND)
                ok_open = gp.opened(client, package)
                print(f"  {cell}: {powermode()}; load average before {gp.loadavg()}",
                      flush=True)
                offset = gp.log_size(log)
                answer = play(client, package, start, seconds)
                memory = rss(instance.child.pid) if instance.child else "?"
                line = None if off else await_playback(log, offset, None)
            finally:
                instance.stop()
            answered[cell] = ok_open and isinstance(answer, dict) and "error" not in answer
            print(f"  {cell}: open {ok_open}; rss {memory} KiB after; {brief(answer)}",
                  flush=True)
            if not off:
                print(f"  {cell}: playback line {line}", flush=True)
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
    print("#127 G6 phase 2 — preview playback's graphics rasterized ahead on worker threads, "
          "against the built app (proof)", flush=True)
    run_all(args.app)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
