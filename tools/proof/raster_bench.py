#!/usr/bin/env python3
"""Issue #127 G6 phase 6 — the in-place raster's spike: how much of a
graphic frame's raster time sits outside resvg's own render (the pixmap's
allocation and first touch, the RGBA→BGRA copy, the Swift buffer's
zero-fill and the copy into the texture), and the verdict of the stop rule
written before the baseline.

    python3 tools/proof/raster_bench.py PACKAGE [--from 25120000] [--module NAME]
                                        [--frames 40] [--rounds 5] [--iterations 40]
    python3 tools/proof/raster_bench.py --mutant {no-clear,no-swap,padded-in-place}

The package is COPIED under `tools/proof/work/raster-bench/` and only the
copy is opened (`image_cache_bench.dump_scene`: one owned instance, stopped
by PID, `--frames` evenly spaced SVG frames of the graphic clip covering
`--from` on the frontmost track, or of `--module`'s clip there). The probe
`raster_upload_probe.swift` is built through `swift_build.build(optimize=
True)`; a failed build is a scored FAIL. Then `pmset -g`'s powermode line
and `sysctl -n vm.loadavg` are printed, `cd graphic && cargo test --release
--test image_bench -- --ignored --nocapture --exact
section_scene_raster_overhead` runs over the dump (single-threaded), and
the probe at the dump's size for `--iterations`. Both outputs are printed
whole, then the per-frame figures (f frames; Z, U, M the probe's zero,
upload and texture medians):

    row = row_ms/f, alloc = alloc_ms/f, swz = swizzle_ms/f, cs = clearswap_ms/f
    net = max(0, alloc + swz − cs), copy = max(0, U − M), F = row + Z + U
    outside = net + Z + copy, share = outside/F, rust = net/F,
    swift = (Z + copy)/F, spread = row_spread, inplace saving = 1 − row_ms/padded_ms

then the load average again and one `verdict:` line: STOP if share < 0.03
or share ≤ spread; else BUILD if rust ≥ 0.03 and rust > spread; else SWIFT
if swift ≥ 0.03 and swift > spread; else STOP. Every child runs under
`graphics_spike/bounded.py`.

Exit 0 iff the dump, the build, the bench (its assertion: every frame's
ROW bytes equal PADDED's rows) and the probe all succeeded; the verdict
does not set it.

`--mutant NAME` copies `graphic/` (without `target`) to
`work/raster-bench/mutant/` beside an `app` symlink, replaces each of its
anchors in `src/raster.rs` exactly once, and runs `cargo test --release
--test pixels` there with its own target dir (`work/raster-bench-target/`,
kept between runs): `no-clear` must fail R1, `no-swap`
`a_rect_draws_in_bgra_and_nothing_else_is_touched`, `padded-in-place` R2 or
`bytes_past_the_row_are_untouched`. Exit 0 caught, 1 survived, 2 the
control was not performed. The anchors are the in-place route's, which the
spike's STOP (2026-10-22) left unbuilt: today each occurs 0 times in
`raster.rs` and every mutant answers 2.
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_prefetch_proof as gp  # noqa: E402
import image_cache_bench  # noqa: E402
import swift_build  # noqa: E402
from image_cache_proof import apply_anchors  # noqa: E402

WORK = ROOT / "tools/proof/work/raster-bench"
TARGET = ROOT / "tools/proof/work/raster-bench-target"
PROBE_SOURCE = ROOT / "tools/proof/raster_upload_probe.swift"
# Outside WORK, which every dump empties; swift_build's cache reuses an unchanged build.
PROBE_DIR = ROOT / "tools/proof/work/raster-upload-probe"
BENCH_BOUND = 3600
PROBE_BOUND = 600
THRESHOLD = 0.03
RASTER = "graphic/src/raster.rs"
R1 = "a_dirty_row_buffer_draws_as_a_clean_one"
R2 = "the_row_and_padded_strides_draw_the_same_rows"
MUTANTS = {
    "no-clear": ([(RASTER, "pixmap.data_mut().fill(0);", "")], [R1]),
    "no-swap": ([(RASTER, "pixel.swap(0, 2);", "")],
                ["a_rect_draws_in_bgra_and_nothing_else_is_touched"]),
    "padded-in-place": ([(RASTER, "if stride == row {", "if stride >= row {")],
                        [R2, "bytes_past_the_row_are_untouched"]),
}


def build_probe():
    """The probe as `main.swift` over every other file in `app/Sources`,
    optimized. (the binary or None, why not)."""
    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    entry = PROBE_DIR / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    binary = PROBE_DIR / "raster_upload_probe"
    try:
        swift_build.build(sources=swift_build.app_sources() + [entry], output=binary,
                          optimize=True, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"{error} {(error.diagnostics or ['(no output)'])[:6]}")
    return binary, ""


def last_json(text, prefix=""):
    """The last line of `text` that starts with `prefix`, as JSON, or None."""
    for line in reversed(text.strip().splitlines()):
        if line.startswith(prefix):
            try:
                return json.loads(line[len(prefix):])
            except ValueError:
                return None
    return None


def figures(result, probe):
    """The per-frame arithmetic of the docstring, every value in ms or a ratio."""
    f = result["frames"]
    row, alloc = result["row_ms"] / f, result["alloc_ms"] / f
    swz, cs = result["swizzle_ms"] / f, result["clearswap_ms"] / f
    zero, upload, texture = probe["zero_ms"], probe["upload_ms"], probe["texture_ms"]
    net = max(0.0, alloc + swz - cs)
    copy = max(0.0, upload - texture)
    frame = row + zero + upload
    outside = net + zero + copy
    return {"row": row, "alloc": alloc, "swz": swz, "cs": cs, "net": net, "Z": zero,
            "U": upload, "M": texture, "copy": copy, "F": frame, "outside": outside,
            "share": outside / frame, "rust": net / frame, "swift": (zero + copy) / frame,
            "spread": result["row_spread"], "padded_spread": result["padded_spread"],
            "inplace saving": 1 - result["row_ms"] / result["padded_ms"]}


def verdict(fig):
    share, rust, swift, spread = fig["share"], fig["rust"], fig["swift"], fig["spread"]
    if share < THRESHOLD or share <= spread:
        return "STOP", f"share {share:.4f} is under {THRESHOLD} or within spread {spread:.4f}"
    if rust >= THRESHOLD and rust > spread:
        return "BUILD", f"rust {rust:.4f} ≥ {THRESHOLD} and > spread {spread:.4f}"
    if swift >= THRESHOLD and swift > spread:
        return "SWIFT", f"swift {swift:.4f} ≥ {THRESHOLD} and > spread {spread:.4f}"
    return "STOP", (f"share {share:.4f} clears the rule but neither rust {rust:.4f} nor "
                    f"swift {swift:.4f} does (spread {spread:.4f})")


def run_bench(args):
    source = args.package.expanduser().resolve()
    named = f" ({args.module})" if args.module else ""
    print(f"#127 G6 phase 6 — the raster bench of {source.name} at {args.at}{named}",
          flush=True)
    ok, out, detail = image_cache_bench.dump_scene(source, args.at, args.frames, WORK,
                                                   args.module)
    if not ok:
        print(f"bench FAIL — {detail}")
        return 1
    print(f"  dump ok — {detail}", flush=True)
    binary, why = build_probe()
    if binary is None:
        print(f"bench FAIL — the probe did not build: {why}")
        return 1
    print(f"  probe built: {binary}", flush=True)
    power = bounded.run(["pmset", "-g"], 30)["stdout"]
    print("  " + next((line.strip() for line in power.splitlines() if "powermode" in line),
                      "powermode: not reported"), flush=True)
    print(f"  load average {gp.loadavg()}", flush=True)
    bench = bounded.run(
        ["cargo", "test", "--release", "--test", "image_bench", "--", "--ignored",
         "--nocapture", "--exact", "section_scene_raster_overhead"],
        BENCH_BOUND, cwd=str(ROOT / "graphic"),
        env=bounded.child_env({"GRAPHIC_IMAGE_BENCH": str(out),
                               "GRAPHIC_IMAGE_BENCH_ROUNDS": str(args.rounds)}))
    print(bench["stdout"], flush=True)
    bench_ok = bench["rc"] == 0 and not bench["expired"]
    if not bench_ok:
        print(bench["stderr"][-4000:])
    result = last_json(bench["stdout"], "RESULT ") if bench_ok else None
    probe, probe_ok = None, False
    if result is not None:
        ran = bounded.run([str(binary), str(result["width"]), str(result["height"]),
                           str(args.iterations)], PROBE_BOUND)
        print(f"  probe: {ran['stdout'].strip()}", flush=True)
        if ran["rc"] != 0 or ran["expired"]:
            print(ran["stderr"][-2000:])
        probe = last_json(ran["stdout"])
        probe_ok = (ran["rc"] == 0 and not ran["expired"] and isinstance(probe, dict)
                    and "error" not in probe)
    if result is not None and probe_ok:
        fig = figures(result, probe)
        print("  per frame (ms): " + ", ".join(
            f"{key} {fig[key]:.3f}" for key in
            ("row", "alloc", "swz", "cs", "net", "Z", "U", "M", "copy", "F", "outside")),
            flush=True)
        print("  ratios: " + ", ".join(
            f"{key} {fig[key]:.4f}" for key in
            ("share", "rust", "swift", "spread", "padded_spread", "inplace saving")),
            flush=True)
    print(f"  load average after {gp.loadavg()}", flush=True)
    if result is not None and probe_ok:
        word, why = verdict(fig)
        print(f"verdict: {word} — {why}")
    else:
        print("verdict: none — the bench or the probe did not answer")
    good = bench_ok and result is not None and probe_ok
    print(f"bench {'ok' if good else 'FAIL'} — cargo exited {bench['rc']}"
          f"{' (expired)' if bench['expired'] else ''} in {bench['seconds']} s; "
          f"probe {'ok' if probe_ok else 'FAIL'}")
    return 0 if good else 1


def run_mutant(name):
    edits, tests = MUTANTS[name]
    print(f"raster bench — the {name} MUTANT ({' or '.join(tests)} must FAIL)", flush=True)
    copy = WORK / "mutant"
    if copy.exists():
        shutil.rmtree(copy)
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "graphic", copy / "graphic", ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "app", copy / "app")
    why = apply_anchors(copy, edits)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    got = bounded.run(["cargo", "test", "--release", "--test", "pixels"], 1800,
                      cwd=str(copy / "graphic"),
                      env=bounded.child_env({"CARGO_TARGET_DIR": str(TARGET)}))
    output = got["stdout"] + got["stderr"]
    (WORK / f"mutant-{name}.log").write_text(output)
    if got["expired"] or not any(f"test {test} ... " in output for test in tests):
        errors = [line for line in output.splitlines() if line.startswith("error")][:5]
        print(f"mutant {name}: the control could not be performed — the tests did not run "
              f"(rc {got['rc']}, expired {got['expired']}): {errors}")
        return 2
    for line in output.splitlines():
        if line.startswith("test ") and " ... " in line:
            print(f"  {line}")
    failed = [test for test in tests if f"test {test} ... FAILED" in output]
    print(f"the mutant is CAUGHT: {', '.join(failed)} FAILED" if failed
          else "the mutant was NOT caught")
    return 0 if failed else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path, nargs="?")
    parser.add_argument("--from", dest="at", type=int, default=25_120_000)
    parser.add_argument("--module", default=None)
    parser.add_argument("--frames", type=int, default=40)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=40)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mutant:
        return run_mutant(args.mutant)
    if args.package is None:
        parser.error("PACKAGE is required unless --mutant is given")
    return run_bench(args)


if __name__ == "__main__":
    sys.exit(main())
