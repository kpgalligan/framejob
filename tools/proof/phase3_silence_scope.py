"""Road map 2, phase 3a — the SCOPE half of Remove Silences, against the built
binary over MCP.

`phase3_proof.py` measures what the detector finds in a timeline where
everything is audible. This measures what it must NOT find when something is
not: a clip the mix has silenced covers its span while reading quiet at every
tick (`SilenceDetector.level` short-circuits on a zero envelope), so a scope
that let one in would answer with one cut across the whole clip — and
`ripple_delete_ranges` cuts every unlocked track, so that answer takes the
audible voiceover under the muted music bed away with it.

The fixture is the ordinary way a mix is checked: two tracks holding the same
recording, the front one muted so the back one can be heard alone.

* `detect_silence {clips: [<the muted clip>]}` — the `Selected clips` scope,
  spelled as an agent has it — must find NOTHING and name no clips.
* With the muted clip SELECTED and no `clips` argument, the opening scope must
  be `audible`, not `selected`: `Input.defaultScope` is what the sheet's popup
  opens on and what disables its "Selected clips" row, so a default of
  `selected` there puts a whole-timeline cut in front of the user with Remove
  enabled and no warning.
* And the ordinary reading must be untouched: the same call over the AUDIBLE
  clip still finds the fixture's two quiet spans.

Both failing checks answer `[[padding, 10 s − padding]]` on a build without
the fix, so neither can pass against one.

Media: `media/silence.mov` (the recipe is in README.md). No ffmpeg needed —
nothing here is exported.

    python3 tools/proof/phase3_silence_scope.py <dir>/agent.sock
"""

import os
import re
import shutil
import sys
import time

from mcp import MCP, ToolError, target

SOCKET = target(sys.argv)
HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work")

SEC = 600_000
# What `media/silence.mov` actually holds, in seconds (README.md).
QUIET = [(2.000, 3.500), (6.000, 7.000)]
CANVAS = (640, 360)

failures = []
checks = 0


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def ticks_of(seconds):
    return int(round(seconds * SEC))


def detect(mcp, path, **settings):
    """`detect_silence`, waiting out the peaks cache.

    `ProjectDocument.generateCaches` writes `cache/peaks/<media>.bin` in a
    fire-and-forget task at import and the detector proposes nothing inside a
    media whose waveform has not landed, so a run against a just-imported file
    has to wait or it would be measuring the cache rather than the mix."""
    for _ in range(60):
        answer = mcp.call("detect_silence", project=path, **settings)
        if "pending_peaks" not in answer:
            return answer
        time.sleep(0.5)
    raise RuntimeError("the peaks cache never landed for media/silence.mov")


def build(mcp):
    """Two tracks holding the same 10 s recording, the front one muted.

    Returns the project path and the two clip ids, back (audible) first."""
    for stale in os.listdir(WORK) if os.path.isdir(WORK) else []:
        if re.fullmatch(r"silence-scope-\d+\.reelcut", stale):
            shutil.rmtree(os.path.join(WORK, stale))
    path = os.path.join(WORK, f"silence-scope-{os.getpid()}.reelcut")
    mcp.call("new_project", path=path)
    mcp.call("set_canvas", project=path, width=CANVAS[0], height=CANVAS[1])
    media = mcp.call("import_media", project=path, path=os.path.join(MEDIA, "silence.mov"))["media"]

    def project():
        return mcp.call("get_project", project=path)["project"]

    back = project()["tracks"][0]["id"]
    before = {t["id"] for t in project()["tracks"]}
    # `name` is this tool's own argument, which collides with `call`'s first
    # parameter (mcp.py says so), so it goes through `call_with`.
    mcp.call_with("add_track", {"project": path, "name": "Music"})
    front = next(t["id"] for t in project()["tracks"] if t["id"] not in before)

    voice = mcp.call("add_clip", project=path, track=back, media=media, at=0)["new_clips"][0]
    music = mcp.call("add_clip", project=path, track=front, media=media, at=0)["new_clips"][0]
    mcp.call("set_track", project=path, track=front, muted=True)
    muted = next(t for t in project()["tracks"] if t["id"] == front)["muted"]
    check(muted is True, "the front track is muted (the fixture's premise)")
    return path, voice, music


def spans_of(answer):
    return [tuple(span) for span in answer["ranges"]]


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(SOCKET)
    print("3a — the scope of Remove Silences")
    path, voice, music = build(mcp)

    # The control: the audible clip alone still reads the way phase3_proof.py
    # measures it. Without this the two checks below would also pass against a
    # build that had simply stopped detecting anything.
    heard = detect(mcp, path, clips=[voice])
    padding = heard["padding"]
    want = [(ticks_of(a) + padding, ticks_of(b) - padding) for a, b in QUIET]
    check(
        heard["scope"] == "selected" and heard["clips"] == [voice],
        f"the audible clip is analysed on its own (scope {heard['scope']}, "
        f"clips {heard['clips']})",
    )
    check(
        spans_of(heard) == want,
        f"and answers the fixture's two quiet spans: {spans_of(heard)}",
    )

    # The defect: a silenced voice reads quiet at every tick, so scoping one
    # answers with its WHOLE span — a single cut across the entire song, which
    # `ripple_delete_ranges` would take out of every unlocked track.
    whole = (padding, 10 * SEC - padding)
    silenced = detect(mcp, path, clips=[music])
    check(
        spans_of(silenced) == [],
        f"the MUTED clip proposes no cut at all — not its whole span "
        f"{list(whole)} — got {silenced['ranges']}",
    )
    check(
        silenced["clips"] == [],
        f"and nothing was analysed, which is what the note says: "
        f"{silenced.get('note', '<no note>')!r}",
    )

    # And the opening scope, which is what the sheet's popup shows and what
    # disables its "Selected clips" row: a selection of silenced clips must
    # not open on `selected`, or the sheet puts that same whole-timeline cut
    # up with Remove enabled and no warning.
    mcp.call("set_selection", project=path, clips=[music])
    opened = detect(mcp, path)
    check(
        opened["scope"] == "audible",
        f"with only the muted clip SELECTED the default scope is audible, not "
        f"selected (got {opened['scope']})",
    )
    check(
        spans_of(opened) == want,
        f"so the default run measures the audible track: {opened['ranges']}",
    )

    # The other half of the default rule is untouched: an AUDIBLE selection
    # still opens on `selected`.
    mcp.call("set_selection", project=path, clips=[voice])
    check(
        detect(mcp, path)["scope"] == "selected",
        "an audible selection still opens on the selected scope",
    )

    summary()


def summary(aborted=None):
    tail = f" — ABORTED by {aborted}" if aborted else ""
    print(f"\n{checks - len(failures)}/{checks} checks passed{tail}")
    if failures:
        for line in failures:
            print(f"  FAILED: {line}")
    if failures or aborted:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, KeyError, RuntimeError, OSError, StopIteration) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
