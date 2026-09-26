"""The patch door's harness: the project under test and the four helpers.

Everything `patch_door_proof.py` proves is built out of this file, and
nothing here knows about any one door. It is the vocabulary — what a
`Session` is, what "the project is unchanged" means, what a refusal has to
say — so that a door's section is the door and nothing else.

**Why it is a file of its own** (deepening D1·4,
`archive/reelcut-roadmap-7.md` §2.4). The proof arrives one door at a time:
D1·3 built it with `set_video` alone, at exactly the 400 lines §0 gives a
new file, and D1·4 added eight more sections. A file at its cap gives
something up before it takes anything on (`CLAUDE.md`), and the thing to
give up first is the half that does not grow. This split was landed ALONE,
as a pure move, before a single door was added: the same functions, the same
bodies, the same order. The sections themselves then split by kind
(`patch_door_patches.py`, `patch_door_args.py`), leaving
`patch_door_proof.py` the explanation and `main`.

Nothing here is imported outside those three, and that is the point rather
than an oversight — `mcp.py` is the seam every script in this directory
crosses, and this is one proof's own scaffolding, kept separate for size and
not for reuse.
"""

import json
import os
import re
import shutil
import sys

from mcp import MCP, ToolError  # noqa: F401 — re-exported for the proof script

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work")

SEC = 600_000
CANVAS = (640, 360)
FPS = 30
FRAME = SEC // FPS                 # 20 000 ticks — the grid a patch's ticks land on

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


def shown(message):
    """A refusal on one line, for a transcript that has to stay readable."""
    if message is None:
        return "no error at all"
    flat = " ".join(str(message).split())
    return flat if len(flat) <= 140 else flat[:137] + "…"


# ---- the project under test ----------------------------------------------


class Session:
    """One project, the shape every script here uses.

    `<name>-<pid>.reelcut`, never a fixed name: a `project` path is matched
    against every open document and no tool closes one, so an earlier run's
    SAVED package would have the app answering for an old one (measured in
    phase 2). Older runs' under this name go."""

    def __init__(self, mcp, name, canvas=CANVAS, fps=FPS):
        self.mcp = mcp
        self.name = name
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=canvas[0], height=canvas[1], fps=fps)

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def text(self):
        """The whole project as ONE canonical string — the "unchanged" claim.

        `get_project` hands back parsed JSON, so the comparison is made over
        a key-sorted re-encoding of it rather than over the wire bytes: two
        encodings of one project compare equal and two different projects
        cannot, which is the property the claim needs. A door that corrected
        a value, cleared a field or completed an entry would answer with a
        new project and this string would move."""
        return json.dumps(self.project(), sort_keys=True)

    def clip_of(self, movie="A.mov"):
        media = self.op("import_media", path=os.path.join(MEDIA, movie))["media"]
        track = self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=0)["new_clips"][0]

    def clip(self, clip):
        """One clip as `get_project` reports it, whole — so a section can read
        back whichever group its door patched, or the clip's own name and
        label. `video` keeps a reader of its own below because `video_door`
        was the only section this file was written for."""
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def video(self, clip):
        return self.clip(clip)["video"]

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)


# ---- the four helpers every door's section is built out of ----------------


def refused(s, tool, what, sentence, **call):
    """One bad call, scored twice: the refusal says `sentence` VERBATIM, and
    the project afterwards is the project before.

    The sentence is a substring and never a keyword, because the wording IS
    the interface — an agent reads the path and the value out of it to fix
    its call — and a check looking only for `"kind"` passes against the door
    D1 deleted, which said `"kind"` too and meant something else. The second
    half is the one no keyword check can fake: a misspelt filter kind used
    to LAND as `blur`, a success, with the project moved."""
    before = s.text()
    message = s.error(tool, **call)
    after = s.text()
    check(message is not None and sentence in message,
          f"{what} — {sentence!r}; got: {shown(message)}")
    check(before == after,
          f"…and the project is unchanged after it ({len(before)} chars either side)")


def landed(what, got, wanted):
    """One placement read back through `get_project`."""
    check(got == wanted, f"{what} — {json.dumps(got)} (wanted {json.dumps(wanted)})")


def marker_gone(got, wanted):
    """The line after `undo_claim`, spelled once because every section says
    it: the marker edit is itself gone, so the one `undo` above undid THAT
    and not some step a refusal had left behind. It is `landed` with a fixed
    sentence, and the value is whichever key the marker moved."""
    landed("…the marker edit itself is gone, so the undo above undid THAT and nothing "
           "else", got, wanted)


def undo_marker(s, mark):
    """The first half of the "a refusal is not an undo step" claim: one REAL
    edit, whose undo step the refusals that follow have to leave alone.
    Answers the project as it was before it."""
    start = s.text()
    mark()
    check(s.text() != start,
          "a real edit moves the project — the marker the undo claim below needs")
    return start


def undo_claim(s, start):
    """Its second half, run after the refusals. If any of them had registered
    a step — or, worse, landed — this single `undo` would put back that step
    instead of the marker's and the project would not return to `start`. One
    undo for the whole batch is the stronger claim, not the cheaper one: N
    refusals that each left a step would need N undos."""
    s.op("undo")
    check(s.text() == start,
          "…and ONE undo after every refusal above puts the project back, so not one "
          "of them registered an undo step")


def summary(aborted=None):
    """The last line, and the exit status. An op that unexpectedly refused or
    errored — a `ToolError` no check was waiting for — aborts the run and is
    reported as the failure it is, with the checks that had passed by then,
    rather than as a bare traceback with no count."""
    tail = f" — ABORTED by {aborted}" if aborted else ""
    print(f"\n{checks - len(failures)}/{checks} checks passed{tail}")
    if failures:
        for line in failures:
            print(f"  FAILED: {line}")
    if failures or aborted:
        sys.exit(1)
