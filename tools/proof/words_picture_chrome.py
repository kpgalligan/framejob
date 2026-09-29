#!/usr/bin/env python3
"""Word captions, the inspector's two items offscreen: road map 8's W3 (§10.7).

The Text inspector gained two things in W3, and both are CHROME: the Style
section's UPPERCASE checkbox (`case`), and what a word-styled page does to two
sections — the Animation section's three rows greyed with the sentence "Word
style wins; the reveal does not apply.", and the Content
section's footnote "Not timed — regenerate to time it again" on a styled page
whose `words` is empty. This script photographs them through
`tools/proof/harness/` (the root CLAUDE.md's "Seeing the chrome") and compares
PNGs pixel by pixel.

    python3 tools/proof/words_picture_chrome.py

Four packages of ONE text clip, "TITLE 2026" — already capitals, so switching
`case` cannot move a glyph or the canvas overlay's handles and every changed
pixel is the inspector's:

  title    as_written, no style
  upper    case: upper
  styled   a colour-only word_style (nothing can pop, so the box is the
           title's) and two timed words
  untimed  the styled page with words: []

CONTROL  title rendered twice is identical;
then title vs upper, title vs styled and styled vs untimed each differ, and
every differing pixel is inside the inspector column (x ≥ width − 304 pt).

Run it AFTER anything that builds `tools/proof/harness`, never beside it.
"""

import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work", "chrome-words")
BUILD = os.path.join(HERE, "harness", "build.sh")
WIDTH, HEIGHT = 1440, 1600
INSPECTOR_W = 304        # DS.panelWidth
EXPAND = "text.content,text.style,text.animation"

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


# ---- PNG, in pure Python (phase4_chrome.py's) -----------------------------


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
        sys.exit(f"{path}: {depth}-bit or interlaced")
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


class Image:
    def __init__(self, path):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)
        self.scale = self.width / WIDTH


def changed_pixels(a, b):
    """Every (x, y) whose bytes differ — `e2_chrome.py`'s XOR walk."""
    if (a.width, a.height, a.channels) != (b.width, b.height, b.channels):
        return None
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


# ---- the fixtures and the harness -----------------------------------------


def package(name, text):
    path = os.path.join(WORK, f"{name}.reelcut")
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    document = {
        "version": 9,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [], "tracks": [{"id": 1, "name": "Text"}],
        "clips": [{"id": 10, "track": 1, "start": 0, "duration": 3 * 600_000,
                   "source": {"kind": "text"}, "video": {}, "text": text}],
        "markers": [], "nests": [], "next_id": 20,
    }
    with open(os.path.join(path, "project.json"), "w", encoding="utf-8") as stream:
        json.dump(document, stream)
    return path


def fixtures():
    title = {"content": "TITLE 2026", "size": 96}
    style = {"mode": "highlight", "active_color": [1.0, 0.85, 0.0, 1.0]}
    timed = [{"start": 0, "end": 300_000}, {"start": 300_000, "end": 600_000}]
    return {
        "title": package("title", title),
        "upper": package("upper", dict(title, case="upper")),
        "styled": package("styled", dict(title, words=timed, word_style=style)),
        "untimed": package("untimed", dict(title, words=[], word_style=style)),
    }


def build_harness():
    began = time.time()
    result = subprocess.run([BUILD], capture_output=True, text=True, timeout=900)
    if result.returncode != 0:
        return None, (result.stdout + result.stderr).strip()[-400:]
    binary = result.stdout.strip().splitlines()[-1]
    print(f"harness: {binary} ({time.time() - began:.1f} s)")
    return binary, None


def render(binary, package_path, out):
    args = [binary, package_path, out, "light", str(WIDTH), str(HEIGHT), "0", "1", "1",
            "clip", "-", EXPAND]
    result = subprocess.run(args, capture_output=True, text=True, timeout=300)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return Image(out), None


def compare(renders, a, b, name):
    if a not in renders or b not in renders:
        check(name, False, "a render is missing")
        return
    diff = changed_pixels(renders[a], renders[b])
    if diff is None:
        check(name, False, "the two renders differ in shape")
        return
    scale = renders[a].scale
    left = (WIDTH - INSPECTOR_W) * scale
    outside = [p for p in diff if p[0] < left]
    box = None
    if diff:
        xs = [p[0] for p in diff]
        ys = [p[1] for p in diff]
        box = (min(xs) / scale, min(ys) / scale, (max(xs) + 1) / scale, (max(ys) + 1) / scale)
    check(name, bool(diff) and not outside,
          f"{len(diff)} changed pixels, bounding box {box} pt, {len(outside)} left of "
          f"x = {WIDTH - INSPECTOR_W} pt")


def main():
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    print("W3 chrome — UPPERCASE, the greyed Reveal and the untimed footnote")
    packages = fixtures()
    binary, error = build_harness()
    check("the harness builds over app/Sources", binary is not None, error or "")
    renders = {}
    if binary:
        for tag in ("title", "upper", "styled", "untimed"):
            image, error = render(binary, packages[tag], os.path.join(WORK, f"{tag}.png"))
            if error:
                check(f"the {tag} fixture renders", False, error)
            else:
                renders[tag] = image
        again, error = render(binary, packages["title"], os.path.join(WORK, "title-again.png"))
        if error:
            check("the title fixture renders a second time", False, error)
        else:
            renders["title-again"] = again
    if "title" in renders and "title-again" in renders:
        diff = changed_pixels(renders["title"], renders["title-again"])
        check("CONTROL: the title rendered twice is identical", diff == [],
              f"{'shape differs' if diff is None else len(diff)} changed pixels")
    else:
        check("CONTROL: the title rendered twice is identical", False, "a render is missing")
    compare(renders, "title", "upper",
            "title vs UPPERCASE differs, only inside the inspector column")
    compare(renders, "title", "styled",
            "title vs styled (Reveal greyed, the word-style note) differs, only in the inspector")
    compare(renders, "styled", "untimed",
            "styled vs words [] (the untimed footnote) differs, only in the inspector")
    print(f"{passed}/{passed + failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
