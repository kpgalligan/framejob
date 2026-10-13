#!/usr/bin/env python3
"""Road map "mattes" MT0 — the matte spike: what a matte costs the compositor,
and which of two routes an UNMATTED layer takes (spec §11 MT-6).

    python3 tools/proof/matte_spike/matte_spike.py --check                 # builds, 10 frames a scene, K3/K4
    python3 tools/proof/matte_spike/matte_spike.py --measure               # release-only kind: host gate, timings
    python3 tools/proof/matte_spike/matte_spike.py --check --mutant resolve-writes-one|anchor-missing
    python3 tools/proof/matte_spike/matte_spike.py --check --tree          # MT5: the tree's own shader
    python3 tools/proof/matte_spike/matte_spike.py --measure --tree        # MT5's record

Nothing is merged into `app/`. Three shaders are made in `work/matte_spike/<tag>/`
from `app/Resources/Shaders/Compositor.metal` as it stood at 464a3aa, before
MT2 (`git show`; a failed show is the scored FAILURE row B0): V0 that file;
V1 + the placeholder route (both layer entry points take `texture(1)` and step
7 multiplies the layer's coverage by its sample at the fragment's
canvas-normalised position, always); V2 + the function-constant route (the same
multiply behind `kMatte [[function_constant(1)]]`). Both add `MatteUniforms` and
`framejob_matte_resolve_fragment`. Every patch is applied at an anchor that must
occur EXACTLY once; a missing or repeated anchor is the scored FAILURE row B0.
Each is compiled with `xcrun metal` (B1). `bench.swift` is built over
`app/Sources` (for the app's own `LayerUniforms`) through
`swift_build.build(…, optimize=True)` (B2) — never a Debug build: this times
the GPU, so it is the release-only kind (spec §11 V-4), though it launches no
app.

Rows, per size (1920×1080, 3840×2160): K3/K4 (V1 and V2) read one pixel inside
and one outside the matte in S3 (the text as an alpha matte) and S4 (S3 plus a
gradient luma matte): inside = the picture's own bytes (S1's render), outside =
the background, ±1 — so a broken pass is never timed. `--measure` adds H0 (the
host gate: `pmset -g` powermode ≠ 1 and `pmset -g batt` on AC Power, read only;
else every timing row is a named SKIP and the run stops for the owner), C0 (the
CONTROL: two interleaved V0 series of S1, |Δ median| = the noise floor), T1 (the
route, recorded, never a failure), T2 (the cost: the route's S3 − S2 and
S4 − S2 within 0.50 ms at 1080p and 2.00 ms at 4K — the only stop) and M0 (the
memory, computed). A figure is the median of the runs' medians (200 frames
each, three runs, every series interleaved), with the runs' range beside it.
Exit 0 when every scored row passes, 1 when one fails, 2 when the host gate
stops the run. README: `tools/proof/README.md`, "Road map mattes — MT0".

`--tree` (MT5) measures what MT2 built instead of the two candidate routes: V0
is still the pinned pre-MT2 shader, and VT is the tree's own
`app/Resources/Shaders/Compositor.metal`, unpatched (B0 records that no patch
is made). K3/K4 score VT; T0 is VT's S1 overhead over V0 (what the placeholder
costs an unmatted layer in the shipped shader); T1 (the route) is not asked;
T2 scores VT's unmatted-against-matted frames (S3 − S2, S4 − S2) against the
same budget. No mutant runs with `--tree`.
"""

import argparse
import datetime
import json
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = PROOF.parents[1]
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(PROOF / "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

SHADER = "app/Resources/Shaders/Compositor.metal"
# The commit whose shader the anchors were written against: the shader as it
# stood before MT2 put route V1 into it (unchanged from b3dc3c2 through 464a3aa).
SHADER_COMMIT = "464a3aa"
WORK = PROOF / "work/matte_spike"
SIZES = [(1920, 1080), (3840, 2160)]
# The route's bound on V1's S1 overhead over V0 (ms): at 1080p the tree's
# smallest measured effect (a destination read, `Compositor.metal`'s cost
# notes); at 4K four times that.
BOUND = {1080: 0.02, 2160: 0.08}
# The matte's own cost budget (ms): S3 − S2 and S4 − S2. The only stop.
BUDGET = {1080: 0.50, 2160: 2.00}
MUTANTS = ("resolve-writes-one", "anchor-missing")

# ---- the shader patches -------------------------------------------------------

SIGNATURE_ANCHOR = """                                             texture2d<float> source,
                                             sampler samp) {"""
SIGNATURE_PATCH = """                                             texture2d<float> source,
                                             sampler samp,
                                             texture2d<float> matte) {"""

STEP7_ANCHOR = """        alpha *= clamp(0.5 - d / feather, 0.0, 1.0);
    }
"""
COVERAGE_NOTE = """    // (7c) The matte coverage (spec §11 MT-3, MT-6): the layer's coverage
    // times the resolved coverage texture at the fragment's canvas-normalised
    // position.
"""
COVERAGE = {
    "placeholder": COVERAGE_NOTE + """    alpha *= matte.sample(samp, canvasPixels(
        in.position.xy, float2(u.canvasPerDestX, u.canvasPerDestY))
        / max(float2(u.canvasWidth, u.canvasHeight), float2(1.0))).r;
""",
    "constant": COVERAGE_NOTE + """    if (kMatte) {
        alpha *= matte.sample(samp, canvasPixels(
            in.position.xy, float2(u.canvasPerDestX, u.canvasPerDestY))
            / max(float2(u.canvasWidth, u.canvasHeight), float2(1.0))).r;
    }
""",
}

PLAIN_ANCHOR = """                                       sampler samp [[sampler(0)]]) {
    return layerColorPremultiplied(in, u, source, samp);"""
PLAIN_PATCH = """                                       sampler samp [[sampler(0)]],
                                       texture2d<float> matte [[texture(1)]]) {
    return layerColorPremultiplied(in, u, source, samp, matte);"""

BLEND_ANCHOR = """                                             float4 dst [[color(0)]]) {
    float4 src = layerColorPremultiplied(in, u, source, samp);"""
BLEND_PATCH = """                                             float4 dst [[color(0)]],
                                             texture2d<float> matte [[texture(1)]]) {
    float4 src = layerColorPremultiplied(in, u, source, samp, matte);"""

CONSTANT_ANCHOR = "constant bool kGatherFilters [[function_constant(0)]];\n"
CONSTANT_PATCH = CONSTANT_ANCHOR + "constant bool kMatte [[function_constant(1)]];\n"

RESOLVE_RETURN = "    return float4(clamp(v, 0.0, 1.0));\n"
RESOLVE = """
// MARK: - Mattes (road map "mattes" MT0 spike, spec §11 MT-3, MT-6)

constant int kMatteNone          = 0;
constant int kMatteAlpha         = 1;
constant int kMatteAlphaInverted = 2;
constant int kMatteLuma          = 3;
constant int kMatteLumaInverted  = 4;

struct MatteUniforms {
    float mode;
    float reserved0;
    float reserved1;
    float reserved2;
};

// One matte's value at this pixel, multiplied into the r8 coverage by the
// pipeline (source factor zero, destination factor sourceColor).
fragment float4 framejob_matte_resolve_fragment(ShadowVaryings in [[stage_in]],
                                               constant MatteUniforms &u [[buffer(0)]],
                                               texture2d<float> mask [[texture(0)]]) {
    float4 m = mask.read(uint2(in.position.xy));
    int mode = int(u.mode + 0.5);
    float luma = dot(m.rgb, float3(0.2126, 0.7152, 0.0722));
    float v = 1.0;
    if (mode == kMatteAlpha) {
        v = m.a;
    } else if (mode == kMatteAlphaInverted) {
        v = 1.0 - m.a;
    } else if (mode == kMatteLuma) {
        v = luma;
    } else if (mode == kMatteLumaInverted) {
        v = 1.0 - luma;
    }
""" + RESOLVE_RETURN + "}\n"


def patches(route, mutant):
    """(name, anchor, replacement) for V1 ("placeholder") or V2 ("constant")."""
    coverage = COVERAGE[route]
    step7 = STEP7_ANCHOR
    if mutant == "anchor-missing" and route == "placeholder":
        step7 = step7.replace("feather", "feathr")
    rows = [("signature", SIGNATURE_ANCHOR, SIGNATURE_PATCH),
            ("step 7", step7, step7 + "\n" + coverage),
            ("plain entry", PLAIN_ANCHOR, PLAIN_PATCH),
            ("blend entry", BLEND_ANCHOR, BLEND_PATCH)]
    if route == "constant":
        rows.insert(0, ("function constant", CONSTANT_ANCHOR, CONSTANT_PATCH))
    return rows


def patched(source, route, mutant):
    """(text, None) or (None, why): every anchor exactly once, then the resolve
    appended."""
    text = source
    for name, anchor, replacement in patches(route, mutant):
        count = text.count(anchor)
        if count != 1:
            return None, f"the {name} anchor occurs {count} times, not once"
        text = text.replace(anchor, replacement)
    resolve = RESOLVE
    if mutant == "resolve-writes-one":
        resolve = resolve.replace(RESOLVE_RETURN, "    return float4(1.0);\n")
    return text + resolve, None


# ---- rows ---------------------------------------------------------------------

ROWS = []


def emit(row, verdict, detail):
    """verdict: PASS, FAIL (scored), SKIP (named), CONTROL or RECORD (figures)."""
    ROWS.append({"row": row, "verdict": verdict, "detail": detail})
    print(f"{row:<6} {verdict:<8} {detail}", flush=True)


def run(argv, seconds):
    return bounded.run([str(a) for a in argv], seconds, env=bounded.child_env())


# ---- building -----------------------------------------------------------------

def build_shaders(folder, mutant, tree=False):
    shown = subprocess.run(["git", "-C", str(ROOT), "show", f"{SHADER_COMMIT}:{SHADER}"],
                           capture_output=True, text=True)
    if shown.returncode != 0:
        emit("B0", "FAIL", f"git show {SHADER_COMMIT}:{SHADER} failed: {shown.stderr.strip()[-300:]}")
        return None
    # The commit predates rename R1: its entry points take the names the bench asks for.
    source = shown.stdout.replace("reelcut_", "framejob_")
    texts = {"V0": source}
    if tree:
        texts["VT"] = (ROOT / SHADER).read_text()
        emit("B0", "PASS", f"--tree: V0 the shader at {SHADER_COMMIT}, VT the tree's own {SHADER}, "
             "unpatched (no anchor asked)")
    for name, route in () if tree else (("V1", "placeholder"), ("V2", "constant")):
        text, why = patched(source, route, mutant)
        if text is None:
            emit("B0", "FAIL", f"{name} ({route} route): {why}")
            return None
        texts[name] = text
    if not tree:
        emit("B0", "PASS", "V1 and V2 patched, every anchor exactly once")
    libs = {}
    for name, text in texts.items():
        metal, air, lib = folder / f"{name}.metal", folder / f"{name}.air", folder / f"{name}.metallib"
        metal.write_text(text)
        step = run(["xcrun", "-sdk", "macosx", "metal", "-c", metal, "-o", air], 300)
        if step["rc"] == 0 and not step["expired"]:
            step = run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib], 300)
        if step["expired"] or step["rc"] != 0 or not lib.exists():
            emit("B1", "FAIL", f"{name} did not compile: "
                 f"{'expired' if step['expired'] else step['stderr'][-600:]}")
            return None
        libs[name] = lib
    emit("B1", "PASS", f"{', '.join(texts)} metallibs in {folder.relative_to(ROOT)}")
    return libs


def build_bench():
    folder = WORK / "bench"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    source = (HERE / "bench.swift").read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    try:
        built = swift_build.build(sources=swift_build.app_sources() + [entry],
                                  output=folder / "matte_bench", defines=["FRAMEJOB_DEV_TOOLS"],
                                  optimize=True, timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        emit("B2", "FAIL", f"the bench did not build (-O): {error.diagnostics[:6]}")
        return None
    emit("B2", "PASS", f"bench {'reused' if built.reused else f'built in {built.seconds} s'} "
         f"(-O, over app/Sources) — {built.binary.relative_to(ROOT)}")
    return built.binary


# ---- the host gate ------------------------------------------------------------

def host_gate():
    """(ok, text): read only — `pmset -g` and `pmset -g batt`, never a setting."""
    general = run(["pmset", "-g"], 30)
    battery = run(["pmset", "-g", "batt"], 30)
    mode = re.search(r"^\s*powermode\s+(\d+)", general["stdout"], re.M)
    source = re.search(r"Now drawing from '([^']+)'", battery["stdout"])
    mode_text = mode.group(1) if mode else "absent"
    source_text = source.group(1) if source else "unknown"
    ok = mode is not None and mode.group(1) != "1" and source_text == "AC Power"
    return ok, f"powermode {mode_text}; drawing from {source_text}"


# ---- one size -----------------------------------------------------------------

def bench(binary, libs, size, folder, frames, runs, warmup):
    w, h = size
    out = folder / f"bench-{h}.json"
    out.unlink(missing_ok=True)
    argv = [binary] + [x for name, lib in libs.items() for x in ("--lib", f"{name}={lib}")]
    argv += ["--width", w, "--height", h, "--frames", frames, "--runs", runs,
             "--warmup", warmup, "--out", out]
    ran = run(argv, 600)
    if ran["expired"] or ran["rc"] != 0 or not out.exists():
        emit(f"R{h}", "FAIL", f"the bench at {w}×{h} "
             f"{'ran past 600 s' if ran['expired'] else 'exited ' + str(ran['rc'])}: "
             f"{ran['stderr'][-600:]}")
        return None
    return json.loads(out.read_text())


def k_rows(answer, h, variants):
    ok_all = True
    for row in ("K3", "K4"):
        for variant in variants:
            entries = [k for k in answer["k"] if k["row"] == row and k["variant"] == variant]
            ok = len(entries) == 2 and all(k["ok"] for k in entries)
            ok_all &= ok
            detail = "; ".join(
                f"{k['side']} ({k.get('x')},{k.get('y')}) got {k.get('got_bgra')} "
                f"want {k.get('want_bgra')}" if "got_bgra" in k else f"{k['side']}: {k['detail']}"
                for k in entries)
            emit(f"{row}", "PASS" if ok else "FAIL", f"{h}p {variant}: {detail}")
    return ok_all


def figure(answer, series):
    medians = [s["median"] for s in answer["samples"][series]]
    return statistics.median(medians), min(medians), max(medians)


def ms(value):
    return f"{value:.3f} ms"


# ---- main ---------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--measure", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS)
    parser.add_argument("--tree", action="store_true",
                        help="measure the tree's own shader (VT) against the pre-MT2 one (MT5)")
    args = parser.parse_args()
    if args.mutant and args.measure:
        parser.error("a mutant runs with --check")
    if args.mutant and args.tree:
        parser.error("no mutant runs with --tree")
    matte_variants = ("VT",) if args.tree else ("V1", "V2")

    tag = f"mutant-{args.mutant}" if args.mutant else ("measure" if args.measure else "check")
    if args.tree:
        tag = f"tree-{tag}"
    folder = WORK / tag
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    started = datetime.datetime.now().astimezone()
    print(f"matte_spike {tag} at {started:%Y-%m-%d %H:%M %Z}", flush=True)

    timing = args.measure
    host_text = None
    if args.measure:
        ok, host_text = host_gate()
        emit("H0", "PASS" if ok else "SKIP", host_text if ok else
             f"{host_text}: the host gate is shut, so every timing row is skipped"
             + (" (MT5's record is a named skip)" if args.tree else " and MT0 stops for the owner"))
        timing = ok

    libs = build_shaders(folder, args.mutant, args.tree)
    binary = build_bench() if libs else None
    answers = {}
    scored_ok = libs is not None and binary is not None
    if scored_ok:
        frames, runs, warmup = (200, 3, 5) if timing else (10, 1, 1)
        for size in SIZES:
            answer = bench(binary, libs, size, folder, frames, runs, warmup)
            if answer is None:
                scored_ok = False
                continue
            answers[size[1]] = answer
            scored_ok &= k_rows(answer, size[1], matte_variants)

    result = {"tag": tag, "started": started.isoformat(), "host": host_text, "rows": ROWS,
              "answers": {str(h): a for h, a in answers.items()}}
    if args.measure and not timing:
        for row in ("C0", "T2") if args.tree else ("C0", "T1", "T2"):
            emit(row, "SKIP", "the host gate is shut (H0)")
    elif timing and scored_ok and len(answers) == len(SIZES):
        result["figures"] = figures = {}
        overheads = {}
        for w, h in SIZES:
            answer = answers[h]
            f = {s: figure(answer, s) for s in answer["samples"]}
            noise = abs(f["V0:S1"][0] - f["V0b:S1"][0])
            over = {v: f[f"{v}:S1"][0] - f["V0:S1"][0] for v in matte_variants}
            overheads[h] = (over, noise)
            figures[h] = {"series": {s: {"median": m, "low": lo, "high": hi}
                                     for s, (m, lo, hi) in f.items()},
                          "noise": noise, "overhead": over, "gpu": answer["gpu"]}
            emit("C0", "CONTROL", f"{h}p V0 S1 twice: {ms(f['V0:S1'][0])} "
                 f"({ms(f['V0:S1'][1])}–{ms(f['V0:S1'][2])}) and {ms(f['V0b:S1'][0])} "
                 f"({ms(f['V0b:S1'][1])}–{ms(f['V0b:S1'][2])}): noise floor {ms(noise)}")
            for s in sorted(f):
                emit("F", "RECORD", f"{h}p {s}: {ms(f[s][0])} (runs {ms(f[s][1])}–{ms(f[s][2])})")
            emit("T0", "RECORD", f"{h}p S1 overhead over V0: "
                 + ", ".join(f"{v} {ms(over[v])}" for v in matte_variants)
                 + f" (bound {BOUND[h]:.2f} ms + noise {ms(noise)})")
        v1_fits = not args.tree and all(
            overheads[h][0]["V1"] <= BOUND[h] + overheads[h][1] for _, h in SIZES)
        if args.tree:
            route = "VT"
        elif v1_fits:
            route = "V1"
            why = "V1's S1 overhead is within bound + noise at both sizes"
        else:
            route = min(("V1", "V2"), key=lambda v: overheads[2160][0][v])
            why = (f"V1's S1 overhead passes bound + noise at "
                   f"{[h for _, h in SIZES if overheads[h][0]['V1'] <= BOUND[h] + overheads[h][1]]}"
                   f" only; {route} has the smaller S1 overhead at 4K")
        result["route"] = route
        if not args.tree:
            emit("T1", "RECORD", f"route {route} "
                 f"({'placeholder' if route == 'V1' else 'function constant'}): {why}")
        for w, h in SIZES:
            f = figures[h]["series"]
            s2 = f[f"{route}:S2"]["median"]
            c3 = f[f"{route}:S3"]["median"] - s2
            c4 = f[f"{route}:S4"]["median"] - s2
            figures[h]["cost"] = {"S3-S2": c3, "S4-S2": c4}
            ok = c3 <= BUDGET[h] and c4 <= BUDGET[h]
            scored_ok &= ok
            emit("T2", "PASS" if ok else "FAIL",
                 f"{h}p {route}: S3 − S2 {ms(c3)}, S4 − S2 {ms(c4)} (budget {BUDGET[h]:.2f} ms; "
                 f"noise {ms(figures[h]['noise'])})")
    for w, h in SIZES:
        emit("M0", "RECORD", f"{w}×{h}: {4 * w * h / 1e6:.1f} MB per matte (bgra8), "
             f"{w * h / 1e6:.1f} MB per coverage (r8)")

    result["exit"] = 0 if scored_ok else 1
    if args.measure and not timing:
        result["exit"] = 2
    (folder / "result.json").write_text(json.dumps(result, indent=1, sort_keys=True))
    failed = sorted({r["row"] for r in ROWS if r["verdict"] == "FAIL"})
    if args.mutant:
        print(f"mutant {args.mutant}: {'killed by ' + ', '.join(failed) if failed else 'SURVIVED'}")
    print(f"matte_spike {tag}: {'all scored rows pass' if scored_ok else 'FAILED ' + ', '.join(failed)}"
          f"{'; STOP: the host gate is shut' if result['exit'] == 2 else ''} "
          f"— {(folder / 'result.json').relative_to(ROOT)}")
    return result["exit"]


if __name__ == "__main__":
    sys.exit(main())
