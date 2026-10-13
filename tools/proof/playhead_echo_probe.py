#!/usr/bin/env python3
"""The playhead echo — `Playback`'s own restore seeks reported as playhead
moves, measured (2026-09-26).

What happened. Dragging a clip flashed the playhead to 0 and yanked the
timeline's scroll: every structural edit rebuilds the player item, and
`finishRebuild` swaps the item (which starts at 0) and seeks back to where
the transport was. The periodic time observer reported BOTH jumps through
`onTimeChanged`, so the document heard 0 and then its own playhead again, the
timeline revealed each one, and the entry rule for actions (spec §11 CI-1)
saw the playhead leave a span and come back. The paused refresh's one-tick
round trip was reported the same way. The fix: `onTimeChanged` carries a
seek someone ASKED for and time while PLAYING, and a restore is silent unless
it comes to rest somewhere other than the tick last reported.

Why a probe and not an MCP script. No tool reads what the editor's own player
reports. This is `media_less_playback_probe.py`'s instrument:
`playhead_echo_probe.swift` compiled as `main.swift` against the whole of
`app/Sources` with `swift_build.py`'s line, `--sources PATH` to
build the same probe over another tree, a build failure or a missing ffmpeg
scored as a FAILURE on every row. Every subprocess runs under
`graphics_spike/bounded.py` (Rule H). The instrument wraps the editor's
`playback.onTimeChanged` to log every tick it carries, then forwards it.

Fixture, rewritten every run under `work/playhead-echo/`: `card.mov` (an 8 s
test card) and `echo.framejob`, 432 × 280 at 30 fps, clip 3 at 0–3 s and
clip 4 at 4–6 s on one track, both from the card's 0.

Rows (B = predicted to fail before the fix; M = no prediction, both trees'
result recorded; every other row is a CONTROL). No row reads a picture, so
every row is scored whatever the console state.

Issue batch B53 (#204, #209) added `twice·1` [B] and `twice·2`: two asked
seeks in ONE run-loop turn, `setPlayhead(2 s)` then `setPlayhead(0.5 s)`
from 1 s, with no spin between (`scope_playhead_probe.py`'s "two calls in
ONE turn"). `twice·1`: at least one report and every one 0.5 s — before the
fix a late observer callback for the superseded 2 s seek was heard while
paused. `twice·2` (a CONTROL): the document, the timeline and the player
all rest at 0.5 s. `pause·1` (a CONTROL): after play·1's mid-play pause the
document, the timeline and the player agree and the last report is the
player's tick — the paused guard must not drop the pause's own callback.

Needs `ffmpeg`, `swiftc`, `xcrun metal` and
`core/target/release/libframejob_core.a`. No port. Run from anywhere:

    python3 tools/proof/playhead_echo_probe.py [--sources PATH]
"""

import argparse
import hashlib
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = os.path.join(HERE, "work", "playhead-echo")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "playhead_echo_probe.swift")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")

TICKS = 600_000
WIDTH, HEIGHT = 432, 280

passed = 0
failed = 0


def check(name, ok, detail="", show=False):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}" + (f"\n       {detail}" if show and detail else ""))
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


# ---------------------------------------------------------------------------
# The fixture.


def make_fixture():
    """(package, None) or (None, reason)."""
    os.makedirs(WORK, exist_ok=True)
    if shutil.which("ffmpeg") is None:
        return None, "ffmpeg is not on PATH"
    movie = os.path.join(WORK, "card.mov")
    made = bounded.run(
        ["ffmpeg", "-v", "error", "-y", "-t", "8",
         "-f", "lavfi", "-i", f"testsrc2=size={WIDTH}x{HEIGHT}:rate=30",
         "-c:v", "h264", "-pix_fmt", "yuv420p", movie], 120)
    if made["rc"] != 0 or not os.path.exists(movie):
        return None, f"ffmpeg failed: {made['stderr'].strip()[:300]}"
    package = os.path.join(WORK, "echo.framejob")
    shutil.rmtree(package, ignore_errors=True)
    os.makedirs(package)

    def clip(cid, start, duration):
        return {"id": cid, "track": 1, "start": start, "duration": duration,
                "source": {"kind": "media", "media": 2, "in": 0}, "video": {}, "audio": {}}

    project = {
        "version": 10,
        "canvas": {"width": WIDTH, "height": HEIGHT, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": True},
        "media": [{"id": 2, "path": movie, "kind": "video", "duration": 8 * TICKS,
                   "width": WIDTH, "height": HEIGHT, "fps": [30, 1],
                   "has_video": True, "has_audio": False}],
        "tracks": [{"id": 1, "name": "Track 1"}],
        "clips": [clip(3, 0, 3 * TICKS), clip(4, 4 * TICKS, 2 * TICKS)],
        "markers": [], "next_id": 5, "nests": [],
    }
    with open(os.path.join(package, "project.json"), "w") as f:
        json.dump(project, f, indent=1)
    return package, None


# ---------------------------------------------------------------------------
# The probe.


def build_shader(probe):
    lib = os.path.join(probe, "default.metallib")
    air = os.path.join(probe, "Compositor.air")
    if os.path.exists(lib) and os.path.getmtime(SHADER) < os.path.getmtime(lib):
        return lib, None
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", SHADER, "-o", air], 300)
    if step["rc"] != 0:
        return None, "xcrun metal failed: " + step["stderr"].strip()[:300]
    step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib], 300)
    if step["rc"] != 0 or not os.path.exists(lib):
        return None, "xcrun metallib failed: " + step["stderr"].strip()[:300]
    return lib, None


def build_probe(sources):
    """The probe over `sources`, in a directory of its own per source tree.
    (binary, None) or (None, reason)."""
    tag = "probe" if os.path.samefile(sources, SOURCES) else (
        "probe-" + hashlib.sha256(os.path.abspath(sources).encode()).hexdigest()[:10])
    probe = os.path.join(WORK, tag)
    os.makedirs(probe, exist_ok=True)
    binary = os.path.join(probe, "playhead_echo_probe")
    entry = os.path.join(probe, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    fonts = os.path.join(probe, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(probe, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    shader, why = build_shader(probe)
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, name) for name in os.listdir(sources)
                   if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=swift + [entry], output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc exited {error.rc if error.rc is not None else 'before running'} "
                      f"(expired {error.expired}): "
                      + " | ".join(error.diagnostics[:6] or ["(no output)"]))
    if built.reused:
        print(f"probe: {binary} (up to date)")
    else:
        print(f"probe: {binary} (built in {built.seconds:.1f} s)")
    return binary, None


def run_probe(binary, package):
    ran = bounded.run([binary, package], 300, cwd=os.path.dirname(binary))
    if ran["expired"]:
        return None, "the probe ran past 300 s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-300:]}"


def console_locked():
    """Host state is a proof input — named, though no row here needs it."""
    out = bounded.run(["ioreg", "-n", "Root", "-d1", "-a"], 60)["stdout"]
    marker = out.find("<key>IOConsoleLocked</key>")
    return marker >= 0 and out[marker:marker + 60].find("<true/>") >= 0


# ---------------------------------------------------------------------------
# The rows: (id, kind, name, predicate over the answer, detail). kind is "B"
# (predicted to fail before the fix), "M" (no prediction) or "" (CONTROL).


def all_at(log, t):
    return all(x == t for x in log)


def rests(s, t):
    return s["playhead"] == t and s["playerTicks"] == t


def rows():
    sec = TICKS
    yield ("refresh·1", "", "at 1 s, opacity 0.5 leaves the built plan unchanged",
           lambda a: a["refresh"]["samePlan"] is True, lambda a: a["refresh"]["samePlan"])
    yield ("refresh·2", "B", "the refresh's round trip: every report is 1 s",
           lambda a: all_at(a["refresh"]["log"], sec), lambda a: a["refresh"]["log"])
    yield ("refresh·3", "", "the player tick == the playhead == 1 s, rate 0",
           lambda a: rests(a["refresh"], sec) and a["refresh"]["rate"] == 0,
           lambda a: a["refresh"])
    yield ("step·1", "", "right arrow at 1 s: a report of 1 s + 1 frame; the document and "
           "the timeline both there",
           lambda a: sec + a["frame"] in a["step"]["log"]
           and a["step"]["playhead"] == sec + a["frame"]
           and a["step"]["timeline"] == sec + a["frame"], lambda a: a["step"])
    yield ("seek·1", "", "setPlayhead(2 s): a report of 2 s; the document and the player "
           "at 2 s", lambda a: 2 * sec in a["seek"]["log"] and rests(a["seek"], 2 * sec),
           lambda a: a["seek"])
    yield ("twice·1", "B", "setPlayhead(2 s) then setPlayhead(0.5 s) in one turn: at least one "
           "report, every one 0.5 s",
           lambda a: len(a["twice"]["log"]) >= 1 and all_at(a["twice"]["log"], sec // 2),
           lambda a: a["twice"]["log"])
    yield ("twice·2", "", "… the document, the timeline and the player all rest at 0.5 s",
           lambda a: rests(a["twice"], sec // 2) and a["twice"]["timeline"] == sec // 2,
           lambda a: a["twice"])
    yield ("rebuild·1", "", "at 1 s, the live drag changed the built plan",
           lambda a: a["rebuild"]["changedPlan"] is True, lambda a: a["rebuild"]["changedPlan"])
    yield ("rebuild·2", "B", "the live drag's rebuilds: every report is 1 s",
           lambda a: all_at(a["rebuild"]["log"], sec), lambda a: a["rebuild"]["log"])
    yield ("rebuild·3", "", "the document == the player == 1 s, rate 0",
           lambda a: rests(a["rebuild"], sec) and a["rebuild"]["rate"] == 0,
           lambda a: a["rebuild"])
    yield ("rebuild·4", "B", "a non-live move of clip 3 by one frame: every report is 1 s",
           lambda a: all_at(a["rebuild4"]["log"], sec), lambda a: a["rebuild4"]["log"])
    yield ("action·1", "B", "a deselected span holding the 1 s playhead (not 0): a structural "
           "edit leaves selectedAction nil",
           lambda a: a["action"]["actionID"] is not None
           and a["action"]["underPlayhead"] == a["action"]["actionID"]
           and a["action"]["selectedAction"] is None,
           lambda a: {k: a["action"][k] for k in
                      ("actionID", "underPlayhead", "selectedAction", "log", "playhead")})
    yield ("reveal·1", "", "zoomed in and scrolled to 4 s: the 1 s playhead is outside the band",
           lambda a: a["reveal"]["outside"] is True, lambda a: a["reveal"]["outside"])
    yield ("reveal·2", "B", "a live drag leaves the clip view's minX unchanged after every "
           "tick and after the settle",
           lambda a: len(a["reveal"]["minX"]) == 6
           and all(x == a["reveal"]["minX0"] for x in a["reveal"]["minX"]),
           lambda a: {"minX0": a["reveal"]["minX0"], "minX": a["reveal"]["minX"],
                      "log": a["reveal"]["dragLog"]})
    yield ("reveal·3", "", "a right arrow then brings the playhead inside the band",
           lambda a: a["reveal"]["arrowInside"] is True
           and a["reveal"]["arrow"]["playhead"] == sec + a["frame"],
           lambda a: {"arrow": a["reveal"]["arrow"], "arrowMinX": a["reveal"]["arrowMinX"]})
    yield ("play·1", "", "1.2 s from 0.5 s: ≥ 10 reports, non-decreasing, advanced ≥ 0.4 s, "
           "the document == the last",
           lambda a: len(a["play"]["log"]) >= 10
           and all(y >= x for x, y in zip(a["play"]["log"], a["play"]["log"][1:]))
           and a["play"]["playhead"] - a["play"]["from"] >= 0.4 * sec
           and a["play"]["playhead"] == a["play"]["log"][-1],
           lambda a: {"count": len(a["play"]["log"]), "first": a["play"]["log"][:3],
                      "last": a["play"]["log"][-3:], "playhead": a["play"]["playhead"]})

    yield ("pause·1", "", "paused mid-play after play·1: rate 0; the document, the timeline "
           "and the player tick agree; the last report is the player tick",
           lambda a: a["pause"]["rate"] == 0 and len(a["pause"]["log"]) > 0
           and rests(a["pause"], a["pause"]["playerTicks"])
           and a["pause"]["timeline"] == a["pause"]["playerTicks"]
           and a["pause"]["log"][-1] == a["pause"]["playerTicks"],
           lambda a: {"last": a["pause"]["log"][-3:], "playhead": a["pause"]["playhead"],
                      "timeline": a["pause"]["timeline"],
                      "playerTicks": a["pause"]["playerTicks"], "rate": a["pause"]["rate"]})

    def play2(a):
        p = a["play2"]
        before, after = p["log"][:p["earlier"]], p["log"][p["earlier"]:]
        return (len(before) > 0 and len(after) > 0 and min(after) >= before[-1]
                and p["rate"] != 0 and p["playhead"] - before[-1] >= 0.3 * sec)

    yield ("play·2", "M", "a structural edit 0.6 s into play: no later report below the last "
           "earlier one; still playing, advanced ≥ 0.3 s after it", play2,
           lambda a: {"before": a["play2"]["log"][max(0, a["play2"]["earlier"] - 3):
                                                  a["play2"]["earlier"]],
                      "after": a["play2"]["log"][a["play2"]["earlier"]:][:8],
                      "playhead": a["play2"]["playhead"], "rate": a["play2"]["rate"]})
    yield ("loop·1", "", "in 0.5 s, out 2.0 s, loop on, 1.2 s from 1.5 s: a report decreases "
           "into [0.5 s, 1.5 s); still playing",
           lambda a: a["loop"]["rate"] != 0 and any(
               y < x and 0.5 * sec <= y < 1.5 * sec
               for x, y in zip(a["loop"]["log"], a["loop"]["log"][1:])),
           lambda a: {"range": a["loop"]["range"], "playhead": a["loop"]["playhead"],
                      "rate": a["loop"]["rate"]})
    yield ("end·1", "", "parked at the end, an opacity edit: reports non-empty and all "
           "duration − 1; the document and the player both there",
           lambda a: len(a["end1"]["log"]) > 0
           and all_at(a["end1"]["log"], a["end1"]["duration"] - 1)
           and rests(a["end1"], a["end1"]["duration"] - 1), lambda a: a["end1"])
    yield ("end·2", "", "12 frames from the end, played 1.5 s: rate 0, the document == the "
           "player tick",
           lambda a: a["end2"]["rate"] == 0
           and a["end2"]["playhead"] == a["end2"]["playerTicks"], lambda a: a["end2"])
    yield ("short·1", "", "playhead 5 s, clip 4 deleted: after the settle the document == the "
           "player tick", lambda a: a["short"]["playhead"] == a["short"]["playerTicks"],
           lambda a: a["short"])
    yield ("short·2", "M", "every report equals the document's final playhead",
           lambda a: all_at(a["short"]["log"], a["short"]["playhead"]), lambda a: a["short"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default=SOURCES,
                        help="an app/Sources tree to build the probe over (default: this tree's)")
    sources = os.path.abspath(parser.parse_args().sources)
    locked = console_locked()
    print(f"console: {'LOCKED' if locked else 'unlocked'} (no row reads a picture; "
          "every row is scored either way)")
    print(f"sources: {sources}")
    package, why = make_fixture()
    binary, answer = None, None
    if package is not None:
        binary, why = build_probe(sources)
    if binary is not None:
        answer, why = run_probe(binary, package)
    print()
    for rid, kind, name, predicate, detail in rows():
        label = f"{rid}{' [' + kind + ']' if kind else ''} {name}"
        if answer is None:
            check(label, False, why)
            continue
        try:
            ok, shown = predicate(answer), json.dumps(detail(answer))
        except (KeyError, TypeError, IndexError, ValueError) as error:
            ok, shown = False, f"{type(error).__name__}: {error}"
        shown_always = kind in ("B", "M") or rid.startswith(("play", "loop", "end", "short"))
        check(label, ok, shown, show=shown_always)
    total = passed + failed
    print(f"\n{passed}/{total} checks passed")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
