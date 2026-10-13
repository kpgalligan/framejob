#!/usr/bin/env python3
"""Road map 2, phase 2 (clip identity) — the CHROME half of the proof.

The claim under test is the road map's "a renamed clip shows its name in the
three places at once — selection block, Clip header, name strip — in an
offscreen render", plus the label dot being a badge and never a tint, and the
track header's S lighting for a soloed track. No running app is needed: the
offscreen harness (`tools/proof/harness/`, CLAUDE.md's "Seeing the chrome")
renders a package from disk, and every claim here is a BYTE comparison of two
PNGs it wrote — a diff of pixels, then where those pixels landed measured
against rectangles derived from the app's own layout constants.

The packages are written BY HAND (a `.framejob` is a directory holding
`project.json`, spec §5.2) around one TEXT clip, so nothing loads
asynchronously and every render is deterministic — no media at all:

    identity-v2        version 2, no name/label/solo keys (the fallback)
    identity-plain     version 3, name null, label null, solo false
    identity-named     name "Intro"
    identity-labelled  name "Intro", label "blue"
    identity-labelled-red  name "Intro", label "red" — the same dots, the other ink
    identity-solo      the track soloed

Run it from anywhere; it builds the harness if it is stale:

    python3 tools/proof/phase2_chrome.py

The last line is `<n>/<n> checks passed` and the exit status is non-zero if
any failed. The PNGs stay in `tools/proof/work/chrome/` (with crops of the
three places for an eye check), and the changed-pixel clusters of every
comparison are printed as bounding boxes so a reader can see where a diff
landed without opening anything.
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
CHROME = os.path.join(WORK, "chrome")
BUILD = os.path.join(HERE, "harness", "build.sh")

# ---------------------------------------------------------------------------
# Geometry, in POINTS, from the app's layout constants. Each number names the
# Swift constant it mirrors; the harness renders a 1440 x 862 window and the
# PNG's width / 1440 is the backing scale (2 on a Retina Mac).

WIDTH, HEIGHT = 1440, 862
TOOLBAR = 44            # DS.toolbarHeight
TAB = 32                # DS.tabHeight — the inspector's tab strip
INSPECTOR_W = 304       # DS.panelWidth = EditorViewController.defaultInspectorWidth
TIMELINE_H = 300        # EditorViewController.defaultTimelineHeight
BAR_H = 36              # DS.timelineBarHeight
RULER_H = 22            # DS.rulerHeight
HEADER_W = 132          # DS.trackHeaderWidth
LANES_INSET = 4         # TimelineLayout.lanesInset
TEXT_LANE_M = 44        # DS.trackHeights[1][0] — a text lane at M
ZOOM = 42               # TimelineLayout.defaultZoom, points per second
BODY_INSET = 3          # TimelineContentView.bodyRect
STRIP_H = 16            # DS.clipHeaderHeight
BLOCK_X, BLOCK_W = 12, 176          # TimelineBar.padding, TimelineSelectionBlock.width
CLIP_HEADER_H = 44                  # ClipSelectionHeaderView.height
CLIP_SECONDS = 5

INSPECTOR_X = WIDTH - INSPECTOR_W               # 1136 (the 1 pt divider is left of it)
TIMELINE_Y = HEIGHT - TIMELINE_H                # 562
LANES_TOP = TIMELINE_Y + BAR_H + RULER_H + LANES_INSET   # 624
CLIP_X0 = HEADER_W                              # time zero sits at x == headerWidth
CLIP_X1 = HEADER_W + ZOOM * CLIP_SECONDS        # 342
STRIP_Y = LANES_TOP + BODY_INSET                # 627
# TimelineHeaderView.buttonRect(3, height:): x = 6 + 3 * (17 + 3), y = min(max(h-19, 16), max(h-17, 0))
SOLO_X = 6 + 3 * (17 + 3)
SOLO_Y = LANES_TOP + min(max(TEXT_LANE_M - 19, 16), max(TEXT_LANE_M - 17, 0))


class Rect:
    def __init__(self, name, x, y, w, h):
        self.name, self.x0, self.y0, self.x1, self.y1 = name, x, y, x + w, y + h

    def contains(self, x, y, scale, slop=0):
        return (self.x0 - slop) * scale <= x < (self.x1 + slop) * scale \
            and (self.y0 - slop) * scale <= y < (self.y1 + slop) * scale

    def __str__(self):
        return f"{self.name} x {self.x0}–{self.x1} y {self.y0}–{self.y1} pt"


RECTS = {
    # The three places a clip's name shows.
    "selection block": Rect("selection block", BLOCK_X, TIMELINE_Y, BLOCK_W, BAR_H),
    "clip header": Rect("clip header", INSPECTOR_X, TOOLBAR + TAB, INSPECTOR_W, CLIP_HEADER_H),
    "name strip": Rect("name strip", CLIP_X0, STRIP_Y, CLIP_X1 - CLIP_X0, STRIP_H),
    # Where a label dot goes: the strip's right end and the header's right end.
    # The header's pane is 304 less the 16 pt legacy scroller the harness pins
    # (`AppleShowScrollBars = Always`), so its dot sits at x 1408–1414 and the
    # name field's trailing edge steps from 1414 to 1402 to make room for it.
    "strip right end": Rect("strip right end", CLIP_X1 - 42, STRIP_Y, 42, STRIP_H),
    "header right end": Rect("header right end", WIDTH - 60, TOOLBAR + TAB, 60, CLIP_HEADER_H),
    # Regions a change may or may not be confined to.
    "track header column": Rect(
        "track header column", 0, TIMELINE_Y + BAR_H + RULER_H, HEADER_W,
        HEIGHT - (TIMELINE_Y + BAR_H + RULER_H)),
    "timeline lanes": Rect(
        "timeline lanes", HEADER_W, TIMELINE_Y + BAR_H + RULER_H, WIDTH - HEADER_W,
        HEIGHT - (TIMELINE_Y + BAR_H + RULER_H)),
    "timeline bar": Rect("timeline bar", 0, TIMELINE_Y, WIDTH, BAR_H),
    "inspector": Rect("inspector", INSPECTOR_X, TOOLBAR, INSPECTOR_W, TIMELINE_Y - TOOLBAR),
    "solo box": Rect("solo box", SOLO_X, SOLO_Y, 17, 17),
}
# The clip body's centre, under the strip and clear of the grips: the tint.
BODY_CENTRE = ((CLIP_X0 + CLIP_X1) // 2, STRIP_Y + STRIP_H + (TEXT_LANE_M - 2 * BODY_INSET - STRIP_H) // 2)


# ---------------------------------------------------------------------------
# Packages, by hand (spec §5.2). One text clip, 0–5 s, on one track.

TICKS_PER_SECOND = 600_000


def project_json(version, name, label, solo):
    track = {"id": 1, "name": "Track 1", "hidden": False, "muted": False, "locked": False}
    clip = {
        "id": 2, "track": 1, "start": 0, "duration": CLIP_SECONDS * TICKS_PER_SECOND,
        "source": {"kind": "text"},
        "enabled": {"video": True, "audio": True},
        "speed": 1.0,
        "video": {
            "x": 0.0, "y": 0.0, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
            "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
            "corner_radius": 0.0, "shadow": None,
            "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
            "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        },
        "audio": None,
        "text": {
            "content": "Hello", "font": "SourceSans3-SemiBold", "size": 72.0,
            "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
            "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": None,
            "width": None,
        },
        "shape": None, "actions": [], "transition_in": None,
    }
    if version >= 3:
        # Version 3's three keys, at the END of their objects (the contract).
        track["solo"] = solo
        clip["name"] = name
        clip["label"] = label
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
    "identity-v2": dict(version=2, name=None, label=None, solo=False),
    "identity-plain": dict(version=3, name=None, label=None, solo=False),
    "identity-named": dict(version=3, name="Intro", label=None, solo=False),
    "identity-labelled": dict(version=3, name="Intro", label="blue", solo=False),
    "identity-labelled-red": dict(version=3, name="Intro", label="red", solo=False),
    "identity-solo": dict(version=3, name=None, label=None, solo=True),
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


def render(binary, package, out, select=0):
    args = [binary, package, out, "light", str(WIDTH), str(HEIGHT), str(select), "0", "1", "clip"]
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


def mean_colour(image, pixels):
    """The mean (R, G, B) of `image` over `pixels`, or None when there are none."""
    if not pixels:
        return None
    total = [0, 0, 0]
    for x, y in pixels:
        value = image.pixel(x, y)
        for i in range(3):
            total[i] += value[i]
    return tuple(t // len(pixels) for t in total)


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


def main():
    os.makedirs(CHROME, exist_ok=True)
    binary = build_harness()
    packages = {name: write_package(name, spec) for name, spec in PACKAGES.items()}
    print("packages:", ", ".join(os.path.relpath(p, ROOT) for p in packages.values()))

    def png(tag):
        return os.path.join(CHROME, tag + ".png")

    start = time.time()
    renders = {
        "plain-a": render(binary, packages["identity-plain"], png("plain-a")),
        "plain-b": render(binary, packages["identity-plain"], png("plain-b")),
        "plain-noselect": render(binary, packages["identity-plain"], png("plain-noselect"), select=-1),
        "v2": render(binary, packages["identity-v2"], png("v2")),
        "named": render(binary, packages["identity-named"], png("named")),
        "labelled": render(binary, packages["identity-labelled"], png("labelled")),
        "labelled-red": render(binary, packages["identity-labelled-red"], png("labelled-red")),
        "solo": render(binary, packages["identity-solo"], png("solo")),
    }
    print(f"rendered {len(renders)} PNGs in {time.time() - start:.1f} s")

    start = time.time()
    images = {tag: Image(path) for tag, path in renders.items()}
    scale = images["plain-a"].scale
    print(f"decoded {len(images)} PNGs in {time.time() - start:.1f} s; "
          f"{images['plain-a'].width}x{images['plain-a'].height} "
          f"{images['plain-a'].channels}-channel, scale {scale:g}")
    print("rectangles (points):")
    for rect in RECTS.values():
        print(f"   {rect}")
    print(f"   body centre ({BODY_CENTRE[0]}, {BODY_CENTRE[1]}) pt")

    # 1. Determinism.
    print("\n1. determinism — plain rendered twice")
    if same_file(renders["plain-a"], renders["plain-b"]):
        check("plain twice → byte-identical PNGs", True)
    else:
        diff = changed_pixels(images["plain-a"], images["plain-b"])
        check("plain twice → byte-identical PNGs", not diff,
              ("the PNG bytes differ but every pixel is the same" if not diff else
               f"{len(diff)} pixels differ:\n" + describe(clusters(diff), scale)))
    plain = images["plain-a"]

    # 2. A version-2 file renders exactly like its version-3 spelling.
    print("\n2. v2 == plain — the fallback is the old behaviour")
    if same_file(renders["v2"], renders["plain-a"]):
        check("v2 vs plain → byte-identical PNGs", True)
    else:
        diff = changed_pixels(images["v2"], plain)
        check("v2 vs plain → byte-identical PNGs", not diff,
              ("the PNG bytes differ but every pixel is the same" if not diff else
               f"{len(diff)} pixels differ:\n" + describe(clusters(diff), scale)))

    # 3. Calibration, then the rename.
    print("\n3a. calibration — plain with and without a selection")
    diff = changed_pixels(images["plain-noselect"], plain)
    boxes = clusters(diff)
    print(f"      {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=20))
    three = [RECTS["selection block"], RECTS["clip header"], RECTS["name strip"]]
    for rect in three:
        hit = inside(diff, rect, scale)
        check(f"selecting the clip changes pixels inside the {rect.name}", bool(hit),
              f"{len(hit)} px inside {rect}")

    print("\n3b. named vs plain — the name in three places at once")
    diff = changed_pixels(images["named"], plain)
    boxes = clusters(diff)
    print(f"      {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=20))
    check("renaming changes pixels somewhere", bool(diff))
    for rect in three:
        hit = inside(diff, rect, scale)
        check(f"the rename shows in the {rect.name}", bool(hit), f"{len(hit)} px inside {rect}")
    stray = outside(diff, three, scale)
    check("and nowhere else", not stray,
          "" if not stray else f"{len(stray)} px outside the three:\n" + describe(clusters(stray), scale))

    # 4. The label is a dot at two right ends and never a tint.
    print("\n4. labelled vs named — a dot, not a tint")
    diff = changed_pixels(images["labelled"], images["named"])
    boxes = clusters(diff)
    print(f"      {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=20))
    for key in ("strip right end", "header right end"):
        hit = inside(diff, RECTS[key], scale)
        check(f"the label changes the {key}", bool(hit), f"{len(hit)} px inside {RECTS[key]}")
    allowed = [RECTS["timeline lanes"], RECTS["clip header"]]
    stray = outside(diff, allowed, scale)
    check("nothing changes outside the timeline lanes and the clip header", not stray,
          "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))
    cx, cy = int(BODY_CENTRE[0] * scale), int(BODY_CENTRE[1] * scale)
    a, b = images["labelled"].pixel(cx, cy), images["named"].pixel(cx, cy)
    patch = [(x, y) for x, y in diff if abs(x - cx) <= 10 * scale and abs(y - cy) <= 6 * scale]
    check("the clip body's centre pixel is identical (the tint stays the kind's)",
          a == b and not patch,
          f"({cx}, {cy}) px = RGBA {a} in both; {len(patch)} changed px within ±10x6 pt of it")

    # 4b. The label's VALUE reaches both dots. A build that painted every
    # label in one ink would pass 4 unchanged — a dot would still appear at
    # both right ends — so the same clip labelled red is rendered too: the
    # two renders must differ at each right end, in nothing else, and the
    # pixels that differ must read bluer under "blue" and redder under "red".
    print("\n4b. labelled-red vs labelled — the dot carries the label's colour")
    diff = changed_pixels(images["labelled-red"], images["labelled"])
    boxes = clusters(diff)
    print(f"      {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=20))
    ends = [RECTS["strip right end"], RECTS["header right end"]]
    check("red vs blue changes pixels somewhere", bool(diff))
    for rect in ends:
        hit = inside(diff, rect, scale)
        check(f"the colour changes the {rect.name}", bool(hit), f"{len(hit)} px inside {rect}")
        blue, red = mean_colour(images["labelled"], hit), mean_colour(images["labelled-red"], hit)
        check(f"and there it reads bluer under blue and redder under red",
              blue is not None and blue[2] > blue[0] and red[0] > red[2],
              f"mean RGB over those px: blue {blue}, red {red}")
    stray = outside(diff, ends, scale)
    check("and nothing else changes", not stray,
          "" if not stray else f"{len(stray)} px elsewhere:\n" + describe(clusters(stray), scale))

    # 5. Solo lights the S box and nothing else.
    print("\n5. solo vs plain — the S box lit")
    diff = changed_pixels(images["solo"], plain)
    boxes = clusters(diff)
    print(f"      {len(diff)} changed pixels in {len(boxes)} clusters:")
    print(describe(boxes, scale, limit=20))
    check("soloing changes pixels somewhere", bool(diff))
    column = RECTS["track header column"]
    stray = outside(diff, [column], scale)
    check("every changed pixel is inside the track header column", not stray,
          "" if not stray else f"{len(stray)} px outside:\n" + describe(clusters(stray), scale))
    for key in ("timeline lanes", "timeline bar", "inspector"):
        hit = inside(diff, RECTS[key], scale)
        check(f"none in the {key}", not hit, f"{len(hit)} px inside {RECTS[key]}")
    box = RECTS["solo box"]
    beyond = outside(diff, [box], scale, slop=1)
    check("and they lie within the S box (±1 pt)", not beyond,
          f"{box}; {len(beyond)} px beyond it")

    # Crops for the eye check.
    for tag in ("named", "labelled", "labelled-red", "solo"):
        for key in ("selection block", "clip header", "name strip", "track header column"):
            images[tag].crop(RECTS[key], os.path.join(CHROME, f"crop-{tag}-{key.replace(' ', '-')}.png"))
    print(f"\nPNGs and crops are in {os.path.relpath(CHROME, ROOT)}/")

    passed = sum(RESULTS)
    print(f"\n{passed}/{len(RESULTS)} checks passed")
    sys.exit(0 if passed == len(RESULTS) else 1)


if __name__ == "__main__":
    main()
