#!/usr/bin/env python3
"""Road map 2, phase 3 (the screencast trio) — the CHROME half of the proof.

Phase 3 is three features and the harness can photograph exactly one and a
half of them. The preview well renders BLACK offscreen (a Metal layer has no
drawable), and there is no way to arm a modal canvas session from a bare
binary, so **nothing about the picture, the zoom band or the obscure effect
itself is claimed here** — those belong to `phase3_proof.py`, which drives a
running app over MCP. What is left is the chrome, and it is worth having:

    3a  Remove Silences' candidate-span wash on the ruler and the lanes,
        and the new `DS.timelineCandidateShade` token under it.
    3c  The Obscure inspector section — that it exists, that its summary
        reads the list, and that its ROWS grow and shrink with it.

Every claim is a BYTE comparison of two PNGs the offscreen harness wrote
(`tools/proof/harness/`, CLAUDE.md's "Seeing the chrome"), then a
measurement of WHERE the changed pixels landed against rectangles derived
from the app's own layout constants. `phase2_chrome.py` is the model and
this file follows it line for line.

The packages are written BY HAND (a `.reelcut` is a directory holding
`project.json`, spec §5.2) around one TEXT clip, so nothing loads
asynchronously and every render is deterministic — no media at all:

    obscure-v3        version 3, no `video.obscure` key at all (the fallback)
    obscure-none      version 4, `"obscure": []`
    obscure-one       version 4, one region, the core's defaults (pixelate)
    obscure-one-blur  version 4, one region, `"kind": "blur"`
    obscure-two       version 4, two regions

TWO HARNESS ARGUMENTS WERE ADDED FOR THIS SCRIPT, and they are declared
loudly here because a proof that quietly grew its own instrument is not a
proof. Both are view state a package cannot carry — the same category as
`selectIndex` and `playheadSec`, which is why the harness has an argument
list at all — and both default to "nothing", so every earlier caller renders
the bytes it always did (`phase2_chrome.py` still passes 26/26):

    [candidateSpans]   "1-2,6-7", seconds. `TimelineView.candidateSpans` is
                       set by the Remove Silences SHEET and by nothing else,
                       and a sheet cannot be put up offscreen. Without this
                       the wash could not be photographed at all.
    [expandSections]   "video.obscure,…". A section's collapsed state is a
                       `UserDefaults` key the harness already pins, and the
                       Obscure section is built `defaultExpanded: false`, so
                       without this its rows are never drawn and only its
                       header summary could be measured.

Run it from anywhere; it builds the harness if it is stale:

    python3 tools/proof/phase3_chrome.py

The last line is `<n>/<n> checks passed` and the exit status is non-zero if
any failed. The PNGs stay in `tools/proof/work/chrome3/` (with crops of the
two candidate spans and the Obscure section for an eye check), and the
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
CHROME = os.path.join(WORK, "chrome3")
BUILD = os.path.join(HERE, "harness", "build.sh")

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants. Each number names the
# Swift constant it mirrors; the PNG's width / WIDTH is the backing scale
# (2 on a Retina Mac).
#
# Two window heights are used, and the second one needs a word. The Clip tab
# of a text clip carries fourteen sections and the Obscure section is the
# thirteenth, so at the 862 pt window phase 2 uses it is BELOW THE FOLD and
# nothing about it can be measured — the inspector's scroll view starts at
# the top and the harness cannot scroll it. TALL is the height at which the
# whole section is on screen AND the content still overflows: with Timing and
# Actions held open (`INSPECTOR_BELOW`) the stack has no slack to redistribute,
# so opening Obscure moves nothing above it and the arithmetic below is a
# pure downward shift. Measured, not guessed: at 1400 and above the empty-list
# package regains slack and the sections above Obscure start to move.

WIDTH = 1440
HEIGHT = 862             # phase 2's window: the timeline claims
TALL = 1500              # the inspector claims (see above)

TOOLBAR = 44             # DS.toolbarHeight
TAB = 32                 # DS.tabHeight — the inspector's tab strip
INSPECTOR_W = 304        # DS.panelWidth = EditorViewController.defaultInspectorWidth
TIMELINE_H = 300         # EditorViewController.defaultTimelineHeight
BAR_H = 36               # DS.timelineBarHeight
RULER_H = 22             # DS.rulerHeight
HEADER_W = 132           # DS.trackHeaderWidth
LANES_INSET = 4          # TimelineLayout.lanesInset
LANE_SPACING = 2         # TimelineLayout.laneSpacing
TEXT_LANE_M = 44         # DS.trackHeights[1][0] — a text lane at M
ZOOM = 42                # TimelineLayout.defaultZoom, points per second
BODY_INSET = 3           # TimelineContentView.bodyRect
SCROLLER_W = 16          # AppKit's legacy scroller, pinned by the harness
SECTION_HEADER_H = 28    # InspectorMetrics.headerHeight
CONTROL_H = 22           # DS.controlHeight
ROW_SPACING = 7          # InspectorMetrics.rowSpacing
CLIP_SECONDS = 5

INSPECTOR_X = WIDTH - INSPECTOR_W                        # 1136
TIMELINE_Y = HEIGHT - TIMELINE_H                         # 562
RULER_Y = TIMELINE_Y + BAR_H                             # 598
LANES_TOP = RULER_Y + RULER_H + LANES_INSET              # 624
LANES_H = TEXT_LANE_M + LANE_SPACING                     # 46 = layout.lanesHeight, one track
CLIP_X0 = HEADER_W                                       # time zero is at x == headerWidth
CLIP_X1 = HEADER_W + ZOOM * CLIP_SECONDS                 # 342
BODY_Y0 = LANES_TOP + BODY_INSET                         # 627
BODY_Y1 = LANES_TOP + TEXT_LANE_M - BODY_INSET           # 665

# The candidate spans this proof asks for, in SECONDS. One OVER the clip (so
# the wash has to sit under it) and one PAST it (so a whole lane row is
# visible and the ink can be measured against two different backgrounds).
SPAN_A = (1.0, 2.0)
SPAN_B = (6.0, 7.0)
CANDIDATES = f"{SPAN_A[0]:g}-{SPAN_A[1]:g},{SPAN_B[0]:g}-{SPAN_B[1]:g}"

# The two `InspectorSection` ids BELOW Obscure in the Clip tab, held open in
# every inspector render so the section stack has no spare height to give
# back when Obscure opens (see the note on TALL).
INSPECTOR_BELOW = "clip.timing,video.actions"
OBSCURE_ID = "video.obscure"

# `DS.timelineCandidateShade` is `coral.withAlphaComponent(0.24)` and
# `DS.timelineRangeShade` is the same ink at 0.12. The wash is measured, not
# assumed: a build that reached for the range's constant reads 0.12 here.
CANDIDATE_ALPHA = 0.24
RANGE_ALPHA = 0.12


class Rect:
    def __init__(self, name, x, y, w, h):
        self.name, self.x0, self.y0, self.x1, self.y1 = name, x, y, x + w, y + h

    def contains(self, x, y, scale, slop=0):
        return (self.x0 - slop) * scale <= x < (self.x1 + slop) * scale \
            and (self.y0 - slop) * scale <= y < (self.y1 + slop) * scale

    def __str__(self):
        return f"{self.name} x {self.x0}–{self.x1} y {self.y0}–{self.y1} pt"


def span_x(span):
    """A span's x range, through TimelineLayout.x(for:) = headerWidth + zoom·t."""
    return HEADER_W + ZOOM * span[0], HEADER_W + ZOOM * span[1]


def span_rects(name, span):
    """The two bands `TimelineView+Candidates.swift` fills for one span: the
    ruler's whole height, and the lanes from `lanesTop` for `lanesHeight`."""
    x0, x1 = span_x(span)
    return [
        Rect(f"{name} ruler", x0, RULER_Y, x1 - x0, RULER_H),
        Rect(f"{name} lanes", x0, LANES_TOP, x1 - x0, LANES_H),
    ]


WASH = span_rects("span A", SPAN_A) + span_rects("span B", SPAN_B)

RECTS = {
    # The clip's own body under span A — the wash is drawn BEFORE the clip
    # loop, so these pixels must not move.
    "clip body under span A": Rect(
        "clip body under span A", span_x(SPAN_A)[0], BODY_Y0,
        span_x(SPAN_A)[1] - span_x(SPAN_A)[0], BODY_Y1 - BODY_Y0),
    # Between the two spans: a build that washed one rectangle from the first
    # start to the last end would paint here.
    "between the spans": Rect(
        "between the spans", span_x(SPAN_A)[1], RULER_Y,
        span_x(SPAN_B)[0] - span_x(SPAN_A)[1], LANES_TOP + LANES_H - RULER_Y),
    "track header column": Rect(
        "track header column", 0, RULER_Y, HEADER_W, TIMELINE_H - BAR_H),
}

# The inspector, at the tall window: below the toolbar and its tab strip,
# above the timeline.
INSPECTOR = Rect(
    "inspector", INSPECTOR_X, TOOLBAR + TAB, INSPECTOR_W,
    (TALL - TIMELINE_H) - (TOOLBAR + TAB))
# The band the shift is solved over: the bottom 200 pt of the inspector, clear
# of the scroller (whose knob length changes with the content height).
SHIFT_BAND = Rect(
    "shift band", INSPECTOR_X, TALL - TIMELINE_H - 200,
    INSPECTOR_W - SCROLLER_W, 200)
# Six rows is what one more region adds: `Region N`, Shape, Amount, Feather,
# Center, Size (VideoPane.obscureSection), each DS.controlHeight tall with
# InspectorMetrics.rowSpacing under it.
REGION_ROWS = 6
ROW_PITCH = CONTROL_H + ROW_SPACING          # 29
REGION_HEIGHT = REGION_ROWS * ROW_PITCH      # 174

# Where the ink is sampled, inside span B and clear of the clip: an empty
# lane row (DS.timelineLaneAlt) and the 2 pt gap under it (DS.timelineLane).
# Two DIFFERENT backgrounds under one wash is what makes the alpha solvable
# without knowing what colour space the bitmap came back in.
INK_X0, INK_X1 = 396, 404
INK_SAMPLES = {
    "lane row": Rect("lane row", INK_X0, LANES_TOP + 16, INK_X1 - INK_X0, 24),
    "lane gap": Rect(
        "lane gap", INK_X0, LANES_TOP + TEXT_LANE_M + 0.5, INK_X1 - INK_X0, 1),
}


# ---------------------------------------------------------------------------
# Packages, by hand (spec §5.2). One text clip, 0–5 s, on one track.

TICKS_PER_SECOND = 600_000


def region(kind="pixelate", shape="rect", x=0.0, y=0.0, width=480.0, height=270.0,
           feather=20.0, amount=1.0):
    """One `ObscureRegion`, in the core's field order (`model_regions.rs`).
    The defaults are `ObscureRegion::default()`'s."""
    return {
        "shape": shape, "x": x, "y": y, "width": width, "height": height,
        "feather": feather, "kind": kind, "amount": amount,
    }


def project_json(version, obscure):
    track = {
        "id": 1, "name": "Track 1", "hidden": False, "muted": False, "locked": False,
        "solo": False,
    }
    video = {
        "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": None,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
    }
    if version >= 4:
        # Version 4's one key, at the END of VideoProps (the contract).
        video["obscure"] = obscure
    clip = {
        "id": 2, "track": 1, "start": 0, "duration": CLIP_SECONDS * TICKS_PER_SECOND,
        "source": {"kind": "text"},
        "enabled": {"video": True, "audio": True},
        "speed": 1.0,
        "video": video,
        "audio": None,
        "text": {
            "content": "Hello", "font": "SourceSans3-SemiBold", "size": 72.0,
            "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
            "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": None,
            "width": None,
        },
        "shape": None, "actions": [], "transition_in": None,
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
    "obscure-v3": dict(version=3, obscure=[]),
    "obscure-none": dict(version=4, obscure=[]),
    "obscure-one": dict(version=4, obscure=[region()]),
    "obscure-one-blur": dict(version=4, obscure=[region(kind="blur")]),
    "obscure-two": dict(version=4, obscure=[region(), region(x=120.0, y=60.0)]),
}


def write_package(package, spec):
    path = os.path.join(WORK, package + ".reelcut")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.json"), "w") as f:
        json.dump(project_json(**spec), f, indent=2)
        f.write("\n")
    return path


# ---------------------------------------------------------------------------
# The harness.

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


def render(binary, package, out, height=HEIGHT, candidates="-", expand="-", select=0):
    args = [
        binary, package, out, "light", str(WIDTH), str(height), str(select), "0", "1",
        "clip", candidates, expand,
    ]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(f"render failed for {package}")
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

    def block(self, rect):
        """Every pixel inside `rect`, as a list of RGBA tuples."""
        s = self.scale
        out = []
        for y in range(int(rect.y0 * s), int(rect.y1 * s)):
            for x in range(int(rect.x0 * s), int(rect.x1 * s)):
                out.append(self.pixel(x, y))
        return out

    def crop(self, rect, out):
        s = self.scale
        x0, x1 = int(rect.x0 * s), int(rect.x1 * s)
        y0, y1 = int(rect.y0 * s), int(rect.y1 * s)
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


def uniform(values):
    """The one colour of a block, or None when the block is not flat."""
    first = values[0]
    return first if all(v == first for v in values) else None


def shift_match(top, bottom, band, limit=260):
    """How far DOWN `bottom` is `top`, measured over `band`.

    With the section stack overflowing its scroll view there is no spare
    height to redistribute, so opening a second region can only push what is
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
    """Two renders that must be byte-identical, reported like phase 2's."""
    if same_file(renders[a], renders[b]):
        check(name, True)
        return
    diff = changed_pixels(images[a], images[b])
    check(name, not diff,
          ("the PNG bytes differ but every pixel is the same" if not diff else
           f"{len(diff)} pixels differ:\n" + describe(clusters(diff), scale)))


def main():
    os.makedirs(CHROME, exist_ok=True)
    binary = build_harness()
    packages = {name: write_package(name, spec) for name, spec in PACKAGES.items()}
    print("packages:", ", ".join(os.path.relpath(p, ROOT) for p in packages.values()))

    def png(tag):
        return os.path.join(CHROME, tag + ".png")

    start = time.time()
    opened = INSPECTOR_BELOW + "," + OBSCURE_ID
    renders = {
        # The timeline, at phase 2's window.
        "plain-a": render(binary, packages["obscure-one"], png("plain-a")),
        "plain-b": render(binary, packages["obscure-one"], png("plain-b")),
        "cand": render(binary, packages["obscure-one"], png("cand"), candidates=CANDIDATES),
        # The inspector, at the tall window. "closed" is the Obscure section
        # as the design ships it (`defaultExpanded: false`); "open" has it open.
        "closed-v3": render(
            binary, packages["obscure-v3"], png("closed-v3"), TALL, expand=INSPECTOR_BELOW),
        "closed-none": render(
            binary, packages["obscure-none"], png("closed-none"), TALL, expand=INSPECTOR_BELOW),
        "closed-one": render(
            binary, packages["obscure-one"], png("closed-one"), TALL, expand=INSPECTOR_BELOW),
        "closed-blur": render(
            binary, packages["obscure-one-blur"], png("closed-blur"), TALL,
            expand=INSPECTOR_BELOW),
        "closed-two": render(
            binary, packages["obscure-two"], png("closed-two"), TALL, expand=INSPECTOR_BELOW),
        "open-one": render(
            binary, packages["obscure-one"], png("open-one"), TALL, expand=opened),
        "open-two": render(
            binary, packages["obscure-two"], png("open-two"), TALL, expand=opened),
    }
    print(f"rendered {len(renders)} PNGs in {time.time() - start:.1f} s")

    start = time.time()
    images = {tag: Image(path) for tag, path in renders.items()}
    scale = images["plain-a"].scale
    print(f"decoded {len(images)} PNGs in {time.time() - start:.1f} s; "
          f"{images['plain-a'].width}x{images['plain-a'].height} "
          f"{images['plain-a'].channels}-channel, scale {scale:g}")
    print("rectangles (points):")
    for rect in WASH + list(RECTS.values()) + [INSPECTOR, SHIFT_BAND]:
        print(f"   {rect}")
    print(f"   candidate spans: {CANDIDATES} s; one region is "
          f"{REGION_ROWS} × {ROW_PITCH} = {REGION_HEIGHT} pt of rows")

    # 1. Determinism — everything below is a comparison of two renders.
    print("\n1. determinism — the same package rendered twice")
    identical("one region twice → byte-identical PNGs", renders, images, "plain-a", "plain-b",
              scale)
    plain = images["plain-a"]

    # 2. A version-3 file has no `video.obscure` key at all; it must read as
    # the empty list, which is what the version-4 spelling of the same
    # project says out loud.
    print("\n2. v3 == an empty list — the schema-4 field defaults")
    identical("v3 vs obscure: [] → byte-identical PNGs", renders, images, "closed-v3",
              "closed-none", scale)

    # 3. The candidate wash (3a).
    print("\n3. the candidate spans — the ruler and the lanes, under the clips")
    diff = changed_pixels(images["cand"], plain)
    boxes = clusters(diff)
    print(f"      {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=20))
    check("the candidate spans change pixels somewhere", bool(diff))
    for rect in WASH:
        hit = inside(diff, rect, scale)
        check(f"the wash lands in the {rect.name}", bool(hit), f"{len(hit)} px inside {rect}")
    stray = outside(diff, WASH, scale)
    check("and every changed pixel is inside one of those four bands", not stray,
          "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
    for key, phrase in (
        ("clip body under span A", "the wash is UNDER the clips — the body under span A is"
                                   " byte-identical"),
        ("between the spans", "the two spans are washed separately — nothing changes between"
                              " them"),
        ("track header column", "and nothing reaches the track header column"),
    ):
        hit = inside(diff, RECTS[key], scale)
        check(phrase, not hit, f"{len(hit)} px inside {RECTS[key]}")

    # 4. The ink. Both washes are the same coral, so the DISCRIMINATOR
    # between DS.timelineCandidateShade and DS.timelineRangeShade is the
    # alpha, and alpha is solvable without knowing the bitmap's colour space:
    # over two different backgrounds B1, B2 under one wash,
    #     p1 − p2 = (1 − a)·(B1 − B2)
    # so the ink's own colour drops out. A build that reached for the range's
    # constant reads 0.12 here and fails.
    print("\n4. the ink — DS.timelineCandidateShade, measured")
    samples = {}
    for name, rect in INK_SAMPLES.items():
        base = uniform(plain.block(rect))
        washed = uniform(images["cand"].block(rect))
        ok = base is not None and washed is not None
        check(f"the {name} sample is flat in both renders", ok,
              f"{rect}: base {base}, washed {washed}")
        samples[name] = (base, washed) if ok else (None, None)
    for name, (base, washed) in samples.items():
        delta = None if base is None else tuple(washed[i] - base[i] for i in range(3))
        check(f"the wash pushes the {name} toward coral (ΔR > ΔG > ΔB)",
              delta is not None and delta[0] > delta[1] > delta[2],
              f"base {base and base[:3]} → {washed and washed[:3]}, Δ {delta}")
    (b1, p1), (b2, p2) = samples.values()
    solvable = None not in (b1, b2)
    spread = sum((b1[i] - b2[i]) ** 2 for i in range(3)) if solvable else 0
    check("the two sampled backgrounds are far enough apart to solve for α",
          spread >= 3 * 40 ** 2,
          f"{b1 and b1[:3]} vs {b2 and b2[:3]}, |ΔB|² = {spread} "
          f"(need ≥ {3 * 40 ** 2})")
    alpha = None
    if spread:
        covariance = sum((p1[i] - p2[i]) * (b1[i] - b2[i]) for i in range(3))
        alpha = 1 - covariance / spread
    check("the wash measures as the CANDIDATE token's α, not the range's",
          alpha is not None and abs(alpha - CANDIDATE_ALPHA) < 0.02 < abs(alpha - RANGE_ALPHA),
          f"α = {alpha if alpha is None else round(alpha, 4)}; "
          f"DS.timelineCandidateShade = {CANDIDATE_ALPHA}, "
          f"DS.timelineRangeShade = {RANGE_ALPHA}")

    # 5. The Obscure section, closed — the header summary reads the list.
    print("\n5. the Obscure section, as it ships (closed) — the summary reads the data")
    header_band = None
    for tag, other, what in (
        ("closed-one", "closed-none", "one region vs an empty list"),
        ("closed-blur", "closed-one", "blur vs pixelate — the same COUNT, another kind"),
        ("closed-two", "closed-one", "two regions vs one"),
    ):
        diff = changed_pixels(images[tag], images[other])
        boxes = clusters(diff)
        print(f"\n   {what}: {len(diff)} changed pixels in {len(boxes)} clusters:")
        print(describe(boxes, scale, limit=8))
        check(f"{what} changes pixels", bool(diff))
        stray = outside(diff, [INSPECTOR], scale)
        check("and every one of them is inside the inspector", not stray,
              "" if not stray else f"{len(stray)} px elsewhere:\n"
              + describe(clusters(stray), scale))
        top, bottom = extent(diff, scale)
        check("they fit inside one section header (InspectorMetrics.headerHeight)",
              top is not None and len(boxes) == 1 and bottom - top <= SECTION_HEADER_H,
              f"{len(boxes)} cluster(s), y {top}–{bottom} pt")
        if header_band is None:
            header_band = (top, bottom)
        else:
            check("and in the same band as the first — one section, not three",
                  None not in (top, header_band[0]) and abs(top - header_band[0]) <= 1,
                  f"y {top} pt vs {header_band[0]} pt")

    # 6. The Obscure section, open — the ROWS.
    print("\n6. the Obscure section, open — the rows grow with the list")
    closed = changed_pixels(images["closed-two"], images["closed-one"])
    diff = changed_pixels(images["open-two"], images["open-one"])
    boxes = clusters(diff)
    print(f"      {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=10))
    check("a second region changes pixels with the section open", bool(diff))
    stray = outside(diff, [INSPECTOR], scale)
    check("every one of them is inside the inspector", not stray,
          "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
    check("and far more of them than the closed section moved — that is the rows",
          len(diff) > 20 * len(closed),
          f"{len(diff)} px open vs {len(closed)} px closed "
          f"({len(diff) / max(len(closed), 1):.0f}×)")
    top, _ = extent(diff, scale)
    check("the change begins at the section header, so nothing above it moved",
          None not in (top, header_band[0]) and abs(top - header_band[0]) <= 1,
          f"first changed row y {top} pt; the header's summary is at "
          f"{header_band[0]} pt")
    scores = shift_match(images["open-one"], images["open-two"], SHIFT_BAND)
    best, runner = scores[0], scores[1]
    print(f"      best shifts (mismatched rows, points): {scores[:4]}")
    check("the content below is the one-region render pushed DOWN by six rows",
          best[1] == REGION_HEIGHT and best[0] * 4 < runner[0],
          f"{best[1]} pt at {best[0]} mismatched rows of {int(200 * scale)}; next best "
          f"{runner[1]} pt at {runner[0]}. Six rows = {REGION_ROWS} × "
          f"(DS.controlHeight {CONTROL_H} + InspectorMetrics.rowSpacing {ROW_SPACING}) "
          f"= {REGION_HEIGHT} pt")

    # Crops for the eye check.
    for tag in ("plain-a", "cand"):
        for rect in WASH:
            images[tag].crop(
                rect, os.path.join(CHROME, f"crop-{tag}-{rect.name.replace(' ', '-')}.png"))
    section = Rect(
        "section", INSPECTOR_X, (header_band[0] or INSPECTOR.y0 + 8) - 8, INSPECTOR_W, 260)
    for tag in ("closed-none", "closed-one", "closed-two", "open-one", "open-two"):
        images[tag].crop(section, os.path.join(CHROME, f"crop-{tag}-obscure.png"))
    print(f"\nPNGs and crops are in {os.path.relpath(CHROME, ROOT)}/")

    passed = sum(RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed")
    sys.exit(0 if passed == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
