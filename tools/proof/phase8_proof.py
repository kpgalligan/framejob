"""Road map 2, phase 8 — Viewing, driven against the built binary over MCP.

Phase 8 is three features and **none of them has an MCP surface**, which is
not an oversight and is the hardest thing about proving it. View ▸ Preview
Quality (8a) edits nothing; the preview window (8b) is an `NSPanel` and a
second `AVPlayerLayer`; the Media tab's search, sort, "unused only" and
Reveal in Timeline (8c) are a pane's own state. Adding a tool so that a
proof could exist would be the proof deciding the product's API — settled
for phase 5's level meter, inherited by phase 7's export queue, and
inherited again here.

So this script claims the two things that ARE over the wire — and then,
because those two together would pass against a build with 8a deleted, one
more through a PROBE built out of `app/Sources` (section 5 below).

**Section 1 is the headline, and it is a claim about ISOLATION rather than
about effect.** `PreviewQuality` is persisted at `FrameJobPreviewQuality` in
`UserDefaults`, and `PreviewQuality.stored()` reads
`UserDefaults.standard` — so the setting can be put into a running app
through the argument domain at launch, exactly as
`-ApplePersistenceIgnoreState` already is. This script therefore launches
**two instances of the same binary**, one with the key ABSENT (Full) and one
with `-FrameJobPreviewQuality 2` (Quarter), drives the identical scripted
sequence through both, and byte-compares what comes out:

* every `render_frame` PNG, byte for byte;
* an `apng` and a `gif` export, byte for byte (both go through
  `ExporterImageSequence.swift`, which has no clock in it — phase 7 measured
  that a `.mov` carries a creation time at one-second resolution, so two
  movies of one project differ in six header bytes when they land in
  different seconds);
* and a `prores_422` export compared on its DECODED PIXELS rather than its
  bytes, because that is the `ExportWriter` limb and the movie clock makes a
  byte comparison of two `.mov` files a comparison of two clocks.

That is what "the export and `render_frame` paths are UNREACHABLE from this
setting" means where it can be measured: not that the two calls agree, but
that two processes AT DIFFERENT QUALITIES write identical files. The mutant
this catches is the one the design exists to prevent — the scale passed into
`CompositionBuilder.build`, which every path shares, instead of applied to
`Playback`'s own copy of the configuration (`Playback.previewComposition`).

**What section 1 deliberately CANNOT claim, said plainly.** No MCP call
reads the player, its composition, or its render size: `render_frame` builds
its own composition and `export` builds two more, and none of the three is
the item the `AVPlayerLayer` is showing. So section 1 says only that the
setting does not LEAK — never that it does anything. That gap is not
theoretical and was not reasoned about: a build whose `previewComposition`
returned its argument unconditionally, the feature deleted outright, scored
**65/65 against this file before section 5 existed**, which is why section 5
exists.

**Section 5 is the other half, and it is a PROBE rather than a tool call.**
`phase5_chrome.py` compiles one out of `Loudness.swift`, `phase6_chrome.py`
one out of the whole of `app/Sources`, and CLAUDE.md states the rule: when
the thing to check is app arithmetic or app structure with no caller a script
can reach, the answer is a probe and not a photograph — and adding a tool so
that a proof could exist would be the proof deciding the product's API. So
section 5 compiles every file in `app/Sources` except its `main.swift`
against a `main.swift` of this script's own (`tools/proof/swift_build.py`'s
line, cached by content), opens the package section 5 just
saved, puts an `EditorViewController` in a window, spins the runloop until
the player has an item, and reads the render size of the composition that
item is carrying. At Full it is the canvas, at Half 320 × 180, at Quarter
160 × 90 — the setting DOING something, read off a real `AVPlayerItem` — and
the same probe drives View ▸ Preview Quality ▸ itself, with an `NSMenuItem`
carrying the row's tag, to show the LIVE item taking the new size and coming
back. **It is the app's own sources in a second process and not the shipped
binary**, which is the same standard the offscreen harness sets and is said
here rather than implied.

What is left over after both halves needs a person at the machine: whether
the preview is FASTER, and whether the picture through the scaler is the Full
frame through one resample rather than a different frame. A render size is
not a frame rate.

**Section 0 scores the launch mechanism before section 1 leans on it**, in
the shape phase 7's section 0 established for its two ffmpeg instruments. A
build in which the argument never reached the app would make section 1's
byte comparisons pass by rendering the same quality twice, and no check
inside it could tell. So section 0 EXTRACTS `enum PreviewQuality` from
`app/Sources/EditorViewController+PreviewQuality.swift` — the app's own
bytes, `sed`'s job done in Python, with two imports prepended and nothing
else — compiles it with a `main.swift` of its own, and runs it twice: once
bare and once with `-FrameJobPreviewQuality 2`. It also pins the trap under
that: an argument-domain value arrives as a **String**, so
`object(forKey:) != nil` is satisfied and `integer(forKey:)` coerces it,
which is why `stored()`'s two-call spelling is load-bearing and why an
`object(forKey:) as? Int` would read Full for every launch argument ever
passed. This is an instrument, not the app: it is the same source text in a
different process, and the app's own reading of it is unobservable. What
makes the whole thing hang together is the mutation run — under mutant 1 the
Quarter instance renders 160 × 90 where the Full one renders 640 × 360,
which can only happen if the launch argument reached `PreviewQuality.stored()`
inside a running Frame Job.

**Section 2 is phase 8c's defect fix, end to end, and it is the one place
phase 8 changed an answer an agent can read.** "Is this media used" was
written twice in Swift and both spellings filtered `snapshot.clips` — the
TOP LEVEL alone — while the core refuses against `every_clip()`, the
timeline's clips CHAINED with every nest's (`core/src/edit_track.rs`). So
media used only inside a compound clip walked past the Swift guard with a
user count of zero and was refused by the core with a reason-less "nothing
changed", which reached a caller as the shared "Remove Media made no
change…" and told it nothing. `MediaUsage.swift` is the one spelling now,
and the Media tab's alert is its only caller: deepening D2·4
(kpgalligan/framejob#12) deleted the agent handler's count, so what an agent
hears is **the core's own sentence**, "media 3 is still used by clip 7; pass
with_clips: true to remove the media and its clips". The section asserts it
WHOLE, which is a stronger claim than the file-and-count one it replaced —
the clip id is the thing a caller acts on, and it is the id the core names
at the moment it refuses. It builds the fixture over the wire — import, a
clip, `nest` — and asserts that the identity's "made no change" is NOT what
comes back, that `with_clips: true` removes the entry and the nested clip
while leaving the nest CLIP itself on the timeline, and that one undo puts
the whole project JSON back. The check with the sharpest teeth is the
both-levels one: media used once at the top level AND once inside a nest is
refused naming BOTH clips, where anything counting the top level alone names
one. `refusal_proof.py` §6 is this rule's own section and the two moved
together.

**Sections 3 and 4 are the "nothing else moved" half.** The catalog is
EXACTLY 73 tools, the number phase 6 took and phase 7 kept: phase 8 adds no
op and no tool, so a fourth phase in a row asserts it unchanged, and no tool
name mentions the preview or the quality — the parity rule owes a mirror to
every user-visible EDIT and this edits nothing. The startup parity log is
empty for every instance this run touches, its own two included. The schema
is still the header's `RC_FORMAT_VERSION`, read off `core/include/framejob_core.h` at import and never copied, in
`get_project` and in a saved `project.json`. And the
three view-state calls an agent has (`set_playhead`, `set_selection`,
`set_range`) leave the project JSON byte-identical and the frame at one
instant byte-identical, which is the machine-checkable half of "phase 8 is
view state throughout".

**What no script in this tree can claim about phase 8**, gathered here so it
is not spread through the sections: that the preview is FASTER, or that what
the scaler puts on screen is the Full frame resampled once rather than a
different picture — a render size is not a frame rate and not a pixel; that
the second window shows the same frames as the first (`makePreviewLayer` is
called by a window controller, and nothing here opens one); that ⇧⌘P reaches
it; that the Media tab's search, sort and "unused only" narrow the LIST; that
Reveal in Timeline scrolls to the right clip; and that `MediaUsage.usesMedia`
and `timelineClipsUsing` — the other two spellings of the question section 2
is about — do anything at all, because no tool calls either and section 5's
probe does not ask them. That last one is measured rather than assumed:
deleting the nest walk from `usesMedia` alone SURVIVES this whole file
(79/79), and the run at the bottom of `tools/proof/README.md` says so. The
pane, the menus and those two functions are the offscreen lane's
(`phase8_chrome.py`); the picture and the speed are a person's.

**Media.** `media/A.mov`, `media/B.mov` and `media/C.mov`, all three already
in the tree — three files rather than one because a second `import_media` of
one path is an identity edit and is refused.
`ffmpeg` is needed at proof time, for the ProRes comparison alone, and
`swiftc` for section 0's enum and section 5's whole-app probe (which also
needs `core/target/release/libframejob_core.a` — `make test` builds it).

Run it with the socket of an instance already up; it launches two more of
its own (each on a scratch socket under `$TMPDIR`, `mcp.launch`) and kills
only those two:

    python3 tools/proof/phase8_proof.py <dir>/agent.sock
"""

import hashlib
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import zlib

import mcp as mcp_launch
from mcp import MCP, ToolError, log_beside, remove_scratch, target
import proof_app
import proof_defaults
import swift_build

SOCKET = target(sys.argv)
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
MEDIA = os.path.join(HERE, "media")
ROOT = os.path.dirname(os.path.dirname(HERE))
BINARY = str(proof_app.binary())
SOURCE = os.path.join(ROOT, "app", "Sources", "EditorViewController+PreviewQuality.swift")

SEC = 600_000
CANVAS = (640, 360)

# The whole catalog after phase 8 — phase 6's number, kept by phase 7 and
# kept again here. Phase 8 adds no op and no tool BY DESIGN: none of its
# three features edits anything (`EditorViewController+PreviewQuality.swift`
# argues it for 8a, `MediaReveal.swift` for 8c's selection). The EXACT count
# belongs to the newest phase's script (README) — it is what tells a stale
# binary on the port from the build under test — and phase 9's `set_scope`
# took it, so this is a floor now, as phase 6's and phase 7's are.
TOOLS = 73

# What this build writes. Phase 8 declares "no schema; view state
# throughout", so the number is whatever the tree's header names, read at import: the copy this file carried went stale at road map 8's W1b (8 → 9).
HEADER = os.path.join(ROOT, "core", "include", "framejob_core.h")


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes stale at every bump."""
    with open(HEADER) as f:
        text = f.read()
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", text)
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


VERSION = format_version()

# The app's own defaults key and the build under test's bundle id (Release's
# com.kgalligan.FrameJob, Debug's com.kgalligan.FrameJob.debug). The first is
# read off the source in section 0 as well as spelled here, so a rename shows
# up as a failure rather than as two files quietly disagreeing.
DEFAULTS_KEY = "FrameJobPreviewQuality"
BUNDLE_ID = proof_defaults.bundle_domain(BINARY) or proof_defaults.APP_DOMAIN

# `AgentServer+Render.swift`'s sentence, read the way six earlier scripts
# read it.
FRAME_SENTENCE = re.compile(r"Written to (\S+\.png)\.")

# The startup parity check complaining, which must never appear.
PARITY = "Frame Job: "

failures = []
checks = 0
# Every instance this run LAUNCHED, so the cleanup in `main` can never reach
# a process it did not start (`tools/proof/README.md`'s first rule).
launched = []
# tag -> log path, for section 3's parity read after the instances are gone.
logs = {}


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def section(name, run, *args):
    """One section, isolated. A section that raises scores ONE failure and
    the run goes on — phase 7's shape, for phase 6's reason: a crash is a
    worse detection than a failure, because every later section goes unrun
    and the mutant that caused it reads as weaker than it is."""
    global checks
    print(f"\n{name}")
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — the point is to keep scoring
        checks += 1
        what = f"section {name.split(' ')[0]} ran to the end (raised {error!r})"
        print(f"  FAIL {what}")
        failures.append(what)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def read(path):
    with open(path, "rb") as handle:
        return handle.read()


# ---- PNG, in pure Python -------------------------------------------------
#
# The decoder phases 2, 3, 6 and 7 carry, copied rather than imported for
# their reason: those files are SCRIPTS, importing one would run its main,
# and a proof that measures its own evidence should carry the decoder it
# trusts. It is here so section 1 can say the two identical frames are a
# PICTURE — two identical black canvases would satisfy a byte comparison and
# claim nothing.


def decode_png(path):
    data = read(path)
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
    stride, bpp = width * channels, channels
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
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
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

    def centre(self):
        return self.pixel(self.width // 2, self.height // 2)

    def colours(self):
        """Every distinct pixel value in the frame. One entry means a flat
        canvas, which is what "the picture arrived" has to rule out."""
        seen = set()
        for row in self.rows:
            for x in range(self.width):
                seen.add(row[x * self.channels:(x + 1) * self.channels])
        return seen


# ---- an instance of this build, launched and killed by this script -------


class Instance:
    """One Frame Job launched BY THIS SCRIPT, on a port of its own.

    No proof script in this tree had ever launched the app before phase 8,
    and this one does it for one reason: `PreviewQuality` is read from
    `UserDefaults` at `Playback.init` and there is no tool that sets it, so
    the only way a proof can put a quality into a running Frame Job is the
    argument domain at launch. `-ApplePersistenceIgnoreState` already
    travels that way (CLAUDE.md's launch line); this adds one more argument
    to the same list. The launch is `mcp.launch`, on a scratch socket.

    **It kills only what it started.** `subprocess.Popen`'s own pid, SIGTERM
    then SIGKILL, and nothing in this file ever reads `pgrep` — another
    session's instance is none of its business (`tools/proof/README.md`)."""

    def __init__(self, tag, extra=()):
        self.tag = tag
        self.started = mcp_launch.launch(BINARY, list(extra), env=dict(os.environ), seconds=45)
        self.process = self.started.child
        self.socket = self.started.socket_path
        self.log = self.started.log_path
        logs[tag] = self.log
        launched.append(self)
        if self.started.client is None:
            raise RuntimeError(
                f"the {tag} instance did not bind its socket (rc {self.process.poll()}) — "
                f"{self.log}")
        self.mcp = self.started.client

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            deadline = time.time() + 10
            while time.time() < deadline and self.process.poll() is None:
                time.sleep(0.2)
            if self.process.poll() is None:
                self.process.send_signal(signal.SIGKILL)
                self.process.wait(timeout=10)


def stop_launched():
    for instance in launched:
        try:
            instance.stop()
        except Exception as error:  # noqa: BLE001 — cleanup must not raise
            print(f"  (could not stop the {instance.tag} instance: {error!r})")


def parity_lines(path):
    """The startup parity check's complaints in one log, if any."""
    if not os.path.exists(path):
        return None
    return [line for line in read(path).decode("utf-8", "replace").splitlines()
            if PARITY in line]


# ---- the project under test ----------------------------------------------


class Session:
    """One project, the shape phases 2 to 7 use.

    `<name>-<pid>.framejob`, never a fixed name: a `project` path is matched
    against every open document and no tool closes one, so two earlier runs'
    saved packages would have the app answering for an old one."""

    def __init__(self, mcp, name, canvas=CANVAS):
        self.mcp = mcp
        self.name = name
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.framejob", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.canvas = canvas
        self.op("set_canvas", width=canvas[0], height=canvas[1], background=[0, 0, 0, 1])

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def opw(self, tool, arguments):
        """A call whose ARGUMENTS include one spelled `name` — `nest`'s."""
        arguments = dict(arguments, project=self.path)
        return self.mcp.call_with(tool, arguments)

    def project(self):
        return self.op("get_project")["project"]

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def png(self, t=SEC):
        answer = str(self.op("render_frame", t=int(t)))
        found = FRAME_SENTENCE.search(answer)
        if not found:
            raise RuntimeError(f"render_frame said something else: {answer}")
        return found.group(1)

    def export(self, preset, tag, extension, **kwargs):
        target = os.path.join(WORK, f"{self.name}-{tag}-{os.getpid()}.{extension}")
        if os.path.exists(target):
            os.remove(target)
        return self.op("export", preset=preset, path=target, **kwargs)["path"]

    def save(self):
        self.op("save_project")
        return read(os.path.join(self.path, "project.json")).decode()


def canonical(project):
    """A project JSON as one comparable string."""
    return json.dumps(project, sort_keys=True)


def numeric(value):
    """The same JSON with every number spelled as a float.

    Only for comparing a SAVED `project.json` against what `get_project`
    answered, and it is a fact about the wire rather than about the
    document: `AgentServer.getProject` parses the core's JSON with
    `JSONSerialization` and re-serialises it, which writes `0.0` back out as
    `0`. Two spellings of one number, and a comparison that called them
    different would be measuring Foundation. Booleans first — a `bool` is an
    `int` in Python and `True` must not become `1.0`."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, list):
        return [numeric(item) for item in value]
    if isinstance(value, dict):
        return {key: numeric(item) for key, item in value.items()}
    return value


def users(project, media):
    """(top-level clips, nested clips) that show `media` — the two halves of
    `MediaUsage.clipsUsing`, computed here from `get_project` so the
    fixture's shape is a scored fact and not an assumption."""
    top = [c["id"] for c in project["clips"] if c["source"].get("media") == media]
    nested = [c["id"] for nest in project.get("nests", [])
              for c in nest["clips"] if c["source"].get("media") == media]
    return top, nested


# ---- the fixture both instances build ------------------------------------


def build_fixture(session):
    """The picture section 1 compares, built by the identical call sequence
    in both instances.

    A movie clip UNDER a flat red card: the movie so the comparison crosses a
    decoder and the compositor's texture path rather than only its shape
    drawing, and the card so one pixel of the frame has a value this script
    knows without decoding anything. `A.mov` is `testsrc`, whose picture
    changes every frame, which is what lets section 1 say the frames it
    compares are not three copies of one still."""
    back = session.tracks()[0]
    media = session.op("import_media", path=os.path.join(MEDIA, "A.mov"))["media"]
    session.op("add_clip", track=back, media=media, at=0)
    # `add_track` takes `index` and `name` and nothing else; the `kind` this
    # line used to send was dropped in silence until kpgalligan/framejob#21's
    # gate, which refuses it by name.
    front = session.op("add_track")["new_tracks"][0]
    session.op(
        "add_shape_clip", track=front, at=0, duration=6 * SEC,
        shape={"kind": "rectangle", "width": 200, "height": 100,
               "stroke": None, "fill": [1, 0, 0, 1]})
    # The export range, so the three exports are six frames rather than three
    # hundred: `export` takes a range CHOICE and not a start and a duration,
    # so the in/out range is what bounds them.
    session.op("set_range", start=0, end=int(0.2 * SEC))
    return media


# ---- section 0: the launch mechanism, scored before section 1 leans on it -


PROBE_MAIN = '''import CoreGraphics
import Foundation

// Everything this prints is `PreviewQuality`'s own answer. The enum beside
// this file is EXTRACTED from app/Sources/EditorViewController+PreviewQuality.swift
// at proof time, so a rename or a rewrite shows up as a compile failure
// rather than as a stale copy quietly agreeing with itself.
let quality = PreviewQuality.stored()
let raw = UserDefaults.standard.object(forKey: PreviewQuality.defaultsKey)
var sizes: [String: [Int]] = [:]
for (w, h) in [(1920, 1080), (999, 666), (1001, 667), (640, 360)] {
    for row in PreviewQuality.allCases {
        let size = row.renderSize(for: CGSize(width: w, height: h))
        sizes["\\(w)x\\(h)@\\(row.rawValue)"] = [Int(size.width), Int(size.height)]
    }
}
let out: [String: Any] = [
    "stored": quality.rawValue,
    "title": quality.title,
    "key": PreviewQuality.defaultsKey,
    "raw_type": raw == nil ? "absent" : String(describing: type(of: raw!)),
    "raw_value": raw == nil ? "absent" : String(describing: raw!),
    "sizes": sizes,
]
print(String(data: try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
             encoding: .utf8)!)
'''


def build_probe():
    """The extracted enum, compiled. Answers the binary's path.

    The extraction is deliberately dumb — from the line that declares the
    enum to the first `}` in column 1 — because a clever one could quietly
    take something else. What it took is asserted before it is run."""
    out = os.path.join(WORK, "phase8-probe")
    os.makedirs(out, exist_ok=True)
    text = read(SOURCE).decode()
    found = re.search(r"^enum PreviewQuality[^\n]*\n.*?^\}\n", text, re.M | re.S)
    if not found:
        raise RuntimeError(f"no `enum PreviewQuality {{ … }}` found in {SOURCE}")
    body = found.group(0)
    for wanted in ("static func stored()", "func renderSize(for canvas: CGSize)",
                   f'"{DEFAULTS_KEY}"'):
        if wanted not in body:
            raise RuntimeError(f"the extracted enum is missing `{wanted}` — extraction is wrong")
    # The two imports the original file gets from `import AppKit` and
    # `import AVFoundation`, and nothing else.
    with open(os.path.join(out, "PreviewQuality.swift"), "w") as handle:
        handle.write("import CoreGraphics\nimport Foundation\n\n" + body)
    with open(os.path.join(out, "main.swift"), "w") as handle:
        handle.write(PROBE_MAIN)
    binary = os.path.join(out, "previewprobe")
    build = subprocess.run(
        ["swiftc", "-O", os.path.join(out, "PreviewQuality.swift"),
         os.path.join(out, "main.swift"), "-o", binary],
        capture_output=True, text=True)
    if build.returncode != 0:
        raise RuntimeError(f"the probe would not build: {build.stderr.strip()[:400]}")
    return binary


def run_probe(binary, *arguments):
    answer = subprocess.run([binary, *arguments], capture_output=True, text=True, check=True)
    return json.loads(answer.stdout)


def instrument_part():
    check(os.path.exists(BINARY), f"the build under test is at {BINARY}")

    binary = build_probe()
    check(True, "`enum PreviewQuality` extracts from the app's own source and compiles — "
                "the instrument section 1's two launches rest on")

    bare = run_probe(binary)
    check(bare["key"] == DEFAULTS_KEY,
          f"the defaults key the app reads is `{bare['key']}`, which is what this script "
          "launches with")
    check(bare["raw_value"] == "absent" and bare["stored"] == 0 and bare["title"] == "Full",
          f"with no launch argument the key is absent and `stored()` is Full "
          f"({bare['title']}) — an absent key is the only value that cannot surprise "
          "somebody who does not know the setting exists")

    quarter = run_probe(binary, f"-{DEFAULTS_KEY}", "2")
    check(quarter["stored"] == 2 and quarter["title"] == "Quarter",
          f"…and with `-{DEFAULTS_KEY} 2` on the command line `stored()` is Quarter "
          f"({quarter['title']}) — the whole mechanism section 1 uses to put a quality "
          "into a running app that has no tool for it")
    check("String" in quarter["raw_type"] and quarter["raw_value"] == "2",
          f"the argument domain delivers it as a {quarter['raw_type']}, not a number "
          "— which is why `stored()` asks `object(forKey:) != nil` and then "
          "`integer(forKey:)`: an `object(forKey:) as? Int` would read Full for every "
          "launch argument ever passed")

    silly = run_probe(binary, f"-{DEFAULTS_KEY}", "7")
    check(silly["stored"] == 0,
          f"a stored value outside the three cases reads Full ({silly['title']}), which is "
          "what a downgrade after a future fourth row would leave behind")

    # The aspect rule, at the three canvases its own doc names plus this
    # script's. It is here rather than for its own sake: 640 × 360 at Quarter
    # is 160 × 90, and that is the size section 1's frames come back at on a
    # build where the setting reaches the shared builder.
    sizes = bare["sizes"]
    check(sizes["1920x1080@1"] == [960, 540] and sizes["1920x1080@2"] == [480, 270],
          f"a canvas the divisor divides gives exactly the fraction the row names "
          f"(1920×1080 → {sizes['1920x1080@1']} at Half, {sizes['1920x1080@2']} at Quarter)")
    check(sizes["999x666@1"] == [501, 334],
          f"one it does not rounds toward a COARSER preview and stays exactly 3∶2 "
          f"(999×666 → {sizes['999x666@1']} at Half)")
    check(sizes["1001x667@1"] == [1001, 667] and sizes["1001x667@2"] == [1001, 667],
          "a coprime canvas cannot be divided proportionally at all, so every row "
          f"degrades to FULL ({sizes['1001x667@2']}) rather than letterboxing inside the "
          "player layer and moving every drag handle in the frame")
    check(sizes["640x360@2"] == [160, 90],
          f"…and this script's own canvas at Quarter is {sizes['640x360@2']} — the size a "
          "frame comes back at when the setting reaches the shared builder, which is "
          "mutant 1")

    # The precondition for calling the key-absent instance "Full": nothing in
    # the app's persisted domain. Asserted rather than assumed — a machine
    # where somebody had picked Quarter from the menu would run section 1
    # with both instances at Quarter and every byte comparison would pass
    # while claiming nothing.
    stored = subprocess.run(
        ["defaults", "read", BUNDLE_ID, DEFAULTS_KEY], capture_output=True, text=True)
    persisted = stored.stdout.strip() if stored.returncode == 0 else None
    check(persisted is None or persisted == "0",
          f"the app's persisted domain holds no {DEFAULTS_KEY} (got {persisted!r}), so "
          "launching one instance without the argument genuinely launches it at Full")


# ---- section 1: two instances, two qualities, one set of bytes ------------


def isolation_part(mcp):
    full = Instance("full")
    quarter = Instance("quarter", extra=[f"-{DEFAULTS_KEY}", "2"])
    check(full.socket != quarter.socket,
          f"two instances of the SAME binary are up, at {full.socket} and {quarter.socket} — "
          "one with the preview-quality key absent, one launched at Quarter")
    for tag, instance in (("full", full), ("quarter", quarter)):
        names = instance.mcp.tools()
        check(len(names) >= TOOLS,
              f"the {tag} instance serves {len(names)} tools, phase 8's {TOOLS} or more")

    a = Session(full.mcp, "phase8-full")
    b = Session(quarter.mcp, "phase8-quarter")
    build_fixture(a)
    build_fixture(b)

    # The two documents FIRST. Every byte claim below compares two pictures
    # of two projects, and if the projects differed the comparison would be
    # measuring the fixture rather than the setting.
    check(canonical(a.project()) == canonical(b.project()),
          "the two instances hold the same document, project JSON for project JSON — "
          "so anything that differs below belongs to the process and not to the fixture")

    # Three instants, and the picture at each is scored before it is
    # compared: two identical black canvases would satisfy a byte comparison
    # and claim nothing at all.
    instants = [0.2 * SEC, 1.0 * SEC, 4.5 * SEC]
    frames_a = [a.png(t) for t in instants]
    frames_b = [b.png(t) for t in instants]
    first = Frame(frames_a[0])
    check((first.width, first.height) == CANVAS,
          f"the Full instance renders the canvas at {first.width}×{first.height}")
    check(first.centre()[:3] == (255, 0, 0),
          f"…with the red card at its centre ({first.centre()}), so the picture arrived")
    check(len(first.colours()) > 100,
          f"…and {len(first.colours())} distinct colours in it, so the frame is a PICTURE "
          "and not a flat canvas two builds could agree about by drawing nothing")
    check(len({read(p) for p in frames_a}) == 3,
          "the three instants are three DIFFERENT frames, so comparing at one instant "
          "compares a picture that moves")

    for t, pa, pb in zip(instants, frames_a, frames_b):
        check(read(pa) == read(pb),
              f"render_frame at {t / SEC:g} s is byte-identical between a Full instance and "
              f"a Quarter one ({digest(pa)})")
    later = Frame(frames_b[0])
    check((later.width, later.height) == CANVAS,
          f"…and the Quarter instance's frame measures {later.width}×{later.height}, the "
          "canvas: a setting that reached the shared builder would render it at the "
          "160×90 section 0 works out for this canvas at Quarter")

    # The two writers, both of them. `apng` and `gif` go through
    # `ExporterImageSequence.swift` (no clock in the file, so a byte
    # comparison is legitimate); `prores_422` goes through `ExportWriter`,
    # and a .mov carries a creation time at one-second resolution — phase 7
    # measured six differing header bytes between two exports of one
    # unchanged project — so that one is compared on DECODED PIXELS.
    written = {}
    for preset, extension in (("apng", "png"), ("gif", "gif")):
        fa = a.export(preset, "iso", extension, range="in_out")
        fb = b.export(preset, "iso", extension, range="in_out")
        written[preset] = fa
        bytes_a, bytes_b = read(fa), read(fb)
        check(len(bytes_a) > 1000, f"the {preset} export is a real file ({len(bytes_a)} bytes)")
        check(bytes_a == bytes_b,
              f"a {preset} export is byte-identical between the two qualities "
              f"({digest(fa)}, {len(bytes_a)} bytes)")
    apng = read(written["apng"])
    check(apng[:8] == b"\x89PNG\r\n\x1a\n" and b"acTL" in apng,
          "…and the apng really is an animated PNG (acTL), not one still frame the two "
          "sides could agree about trivially")

    mov_a = a.export("prores_422", "iso", "mov", range="in_out")
    mov_b = b.export("prores_422", "iso", "mov", range="in_out")
    pixels_a, pixels_b = decoded_frames(mov_a), decoded_frames(mov_b)
    check(len(pixels_a) == CANVAS[0] * CANVAS[1] * 4 * 3,
          f"the ProRes export decodes to three whole {CANVAS[0]}×{CANVAS[1]} RGBA frames "
          f"({len(pixels_a)} bytes)")
    check(pixels_a == pixels_b,
          "…and the ExportWriter limb agrees pixel for pixel across the two qualities "
          f"({hashlib.sha256(pixels_a).hexdigest()[:16]}) — compared decoded rather than "
          "byte for byte because a .mov carries a clock")

    for tag in ("full", "quarter"):
        complaints = parity_lines(logs[tag])
        check(complaints == [],
              f"the {tag} instance's startup parity log is empty ({complaints})")


def decoded_frames(path, count=3):
    """The first `count` frames of a written movie, as straight 8-bit RGBA.

    The one place this script needs ffmpeg. `-vframes` rather than the whole
    file: three frames is enough to say two encoders were handed the same
    pictures, and a whole ProRes decode is 13 MB a frame."""
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vframes", str(count), "-f", "rawvideo",
         "-pix_fmt", "rgba", "-"],
        capture_output=True, check=True).stdout


# ---- section 2: "is this media used" now walks the nests -----------------


def usage_part(mcp):
    s = Session(mcp, "phase8-usage")
    back = s.tracks()[0]
    front = s.op("add_track")["new_tracks"][0]  # no `kind`: see line 542

    # (a) media used ONLY inside a nest — the case both old spellings missed.
    hidden = s.op("import_media", path=os.path.join(MEDIA, "A.mov"))["media"]
    inside = s.op("add_clip", track=back, media=hidden, at=0)["new_clips"][0]
    group = s.opw("nest", {"clips": [inside], "name": "Group"})["new_clips"][0]
    top, nested = users(s.project(), hidden)
    check(top == [] and len(nested) == 1,
          f"the fixture is right: A.mov has {len(top)} top-level users and {len(nested)} "
          "inside a nest, which is the shape a Swift guard filtering snapshot.clips "
          "reads as unused")

    refusal = s.error("remove_media", media=hidden)
    check(refusal is not None, "remove_media refuses it without with_clips")
    check(refusal is not None
          and refusal.endswith(
              f"was refused at remove_media: media {hidden} is still used by clip "
              f"{inside}; pass with_clips: true to remove the media and its clips"),
          f"…and the refusal NAMES the clip inside the nest: {refusal!r}")
    check(refusal is not None and "made no change" not in refusal,
          "…and it is NOT an identity's \"made no change\", which is what a core "
          "counting only the timeline's clips would make of this")
    check(refusal is not None and "with_clips: true" in refusal,
          "…and it says how to go on")

    before = canonical(s.project())
    s.op("remove_media", media=hidden, with_clips=True)
    project = s.project()
    check(hidden not in [m["id"] for m in project["media"]],
          "with_clips: true removes the media entry")
    top, nested = users(project, hidden)
    check(top == [] and nested == [],
          "…and the clip INSIDE the nest with it")
    check(group in [c["id"] for c in project["clips"]],
          "…while the nest CLIP itself stays on the timeline: it is not a user of the "
          "media, and taking it out would throw away everything else in the group over "
          "one file")
    s.mcp.call("undo", project=s.path)
    check(canonical(s.project()) == before,
          "…and ONE undo puts the whole project JSON back")

    # (b) the both-levels count. This is the check with teeth: a build
    # counting the top level alone still REFUSES here, with the wrong number
    # in the sentence.
    shared = s.op("import_media", path=os.path.join(MEDIA, "C.mov"))["media"]
    visible = s.op("add_clip", track=front, media=shared, at=0)["new_clips"][0]
    third = s.op("add_track")["new_tracks"][0]
    buried = s.op("add_clip", track=third, media=shared, at=0)["new_clips"][0]
    s.opw("nest", {"clips": [buried], "name": "Second"})
    top, nested = users(s.project(), shared)
    check(len(top) == 1 and len(nested) == 1,
          f"C.mov is used once at the top level and once inside a nest ({top}, {nested})")
    refusal = s.error("remove_media", media=shared)
    check(refusal is not None
          and refusal.endswith(
              f"was refused at remove_media: media {shared} is still used by clips "
              f"{visible} and {buried}; pass with_clips: true to remove the media and "
              "its clips"),
          f"…and the refusal names BOTH clips, the timeline's first and the nest's "
          f"after it: {refusal!r} — a count of the top level alone would name one")

    # (c) the contrast: top-level usage behaves as it always did. A DIFFERENT
    # file, because a second import of one path is an identity edit and is
    # refused — one media entry per file, which is also why (d) below can
    # only re-import what (c) has just removed.
    fourth = s.op("add_track")["new_tracks"][0]
    plain = s.op("import_media", path=os.path.join(MEDIA, "B.mov"))["media"]
    check(plain != shared, "B.mov is a media entry of its own")
    alone = s.op("add_clip", track=fourth, media=plain, at=0)["new_clips"][0]
    refusal = s.error("remove_media", media=plain)
    check(refusal is not None
          and refusal.endswith(
              f"was refused at remove_media: media {plain} is still used by clip "
              f"{alone}; pass with_clips: true to remove the media and its clips"),
          f"media used only at the TOP level refuses in the same words: {refusal!r}")
    s.op("remove_media", media=plain, with_clips=True)
    project = s.project()
    check(plain not in [m["id"] for m in project["media"]]
          and alone not in [c["id"] for c in project["clips"]],
          "…and with_clips takes the entry and its clip")

    # (d) unused media, and a media id that names nothing. B.mov again,
    # which (c) has just taken out of this project.
    spare = s.op("import_media", path=os.path.join(MEDIA, "B.mov"))["media"]
    top, nested = users(s.project(), spare)
    check(top == [] and nested == [], "a freshly imported file is used by nothing")
    s.op("remove_media", media=spare)
    check(spare not in [m["id"] for m in s.project()["media"]],
          "…so remove_media takes it with no with_clips at all")
    missing = s.error("remove_media", media=99999)
    check(missing is not None and "99999" in missing,
          f"…and an id that names no media is refused by name: {missing!r}")


# ---- section 3: the catalog, and the setting's deliberate absence --------


def catalog_part(mcp):
    names = mcp.tools()
    check(len(names) >= TOOLS,
          f"the catalog holds phase 8's {TOOLS} tools or more (got {len(names)}) — phase 8 "
          "adds no op and no tool, so this was phase 6's number for the third phase "
          "running, and phase 9's set_scope is what turned it into a floor")
    check(not [n for n in names if "preview" in n or "quality" in n],
          "and no tool mentions the preview or the quality: the parity rule owes a "
          "mirror to every user-visible EDIT (spec §7.9) and phase 8a edits nothing — "
          "there is nothing an agent could observe if it did")
    for absent in ("set_preview_quality", "open_preview_window", "search_media"):
        check(absent not in names, f"`{absent}` is not a tool, and must not become one "
                                   "so that a proof can exist")
    for tag in ("full", "quarter"):
        complaints = parity_lines(logs.get(tag, ""))
        check(complaints == [],
              f"the {tag} instance this script launched left an empty parity log")
    house = log_beside(SOCKET)
    complaints = parity_lines(house)
    check(complaints in ([], None),
          f"…and so did the instance at {SOCKET}, if it logged where the README says "
          f"({house}: {'no such file' if complaints is None else complaints})")


# ---- section 4: nothing else moved --------------------------------------


def unchanged_part(mcp):
    s = Session(mcp, "phase8-unchanged")
    media = build_fixture(s)
    project = s.project()
    check(project["version"] == VERSION,
          f"the project this build holds is schema version {project['version']}, still "
          f"{VERSION}, the header's RC_FORMAT_VERSION: phase 8 is view state throughout "
          f"and bumps nothing")

    before = canonical(project)
    frame_before = read(s.png(2 * SEC))
    clips = [c["id"] for c in project["clips"]]
    s.op("set_playhead", t=3 * SEC)
    s.op("set_selection", clips=clips[:1])
    s.op("set_range", start=SEC, end=2 * SEC)
    after = s.op("get_project")
    check(canonical(after["project"]) == before,
          "the three view-state calls an agent has — playhead, selection, in/out range — "
          "leave the project JSON byte-identical, which is the machine-checkable half of "
          "\"phase 8 is view state throughout\"")
    check(after["playhead"] == 3 * SEC and after["selection"] == clips[:1]
          and after["in_out_range"] == {"start": SEC, "end": 2 * SEC},
          "…and they did take effect, so that identity is not three calls that did "
          f"nothing ({after['playhead']}, {after['selection']}, {after['in_out_range']})")
    check(read(s.png(2 * SEC)) == frame_before,
          "…and the frame at one instant is byte-identical across them")

    text = s.save()
    check(re.search(r'"version"\s*:\s*(\d+)', text).group(1) == str(VERSION),
          f"the saved project.json is version {VERSION}, the header's RC_FORMAT_VERSION")
    reopened = json.loads(text)
    check(canonical(numeric(reopened)) == canonical(numeric(json.loads(before))),
          "…and what it wrote is the document it was holding, key for key — compared with "
          "every number spelled as a float, because the MCP path re-serialises the core's "
          "JSON through JSONSerialization and writes 0.0 back out as 0")
    check(media in [m["id"] for m in reopened["media"]],
          "…including the media entry, which is what section 2's question is asked about")



# ---- section 5: the PLAYER's own composition, through a whole-app probe ---
#
# The claim section 1 cannot make, made the way this tree already makes app
# claims no running app exposes: a probe compiled against `app/Sources`
# (CLAUDE.md's "Seeing the chrome" — `phase5_chrome.py` compiles one out of
# `Loudness.swift`, `phase6_chrome.py` one out of the whole of `app/Sources`,
# and section 0 above one out of a single enum). Nothing over MCP reaches the
# player: `render_frame` builds its own composition and `export` builds two
# more, and none of the three is the item the `AVPlayerLayer` is showing. So
# the size the setting is FOR — the render size of the composition on the
# player's current item — is unobservable over the wire, and a script that
# stopped at section 1 would report a perfect score against a build with the
# feature deleted outright. (It was measured: `previewComposition` returning
# its argument unconditionally scored 65/65 before this section existed.)
#
# This is the app's own code — `ProjectDocument.read`, `EditorViewController`,
# `Playback`, `CompositionBuilder` — in a second process, which is the same
# standard the offscreen harness sets and is stated rather than implied: it is
# NOT the shipped binary, and what it proves is that these SOURCES put the
# smaller size on the player.


PLAYER_PROBE_MAIN = '''import AVFoundation
import AppKit

// Compiled against the whole of `app/Sources` by `phase8_proof.py`, in the
// swiftc line `tools/proof/harness/build.sh` uses. Opens a package the way
// the harness does, puts an `EditorViewController` in a window, spins the
// runloop until the PLAYER has an item, and reports the render size of the
// composition that item is carrying — `Playback.previewComposition`'s answer,
// which no tool can reach.
//
//   playerprobe <package> <tag to switch to at runtime, or -> [-FrameJobPreviewQuality N]
//
// The positional arguments come FIRST because the launch argument stays in
// `CommandLine.arguments` as well as reaching the argument domain.
let arguments = CommandLine.arguments
let projectURL = URL(fileURLWithPath: arguments[1])
let switchTo = Int(arguments[2])

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let document = ProjectDocument()
do {
    try document.read(from: projectURL, ofType: ProjectDocument.projectTypeIdentifier)
    document.fileURL = projectURL
} catch {
    FileHandle.standardError.write("read failed: \\(error)\\n".data(using: .utf8)!)
    exit(1)
}
let controller = EditorViewController(document: document)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1440, height: 862),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)

func playerRenderSize() -> CGSize? {
    controller.playback.playerLayer.player?.currentItem?.videoComposition?.renderSize
}
func settle(_ turns: Int, until ready: () -> Bool) {
    for _ in 0..<turns {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        if ready() { return }
    }
}

settle(200) { playerRenderSize() != nil }
let first = playerRenderSize()

// The MENU action, driven exactly as a click does: the sender's tag is the
// row. `setPreviewQuality(_:)` re-assigns the composition on the LIVE item,
// which is a different path from the one `finishRebuild` takes.
var second: CGSize?
if let tag = switchTo {
    let item = NSMenuItem(
        title: "", action: #selector(EditorViewController.setPreviewQuality(_:)),
        keyEquivalent: "")
    item.tag = tag
    controller.setPreviewQuality(item)
    settle(60) { playerRenderSize() != first }
    second = playerRenderSize()
}

// The validator's checkmark, one row at a time — the other half of the menu.
var marks: [Int] = []
for tag in 0..<3 {
    let item = NSMenuItem(
        title: "", action: #selector(EditorViewController.setPreviewQuality(_:)),
        keyEquivalent: "")
    item.tag = tag
    let enabled = controller.validatePreviewQualityAction(
        #selector(EditorViewController.setPreviewQuality(_:)), item: item)
    marks.append(item.state == .on ? 1 : 0)
    if enabled != true { marks[marks.count - 1] = -1 }
}

let canvas = document.project.snapshot.canvas
let out: [String: Any] = [
    "quality": controller.playback.previewQuality.rawValue,
    "title": controller.playback.previewQuality.title,
    "canvas": [canvas.width, canvas.height],
    "player": first.map { [Int($0.width), Int($0.height)] } ?? [-1, -1],
    "after": second.map { [Int($0.width), Int($0.height)] } ?? [-1, -1],
    "after_quality": controller.playback.previewQuality.rawValue,
    "marks": marks,
]
print(String(data: try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
             encoding: .utf8)!)
exit(0)
'''


def build_player_probe():
    """The whole-app probe, compiled through `swift_build.build` with a
    `main.swift` of this script's own — the shape `phase6_chrome.py`
    established for the checks a render cannot answer. Reused when every
    input is byte-identical to a cached build's, so a re-run costs nothing
    and a stale instrument is impossible."""
    out = os.path.join(WORK, "phase8-player")
    os.makedirs(out, exist_ok=True)
    binary = os.path.join(out, "playerprobe")
    main = os.path.join(out, "main.swift")
    library = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(library):
        raise RuntimeError(f"{library} is missing — `make test` builds it")
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    with open(main, "w") as handle:
        handle.write(PLAYER_PROBE_MAIN)
    try:
        swift_build.build(sources=[*sources, main], output=binary)
    except swift_build.SwiftBuildFailed as error:
        raise RuntimeError("the player probe would not build: "
                           + "\n".join(error.diagnostics).strip()[-600:]) from None
    return binary


def run_player_probe(binary, package, quality=None, switch_to=None):
    arguments = [binary, package, "-" if switch_to is None else str(switch_to)]
    if quality is not None:
        arguments += [f"-{DEFAULTS_KEY}", str(quality)]
    answer = subprocess.run(arguments, capture_output=True, text=True)
    if answer.returncode != 0:
        raise RuntimeError(f"the player probe failed: {answer.stderr.strip()[-400:]}")
    return json.loads(answer.stdout)


def player_part(mcp):
    s = Session(mcp, "phase8-player")
    build_fixture(s)
    s.save()
    package = s.path

    binary = build_player_probe()
    check(True, "a probe compiled against the WHOLE of app/Sources builds — the only "
                "instrument that can see the player, since no tool reaches it")

    full = run_player_probe(binary, package)
    half = run_player_probe(binary, package, quality=1)
    quarter = run_player_probe(binary, package, quality=2)

    canvas = tuple(full["canvas"])
    check(canvas == CANVAS,
          f"the probe opened this script's own package and reads its canvas as {canvas}")
    check([full["quality"], half["quality"], quarter["quality"]] == [0, 1, 2],
          "the shipping `Playback` reads the launch argument: three processes of one "
          f"build report Full, {half['title']} and {quarter['title']} "
          f"({[full['title'], half['title'], quarter['title']]})")

    check(tuple(full["player"]) == CANVAS,
          f"at Full the player's composition renders the whole canvas ({full['player']}) — "
          "`previewComposition` returns the builder's own object, so a default preview is "
          "what this file built before the setting existed")
    check(tuple(half["player"]) == (320, 180),
          f"at Half it renders {half['player']} — half of 640×360 in each direction, which "
          "is the setting DOING something and is what section 1 cannot see")
    check(tuple(quarter["player"]) == (160, 90),
          f"at Quarter it renders {quarter['player']}, a sixteenth of the fragment work — "
          "the number section 0 derives from the aspect rule, now read off a real "
          "AVPlayerItem")

    for row in (full, half, quarter):
        width, height = row["player"]
        check(width * canvas[1] == height * canvas[0],
              f"…and {row['title']}'s {row['player']} carries the canvas's aspect EXACTLY "
              f"({width}×{canvas[1]} = {height}×{canvas[0]}), which is what stops "
              "`AVPlayerLayer.videoRect` letterboxing and moving every drag handle")

    # The two halves of the isolation claim, side by side rather than a
    # section apart: the same package, at the same quality, seen through the
    # player and through `render_frame`.
    rendered = Frame(s.png(SEC))
    check((rendered.width, rendered.height) == CANVAS
          and tuple(quarter["player"]) != CANVAS,
          f"the two halves together: at Quarter the PLAYER renders {quarter['player']} "
          f"while render_frame of the same package answers {rendered.width}×"
          f"{rendered.height} — the setting reaches one and not the other, which is the "
          "whole design")

    # The menu action on a LIVE item, which is a different limb from the one
    # `finishRebuild` takes: `AVPlayerItem.videoComposition` is a COPY
    # property, so mutating the retained composition in place would change
    # nothing and only a re-assignment shows.
    down = run_player_probe(binary, package, switch_to=2)
    check(tuple(down["player"]) == CANVAS and tuple(down["after"]) == (160, 90),
          f"View ▸ Preview Quality ▸ Quarter on a running editor takes the player from "
          f"{down['player']} to {down['after']} with no rebuild — the menu action's own "
          "path, and the one an in-place mutation of the composition would leave at Full")
    up = run_player_probe(binary, package, quality=2, switch_to=0)
    check(tuple(up["player"]) == (160, 90) and tuple(up["after"]) == CANVAS,
          f"…and back: {up['player']} → {up['after']}, so the scale is taken from the "
          "PRISTINE canvas size every time and never from a size already scaled")
    check(down["after_quality"] == 2 and up["after_quality"] == 0,
          "…and the setting the object holds moved with it, so the two sizes are not one "
          "quality answering twice")

    check(full["marks"] == [1, 0, 0] and half["marks"] == [0, 1, 0]
          and quarter["marks"] == [0, 0, 1],
          f"the validator checkmarks EXACTLY the row the player is at "
          f"({full['marks']}, {half['marks']}, {quarter['marks']}) and enables all three, "
          "which is the menu's other half")


def main():
    for binary in ("ffmpeg",):
        if not shutil.which(binary):
            print(f"{binary} is needed: section 1 compares the ProRes limb on decoded "
                  "pixels, because a .mov carries a clock.")
            return 2
    if not shutil.which("swiftc"):
        print("swiftc is needed: section 0 compiles the app's own PreviewQuality enum.")
        return 2
    for name in ("A.mov", "B.mov", "C.mov"):
        if not os.path.exists(os.path.join(MEDIA, name)):
            print(f"tools/proof/media/{name} is missing — tools/proof/README.md has the "
                  "ffmpeg line that writes it.")
            return 2
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(SOCKET)
    print(f"phase 8 — Viewing, against {SOCKET}")

    try:
        section("0 — the launch mechanism, scored before section 1 leans on it",
                instrument_part)
        section("1 — two instances, two preview qualities, one set of bytes",
                isolation_part, mcp)
        section("2 — remove_media: \"is this media used\" now walks the nests",
                usage_part, mcp)
        section("3 — the catalog, and the setting's deliberate absence from it",
                catalog_part, mcp)
        section("4 — nothing else moved", unchanged_part, mcp)
        section("5 — the PLAYER's own composition, through a whole-app probe",
                player_part, mcp)
    finally:
        stop_launched()
        for instance in launched:
            remove_scratch(instance.socket)

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
