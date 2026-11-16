#!/usr/bin/env python3
"""The graphics engine through the app's wrappers: road map 10's G1d (§10.4).

Builds `graphics_ffi_probe.swift` over `app/Sources` with
`tools/proof/swift_build.py`'s line (a probe that will not build is a
scored FAILURE, never an exit), runs it under `graphics_spike/bounded.py`'s
`run`, and scores what it measured against oracles of its own:

P1  the probe builds over app/Sources and answers one JSON object;
P2  `GraphicLibrary.addFont` takes every `.ttf` in app/Resources/Fonts (the
    count is the folder's) and refuses 16 zero bytes;
P3  `describeJSON`'s schema keys come in the module's order, and its revision
    is hashlib's SHA-256 of the fixture;
P4  frame 30 is an `<svg` with no warnings;
P5  the SHA-256 of its BGRA is the crate's own pin (`graphic/tests/pins.json`
    `lower-third.30`), and `work/graphics-ffi-probe/lower-third-30.png` is a
    PNG with a 1920×1080 IHDR;
P6  the same frame twice is byte-identical, and frame 0 differs from frame 30;
P7  a syntax error is one error that names its line;
P8  a top-level `while (true) {}` at 50 ms fails inside the bound, in the
    budget's sentence;
P9  `{"size":"big"}` at frame 30 is the one `props.size` warning, frame 30;
P10 (spec §11 PR-15) `rasterize(…, deep: true)` of frame 30 answers
    1920 × 1080 × 4 values, an empty `bgra`, rows 15360 bytes apart, and a
    `byteCount` twice the 8-bit raster's; every value is within 4 levels of
    the 8-bit raster's, and it warns nothing;
P11 `Exporter.graphicsDeep` for every row the core lists: in an SDR project
    true for `hevc_10bit`, `av1`, `av1_webm`, `prores_422` and `prores_4444`
    and false for every other row (`h264`, `hevc`, `hevc_alpha`, `vp9_webm`,
    `vp9_alpha_webm`, the audio rows, `gif`, `apng`); in an HLG project
    `vp9_webm` true as HLG and as HDR10, and false as the SDR version;
P12 `LayerRenderers.textureKey` at 8 bits is `graphic:<sha256>:<w>x<h>:<lib>`
    exactly, and the deep key is that with `:16`;
P13 the raster budget counts bytes through `GraphicRaster.byteCount`: no
    `bgra.count` and no `height * 4` is left in `GraphicPrefetch.swift` or
    `GraphicPrefetch+Memory.swift`, and `byteCount` is read at eight sites.

    python3 tools/proof/graphics_ffi_probe.py
    python3 tools/proof/graphics_ffi_probe.py --mutant frame-off-by-one
    python3 tools/proof/graphics_ffi_probe.py --mutant bytes-uncounted      # P10
    python3 tools/proof/graphics_ffi_probe.py --mutant frame-form-unread    # P11
    python3 tools/proof/graphics_ffi_probe.py --mutant a-site-uncounted     # P13

The mutant is built from a COPY of `app/Sources` with one anchor in
`GraphicModule.svg`, asserted to occur exactly once, replaced so the frame
crosses the FFI as `frame + 1`; exit 0 means P5 FAILED in the copy, which is
the pass. A mutant copy that does not build is a FAILURE. PR-15's three
mutants each name the row that must fail.
"""

import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
from bounded import run as bounded_run  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-ffi-probe"
FONTS = ROOT / "app/Resources/Fonts"
FIXTURE = ROOT / "graphic/tests/graphics/lower-third.js"
PINS = ROOT / "graphic/tests/pins.json"
DEADLINE = 600
SCHEMA_ORDER = ["title", "subtitle", "accent", "size", "boxed", "align"]
# Every row of `core/src/export_table.rs`.
EXPORT_ROWS = ["h264", "hevc", "hevc_alpha", "hevc_10bit", "av1", "av1_webm", "vp9_webm",
               "vp9_alpha_webm", "prores_422", "prores_4444", "audio_m4a", "audio_wav",
               "audio_aiff", "gif", "apng"]
SIZE_WARNING = "props.size is a string but the schema says number; the default 64 is used"

rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""))


def build(sources, out, seconds):
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/graphics_ffi_probe.swift", entry)
    binary = out / "graphics-ffi-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    try:
        swift_build.build(sources=swift + [entry], output=binary, timeout=seconds)
    except swift_build.SwiftBuildFailed as error:
        if error.expired:
            return None, f"the build did not finish within {seconds} s"
        return None, "; ".join(error.diagnostics[:8])
    return binary, ""


def schema_order(describe):
    """The schema's keys in the order the TEXT carries them."""
    schema = json.loads(describe)["schema"]
    return list(schema.keys())


def png_header(path):
    try:
        data = Path(path).read_bytes()[:24]
    except OSError:
        return None
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def score(answer, out):
    p2 = answer.get("p2", {})
    folder = len([p for p in FONTS.iterdir() if p.suffix == ".ttf"])
    check(f"P2 addFont takes every bundled .ttf ({folder}) and refuses 16 zero bytes",
          p2.get("folder") == folder and p2.get("taken") == folder
          and p2.get("zero") == "font bytes loaded no face", f"{p2}")

    describe = answer.get("p3", {}).get("describe", "{}")
    revision = hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
    parsed = json.loads(describe)
    check("P3 describe's schema keys are in module order and its revision is the SHA-256",
          schema_order(describe) == SCHEMA_ORDER and parsed.get("revision") == revision,
          f"keys {schema_order(describe)}, revision {parsed.get('revision')} vs {revision}")

    p4 = answer.get("p4", {})
    check("P4 frame 30 is an <svg with no warnings",
          p4.get("prefix") == "<svg" and p4.get("warnings") == []
          and p4.get("raster_warnings") == [], f"{p4}")

    p5 = answer.get("p5", {})
    pin = json.loads(PINS.read_text())["lower-third"]["30"]
    try:
        got = hashlib.sha256(Path(p5.get("bgra", "")).read_bytes()).hexdigest()
    except OSError:
        got = None
    header = png_header(p5.get("png", ""))
    check("P5 the BGRA's SHA-256 is the crate's pin, and the PNG is 1920×1080",
          got == pin and p5.get("png_written") is True and header == (1920, 1080),
          f"sha256 {got} vs pin {pin}; png {header}")

    p6 = answer.get("p6", {})
    check("P6 the same frame twice is byte-identical, and frame 0 differs from frame 30",
          p6.get("svg_again_equal") is True and p6.get("bgra_again_equal") is True
          and p6.get("bgra_0_differs") is True, f"{p6}")

    p7 = answer.get("p7", {})
    d7 = p7.get("diagnostics") or [{}]
    check("P7 a syntax error is one error naming its line",
          p7.get("compiled") is False and len(d7) == 1 and d7[0].get("level") == "error"
          and str(d7[0].get("message", "")).startswith("SyntaxError:") and d7[0].get("line") == 3,
          f"{p7}")

    p8 = answer.get("p8", {})
    d8 = p8.get("diagnostics") or [{}]
    check("P8 a top-level loop at 50 ms fails inside the bound, in the budget's sentence",
          p8.get("compiled") is False and len(d8) == 1
          and "over the 50 ms budget while loading" in str(d8[0].get("message", "")),
          f"{p8}")

    p9 = answer.get("p9", {})
    w9 = p9.get("warnings") or []
    check("P9 {\"size\":\"big\"} at frame 30 is the one props.size warning",
          p9.get("drew") is True and len(w9) == 1 and w9[0].get("level") == "warning"
          and w9[0].get("message") == SIZE_WARNING and w9[0].get("frame") == 30, f"{p9}")

    p10 = answer.get("p10", {})
    pixels = 1920 * 1080 * 4
    check("P10 a deep raster: 1920×1080×4 values, no bgra, stride 15360, byteCount twice the "
          "8-bit raster's, within 4 levels of it, no warning",
          p10.get("values") == pixels and p10.get("bgra") == 0 and p10.get("deep") is True
          and p10.get("eight_deep") is False and p10.get("stride") == 15360
          and p10.get("eight_bytes") == pixels and p10.get("bytes") == 2 * pixels
          and isinstance(p10.get("far"), int) and p10["far"] <= 4 * 257
          and p10.get("warnings") == [], f"{p10}")

    p11 = answer.get("p11", {})
    deep_rows = {"hevc_10bit", "av1", "av1_webm", "prores_422", "prores_4444"}
    sdr = p11.get("sdr") or {}
    want = {row: row in deep_rows for row in EXPORT_ROWS}
    hdr = {name: (p11.get(name) or {}).get("vp9_webm") for name in ("hlg", "pq", "sdr_version")}
    check("P11 graphicsDeep by row: the five deep rows true and every other false in an SDR "
          "project; vp9_webm true as HLG and HDR10 and false as the SDR version",
          sdr == want and hdr == {"hlg": True, "pq": True, "sdr_version": False},
          f"sdr {sdr}; vp9_webm {hdr}; hlg {p11.get('hlg')}")

    p12 = answer.get("p12", {})
    key = "graphic:" + hashlib.sha256(b"<svg/>").hexdigest() + ":640x360:v"
    check("P12 the texture key is today's at 8 bits and gains :16 when deep",
          p12.get("eight") == key and p12.get("deep") == key + ":16", f"{p12} vs {key}")


def scan(sources):
    """P13, over the two prefetch files of `sources`."""
    texts = [(Path(sources) / name).read_text()
             for name in ("GraphicPrefetch.swift", "GraphicPrefetch+Memory.swift")]
    stale = sum(text.count("bgra.count") + text.count("height * 4") for text in texts)
    sites = sum(text.count("raster.byteCount") for text in texts)
    check("P13 the raster budget counts byteCount: no bgra.count or height * 4 in the two "
          "prefetch files, byteCount read at 8 sites", stale == 0 and sites == 8,
          f"{stale} stale spellings, {sites} byteCount sites")


def probe(sources, out):
    began = time.monotonic()
    binary, problem = build(sources, out, DEADLINE)
    if binary is None:
        check("P1 the probe builds over app/Sources and answers", False, problem)
        return
    left = max(DEADLINE - (time.monotonic() - began), 30)
    result = bounded_run([str(binary), str(FONTS), str(FIXTURE), str(out)], left)
    try:
        answer = json.loads(result["stdout"])
    except json.JSONDecodeError:
        answer = {}
    check("P1 the probe builds over app/Sources and answers", answer.get("ok") is True,
          "" if answer.get("ok") else
          f"expired {result['expired']}, rc {result['rc']}: {result['stdout'][-300:]}"
          f"{result['stderr'][-300:]} {answer}")
    if answer:
        (out / "answer.json").write_text(json.dumps(answer, indent=1, sort_keys=True))
    if answer.get("ok") is True:
        score(answer, out)
        scan(sources)


def replace_once(path, before, after):
    text = path.read_text(encoding="utf-8")
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {path.name}: expected once, found {count}: "
                           f"{before!r}")
    path.write_text(text.replace(before, after), encoding="utf-8")


MUTANTS = {
    "frame-off-by-one": ("ReelCore+Graphics.swift",
                         "            handle, Int64(frame), propsJSON, ctxJSON,",
                         "            handle, Int64(frame + 1), propsJSON, ctxJSON,"),
    "bytes-uncounted": (
        "CoreValues.swift",
        "    var byteCount: Int { bgra.count + rgba16.count * MemoryLayout<UInt16>.stride }",
        "    var byteCount: Int { bgra.count }"),
    "frame-form-unread": (
        "ExporterGraphics.swift",
        "        case .eightBit?, .straightEightBit?: return false\n", "        case nil: return true\n"),
    "a-site-uncounted": (
        "GraphicPrefetch+Memory.swift", "        bytes += raster.byteCount\n",
        "        bytes += raster.bgra.count\n"),
}
MUST_FAIL = {"frame-off-by-one": "P5", "bytes-uncounted": "P10", "frame-form-unread": "P11",
             "a-site-uncounted": "P13"}


def mutant(name):
    file, before, after = MUTANTS[name]
    with tempfile.TemporaryDirectory(prefix=f"framejob-graphics-ffi-{name}-") as temp:
        sources = Path(temp) / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        replace_once(sources / file, before, after)
        print(f"MUTANT {name}: {file}, anchor replaced once, in {sources}")
        probe(sources, Path(temp) / "out")
    built, row = rows.get("P1", False), MUST_FAIL[name]
    if built and rows.get(row) is False:
        failed = [k for k, v in rows.items() if not v]
        print(f"MUTANT PASS: {name} — {row} FAILED in the copy (failed: {', '.join(failed)})")
        return 0
    print(f"MUTANT FAILURE: {name} — built {built}, {row} {rows.get(row)}")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("G1d — the graphics engine through ReelCore.swift (probe)")
    probe(ROOT / "app/Sources", WORK)
    passed = sum(rows.values())
    print(f"{passed}/13")
    return 0 if len(rows) == 13 and all(rows.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
