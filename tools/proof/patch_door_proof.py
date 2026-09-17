"""The PATCH DOOR, driven against the built binary over MCP.

Named for the seam and not for a phase: what it proves is the one door every
caller-authored object comes through (`core/src/patch.rs`, `CONTEXT.md`'s
**Patch**), and the doors arrive one deepening ticket at a time
(`designs/reelcut-roadmap-7.md` §1, kpgalligan/reelcut#1). Deepening D1·3
built the file with `set_video`'s section; D1·4 and D1·5 add theirs beside
it. There is no phase number to put on that.

**What a patch means, which is the whole of what is checked here.** A patch
merges key by key at EVERY depth, `null` clears a key and an array replaces
its whole list. A key or a value the vocabulary does not have is REFUSED —
never dropped, corrected or clamped — naming the dotted path to it, array
indices included, and the value sent; the project is left exactly as it was,
so a failed call is safe to retry.

**The four sentence forms** the core gives, which every section below
asserts verbatim rather than by keyword:

    unknown key "<path>" in <subject>
    missing key "<path>" in <subject>
    bad value at "<path>" in <subject>: <serde's own sentence>
    <group> patch must be a json object, not <value>

`<subject>` is `a video patch`, `an audio patch`, `a text patch`, `a shape
patch` or `an action end patch`; in the last the path carries the group
(`video.filters[1].kind`). Beside them the RANGE refusals, `props_check.rs`'s,
spelled with the group's name and no index — `video.shadow.color must be
between 0 and 1, not 2`.

**Why it has to be driven through the app.** `core/tests/patch_door.rs`
proves all of this through the FFI. What it cannot see is the Swift agent
door, which until D1·3 decoded the caller's object through the app's LENIENT
project types and sent the RESULT on: a misspelt enum arrived as the
vocabulary's first case, an unknown key inside a nested object was dropped,
a three-element colour had an alpha filled in and an out-of-range component
was clamped — each of them an edit nobody asked for, reported as success.
Only a call made over MCP against the built binary tells the two apart.

**The template, and where the next door's section goes.** One section per
door, built out of the four helpers below — `refused` (the refusal AND the
unchanged project), `landed` (a merge read back) and `undo_marker` /
`undo_claim` (the two halves of "a refusal registers no undo step"). A new
section is a function shaped like `video_door` plus one line in `main`; the
marker `# ---- the next door's section goes here` says where, and which
doors are still owed.

Needs no ffmpeg and nothing in `media/` but `A.mov`, which
`tools/proof/README.md` says how to make. Run it as every other script here
is run:

    python3 tools/proof/patch_door_proof.py <port>
"""

import json
import os
import re
import shutil
import sys

from mcp import MCP, ToolError

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4823
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

    def video(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]["video"]

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
    this ticket deleted, which said `"kind"` too and meant something else.
    The second half is the one no keyword check can fake: a misspelt filter
    kind used to LAND as `blur`, a success, with the project moved."""
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


# ---- set_video (D1·3, kpgalligan/reelcut#4) -------------------------------


def video_door(mcp):
    """`set_video` — the first door to forward the caller's patch raw.

    The fixture stores a shadow, a filter stack and a motion BEFORE anything
    is refused, which is deliberate: wherever a refusal below names a key
    the clip already holds a value for — the shadow, the filters, a motion
    slot — a door that dropped the key, cleared the field or completed the
    entry would be making a real edit, and the "unchanged" half of `refused`
    would go red. (`spotlight.shape` and the unknown `blurr` have nothing
    stored behind them; they discriminate on the sentence alone.)"""
    print("\n1 — set_video: the patch goes to the core as the caller wrote it")
    s = Session(mcp, "patch-door-video")
    clip = s.clip_of()
    s.op("set_video", clips=[clip], patch={
        "shadow": {"color": [0.0, 0.0, 0.0, 1.0], "opacity": 0.8, "blur": 10.0,
                   "angle": 315.0, "distance": 30.0},
        "filters": [{"kind": "sepia", "amount": 1.0}],
        "motion": {"in": {"kind": "slide_up", "duration": 5 * FRAME},
                   "out": {"kind": "fade", "duration": 10 * FRAME}},
    })
    stored = s.video(clip)
    check(stored["shadow"]["blur"] == 10 and stored["filters"][0]["kind"] == "sepia"
          and stored["motion"]["out"]["kind"] == "fade",
          "the fixture stores a shadow, a sepia filter and a motion with both edges")

    print("\n1a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("set_video", clips=[clip], patch={"opacity": 0.25}))

    print("\n1b — a key or a value the vocabulary does not have, refused by path")
    # The ticket's three, first (kpgalligan/reelcut#4): each of them used
    # to LAND. A misspelt kind arrived as the enum's first case, an
    # unknown key inside a nested object was dropped on the way through
    # the typed decoder, and a number where an object belongs read as
    # "clear it".
    refused(s, "set_video", "a misspelt filter kind, by INDEX",
            'bad value at "filters[1].kind" in a video patch: unknown variant `glow`',
            clips=[clip],
            patch={"filters": [{"kind": "blur", "amount": 0.5},
                               {"kind": "glow", "amount": 1.0}]})
    refused(s, "set_video", "an unknown key INSIDE a filter entry",
            'unknown key "filters[0].amont" in a video patch',
            clips=[clip],
            patch={"filters": [{"kind": "blur", "amount": 0.5, "amont": 1.0}]})
    refused(s, "set_video", "a number where the shadow OBJECT belongs",
            'bad value at "shadow" in a video patch: expected an object, not 5',
            clips=[clip], patch={"shadow": 5})
    # The fourth sentence form (D1·2), and the most tempting patch an
    # agent writes: "the same filter, more of it". A list replaces
    # whole, so the entry is merged over nothing and a missing `kind`
    # would be completed into a half-strength blur.
    refused(s, "set_video", "a filter entry naming only its amount",
            'missing key "filters[0].kind" in a video patch',
            clips=[clip], patch={"filters": [{"amount": 1.0}]})
    # A `null` is a spelling of a key, not a way past the walk.
    refused(s, "set_video", "an unknown key spelled with a null",
            'unknown key "blurr" in a video patch',
            clips=[clip], patch={"blurr": None})
    # Two levels down, inside `motion` — where the Swift door used to
    # have a hand-written reader of its own (`AgentServer+Motion.swift`,
    # deleted in D1·3) saying the same thing in different words.
    refused(s, "set_video", "a misspelt key inside a motion slot",
            'unknown key "motion.in.durration" in a video patch',
            clips=[clip],
            patch={"motion": {"in": {"kind": "fade", "durration": 3 * FRAME}}})
    refused(s, "set_video", "a misspelt motion kind",
            'bad value at "motion.in.kind" in a video patch: unknown variant `slide_upp`',
            clips=[clip],
            patch={"motion": {"in": {"kind": "slide_upp", "duration": 5 * FRAME}}})
    refused(s, "set_video", "a misspelt spotlight shape",
            'bad value at "spotlight.shape" in a video patch: unknown variant `circle`',
            clips=[clip], patch={"spotlight": {"shape": "circle"}})
    # A colour is FOUR numbers (spec #1). The three-element form used to
    # have its alpha filled in on the way past and an out-of-range
    # component used to be CLAMPED — a value changed without the caller
    # knowing, which is the one thing a patch may never do.
    refused(s, "set_video", "a three-element colour",
            'bad value at "shadow.color" in a video patch: invalid length 3',
            clips=[clip], patch={"shadow": {"color": [1.0, 0.0, 0.0]}})
    refused(s, "set_video", "a colour component outside 0–1",
            "video.shadow.color must be between 0 and 1, not 2",
            clips=[clip], patch={"shadow": {"color": [2.0, 0.0, 0.0, 1.0]}})
    # The patch itself. The core names the GROUP, which is what a check
    # on this side could not: it is answering for `set_video` here and
    # for `set_shape` in the same words.
    refused(s, "set_video", "a patch that is not an object at all",
            "video patch must be a json object, not 5",
            clips=[clip], patch=5)

    print("\n1c — and not one of them was an undo step")
    undo_claim(s, start)
    check(s.video(clip)["opacity"] == 1.0,
          "…the marker edit itself is gone, so the undo above undid THAT and nothing else")

    print("\n1d — and a good patch merges, key by key, at every depth")
    s.op("set_video", clips=[clip], patch={"shadow": {"blur": 20.0}})
    landed("a one-key shadow patch keeps the colour, the angle and the distance",
           s.video(clip)["shadow"],
           {"color": [0, 0, 0, 1], "opacity": 0.8, "blur": 20, "angle": 315, "distance": 30})
    s.op("set_video", clips=[clip], patch={"shadow": None})
    landed("…and null clears the whole object", s.video(clip)["shadow"], None)

    s.op("set_video", clips=[clip],
         patch={"filters": [{"kind": "blur", "amount": 0.25}]})
    landed("a filter LIST replaces rather than merging",
           s.video(clip)["filters"], [{"kind": "blur", "amount": 0.25}])
    s.op("set_video", clips=[clip], patch={"filters": []})
    landed("…and an empty list clears the stack", s.video(clip)["filters"], [])

    # `motion` is the key this ticket changes for an agent: the MCP argument
    # used to replace the whole object, so a patch naming `in` cleared a
    # stored `out`. It merges like every other nested object now, and the
    # app's own two writers send all three slots, which is the same rule
    # spelled out by a writer that knows them all.
    s.op("set_video", clips=[clip], patch={"motion": {"in": {"kind": "pop"}}})
    landed("a motion patch naming only `in` KEEPS the stored `out`",
           s.video(clip)["motion"],
           {"in": {"kind": "pop", "duration": 5 * FRAME},
            "out": {"kind": "fade", "duration": 10 * FRAME}, "during": None})
    s.op("set_video", clips=[clip], patch={"motion": {"out": None}})
    landed("…a slot set to null clears THAT slot",
           s.video(clip)["motion"],
           {"in": {"kind": "pop", "duration": 5 * FRAME}, "out": None, "during": None})
    s.op("set_video", clips=[clip], patch={"motion": {"in": None}})
    landed("…and a motion whose every slot is null reads back as none",
           s.video(clip)["motion"], None)
    s.op("set_video", clips=[clip],
         patch={"motion": {"during": {"kind": "pulse", "amount": 0.5,
                                      "period": 30 * FRAME}}})
    check(s.video(clip)["motion"]["during"]["kind"] == "pulse",
          "a motion set again from none lands")
    s.op("set_video", clips=[clip], patch={"motion": None})
    landed("…and `motion: null` clears the whole preset",
           s.video(clip)["motion"], None)

    print("\n1e — and the ticks a patch carries land on the frame grid")
    # 30 fps, so a frame is 20 000 ticks. 313 000 is 15.65 frames and has to
    # come back as 16 of them; the core snaps AFTER the range check, so a
    # negative duration is still named rather than rounded into a legal 0.
    s.op("set_video", clips=[clip],
         patch={"motion": {"in": {"kind": "fade", "duration": 313_000}}})
    landed("an off-grid motion duration reads back ON the grid",
           s.video(clip)["motion"]["in"]["duration"], 16 * FRAME)
    s.op("set_video", clips=[clip],
         patch={"motion": {"during": {"kind": "shake", "amount": 0.5, "period": 5}}})
    landed("…a period under half a frame floors at one FRAME rather than at 0",
           s.video(clip)["motion"]["during"]["period"], FRAME)
    refused(s, "set_video", "…and a negative duration is still named, not rounded to 0",
            "video.motion.in.duration must not be negative, not -1",
            clips=[clip], patch={"motion": {"in": {"kind": "fade", "duration": -1}}})


# ---- the next door's section goes here ------------------------------------
#
# Copy `video_door` whole. What changes is the fixture (a door needs a clip
# that HAS the group it patches, holding a value the refusals name), the
# tool, and the subject inside each sentence — `an audio patch`, `a text
# patch`, `a shape patch`, `an action end patch` — plus the group prefix an
# end patch's paths carry (`video.filters[1].kind`). The three helpers and
# the three sub-sections (refusals, the undo claim, the merges) do not
# change, and neither does the order: the fixture first, so that every
# refusal is against a key the clip already has a value for.
#
# D1·4 (kpgalligan/reelcut#5): `set_audio`, `set_text`, `set_clip`,
# `set_shape`, `add_text_clip`, `add_shape_clip`, and the two colour-only
# arguments — `set_canvas`'s `background` and `add_background_clip`'s
# `color`, whose sections assert the four-number rule at an argument rather
# than inside a patch.
#
# D1·5 (kpgalligan/reelcut#6): `set_action_end` and `add_zoom_action`.


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)
    print(f"the patch door, against 127.0.0.1:{PORT}")
    video_door(mcp)
    summary()


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


if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, KeyError, RuntimeError, OSError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
