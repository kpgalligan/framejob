"""WHAT AN OP ANSWERS, driven against the built binary over MCP.

Named for the seam and not for a phase, as `patch_door_proof.py` is: what it
proves is the answer every edit comes back with (`core/src/outcome.rs`,
`app/Sources/ReelEdit.swift`, `CONTEXT.md`'s **Op**), and the rules that can
say why arrive one deepening ticket at a time
(`archive/reelcut-roadmap-7.md` §4, kpgalligan/reelcut#8). Deepening D2·2
built it with the overlap rule's section; D2·3 adds one section per rule that
finds its voice. There is no phase number to put on that.

**The three answers, which are the whole of what is checked here.** An op
either changes the project, or is an IDENTITY (it was valid and nothing
needed to change), or is REFUSED (a rule declined it, in the rule's own
words). The last two are both "the project did not change": neither
registers an undo step, neither is an error tier, and a person at the
machine gets the same beep for both. What is new since D2 is that a caller
can tell them apart, and that is what this script measures.

**The two sentence forms** an agent reads, asserted whole and never by
keyword:

    <Action> made no change: the project is already in that state.
    <Action> was refused at <op>: <the rule's own sentence>

The identity says ONLY that. It names no rule, because a caller told about
one here would go looking for a rule it did not break. The refusal carries
the core's sentence verbatim — "clips 3 and 4 would overlap by 3200000
ticks, more than half of the shorter clip (3000000 ticks)" — with the clip
ids and the tick counts intact, since those are the part a caller acts on;
and it names the OP from the table, because one call may carry several ops
and the caller has to know which to fix.

**What it replaced.** Until D2·2 both answers came back as one paragraph
that offered the caller both meanings and then lectured it about the overlap
rule — sent in reply to a font size, as deepening D1's verification kept
demonstrating. Every section below asserts that paragraph is gone as well as
that the right one arrived: a check that only looked for the new words would
pass against a build that sent both.

**Why it has to be driven through the app.** `core/tests/refusal.rs` proves
the three arms through the FFI. What it cannot see is the Swift side of the
seam — whether the app READS `reason_out` at all, whether the agent's shared
reply still guesses, and whether a refusal is still no undo step once it has
been through `ProjectDocument`. Only a call made over MCP against the built
binary answers those.

**One section per rule, built out of five helpers**: `refused` (the whole
sentence, the op named, the old paragraph gone, and the project unchanged),
`identity` (the whole sentence, no rule named, the project unchanged),
`landed` (a placement read back), and `undo_marker` / `undo_claim` (the two
halves of "neither answer registers an undo step"). A new rule's section is
a function shaped like `overlap_rule` plus one line in `main`.

Needs no ffmpeg. It reads `A.mov` and `AV.mov` from `media/`, which
`tools/proof/README.md` says how to make. Run it as every other script here
is run, on an instance of its OWN:

    python3 tools/proof/refusal_proof.py <dir>/agent.sock
"""

import json
import os
import re
import shutil
import sys
import time

from mcp import MCP, ToolError, target

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work")

SEC = 600_000
CANVAS = (640, 360)
FPS = 30
FRAME = SEC // FPS                 # 20 000 ticks — the grid every tick lands on

# The identity's whole sentence, after the action name.
IDENTITY = "made no change: the project is already in that state."

# Two fragments of the paragraph D2·2 deleted. Both are asserted ABSENT at
# every refusal and every identity: the old text also began "<Action> made no
# change", so a build that sent it would pass a check that looked only for
# the new words.
GUESSES = [
    "Either the project is already in that state",
    "the usual reason for a placement op is the overlap rule",
]

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
    """A reply on one line, for a transcript that has to stay readable."""
    if message is None:
        return "no error at all"
    flat = " ".join(str(message).split())
    return flat if len(flat) <= 160 else flat[:157] + "…"


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
        cannot, which is the property the claim needs."""
        return json.dumps(self.project(), sort_keys=True)

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def media(self, movie):
        return self.op("import_media", path=os.path.join(MEDIA, movie))["media"]

    def peaked(self, movie):
        """A media whose peaks cache has landed — what `normalize_clip` needs
        before it can measure anything. The cache is written by a
        fire-and-forget task at import, so a normalise issued in the same
        breath legitimately answers "still being analysed"
        (`phase5_proof.py` argues the same wait)."""
        media = self.media(movie)
        peaks = os.path.join(self.path, "cache", "peaks", f"{media}.bin")
        for _ in range(300):
            if os.path.exists(peaks):
                return media
            time.sleep(0.05)
        raise RuntimeError(f"{self.name}: cache/peaks/{media}.bin was never written")

    def place(self, media, at, track=None):
        track = track if track is not None else self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)


# ---- the five helpers every section is built out of -----------------------


def refused(s, tool, op, what, sentence, **call):
    """One refused call, scored three times.

    The reply must END in the rule's own sentence, introduced by the op the
    core refused — `<Action> was refused at <op>: <sentence>` — and the
    sentence is matched WHOLE, ids and tick counts included, never by
    keyword: the numbers are what a caller computes its next request from,
    and a check looking for `"overlap"` passes against the paragraph D2·2
    deleted, which said `"overlap"` too and meant nothing by it. The second
    check is that paragraph's absence. The third is the one no wording check
    can fake: a refusal leaves the project exactly as it was."""
    before = s.text()
    message = s.error(tool, **call)
    after = s.text()
    tail = f"was refused at {op}: {sentence}"
    check(message is not None and message.endswith(tail),
          f"{what} — …{tail!r}; got: {shown(message)}")
    check(message is not None and not any(g in message for g in GUESSES),
          "…and not one word of the paragraph that used to guess at the reason")
    check(before == after,
          f"…and the project is unchanged after it ({len(before)} chars either side)")


def identity(s, tool, action, what, **call):
    """One identity call, scored three times: the reply is that whole
    sentence and NOTHING else, it names no rule, and the project is
    unchanged.

    The first check is an equality rather than a substring, which is what
    makes "says only that" measurable — any lecture appended to it would
    move the string. The second is spelled out anyway, because "a refusal
    never mentions the overlap rule when the overlap rule is not what
    refused me" is the user story this section exists for, and a transcript
    should say so in those words."""
    before = s.text()
    message = s.error(tool, **call)
    after = s.text()
    whole = f"{tool}: {action} {IDENTITY}"
    check(message == whole, f"{what} — {whole!r}; got: {shown(message)}")
    check(message is not None
          and not any(g in message for g in GUESSES)
          and "overlap" not in message and "refused" not in message,
          "…and it names no rule at all, so nobody goes looking for one they did not break")
    check(before == after,
          f"…and the project is unchanged after it ({len(before)} chars either side)")


def landed(what, got, wanted):
    """One placement read back through `get_project`."""
    check(got == wanted, f"{what} — {json.dumps(got)} (wanted {json.dumps(wanted)})")


def applied(s, tool, what, **call):
    """The other answer, scored once: a call that the core APPLIED, which is
    what makes the refusals beside it a rule rather than a blanket."""
    message = s.error(tool, **call)
    check(message is None,
          what if message is None else f"{what} — but it answered: {shown(message)}")


def undo_marker(s, mark):
    """The first half of the "neither answer is an undo step" claim: one REAL
    edit, whose undo step the answers that follow have to leave alone.
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
    answers that each left a step would need N undos."""
    s.op("undo")
    check(s.text() == start,
          "…and ONE undo after every answer above puts the project back, so not one of "
          "them registered an undo step")


# ---- the overlap rule (D2·2, kpgalligan/reelcut#10) -----------------------


def overlap_rule(mcp):
    """The overlap rule, the first rule to speak — and the TEMPLATE every
    later rule's section copies.

    The rule: a clip may overlap at most one neighbour on each side, and each
    overlap must be at most half the shorter of the two clips
    (`core/src/transition.rs`'s `check_overlap_rule`, which writes the
    sentence). It is the rule with the most to say, because its sentence
    carries four numbers a caller can act on — the two clip ids, the overlap
    it would make, and the limit it broke.

    The fixture is two abutting ten-second clips on one track, so every
    number below is hand-computed rather than read back off the project: a
    sentence that had lost exactly the part a caller reads would still
    contain every word this section asserts if the numbers came from the
    same place the app got them."""
    print("\n1 — the overlap rule speaks, in its own words, through the app")
    s = Session(mcp, "refusal-overlap")
    media = s.media("A.mov")
    a = s.place(media, 0)
    b = s.place(media, 10 * SEC)
    landed("the fixture is two abutting clips of the ten-second card",
           [[c["start"], c["duration"]] for c in s.project()["clips"]],
           [[0, 10 * SEC], [10 * SEC, 10 * SEC]])
    half = 10 * SEC // 2           # 3 000 000 — half of the shorter clip

    print("\n1a — a real edit, whose undo step every answer below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[a], patch={"name": "Marker"}))

    print("\n1b — a move the rule declines, answered in the rule's own sentence")
    over = half + 10 * FRAME       # 3 200 000 — ten frames past the limit
    refused(s, "move_clip", "move_clip",
            "a move that would overlap the neighbour by more than half of it",
            f"clips {a} and {b} would overlap by {over} ticks, more than half of the "
            f"shorter clip ({half} ticks)",
            clips=[b], delta=-over)
    # One frame under the limit is the same rule NOT refusing, which is what
    # makes the refusal above a rule and not a blanket — and it is read BACK
    # off the project, because an absent error is not a placement.
    applied(s, "move_clip",
            "…while an overlap one frame UNDER the limit is allowed, so the number in "
            "the sentence is the rule's own boundary",
            clips=[b], delta=-(half - FRAME))
    landed("…and that move LANDED, at the tick the delta asks for",
           s.clip(b)["start"], 10 * SEC - (half - FRAME))
    s.op("undo")

    print("\n1c — and the same sentence out of a DIFFERENT op, about the clip it would mint")
    # `duplicate` places the copy immediately after its original, where the
    # neighbour already is. The ids in the sentence are the core's own — the
    # copy is named although it was never created, which is the proof that
    # the words come from the rule at the moment it decided and not from
    # anything the app read back afterwards.
    refused(s, "duplicate", "duplicate",
            "a duplicate whose copy would land on the neighbour",
            f"clips {b} and {b + 1} would overlap by {10 * SEC} ticks, more than half of "
            f"the shorter clip ({half} ticks)",
            clips=[a])

    print("\n1d — the sentence survives a SCOPED call, which is the app's own addressing")
    s.op("nest", clips=[a, b])
    group = s.project()["nests"][0]
    inside = [c["id"] for c in group["clips"]]
    landed("the two clips are inside a nest now, under the ids they had",
           inside, [a, b])
    refused(s, "move_clip", "move_clip",
            "the same move inside a nest answers in the same words",
            f"clips {a} and {b} would overlap by {over} ticks, more than half of the "
            f"shorter clip ({half} ticks)",
            clips=[b], delta=-over, scope=group["id"])

    print("\n1e — and not one of them was an undo step")
    s.op("undo")                   # the nest, which WAS a real edit
    undo_claim(s, start)
    landed("…the marker edit itself is gone, so the undo above undid THAT and nothing "
           "else", s.clip(a)["name"], None)


# ---- an identity, which says only that ------------------------------------


def identity_says_only_that(mcp):
    """An op that genuinely changes nothing, at four doors.

    This is the other half of the seam, and the half that used to be
    slandered: the reply to a font size named the overlap rule, because one
    answer covered both meanings. Each call below asks for the value the
    project already holds — no rule is anywhere near them — and the reply is
    asserted as a WHOLE string, which is the only way to measure "says only
    that"."""
    print("\n2 — an identity says only that it changed nothing")
    s = Session(mcp, "refusal-identity")
    media = s.media("A.mov")
    clip = s.place(media, 0)

    print("\n2a — a real edit, whose undo step every answer below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[clip], patch={"name": "Marker"}))

    print("\n2b — four values the project already holds")
    identity(s, "set_video", "Video Properties",
             "an opacity of 1, which is what the clip already has",
             clips=[clip], patch={"opacity": 1.0})
    identity(s, "set_clip", "Clip Properties",
             "the name the clip was just given", clips=[clip], patch={"name": "Marker"})
    identity(s, "set_canvas", "Canvas",
             "the canvas size and rate the project was made with",
             width=CANVAS[0], height=CANVAS[1], fps=FPS)
    identity(s, "split", "Split",
             "a split at a clip's own start, where there is nothing to cut",
             clips=[clip], at=0)

    print("\n2c — and not one of them was an undo step")
    undo_claim(s, start)
    landed("…the marker edit itself is gone, so the undo above undid THAT and nothing "
           "else", s.clip(clip)["name"], None)


# ---- a call that carries several ops --------------------------------------


def several_ops(mcp):
    """A call that groups several ops, and what its answer is about.

    `normalize_clip` is the tool that sends one op PER CLIP — a `set_audio`
    carrying the gain measured for that clip — so it is where the fold over a
    list is observable from outside the app. Three properties of that fold
    are what the sections above rest on:

      * a later op still runs after an earlier identity, so a call is not
        lost because its first step happened to change nothing;
      * the answer is an identity only when EVERY op was one;
      * and a refusal is answered only when nothing applied at all, naming
        the op it came from.

    **The third has no fixture here, and that is a fact about the tools
    rather than an omission.** Only three tools send a list — this one,
    `import_captions` and `consolidate_media` — and none can send one where
    nothing applied and something was refused: a `set_audio` of a measured
    gain has no rule to decline it, `CaptionLayout` probes its own batch and
    refuses app-side before the shared reply is reached
    (`CaptionLayout.LayoutError.refused`), and `consolidate_media`
    short-circuits an empty plan. The naming itself is proved in §1, which
    goes through the same one format string. When a tool gains such a list,
    its fixture goes here."""
    print("\n3 — a call that carries several ops")
    s = Session(mcp, "refusal-several")
    media = s.peaked("AV.mov")
    first = s.place(media, 0)
    second = s.place(media, 5 * SEC)

    print("\n3a — two clips, two ops, and something changed")
    applied(s, "normalize_clip", "normalising both is one call that applied",
            clips=[first, second])
    volume = s.clip(first)["audio"]["volume"]
    check(volume > 1.0 and s.clip(second)["audio"]["volume"] == volume,
          f"…and both clips carry the same measured volume ({volume})")

    print("\n3b — the same call again is a list of two identities, and says so")
    identity(s, "normalize_clip", "Normalize",
             "every op in the list changed nothing, so the CALL changed nothing",
             clips=[first, second])

    print("\n3c — a later op still runs after an earlier identity")
    s.op("undo")
    landed("one undo puts both volumes back, so the two ops were ONE undo step",
           [s.clip(first)["audio"]["volume"], s.clip(second)["audio"]["volume"]], [1.0, 1.0])
    s.op("normalize_clip", clips=[first])
    landed("normalising the first clip alone applies", s.clip(first)["audio"]["volume"],
           volume)
    applied(s, "normalize_clip",
            "…and a call naming BOTH is not refused although its first op is now an "
            "identity", clips=[first, second])
    landed("…because the second op still ran", s.clip(second)["audio"]["volume"], volume)


# ---- the rules D2·3 gave words to (kpgalligan/reelcut#11) ----------------
#
# Five rules, five sections, each shaped like `overlap_rule`. Four checks in
# them used to be scored by a `shadowed` helper rather than by `refused`,
# because an app-side guard asked the same question one step earlier and
# answered in its own words: §5d, §6b, §7b and §7d. D2·4
# (kpgalligan/reelcut#12) deleted those guards — two `with_clips` counts and
# a trial-apply — and all four are `refused` now, against the CORE's
# sentence, which is what that ticket's third criterion asks for. The
# helper went with them; the sentences it used to assert are in road map 7
# §5.4's "what went" table, which is where the old answers stay on record
# (§5.3's table is the CORE's sentences, which is a different list).


def locked_track(mcp):
    """A locked track, at the two ops that reach the core with one.

    The rule: `close_gap` and `insert_clip` both have to MOVE what is on the
    destination track, and a lock is exactly the promise that nothing there
    moves, so both refuse up front rather than by collision
    (`core/src/edit_time.rs`'s `locked_track`, which writes the sentence once
    for all three of its callers). What a caller acts on is the track id in
    it: unlock that track, not move the clip.

    The third caller, a RIPPLED `add_transition`, is section 7's — §7d,
    where the trial-apply that used to answer over it is gone.

    The fixture is two ten-second clips with a ten-second gap between them,
    so `close_gap` has a real gap to be stopped from closing: the refusal is
    the lock's and not "there is no gap here", which is a different sentence
    (spec §11 #88) and is scored below."""
    print("\n4 — a locked track says which track is locked")
    s = Session(mcp, "refusal-locked")
    media = s.media("A.mov")
    track = s.project()["tracks"][0]["id"]
    a = s.place(media, 0)
    b = s.place(media, 20 * SEC)
    landed("the fixture is two ten-second clips with a ten-second gap between them",
           [[c["start"], c["duration"]] for c in s.project()["clips"]],
           [[0, 10 * SEC], [20 * SEC, 10 * SEC]])

    print("\n4a — a real edit, whose undo step every answer below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[a], patch={"name": "Marker"}))

    print("\n4b — the lock goes on, and both ops name it")
    s.op("set_track", track=track, locked=True)
    refused(s, "close_gap", "close_gap",
            "a gap that is really there, on a track that may not move",
            f"track {track} is locked, so the gap on it cannot be closed",
            track=track, at=15 * SEC)
    refused(s, "insert_clip", "insert_clip",
            "an insert onto the same track, with room to spare",
            f"track {track} is locked, so an insert cannot open room on it",
            track=track, media=media, at=40 * SEC)

    print("\n4c — the lock comes off, and the same call lands")
    # Undone rather than set back, so the only edit left on the stack above
    # the marker is the one 4c makes and undoes itself.
    s.op("undo")
    applied(s, "close_gap", "the gap closes once the track is unlocked",
            track=track, at=15 * SEC)
    landed("…and the later clip moved to the gap's start, so that was the whole edit",
           s.clip(b)["start"], 10 * SEC)
    s.op("undo")
    landed("…undone again, so the fixture is back where 4b found it",
           s.clip(b)["start"], 20 * SEC)

    print("\n4d — and a gap that is not there is a different sentence, not this rule")
    # The distinction at one op: same tool, same track, two different
    # sentences — the lock's, and the one naming the clip under `at`
    # (spec §11 #88; this row scored an identity before it).
    refused(s, "close_gap", "close_gap",
            "a time that is ON a clip names the clip, not the lock",
            f"clip {a} runs from 0 to {10 * SEC} on track {track}, so {1 * SEC} is not "
            "in a gap",
            track=track, at=1 * SEC)

    print("\n4e — and not one of them was an undo step")
    undo_claim(s, start)


def the_track_stack(mcp):
    """The last track in a project, and the track that still holds clips.

    Two refusals in one op, and the order between them matters: the
    last-track one is asked FIRST, because `with_clips: true` is the way past
    the other and past this one it is not. A caller told about the clips
    would send it and be refused again.

    Both reach the core over MCP since D2·4. `AgentServer+Tracks.swift` used
    to ask "does this track still hold clips" before the core did and to
    answer in its own words; §5d is where that guard was, and §5e sends the
    argument its replacement names."""
    print("\n5 — the track stack: the last track, and the one still holding clips")
    s = Session(mcp, "refusal-tracks")
    media = s.media("A.mov")
    first = s.project()["tracks"][0]["id"]
    landed("a new project has exactly one track", len(s.project()["tracks"]), 1)

    print("\n5a — the only track in the project, with nothing on it at all")
    # No clips, so the app's own guard is not in the way and the call
    # reaches the core. `with_clips: true` is sent as well, because the
    # sentence has to be the same either way: that flag is the way past the
    # OTHER refusal and not past this one.
    refused(s, "remove_track", "remove_track",
            "removing the only track a project has",
            f"track {first} is the only track left, and a project must always have one",
            track=first)
    refused(s, "remove_track", "remove_track",
            "…and with_clips: true does not get past it, because this is not that rule",
            f"track {first} is the only track left, and a project must always have one",
            track=first, with_clips=True)

    print("\n5b — a second track, so the rule stops applying")
    # `add_track` takes `index` and `name` and nothing else; the `kind` these
    # calls used to send was dropped in silence until kpgalligan/reelcut#21's
    # gate, which refuses it by name.
    second = s.op("add_track")["new_tracks"][0]
    applied(s, "remove_track", "with two tracks the same call lands", track=second)
    landed("…and the project is back to one track", len(s.project()["tracks"]), 1)

    print("\n5c — a clip and a second track, and then the marker edit")
    # Both are real edits and both are made BEFORE the marker, so 5f's
    # single undo is the marker's and the claim it makes is exact.
    clip = s.place(media, 0)
    s.op("add_track")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[clip], patch={"name": "Marker"}))

    print("\n5d — the other refusal, in the core's words since D2·4")
    # `AgentServer+Tracks.swift` used to count the clips and answer first,
    # naming the track's NAME and a count — 'Track 1 ("Track 1") still holds
    # 1 clip. Pass with_clips: true to remove them too.' That guard is gone,
    # so what arrives is the rule's own sentence, and the id in it is the
    # CLIP a caller has to deal with rather than a number it has to go and
    # look up. `clip_list`'s singular arm is what writes "clip N".
    refused(s, "remove_track", "remove_track",
            "a track that still holds clips names the clip, not a count",
            f"track {first} still holds clip {clip}; pass with_clips: true to remove the "
            "track and its clips",
            track=first)

    print("\n5e — and the argument that sentence names is the way past it")
    applied(s, "remove_track", "with_clips: true removes the track and its clip",
            track=first, with_clips=True)
    landed("…and the clip went with the track",
           [c["id"] for c in s.project()["clips"]], [])

    print("\n5f — and not one of the refusals was an undo step")
    s.op("undo")                   # the removal, which WAS a real edit
    undo_claim(s, start)


def the_media_list(mcp):
    """A media row a clip still shows.

    The core's rule: a media entry cannot go while any clip anywhere in the
    document still shows it, because the model has no "missing on purpose"
    state and a clip pointing at an id that is gone is what `validate`
    rejects. Since D2·3 it says so naming the clips and the argument that
    would let it through.

    That is what arrives since D2·4. `AgentServer+Media.swift` used to ask
    the same question first through `MediaUsage` — which walks the nests,
    the fix phase 8 made — and to answer naming the FILE and a count, the
    better sentence for a person and the worse one for a caller that has to
    name a clip. The guard is gone and the core's sentence is what this
    section asserts; the Media tab's ALERT still asks it, which is the place
    a person reads a file name (`MediaPaneCommands.swift`).
    `phase8_proof.py` §2 is the other half of this and moved with it: its
    both-levels check now reads the core's clip ids rather than a count."""
    print("\n6 — a media row a clip still shows")
    s = Session(mcp, "refusal-media")
    media = s.media("A.mov")
    spare = s.media("B.mov")       # imported before the marker: 6d undoes ONE edit
    clip = s.place(media, 0)

    print("\n6a — a real edit, whose undo step the answers below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[clip], patch={"name": "Marker"}))

    print("\n6b — the core's own sentence, naming the clip and the way past it")
    # The guard `AgentServer+Media.swift` used to answer with said
    # "A.mov is used by 1 clip. Pass with_clips: true to remove them too."
    # — the file, and a count. What a caller acts on is the clip id.
    refused(s, "remove_media", "remove_media",
            "a media one clip still shows names that clip",
            f"media {media} is still used by clip {clip}; pass with_clips: true to remove "
            "the media and its clips",
            media=media)

    print("\n6c — the boundary: an unused row goes with no argument at all")
    applied(s, "remove_media", "a media in nobody's use is removed as it asks",
            media=spare)
    landed("…and the media list is back to the one file the clip shows",
           [m["id"] for m in s.project()["media"]], [media])

    print("\n6d — and neither answer was an undo step")
    s.op("undo")                   # the removal of B.mov, which WAS a real edit
    undo_claim(s, start)


def the_transition_cut(mcp):
    """A cut with no unused material left to give a transition.

    The core's rule, and the one with the most arithmetic behind it: an
    overlap at a hard cut is built out of the two clips' unused source — the
    frames after the outgoing clip's out point and before the incoming
    clip's in point — clamped again by the neighbours on the track and by
    the overlap rule. When all of that leaves nothing, the core now says how
    many frames were asked for and names `ripple: true`, the way that needs
    no handles at all.

    Until D2·4 `AgentServer+Transitions.swift` trial-applied the op and
    wrote two sentences of its own, one per form, because `.project == nil`
    was all it could see and the shared reply used to be the overlap rule's
    paragraph. The trial is deleted, so both forms answer in the core's
    words, and the two numbers below — 15 frames, and the locked track's id
    — are what the app could never have said.

    The fixture is section 1's — two abutting ten-second clips, each showing
    the whole of a ten-second file, so neither side has one frame to give."""
    print("\n7 — a cut with nothing left to give a transition")
    s = Session(mcp, "refusal-transition")
    media = s.media("A.mov")
    a = s.place(media, 0)
    b = s.place(media, 10 * SEC)
    landed("the fixture is two abutting clips, each showing its whole file",
           [[c["start"], c["duration"]] for c in s.project()["clips"]],
           [[0, 10 * SEC], [10 * SEC, 10 * SEC]])

    print("\n7a — a real edit, whose undo step the answers below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[a], patch={"name": "Marker"}))

    print("\n7b — the handle form, in the core's words")
    # The request in whole FRAMES is what the sentence names, because that
    # is the unit every clamp above it is measured in: half a second at 30
    # fps is 15 frames, hand-computed here and not read back off anything.
    frames = (SEC // 2) // FRAME
    landed("half a second is fifteen frames on this project's grid", frames, 15)
    refused(s, "add_transition", "add_transition",
            "a cut whose two clips have no unused material names the frames asked for",
            f"the cut before clip {b} has no room for an overlap: the {frames} frames "
            "asked for clamp to nothing against the two clips' unused material, their "
            "neighbours and the overlap rule; pass ripple: true to make the overlap by "
            "shifting the timeline left instead",
            clip=b, duration=SEC // 2)

    print("\n7c — and the rippled form, which has somewhere to go")
    # The same cut with `ripple: true` LANDS here: nothing is read out of
    # the source, the incoming clip simply slides left. That is what makes
    # 7b's sentence about the material and not about the cut.
    applied(s, "add_transition", "the same cut takes a rippled transition",
            clip=b, duration=SEC // 2, ripple=True)
    landed("…and the incoming clip slid left by exactly the overlap asked for",
           s.clip(b)["start"], 10 * SEC - SEC // 2)
    s.op("undo")

    print("\n7d — a LOCKED track is where the rippled form has nowhere to go")
    # `locked_track`'s third caller, the one §4 could not reach: the app's
    # trial-apply used to answer here with a sentence offering all three
    # reasons the shift can clamp to nothing ("the incoming clip's track is
    # locked, a clip is too short …, or sliding a clip on another track …").
    # The core knows WHICH, and names the track to unlock and the clip that
    # cannot move.
    track = s.project()["tracks"][0]["id"]
    s.op("set_track", track=track, locked=True)
    refused(s, "add_transition", "add_transition",
            "a rippled transition on a locked track names the track and the clip",
            f"track {track} is locked, so clip {b} cannot be shifted left to make the "
            "overlap",
            clip=b, duration=SEC // 2, ripple=True)
    s.op("undo")                   # the lock, which WAS a real edit

    print("\n7e — and not one of them was an undo step")
    undo_claim(s, start)


def the_action_rules(mcp):
    """An action that would overlap another, or run past its clip.

    Two refusals stated in one doc sentence, at two ops each, and both reach
    the core over MCP with nothing in the way. Actions on a clip may not
    overlap (spec §5.4) and an action is a span of CLIP time that has to fit
    inside it; what a caller acts on is in both sentences — which action is
    in the way and where it runs, or where the action it asked for would end
    against where the clip does.

    Every number below is hand-computed from a ten-second clip on a 30 fps
    canvas: 600 000 ticks to the second, 20 000 to the frame."""
    print("\n8 — an action that would overlap another, or run past its clip")
    s = Session(mcp, "refusal-actions")
    media = s.media("A.mov")
    clip = s.place(media, 0)
    landed("the fixture is one ten-second clip", s.clip(clip)["duration"], 10 * SEC)
    first = s.op("add_action", clip=clip, at=0, duration=2 * SEC)["new_actions"][0]
    second = s.op("add_action", clip=clip, at=4 * SEC, duration=SEC)["new_actions"][0]

    print("\n8a — a real edit, whose undo step every answer below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[clip], patch={"name": "Marker"}))

    print("\n8b — a second action inside the first, at both ops")
    refused(s, "add_action", "add_action",
            "an action that would start inside the one already there",
            f"action {first} on clip {clip} already runs from 0 to {2 * SEC} ticks, and "
            "two actions on one clip may not overlap",
            clip=clip, at=SEC, duration=SEC)
    refused(s, "set_action", "set_action",
            "…and the same words when an EXISTING action is dragged back onto it",
            f"action {first} on clip {clip} already runs from 0 to {2 * SEC} ticks, and "
            "two actions on one clip may not overlap",
            clip=clip, action=second, start=SEC)

    print("\n8c — the boundary: an action that starts exactly where the other ends")
    applied(s, "set_action", "abutting is not overlapping, so the same drag one tick "
            "later lands", clip=clip, action=second, start=2 * SEC)
    landed("…and it LANDED at the tick asked for",
           [a["start"] for a in s.clip(clip)["actions"] if a["id"] == second], [2 * SEC])
    s.op("undo")

    print("\n8d — an action that would run past the clip's own end, at both ops")
    refused(s, "add_action", "add_action",
            "an action whose span would end past the clip",
            f"an action of {2 * SEC} ticks at {9 * SEC} would end at {11 * SEC}, past "
            f"clip {clip}'s own end at {10 * SEC} ticks",
            clip=clip, at=9 * SEC, duration=2 * SEC)
    refused(s, "set_action", "set_action",
            "…and the same when an existing action is stretched past it",
            f"an action of {12 * SEC} ticks at 0 would end at {12 * SEC}, past clip "
            f"{clip}'s own end at {10 * SEC} ticks",
            clip=clip, action=first, duration=12 * SEC)

    print("\n8e — the boundary: an action that ends exactly at the clip's end")
    applied(s, "add_action", "an action ending exactly at the clip's end lands",
            clip=clip, at=9 * SEC, duration=SEC)
    s.op("undo")

    print("\n8f — and not one of them was an undo step")
    undo_claim(s, start)


def off_the_track_stack(mcp):
    """A move to a track index the document has not got.

    The smallest of the rules and the one whose silence was the plainest
    contradiction: the comment beside it has read "a selection dragged off
    either end of the track list is a refusal, not a clamp" since it was
    written, and the line under it answered an identity. It says the index
    now, in `move_track`'s own words for the same mistake.

    A selection spanning two tracks is what reaches it: the whole selection
    moves by the index offset of its FIRST clip (by track order), so a
    two-track selection moved to the front-most track puts its second clip
    one past the end."""
    print("\n9 — a move to a track index the document has not got")
    s = Session(mcp, "refusal-stack")
    media = s.media("A.mov")
    lower = s.op("add_track")["new_tracks"][0]
    upper = s.op("add_track")["new_tracks"][0]
    landed("three tracks, indices 0 to 2", len(s.project()["tracks"]), 3)
    a = s.place(media, 0, track=lower)
    b = s.place(media, 0, track=upper)

    print("\n9a — a real edit, whose undo step the answer below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[a], patch={"name": "Marker"}))

    print("\n9b — a two-track selection moved one track too far")
    # Clip a is on index 1 and clip b on index 2; the anchor is the lower of
    # the two, so moving to index 2 moves BOTH up one and b would land on
    # index 3, which is one past the end of a three-track stack.
    refused(s, "move_clip", "move_clip",
            "the clip that would go off the top of the stack is the one named",
            f"clip {b} would land on track index 3, which is out of range (0..3)",
            clips=[a, b], delta=0, track=upper)

    print("\n9c — the boundary: the same move one track lower lands")
    applied(s, "move_clip", "a move onto a track the stack HAS applies",
            clips=[a], delta=10 * SEC, track=upper)
    landed("…and it landed on that track, at the tick the delta asks for",
           [s.clip(a)["track"], s.clip(a)["start"]], [upper, 10 * SEC])
    s.op("undo")

    print("\n9d — and it was not an undo step")
    undo_claim(s, start)


def the_non_edits_that_speak(mcp):
    """The non-edits a rule declined, each in its own sentence (spec §11 #88).

    Until #88 each of these answered the IDENTITY, which says only that the
    project is already in that state — true, and no help to a caller who
    aimed at a cut, a gap or a clip's audio that is not there. Now each names
    the value: the track and the start with no cut before them, the first
    clip of a track, the overlap limit a transition may have (and sending it
    LANDS), the track with nothing after `at`, and why a clip has no audio to
    detach — not media, media with no audio (`A.mov`), or audio already
    detached (`AV.mov`, after one detach that applied).

    The fixture: A.mov (ten seconds, no audio) at 0 and at 12 s on the
    bottom track, so there is a two-second gap and not a cut in front of the
    second; on a track above, a one-second text clip at 0 and AV.mov (five
    seconds, with audio) at 30 s, whose detached twin lands on the bottom
    track clear of both."""
    print("\n10 — the non-edits that speak")
    s = Session(mcp, "refusal-non-edits")
    silent = s.media("A.mov")
    sound = s.media("AV.mov")
    track = s.project()["tracks"][0]["id"]
    upper = s.op("add_track")["new_tracks"][0]
    a = s.place(silent, 0)
    b = s.place(silent, 12 * SEC)
    t = s.op("add_text_clip", track=upper, at=0, duration=SEC)["new_clips"][0]
    c = s.place(sound, 30 * SEC, track=upper)
    landed("the fixture: two ten-second clips with a gap, a text clip and a five-second one",
           [[x["id"], x["start"], x["duration"]] for x in s.project()["clips"]],
           [[a, 0, 10 * SEC], [b, 12 * SEC, 10 * SEC], [t, 0, SEC], [c, 30 * SEC, 5 * SEC]])

    print("\n10a — a real edit, whose undo step the answers below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[a], patch={"name": "Marker"}))

    print("\n10b — a roll with no cut in front of the clip")
    refused(s, "roll", "roll",
            "a roll across a gap names the track and where the clip begins",
            f"no clip on track {track} ends where clip {b} begins ({12 * SEC}), so there is "
            "no cut to roll",
            clip=b, to=11 * SEC)

    print("\n10c — a transition length with nothing before the clip, or past the limit")
    refused(s, "set_transition_duration", "set_transition_duration",
            "the first clip on a track has nothing to overlap",
            f"clip {a} is the first clip on track {track}, so there is no clip before it to "
            "overlap",
            clip=a, duration=SEC)
    # clip a ends at 10 s, so twelve seconds of overlap would start clip b
    # at -2 s; half the shorter clip is five seconds, on the grid already.
    refused(s, "set_transition_duration", "set_transition_duration",
            "an overlap that would start the clip before the timeline names the limit",
            f"clip {b} would start at {-2 * SEC}, before the timeline, to overlap clip {a} by "
            f"{12 * SEC} ticks; the two can overlap by at most {5 * SEC} ticks",
            clip=b, duration=12 * SEC)
    applied(s, "set_transition_duration", "…and the limit it names, sent back, lands",
            clip=b, duration=5 * SEC)
    landed("…with clip b five seconds before clip a's end", s.clip(b)["start"], 5 * SEC)
    s.op("undo")

    print("\n10d — a gap with nothing after it")
    refused(s, "close_gap", "close_gap",
            "a time past the track's last clip names the track and the time",
            f"no clip on track {track} starts after {25 * SEC}, so there is no gap to close",
            track=track, at=25 * SEC)

    print("\n10e — detach_audio with nothing to detach, three ways")
    refused(s, "detach_audio", "detach_audio",
            "a text clip is not media",
            f"clip {t} has no audio to detach: it is not a media clip",
            clip=t)
    refused(s, "detach_audio", "detach_audio",
            "A.mov has no audio track",
            f"clip {a} has no audio to detach: media {silent} has no audio track",
            clip=a)
    applied(s, "detach_audio", "AV.mov's audio detaches", clip=c)
    landed("…and the original's audio is switched off",
           s.clip(c)["enabled"]["audio"], False)
    refused(s, "detach_audio", "detach_audio",
            "a second detach names the audio already switched off",
            f"clip {c} has no audio to detach: its audio is switched off",
            clip=c)
    s.op("undo")
    landed("…and one undo puts the audio back, so the refusal was not a step",
           [s.clip(c)["enabled"]["audio"], len(s.project()["clips"])], [True, 4])

    print("\n10f — and not one of them was an undo step")
    undo_claim(s, start)


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


SOCKET = target(sys.argv)


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(SOCKET)
    print(f"what an op answers, against {SOCKET}")
    overlap_rule(mcp)
    identity_says_only_that(mcp)
    several_ops(mcp)
    locked_track(mcp)
    the_track_stack(mcp)
    the_media_list(mcp)
    the_transition_cut(mcp)
    the_action_rules(mcp)
    off_the_track_stack(mcp)
    the_non_edits_that_speak(mcp)
    summary()


# ---- the next rule's section goes here ------------------------------------
#
# Sections 4 to 9 are D2·3's (kpgalligan/reelcut#11) and section 10 is
# spec §11 #88's, and the shape has not changed: a fixture whose numbers are
# hand-computed, a marker edit, the refusals with their WHOLE sentences, a
# boundary that LANDS, and one `undo` closing the batch.
# `Outcome::Identity`'s doc in `core/src/outcome.rs` is the list of which
# rules can say why and which stay identities on purpose.
#
# Every rule that speaks is now measured HERE as well as in
# `core/tests/refusal.rs`: D2·4 (kpgalligan/reelcut#12) deleted the four
# app-side answers that stood in front of §5d, §6b, §7b and §7d, and there
# is no `shadowed` helper any more. The clamped-edge family in
# `Outcome::Identity`'s doc stays an identity (spec §5.5, §11 #88); a rule
# that finds its voice later gets its section here.

if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, IndexError, KeyError, RuntimeError, OSError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
