#!/usr/bin/env python3
"""Issue #127 G6 phase 5 — the graphics engine's decoded-image cache (spec §11
G-39, `graphic/src/images.rs`, `GraphicPrefetch+Memory.swift`'s limit), against
the built app, read with the dev tool `graphic_memory`
(`AgentServer+GraphicMemory.swift`).

A PNG or JPEG asset is drawn from a stored PNG copy only when the copy decodes
to the original's pixmap, so every frame with the cache ON must be the bytes
of the cache OFF; its limit is a sixteenth of G-37's budget at the level in
force. Two owned instances, one after the other, each on a scratch socket,
launched and stopped by PID, logs under `tools/proof/work/image-cache/`: OFF
with `-FrameJobGraphicImageCacheOff YES` (the argument domain only; nothing
persists) and ON without. Nothing else is ever killed. Every child runs under
`graphics_spike/bounded.py`; the launch is `playback_prefetch_proof.Instance`
(Background render off, the kept frames off, G-38 (e), G-37 (e)).

Fixture C, made over MCP on OFF through `new_project`, `write_graphic`,
`import_graphic_asset` and `add_graphic_clip` and saved under `work/`: a
30 fps project with one graphic clip, 4 s from 0, whose module draws a
generated 640×360 RGBA alpha-ramp `ramp.png` and the committed `steel.jpg`
under a frame-dependent transform and opacity. Each instance opens its own
copy of C (OFF `C-off`, ON `C-on`), so C4's replacement on one cannot reach
the other.

C0  CONTROL: the fixture is made, saved and copied, and each copy opens;
C1  `render_frame` at 6 frames on OFF and on ON; the PNGs are byte-equal;
C2  after C1, ON's `graphic_memory` has image_cache_bytes > 0 and
    image_cache_limit == budget_bytes // 16; OFF's has both 0;
C3  ON at `pressure: critical` answers image_cache_limit and
    image_cache_bytes 0, and a `render_frame` there equals OFF's; at
    `warning` the limit is physical // 8 // 16, at `normal` physical // 4 //
    16 (physical_bytes from the answer);
C4  `import_graphic_asset` replaces `ramp.png` with a second generated image
    on both instances; ON's `render_frame` then equals OFF's, and differs
    from ON's frame before the replacement;
Z1  `grep "Frame Job: "` over every log prints nothing.

    python3 tools/proof/image_cache_proof.py [--app PATH]
    python3 tools/proof/image_cache_proof.py --mutant NAME

`--mutant NAME`: each anchor must occur exactly once in its file. The graphic
mutants run `cargo test --release --test image_cache` in a copy of `graphic/`
under `work/image-cache/mutant/` (a sibling `app` symlink for the fonts, and
its own `CARGO_TARGET_DIR`, `work/image-cache-target/`, kept between runs) and
must fail their row's assertion: `name-key` (the digest taken over the name,
not the bytes) → I2; `premultiplied-copy` (the copy encodes the premultiplied
pixmap) → I1's bytes; `unchecked` (that, with the check removed) → I1's
pixels; `no-trim` (`set_image_cache_limit` evicts nothing) → I3;
`over-limit` (a copy over the limit is kept) → I4's bytes; `no-skip-marker`
(a copy over the limit leaves no `Skipped` entry) → I4's builds;
`no-building-recheck` (a build writes its copy whether or not its digest is
still `Building`) → I7, whose two builds of one digest straddle a limit of 0
under the crate's doc-hidden build hook (#329). The app
mutant `pressure-ignored` (`imageCacheLimit` always at `.normal`'s budget) is
built through `tree_copy.make_copy` and `build_app` and driven through every
row; it must fail C3. Exit 0 = caught, 1 = survived, 2 = the control could not
be performed (the copy did not build, the tests did not run, or C0 failed).

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row
passes.
"""

import argparse
import os
import shutil
import struct
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_prefetch_proof as gp  # noqa: E402
import playback_prefetch_proof as pp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/image-cache"
TARGET = ROOT / "tools/proof/work/image-cache-target"
APP = proof_app.binary()
FRAME = pp.FRAME
ROWS = ["C0", "C1", "C2", "C3", "C4", "Z1"]
CONTROLS = ("C0",)
FRAMES = [0, 7, 19, 33, 61, 97]
STEEL = ROOT / "graphic/tests/assets/steel.jpg"
OFF_SWITCH = ["-FrameJobGraphicImageCacheOff", "YES"]

CACHE_JS = """export const meta = { name: "Cache", durationInFrames: 120 };
export const schema = {};
export function render(frame, props, ctx) {
  const angle = (frame * 7) % 360;
  const opacity = 0.35 + 0.65 * ((frame % 10) / 10);
  const scale = 1 + frame / 60;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${ctx.width}" height="${ctx.height}">
  <rect width="${ctx.width}" height="${ctx.height}" fill="#203040"/>
  <image href="${asset("ramp.png")}" x="120" y="90" width="640" height="360"
    opacity="${opacity}" transform="rotate(${angle} 440 270)"/>
  <image href="${asset("steel.jpg")}" x="900" y="420" width="240" height="240"
    transform="translate(${frame * 3} 0) scale(${scale})"/>
</svg>`;
}
"""

IMAGES = "graphic/src/images.rs"
LIBRARY = "graphic/src/library.rs"
MEMORY = "app/Sources/GraphicPrefetch+Memory.swift"
PREMULTIPLIED = (IMAGES, "    let copy = encode(width, height, &rgba)?;\n",
                 "    let copy = encode(width, height, Pixmap::decode_png(original).ok()?.data())?;\n")
OVER_LIMIT_ARM = ("        Some(copy) if copy.len() > cache.limit => {\n"
                  "            cache.mark(asset.digest, Entry::Skipped { len: copy.len() })\n"
                  "        }\n")
# name: ([(file, anchor, replacement)], the row, the test, its failing message)
GRAPHIC_MUTANTS = {
    "name-key": (
        [(LIBRARY, "let digest = Sha256::digest(&data).into();",
          "let digest = Sha256::digest(name.as_bytes()).into();")],
        "I2", "i2_the_same_name_with_other_bytes_draws_its_own_pixel", "the green swatch"),
    "premultiplied-copy": (
        [PREMULTIPLIED], "I1", "i1_cached_copies_draw_the_original_pixels", "the cache holds"),
    "unchecked": (
        [PREMULTIPLIED, (IMAGES, "    same.then_some(copy)\n", "    let _ = same;\n    Some(copy)\n")],
        "I1", "i1_cached_copies_draw_the_original_pixels", "a cached draw differs"),
    "no-trim": (
        [(IMAGES, "    if bytes == 0 {\n        cache.entries.clear();\n        cache.bytes = 0;\n"
                  "    } else {\n        cache.trim();\n    }\n", "")],
        "I3", "i3_a_limit_of_zero_empties_the_cache",
        "a limit of 0 left bytes held"),
    "over-limit": (
        [(IMAGES, OVER_LIMIT_ARM,
          "        Some(copy) if copy.len() > cache.limit => {\n"
          "            let stamp = cache.tick();\n"
          "            cache.bytes += copy.len();\n"
          "            let copy = copy.clone();\n"
          "            cache.entries.insert(asset.digest, Entry::Ready { copy, stamp });\n"
          "        }\n")],
        "I4", "i4_a_copy_over_the_limit_is_kept_nowhere_and_not_rebuilt",
        "a copy over the limit was kept"),
    "no-skip-marker": (
        [(IMAGES, OVER_LIMIT_ARM,
          "        Some(copy) if copy.len() > cache.limit => {\n"
          "            cache.entries.remove(&asset.digest);\n"
          "        }\n")],
        "I4", "i4_a_copy_over_the_limit_is_kept_nowhere_and_not_rebuilt", "the copy was rebuilt"),
    "no-building-recheck": (
        [(IMAGES, "    if !matches!(cache.entries.get(&asset.digest), Some(Entry::Building)) {\n"
                  "        return built.map(usvg::ImageKind::PNG);\n"
                  "    }\n", "")],
        "I7", "i7_two_builds_of_one_digest_across_a_limit_of_zero_count_one_copy",
        "two builds of one digest counted its copy twice"),
}
APP_MUTANTS = {
    "pressure-ignored": (
        [(MEMORY, "budgetBytes / 16",
          "MemoryPressure.normal.budget(physical: Self.physicalBytes) / 16")], "C3"),
}

rows = {}


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'ok' if good else 'FAIL'} — {detail}", flush=True)


def png(width, height, rows_rgba):
    """An 8-bit RGBA PNG of `rows_rgba` (bytes per row), zlib at level 6."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    raw = b"".join(b"\x00" + row for row in rows_rgba)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def ramp(seed):
    """640×360: alpha rises left to right; colour varies with x, y and seed."""
    width, height = 640, 360
    rows_rgba = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            row += bytes(((x * 255 // width) ^ seed, y * 255 // height, (200 + seed) % 256,
                          x * 255 // (width - 1)))
        rows_rgba.append(bytes(row))
    return png(width, height, rows_rgba)


def fixture(client, package, ramp_png):
    """C: a new 30 fps project with the module, both assets and one clip,
    saved. (ok, detail)."""
    steps, bad = [], []

    def step(label, ok, detail=""):
        steps.append(f"{label} {'ok' if ok else 'FAILED ' + str(detail)}")
        if not ok:
            bad.append(label)

    made = gp.attempt(client, "new_project", {"path": str(package)})
    step("new", made["ok"], made.get("error"))
    gp.attempt(client, "set_canvas", {"project": str(package), "fps": [30, 1]})
    fps = gp.project_of(client, package).get("canvas", {}).get("fps")
    step("30 fps", fps == [30, 1], fps)
    for path in (ramp_png, STEEL):
        got = gp.attempt(client, "import_graphic_asset", {"project": str(package),
                                                          "path": str(path)})
        step(f"asset {path.name}", got["ok"], got.get("error"))
    wrote = gp.attempt(client, "write_graphic", {"project": str(package), "name": "cache",
                                                 "source": CACHE_JS})
    step("write", wrote["ok"] and isinstance(wrote["reply"], dict) and wrote["reply"].get("ok"),
         wrote.get("error", wrote.get("reply")))
    tracks = [t.get("id") for t in gp.project_of(client, package).get("tracks", [])]
    step("track", bool(tracks), tracks)
    if bad:
        return False, "; ".join(steps)
    ok, why = gp.land(client, package, "cache", tracks[0])
    step("clip", ok, why)
    saved = gp.attempt(client, "save_project", {"project": str(package)})
    step("saved", saved["ok"], saved.get("error"))
    return not bad, "; ".join(steps)


def frame_png(client, package, frame, out):
    """`render_frame` at `frame` written to `out`; its bytes, or None."""
    if out.exists():
        out.unlink()
    got = gp.attempt(client, "render_frame", {"project": str(package), "t": frame * FRAME,
                                              "path": str(out)})
    return out.read_bytes() if got["ok"] and out.exists() else None


def memory(client, **arguments):
    got = gp.attempt(client, "graphic_memory", arguments)
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) \
        else {"error": got.get("error", got.get("reply"))}


def replaced_frame(client, package, before, frame, out, seconds=10):
    """`render_frame` at `frame` after the replacement, asked again for up to
    `seconds` while it still answers `before`; the last bytes."""
    deadline = time.monotonic() + seconds
    while True:
        now = frame_png(client, package, frame, out)
        if (now is not None and now != before) or time.monotonic() >= deadline:
            return now
        time.sleep(0.5)


def side(app, name, package, extra, replacement):
    """One instance's half: open, C1's frames, C2's answer, C3 (ON only), C4.
    A dict of what it saw, or None when it did not open."""
    instance = pp.Instance(app, WORK / f"{name}.log", off=False, extra=extra)
    seen = {"frames": [], "memory": {}, "pressure": {}, "critical_frame": None,
            "before": None, "after": None, "replaced": None}
    try:
        client = instance.start()
        if client is None or not gp.opened(client, package):
            return None
        for frame in FRAMES:
            seen["frames"].append(frame_png(client, package, frame, WORK / f"{name}-{frame}.png"))
        seen["memory"] = memory(client)
        if name == "on":
            seen["pressure"]["critical"] = memory(client, pressure="critical")
            seen["critical_frame"] = frame_png(client, package, FRAMES[0],
                                               WORK / f"{name}-critical.png")
            seen["pressure"]["warning"] = memory(client, pressure="warning")
            seen["pressure"]["normal"] = memory(client, pressure="normal")
        seen["before"] = frame_png(client, package, FRAMES[2], WORK / f"{name}-before.png")
        got = gp.attempt(client, "import_graphic_asset", {
            "project": str(package), "path": str(replacement), "name": "ramp.png"})
        seen["replaced"] = got["reply"] if got["ok"] else {"error": got.get("error")}
        seen["after"] = replaced_frame(client, package, seen["before"], FRAMES[2],
                                       WORK / f"{name}-after.png")
    finally:
        instance.stop()
    return seen


def run_all(app):
    rows.clear()
    first, second = WORK / "ramp.png", WORK / "ramp2" / "ramp.png"
    second.parent.mkdir(parents=True, exist_ok=True)
    first.write_bytes(ramp(0))
    second.write_bytes(ramp(77))
    base = WORK / "C.framejob"
    maker = pp.Instance(app, WORK / "fixture.log", off=False, extra=OFF_SWITCH)
    try:
        client = maker.start()
        made, detail = fixture(client, base, first) if client else (False, "did not launch")
        if made:
            closed = gp.attempt(client, "close_project", {"project": str(base)})
            made, detail = closed["ok"], f"{detail}; close {closed.get('error', 'ok')}"
    finally:
        maker.stop()
    copies = {}
    if made:
        for name in ("off", "on"):
            copies[name] = WORK / f"C-{name}.framejob"
            shutil.copytree(base, copies[name], symlinks=True)
    off = side(app, "off", copies["off"], OFF_SWITCH, second) if made else None
    on = side(app, "on", copies["on"], [], second) if made else None
    check("C0", made and off is not None and on is not None,
          f"{detail}; OFF opened {off is not None}, ON opened {on is not None}")
    if off is None or on is None:
        for row in ROWS[1:-1]:
            check(row, False, "the control was not performed")
    else:
        drawn = all(f is not None for f in off["frames"] + on["frames"])
        equal = [a == b for a, b in zip(off["frames"], on["frames"])]
        check("C1", drawn and all(equal),
              f"frames {FRAMES}: drawn {drawn}, OFF == ON {equal}")
        mon, moff = on["memory"], off["memory"]
        budget = gp_field(mon, "budget_bytes")
        good = (gp_field(mon, "image_cache_bytes") or 0) > 0 and budget is not None \
            and gp_field(mon, "image_cache_limit") == budget // 16 \
            and gp_field(moff, "image_cache_bytes") == 0 \
            and gp_field(moff, "image_cache_limit") == 0
        check("C2", good, f"ON {pick(mon)}; OFF {pick(moff)}")
        crit, warn, norm = (on["pressure"].get(k, {}) for k in ("critical", "warning", "normal"))
        physical = gp_field(norm, "physical_bytes")
        good = gp_field(crit, "image_cache_limit") == 0 \
            and gp_field(crit, "image_cache_bytes") == 0 \
            and on["critical_frame"] is not None and on["critical_frame"] == off["frames"][0] \
            and physical is not None \
            and gp_field(warn, "image_cache_limit") == physical // 8 // 16 \
            and gp_field(norm, "image_cache_limit") == physical // 4 // 16
        check("C3", good,
              f"critical {pick(crit)}, its frame equals OFF's "
              f"{on['critical_frame'] is not None and on['critical_frame'] == off['frames'][0]}; "
              f"warning {pick(warn)}; normal {pick(norm)}; physical {physical}")
        replaced = all(isinstance(s["replaced"], dict) and "error" not in s["replaced"]
                       for s in (off, on))
        good = replaced and on["after"] is not None and on["after"] == off["after"] \
            and on["after"] != on["before"]
        check("C4", good,
              f"replaced on both {replaced}; ON after == OFF after "
              f"{on['after'] is not None and on['after'] == off['after']}; ON after != ON before "
              f"{on['after'] != on['before']}")
    complaints = gp.complaints()
    check("Z1", not complaints, f"{len(complaints)} complaint line(s) {complaints[:3]}")
    passed = sum(1 for row in ROWS if rows.get(row))
    print(f"{passed}/{len(ROWS)}")
    return passed == len(ROWS)


def gp_field(answer, key):
    return answer.get(key) if isinstance(answer, dict) and "error" not in answer else None


def pick(answer):
    keys = ("pressure", "budget_bytes", "image_cache_bytes", "image_cache_limit")
    if not isinstance(answer, dict) or "error" in answer:
        return answer
    return {key: answer.get(key) for key in keys}


def apply_anchors(copy, edits):
    """Each anchor replaced exactly once; None, or why not."""
    for path, anchor, replacement in edits:
        target = copy / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"{anchor!r} occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def run_graphic_mutant(name):
    edits, row, test, message = GRAPHIC_MUTANTS[name]
    print(f"image cache — the {name} MUTANT ({row}'s {test} must FAIL with {message!r})",
          flush=True)
    copy = WORK / "mutant"
    shutil.copytree(ROOT / "graphic", copy / "graphic",
                    ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "app", copy / "app")
    why = apply_anchors(copy, edits)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    got = bounded.run(["cargo", "test", "--release", "--test", "image_cache"], 1800,
                      cwd=str(copy / "graphic"),
                      env=bounded.child_env({"CARGO_TARGET_DIR": str(TARGET)}))
    output = got["stdout"] + got["stderr"]
    (WORK / f"mutant-{name}.log").write_text(output)
    if got["expired"] or "running 8 tests" not in output:
        errors = [line for line in output.splitlines() if line.startswith("error")][:5]
        print(f"mutant {name}: the control could not be performed — the tests did not run "
              f"(rc {got['rc']}, expired {got['expired']}): {errors}")
        return 2
    failed = f"test {test} ... FAILED" in output
    said = failed and any(message in block for block in output.split("---- ")
                          if block.startswith(test))
    for line in output.splitlines():
        if line.startswith("test ") and " ... " in line:
            print(f"  {line}")
    caught = failed and said
    print(f"the mutant is CAUGHT: {row} FAILED with {message!r}" if caught
          else f"the mutant was NOT caught (failed {failed}, its message {said})")
    return 0 if caught else 1


def run_app_mutant(name):
    edits, row = APP_MUTANTS[name]
    print(f"image cache — the {name} MUTANT ({row} must FAIL)", flush=True)
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        print(f"mutant {name}: the control could not be performed — {reason}")
        return 2
    why = apply_anchors(Path(made), edits)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    app, reason = tree_copy.build_app(Path(made), 1500)
    if app is None:
        print(f"mutant {name}: the control could not be performed — the copy was not built: "
              f"{reason}")
        return 2
    run_all(proof_app.executable(app))
    failed = [r for r in CONTROLS if not rows.get(r)]
    if failed:
        print(f"mutant {name}: the control could not be performed — {failed} failed")
        return 2
    caught = not rows.get(row)
    print(f"the mutant is CAUGHT: {row} FAILED" if caught else "the mutant was NOT caught")
    return 0 if caught else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted({**GRAPHIC_MUTANTS, **APP_MUTANTS}))
    args = parser.parse_args()
    tree_copy.remove_tree(WORK)
    WORK.mkdir(parents=True)
    if args.mutant in GRAPHIC_MUTANTS:
        return run_graphic_mutant(args.mutant)
    if args.mutant:
        return run_app_mutant(args.mutant)
    if not args.app.exists():
        print(f"the app is not built: {args.app}")
        return 1
    print("#127 G6 phase 5 — the decoded-image cache, OFF against ON, against the built app "
          "(proof)", flush=True)
    return 0 if run_all(args.app) else 1


if __name__ == "__main__":
    sys.exit(main())
