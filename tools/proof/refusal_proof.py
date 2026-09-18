"""WHAT AN OP ANSWERS, driven against the built binary over MCP.

Named for the seam and not for a phase, as `patch_door_proof.py` is: what it
proves is the answer every edit comes back with (`core/src/outcome.rs`,
`app/Sources/ReelEdit.swift`, `CONTEXT.md`'s **Op**), and the rules that can
say why arrive one deepening ticket at a time
(`designs/reelcut-roadmap-7.md` §4, kpgalligan/reelcut#8). Deepening D2·2
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

    python3 tools/proof/refusal_proof.py <port>
"""

import json
import os
import re
import shutil
import sys
import time

from mcp import MCP, ToolError

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


PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4823


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)
    print(f"what an op answers, against 127.0.0.1:{PORT}")
    overlap_rule(mcp)
    identity_says_only_that(mcp)
    several_ops(mcp)
    summary()


# ---- the next rule's section goes here ------------------------------------
#
# D2·3 (kpgalligan/reelcut#11) gives the remaining rules their sentences — a
# locked track, the last track, a media row a clip still shows, a cut with
# nothing left to give a transition, and an action that would overlap
# another. Each is a function shaped like `overlap_rule` above: the fixture,
# a marker edit, the refusals with their WHOLE sentences, and one `undo`
# closing the batch. `Outcome::Identity`'s doc in `core/src/outcome.rs` is
# the list of which rules are still owed one.

if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, IndexError, KeyError, RuntimeError, OSError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
