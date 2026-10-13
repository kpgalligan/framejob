"""The patch door's caller-authored ARGUMENTS, as against its patches.

`patch_door_proof.py` is the whole of this proof — its docstring says what a
patch means and how a section is built, and its `main` runs these five
sections in order with the rest. They live here because the file they came
out of reached the ~600-line cap with its five patch-op doors in it
(`CLAUDE.md`'s size rule; the harness had already moved to `patch_door.py`),
and because these five are the doors where the caller's object is an
ARGUMENT of an op rather than a property patch:

- `add_text_clip`'s `text` and `add_shape_clip`'s `shape` are a `set_text` /
  `set_shape` patch merged over a preset, so they answer in the patch walk's
  own sentences — which is the point of proving them, since a build that
  checked a vocabulary at `set_text` alone would make the clip here and
  report success.
- `set_canvas`'s `background` and `add_background`'s `color` are colours and
  nothing else, so they answer in the ENVELOPE's sentences
  (`op "set_canvas" is not valid: invalid length 3…`) with the range refusal
  coming from `props_check.rs` under them. They are where "a colour is four
  numbers, neither filled in nor clamped" is proved at an argument.
- `add_zoom_action`'s `region` is the one op argument that is an OBJECT,
  read as a TYPE off the envelope, so a misspelt or missing member is
  named inside the envelope's own sentence. It is where "a region with a
  mistyped member is never read as a region of nothing" is proved.
"""

from patch_door import (
    SEC, Session, check, landed, marker_gone, refused, shown, undo_claim,
    undo_marker,
)


# ---- add_text_clip's `text` (D1·4, kpgalligan/framejob#5) ------------------


def new_text_clip_door(mcp):
    """`add_text_clip`'s `text` — the same patch at the OTHER door.

    It is a `set_text` patch merged over the core's Title preset, so it
    answers in the same words, and the proof of that is what keeps the two
    doors from drifting: a build that checked the vocabulary only in
    `set_text` MAKES the clip here, answers ok, and hands back a typewriter
    nobody asked for. The bare-string shorthand stays (spec #1's Out of
    Scope) — it PRODUCES `{"content": …}`, which is then forwarded, so the
    words land and nothing about the object form is read on the way."""
    print("\n6 — add_text_clip: the text patch answers as set_text's does")
    s = Session(mcp, "patch-door-new-text")
    track = s.project()["tracks"][0]["id"]

    print("\n6a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("add_text_clip", track=track, at=0))

    print("\n6b — a key or a value the vocabulary does not have, refused by path")
    refused(s, "add_text_clip", "a misspelt key in the patch",
            'unknown key "contnt" in a text patch',
            track=track, at=10 * SEC, text={"contnt": "x"})
    refused(s, "add_text_clip", "a misspelt animation kind",
            'bad value at "animation.kind" in a text patch: unknown variant `fade`',
            track=track, at=10 * SEC, text={"content": "Hi", "animation": {"kind": "fade"}})
    refused(s, "add_text_clip", "a misspelt key INSIDE the outline",
            'unknown key "outline.widht" in a text patch',
            track=track, at=10 * SEC, text={"outline": {"widht": 4.0}})
    refused(s, "add_text_clip", "a number where the outline OBJECT belongs",
            'bad value at "outline" in a text patch: expected an object, not 5',
            track=track, at=10 * SEC, text={"outline": 5})
    refused(s, "add_text_clip", "a three-element colour",
            'bad value at "color" in a text patch: invalid length 3',
            track=track, at=10 * SEC, text={"color": [1.0, 0.0, 0.0]})
    refused(s, "add_text_clip", "a text argument that is not an object at all",
            'text patch must be a json object, not 5',
            track=track, at=10 * SEC, text=5)

    print("\n6c — and not one of them was an undo step, or a clip")
    undo_claim(s, start)
    check(len(s.project()["clips"]) == 0,
          "…and after every refusal above the project holds no clip at all")

    print("\n6d — and both documented forms of the argument still land")
    bare = s.op("add_text_clip", track=track, at=0, duration=2 * SEC,
                text="Chapter One")["new_clips"][0]
    landed("the bare-string shorthand creates a clip with those words",
           s.clip(bare)["text"]["content"], "Chapter One")
    whole = s.op("add_text_clip", track=track, at=10 * SEC, duration=2 * SEC,
                 text={"content": "Two", "size": 96.0})["new_clips"][0]
    check(s.clip(whole)["text"]["size"] == 96
          and s.clip(whole)["text"]["align"] == "center",
          "…and an object patch merges over the Title preset, keeping its alignment")


# ---- add_shape_clip's `shape` (D1·4, kpgalligan/framejob#5) ----------------


def new_shape_clip_door(mcp):
    """`add_shape_clip`'s `shape` — the shape patch at the other door.

    The shorthand here is a bare KIND name, and taking the door raw moved
    the one thing it used to judge: an unknown kind was this side's sentence
    listing the four, and is the core's `unknown variant` now, at the path
    the shorthand put it on."""
    print("\n7 — add_shape_clip: the shape patch answers as set_shape's does")
    s = Session(mcp, "patch-door-new-shape")
    track = s.project()["tracks"][0]["id"]

    print("\n7a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("add_shape_clip", track=track, at=0))

    print("\n7b — a key or a value the vocabulary does not have, refused by path")
    refused(s, "add_shape_clip", "a misspelt key in the patch",
            'unknown key "kindd" in a shape patch',
            track=track, at=10 * SEC, shape={"kindd": "rectangle"})
    refused(s, "add_shape_clip", "a bare kind name outside the enum, by its PATH",
            'bad value at "kind" in a shape patch: unknown variant `square`',
            track=track, at=10 * SEC, shape="square")
    refused(s, "add_shape_clip", "a misspelt key INSIDE the stroke",
            'unknown key "stroke.widht" in a shape patch',
            track=track, at=10 * SEC, shape={"stroke": {"widht": 2.0}})
    refused(s, "add_shape_clip", "a number where the stroke OBJECT belongs",
            'bad value at "stroke" in a shape patch: expected an object, not 5',
            track=track, at=10 * SEC, shape={"stroke": 5})
    refused(s, "add_shape_clip", "a three-element stop colour",
            'bad value at "gradient.stops[0].color" in a shape patch: invalid length 3',
            track=track, at=10 * SEC,
            shape={"gradient": {"stops": [{"at": 0.0, "color": [0, 0, 0]},
                                          {"at": 1.0, "color": [1, 1, 1]}]}})
    refused(s, "add_shape_clip", "a shape argument that is not an object at all",
            "shape patch must be a json object, not 5",
            track=track, at=10 * SEC, shape=5)

    print("\n7c — and not one of them was an undo step, or a clip")
    undo_claim(s, start)
    check(len(s.project()["clips"]) == 0,
          "…and after every refusal above the project holds no clip at all")

    print("\n7d — and both documented forms of the argument still land")
    bare = s.op("add_shape_clip", track=track, at=0, duration=2 * SEC,
                shape="arrow")["new_clips"][0]
    check(s.clip(bare)["shape"]["kind"] == "arrow"
          and s.clip(bare)["shape"]["arrow_end"] is True,
          "the bare-kind shorthand creates a shape clip of that kind, head on")
    whole = s.op("add_shape_clip", track=track, at=10 * SEC, duration=2 * SEC,
                 shape={"kind": "ellipse", "width": 400.0})["new_clips"][0]
    check(s.clip(whole)["shape"]["kind"] == "ellipse"
          and s.clip(whole)["shape"]["width"] == 400,
          "…and an object patch merges over the default rectangle")


# ---- set_canvas's `background` (D1·4, kpgalligan/framejob#5) ---------------


def canvas_background_door(mcp):
    """`set_canvas`'s `background` — a colour-only ARGUMENT, not a patch.

    Its sentences are the envelope's rather than the patch walk's, because
    there is no group to name: the wrong length is the op's own deserialise
    (`op "set_canvas" is not valid: invalid length 3…`) and a component out
    of range is `props_check.rs`'s, spelled `canvas background`. What
    matters is that BOTH exist, since `colorArg` used to fill an alpha into
    a three-element colour and clamp a component to 0–1 — a value changed
    without the caller knowing, at the one door where it is the whole
    argument."""
    print("\n8 — set_canvas: a background colour is four numbers, filled in by nobody")
    s = Session(mcp, "patch-door-canvas")
    # Not black: black is the default, so storing it would be the identity
    # and there would be nothing for the refusals below to leave alone.
    s.op("set_canvas", background=[0.5, 0.0, 0.0, 1.0])
    check(s.project()["canvas"]["background"] == [0.5, 0, 0, 1],
          "the fixture stores a background, which a corrected colour would move")

    print("\n8a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(
        s, lambda: s.op("set_canvas", background=[0.25, 0.5, 0.75, 1.0]))

    print("\n8b — a colour that is not four numbers 0–1, refused")
    refused(s, "set_canvas", "a three-element colour, which used to gain an alpha",
            'op "set_canvas" is not valid: invalid length 3, expected an array of length 4',
            background=[1.0, 0.0, 0.0])
    refused(s, "set_canvas", "a five-element one",
            'op "set_canvas" is not valid: invalid length 5',
            background=[1.0, 0.0, 0.0, 1.0, 1.0])
    refused(s, "set_canvas", "a component outside 0–1, which used to be CLAMPED",
            "canvas background must be between 0 and 1, not 2",
            background=[2.0, 0.0, 0.0, 1.0])
    refused(s, "set_canvas", "a colour name",
            'op "set_canvas" is not valid: invalid type: string "red"',
            background="red")

    print("\n8c — and not one of them was an undo step")
    undo_claim(s, start)
    marker_gone(s.project()["canvas"]["background"], [0.5, 0, 0, 1])

    print("\n8d — and a four-number colour lands exactly as it was written")
    s.op("set_canvas", background=[0.1, 0.2, 0.3, 0.4])
    landed("every component kept, alpha included", s.project()["canvas"]["background"],
           [0.1, 0.2, 0.3, 0.4])
    # A behaviour the forwarding changed, pinned so it is not a surprise: an
    # explicit null is sent rather than stripped, so a call carrying nothing
    # BUT that null is the core's identity refusal instead of the handler's
    # own "set_canvas: nothing to change". Both refuse; the sentence moved.
    message = s.error("set_canvas", background=None)
    check(message is not None and "made no change" in message,
          "…and a call carrying nothing but an explicit null is the core's identity "
          f"refusal, the null reading as absent — got: {shown(message)}")
    landed("…with the colour still the one that landed",
           s.project()["canvas"]["background"], [0.1, 0.2, 0.3, 0.4])


# ---- add_background's `color` (D1·4, kpgalligan/framejob#5) ----------------


def background_clip_door(mcp):
    """`add_background`'s `color` — the second colour-only argument.

    The plate IS a shape clip, so the range refusal comes back as
    `shape.fill`: the colour reaches the group it is going to be stored in
    and `check_shape` answers, which is why there is no second range rule to
    keep in step with the first. The length is the envelope's, as above."""
    print("\n9 — add_background: the plate's colour, four numbers and no clamp")
    s = Session(mcp, "patch-door-plate")
    s.clip_of()

    print("\n9a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("add_background", color=[1.0, 1.0, 0.0, 1.0]))

    print("\n9b — a colour that is not four numbers 0–1, refused")
    refused(s, "add_background", "a three-element colour, which used to gain an alpha",
            'op "add_background" is not valid: invalid length 3, expected an array of length 4',
            color=[1.0, 0.0, 0.0])
    refused(s, "add_background", "a component outside 0–1, which used to be CLAMPED",
            "shape.fill must be between 0 and 1, not 2",
            color=[2.0, 0.0, 0.0, 1.0])
    refused(s, "add_background", "a colour name",
            'op "add_background" is not valid: invalid type: string "red"',
            color="red")

    print("\n9c — and not one of them was an undo step, or a plate")
    undo_claim(s, start)
    check(len(s.project()["tracks"]) == 1,
          "…and after every refusal above there is still no back-most track")

    print("\n9d — and a four-number colour lands exactly as it was written")
    plate = s.op("add_background", color=[0.1, 0.2, 0.3, 1.0])["new_clips"][0]
    landed("the plate is filled with the colour that was sent",
           s.clip(plate)["shape"]["fill"], [0.1, 0.2, 0.3, 1.0])


# ---- add_zoom_action's `region` (D1·5, kpgalligan/framejob#6) --------------


def zoom_region_door(mcp):
    """`add_zoom_action`'s `region` — the one op argument that is an OBJECT.

    Its sentences are §8's kind and not §6's: the core reads the region as a
    TYPE off the op envelope, and there is no property group to name, so a
    misspelt or missing member comes back inside
    `op "add_zoom_action" is not valid: …` with the member's own path after
    it. The two REQUIREMENTS below are not the envelope's, and each has a
    reason of its own: the four numbers are `edit_zoom.rs`'s `check_region`
    (a zero width asks for an infinite scale), and the required KEY is the
    handler's, the one line it keeps — the op reads an absent argument and
    an explicit null identically, so a forgotten rectangle would silently
    become a zoom BACK, the opposite edit.

    The fixture is a clip long enough to hold two actions at different
    times, so that a refusal below cannot be mistaken for the overlap rule,
    and the marker edit leaves a real action for the undo claim to take
    back."""
    print("\n11 — add_zoom_action: the region goes to the core as the caller wrote it")
    s = Session(mcp, "patch-door-region")
    clip = s.clip_of()
    good = {"x": -120.0, "y": -20.0, "width": 160.0, "height": 90.0}

    print("\n11a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(
        s, lambda: s.op("add_zoom_action", clip=clip, at=0, duration=SEC,
                        region=good))

    print("\n11b — a region the vocabulary does not have, refused by member")
    refused(s, "add_zoom_action", "a misspelt member, named beside the four",
            'op "add_zoom_action" is not valid: bad value at "region.widht": '
            'unknown field `widht`, expected one of `x`, `y`, `width`, `height`',
            clip=clip, at=4 * SEC, duration=SEC,
            region=dict(good, widht=1.0))
    refused(s, "add_zoom_action", "a missing member — there is no default for any",
            'op "add_zoom_action" is not valid: bad value at "region": '
            'missing field `height`',
            clip=clip, at=4 * SEC, duration=SEC,
            region={"x": 0.0, "y": 0.0, "width": 480.0})
    refused(s, "add_zoom_action", "a member of the wrong type, by its path",
            'op "add_zoom_action" is not valid: bad value at "region.width": '
            'invalid type: string "wide", expected f64',
            clip=clip, at=4 * SEC, duration=SEC,
            region=dict(good, width="wide"))
    # serde reads a struct from a JSON array of its fields in declaration
    # order, so this would zoom to a rectangle nobody spelled — a spelling no
    # tool description offers and `get_project` never gives back.
    refused(s, "add_zoom_action", "a four-number list, never read positionally",
            'op "add_zoom_action" is not valid: expected an object, not [0,0,480,270]',
            clip=clip, at=4 * SEC, duration=SEC, region=[0, 0, 480, 270])
    refused(s, "add_zoom_action", "a number where the region belongs",
            'op "add_zoom_action" is not valid: expected an object, not 5',
            clip=clip, at=4 * SEC, duration=SEC, region=5)
    refused(s, "add_zoom_action", "a region with no extent",
            "region.width must be greater than 0, not 0",
            clip=clip, at=4 * SEC, duration=SEC, region=dict(good, width=0.0))
    # The one refusal this side still makes, and the only one it can: the
    # core cannot tell an absent key from an explicit null, and those two
    # mean opposite things here.
    message = s.error("add_zoom_action", clip=clip, at=4 * SEC, duration=SEC)
    check(message is not None and "Missing required argument: region" in message,
          "an absent region is refused BY NAME rather than read as a zoom back "
          f"— got: {shown(message)}")

    print("\n11c — and not one of them was an undo step, or an action")
    undo_claim(s, start)
    check(len(s.clip(clip)["actions"]) == 0,
          "…and after every refusal above the clip carries no action at all")

    print("\n11d — and both documented forms of the argument still land")
    s.op("add_zoom_action", clip=clip, at=0, duration=SEC, region=good)
    action = s.clip(clip)["actions"][0]
    check(action["end"]["video"]["scale"] > 1
          and action["end"]["video"]["x"] is not None,
          "a four-member region lands as the scale and offset that bring it to "
          "the canvas")
    s.op("add_zoom_action", clip=clip, at=4 * SEC, duration=SEC, region=None)
    back = s.clip(clip)["actions"][1]
    landed("…and an explicit null is still a zoom BACK, to the clip's own scale",
           back["end"]["video"]["scale"], s.video(clip)["scale"])


# ---- the next argument door's section goes here ---------------------------
#
# **There is no argument door left owed.** D1·5 (kpgalligan/framejob#6) added
# the last of them, `add_zoom_action`'s region; what follows is for an
# argument a LATER phase adds.
#
# Copy §8 or §11 when the core reads the argument as a TYPE off the op
# envelope — its refusals open `op "<name>" is not valid: …` because there is
# no property group to name — and §6 when the argument IS a property patch
# and answers in the patch walk's own sentences. A patch OP's section belongs
# in `patch_door_patches.py` instead.
