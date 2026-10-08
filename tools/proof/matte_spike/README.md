# The matte spike (road map "mattes" MT0, spec §11 MT-6)

What a matte costs the compositor, and which route an UNMATTED layer takes
once the layer stage samples a coverage texture at `texture(1)`. Nothing here
is merged into `app/`; MT2 builds the chosen route into `Compositor.metal`.

```
python3 tools/proof/matte_spike/matte_spike.py --check                       # the loop: builds, 10 frames a scene, K3/K4
python3 tools/proof/matte_spike/matte_spike.py --check --mutant NAME         # resolve-writes-one | anchor-missing
perl -e 'alarm 600; exec @ARGV' python3 tools/proof/matte_spike/matte_spike.py --measure   # recorded
```

**Release-only kind.** It times the GPU, so its bench is always an optimised
build (`swift_build.build(…, optimize=True)`), never a Debug one (spec §11
V-4). It launches no app, so it takes no `release_only=` argument: there is no
app for `proof_app.py` to choose.

**Files.**

- `matte_spike.py` — patches, compiles, builds, runs the bench per size,
  scores. Its docstring is the row list.
- `bench.swift` — compiled as `main.swift` over every other `app/Sources` file
  for the app's own `LayerUniforms` (416 bytes, asserted), with pipelines built
  as `MetalRenderer.init` builds them.
- Output under `tools/proof/work/matte_spike/<check|measure|mutant-NAME>/`:
  the three `.metal` sources and metallibs, `bench-<height>.json` (each
  sample's median, min and max, and the K readbacks) and `result.json` (the
  rows, the figures, the route).

**The variants.** V0 is `Compositor.metal` as it stood before MT2
(`git show 464a3aa:app/Resources/Shaders/Compositor.metal`; a failed show is
a B0 failure). V1 (placeholder) and V2
(function constant) both add `kMatte*` codes, `MatteUniforms`,
`reelcut_matte_resolve_fragment` (it reads the matte target at the fragment's
pixel and returns the mode's value; its pipeline is `r8Unorm` with source
factor zero and destination factor `sourceColor`, so each matte multiplies
into a coverage cleared to 1), a `texture2d<float> matte [[texture(1)]]` on
both layer entry points, and, after step 7's corner radius, `alpha *=` the
coverage sampled at the fragment's canvas-normalised position — always in V1
(an unmatted layer binds a 1×1 white texture), behind
`kMatte [[function_constant(1)]]` in V2. Every patch has an anchor that must
occur exactly once in that shader; otherwise B0 fails naming it.

**The scenes**, full bleed at 1920×1080 and 3840×2160: S1 one picture layer;
S2 the picture, then a white-text layer drawn normally; S3 S2 with the text as
an alpha matte (the text drawn into a `bgra8Unorm` matte target, resolved, the
picture drawn cut, the text not drawn on the canvas); S4 S3 plus a static
full-frame gradient (black left of a quarter, white right of a half) as a luma
matte, resolved into the same coverage.

**Rows.** B0 the patches; B1 the three metallibs; B2 the bench; K3 / K4, per
size and per route: one pixel inside and one outside the matte (5×5 interior
pixels picked from the fixtures: K3 inside the text and outside it; K4 inside
the text where the gradient is white and inside it where it is black), inside
= the picture's own bytes from an S1 render, outside = the background
`[153, 102, 51, 255]` (BGRA), ±1. `--measure` adds H0 (the host gate, read
only: `pmset -g` `powermode` ≠ 1 and `pmset -g batt` on AC Power; shut, every
timing row is a named SKIP and the script exits 2), C0 (the CONTROL: two
interleaved V0 series of S1; |Δ median| is the noise floor), F (each series'
figure), T0 (each route's S1 overhead over V0), T1 (the route, recorded,
never a failure: V1 iff its S1 overhead ≤ bound + noise at both sizes, the
bound 0.02 ms at 1080p and 0.08 ms at 4K; else whichever route has the smaller
S1 overhead at 4K), T2 (the cost, the only stop: the route's S3 − S2 and
S4 − S2 ≤ 0.50 ms at 1080p and ≤ 2.00 ms at 4K) and M0 (memory, computed:
4·W·H per matte, W·H per coverage).

**Timing.** A sample is 200 frames after 5 unrecorded ones, one command
buffer per frame, committed and waited on, its time `gpuEndTime −
gpuStartTime`; three runs, and within each run every (scene, variant) sample in
turn, V0 / V1 / V2 / V0 again at S1, so a drift in the GPU's clocks lands on
every series alike. A figure is the median of the three runs' medians, quoted
with the runs' range. `--check` takes 10 frames, one run, and scores K only.

**Mutants.** `resolve-writes-one` (the resolve returns 1 everywhere) must fail
K3 and K4; `anchor-missing` (V1's step-7 anchor misspelt) must fail B0. The
script prints `mutant NAME: killed by …` or `SURVIVED`.

**Its record** is `designs/mattes.md`'s MT0 section, and spec §11 MT-6 carries
the route and its figures.
