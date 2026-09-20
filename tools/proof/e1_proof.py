"""Road map 5, E1 — transitions second pass, driven against the built binary
over MCP, and against a SECOND binary built from the tree as it stood before
E1 landed.

    python3 tools/proof/e1_proof.py [port=4825] [reference_port=4826]

Every claim here is a placement read back through `get_project`, a BYTE
comparison of two PNGs, or a sample-for-sample comparison of two decoded
exports. Nothing reads a source file.

**Why there are two instances.** Four of E1's claims are about what did NOT
move: a version-6 project's overlap must go on drawing linearly and sounding
silent, exactly as it did before `curve` and `audio` existed (spec §11,
R5-2). "Exactly" is only checkable against a build that never had them, so
the reference tree is `1c3e92e` — the commit before E1's first toll —
extracted into `tools/proof/work/e1-reference`, built there, and launched on
its own port. Its format version is SIX, so it refuses anything this build
saves; every fixture the two share is therefore hand-written back to version
6 by `as_version`, which is also exactly the file a person who used the app
last month has on disk.

The reference build answers 75 tools and 55 ops; this one answers at least 77
and 57. The two numbers are how a row knows which instance it is talking to,
and section 0 scores them before anything else runs.

**The counts here are FLOORS.** `tools/proof/README.md`'s rule is that the
newest phase owns the exact count, and since road map 7's D3 that is
`op_argument_proof.py:116-117`. This script asserts `>= 77` and `>= 57` so a
later phase that adds a tool does not have to come back and edit E1's proof;
the reference's `== 75` / `== 55` stay exact, because that tree is frozen.

**What is measured, section by section.**

* **0** the two instances: tool and op counts, and both parity logs empty.
* **1** the schema: a hand-written version-6 file opens with
  `curve: linear, audio: false`; a copy of it saves as version 8 with `audio`
  the LAST key of `transition_in`; `set_transition` over a stored style keeps
  the curve; `set_transition_style` at a hard cut stores a minted transition
  that nothing draws.
* **2** the three wipe directions, at p = 0.25 on a two-second overlap: which
  SIDE the incoming colour is on and where the boundary sits, to a pixel; the
  curve moving it; and the old `wipe` rendering byte-identical to the
  reference build.
* **3** a push's offset under `ease_in_out` and under `linear`; five ticks of
  a version-6 cross dissolve byte-identical to the reference build.
* **4** `add_transition`'s arithmetic: centre, the two alignments, the
  step-down, the odd frame, a speed, a nest, an action's rebase, the
  refusals, and one `undo` restoring `get_project` exactly.
* **5** the audio crossfade, measured by projecting each tone onto its OWN
  frequency with a Goertzel filter in 25 ms windows — 11 cycles of 440 Hz and
  22 of 880 Hz at 48 kHz, so neither leaks into the other's bin — ending at a
  HARD CUT with the incoming clip muted, which is what scores the first
  window's burst as the host's rather than the ramp's.
* **6** Remove Silences never proposing a cut inside a transition.

Fixtures: `tools/proof/media/`'s `toneA.m4a` (440 Hz), `toneB.m4a` (880 Hz),
`AV.mov` (the test card with 440 Hz under it) and `silence.mov`, plus shape
cards drawn by the app. **The tones are TRIMMED first**: placed whole they
have no handles at all, and `add_transition` is built from handles.

`ffmpeg` is needed at proof time, to decode an export to raw PCM.
"""

import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib
from array import array

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
MEDIA = os.path.join(HERE, "media")
REFERENCE_TREE = os.path.join(WORK, "e1-reference")

SEC = 600_000
FRAME = 20_000
CANVAS = (640, 360)
VERSION = 8

# This build's floors (D3's `op_argument_proof.py` owns the exact numbers),
# and the reference build's exact counts — that tree is frozen at 1c3e92e.
TOOLS_FLOOR = 77
OPS_FLOOR = 57
REFERENCE_TOOLS = 75
REFERENCE_OPS = 55

failures = []
skipped = []
checks = 0


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def skip(count, why):
    """A row that could not RUN, printed by name with the checks it would
    have scored — `phase5_chrome.py`'s shape. It exists so a reference
    instance that is not there reports ITSELF by name instead of reading as
    eleven separate failures; the run is still non-zero, because road map
    5's Verification forbids a skip on the landing run and an unmeasured row
    is not a passed one."""
    global checks
    checks += count
    for _ in range(count):
        failures.append(f"SKIP {why}")
    skipped.append(f"{why} ({count} checks)")
    print(f"  SKIP {why} — {count} checks not taken")


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def grey(value):
    """A colour argument for an 8-bit grey — every fill here is k/255 for a
    whole k, so a byte comparison can never fail on a dithered colour
    (`phase6_proof.py`'s rule)."""
    return [value / 255.0, value / 255.0, value / 255.0, 1.0]


# ---- the curves, in Python -----------------------------------------------
#
# Transcribed from the RULES, not from the implementation: `core/src/
# actions.rs`'s four closed forms, `core/src/audio_crossfade.rs`'s constant-
# power pair and `core/src/motion.rs`'s overshoot. The two agreeing is the
# claim being made, so they may not share a line.


def ease(curve, u):
    u = min(max(u, 0.0), 1.0)
    if curve == "linear":
        return u
    if curve == "ease_in":
        return u * u
    if curve == "ease_out":
        return 1.0 - (1.0 - u) * (1.0 - u)
    if curve == "ease_in_out":
        return u * u * (3.0 - 2.0 * u)
    raise RuntimeError(f"{curve} is not a curve")


def gain(p, incoming):
    """Constant power: the incoming clip rises as sin, the outgoing falls as
    cos, of a quarter turn (`audio_crossfade.rs`)."""
    angle = min(max(p, 0.0), 1.0) * math.pi / 2
    return math.sin(angle) if incoming else math.cos(angle)


def goertzel(mono, hz, sr):
    """The amplitude of `hz` in `mono`, by projection onto that one bin.

    At 48 kHz over 1200 samples (25 ms) the bin index is a whole number for
    both 440 Hz (11 cycles) and 880 Hz (22), so neither tone leaks into the
    other's bin and one window answers for one tone."""
    n = len(mono)
    if n == 0:
        return 0.0
    k = round(n * hz / sr)
    omega = 2.0 * math.pi * k / n
    coeff = 2.0 * math.cos(omega)
    s1 = s2 = 0.0
    for x in mono:
        s0 = x + coeff * s1 - s2
        s2, s1 = s1, s0
    power = s1 * s1 + s2 * s2 - coeff * s1 * s2
    return 2.0 * math.sqrt(max(power, 0.0)) / n


def db(ratio):
    return 20.0 * math.log10(ratio) if ratio > 1e-12 else -240.0


# ---- PNG, in pure Python -------------------------------------------------
#
# `phase6_proof.py`'s decoder, copied rather than imported: those files are
# SCRIPTS, importing one would run its main, and a proof that measures its
# own evidence carries the decoder it trusts. The 8-bit guard is not
# paperwork — `render_frame` writes at the depth the frame needs, and a
# 16-bit PNG would silently change what "a byte" means here.


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
    return width, height, depth, channels, rows


class Frame:
    """One rendered PNG, decoded. Positions are pixel indices."""

    def __init__(self, path):
        self.path = path
        self.width, self.height, self.depth, self.channels, self.rows = decode_png(path)

    def pixel(self, x, y):
        return tuple(self.rows[y][x * self.channels:(x + 1) * self.channels])

    def centre(self):
        return self.pixel(self.width // 2, self.height // 2)

    def row(self, y, channel=0):
        row = self.rows[y]
        return [row[x * self.channels + channel] for x in range(self.width)]

    def column(self, x, channel=0):
        return [row[x * self.channels + channel] for row in self.rows]

    def changed(self, other):
        out = []
        ch = self.channels
        for y, (ra, rb) in enumerate(zip(self.rows, other.rows)):
            if ra == rb:
                continue
            for x in range(self.width):
                if ra[x * ch:(x + 1) * ch] != rb[x * ch:(x + 1) * ch]:
                    out.append((x, y))
        return out


def box(pixels):
    """(x0, y0, x1, y1) of a list of pixels, inclusive."""
    xs = [x for x, _ in pixels]
    ys = [y for _, y in pixels]
    return min(xs), min(ys), max(xs), max(ys)


def columns(pixels, band=None):
    """The distinct x of a pixel list, ascending (`phase4_proof.py`'s)."""
    if band is None:
        return sorted({x for x, _ in pixels})
    return sorted({x for x, y in pixels if band[0] <= y < band[1]})


def span(values):
    """(first, last, count) of a column list, or the word for an empty one."""
    if not values:
        return "empty"
    return f"{values[0]}…{values[-1]} ({len(values)} columns)"


# ---- PCM ------------------------------------------------------------------


def pcm(path):
    """`path` decoded to raw signed 16-bit LE stereo 48 kHz, as bytes — the
    same line phases 2, 5 and 6 decode with."""
    out = os.path.splitext(path)[0] + ".pcm"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-f", "s16le",
         "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", out],
        check=True)
    with open(out, "rb") as handle:
        return handle.read()


def samples(data):
    values = array("h")
    values.frombytes(data)
    return values


def wobble(a, b):
    """(max |Δ|, count of differing samples) between two PCM dumps, or None
    when they are not even the same length (`phase2_proof.py`'s)."""
    if len(a) != len(b):
        return None
    if a == b:
        return (0, 0)
    diffs = [abs(p - q) for p, q in zip(samples(a), samples(b)) if p != q]
    return (max(diffs), len(diffs))


def same(a, b, tolerance):
    """Sample-for-sample equal, within the measured wobble (0 = byte-equal)."""
    w = wobble(a, b)
    return w is not None and w[0] <= tolerance


def describe_pcm(a, b):
    w = wobble(a, b)
    if w is None:
        return f"lengths differ ({len(a)} vs {len(b)} bytes)"
    return f"max |Δ| {w[0]}, {w[1]} samples differ, of {len(a) // 2}"


def mono_window(data, start_sec, length_sec=0.025, rate=48000):
    """(L + R) / 2 over one window of a stereo PCM dump."""
    values = samples(data)
    first = int(round(start_sec * rate)) * 2
    count = int(round(length_sec * rate)) * 2
    chunk = values[first:first + count]
    return [(chunk[i] + chunk[i + 1]) / 2.0 for i in range(0, len(chunk) - 1, 2)]


def rms(values):
    if not values:
        return 0.0
    return math.sqrt(sum(v * v for v in values) / len(values))


# ---- hand-writing a package back to an older version ----------------------


def as_version(src, dst, version):
    """A byte copy of a saved package whose `project.json` is rewritten as a
    file of `version`: the version number itself, every `transition_in`
    reduced to its version-6 spelling (`{"kind": k}` — `curve` and `audio`
    did not exist), and every `video.motion` deleted (version 8's key).

    This is what a project saved by last month's build actually looks like,
    and it is the only fixture the reference instance can open at all: the
    core refuses a file from the future, so a version-8 package is simply
    rejected there."""
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    path = os.path.join(dst, "project.json")
    with open(path, encoding="utf-8") as handle:
        project = json.load(handle)

    def strip(clips):
        for clip in clips:
            # Version 7 added `curve` and `audio`; version 8 added `motion`.
            # A file is written back only as far as its own version asks, so
            # `as_version(…, 8)` is a byte copy with a different name and
            # nothing is quietly removed from it.
            if version < 7 and isinstance(clip.get("transition_in"), dict):
                clip["transition_in"] = {"kind": clip["transition_in"]["kind"]}
            video = clip.get("video")
            if version < 8 and isinstance(video, dict):
                video.pop("motion", None)
            inner = clip.get("clips")
            if isinstance(inner, list):
                strip(inner)

    strip(project.get("clips", []))
    for nest in project.get("nests", []):
        strip(nest.get("clips", []))
    project["version"] = version
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(project, handle, indent=2)
        handle.write("\n")
    return dst


def canonical(value):
    """A project dumped with sorted keys — the oracle for "undo restored
    everything" and "nothing else moved"."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


# ---- the project under test ----------------------------------------------


class Session:
    """One project, `phase6_proof.py`'s shape.

    `<name>-<pid>.reelcut`, never a fixed name: a `project` path is matched
    against every open document and no tool closes one, so two earlier runs'
    SAVED packages would have the app answering for an old one."""

    def __init__(self, mcp, name, canvas=CANVAS, background=(0, 0, 0), open_from=None):
        self.mcp = mcp
        self.name = name
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        if open_from is None:
            mcp.call("new_project", path=self.path)
            self.op("set_canvas", width=canvas[0], height=canvas[1],
                    background=[c / 255.0 for c in background] + [1.0])
        else:
            if os.path.exists(self.path):
                shutil.rmtree(self.path)
            shutil.copytree(open_from, self.path)
            mcp.call("open_project", path=self.path)

    @classmethod
    def opened(cls, mcp, path):
        """An instance's view of a package that already exists at `path` —
        used where the SAME file has to be opened by two builds."""
        session = cls.__new__(cls)
        session.mcp = mcp
        session.name = os.path.basename(path)
        session.path = path
        mcp.call("open_project", path=path)
        return session

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def op_with(self, name, arguments):
        """For a tool whose own ARGUMENT is spelled `name` — `nest`'s."""
        arguments = dict(arguments)
        arguments["project"] = self.path
        return self.mcp.call_with(name, arguments)

    def project(self):
        return self.op("get_project")["project"]

    def duration(self):
        """The timeline's length, as the tool reports it beside the project."""
        return self.op("get_project")["duration"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def add_track(self):
        self.op("add_track")
        return self.tracks()[-1]

    def media(self, name):
        return self.op("import_media", path=os.path.join(MEDIA, name))["media"]

    def place(self, track, media, at):
        return self.op("add_clip", track=track, media=media, at=int(at))["new_clips"][0]

    def card(self, track, fill, size=CANVAS, at=0, duration=3 * SEC):
        """A flat rectangle with no stroke — the fixture's one drawing."""
        return self.op(
            "add_shape_clip", track=track, at=int(at), duration=int(duration),
            shape={
                "kind": "rectangle", "width": size[0], "height": size[1],
                "stroke": None, "fill": fill,
            })["new_clips"][0]

    def png(self, t=SEC):
        answer = self.op("render_frame", t=int(t))
        found = re.search(r"Written to (\S+\.png)\.", str(answer))
        assert found, f"render_frame said something else: {answer}"
        return found.group(1)

    def frame(self, t=SEC):
        return digest(self.png(t))

    def image(self, t=SEC):
        return Frame(self.png(t))

    def settle(self, tool, **kwargs):
        """A call whose result is a STATE, not a change: an op already in that
        state answers "made no change", which is an identity and not a
        failure. Used only where a row wants the state and does not care
        whether it moved (setting `linear` on a file that is already
        linear).

        It is also what keeps a MUTATION run SCORING rather than aborting: a
        build whose `minted` writes `linear` turns four of these set-up calls
        into identities, and a traceback is a weaker signal than a score."""
        try:
            return self.op(tool, **kwargs)
        except ToolError as error:
            if "made no change" in str(error):
                return None
            raise

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def save(self):
        self.op("save_project")
        with open(os.path.join(self.path, "project.json"), encoding="utf-8") as handle:
            return handle.read()

    def undo(self):
        return self.op("undo")["undone"]

    def export_wav(self, tag):
        """An audio-only export into `work/`, with the pid on it: half of §5's
        claim is a comparison between two files, and a second run must never
        find the first run's."""
        target = os.path.join(WORK, f"{self.name}-{tag}-{os.getpid()}.wav")
        if os.path.exists(target):
            os.remove(target)
        return self.op("export", preset="audio_wav", path=target)["path"]


def trimmed(session, track, media, at, body=3 * SEC):
    """One clip of exactly `body` ticks at `at`, with every unused frame of
    its file left at the HEAD.

    Placed whole, a file has no handle at all and `add_transition` is built
    from handles — so the clip is placed, trimmed at its head by whatever it
    has over `body`, and moved back by the same, which leaves the head as the
    handle and the clip where it was asked for.

    The handle is MEASURED and not the file's nominal length. `toneA.m4a` is
    written by ffmpeg as five seconds and decodes to 2 986 400 ticks, which
    snaps to 149 frames — so "a two-second handle" is really 59 frames, and a
    fixture that assumed 60 would be measuring the encoder's padding rather
    than the op."""
    clip = session.place(track, media, at)
    whole = session.clip(clip)["duration"]
    head = whole - body
    session.op("trim_start", clip=clip, to=at + head)
    session.op("move_clip", clips=[clip], delta=-head)
    return clip, head


def trimmed_pair(session, track, a_media, b_media, body=3 * SEC):
    """The fixture §4, §5 and §6 are built on: two clips of `body` ticks meeting
    at a hard cut, A with its spare material at the TAIL and B with its spare
    material at the HEAD.

    Answers `(A, B, A's tail, B's head)`, both handles in ticks and both
    measured, so every expectation below is written against the fixture this
    run actually built."""
    a = session.place(track, a_media, 0)
    whole_a = session.clip(a)["duration"]
    session.op("trim_end", clip=a, to=body)
    b, head = trimmed(session, track, b_media, body, body)
    return a, b, whole_a - body, head


def first_nearer(values, near, far):
    """The first index whose value is nearer `near` than `far`, or None."""
    for index, value in enumerate(values):
        if abs(value - near) < abs(value - far):
            return index
    return None


def last_run_start(values, near, far):
    """Where the TRAILING run of values nearer `near` begins — the boundary
    when the incoming colour is on the right or at the bottom."""
    found = None
    for index, value in enumerate(values):
        if abs(value - near) < abs(value - far):
            if found is None:
                found = index
        else:
            found = None
    return found


# ---- section 0 ------------------------------------------------------------


def tool_counts(mcp):
    schemas = mcp.schemas()
    tools = sorted(schemas)
    ops = sorted(
        name for name, tool in schemas.items()
        if "scope" in tool.get("inputSchema", {}).get("properties", {}))
    return tools, ops


def log_is_clean(port):
    """`grep "Reelcut: " /tmp/reelcut-<port>.log` printing nothing — the
    prefix the startup parity check complains with. A log this script cannot
    find is not a pass."""
    path = f"/tmp/reelcut-{port}.log"
    if not os.path.exists(path):
        return False, f"{path} does not exist"
    with open(path, encoding="utf-8", errors="replace") as handle:
        bad = [line.rstrip() for line in handle if "Reelcut: " in line]
    return not bad, "; ".join(bad[:3]) if bad else "clean"


def counts_part(mcp, reference, port, reference_port):
    print("\n0 — the two instances, scored before anything is built on them")
    tools, ops = tool_counts(mcp)
    check(len(tools) >= TOOLS_FLOOR,
          f"this build publishes at least {TOOLS_FLOOR} tools ({len(tools)}) "
          "— a FLOOR: op_argument_proof.py owns the exact count")
    check(len(ops) >= OPS_FLOOR,
          f"…of which at least {OPS_FLOOR} take the scope envelope ({len(ops)})")
    ok, detail = log_is_clean(port)
    check(ok, f"this build's parity log is empty ({detail})")

    if reference is None:
        skip(3, "the reference instance did not answer tools/list")
        return None
    rtools, rops = tool_counts(reference)
    if len(rtools) != REFERENCE_TOOLS:
        skip(3, f"the reference instance answered {len(rtools)} tools, not {REFERENCE_TOOLS}"
                " — it is not the build at 1c3e92e")
        return None
    check(len(rtools) == REFERENCE_TOOLS,
          f"the reference build publishes exactly {REFERENCE_TOOLS} tools ({len(rtools)})")
    check(len(rops) == REFERENCE_OPS,
          f"…and exactly {REFERENCE_OPS} ops ({len(rops)}) — the two instances cannot be confused")
    ok, detail = log_is_clean(reference_port)
    check(ok, f"the reference build's parity log is empty ({detail})")
    missing = sorted(set(tools) - set(rtools))
    print(f"      this build adds {len(missing)} tools over the reference: "
          + ", ".join(missing[:8]))
    return reference


# ---- the version-6 fixtures ----------------------------------------------


def write_v6_pair(mcp, name, kind):
    """A two-card pair saved, then hand-written back to version 6 with
    `kind` as its bare `transition_in`.

    A `[0, 5)` grey 192 and B `[3, 8)` grey 64 on ONE track: a two-second
    overlap, which is exactly half of the shorter clip and so the longest the
    overlap rule allows. Two seconds is also what puts p = 0.25 on the frame
    grid (a one-second overlap would not), which is the whole reason the
    cards are five seconds and not three."""
    builder = Session(mcp, name + "-src")
    track = builder.tracks()[0]
    builder.card(track, grey(192), at=0, duration=5 * SEC)
    builder.card(track, grey(64), at=3 * SEC, duration=5 * SEC)
    builder.save()
    package = as_version(
        builder.path, os.path.join(WORK, f"{name}-{os.getpid()}.reelcut"), 6)
    # The overlap the app minted is a `cross_dissolve`; the version-6 spelling
    # this fixture is about is written in by hand.
    path = os.path.join(package, "project.json")
    with open(path, encoding="utf-8") as handle:
        project = json.load(handle)
    for clip in project["clips"]:
        if isinstance(clip.get("transition_in"), dict):
            clip["transition_in"] = {"kind": kind}
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(project, handle, indent=2)
        handle.write("\n")
    return package, builder


def schema_part(mcp, v6_wipe):
    print("\n1 — the schema: what a version-6 file means, and what a save writes")
    session = Session.opened(mcp, v6_wipe)
    clips = sorted(session.project()["clips"], key=lambda c: c["start"])
    later = clips[1]
    check(later["transition_in"] == {"kind": "wipe", "curve": "linear", "audio": False},
          f"a version-6 overlap opens as linear and silent ({later['transition_in']})")

    copy = Session(mcp, "e1-v6-wipe-copy", open_from=v6_wipe)
    text = copy.save()
    found_version = re.search(r'"version"\s*:\s*(\d+)', text)
    check(f'"version": {VERSION}' in text,
          f"saving that project writes version {VERSION} "
          f"(found {found_version.group(1) if found_version else 'no version key'})")
    pattern = (r'"transition_in"\s*:\s*\{\s*"kind"\s*:\s*"wipe"\s*,\s*'
               r'"curve"\s*:\s*"linear"\s*,\s*"audio"\s*:\s*false\s*\}')
    check(re.search(pattern, text) is not None,
          "…with kind, curve and audio in that order — `audio` LAST, read off the text")

    b = sorted(copy.project()["clips"], key=lambda c: c["start"])[1]["id"]
    copy.settle("set_transition_style", clip=b, curve="ease_in")
    copy.settle("set_transition", clip=b, kind="push_left")
    after = copy.clip(b)["transition_in"]
    check(after == {"kind": "push_left", "curve": "ease_in", "audio": False},
          f"a kind change over a STORED style keeps the curve and the flag ({after})")

    cut = Session(mcp, "e1-hardcut")
    track = cut.tracks()[0]
    cut.card(track, grey(192), at=0, duration=3 * SEC)
    hard_b = cut.card(track, grey(64), at=3 * SEC, duration=3 * SEC)
    before = cut.frame(3 * SEC)
    cut.settle("set_transition_style", clip=hard_b, curve="ease_out")
    stored = cut.clip(hard_b)["transition_in"]
    check(stored == {"kind": "cross_dissolve", "curve": "ease_out", "audio": True},
          f"`set_transition_style` at a HARD CUT stores a minted transition ({stored})")
    check(cut.frame(3 * SEC) == before,
          "…and nothing draws it: the frame at the cut is byte-identical")
    return session


# ---- section 2: the wipes -------------------------------------------------


def wipe_part(session, reference, v6_wipe):
    print("\n2 — the three wipe directions, and `wipe` against the reference build")
    # The reference row FIRST, while this instance's copy of the fixture is
    # still exactly what is on disk.
    if reference is None:
        skip(1, "no reference instance for the version-6 `wipe` render")
    else:
        mine = session.png(3 * SEC + SEC // 2)
        theirs = Session.opened(reference, v6_wipe).png(3 * SEC + SEC // 2)
        check(digest(mine) == digest(theirs),
              "a version-6 `wipe` renders byte-identical to the build before E1 "
              f"({digest(mine)} vs {digest(theirs)})")

    b = sorted(session.project()["clips"], key=lambda c: c["start"])[1]["id"]
    # Overlap [3, 5): p = 0.25 at 3.5 s, and linear so p is the raw progress.
    at = 3 * SEC + SEC // 2
    for kind, axis, side, wanted in [
        ("wipe_left", "column", "right", 480),
        ("wipe_up", "row", "bottom", 270),
        ("wipe_down", "row", "top", 90),
    ]:
        session.settle("set_transition", clip=b, kind=kind)
        session.settle("set_transition_style", clip=b, curve="linear")
        image = session.image(at)
        if axis == "column":
            values = image.row(image.height // 2)
        else:
            values = image.column(image.width // 2)
        if side in ("right", "bottom"):
            # The incoming band is the TRAILING run; its first index is the
            # edge.
            found = last_run_start(values, 64, 192)
        else:
            # The incoming band runs from 0, so the edge is where it STOPS —
            # the first pixel nearer the OUTGOING colour.
            found = first_nearer(values, 192, 64)
        check(found is not None and abs(found - wanted) <= 1,
              f"{kind} at p = 0.25: the incoming colour is on the {side}, "
              f"boundary {axis} {found} (wanted {wanted} ± 1)")

    session.settle("set_transition", clip=b, kind="wipe_left")
    session.settle("set_transition_style", clip=b, curve="ease_in_out")
    image = session.image(at)
    wanted = round(640 * (1 - ease("ease_in_out", 0.25)))
    found = last_run_start(image.row(image.height // 2), 64, 192)
    check(found is not None and abs(found - wanted) <= 1,
          f"`ease_in_out` moves that boundary to 640·(1 − smoothstep(0.25)) = {wanted} "
          f"(found {found})")


# ---- section 3: the push, and the dissolve against the reference ----------


def push_part(session, reference, v6_dissolve):
    print("\n3 — a push's offset under two curves, and a version-6 dissolve")
    b = sorted(session.project()["clips"], key=lambda c: c["start"])[1]["id"]
    # Cleared, then set: a clip that had NO transition gets a MINTED one,
    # which is eased at both ends (spec §11, R5-2).
    session.settle("set_transition", clip=b, kind=None)
    session.settle("set_transition", clip=b, kind="push_left")
    minted = session.clip(b)["transition_in"]
    check(minted == {"kind": "push_left", "curve": "ease_in_out", "audio": True},
          f"a kind on a clip that had none MINTS the transition ({minted})")
    at = 3 * SEC + SEC // 2
    wanted = round(640 * (1 - ease("ease_in_out", 0.25)))
    found = last_run_start(session.image(at).row(180), 64, 192)
    check(found is not None and abs(found - wanted) <= 1,
          f"a minted push_left puts the seam at 640·(1 − smoothstep(0.25)) = {wanted} "
          f"(found {found})")
    session.settle("set_transition_style", clip=b, curve="linear")
    found = last_run_start(session.image(at).row(180), 64, 192)
    check(found is not None and abs(found - 480) <= 1,
          f"…and `linear` puts it back at 640·0.75 = 480 (found {found})")

    if reference is None:
        skip(5, "no reference instance for the version-6 cross dissolve")
        return
    mine = Session.opened(session.mcp, v6_dissolve)
    theirs = Session.opened(reference, v6_dissolve)
    for t in [3 * SEC, 3 * SEC + SEC // 2, 4 * SEC, 4 * SEC + SEC // 2,
              4 * SEC + 29 * FRAME]:
        a = digest(mine.png(t))
        b2 = digest(theirs.png(t))
        check(a == b2,
              f"a version-6 cross dissolve at {t / SEC:.4f} s is byte-identical to the "
              f"build before E1 ({a} vs {b2})")


# ---- section 4: add_transition's arithmetic -------------------------------


def restore(session, p0, what):
    """Every bullet below starts from P0. `undo` until `get_project` is P0
    again, and SAY so — the step-down loop reads both clips' durations, so a
    bullet that started from the previous bullet's leftovers would measure a
    different rule."""
    for _ in range(12):
        if canonical(session.project()) == p0:
            break
        try:
            session.undo()
        except ToolError:
            break
    ok = canonical(session.project()) == p0
    check(ok, f"{what}: the fixture is back at P0 before this bullet's first edit")
    return ok


def add_part(mcp):
    print("\n4 — `add_transition`: the arithmetic, the clamps and the refusals")
    s4 = Session(mcp, "e1-s4")
    track = s4.tracks()[0]
    tone_a = s4.media("toneA.m4a")
    tone_b = s4.media("toneB.m4a")
    a, b, tail, head = trimmed_pair(s4, track, tone_a, tone_b)
    c = s4.card(track, grey(192), at=8 * SEC, duration=2 * SEC)
    other = s4.add_track()
    far = s4.card(other, grey(64), at=0, duration=2 * SEC)
    p0 = canonical(s4.project())
    before = {clip["id"]: clip for clip in s4.project()["clips"]}
    check(before[a]["start"] == 0 and before[a]["duration"] == 3 * SEC
          and tail >= SEC,
          f"the fixture: A is [0, 3) with a {tail / SEC:.4f} s tail "
          f"({before[a]['start']}, {before[a]['duration']})")
    check(before[b]["start"] == 3 * SEC and before[b]["duration"] == 3 * SEC
          and before[b]["source"].get("in") == head,
          f"…and B is [3, 6) with a {head / SEC:.4f} s head "
          f"(in = {before[b]['source'].get('in')})")
    duration0 = s4.duration()

    # --- centre ---
    s4.op("add_transition", clip=b, duration=SEC)
    now = {clip["id"]: clip for clip in s4.project()["clips"]}
    check(now[a]["start"] == 0 and now[a]["duration"] == 3 * SEC + SEC // 2,
          f"centre: A grows half the overlap, [0, 3.5) ({now[a]['duration']})")
    check(now[b]["start"] == 3 * SEC - SEC // 2
          and now[b]["duration"] == 3 * SEC + SEC // 2,
          f"…B moves back the other half, [2.5, 6) ({now[b]['start']})")
    check(now[b]["source"].get("in") == head - SEC // 2,
          f"…and its source window opens by exactly that much (in = "
          f"{now[b]['source'].get('in')}, wanted {head - SEC // 2})")
    overlap = now[a]["start"] + now[a]["duration"] - now[b]["start"]
    check(overlap == SEC, f"…the overlap is one second ({overlap} ticks)")
    check(json.dumps(now[c], sort_keys=True) == json.dumps(before[c], sort_keys=True),
          "…the third clip on the track did not move")
    check(json.dumps(now[far], sort_keys=True) == json.dumps(before[far], sort_keys=True),
          "…nor did the clip on the other track")
    check(s4.duration() == duration0,
          f"…and the timeline is the same length ({s4.duration()})")
    s4.undo()
    check(canonical(s4.project()) == p0,
          "one undo restores `get_project` byte for byte")

    # --- align ---
    restore(s4, p0, "before")
    s4.op("add_transition", clip=b, duration=SEC, align="before")
    now = {clip["id"]: clip for clip in s4.project()["clips"]}
    check(now[a]["duration"] == 3 * SEC, f"`before`: A does not move ({now[a]['duration']})")
    check(now[b]["start"] == 2 * SEC and now[b]["source"].get("in") == head - SEC,
          f"…the whole overlap comes out of B's head, [2, 6) "
          f"({now[b]['start']}, in = {now[b]['source'].get('in')}, wanted {head - SEC})")

    restore(s4, p0, "after")
    s4.op("add_transition", clip=b, duration=SEC, align="after")
    now = {clip["id"]: clip for clip in s4.project()["clips"]}
    check(now[a]["duration"] == 4 * SEC, f"`after`: A grows the whole overlap ({now[a]['duration']})")
    check(now[b]["start"] == 3 * SEC and now[b]["source"].get("in") == head,
          f"…and B does not move at all ({now[b]['start']})")

    # --- the step-down ---
    restore(s4, p0, "step-down")
    s4.op("add_transition", clip=b, duration=10 * SEC)
    now = {clip["id"]: clip for clip in s4.project()["clips"]}
    overlap = now[a]["start"] + now[a]["duration"] - now[b]["start"]
    shorter = min(now[a]["duration"], now[b]["duration"])
    check(overlap == 2 * SEC,
          f"a ten-second request clamps to a two-second overlap ({overlap} ticks)")
    check(2 * overlap <= shorter,
          f"…which is the overlap rule's own bound: 2·{overlap} ≤ {shorter}")

    # --- the odd frame ---
    restore(s4, p0, "odd frame")
    s4.op("add_transition", clip=b, duration=3 * FRAME)
    now = {clip["id"]: clip for clip in s4.project()["clips"]}
    check(now[b]["start"] == 3 * SEC - 2 * FRAME,
          f"three frames: the odd one goes to B, whose start moves back two "
          f"({3 * SEC - now[b]['start']} ticks)")
    check(now[a]["start"] + now[a]["duration"] == 3 * SEC + FRAME,
          f"…and A grows by the remaining one ({now[a]['duration'] - 3 * SEC} ticks)")

    # --- speed ---
    s4s = Session(mcp, "e1-s4-speed")
    strack = s4s.tracks()[0]
    sa, sb, stail, shead = trimmed_pair(
        s4s, strack, s4s.media("toneA.m4a"), s4s.media("toneB.m4a"))
    s4s.op("set_speed", clip=sb, rate=2)
    sped = s4s.clip(sb)
    check(sped["start"] == 3 * SEC and sped["duration"] == 3 * SEC // 2,
          f"at 2× B is [3, 4.5) — `set_speed` rescales the duration ({sped['duration']})")
    s4s.op("add_transition", clip=sb, duration=SEC // 2, align="before")
    sped = s4s.clip(sb)
    check(sped["start"] == 3 * SEC - SEC // 2,
          f"…half a second of TIMELINE comes off its head ({sped['start']})")
    check(sped["source"].get("in") == shead - SEC,
          f"…and TWICE that of SOURCE, the speed applied ONCE: in = "
          f"{sped['source'].get('in')} (wanted {shead} − 2·{SEC // 2} = {shead - SEC}; "
          "applied twice it would clamp to 0)")

    # --- a nest ---
    restore(s4, p0, "nest")
    nest = s4.op_with("nest", {"clips": [b]})["new_clips"][0]
    nested = s4.clip(nest)
    check(nested["start"] == 3 * SEC and nested["duration"] == 3 * SEC,
          f"the nest clip is [3, 6) ({nested['start']}, {nested['duration']})")
    s4.op("add_transition", clip=nest, duration=SEC)
    now = {clip["id"]: clip for clip in s4.project()["clips"]}
    check(now[a]["duration"] == 4 * SEC,
          f"a nest gives no head, so `center` takes the whole overlap from A's tail "
          f"({now[a]['duration']})")
    check(now[nest]["start"] == 3 * SEC and now[nest]["duration"] == 3 * SEC,
          f"…and the nest clip does not move ({now[nest]['start']})")
    s4.undo()
    message = s4.error("add_transition", clip=nest, duration=SEC, align="before")
    check(message is not None and "no room for an overlap" in message
          and "ripple: true" in message,
          f"…under `before` there is nowhere to take it from: {message!r}")
    checks_project = {clip["id"]: clip for clip in s4.project()["clips"]}
    check(checks_project[nest]["start"] == 3 * SEC
          and checks_project[a]["duration"] == 3 * SEC,
          "…and the refusal changed nothing")

    # --- an action's rebase ---
    s4a = Session(mcp, "e1-s4-action")
    atrack = s4a.tracks()[0]
    # B is `AV.mov` and not a tone: an `.m4a` clip has no video group at all,
    # so two renders of it would be two backdrops and the rebase would be
    # invisible. `AV.mov` is also five seconds, so the same three calls trim
    # it identically.
    aa, ab, atail, ahead = trimmed_pair(
        s4a, atrack, s4a.media("toneA.m4a"), s4a.media("AV.mov"))
    action = s4a.op("add_action", clip=ab, at=SEC, duration=SEC)["new_actions"][0]
    s4a.op("set_action_end", clip=ab, action=action, patch={"video": {"scale": 2}})

    def action_end(session, clip_id, action_id):
        clip = session.clip(clip_id)
        one = {act["id"]: act for act in clip["actions"]}[action_id]
        return clip["start"] + one["start"] + one["duration"], one["start"]

    end_before, start_before = action_end(s4a, ab, action)
    check(end_before == 5 * SEC,
          f"the action ends at 5 s on the timeline, over source 4 s ({end_before})")
    frame_before = s4a.frame(end_before)
    s4a.op("add_transition", clip=ab, duration=SEC)
    end_after, start_after = action_end(s4a, ab, action)
    check(start_after == start_before + SEC // 2,
          f"the action is rebased by the head the transition revealed "
          f"({start_before} → {start_after})")
    check(end_after == end_before,
          f"…so it still ends at the same moment ({end_after})")
    check(s4a.frame(end_after) == frame_before,
          "…and that moment renders the same SOURCE frame, byte for byte "
          "(a lost rebase would draw source 3.5 s instead of 4 s)")

    # --- the refusals ---
    restore(s4, p0, "refusals")
    for kwargs, wanted in [
        (dict(clip=b, duration=0), "duration must be positive"),
        (dict(clip=a, duration=SEC), "is the first clip on its track"),
        (dict(clip=c, duration=SEC), "there is a gap of"),
        (dict(clip=999, duration=SEC), "999"),
    ]:
        message = s4.error("add_transition", **kwargs)
        check(message is not None and wanted in message,
              f"refused, saying {wanted!r}: {message!r}")
    s4.op("add_transition", clip=b, duration=SEC)
    message = s4.error("add_transition", clip=b, duration=SEC)
    check(message is not None and "it already overlaps clip" in message,
          f"a second transition on the same cut is refused: {message!r}")
    restore(s4, p0, "after the refusals")

    # --- no handle at all ---
    s4n = Session(mcp, "e1-s4-nohandle")
    ntrack = s4n.tracks()[0]
    na = s4n.place(ntrack, s4n.media("toneA.m4a"), 0)
    # At A's own end, whatever the file decodes to: a gap of one frame would
    # be refused for the wrong reason.
    nb = s4n.place(ntrack, s4n.media("toneB.m4a"), s4n.clip(na)["duration"])
    message = s4n.error("add_transition", clip=nb, duration=SEC)
    check(message is not None and "was refused at add_transition: the cut before clip" in message,
          f"two WHOLE files butted: the refusal is the rule's own sentence: {message!r}")
    check(message is not None and "no room for an overlap" in message,
          "…naming what clamped to nothing")
    check(message is not None and "ripple: true" in message,
          "…and the way to get the transition anyway")
    check(na is not None and nb is not None, "…the fixture placed two whole tones")
    return s4


# ---- section 5: the audio crossfade ---------------------------------------


def audio_part(mcp, reference):
    print("\n5 — the crossfade, measured tone by tone in 25 ms windows")
    pair = Session(mcp, "e1-audio")
    track = pair.tracks()[0]
    a, b, tail, head = trimmed_pair(
        pair, track, pair.media("toneA.m4a"), pair.media("toneB.m4a"))
    pair.op("add_transition", clip=b, duration=SEC)
    minted = pair.clip(b)["transition_in"]
    check(minted["audio"] is True and minted["curve"] == "ease_in_out",
          f"the overlap's transition is minted: eased and crossfading ({minted})")
    start = (3 * SEC - SEC // 2) / SEC          # 2.5 s
    data = pcm(pair.export_wav("mix"))

    def amplitude(at, hz):
        return goertzel(mono_window(data, at), hz, 48000)

    a0 = sum(amplitude(1.0 + 0.025 * k, 440) for k in range(40)) / 40.0
    b0 = sum(amplitude(4.0 + 0.025 * k, 880) for k in range(40)) / 40.0
    check(a0 > 1000 and b0 > 1000,
          f"the two tones are there to measure: 440 at {a0:.0f}, 880 at {b0:.0f} "
          "(16-bit full scale is 32768)")

    # **The first window is the HOST's, not the feature's.** AVFoundation
    # does not apply a mix input's first volume point until some twelve
    # milliseconds in, measured: the incoming clip's first ~20 ms play at
    # full level whatever the ramp says — at a hard cut with the clip MUTED
    # too, which is where this was pinned down and why it is not E1's. So
    # every window from 25 ms on is scored, window 0 is PRINTED, and §12
    # records it as a limit. **The hard cut is SCORED**, at the end of this
    # section: the exclusion rests on that row and not on this paragraph.
    worst_out = worst_in = worst_sum = 0.0
    measured = 0
    edge_in = amplitude(start, 880) / b0
    for k in range(1, 40):
        at = start + 0.025 * k
        centre = at + 0.0125
        p = ease("ease_in_out", (centre - start) / 1.0)
        out_ratio = amplitude(at, 440) / a0
        in_ratio = amplitude(at, 880) / b0
        if gain(p, False) >= 0.1:
            worst_out = max(worst_out, abs(db(out_ratio) - db(gain(p, False))))
            measured += 1
        if gain(p, True) >= 0.1:
            worst_in = max(worst_in, abs(db(in_ratio) - db(gain(p, True))))
        worst_sum = max(
            worst_sum,
            abs(10 * math.log10(max(out_ratio ** 2 + in_ratio ** 2, 1e-12))))
    print(f"      (the mix edge: the incoming tone reads {edge_in:.3f} of full scale in "
          f"the first 25 ms, where the ramp asks for {gain(ease('ease_in_out', 0.0125), True):.4f}"
          " — a limit, measured at a hard cut too)")
    check(measured >= 20, f"{measured} windows carry an outgoing gain above 0.1")
    check(worst_out <= 0.3,
          f"the outgoing tone tracks cos(pπ/2) within {worst_out:.3f} dB (≤ 0.3)")
    check(worst_in <= 0.3,
          f"the incoming tone tracks sin(pπ/2) within {worst_in:.3f} dB (≤ 0.3)")
    check(worst_sum <= 0.5,
          f"…and the summed power is flat within {worst_sum:.3f} dB (≤ 0.5)")

    pair.op("set_audio", clips=[b], patch={"muted": True})
    muted = pcm(pair.export_wav("muted"))
    loudest = max(
        goertzel(mono_window(muted, start + 0.025 * k), 880, 48000) for k in range(1, 40))
    check(db(loudest / 32768.0) < -60,
          f"with the INCOMING clip muted the 880 tone is gone from 25 ms on: peak "
          f"{db(loudest / 32768.0):.1f} dBFS (< −60)")
    tail = rms(mono_window(muted, 3.475)) / 32768.0
    check(db(tail) < -60,
          f"…and the last 25 ms of the outgoing clip are silent too: "
          f"{db(tail):.1f} dBFS (< −60)")
    pair.undo()

    # --- the version-6 export, against the reference build ---
    pair.save()
    v6_audio = as_version(
        pair.path, os.path.join(WORK, f"e1-v6-audio-{os.getpid()}.reelcut"), 6)
    mine = Session.opened(mcp, v6_audio)
    once = pcm(mine.export_wav("v6-a"))
    twice = pcm(mine.export_wav("v6-b"))
    w = wobble(once, twice)
    tolerance = w[0] if w else 0
    check(w is not None,
          f"two exports of the same version-6 project from THIS build: {describe_pcm(once, twice)}")
    if reference is None:
        skip(1, "no reference instance for the version-6 export")
    else:
        theirs = pcm(Session.opened(reference, v6_audio).export_wav("v6-ref"))
        check(same(theirs, once, tolerance),
              f"a version-6 overlap decodes sample-for-sample as it did before E1, "
              f"within this build's own wobble of {tolerance}: {describe_pcm(theirs, once)}")

    # --- nested ---
    nest_session = Session(mcp, "e1-audio-nest")
    ntrack = nest_session.tracks()[0]
    tone_a = nest_session.media("toneA.m4a")
    tone_b = nest_session.media("toneB.m4a")
    na, nb, ntail, nhead = trimmed_pair(nest_session, ntrack, tone_a, tone_b)
    nest_session.op("add_transition", clip=nb, duration=SEC)
    nest = nest_session.op_with("nest", {"clips": [na, nb]})["new_clips"][0]
    check(nest_session.clip(nest)["start"] == 0
          and nest_session.clip(nest)["duration"] == 6 * SEC,
          f"the nest clip is [0, 6) ({nest_session.clip(nest)['duration']})")
    nc, chead = trimmed(nest_session, ntrack, tone_a, 6 * SEC)
    nest_session.op("add_transition", clip=nc, duration=SEC, align="before")
    outer = nest_session.clip(nc)
    check(outer["start"] == 5 * SEC,
          f"the outer overlap is [5, 6) ({outer['start']})")
    data = pcm(nest_session.export_wav("nested"))

    # Window 0 excluded for the reason above: the mix's first ramp point does
    # not take hold until ~12 ms in, at every overlap and at a hard cut.
    inner_worst = 0.0
    for k in range(1, 40):
        at = 2.5 + 0.025 * k
        p = ease("ease_in_out", (at + 0.0125 - 2.5) / 1.0)
        out_ratio = goertzel(mono_window(data, at), 440, 48000) / a0
        in_ratio = goertzel(mono_window(data, at), 880, 48000) / b0
        inner_worst = max(
            inner_worst,
            abs(10 * math.log10(max(out_ratio ** 2 + in_ratio ** 2, 1e-12))))
    check(inner_worst <= 0.5,
          f"the INNER overlap still follows the constant-power law inside the nest: "
          f"{inner_worst:.3f} dB (≤ 0.5)")

    outer_out = outer_in = 0.0
    for k in range(1, 40):
        at = 5.0 + 0.025 * k
        p = ease("ease_in_out", (at + 0.0125 - 5.0) / 1.0)
        out_ratio = goertzel(mono_window(data, at), 880, 48000) / b0
        in_ratio = goertzel(mono_window(data, at), 440, 48000) / a0
        if gain(p, False) >= 0.1:
            outer_out = max(outer_out, abs(db(out_ratio) - db(gain(p, False))))
        if gain(p, True) >= 0.1:
            outer_in = max(outer_in, abs(db(in_ratio) - db(gain(p, True))))
    check(outer_out <= 0.3,
          f"the OUTER overlap fades the nest's 880 out as cos: {outer_out:.3f} dB (≤ 0.3)")
    check(outer_in <= 0.3,
          f"…and brings the new 440 in as sin: {outer_in:.3f} dB (≤ 0.3)")

    # --- the same burst where there is NO ramp: a hard cut, the clip muted --
    # This is the row the exclusion of window 0 rests on. The fixture is the
    # §4 pair with no transition on it at all and the incoming clip MUTED, so
    # nothing in E1 touches the cut and the mix is asked for silence from the
    # incoming clip's first sample. If the first 25 ms still carry the tone
    # here, the same 25 ms in the crossfade above are the host's mix and not
    # the ramp's. This row has no ramp in it, so it guards nothing about a
    # ramp: the cut's edge against the overlap's own first window is printed
    # below, not scored.
    cut = Session(mcp, "e1-audio-hardcut")
    cut_track = cut.tracks()[0]
    _, cut_b, _, _ = trimmed_pair(
        cut, cut_track, cut.media("toneA.m4a"), cut.media("toneB.m4a"))
    cut.op("set_audio", clips=[cut_b], patch={"muted": True})
    cut_data = pcm(cut.export_wav("hardcut-muted"))
    cut_edge = goertzel(mono_window(cut_data, 3.0), 880, 48000) / b0
    cut_rest = max(
        goertzel(mono_window(cut_data, 3.0 + 0.025 * k), 880, 48000) for k in range(1, 40))
    check(cut.clip(cut_b).get("transition_in") is None
          and cut_edge > 0.2 and db(cut_rest / 32768.0) < -60,
          f"at a HARD CUT with the incoming clip MUTED — no transition, no ramp — its "
          f"first 25 ms still carry {cut_edge:.3f} of the tone (> 0.2) and every window "
          f"after them is {db(cut_rest / 32768.0):.1f} dBFS (< −60): the burst is the "
          f"host's mix, which is why window 0 is excluded above "
          f"(the overlap's own first window read {edge_in:.3f})")


# ---- section 6: Remove Silences never cuts inside a transition ------------


def detect(session, **kwargs):
    """`detect_silence`, waited on: a media file whose peaks are still being
    written reports `pending_peaks` and proposes nothing inside it."""
    for _ in range(60):
        answer = session.op("detect_silence", **kwargs)
        if "pending_peaks" not in answer:
            return answer
        time.sleep(1.0)
    return answer


def silence_part(mcp):
    print("\n6 — Remove Silences never proposes a cut inside a transition")
    a_session = Session(mcp, "e1-walls")
    track = a_session.tracks()[0]
    media = a_session.media("silence.mov")
    a = a_session.place(track, media, 0)
    a_session.op("trim_end", clip=a, to=25 * SEC // 10)
    # B shows the file from 3 s on, so the 2.0–3.5 s quiet straddles the cut
    # (A's own 2.0–2.5 s, then B's 3.0–3.5 s at project 2.5–3.0 s) and the
    # 6–7 s gap lands at [5.5, 6.5).
    b = a_session.place(track, media, 25 * SEC // 10)
    a_session.op("trim_start", clip=b, to=55 * SEC // 10)
    a_session.op("move_clip", clips=[b], delta=-3 * SEC)
    control = detect(a_session, mode="level", threshold_db=-40.0,
                     min_length=SEC // 2, padding=0)
    ranges = [tuple(r) for r in control["ranges"]]
    check(any(r[0] < 3 * SEC and r[1] > 2 * SEC for r in ranges),
          f"without a transition a quiet run crosses the cut at 2.5 s ({ranges})")

    a_session.op("add_transition", clip=b, duration=SEC // 2)
    clips = {clip["id"]: clip for clip in a_session.project()["clips"]}
    a_end = clips[a]["start"] + clips[a]["duration"]
    b_start = clips[b]["start"]
    width = a_end - b_start
    wall = (b_start - width, a_end + width)
    after = detect(a_session, mode="level", threshold_db=-40.0,
                   min_length=SEC // 2, padding=0)
    walled = [tuple(r) for r in after["ranges"]]
    check(width > 0, f"the overlap is {width} ticks, wall [{wall[0]}, {wall[1]}]")
    check(not any(r[0] < wall[1] and r[1] > wall[0] for r in walled),
          f"no proposed range reaches into the wall around it ({walled})")
    check(len(walled) > 0,
          f"…and the quiet away from it is still proposed ({walled})")
    check(any(abs(r[0] - 55 * SEC // 10) < SEC // 2 for r in walled),
          f"…which is the file's 6–7 s gap, now at [5.5, 6.5) ({walled})")
    check(set(after) == set(control),
          f"the answer has the same keys with and without the transition — a wall is "
          f"never reported ({sorted(set(after) ^ set(control))})")

    # (b) the crossfade's own dip, and a fade that proves the detector sees one.
    b_session = Session(mcp, "e1-walls-fade")
    btrack = b_session.tracks()[0]
    ba = b_session.place(btrack, b_session.media("toneA.m4a"), 0)
    b_session.op("trim_end", clip=ba, to=3 * SEC)
    b_session.card(btrack, grey(192), at=3 * SEC, duration=3 * SEC)
    later = sorted(b_session.project()["clips"], key=lambda c: c["start"])[1]["id"]
    b_session.op("add_transition", clip=later, duration=2 * SEC, align="after")
    found = detect(b_session, mode="level", threshold_db=-40.0,
                   min_length=SEC // 10, padding=0)
    check(found["ranges"] == [],
          f"the crossfade's own dip is inside the wall, so nothing is proposed "
          f"({found['ranges']})")

    # (c) the WIDENING itself, which §3f argues for and nothing measured:
    #     with an EXACT wall the nearest legal cut destroys the transition.
    #     The run has to be long enough that what an exact wall leaves of it
    #     survives the length filter — the reason (a) above cannot see this.
    d_session = Session(mcp, "e1-walls-widening")
    dtrack = d_session.tracks()[0]
    dmedia = d_session.media("silence.mov")
    da = d_session.place(dtrack, dmedia, 0)
    d_session.op("trim_end", clip=da, to=35 * SEC // 10)
    # A ends inside the file's 2.0–3.5 s quiet, so the run ends AT the cut;
    # B shows the file from 7 s, where it is a tone again.
    db = d_session.place(dtrack, dmedia, 35 * SEC // 10)
    d_session.op("trim_start", clip=db, to=7 * SEC)
    d_session.op("move_clip", clips=[db], delta=-35 * SEC // 10)
    d_session.op("add_transition", clip=db, duration=SEC // 2)
    dclips = {clip["id"]: clip for clip in d_session.project()["clips"]}
    d_a_end = dclips[da]["start"] + dclips[da]["duration"]
    d_b_start = dclips[db]["start"]
    d_width = d_a_end - d_b_start
    proposed = [tuple(r) for r in detect(d_session, mode="level", threshold_db=-40.0,
                                         min_length=SEC // 2, padding=0)["ranges"]]
    check(d_width > 0 and any(r[1] > 0 for r in proposed),
          f"a quiet run ends at the cut and something is still proposed "
          f"(overlap {d_width}, {proposed})")
    d_wall = (d_b_start - d_width, d_a_end + d_width)
    check(not any(r[0] < d_wall[1] and r[1] > d_wall[0] for r in proposed),
          f"no proposal reaches into the WIDENED wall {list(d_wall)} — an exact one "
          f"leaves a proposal ending at the overlap's own first tick ({proposed})")
    d_session.op("ripple_delete_ranges", ranges=[list(r) for r in proposed])
    # The ids do not survive a split, so the pair is found by geometry: the
    # overlaps left on the track, and the rule each of them has to obey.
    ordered = sorted((c for c in d_session.project()["clips"] if c["track"] == dtrack),
                     key=lambda c: c["start"])
    pairs = [(a, b) for a, b in zip(ordered, ordered[1:])
             if a["start"] + a["duration"] > b["start"]]
    check(len(pairs) == 1,
          f"the transition survives the cut: {len(pairs)} overlap(s) left on the track "
          f"({[(c['start'], c['duration']) for c in ordered]})")
    worst = max(
        ((a["start"] + a["duration"] - b["start"], min(a["duration"], b["duration"]) // 2)
         for a, b in pairs), default=(0, 0))
    check(worst[0] <= worst[1],
          f"…and it is still inside the overlap rule — {worst[0]} ticks against half of "
          f"the shorter clip ({worst[1]}). An EXACT wall lets the cut leave A's tail "
          f"wholly under B, which neither ripple_delete_ranges nor validate checks.")

    c_session = Session(mcp, "e1-walls-control")
    ctrack = c_session.tracks()[0]
    ca = c_session.place(ctrack, c_session.media("toneA.m4a"), 0)
    c_session.op("trim_end", clip=ca, to=3 * SEC)
    c_session.op("set_audio", clips=[ca], patch={"fade_out": 2 * SEC})
    control_b = detect(c_session, mode="level", threshold_db=-40.0,
                       min_length=SEC // 10, padding=0)
    tails = [tuple(r) for r in control_b["ranges"]]
    check(any(abs(r[1] - 3 * SEC) <= FRAME for r in tails),
          f"the control — the same tail faded, with no transition — IS proposed ({tails})")


# ---- main -----------------------------------------------------------------


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4825
    reference_port = int(sys.argv[2]) if len(sys.argv) > 2 else 4826
    os.makedirs(WORK, exist_ok=True)
    print(f"E1 — transitions, second pass. Build on {port}, reference on {reference_port}.")
    mcp = MCP(port)
    try:
        reference = MCP(reference_port)
    except Exception as error:               # noqa: BLE001 — reported, never fatal
        print(f"  (the reference instance on {reference_port} did not answer: {error})")
        reference = None

    reference = counts_part(mcp, reference, port, reference_port)

    v6_wipe, _ = write_v6_pair(mcp, "e1-v6-wipe", "wipe")
    v6_dissolve, _ = write_v6_pair(mcp, "e1-v6-dissolve", "cross_dissolve")

    session = schema_part(mcp, v6_wipe)
    wipe_part(session, reference, v6_wipe)
    push_part(session, reference, v6_dissolve)
    add_part(mcp)
    audio_part(mcp, reference)
    silence_part(mcp)

    print()
    if skipped:
        print("SKIPPED:")
        for line in skipped:
            print(f"  - {line}")
    if failures:
        print(f"{checks - len(failures)}/{checks} checks passed — {len(failures)} FAILED:")
        for line in failures:
            print(f"  - {line}")
        sys.exit(1)
    print(f"{checks}/{checks} checks passed")


if __name__ == "__main__":
    main()
