"""The patch door's six PATCH-OP sections: `set_video` and its siblings.

`patch_door_proof.py` is the script — its docstring says what a patch means,
which sentences the core gives and how a section is built, and its `main`
runs these in order and then the argument doors in `patch_door_args.py`.

Everything here is a door whose caller-authored object is a PATCH: a partial
property object merged into what the clip already holds (`CONTEXT.md`). They
all answer in the patch walk's own sentences, naming the group — `a video
patch`, `an audio patch`, `a text patch`, `a shape patch`, `a clip patch`,
`an action end patch` — and the dotted path to the mistake. The last of
those is §10's, and it is the one whose paths carry the group inside them
(`video.filters[1].kind`), since an end patch spans three.

They live beside the script rather than in it under the size rule
(`CLAUDE.md`): six sections is about seven hundred lines, the doors arrived
one deepening ticket at a time, and the file that had to keep growing was
this one rather than the one holding the explanation.
"""

from patch_door import (
    FRAME, SEC, Session, check, landed, marker_gone, refused, shown,
    undo_claim, undo_marker,
)


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
    marker_gone(s.video(clip)["opacity"], 1.0)

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


# ---- set_audio (D1·4, kpgalligan/reelcut#5) -------------------------------


def audio_door(mcp):
    """`set_audio` — the group with no enum and no list in it at all.

    What the forwarding buys here is entirely the NESTED object: `duck` and
    `compressor` are the two, and the old door decoded and re-encoded both,
    so a one-key patch replaced the whole thing from defaults and a key
    misspelt inside one was dropped in silence. The fixture stores both
    before anything is refused, so a door that did either would be making a
    real edit and the "unchanged" half of `refused` would go red."""
    print("\n2 — set_audio: a duck and a compressor merge, and a typo inside one is named")
    s = Session(mcp, "patch-door-audio")
    clip = s.clip_of("AV.mov")          # A.mov has no sound, and no audio props
    s.op("set_audio", clips=[clip], patch={
        "volume": 0.8,
        "duck": {"level": 0.3, "attack": 5 * FRAME, "release": 10 * FRAME},
        "compressor": {"threshold_db": -20.0, "ratio": 4.0, "attack": FRAME,
                       "release": 2 * FRAME, "makeup_db": 3.0},
    })
    stored = s.clip(clip)["audio"]
    check(stored["duck"]["level"] == 0.3 and stored["compressor"]["ratio"] == 4,
          "the fixture stores a duck and a compressor, both of them whole")

    print("\n2a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("set_audio", clips=[clip], patch={"volume": 0.5}))

    print("\n2b — a key or a value the vocabulary does not have, refused by path")
    refused(s, "set_audio", "a misspelt key at the top level",
            'unknown key "volumee" in an audio patch',
            clips=[clip], patch={"volumee": 1.0})
    refused(s, "set_audio", "a misspelt key INSIDE the duck",
            'unknown key "duck.levl" in an audio patch',
            clips=[clip], patch={"duck": {"levl": 0.5}})
    refused(s, "set_audio", "a number where the duck OBJECT belongs",
            'bad value at "duck" in an audio patch: expected an object, not 5',
            clips=[clip], patch={"duck": 5})
    # `muted` is the group's only flag, and 1 is what a caller writes for
    # true. A number is not a bool: the kind check names it rather than
    # letting serde read it.
    refused(s, "set_audio", "a number where a flag belongs",
            'bad value at "muted" in an audio patch: expected true or false, not 1',
            clips=[clip], patch={"muted": 1})
    refused(s, "set_audio", "a string where a number belongs",
            'bad value at "volume" in an audio patch: expected a number, not "loud"',
            clips=[clip], patch={"volume": "loud"})
    refused(s, "set_audio", "an unknown key spelled with a null",
            'unknown key "pann" in an audio patch',
            clips=[clip], patch={"pann": None})
    # The range refusals are `props_check.rs`'s and carry the GROUP's name
    # with no array index, which is the other sentence shape a caller meets.
    refused(s, "set_audio", "a volume past the ceiling",
            "audio.volume must be between 0 and 4, not 9",
            clips=[clip], patch={"volume": 9})
    refused(s, "set_audio", "a compressor ratio past the limiter",
            "audio.compressor.ratio must be between 1 and 20, not 99",
            clips=[clip], patch={"compressor": {"ratio": 99.0}})
    refused(s, "set_audio", "a patch that is not an object at all",
            "audio patch must be a json object, not 5",
            clips=[clip], patch=5)

    print("\n2c — and not one of them was an undo step")
    undo_claim(s, start)
    marker_gone(s.clip(clip)["audio"]["volume"], 0.8)

    print("\n2d — and a good patch merges, key by key, at every depth")
    s.op("set_audio", clips=[clip], patch={"duck": {"level": 0.7}})
    landed("a one-key duck patch keeps the attack and the release",
           s.clip(clip)["audio"]["duck"],
           {"level": 0.7, "attack": 5 * FRAME, "release": 10 * FRAME})
    s.op("set_audio", clips=[clip], patch={"duck": None})
    landed("…and null clears the whole object", s.clip(clip)["audio"]["duck"], None)
    landed("…while the compressor beside it is untouched",
           s.clip(clip)["audio"]["compressor"],
           {"threshold_db": -20, "ratio": 4, "attack": FRAME, "release": 2 * FRAME,
            "makeup_db": 3})


# ---- set_text (D1·4, kpgalligan/reelcut#5) --------------------------------


def text_door(mcp):
    """`set_text` — the group whose one enum used to be checked by hand.

    `checkTextEnums` was here because `TextAnimationKind` decodes leniently
    on the Swift side, so `{"animation": {"kind": "fade"}}` reached the core
    as a TYPEWRITER and the caller was told the animation they asked for had
    been applied. The fixture stores an outline, a backdrop and an animation,
    so every refusal below names a key the clip already holds a value for."""
    print("\n3 — set_text: the animation's vocabulary, and colours of four numbers")
    s = Session(mcp, "patch-door-text")
    track = s.project()["tracks"][0]["id"]
    clip = s.op("add_text_clip", track=track, at=0, duration=5 * SEC)["new_clips"][0]
    s.op("set_text", clips=[clip], patch={
        "content": "Chapter One", "color": [1.0, 1.0, 1.0, 1.0],
        "outline": {"width": 3.0, "color": [0.0, 0.0, 0.0, 1.0]},
        "backdrop": {"color": [0.0, 0.0, 0.0, 0.5], "padding": 12.0, "radius": 6.0},
        "animation": {"kind": "typewriter", "in": 2 * FRAME, "out": 0},
    })
    stored = s.clip(clip)["text"]
    check(stored["outline"]["width"] == 3 and stored["backdrop"]["padding"] == 12
          and stored["animation"]["kind"] == "typewriter",
          "the fixture stores an outline, a backdrop and a typewriter animation")

    print("\n3a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("set_text", clips=[clip], patch={"size": 96.0}))

    print("\n3b — a key or a value the vocabulary does not have, refused by path")
    refused(s, "set_text", "a misspelt key at the top level",
            'unknown key "contnt" in a text patch',
            clips=[clip], patch={"contnt": "x"})
    refused(s, "set_text", "a misspelt key INSIDE the outline",
            'unknown key "outline.widht" in a text patch',
            clips=[clip], patch={"outline": {"widht": 4.0}})
    refused(s, "set_text", "a number where the outline OBJECT belongs",
            'bad value at "outline" in a text patch: expected an object, not 5',
            clips=[clip], patch={"outline": 5})
    # The one `checkTextEnums` existed for, now the core's own sentence and
    # with the path to it. A keyword check for `typewriter` passes against
    # BOTH doors, which is why the whole sentence is asserted.
    refused(s, "set_text", "a misspelt animation kind, inside a T?? field",
            'bad value at "animation.kind" in a text patch: unknown variant `fade`',
            clips=[clip], patch={"animation": {"kind": "fade"}})
    refused(s, "set_text", "a misspelt key inside the animation",
            'unknown key "animation.durration" in a text patch',
            clips=[clip], patch={"animation": {"kind": "typewriter", "durration": 1}})
    refused(s, "set_text", "a misspelt alignment",
            'bad value at "align" in a text patch: unknown variant `centre`',
            clips=[clip], patch={"align": "centre"})
    refused(s, "set_text", "an unknown key spelled with a null",
            'unknown key "sizee" in a text patch',
            clips=[clip], patch={"sizee": None})
    # A colour is FOUR numbers at every door (spec #1). `withOpaqueColors`
    # used to fill an alpha into the top-level `color` AND into the one
    # inside `outline`, since it recursed into nested dictionaries.
    refused(s, "set_text", "a three-element colour",
            'bad value at "color" in a text patch: invalid length 3',
            clips=[clip], patch={"color": [1.0, 0.0, 0.0]})
    refused(s, "set_text", "…and one three levels down, inside the outline",
            'bad value at "outline.color" in a text patch: invalid length 3',
            clips=[clip], patch={"outline": {"color": [1.0, 0.0, 0.0]}})
    refused(s, "set_text", "a colour component outside 0–1",
            "text.color must be between 0 and 1, not 2",
            clips=[clip], patch={"color": [2.0, 0.0, 0.0, 1.0]})
    refused(s, "set_text", "a patch that is not an object at all",
            "text patch must be a json object, not 5",
            clips=[clip], patch=5)

    print("\n3c — and not one of them was an undo step")
    undo_claim(s, start)
    marker_gone(s.clip(clip)["text"]["size"], 72)

    print("\n3d — and a good patch merges, key by key, at every depth")
    s.op("set_text", clips=[clip], patch={"outline": {"width": 8.0}})
    landed("a one-key outline patch keeps its colour",
           s.clip(clip)["text"]["outline"], {"width": 8, "color": [0, 0, 0, 1]})
    s.op("set_text", clips=[clip], patch={"backdrop": None})
    landed("…and null clears the whole object", s.clip(clip)["text"]["backdrop"], None)

    print("\n3e — and the ticks the animation carries land on the frame grid")
    # 313 000 is 15.65 frames at 30 fps and has to read back as 16 of them.
    # The snap is the core's (D1·2), where it used to be the inspector's
    # stepper alone and an agent could store a sub-frame reveal.
    s.op("set_text", clips=[clip], patch={"animation": {"in": 313_000}})
    landed("an off-grid reveal reads back ON the grid",
           s.clip(clip)["text"]["animation"],
           {"kind": "typewriter", "in": 16 * FRAME, "out": 0})
    refused(s, "set_text", "…and a negative one is still named, not rounded to 0",
            "text.animation.in must not be negative, not -1",
            clips=[clip], patch={"animation": {"in": -1}})


# ---- set_shape (D1·4, kpgalligan/reelcut#5) -------------------------------


def shape_door(mcp):
    """`set_shape` — the door that lost the most Swift.

    `ShapePatch` is the one patch that is not `Codable`, so the agent door
    read all eleven keys by hand (`shapePatchArg`), three-state `stroke` and
    `fill` included, with a second hand reader under it for the gradient and
    every stop (`gradientArg`). Both are gone: the core walks the patch
    against `ShapeProps`' own template, which carries a `Gradient::default()`
    with two stops in it, so a key misspelt inside a STOP is named by its
    index. The fixture stores a stroke, a fill and a gradient."""
    print("\n4 — set_shape: the hand-built reader's whole job, done by the core")
    s = Session(mcp, "patch-door-shape")
    track = s.project()["tracks"][0]["id"]
    clip = s.op("add_shape_clip", track=track, at=0, duration=5 * SEC)["new_clips"][0]
    s.op("set_shape", clips=[clip], patch={
        "width": 300.0, "height": 200.0,
        "stroke": {"width": 4.0, "color": [0.0, 0.0, 1.0, 1.0]},
        "fill": [1.0, 0.0, 0.0, 1.0],
        "gradient": {"kind": "linear", "angle": 0.0,
                     "stops": [{"at": 0.0, "color": [0.0, 0.0, 0.0, 1.0]},
                               {"at": 1.0, "color": [1.0, 1.0, 1.0, 1.0]}]},
    })
    stored = s.clip(clip)["shape"]
    check(stored["stroke"]["width"] == 4 and stored["fill"] == [1, 0, 0, 1]
          and len(stored["gradient"]["stops"]) == 2,
          "the fixture stores a stroke, a flat fill and a two-stop gradient")

    print("\n4a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("set_shape", clips=[clip], patch={"radius": 12.0}))

    print("\n4b — a key or a value the vocabulary does not have, refused by path")
    refused(s, "set_shape", "a misspelt key at the top level",
            'unknown key "kindd" in a shape patch',
            clips=[clip], patch={"kindd": "rectangle"})
    refused(s, "set_shape", "a geometry outside the closed enum",
            'bad value at "kind" in a shape patch: unknown variant `square`',
            clips=[clip], patch={"kind": "square"})
    refused(s, "set_shape", "a misspelt key INSIDE the stroke",
            'unknown key "stroke.widht" in a shape patch',
            clips=[clip], patch={"stroke": {"widht": 2.0}})
    refused(s, "set_shape", "a number where the stroke OBJECT belongs",
            'bad value at "stroke" in a shape patch: expected an object, not 5',
            clips=[clip], patch={"stroke": 5})
    refused(s, "set_shape", "a misspelt key inside the gradient",
            'unknown key "gradient.stpos" in a shape patch',
            clips=[clip], patch={"gradient": {"stpos": []}})
    # Three levels down and inside an ARRAY. `gradientArg` was the only
    # nested object in any patch that could name this, and it named it
    # without the group or the word "shape"; the core names every one of
    # them the same way now, index included.
    refused(s, "set_shape", "a misspelt key inside a gradient STOP, by index",
            'unknown key "gradient.stops[1].att" in a shape patch',
            clips=[clip],
            patch={"gradient": {"stops": [{"at": 0.0, "color": [0, 0, 0, 1]},
                                          {"att": 1.0, "color": [1, 1, 1, 1]}]}})
    refused(s, "set_shape", "a gradient geometry outside the closed enum",
            'bad value at "gradient.kind" in a shape patch: unknown variant `conic`',
            clips=[clip], patch={"gradient": {"kind": "conic"}})
    # `gradientArg` took three OR four components per stop, deliberately,
    # because `withOpaqueColors` could not reach into an array of objects.
    # Four everywhere now, and the length is what is refused.
    refused(s, "set_shape", "a three-element fill",
            'bad value at "fill" in a shape patch: invalid length 3',
            clips=[clip], patch={"fill": [1.0, 0.0, 0.0]})
    refused(s, "set_shape", "a three-element STOP colour, which the hand reader took",
            'bad value at "gradient.stops[0].color" in a shape patch: invalid length 3',
            clips=[clip],
            patch={"gradient": {"stops": [{"at": 0.0, "color": [0, 0, 0]},
                                          {"at": 1.0, "color": [1, 1, 1]}]}})
    refused(s, "set_shape", "a stop colour component outside 0–1",
            "shape.gradient.stops[0].color must be between 0 and 1, not 2",
            clips=[clip],
            patch={"gradient": {"stops": [{"at": 0.0, "color": [2, 0, 0, 1]},
                                          {"at": 1.0, "color": [1, 1, 1, 1]}]}})
    refused(s, "set_shape", "a patch that is not an object at all",
            "shape patch must be a json object, not 5",
            clips=[clip], patch=5)

    print("\n4c — and not one of them was an undo step")
    undo_claim(s, start)
    marker_gone(s.clip(clip)["shape"]["radius"], 0)

    print("\n4d — and a good patch merges, key by key, at every depth")
    s.op("set_shape", clips=[clip], patch={"stroke": {"width": 9.0}})
    landed("a one-key stroke patch keeps its colour",
           s.clip(clip)["shape"]["stroke"], {"width": 9, "color": [0, 0, 1, 1]})
    # The behaviour change an agent sees at this door: `gradientArg`
    # REPLACED the whole gradient, so an angle-only patch came back as
    # black-to-white from the type's default. It merges now.
    s.op("set_shape", clips=[clip], patch={"gradient": {"angle": 90.0}})
    landed("an angle-only gradient patch KEEPS the stops it was drawn with",
           s.clip(clip)["shape"]["gradient"],
           {"kind": "linear", "angle": 90,
            "stops": [{"at": 0, "color": [0, 0, 0, 1]}, {"at": 1, "color": [1, 1, 1, 1]}]})
    s.op("set_shape", clips=[clip], patch={"gradient": None})
    landed("…and null clears it", s.clip(clip)["shape"]["gradient"], None)
    landed("…bringing the flat fill back out from under it",
           s.clip(clip)["shape"]["fill"], [1, 0, 0, 1])


# ---- set_clip (D1·4, kpgalligan/reelcut#5) --------------------------------


def clip_door(mcp):
    """`set_clip` — the fifth patch, two flat strings and no nesting at all.

    What the forwarding buys here is the wrong TYPE. Both keys are `String??`
    (`ClipPatch`), and a lenient decode reads a value of the wrong type as
    `.some(nil)` — a CLEAR — which `patchArg`'s round trip could not tell
    from a real null, so this door carried a hand check of its own
    (measured: `{"label": 7}` read as "remove the label"). The fixture stores
    both, so a door that cleared one would be making a real edit."""
    print("\n5 — set_clip: a wrong-typed value is refused, never read as a clear")
    s = Session(mcp, "patch-door-clip")
    clip = s.clip_of()
    s.op("set_clip", clips=[clip], patch={"name": "Talk", "label": "blue"})
    stored = s.clip(clip)
    check(stored["name"] == "Talk" and stored["label"] == "blue",
          "the fixture stores a name and a label, both of which a clear would take")

    print("\n5a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(s, lambda: s.op("set_clip", clips=[clip], patch={"name": "Talk, take 2"}))

    print("\n5b — a key or a value the vocabulary does not have, refused by path")
    refused(s, "set_clip", "a misspelt key",
            'unknown key "nmae" in a clip patch',
            clips=[clip], patch={"nmae": "x"})
    refused(s, "set_clip", "a number where a label belongs, which used to CLEAR it",
            '"label" in a clip patch must be a string or null, not 7',
            clips=[clip], patch={"label": 7})
    refused(s, "set_clip", "a list where a name belongs",
            '"name" in a clip patch must be a string or null, not ["Talk"]',
            clips=[clip], patch={"name": ["Talk"]})
    refused(s, "set_clip", "an unknown key spelled with a null",
            'unknown key "labl" in a clip patch',
            clips=[clip], patch={"labl": None})
    refused(s, "set_clip", "a patch that is not an object at all",
            "clip patch must be a json object, not 5",
            clips=[clip], patch=5)

    print("\n5c — and not one of them was an undo step")
    undo_claim(s, start)
    marker_gone(s.clip(clip)["name"], "Talk")

    print("\n5d — and a good patch changes the key it names and nothing else")
    s.op("set_clip", clips=[clip], patch={"label": None})
    check(s.clip(clip).get("label") is None and s.clip(clip)["name"] == "Talk",
          "null clears the label and leaves the name — the reading a wrong TYPE "
          "must never get")


# ---- set_action_end (D1·5, kpgalligan/reelcut#6) -------------------------


def action_end_door(mcp):
    """`set_action_end` — the sixth patch, and the LAST door D1 moved.

    Its object is a patch of a patch: three group bodies under one envelope,
    so every path a refusal names carries the group (`video.filters[1].kind`)
    and the subject is `an action end patch` rather than any one group's.
    Until this ticket it was the one door still laundering — `patchArg`, the
    three allowed-key sets, `checkActionPatch` and the two enum checks — and
    the three holes that left are what the refusals below are chosen for: a
    wrong TYPE one level down read as a CLEAR, a three-element colour had an
    alpha filled in, and `withOpaqueColors` reached no further than a key
    called `color`.

    The fixture stores a value for every key a refusal names, in all three
    groups, BEFORE anything is refused: a door that dropped, cleared or
    corrected a key would be merging a real edit into the end state, and the
    "unchanged" half of `refused` would go red. (`shape`, `video.motion` and
    the unknown `blurr` have nothing stored behind them; they discriminate on
    the sentence alone.)"""
    print("\n10 — set_action_end: an end patch is walked like every other patch")
    s = Session(mcp, "patch-door-action-end")
    clip = s.clip_of()
    s.op("add_action", clip=clip, at=0, duration=2 * SEC)
    action = s.clip(clip)["actions"][0]["id"]

    def end():
        return s.clip(clip)["actions"][0]["end"]

    s.op("set_action_end", clip=clip, action=action, patch={
        "video": {"opacity": 0.5, "blend": "screen",
                  "shadow": {"color": [0.0, 0.0, 0.0, 1.0], "opacity": 0.8,
                             "blur": 10.0, "angle": 315.0, "distance": 30.0},
                  "filters": [{"kind": "sepia", "amount": 1.0}],
                  "spotlight": {"shape": "ellipse"}},
        "audio": {"volume": 0.25, "fade_in": 4 * FRAME},
        "text": {"size": 96.0,
                 "animation": {"kind": "typewriter", "in": 5 * FRAME, "out": 0}},
    })
    stored = end()
    check(stored["video"]["shadow"]["blur"] == 10
          and stored["video"]["filters"][0]["kind"] == "sepia"
          and stored["audio"]["fade_in"] == 4 * FRAME
          and stored["text"]["animation"]["kind"] == "typewriter",
          "the fixture's end state holds a shadow, a sepia filter, a fade and an "
          "animation — a value behind every key the refusals name")

    print("\n10a — a real edit, whose undo step every refusal below must leave alone")
    start = undo_marker(
        s, lambda: s.op("set_action_end", clip=clip, action=action,
                        patch={"video": {"opacity": 0.25}}))

    print("\n10b — a key or a value the vocabulary does not have, refused by path")
    # The group is in the path and `an action end patch` is the subject, which
    # is the whole difference between this door's sentences and `set_video`'s.
    refused(s, "set_action_end", "a misspelt key inside a group",
            'unknown key "video.opacty" in an action end patch',
            clip=clip, action=action, patch={"video": {"opacty": 0.5}})
    refused(s, "set_action_end", "an unknown key INSIDE a filter entry, by INDEX",
            'unknown key "video.filters[1].kindd" in an action end patch',
            clip=clip, action=action,
            patch={"video": {"filters": [{"kind": "blur", "amount": 0.5},
                                         {"kindd": "sepia", "amount": 1.0}]}})
    # `checkVideoEnums` and `checkTextEnums` existed for these two, and could
    # not reach either one's path: a misspelt kind arrived at the core as the
    # vocabulary's FIRST case, a different effect applied and reported as
    # success.
    refused(s, "set_action_end", "a misspelt filter kind, by index",
            'bad value at "video.filters[1].kind" in an action end patch: '
            'unknown variant `glow`',
            clip=clip, action=action,
            patch={"video": {"filters": [{"kind": "blur", "amount": 0.5},
                                         {"kind": "glow", "amount": 1.0}]}})
    refused(s, "set_action_end", "a misspelt text animation kind",
            'bad value at "text.animation.kind" in an action end patch: '
            'unknown variant `fade`',
            clip=clip, action=action,
            patch={"text": {"animation": {"kind": "fade"}}})
    refused(s, "set_action_end", "a misspelt blend, two levels in",
            'bad value at "video.blend" in an action end patch: '
            'unknown variant `muliply`',
            clip=clip, action=action, patch={"video": {"blend": "muliply"}})
    refused(s, "set_action_end", "a misspelt spotlight shape",
            'bad value at "video.spotlight.shape" in an action end patch: '
            'unknown variant `circle`',
            clip=clip, action=action,
            patch={"video": {"spotlight": {"shape": "circle"}}})
    # A wrong TYPE one level down, which the round-trip check could not see
    # at all: `shadow` is a `T??` field, so `5` decoded as `.some(nil)` and
    # REMOVED the shadow the fixture stores.
    refused(s, "set_action_end", "a number where the shadow OBJECT belongs",
            'bad value at "video.shadow" in an action end patch: '
            'expected an object, not 5',
            clip=clip, action=action, patch={"video": {"shadow": 5}})
    refused(s, "set_action_end", "a fraction where a tick count belongs",
            'bad value at "audio.fade_in" in an action end patch: '
            'expected a whole number, not 0.5',
            clip=clip, action=action, patch={"audio": {"fade_in": 0.5}})
    # A colour is FOUR numbers here too. This is the one door where the
    # three-element form was still taken: `withOpaqueColors` filled in the
    # alpha on the way past, so what landed was not what was sent.
    refused(s, "set_action_end", "a three-element colour, which used to gain an alpha",
            'bad value at "video.shadow.color" in an action end patch: '
            'invalid length 3, expected an array of length 4',
            clip=clip, action=action,
            patch={"video": {"shadow": {"color": [1.0, 0.0, 0.0]}}})
    refused(s, "set_action_end", "a filter entry naming only its amount",
            'missing key "video.filters[0].kind" in an action end patch',
            clip=clip, action=action,
            patch={"video": {"filters": [{"amount": 1.0}]}})
    refused(s, "set_action_end", "an unknown key spelled with a null",
            'unknown key "video.blurr" in an action end patch',
            clip=clip, action=action, patch={"video": {"blurr": None}})
    # §5.4's patch is video, audio and text and there is no fourth: a shape
    # is not animatable, so the key is not an inert one to keep.
    refused(s, "set_action_end", "a fourth group",
            'unknown key "shape" in an action end patch',
            clip=clip, action=action, patch={"shape": {"width": 640.0}})
    refused(s, "set_action_end", "a group that is not an object",
            'bad value at "video" in an action end patch: expected an object, not 5',
            clip=clip, action=action, patch={"video": 5})
    refused(s, "set_action_end", "a patch that is not an object at all",
            "action end patch must be a json object, not 5",
            clip=clip, action=action, patch=5)
    # The refusal that is about the OP rather than about the vocabulary, and
    # the one the handler used to make in its own words: a preset is anchored
    # to the clip's two ends, so there is nothing for an action to ramp
    # between. A `null` is still naming it.
    refused(s, "set_action_end", "a video group naming motion",
            "video.motion is not an animation target",
            clip=clip, action=action,
            patch={"video": {"motion": {"in": {"kind": "fade"}}}})
    refused(s, "set_action_end", "…and naming it with a null",
            "video.motion is not an animation target",
            clip=clip, action=action, patch={"video": {"motion": None}})
    # The two above are the ONLY refusals in this section a laundering door
    # could also pass: `refused` matches a substring, and the handler's
    # deleted sentence CONTAINED the core's
    # (`patch.video.motion is not an animation target — set it with
    # set_video.`). So this one says the message ENDS there, which is the
    # difference between the two doors and nothing else.
    motion = s.error("set_action_end", clip=clip, action=action,
                     patch={"video": {"motion": {"in": {"kind": "fade"}}}})
    check(motion is not None
          and motion.endswith("video.motion is not an animation target"),
          "…and the refusal ENDS there: the core's whole sentence, with no tail "
          f"this side used to add — got: {shown(motion)}")

    print("\n10c — and not one of them was an undo step")
    undo_claim(s, start)
    marker_gone(end()["video"]["opacity"], 0.5)

    print("\n10d — and a good patch merges, key by key, at every depth")
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"shadow": {"blur": 40.0}}})
    landed("a one-key shadow patch keeps the colour, the angle and the distance",
           end()["video"]["shadow"],
           {"color": [0, 0, 0, 1], "opacity": 0.8, "blur": 40, "angle": 315,
            "distance": 30})
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"filters": [{"kind": "noir", "amount": 0.25}]}})
    landed("a filter LIST replaces rather than merging",
           end()["video"]["filters"], [{"kind": "noir", "amount": 0.25}])

    print("\n10e — and null REMOVES a key rather than clearing it")
    # The one thing an end patch spells differently from every other patch,
    # and the reason the walk passes every null: there is no stored property
    # to clear, so a null means "stop animating this".
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"shadow": None}})
    check("shadow" not in end()["video"] and end()["video"]["blend"] == "screen",
          "a null takes the key out of the end state altogether, leaving its "
          "siblings — not stored as a null, and not a cleared property")
    s.op("set_action_end", clip=clip, action=action, patch={"text": None})
    check("text" not in end() and "audio" in end(),
          "…and a whole group set to null goes the same way")
    # An out-of-range value is NOT refused here, unlike at every other patch
    # door: the state a clip interpolates toward may name a value no stored
    # group could hold, and `actions_clamp.rs`'s `clamp_video` bounds the evaluated
    # value instead (spec §5.4). Pinned so the difference is deliberate.
    s.op("set_action_end", clip=clip, action=action, patch={"video": {"opacity": 5.0}})
    landed("an out-of-range value is STORED rather than refused, which is this "
           "door's one documented difference", end()["video"]["opacity"], 5.0)
    # A behaviour the forwarding changed, pinned as §8d pins `set_canvas`'s:
    # a patch that names nothing is the core's identity refusal where it used
    # to be the handler's own "patch names nothing to change". Both refuse;
    # the sentence moved, and an empty end patch really does change nothing.
    before = s.text()
    message = s.error("set_action_end", clip=clip, action=action, patch={})
    check(message is not None and "made no change" in message,
          "…and an empty patch is the core's identity refusal, not this side's "
          f"\"names nothing to change\" — got: {shown(message)}")
    check(s.text() == before, "…with the end state exactly as it was")


# ---- the next patch door's section goes here ------------------------------
#
# **There is no patch door left owed.** D1·5 (kpgalligan/reelcut#6) added the
# sixth and last of them, `set_action_end`, so what follows is for a door a
# LATER phase adds: an op that takes a caller-authored patch is a door here
# the day it lands.
#
# Copy any section above whole. What changes is the fixture (a door needs a
# clip that HAS the group it patches, holding a value the refusals name), the
# tool, and the subject inside each sentence — the six spellings are in
# `patch_door_proof.py`'s docstring — plus any prefix the paths carry
# (§10's are `video.filters[1].kind`, because an end patch spans three
# groups). The four helpers and the sub-sections (the undo marker, the
# refusals, the undo claim, the merges, the snap) do not change, and neither
# does their order: the fixture FIRST, so that a refusal names a key the clip
# already holds a value for. Then one line in `patch_door_proof.py`'s `main`.
