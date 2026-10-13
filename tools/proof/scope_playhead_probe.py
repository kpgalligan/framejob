#!/usr/bin/env python3
"""The nest-scope playhead (#130, issue batch B21) — a scope change's playhead
write made authoritative, proved by FORCING the interleavings.

What happened. `phase9_proof.py`'s nest-scope rows failed one on every run and
three now and then ("with the playhead mapped back out", "maps the playhead
in", "the playhead reads …", "leaving maps the playhead back OUT"): entering or
leaving a nest rebuilt the player item for the other container, and
`finishScopeChange` then called `setPlayhead`, whose ASKED seek went to the
OUTGOING item — measured in the old container, so it clamped at that item's
end and was HEARD, and the rebuild then restored to the clamped time. The fix
is `Playback.seekAfterRebuild(to:)`: a scope change's time is the NEW
container's, so the outgoing item is neither sought nor heard, and the rebuild
in flight lands there, heard once. Two neighbours of the same race are fixed
beside it: an asked seek arriving while a restore is seeking is heard once,
when it lands; and `update`'s same-plan and empty-plan arms discard a rebuild
in flight (enter then leave in one turn installed the NEST's item under the
timeline).

Why a probe and not an MCP script. A race proved by re-running until it shows
is not proved. `Playback.rebuildHop` (nil in the app) stores the block a
rebuild would hand `DispatchQueue.main.async`, so the probe HOLDS a rebuild in
flight as long as a row needs, and runs two calls in ONE run-loop turn where a
row needs them together. `playhead_echo_probe.py`'s instrument otherwise:
`scope_playhead_probe.swift` compiled as `main.swift` against the whole of
`app/Sources` with `swift_build.py`'s line, `--sources PATH` to build
the same probe over another tree (the pre-fix reference is
`work/b30/prefix-sources/`, the tree with issue batch B30's seam and rows and
without its fix; the probe no longer builds over `work/b21/prefix-sources/`,
whose `rebuildHop` block takes no error), a build failure or a missing answer
scored as a FAILURE on every row. Every subprocess runs under
`graphics_spike/bounded.py` (Rule H). The editor's own `playback.onTimeChanged`
is wrapped to log every tick it carries, and `playback.onError` is replaced by
a recorder that never forwards (the editor's alert is app-modal).

Issue batch B30 (#185). A held scope change whose rebuild FAILS, or whose new
container's plan is EMPTY, used to leave the outgoing item on the player under
the new container's time, with `restoring` left set and the time unheard; the
fix drops the item, keeps the time and hears it once
(`Playback.endHoldWithoutItem`). The seam's block now takes an error: the probe
runs it with `nil` (the build's own result) or with `ProbeFault` (a failed
build). S13–S15 force both cases, and a row that expects a report now requires
one (`all_at`'s `at_least`): an empty log used to pass.

Fixture, rewritten every run under `work/scope-playhead/`: `scope.framejob`,
640 × 360 at 30 fps, black, one track, no clips — the probe itself adds shape A
at 0–1 s and shape B at 2–4 s and nests B into N at 2–4 s. No media, so no
ffmpeg: S8–S11 are `playhead_echo_probe.py`'s rows without its movie.

Rows (B = predicted to fail before the fix; every other row is a CONTROL).
"Held" = the rebuild's finishing block is stored, the probe waits for it and
for the player to come to rest, then runs it. "Rests at t" = the document's
playhead, the player's tick and the timeline's playhead all t. The log is
every tick `onTimeChanged` carried since the row began. "Kept at t" = the
document's playhead, the timeline's playhead and `Playback.currentTime` all t,
with no item on the player (so no player tick). S13 [B]: timeline 3 s, held,
enter N, the held build FAILS → no item, the built plan cleared, `restoring`
false, one error, kept at 1 s, heard at least once, every tick 1 s. S14 [B]:
then an opacity edit on N's clips → an item again, the built plan N's, rests at
1 s, every tick 1 s. S15 [B]: timeline 3 s, held, enter N, N's clips deleted
with the block held (N's plan empties), the held block run (a stale
generation) → no item, `restoring` false, kept at 1 s, heard at least once,
every tick 1 s.

Needs `swiftc`, `xcrun metal` and `core/target/release/libframejob_core.a`. No
port. Run from anywhere:

    python3 tools/proof/scope_playhead_probe.py [--sources PATH]
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = os.path.join(HERE, "work", "scope-playhead")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "scope_playhead_probe.swift")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")
HEADER = os.path.join(ROOT, "core", "include", "framejob_core.h")

TICKS = 600_000

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


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy (`e2_proof.py`'s)."""
    with open(HEADER) as f:
        match = re.search(r"#define RC_FORMAT_VERSION (\d+)", f.read())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


# ---------------------------------------------------------------------------
# The fixture.


def make_fixture():
    """(package, None) or (None, reason)."""
    os.makedirs(WORK, exist_ok=True)
    package = os.path.join(WORK, "scope.framejob")
    shutil.rmtree(package, ignore_errors=True)
    os.makedirs(package)
    try:
        version = format_version()
    except (OSError, RuntimeError) as error:
        return None, f"no format version: {error}"
    project = {
        "version": version,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": True},
        "media": [],
        "tracks": [{"id": 1, "name": "Track 1"}],
        "clips": [], "markers": [], "next_id": 2, "nests": [],
    }
    with open(os.path.join(package, "project.json"), "w") as f:
        json.dump(project, f, indent=1)
    return package, None


# ---------------------------------------------------------------------------
# The probe — `playhead_echo_probe.py`'s build, verbatim but for the names.


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
    binary = os.path.join(probe, "scope_playhead_probe")
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


# ---------------------------------------------------------------------------
# The rows: (id, kind, name, predicate over the answer, detail). kind is "B"
# (predicted to fail before the fix) or "" (CONTROL).


def all_at(log, t, at_least=0):
    """At least `at_least` reports, every one of them `t`."""
    return len(log) >= at_least and all(x == t for x in log)


def rests(s, t):
    return s["playhead"] == t and s["playerTicks"] == t and s["timeline"] == t


def kept_at(s, t):
    """No item on the player, so no player tick: the document, the timeline
    and `Playback.currentTime`."""
    return s["playhead"] == t and s["timeline"] == t and s["currentTime"] == t


def rows():
    sec = TICKS
    yield ("S0", "", "built: the timeline 4 s, N at 2 s, the nest 2 s",
           lambda a: a["S0"]["duration"] == 4 * sec and a["S0"]["nStart"] == 2 * sec
           and a["S0"]["nDuration"] == 2 * sec, lambda a: a["S0"])
    yield ("S1", "B", "inside at 1 s, the rebuild held, leave: 3 s during the hold; rests at "
           "3 s; every tick 3 s",
           lambda a: a["S1"]["held"] and a["S1"]["duringHold"] == 3 * sec
           and a["S1"]["scope"] == 0 and rests(a["S1"], 3 * sec)
           and all_at(a["S1"]["log"], 3 * sec, at_least=1), lambda a: a["S1"])
    # S2 and S5 were written as B rows and PASS on the pre-fix tree, on every
    # run (issue batch B21): the scope's rebuild lands before the seek in
    # flight, and the restore takes the last asked time. They are controls.
    yield ("S2", "", "inside at 0, one turn: setPlayhead(1 s), leave: rests at 3 s; every "
           "tick 3 s",
           lambda a: a["S2"]["scope"] == 0 and rests(a["S2"], 3 * sec)
           and all_at(a["S2"]["log"], 3 * sec, at_least=1), lambda a: a["S2"])
    yield ("S3", "", "timeline 3 s, the rebuild held, enter N: rests at 1 s; every tick 1 s",
           lambda a: a["S3"]["held"] and a["S3"]["scope"] == 1 and rests(a["S3"], sec)
           and all_at(a["S3"]["log"], sec, at_least=1), lambda a: a["S3"])
    yield ("S4", "B", "timeline 3 s, one turn: enter N, leave: the built plan is the "
           "timeline's; rests at 3 s",
           lambda a: a["S4"]["planMatches"] is True and a["S4"]["scope"] == 0
           and rests(a["S4"], 3 * sec), lambda a: a["S4"])
    yield ("S5", "", "timeline 0.5 s, one turn: opacity on A, setPlayhead(3 s), enter N: "
           "rests at 1 s; every tick 1 s",
           lambda a: a["S5"]["scope"] == 1 and rests(a["S5"], sec)
           and all_at(a["S5"]["log"], sec, at_least=1), lambda a: a["S5"])
    yield ("S6", "B", "timeline 1 s, one turn: opacity on A, setPlayhead(2 s): rests at 2 s; "
           "the log non-empty, every tick 2 s",
           lambda a: rests(a["S6"], 2 * sec)
           and all_at(a["S6"]["log"], 2 * sec, at_least=1), lambda a: a["S6"])
    yield ("S7", "B", "timeline 1 s, a move of A held, one turn: the held block, "
           "setPlayhead(2 s): rests at 2 s; every tick 2 s",
           lambda a: a["S7"]["held"] and rests(a["S7"], 2 * sec)
           and all_at(a["S7"]["log"], 2 * sec, at_least=1), lambda a: a["S7"])
    yield ("S8", "", "from 1 s, setPlayhead(0.5 s): 0.5 s in the log; rests at 0.5 s",
           lambda a: sec // 2 in a["S8"]["log"] and rests(a["S8"], sec // 2),
           lambda a: a["S8"])
    yield ("S9", "", "at 0.5 s, the right arrow: 0.5 s + 1 frame in the log; the document "
           "and the timeline there",
           lambda a: sec // 2 + a["frame"] in a["S9"]["log"]
           and a["S9"]["playhead"] == sec // 2 + a["frame"]
           and a["S9"]["timeline"] == sec // 2 + a["frame"], lambda a: a["S9"])
    # S10 and S11 keep `at_least` 0: a restore that rests on the tick last
    # reported is silent by design, so an empty log is the right answer there.
    yield ("S10", "", "at 1 s, an opacity edit on A: every tick 1 s; rests at 1 s",
           lambda a: all_at(a["S10"]["log"], sec) and rests(a["S10"], sec),
           lambda a: a["S10"])
    yield ("S11", "", "at 1 s, A moved one frame, non-live: every tick 1 s; rests at 1 s",
           lambda a: all_at(a["S11"]["log"], sec) and rests(a["S11"], sec),
           lambda a: a["S11"])
    yield ("S12", "", "after S1–S7, 1.2 s of play from 0.5 s: ≥ 10 ticks, non-decreasing, "
           "advanced ≥ 0.4 s, the document == the last",
           lambda a: len(a["S12"]["log"]) >= 10
           and all(y >= x for x, y in zip(a["S12"]["log"], a["S12"]["log"][1:]))
           and a["S12"]["playhead"] - a["S12"]["from"] >= 0.4 * sec
           and a["S12"]["playhead"] == a["S12"]["log"][-1],
           lambda a: {"count": len(a["S12"]["log"]), "first": a["S12"]["log"][:3],
                      "last": a["S12"]["log"][-3:], "playhead": a["S12"]["playhead"]})
    yield ("S13", "B", "timeline 3 s, the rebuild held, enter N, the build FAILS: no item, the "
           "built plan cleared, not restoring, one error; kept at 1 s; heard, every tick 1 s",
           lambda a: a["S13"]["held"] and a["S13"]["hasItem"] is False
           and a["S13"]["builtPlanCleared"] is True and a["S13"]["restoring"] is False
           and a["S13"]["errors"] == 1 and a["S13"]["scope"] == 1 and kept_at(a["S13"], sec)
           and all_at(a["S13"]["log"], sec, at_least=1), lambda a: a["S13"])
    yield ("S14", "B", "then, inside N, an opacity edit on N's clips: an item, the built plan "
           "N's; rests at 1 s; every tick 1 s",
           lambda a: a["S14"]["hasItem"] is True and a["S14"]["planMatches"] is True
           and a["S14"]["scope"] == 1 and rests(a["S14"], sec)
           and all_at(a["S14"]["log"], sec), lambda a: a["S14"])
    yield ("S15", "B", "timeline 3 s, the rebuild held, enter N, N's clips deleted, the held "
           "block run: no item, not restoring; kept at 1 s; heard, every tick 1 s",
           lambda a: a["S15"]["held"] and a["S15"]["hasItem"] is False
           and a["S15"]["restoring"] is False and a["S15"]["scope"] == 1
           and kept_at(a["S15"], sec) and all_at(a["S15"]["log"], sec, at_least=1),
           lambda a: a["S15"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default=SOURCES,
                        help="an app/Sources tree to build the probe over (default: this tree's)")
    sources = os.path.abspath(parser.parse_args().sources)
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
        check(label, ok, shown, show=kind == "B")
    total = passed + failed
    print(f"\n{passed}/{total} checks passed")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
