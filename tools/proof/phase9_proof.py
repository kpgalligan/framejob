"""Road map 2, phase 9 — Inside the nest, driven against the built binary over MCP.

Phase 9 gives the op ENVELOPE a `scope` (a nest id) instead of teaching
fifty-five ops about nests: `core/src/scope.rs` builds a view project out of
the nest, applies the op to it unchanged, and merges it back. This script is
the half of that a LIVE SERVER can say, and it is deliberately the smaller
half — `tools/proof/phase9_probe.py` already owns everything the app decides
before a tool call leaves it (`ReelOp.scope` and `scoped(_:)`, the
`isDocumentLevel` list, `NestScope`'s path arithmetic, and
`ProjectDocument`'s view state), because none of those has a caller a
running binary can be asked to reach. Nothing here duplicates it; where the
two touch the same idea they touch it from opposite sides — the probe reads
the JSON an op leaves with, this reads what a document that got one looks
like afterwards.

**Section 1 is the phase's oracle and it runs first after the catalog.**
The road map states it in one line — *"apply inside with `scope`, then
`unnest`" equals "`unnest`, then apply at top level", on clip content, ids
aside* — and the sameness in it is not this script's to define. The core's
own comparator moved out of `core/tests/nest.rs` into
`core/tests/common/mod.rs` for exactly this reason, so `content` and
`contents` below are that Rust pair transcribed key for key: strip `id`,
`track` and each action's `id`; key each clip by its start and by the INDEX
of the track it sits on; sort. A second, looser rule invented here would
make the core's identity claim and this one two different claims wearing one
sentence.

The table is the road map's seven plus twenty-five more, and each row is
scored TWICE: the two halves agree, **and** each half differs from the
untouched round trip. Without the second check a build in which the scoped
op silently did nothing would agree perfectly with a build in which the
top-level op silently did nothing, and thirty-two rows would pass green
against a core that had stopped editing.

Three things about the fixture are deliberate and all three are the core
fixture's own reasons, restated because a reader here cannot see that file:

* **The nest clip starts at 0.** Nest-local time is `t − nest_clip.start`,
  so a nest clip at zero lets both halves send the SAME time arguments. The
  mapping is not what the oracle is testing, and a fixture that made every
  row's arguments differ would hide a real disagreement behind arithmetic.
* **The canvas is never changed in that document.** `add_zoom_action`,
  `add_background` and `add_blurred_background` all SOLVE against a canvas,
  and inside a scope that canvas is the nest's frozen pair. The nest is
  frozen at the document's own size here, so the two halves agree; a
  document whose canvas had moved would fail those three rows for a reason
  that is a fact about nests rather than a disagreement about scoping, and
  section 3 is where that reading is checked on its own.
* **The fixture holds a real media clip**, which is why `media/AV.mov` is
  required at proof time: `slip`, `set_speed`, `rate_stretch`,
  `freeze_frame`, `detach_audio`, `insert_clip`, `overwrite_clip` and
  `add_blurred_background` are eight of the thirty-two rows and none of them
  means anything on a shape.

**Section 3 is the frame claim, and "the corresponding region" is worth
spelling out because the road map's phrase hides an arithmetic.** A nest is
composited at its FROZEN size and then placed on the project canvas as one
layer (`core/src/nest.rs`'s `Frame::enter`). At the identity transform the
fold contributes scale 1 and no offset, so the nest's canvas rect lands
CENTRED on the project canvas at 1:1 — no resampling anywhere — and the
corresponding region is the centred `nest.width × nest.height` rectangle of
the outer frame. Two facts make that exact rather than approximate:

* the comparison is a byte comparison of decoded pixels, all four channels,
  every pixel of the region; and
* the centre never falls between pixels. `set_canvas` refuses an odd
  dimension by name (*"canvas width must be even (h.264 encodes in
  macroblocks)"*) and a nest's frozen size is a canvas size, so
  `canvas − nest` is even in both axes for every project the ops can build.

So this is NOT a claim that only holds at one size, and the script proves
that by making it at three: 640 × 360 with the nest frozen at 640 × 360 (the
whole frame), 1280 × 720 (a clean double) and 1000 × 800 (neither a multiple
nor the same aspect). The fixture's content deliberately includes a shape
BIGGER than the nest's canvas, so the recipe's `clip_rect` — which is what
cuts the outer render — is compared against the view's own canvas edge,
which is what cuts the inner one, exactly where the two act. The control is
the same comparison with the nest clip at `scale: 0.5`, which must differ in
most of the region; without it a build whose two renders were the same
picture for the wrong reason would pass.

**What the live server alone can say** is sections 0 and 4 to 9: the
catalog (at least 74 tools — the exact count was this script's until road
map 3's `record_screen` made it 75 and `recording_proof.py`'s, the handover
`tools/proof/README.md` describes — and exactly 55 declaring `scope`; that 55
is `rc_op_names` read through `AgentCatalog.opNames`, so it is the live
core's op count and not a number typed here, and the twenty tools WITHOUT
one are still named exactly), one undo step per edit with entering and leaving
contributing none, `set_scope` in all its shapes, the seven refusals reached
BY MESSAGE, the wide `Err` arm — the two invariants a view cannot see,
which are the phase's most surprising contract and which nothing but a
document at a cap can exercise — and, in section 9, the two things the APP
decides about a scope that was inherited from `set_scope` rather than asked
for: the marker ticks it refuses before the edit reaches the core, and the
landing a result reports under `scope` and `document_ops`. Section 10 pins
the documented limits, last, because a limit reads best after the behaviour
it bounds.

**Two of the seven refusals cannot be reached without a fixture, and that
is a finding rather than a footnote.** `set_marker`, `remove_marker`,
`relink_media` and `remove_media` are refused by the APP's own id readers
before the core is asked anything, so a project with no markers and no media
answers "No marker has id 99" and the scope refusal never runs; `add_media`
answers about its descriptor first. Section 6 therefore builds a document
that HAS a marker and a media and copies the media row back as a descriptor,
so all seven reach `core/src/scope.rs`'s own sentence. A proof that had
skipped that would have scored four passes on messages that say nothing
about scoping at all.

**What this script does not claim, and where those claims live.** The
gestures and the chrome are untouched here: ⌘↓ / ⌘↑, the double-click that
enters, and the breadcrumb in the ruler's 132 × 22 pt corner (264 × 44 px
at the Retina scale) are a PICTURE and a click count, and they are
`phase9_chrome.py`'s (62/62) — a probe that renders a bare `TimelineView`
SCROLLED and byte-compares that crop, which is what a photograph at scroll 0
could never show; this sentence used to say there was no such script and
sized the corner at 131 × 21. The probe below reads `NestScope.names`,
which is what the breadcrumb prints, and does not photograph it. Nor can
anything here say a nest PLAYS: a scoped
composition's audio and its 60 fps are the two things spec §10 has always
left to a person at the machine. And the identity between the handle
`rc_project_scoped` returns and the view an edit is applied to is
`core/tests/scope.rs`'s claim, made in-process against one `scoped_view`;
what this file adds is that the app, the renderer and the tools all agree
with that handle once it is open.

**Media.** `media/AV.mov` is read (never written) and nothing is added to
`media/`. Every other fixture is shape cards, text and hand-written
`.reelcut` packages under `work/`. No `ffmpeg` is needed: nothing here
decodes an exported movie.

**The parity log.** `AgentServer`'s startup check logs and does not refuse,
so a scope-less op tool would leave a clean-looking server on the port. Part
4 of that check is re-derived over the wire in section 0 (the 55), and the
log itself is read from `/tmp/reelcut-<port>.log` — the path
`CLAUDE.md`'s own launch line writes — or from a second argument.

    python3 tools/proof/phase9_proof.py [port] [log path]
"""

import hashlib
import json
import os
import re
import struct
import sys
import zlib

from mcp import MCP, ToolError
from dev_tools import DEV_TOOLS

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4823
LOG = sys.argv[2] if len(sys.argv) > 2 else f"/tmp/reelcut-{PORT}.log"

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
MEDIA = os.path.join(HERE, "media", "AV.mov")
# A second file nobody places, for section 6's `remove_media` (a media in use
# is refused for being in use, ahead of the scope), and a third that only
# ever appears as a PATH inside a paste payload, in section 2.
UNUSED_MEDIA = os.path.join(HERE, "media", "A.mov")
SPARE_MEDIA = os.path.join(HERE, "media", "B.mov")

SEC = 600_000
HEADER = os.path.join(HERE, "..", "..", "core", "include", "reelcut_core.h")


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes stale at every bump."""
    with open(HEADER) as f:
        text = f.read()
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", text)
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


CURRENT_VERSION = format_version()

# The whole catalog after phase 9: phase 7's 73 plus `set_scope`, which is
# not an op — view state like `set_playhead`, `set_range` and
# `set_selection`. The EXACT count belongs to the newest phase's script
# (tools/proof/README.md), and this WAS that script until road map 3's
# `record_screen` took the count to 75 — `recording_proof.py` asserts the
# exact 75 now, and this number is a FLOOR, the handover phases 6, 7 and 8's
# `== 73` went through when this script took theirs.
TOOLS = 74

# `rc_op_names`' own length. It is asserted here as the number of tools that
# declare `scope`, because `AgentCatalog.opNames` IS `ReelOp.coreNames()` and
# the injection is one line gated on it: a core that reported 54 or 56 ops
# would move this number, which is the point — a scope is an envelope key,
# not an op, so phase 9 must NOT have moved it.
OPS = 55

# The twenty tools that are not §6 rows and therefore carry no `scope`.
# Spelled out rather than counted: an op tool that silently lost its scope
# would leave the count right and this set wrong, and vice versa.
# `record_screen` is road map 3's (R1d): an app-state tool like `transcribe`,
# added here in the same commit as the tool because this set is asserted
# EXACTLY below and a new scopeless tool would otherwise fail phase 9's own
# catalog row for the right reason at the wrong address.
APP_STATE_TOOLS = {
    "open_project", "new_project", "save_project", "get_project", "import_media",
    "import_captions", "export_captions", "transcribe", "consolidate_media",
    "detect_silence", "normalize_clip", "set_playhead", "set_range", "set_selection",
    "set_scope", "undo", "redo", "render_frame", "export", "record_screen",
    "write_graphic", "get_graphic", "graphic_reference", "render_graphic",
    "import_graphic_font", "import_graphic_asset", "close_project",
}

# The seven ops `core/src/scope.rs` refuses inside a nest, and the sentence
# it refuses them with. The message is the CORE's, and the app does not
# rewrite it.
REFUSED_INSIDE = [
    "add_marker", "set_marker", "remove_marker", "set_canvas",
    "add_media", "relink_media", "remove_media",
]

# `AgentServer+Render.swift`'s sentence, read the way six earlier scripts
# read it. Spelled verbatim rather than adapted.
FRAME_SENTENCE = re.compile(r"Written to (\S+\.png)\.")

failures = []
checks = 0


def check(ok_, what):
    global checks
    checks += 1
    if ok_:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def section(name, run, *args):
    """One section, isolated. A section that raises scores ONE failure and
    the run goes on.

    Phase 7's idiom for phase 7's reason, which phase 9 needs more than any
    earlier phase did: a mutant that makes one section throw — a refusal
    where an edit was expected, a `set_scope` that no longer answers — would
    otherwise abort the process and leave every later section UNRUN, which
    reads as a weaker detection than it is. A crash is a worse detection
    than a failure. Each section also opens its OWN document as its first
    act, so a section that died half way through cannot leave the next one
    editing its wreckage."""
    global checks
    print(f"\n{name}")
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — the point is to keep scoring
        checks += 1
        what = f"section {name.split(' ')[0]} ran to the end (raised {error!r})"
        print(f"  FAIL {what}")
        failures.append(what)


# ---- driving the server --------------------------------------------------


def call(mcp, tool, args):
    """One tool call. Raises `ToolError` on a refusal, like `mcp.call_with`;
    it exists only so every call site reads the same way."""
    return mcp.call_with(tool, args)


def refusal(mcp, tool, args):
    """The refusal MESSAGE, with the tool's own prefix stripped, or None
    when the call succeeded. The prefix is stripped so a check can quote
    `core/src/scope.rs`'s sentence exactly as that file writes it."""
    try:
        mcp.call_with(tool, args)
        return None
    except ToolError as error:
        text = str(error)
        prefix = f"{tool}: "
        return text[len(prefix):] if text.startswith(prefix) else text


def state(mcp):
    """`get_project`'s whole answer — the project AND the view state around
    it (the playhead, the selection, the range, and phase 9's scope trio)."""
    return mcp.call_with("get_project", {})


def project(mcp):
    """The project object `get_project` reports, which inside a nest is the
    NEST as a project.

    It raises rather than `KeyError`s when the object is missing, and that
    case is real: `getProject` falls back to a raw `project_json` string
    when the handle will not serialise, which is what a document pushed past
    a cap looks like from out here. Section 7 is the one that can produce
    one, and it asks before it reads."""
    reported = state(mcp)
    found = reported.get("project")
    if not isinstance(found, dict) or "tracks" not in found or "clips" not in found:
        raise RuntimeError(
            "get_project did not answer a readable project — the document is in a state its "
            f"own writer will not hand back (keys: {sorted(reported)}, project: "
            f"{sorted(found) if isinstance(found, dict) else type(found).__name__})")
    return found


def fingerprint(mcp):
    """The whole reported project as one string, for "did undo put it back"."""
    return json.dumps(project(mcp), sort_keys=True)


def undo_to(mcp, target, limit=8):
    """Undoes until the project matches `target` again. Returns True when it
    got there.

    Counting undo steps would be the obvious way and it is the wrong one: an
    op that changed nothing registers no step (spec §5.5), so a row whose op
    was silently refused would leave the count one ahead and every LATER row
    of the table would be measured against a drifting base. Undoing until
    the document is provably back is self-correcting, and it is also a check
    in its own right — a scoped edit that could not be undone shows up here
    as a row that never restores."""
    for _ in range(limit):
        if fingerprint(mcp) == target:
            return True
        try:
            mcp.call_with("undo", {})
        except ToolError:
            return False
    return fingerprint(mcp) == target


def frame_path(mcp, t, **extra):
    """`render_frame` at `t`, through the sentence six earlier scripts read."""
    args = {"t": t}
    args.update(extra)
    answer = mcp.call_with("render_frame", args)
    found = FRAME_SENTENCE.search(answer)
    if not found:
        raise RuntimeError(f"render_frame's sentence changed: {answer!r}")
    return found.group(1)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def scoped_edit(mcp, tool, args, what):
    """A scoped op a section's later claims all depend on: asked for, then
    CHECKED, and None when it was refused.

    Every caller stops on a None. A build in which scoping is broken
    outright refuses the first scoped op of a section, and a section that
    let that raise would leave every claim below it unrun — which reads as a
    weaker detection than it is. This is the section-level half of the same
    rule `section()` applies to the run."""
    try:
        return mcp.call_with(tool, args)
    except ToolError as error:
        check(False, f"{what} ({error})")
        return None


# ---- "the same clips, ids aside" -----------------------------------------
#
# `core/tests/common/mod.rs`'s `content` and `contents`, transcribed. That
# file is where the pair lives BECAUSE this script wanted it too: `nest` /
# `unnest`'s identity claim and phase 9's oracle have to be about one notion
# of sameness or neither of them means what it says. Change one, change
# both — and the Rust is the original.


def content(clip):
    """A clip with everything that names an id stripped out."""
    out = dict(clip)
    out.pop("id", None)
    out.pop("track", None)
    actions = out.get("actions")
    if isinstance(actions, list):
        out["actions"] = [
            {k: v for k, v in action.items() if k != "id"} for action in actions
        ]
    return out


def contents(reported):
    """Every clip's content, ordered by start then by the track INDEX it sits
    on, so two projects compare equal only if their stacking agrees too."""
    order = [track["id"] for track in reported["tracks"]]
    rows = []
    for clip in reported["clips"]:
        index = order.index(clip["track"]) if clip["track"] in order else 0
        rows.append((clip["start"], index, json.dumps(content(clip), sort_keys=True)))
    rows.sort()
    return rows


# ---- PNG, in pure Python -------------------------------------------------
#
# The decoder phases 2, 3, 6 and 7 carry, copied rather than imported for
# their reason: those files are SCRIPTS, importing one would run its main,
# and a proof that measures its own evidence should carry the decoder it
# trusts. The 8-bit guard raises rather than fails, which is why section 3's
# fixture is shape cards and text and never a ProRes clip.


def decode_png(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"{path} is not a PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        raise RuntimeError(
            f"{path}: {depth}-bit or interlaced — this decoder reads 8-bit "
            "non-interlaced PNGs, and every byte comparison here assumes one")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            raise RuntimeError(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, channels, rows


class Frame:
    """One rendered PNG, decoded."""

    def __init__(self, path):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)

    def pixel(self, x, y):
        return tuple(self.rows[y][x * self.channels:(x + 1) * self.channels])

    def region_differences(self, inner):
        """How many pixels of `inner` differ from the CENTRED region of this
        frame that they correspond to, and where the first one is.

        The offset is `(self.width - inner.width) // 2`, and the `//` is
        exact rather than a rounding: `set_canvas` refuses an odd dimension
        and a nest's frozen size is a canvas size, so both differences are
        even for any project the ops can build."""
        ox = (self.width - inner.width) // 2
        oy = (self.height - inner.height) // 2
        if ox < 0 or oy < 0:
            raise RuntimeError("the inner frame is bigger than the outer one")
        differ, first = 0, None
        for y in range(inner.height):
            here = inner.rows[y]
            there = self.rows[oy + y]
            if here == there[ox * self.channels:(ox + inner.width) * self.channels]:
                continue
            for x in range(inner.width):
                a = here[x * inner.channels:(x + 1) * inner.channels]
                b = there[(ox + x) * self.channels:(ox + x + 1) * self.channels]
                if a != b:
                    differ += 1
                    if first is None:
                        first = (x, y, tuple(a), tuple(b))
        return differ, first

    def outside_region(self, inner):
        """How many pixels OUTSIDE the centred region are not the canvas
        background — read at the top-left corner, which no fixture here
        draws on."""
        ox = (self.width - inner.width) // 2
        oy = (self.height - inner.height) // 2
        background = self.pixel(0, 0)
        painted = 0
        for y in range(self.height):
            inside_rows = oy <= y < oy + inner.height
            for x in range(self.width):
                if inside_rows and ox <= x < ox + inner.width:
                    continue
                if self.pixel(x, y) != background:
                    painted += 1
        return painted


# ---- fixtures ------------------------------------------------------------


def fresh(mcp, width=640, height=360):
    """A new, empty document at a canvas small enough to decode quickly.

    Every section starts with one. The app deadlocks somewhere past forty
    open documents and nothing closes one (`tools/proof/README.md`), so the
    count matters: this script opens sixteen — ten `new_project`, one per
    section that builds its own fixture (section 7 builds two), and section
    8's six `open_project` — which is why the README says to relaunch
    between proof sessions rather than read a hang as a failure."""
    mcp.call_with("new_project", {})
    mcp.call_with("set_canvas", {"width": width, "height": height})
    return project(mcp)["tracks"][0]["id"]


def one_nest(mcp):
    """The oracle fixture, and the core's own shape (`core/tests/scope.rs`):
    one timeline track holding ONE nest clip at 0 for 4 s, and inside it two
    clips on one track — a media clip at 0 – 2 s and a text clip at
    2 – 4 s.

    Built by ops rather than written as JSON, deliberately: the point of
    driving the built binary is that the fixture is one the product can
    actually make."""
    track = fresh(mcp)
    media = mcp.call_with("import_media", {"path": MEDIA})["media"]
    first = mcp.call_with("add_clip", {"track": track, "media": media, "at": 0})
    first = first["new_clips"][0]
    mcp.call_with("trim_end", {"clip": first, "to": 2 * SEC})
    second = mcp.call_with(
        "add_text_clip",
        {"track": track, "at": 2 * SEC, "duration": 2 * SEC, "text": {"content": "Two"}},
    )["new_clips"][0]
    mcp.call_with("nest", {"clips": [first, second]})

    reported = project(mcp)
    nest = reported["nests"][0]
    inside = {clip["start"]: clip["id"] for clip in nest["clips"]}
    return {
        "media": media,
        "nest": nest["id"],
        "nest_clip": reported["clips"][0]["id"],
        "nest_track": nest["tracks"][0]["id"],
        "first": inside[0],
        "second": inside[2 * SEC],
        "timeline_track": track,
    }


# ---- 0. the catalog ------------------------------------------------------


def catalog_part(mcp):
    listed = mcp.schemas().values()
    names = {tool["name"] for tool in listed}
    check(len(names) >= TOOLS,
          f"the catalog holds at least phase 9's {TOOLS} tools (got {len(names)}) — phase 7's "
          "73 plus set_scope, which is view state and not an op; the exact count belongs to "
          "the newest phase's script, which since road map 3's record_screen is "
          "recording_proof.py at 75, so this one is a floor as phases 6, 7 and 8's became "
          "when it took theirs")
    check("set_scope" in names, "set_scope is among them")

    scoped = sorted(
        tool["name"] for tool in listed
        if "scope" in (tool["inputSchema"].get("properties") or {}))
    check(len(scoped) >= OPS,
          f"at least {OPS} tools declare the envelope's scope (got {len(scoped)}) — that "
          "number is rc_op_names read through AgentCatalog.opNames, so a phase that had "
          "added an op would move it, and phase 9 must NOT have: a scope is an envelope "
          "key, not an op. A FLOOR since road map 5's E1 added two ops; the exact "
          "count is the newest phase's")
    check(names - set(scoped) - set(DEV_TOOLS) == APP_STATE_TOOLS,
          "and the tools WITHOUT one are exactly the twenty-seven app-state tools, named rather "
          f"than counted (the dev tools apart): "
          f"{sorted(names - set(scoped) - set(DEV_TOOLS) - APP_STATE_TOOLS)} unexpected, "
          f"{sorted(APP_STATE_TOOLS - (names - set(scoped)))} missing")
    check("set_scope" not in scoped,
          "set_scope itself declares no scope — it IS the scope, and a scope on it would be "
          "two spellings of one destination in one call")

    schemas = {tool["name"]: tool["inputSchema"] for tool in listed}
    trim = schemas.get("trim_start", {"properties": {}})
    scope_property = trim["properties"].get("scope", {})
    check(scope_property.get("type") == "integer" and scope_property.get("minimum") == 0,
          f"the injected property is a non-negative integer ({scope_property.get('type')}, "
          f"minimum {scope_property.get('minimum')})")
    for phrase, why in (
            ("Seven ops have no meaning inside a nest",
             "so a caller meets the refusal list before it trips over one"),
            ("still be refused for the whole DOCUMENT's sake",
             "so a caller meets the wide Err arm before it is surprised by one")):
        check(phrase in str(scope_property.get("description")),
              f"…and its description says \"{phrase}\" — {why}")

    set_scope = schemas.get("set_scope", {"properties": {}})
    check(set(set_scope["properties"]) == {"nest", "clip", "project"},
          f"set_scope takes nest, clip and project and nothing else: "
          f"{sorted(set_scope['properties'])}")
    check(not set_scope.get("required"),
          "with neither required, because calling it with neither is how you come back out")

    if not os.path.exists(LOG):
        check(False,
              f"the startup parity log is empty — no log at {LOG}; CLAUDE.md's launch line "
              "writes /tmp/reelcut-<port>.log, or pass the path as the second argument")
    else:
        with open(LOG, "r", errors="replace") as handle:
            complaints = [line.strip() for line in handle if "Reelcut: " in line]
        check(not complaints,
              "the startup parity log is EMPTY — that prefix is the check complaining, and "
              "phase 9 gave it a FOURTH part (every op tool declares scope), which logs "
              f"rather than refuses{': ' + complaints[0] if complaints else ''}")


# ---- 1. the oracle -------------------------------------------------------


def oracle_part(mcp):
    ids = one_nest(mcp)
    nest, nest_clip, nest_track = ids["nest"], ids["nest_clip"], ids["nest_track"]
    first, second, media = ids["first"], ids["second"], ids["media"]

    reported = project(mcp)
    check(len(reported["clips"]) == 1 and reported["clips"][0]["start"] == 0,
          "the fixture is one nest clip at 0 — nest-local time is t minus its start, so at "
          "zero both halves of every row can send the same time arguments")
    check(len(reported["nests"][0]["clips"]) == 2,
          "with two clips inside it, a media clip at 0 and a text clip at 2 s")

    open_it = ("unnest", {"clip": nest_clip})

    def clip_at(start):
        """The id of the only clip starting at `start` — how the top-level
        half names the clip the scoped half named by its fixture id, since
        `unnest` re-mints every one of them."""
        found = [c for c in project(mcp)["clips"] if c["start"] == start]
        if len(found) != 1:
            raise RuntimeError(f"expected one clip at {start}, got {len(found)}")
        return found[0]["id"]

    def track_at(start):
        found = [c for c in project(mcp)["clips"] if c["start"] == start]
        return found[0]["track"]

    base = fingerprint(mcp)
    mcp.call_with(open_it[0], open_it[1])
    untouched = contents(project(mcp))
    if not undo_to(mcp, base):
        check(False, "the untouched round trip undoes cleanly")
        return
    check(untouched != contents(reported),
          "opening the nest changes the reported clips at all — the baseline the rows are "
          "measured against is not the state they start in")

    # The road map names seven; the core's own table adds seven more; this
    # adds eighteen beyond that, chosen for what they could each get wrong
    # that the others could not — an op that mints a TRACK inside the nest
    # (detach_audio, add_background, add_blurred_background), one that reads
    # the CANVAS (add_zoom_action, add_background), one that reads the
    # SOURCE's pixel size (add_blurred_background), one that reads the plan's
    # segment (freeze_frame, rate_stretch), the range family, and the two
    # transition ops, whose overlap rule is judged inside the container.
    rows = [
        ("slip",
         ("slip", {"clip": first, "delta": SEC, "scope": nest}),
         lambda: ("slip", {"clip": clip_at(0), "delta": SEC})),
        ("trim_start",
         ("trim_start", {"clip": first, "to": SEC // 2, "scope": nest}),
         lambda: ("trim_start", {"clip": clip_at(0), "to": SEC // 2})),
        ("trim_end",
         ("trim_end", {"clip": first, "to": SEC + SEC // 2, "scope": nest}),
         lambda: ("trim_end", {"clip": clip_at(0), "to": SEC + SEC // 2})),
        ("split",
         ("split", {"clips": [first], "at": SEC, "scope": nest}),
         lambda: ("split", {"clips": [clip_at(0)], "at": SEC})),
        ("roll",
         ("roll", {"clip": second, "to": SEC + SEC // 2, "scope": nest}),
         lambda: ("roll", {"clip": clip_at(2 * SEC), "to": SEC + SEC // 2})),
        ("move_clip",
         ("move_clip", {"clips": [second], "delta": SEC, "scope": nest}),
         lambda: ("move_clip", {"clips": [clip_at(2 * SEC)], "delta": SEC})),
        ("delete",
         ("delete", {"clips": [first], "scope": nest}),
         lambda: ("delete", {"clips": [clip_at(0)]})),
        ("ripple_delete",
         ("ripple_delete", {"clips": [first], "scope": nest}),
         lambda: ("ripple_delete", {"clips": [clip_at(0)]})),
        ("duplicate",
         ("duplicate", {"clips": [second], "scope": nest}),
         lambda: ("duplicate", {"clips": [clip_at(2 * SEC)]})),
        ("set_video",
         ("set_video", {"clips": [first], "patch": {"opacity": 0.5}, "scope": nest}),
         lambda: ("set_video", {"clips": [clip_at(0)], "patch": {"opacity": 0.5}})),
        ("set_audio",
         ("set_audio", {"clips": [first], "patch": {"volume": 0.25}, "scope": nest}),
         lambda: ("set_audio", {"clips": [clip_at(0)], "patch": {"volume": 0.25}})),
        ("set_text",
         ("set_text", {"clips": [second], "patch": {"content": "Zed"}, "scope": nest}),
         lambda: ("set_text", {"clips": [clip_at(2 * SEC)], "patch": {"content": "Zed"}})),
        ("set_clip",
         ("set_clip", {"clips": [second], "patch": {"name": "Chapter"}, "scope": nest}),
         lambda: ("set_clip", {"clips": [clip_at(2 * SEC)], "patch": {"name": "Chapter"}})),
        ("set_enabled",
         ("set_enabled", {"clip": first, "audio": False, "scope": nest}),
         lambda: ("set_enabled", {"clip": clip_at(0), "audio": False})),
        ("set_speed",
         ("set_speed", {"clip": first, "rate": 2.0, "scope": nest}),
         lambda: ("set_speed", {"clip": clip_at(0), "rate": 2.0})),
        ("rate_stretch",
         ("rate_stretch", {"clip": first, "to_end": SEC, "scope": nest}),
         lambda: ("rate_stretch", {"clip": clip_at(0), "to_end": SEC})),
        ("freeze_frame",
         ("freeze_frame", {"clip": first, "at": SEC, "scope": nest}),
         lambda: ("freeze_frame", {"clip": clip_at(0), "at": SEC})),
        ("detach_audio",
         ("detach_audio", {"clip": first, "scope": nest}),
         lambda: ("detach_audio", {"clip": clip_at(0)})),
        ("add_action",
         ("add_action", {"clip": first, "at": 0, "duration": SEC, "scope": nest}),
         lambda: ("add_action", {"clip": clip_at(0), "at": 0, "duration": SEC})),
        ("add_zoom_action",
         ("add_zoom_action", {"clip": first, "at": 0, "duration": SEC, "scope": nest,
                              "region": {"x": 0, "y": 0, "width": 320, "height": 180}}),
         lambda: ("add_zoom_action", {"clip": clip_at(0), "at": 0, "duration": SEC,
                                      "region": {"x": 0, "y": 0,
                                                 "width": 320, "height": 180}})),
        ("set_transition",
         ("set_transition", {"clip": second, "kind": "fade_black", "scope": nest}),
         lambda: ("set_transition", {"clip": clip_at(2 * SEC), "kind": "fade_black"})),
        ("set_transition_duration",
         ("set_transition_duration", {"clip": second, "duration": SEC // 4, "scope": nest}),
         lambda: ("set_transition_duration", {"clip": clip_at(2 * SEC),
                                              "duration": SEC // 4})),
        ("add_text_clip",
         ("add_text_clip", {"track": nest_track, "at": 4 * SEC, "duration": SEC,
                            "scope": nest}),
         lambda: ("add_text_clip", {"track": track_at(0), "at": 4 * SEC,
                                    "duration": SEC})),
        ("add_shape_clip",
         ("add_shape_clip", {"track": nest_track, "at": 4 * SEC, "duration": SEC,
                             "scope": nest, "shape": {"kind": "rectangle"}}),
         lambda: ("add_shape_clip", {"track": track_at(0), "at": 4 * SEC,
                                     "duration": SEC, "shape": {"kind": "rectangle"}})),
        ("insert_clip",
         ("insert_clip", {"track": nest_track, "media": media, "at": SEC, "scope": nest}),
         lambda: ("insert_clip", {"track": track_at(0), "media": media, "at": SEC})),
        ("overwrite_clip",
         ("overwrite_clip", {"track": nest_track, "media": media, "at": SEC,
                             "scope": nest}),
         lambda: ("overwrite_clip", {"track": track_at(0), "media": media, "at": SEC})),
        ("insert_time",
         ("insert_time", {"at": SEC, "length": SEC, "scope": nest}),
         lambda: ("insert_time", {"at": SEC, "length": SEC})),
        ("lift_range",
         ("lift_range", {"from": SEC // 2, "to": SEC, "scope": nest}),
         lambda: ("lift_range", {"from": SEC // 2, "to": SEC})),
        ("ripple_delete_range",
         ("ripple_delete_range", {"from": SEC // 2, "to": SEC, "scope": nest}),
         lambda: ("ripple_delete_range", {"from": SEC // 2, "to": SEC})),
        ("ripple_delete_ranges",
         ("ripple_delete_ranges",
          {"ranges": [[SEC // 2, SEC], [2 * SEC, 2 * SEC + SEC // 2]], "scope": nest}),
         lambda: ("ripple_delete_ranges",
                  {"ranges": [[SEC // 2, SEC], [2 * SEC, 2 * SEC + SEC // 2]]})),
        ("add_background",
         ("add_background", {"color": [0, 0, 1, 1], "scope": nest}),
         lambda: ("add_background", {"color": [0, 0, 1, 1]})),
        ("add_blurred_background",
         ("add_blurred_background", {"clip": first, "scope": nest}),
         lambda: ("add_blurred_background", {"clip": clip_at(0)})),
    ]

    for name, inside, outside in rows:
        try:
            mcp.call_with(inside[0], inside[1])
            mcp.call_with(open_it[0], open_it[1])
            after_inside = contents(project(mcp))
            restored_a = undo_to(mcp, base)

            mcp.call_with(open_it[0], open_it[1])
            tool, args = outside()
            mcp.call_with(tool, args)
            after_outside = contents(project(mcp))
            restored_b = undo_to(mcp, base)
        except ToolError as error:
            check(False, f"{name}: both halves of the oracle apply ({error})")
            undo_to(mcp, base)
            continue

        if not (restored_a and restored_b):
            check(False, f"{name}: each half undoes back to the fixture "
                         f"({restored_a}, {restored_b})")
            continue

        same = after_inside == after_outside
        detail = ""
        if not same:
            for a, b in zip(after_inside, after_outside):
                if a != b:
                    detail = f" — first difference at start {a[0]}, track index {a[1]}"
                    break
            if len(after_inside) != len(after_outside):
                detail = f" — {len(after_inside)} clips against {len(after_outside)}"
        check(same, f"{name}: editing inside the nest and then opening it gives the same "
                    f"clip content as opening it and then editing{detail}")
        check(after_inside != untouched,
              f"…and {name} changed something, so the row is not two no-ops agreeing")


# ---- 2. the view, as get_project reports it ------------------------------


def view_part(mcp):
    track = fresh(mcp)
    first = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 0, "duration": 2 * SEC,
         "shape": {"kind": "rectangle"}})["new_clips"][0]
    media = mcp.call_with("import_media", {"path": MEDIA})["media"]
    mcp.call_with("add_marker", {"at": SEC, "name": "M"})
    mcp.call_with("nest", {"clips": [first]})

    outer = project(mcp)
    nest_id = outer["nests"][0]["id"]
    nest_clip = outer["clips"][0]
    # The document's canvas moves AFTER the nest is made, which is the only
    # way to tell "the nest's frozen size" from "the document's size" — they
    # are the same number at the moment a nest is born.
    mcp.call_with("set_canvas", {"width": 1280, "height": 720,
                                 "background": [0.1, 0.2, 0.3, 1]})
    outer = project(mcp)

    mcp.call_with("set_scope", {"nest": nest_id})
    reported = state(mcp)
    view = reported["project"]

    check((view["canvas"]["width"], view["canvas"]["height"]) == (640, 360),
          f"the view's canvas is the NEST's FROZEN size, not the document's — "
          f"{view['canvas']['width']}×{view['canvas']['height']} against the document's "
          f"{outer['canvas']['width']}×{outer['canvas']['height']}")
    check(view["canvas"]["fps"] == outer["canvas"]["fps"],
          "at the document's rate — a nest has none of its own, and there is one frame grid")
    check(view["canvas"]["background"] == outer["canvas"]["background"],
          f"with the document's background ({view['canvas']['background']}), moved after "
          "the nest was made so the two could be told apart")
    check(view["canvas"]["fit_new_clips"] == outer["canvas"]["fit_new_clips"]
          and view["canvas"]["timecode_frames"] == outer["canvas"]["timecode_frames"],
          "and the document's two switches")
    check([c["id"] for c in view["clips"]] == [n["id"] for n in outer["nests"][0]["clips"]],
          "its clips are the nest's, and the timeline clip that SHOWS the nest is not "
          f"among them ({[c['id'] for c in view['clips']]} against the timeline's "
          f"{[c['id'] for c in outer['clips']]})")
    check(view["markers"] == [],
          f"it has no markers, where the document has {len(outer['markers'])} — a nest has "
          "no markers[] and the timeline's are project time")
    check([mrow["id"] for mrow in view["media"]] == [mrow["id"] for mrow in outer["media"]],
          "its media is the document's, whole: one id space, and a view with none would "
          "fail validate on the first clip that shows a file")
    check(view["next_id"] == outer["next_id"],
          f"its next_id is the document's ({view['next_id']}) — an id minted inside is "
          "minted for the whole document")
    check(view["version"] == outer["version"],
          "and it is stamped the same format version")

    scoped_row = [n for n in view["nests"] if n["id"] == nest_id]
    check(len(scoped_row) == 1,
          "the scoped nest's own ROW is still in the view's nests[] — taking it out would "
          "dangle every OTHER nest's clip that shows it")
    if scoped_row:
        row = scoped_row[0]
        check(row["clips"] == [] and row["tracks"] == [],
              "…with its tracks and clips EMPTIED, because they are the view's top level "
              "and a second copy would double every id in validate's one uniqueness sweep")
        check((row["width"], row["height"]) == (640, 360),
              "…and its frozen size kept, which is what the view's canvas was taken from")

    check(reported["scope"] == nest_id and reported["scope_clip"] == nest_clip["id"],
          f"get_project reports the scope as the NEST id ({reported['scope']}) beside the "
          f"clip it was entered through ({reported['scope_clip']}) — the nest id is the "
          "number an op's own scope takes, so a caller copies it straight across")
    check([step["nest"] for step in reported["scope_path"]] == [nest_id],
          "and the whole trail under scope_path")
    check("A nest is OPEN" in reported["note"],
          "and the note says so, so a caller reading clips it cannot name on the timeline "
          "is told why before it files a bug")

    # Where a scoped edit LANDS. `contents` cannot see a track property, so
    # this is the one claim the oracle structurally could not make.
    if scoped_edit(mcp, "set_track",
                   {"track": view["tracks"][0]["id"], "solo": True, "scope": nest_id},
                   "a scoped set_track applies at all") is None:
        return
    mcp.call_with("insert_time", {"at": 0, "length": SEC, "scope": nest_id})
    mcp.call_with("set_scope", {})
    after = project(mcp)
    check(after["nests"][0]["tracks"][0]["solo"] is True,
          "a scoped set_track solos the NEST's track")
    check(all(t["solo"] is False for t in after["tracks"]),
          "and leaves every timeline track alone")
    check(after["markers"][0]["time"] == outer["markers"][0]["time"],
          f"a scoped insert_time does NOT move the timeline's marker (still at "
          f"{after['markers'][0]['time']}) — the merge never writes markers back, which "
          "is the half of core/src/scope.rs the mutation run called out")
    check(after["clips"][0]["start"] == nest_clip["start"]
          and after["clips"][0]["duration"] == nest_clip["duration"],
          "and the nest CLIP's own placement is untouched by everything done inside it")
    check(after["nests"][0]["clips"][0]["start"] == SEC,
          "while inside the nest the insert really did open a second of time")

    # `paste` is the ONE op that can GROW the media list from inside a scope
    # (`edit_paste.rs` matches media by PATH and brings a row the project has
    # not got), which is why `merge_scope` writes the view's media back at
    # all. Measured here because it is the only way the write-back has an
    # observable consequence: without it the merged parent would hold clips
    # inside the nest naming a media it does not have, and `check_clips`
    # would refuse the whole paste.
    before_media = {row["id"] for row in after["media"]}
    payload = {
        "media": [{"id": 900, "path": SPARE_MEDIA, "kind": "video",
                   "duration": 3 * SEC, "width": 640, "height": 360, "fps": [30, 1],
                   "has_video": True, "has_audio": False}],
        "clips": [{"id": 901, "track": 0, "start": 0, "duration": SEC,
                   "source": {"kind": "media", "media": 900, "in": 0},
                   "video": {}, "audio": {}}],
    }
    args = {"payload": payload, "at": 3 * SEC,
            "track": after["nests"][0]["tracks"][0]["id"], "scope": nest_id}
    try:
        pasted = mcp.call_with("paste", args)["new_clips"][0]
    except ToolError as error:
        # A build that dropped the write-back answers exactly this, naming
        # the media the merged parent has not got. Scored rather than raised.
        check(False, f"a paste inside a scope applies at all ({error})")
        return
    after = project(mcp)
    grown = [row for row in after["media"] if row["id"] not in before_media]
    check(len(grown) == 1 and grown[0]["path"] == SPARE_MEDIA,
          f"a paste INSIDE a scope brings its media row into the DOCUMENT's list "
          f"({[row['path'].rsplit('/', 1)[-1] for row in grown]}) — the one op that can "
          "grow it from in there, and the whole reason the merge writes media back")
    landed = [c for c in after["nests"][0]["clips"] if c["id"] == pasted]
    check(len(landed) == 1 and landed[0]["source"]["media"] == grown[0]["id"],
          "and the pasted clip, which is inside the nest, names that new row — the merged "
          "parent holds both halves or `check_clips` would have refused the paste outright")


# ---- 3. the frame ---------------------------------------------------------


def frame_part(mcp):
    track = fresh(mcp)
    # A shape BIGGER than the canvas, so the recipe's clip_rect (which cuts
    # the outer render) and the view's own canvas edge (which cuts the inner
    # one) are compared exactly where they act; an ellipse over it, so the
    # stack has more than one layer; and text, whose texture is measured by
    # the platform rather than by the core.
    big = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 0, "duration": 2 * SEC,
         "shape": {"kind": "rectangle", "width": 900, "height": 500,
                   "fill": [0.2, 0.3, 0.9, 1]}})["new_clips"][0]
    over = mcp.call_with("add_track", {})["new_tracks"][0]
    small = mcp.call_with(
        "add_shape_clip",
        {"track": over, "at": 0, "duration": 2 * SEC,
         "shape": {"kind": "ellipse", "width": 180, "height": 180,
                   "fill": [1, 0.4, 0, 1]}})["new_clips"][0]
    words = mcp.call_with("add_track", {})["new_tracks"][0]
    text = mcp.call_with(
        "add_text_clip",
        {"track": words, "at": 0, "duration": 2 * SEC,
         "text": {"content": "Nested Words"}})["new_clips"][0]
    mcp.call_with("nest", {"clips": [big, small, text]})

    reported = project(mcp)
    nest_id = reported["nests"][0]["id"]
    nest_clip = reported["clips"][0]
    at = nest_clip["start"]
    check(nest_clip["video"]["scale"] == 1 and nest_clip["video"]["x"] == 0
          and nest_clip["video"]["y"] == 0 and nest_clip["video"]["rotation"] == 0,
          "the nest clip is at the identity transform, which is the condition the road "
          "map's frame claim is stated under")

    def pair():
        mcp.call_with("set_scope", {})
        outer = Frame(frame_path(mcp, at))
        mcp.call_with("set_scope", {"nest": nest_id})
        inner = Frame(frame_path(mcp, 0))
        mcp.call_with("set_scope", {})
        return outer, inner

    for width, height, note in ((640, 360, "the nest's own frozen size, so the region is "
                                           "the WHOLE frame"),
                                (1280, 720, "a clean double"),
                                (1000, 800, "neither a multiple of it nor its aspect")):
        canvas = project(mcp)["canvas"]
        # An op that changes nothing is an IDENTITY (spec §5.5) and arrives
        # here as a ToolError, so the first size — which the fixture is
        # already at — is set only when it needs setting.
        if (canvas["width"], canvas["height"]) != (width, height):
            mcp.call_with("set_canvas", {"width": width, "height": height})
        outer, inner = pair()
        check((inner.width, inner.height) == (640, 360),
              f"with the document at {width}×{height}, render_frame INSIDE the nest writes "
              f"{inner.width}×{inner.height} — the nest's frozen canvas, not the document's")
        check((outer.width, outer.height) == (width, height),
              f"…while outside it writes {outer.width}×{outer.height}")
        differ, first = outer.region_differences(inner)
        check(differ == 0,
              f"…and the inner frame is byte-identical to the centred "
              f"{inner.width}×{inner.height} region of the outer one, all four channels, "
              f"{inner.width * inner.height} pixels ({width}×{height} is {note}); "
              f"{differ} differ{'' if first is None else ', first ' + str(first)}")
        if (width, height) != (640, 360):
            painted = outer.outside_region(inner)
            check(painted == 0,
                  f"…and every pixel OUTSIDE that region is the canvas background, so the "
                  f"region is the whole of what the nest drew ({painted} painted)")

    # The control. Without it the three rows above would pass against a
    # build whose two renders were the same picture for the wrong reason.
    mcp.call_with("set_canvas", {"width": 1280, "height": 720})
    mcp.call_with("set_video", {"clips": [nest_clip["id"]], "patch": {"scale": 0.5}})
    outer, inner = pair()
    differ, _ = outer.region_differences(inner)
    check(differ > inner.width * inner.height // 4,
          f"with the nest clip at scale 0.5 the same comparison FAILS, in "
          f"{differ} of {inner.width * inner.height} pixels — the identity above is a "
          "statement about the identity transform and not about two calls agreeing")
    mcp.call_with("undo", {})
    outer, inner = pair()
    differ, _ = outer.region_differences(inner)
    check(differ == 0, "and undoing the scale brings the region back byte-identical")


# ---- 4. one undo step per edit -------------------------------------------


def undo_part(mcp):
    track = fresh(mcp)
    first = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 0, "duration": 2 * SEC,
         "shape": {"kind": "rectangle", "fill": [0.9, 0.3, 0.2, 1]}})["new_clips"][0]
    mcp.call_with("nest", {"clips": [first]})
    reported = project(mcp)
    nest_id = reported["nests"][0]["id"]
    nest_clip = reported["clips"][0]["id"]
    inner = reported["nests"][0]["clips"][0]["id"]
    at = reported["clips"][0]["start"]

    before = digest(frame_path(mcp, at))

    # One edit OUTSIDE first, so that the scoped edits below are provably
    # their own steps rather than the only steps there are.
    mcp.call_with("set_video", {"clips": [nest_clip], "patch": {"opacity": 0.9}})
    outer_only = digest(frame_path(mcp, at))
    check(outer_only != before, "the outer edit changed the outer frame")

    mcp.call_with("set_scope", {"nest": nest_id})
    # Entering with no edit at all: the next undo must still be the outer
    # edit, which is what "entering is not an undo step" means.
    mcp.call_with("set_scope", {})
    mcp.call_with("set_scope", {"nest": nest_id})

    # Two sent with NO scope, which is how a gesture sends one — the open
    # view is what they follow — and one with an explicit scope that also
    # mints TWO objects, to show that is still a single step. Each is asked
    # for and then checked rather than assumed: a build in which an absent
    # scope stopped following the view would refuse these, and a section
    # that let that raise would leave every undo claim below it UNRUN.
    for tool, args in (("set_video", {"clips": [inner], "patch": {"opacity": 0.5}}),
                       ("trim_end", {"clip": inner, "to": SEC}),
                       ("add_background", {"color": [0, 0.6, 0.2, 1], "scope": nest_id})):
        try:
            mcp.call_with(tool, args)
        except ToolError as error:
            check(False, f"the scoped edit {tool} applies with the nest open ({error})")
            mcp.call_with("set_scope", {})
            return
    mcp.call_with("set_scope", {})
    edited = digest(frame_path(mcp, at))
    check(edited != outer_only, "the three scoped edits changed the outer frame")

    undone = []
    for _ in range(3):
        undone.append(mcp.call_with("undo", {})["undone"])
    check(undone == ["Add Background", "Trim End", "Video Properties"],
          f"three scoped edits are exactly three undo steps, newest first, each named: "
          f"{undone} — including the one that minted a track AND a clip")
    check(digest(frame_path(mcp, at)) == outer_only,
          "and after those three the outer frame is byte-identical to what it was before "
          "the nest was entered")

    fourth = mcp.call_with("undo", {})["undone"]
    check(fourth == "Video Properties",
          f"the FOURTH undo is the edit made outside ({fourth}), so entering the nest, "
          "leaving it, entering it again and leaving it again contributed no steps at all")
    check(digest(frame_path(mcp, at)) == before,
          "and the frame is byte-identical to the one before any edit")

    redone = mcp.call_with("redo", {})
    check(redone.get("redone") == "Video Properties" or redone.get("ok"),
          "and the redo stack survived the round trip in and out")


# ---- 5. set_scope, in all its shapes -------------------------------------


def set_scope_part(mcp):
    track = fresh(mcp)
    plain = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 0, "duration": SEC,
         "shape": {"kind": "rectangle"}})["new_clips"][0]
    later = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 2 * SEC, "duration": 2 * SEC,
         "shape": {"kind": "ellipse"}})["new_clips"][0]
    mcp.call_with("nest", {"clips": [later]})
    reported = project(mcp)
    outer_nest = reported["nests"][0]["id"]
    outer_clip = [c for c in reported["clips"] if c["source"]["kind"] == "nest"][0]
    inner_ids = [c["id"] for c in reported["nests"][0]["clips"]]
    if scoped_edit(mcp, "nest", {"clips": inner_ids, "scope": outer_nest},
                   "a scoped nest builds the second level this section needs") is None:
        return
    reported = project(mcp)
    inner_nest = [n["id"] for n in reported["nests"] if n["id"] != outer_nest][0]
    inner_clip = [c["id"] for c in
                  [n for n in reported["nests"] if n["id"] == outer_nest][0]["clips"]
                  if c["source"]["kind"] == "nest"][0]

    mcp.call_with("set_playhead", {"t": 3 * SEC})
    mcp.call_with("set_range", {"start": 0, "end": SEC})

    entered = mcp.call_with("set_scope", {"nest": outer_nest})
    check(entered["scope"] == outer_nest and entered["scope_clip"] == outer_clip["id"],
          f"{{nest}} enters through the earliest TIMELINE clip that shows it "
          f"(clip {entered['scope_clip']})")
    check(entered["playhead"] == 3 * SEC - outer_clip["start"],
          f"and maps the playhead in by the nest clip's start — {3 * SEC} outside becomes "
          f"{entered['playhead']} inside, the nest clip starting at {outer_clip['start']}, "
          "so the frame under it does not move")
    check("in_out_range" not in state(mcp),
          "and CLEARS the in/out range, because a pair of ticks means one thing in a nest "
          "and another to an export")

    by_clip = mcp.call_with("set_scope", {"clip": outer_clip["id"]})
    check(by_clip["scope"] == outer_nest,
          "{clip} names the same destination — the precise spelling, and what a "
          "double-click sends")

    deep = mcp.call_with("set_scope", {"clip": inner_clip})
    check(deep["scope"] == inner_nest and len(deep["scope_path"]) == 2,
          f"{{clip}} is ABSOLUTE: from one level in, naming a clip two levels down lands "
          f"there in one call ({[s['nest'] for s in deep['scope_path']]})")
    check([step["name"] for step in deep["scope_path"]] == ["Nest 1", "Nest 2"],
          f"and the trail carries each step's own name, which is what the breadcrumb "
          f"prints: {[step['name'] for step in deep['scope_path']]}")

    up = mcp.call_with("set_scope", {"nest": outer_nest})
    check(up["scope"] == outer_nest and len(up["scope_path"]) == 1,
          "and it is absolute in the other direction too — naming the outer nest from "
          "inside the inner one comes UP one level rather than failing")

    out = mcp.call_with("set_scope", {})
    check(out["scope"] is None,
          "{} with neither argument comes back to the timeline")
    check(out["project"]["selection"] == [outer_clip["id"]],
          f"and re-selects the nest clip it was entered through "
          f"({out['project']['selection']})")
    check(state(mcp)["playhead"] == 3 * SEC,
          "with the playhead mapped back out to where it started")

    for label, args, phrase in (
            ("a nest no TIMELINE clip shows",
             {"nest": inner_nest}, "No clip on the timeline shows nest"),
            ("both arguments at once",
             {"nest": outer_nest, "clip": outer_clip["id"]}, "not both"),
            ("a clip that shows no nest",
             {"clip": plain}, "does not show a nest"),
            ("an unknown nest", {"nest": 4242}, "no nest with id 4242"),
            ("an unknown clip", {"clip": 4242}, "in this timeline or in any of its nests")):
        message = refusal(mcp, "set_scope", args)
        check(message is not None and phrase in message,
              f"set_scope refuses {label} by name: {message!r}")

    # The nest the VIEW cannot reach is still reachable by an op, and the
    # refusal says so — a claim about the refusal's usefulness, not its text.
    message = refusal(mcp, "set_scope", {"nest": inner_nest})
    check(message is not None and f"scope: {inner_nest}" in message,
          "…and the one it cannot reach names the way in that does not need a view: send "
          "the op itself with that scope")
    mcp.call_with("set_video", {"clips": [inner_ids[0]], "patch": {"opacity": 0.5},
                                "scope": inner_nest})
    deepest = [n for n in project(mcp)["nests"] if n["id"] == inner_nest][0]
    check(deepest["clips"][0]["video"]["opacity"] == 0.5,
          "which works: an op reached the nest the view could not")


# ---- 6. the refusals, and the order they come in -------------------------


def refusal_part(mcp):
    track = fresh(mcp)
    media = mcp.call_with("import_media", {"path": MEDIA})["media"]
    clip = mcp.call_with("add_clip", {"track": track, "media": media, "at": 0})
    clip = clip["new_clips"][0]
    mcp.call_with("trim_end", {"clip": clip, "to": 2 * SEC})
    # A SECOND media, imported and never placed. `remove_media` refuses a
    # file that clips still show ("used by 1 clip") in the app, ahead of the
    # core, so without an unused row that refusal is the one this section
    # would score — a sentence with nothing to do with scoping.
    spare = mcp.call_with(
        "import_media", {"path": UNUSED_MEDIA})["media"]
    marker = mcp.call_with("add_marker", {"at": SEC, "name": "M"})["new_markers"][0]
    mcp.call_with("nest", {"clips": [clip]})
    reported = project(mcp)
    nest_id = reported["nests"][0]["id"]
    nest_clip = reported["clips"][0]["id"]
    inner = reported["nests"][0]["clips"][0]["id"]
    descriptor = {k: v for k, v in reported["media"][0].items() if k != "id"}

    # All seven, each given arguments GOOD enough to reach the core. Four of
    # them are refused by the app's own id readers otherwise, and one by its
    # descriptor reader, which is why this fixture carries a marker, a media
    # in use and a media in nobody's use at all.
    seven = {
        "add_marker": {"at": 0, "scope": nest_id},
        "set_marker": {"marker": marker, "name": "x", "scope": nest_id},
        "remove_marker": {"marker": marker, "scope": nest_id},
        "set_canvas": {"width": 800, "height": 450, "scope": nest_id},
        "add_media": {"descriptor": descriptor, "scope": nest_id},
        "relink_media": {"media": media, "path": MEDIA, "scope": nest_id},
        "remove_media": {"media": spare, "scope": nest_id},
    }
    check(sorted(seven) == sorted(REFUSED_INSIDE),
          "the seven ops with no meaning inside a nest are the ones this section sends")
    for tool, args in seven.items():
        message = refusal(mcp, tool, args)
        check(message == f"{tool} has no meaning inside nest {nest_id}",
              f"{tool} inside a nest refuses with core/src/scope.rs's own sentence: "
              f"{message!r}")
    # The control for the whole group: the SAME call without a scope works,
    # so the seven refusals above are the scope's doing and not seven
    # arguments that were wrong anyway.
    check(refusal(mcp, "remove_media", {"media": spare}) is None,
          "and remove_media of that same unused media, unscoped, applies — so what the "
          "seven refuse is the scope and not the arguments")
    mcp.call_with("undo", {})

    # The order. `scope` decides which document the caller thinks it is
    # editing, so a mistake there outranks a mistake in anything else.
    both_wrong = refusal(mcp, "trim_start", {"clip": 9999, "to": 0, "scope": 4242})
    check(both_wrong is not None and both_wrong.startswith("no nest with id 4242"),
          f"an unknown SCOPE is answered ahead of a bad clip id in the same call: "
          f"{both_wrong!r}")
    also = refusal(mcp, "add_marker", {"at": 0, "scope": 4242})
    check(also is not None and also.startswith("no nest with id 4242"),
          "and ahead of the op being classified at all, so a document-level op with an "
          f"unknown scope hears about the scope: {also!r}")

    scoped_miss = refusal(mcp, "trim_start", {"clip": nest_clip, "to": 0, "scope": nest_id})
    check(scoped_miss is not None
          and scoped_miss.startswith(f"No clip has id {nest_clip} inside nest {nest_id}")
          and "drop the scope" in scoped_miss,
          f"naming a TIMELINE clip through a scope is refused by name, and the message says "
          f"how to get back out: {scoped_miss!r}")

    mcp.call_with("set_scope", {"nest": nest_id})
    open_miss = refusal(mcp, "trim_start", {"clip": nest_clip, "to": 0})
    check(open_miss is not None and "that nest is OPEN in the view" in open_miss,
          f"…and with the nest OPEN rather than named, the same miss gets the other "
          f"sentence, because dropping an argument does nothing about a view: {open_miss!r}")
    mcp.call_with("set_scope", {})

    for value, spelling in ((-1, "-1"), (1.5, "1.5"), ("three", '"three"'), (True, "true")):
        message = refusal(mcp, "trim_start", {"clip": inner, "to": 0, "scope": value})
        check(message == f"scope must be a nest id, not {spelling}",
              f"a scope that is not a nest id is refused by VALUE ({spelling}): {message!r}")

    # An unscoped call must behave EXACTLY as it did before phase 9.
    plain_miss = refusal(mcp, "trim_start", {"clip": inner, "to": 0})
    check(plain_miss == f"No clip has id {inner}. get_project lists the clips.",
          f"an unscoped call naming a clip inside a nest is refused with the M2 sentence, "
          f"byte for byte — spec §4.4's limit, still true for every op that does not carry "
          f"a scope: {plain_miss!r}")
    check(refusal(mcp, "trim_start", {"clip": inner, "to": 0, "scope": None}) == plain_miss,
          "and an explicit null scope is the same call as no scope at all — the envelope's "
          "standing rule that absent and null mean one thing")
    stray = refusal(mcp, "get_project", {"scope": 4242})
    check(stray == "get_project does not take scope. It takes project."
          and (refusal(mcp, "render_frame", {"t": 0, "scope": 4242}) or "").startswith(
              "render_frame does not take scope. It takes "),
          "while a scope sent to a tool that is not an op is refused by the argument gate as "
          "a key that tool never published (kpgalligan/reelcut#21) — until then it was the "
          f"ignored extra key, read only for the ops: {stray!r}")

    # The seam the orchestrator measured and fixed: an EXPLICIT scope
    # outranks the open view, in both directions.
    second = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 3 * SEC, "duration": SEC,
         "shape": {"kind": "rectangle"}})["new_clips"][0]
    mcp.call_with("nest", {"clips": [second]})
    other = [n["id"] for n in project(mcp)["nests"] if n["id"] != nest_id][0]
    other_clip = [n for n in project(mcp)["nests"] if n["id"] == other][0]["clips"][0]["id"]
    mcp.call_with("set_scope", {"nest": nest_id})
    landed = refusal(mcp, "set_video", {"clips": [other_clip], "patch": {"opacity": 0.25},
                                        "scope": other})
    check(landed is None,
          f"an op carrying an explicit scope applies while a DIFFERENT nest is open "
          f"({landed})")
    mcp.call_with("set_scope", {})
    nests = {n["id"]: n for n in project(mcp)["nests"]}
    check(nests[other]["clips"][0]["video"]["opacity"] == 0.25,
          "an op carrying an explicit scope while a DIFFERENT nest is open lands in the "
          "one it named")
    check(nests[nest_id]["clips"][0]["video"]["opacity"] == 1,
          "and not in the one the view had open — the defect that used to answer ok and "
          "edit the wrong container")


# ---- 7. the wide Err arm --------------------------------------------------


def wide_err_part(mcp):
    """The two invariants a view cannot see (`core/src/scope.rs`): an op can
    be perfectly valid against the view and the scoped apply still `Err`.

    Nothing but a document AT a cap exercises this, which is why it is here
    and not in the core's own file alone — over the wire it is also the one
    place a caller learns that reading the result matters."""
    track = fresh(mcp)
    clip = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 0, "duration": SEC,
         "shape": {"kind": "rectangle"}})["new_clips"][0]
    mcp.call_with("nest", {"clips": [clip]})
    nest_id = project(mcp)["nests"][0]["id"]

    def totals():
        """(tracks across every container, nests), or None when the document
        can no longer be read at all.

        None is not defensive tidying: a build that accepted the 65th track
        would leave a document its own writer refuses, and reading it would
        raise here and abort the section — a crash is a worse detection than
        a failure, so the answer is asked for and then checked."""
        try:
            reported = project(mcp)
        except RuntimeError:
            return None
        return (len(reported["tracks"]) + sum(len(n["tracks"]) for n in reported["nests"]),
                len(reported["nests"]))

    # ---- the caps ----
    while totals()[0] < 63:
        mcp.call_with("add_track", {})
    check(totals()[0] == 63, f"the document is one track under the cap ({totals()[0]} of 64, "
                             "counted across the timeline AND every nest, which is what "
                             "check_caps sums)")
    view_tracks = len([n for n in project(mcp)["nests"] if n["id"] == nest_id][0]["tracks"])
    check(view_tracks < 10,
          f"while the nest the op will be applied in holds {view_tracks} — the view is "
          "nowhere near a cap, which is the whole point")
    added = scoped_edit(mcp, "add_track", {"scope": nest_id},
                        "a scoped add_track at 63 applies")
    if added is None:
        return
    check("new_tracks" in added and totals()[0] == 64,
          "a scoped add_track at 63 SUCCEEDS, so the view is not refusing on its own")
    message = refusal(mcp, "add_track", {"scope": nest_id})
    check(message == "too many tracks: 65 (max 64)",
          f"and the very next one is an Err naming the DOCUMENT's total, although the view "
          f"it was applied to holds {view_tracks + 1}: {message!r}")
    after = totals()
    check(after is not None and after[0] == 64,
          "with the document unchanged — a refusal on the merged parent leaves nothing "
          f"half written ({after})")

    # ---- the depth ----
    track = fresh(mcp)
    clip = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 0, "duration": SEC,
         "shape": {"kind": "rectangle"}})["new_clips"][0]
    mcp.call_with("nest", {"clips": [clip]})
    scope = project(mcp)["nests"][0]["id"]
    depth = 1
    while depth < 8:
        inside = [n for n in project(mcp)["nests"] if n["id"] == scope][0]
        if scoped_edit(mcp, "nest",
                       {"clips": [c["id"] for c in inside["clips"]], "scope": scope},
                       f"a scoped nest builds level {depth + 1} of the ladder") is None:
            return
        inside = [n for n in project(mcp)["nests"] if n["id"] == scope][0]
        scope = [c["source"]["project"] for c in inside["clips"]
                 if c["source"]["kind"] == "nest"][0]
        depth += 1
    built = totals()
    check(built is not None and built[1] == 8,
          f"eight levels of nesting built one scoped `nest` at a time ({built} ) — every "
          "one of them an op that could only be sent because a scope exists")
    message = refusal(mcp, "nest",
                      {"clips": [c["id"] for c in
                                 [n for n in project(mcp)["nests"]
                                  if n["id"] == scope][0]["clips"]],
                       "scope": scope})
    check(message is not None and message.startswith("nests are more than 8 deep at nest"),
          f"a ninth is an Err — check_nesting starts every walk at level 1, so the view "
          f"cannot see how deep it already sits and only the merged parent can: {message!r}")
    after = totals()
    check(after is not None and after[1] == 8,
          "and the nest the view minted on the way is not in the document: the merge is "
          f"judged whole or not at all ({after})")


# ---- 8. a file of every earlier version ----------------------------------


def versions_part(mcp):
    """The core's `schema_v*.rs` tests own this claim in-process; what the
    live server adds is that the whole APP opens each one — the importer,
    the snapshot, the timeline and the agent — and that a file from the
    future is still refused at the door."""
    os.makedirs(WORK, exist_ok=True)

    def package(version, extra_clips=()):
        path = os.path.join(WORK, f"phase9-v{version}.reelcut")
        os.makedirs(path, exist_ok=True)
        document = {
            "version": version,
            "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
            "media": [], "tracks": [{"id": 2, "name": "T"}],
            "clips": [{"id": 3, "track": 2, "start": 0, "duration": 2 * SEC,
                       "source": {"kind": "text"}, "video": {},
                       "text": {"content": f"v{version}"}}] + list(extra_clips),
            "markers": [], "next_id": 20,
        }
        with open(os.path.join(path, "project.json"), "w") as handle:
            json.dump(document, handle, indent=1)
        return path

    # Version 1 gets the one shape serde cannot absorb with a default: a nest
    # clip whose `project` was a PATH STRING, which `migrate_1_to_2` rewrites
    # into a named empty Nest.
    old_nest = {"id": 4, "track": 2, "start": 2 * SEC, "duration": 2 * SEC,
                "source": {"kind": "nest", "project": "/gone/Old Group.reelcut"},
                "video": {}}
    for version in range(1, CURRENT_VERSION + 1):
        extra = (old_nest,) if version == 1 else ()
        try:
            mcp.call_with("open_project", {"path": package(version, extra)})
        except ToolError as error:
            check(False, f"a version-{version} file opens in the built app ({error})")
            continue
        reported = project(mcp)
        check(reported["version"] == CURRENT_VERSION
              and reported["clips"][0]["text"]["content"] == f"v{version}",
              f"a version-{version} file opens in the built app and is stamped "
              f"{CURRENT_VERSION} in memory, its content intact")

    # The migrated nest is the interesting one: version 1's path string is
    # now a real Nest, and phase 9 can scope into it.
    mcp.call_with("open_project", {"path": package(1, (old_nest,))})
    reported = project(mcp)
    check(len(reported["nests"]) == 1
          and reported["nests"][0]["name"] == "/gone/Old Group.reelcut"
          and reported["nests"][0]["clips"] == [],
          "version 1's path-string nest clip came back as a NAMED EMPTY nest, which is what "
          "migrate_1_to_2 promises")
    migrated = reported["nests"][0]["id"]
    entered = mcp.call_with("set_scope", {"nest": migrated})
    check(entered["scope"] == migrated and project(mcp)["clips"] == [],
          "and phase 9 can scope into it: an empty container is a container")
    mcp.call_with("add_track", {"scope": migrated})
    mcp.call_with("set_scope", {})
    check(len(project(mcp)["nests"][0]["tracks"]) == 1,
          "…and edit in it, which is the one thing a project rescued from version 1 could "
          "never have had done to it before")

    # ONE PAST the current version, read off the header so it moves with
    # every bump by itself (the trap `core/CLAUDE.md` records was a literal
    # here that had to be walked forward by hand).
    past = CURRENT_VERSION + 1
    future = refusal(mcp, "open_project", {"path": package(past)})
    check(future is not None
          and f"version {past} is newer than this build understands" in future,
          f"and a file one version PAST the current one is still refused at the door: "
          f"{future!r}")


# ---- 9. an inherited scope: the marker ticks, and the landing -------------


def marker_scope_part(mcp):
    """Phase 9's two MCP-coherence fixes, measured where their evidence
    belongs. The review's fix wave proved them in
    `work/lane9_marker_scope_mcp.py`, which was untracked, and a fix with no
    permanent proof is the shape this tree does not accept; the checks are
    that script's, sentence for sentence, because their sentences are the
    fixes' rationale.

    Both are about a scope the caller did not ASK for. `set_scope` opens a
    nest and every later op inherits it; the core is handed a `scope` key
    either way and cannot tell an inherited one from an explicit one, so two
    things are the APP's to decide (`AgentServer+Scope.swift`):

    (a) A marker's time is the TIMELINE's, and inside a nest every tick in a
        call — `add_marker`'s default `at`, the playhead, most of all — is
        measured from the nest's own zero. So `add_marker`, and `set_marker`
        when it carries a `time`, are refused on an inherited scope BEFORE
        the edit (`checkDocumentLevelTicks`), with the way out in the
        sentence; `set_marker`'s name, chapter and color mean the same thing
        in either container and are accepted. An EXPLICIT scope still
        reaches `core/src/scope.rs`'s own refusal, because asking is a
        different act from inheriting — section 6 reads that sentence with
        the nest NAMED, and what is new here is that it is unchanged with
        the nest OPEN as well.

    (b) A result reports where its ops actually LANDED (`scopeLanding`): the
        nest they were stamped with under `scope`, and any op the
        document-level list sent to the DOCUMENT instead under
        `document_ops`. It used to echo the open view on every result, so a
        `set_canvas` inside a nest answered `scope: N` while it had changed
        the document's canvas.

    The fixture is section 10's plus a marker, and the nest clip starts at
    2 s for the reason it does there: nest-local zero and timeline zero are
    then two different numbers, so the placement (a) refuses is VISIBLE in
    the playhead the view reports. The `outer` snapshot is taken before the
    unscoped checks add and remove a second marker, so it describes the
    document every later "nothing was placed" is measured against.

    Two mutants gate it, each on a copy of the tree and never the working
    one (tools/proof/README.md): `checkDocumentLevelTicks` made a no-op fails
    five of these checks, and `scopeLanding` put back to the unconditional
    echo fails five others. The README names which."""
    track = fresh(mcp)
    # A nest clip that starts at 2 s, so the nest's zero and the timeline's
    # are two different numbers and the playhead mapping is visible.
    inner_src = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 2 * SEC, "duration": 2 * SEC,
         "shape": {"kind": "rectangle"}})["new_clips"][0]
    marker = mcp.call_with("add_marker", {"at": SEC, "name": "M"})["new_markers"][0]
    mcp.call_with("nest", {"clips": [inner_src]})
    outer = project(mcp)
    nest_id = outer["nests"][0]["id"]
    nest_clip = outer["clips"][0]
    inner = outer["nests"][0]["clips"][0]["id"]
    check(nest_clip["start"] == 2 * SEC, "fixture: the nest clip starts at 2 s")

    def marker_row(ident):
        """The timeline's marker with this id, or None. Read by ID and never
        by index: `add_marker` pushes and nothing sorts, so `markers[0]`
        would hold today, but a check leaning on that is a check on the
        array's order and not on the marker."""
        return next((x for x in project(mcp)["markers"] if x["id"] == ident), None)

    # -- the unscoped path is untouched: no nest open, no scope named --
    r = mcp.call_with("add_marker", {"at": 3 * SEC, "name": "N"})
    check("scope" not in r and "document_ops" not in r,
          f"with no nest open an add_marker result carries neither key: {sorted(r)}")
    second = r["new_markers"][0]
    r = mcp.call_with("set_marker", {"marker": second, "time": 3 * SEC + SEC // 2})
    check("scope" not in r and "document_ops" not in r,
          "…and neither does a set_marker that moves one")
    r = mcp.call_with("set_clip", {"clips": [nest_clip["id"]], "patch": {"name": "Group"}})
    check("scope" not in r and "document_ops" not in r,
          "…nor an ordinary clip edit on the timeline")
    mcp.call_with("remove_marker", {"marker": second})

    # -- the mismatch that makes (a) a wrong PLACEMENT --
    mcp.call_with("set_playhead", {"t": 2 * SEC})
    mcp.call_with("set_scope", {"nest": nest_id})
    view = state(mcp)
    check(view["scope"] == nest_id, f"the nest is open (scope {view['scope']})")
    check(view["playhead"] == 0,
          f"the playhead reads {view['playhead']} in here where the timeline's is "
          f"{2 * SEC} — nest-local, measured from the nest clip's start")
    check(view["project"]["markers"] == [],
          "and get_project answers NO markers, so every marker id and time in this call "
          "came from a container the caller cannot see from in here")

    # -- (a) the two tick-carrying marker tools are refused --
    before = len(outer["markers"])
    msg = refusal(mcp, "add_marker", {})
    check(msg is not None
          and msg.startswith(f"add_marker has no meaning inside nest {nest_id}"),
          f"add_marker with no `at` — the one that would have taken the nest-local "
          f"playhead — is refused with a sentence that opens as the core's does: {msg!r}")
    check("set_scope with no arguments comes back out" in (msg or ""),
          "…and the message carries the way out")
    msg2 = refusal(mcp, "add_marker", {"at": 3 * SEC, "name": "X"})
    # `is not None` is load-bearing. Under a build whose refusal is gone both
    # calls SUCCEED, both answers are None, and `None == None` would score
    # this green — the lane script had it that way, and the refusal mutant
    # killed one check fewer than it reads as killing.
    check(msg2 is not None and msg2 == msg,
          "an explicit `at` is refused identically — every tick in the call is "
          "the nest's, so naming one changes nothing")
    msg3 = refusal(mcp, "set_marker", {"marker": marker, "time": 0})
    check(msg3 is not None
          and msg3.startswith(f"set_marker's time has no meaning inside nest {nest_id}"),
          f"set_marker's `time` is refused by ARGUMENT name: {msg3!r}")
    mcp.call_with("set_scope", {})
    after = project(mcp)
    check(len(after["markers"]) == before
          and [x["time"] for x in after["markers"]] == [x["time"] for x in outer["markers"]],
          "and nothing was placed: the timeline's markers are exactly what they were")
    mcp.call_with("set_scope", {"nest": nest_id})

    # -- (a) what is NOT refused, and lands on the document --
    r = mcp.call_with("set_marker", {"marker": marker, "name": "Renamed"})
    check("scope" not in r and r.get("document_ops") == ["set_marker"],
          f"set_marker {{name}} applies in here and the result says it went to the "
          f"DOCUMENT: scope={r.get('scope')!r} document_ops={r.get('document_ops')!r}")
    mcp.call_with("set_scope", {})
    renamed = marker_row(marker)
    check(renamed is not None and renamed["name"] == "Renamed",
          "…and the timeline's marker really is renamed")
    mcp.call_with("set_scope", {"nest": nest_id})
    r = mcp.call_with("set_marker", {"marker": marker, "chapter": True})
    check("scope" not in r and r.get("document_ops") == ["set_marker"],
          "so does set_marker {chapter}")
    r = mcp.call_with("remove_marker", {"marker": marker})
    check("scope" not in r and r.get("document_ops") == ["remove_marker"],
          f"and remove_marker, which names an id and reads no clock: "
          f"document_ops={r.get('document_ops')!r}")
    mcp.call_with("undo", {})
    # That undo is the next group's PRECONDITION as much as a claim of its
    # own: `markerArg` resolves against the timeline's markers, so a marker
    # the undo had not put back would make three refusals below answer "No
    # marker has id" and read as scope refusals gone wrong. Scored, then,
    # rather than assumed — an op that went to the document undoes ON the
    # document, renamed and chaptered as it was, with the nest still open.
    mcp.call_with("set_scope", {})
    restored = marker_row(marker)
    check(restored is not None and restored["name"] == "Renamed"
          and restored["chapter"] is True,
          "…and undoing it with the nest still open puts the marker back on the DOCUMENT, "
          "renamed and chaptered as it was")
    mcp.call_with("set_scope", {"nest": nest_id})

    # -- (a) an EXPLICIT scope still reaches the core --
    msg = refusal(mcp, "add_marker", {"at": 0, "scope": nest_id})
    check(msg == f"add_marker has no meaning inside nest {nest_id}",
          f"add_marker with an explicit scope hears core/src/scope.rs's own sentence, "
          f"unchanged: {msg!r}")
    msg = refusal(mcp, "set_marker", {"marker": marker, "name": "x", "scope": nest_id})
    check(msg == f"set_marker has no meaning inside nest {nest_id}",
          f"…and so does a set_marker the inherited path ACCEPTS, because asking is a "
          f"different act from inheriting: {msg!r}")
    msg = refusal(mcp, "remove_marker", {"marker": marker, "scope": nest_id})
    check(msg == f"remove_marker has no meaning inside nest {nest_id}",
          "…and remove_marker")

    # -- (a) the documented cost of the placement --
    msg = refusal(mcp, "add_marker", {"at": "half past"})
    check(msg is not None and "add_marker has no meaning" not in msg,
          f"a call whose `at` is ALSO unreadable hears about the `at` first — the handler "
          f"reads its arguments before the edit: {msg!r}")
    check(msg == "at must be a time in ticks (600000 per second).",
          "…and what it hears is AgentServer+Arguments.swift's own sentence, verbatim, so "
          "the voice above is the argument reader's and not a third one")

    # -- (b) the echoed scope is what was STAMPED --
    r = mcp.call_with("set_clip", {"clips": [inner], "patch": {"name": "Inside"}})
    check(r.get("scope") == nest_id and "document_ops" not in r,
          f"a scoped edit inherited from the view reports the nest it landed in and "
          f"nothing else: scope={r.get('scope')!r}")
    r = mcp.call_with("set_canvas", {"width": 800, "height": 450})
    check("scope" not in r and r.get("document_ops") == ["set_canvas"],
          f"a DOCUMENT-level edit inherited from the same view reports no scope and names "
          f"the op that went to the document — it used to answer scope={nest_id}: "
          f"{ {k: r[k] for k in ('scope', 'document_ops') if k in r} }")
    mcp.call_with("set_scope", {})
    check(project(mcp)["canvas"]["width"] == 800,
          "…and it really did land on the document's canvas, not the nest's frozen size")
    check(project(mcp)["nests"][0]["width"] == 640,
          "…which is still 640, exactly as before")
    mcp.call_with("set_scope", {"nest": nest_id})
    spare = mcp.call_with("import_media", {"path": UNUSED_MEDIA})["media"]
    r = mcp.call_with("remove_media", {"media": spare})
    check("scope" not in r and r.get("document_ops") == ["remove_media"],
          f"remove_media inherited answers the same way: {r.get('document_ops')!r}")

    # -- (b) an EXPLICIT scope is echoed as itself --
    r = mcp.call_with(
        "set_clip", {"clips": [inner], "patch": {"name": "Named"}, "scope": nest_id})
    check(r.get("scope") == nest_id and "document_ops" not in r,
          "an op carrying its own scope reports it")
    mcp.call_with("set_scope", {})
    r = mcp.call_with(
        "set_clip", {"clips": [inner], "patch": {"name": "Again"}, "scope": nest_id})
    check(r.get("scope") == nest_id and "document_ops" not in r,
          "…with no nest open at all, which is the case effectiveScope and the stamp agree on")
    r = mcp.call_with("set_clip", {"clips": [nest_clip["id"]], "patch": {"name": "Outer"}})
    check("scope" not in r and "document_ops" not in r,
          "and a plain timeline edit still carries neither key")
    # Closed already, two calls up; closed again so the section's last act
    # says so, the way section 10's does.
    mcp.call_with("set_scope", {})


# ---- 10. the documented limits, pinned ------------------------------------


def limits_part(mcp):
    """Two behaviours road map 2's phase 9 recorded as limits rather than
    fixed. They are scored here so that a later change is NOTICED — a limit
    nobody measures is a limit nobody knows has moved."""
    track = fresh(mcp)
    clip = mcp.call_with(
        "add_shape_clip",
        {"track": track, "at": 2 * SEC, "duration": 2 * SEC,
         "shape": {"kind": "rectangle"}})["new_clips"][0]
    mcp.call_with("nest", {"clips": [clip]})
    reported = project(mcp)
    nest_id = reported["nests"][0]["id"]
    start = reported["clips"][0]["start"]

    document_duration = state(mcp)["duration"]
    mcp.call_with("set_scope", {"nest": nest_id})
    nest_duration = state(mcp)["duration"]
    check(nest_duration < document_duration,
          f"the nest is shorter than the document that shows it ({nest_duration} against "
          f"{document_duration}), which is what makes the next two readable")

    mcp.call_with("set_playhead", {"t": SEC})
    check(state(mcp)["playhead"] == SEC,
          "inside a nest set_playhead is NEST-LOCAL: what you send is what you get back")

    # The limit road map 2 records: `set_range`'s handler defaults its end to
    # `document.project.duration` where the playhead is `editedProject`'s, so
    # an open-ended range inside a nest runs to the whole TIMELINE's end.
    open_ended = mcp.call_with("set_range", {"start": 0})["in_out_range"]
    check(open_ended["end"] == document_duration,
          f"…while set_range's open end defaults to the DOCUMENT's duration "
          f"({open_ended['end']}) and not the nest's ({nest_duration}): set_range stays in "
          "PROJECT time inside a nest where set_playhead is nest-local. Road map 2 records "
          "that as a limit rather than a defect; this check is here so that changing it is "
          "noticed rather than discovered")

    mcp.call_with("set_scope", {})
    outside = state(mcp)
    check(outside["playhead"] == SEC + start,
          f"leaving maps the playhead back OUT ({outside['playhead']}), so the frame under "
          "it does not move")
    check("in_out_range" not in outside,
          "and CLEARS the range on the way out as well as on the way in, so a pair of ticks "
          "chosen inside a nest can never reach an export meaning something else")


def main():
    for needed, why in (
            (MEDIA, "eight of section 1's thirty-two oracle rows mean nothing on a shape"),
            (UNUSED_MEDIA,
             "section 6 needs a media NOBODY shows, or remove_media is refused for being "
             "in use before the scope is ever considered"),
            (SPARE_MEDIA,
             "section 2's paste payload names a file the project has never seen, which is "
             "how the merge's media write-back is made observable")):
        if not os.path.exists(needed):
            print(f"{needed} is needed: {why}. tools/proof/README.md says how to make the "
                  "test media.")
            return 2
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)
    print(f"phase 9 — Inside the nest, against 127.0.0.1:{PORT}")

    section("0 — the catalog, and rc_op_names through it", catalog_part, mcp)
    section("1 — the oracle: inside-then-open equals open-then-inside", oracle_part, mcp)
    section("2 — the view, as get_project reports it, and where an edit lands",
            view_part, mcp)
    section("3 — a frame rendered inside, against the outer frame's region",
            frame_part, mcp)
    section("4 — one undo step per edit; entering and leaving are none", undo_part, mcp)
    section("5 — set_scope, in all its shapes", set_scope_part, mcp)
    section("6 — the seven refusals, the order, and what an unscoped call still does",
            refusal_part, mcp)
    section("7 — the wide Err arm: the caps and the depth, which a view cannot see",
            wide_err_part, mcp)
    section("8 — a file of every earlier version still opens", versions_part, mcp)
    section("9 — an inherited scope: the two marker ticks refused, and the landing the "
            "result reports", marker_scope_part, mcp)
    section("10 — the documented limits, pinned so a change is noticed", limits_part, mcp)

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
