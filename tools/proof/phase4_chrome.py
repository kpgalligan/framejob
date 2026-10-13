#!/usr/bin/env python3
"""Road map 2, phase 4 (Words) — the CHROME half of the proof.

Phase 4 is three features and the harness can photograph exactly one of
them. **Nothing about the picture is claimed here.** The preview well
renders BLACK offscreen — a Metal layer has no drawable — so the reveal
itself (the typewriter's prefix, the word fade's per-word alpha, the line
rise's per-line offset) cannot be seen by this program at all, and auto
captions are a transcription, not a picture. Those belong to the proofs that
drive a running app over MCP (`tools/proof/phase4_proof.py`, and
`transcribe` for the captions). What is left is the chrome, and for phase 4 that is
one thing:

    4c  the TextPane "Animation" section — that it EXISTS in the Clip tab
        under its own id, that it is exactly three rows tall, that its
        summary and each of its three rows read the data they are bound to,
        and that a text animation changes NOTHING else in the window.

Every claim is a BYTE comparison of two PNGs the offscreen harness wrote
(`tools/proof/harness/`, CLAUDE.md's "Seeing the chrome"), then a
measurement of WHERE the changed pixels landed against rectangles derived
from the app's own layout constants. `phase3_chrome.py` is the model and
this file follows it line for line — through section 7.

**Section 8 is not a picture at all**, and it is here because the HARNESS is
here. It is the one binary in the tree that links `app/Sources` outside the
app, so it is the one place that hands 4a's cue builder — `CaptionCues`,
whose four rules (at most 2 lines, at most 42 characters a line, at most 6 s
a cue, at least one frame of gap between cues) shape every Subtitles
caption — an ARBITRARY word list. The app reaches it through `CaptionPages`
once a transcription has produced words (`SpeechTranscriber`, which asks for
no grant, spec §11 W-8, or the cloud engine), and `transcribe` reaches it
over MCP, but only with the words a transcription heard. The rules
themselves are arithmetic over a word list with no `Speech` in them, so the
harness grew a second mode that runs the builder over a word list from a
file (`harness cues <words.json> <out.json>`, added, not rearranged — every
render argument keeps the position `phase2_chrome.py` and `phase3_chrome.py`
depend on), and section 8 asserts the four rules over its answer, each at
its BOUNDARY rather than in the middle: a word longer than a line, a list of
one word, a pause longer than a cue may be, two words at the same instant, a
line of exactly 42 characters and a cue of exactly 6 s (both `<=`), and the
one frame of gap surviving the snap to the frame grid at two frame rates and
five offsets from it.

**The chrome half needs no new harness argument.** Phase 3 added
`expandSections` so a section built `defaultExpanded: false` could be
photographed with its rows showing, and `text.animation` is built that way
too, so the instrument is already here; the ONE thing sections 1–7 rely on
that a package cannot carry is that pin, and that it is an existing argument
is worth saying because a proof that quietly grows its own instrument is not
a proof. Section 8's mode is the counter-case and is declared as one: it
photographs nothing, changes no render argument, and exists because the code
it calls has no other caller a script can reach.

The packages are written BY HAND (a `.framejob` is a directory holding
`project.json`, spec §5.2) around one clip, so nothing loads
asynchronously and every render is deterministic — no media at all:

    text-v4     version 4, no `animation` key at all (the schema default)
    text-none   version 5, `"animation": null`
    text-type   typewriter, in 1 s, out 0 — the core's own default
    text-word   word_fade, in 1 s, out 0
    text-line   line_rise, in 1 s, out 0
    text-in2    typewriter, in 2 s, out 0   (the In row alone moves)
    text-out    typewriter, in 1 s, out 0.5 (the Out row alone moves)
    shape-clip  one SHAPE clip — the kind that must not get the section

THE WINDOW IS 1440 x 1100, and the height is measured rather than picked.
A text clip's Clip tab carries sixteen sections and Animation is the
eighth, so at the 862 pt window phase 2 uses it is BELOW THE FOLD:
measured, the closed-vs-open, kind and value comparisons all come back at
zero changed pixels, which is a score of checks that cannot fail. At 1300
and above the section stack regains slack and opening a section moves the
sections ABOVE it too (measured: full-width changed blocks 300 pt above
the header), so the downward-shift arithmetic stops being pure. At 1100
the whole section is on screen AND the stack still overflows, so opening
it can only push what is under it down — which is what section 3 measures.
The shape package is the one exception and gets its own window; the note
on `SHAPE_HEIGHT` says why, and it is worth reading before changing either
number, because the reason is a flakiness that is still in the app.

Every check here was MUTATION-TESTED against deliberately broken builds of
the same sources, each compiled outside the repository so the tree was
never touched. A check nothing can break is not a check, and each number
below names the ones that broke.

Sections 1–7, the CHROME's forty, against five: dropping
`animationSection()` from `ClipPane` (17/40), giving the section another id
(30/40), pointing the header summary at `out` instead of `in` (38/40),
swapping the In and Out rows (37/40), and making the two value rows ignore
`enabled: on` (37/40). Those five are edits to `ClipPane` and `TextPane`
and reach no cue at all, so the denominator is the chrome's own forty and
section 8 is not in it — the fractions were measured before section 8
existed and are left as they were measured.

Section 8, the cue builder's nineteen, against five mutations of
`CaptionLayout.swift`: the 42-character rule written `<` instead of `<=`
(18/19 — ONLY the exactly-42 boundary check, which is the whole argument
for testing a rule at its edge rather than in the middle), the six-second
test widened to never fire (15/19), the frame of gap dropped so cues merely
abut (15/19), a third line allowed (16/19 — the line sweep and both gap
fixtures, whose packing changes with it), and an over-long word truncated
to 42 characters (17/19 — the whole-word check and word conservation).

Run it from anywhere; it builds the harness if it is stale:

    python3 tools/proof/phase4_chrome.py

The last line is `<n>/<n> checks passed` and the exit status is non-zero if
any failed. The PNGs stay in `tools/proof/work/chrome4/` (with a crop of
the Animation section out of every text render for an eye check, and
section 8's word lists and the cues built from them beside them), and the
changed-pixel clusters of every comparison are printed as bounding boxes so
a reader can see where a diff landed without opening anything.
"""

import json
import os
import re
import struct
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work")
CHROME = os.path.join(WORK, "chrome4")
BUILD = os.path.join(HERE, "harness", "build.sh")

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants. Each number names the
# Swift constant it mirrors; the PNG's width / WIDTH is the backing scale
# (2 on a Retina Mac).

WIDTH = 1440
HEIGHT = 1100            # see the header — measured, not picked
# The SHAPE clip's window, and it is a different number for a reason worth
# knowing before touching either. An inspector whose sections do not fill
# their scroll view has SLACK to hand out, and a section that takes it is
# bistable ACROSS PROCESSES: measured, one render in twenty of the shape
# package at 1100 came back with everything below y 330 pt sitting 23 pt
# higher, and no amount of settling fixes that — the harness waits for a
# layout that has stopped moving, and both of these have. A text clip's
# sixteen sections overflow at 1100 and a shape clip's twelve do not, so the
# shape pair is rendered at the height where its own stack overflows too.
# Section 7 measures that rather than trusting it: at 862 and at 900 the
# shape clip's inspector draws the same bytes, which is what "nothing
# stretches" looks like. Over forty renders at 862 have come back
# byte-identical; the bistability is the app's, not this script's, and it
# is the reason a proof should never rest a byte comparison on a pane with
# room to spare.
SHAPE_HEIGHT = 862
SHAPE_TALLER = 900       # the second height section 7 compares against

TOOLBAR = 44             # DS.toolbarHeight
TAB = 32                 # DS.tabHeight — the inspector's tab strip
INSPECTOR_W = 304        # DS.panelWidth = EditorViewController.defaultInspectorWidth
TIMELINE_H = 300         # EditorViewController.defaultTimelineHeight
SCROLLER_W = 16          # AppKit's legacy scroller, pinned by the harness

SECTION_HEADER_H = 28    # InspectorMetrics.headerHeight
CONTROL_H = 22           # DS.controlHeight — one row
ROW_SPACING = 7          # InspectorMetrics.rowSpacing
CONTENT_TOP = 2          # InspectorSection's content edgeInsets.top
CONTENT_BOTTOM = 8       # …and .bottom
ROW_PITCH = CONTROL_H + ROW_SPACING          # 29

# The section's three rows, in order (`TextPane.animationSection`).
ANIMATION_ROWS = ["Reveal", "In", "Out"]
# What the section adds when it opens: the content stack's two insets, three
# rows and the two spacings between them. THIS number is the "exactly three
# rows tall" claim, and section 3 solves for it out of the pixels.
SECTION_BODY = (
    CONTENT_TOP + len(ANIMATION_ROWS) * CONTROL_H
    + (len(ANIMATION_ROWS) - 1) * ROW_SPACING + CONTENT_BOTTOM)          # 90
SECTION_OPEN_H = SECTION_HEADER_H + SECTION_BODY                         # 118

INSPECTOR_X = WIDTH - INSPECTOR_W                        # 1136
INSPECTOR_BOTTOM = HEIGHT - TIMELINE_H                   # 800

# The inspector: below the toolbar and its tab strip, above the timeline.
INSPECTOR = None                                         # built in main()

# The section id the harness pins open. It is the id in `TextPane.swift`, and
# that it is a STRING both sides spell is half of what section 3 proves: a
# section under any other id would not open and the render would not move.
ANIMATION_ID = "text.animation"
# An id no section has. Pinning it must change nothing, which is what makes
# the comparison above a fact about THIS id rather than about pinning.
ABSENT_ID = ANIMATION_ID + ".nope"

# Where each part of the section sits relative to the section's own top edge
# S, straight out of `InspectorSection.init`: the header, then the content
# stack's top inset, then one row per pitch. Section 5 solves for S and
# checks that ONE value of it puts all four measured bands in these
# rectangles at once.
def row_offsets(index):
    """(top, bottom) of row `index` relative to the section's top edge."""
    top = SECTION_HEADER_H + CONTENT_TOP + index * ROW_PITCH
    return top, top + CONTROL_H


OFFSETS = [("header", (0, SECTION_HEADER_H))] + [
    (name, row_offsets(i)) for i, name in enumerate(ANIMATION_ROWS)
]


class Rect:
    def __init__(self, name, x, y, w, h):
        self.name, self.x0, self.y0, self.x1, self.y1 = name, x, y, x + w, y + h

    def contains(self, x, y, scale, slop=0):
        return (self.x0 - slop) * scale <= x < (self.x1 + slop) * scale \
            and (self.y0 - slop) * scale <= y < (self.y1 + slop) * scale

    def __str__(self):
        return f"{self.name} x {self.x0}–{self.x1} y {self.y0}–{self.y1} pt"


# ---------------------------------------------------------------------------
# Packages, by hand (spec §5.2). One clip, 0–5 s, on one track.

TICKS_PER_SECOND = 600_000
CLIP_SECONDS = 5


def animation(kind="typewriter", seconds_in=1.0, seconds_out=0.0):
    """One `TextAnimation`, in the core's field order (`model_props.rs`).
    The defaults are `TextAnimation::default()`'s: a one-second typewriter
    that does not un-reveal."""
    return {
        "kind": kind,
        "in": round(seconds_in * TICKS_PER_SECOND),
        "out": round(seconds_out * TICKS_PER_SECOND),
    }


def video_props():
    return {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [],
    }


def project_json(version=5, text=True, anim=None):
    track = {
        "id": 1, "name": "Track 1", "hidden": False, "muted": False, "locked": False,
        "solo": False,
    }
    props = {
        "content": "Hello", "font": "SourceSans3-SemiBold", "size": 72.0,
        "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
        "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": None,
        "width": None,
    }
    if version >= 5:
        # Version 5's one key, at the END of TextProps (the contract).
        props["animation"] = anim
    shape = {
        "kind": "rectangle", "width": 320.0, "height": 120.0,
        "stroke": {"width": 6.0, "color": [1.0, 1.0, 1.0, 1.0]}, "fill": None,
        "arrow_start": False, "arrow_end": False, "radius": 0.0,
        "from": [0.0, 1.0], "to": [1.0, 0.0],
    }
    clip = {
        "id": 2, "track": 1, "start": 0, "duration": CLIP_SECONDS * TICKS_PER_SECOND,
        "source": {"kind": "text" if text else "shape"},
        "enabled": {"video": True, "audio": True},
        "speed": 1.0,
        "video": video_props(),
        "audio": None,
        "text": props if text else None,
        "shape": None if text else shape,
        "actions": [], "transition_in": None,
        "name": None, "label": None,
    }
    return {
        "version": version,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0.0, 0.0, 0.0, 1.0], "fit_new_clips": True,
            "timecode_frames": True,
        },
        "media": [],
        "tracks": [track],
        "clips": [clip],
        "markers": [],
        "next_id": 3,
        "nests": [],
    }


PACKAGES = {
    # No `animation` key at all: the field is an Option that defaults to None
    # and version 5 has no migrate step, so this must read as an explicit null.
    "text-v4": dict(version=4),
    "text-none": dict(anim=None),
    "text-type": dict(anim=animation()),
    "text-word": dict(anim=animation(kind="word_fade")),
    "text-line": dict(anim=animation(kind="line_rise")),
    "text-in2": dict(anim=animation(seconds_in=2.0)),
    "text-out": dict(anim=animation(seconds_out=0.5)),
    # A shape clip: `ClipPane.makeSections` gives the text sections to a text
    # selection only, so this one must not have an Animation section at all.
    "shape-clip": dict(text=False),
}


def write_package(package, spec):
    path = os.path.join(WORK, package + ".framejob")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.json"), "w") as f:
        json.dump(project_json(**spec), f, indent=2)
        f.write("\n")
    return path


# ---------------------------------------------------------------------------
# The harness.

WARNINGS = []


def build_harness():
    start = time.time()
    result = subprocess.run([BUILD], capture_output=True, text=True)
    elapsed = time.time() - start
    if result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit("harness build failed")
    binary = result.stdout.strip().splitlines()[-1]
    built = "built" in result.stderr
    print(f"harness: {binary} ({'built in %.1f s' % elapsed if built else 'up to date'})")
    return binary


def render(binary, package, out, expand="-", height=HEIGHT, select=0):
    args = [
        binary, package, out, "light", str(WIDTH), str(height), str(select), "0", "1",
        "clip", "-", expand,
    ]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"render failed for {package}")
    # `Harness.png` writes one line to stderr when two consecutive captures
    # never came back equal — the layout was still moving when it gave up, and
    # every byte comparison below would then be measuring a race instead of
    # the feature. Collected rather than ignored, and reported as its own
    # check at the end.
    if result.stderr.strip():
        WARNINGS.append(f"{os.path.basename(out)}: {result.stderr.strip()}")
    return out


# ---------------------------------------------------------------------------
# PNG, in pure Python: chunks, zlib, the five filters.

def decode_png(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path} is not a PNG")
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
        sys.exit(f"{path}: only 8-bit non-interlaced PNGs are decoded here")
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
            sys.exit(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, channels, rows


def encode_png(width, height, channels, rows):
    """Filter-0 rows, for the crops written beside the renders."""
    colour = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(
            ">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


class Image:
    def __init__(self, path):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)
        self.scale = self.width / WIDTH

    def pixel(self, x, y):
        row = self.rows[y]
        return tuple(row[x * self.channels:(x + 1) * self.channels])

    def crop(self, rect, out):
        s = self.scale
        x0, x1 = int(rect.x0 * s), int(rect.x1 * s)
        y0, y1 = max(int(rect.y0 * s), 0), min(int(rect.y1 * s), self.height)
        rows = [row[x0 * self.channels:x1 * self.channels] for row in self.rows[y0:y1]]
        with open(out, "wb") as f:
            f.write(encode_png(x1 - x0, y1 - y0, self.channels, rows))


def changed_pixels(a, b):
    """Every (x, y) whose bytes differ, found by XOR-ing whole rows."""
    if (a.width, a.height, a.channels) != (b.width, b.height, b.channels):
        sys.exit(f"{a.path} and {b.path} differ in shape")
    out = []
    ch = a.channels
    for y, (ra, rb) in enumerate(zip(a.rows, b.rows)):
        if ra == rb:
            continue
        x = int.from_bytes(ra, "big") ^ int.from_bytes(rb, "big")
        xb = x.to_bytes(len(ra), "big")
        for m in re.finditer(rb"[^\x00]+", xb):
            for px in range(m.start() // ch, (m.end() - 1) // ch + 1):
                out.append((px, y))
    return out


def clusters(pixels, cell=12):
    """Bounding boxes of changed pixels grouped within `cell` px of each other."""
    buckets = {}
    for x, y in pixels:
        buckets.setdefault((x // cell, y // cell), []).append((x, y))
    parent = {k: k for k in buckets}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for cx, cy in buckets:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (cx + dx, cy + dy)
                if n in buckets:
                    parent[find(n)] = find((cx, cy))
    groups = {}
    for k, pts in buckets.items():
        groups.setdefault(find(k), []).extend(pts)
    boxes = []
    for pts in groups.values():
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        boxes.append((min(xs), min(ys), max(xs), max(ys), len(pts)))
    return sorted(boxes, key=lambda b: (b[1], b[0]))


def describe(boxes, scale, limit=12):
    lines = []
    for x0, y0, x1, y1, n in boxes[:limit]:
        lines.append(
            f"      x {x0}–{x1} y {y0}–{y1} px  = x {x0 / scale:.1f}–{(x1 + 1) / scale:.1f}"
            f" y {y0 / scale:.1f}–{(y1 + 1) / scale:.1f} pt  ({n} px)")
    if len(boxes) > limit:
        lines.append(f"      … and {len(boxes) - limit} more clusters")
    return "\n".join(lines)


def differing_rows(a, b, y0, y1, x0=INSPECTOR_X, x1=WIDTH):
    """The rows of `[y0, y1)` whose `[x0, x1)` bytes differ, in PIXELS.

    `changed_pixels` refuses two images of different shapes, and the two
    images section 7 compares are two window HEIGHTS of one package. Both
    hang their inspector off the same top edge, so the comparison is per
    row over the band they share.
    """
    scale = a.scale
    ch = a.channels
    lo, hi = int(x0 * scale) * ch, int(x1 * scale) * ch
    return [y for y in range(int(y0 * scale), int(y1 * scale))
            if a.rows[y][lo:hi] != b.rows[y][lo:hi]]


def inside(pixels, rect, scale, slop=0):
    return [p for p in pixels if rect.contains(p[0], p[1], scale, slop)]


def outside(pixels, rects, scale, slop=0):
    return [p for p in pixels if not any(r.contains(p[0], p[1], scale, slop) for r in rects)]


def extent(pixels, scale):
    """(top, bottom) of a changed set in points, or (None, None) when empty.

    Never a `guard` at a call site: a check that quietly disappears when its
    diff comes back empty is a check that cannot fail, so every caller here
    reports the empty case as a FAIL and the score stays the same length.
    """
    if not pixels:
        return None, None
    ys = [y for _, y in pixels]
    return min(ys) / scale, (max(ys) + 1) / scale


def shift_match(top, bottom, band, limit=140):
    """How far DOWN `bottom` is `top`, measured over `band`.

    With the section stack overflowing its scroll view there is no spare
    height to redistribute, so opening the section can only push what is
    under it down. This walks every whole-point shift and counts the rows of
    `band` that do not match; the winner is the growth, in points.
    """
    scale = bottom.scale
    ch = bottom.channels
    x0, x1 = int(band.x0 * scale) * ch, int(band.x1 * scale) * ch
    y0, y1 = int(band.y0 * scale), int(band.y1 * scale)
    scores = []
    for points in range(limit):
        offset = int(points * scale)
        if y0 - offset < 0:
            break
        mismatch = sum(
            1 for y in range(y0, y1)
            if bottom.rows[y][x0:x1] != top.rows[y - offset][x0:x1])
        scores.append((mismatch, points))
    scores.sort()
    return scores


# ---------------------------------------------------------------------------
# The checks.

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}: {name}")
    if detail:
        print(detail if detail.startswith("      ") else "      " + detail)


def same_file(a, b):
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


def identical(name, renders, images, a, b, scale):
    """Two renders that must be byte-identical, reported like phase 3's."""
    if same_file(renders[a], renders[b]):
        check(name, True)
        return
    diff = changed_pixels(images[a], images[b])
    check(name, not diff,
          ("the PNG bytes differ but every pixel is the same" if not diff else
           f"{len(diff)} pixels differ:\n" + describe(clusters(diff), scale)))


def report(images, a, b, what, scale, limit=10):
    """The changed pixels of one comparison, printed as clusters."""
    diff = changed_pixels(images[a], images[b])
    boxes = clusters(diff)
    print(f"\n   {what}: {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=limit))
    return diff, boxes


def origin_interval(band, offsets):
    """The values of the section's top edge S for which `band` (top, bottom)
    fits inside [S + lo, S + hi] — an interval, or None when the band is
    empty. Section 5 intersects one of these per measured band."""
    top, bottom = band
    if top is None:
        return None
    lo, hi = offsets
    return bottom - hi, top - lo


# ---------------------------------------------------------------------------
# The cue builder — `CaptionCues` in `app/Sources/CaptionLayout.swift`, over
# the harness's SECOND mode. Nothing below renders anything.
#
# It is here, in a script named for the chrome, because the harness is here:
# it is the one binary in the tree that links `app/Sources` outside the app,
# and so the one place that hands the builder an ARBITRARY word list. The app
# reaches `CaptionCues.build` through `CaptionPages` (the Subtitles style) once
# a transcription has produced words — `SpeechTranscriber`, which asks for no
# grant (spec §11 W-8), or the cloud engine — and `transcribe` reaches it over
# MCP, but only with the words a transcription heard. The rules are pure
# arithmetic over a word list with no `Speech` in them at all, so the harness
# hands the builder a word list and these checks read the answer, each rule at
# its boundary. The four:
#
#     at most 2 lines · at most 42 characters a line · at most 6 s a cue ·
#     at least one frame of gap between cues
#
# and each is asserted at its BOUNDARY, not in the middle, because a rule
# tested only in the middle passes against `<` where the code says `<=` and
# against a build that rounds the gap away. Times are in TICKS throughout:
# a frame at 30 fps is 20 000 ticks and 0.0333… of a second, so a fixture
# written in seconds could not say "exactly one frame" exactly.

CUE_MAX_LINES = 2                                 # CaptionCues.maxLines
CUE_MAX_CHARACTERS = 42                           # CaptionCues.maxCharacters
CUE_MAX_LENGTH = 6 * TICKS_PER_SECOND             # CaptionCues.maxLength


def stream(text, count, pitch, length, offset=0):
    """`count` copies of `text`, one every `pitch` ticks, each `length` long."""
    return [(text, i * pitch + offset, i * pitch + offset + length) for i in range(count)]


# The word lists, each written for ONE boundary and named for it. A word is
# `(text, start, end)`; `end` is one tick past the word's last, like every
# other span in the app.
CUE_FIXTURES = {
    # A word list of one. The last cue of a list has no successor to leave a
    # frame for, so its times must come back exactly as they went in.
    "one": ((30, 1), [("hello", 0, 300_000)]),
    # Nothing at all. The builder must answer with no cues rather than crash
    # or invent one; `CaptionLayout.place` is what reports the empty run.
    "none": ((30, 1), []),
    # One word LONGER than a whole line. It must come back whole: a hyphen
    # inserted in the middle of a word is a worse caption than a wide one,
    # and `text.width` soft-wraps it on the canvas anyway.
    "long-word": ((30, 1), [("X" * 60, 0, 300_000)]),
    # Two words at the same instant — which a recogniser can emit, and which
    # is where an ordering written as a subtraction goes wrong.
    "same-time": ((30, 1), [("alpha", 0, 300_000), ("beta", 0, 300_000)]),
    # 10 + 1 + 10 + 1 + 10 + 1 + 9 = EXACTLY 42 characters: the rule is
    # `<=`, so all four words stay on one line.
    "exactly-42": ((30, 1), [
        ("A" * 10, 0, 100_000), ("B" * 10, 100_000, 200_000),
        ("C" * 10, 200_000, 300_000), ("D" * 9, 300_000, 400_000)]),
    # The same list with one more character in the last word — 43 — so the
    # fourth word cannot fit and starts the second line.
    "just-over-42": ((30, 1), [
        ("A" * 10, 0, 100_000), ("B" * 10, 100_000, 200_000),
        ("C" * 10, 200_000, 300_000), ("D" * 10, 300_000, 400_000)]),
    # A second word ending EXACTLY six seconds after the first one started.
    # The rule is `<=` and measured against the word's END, so it joins.
    "exactly-6s": ((30, 1), [
        ("one", 0, 100_000), ("two", 3_400_000, CUE_MAX_LENGTH)]),
    # …and one tick later, which cannot.
    "just-over-6s": ((30, 1), [
        ("one", 0, 100_000), ("two", 3_400_000, CUE_MAX_LENGTH + 1)]),
    # A pause far longer than a cue may be: two words ten seconds apart.
    "pause": ((30, 1), [("one", 0, 100_000), ("two", 10 * TICKS_PER_SECOND,
                                              10 * TICKS_PER_SECOND + 100_000)]),
    # Thirty one-character words half a second apart. Twelve of them are 23
    # characters on one line, so NEITHER character rule can fire and the only
    # thing that can end a cue here is the six-second rule.
    "six-seconds": ((30, 1), stream("a", 30, 300_000, 270_000)),
}

# The gap fixtures: twenty 20-character words half a second apart, which pack
# two to a line and four to a cue, so a cue ends where the next one's first
# word begins — the tightest case the frame of gap has, and the only one where
# the clamp does any work at all. Each `offset` slides the whole stream off
# the frame grid by a different fraction of a frame (none at all, a tick, just
# under half, exactly half, just under a whole), because the claim is not only
# that the builder leaves a frame but that the frame SURVIVES `place`'s
# snap: both ends move, and they move together. 25 fps is there so the frame
# is 24 000 ticks rather than 20 000 and a builder that had hard-coded 30 fps
# would answer with the wrong gap.
GAP_OFFSETS = [0, 1, 9_999, 10_000, 19_999]
GAP_RATES = [(30, 1), (25, 1)]
for _rate in GAP_RATES:
    for _offset in GAP_OFFSETS:
        CUE_FIXTURES[f"gap-{_rate[0]}-{_offset}"] = (
            _rate, stream("W" * 20, 20, 300_000, 290_000, _offset))


def build_cues(binary, name, words, fps):
    """The harness's cue mode over one word list: `CaptionCues.build`'s own
    answer, as JSON. Nothing here re-implements a rule — a proof that
    computed the cues in order to check them would be checking itself."""
    source = os.path.join(CHROME, f"words-{name}.json")
    out = os.path.join(CHROME, f"cues-{name}.json")
    with open(source, "w") as f:
        json.dump({
            "fps": list(fps),
            "words": [{"text": t, "start": s, "end": e} for t, s, e in words],
        }, f, indent=2)
    result = subprocess.run([binary, "cues", source, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"the cue builder failed for {name}")
    with open(out) as f:
        return json.load(f)


def cue_lines(cue):
    """A cue's lines. The builder joins them with `"\\n"` — an advisory break
    CoreText honours inside a box that may add more of its own."""
    return cue["text"].split("\n")


def cue_gaps(built, prefix=""):
    """Every consecutive pair's gap, in ticks. `prefix` is `"snapped_"` for
    the times as `CaptionLayout.place` will see them."""
    cues = built["cues"]
    return [cues[i + 1][prefix + "start"] - cues[i][prefix + "end"]
            for i in range(len(cues) - 1)]


def cue_checks(binary):
    """The four cue rules, at their boundaries, over `CUE_FIXTURES`."""
    os.makedirs(CHROME, exist_ok=True)
    print("\n8. the cue builder — the four rules over a word list, no recogniser")
    built = {name: build_cues(binary, name, words, fps)
             for name, (fps, words) in CUE_FIXTURES.items()}
    for name in built:
        out = built[name]
        cues = out["cues"]
        lengths = [c["end"] - c["start"] for c in cues]
        print(f"      {name:<14} {len(cues):>2} cue(s)  frame {out['frame']:>5}  "
              f"lines {sorted({len(cue_lines(c)) for c in cues}) or '—'}  "
              f"longest {max(lengths, default=0) / TICKS_PER_SECOND:.2f} s  "
              f"gaps {sorted(set(cue_gaps(out))) or '—'}")

    every = [(name, cue) for name, out in built.items() for cue in out["cues"]]
    check("the fixtures built cues at all — every check below is over these",
          len(every) > 20, f"{len(every)} cues from {len(built)} word lists")

    # The four rules, swept over every cue of every fixture at once. Each one
    # names the worst case it found, so a failure says which fixture broke it.
    over = [(n, len(cue_lines(c))) for n, c in every if len(cue_lines(c)) > CUE_MAX_LINES]
    check(f"no cue is more than {CUE_MAX_LINES} lines (CaptionCues.maxLines) — a build "
          "without the line rule runs a paragraph under the picture", not over,
          f"over {len(every)} cues" if not over else f"{len(over)}: {over[:4]}")
    # A line may be longer than 42 characters only when it is ONE word: the
    # builder leaves an over-long word whole rather than hyphenating it.
    wide = [(n, len(line)) for n, c in every for line in cue_lines(c)
            if len(line) > CUE_MAX_CHARACTERS and " " in line]
    widest = max((len(line) for _, c in every for line in cue_lines(c) if " " in line),
                 default=0)
    check(f"no line of more than one word is over {CUE_MAX_CHARACTERS} characters "
          "(CaptionCues.maxCharacters) — a build without the width rule writes a line "
          "the canvas has to wrap for it", not wide,
          f"the longest multi-word line is {widest} characters"
          if not wide else f"{len(wide)}: {wide[:4]}")
    slow = [(n, (c["end"] - c["start"]) / TICKS_PER_SECOND) for n, c in every
            if c["end"] - c["start"] > CUE_MAX_LENGTH]
    longest = max((c["end"] - c["start"] for _, c in every), default=0)
    check(f"no cue is longer than {CUE_MAX_LENGTH // TICKS_PER_SECOND} s "
          "(CaptionCues.maxLength) — a build without the length rule leaves one screenful "
          "of words up for the whole recording", not slow,
          f"the longest is {longest / TICKS_PER_SECOND:.2f} s"
          if not slow else f"{len(slow)}: {slow[:4]}")
    # The gap, twice: as the builder leaves it, and as `CaptionLayout.place`
    # will see it once both ends are on the frame grid. The second is the one
    # that matters — a gap the snap ate would be trimmed back to an abutting
    # pair by the placement, silently retiming a transcript.
    for prefix, what in (("", "as the builder leaves them"),
                         ("snapped_", "after ReelTime.snapToFrame, which the placement runs")):
        tight = [(n, gap, built[n]["frame"]) for n, out in built.items()
                 for gap in cue_gaps(out, prefix) if gap < out["frame"]]
        pairs = sum(len(cue_gaps(out, prefix)) for out in built.values())
        check(f"consecutive cues are at least one frame apart, {what}", not tight,
              f"over {pairs} pairs" if not tight else f"{len(tight)}: {tight[:4]}")
    # And nothing was lost on the way. Compared as multisets, because two
    # words at the same instant have no defined order (see `same-time`).
    lost = []
    for name, (_, words) in CUE_FIXTURES.items():
        said = sorted(w[0] for w in words if w[0].strip())
        heard = sorted(w for cue in built[name]["cues"] for w in cue["text"].split())
        if said != heard:
            lost.append(name)
    check("every word comes back, once, and none is invented — a builder that dropped "
          "a word would still pass all four rules", not lost,
          f"over {sum(len(w) for _, w in CUE_FIXTURES.values())} words"
          if not lost else f"{lost}")

    # Now the boundaries, one fixture at a time.
    one = built["one"]["cues"]
    words = CUE_FIXTURES["one"][1]
    check("a word list of ONE builds one cue with the word's own times — the last cue "
          "has no successor to leave a frame for, so nothing is subtracted from it",
          len(one) == 1 and (one[0]["start"], one[0]["end"]) == words[0][1:]
          and one[0]["text"] == words[0][0],
          f"{[(c['start'], c['end'], c['text']) for c in one]} from {words}")
    check("an EMPTY word list builds no cues at all rather than one empty caption",
          built["none"]["cues"] == [], f"{built['none']['cues']}")

    long_word = built["long-word"]["cues"]
    text = CUE_FIXTURES["long-word"][1][0][0]
    check(f"a single word of {len(text)} characters — longer than a whole line — comes back "
          "WHOLE, on one line: no hyphen, no break, nothing truncated",
          len(long_word) == 1 and cue_lines(long_word[0]) == [text],
          f"{len(long_word)} cue(s), lines {[len(line) for line in cue_lines(long_word[0])]}"
          if long_word else "no cue at all")

    same = built["same-time"]["cues"]
    check("two words at the SAME instant land in one cue, both of them, spanning the "
          "instant they share — a build that ordered them by subtraction, or dropped "
          "the second as a duplicate key, loses one",
          len(same) == 1 and sorted(same[0]["text"].split()) == ["alpha", "beta"]
          and (same[0]["start"], same[0]["end"]) == (0, 300_000),
          f"{[(c['start'], c['end'], c['text']) for c in same]} "
          "(their ORDER is not asserted: Swift's sort is not documented stable and the "
          "two compare equal)")

    exact = built["exactly-42"]["cues"]
    over42 = built["just-over-42"]["cues"]
    check(f"a line of EXACTLY {CUE_MAX_CHARACTERS} characters stays one line — the rule is "
          "`<=`, and a build that wrote `<` breaks this line in two",
          len(exact) == 1 and len(cue_lines(exact[0])) == 1
          and len(exact[0]["text"]) == CUE_MAX_CHARACTERS,
          f"{[len(line) for line in cue_lines(exact[0])]} characters per line"
          if exact else "no cue at all")
    check(f"one character more than {CUE_MAX_CHARACTERS} moves the last word to the second "
          "line and leaves the first at 32 — the same cue, not a new one",
          len(over42) == 1 and [len(line) for line in cue_lines(over42[0])] == [32, 10],
          f"{[len(line) for line in cue_lines(over42[0])]} characters per line"
          if over42 else "no cue at all")

    exact6 = built["exactly-6s"]["cues"]
    over6 = built["just-over-6s"]["cues"]
    check(f"a word ending EXACTLY {CUE_MAX_LENGTH // TICKS_PER_SECOND} s after its cue began "
          "still joins it — `<=` again, measured against the word's END because a cue is up "
          "until its last word has been said",
          len(exact6) == 1 and exact6[0]["end"] == CUE_MAX_LENGTH,
          f"{[(c['start'], c['end'], c['text']) for c in exact6]}")
    check("…and ONE TICK later it starts a cue of its own",
          len(over6) == 2 and [c["text"] for c in over6] == ["one", "two"],
          f"{[(c['start'], c['end'], c['text']) for c in over6]}")

    pause = built["pause"]["cues"]
    check("a ten-second pause splits the cues, and the first holds only the word before it "
          "— a build without the length rule answers with one caption ten seconds wide",
          len(pause) == 2 and pause[0]["text"] == "one" and pause[1]["text"] == "two",
          f"{[(c['start'], c['end'], c['text']) for c in pause]}")

    six = built["six-seconds"]["cues"]
    lengths = [c["end"] - c["start"] for c in six]
    check(f"{len(CUE_FIXTURES['six-seconds'][1])} words that stay on ONE 23-character line "
          f"break into cues under {CUE_MAX_LENGTH // TICKS_PER_SECOND} s and over five — so "
          "it is the LENGTH rule that broke them and neither character rule could have",
          len(six) > 1 and max(lengths) <= CUE_MAX_LENGTH
          and max(lengths) > 5 * TICKS_PER_SECOND
          and all(len(cue_lines(c)) == 1 for c in six),
          f"{len(six)} cues of {[round(n / TICKS_PER_SECOND, 2) for n in lengths]} s, "
          f"{sorted({len(cue_lines(c)) for c in six})} line(s) each")

    # The gap fixtures: every one of them is the TIGHTEST case, where a cue's
    # last word ends where the next cue's first word begins, so every gap here
    # is the clamp's own work and nothing else's.
    for rate in GAP_RATES:
        names = [f"gap-{rate[0]}-{offset}" for offset in GAP_OFFSETS]
        frame = built[names[0]]["frame"]
        raw = {name: set(cue_gaps(built[name])) for name in names}
        snapped = {name: set(cue_gaps(built[name], "snapped_")) for name in names}
        counts = {name: len(built[name]["cues"]) for name in names}
        # Two 20-character words to a line and two lines to a cue, so the cue
        # count follows from the rules and is a claim in itself: a build that
        # allowed a third line packs six to a cue and answers four of them.
        cues = len(CUE_FIXTURES[names[0]][1]) // (2 * CUE_MAX_LINES)
        detail = "; ".join(
            f"{kind} " + ", ".join(f"{n.split('-')[-1]}: {sorted(g)}" for n, g in found.items())
            for kind, found in (("raw", raw), ("snapped", snapped)))
        check(f"at {rate[0]} fps, words that pack four to a cue and end where the next cue "
              f"begins are left EXACTLY one frame apart ({frame} ticks), at every offset "
              "from the frame grid — and still exactly one frame apart after the snap, "
              "which is the whole point: a gap the snap ate would be trimmed to an "
              "abutting pair and retime the transcript",
              set(counts.values()) == {cues}
              and all(gaps == {frame} for gaps in raw.values())
              and all(gaps == {frame} for gaps in snapped.values()),
              f"{cues} cues expected, {sorted(set(counts.values()))} built; " + detail)


def main():
    global INSPECTOR
    os.makedirs(CHROME, exist_ok=True)
    binary = build_harness()
    packages = {name: write_package(name, spec) for name, spec in PACKAGES.items()}
    print("packages:", ", ".join(os.path.relpath(p, ROOT) for p in packages.values()))

    INSPECTOR = Rect(
        "inspector", INSPECTOR_X, TOOLBAR + TAB, INSPECTOR_W,
        INSPECTOR_BOTTOM - (TOOLBAR + TAB))

    def png(tag):
        return os.path.join(CHROME, tag + ".png")

    start = time.time()
    # "shut" is the section as the design ships it (`defaultExpanded: false`),
    # so only its header is drawn; "open" pins its collapsed key to false.
    plan = [("shut-" + k, k, "-") for k in
            ("a", "v4", "none", "word", "line")] \
        + [("open-" + k, k, ANIMATION_ID) for k in
           ("a", "v4", "none", "word", "line", "in2", "out")]
    source = {
        "a": "text-type", "v4": "text-v4", "none": "text-none", "word": "text-word",
        "line": "text-line", "in2": "text-in2", "out": "text-out",
    }
    renders = {tag: render(binary, packages[source[key]], png(tag), expand=expand)
               for tag, key, expand in plan}
    # The two determinism renders, the pin that names nothing, and the shape
    # clip's pair — the last at its own window height (see SHAPE_HEIGHT).
    renders["shut-b"] = render(binary, packages["text-type"], png("shut-b"))
    renders["open-b"] = render(
        binary, packages["text-type"], png("open-b"), expand=ANIMATION_ID)
    renders["shut-absent"] = render(
        binary, packages["text-type"], png("shut-absent"), expand=ABSENT_ID)
    renders["shape-shut"] = render(
        binary, packages["shape-clip"], png("shape-shut"), height=SHAPE_HEIGHT)
    renders["shape-open"] = render(
        binary, packages["shape-clip"], png("shape-open"), expand=ANIMATION_ID,
        height=SHAPE_HEIGHT)
    renders["shape-taller"] = render(
        binary, packages["shape-clip"], png("shape-taller"), height=SHAPE_TALLER)
    print(f"rendered {len(renders)} PNGs in {time.time() - start:.1f} s")

    start = time.time()
    images = {tag: Image(path) for tag, path in renders.items()}
    scale = images["shut-a"].scale
    print(f"decoded {len(images)} PNGs in {time.time() - start:.1f} s; "
          f"{images['shut-a'].width}x{images['shut-a'].height} "
          f"{images['shut-a'].channels}-channel, scale {scale:g}")
    print(f"   {INSPECTOR}")
    print(f"   the section, open: {SECTION_HEADER_H} pt of header + {SECTION_BODY} pt of body"
          f" = {SECTION_OPEN_H} pt; one row every {ROW_PITCH} pt")
    print("   offsets from the section's top edge: "
          + ", ".join(f"{n} {lo}–{hi}" for n, (lo, hi) in OFFSETS))

    # 1. Determinism — everything below is a comparison of two renders, so
    # this is asserted FIRST and the rest of the score means nothing without
    # it. The harness captures on settle (two byte-identical consecutive
    # captures) rather than after a fixed spin count, and phase 4 is what
    # made that necessary: linking Speech.framework was enough to make the
    # inspector's height bistable across processes.
    print("\n1. determinism — one package rendered twice")
    identical("the closed section, twice → byte-identical PNGs", renders, images, "shut-a",
              "shut-b", scale)
    identical("the OPEN section, twice → byte-identical PNGs", renders, images, "open-a",
              "open-b", scale)

    # 2. The schema default. A version-4 file has no `animation` key at all,
    # and version 5 has no migrate step (the field is an Option), so it must
    # read as the null the version-5 spelling says out loud.
    print("\n2. the version-5 field defaults — a v4 file has no `animation` key")
    identical("v4 vs `animation: null`, closed → byte-identical PNGs", renders, images,
              "shut-v4", "shut-none", scale)
    identical("…and open, where the three rows would show it", renders, images, "open-v4",
              "open-none", scale)

    # 3. The section EXISTS, under the id `TextPane.animationSection` gives
    # it. The harness pins `FrameJobInspectorSection.text.animation` to "not
    # collapsed"; a section under any other id, or no section at all, leaves
    # the render exactly where it was.
    print("\n3. the section exists, under its own id — and is three rows tall")
    diff, _ = report(images, "shut-a", "open-a", "closed vs open", scale)
    check(f"pinning `{ANIMATION_ID}` open changes pixels", bool(diff))
    stray = outside(diff, [INSPECTOR], scale)
    check("every changed pixel is inside the inspector", not stray,
          "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
    top, _ = extent(diff, scale)

    # The header band, from the closed comparison in section 4 below: the
    # summary is the only thing a closed section draws that reads the data.
    # It is measured here first because section 3's "nothing above it moved"
    # needs it.
    header_band = extent(changed_pixels(images["shut-none"], images["shut-a"]), scale)
    if header_band[0] is None:
        # Every rectangle below is hung off this band, so a build whose closed
        # section says nothing would take the rest of the file down with it in
        # a traceback. A placeholder keeps the score the same LENGTH — the
        # checks that rest on the band then fail, which is the report a broken
        # build should get, rather than a shorter list that looks like a pass.
        print("      the closed section changed NO pixel — the measurements below are "
              "against a placeholder band and are expected to FAIL")
        header_band = (INSPECTOR.y0 + SECTION_HEADER_H, INSPECTOR.y0 + SECTION_HEADER_H + 10)
    check("nothing above the section header moved",
          top is not None and top >= header_band[0] - 1,
          f"first changed row y {top} pt; the header's summary starts at {header_band[0]} pt")
    # The band the shift is solved over: from below the deepest the section
    # can reach (its own summary's top plus a whole open section) to the
    # bottom of the inspector, clear of the scroller, whose knob length
    # changes with the content height.
    band_top = header_band[0] + SECTION_OPEN_H
    shift_band = Rect(
        "shift band", INSPECTOR_X, band_top, INSPECTOR_W - SCROLLER_W,
        INSPECTOR_BOTTOM - band_top)
    scores = shift_match(images["shut-a"], images["open-a"], shift_band)
    best, runner = scores[0], scores[1]
    print(f"      {shift_band}")
    print(f"      best shifts (mismatched rows, points): {scores[:4]}")
    check("the content below is the closed render pushed DOWN by exactly three rows",
          best[1] == SECTION_BODY and best[0] * 4 < runner[0],
          f"{best[1]} pt at {best[0]} mismatched rows of "
          f"{int((INSPECTOR_BOTTOM - band_top) * scale)}; next best {runner[1]} pt at "
          f"{runner[0]}. Three rows = {CONTENT_TOP} + {len(ANIMATION_ROWS)} × "
          f"(DS.controlHeight {CONTROL_H}) + {len(ANIMATION_ROWS) - 1} × "
          f"(InspectorMetrics.rowSpacing {ROW_SPACING}) + {CONTENT_BOTTOM} = {SECTION_BODY} pt")
    # …and that it is THIS id that did it: a pin naming a section nobody
    # built changes nothing at all.
    identical(f"pinning `{ABSENT_ID}`, which no section has, renders byte-identically",
              renders, images, "shut-a", "shut-absent", scale)
    # And the section belongs to TEXT. `ClipPane.makeSections` hands out the
    # text group on `textPane.allText`, so a shape clip has no section with
    # this id and the same pin can change nothing.
    identical("a SHAPE clip has no Animation section: the same pin renders byte-identically",
              renders, images, "shape-shut", "shape-open", scale)

    # 4. The closed section's summary reads the data.
    print("\n4. the closed section — the summary reads the animation")
    bands = {}
    for tag, other, what in (
        ("shut-a", "shut-none", "typewriter vs no animation"),
        ("shut-word", "shut-a", "word fade vs typewriter — another kind, the same timings"),
        ("shut-line", "shut-word", "line rise vs word fade — the third kind"),
    ):
        diff, boxes = report(images, tag, other, what, scale, limit=6)
        check(f"{what} changes pixels", bool(diff))
        stray = outside(diff, [INSPECTOR], scale)
        check("and every one of them is inside the inspector", not stray,
              "" if not stray else f"{len(stray)} px elsewhere:\n"
              + describe(clusters(stray), scale))
        top, bottom = extent(diff, scale)
        check("they fit inside one section header (InspectorMetrics.headerHeight)",
              top is not None and bottom - top <= SECTION_HEADER_H,
              f"{len(boxes)} cluster(s), y {top}–{bottom} pt")
        bands[what] = (top, bottom)
    # Re-measured in place 2026-09-23 (road map 9 phase 3b, spec §11 CI-9):
    # Reset now shows only while the section differs from its default, so
    # "typewriter vs no animation" ALSO changes the header's Reset button,
    # whose top sits above the summary's. The later pairs (Reset shown in
    # both) must lie INSIDE the first pair's band rather than start at its top.
    first = list(bands.values())[0]
    for what, (top, bottom) in list(bands.items())[1:]:
        check(f"…and in the same band as the first — one summary, not three ({what})",
              None not in (top, first[0])
              and first[0] - 1 <= top and bottom <= first[1] + 1,
              f"y {top}–{bottom} pt vs {first[0]}–{first[1]} pt")

    # 5. The open section's ROWS — each reads its own key and nothing else's.
    print("\n5. the open section — three rows, each bound to one key")
    kind_diff, _ = report(
        images, "open-a", "open-line", "the Reveal popup: typewriter vs line rise", scale)
    in_diff, _ = report(images, "open-a", "open-in2", "the In row: 1 s vs 2 s", scale)
    out_diff, _ = report(images, "open-a", "open-out", "the Out row: 0 s vs 0.5 s", scale)

    for name, diff in (("kind", kind_diff), ("in", in_diff), ("out", out_diff)):
        check(f"the {name} change moves pixels", bool(diff))
    # Everything one of these three edits touches is inside the ONE section:
    # a band a whole open section tall, hung one header above the summary,
    # is the widest the section can be given where its summary was seen.
    section_band = Rect(
        "the Animation section", INSPECTOR_X, header_band[0] - SECTION_HEADER_H, INSPECTOR_W,
        SECTION_HEADER_H + SECTION_OPEN_H)
    print(f"      {section_band}")
    for name, diff in (("kind", kind_diff), ("in", in_diff), ("out", out_diff)):
        stray = outside(diff, [section_band], scale)
        check(f"the {name} change lands in the Animation section and NOWHERE else", not stray,
              "" if not stray else f"{len(stray)} px elsewhere:\n"
              + describe(clusters(stray), scale))

    # The summary spells the KIND and the IN duration and nothing else
    # (`TextPane.animationSection`'s `summary`), so the Out row's edit must
    # leave the header alone — a summary that read `out` would fail here.
    summary = Rect(
        "the header summary", INSPECTOR_X, header_band[0], INSPECTOR_W,
        header_band[1] - header_band[0])
    for name, diff, want in (("kind", kind_diff, True), ("in", in_diff, True),
                             ("out", out_diff, False)):
        hit = inside(diff, summary, scale)
        check(f"the summary {'follows' if want else 'ignores'} the {name}",
              bool(hit) == want, f"{len(hit)} px inside {summary}")

    # The three row bands, measured below the header.
    def row_band(diff):
        return extent([p for p in diff if p[1] / scale >= header_band[1]], scale)

    measured = [("header", header_band)] + list(
        zip(ANIMATION_ROWS, (row_band(kind_diff), row_band(in_diff), row_band(out_diff))))
    for name, band in measured:
        print(f"      {name:<7} ink y {band[0]}–{band[1]} pt")
    ordered = all(
        None not in measured[i][1] + measured[i + 1][1]
        and measured[i][1][1] <= measured[i + 1][1][0]
        for i in range(len(measured) - 1))
    check("the four bands are disjoint and in the section's own order "
          "(header, Reveal, In, Out)", ordered,
          " → ".join(f"{n} {b[0]}–{b[1]}" for n, b in measured))
    # In and Out are the SAME control (a slider beside a field), so their ink
    # sits at the same place inside their rows and the pitch between them is
    # exact — a whole DS.controlHeight + InspectorMetrics.rowSpacing.
    in_band, out_band = measured[2][1], measured[3][1]
    exact = None not in in_band + out_band and \
        (out_band[0] - in_band[0], out_band[1] - in_band[1]) == (ROW_PITCH, ROW_PITCH)
    check(f"the Out row is exactly one row pitch below the In row ({ROW_PITCH} pt), "
          "top and bottom", exact,
          f"In {in_band[0]}–{in_band[1]} pt, Out {out_band[0]}–{out_band[1]} pt")
    # And ONE section origin puts all four where InspectorSection.init would.
    intervals = [(n, origin_interval(b, dict(OFFSETS)[n])) for n, b in measured]
    for name, interval in intervals:
        print(f"      {name:<7} → section top S ∈ "
              f"{'nothing (the band is empty)' if interval is None else interval}")
    lows = [i[1][0] for i in intervals if i[1]]
    highs = [i[1][1] for i in intervals if i[1]]
    feasible = (max(lows), min(highs)) if len(lows) == len(intervals) else None
    check("one section origin puts the header and all three rows where "
          "InspectorSection.init would", feasible is not None and feasible[0] <= feasible[1],
          f"S ∈ {feasible}" if feasible else "at least one band was empty")

    # 6. The popup at None. `TextAnimation()` mirrors the core's default — a
    # one-second typewriter that does not un-reveal — and that is what the
    # In and Out rows READ when there is no animation, so both show exactly
    # the numbers `text-type` shows. Anything that changes in those two rows
    # is therefore the section's `enabled: on` closure and nothing else.
    print("\n6. the popup at None — the value rows go dead without changing their numbers")
    none_diff, _ = report(images, "open-none", "open-a", "no animation vs typewriter", scale)
    stray = outside(none_diff, [section_band], scale)
    check("switching the reveal on lands in the Animation section and NOWHERE else", not stray,
          "" if not stray else f"{len(stray)} px elsewhere:\n"
          + describe(clusters(stray), scale))
    for name, band in measured[1:]:
        if band[0] is None:
            # Its own edit changed nothing, so there is no band to look in —
            # a FAIL rather than a skipped check (see `extent`).
            check(f"the {name} row is drawn differently with the reveal off", False,
                  f"the {name} row's own edit moved no pixel, so it has no band")
            continue
        row = Rect(name, INSPECTOR_X, band[0], INSPECTOR_W, band[1] - band[0])
        hit = inside(none_diff, row, scale)
        check(f"the {name} row is drawn differently with the reveal off", bool(hit),
              f"{len(hit)} px inside {row}")
    check("and far more pixels change than the In row's own value does — "
          "that is two rows going live, not a number",
          len(none_diff) > 4 * len(in_diff),
          f"{len(none_diff)} px vs {len(in_diff)} px "
          f"({len(none_diff) / max(len(in_diff), 1):.1f}×)")

    # 7. The instrument's own honesty.
    print("\n7. the renders themselves")
    check("no render reported an unsettled layout", not WARNINGS,
          "" if not WARNINGS else "\n".join("      " + w for w in WARNINGS))
    # Why the shape pair is rendered at its own height (see SHAPE_HEIGHT): a
    # section stack with slack hands it to whichever section will stretch,
    # and which one wins is decided per PROCESS. A stack that overflows has
    # none to hand out, and this is what that looks like — make the window
    # 38 pt taller and the inspector draws the same bytes, because the extra
    # height went to the scroll view's clip and not to a section.
    # One point short of the shorter window's fold: the last row there is the
    # split view's divider with the timeline behind it, and the taller window
    # has inspector at that y. That row is the FOLD moving, not a section.
    moved = differing_rows(
        images["shape-shut"], images["shape-taller"], INSPECTOR.y0,
        SHAPE_HEIGHT - TIMELINE_H - 1)
    check(f"the shape clip's sections do not stretch at {SHAPE_HEIGHT} pt, so its layout "
          "has nothing to be bistable about", not moved,
          f"{len(moved)} of "
          f"{int((SHAPE_HEIGHT - TIMELINE_H - 1 - INSPECTOR.y0) * scale)} inspector rows differ "
          f"between the {SHAPE_HEIGHT} pt and {SHAPE_TALLER} pt windows"
          + (f", first at y {moved[0] / scale} pt" if moved else ""))

    # 8. The cue builder, which is arithmetic and not a picture at all — see
    # the section's own header for why it is nonetheless in this file.
    cue_checks(binary)

    # Crops for the eye check.
    crop = Rect(
        "section", INSPECTOR_X, header_band[0] - SECTION_HEADER_H, INSPECTOR_W,
        SECTION_HEADER_H + SECTION_OPEN_H + 8)
    for tag in renders:
        if tag.startswith("shape"):
            continue
        images[tag].crop(crop, os.path.join(CHROME, f"crop-{tag}-animation.png"))
    print(f"\nPNGs, crops and the cue builder's word lists and answers are in "
          f"{os.path.relpath(CHROME, ROOT)}/")
    print("The reveal ITSELF is not claimed here — the preview well renders black "
          "offscreen.\nThat is phase4_proof.py's, over MCP against a running app.")

    passed = sum(RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed")
    sys.exit(0 if passed == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
