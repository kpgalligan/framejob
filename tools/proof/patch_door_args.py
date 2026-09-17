"""The patch door's caller-authored ARGUMENTS, as against its patches.

`patch_door_proof.py` is the whole of this proof — its docstring says what a
patch means and how a section is built, and its `main` runs these four
sections in order with the rest. They live here because the file they came
out of reached the ~600-line cap with its five patch-op doors in it
(`CLAUDE.md`'s size rule; the harness had already moved to `patch_door.py`),
and because these four are the doors where the caller's object is an
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

kpgalligan/reelcut#6's `add_zoom_action` region is the next section here.
"""

from patch_door import (
    SEC, Session, check, landed, marker_gone, refused, shown, undo_claim,
    undo_marker,
)


# ---- add_text_clip's `text` (D1·4, kpgalligan/reelcut#5) ------------------


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


# ---- add_shape_clip's `shape` (D1·4, kpgalligan/reelcut#5) ----------------


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


# ---- set_canvas's `background` (D1·4, kpgalligan/reelcut#5) ---------------


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


# ---- add_background's `color` (D1·4, kpgalligan/reelcut#5) ----------------


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


# ---- the next argument door's section goes here ---------------------------
#
# D1·5 (kpgalligan/reelcut#6): `add_zoom_action`'s `region`, forwarded raw.
# Copy §8 rather than §6: a region is an argument the core reads as a TYPE,
# so an unknown or a missing member is the envelope's sentence, not the patch
# walk's. `set_action_end` is a patch op and its section belongs in
# `patch_door_proof.py` beside the other five.
