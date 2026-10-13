#!/usr/bin/env python3
"""Issue batch B11's #91: the video composition built from, and varied
through, an `AVVideoComposition.Configuration` draws exactly what the
`AVMutableVideoComposition` it replaced drew.

The fixture is `target_bump_proof.py`'s `document()` — a media clip
(`tools/proof/media/A.mov`; a missing file FAILS by name), a text clip and a
shape clip on three tracks — written as `<dir>/frames.framejob` by `capture`
and opened again by `compare`.

    python3 tools/proof/video_configuration_proof.py <socket> capture <dir>   # the CONTROL tree
    python3 tools/proof/video_configuration_proof.py <socket> compare <dir>   # the tree under test
    python3 tools/proof/video_configuration_proof.py --mutant keep-frame-duration compare <dir>

Over MCP (the caller owns the instance at <socket>; nothing is launched or
killed): `render_frame` at the three ticks, and `export` of `apng`, `gif` and
`prores_422` at the canvas's 30 fps. Through the probe
(`video_configuration_probe.swift`, built as `export_cancel_proof.py`'s
`build_probe` with `Fonts`, `Blank.mp4` and `default.metallib` beside it):
`prores_422` at 25 fps, the export sheet's frame-rate override, which is the
one path that draws through `ExportWriter`'s frame-duration variant.

Movies compare byte for byte after zeroing `creation_time` and
`modification_time` in every `mvhd`, `tkhd` and `mdhd` box; the masked-box
count is printed and must be >= 3. APNG and GIF compare as plain bytes.

  capture  C1  each MCP export written twice is masked-equal to itself
           C2  the probe's 25 fps ProRes written twice is masked-equal
  compare  V1–V3  the three renders, byte for byte against the control
           V4 apng, V5 gif (plain bytes), V6 MCP ProRes, V7 probe ProRes at
           25 fps (masked); each compared file written by this run
  --mutant keep-frame-duration  the probe rebuilt over a copy of app/Sources
           whose `ExportWriter` variant returns `built.videoComposition`;
           V7 alone, which must FAIL (exit 1; 0 when it survives, 2 when the
           copy or the build could not be made, or — rule R, issue batch
           B13 — when V7 was scored without its comparison running: the
           probe wrote no file, or there is no control file)

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row passes.
Every child runs under `graphics_spike/bounded.py`.
"""

import hashlib
import json
import os
import re
import shutil
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
from mcp import MCP, target  # noqa: E402
from target_bump_proof import TICKS, document, package  # noqa: E402
import swift_build  # noqa: E402

SOURCES = os.path.join(ROOT, "app", "Sources")
RESOURCES = os.path.join(ROOT, "app", "Resources")
PROBE_SWIFT = os.path.join(HERE, "video_configuration_probe.swift")
PROBE_WORK = os.path.join(HERE, "work", "video_configuration_probe")
PROBE_DIR = os.path.join(PROBE_WORK, "tree")
LIB = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
A_MOV = os.path.join(ROOT, "tools", "proof", "media", "A.mov")
WRITTEN = re.compile(r"Written to (\S+\.png)\.")
EXPORTS = ("apng", "gif", "prores_422")
WALL_BUILD, WALL_RUN = 900, 400
MASKED = (b"mvhd", b"tkhd", b"mdhd")
CONTAINERS = (b"moov", b"trak", b"mdia", b"edts", b"minf", b"stbl", b"udta")

# name: (file in app/Sources, before — exactly once, after, row)
MUTANTS = {
    "keep-frame-duration": ("ExporterWriter+Settings.swift",
                            "return AVVideoComposition(configuration: configuration)",
                            "return built.videoComposition", "V7"),
}

rows = []


def score(row_id, ok, detail, *, instrument=False):
    rows.append((row_id, bool(ok), instrument))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- movies, masked ---------------------------------------------------------

def mask_boxes(data):
    """(bytes with every mvhd/tkhd/mdhd creation and modification time zeroed,
    how many boxes were masked)."""
    out = bytearray(data)
    count = 0

    def walk(start, end):
        nonlocal count
        at = start
        while at + 8 <= end:
            size, kind = struct.unpack(">I4s", bytes(out[at:at + 8]))
            header = 8
            if size == 1:
                if at + 16 > end:
                    return
                size = struct.unpack(">Q", bytes(out[at + 8:at + 16]))[0]
                header = 16
            elif size == 0:
                size = end - at
            if size < header or at + size > end:
                return
            body = at + header
            if kind in MASKED and body + 4 <= at + size:
                version = out[body]
                width = 8 if version == 1 else 4
                times = body + 4
                if times + 2 * width <= at + size:
                    out[times:times + 2 * width] = bytes(2 * width)
                    count += 1
            elif kind in CONTAINERS:
                walk(body, at + size)
            at += size

    walk(0, len(out))
    return bytes(out), count


def sha(data):
    return hashlib.sha256(data).hexdigest()[:16]


def read(path):
    with open(path, "rb") as stream:
        return stream.read()


def same_movie(a, b):
    """(equal after masking, detail)."""
    ma, ca = mask_boxes(read(a))
    mb, cb = mask_boxes(read(b))
    equal = ma == mb and ca >= 3 and cb >= 3
    return equal, (f"{os.path.basename(a)} {len(ma)} bytes masked {ca} boxes sha {sha(ma)} vs "
                   f"{os.path.basename(b)} {len(mb)} bytes masked {cb} boxes sha {sha(mb)}")


def same_bytes(a, b):
    da, db = read(a), read(b)
    return da == db, (f"{os.path.basename(a)} {len(da)} bytes sha {sha(da)} vs "
                      f"{os.path.basename(b)} {len(db)} bytes sha {sha(db)}")


def fresh(path, since):
    return os.path.exists(path) and os.path.getmtime(path) >= since


# ---- the probe --------------------------------------------------------------

def mutant_sources(name):
    """(PROBE_WORK/mutants/<name>/Sources, None) with the mutant's `before`
    replaced exactly once; or (None, reason)."""
    file, before, after, _ = MUTANTS[name]
    target = os.path.join(PROBE_WORK, "mutants", name, "Sources")
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    for entry in sorted(os.listdir(SOURCES)):
        if entry.endswith(".swift"):
            shutil.copy2(os.path.join(SOURCES, entry), os.path.join(target, entry))
    path = os.path.join(target, file)
    text = open(path).read() if os.path.exists(path) else ""
    count = text.count(before)
    if count != 1:
        return None, f"{file} holds {before!r} {count} times, not once"
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    return target, None


def build_probe(sources=None, probe_dir=None):
    """(binary, None) or (None, reason), through `swift_build.build` (reused
    when every input is byte-identical to a cached build's). `None` for
    either argument means the module's `SOURCES` / `PROBE_DIR`, read at call
    time, so an importer that sets them is heard."""
    sources = SOURCES if sources is None else sources
    probe_dir = PROBE_DIR if probe_dir is None else probe_dir
    os.makedirs(probe_dir, exist_ok=True)
    binary = os.path.join(probe_dir, "video_configuration_probe")
    entry = os.path.join(probe_dir, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    fonts = os.path.join(probe_dir, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(
            os.path.join(RESOURCES, "Fonts")) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(os.path.join(RESOURCES, "Fonts"), fonts)
    if not os.path.exists(os.path.join(probe_dir, "Blank.mp4")):
        shutil.copy2(os.path.join(RESOURCES, "Blank.mp4"), os.path.join(probe_dir, "Blank.mp4"))
    shader = os.path.join(RESOURCES, "Shaders", "Compositor.metal")
    metallib = os.path.join(probe_dir, "default.metallib")
    air = os.path.join(probe_dir, "Compositor.air")
    if not os.path.exists(metallib) or os.path.getmtime(shader) > os.path.getmtime(metallib):
        step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", shader, "-o", air], 300)
        if step["rc"] == 0:
            step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", metallib], 300)
        if step["rc"] != 0 or not os.path.exists(metallib):
            return None, f"the shader did not build: {step['stderr'][-400:]}"
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `cd core && cargo build --release` first"
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    print(f"probe: {len(swift)} sources through swift_build (up to {WALL_BUILD} s)…", flush=True)
    try:
        built = swift_build.build(sources=swift + [entry], output=binary,
                                  defines=["FRAMEJOB_DEV_TOOLS"], timeout=WALL_BUILD)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc exited {error.rc if error.rc is not None else 'before running'} "
                      f"(expired {error.expired}): "
                      + " | ".join(error.diagnostics[:6] or ["(no output)"]))
    print(f"probe: {binary} (up to date)" if built.reused
          else f"probe: built in {built.seconds:.0f} s", flush=True)
    return binary, None


def run_probe(binary, project, out):
    """The probe's export to `out`: (path, None) or (None, reason)."""
    got = bounded.run([binary, project, out], WALL_RUN, cwd=os.path.dirname(binary))
    if got["expired"]:
        return None, f"the probe ran past {WALL_RUN} s and was killed"
    try:
        answer = json.loads(got["stdout"].strip().splitlines()[-1])
    except (IndexError, ValueError):
        return None, f"no answer (exit {got['rc']}): {(got['stdout'] + got['stderr'])[-300:]!r}"
    if answer.get("outcome") != "success" or answer.get("fps") != [25, 1]:
        return None, f"the probe answered {answer}"
    return answer["path"], None


# ---- MCP --------------------------------------------------------------------

def render(mcp, tick):
    answer = str(mcp.call("render_frame", t=tick))
    found = WRITTEN.search(answer)
    if not found:
        raise RuntimeError(f"render_frame said something else: {answer}")
    return found.group(1)


def export(mcp, project, preset, path):
    reply = mcp.call("export", project=project, preset=preset, path=path)
    if not isinstance(reply, dict) or not reply.get("ok"):
        raise RuntimeError(f"export {preset} answered {reply}")
    return reply["path"]


# ---- the modes --------------------------------------------------------------

def capture(socket_path, where):
    shutil.rmtree(where, ignore_errors=True)
    os.makedirs(where)
    package(where, "frames", document())
    project = os.path.join(where, "frames.framejob")
    mcp = MCP(socket_path)
    mcp.call("open_project", path=project)
    for tick in TICKS:
        kept = os.path.join(where, f"t{tick}.png")
        shutil.copyfile(render(mcp, tick), kept)
        print(f"  kept {kept} {os.path.getsize(kept)} bytes sha {sha(read(kept))}", flush=True)
    pairs = []
    for preset in EXPORTS:
        first = export(mcp, project, preset, os.path.join(where, f"mcp-{preset}"))
        second = export(mcp, project, preset, os.path.join(where, f"mcp-{preset}-again"))
        if preset == "prores_422":
            pairs.append(same_movie(first, second))
        else:
            pairs.append(same_bytes(first, second))
        print(f"  kept {first}", flush=True)
    score("C1", all(ok for ok, _ in pairs),
          "each MCP export written twice is equal to itself (ProRes masked): "
          + "; ".join(detail for _, detail in pairs))
    binary, why = build_probe()
    if binary is None:
        score("C2", False, f"the probe did not build: {why}")
        return
    first, why1 = run_probe(binary, project, os.path.join(where, "probe-prores25.mov"))
    second, why2 = run_probe(binary, project, os.path.join(where, "probe-prores25-again.mov"))
    if first is None or second is None:
        score("C2", False, f"the probe's export failed: {why1 or why2}")
        return
    ok, detail = same_movie(first, second)
    score("C2", ok, "the probe's 25 fps ProRes written twice is masked-equal: " + detail)


def kept_of(where, stem):
    """The control's file for `stem` (the extension the export chose)."""
    for name in sorted(os.listdir(where)):
        if os.path.splitext(name)[0] == stem:
            return os.path.join(where, name)
    return None


def compare_probe(where, binary, why, row_id="V7"):
    project = os.path.join(where, "frames.framejob")
    kept = os.path.join(where, "probe-prores25.mov")
    if binary is None:
        score(row_id, False, f"the probe did not build: {why}", instrument=True)
        return
    out_dir = os.path.join(where, "compare")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "probe-prores25.mov")
    if os.path.exists(out):
        os.remove(out)
    started = time.time() - 1
    written, why = run_probe(binary, project, out)
    if written is None or not fresh(written, started):
        score(row_id, False, f"the probe wrote no file this run: {why}", instrument=True)
        return
    if not os.path.exists(kept):
        score(row_id, False, f"no control file {kept}", instrument=True)
        return
    ok, detail = same_movie(written, kept)
    score(row_id, ok, "probe ProRes at 25 fps, masked, against the control: " + detail)


def compare(socket_path, where):
    project = os.path.join(where, "frames.framejob")
    if not os.path.isdir(project):
        sys.exit(f"no control package at {project}; run capture on the control tree first")
    out_dir = os.path.join(where, "compare")
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    started = time.time() - 1
    mcp = MCP(socket_path)
    mcp.call("open_project", path=project)
    for index, tick in enumerate(TICKS, 1):
        written = render(mcp, tick)
        kept = os.path.join(where, f"t{tick}.png")
        if not fresh(written, started):
            score(f"V{index}", False, f"t={tick}: {written} was not written by this run")
            continue
        ok, detail = same_bytes(written, kept)
        score(f"V{index}", ok, f"t={tick} renders byte for byte as the control: {detail}")
    for index, preset in enumerate(EXPORTS, 4):
        row_id = f"V{index}"
        kept = kept_of(where, f"mcp-{preset}")
        written = export(mcp, project, preset, os.path.join(out_dir, f"mcp-{preset}"))
        if kept is None or not fresh(written, started):
            score(row_id, False, f"{preset}: control {kept}, written this run "
                                 f"{fresh(written, started)}")
            continue
        if preset == "prores_422":
            ok, detail = same_movie(written, kept)
            score(row_id, ok, f"MCP {preset} at 30 fps, masked, against the control: {detail}")
        else:
            ok, detail = same_bytes(written, kept)
            score(row_id, ok, f"MCP {preset}, plain bytes, against the control: {detail}")
    binary, why = build_probe()
    compare_probe(where, binary, why)


def run_mutant(name, where):
    _, _, _, row_id = MUTANTS[name]
    sources, why = mutant_sources(name)
    if sources is None:
        print(f"mutant {name}: the control could not be performed — {why}", flush=True)
        return 2
    binary, why = build_probe(sources, os.path.join(PROBE_WORK, "mutants", name, "probe"))
    if binary is None:
        print(f"mutant {name}: the control could not be performed — the probe did not "
              f"build: {why}", flush=True)
        return 2
    compare_probe(where, binary, why, row_id)
    if rows[-1][2]:
        print(f"mutant {name}: the control could not be performed — {row_id} was scored "
              f"without its comparison", flush=True)
        return 2
    failed = not rows[-1][1]
    print(f"mutant {name}: {row_id} {'FAILS (expected)' if failed else 'PASSES (survived)'}",
          flush=True)
    return 1 if failed else 0


def main():
    args = sys.argv[1:]
    if not os.path.exists(A_MOV):
        print(f"FIXTURE FAIL — {A_MOV} is missing (see tools/proof/README.md for the test media)")
        sys.exit(1)
    if len(args) == 4 and args[0] == "--mutant" and args[1] in MUTANTS and args[2] == "compare":
        sys.exit(run_mutant(args[1], os.path.abspath(args[3])))
    if len(args) != 3 or args[1] not in ("capture", "compare"):
        sys.exit(__doc__)
    socket_path, mode, where = target(args, 0), args[1], os.path.abspath(args[2])
    if mode == "capture":
        capture(socket_path, where)
    else:
        compare(socket_path, where)
    passed = sum(1 for _, ok, _ in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    sys.exit(0 if rows and passed == len(rows) else 1)


if __name__ == "__main__":
    main()
