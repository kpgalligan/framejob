# The grading spike (road map "grading" GR0; #258)

What tone and a 3D LUT cost an UNGRADED and a graded layer in the tree's own
compositor shader, under three routes, and whether a 10-bit biplanar source
wins back what deep decode costs the layer stage at 4K (#258). Nothing here is
merged into `app/`; GR2 builds the chosen route. The two choosing rules, with
the constants at the top of `grading_spike.py`, were written in
`archive/grading.md` ("GR0's rules, written before measuring") before the
first `--measure`.

```
python3 tools/proof/grading_spike/grading_spike.py --check                       # the loop: builds, 10 frames, B0–B2, K1–K5
python3 tools/proof/grading_spike/grading_spike.py --check --mutant NAME         # one of the six below
perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_spike/grading_spike.py --measure [--seed N]   # recorded
```

**Release-only kind.** It times the GPU, so its bench is always an optimised
build (`swift_build.build(…, optimize=True)`), never a Debug one (spec §11
V-4). It launches no app, so it takes no `release_only=` argument. `build()`
needs `core/target/release/libframejob_core.a`. `--measure` also needs `ffmpeg`
(with `prores_ks` and `libx265`) for D1's two fixtures, made once under
`work/grading_spike/media/` and reused.

**Files.**

- `grading_spike.py` — patches, compiles, builds, runs the bench per size,
  scores, applies the rules, runs D1. Its docstring is the row list.
- `bench.swift` — compiled as `main.swift` over every other `app/Sources` file
  for the app's own `LayerUniforms`, handing the shader its first 104 floats
  (416 bytes, asserted; the tree's block grew a tone group in grading GR2)
  followed by 16 grade floats (480 bytes, asserted), `MetalRenderer.workingFormat` and
  `MetalRenderer.metalFormat(for:)`. Its second mode, `--decode`, is D1's timer.
- Output under `tools/proof/work/grading_spike/<check|measure|mutant-NAME>/`:
  the nine `.metal` sources and metallibs, `bench-<height>.json` (each
  sample's median, min and max, each run's series order, the K readbacks and
  P1), `decode.json` (D1) and `result.json` (the rows, the host, the figures,
  the route, #258's outcome).

**The variants**, each made from `app/Resources/Shaders/Compositor.metal` as it
stood at `4d742cc` (`SHADER_COMMIT`, `git show`; a failed show is a B0 failure),
the tree GR0 measured: grading GR2 built tone into the tree's own shader, so
the spike was pinned there, matte_spike's pattern. Every patch anchor must occur
exactly once and every token rewrite must hit its count pinned at `3cc61e7`;
otherwise B0 fails naming it.

- **V0** — the tree, unpatched (and V0b, the same library drawn as a second
  series, for the C0 control).
- **Every grading variant** appends 16 floats to `LayerUniforms` (`exposure,
  temperature, tint, highlights, shadows, whites, blacks, vibrance, fade,
  toneEnabled, lookAmount, lookEnabled, lookSize, reserved0..2`), adds
  `texture3d<float> look [[texture(2)]]` to both layer entry points and the
  stage, and the helpers: the IEC 61966-2-1 transfer functions, `gradeTone`
  (exposure and white-balance gains in local linear light, then highlights,
  shadows, whites, blacks, vibrance and fade on encoded values; neutral is the
  identity) and `gradeLook` (`mix(rgb, look.sample(samp, rgb·(n−1)/n +
  0.5/n).rgb, lookAmount)`). Textbook formulas only (the Concat rule).
- **VF-T / VF-TL** (uniform flag): `toneEnabled` (and `lookEnabled`) join the
  effects sum; tone is 4c inside the effects block before `// (5) The four
  point filters`, the look 4d after it (TL only).
- **VC-T / VC-TL** (function constant): `kTone [[function_constant(2)]]` and
  `kLook [[function_constant(3)]]`; `effects` becomes `sum > 0.5 || kTone (||
  kLook)`, the stages behind `if (kTone)` / `if (kLook)` at the same place.
- **VA-T / VA-TL** (always on): the stages run on every fragment, right before
  `// (7b) Coverage.`; an ungraded layer carries neutral values and an
  identity 2³ `rgba16Float` lattice at amount 0.
- **VE** — VF-TL with exposure and white balance on encoded values, only to
  price the linear-light step.
- **The adjustment fragment** `framejob_adjust_fragment` is appended to each TL
  library (and VE): it reads `[[color(0)]]`, un-premultiplies, applies tone and
  look, and mixes by the block's opacity; its pipeline has blending OFF.
- **VB** (#258): `kBiplanar [[function_constant(4)]]` and `texture2d<float>
  chroma [[texture(3)]]`, threaded through every `texture2d<float> source`
  signature (3 and 2) and `source, samp` call (13) by token rewrite; with
  `kBiplanar` true `layerSample` reads Y from `source` (`r16Unorm`) and CbCr
  from `chroma` (`rg16Unorm`) as 10-bit video-range BT.709: `code =
  sample·65535/64`, `Y' = (code−64)/876`, `C = (code−512)/896`.

**The scenes**, full bleed at 1920×1080 and 3840×2160, over an `rgba16Float`
picture (PR-2's stand-in source): **S1** one layer, ungraded; **ST** tone at
exposure 0.5, temperature 0.2, tint −0.1, highlights −0.2, shadows 0.2, whites
0.1, blacks −0.1, vibrance 0.2, fade 0.1; **STL** ST plus a smooth 33³ look
baked on the CPU, at 0.8; **SA** S1 then one full-frame adjustment pass with
STL's grade; **SH** (#258) four video layers — one full bleed, two at scale 0.5
in opposite quarters, one at 0.35 — each with its own IOSurface-backed
`CVPixelBuffer` source, filled on the CPU and wrapped every frame through one
`CVMetalTextureCache` (`Compositor.texture(from:live:)`'s call shape, each
wrapper held until its frame's command buffer completes), as B8 (`32BGRA` →
`bgra8Unorm`, V0), H16 and H16b (`64RGBAHalf` → `rgba16Float`, V0), X420 and
X422 (`x420` / `x422`, VB) and VB0 (VB with `kBiplanar` false on H16 sources).

**Rows.** B0 the patches; B1 the nine metallibs; B2 the bench. Scored, before
any timing, at each size: **K1** every grading variant's S1 = V0's within
1/1023 over the whole frame; **K2** per route variant, a flat 0.5 grey at +1 EV
= `encode(min(1, 2·decode(0.5)))` ± 1/255; **K3** per TL route, an identity 33³
look at amount 1 = amount 0 within 1/1023, and a channel-swap look (out = b, g,
r) on a flat (0.2, 0.5, 0.8) gives (0.8, 0.5, 0.2) ± 1/255; **K4** per TL
route, the adjustment pass at +1 EV alone over the 256-column grey ramp (column
i holds encoded i/255, drawn with V0) = `encode(min(1, 2·decode(i/255)))` ±
1/255 column by column (not a flat grey: a fragment that tones a constant 0.5
would pass there); **K5** an 8-band 75 % colour bar written into the four
buffer forms: X420's and X422's band centres = H16's ± 2/255, B8's ± 1/255.
`--measure` adds **H0** (the host gate, read only: `pmset -g` powermode ≠ 1 and
`pmset -g batt` on AC Power; shut, every timing row is a named SKIP and the
script exits 2; it records the CPU, macOS, the GPU and `vm.loadavg` before and
after), **C0** (CONTROL |V0:S1 − V0b:S1|), **C1** (CONTROL |H16 − H16b| on SH),
**F** (every series), **T0** (each variant's S1 overhead over V0), **T1** (the
route, a RECORD: the first of VA, VF, VC whose TL variant's S1 overhead is ≤
`BOUND[h]` + C0 noise at both sizes, `BOUND = {1080: 0.02, 2160: 0.06}`; if
none, the smallest 4K overhead and the size of its miss), **T2** (ST and STL
over S1 per route, the linear step VF-TL:STL − VE:STL, SA − S1), **P1** (−1 EV
then +1 EV as two adjustment passes, each its own render pass, over the ramp:
distinct `round(v·255)` levels and max |Δ| through `rgba16Float`, and as a
CONTROL through `bgra8Unorm`), **X0** (the SH figures, G = H16 − B8 and W = H16
− min(X420, X422)), **X1** (#258's outcome at 4K, a RECORD: G ≤ 2·C1 → close;
else W ≥ `WIN_SHARE`·G (0.5) → open for the owner; else close) and **D1** (two
ffmpeg fixtures, 2 s of 3840×2160 at 30 fps — `prores_ks -profile:v 2 -pix_fmt
yuv422p10le` and `libx265 -preset ultrafast -pix_fmt yuv420p10le -tag:v hvc1` —
each decoded through `AVAssetReader` into 32BGRA, 64RGBAHalf, x420 and x422, 60
frames, the eight pairs in a seeded order, three runs; a RECORD in frames per
second).

**Timing.** A sample is 200 frames after 5 unrecorded ones, one command buffer
per frame, committed and waited on, its time `gpuEndTime − gpuStartTime`;
three runs, and within each run the series are taken in a permutation drawn
from SplitMix64 seeded with the seed plus the run index (the brief's caveat: a
fixed order moved absolute figures and broke a control), each order stored in
the JSON. A figure is the median of the three runs' medians, quoted with the
runs' range. `--check` takes 10 frames, one run, and scores B and K only.

**Mutants.** Each edits the driver's own patch text, its anchor asserted once:
`anchor-missing` (VF's step-5 anchor misspelt) must fail B0;
`exposure-encoded` (exposure and white balance on encoded values in every
route) K2 and K4; `lut-axes-swapped` (the look sampled at `.bgr`) K3;
`adjust-ignores-destination` (the adjustment fragment tones a constant mid
grey) K4 on the ramp; `biplanar-full-range` (Y' = code/1023, C =
(code−512)/1023) K5; `neutral-drift` (VA's exposure read as exposure + 0.05)
K1. The script prints `mutant NAME: killed by …` or `SURVIVED`.

**`--tree` (grading GR7a).** In place of the routes, what the branch BUILT:
V0 is `Compositor.metal` as it stood at `--tree-base REV` (by default `f407f87`,
`TREE_BASE`, main at the branch point; grading-2 G2-2 passes `4f52ead`, the
commit before its wheels, G2-3 `b2fd1f9`, the commit before its curves, and
G2-4 `75ebf34`, the commit before its qualifier; `git show`,
a failed show is a B0 failure) and VT is the tree's
own file, unpatched — matte_spike's `--tree` pattern. B1 compiles the two;
B2 builds `tree_bench.swift` (`-O`, over `app/Sources`), which hands BOTH
libraries the app's whole `LayerUniforms` (128 floats, 512 bytes since
grading-2 G2-2, asserted at `gradeReserved0`; an older base's shader reads a
prefix of it), binds the picture at `texture(0)`, a 1×1
white placeholder at `texture(1)`, an identity 2³ `rgba16Float` lattice at
`texture(2)` and an identity 2×1 `rgba32Float` curve strip at `texture(3)` (since
grading-2 G2-3; a base's shader that names no `texture(3)` ignores it), and builds
its pipelines as `bench.swift`'s `layerState`
(`kGatherFilters` false, the same blending, `MetalRenderer.workingFormat`)
and, since grading-2 G2-4, the adjustment pass's as `adjustPipeline`'s (the
shadow vertex stage, `framejob_adjust_fragment`, blending OFF) with a neutral
`QualifierUniforms` at fragment `buffer(1)` (a base's fragment that names no
`buffer(1)` ignores it). Two scenes over a copy of `bench.swift`'s
`halfPicture`: S1, and SA (S1 then one full-frame adjustment pass at +1 EV,
unqualified); series V0:S1, VT:S1, V0b:S1, V0:SA, VT:SA and V0b:SA in the same
seeded SplitMix64 order, 5 warm-up and N timed frames each. **KT** and **KA**,
scored at both sizes before any timing: VT:S1 = V0:S1 and VT:SA = V0:SA within
1/1023 over the whole frame. `--measure --tree` adds H0, C0 (|V0:S1 −
V0b:S1|, and |V0:SA − V0b:SA|), F, T0 (VT:S1 − V0:S1), **TC** (a RECORD: T0 ≤
`BOUND[h]` + C0 at 1080 and 2160 — "What it may cost"'s UNGRADED-layer cap,
+0.02 ms and +0.06 ms) and **TA** (a RECORD: VT:SA − V0:SA ≤ `BOUND[h]` + the
SA series' C0 — what the qualifier costs an unqualified adjustment pass). Mutant `tree-graded` (`--vt-exposure 0.5`: VT's draws carry +0.5
EV with `toneEnabled` 1) must fail KT. Output under
`work/grading_spike/tree-<check|measure|mutant-tree-graded>/` (`bench-<h>.json`
of the same shape, `result.json`).

```
python3 tools/proof/grading_spike/grading_spike.py --check --tree                    # B0–B2, KT
python3 tools/proof/grading_spike/grading_spike.py --check --tree --mutant tree-graded
perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_spike/grading_spike.py --measure --tree   # GR7a's record
perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_spike/grading_spike.py --measure --tree --tree-base 4f52ead   # G2-2's
perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_spike/grading_spike.py --measure --tree --tree-base b2fd1f9   # G2-3's
perl -e 'alarm 600; exec @ARGV' python3 tools/proof/grading_spike/grading_spike.py --measure --tree --tree-base 75ebf34   # G2-4's
```

**Its record** is `archive/grading.md`, "GR0 — the road map and the spike"
(and, for `--tree`, "GR7a").
