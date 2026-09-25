#!/usr/bin/env python3
"""A timeline with no media, played — road map 10 §10.8, measured.

What happened. A timeline of ONLY graphics, text, shapes or images — Insert ▸
Graphic into an empty document is the common way to make one — showed nothing
in the editor and would not play: the transport beeped. The core gives those
layers no composition segment by design (spec §7.2), so the plan has no
video and no audio track, and `Playback.startRebuild` dropped the player item
for any plan with no tracks — a guard written for the EMPTY timeline, which
also caught this one. `CompositionBuilder.addPlaceholderIfNeeded` already
gives such a plan a one-frame black video track to tick against (the export
and `render_frame` paths use it and were never wrong); the preview never got
that far. The fix drops the item only when the plan's duration is 0.

Why a probe and not an MCP script. `render_frame` composes offline, so every
MCP frame comparison passes against the broken build; the defect is in the
editor's OWN player, which no tool reads. This is `preview_refresh_probe.py`'s
instrument: `media_less_playback_probe.swift` compiled as `main.swift` against
the whole of `app/Sources` with `harness/build.sh`'s swiftc line, the app's
`Compositor.metal`, `Fonts` and `Blank.mp4` beside it, `--sources PATH` to
build the same probe over another tree (`mixed_audio_probe.py`'s tag scheme),
a build failure scored as a FAILURE on every row. Every subprocess runs under
`graphics_spike/bounded.py` (Rule H).

Fixtures, rewritten every run under `work/media-less-playback/`: one 3 s clip
on a 432 × 280 black canvas — `graphic` (a module drawing a white bar that
grows from a quarter of the width to all of it), `text` (white on a white
backdrop), `shape` (a white rectangle the canvas's size), `image` (a white
PNG written here) — and `empty`, the same canvas with no clip.

Rows, for each media-less fixture F:
  F·1 the player holds an item, ready to play, its video composition valid;
  F·2 [pic] the paused frame at 0 s is drawn;
  F·3 CONTROL — the Play/Pause validator is on;
  F·4 play: the rate is non-zero and the playhead advanced ≥ 0.4 s in 1.2 s;
      pause stops it;
  F·5 [pic] the playhead moved to 0.5 s and 2.5 s: each drawn, on its tick;
  F·6 [pic] paused, opacity 0 goes black and opacity 1 comes back with the
      item's plan unchanged — the refresh branch on the placeholder item;
and for the graphic G·7 [pic] the picture moves with time (2.5 s brighter
than 0.5 s, and two frames the item composes 1 s apart while playing differ
— read through an `AVPlayerItemVideoOutput` added to the item for the run,
because `displayedPixelBuffer()` answers nil for ANY playing layer, a media
clip's included, measured 2026-09-25), G·8 rate 2 runs
twice as far, G·9 the in/out loop wraps inside the item; and the CONTROL
`empty`: E·1 no item, E·2 play does nothing, E·3 the validator is off,
E·4 Insert ▸ Shape brings an item that plays, E·5 undo takes it away again.

[pic] rows read the displayed buffer and are skipped BY NAME on a locked
console, which displays nothing in any layer; every other row is scored.

Needs `swiftc`, `xcrun metal` and `core/target/release/libreelcut_core.a`.
No port, no ffmpeg. Run from anywhere:

    python3 tools/proof/media_less_playback_probe.py [--sources PATH]
"""

import argparse
import hashlib
import json
import os
import shutil
import struct
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402

WORK = os.path.join(HERE, "work", "media-less-playback")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "media_less_playback_probe.swift")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")

TICKS = 600_000
CLIP = 3 * TICKS
WIDTH, HEIGHT = 432, 280
# `preview_refresh_probe.py`'s thresholds on the 40 × 40-grid mean.
PICTURE = 16
BLACK = 8
MARGIN = 20
ADVANCE = 0.4
FIXTURES = ["graphic", "text", "shape", "image", "empty"]
MEDIA_LESS = ["graphic", "text", "shape", "image"]

GROW = """export const meta = { name: "Grow" };
export function render(frame, props, ctx) {
  const w = ctx.width * (0.25 + 0.75 * ctx.progress);
  return svg(ctx, `<rect x="0" y="0" width="${w}" height="${ctx.height}" fill="#ffffff"/>`);
}
"""

passed = 0
failed = 0
skipped = 0


def check(name, ok, detail="", show=False):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}" + (f"\n       {detail}" if show and detail else ""))
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def skip(name, reason):
    global skipped
    skipped += 1
    print(f"  skip {name} — {reason}")


# ---------------------------------------------------------------------------
# The fixtures.


def white_png(path):
    """A WIDTH × HEIGHT opaque white RGBA PNG, with no dependency."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    rows = b"".join(b"\x00" + b"\xff" * (WIDTH * 4) for _ in range(HEIGHT))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(rows)))
        f.write(chunk(b"IEND", b""))


def clip(source, **extra):
    return dict({"id": 2, "track": 1, "start": 0, "duration": CLIP, "source": source,
                 "video": {}}, **extra)


def write_package(name, clips, media=(), graphics=None):
    package = os.path.join(WORK, f"{name}.reelcut")
    shutil.rmtree(package, ignore_errors=True)
    os.makedirs(package)
    project = {
        "version": 10,
        "canvas": {"width": WIDTH, "height": HEIGHT, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": True},
        "media": list(media),
        "tracks": [{"id": 1, "name": "Track 1"}],
        "clips": clips, "markers": [], "next_id": 6, "nests": [],
    }
    with open(os.path.join(package, "project.json"), "w") as f:
        json.dump(project, f, indent=1)
    for module, source in (graphics or {}).items():
        os.makedirs(os.path.join(package, "graphics"), exist_ok=True)
        with open(os.path.join(package, "graphics", f"{module}.js"), "w") as f:
            f.write(source)
    return package


def make_fixtures():
    os.makedirs(WORK, exist_ok=True)
    png = os.path.join(WORK, "white.png")
    white_png(png)
    white = [1.0, 1.0, 1.0, 1.0]
    return {
        "graphic": write_package("graphic", [clip(
            {"kind": "graphic"},
            graphic={"name": "grow", "width": WIDTH, "height": HEIGHT, "in": 0,
                     "length": None, "props": {}})], graphics={"grow": GROW}),
        "text": write_package("text", [clip(
            {"kind": "text"},
            text={"content": "REEL", "size": 140.0, "color": white,
                  "backdrop": {"color": white, "padding": 40.0, "radius": 0.0}})]),
        "shape": write_package("shape", [clip(
            {"kind": "shape"},
            shape={"kind": "rectangle", "width": float(WIDTH), "height": float(HEIGHT),
                   "stroke": {"width": 6.0, "color": white}, "fill": white,
                   "arrow_start": False, "arrow_end": False, "radius": 0.0,
                   "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None})]),
        "image": write_package("image", [clip({"kind": "image", "media": 5})], media=[
            {"id": 5, "kind": "image", "path": png, "width": WIDTH, "height": HEIGHT,
             "has_video": True}]),
        "empty": write_package("empty", []),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_shader(probe):
    lib = os.path.join(probe, "default.metallib")
    air = os.path.join(probe, "Compositor.air")
    if os.path.exists(lib) and os.path.getmtime(SHADER) < os.path.getmtime(lib):
        return lib, None
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", SHADER, "-o", air], 300)
    if step["rc"] != 0:
        return None, "xcrun metal failed: " + step["stderr"].strip()[:300]
    step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib], 300)
    if step["rc"] != 0 or not os.path.exists(lib):
        return None, "xcrun metallib failed: " + step["stderr"].strip()[:300]
    return lib, None


def build_probe(sources):
    """The probe over `sources`, in a directory of its own per source tree.
    (binary, None) or (None, reason)."""
    tag = "probe" if os.path.samefile(sources, SOURCES) else (
        "probe-" + hashlib.sha256(os.path.abspath(sources).encode()).hexdigest()[:10])
    probe = os.path.join(WORK, tag)
    os.makedirs(probe, exist_ok=True)
    binary = os.path.join(probe, "media_less_playback_probe")
    entry = os.path.join(probe, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    fonts = os.path.join(probe, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(probe, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    shader, why = build_shader(probe)
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, name) for name in os.listdir(sources)
                   if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    stamp = os.path.join(probe, "sources.txt")
    listing = "\n".join(swift)
    same_set = os.path.exists(stamp) and open(stamp).read() == listing
    if same_set and os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in swift + [entry, lib]
    ):
        print(f"probe: {binary} (up to date)")
        return binary, None
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    start = time.time()
    if os.path.exists(binary):
        os.remove(binary)
    built = bounded.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + swift + [entry, "-o", binary], 900)
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = [line for line in built["stderr"].strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    with open(stamp, "w") as f:
        f.write(listing)
    print(f"probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary, packages):
    ran = bounded.run([binary] + [packages[name] for name in FIXTURES], 300,
                      cwd=os.path.dirname(binary))
    if ran["expired"]:
        return None, "the probe ran past 300 s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-300:]}"


def console_locked():
    """Host state is a proof input: a locked console displays nothing."""
    out = bounded.run(["ioreg", "-n", "Root", "-d1", "-a"], 60)["stdout"]
    marker = out.find("<key>IOConsoleLocked</key>")
    return marker >= 0 and out[marker:marker + 60].find("<true/>") >= 0


# ---------------------------------------------------------------------------
# The rows: (id, name, needs the picture, predicate over the answer, detail).


def mean(s):
    return (s or {}).get("mean", -1)


def drawn(s):
    return mean(s) > PICTURE


def seconds(t):
    return t / TICKS


def rows():
    for f in MEDIA_LESS:
        yield (f"{f}·1", "after open the player holds an item, ready, its composition valid", False,
               lambda a, f=f: a[f]["item"].get("item") is True and a[f]["item"]["ready"] is True
               and a[f]["item"]["valid"] is True, lambda a, f=f: a[f]["item"])
        yield (f"{f}·2", "the paused frame at 0 s is drawn", True,
               lambda a, f=f: drawn(a[f]["opened"]), lambda a, f=f: a[f]["opened"])
        yield (f"{f}·3", "CONTROL — the Play/Pause validator is on", False,
               lambda a, f=f: a[f]["playEnabled"] is True, lambda a, f=f: a[f]["playEnabled"])
        yield (f"{f}·4", f"play: rate non-zero, the playhead advanced ≥ {ADVANCE} s in 1.2 s; "
               "pause leaves rate 0", False,
               lambda a, f=f: a[f]["play"]["rate"] != 0 and a[f]["play"]["advanced"] >= ADVANCE
               and a[f]["play"]["rateAfterPause"] == 0, lambda a, f=f: a[f]["play"])
        yield (f"{f}·5", "moved to 0.5 s and 2.5 s: each drawn, the playhead on that tick", True,
               lambda a, f=f: all(drawn(a[f][k]) and a[f][k]["playhead"] == a[f][k]["expected"]
                                  and a[f][k]["playerTicks"] == a[f][k]["playhead"]
                                  for k in ("at05", "at25")),
               lambda a, f=f: [a[f]["at05"], a[f]["at25"]])
        yield (f"{f}·6", "paused, opacity 0 goes black and 1 comes back, the plan unchanged "
               "(the refresh branch)", True,
               lambda a, f=f: 0 <= mean(a[f]["opacity0"]) < BLACK and drawn(a[f]["opacity1"])
               and a[f]["samePlan"] is True,
               lambda a, f=f: [a[f]["opacity0"], a[f]["opacity1"], a[f]["samePlan"]])
    yield ("graphic·7", f"the picture moves: 2.5 s exceeds 0.5 s by ≥ {MARGIN}, and two frames "
           f"the item composes 1 s apart while playing differ by ≥ {MARGIN}", True,
           lambda a: mean(a["graphic"]["at25"]) - mean(a["graphic"]["at05"]) >= MARGIN
           and min(mean(s) for s in a["graphic"]["playing"]) >= 0
           and all(s["rate"] != 0 for s in a["graphic"]["playing"])
           and abs(mean(a["graphic"]["playing"][1]) - mean(a["graphic"]["playing"][0])) >= MARGIN,
           lambda a: [mean(a["graphic"]["at05"]), mean(a["graphic"]["at25"]),
                      a["graphic"]["playing"]])
    yield ("graphic·8", "setRate(2): rate 2 and the playhead advanced ≥ 0.8 s in 1.2 s", False,
           lambda a: a["graphic"]["rate2"]["rate"] == 2 and a["graphic"]["rate2"]["advanced"] >= 0.8,
           lambda a: a["graphic"]["rate2"])
    yield ("graphic·9", "in 0.5 s, out 2.0 s, loop on, play from 1.5 s for 1.2 s: still playing, "
           "the playhead wrapped into [0.5 s, 1.5 s)", False,
           lambda a: a["graphic"]["loop"]["rate"] != 0
           and 0.5 <= seconds(a["graphic"]["loop"]["playhead"]) < 1.5,
           lambda a: a["graphic"]["loop"])
    yield ("empty·1", "CONTROL — no item after open", False,
           lambda a: a["empty"]["item"] is False, lambda a: a["empty"]["item"])
    yield ("empty·2", "CONTROL — play leaves rate 0 and the playhead at 0 after 1.2 s", False,
           lambda a: a["empty"]["play"]["rate"] == 0 and a["empty"]["play"]["playhead"] == 0,
           lambda a: a["empty"]["play"])
    yield ("empty·3", "CONTROL — the Play/Pause validator is off", False,
           lambda a: a["empty"]["playEnabled"] is False, lambda a: a["empty"]["playEnabled"])
    yield ("empty·4", f"Insert ▸ Shape: an item appears and play advances the playhead "
           f"≥ {ADVANCE} s in 1.2 s", False,
           lambda a: a["empty"]["inserted"]["clips"] == 1 and a["empty"]["inserted"]["item"] is True
           and a["empty"]["insertedPlay"]["advanced"] >= ADVANCE,
           lambda a: [a["empty"]["inserted"], a["empty"]["insertedPlay"]])
    yield ("empty·5", "undo: the timeline is empty, the item gone, the validator off again", False,
           lambda a: a["empty"]["undone"] == {"clips": 0, "item": False, "playEnabled": False},
           lambda a: a["empty"]["undone"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default=SOURCES,
                        help="an app/Sources tree to build the probe over (default: this tree's)")
    sources = os.path.abspath(parser.parse_args().sources)
    print(f"sources: {sources}")
    packages = make_fixtures()
    binary, why = build_probe(sources)
    locked = console_locked()
    answer = None
    if binary is not None:
        answer, why = run_probe(binary, packages)
    print()
    for rid, name, picture, predicate, detail in rows():
        label = f"{rid} {name}"
        if answer is None:
            check(label, False, why)
        elif picture and locked:
            skip(label, "the console is locked, and a locked console displays nothing in any layer")
        else:
            try:
                ok, shown = predicate(answer), json.dumps(detail(answer))
            except (KeyError, TypeError, IndexError) as error:
                ok, shown = False, f"{type(error).__name__}: {error}"
            check(label, ok, shown, show=rid.endswith(("·4", "·7", "·8", "·9")))
    total = passed + failed
    print(f"\n{passed}/{total} checks passed" + (f", {skipped} skipped by name" if skipped else ""))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
