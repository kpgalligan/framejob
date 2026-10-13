# Code-driven motion graphics — the input proposal

- **Status:** Closed (2026-09-24). It was input to road map 10, which
  reviewed it and built the feature (merged 2026-09-25). Where the two
  disagree, road map 10 holds.
- **Original:** `archive/svg-motion-components-plan.md` (201 lines). Sections
  cited below as "orig §x" refer to its headings. The review is in
  `archive/roadmap-10.md` §1, and the build's ADR is
  `designs/adr/roadmap-10-graphics.md`.
- **Spec decisions:** none of its own. What survived became spec §11
  G-1..G-16 through road map 10.

## Context

The user drafted this plan before any code was read. It proposes a
Remotion-shaped "motion component": a small ES module whose
`render(frame, props, meta)` returns SVG, run in embedded QuickJS and
rasterized by resvg. It should be deterministic, sandboxed, easy for an LLM
to write, permissively licensed, and have no external services.

Road map 10 §1 judged its technology sound but changed about a dozen points
to fit this codebase. Each change is recorded below.

## Adopted as written

- **Engine and rasterizer.** `rquickjs` (which vendors quickjs-ng 0.16.2)
  and `usvg`/`resvg`/`tiny-skia`, with fontdb reached through usvg.
- **`render` is pure.** `Math.random` throws and points to `random(seed)`,
  `Date` is frozen, and there is no I/O, a memory limit and an interrupt
  deadline (spec G-5).
- **`measureText` step 1 is the whole answer.** It parses a one-`<text>`
  SVG with the engine's own options, and G0 q4 measured that step 2 (direct
  shaping) is unnecessary. One amendment: it answers the ink box as well as
  the advance, because only the ink box agrees with the pixels.
- **A standard library written from scratch in Remotion's shapes:**
  `interpolate`, `Easing`, `spring`, `interpolateColors` (OKLab), `random`,
  `noise2D`/`noise3D`, `escapeXml`, `wrapText`, `fitText` and `textLines`.
  Road map 10 added `svg()`, `formatNumber` (quickjs-ng has no `Intl`) and
  `asset()`. No Remotion code was used.
- **Project-bundled fonts only, never system fonts** (spec G-6). This
  answers the plan's first open question. The bundled set is the app's six
  families plus `graphics/fonts/`.
- **Errors carry a line and column and show on the clip, not a crash.** They
  appear as an error card (spec G-8).
- **An inspector built from `schema`.** It became the first data-driven
  inspector section (spec G-15).
- **"Open script in external editor" and "Duplicate as new component"** are
  in the Graphic sub-tab.
- **Plain JavaScript, not TypeScript** (spec G-11). This answers the plan's
  third open question. `API.d.ts` gives editors completions.
- **Tests:** determinism across threads and orders, sandbox cases, stdlib
  unit tests in JS, `measureText` parity and edge-fringe alpha tests. All
  were built in `graphic/tests/`.
- **Example components.** Six were written: lower third, title card,
  counter, bar chart, kinetic type and callout. They serve as fixtures and
  as the Insert ▸ Graphic templates, and there is an LLM-sized API reference
  (`docs/graphics-api.md`).

## Amended

- **"Rust: MotionComponent" became a separate crate, `graphic/`,** linked
  into the one staticlib through `core/src/ffi_graphic.rs` alone (spec G-2).
  The reason is that the core's rules ("no pixel work", "no filesystem")
  stay true of the core.
- **The name became "graphic".** "Motion" was already taken by
  `video.motion` presets.
- **`asset://` ids and "the asset manager" became package-relative
  files:** `graphics/<name>.js`, `graphics/fonts/` and `graphics/assets/`
  (spec G-3). Reelcut has no asset manager, and a graphic's files travel
  with the package.
- **The frame cache is two levels, not one content hash.** The recipe hash
  says which JavaScript result to ask for, and the texture cache is keyed on
  the SVG TEXT plus size and library version. A settled graphic rasterizes
  once and cannot go stale.
- **Props are validated by the CORE against the schema the op carries,**
  not by the component (spec G-4), because the core is the one validator of
  a caller's patch. At render time the check is lenient: stale keys and
  wrong types become warnings.
- **`durationInFrames` from `meta` became the clip's own timeline, `in` +
  `length`, and `split` pins it** (spec G-9). Otherwise a split would
  restart the animation and play the outro twice.
- **"The last good frame may be shown dimmed" was reversed:** the error
  card never shows the last good frame, because that would hide the error
  from a person scrubbing (spec G-8).
- **The `asset` schema type is images only** (`kind: "image"`: PNG, JPEG,
  GIF, WebP, SVG, SVGZ). Fonts come in through `import_graphic_font`, not
  through a prop.
- **Hashing is SHA-256 (the revision) and FNV (the recipe), not
  blake3/xxhash.** The project already used FNV for the recipe, and CryptoKit
  provides SHA-256.
- **"Copy component context for LLM" became MCP tools** instead of a
  clipboard action: `graphic_reference`, `get_graphic` and `render_graphic`
  (a contact sheet), plus `API.md` written into the package's `graphics/`.

## Rejected

- **Worker pool, `rayon`, playback prefetch and parallel export.** The
  compositor and export are serial, and G0 measured the six samples at a
  worst p95 of 7.62 ms per frame at 1080p. This became G6, which the user
  deferred after 4K showed no stutter. The plan's fourth open question was
  answered with a target of 1080p30 in preview.
- **Reduced-resolution preview by scaling the pixmap.** A graphic
  rasterizes at its own size, 1 px to 1 px (spec G-7), and Preview Quality
  already scales the composition.
- **HEVC with alpha.** ProRes 4444 and APNG already carry alpha from a
  transparent canvas. HEVC-with-alpha is a separate export row, not a
  graphics feature, and is not built.
- **Golden-image tests with zero tolerance.** They conflict with
  `core/CLAUDE.md`'s oracle-only rule. The one exception is
  `graphic/tests/pins.json`, a SHA-256 tripwire for resvg upgrades.
- **Video or timeline layers as inputs to a component.** This was the
  plan's second open question, answered no. A graphic is a layer and
  combines through blend modes and track order. Mattes are compositor
  features.
- **Path helpers.** These were the plan's "can come later" item, and are
  still not built: they wait for an example that needs them.

## Known limits

The plan's non-goals still hold:
- no HTML/CSS or browser engine;
- no `<foreignObject>` or SMIL/CSS animation (resvg ignores both);
- no Canvas2D API;
- no audio from scripts.

Its crate choice makes `Intl` unavailable (quickjs-ng has none). Issue #39
reopens the engine choice for that reason. See the road map 10 ADR's G-2
entry for what a switch to JavaScriptCore must answer.

## Open items

None of its own. Everything left from the plan (G6, HEVC with alpha, path
helpers, and issue #39) is listed under Open items in
`designs/adr/roadmap-10-graphics.md` and tracked in issues #127 (G6), #103
(HEVC with alpha and path helpers) and #39.

## Where to look in the original

- orig Context, Goals, Non-goals: the ask and its constraints (determinism,
  permissive licences, LLM-writable).
- orig Architecture, Crates: the proposed stack and crate table.
- orig Component file format: the module shape, which road map 10 §5c
  extended.
- orig Script runtime, Standard library, SVG rendering, `measureText`
  implementation: the sandbox and API as proposed.
- orig Caching and parallelism, Editor integration, Export, Testing,
  Milestones: the proposed cache, UI, codecs, tests and nine milestones.
- orig Open questions: system fonts, video inputs, TypeScript and the
  performance budget, all answered in road map 10 §4/§6.
