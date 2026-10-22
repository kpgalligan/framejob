#!/usr/bin/env python3
"""Issue #127 G6 phase 4 — Background render: graphic frames drawn ahead
while paused once Frame Job is left alone (spec §11 G-38,
`app/Sources/BackgroundRender.swift`, `GraphicPrefetch.swift`'s background
sessions, `GraphicPrefetch+Memory.swift`'s ahead marks), against the built
app, measured with the dev tools `graphic_memory` and `play_preview`.

A background pass draws a paused document's graphic frames from its playhead
into its kept frames (G-37), marked as drawn ahead; any activity stops it,
it never runs beside a play, and the play that follows from the same
playhead keeps those frames until the compositor reaches them. A kept raster
is the serial path's, so the pass changes when a frame is ready, never its
pixels. Three owned instances, one after the other, each on a scratch
socket, launched and stopped by PID, logs under
`tools/proof/work/background-render/`: SERIAL (prefetch off, keep off,
background off), BG-OFF (keeping, `-FrameJobBackgroundRender NO`,
`-FrameJobBackgroundRenderDelay 1`) and BG (keeping, Background render on,
`-FrameJobBackgroundRenderDelay 1`), switches in the argument domain only.
BG, BG-OFF and the bench's cells also get `-NSAppSleepDisabled YES`, so App
Nap, which throttles a hidden app's utility-QoS threads, cannot stand between
a row and the pass it measures (a precaution: on a host loaded by other
sessions the passes drew 0 to 98 frames a second, not measured with and
without it).
Nothing else is ever killed, and no proof clicks the Settings pane. Every
child runs under `graphics_spike/bounded.py`; the launch, the plays and the
log reading are `playback_prefetch_proof.py`'s (`pp`),
`graphics_prefetch_proof.py`'s (`gp`) and `graphic_memory_proof.py`'s
(`gm`).

Fixtures, made over MCP on SERIAL and saved under `work/`: H is
`gp.fixture()` (30 fps, two `heavy` clips, `static` and `stepped`, each 4 s
from 0, over a 5 s shape clip), H2 a copy of H; LONG is one `heavy` clip
through `gp.graphic_project`, on a 2560 x 1440 canvas at that size (so that
B12's pass stays under a session's 1,024 entries and unguarded workers can
outrun its play; `LONG_SIZE`'s comment),
lengthened by `trim_end` to the greater of 60 s and the length whose frames,
at its canvas's width x height x 4 bytes, hold 1.5 x physical / 8 (physical
from `graphic_memory`). Before each
mid-pass row the kept frames are emptied (`graphic_memory {pressure:
"critical"}`, then `"normal"`).

The CONTROLS (the rule, written before the rows): a mid-pass row's control is
a `started` line for the key since its offset and no end line yet at the
interruption (B5, B6, B7, B10); B12's is an end line reading `full`; B13's is
H's `set_playhead` answering while LONG plays (the pausing `play_preview`
then starts at least 1 s in). A mid-pass row's and B12's are performed
again once when they fail: activity this proof does not make (a scroll over
one of its windows, an autosave) stops a pass too. A run whose control fails
exits 2.

B1  BG: `set_playhead` H to 1 frame; measured from its return, no
    `graphic background:` line by 0.5 s;
B2  then, by 4 s, a `started … from 20000` line; within 30 s an end line
    `done` with drawn > 0, and kept_frames rose;
B3  `set_playhead` H to 1 frame again: the next end line has 0 drawn and
    already kept > 0 (not to 0, as written first: frame 0's rasters were
    emptied before B1 and the compositor's pool still holds them, so the
    seek to 0 keeps none and the pass draws frame 0's two `heavy` layers —
    measured, 2 drawn);
B4  H plays from 0 for 3 s: kept_hits rose and its playback line's kept > 10.
    The composed_ratio is MEASURED;
B11 H2 `set_playhead` 0 and its `done` awaited, then H2 plays from 0, 1 and 2
    frames with digests, against SERIAL's (`pp.digests_agree`): at least 10
    common ticks, every common digest equal;
B9  BG, H2, under `{pressure: "critical"}`: `set_playhead` to 1 frame; an end
    line `full` with 0 drawn within 5 s; then `"normal"`;
B5  mid-pass on LONG, `set_playhead` on H (another window): LONG's end line
    reads `stopped` within 5 s;
B6  mid-pass on LONG, `set_playhead` LONG to frame 10: LONG reads `stopped`,
    then a new `started … from 200000`;
B12 under `{pressure: "warning"}`: LONG's kept frames emptied, `set_playhead`
    LONG to 1 frame and its `full` end line awaited (bound 300 s; D drawn);
    `graphic_memory` read (which resets `ahead_evicted`); LONG then plays
    from that frame for 0.8 x D / 30 s: its playback line's kept > 30 and
    kept >= 0.9 x (kept + hits + missed + mismatched), and `graphic_memory`
    then answers `ahead_evicted` 0 — no frame the pass drew ahead was
    trimmed out before the compositor reached it. The share alone cannot
    see an unguarded play (fix pass 1): a `full` pass leaves less than one
    frame of room, so each unguarded worker's first reservation trims out a
    marked frame at once, about one per worker, and the rest of the damage
    waits on the workers passing the pass's end, which the host's speed
    decides (shares 0.994 and 0.958 survived 0.9); the count sees the first
    trim on any host. Then `"normal"`;
B13 LONG plays from 0 through Clip ▸ Motion ▸ Preview (`set_selection` its
    clip, `perform_menu_item`, which answers while LONG plays: the agent
    lane serialises every call, AI-2, so a second client's `play_preview`
    would hold the first client's call until it ended); 0.5 s into that
    play H's playhead goes to 1 frame; 8 s in, `play_preview {seconds:
    0.5}` pauses LONG. No `started` line appears before LONG's playback line
    — before that pause, as the log is written: a following session's line
    is written by its last worker, which a loaded host can hold seconds past
    the pause, so its place in the log is not when the play stopped — and a
    `started` line for LONG's key appears within 4 s after it (the playback
    line itself awaited for 30 s);
B7  mid-pass on LONG, a property edit on LONG's clip (`set_video` opacity):
    LONG reads `stopped` within 5 s. It runs after B12 and B13, and LONG is
    then saved: an edit's autosave in place clears the edited state about
    15 s later, which is activity — B12's pass, run after B7 once, was
    stopped 15 s after the edit, with no other line to explain it;
B10 `close_project` H and H2, then LONG mid-pass, then `close_project` LONG:
    LONG's end line reads `stopped` within 5 s, and kept_frames == 0 at 5 s
    and at 8 s;
B8  BG-OFF: `set_playhead` H to 1 frame: no `graphic background:` line within
    4 s, and kept_frames <= 2 x H_LAYERS; H then plays from 0 for 3 s. The
    composed_ratio is MEASURED;
B14 `graphic_memory`'s `pass_activity` (the App Nap opt-out, G-38 (c)) reads
    False after B2's `done` line, True during B5's pass (read after its
    control, before the interruption) and False 5 s after B10's close
    stopped LONG's pass with no document left open;
Z1  `grep "Frame Job: "` over every log prints nothing.

    python3 tools/proof/background_render_proof.py [--app PATH]
    python3 tools/proof/background_render_proof.py --mutant NAME
    python3 tools/proof/background_render_proof.py --bench PACKAGE --from T --seconds S

A mutant is built in a copy of the tree under this proof's own `work/`
(`graphic_memory_proof.build_mutant`'s way, each anchor exactly once in its
file) and driven through every row; it must fail its row: `no-idle-delay`
(the idle Timer at 0.05 s) → B1, `ignores-setting` (`idle()`'s enabled guard
removed) → B8, `activity-stops-own-only` (`noteActivity`'s `stopBackground()`
removed) → B5, `background-past-budget` (`claim`'s background `full` check
removed) → B9, `close-keeps-drawing` (`stopGraphicStore`'s `stop` removed) →
B10, `draws-kept-again` (`keptAlready` always false) → B3, `ahead-unguarded`
(the following session's ahead wait removed: `claim`'s, and `insert`'s, the
one that holds a worker's frame until it fits beside the marked frames) → B12,
`ahead-evicted-first` (`trim`'s marked-last rule removed: plain least
recently used) → B12, `background-beside-play` (`start(background:)`'s
refusal while a session follows removed, and `idle()`'s while any transport
plays: either alone keeps a pass from starting beside B13's play) → B13,
`nap-outlives-stop` (`stop`'s end of a pass's App Nap opt-out removed) →
B14. Exit 0 = caught, 1 = survived, 2 = the row's control could not be
performed.

`--bench PACKAGE` runs two cells at Full (`-FrameJobPreviewQuality 0`),
BG-OFF and BG, each copying PACKAGE under `work/background-render-bench/`
(the original is never opened) and calling `set_playhead` T. BG awaits its
end line (bound 300 s) and prints it; BG-OFF waits 5 s. Each cell then plays
S s once, printing `pmset -g`'s powermode line, `sysctl -n vm.loadavg`, the
answer, the playback line, `graphic_memory` and `ps -o rss=`. Scored only on
each play answering.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row
passes, 2 when a control failed.
"""

import argparse
import math
import re
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import graphic_memory_proof as gm  # noqa: E402
import graphics_prefetch_proof as gp  # noqa: E402
import playback_prefetch_proof as pp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/background-render"
BENCH_WORK = ROOT / "tools/proof/work/background-render-bench"
APP = proof_app.binary()
SECOND = pp.SECOND
FRAME = pp.FRAME
H_LAYERS = gm.H_LAYERS
# LONG's canvas, and its clip's size, 2560 x 1440: B12's pass (a warning
# budget of physical / 8) must stay under a session's 1,024 entries, and its
# frames must be cheap enough for unguarded workers to fill the budget within
# the play. At 1920 x 1080 the pass drew 1,553 frames, a following session's
# deferred entries over them reached the ceiling before its workers passed the
# pass's end, and `ahead-unguarded` survived (kept share 0.994); at
# 3840 x 2160 (388 frames) a 4K raster was too slow for the workers to outrun
# a 10 s play, and it survived again (0.958; Release, 2026-10-21). Here about
# 876 frames, each about 0.44 of a 4K raster.
LONG_SIZE = (2560, 1440)
DELAY = ["-FrameJobBackgroundRenderDelay", "1", "-NSAppSleepDisabled", "YES"]
ROWS = ["B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "B10", "B11", "B12", "B13",
        "B14", "Z1"]
STARTED = re.compile(r"graphic background: key (\d+), from (\d+), started")
ENDED = re.compile(r"graphic background: key (\d+), (\d+) workers, from (\d+), (\d+) frames with "
                   r"graphics, (\d+) drawn, (\d+) already kept, (\d+) bytes kept, "
                   r"(done|full|stopped)")
END_FIELDS = ("key", "workers", "start", "frames", "drawn", "already", "bytes")
ANY = re.compile(r"graphic background:")

BACKGROUND = "app/Sources/BackgroundRender.swift"
PREFETCH = "app/Sources/GraphicPrefetch.swift"
MEMORY = "app/Sources/GraphicPrefetch+Memory.swift"
DOCUMENT = "app/Sources/ProjectDocument+Graphics.swift"
# name: ([(file, anchor, replacement)], the row it must fail)
MUTANTS = {
    "no-idle-delay": (
        [(BACKGROUND, "let delay = TimeInterval(BackgroundRenderSettings.load().delaySeconds)",
          "let delay: TimeInterval = 0.05")], "B1"),
    "ignores-setting": (
        [(BACKGROUND, "        guard BackgroundRenderSettings.load().enabled else { return }\n",
          "")], "B8"),
    "activity-stops-own-only": (
        [(BACKGROUND, "        GraphicPrefetch.shared.stopBackground()\n", "")], "B5"),
    "background-past-budget": (
        [(PREFETCH, "if session.background, kept.aheadBytes + heldTotal >= budgetBytes {",
          "if false {")], "B9"),
    "close-keeps-drawing": (
        [(DOCUMENT, "        GraphicPrefetch.shared.stop(recipeKey)\n", "")], "B10"),
    "draws-kept-again": (
        [(PREFETCH,
          "let keptAlready = keeping.contains(session.key) && kept.contains(session.key, key)",
          "let keptAlready = false")], "B3"),
    "ahead-unguarded": (
        [(PREFETCH,
          "\n                || session.follows && aheadOrigin?.key == session.key\n"
          "                    && heldTotal + kept.aheadBytes >= budgetBytes", ""),
         (PREFETCH,
          "        while session.follows, aheadOrigin?.key == session.key, !session.stopped,\n"
          "            !roomAhead(for: slots) { condition.wait() }\n", "")], "B12"),
    "ahead-evicted-first": (
        [(MEMORY, ", ahead[name] == nil else { continue }", " else { continue }")], "B12"),
    "background-beside-play": (
        [(PREFETCH, "\n                || sessions.values.contains { $0.follows })", ")"),
         (BACKGROUND, "if playing || current?", "if current?")], "B13"),
    "nap-outlives-stop": (
        [(PREFETCH, "        if session.background { endPassActivity() }\n", "")], "B14"),
}

rows = {}
controls = {}


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'ok' if good else 'FAIL'} — {detail}", flush=True)


def control(row, good, detail):
    """A row's control (the rule above): recorded, and printed when it fails."""
    controls[row] = bool(good)
    if not good:
        print(f"  {row} CONTROL could not be performed — {detail}", flush=True)
    return bool(good)


# ---- the log ----------------------------------------------------------------

def text_since(log, offset, end=None):
    """The log's bytes from `offset` (to `end` when given), as text."""
    try:
        with open(log, "rb") as handle:
            handle.seek(offset)
            data = handle.read() if end is None else handle.read(max(0, end - offset))
    except OSError:
        return ""
    return data.decode(errors="replace")


def events(log, offset, end=None):
    """Every background line appended after `offset` (and before `end`), in
    log order, as dicts with `kind` ("started" or the end), `pos` and their
    fields."""
    text = text_since(log, offset, end)
    found = []
    for m in STARTED.finditer(text):
        found.append({"kind": "started", "pos": m.start(), "key": int(m.group(1)),
                      "start": int(m.group(2))})
    for m in ENDED.finditer(text):
        one = dict(zip(END_FIELDS, map(int, m.groups()[:7])))
        one.update({"kind": "end", "pos": m.start(), "end": m.group(8)})
        found.append(one)
    return sorted(found, key=lambda e: e["pos"])


def await_event(log, offset, wanted, seconds):
    """The first background line after `offset` that `wanted` accepts,
    waited for up to `seconds`; None when none came."""
    deadline = time.monotonic() + seconds
    while True:
        found = [e for e in events(log, offset) if wanted(e)]
        if found or time.monotonic() >= deadline:
            return found[0] if found else None
        time.sleep(0.1)


def playback_line(log, offset, key, start, seconds=10):
    """The first playback line of `key` from `start` after `offset`, with its
    position: (fields, pos), or (None, None)."""
    deadline = time.monotonic() + seconds
    while True:
        text = text_since(log, offset)
        for m in gm.KEPT.finditer(text):
            line = dict(zip(gm.KEPT_FIELDS, map(int, m.groups())))
            if line["key"] == key and line["start"] == start:
                return line, m.start()
        if time.monotonic() >= deadline:
            return None, None
        time.sleep(0.25)


def ended(key, *ends, after=-1):
    """An end line of `key` (reading one of `ends` when given) after
    position `after` — the pass's own `started` line, so that an earlier
    pass's end, written when that pass's last worker exits, is not taken
    for it."""
    return lambda e: (e["kind"] == "end" and e["key"] == key and e["pos"] > after
                      and (not ends or e["end"] in ends))


def started(key=None, start=None, after=-1):
    return lambda e: (e["kind"] == "started" and (key is None or e["key"] == key)
                      and (start is None or e["start"] == start) and e["pos"] > after)


# ---- the steps --------------------------------------------------------------

def set_playhead(client, package, t):
    got = gp.attempt(client, "set_playhead", {"project": str(package), "t": t})
    return got["ok"], got.get("error")


def empty(client, then="normal"):
    """The kept frames emptied: critical, then `then`."""
    gm.memory(client, pressure="critical")
    return gm.memory(client, pressure=then)


def settle(log, offset, seconds=120):
    """Waits until every pass started after `offset` has its end line and
    no line has come for 2.5 s (the 1 s delay and a margin); bounded."""
    deadline = time.monotonic() + seconds
    last, quiet_since = None, time.monotonic()
    while time.monotonic() < deadline:
        found = events(log, offset)
        if found != last:
            last, quiet_since = found, time.monotonic()
        starts = [e["key"] for e in found if e["kind"] == "started"]
        ends = [e["key"] for e in found if e["kind"] == "end"]
        open_passes = len(starts) > len(ends)
        if not open_passes and time.monotonic() - quiet_since >= 2.5:
            return True
        time.sleep(0.2)
    return False


def mid_pass(client, log, package, t, row, key=None):
    """The kept frames emptied, `set_playhead` `package` to `t`, its pass's
    `started` line (of `key` when known) awaited and 1 s given; the row's
    control is that no end line has come. Performed again once when the
    control fails (activity this proof did not make — a scroll over a
    window, a document's autosave — stops a pass too). (the started event or
    None, the offset after it)."""
    for attempt in (1, 2):
        empty(client)
        time.sleep(0.5)
        offset = gp.log_size(log)
        ok, error = set_playhead(client, package, t)
        first = await_event(log, offset, started(key), 4) if ok else None
        if first:
            time.sleep(1.0)
        stray = [e for e in events(log, offset)
                 if first and e["kind"] == "end" and e["key"] == first["key"]
                 and e["pos"] > first["pos"]]
        if control(row, ok and first is not None and not stray,
                   f"attempt {attempt}: set_playhead {ok or error}; started {first}; end lines "
                   f"since {stray}"):
            break
    return first, gp.log_size(log)


def long_project(client, package, physical):
    """LONG: one `heavy` clip on a 3840 x 2160 canvas, lengthened by
    `trim_end`. (ok, detail)."""
    made, detail = gp.graphic_project(client, package, [("heavy", gp.HEAVY_JS)], [], tail=False)
    if not made:
        return False, detail
    sized = gp.attempt(client, "set_canvas", {"project": str(package), "width": LONG_SIZE[0],
                                              "height": LONG_SIZE[1]})
    tracks = [t.get("id") for t in gp.project_of(client, package).get("tracks", [])]
    ok, why = gp.land(client, package, "heavy", tracks[0] if tracks else None,
                      {"props": {"title": "Long", "hue": 120}, "width": LONG_SIZE[0],
                       "height": LONG_SIZE[1]})
    canvas = gp.project_of(client, package).get("canvas", {})
    width, height = canvas.get("width"), canvas.get("height")
    clip = pp.first_clip(client, package, "heavy")
    if not (sized["ok"] and ok and isinstance(width, int) and isinstance(height, int) and clip
            and physical):
        return False, (f"{detail}; set_canvas {sized['ok'] or sized.get('error')}; clip {ok} "
                       f"{why}; canvas {canvas}; clip {clip}; physical {physical}")
    frames = math.ceil(1.5 * physical / 8 / (width * height * 4))
    seconds = max(60, math.ceil(frames / 30))
    trimmed = gp.attempt(client, "trim_end", {"project": str(package), "clip": clip,
                                              "to": seconds * SECOND})
    saved = gp.attempt(client, "save_project", {"project": str(package)})
    return (trimmed["ok"] and saved["ok"],
            f"{detail}; canvas {width} x {height}; {frames} frames hold 1.5 x physical / 8; "
            f"{seconds} s; trim_end {trimmed['ok'] or trimmed.get('error')}")


def ratio_share(line):
    if not line:
        return False, None
    taken = line["kept"] + line["hits"] + line["missed"] + line["mismatched"]
    share = line["kept"] / taken if taken else 0.0
    return line["kept"] > 30 and line["kept"] >= 0.9 * taken, round(share, 3)


# ---- the rows ---------------------------------------------------------------

def run_serial(app, heavy, heavy2, long, plays):
    serial = pp.Instance(app, WORK / "serial.log", off=True)
    try:
        client = serial.start()
        made_h, detail_h = gp.fixture(client, heavy) if client else (False, "SERIAL did not launch")
        if made_h:
            shutil.copytree(heavy, heavy2, symlinks=True)
        physical = gm.field(gm.memory(client), "physical_bytes") if client else None
        made_l, detail_l = long_project(client, long, physical) if client else (False, "")
        print(f"  fixture H: {made_h} {detail_h}\n  fixture H2: copy of H\n"
              f"  fixture LONG: {made_l} {detail_l}", flush=True)
        opened = gp.opened(client, heavy2)
        plays["serial-H2-digests"] = [pp.play(client, heavy2, start, 3, digests=True)
                                      for start in (0, FRAME, 2 * FRAME)]
        print(f"  SERIAL H2 opened {opened}", flush=True)
    finally:
        serial.stop()
    return made_h and made_l


def run_bg_off(app, heavy, plays):
    log = WORK / "bg-off.log"
    instance = pp.Instance(app, log, off=False, keep_off=False, extra=DELAY)
    try:
        client = instance.start()
        opened = gp.opened(client, heavy)
        time.sleep(2)
        offset = gp.log_size(log)
        ok, error = set_playhead(client, heavy, FRAME)
        time.sleep(4)
        stray = ANY.findall(text_since(log, offset))
        state = gm.memory(client)
        frames = gm.field(state, "kept_frames")
        plays["bg-off-H"] = pp.play(client, heavy, 0, 3)
        check("B8", opened and ok and not stray and frames is not None
              and frames <= 2 * H_LAYERS,
              f"open {opened}; set_playhead {ok or error}; background lines within 4 s "
              f"{len(stray)}; {gm.short(state)} (at most {2 * H_LAYERS})")
        print(f"B8 MEASURED — BG-OFF H from 0 for 3 s: {pp.brief(plays['bg-off-H'])}",
              flush=True)
    finally:
        instance.stop()


def run_bg(app, heavy, heavy2, long, plays):
    log = WORK / "bg.log"
    instance = pp.Instance(app, log, off=False, keep_off=False, background=True, extra=DELAY)
    keys = {}
    nap = {}
    try:
        client = instance.start()
        start = gp.log_size(log)
        opened = gp.opened(client, heavy)
        settled = settle(log, start)
        empty(client)
        print(f"  BG opened H {opened}, settled {settled}", flush=True)

        # B1, B2
        before = gm.memory(client)
        offset = gp.log_size(log)
        ok, error = set_playhead(client, heavy, FRAME)
        returned = time.monotonic()
        time.sleep(max(0, returned + 0.5 - time.monotonic()))
        early = ANY.findall(text_since(log, offset))
        check("B1", ok and not early,
              f"set_playhead {ok or error}; background lines by 0.5 s {len(early)}")
        first = await_event(log, offset, started(start=FRAME),
                            max(0, returned + 4 - time.monotonic()))
        if first:
            keys["H"] = first["key"]
        end = await_event(log, offset, ended(first["key"], after=first["pos"]), 30) \
            if first else None
        after = gm.memory(client)
        nap["after B2's done"] = gm.field(after, "pass_activity")
        check("B2", first is not None and end is not None and end["end"] == "done"
              and end["drawn"] > 0
              and (gm.field(after, "kept_frames") or 0) > (gm.field(before, "kept_frames") or 0),
              f"started {first}; end {end}; before {gm.short(before)}; after {gm.short(after)}")

        # B3
        offset = gp.log_size(log)
        ok, error = set_playhead(client, heavy, FRAME)
        end = await_event(log, offset, ended(keys.get("H"), "done", "full"), 30) \
            if keys.get("H") else None
        check("B3", ok and end is not None and end["drawn"] == 0 and end["already"] > 0,
              f"set_playhead 1 frame again {ok or error}; end {end}")

        # B4
        before = gm.memory(client)
        offset = gp.log_size(log)
        plays["bg-H"] = pp.play(client, heavy, 0, 3)
        line = gm.await_kept(log, offset, 0)
        after = gm.memory(client)
        check("B4", "error" not in plays["bg-H"] and line is not None and line["kept"] > 10
              and gm.rose(before, after),
              f"H {pp.brief(plays['bg-H'])}; line {line}; before {gm.short(before)}; after "
              f"{gm.short(after)}")
        print(f"B4 MEASURED — BG H from 0 for 3 s: {pp.brief(plays['bg-H'])}", flush=True)

        # B11
        start = gp.log_size(log)
        opened2 = gp.opened(client, heavy2)
        settle(log, start)
        offset = gp.log_size(log)
        ok, error = set_playhead(client, heavy2, 0)
        first = await_event(log, offset, started(start=0), 5)
        if first:
            keys["H2"] = first["key"]
        done = await_event(log, offset, ended(first["key"], after=first["pos"]), 60) \
            if first else None
        plays["bg-H2-digests"] = [pp.play(client, heavy2, at, 3, digests=True)
                                  for at in (0, FRAME, 2 * FRAME)]
        good, detail = pp.digests_agree(plays["serial-H2-digests"], plays["bg-H2-digests"])
        check("B11", opened2 and ok and done is not None and done["end"] == "done" and good,
              f"H2 open {opened2}; set_playhead 0 {ok or error}; pass {done}; SERIAL against "
              f"BG: {detail}")

        # B9
        critical = gm.memory(client, pressure="critical")
        time.sleep(0.5)
        offset = gp.log_size(log)
        ok, error = set_playhead(client, heavy2, FRAME)
        said = time.monotonic()
        first = await_event(log, offset, started(keys.get("H2"), FRAME), 5)
        end = await_event(log, offset, ended(first["key"], after=first["pos"]),
                          max(0, said + 5 - time.monotonic())) if first else None
        normal = gm.memory(client, pressure="normal")
        check("B9", ok and end is not None and end["end"] == "full" and end["drawn"] == 0,
              f"critical {gm.short(critical)}; set_playhead {ok or error}; started {first}; "
              f"end {end}; normal {gm.short(normal)}")

        # LONG opened, and its open's pass awaited (the open is done moving
        # it); that pass is stopped by the first mid-pass.
        start = gp.log_size(log)
        opened_long = gp.opened(client, long)
        long_clip = pp.first_clip(client, long, "heavy")
        open_pass = await_event(log, start, started(), 15)
        print(f"  BG opened LONG {opened_long}, clip {long_clip}, its pass {open_pass}",
              flush=True)

        # B5
        first, offset = mid_pass(client, log, long, 0, "B5")
        if first:
            keys["LONG"] = first["key"]
        nap["during B5's pass"] = gm.field(gm.memory(client), "pass_activity")
        ok, error = set_playhead(client, heavy, FRAME)
        end = await_event(log, offset, ended(keys.get("LONG")), 5)
        check("B5", controls["B5"] and ok and end is not None and end["end"] == "stopped",
              f"H set_playhead {ok or error}; LONG's end {end}")

        # B6
        first, offset = mid_pass(client, log, long, 0, "B6", keys.get("LONG"))
        ok, error = set_playhead(client, long, 10 * FRAME)
        end = await_event(log, offset, ended(keys.get("LONG")), 5)
        again = await_event(log, offset, started(keys.get("LONG"), 10 * FRAME,
                                                 end["pos"] if end else -1), 5)
        check("B6", controls["B6"] and ok and end is not None and end["end"] == "stopped"
              and again is not None,
              f"LONG set_playhead frame 10 {ok or error}; end {end}; then {again}")

        # B12, performed again once when its control fails (`mid_pass`'s
        # reason)
        for attempt in (1, 2):
            empty(client, then="warning")
            time.sleep(0.5)
            offset = gp.log_size(log)
            ok, error = set_playhead(client, long, FRAME)
            first = await_event(log, offset, started(keys.get("LONG"), FRAME), 5)
            end = await_event(log, offset, ended(keys.get("LONG"), after=first["pos"]), 300) \
                if first else None
            if control("B12", ok and end is not None and end["end"] == "full",
                       f"attempt {attempt}: set_playhead {ok or error}; started {first}; "
                       f"end {end}"):
                break
        drawn = end["drawn"] if end else 0
        seconds = round(0.8 * drawn / 30, 2)
        line = None
        reset = None
        if controls["B12"] and seconds > 0:
            reset = gm.memory(client)
            offset = gp.log_size(log)
            plays["bg-LONG"] = pp.play(client, long, FRAME, seconds)
            line = gm.await_kept(log, offset, FRAME)
        warned = gm.memory(client)
        gm.memory(client, pressure="normal")
        good, share = ratio_share(line)
        evicted = gm.field(warned, "ahead_evicted")
        check("B12", controls["B12"] and good and evicted == 0,
              f"pass {end}; before the play {ahead(reset)}; LONG from {FRAME} for {seconds} s "
              f"{pp.brief(plays.get('bg-LONG'))}; line {line}; kept share {share}; after "
              f"{ahead(warned)} (ahead_evicted must be 0); {gm.short(warned)}")

        # B13
        time.sleep(2)
        offset = gp.log_size(log)
        chose = gp.attempt(client, "set_selection", {"project": str(long), "clips": [long_clip]})
        menu = gp.attempt(client, "perform_menu_item",
                          {"project": str(long), "path": ["Clip", "Motion", "Preview"]})
        time.sleep(0.5)
        ok, error = set_playhead(client, heavy, FRAME)
        time.sleep(7.5)
        before_pause = time.monotonic()
        at_pause = gp.log_size(log)
        paused = gp.attempt(client, "play_preview", {"project": str(long), "seconds": 0.5})
        reached = paused["reply"].get("from") if paused["ok"] and isinstance(
            paused["reply"], dict) else None
        control("B13", chose["ok"] and menu["ok"] and ok and reached is not None
                and reached >= SECOND,
                f"selection {chose['ok'] or chose.get('error')}; menu {menu['ok'] or menu.get('error')}; "
                f"H set_playhead {ok or error}; the pause found LONG at {reached}")
        after = await_event(log, at_pause, started(keys.get("LONG")),
                            max(0, before_pause + 4 - time.monotonic()))
        line, _ = playback_line(log, offset, keys.get("LONG"), 0, seconds=30)
        before_line = [e for e in events(log, offset, at_pause) if e["kind"] == "started"]
        check("B13", controls["B13"] and line is not None and not before_line
              and after is not None,
              f"LONG's playback line {line}; started before it {before_line}; LONG's started "
              f"after it {after}")

        # B7
        first, offset = mid_pass(client, log, long, 0, "B7", keys.get("LONG"))
        edit = gp.attempt(client, "set_video", {"project": str(long), "clips": [long_clip],
                                                "patch": {"opacity": 0.9}})
        end = await_event(log, offset, ended(keys.get("LONG")), 5)
        check("B7", controls["B7"] and edit["ok"] and end is not None and end["end"] == "stopped",
              f"set_video opacity 0.9 {edit['ok'] or edit.get('error')}; end {end}")
        saved = gp.attempt(client, "save_project", {"project": str(long)})
        print(f"  LONG saved {saved['ok'] or saved.get('error')}", flush=True)

        # B10
        closed = [gp.attempt(client, "close_project", {"project": str(p), "discard": True})["ok"]
                  for p in (heavy, heavy2)]
        first, offset = mid_pass(client, log, long, 0, "B10", keys.get("LONG"))
        shut = gp.attempt(client, "close_project", {"project": str(long), "discard": True})
        shut_at = time.monotonic()
        end = await_event(log, offset, ended(keys.get("LONG")), 5)
        time.sleep(max(0, shut_at + 5 - time.monotonic()))
        at5 = gm.memory(client)
        nap["5 s after B10's close"] = gm.field(at5, "pass_activity")
        time.sleep(max(0, shut_at + 8 - time.monotonic()))
        at8 = gm.memory(client)
        check("B10", controls["B10"] and all(closed) and shut["ok"] and end is not None
              and end["end"] == "stopped" and gm.field(at5, "kept_frames") == 0
              and gm.field(at8, "kept_frames") == 0,
              f"H and H2 closed {closed}; LONG closed {shut['ok'] or shut.get('error')}; end "
              f"{end}; at 5 s {gm.short(at5)}; at 8 s {gm.short(at8)}")

        # B14
        check("B14", nap == {"after B2's done": False, "during B5's pass": True,
                             "5 s after B10's close": False},
              f"pass_activity {nap} (must read False, True, False)")
    finally:
        instance.stop()


def ahead(answer):
    """`graphic_memory`'s G-38 fields, short."""
    return {k: gm.field(answer, k) for k in ("ahead_bytes", "ahead_evicted", "pass_activity")}


def run_all(app):
    heavy, heavy2, long = WORK / "H.framejob", WORK / "H2.framejob", WORK / "LONG.framejob"
    plays = {}
    made = run_serial(app, heavy, heavy2, long, plays)
    if not made:
        print("  the fixtures were not all made", flush=True)
    run_bg(app, heavy, heavy2, long, plays)
    run_bg_off(app, heavy, plays)
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
    print(f"background render — the {name} MUTANT ({row} must FAIL)", flush=True)
    binary, why = build_mutant(name)
    if binary is None:
        print(f"mutant {name}: the control could not be performed — the copy was not built: "
              f"{why}")
        return 2
    run_all(binary)
    if controls.get(row) is False:
        print(f"mutant {name}: the control could not be performed — {row}'s control failed")
        return 2
    caught = not rows.get(row)
    print(f"the mutant is CAUGHT: {row} FAILED" if caught else "the mutant was NOT caught")
    return 0 if caught else 1


# ---- the bench --------------------------------------------------------------

def run_bench(app, source, start, seconds):
    print(f"background render — bench of {source}, from {start} for {seconds} s, BG-OFF and BG "
          f"at Full", flush=True)
    if not source.is_dir():
        print(f"bench FAIL — {source} is not a package")
        return 1
    tree_copy.remove_tree(BENCH_WORK)
    BENCH_WORK.mkdir(parents=True)
    answered = {}
    for cell, background in (("bg-off", False), ("bg", True)):
        package = BENCH_WORK / cell / source.name
        shutil.copytree(source, package, symlinks=True)
        log = BENCH_WORK / f"bench-{cell}.log"
        instance = pp.Instance(app, log, off=False, keep_off=False, background=background,
                               extra=["-FrameJobPreviewQuality", "0"] + DELAY)
        try:
            client = instance.start(timeout=gp.BENCH_BOUND)
            ok_open = gp.opened(client, package)
            offset = gp.log_size(log)
            ok, error = set_playhead(client, package, start)
            print(f"  {cell}: open {ok_open}; set_playhead {ok or error}", flush=True)
            if background:
                first = await_event(log, offset, started(), 10)
                end = await_event(log, offset, lambda e: e["kind"] == "end" and first
                                  and e["key"] == first["key"] and e["pos"] > first["pos"],
                                  300) if first else None
                print(f"  {cell}: pass {first} → {end}", flush=True)
            else:
                time.sleep(5)
            print(f"  {cell}: {pp.powermode()}; load average before {gp.loadavg()}", flush=True)
            offset = gp.log_size(log)
            answer = pp.play(client, package, start, seconds)
            line = gm.await_kept(log, offset, None)
            state = gm.memory(client)
            size = pp.rss(instance.child.pid) if instance.child else "?"
            answered[cell] = ok_open and isinstance(answer, dict) and "error" not in answer
            print(f"  {cell}: {pp.brief(answer)}\n    playback line {line}\n"
                  f"    graphic_memory {gm.short(state)}\n    rss {size} KiB after", flush=True)
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
    print("#127 G6 phase 4 — background render: graphic frames drawn ahead while paused and "
          "idle, against the built app (proof)", flush=True)
    run_all(args.app)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    failed = [row for row, good in controls.items() if not good]
    if failed:
        print(f"the control could not be performed for {failed}")
        return 2
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
