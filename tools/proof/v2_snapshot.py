#!/usr/bin/env python3
"""Road map 11's V2a — `snapshot_ui`, proved against the running app.

    python3 tools/proof/v2_snapshot.py <port> [--log PATH] [--only LETTERS]

`--only` takes row letters (`T,N,O,C,F,A,L,P`); omitted, every row runs. The
app is the Release build on `<port>`, launched with the pinned defaults of the
V2a spec's Verification (`-ReelcutInspectorWidth 304 -ReelcutTimelineHeight
300 …`), fresh for each run; `--log` defaults to `/tmp/reelcut-<port>.log`.

**The cover.** The O rows and F0 put an opaque, non-activating panel
(`v2_cover.swift`, built here) over the editor window's frame so the editor
reads OCCLUDED, and capture it there. The panel is at floating level and
covers that region of the person's screen for the episode, each under 60 s.
**Keep the pointer off the Reelcut window while this runs**, and expect the
grey rectangle; nothing is ever activated. A locked console skips the O rows
and F0 by name.

Before the first MCP call the script writes its two fixtures
(`work/v2_snapshot/fixtures/{v2well,note}.reelcut`, version 10) and builds the
layout probe (`v2_layout_probe.swift` over `harness/build.sh`'s swiftc line)
and the cover; a build that fails is a scored FAIL of the rows that need it.
Every child is bounded (`graphics_spike/bounded.py`) and only this script's
own children are ever killed.

Rows print as `<ID> <pass|fail|skip> <I|C|A> — <reason>`, then `scores:` and
`digest:` (sha256 of the sorted `ID=state` lines). Exit 0 iff no row failed.
Byte rows compare PNG files; pixel rows decode only preview-region captures.
Two captures whose `scale`, `active`, `key` or `color_space` differ are never
compared: that row is a named host skip.

L2 compares the dump's `problems` to `KNOWN`, the FILED layout defects (each
named by its issue): it fails on a problem not listed and on a listed defect
that no longer appears. The tool itself exempts nothing. Pixel thresholds are
for colour-managed captures (see `yellow`).
"""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
from dev_tools import DEV_TOOLS, dev_marker_count  # noqa: E402
from mcp import MCP, ToolError  # noqa: E402
from media_less_playback_probe import console_locked  # noqa: E402

WORK = os.path.join(HERE, "work", "v2_snapshot")
FIXTURES = os.path.join(WORK, "fixtures")
PNG = os.path.join(WORK, "png")
PROBE_DIR = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
TICKS = 600_000
PLAYHEAD = 600_000
WELL = os.path.join(FIXTURES, "v2well.reelcut")
NOTE = os.path.join(FIXTURES, "note.reelcut")
PROPERTIES = {"window", "view", "appearance", "path", "fill_preview", "layout", "project"}
REGIONS = ["toolbar", "preview", "inspector", "timeline"]
EPISODE = 60

# L2's known defects: problems the layout dump reports on v2well (nothing
# selected, whole window) that are FILED, each named by its issue. The tool
# still reports them; L2 fails on any problem not matched here AND on a listed
# defect that no longer appears, so a fix forces this list to shrink. Each
# entry matches kind, class, the view's text and its frame (capture points).
# #129 was measured the same — frame [367, 15, 90, 14], overhang
# [0, 0, 2, 0] — at content widths 900–1440 pt (the window's minimum is 900)
# on a scale-1 and a scale-2 screen, so it does not depend on either.
KNOWN = {
    "#129": {"kind": "outside_superview", "class": "NSTextField",
             "text": "/ 00:00:06:00", "frame": [367, 15, 90, 14]},
}

ROWS = [("T1", "I"), ("T2", "C"), ("N1", "A"), ("O0", "I"), ("O1", "A"), ("O2", "A"),
        ("O3", "A"), ("O5", "A"), ("C1", "A"), ("C2", "A"), ("C3", "A"), ("C4", "A"),
        ("C5", "A"), ("F0", "A"), ("F1", "A"), ("F2", "A"), ("F3", "A"), ("F4", "A"),
        ("A1", "A"), ("A2", "A"), ("L1", "A"), ("L2", "A"), ("L3", "A"), ("P1", "C"),
        ("P2", "C"), ("P3", "C"), ("P4", "C"), ("P5", "C"), ("P6", "C")]
KIND = dict(ROWS)
states = {}
captures = []


def score(rid, state, reason):
    states[rid] = state
    print(f"{rid} {state} {KIND[rid]} — {reason}", flush=True)


# ---------------------------------------------------------------------------
# Fixtures and builds.


def write_package(path, canvas, clips):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    project = {"version": 10, "canvas": canvas, "media": [],
               "tracks": [{"id": 1, "name": "Track 1"}], "clips": clips, "markers": [],
               "next_id": 6, "nests": []}
    with open(os.path.join(path, "project.json"), "w") as f:
        json.dump(project, f, indent=1)


def shape(clip, start, fill):
    return {"id": clip, "track": 1, "start": start, "duration": 3 * TICKS,
            "source": {"kind": "shape"}, "video": {},
            "shape": {"kind": "rectangle", "width": 320.0, "height": 180.0, "stroke": None,
                      "fill": fill, "arrow_start": False, "arrow_end": False, "radius": 0.0,
                      "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None}}


def make_fixtures():
    """`capture_spike.py:make_fixtures`'s well plus a second shape at 3–6 s,
    and its note."""
    os.makedirs(FIXTURES, exist_ok=True)
    canvas = {"width": 640, "height": 360, "fps": [30, 1], "background": [1.0, 0.0, 1.0, 1.0],
              "fit_new_clips": True}
    write_package(WELL, canvas, [shape(2, 0, [1.0, 1.0, 0.0, 1.0]),
                                 shape(3, 3 * TICKS, [0.0, 1.0, 1.0, 1.0])])
    content = "Every word here is timed"
    tokens = content.split()
    step = 3 * TICKS // len(tokens)
    words = [{"start": i * step, "end": (i + 1) * step - TICKS // 30} for i in range(len(tokens))]
    write_package(NOTE, dict(canvas, background=[0.0, 0.0, 0.0, 1.0]), [{
        "id": 2, "track": 1, "start": 0, "duration": 3 * TICKS, "source": {"kind": "text"},
        "video": {},
        "text": {"content": content, "size": 48.0, "color": [1.0, 1.0, 1.0, 1.0],
                 "words": words, "word_style": {"mode": "highlight"}}}])


def sdk():
    return bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()


def fresh(binary, stamp, argv, inputs):
    return (os.path.exists(binary) and os.path.exists(stamp) and open(stamp).read() == "\n".join(argv)
            and all(os.path.getmtime(f) < os.path.getmtime(binary) for f in inputs))


def compile_once(argv, binary, inputs, seconds, label):
    stamp = binary + ".argv"
    if fresh(binary, stamp, argv, inputs):
        print(f"{label}: {binary} (up to date)", flush=True)
        return binary, None
    if os.path.exists(binary):
        os.remove(binary)
    print(f"{label}: building…", flush=True)
    built = bounded.run(argv, seconds)
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = [line for line in built["stderr"].strip().splitlines()[-3:] if line.strip()]
        return None, (f"{label} did not build: swiftc exited {built['rc']} (expired "
                      f"{built['expired']}): " + " | ".join(errors[:4] or tail or ["no output"]))
    with open(stamp, "w") as f:
        f.write("\n".join(argv))
    print(f"{label}: built in {built['seconds']:.0f} s", flush=True)
    return binary, None


def build_probe():
    if not os.path.exists(LIB):
        return None, f"the probe did not build: {LIB} is missing"
    os.makedirs(PROBE_DIR, exist_ok=True)
    entry = os.path.join(PROBE_DIR, "main.swift")
    source = open(os.path.join(HERE, "v2_layout_probe.swift")).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    swift = sorted(os.path.join(SOURCES, n) for n in os.listdir(SOURCES)
                   if n.endswith(".swift") and n != "main.swift")
    binary = os.path.join(PROBE_DIR, "v2_layout_probe")
    argv = (["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk(), "-target", "arm64-apple-macos26.0",
             "-module-name", "Reelcut", "-import-objc-header",
             os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
             "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary])
    return compile_once(argv, binary, swift + [entry, LIB], 1200, "probe")


def build_cover():
    os.makedirs(WORK, exist_ok=True)
    source = os.path.join(HERE, "v2_cover.swift")
    binary = os.path.join(WORK, "v2_cover")
    argv = ["swiftc", "-sdk", sdk(), "-target", "arm64-apple-macos26.0", source, "-o", binary]
    return compile_once(argv, binary, [source], 600, "cover")


# ---------------------------------------------------------------------------
# PNG, in pure Python — `e1_proof.py:214`'s decoder, copied.


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


def png_size(path):
    with open(path, "rb") as handle:
        head = handle.read(24)
    return struct.unpack(">II", head[16:24])


def differing(a, b):
    """The set of (x, y) whose pixels differ between two decoded PNGs."""
    _, _, _, ch, rows_a = a
    rows_b = b[4]
    out = set()
    for y, (ra, rb) in enumerate(zip(rows_a, rows_b)):
        if ra == rb:
            continue
        for x in range(len(ra) // ch):
            if ra[x * ch:(x + 1) * ch] != rb[x * ch:(x + 1) * ch]:
                out.add((x, y))
    return out


# ---------------------------------------------------------------------------
# The tool.


def snap(mcp, **arguments):
    """One `snapshot_ui` call: the parsed text block, plus `_image` (the image
    block) and `_bytes` (the PNG file) for a capture."""
    result = mcp._request("tools/call", {"name": "snapshot_ui", "arguments": arguments})
    content = result.get("content", [])
    text = "".join(p.get("text", "") for p in content if p.get("type") == "text")
    if result.get("isError"):
        raise ToolError(f"snapshot_ui: {text}")
    answer = json.loads(text)
    image = next((p for p in content if p.get("type") == "image"), None)
    if image is not None:
        answer["_image"] = image
        with open(answer["path"], "rb") as f:
            answer["_bytes"] = f.read()
        captures.append(answer)
    return answer


def shot(mcp, name, **arguments):
    return snap(mcp, path=os.path.join(PNG, name + ".png"), **arguments)


def refused(mcp, arguments):
    try:
        snap(mcp, **arguments)
    except ToolError as error:
        return str(error)
    return None


def facts_differ(*answers):
    """None when every capture's scale, active, key and colour space agree;
    else the named host condition."""
    for key in ("scale", "active", "key", "color_space"):
        values = [a["window_facts"].get(key) for a in answers]
        if len(set(map(str, values))) > 1:
            return f"host: window_facts.{key} differs between the captures ({values})"
    return None


def same_bytes(a, b):
    return a["_bytes"] == b["_bytes"]


def canonical(path):
    return os.path.realpath(os.path.expanduser(path)) if path else None


def editor_row(listing, fixture):
    for window in listing.get("windows", []):
        if window.get("kind") == "editor" and canonical(window.get("project")) == canonical(fixture):
            return window
    return None


class Cover:
    def __init__(self, binary, frame):
        self.release = os.path.join(WORK, f"release-{os.getpid()}-{time.time():.0f}")
        if os.path.exists(self.release):
            os.remove(self.release)
        x, y, w, h = frame
        self.started = time.monotonic()
        self.child = bounded.Background(
            [binary, str(x), str(y), str(w), str(h), str(EPISODE), self.release], EPISODE + 10)
        self.up = False
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and not self.up:
            self.up = any(line == "UP" for _, line in self.child.lines)
            time.sleep(0.05)

    def finish(self):
        with open(self.release, "w") as f:
            f.write("release\n")
        done = self.child.finish()
        os.remove(self.release)
        return round(time.monotonic() - self.started, 1), done


def wait_occluded(mcp, fixture, wanted, seconds=5.0):
    deadline = time.monotonic() + seconds
    row = None
    while time.monotonic() < deadline:
        row = editor_row(snap(mcp), fixture)
        if row is not None and row.get("occluded") == wanted:
            return row
        time.sleep(0.1)
    return row


# ---------------------------------------------------------------------------
# The rows.


def rows_t(mcp, log):
    tools = mcp.schemas()
    tool = tools.get("snapshot_ui")
    if tool is None:
        score("T1", "fail", "snapshot_ui is not in tools/list")
    else:
        schema = tool["inputSchema"]
        props = set(schema.get("properties", {}))
        parity = []
        if os.path.exists(log):
            parity = [line for line in open(log, errors="replace") if "Reelcut: " in line]
        marker = dev_marker_count(log)
        ok = (props == PROPERTIES and schema.get("required", []) == [] and "scope" not in props
              and os.path.exists(log) and parity == [] and marker == len(DEV_TOOLS))
        score("T1", "pass" if ok else "fail",
              f"properties {sorted(props)}, required {schema.get('required')}, scope "
              f"{'scope' in props}; `Reelcut: ` lines {len(parity)} in {log}; marker count "
              f"{marker} (want {len(DEV_TOOLS)})")
    stranger = "v2_stranger_key"
    try:
        mcp.call_with("snapshot_ui", {stranger: 1})
        score("T2", "fail", "a stranger key was accepted")
    except ToolError as error:
        text = str(error)
        score("T2", "pass" if stranger in text else "fail", f"refused: {text[:160]!r}")


def open_well(mcp):
    mcp.call_with("open_project", {"path": WELL})
    mcp.call_with("set_playhead", {"project": WELL, "t": PLAYHEAD})
    mcp.call_with("set_selection", {"project": WELL, "clips": []})


def rows_n(mcp):
    listing = snap(mcp)
    row = editor_row(listing, WELL)
    keys = ["frame", "content", "scale", "occluded"]
    ok = row is not None and all(k in row for k in keys) and isinstance(listing.get("active"), bool)
    score("N1", "pass" if ok else "fail",
          f"editor for {os.path.basename(WELL)}: "
          + (f"frame {row['frame']}, content {row['content']}, scale {row['scale']}, occluded "
             f"{row['occluded']}" if row else "not listed")
          + f"; active {listing.get('active')}; {len(listing.get('windows', []))} windows")


def rows_o(mcp, cover_binary, cover_error):
    ids = ["O0", "O1", "O2", "O3"]
    if console_locked():
        for rid in ids:
            score(rid, "skip", "host: console locked")
        return
    if cover_binary is None:
        for rid in ids:
            score(rid, "fail", cover_error)
        return
    listing = snap(mcp)
    row = editor_row(listing, WELL)
    if row is None:
        for rid in ids:
            score(rid, "fail", "the v2well editor is not in the listing")
        return
    before = shot(mcp, "o_before", window="editor", project=WELL)
    cover = Cover(cover_binary, row["frame"])
    try:
        covered_row = wait_occluded(mcp, WELL, True) if cover.up else None
        o0 = cover.up and covered_row is not None and covered_row.get("occluded") is True
        score("O0", "pass" if o0 else "fail",
              f"cover up {cover.up} over {row['frame']}; listing occluded "
              f"{covered_row.get('occluded') if covered_row else None}")
        if not o0:
            for rid in ["O1", "O2", "O3"]:
                score(rid, "fail", "O0 failed: the editor did not read occluded under the cover")
            return
        c1 = shot(mcp, "o_covered1", window="editor", project=WELL)
        c2 = shot(mcp, "o_covered2", window="editor", project=WELL)
        regions_before = {r: shot(mcp, f"o_{r}_before", window="editor", project=WELL, view=r)
                          for r in REGIONS}
        mcp.call_with("set_selection", {"project": WELL, "clips": [3]})
        regions_after = {r: shot(mcp, f"o_{r}_after", window="editor", project=WELL, view=r)
                         for r in REGIONS}
        mcp.call_with("set_selection", {"project": WELL, "clips": []})
    finally:
        seconds, _ = cover.finish()
    print(f"   (cover episode {seconds} s)", flush=True)

    content = row["content"]
    want = [round(content[0] * c1["scale"]), round(content[1] * c1["scale"])]
    got = [c1["width_px"], c1["height_px"]]
    differ = facts_differ(c1, c2)
    occluded = [c["window_facts"]["occluded"] for c in (c1, c2)]
    if differ:
        score("O1", "skip", differ)
    else:
        ok = (same_bytes(c1, c2) and c1["settled"] and c2["settled"] and got == want
              and occluded == [True, True])
        score("O1", "pass" if ok else "fail",
              f"byte-identical {same_bytes(c1, c2)}, settled {c1['settled']}/{c2['settled']} "
              f"(passes {c1['passes']}/{c2['passes']}), {got[0]}×{got[1]} px vs content × scale "
              f"{want[0]}×{want[1]}, occluded {occluded}")

    wait_occluded(mcp, WELL, False, 3.0)
    after = shot(mcp, "o_after", window="editor", project=WELL)
    references = [(name, c) for name, c in (("before", before), ("after", after))
                  if c["window_facts"]["occluded"] is False]
    if not references:
        score("O2", "skip", "host: editor occluded without the cover (occluded before "
                            f"{before['window_facts']['occluded']}, after "
                            f"{after['window_facts']['occluded']})")
    else:
        name, reference = references[0]
        differ = facts_differ(c1, reference)
        if differ:
            score("O2", "skip", differ)
        else:
            ok = same_bytes(c1, reference)
            score("O2", "pass" if ok else "fail",
                  f"covered capture vs the uncovered one {name} (occluded False): byte-identical "
                  f"{ok}")

    differ = facts_differ(*regions_before.values(), *regions_after.values())
    if differ:
        score("O3", "skip", differ)
    else:
        same = {r: same_bytes(regions_before[r], regions_after[r]) for r in REGIONS}
        ok = (same["toolbar"] and same["preview"] and not same["inspector"]
              and not same["timeline"])
        score("O3", "pass" if ok else "fail",
              "set_selection [3] while covered — byte-identical before/after: "
              + ", ".join(f"{r} {same[r]}" for r in REGIONS)
              + " (want toolbar, preview True; inspector, timeline False)")


def rows_c(mcp):
    a = shot(mcp, "c1_a", window="editor", project=WELL)
    b = shot(mcp, "c1_b", window="editor", project=WELL)
    differ = facts_differ(a, b)
    if differ:
        score("C1", "skip", differ)
    else:
        score("C1", "pass" if same_bytes(a, b) else "fail",
              f"two captures of one state byte-identical {same_bytes(a, b)} "
              f"({len(a['_bytes'])} bytes)")
    block = base64.b64decode(a["_image"]["data"])
    ok = block == a["_bytes"] and a["_image"].get("mimeType") == "image/png"
    score("C2", "pass" if ok else "fail",
          f"image block {len(block)} bytes == file {len(a['_bytes'])} bytes: "
          f"{block == a['_bytes']}, mimeType {a['_image'].get('mimeType')}")

    notes = []
    ok = True
    for region in REGIONS:
        r = shot(mcp, f"c3_{region}", window="editor", project=WELL, view=region)
        rect = r["regions"][region]
        want = (rect[2] * r["scale"], rect[3] * r["scale"])
        got = png_size(r["path"])
        fits = (abs(got[0] - want[0]) <= 1 and abs(got[1] - want[1]) <= 1
                and [got[0], got[1]] == [r["width_px"], r["height_px"]])
        ok = ok and fits
        notes.append(f"{region} {got[0]}×{got[1]} px vs {want[0]:g}×{want[1]:g}")
    score("C3", "pass" if ok else "fail", "; ".join(notes))

    missing = os.path.join(WORK, "no", "such", "folder", "x.png")
    cases = [
        ({"view": "toolbar"}, ["view", "window"]),
        ({"appearance": "dark"}, ["appearance", "-RCDevAppearance"]),
        ({"path": os.path.join(PNG, "x.png")}, ["path", "window"]),
        ({"fill_preview": False}, ["fill_preview", "window"]),
        ({"layout": False}, ["layout", "window"]),
        ({"window": "nope"}, ["window", "editor, sheet, settings, welcome"]),
        ({"window": "editor", "view": "nope"}, ["view", "toolbar, preview, inspector, timeline"]),
        ({"window": "editor", "appearance": "sepia"}, ["appearance", "-RCDevAppearance"]),
        ({"project": WELL}, ["project"]),
        ({"window": "settings", "project": WELL}, ["project", "settings"]),
        ({"window": "welcome", "project": WELL}, ["project", "welcome"]),
        ({"window": "welcome", "view": "toolbar"}, ["view", "welcome"]),
        ({"window": "sheet", "project": WELL}, ["sheet"]),
        ({"window": "editor", "project": WELL, "path": missing}, [os.path.dirname(missing)]),
        ({"window": "editor", "project": "/no/such/v2.reelcut"}, ["/no/such/v2.reelcut"]),
    ]
    bad = []
    for arguments, words in cases:
        text = refused(mcp, arguments)
        if text is None or not all(w.lower() in text.lower() for w in words):
            bad.append(f"{sorted(arguments)} → {text!r}")
    score("C4", "pass" if not bad else "fail",
          f"{len(cases) - len(bad)}/{len(cases)} refusals name their argument or window"
          + (f"; wrong: {bad}" if bad else "")
          + "; not reachable over MCP in V2a: a windowless document, a file-panel sheet")

    listing = snap(mcp)
    notes = []
    ok = True
    for kind in ("welcome", "settings"):
        rows = [w for w in listing["windows"] if w["kind"] == kind]
        text = refused(mcp, {"window": kind})
        if rows:
            if text is not None:
                ok = False
                notes.append(f"{kind} listed but refused: {text!r}")
                continue
            r = shot(mcp, f"c5_{kind}", window=kind)
            want = [round(rows[0]["content"][0] * r["scale"]),
                    round(rows[0]["content"][1] * r["scale"])]
            fits = [r["width_px"], r["height_px"]] == want
            ok = ok and fits
            notes.append(f"{kind} open: {r['width_px']}×{r['height_px']} px vs {want}")
        else:
            named = text is not None and kind in text.lower()
            ok = ok and named
            notes.append(f"{kind} closed: refused {text!r}")
    score("C5", "pass" if ok else "fail", "; ".join(notes))


def box_of(capture):
    s = capture["scale"]
    x, y, w, h = capture["well"]
    x0, x1 = int(-(-((x + w * 7 / 16) * s) // 1)), int(((x + w * 9 / 16) * s) // 1)
    y0, y1 = int(-(-((y + h * 7 / 16) * s) // 1)), int(((y + h * 9 / 16) * s) // 1)
    return x0, y0, x1, y1


def box_stats(capture, predicate):
    x0, y0, x1, y1 = box_of(capture)
    _, _, _, ch, rows = decode_png(capture["path"])
    lo, hi, bad = [255, 255, 255], [0, 0, 0], 0
    for y in range(y0, y1):
        row = rows[y]
        for x in range(x0, x1):
            p = row[x * ch:x * ch + 3]
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
            if not predicate(p):
                bad += 1
    return (x0, y0, x1, y1), lo, hi, bad


# The capture is in the WINDOW's colour space, so the fixture's sRGB yellow
# comes back colour-managed: [252, 254, 48] on a BenQ GW2790QT at scale 1 and
# [255, 255, 84] on the built-in "Color LCD" (Display P3) at scale 2, measured
# for V2a. The spec's B < 60 would fail the second on colour management alone,
# so blue's bound is 100; magenta's G < 60 holds on both (25 and 51).
def yellow(p):
    return p[0] > 200 and p[1] > 200 and p[2] < 100


def magenta(p):
    return p[0] > 200 and p[2] > 200 and p[1] < 60


def row_f0(mcp, cover_binary, cover_error):
    if console_locked():
        score("F0", "skip", "host: console locked")
        return
    if cover_binary is None:
        score("F0", "fail", cover_error)
        return
    row = editor_row(snap(mcp), WELL)
    if row is None:
        score("F0", "fail", "the v2well editor is not in the listing")
        return
    cover = Cover(cover_binary, row["frame"])
    try:
        covered = wait_occluded(mcp, WELL, True) if cover.up else None
        filled = shot(mcp, "f0_filled", window="editor", project=WELL, view="preview")
        unfilled = shot(mcp, "f0_unfilled", window="editor", project=WELL, view="preview",
                        fill_preview=False)
    finally:
        seconds, _ = cover.finish()
    print(f"   (cover episode {seconds} s)", flush=True)
    occluded = [c["window_facts"]["occluded"] for c in (filled, unfilled)]
    if not (covered and covered.get("occluded") is True):
        score("F0", "fail", f"the cover did not occlude the editor (occluded {occluded})")
        return
    if filled.get("well") is None:
        score("F0", "fail", "the preview capture reports no well")
        return
    box, flo, fhi, fbad = box_stats(filled, yellow)
    _, ulo, uhi, ubad = box_stats(unfilled, magenta)
    ok = fbad == 0 and ubad == 0 and occluded == [True, True]
    score("F0", "pass" if ok else "fail",
          f"covered (occluded {occluded}); box px {list(box)} of well {filled['well']} × "
          f"{filled['scale']}; filled RGB min {flo} max {fhi}, {fbad} not yellow; unfilled "
          f"RGB min {ulo} max {uhi}, {ubad} not magenta")


def rows_f(mcp, baseline):
    filled = shot(mcp, "f1_filled", window="editor", project=WELL, view="preview")
    unfilled = shot(mcp, "f1_unfilled", window="editor", project=WELL, view="preview",
                    fill_preview=False)
    timeline = shot(mcp, "f1_timeline", window="editor", project=WELL, view="timeline")
    ok = (filled.get("preview") == "filled" and filled.get("preview_tick") == PLAYHEAD
          and unfilled.get("preview") == "unfilled" and timeline.get("preview") == "not_in_capture"
          and all(c.get("preview_note") for c in (filled, unfilled, timeline)))
    score("F1", "pass" if ok else "fail",
          f"preview {filled.get('preview')} tick {filled.get('preview_tick')}; fill_preview false "
          f"{unfilled.get('preview')}; view timeline {timeline.get('preview')}")

    mcp.call_with("set_selection", {"project": WELL, "clips": [2]})
    sel_u = shot(mcp, "f2_sel_unfilled", window="editor", project=WELL, view="preview",
                 fill_preview=False)
    sel_f = shot(mcp, "f2_sel_filled", window="editor", project=WELL, view="preview")
    mcp.call_with("set_selection", {"project": WELL, "clips": []})
    none_u = shot(mcp, "f2_none_unfilled", window="editor", project=WELL, view="preview",
                  fill_preview=False)
    none_f = shot(mcp, "f2_none_filled", window="editor", project=WELL, view="preview")
    differ = facts_differ(sel_u, sel_f, none_u, none_f)
    if differ:
        score("F2", "skip", differ)
    else:
        marks = differing(decode_png(sel_u["path"]), decode_png(none_u["path"]))
        filled_diff = differing(decode_png(sel_f["path"]), decode_png(none_f["path"]))
        kept = len(marks & filled_diff)
        fraction = kept / len(marks) if marks else 0.0
        score("F2", "pass" if marks and fraction >= 0.5 else "fail",
              f"M {len(marks)} px (clip 2 selected vs not, unfilled); {kept} also differ when "
              f"filled: {fraction:.4f} (want ≥ 0.5)")

    u1 = shot(mcp, "f3_unfilled_before", window="editor", project=WELL, view="preview",
              fill_preview=False)
    shot(mcp, "f3_filled", window="editor", project=WELL, view="preview")
    u2 = shot(mcp, "f3_unfilled_after", window="editor", project=WELL, view="preview",
              fill_preview=False)
    # `baseline` is the run's first capture, taken before ANY filled one: a
    # fill left in by one capture would be in `u1` as well as `u2`, and the
    # two would agree.
    differ = facts_differ(baseline, u1, u2)
    if differ:
        score("F3", "skip", differ)
    else:
        ok = same_bytes(u1, u2) and same_bytes(baseline, u2)
        score("F3", "pass" if ok else "fail",
              f"unfilled after a filled capture byte-identical to the one just before: "
              f"{same_bytes(u1, u2)}, to the run's first capture (before any fill): "
              f"{same_bytes(baseline, u2)}")


def row_f4(mcp):
    mcp.call_with("new_project", {})
    r = shot(mcp, "f4_empty", window="editor")
    ok = r.get("preview") == "no_frame" and os.path.exists(r["path"])
    score("F4", "pass" if ok else "fail",
          f"new_project → preview {r.get('preview')}, file written {os.path.exists(r['path'])}")


def rows_a(mcp):
    """`appearance` is refused, whatever its value (V3): a live switch left
    build-time colours in the launch appearance, so the look is the
    instance's, set at launch with `-RCDevAppearance`."""
    before = shot(mcp, "a_before", window="editor", project=WELL)
    notes, ok = [], True
    for look in ("dark", "light"):
        path = os.path.join(PNG, f"a_{look}.png")
        text = refused(mcp, {"window": "editor", "project": WELL, "appearance": look,
                             "path": path})
        wrote = os.path.exists(path)
        ok = ok and text is not None and "-RCDevAppearance" in text and not wrote
        notes.append(f"{look}: refused {text is not None}, names -RCDevAppearance "
                     f"{text is not None and '-RCDevAppearance' in text}, file written {wrote}")
    score("A1", "pass" if ok else "fail", "; ".join(notes))
    after = shot(mcp, "a_after", window="editor", project=WELL)
    differ = facts_differ(before, after)
    if differ:
        score("A2", "skip", differ)
    else:
        ok = same_bytes(before, after) and before["appearance"] == after["appearance"]
        score("A2", "pass" if ok else "fail",
              f"captures before and after the refusals byte-identical: {same_bytes(before, after)} "
              f"(appearance {before['appearance']} → {after['appearance']})")


def load_layout(capture):
    with open(capture["layout_path"]) as f:
        return json.load(f)


def rows_l(mcp):
    mcp.call_with("set_selection", {"project": WELL, "clips": []})
    r = shot(mcp, "l_well", window="editor", project=WELL)
    try:
        layout = load_layout(r)
        root = layout["views"][0]
        w, h = r["points"]
        ok = (root["parent"] == -1 and root["frame"] == [0, 0, w, h]
              and layout["problems"] == r["problems"]
              and len(layout["private_problems"]) == r["private_problems"])
        score("L1", "pass" if ok else "fail",
              f"{len(layout['views'])} views; root {root['class']} at {root['frame']} vs "
              f"[0, 0, {w}, {h}]; file problems == result's {layout['problems'] == r['problems']}; "
              f"private {len(layout['private_problems'])}")
    except (OSError, ValueError, KeyError, IndexError) as error:
        layout = None
        score("L1", "fail", f"layout file unreadable: {error}")
    problems = r.get("problems", [])
    views = layout["views"] if layout else []
    listed = [{"kind": p["kind"], "class": p["class"],
               "id": views[p["view"]]["id"] if p["view"] < len(views) else None,
               "text": views[p["view"]]["text"] if p["view"] < len(views) else None,
               "frame": p["frame"], "detail": p["detail"]} for p in problems]
    matched, unknown = {}, []
    for entry in listed:
        issue = next((n for n, k in KNOWN.items()
                      if all(entry.get(f) == k[f] for f in ("kind", "class", "text", "frame"))),
                     None)
        if issue is None:
            unknown.append(entry)
        else:
            matched[issue] = matched.get(issue, 0) + 1
    known = [f"{n} {'matched' if n in matched else 'MISSING'}" for n in sorted(KNOWN)]
    ok = not unknown and set(matched) == set(KNOWN) and all(c == 1 for c in matched.values())
    score("L2", "pass" if ok else "fail",
          f"window content {r.get('points')} at scale {r.get('scale')}; {len(problems)} problems, "
          f"{r.get('private_problems')} private; known: {', '.join(known)}; "
          f"{len(unknown)} not known" + (": " + json.dumps(unknown) if unknown else ""))

    note_text = re.search(r'static let wordStyleNote = "([^"]*)"',
                          open(os.path.join(SOURCES, "TextPane.swift")).read())
    note_text = note_text.group(1) if note_text else None
    mcp.call_with("open_project", {"path": NOTE})
    mcp.call_with("set_selection", {"project": NOTE, "clips": []})
    mcp.call_with("set_selection", {"project": NOTE, "clips": [2]})
    n = shot(mcp, "l_note", window="editor", project=NOTE)
    layout = load_layout(n)
    labels = [v for v in layout["views"] if v["class"] == "InspectorNoteLabel"]
    notes = [v for v in labels if v["text"] == note_text]
    if not notes:
        score("L3", "fail", f"note label not in dump: notes_found 0, InspectorNoteLabel views "
                            f"{len(labels)}")
        return
    v = notes[0]
    if v["hidden"]:
        score("L3", "skip", "host: Reveal collapsed")
        return
    if v["intrinsic"][0] <= v["frame"][2] + 0.5:  # the truncation rule's own 0.5 pt tolerance
        score("L3", "skip", f"host: inspector wide enough (intrinsic {v['intrinsic'][0]} ≤ frame "
                            f"{v['frame'][2]})")
        return
    hit = [p for p in n["problems"] if p["kind"] == "truncated" and p["view"] == v["i"]]
    score("L3", "pass" if hit else "fail",
          f"the word-style note #{v['i']}: intrinsic {v['intrinsic'][0]} vs frame {v['frame'][2]}; "
          f"truncated problem {'listed' if hit else 'MISSING'}"
          + (f" ({hit[0]['detail']})" if hit else ""))


def rows_p(probe, probe_error):
    ids = [f"P{i}" for i in range(1, 7)]
    if probe is None:
        for rid in ids:
            score(rid, "fail", probe_error)
        return
    ran = bounded.run([probe], 120, cwd=PROBE_DIR)
    answer = None
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            try:
                answer = json.loads(line[len("ANSWER "):])
            except json.JSONDecodeError:
                answer = None
    for rid in ids:
        if answer is None or rid not in answer:
            score(rid, "fail", f"the probe did not answer (rc {ran['rc']}, expired "
                               f"{ran['expired']}): {ran['stderr'].strip()[-200:]!r}")
        else:
            score(rid, "pass" if answer[rid]["ok"] else "fail", answer[rid]["detail"])


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("port", type=int)
    parser.add_argument("--log")
    parser.add_argument("--only")
    args = parser.parse_args()
    log = args.log or f"/tmp/reelcut-{args.port}.log"
    only = set(args.only.replace(" ", "").split(",")) if args.only else set("TNOCFALP")
    selected = [rid for rid, _ in ROWS if rid[0] in only]

    shutil.rmtree(PNG, ignore_errors=True)
    os.makedirs(PNG)
    make_fixtures()
    probe, probe_error = build_probe() if "P" in only else (None, None)
    cover, cover_error = build_cover() if only & {"O", "F"} else (None, None)
    if "P" in only:
        rows_p(probe, probe_error)

    mcp = MCP(args.port)
    if "T" in only:
        rows_t(mcp, log)
    if only & set("NOCFAL"):
        open_well(mcp)
    baseline = None
    if "F" in only:
        baseline = shot(mcp, "f3_baseline", window="editor", project=WELL, view="preview",
                        fill_preview=False)
    if "N" in only:
        rows_n(mcp)
    if "O" in only:
        rows_o(mcp, cover, cover_error)
    if "C" in only:
        rows_c(mcp)
    if "F" in only:
        row_f0(mcp, cover, cover_error)
        rows_f(mcp, baseline)
    if "A" in only:
        rows_a(mcp)
    if "L" in only:
        rows_l(mcp)
    if "F" in only:
        row_f4(mcp)
    if "O" in only:
        if console_locked() and not captures:
            score("O5", "skip", "host: console locked")
        elif any(c["window_facts"]["active"] is False for c in captures):
            inactive = sum(1 for c in captures if c["window_facts"]["active"] is False)
            score("O5", "pass", f"{inactive} of {len(captures)} captures had active false")
        else:
            score("O5", "skip", f"host: Reelcut active for every capture ({len(captures)})")

    for rid in selected:
        if rid not in states:
            score(rid, "fail", "the row was never scored")
    counts = {s: sum(1 for rid in selected if states[rid] == s) for s in ("pass", "fail", "skip")}
    print(f"scores: {counts['pass']} pass, {counts['fail']} fail, {counts['skip']} skip of "
          f"{len(selected)}")
    digest = hashlib.sha256("\n".join(sorted(f"{rid}={states[rid]}" for rid in selected))
                            .encode()).hexdigest()
    print(f"digest: {digest}")
    return 1 if counts["fail"] else 0


if __name__ == "__main__":
    sys.exit(main())
