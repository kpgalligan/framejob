"""Road map 2, phase 1 — the proof, driven against the built binary over MCP.

Every claim is checked by comparing `render_frame` PNGs byte for byte, or by
reading placements back out of `get_project`. Nothing here reads the source.
"""

import hashlib
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
FRAME = 20_000

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


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


class Session:
    """One project, with frame rendering reduced to a hash."""

    def __init__(self, mcp, name):
        self.mcp = mcp
        self.path = os.path.join(WORK, f"{name}.reelcut")
        if os.path.exists(self.path):
            shutil.rmtree(self.path)
        mcp.call("new_project", path=self.path)
        self.mcp.call("set_canvas", project=self.path, width=640, height=360)

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def frame(self, t):
        """The hash of the PNG `render_frame` wrote — the tool answers with a
        sentence naming the file, so the path is read out of it."""
        answer = self.op("render_frame", t=int(t))
        found = re.search(r"Written to (\S+\.png)\.", str(answer))
        assert found, f"render_frame said something else: {answer}"
        return digest(found.group(1))

    def project(self):
        return self.op("get_project")["project"]

    def clips(self):
        return {c["id"]: c for c in self.project()["clips"]}

    def place(self, track, media, at):
        return self.op("add_clip", track=track, media=media, at=int(at))["new_clips"][0]

    def media(self, name):
        return self.op("import_media", path=os.path.join(MEDIA, name))["media"]

    def refuses(self, tool, **kwargs):
        """A documented refusal comes back as an in-band error whose message
        begins "<Op> made no change" — the app's wording for the core's
        `Ok(None)`, which registers no undo step."""
        try:
            self.op(tool, **kwargs)
            return False
        except ToolError as error:
            return "made no change" in str(error)


def placement(clips, clip):
    return (clips[clip]["start"], clips[clip]["duration"])


def source_in(clips, clip):
    return clips[clip]["source"]["in"]


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)

    names = mcp.tools()
    # A floor, not the count: phase 1 found 63, and every later phase adds
    # tools. The exact count is the NEWEST phase's script's to assert.
    check(len(names) >= 63, f"the catalog holds phase 1's 63 tools or more (got {len(names)})")
    for tool in ["slip", "roll", "lift_range", "close_gap", "insert_clip", "overwrite_clip"]:
        check(tool in names, f"{tool} is a tool")

    # ---- slip -----------------------------------------------------------
    print("\nslip")
    s = Session(mcp, "slip")
    a_id = s.media("A.mov")
    track = s.project()["tracks"][0]["id"]
    a = s.place(track, a_id, 0)
    s.op("trim_end", clip=a, to=6 * SEC)

    at3 = s.frame(3 * SEC)
    at5 = s.frame(5 * SEC)
    check(at3 != at5, "the test card differs between source 3 s and 5 s")

    s.op("slip", clip=a, delta=2 * SEC)
    clips = s.clips()
    check(placement(clips, a) == (0, 6 * SEC), "a slip does not move the clip")
    check(source_in(clips, a) == 2 * SEC, "the source in point advanced by the delta")
    check(s.frame(3 * SEC) == at5, "the frame at 3 s is now the one that was at 5 s")

    s.op("slip", clip=a, delta=-2 * SEC)
    check(s.frame(3 * SEC) == at3, "slip there and back is the identity, frame for frame")

    # The clamps, both ends. The clip is 6 s of a 10 s media, so the window
    # can travel exactly 4 s.
    s.op("slip", clip=a, delta=100 * SEC)
    check(source_in(s.clips(), a) == 4 * SEC, "a slip past the tail stops where the media ends")
    check(
        s.refuses("slip", clip=a, delta=2 * SEC),
        "a slip with nowhere to go reports no change rather than an edit",
    )
    s.op("slip", clip=a, delta=-100 * SEC)
    check(source_in(s.clips(), a) == 0, "and past the head it stops at 0")
    check(s.frame(3 * SEC) == at3, "back at the head, the frame is the one it started with")
    s.op("undo")
    check(source_in(s.clips(), a) == 4 * SEC, "undo restores the in point; a slip is one step")

    # ---- roll -----------------------------------------------------------
    print("\nroll")
    s = Session(mcp, "roll")
    a_id = s.media("A.mov")
    b_id = s.media("B.mov")
    track = s.project()["tracks"][0]["id"]
    a = s.place(track, a_id, 0)
    s.op("trim_end", clip=a, to=6 * SEC)
    b = s.place(track, b_id, 6 * SEC)
    s.op("trim_start", clip=b, to=8 * SEC)
    s.op("move_clip", clips=[b], delta=-2 * SEC)
    clips = s.clips()
    check(placement(clips, a) == (0, 6 * SEC), "A runs 0 – 6 s")
    check(placement(clips, b) == (6 * SEC, 8 * SEC), "B runs 6 – 14 s")
    check(source_in(clips, b) == 2 * SEC, "B has two seconds of head to give")

    inside_a = s.frame(6 * SEC - FRAME)
    across = s.frame(8 * SEC - FRAME)
    inside_b = s.frame(8 * SEC)

    s.op("roll", clip=b, to=8 * SEC)
    clips = s.clips()
    check(placement(clips, a) == (0, 8 * SEC), "the predecessor grew to the new cut")
    check(placement(clips, b) == (8 * SEC, 6 * SEC), "the clip gave up what the other took")
    check(source_in(clips, b) == 4 * SEC, "the in point followed the cut (front trim)")
    check(
        clips[a]["start"] == 0
        and clips[b]["start"] + clips[b]["duration"] == 14 * SEC,
        "the pair's outer edges did not move",
    )
    check(
        clips[a]["duration"] + clips[b]["duration"] == 14 * SEC,
        "the pair's total duration is unchanged",
    )
    check(s.frame(6 * SEC - FRAME) == inside_a, "the film under A did not move")
    check(s.frame(8 * SEC) == inside_b, "the film under B did not move")
    check(s.frame(8 * SEC - FRAME) != across, "the cut moved across 8 s − 1 frame")
    s.op("undo")
    check(s.frame(8 * SEC - FRAME) == across, "undo restores the frame; the roll was one step")

    # A roll needs a hard cut.
    s.op("move_clip", clips=[b], delta=2 * SEC)  # open a gap
    check(s.refuses("roll", clip=b, to=7 * SEC), "a roll across a gap changes nothing")
    s.op("undo")

    # ---- lift, and how it differs from a ripple --------------------------
    print("\nlift_range")
    s = Session(mcp, "lift")
    a_id = s.media("A.mov")
    b_id = s.media("B.mov")
    track = s.project()["tracks"][0]["id"]
    a = s.place(track, a_id, 0)
    s.op("trim_end", clip=a, to=4 * SEC)
    b = s.place(track, b_id, 4 * SEC)
    # A short clip far to the right, so a time in the middle of nothing is
    # still INSIDE the timeline and renders the canvas background rather
    # than erroring off the end.
    s.place(track, a_id, 20 * SEC)
    at5 = s.frame(5 * SEC)
    background = s.frame(15 * SEC)  # a gap that was always a gap

    s.op("lift_range", **{"from": 2 * SEC, "to": 3 * SEC})
    clips = s.clips()
    check(placement(clips, a) == (0, 2 * SEC), "the range came out of A")
    check(placement(clips, b) == (4 * SEC, 10 * SEC), "the clip after the range did not move")
    check(s.frame(2 * SEC + FRAME) == background, "the range renders as the background")
    check(s.frame(5 * SEC) == at5, "the frame after the range is unchanged, byte for byte")
    lifted = {cid: placement(clips, cid) for cid in clips}

    s.op("undo")
    s.op("ripple_delete_range", **{"from": 2 * SEC, "to": 3 * SEC})
    rippled = {cid: placement(s.clips(), cid) for cid in s.clips()}
    check(lifted != rippled, "a lift and a ripple of the same range differ")
    check(
        s.clips()[b]["start"] == 3 * SEC,
        "the ripple closed the hole the lift left open",
    )
    s.op("undo")

    # ---- close_gap ------------------------------------------------------
    print("\nclose_gap")
    s = Session(mcp, "gap")
    a_id = s.media("A.mov")
    c_id = s.media("C.mov")
    picture = s.project()["tracks"][0]["id"]
    s.op("add_track", index=1)
    bed = [t["id"] for t in s.project()["tracks"]][1]
    a = s.place(picture, a_id, 0)
    s.op("trim_end", clip=a, to=2 * SEC)
    later = s.place(picture, a_id, 6 * SEC)
    s.op("trim_end", clip=later, to=8 * SEC)
    locked = s.place(bed, c_id, 10 * SEC)
    s.op("set_track", track=bed, locked=True)

    before = {cid: placement(s.clips(), cid) for cid in s.clips()}
    s.op("close_gap", track=picture, at=4 * SEC)
    clips = s.clips()
    check(placement(clips, a) == (0, 2 * SEC), "the clip before the gap did not move")
    check(placement(clips, later) == (2 * SEC, 2 * SEC), "the next clip moved to the gap's start")
    check(
        placement(clips, locked) == before[locked],
        "a locked track's clips did not move",
    )
    check(s.refuses("close_gap", track=picture, at=4 * SEC), "there is no gap left to close")
    check(s.refuses("close_gap", track=picture, at=SEC), "a time on a clip is not in a gap")
    check(s.refuses("close_gap", track=bed, at=5 * SEC), "a locked track refuses")
    check(
        s.refuses("insert_clip", track=bed, media=c_id, at=20 * SEC),
        "and a locked track refuses an insert with room to spare",
    )
    s.op("undo")
    check(
        {cid: placement(s.clips(), cid) for cid in s.clips()} == before,
        "undo restores every placement; the close was one step",
    )

    # ---- insert_clip ----------------------------------------------------
    print("\ninsert_clip")
    s = Session(mcp, "insert")
    a_id = s.media("A.mov")
    b_id = s.media("B.mov")
    picture = s.project()["tracks"][0]["id"]
    s.op("add_track", index=1)
    bed = [t["id"] for t in s.project()["tracks"]][1]
    a = s.place(picture, a_id, 0)
    # The bed carries a frame-numbered source, not the flat green: a hash of
    # a constant-colour picture is the same at every time, so it could not
    # tell a shifted clip from an unshifted one.
    c = s.place(bed, b_id, 12 * SEC)

    at4 = s.frame(4 * SEC)
    at13 = s.frame(13 * SEC)
    before = {cid: placement(s.clips(), cid) for cid in s.clips()}

    s.op("insert_clip", track=picture, media=b_id, at=4 * SEC)
    clips = s.clips()
    check(placement(clips, a) == (0, 4 * SEC), "the destination clip was cut at the drop")
    tail = [
        cid
        for cid in clips
        if cid not in before and clips[cid]["source"].get("media") == a_id
    ]
    check(len(tail) == 1, "the split left one tail")
    placed = [
        cid
        for cid in clips
        if cid not in before and cid != tail[0] and clips[cid]["source"].get("media") == b_id
    ]
    check(
        len(placed) == 1 and placement(clips, placed[0]) == (4 * SEC, 10 * SEC),
        "the inserted clip is the whole media, in the room that was made",
    )
    check(source_in(clips, placed[0]) == 0, "and it starts at the media's first frame")
    check(
        placement(clips, tail[0]) == (14 * SEC, 6 * SEC),
        "the tail moved right by the whole inserted length",
    )
    check(placement(clips, c) == (22 * SEC, 10 * SEC), "the other track shifted by the same")
    check(s.frame(14 * SEC) == at4, "the frame at at + len is the frame that was at at")
    check(s.frame(23 * SEC) == at13, "and on every track")
    s.op("undo")
    check(
        {cid: placement(s.clips(), cid) for cid in s.clips()} == before
        and s.frame(4 * SEC) == at4,
        "undo restores the timeline; the insert was one step",
    )

    # A straddler on ANOTHER track rides the shift whole.
    straddler = s.place(bed, a_id, 2 * SEC)
    s.op("insert_clip", track=picture, media=b_id, at=4 * SEC)
    check(
        placement(s.clips(), straddler) == (2 * SEC, 10 * SEC),
        "a straddler on another track is neither cut nor moved",
    )
    s.op("undo")

    # ---- overwrite_clip -------------------------------------------------
    print("\noverwrite_clip")
    s = Session(mcp, "overwrite")
    a_id = s.media("A.mov")
    b_id = s.media("B.mov")
    picture = s.project()["tracks"][0]["id"]
    s.op("add_track", index=1)
    bed = [t["id"] for t in s.project()["tracks"]][1]
    a = s.place(picture, a_id, 0)
    c = s.place(bed, b_id, 16 * SEC)

    at2 = s.frame(2 * SEC)
    at5 = s.frame(5 * SEC)
    at17 = s.frame(17 * SEC)
    before = {cid: placement(s.clips(), cid) for cid in s.clips()}

    s.op("overwrite_clip", track=picture, media=b_id, at=4 * SEC)
    clips = s.clips()
    check(placement(clips, a) == (0, 4 * SEC), "the head survived")
    placed = [
        cid
        for cid in clips
        if cid not in before and clips[cid]["source"].get("media") == b_id
    ]
    check(
        len(placed) == 1 and placement(clips, placed[0]) == (4 * SEC, 10 * SEC),
        "the new clip fills the span it took",
    )
    check(placement(clips, c) == before[c], "the other track did not move at all")
    check(s.frame(2 * SEC) == at2, "frames before the span are byte-identical")
    check(s.frame(17 * SEC) == at17, "frames outside the span on another track are too")
    check(s.frame(5 * SEC) != at5, "and inside it the new clip is what plays")
    s.op("undo")
    check(
        {cid: placement(s.clips(), cid) for cid in s.clips()} == before
        and s.frame(5 * SEC) == at5,
        "undo restores the timeline; the overwrite was one step",
    )

    # ---- refusals report themselves -------------------------------------
    print("\nerrors")
    for tool, args, needle in [
        ("slip", {"clip": 9999, "delta": SEC}, "No clip has id 9999"),
        ("roll", {"clip": 9999, "to": SEC}, "No clip has id 9999"),
        ("insert_clip", {"track": 9999, "media": b_id, "at": 0}, "No track has id 9999"),
        ("overwrite_clip", {"track": picture, "media": 9999, "at": 0}, "No media has id 9999"),
        ("close_gap", {"track": 9999, "at": 0}, "No track has id 9999"),
    ]:
        try:
            s.op(tool, **args)
            check(False, f"{tool} with a bad id errors")
        except ToolError as error:
            check(needle in str(error), f"{tool}: {needle}")

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    if failures:
        for line in failures:
            print(f"  FAILED: {line}")
        sys.exit(1)


if __name__ == "__main__":
    main()
