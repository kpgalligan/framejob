#!/usr/bin/env python3
"""Road map "grading" GR0 — the grading spike: what tone and a 3D LUT cost an
UNGRADED and a graded layer in the tree's own compositor shader under three
routes, and whether a 10-bit biplanar source wins back deep decode's heavy-4K
cost (#258). Both choosing rules are written in `archive/grading.md` ("GR0's
rules, written before measuring") with the constants below.

    python3 tools/proof/grading_spike/grading_spike.py --check [--mutant NAME]   # 10 frames, 1 run: B0–B2, K1–K5
    python3 tools/proof/grading_spike/grading_spike.py --measure [--seed N]      # adds H0, C0, C1, F, T0–T2, P1, X0, X1, D1

Nothing is merged into `app/`. Every shader is made in
`work/grading_spike/<tag>/` from `app/Resources/Shaders/Compositor.metal` as it
stood at `SHADER_COMMIT` 4d742cc, the tree GR0 measured (pinned in grading GR2,
when the tree's own shader took tone: `git show`, matte_spike's pattern; a
failed show is the scored FAILURE row B0): V0 that shader unpatched; VF-T and VF-TL
(tone, and tone plus a look, behind a uniform flag that joins the effects sum,
at step 4c/4d before `// (5) The four point filters`); VC-T and VC-TL (the same
stages behind function constants `kTone` 2 and `kLook` 3); VA-T and VA-TL (always
on, no branch, before `// (7b) Coverage.`: an ungraded layer carries neutral
values and an identity 2³ look at amount 0); VE (VF-TL with exposure and white
balance on encoded values, only to price the linear-light step); VB (#258:
`kBiplanar` function constant 4, the chroma plane at `texture(3)`, threaded
through every `texture2d<float> source` signature and `source, samp` call by
token rewrite, BT.709 video-range YCbCr → RGB in `layerSample`). Every grading
variant appends 16 floats to `LayerUniforms`, takes `texture3d<float> look
[[texture(2)]]` on both layer entry points and the stage, and gains the
helpers; each TL variant (and VE) appends `framejob_adjust_fragment`, which
reads `[[color(0)]]` with blending off. Every anchor must occur exactly once
and every token rewrite must hit its pinned count; otherwise B0 fails naming
it. Each is compiled with `xcrun metal` (B1); `bench.swift` is built over
`app/Sources` through `swift_build.build(…, optimize=True)` (B2).

Scored rows, per size (1920×1080, 3840×2160), taken before any timing: K1 every
grading variant's ungraded S1 = V0's S1 within 1/1023 over the whole frame; K2
per route variant, a flat 0.5 grey at +1 EV = encode(min(1, 2·decode(0.5))) ±
1/255; K3 per TL route, an identity 33³ look at amount 1 = amount 0 within
1/1023, and a channel-swap look on (0.2, 0.5, 0.8) gives (0.8, 0.5, 0.2) ±
1/255; K4 per TL route, the adjustment pass at +1 EV over a 256-column grey
ramp = encode(min(1, 2·decode(i/255))) ± 1/255, column by column; K5 an 8-band
colour bar in four IOSurface-backed buffer forms, wrapped through a
`CVMetalTextureCache`: X420 and X422 band centres = H16's ± 2/255, B8's ±
1/255.

`--measure` adds H0 (the host gate, read only: `pmset -g` powermode ≠ 1 and
`pmset -g batt` on AC; the CPU, macOS, GPU and load before and after), C0 (the
CONTROL |V0:S1 − V0b:S1|), C1 (the CONTROL |H16 − H16b| on SH), F (every series:
the median of three runs' medians, 200 frames each, with the runs' range), T0
(each variant's S1 overhead over V0), T1 (the route, a RECORD), T2 (ST and STL
over S1 per route, the linear step VF-TL:STL − VE:STL, and SA − S1), P1 (−1 EV
then +1 EV as two adjustment passes over the ramp: distinct levels and max |Δ|
through `rgba16Float`, and as a CONTROL through `bgra8Unorm`), X0 (the SH
figures), X1 (#258's outcome, a RECORD) and D1 (frames per second decoding two
2 s 3840×2160 fixtures into each of four formats, interleaved, three runs).
Exit 0 when every scored row passes, 1 when one fails, 2 when the host gate is
shut. README: `tools/proof/grading_spike/README.md`.

`--tree` (grading GR7a) measures what the branch built instead of the routes,
matte_spike's `--tree` pattern: V0 is `Compositor.metal` at `--tree-base REV`
(default `TREE_BASE` f407f87, main at the grading branch point; grading-2 G2-2
passes the commit before its own change; `git show`, a failed show is B0), VT
the tree's own file unpatched; both compiled (B1) and timed by
`tree_bench.swift` (B2), which hands both the app's whole 512-byte
`LayerUniforms` (464 until grading-2 G2-2). KT, scored at
both sizes: VT:S1 = V0:S1 within 1/1023 over the frame; KA (grading-2 G2-4):
VT:SA = V0:SA, the scene S1 then one unqualified adjustment pass at +1 EV with a
neutral `QualifierUniforms` at `buffer(1)`. A base whose shader names no
`framejob_adjust_fragment` (one before grading GR4a's adjustment pass, the
default f407f87 among them) has no V0:SA: B0 says so, the bench runs with
`--adjust 0`, and KA (and `--measure`'s TA) is a SKIP by name at each size,
which leaves the verdict to KT (issue #284). `--measure --tree` adds
H0, C0, F, T0 (VT:S1 − V0:S1), TC (a RECORD: T0 ≤ `BOUND[h]` + C0, "What it
may cost"'s UNGRADED-layer cap) and TA (a RECORD: VT:SA − V0:SA ≤ `BOUND[h]` +
the SA series' own C0). Grading-4 T4-4 (spec §11 GR-35) adds TB, a RECORD at
both sizes: tree_bench's VT:SQ2, VT:SQ8 and VT:SQ24 (the adjustment pass reading
a selection map blurred at σ 2, 8 and 24 destination pixels) each less VT:SQ
(the same pass with the qualifier inline), beside the SA noise floor (C0's, the
S1 one when there is no SA). Mutant `tree-graded` (VT drawn at +0.5 EV with
`toneEnabled` 1) must fail KT. Output under `work/grading_spike/tree-<check|
measure|mutant-NAME>/`.

    python3 tools/proof/grading_spike/grading_spike.py --check --tree [--mutant tree-graded]
    python3 tools/proof/grading_spike/grading_spike.py --measure --tree [--tree-base REV]
"""

import argparse
import datetime
import json
import random
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
import bt709_fixture  # noqa: E402
import swift_build  # noqa: E402

# ---- the rules' constants (archive/grading.md, "GR0's rules") -----------------

BOUND = {1080: 0.02, 2160: 0.06}
ROUTE_ORDER = ("VA", "VF", "VC")
WIN_SHARE = 0.5

SHADER = "app/Resources/Shaders/Compositor.metal"
SHADER_COMMIT = "4d742cc"
TREE_BASE = "f407f87"   # --tree: main at the grading branch point (GR7a)
TREE_MUTANTS = ("tree-graded",)
WORK = PROOF / "work/grading_spike"
SIZES = [(1920, 1080), (3840, 2160)]
MUTANTS = ("anchor-missing", "exposure-encoded", "lut-axes-swapped",
           "adjust-ignores-destination", "biplanar-full-range", "neutral-drift")
ROUTE_VARIANTS = ("VF-T", "VF-TL", "VC-T", "VC-TL", "VA-T", "VA-TL")
TL_ROUTES = ("VF-TL", "VC-TL", "VA-TL")
GRADING = ROUTE_VARIANTS + ("VE",)
SH_SERIES = ("B8", "H16", "H16b", "X420", "X422", "VB0")
DECODE_FORMATS = ("32BGRA", "64RGBAHalf", "x420", "x422")
DEFAULT_SEED = 20261009

# ---- the shader patches -------------------------------------------------------

UNIFORMS_ANCHOR = "    float canvasPerDestX;\n    float canvasPerDestY;\n};\n"
GRADE_FIELDS = "".join(f"    float {name};\n" for name in (
    "exposure", "temperature", "tint", "highlights", "shadows", "whites", "blacks",
    "vibrance", "fade", "toneEnabled", "lookAmount", "lookEnabled", "lookSize",
    "reserved0", "reserved1", "reserved2"))
UNIFORMS_PATCH = UNIFORMS_ANCHOR[:-3] + (
    "    // ── The grading spike's 16 floats (road map grading GR0; not the product).\n"
    + GRADE_FIELDS + "};\n")

HELPERS_ANCHOR = "// MARK: - The layer fragment stage\n"
TONE_LINEAR = """    float3 lin = gradeDecode(rgb) * exp2(u.exposure) * gains;
    rgb = gradeEncode(lin);
"""
TONE_ENCODED = """    rgb = clamp(rgb * exp2(u.exposure) * gains, 0.0, 1.0);
"""
LOOK_SAMPLE = "look.sample(samp, rgb * (n - 1.0) / n + 0.5 / n)"
HELPERS = """// MARK: - Grading (road map grading GR0's spike, textbook formulas only)

// The sRGB transfer functions (IEC 61966-2-1), on [0, 1].
static inline float3 gradeDecode(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return select(pow((c + 0.055) / 1.055, float3(2.4)), c / 12.92, c <= 0.04045);
}

static inline float3 gradeEncode(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c <= 0.0031308);
}

// Tone: exposure and white balance in local linear light, the curve and
// saturation shapes on encoded values. Neutral (all zero) is the identity.
static inline float3 gradeTone(float3 rgb, constant LayerUniforms &u) {
    float3 gains = exp2(float3(0.3 * u.temperature, -0.3 * u.tint, -0.3 * u.temperature));
""" + TONE_LINEAR + """    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb += 0.25 * u.highlights * smoothstep(0.5, 1.0, luma)
         + 0.25 * u.shadows * (1.0 - smoothstep(0.0, 0.5, luma));
    rgb += 0.15 * u.whites * rgb + 0.15 * u.blacks * (1.0 - rgb);
    float spread = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b));
    luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = mix(float3(luma), rgb, 1.0 + u.vibrance * (1.0 - saturate(spread)));
    rgb = mix(rgb, rgb * 0.85 + 0.1, u.fade);
    return rgb;
}

// The look: a 3D lattice of side n, sampled at the texel centres' span.
static inline float3 gradeLook(float3 rgb, texture3d<float> look, sampler samp,
                               constant LayerUniforms &u) {
    float n = max(u.lookSize, 2.0);
    return mix(rgb, """ + LOOK_SAMPLE + """.rgb, u.lookAmount);
}

"""

STAGE_SIG_ANCHOR = ("                                             sampler samp,\n"
                    "                                             texture2d<float> matte) {")
STAGE_SIG_PATCH = ("                                             sampler samp,\n"
                   "                                             texture2d<float> matte,\n"
                   "                                             texture3d<float> look) {")
PLAIN_ANCHOR = ("                                       texture2d<float> matte [[texture(1)]]) {\n"
                "    return layerColorPremultiplied(in, u, source, samp, matte);")
PLAIN_PATCH = ("                                       texture2d<float> matte [[texture(1)]],\n"
               "                                       texture3d<float> look [[texture(2)]]) {\n"
               "    return layerColorPremultiplied(in, u, source, samp, matte, look);")
BLEND_ANCHOR = ("                                             texture2d<float> matte [[texture(1)]]) {\n"
                "    float4 src = layerColorPremultiplied(in, u, source, samp, matte);")
BLEND_PATCH = ("                                             texture2d<float> matte [[texture(1)]],\n"
               "                                             texture3d<float> look [[texture(2)]]) {\n"
               "    float4 src = layerColorPremultiplied(in, u, source, samp, matte, look);")

GATE_ANCHOR = "                    + u.obscureEnabled) > 0.5;"
GATES = {
    "VF-T": "                    + u.obscureEnabled + u.toneEnabled) > 0.5;",
    "VF-TL": "                    + u.obscureEnabled + u.toneEnabled + u.lookEnabled) > 0.5;",
    "VC-T": "                    + u.obscureEnabled) > 0.5 || kTone;",
    "VC-TL": "                    + u.obscureEnabled) > 0.5 || kTone || kLook;",
}
STEP5_ANCHOR = "        // (5) The four point filters, in the order the model lists them."
FLAG_TONE = """        // (4c) Tone (grading spike, uniform flag).
        if (u.toneEnabled > 0.5) {
            rgb = gradeTone(rgb, u);
        }
"""
FLAG_LOOK = """        // (4d) The look (grading spike, uniform flag).
        if (u.lookEnabled > 0.5) {
            rgb = gradeLook(rgb, look, samp, u);
        }
"""
CONST_TONE = """        // (4c) Tone (grading spike, function constant).
        if (kTone) {
            rgb = gradeTone(rgb, u);
        }
"""
CONST_LOOK = """        // (4d) The look (grading spike, function constant).
        if (kLook) {
            rgb = gradeLook(rgb, look, samp, u);
        }
"""
CONSTANT_ANCHOR = "constant bool kGatherFilters [[function_constant(0)]];\n"
GRADE_CONSTANTS = ("constant bool kTone [[function_constant(2)]];\n"
                   "constant bool kLook [[function_constant(3)]];\n")
COVERAGE_ANCHOR = "    // (7b) Coverage."
ALWAYS_TONE = """    // (4c, always on) Tone; an ungraded layer carries neutral values.
    rgb = gradeTone(rgb, u);
"""
ALWAYS_LOOK = """    // (4d, always on) The look; an ungraded layer binds the identity 2³ at amount 0.
    rgb = gradeLook(rgb, look, samp, u);
"""
ADJUST_BELOW = "    float4 below = dst;\n"
ADJUST = """
// MARK: - The adjustment pass (road map grading GR0's spike)

// Tone and look over what is already drawn: reads the destination through
// `[[color(0)]]` and returns the finished pixel, so its pipeline is built with
// blending OFF. Its strength is the block's opacity.
fragment float4 framejob_adjust_fragment(ShadowVaryings in [[stage_in]],
                                        constant LayerUniforms &u [[buffer(0)]],
                                        sampler samp [[sampler(0)]],
                                        texture3d<float> look [[texture(2)]],
                                        float4 dst [[color(0)]]) {
""" + ADJUST_BELOW + """    float a = below.a;
    float3 rgb = below.rgb / max(a, 1e-4);
    rgb = gradeTone(rgb, u);
    rgb = gradeLook(rgb, look, samp, u);
    float4 graded = float4(clamp(rgb, 0.0, 1.0) * a, a);
    return saturate(mix(dst, graded, clamp(u.opacity, 0.0, 1.0)));
}
"""

# VB (#258).
BIPLANAR_CONSTANT = "constant bool kBiplanar [[function_constant(4)]];\n"
TOKEN_REWRITES = (  # (label, regex, replacement, the count pinned at HEAD 3cc61e7)
    ("`texture2d<float> source,` signatures", r"texture2d<float> source,",
     "texture2d<float> source, texture2d<float> chroma,", 3),
    ("`texture2d<float> source [[texture(0)]],` entry points",
     r"texture2d<float> source \[\[texture\(0\)\]\],",
     "texture2d<float> source [[texture(0)]],\n"
     "                                       texture2d<float> chroma [[texture(3)]],", 2),
    ("`source, samp` calls", r"\bsource, samp\b", "source, chroma, samp", 13),
)
SAMPLE_ANCHOR = """    float4 texel = saturate(source.sample(
        samp, orientedUV(uv, u.sourceQuarterTurns, u.sourceMirrored)));
"""
SAMPLE_RANGE = """        float y = (codeY - 64.0) / 876.0;
        float2 c = (codeC - 512.0) / 896.0;
"""
SAMPLE_PATCH = """    float2 suv = orientedUV(uv, u.sourceQuarterTurns, u.sourceMirrored);
    float4 texel;
    if (kBiplanar) {
        // #258's spike: Y from `source` (r16Unorm), CbCr from `chroma`
        // (rg16Unorm), 10-bit video-range BT.709 MSB-aligned in 16 bits.
        float codeY = source.sample(samp, suv).r * 65535.0 / 64.0;
        float2 codeC = chroma.sample(samp, suv).rg * 65535.0 / 64.0;
""" + SAMPLE_RANGE + """        texel = saturate(float4(y + 1.5748 * c.y,
                                y - 0.1873 * c.x - 0.4681 * c.y,
                                y + 1.8556 * c.x, 1.0));
    } else {
        texel = saturate(source.sample(samp, suv));
    }
"""

# ---- mutants: each edits the driver's own patch text, its anchor asserted once --

MUTANT_EDITS = {
    # (which variants, which text, old, new)
    "exposure-encoded": (ROUTE_VARIANTS, "helpers", TONE_LINEAR, TONE_ENCODED),
    "lut-axes-swapped": (GRADING, "helpers", LOOK_SAMPLE,
                         "look.sample(samp, (rgb * (n - 1.0) / n + 0.5 / n).bgr)"),
    "adjust-ignores-destination": (TL_ROUTES + ("VE",), "adjust", ADJUST_BELOW,
                                   "    float4 below = float4(0.5, 0.5, 0.5, 1.0);\n"),
    "biplanar-full-range": (("VB",), "sample", SAMPLE_RANGE,
                            "        float y = codeY / 1023.0;\n"
                            "        float2 c = (codeC - 512.0) / 1023.0;\n"),
    "neutral-drift": (("VA-T", "VA-TL"), "helpers", "exp2(u.exposure)",
                      "exp2(u.exposure + 0.05)"),
}


class PatchError(Exception):
    pass


def once(text, anchor, replacement, label):
    count = text.count(anchor)
    if count != 1:
        raise PatchError(f"the {label} anchor occurs {count} times, not once")
    return text.replace(anchor, replacement)


def mutated(part, variant, text, mutant):
    edit = MUTANT_EDITS.get(mutant)
    if edit and edit[1] == part and variant in edit[0]:
        return once(text, edit[2], edit[3], f"mutant {mutant}'s")
    return text


def grading_text(source, variant, mutant):
    helpers = HELPERS
    if variant == "VE":
        helpers = once(helpers, TONE_LINEAR, TONE_ENCODED, "VE's linear-light")
    helpers = mutated("helpers", variant, helpers, mutant)
    step5 = STEP5_ANCHOR
    if mutant == "anchor-missing" and variant.startswith("VF"):
        step5 = step5.replace("point filters", "point filtres")
    route = "VF-TL" if variant == "VE" else variant
    look = route.endswith("TL")
    rows = [("LayerUniforms tail", UNIFORMS_ANCHOR, UNIFORMS_PATCH),
            ("layer-stage MARK", HELPERS_ANCHOR, helpers + HELPERS_ANCHOR),
            ("stage signature", STAGE_SIG_ANCHOR, STAGE_SIG_PATCH),
            ("plain entry", PLAIN_ANCHOR, PLAIN_PATCH),
            ("blend entry", BLEND_ANCHOR, BLEND_PATCH)]
    if route.startswith("VF"):
        rows += [("effects gate", GATE_ANCHOR, GATES[route]),
                 ("step 5", step5, FLAG_TONE + (FLAG_LOOK if look else "") + "\n" + step5)]
    elif route.startswith("VC"):
        rows += [("function constant", CONSTANT_ANCHOR, CONSTANT_ANCHOR + GRADE_CONSTANTS),
                 ("effects gate", GATE_ANCHOR, GATES[route]),
                 ("step 5", step5, CONST_TONE + (CONST_LOOK if look else "") + "\n" + step5)]
    else:
        rows += [("step 7b", COVERAGE_ANCHOR,
                  ALWAYS_TONE + (ALWAYS_LOOK if look else "") + "\n" + COVERAGE_ANCHOR)]
    text = source
    for label, anchor, replacement in rows:
        text = once(text, anchor, replacement, label)
    if look:
        text += mutated("adjust", variant, ADJUST, mutant)
    return text


def biplanar_text(source, mutant):
    text = once(source, CONSTANT_ANCHOR, CONSTANT_ANCHOR + BIPLANAR_CONSTANT, "function constant")
    for label, pattern, replacement, pinned in TOKEN_REWRITES:
        text, count = re.subn(pattern, lambda _m, r=replacement: r, text)
        if count != pinned:
            raise PatchError(f"the {label} rewrite hit {count} times, pinned at {pinned}")
    return once(text, SAMPLE_ANCHOR, mutated("sample", "VB", SAMPLE_PATCH, mutant),
                "layerSample's texel")


# ---- rows ---------------------------------------------------------------------

ROWS = []


def emit(row, verdict, detail):
    """verdict: PASS, FAIL (scored), SKIP (named), CONTROL or RECORD (figures)."""
    ROWS.append({"row": row, "verdict": verdict, "detail": detail})
    print(f"{row:<6} {verdict:<8} {detail}", flush=True)


def run(argv, seconds):
    return bounded.run([str(a) for a in argv], seconds, env=bounded.child_env())


def ms(value):
    return f"{value:.3f} ms"


# ---- building -----------------------------------------------------------------

def build_shaders(folder, mutant):
    shown = subprocess.run(["git", "-C", str(ROOT), "show", f"{SHADER_COMMIT}:{SHADER}"],
                           capture_output=True, text=True)
    if shown.returncode != 0:
        emit("B0", "FAIL", f"git show {SHADER_COMMIT}:{SHADER} failed: "
             f"{shown.stderr.strip()[-300:]}")
        return None
    # The commit predates rename R1: its entry points take the names the bench asks for.
    source = shown.stdout.replace("reelcut_", "framejob_")
    texts = {"V0": source}
    for variant in GRADING + ("VB",):
        try:
            texts[variant] = (biplanar_text(source, mutant) if variant == "VB"
                              else grading_text(source, variant, mutant))
        except PatchError as error:
            emit("B0", "FAIL", f"{variant}: {error}")
            return None
    emit("B0", "PASS", f"{', '.join(n for n in texts if n != 'V0')} patched from "
         f"{SHADER} at {SHADER_COMMIT} ({source.count(chr(10))} lines): every anchor exactly "
         "once; VB's token rewrites hit " + "/".join(str(r[3]) for r in TOKEN_REWRITES))
    libs = {}
    for name, text in texts.items():
        metal, air, lib = folder / f"{name}.metal", folder / f"{name}.air", folder / f"{name}.metallib"
        metal.write_text(text)
        step = run(["xcrun", "-sdk", "macosx", "metal", "-c", metal, "-o", air], 300)
        if step["rc"] == 0 and not step["expired"]:
            step = run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib], 300)
        if step["expired"] or step["rc"] != 0 or not lib.exists():
            emit("B1", "FAIL", f"{name} did not compile: "
                 f"{'expired' if step['expired'] else step['stderr'][-900:]}")
            return None
        libs[name] = lib
    emit("B1", "PASS", f"{len(libs)} metallibs ({', '.join(libs)}) in {folder.relative_to(ROOT)}")
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
                                  output=folder / "grading_bench", defines=["FRAMEJOB_DEV_TOOLS"],
                                  optimize=True, timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        emit("B2", "FAIL", f"the bench did not build (-O): {error} {error.diagnostics[:6]}")
        return None
    emit("B2", "PASS", f"bench {'reused' if built.reused else f'built in {built.seconds} s'} "
         f"(-O, over app/Sources, key {built.key}) — {built.binary.relative_to(ROOT)}")
    return built.binary


# ---- the host --------------------------------------------------------------------

def host_gate():
    """(ok, facts): read only — `pmset -g` and `pmset -g batt`, never a setting."""
    general = run(["pmset", "-g"], 30)
    battery = run(["pmset", "-g", "batt"], 30)
    mode = re.search(r"^\s*powermode\s+(\d+)", general["stdout"], re.M)
    source = re.search(r"Now drawing from '([^']+)'", battery["stdout"])
    facts = {"powermode": mode.group(1) if mode else "absent",
             "power": source.group(1) if source else "unknown",
             "cpu": run(["sysctl", "-n", "machdep.cpu.brand_string"], 30)["stdout"].strip(),
             "macos": run(["sw_vers", "-productVersion"], 30)["stdout"].strip(),
             "load_before": load()}
    ok = mode is not None and mode.group(1) != "1" and facts["power"] == "AC Power"
    return ok, facts


def load():
    return run(["sysctl", "-n", "vm.loadavg"], 30)["stdout"].strip()


# ---- the bench -----------------------------------------------------------------

def bench(binary, libs, size, folder, frames, runs, warmup, seed):
    w, h = size
    out = folder / f"bench-{h}.json"
    out.unlink(missing_ok=True)
    argv = [binary] + [x for name, lib in libs.items() for x in ("--lib", f"{name}={lib}")]
    argv += ["--width", w, "--height", h, "--frames", frames, "--runs", runs,
             "--warmup", warmup, "--seed", seed, "--out", out]
    ran = run(argv, 600)
    if ran["expired"] or ran["rc"] != 0 or not out.exists():
        emit(f"R{h}", "FAIL", f"the bench at {w}×{h} "
             f"{'ran past 600 s' if ran['expired'] else 'exited ' + str(ran['rc'])}: "
             f"{ran['stderr'][-900:]}")
        return None
    return json.loads(out.read_text())


def k_rows(answers):
    ok_all = True
    for row in ("K1", "K2", "K3", "K4", "K5"):
        for (w, h) in SIZES:
            if h not in answers:
                continue
            entries = [k for k in answers[h]["k"] if k["row"] == row]
            if not entries:
                emit(row, "FAIL", f"{h}p: the bench reported no {row} entry")
                ok_all = False
            for entry in entries:
                ok_all &= entry["ok"]
                emit(row, "PASS" if entry["ok"] else "FAIL",
                     f"{h}p {entry['variant']}: {entry['detail']}")
    return ok_all


def figure(answer, series):
    medians = [s["median"] for s in answer["samples"][series]]
    return statistics.median(medians), min(medians), max(medians)


# ---- D1: the decode fixtures and their frame rates --------------------------------

FIXTURES = (
    ("prores422_10", "prores422-10bit.mov",
     ["-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le"]),
    ("hevc420_10", "hevc420-10bit.mp4",
     ["-c:v", "libx265", "-preset", "ultrafast", "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1"]),
)
# What ffprobe must read of each fixture beside 3840×2160 and bt709 ×3 (issue #292).
D1_WANT = {"prores422_10": ("prores", "yuv422p10le"), "hevc420_10": ("hevc", "yuv420p10le")}


def fixtures():
    """D1's fixtures through `bt709_fixture.make` (issue #292): `setparams` on
    the input, the tags on the output, each kept — a cached file too — only
    when ffprobe reads its codec, pix_fmt, 3840×2160 and bt709 ×3 and its
    first frame reads back against its own graph; a refusal is D1's FAIL."""
    media = WORK / "media"
    made = {}
    for key, name, codec in FIXTURES:
        codec_name, pix_fmt = D1_WANT[key]
        path, why = bt709_fixture.make(
            media / name, ["-f", "lavfi", "-i", "testsrc2=size=3840x2160:rate=30:duration=2,"
                           f"{bt709_fixture.SETPARAMS}"], codec,
            {"codec_name": codec_name, "pix_fmt": pix_fmt, "width": 3840, "height": 2160},
            pix_fmt, 300)
        if path is None:
            emit("D1", "FAIL", why)
            return None
        made[key] = path
    return made


def decode_rows(binary, folder, seed):
    made = fixtures()
    if made is None:
        return None, False
    pairs = [(key, fmt) for key in made for fmt in DECODE_FORMATS]
    results = {f"{key}:{fmt}": [] for key, fmt in pairs}
    orders = []
    for index in range(3):
        order = list(pairs)
        random.Random(seed + index).shuffle(order)
        orders.append([f"{key}:{fmt}" for key, fmt in order])
        for key, fmt in order:
            out = folder / f"decode-{key}-{fmt}-{index}.json"
            ran = run([binary, "--decode", made[key], "--format", fmt, "--frames", 60,
                       "--runs", 1, "--out", out], 300)
            if ran["expired"] or ran["rc"] != 0 or not out.exists():
                emit("D1", "FAIL", f"{key} → {fmt} run {index}: "
                     f"{'expired' if ran['expired'] else ran['stderr'][-400:]}")
                return None, False
            answer = json.loads(out.read_text())
            results[f"{key}:{fmt}"].append(answer["runs"][0])
    summary = {}
    for name, rows in results.items():
        fps = [r["fps"] for r in rows]
        summary[name] = {"median_fps": statistics.median(fps), "low": min(fps), "high": max(fps),
                         "frames": [r["frames"] for r in rows]}
        emit("D1", "RECORD", f"{name}: {statistics.median(fps):.1f} fps "
             f"(runs {min(fps):.1f}–{max(fps):.1f}; {rows[0]['frames']} frames of 3840×2160)")
    decode = {"fixtures": {k: str(p.relative_to(ROOT)) for k, p in made.items()},
              "orders": orders, "results": results, "summary": summary}
    (folder / "decode.json").write_text(json.dumps(decode, indent=1, sort_keys=True))
    return decode, True


# ---- the figures and the rules -----------------------------------------------------

def timing_rows(answers, result):
    figures = result["figures"] = {}
    over, noise, sh_noise = {}, {}, {}
    for w, h in SIZES:
        answer = answers[h]
        f = {s: figure(answer, s) for s in answer["samples"]}
        noise[h] = abs(f["V0:S1"][0] - f["V0b:S1"][0])
        sh_noise[h] = abs(f["H16:SH"][0] - f["H16b:SH"][0])
        over[h] = {v: f[f"{v}:S1"][0] - f["V0:S1"][0] for v in GRADING}
        figures[str(h)] = {"series": {s: {"median": m, "low": lo, "high": hi}
                                 for s, (m, lo, hi) in f.items()},
                      "noise_C0": noise[h], "noise_C1": sh_noise[h], "overhead_S1": over[h]}
        emit("C0", "CONTROL", f"{h}p V0 S1 twice: {ms(f['V0:S1'][0])} "
             f"({ms(f['V0:S1'][1])}–{ms(f['V0:S1'][2])}) and {ms(f['V0b:S1'][0])} "
             f"({ms(f['V0b:S1'][1])}–{ms(f['V0b:S1'][2])}): noise floor {ms(noise[h])}")
        emit("C1", "CONTROL", f"{h}p H16 SH twice: {ms(f['H16:SH'][0])} "
             f"({ms(f['H16:SH'][1])}–{ms(f['H16:SH'][2])}) and {ms(f['H16b:SH'][0])} "
             f"({ms(f['H16b:SH'][1])}–{ms(f['H16b:SH'][2])}): noise floor {ms(sh_noise[h])}")
        for s in sorted(f):
            emit("F", "RECORD", f"{h}p {s}: {ms(f[s][0])} (runs {ms(f[s][1])}–{ms(f[s][2])})")
        emit("T0", "RECORD", f"{h}p S1 overhead over V0: "
             + ", ".join(f"{v} {ms(over[h][v])}" for v in GRADING)
             + f" (bound {BOUND[h]:.2f} ms + noise {ms(noise[h])})")

    def qualifies(route):
        return all(over[h][f"{route}-TL"] <= BOUND[h] + noise[h] for _, h in SIZES)

    chosen = next((r for r in ROUTE_ORDER if qualifies(r)), None)
    if chosen:
        why = (f"the first route in {ROUTE_ORDER} whose TL variant's S1 overhead is ≤ bound + "
               "noise at both sizes: " + "; ".join(
                   f"{r}-TL {'qualifies' if qualifies(r) else 'does not'} "
                   f"({', '.join(ms(over[h][r + '-TL']) for _, h in SIZES)})" for r in ROUTE_ORDER))
        result["route"] = {"route": chosen, "qualified": True}
    else:
        chosen = min(ROUTE_ORDER, key=lambda r: over[2160][f"{r}-TL"])
        miss = {str(h): over[h][f"{chosen}-TL"] - (BOUND[h] + noise[h]) for _, h in SIZES}
        why = ("NO route qualifies; the smallest 4K TL overhead is "
               f"{chosen}-TL's, missing bound + noise by "
               + ", ".join(f"{ms(miss[str(h)])} at {h}p" for _, h in SIZES)
               + " — a conversation for the owner, not a stop")
        result["route"] = {"route": chosen, "qualified": False, "miss": miss}
    emit("T1", "RECORD", f"route {chosen}: {why}")

    t2 = result["t2"] = {}
    for w, h in SIZES:
        s = figures[str(h)]["series"]
        m = {k: v["median"] for k, v in s.items()}
        rows = {}
        for r in ROUTE_ORDER:
            rows[r] = {"T:ST-S1": m[f"{r}-T:ST"] - m[f"{r}-T:S1"],
                       "TL:ST-S1": m[f"{r}-TL:ST"] - m[f"{r}-TL:S1"],
                       "TL:STL-S1": m[f"{r}-TL:STL"] - m[f"{r}-TL:S1"],
                       "TL:SA-S1": m[f"{r}-TL:SA"] - m[f"{r}-TL:S1"]}
            emit("T2", "RECORD", f"{h}p {r}: ST − S1 {ms(rows[r]['T:ST-S1'])} (T), "
                 f"{ms(rows[r]['TL:ST-S1'])} (TL); STL − S1 {ms(rows[r]['TL:STL-S1'])}; "
                 f"SA − S1 {ms(rows[r]['TL:SA-S1'])}")
        linear = m["VF-TL:STL"] - m["VE:STL"]
        rows["linear"] = linear
        emit("T2", "RECORD", f"{h}p the linear-light step, VF-TL:STL − VE:STL: {ms(linear)}")
        t2[str(h)] = rows

    x = result["x258"] = {}
    for w, h in SIZES:
        m = {k: v["median"] for k, v in figures[str(h)]["series"].items()}
        g = m["H16:SH"] - m["B8:SH"]
        win = m["H16:SH"] - min(m["X420:SH"], m["X422:SH"])
        x[str(h)] = {"G": g, "W": win, "C1": sh_noise[h]}
        emit("X0", "RECORD", f"{h}p SH: " + ", ".join(f"{s} {ms(m[s + ':SH'])}" for s in SH_SERIES)
             + f"; G = H16 − B8 {ms(g)}, W = H16 − min(X420, X422) {ms(win)}, "
             f"VB0 − H16 {ms(m['VB0:SH'] - m['H16:SH'])}")
    g, win, c1 = x["2160"]["G"], x["2160"]["W"], x["2160"]["C1"]
    if g <= 2 * c1:
        outcome = "close"
        why = (f"G {ms(g)} ≤ 2·C1 {ms(2 * c1)}: the layer stage does not carry deep decode's "
               "cost; #258 recommended closed")
    elif win >= WIN_SHARE * g:
        outcome = "open"
        why = (f"W {ms(win)} ≥ {WIN_SHARE}·G {ms(WIN_SHARE * g)}: biplanar wins back at least half; "
               "#258 stays open for the owner's choice, and building it would amend PR-2")
    else:
        outcome = "close"
        why = (f"G {ms(g)} > 2·C1 {ms(2 * c1)} but W {ms(win)} < {WIN_SHARE}·G "
               f"{ms(WIN_SHARE * g)}: #258 recommended closed")
    x["outcome"] = outcome
    emit("X1", "RECORD", f"#258 at 4K: {why}. GR0 records no §11 entry")


def p1_rows(answers):
    for w, h in SIZES:
        p1 = answers[h]["p1"]
        deep, shallow = p1["rgba16Float"], p1["bgra8Unorm"]
        emit("P1", "RECORD", f"{h}p −1 EV then +1 EV, two adjustment passes ({p1['library']}) "
             f"through rgba16Float: {deep['distinct_levels']} distinct levels of 256, max |Δ| "
             f"{deep['max_delta_levels']} levels")
        emit("P1", "CONTROL", f"{h}p the same through bgra8Unorm: {shallow['distinct_levels']} "
             f"distinct levels, max |Δ| {shallow['max_delta_levels']} levels (the brief's scratch "
             "C4 gave 129)")


# ---- --tree (GR7a): the tree's own shader against main's at the branch point -------

def build_tree_shaders(folder, base):
    shown = subprocess.run(["git", "-C", str(ROOT), "show", f"{base}:{SHADER}"],
                           capture_output=True, text=True)
    if shown.returncode != 0:
        emit("B0", "FAIL", f"git show {base}:{SHADER} failed: {shown.stderr.strip()[-300:]}")
        return None, False
    # `base` predates rename R1: its entry points take the names the bench asks for.
    texts = {"V0": shown.stdout.replace("reelcut_", "framejob_"),
             "VT": (ROOT / SHADER).read_text()}
    # A base before grading GR4a has no adjustment pass, so no KA (#284).
    has_adjust = "framejob_adjust_fragment" in texts["V0"]
    emit("B0", "PASS", f"--tree: V0 {SHADER} at {base} ({texts['V0'].count(chr(10))} "
         f"lines, {'with' if has_adjust else 'no'} framejob_adjust_fragment), VT the tree's "
         f"own, unpatched ({texts['VT'].count(chr(10))} lines; no anchor asked)")
    libs = {}
    for name, text in texts.items():
        metal, air, lib = folder / f"{name}.metal", folder / f"{name}.air", folder / f"{name}.metallib"
        metal.write_text(text)
        step = run(["xcrun", "-sdk", "macosx", "metal", "-c", metal, "-o", air], 300)
        if step["rc"] == 0 and not step["expired"]:
            step = run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib], 300)
        if step["expired"] or step["rc"] != 0 or not lib.exists():
            emit("B1", "FAIL", f"{name} did not compile: "
                 f"{'expired' if step['expired'] else step['stderr'][-900:]}")
            return None, False
        libs[name] = lib
    emit("B1", "PASS", f"{len(libs)} metallibs ({', '.join(libs)}) in {folder.relative_to(ROOT)}")
    return libs, has_adjust


def build_tree_bench():
    folder = WORK / "tree-bench"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    source = (HERE / "tree_bench.swift").read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    try:
        built = swift_build.build(sources=swift_build.app_sources() + [entry],
                                  output=folder / "grading_tree_bench",
                                  defines=["FRAMEJOB_DEV_TOOLS"], optimize=True, timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        emit("B2", "FAIL", f"tree_bench did not build (-O): {error} {error.diagnostics[:6]}")
        return None
    emit("B2", "PASS", f"tree_bench {'reused' if built.reused else f'built in {built.seconds} s'} "
         f"(-O, over app/Sources, key {built.key}) — {built.binary.relative_to(ROOT)}")
    return built.binary


def no_adjust_reason(h, base):
    return (f"{h}p: V0's shader at {base} names no framejob_adjust_fragment (it predates "
            "grading GR4a's adjustment pass), so there is no V0:SA to compare")


def tree_bench(binary, libs, size, folder, frames, runs, warmup, seed, exposure, adjust):
    w, h = size
    out = folder / f"bench-{h}.json"
    out.unlink(missing_ok=True)
    argv = [binary] + [x for name, lib in libs.items() for x in ("--lib", f"{name}={lib}")]
    argv += ["--width", w, "--height", h, "--frames", frames, "--runs", runs,
             "--warmup", warmup, "--seed", seed, "--vt-exposure", exposure,
             "--adjust", 1 if adjust else 0, "--out", out]
    ran = run(argv, 600)
    if ran["expired"] or ran["rc"] != 0 or not out.exists():
        emit(f"R{h}", "FAIL", f"tree_bench at {w}×{h} "
             f"{'ran past 600 s' if ran['expired'] else 'exited ' + str(ran['rc'])}: "
             f"{ran['stderr'][-900:]}")
        return None
    return json.loads(out.read_text())


def tree_timing_rows(answers, result):
    figures = result["figures"] = {}
    for w, h in SIZES:
        answer = answers[h]
        f = {s: figure(answer, s) for s in answer["samples"]}
        noise = abs(f["V0:S1"][0] - f["V0b:S1"][0])
        over = f["VT:S1"][0] - f["V0:S1"][0]
        bound = BOUND[h] + noise
        figures[str(h)] = {"series": {s: {"median": m, "low": lo, "high": hi}
                                      for s, (m, lo, hi) in f.items()},
                           "noise_C0": noise, "overhead_T0": over, "bound": bound}
        emit("C0", "CONTROL", f"{h}p V0 S1 twice: {ms(f['V0:S1'][0])} "
             f"({ms(f['V0:S1'][1])}–{ms(f['V0:S1'][2])}) and {ms(f['V0b:S1'][0])} "
             f"({ms(f['V0b:S1'][1])}–{ms(f['V0b:S1'][2])}): noise floor {ms(noise)}")
        for s in sorted(f):
            emit("F", "RECORD", f"{h}p {s}: {ms(f[s][0])} (runs {ms(f[s][1])}–{ms(f[s][2])})")
        emit("T0", "RECORD", f"{h}p VT:S1 − V0:S1 {ms(over)}")
        emit("TC", "RECORD", f"{h}p T0 {ms(over)} against ≤ BOUND {BOUND[h]:.2f} ms + C0 "
             f"{ms(noise)} = {ms(bound)}: "
             + ("cap held" if over <= bound else f"cap missed by {ms(over - bound)}"))
        # grading-2 G2-4: an unqualified adjustment pass's cost, against the
        # SA series' own noise control (V0b:SA).
        if "VT:SA" in f:
            noise_a = abs(f["V0:SA"][0] - f["V0b:SA"][0])
            over_a = f["VT:SA"][0] - f["V0:SA"][0]
            bound_a = BOUND[h] + noise_a
            figures[str(h)].update({"noise_C0_SA": noise_a, "overhead_TA": over_a,
                                    "bound_TA": bound_a})
            emit("C0", "CONTROL", f"{h}p V0 SA twice: {ms(f['V0:SA'][0])} and "
                 f"{ms(f['V0b:SA'][0])}: noise floor {ms(noise_a)}")
            emit("TA", "RECORD", f"{h}p VT:SA − V0:SA {ms(over_a)} against ≤ BOUND "
                 f"{BOUND[h]:.2f} ms + C0 (SA) {ms(noise_a)} = {ms(bound_a)}: "
                 + ("cap held" if over_a <= bound_a else f"cap missed by {ms(over_a - bound_a)}"))
        else:
            emit("TA", "SKIP", no_adjust_reason(h, result["tree_base"]))
        # grading-4 T4-4 (GR-35): the qualified pass with the blur on, over the
        # same pass inline, beside the SA noise floor (S1's without SA).
        if "VT:SQ" in f:
            floor = figures[str(h)].get("noise_C0_SA", noise)
            inline = f["VT:SQ"][0]
            blurred = {sigma: f[f"VT:SQ{sigma}"][0] - inline for sigma in (2, 8, 24)}
            figures[str(h)].update({"overhead_TB": {str(k): v for k, v in blurred.items()},
                                    "noise_TB": floor})
            emit("TB", "RECORD", f"{h}p over VT:SQ {ms(inline)} (the qualifier inline): "
                 + ", ".join(f"σ {sigma} {ms(d)}" for sigma, d in blurred.items())
                 + f"; noise floor {ms(floor)}")


def tree_main(args):
    tag = "tree-" + (f"mutant-{args.mutant}" if args.mutant else
                     ("measure" if args.measure else "check"))
    folder = WORK / tag
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    started = datetime.datetime.now().astimezone()
    print(f"grading_spike {tag} at {started:%Y-%m-%d %H:%M %Z}, seed {args.seed}", flush=True)
    print(f"rules: BOUND = {BOUND}; V0 = {SHADER} at {args.tree_base}, VT = the tree's own",
          flush=True)
    timing = args.measure
    facts = None
    if args.measure:
        timing, facts = host_gate()
        detail = (f"powermode {facts['powermode']}; drawing from {facts['power']}; "
                  f"{facts['cpu']}; macOS {facts['macos']}; load before {facts['load_before']}")
        emit("H0", "PASS" if timing else "SKIP", detail if timing else
             f"{detail}: the host gate is shut, so every timing row is skipped")
    exposure = 0.5 if args.mutant == "tree-graded" else 0
    libs, has_adjust = build_tree_shaders(folder, args.tree_base)
    binary = build_tree_bench() if libs else None
    answers = {}
    scored_ok = libs is not None and binary is not None
    if scored_ok:
        frames, runs, warmup = (200, 3, 5) if timing else (10, 1, 1)
        for size in SIZES:
            answer = tree_bench(binary, libs, size, folder, frames, runs, warmup, args.seed,
                                exposure, has_adjust)
            if answer is None:
                scored_ok = False
                continue
            answers[size[1]] = answer
        for w, h in SIZES:
            if h not in answers:
                continue
            if not has_adjust:
                emit("KA", "SKIP", no_adjust_reason(h, args.tree_base))
            for row in ("KT", "KA") if has_adjust else ("KT",):
                entries = [k for k in answers[h]["k"] if k["row"] == row]
                if not entries:
                    emit(row, "FAIL", f"{h}p: tree_bench reported no {row} entry")
                    scored_ok = False
                for entry in entries:
                    scored_ok &= entry["ok"]
                    emit(row, "PASS" if entry["ok"] else "FAIL", f"{h}p {entry['variant']}: "
                         f"{entry['detail']}")
    result = {"tag": tag, "started": started.isoformat(), "seed": args.seed, "host": facts,
              "tree_base": args.tree_base, "rules": {"BOUND": BOUND}, "rows": ROWS,
              "answers": {str(h): a for h, a in answers.items()}}
    if args.measure and not timing:
        for row in ("C0", "F", "T0", "TC", "TA", "TB"):
            emit(row, "SKIP", "the host gate is shut (H0)")
    elif timing and scored_ok and len(answers) == len(SIZES):
        tree_timing_rows(answers, result)
    elif timing:
        emit("TC", "SKIP", "a scored row failed, so nothing is timed into a record")
    if facts is not None:
        facts["load_after"] = load()
        facts["gpu"] = next((a["gpu"] for a in answers.values()), None)
        emit("H0", "RECORD", f"GPU {facts['gpu']}; load after {facts['load_after']}")
    result["exit"] = 0 if scored_ok else 1
    if args.measure and not timing:
        result["exit"] = 2
    (folder / "result.json").write_text(json.dumps(result, indent=1, sort_keys=True,
                                                   default=str))
    failed = sorted({r["row"] for r in ROWS if r["verdict"] == "FAIL"})
    if args.mutant:
        print(f"mutant {args.mutant}: {'killed by ' + ', '.join(failed) if failed else 'SURVIVED'}")
    print(f"grading_spike {tag}: {'all scored rows pass' if scored_ok else 'FAILED ' + ', '.join(failed)}"
          f"{'; STOP: the host gate is shut' if result['exit'] == 2 else ''} "
          f"— {(folder / 'result.json').relative_to(ROOT)}")
    return result["exit"]


# ---- main ---------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--measure", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS + TREE_MUTANTS)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--tree", action="store_true",
                        help="the tree's own shader (VT) against main's at TREE_BASE (GR7a)")
    parser.add_argument("--tree-base", default=TREE_BASE, metavar="REV",
                        help=f"with --tree, the commit V0's shader is read at (default {TREE_BASE})")
    args = parser.parse_args()
    if args.mutant and args.measure:
        parser.error("a mutant runs with --check")
    if args.tree and args.mutant and args.mutant not in TREE_MUTANTS:
        parser.error(f"with --tree the mutant is one of {', '.join(TREE_MUTANTS)}")
    if not args.tree and args.mutant in TREE_MUTANTS:
        parser.error(f"{args.mutant} runs with --tree")
    if args.tree:
        return tree_main(args)

    tag = f"mutant-{args.mutant}" if args.mutant else ("measure" if args.measure else "check")
    folder = WORK / tag
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    started = datetime.datetime.now().astimezone()
    print(f"grading_spike {tag} at {started:%Y-%m-%d %H:%M %Z}, seed {args.seed}", flush=True)
    print(f"rules: BOUND = {BOUND}, ROUTE_ORDER = {ROUTE_ORDER}, WIN_SHARE = {WIN_SHARE}",
          flush=True)

    timing = args.measure
    facts = None
    if args.measure:
        timing, facts = host_gate()
        detail = (f"powermode {facts['powermode']}; drawing from {facts['power']}; "
                  f"{facts['cpu']}; macOS {facts['macos']}; load before {facts['load_before']}")
        emit("H0", "PASS" if timing else "SKIP", detail if timing else
             f"{detail}: the host gate is shut, so every timing row is skipped and GR0 stops")

    libs = build_shaders(folder, args.mutant)
    binary = build_bench() if libs else None
    answers = {}
    scored_ok = libs is not None and binary is not None
    if scored_ok:
        frames, runs, warmup = (200, 3, 5) if timing else (10, 1, 1)
        for size in SIZES:
            answer = bench(binary, libs, size, folder, frames, runs, warmup, args.seed)
            if answer is None:
                scored_ok = False
                continue
            answers[size[1]] = answer
        scored_ok &= k_rows(answers)

    result = {"tag": tag, "started": started.isoformat(), "seed": args.seed, "host": facts,
              "rules": {"BOUND": BOUND, "ROUTE_ORDER": ROUTE_ORDER, "WIN_SHARE": WIN_SHARE},
              "rows": ROWS, "answers": {str(h): a for h, a in answers.items()}}
    if args.measure and not timing:
        for row in ("C0", "C1", "F", "T0", "T1", "T2", "P1", "X0", "X1", "D1"):
            emit(row, "SKIP", "the host gate is shut (H0)")
    elif timing and scored_ok and len(answers) == len(SIZES):
        timing_rows(answers, result)
        p1_rows(answers)
        decode, ok = decode_rows(binary, folder, args.seed)
        result["decode"] = decode
        scored_ok &= ok
    elif timing:
        emit("T1", "SKIP", "a scored row failed, so nothing is timed into a record")
    if facts is not None:
        facts["load_after"] = load()
        facts["gpu"] = next((a["gpu"] for a in answers.values()), None)
        emit("H0", "RECORD", f"GPU {facts['gpu']}; load after {facts['load_after']}")

    result["exit"] = 0 if scored_ok else 1
    if args.measure and not timing:
        result["exit"] = 2
    (folder / "result.json").write_text(json.dumps(result, indent=1, sort_keys=True,
                                                   default=str))
    failed = sorted({r["row"] for r in ROWS if r["verdict"] == "FAIL"})
    if args.mutant:
        print(f"mutant {args.mutant}: {'killed by ' + ', '.join(failed) if failed else 'SURVIVED'}")
    print(f"grading_spike {tag}: {'all scored rows pass' if scored_ok else 'FAILED ' + ', '.join(failed)}"
          f"{'; STOP: the host gate is shut' if result['exit'] == 2 else ''} "
          f"— {(folder / 'result.json').relative_to(ROOT)}")
    return result["exit"]


if __name__ == "__main__":
    sys.exit(main())
