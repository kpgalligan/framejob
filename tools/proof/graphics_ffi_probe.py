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
P9  `{"size":"big"}` at frame 30 is the one `props.size` warning, frame 30.

    python3 tools/proof/graphics_ffi_probe.py
    python3 tools/proof/graphics_ffi_probe.py --mutant frame-off-by-one

The mutant is built from a COPY of `app/Sources` with one anchor in
`GraphicModule.svg`, asserted to occur exactly once, replaced so the frame
crosses the FFI as `frame + 1`; exit 0 means P5 FAILED in the copy, which is
the pass. A mutant copy that does not build is a FAILURE.
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


def replace_once(path, before, after):
    text = path.read_text(encoding="utf-8")
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {path.name}: expected once, found {count}: "
                           f"{before!r}")
    path.write_text(text.replace(before, after), encoding="utf-8")


MUTANTS = {
    "frame-off-by-one": ("ReelCore.swift",
                         "            handle, Int64(frame), propsJSON, ctxJSON,",
                         "            handle, Int64(frame + 1), propsJSON, ctxJSON,"),
}


def mutant(name):
    file, before, after = MUTANTS[name]
    with tempfile.TemporaryDirectory(prefix=f"framejob-graphics-ffi-{name}-") as temp:
        sources = Path(temp) / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        replace_once(sources / file, before, after)
        print(f"MUTANT {name}: {file}, anchor replaced once, in {sources}")
        probe(sources, Path(temp) / "out")
    built = rows.get("P1", False)
    if built and rows.get("P5") is False:
        failed = [k for k, v in rows.items() if not v]
        print(f"MUTANT PASS: {name} — P5 FAILED in the copy (failed: {', '.join(failed)})")
        return 0
    print(f"MUTANT FAILURE: {name} — built {built}, P5 {rows.get('P5')}")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("G1d — the graphics engine through ReelCore.swift (probe)")
    probe(ROOT / "app/Sources", WORK)
    passed = sum(rows.values())
    print(f"{passed}/9")
    return 0 if len(rows) == 9 and all(rows.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
