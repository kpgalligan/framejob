"""Road map 2, phase 4 — Words (schema v5), driven against the built binary
over MCP.

Every claim is a placement read back through `get_project`, a BYTE comparison
of two `render_frame` PNGs, a BYTE comparison of a caption file with the file
it came from, or a refusal read for the words it must contain. Nothing here
reads the source, and every check is one that would FAIL against a build where
the feature did nothing.

The three parts, and what each is measured with:

* **4a auto captions** — honesty first. Speech recognition is gated by a TCC
  grant that an agent-driven app can never obtain (the system prompt needs the
  app to be frontmost), so the recogniser itself is out of reach of any script.
  What IS reachable, and is checked here, is everything around it: the SCOPE
  refusals, which `AgentServer+Captions.swift` deliberately answers BEFORE the
  grant so they stay reachable on a machine with no grant; the MISSPELLED-tag
  refusal, which is above the grant for the same reason and is one of the two
  language refusals the catalog promises separately (the other one, a tag the
  framework knows that this Mac has no MODEL for, is a download and is refused
  BELOW the grant, where no script can reach it — an ungranted Mac cannot be
  asked which models it has); and then the authorization refusal itself — the
  exact sentence, the status word inside it, and the fact that a refused run
  places nothing and registers no undo step.
  `media/speech.mov` is here for the person who runs this WITH the grant;
  README.md says what they should see.

* **4b caption export** — `CaptionExporter`'s round trip, measured on the
  bytes. The fixture is written by this script at **25 fps**, where a frame is
  40 ms exactly, so a cue time that has been snapped to the frame grid comes
  back to the millisecond and the exported file must equal the imported one
  BYTE FOR BYTE. The same fixture at 30 fps must NOT come back — 40 ms is 1.2
  frames there — and that half is what makes the first half a proof rather
  than a tautology: a build whose exporter echoed its input file would pass at
  25 fps and fail at 30.

* **4c text animations** — every claim off a rendered PNG. The text is a
  single left-aligned line of the bundled MONOSPACED font (IBM Plex Mono) with
  an EVEN character count and no spaces, because that makes the arithmetic
  exact: at reveal 0.5 a monospaced prefix inks exactly half the columns the
  whole line inks, and at 0.25 exactly a quarter. A proportional font would
  fail those on correct code, which is why the font matters. The reveal-0
  frame is the blank the ink is measured against, and `reveal = 1` must be
  byte-identical to no animation at all.

  The stale-texture guard is measured in ONE frame rather than two: two text
  clips with IDENTICAL descriptions, started half a second apart, are at
  different reveals at the same instant. Swift keys its texture cache on the
  core's content hash alone, so if the hash did not cover the reveal the
  second layer would be handed the first layer's texture and the two would ink
  the same number of columns.

  An OUTLINED word is measured on its own, because it is the one description
  whose glyphs take two draws — a fill and then a stroke — and a partial alpha
  has to meet the finished glyph rather than each of them. Its outline is the
  canvas's own background colour, so a correct fade inks nothing the finished
  word does not; that is the whole check, and it needs no number.

Media: A.mov (the silent test card) and AV.mov (the test card with a tone
under it); the recipes are in README.md. **No ffmpeg is needed at proof
time** — nothing here is exported to a movie.
"""

import hashlib
import json
import os
import re
import shutil
import struct
import sys
import zlib

from mcp import MCP, ToolError

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4901
HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work")

SEC = 600_000
CANVAS = (640, 360)

# The whole catalog after phase 4: 53 ops (`core/src/edit.rs`'s OP_NAMES) plus
# the 17 tools that mirror no op. The EXACT count belongs to the newest
# phase's script — it is the only thing that tells a stale binary on the port
# from the build under test — so this is the assertion phases 1, 2 and 3 handed
# over, and which phase 5 took over in its turn when normalize_clip made it 71.
TOOLS = 70

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


def copy_package(source, destination):
    """A byte copy of a `.reelcut` package, skipping a file that vanishes
    under `cache/` — the instance under proof writes thumbnails while the copy
    runs. `phase2_proof.py` argues the whole thing; the short version is that
    everything under `cache/` is regenerable and no part of any claim made
    here, `cache/` itself must exist or `save_project` refuses the document as
    changed by another application, and a file that vanishes ANYWHERE else is
    still an error."""
    for root, _, files in os.walk(source):
        relative = os.path.relpath(root, source)
        target = destination if relative == "." else os.path.join(destination, relative)
        os.makedirs(target, exist_ok=True)
        for name in files:
            try:
                shutil.copy2(os.path.join(root, name), os.path.join(target, name))
            except FileNotFoundError:
                if relative.split(os.sep)[0] != "cache":
                    raise


# ---- PNG, in pure Python, and the things measured on one ------------------
#
# The same decoder `phase2_chrome.py` and `phase3_proof.py` use: chunks, zlib,
# the five filters. It is copied rather than imported because those files are
# SCRIPTS — importing one would run its main — and because a proof that
# measures its own evidence should carry the decoder it trusts.


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
        raise RuntimeError(f"{path}: only 8-bit non-interlaced PNGs are decoded here")
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
    """One rendered PNG, decoded. Positions are PIXEL INDICES."""

    def __init__(self, path):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)

    def pixel(self, x, y):
        return tuple(self.rows[y][x * self.channels:(x + 1) * self.channels])

    def changed(self, other):
        """Every (x, y) whose bytes differ from `other`'s."""
        out = []
        ch = self.channels
        for y, (ra, rb) in enumerate(zip(self.rows, other.rows)):
            if ra == rb:
                continue
            for x in range(self.width):
                if ra[x * ch:(x + 1) * ch] != rb[x * ch:(x + 1) * ch]:
                    out.append((x, y))
        return out

    def is_flat(self):
        """Whether every pixel of the frame is the same colour — how "the
        reveal has drawn nothing at all yet" is stated without naming a
        background colour this script would then own a second copy of."""
        first = self.rows[0][:self.channels]
        return all(row == first * self.width for row in self.rows)


def ink(frame, blank):
    """The pixels `frame` draws that `blank` does not — the glyphs, when
    `blank` is the same timeline at reveal 0 (nothing revealed, the layer and
    its box otherwise identical)."""
    return frame.changed(blank)


def columns(pixels, band=None):
    """The distinct x of a pixel list, ascending; `band` is a (y0, y1) row
    range to restrict to, which is how the two layers of the cache guard are
    told apart in one frame."""
    if band is None:
        return sorted({x for x, _ in pixels})
    return sorted({x for x, y in pixels if band[0] <= y < band[1]})


def span(values):
    """(first, last, count) of a column list, or the word for an empty one —
    so a check that failed still says what it saw."""
    if not values:
        return "empty"
    return f"{values[0]}…{values[-1]} ({len(values)} columns)"


class Session:
    """One project. The same shape as `phase3_proof.py`'s, minus the export
    accessors — phase 4 writes caption files and PNGs, never a movie."""

    def __init__(self, mcp, name, open_from=None, fps=None, background=None):
        self.mcp = mcp
        # `<name>-<pid>.reelcut`, never a fixed name: a `project` path is
        # matched against every open document and no tool closes one, so two
        # earlier runs' SAVED packages would have the app answering for an old
        # one (measured in phase 2). Older runs' under this name go.
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        if open_from is None:
            mcp.call("new_project", path=self.path)
            canvas = {"width": CANVAS[0], "height": CANVAS[1]}
            if fps is not None:
                canvas["fps"] = fps
            if background is not None:
                canvas["background"] = background
            self.mcp.call("set_canvas", project=self.path, **canvas)
            return
        copy_package(open_from, self.path)
        answer = self.mcp.call("open_project", path=self.path)
        check(
            not answer.get("already_open"),
            f"{name}: the copy was opened from disk, not matched to an open document",
        )

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def op_with(self, name, arguments):
        """For an op whose own ARGUMENT is spelled `name` — `add_track`'s."""
        return self.mcp.call_with(name, dict(arguments, project=self.path))

    def png(self, t):
        """The path of the PNG `render_frame` wrote — the tool answers with a
        sentence naming the file, so it is read out of that."""
        answer = self.op("render_frame", t=int(t))
        found = re.search(r"Written to (\S+\.png)\.", str(answer))
        assert found, f"render_frame said something else: {answer}"
        return found.group(1)

    def frame(self, t):
        """The rendered frame as a hash — the byte-comparison currency."""
        return digest(self.png(t))

    def image(self, t):
        """The rendered frame decoded, for the checks that MEASURE one."""
        return Frame(self.png(t))

    def project(self):
        return self.op("get_project")["project"]

    def text(self):
        return json.dumps(self.project(), sort_keys=True, separators=(",", ":"))

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def tracks(self):
        return self.project()["tracks"]

    def add_text(self, track, at, duration, text):
        return self.op(
            "add_text_clip", track=track, at=at, duration=duration, text=text)["new_clips"][0]

    def clip_of(self, name, track=None, at=0):
        """A clip holding `name` from the media folder."""
        media = self.op("import_media", path=os.path.join(MEDIA, name))["media"]
        track = track if track is not None else self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def undo(self):
        return self.op("undo")["undone"]

    def save(self):
        return self.op("save_project")


# ---- The catalog ----------------------------------------------------------


def catalog_part(mcp):
    print("catalog")
    names = mcp.tools()
    # Phase 4 found 70 — transcribe and export_captions over phase 3's 68 — and
    # held the EXACT count until phase 5 added normalize_clip and took it over,
    # exactly as the comment on TOOLS said it would. A floor still catches a
    # binary older than this phase, which is what the check is for.
    check(len(names) >= TOOLS, f"the catalog holds phase 4's {TOOLS} tools or more (got {len(names)})")
    for tool in ["transcribe", "export_captions"]:
        check(tool in names, f"{tool} is a tool")

    # The schema SHAPE, read off `tools/list` rather than off the source.
    # `mcp.py` reports names only — it is the shared client and nothing else
    # needs the schemas — so this reaches past it for the one thing this phase
    # claims about them.
    schemas = {t["name"]: t for t in mcp._request("tools/list", {})["tools"]}

    def schema_of(name):
        """One tool's input schema, or a stand-in that fails every check
        below rather than aborting the run: a binary missing the tool is
        exactly the case these checks exist for, and it should read as three
        failures and not as a traceback."""
        found = schemas.get(name)
        if found is None:
            return {"properties": {}, "required": ["(no such tool)"], "description": ""}
        return found["inputSchema"]

    transcribe = schema_of("transcribe")
    check(
        set(transcribe["properties"]) == {"clips", "language", "place", "project"},
        "transcribe declares clips, language and place (and project): "
        f"{sorted(transcribe['properties'])}",
    )
    check(
        transcribe["required"] == [],
        f"and requires nothing — a whole-timeline run is the default ({transcribe['required']})",
    )
    check(
        transcribe["properties"].get("clips", {}).get("items", {}).get("type") == "integer"
        and transcribe["properties"].get("place", {}).get("type") == "boolean",
        "with clips an integer array and place a boolean",
    )

    captions = schema_of("export_captions")
    check(
        set(captions["properties"]) == {"track", "path", "format", "project"},
        f"export_captions declares track, path and format: {sorted(captions['properties'])}",
    )
    check(
        captions["required"] == ["path"],
        f"and requires only path — the track is never guessed ({captions['required']})",
    )
    check(
        captions["properties"].get("format", {}).get("enum") == ["srt", "vtt"],
        "with format closed at srt and vtt: "
        f"{captions['properties'].get('format', {}).get('enum')}",
    )

    # `set_text` carries 4c — there is no new op for it — and the schema bump
    # is only half-mirrored if the PATCH's description does not say so: the
    # three kinds are a vocabulary a caller has to spell exactly, and the
    # catalog builds that clause from `TextAnimationKind.allCases` so it
    # cannot drift from the enum.
    described = schema_of("set_text")["properties"].get("patch", {}).get("description", "")
    check(
        all(word in described for word in ["animation", "typewriter", "word_fade", "line_rise"]),
        "set_text's patch description names animation and its three kinds",
    )

    # What `export_captions` TELLS a caller about its round trip, checked
    # against what `captions_part` measures a few functions down. The two used
    # to disagree: the description said a cue "can come back a frame away" at
    # 30 fps, which the arithmetic forbids — a timestamp is rounded to the
    # nearest millisecond, 300 ticks at most, and half a frame is 10,000 ticks
    # even at 30 fps. It is the FILE that moves, and an agent told otherwise
    # avoids a round trip that is in fact exact.
    told = schemas.get("export_captions", {}).get("description", "")
    check(
        "come back a frame away" not in told and "not exact is the FILE" in told,
        "export_captions' description says the cue TIMES survive a round trip and the FILE "
        "is what needs a whole-millisecond frame",
    )


# ---- 4a: auto captions ----------------------------------------------------


def transcribe_part(mcp):
    """What a headless run can reach of the recogniser path: the scope, the
    grant, and the fact that a refusal is a refusal all the way down.

    The order these are asserted in is the order the handler answers in, and
    that ordering is itself the claim: `AgentServer+Captions.swift` answers
    the CALLER's mistakes first so they stay reachable on a machine with no
    grant. A build that checked the grant first would fail every scope check
    below with the authorization sentence."""
    print("\n4a — transcribe: the scope, and the grant")
    s = Session(mcp, "transcribe")

    tracks = s.tracks()
    audible = s.clip_of("AV.mov", track=tracks[0]["id"])
    s.op_with("add_track", {"index": 1, "name": "Words"})
    words = s.tracks()[1]["id"]
    title = s.add_text(words, 0, 2 * SEC, {"content": "not speech"})
    s.op_with("add_track", {"index": 2, "name": "Backwards"})
    backwards_track = s.tracks()[2]["id"]
    media = {m["path"]: m["id"] for m in s.project()["media"]}
    backwards = s.op(
        "add_clip", track=backwards_track, media=media[os.path.join(MEDIA, "AV.mov")],
        at=0)["new_clips"][0]
    # `set_reversed` takes ONE clip, unlike the patch ops beside it.
    s.op("set_reversed", clip=backwards, reversed=True)

    # The three ineligible sources of D-A7, each refused BY NAME with the
    # reason that belongs to it. None of these reaches the recogniser, and
    # none of them would answer at all in a build with no scope pass.
    message = s.error("transcribe", clips=[title]) or ""
    check(
        f"clip {title}" in message and "not a media file" in message,
        f"a text clip is refused by name, with its reason: {message[:110]!r}",
    )
    message = s.error("transcribe", clips=[backwards]) or ""
    check(
        f"clip {backwards}" in message and "reverse" in message,
        f"a REVERSED clip is refused — its words would come out backwards: {message[:110]!r}",
    )

    silent = Session(mcp, "transcribe-silent")
    quiet = silent.clip_of("A.mov")
    message = silent.error("transcribe", clips=[quiet]) or ""
    check(
        f"clip {quiet}" in message and "no audio track" in message,
        f"a clip of a silent movie is refused: {message[:110]!r}",
    )
    message = silent.error("transcribe") or ""
    check(
        "Nothing in this timeline has recorded sound" in message,
        "and a whole timeline with nothing audible in it is refused as that, not as a "
        f"scope: {message[:110]!r}",
    )

    # A clip whose AUDIO IS SWITCHED OFF is the fourth refusal, and it is the
    # media's answer read the way the TIMELINE answers it: `audio.rs` gives
    # such a clip no voice, so the file having an audio track is only half the
    # question (`InspectorTab.hasAudio` asks both halves). Detach Audio is
    # where it bites — it leaves the picture clip switched off and puts a twin
    # with the SAME media, in point, start and speed on the track below, so a
    # run that asked only the media would recognise one recording TWICE and
    # place two identical cues at one time. Both checks below come back with
    # the authorization sentence on a build that does not ask.
    detached = Session(mcp, "transcribe-detached")
    picture = detached.clip_of("AV.mov")
    detached.op("detach_audio", clip=picture)
    message = detached.error("transcribe", clips=[picture]) or ""
    check(
        f"clip {picture}" in message and "audio is switched off" in message,
        f"after Detach Audio the picture half is refused by name: {message[:110]!r}",
    )
    twin = [c["id"] for c in detached.project()["clips"] if c["id"] != picture][0]
    detached.op("set_enabled", clip=twin, audio=False)
    message = detached.error("transcribe") or ""
    check(
        "Nothing in this timeline has recorded sound" in message,
        "and with the twin switched off as well the whole timeline has nothing to "
        f"transcribe, rather than two runs over one recording: {message[:110]!r}",
    )

    # Now the grant, which is everything a headless run can say about the
    # recogniser itself. The scope here is non-empty — the AV clip has a tone
    # under it — so the call gets past the scope pass and stops at
    # `Transcriber.isAuthorized`.
    before = s.text()
    message = s.error("transcribe") or ""
    check(
        message.endswith(
            "speech recognition is not authorized for Reelcut (status: notDetermined) — "
            "run File ▸ Generate Captions… once from the app to grant it"),
        f"an unauthorized transcribe refuses with the exact sentence: {message[:130]!r}",
    )
    status = re.search(r"\(status: (\w+)\)", message)
    check(
        status is not None and status.group(1) in {"notDetermined", "denied", "restricted"},
        "and NAMES the framework's own status word, which is the only observable of the "
        f"grant a script has: {status.group(1) if status else 'none'}",
    )
    check(s.text() == before, "the refused run placed nothing — the project JSON is unchanged")
    # And registered no undo step: the top of the stack is still the edit
    # before it. A "Generate Captions" step here would mean a plan had been
    # committed and then reported as a failure.
    undone = s.undo()
    check(
        "Caption" not in undone,
        f"and pushed no undo step — the top of the stack is still “{undone}”",
    )

    # THE TWO LANGUAGE REFUSALS, which are two because they have two fixes.
    # A tag speech recognition has never heard of is a misspelling and is the
    # CALLER's own mistake, so the handler answers it above the grant with the
    # scope refusals: `SFSpeechRecognizer.supportedLocales()` is a list out of
    # the framework's own bundle and reads the same at every authorization
    # status, which is the only reason this half is reachable here at all. The
    # other half — a tag the framework knows that this Mac has no MODEL for —
    # is a download and sits BELOW the grant on purpose, because an ungranted
    # Mac cannot be asked which models it has and must not be sent to
    # System Settings for one it may already have. So a headless run sees the
    # authorization sentence exactly where a granted one sees the download
    # refusal, and both checks below are read off that fact.
    #
    # The four are a set and none of them stands alone: the first two would
    # pass a build that refused EVERY tag as a misspelling, and the last two
    # would pass the build this phase shipped with, where the misspelling
    # refusal did not exist and every tag alike reached the grant.
    message = s.error("transcribe", language="zz-ZZ") or ""
    check(
        "zz-ZZ" in message and "spelling" in message and "not authorized" not in message,
        "a misspelled language tag is refused AS a misspelling, above the grant: "
        f"{message[:120]!r}",
    )
    tags = re.findall(r"\b[a-z]{2}-[A-Z0-9]{2,3}\b", message)
    check(
        len(tags) >= 10 and "System Settings" not in message,
        f"and it lists the tags speech recognition does know ({len(tags)} of them) without "
        "sending anybody to System Settings — a tag that does not exist is not a missing "
        "download, and the fix for it is to retype it",
    )
    for tag in ["en-US", "fr-FR"]:
        message = s.error("transcribe", language=tag) or ""
        check(
            "not authorized" in message and "spelling" not in message,
            f"while {tag}, which the framework DOES know, is past that gate and stopped by "
            f"the grant — where a Mac with the grant answers about the MODEL "
            f"instead: {message[:90]!r}",
        )

    print(
        "  note the recogniser itself is out of reach here and always will be: the TCC "
        "prompt needs a frontmost app. media/speech.mov is the fixture for a person who "
        "has granted it; README.md says what they should see.")


# ---- 4b: caption export ---------------------------------------------------

# The fixture, written by this script rather than kept under media/: it is
# text, it is the thing being compared against, and a proof that authors its
# own expected bytes cannot be reading a file somebody edited by hand.
#
# Every time is a whole number of 25 fps FRAMES (40 ms) and NONE of them is a
# whole number of 30 fps frames (33⅓ ms) — 440 ms is 11 frames at 25 and 13.2
# at 30. That is what makes the pair of round trips below a proof: the same
# file must come back byte for byte at 25 and must NOT at 30.
#
# The text contains no `&`, `<` or `>`, because WebVTT escapes all three and
# SubRip does not, and cue 2 is two lines, because a cue's own line breaks are
# what the exporter has to carry through without turning them into entry
# separators.
SRT = """1
00:00:00,440 --> 00:00:02,040
The quick brown fox

2
00:00:02,440 --> 00:00:04,040
jumps over the lazy dog
and lands on its feet

3
00:00:04,840 --> 00:00:06,040
Pack my box with five dozen liquor jugs
"""

# What the same three cues are, in the model's own unit, once the importer has
# snapped them to a 25 fps grid: (start, duration, text). Written out rather
# than computed, so the placement claim is against a number this file states
# and not against the arithmetic under test.
PLACED = [
    (264_000, 960_000, "The quick brown fox"),
    (1_464_000, 960_000, "jumps over the lazy dog\nand lands on its feet"),
    (2_904_000, 720_000, "Pack my box with five dozen liquor jugs"),
]


def as_vtt(srt):
    """The WebVTT that must come out of the same track, DERIVED from the
    SubRip rather than typed out again: the header, no index lines, and `.`
    where SubRip writes `,` in a timing line. Deriving it is the claim —
    "the two files differ by exactly these three things" is a statement about
    a transformation, and writing the answer out by hand would only claim that
    two hand-written files match two exports."""
    blocks = srt.rstrip("\n").split("\n\n")
    out = []
    for block in blocks:
        lines = block.split("\n")
        assert lines[0].strip().isdigit(), f"not an index line: {lines[0]!r}"
        timing = lines[1].replace(",", ".")
        out.append("\n".join([timing] + lines[2:]))
    return "WEBVTT\n\n" + "\n\n".join(out) + "\n"


def write_fixture(name):
    """The fixture on disk, at a FIXED name. Only a `.reelcut` PACKAGE needs a
    per-run name — a `project` path is matched against every open document and
    nothing closes one — and a caption file is neither read nor written
    through that machinery, so overwriting it keeps `work/` from growing a
    handful of text files per run. It is `phase3_proof.py`'s rule for its two
    exports, applied to the four files this phase reads and writes."""
    path = os.path.join(WORK, f"{name}.srt")
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(SRT)
    return path


def placements(session):
    """Every clip as (start, duration, words), in play order — the shape
    `PLACED` is written in, and the currency of a placement claim."""
    return [
        (c["start"], c["duration"], c["text"]["content"])
        for c in sorted(session.project()["clips"], key=lambda c: c["start"])
    ]


def captions_part(mcp):
    print("\n4b — caption export: the round trip, on the bytes")
    source = write_fixture("captions")
    s = Session(mcp, "captions", fps=[25, 1])
    answer = s.op("import_captions", path=source)
    check(
        answer.get("cues") == 3,
        f"the 25 fps project imported 3 cues (got {answer.get('cues')})",
    )
    track = s.tracks()[-1]["id"]
    placed = placements(s)
    check(
        placed == PLACED,
        f"and placed them at the frame-snapped times the file names: {placed[:1]}…",
    )
    check(
        all(c["track"] == track for c in s.project()["clips"]),
        "all on the one new front-most track",
    )

    out = os.path.join(WORK, "captions-out.srt")
    result = s.op("export_captions", path=out)
    with open(result["path"], "rb") as handle:
        written = handle.read()
    check(
        written == SRT.encode("utf-8"),
        "the exported .srt is BYTE-IDENTICAL to the file that was imported"
        + ("" if written == SRT.encode("utf-8") else f" — got {written[:60]!r}"),
    )
    check(
        result["track"] == track and result["cues"] == 3,
        f"and the result names the track it wrote and its 3 cues ({result['cues']})",
    )

    # The other half of that claim, and the one that makes it a claim: at 30
    # fps a frame is 33⅓ ms, so a 40 ms grid cannot survive and the exporter
    # must say so in its own output. A build that echoed the input file would
    # pass the check above and fail this one.
    thirty = Session(mcp, "captions-30", fps=[30, 1])
    thirty.op("import_captions", path=write_fixture("captions-30"))
    out30 = os.path.join(WORK, "captions-30-out.srt")
    written30_path = thirty.op("export_captions", path=out30)["path"]
    with open(written30_path, encoding="utf-8") as handle:
        written30 = handle.read()
    check(
        written30 != SRT,
        "the SAME file at 30 fps does NOT come back — the times are the model's, not the "
        "file's",
    )
    check(
        written30.splitlines()[1] == "00:00:00,433 --> 00:00:02,033",
        "and comes back on the 30 fps grid to the millisecond: "
        f"{written30.splitlines()[1]!r}",
    )

    # And what 30 fps does NOT cost, which the tool's own description used to
    # get backwards: the FILE moved, the CUE TIMES did not. Re-import what was
    # just exported and every clip must land on the same tick it was written
    # from — a timestamp is rounded to the nearest millisecond (300 ticks at
    # most) and half a frame is 10,000 ticks even here, so the snap on the way
    # back in can only find the frame the cue left. `catalog_part` checks that
    # `export_captions` says this; this measures it.
    back = Session(mcp, "captions-30-back", fps=[30, 1])
    back.op("import_captions", path=written30_path)
    placed30 = placements(thirty)
    check(
        placements(back) == placed30 and placed30 != PLACED,
        "and a SECOND trip through the 30 fps grid moves nothing — the cues come back "
        f"tick-for-tick, off the 25 fps grid the file was written on: {placed30[:1]}…",
    )

    # WebVTT: the same cues, differing by exactly the header, the missing
    # index lines and the decimal separator.
    outv = os.path.join(WORK, "captions-out.vtt")
    with open(s.op("export_captions", path=outv)["path"], encoding="utf-8") as handle:
        vtt = handle.read()
    check(
        vtt == as_vtt(SRT),
        "the .vtt of the same track is the .srt with a WEBVTT header, no index lines and "
        "“.” for “,” — and nothing else",
    )
    entries = written.decode("utf-8").rstrip("\n").split("\n\n")
    check(
        len(entries) == 3 and entries[1].split("\n")[2:] == PLACED[1][2].split("\n"),
        "the SubRip's three entries are separated by one blank line, and the two-line cue "
        "came back as its own two lines rather than as two entries",
    )
    check(
        vtt.endswith("liquor jugs\n") and not vtt.endswith("liquor jugs\n\n"),
        "and the file ends in exactly one newline",
    )

    # A path whose extension disagrees with the format is REPLACED, never
    # doubled: `srt` and `vtt` joined `replaceableExtensions` for exactly this.
    doubled = out + ".vtt"
    if os.path.exists(doubled):
        os.remove(doubled)
    result = s.op("export_captions", path=out, format="vtt")
    check(
        result["path"] == out[:-4] + ".vtt" and not os.path.exists(doubled),
        f"a .srt path asked for as vtt writes {os.path.basename(result['path'])}, not "
        "captions-out.srt.vtt",
    )
    with open(result["path"], encoding="utf-8") as handle:
        check(handle.read() == as_vtt(SRT), "with the WebVTT bytes in it, not the SubRip ones")
    message = s.error("export_captions", path=out, format="ass") or ""
    check(
        "srt" in message and "vtt" in message and "ass" in message,
        f"and a format outside the two containers is refused by name: {message[:90]!r}",
    )

    # The track is never guessed — the whole posture of D-B2, in three moves.
    empty = Session(mcp, "captions-empty")
    message = empty.error(
        "export_captions", path=os.path.join(WORK, "nothing.srt")) or ""
    check(
        "No track holds only text clips" in message,
        f"a project with no text track refuses rather than writing an empty file: "
        f"{message[:90]!r}",
    )
    other = s.tracks()[0]["id"]
    s.add_text(other, 0, SEC, {"content": "a title, not a caption"})
    message = s.error("export_captions", path=out) or ""
    check(
        "not obvious" in message and f"{track} “Captions”" in message
        and f"{other} “Track 1”" in message,
        f"two all-text tracks refuse and LIST both candidates by id and name: {message[:140]!r}",
    )
    result = s.op("export_captions", path=out, track=track)
    with open(result["path"], "rb") as handle:
        check(
            handle.read() == SRT.encode("utf-8"),
            "while naming the track writes the same bytes as before the ambiguity",
        )
    # Past the title clip: the overlap rule refuses a placement on top of it,
    # and what this needs is a track holding BOTH kinds.
    s.clip_of("A.mov", track=other, at=2 * SEC)
    message = s.error("export_captions", path=out, track=other) or ""
    check(
        "not text" in message and f"{other}" in message,
        f"and a track holding a movie is refused by name: {message[:100]!r}",
    )


# ---- 4c: text animations --------------------------------------------------

# A single line of the bundled MONOSPACED font, twelve characters, no spaces
# and an even count. Monospaced is the whole point: a typewriter at 0.5 shows
# six of twelve glyphs, which ink exactly half the columns the twelve ink, and
# at 0.25 exactly a quarter. A proportional font inks neither, so this check
# would fail on correct code and could only be written with a tolerance.
MONO = "oooooooooooo"
MONO_STYLE = {
    "content": MONO,
    "font": "IBMPlexMono-Regular",
    "size": 72,
    "align": "left",
    "valign": "middle",
    "color": [1, 1, 1, 1],
}
# Something with several words on two lines, for the two kinds whose motion is
# per word and per line.
PROSE = "alpha beta gamma\ndelta epsilon"
PROSE_STYLE = dict(MONO_STYLE, content=PROSE, size=40)

IN = 2 * SEC


def animation_part(mcp):
    print("\n4c — text animations: the reveal, on the pixels")
    s = Session(mcp, "textanim", fps=[30, 1], background=[0, 0, 0, 1])
    track = s.tracks()[0]["id"]
    clip = s.add_text(track, 0, 5 * SEC, MONO_STYLE)

    # The baseline is taken by CLEARING the animation rather than kept from
    # before the phase: a stored PNG proves nothing about this build.
    static = s.frame(IN)
    s.op("set_text", clips=[clip], patch={"animation": {"kind": "typewriter", "in": IN, "out": 0}})
    stored = s.clip(clip)["text"]["animation"]
    check(
        stored == {"kind": "typewriter", "in": IN, "out": 0},
        f"the animation reads back as it was sent: {stored}",
    )
    check(
        s.frame(IN) == static,
        "reveal = 1 renders BYTE-IDENTICAL to no animation at all",
    )

    blank = s.image(0)
    check(
        blank.is_flat(),
        "and reveal = 0 draws nothing at all — the frame is one flat colour",
    )
    whole = s.image(IN)
    half = s.image(IN // 2)
    quarter = s.image(IN // 4)
    # Every measurement below is guarded rather than indexed: a build whose
    # reveal did nothing inks the SAME frame at 0 and at 1, and an empty
    # column list would then abort the run at its first subscript instead of
    # reporting the six checks it broke.
    full_cols = columns(ink(whole, blank))
    half_cols = columns(ink(half, blank))
    quarter_cols = columns(ink(quarter, blank))
    check(len(full_cols) > 0, f"the whole line inks {span(full_cols)}")
    midpoint = (full_cols[0] + full_cols[-1] + 1) / 2 if full_cols else None
    check(
        bool(half_cols) and midpoint is not None and half_cols[-1] < midpoint,
        f"a typewriter half way through its in-ramp inks columns only LEFT of the line's "
        f"midpoint {midpoint}: {span(half_cols)}",
    )
    check(
        bool(half_cols) and bool(full_cols) and half_cols[0] == full_cols[0],
        "starting at the same column the whole line starts at — it types from the left",
    )
    check(
        bool(half_cols) and 2 * len(half_cols) == len(full_cols),
        f"and inks EXACTLY half the columns the whole line inks ({len(half_cols)} × 2 vs "
        f"{len(full_cols)}) — six monospaced glyphs of twelve",
    )
    check(
        bool(quarter_cols) and 4 * len(quarter_cols) == len(full_cols)
        and quarter_cols[-1] < half_cols[-1],
        f"a quarter of the way through it inks exactly a quarter, and no further right "
        f"({len(quarter_cols)} × 4 vs {len(full_cols)})",
    )
    difference = columns(ink(half, whole))
    check(
        bool(difference) and bool(half_cols) and difference[0] > half_cols[-1],
        "and every pixel where the half-typed frame differs from the whole one lies to the "
        f"RIGHT of what it has typed ({span(difference)} against {span(half_cols)})",
    )
    check(
        digest(half.path) != digest(quarter.path),
        "two times inside one ramp render DIFFERENT frames",
    )

    # word_fade and line_rise, on text that has words and lines to move.
    s.op("set_text", clips=[clip], patch={"animation": None, "content": PROSE, "size": 40})
    prose_static = s.frame(IN)
    # The empty frame is taken at reveal 0 with the animation SET, one per
    # kind, the way the MONO half takes its own — never off the cleared clip,
    # whose reveal is 1 at every t (`recipe.rs`'s `Reveal::WHOLE`), so a blank
    # taken there would BE the static frame and "neither the static frame nor
    # the empty one" would be one comparison written twice.
    blanks = {}
    for kind in ["word_fade", "line_rise"]:
        s.op("set_text", clips=[clip], patch={"animation": {"kind": kind, "in": IN, "out": 0}})
        check(
            s.frame(IN) == prose_static,
            f"{kind} at reveal 1 is byte-identical to the static frame",
        )
        empty = s.image(0)
        blanks[kind] = digest(empty.path)
        check(
            empty.is_flat() and blanks[kind] != prose_static,
            f"{kind} at reveal 0 draws nothing at all — one flat colour, and not the "
            "static frame",
        )
        middle = s.frame(IN // 2)
        check(
            middle != prose_static and middle != blanks[kind],
            f"and half way through it is neither the static frame nor the empty one",
        )

    # The out phase, which is the reason the recipe carries a phase word at
    # all: the same clip un-revealing rather than arriving.
    s.op("set_text", clips=[clip], patch={"animation": {"kind": "line_rise", "in": 0, "out": IN}})
    check(
        s.frame(0) == prose_static,
        "an out-only animation is fully revealed at the clip's first frame",
    )
    # Measured against the SAME kind's empty frame: nothing is drawn at
    # reveal 0 whichever phase is holding the amount back, and the out ramp
    # reaches 0 only at the clip's exclusive end, which no frame shows.
    leaving = s.frame(5 * SEC - IN // 2)
    check(
        leaving != prose_static and leaving != blanks["line_rise"],
        "and half way through its OUT ramp is neither static nor empty",
    )

    s.op("set_text", clips=[clip], patch={"animation": None})
    check(
        s.frame(IN) == prose_static,
        "clearing the animation renders byte-identically to before it was ever set",
    )
    return s


# An OUTLINED word, and the one thing an outline changes about a reveal: Core
# Text fills and then strokes each glyph (`attributedString` asks for both
# with a negative stroke width), so a partial alpha has two draws to apply
# itself to rather than one. The outline is drawn in the canvas's own
# BACKGROUND colour, which is what makes the claim below need no number: at
# reveal 1 the whole stroke band renders as background and inks nothing, so
# any pixel the half-faded word inks THERE is an artefact of fading the two
# passes separately and not the word.
OUTLINE = {"width": 6, "color": [0, 0, 0, 1]}
OUTLINE_STYLE = dict(MONO_STYLE, content="oooo", size=96, outline=OUTLINE)


def outline_part(mcp):
    """An outlined word fading: ONE composite, not two.

    A correct fade multiplies the FINISHED glyph, the way the shader has
    always multiplied a finished texture, so it can only ink where the
    finished glyph inks. Fading the fill and the stroke separately cannot:
    the inner half of the stroke lands on ink the fill already laid down and
    composites twice, so a black outline on a white word lights up as a grey
    halo — mid-grey at three quarters alpha where the finished glyph is black
    — for the whole ramp, and snaps to a crisp edge only at reveal 1."""
    print("\n4c — an outlined word at a partial reveal: one composite, not two")
    s = Session(mcp, "textoutline", fps=[30, 1], background=[0, 0, 0, 1])
    track = s.tracks()[0]["id"]
    clip = s.add_text(track, 0, 5 * SEC, OUTLINE_STYLE)
    stored = s.clip(clip)["text"]["outline"]
    check(stored == OUTLINE, f"the outline reads back as it was sent: {stored}")

    # And it is on the PIXELS, not just in the model — without this the claim
    # below would pass against a build that had dropped the outline entirely.
    outlined = s.frame(IN)
    s.op("set_text", clips=[clip], patch={"outline": None})
    check(s.frame(IN) != outlined, "and it changes the frame — clearing it renders another")
    s.op("set_text", clips=[clip], patch={"outline": OUTLINE})
    check(s.frame(IN) == outlined, "and putting it back renders the outlined frame again")

    # One token, so the whole word is at the reveal's own amount and no
    # stagger is in the way: `staggered` hands a single item the amount.
    s.op("set_text", clips=[clip], patch={"animation": {"kind": "word_fade", "in": IN, "out": 0}})
    blank = s.image(0)
    whole = s.image(IN)
    half = s.image(IN // 2)
    check(
        digest(half.path) != digest(whole.path) and not half.is_flat(),
        "half way through the ramp the word is drawn, and it is not the whole word",
    )
    finished = set(ink(whole, blank))
    fading = set(ink(half, blank))
    check(
        len(finished) > 0 and len(fading) > 0,
        f"the finished word inks {len(finished)} pixels and the fading one {len(fading)}",
    )
    stray = sorted(fading - finished)
    where = f", first at {stray[0]}" if stray else ""
    check(
        not stray,
        f"and every pixel the fading word inks is one the finished word inks too: the "
        f"outline fades WITH its glyph, not over it ({len(stray)} stray pixels{where})",
    )


def cache_part(mcp):
    """The stale-texture guard, measured in ONE frame.

    Swift keys its texture cache on the core's content hash and consults
    nothing else, and the compositor that holds that cache is built per
    composition — so two `render_frame` calls could differ even if the reveal
    were left out of the hash. Two layers in the SAME frame cannot: they share
    one cache. Both clips carry an IDENTICAL text description and differ only
    in when they start, so the only thing that can key them apart is the
    reveal the core folded in."""
    print("\n4c — the stale-texture guard: two reveals in one frame")
    s = Session(mcp, "textcache", fps=[30, 1], background=[0, 0, 0, 1])
    s.op_with("add_track", {"index": 1, "name": "Second"})
    tracks = s.tracks()
    early = s.add_text(tracks[0]["id"], 0, 5 * SEC, MONO_STYLE)
    late = s.add_text(tracks[1]["id"], IN // 4, 5 * SEC, MONO_STYLE)
    s.op("set_video", clips=[early], patch={"y": -90})
    s.op("set_video", clips=[late], patch={"y": 90})
    s.op(
        "set_text", clips=[early, late],
        patch={"animation": {"kind": "typewriter", "in": IN, "out": 0}})
    check(
        s.clip(early)["text"] == s.clip(late)["text"],
        "the two clips carry an identical text description — same content, same animation",
    )

    frame = s.image(IN // 2)
    blank = s.image(0)
    marks = ink(frame, blank)
    top = columns(marks, band=(0, CANVAS[1] // 2))
    bottom = columns(marks, band=(CANVAS[1] // 2, CANVAS[1]))
    check(
        bool(top) and bool(bottom),
        f"both layers are drawn at once (top {span(top)}, bottom {span(bottom)})",
    )
    check(
        bool(bottom) and len(top) == 2 * len(bottom),
        f"and the one that started earlier has typed exactly twice as far in the SAME frame "
        f"({len(top)} columns vs {len(bottom)}) — one texture cache, two reveals",
    )


# ---- 4c: the schema -------------------------------------------------------


def schema_part(mcp, session):
    print("\n4c — schema v5")
    animation = {"kind": "line_rise", "in": 3 * SEC, "out": SEC}
    clip = session.project()["clips"][0]["id"]
    session.op("set_text", clips=[clip], patch={"animation": animation})
    session.save()
    with open(os.path.join(session.path, "project.json"), encoding="utf-8") as handle:
        text = handle.read()
    root = json.loads(text)
    check(root["version"] == 8, f"the saved project.json is version 8 (got {root['version']})")
    check(
        all(list(c["text"].keys())[-1] == "animation" for c in root["clips"] if c["text"]),
        "and animation is the LAST key of every text object",
    )
    check(
        root["clips"][0]["text"]["animation"] == animation,
        f"holding the animation as it was sent: {root['clips'][0]['text']['animation']}",
    )

    # A version-4 fixture: the same package with the key REMOVED, not nulled.
    fixture = os.path.join(WORK, f"textanim-v4-source-{os.getpid()}.reelcut")
    if os.path.exists(fixture):
        shutil.rmtree(fixture)
    copy_package(session.path, fixture)
    older = json.loads(text)
    older["version"] = 4
    for entry in older["clips"]:
        if entry.get("text"):
            entry["text"].pop("animation", None)
    with open(os.path.join(fixture, "project.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(older, indent=2))
    check(
        '"animation"' not in json.dumps(older) and older["version"] == 4,
        "the fixture on disk is version 4 with no animation key anywhere",
    )
    v4 = Session(mcp, "textanim-v4", open_from=fixture)
    project = v4.project()
    check(project["version"] == 8, "a version-4 file opens and reports version 8")
    check(
        all(c["text"]["animation"] is None for c in project["clips"] if c["text"]),
        "and every text clip reads a NULL animation",
    )
    check(
        [c["text"]["content"] for c in project["clips"] if c["text"]]
        == [c["text"]["content"] for c in older["clips"] if c.get("text")],
        "with the rest of the text object untouched",
    )

    target = project["clips"][0]["id"]
    message = v4.error(
        "set_text", clips=[target], patch={"animation": {"kind": "fade", "in": SEC}}) or ""
    check(
        "typewriter" in message and "word_fade" in message and "line_rise" in message,
        f"a kind outside the closed enum is refused BY NAME: {message[:110]!r}",
    )
    message = v4.error(
        "set_text", clips=[target],
        patch={"animation": {"kind": "typewriter", "in": -1}}) or ""
    check(
        "text.animation.in" in message and "negative" in message,
        f"and a negative in is refused by the key's own name: {message[:110]!r}",
    )
    message = v4.error(
        "set_text", clips=[target],
        patch={"animation": {"kind": "typewriter", "in": SEC, "out": -5}}) or ""
    check(
        "text.animation.out" in message and "negative" in message,
        f"as is a negative out: {message[:110]!r}",
    )

    # `add_text_clip` is the OTHER door a text patch comes through, and it
    # reads the patch with the same lenient decoder: "fade" decodes to
    # `typewriter` on the Swift side, so a build that checked the vocabulary
    # only in `set_text` MAKES this clip, answers ok, and hands back a
    # typewriter nobody asked for. Both doors, one vocabulary.
    guard_track = v4.tracks()[0]["id"]
    before = len(v4.project()["clips"])
    message = v4.error(
        "add_text_clip", track=guard_track, at=20 * SEC, duration=2 * SEC,
        text={"content": "Hi", "animation": {"kind": "fade", "in": SEC}}) or ""
    check(
        "typewriter" in message and "word_fade" in message and "line_rise" in message,
        f"add_text_clip refuses the same kind BY NAME, not silently: {message[:110]!r}",
    )
    check(
        len(v4.project()["clips"]) == before,
        "and places no clip when it does",
    )


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)
    catalog_part(mcp)
    transcribe_part(mcp)
    captions_part(mcp)
    animated = animation_part(mcp)
    outline_part(mcp)
    cache_part(mcp)
    schema_part(mcp, animated)
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
    except (ToolError, AssertionError, KeyError, IndexError, RuntimeError, OSError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
