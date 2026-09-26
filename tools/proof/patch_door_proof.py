"""The PATCH DOOR, driven against the built binary over MCP.

Named for the seam and not for a phase: what it proves is the one door every
caller-authored object comes through (`core/src/patch.rs`, `CONTEXT.md`'s
**Patch**), and the doors arrive one deepening ticket at a time
(`archive/reelcut-roadmap-7.md` §1, kpgalligan/reelcut#1). Deepening D1·3
built it with `set_video`'s section; D1·4 added eight more; D1·5 added the
last two, `set_action_end` and `add_zoom_action`'s region. There is no phase
number to put on that, and every door the app has is here.

**What a patch means, which is the whole of what is checked here.** A patch
merges key by key at EVERY depth, `null` clears a key and an array replaces
its whole list. A key or a value the vocabulary does not have is REFUSED —
never dropped, corrected or clamped — naming the dotted path to it, array
indices included, and the value sent; the project is left exactly as it was,
so a failed call is safe to retry.

**The four sentence forms** the core gives, which every section asserts
verbatim rather than by keyword:

    unknown key "<path>" in <subject>
    missing key "<path>" in <subject>
    bad value at "<path>" in <subject>: <serde's own sentence>
    <group> patch must be a json object, not <value>

`<subject>` is `a video patch`, `an audio patch`, `a text patch`, `a shape
patch`, `a clip patch` or `an action end patch`; in the last the path carries
the group (`video.filters[1].kind`), and that door alone does NOT range-check,
because the state a clip interpolates toward may name a value no stored group
could hold (spec §5.4). Beside them the RANGE refusals,
`props_check.rs`'s, spelled with the group's name and NO array index —
`video.shadow.color must be between 0 and 1, not 2`,
`shape.gradient.stops[].color must be between 0 and 1, not 2`. A door whose
caller-authored object is an ARGUMENT rather than a patch — a colour, a
region — has no group to name, so its wrong TYPE is refused one level out, by
the op envelope: `op "set_canvas" is not valid: invalid length 3, expected an
array of length 4`, or, where the argument is an object the core reads as a
type, `op "add_zoom_action" is not valid: bad value at "region.widht":
unknown field `widht``.

**Why it has to be driven through the app.** `core/tests/patch_door.rs`
proves all of this through the FFI. What it cannot see is the Swift agent
door, which until D1·3 decoded the caller's object through the app's LENIENT
project types and sent the RESULT on: a misspelt enum arrived as the
vocabulary's first case, an unknown key inside a nested object was dropped,
a three-element colour had an alpha filled in and an out-of-range component
was clamped — each of them an edit nobody asked for, reported as success.
Only a call made over MCP against the built binary tells the two apart.

**Four files, and where the next door's section goes.** One section per
door, built out of the four helpers in `patch_door.py`: `refused` (the
refusal AND the unchanged project), `landed` (a merge read back) and
`undo_marker` / `undo_claim` (the two halves of "a refusal registers no undo
step"). A new section is a function shaped like `video_door` plus one line in
`main` below. The sections themselves sit in two files beside this one, split
by KIND when D1·4's eight took the single file past the ~600-line cap
(`CLAUDE.md`'s size rule):

    patch_door.py           the harness — the Session and the four helpers
    patch_door_patches.py   the doors whose object is a PATCH (six of them)
    patch_door_args.py      the doors whose object is an ARGUMENT (five)
    patch_door_proof.py     this file: what a patch means, and `main`

Each door file's foot carries a marker comment saying what a LATER phase's
door copies; neither is owed a door today. There is nothing to run but this
script.

Needs no ffmpeg and nothing in `media/` but `A.mov`, which
`tools/proof/README.md` says how to make. Run it as every other script here
is run:

    python3 tools/proof/patch_door_proof.py <port>
"""

import os
import sys

from patch_door import MCP, WORK, ToolError, summary
from patch_door_args import (
    background_clip_door, canvas_background_door, new_shape_clip_door,
    new_text_clip_door, zoom_region_door,
)
from patch_door_patches import (
    action_end_door, audio_door, clip_door, shape_door, text_door, video_door,
)

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4823


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)
    print(f"the patch door, against 127.0.0.1:{PORT}")
    video_door(mcp)
    audio_door(mcp)
    text_door(mcp)
    shape_door(mcp)
    clip_door(mcp)
    new_text_clip_door(mcp)
    new_shape_clip_door(mcp)
    canvas_background_door(mcp)
    background_clip_door(mcp)
    action_end_door(mcp)
    zoom_region_door(mcp)
    summary()


if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, KeyError, RuntimeError, OSError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
