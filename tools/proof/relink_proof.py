#!/usr/bin/env python3
"""Spec §11 #63 — a relink that re-probes, measured against the built binary
over MCP.

`relink_media` used to change a media's path and bookmark and nothing else,
so a relink to a file of another length kept the old `duration`, and every
clip window bounded by it was wrong. Now all three doors probe the new file
the way `import_media` does and hand the descriptor to the op as its
`probe`, which the tool does not publish (G-4's shape): the entry takes the
file's duration, size, rate and flags, a file of another kind is refused in
the core's sentence, and a media clip that runs past a SHORTER file's end is
held to it. Every claim here is read back through `get_project`.

  * R0 — the parity log is clean, `relink_media`'s schema has no `probe`,
    and a call that sends one is refused by the gate, naming it.
  * R1 — copies of `A.mov` (10 s, video only) and `AV.mov` (5 s, video and
    audio) are imported; `AV`'s copy is the reference its later relink is
    read against. Three clips of A's media: X whole, Y with its `in` trimmed
    to 4 200 000 (7 s), Z with its duration trimmed to 1 200 000.
  * R2 — A's media relinked to a SECOND copy of `AV.mov`. The record now
    reads the reference's imported duration, `has_audio` true and the new
    copy's path; X ends at that duration snapped down to the 30 fps grid; Y
    is one frame (20 000 ticks) with its `in` kept; Z is unchanged. The
    duration row is the one the unfixed build fails (the mutant is HEAD
    before #63: exit 1, R2's duration row failing).
  * R3 — `undo` restores the record and all three clips.
  * R4 — a relink to a copy of `toneA.m4a` (audio) is refused in the core's
    sentence, and the project is unchanged. R5 — a relink to a `.txt` is
    "Could not read …", and the project is unchanged.
  * R6 — an explicit nest `scope` gets "relink_media has no meaning inside
    nest N".

No `ffmpeg` runs (it is broken on this host; the fixtures are the existing
test media, copied). Copies go under `work/relink/`, named by pid, and an
earlier pid's are swept at start. It opens one document; relaunch between
full runs, as every proof here asks.

    python3 tools/proof/relink_proof.py [port] [log path]
"""

import os
import re
import shutil
import sys

from mcp import MCP, ToolError

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4942
LOG = sys.argv[2] if len(sys.argv) > 2 else f"/tmp/reelcut-{PORT}.log"

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work", "relink")
MEDIA = os.path.join(HERE, "media")
FIXTURES = ("A.mov", "AV.mov", "toneA.m4a")
FRAME = 20_000  # one frame of the default 30 fps canvas

failures = []
checks = 0


def check(ok_, what):
    global checks
    checks += 1
    if ok_:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def section(name, run, *args):
    """One section, isolated: a section that raises scores ONE failure and
    the run goes on (phase 7's idiom)."""
    global checks
    print(f"\n{name}")
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — the point is to keep scoring
        checks += 1
        what = f"section {name.strip().split(' ')[0]} ran to the end (raised {error!r})"
        print(f"  FAIL {what}")
        failures.append(what)


def sweep_earlier_runs():
    """Earlier pids' packages and copies under `work/relink/` go (the
    README's rule): each is named by pid, and a copy means nothing to any
    package but its own run's."""
    mine = str(os.getpid())
    for stale in sorted(os.listdir(WORK)):
        match = re.fullmatch(r"relink-(\d+)[-.].*", stale)
        if match and match.group(1) != mine:
            path = os.path.join(WORK, stale)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.remove(path)


def copy_of(fixture, tag):
    """A copy of one fixture under `work/relink/`, times preserved."""
    extension = os.path.splitext(fixture)[1]
    copy = os.path.join(WORK, f"relink-{os.getpid()}-{tag}{extension}")
    shutil.copy2(os.path.join(MEDIA, fixture), copy)
    return copy


class State:
    """What the sections hand each other."""

    mcp = None
    package = None
    media = None
    reference = None
    clips = {}
    before = None


def op(s, tool, **kwargs):
    return s.mcp.call_with(tool, dict(project=s.package, **kwargs))


def project(s):
    return op(s, "get_project")["project"]


def record(s):
    return next(m for m in project(s)["media"] if m["id"] == s.media)


def clip(s, name):
    return next(c for c in project(s)["clips"] if c["id"] == s.clips[name])


def snapshot(s):
    """The part of the project a relink may touch: the media list and the
    clips."""
    p = project(s)
    return {"media": p["media"], "clips": p["clips"]}


# ---- R0 ----------------------------------------------------------------------


def part_r0(s):
    if os.path.exists(LOG):
        with open(LOG, errors="replace") as handle:
            complaints = [line for line in handle if "Reelcut: " in line]
        check(not complaints, f"the parity log at {LOG} has no `Reelcut: ` line "
                              f"({len(complaints)} found)")
    else:
        check(False, f"the parity log at {LOG} exists (launch with "
                     "`> /tmp/reelcut-<port>.log`, or pass it as the second argument)")
    schema = s.mcp.schemas()["relink_media"]["inputSchema"]
    properties = set(schema.get("properties", {}))
    check("probe" not in properties,
          f"relink_media's schema publishes no `probe` — the host fills it "
          f"(publishes {sorted(properties)})")
    check({"media", "path", "bookmark"} <= properties,
          "  and still publishes media, path and bookmark")
    try:
        s.mcp.call("relink_media", media=1, path="/nowhere.mov", probe={"kind": "video"})
        check(False, "a call that sends `probe` is refused")
    except ToolError as error:
        check("probe" in str(error) and "does not take" in str(error),
              f"a call that sends `probe` is refused by the gate, naming it: {error}")


# ---- R1 ----------------------------------------------------------------------


def part_r1(s):
    s.package = os.path.join(WORK, f"relink-{os.getpid()}.reelcut")
    s.mcp.call("new_project", path=s.package)
    imported = op(s, "import_media", path=copy_of("A.mov", "A"))
    s.media = imported["media"]
    check(not imported["has_audio"] and imported["duration"] == 6_000_000,
          f"A's copy imported: 10 s, video only (duration {imported['duration']})")
    s.reference = op(s, "import_media", path=copy_of("AV.mov", "AVref"))
    check(s.reference["has_audio"] and s.reference["duration"] < 6_000_000,
          f"AV's reference copy imported: video and audio, shorter than A "
          f"(duration {s.reference['duration']})")
    track = project(s)["tracks"][0]["id"]
    for name, at in (("X", 0), ("Y", 12_000_000), ("Z", 24_000_000)):
        s.clips[name] = op(s, "add_clip", track=track, media=s.media, at=at)["new_clips"][0]
    op(s, "trim_start", clip=s.clips["Y"], to=12_000_000 + 4_200_000)
    op(s, "trim_end", clip=s.clips["Z"], to=24_000_000 + 1_200_000)
    x, y, z = clip(s, "X"), clip(s, "Y"), clip(s, "Z")
    check(x["duration"] == 6_000_000, "X is the whole 10 s file")
    check(y["source"]["in"] == 4_200_000 and y["duration"] == 1_800_000,
          f"Y's `in` is 4 200 000, its last 3 s ({y['source']['in']}, {y['duration']})")
    check(z["source"]["in"] == 0 and z["duration"] == 1_200_000,
          f"Z is the file's first 2 s ({z['source']['in']}, {z['duration']})")
    s.before = snapshot(s)


# ---- R2 and R3 ---------------------------------------------------------------


def part_r2(s):
    av = copy_of("AV.mov", "AV")
    answer = op(s, "relink_media", media=s.media, path=av)
    check(answer.get("duration") == s.reference["duration"],
          f"the tool answers the probed duration ({answer.get('duration')})")
    entry = record(s)
    check(entry["duration"] == s.reference["duration"],
          f"get_project: the record's duration is the new file's, "
          f"{s.reference['duration']} ({entry['duration']})")
    check(entry["has_audio"] is True, "get_project: the record now has audio")
    check(entry["path"] == av, f"get_project: the record's path is the new copy's ({entry['path']})")
    end = s.reference["duration"] // FRAME * FRAME
    x, y = clip(s, "X"), clip(s, "Y")
    check(x["start"] + x["duration"] == end,
          f"X ends at the new duration snapped down to the grid, {end} "
          f"({x['start'] + x['duration']})")
    check(y["duration"] == FRAME and y["source"]["in"] == 4_200_000,
          f"Y, whose `in` is past the new end, is one frame with its `in` kept "
          f"({y['duration']}, {y['source']['in']})")
    before_z = next(c for c in s.before["clips"] if c["id"] == s.clips["Z"])
    check(clip(s, "Z") == before_z, "Z, inside the new file, is unchanged")


def part_r3(s):
    op(s, "undo")
    check(snapshot(s) == s.before, "undo restores the record and all three clips")


# ---- R4 to R6 ----------------------------------------------------------------


def part_r4(s):
    tone = copy_of("toneA.m4a", "tone")
    sentence = (f"media {s.media} is video media and {tone} is audio: relink it to a file of "
                f"the same kind, or import this one as new media")
    try:
        op(s, "relink_media", media=s.media, path=tone)
        check(False, "a relink to an audio file is refused")
    except ToolError as error:
        check(sentence in str(error), f"a relink to an audio file is refused in the core's "
                                      f"sentence: {error}")
    check(snapshot(s) == s.before, "  and the project is unchanged")


def part_r5(s):
    text = os.path.join(WORK, f"relink-{os.getpid()}-notes.txt")
    with open(text, "w") as handle:
        handle.write("not a movie\n")
    try:
        op(s, "relink_media", media=s.media, path=text)
        check(False, "a relink to a text file is refused")
    except ToolError as error:
        check("Could not read" in str(error),
              f"a relink to a text file answers \"Could not read\": {error}")
    check(snapshot(s) == s.before, "  and the project is unchanged")


def part_r6(s):
    op(s, "nest", clips=[s.clips["Z"]])
    nest = project(s)["nests"][0]["id"]
    try:
        op(s, "relink_media", media=s.media, path=copy_of("AV.mov", "AV-scoped"), scope=nest)
        check(False, "a relink with a nest scope is refused")
    except ToolError as error:
        check(f"relink_media has no meaning inside nest {nest}" in str(error),
              f"an explicit nest scope is refused by name: {error}")


def main():
    for name in FIXTURES:
        if not os.path.exists(os.path.join(MEDIA, name)):
            print(f"{os.path.join(MEDIA, name)} is needed; tools/proof/README.md says how to "
                  "make the test media.")
            return 2
    os.makedirs(WORK, exist_ok=True)
    sweep_earlier_runs()
    s = State()
    s.mcp = MCP(PORT)
    print(f"spec §11 #63 — relink re-probes, against 127.0.0.1:{PORT}")
    section("R0 — the parity log, the schema and the gate", part_r0, s)
    section("R1 — A's copy, the reference, and three clips", part_r1, s)
    section("R2 — relinked to a 5 s file: the record and the clips", part_r2, s)
    section("R3 — undo", part_r3, s)
    section("R4 — a file of another kind is refused", part_r4, s)
    section("R5 — a file nothing can read", part_r5, s)
    section("R6 — a nest scope", part_r6, s)
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
