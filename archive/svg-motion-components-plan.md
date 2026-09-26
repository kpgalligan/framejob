# Plan: Code-Driven Motion Graphics Components (SVG + Rust)

> **Input document, kept as written.** The design built from it is
> `designs/reelcut-roadmap-10.md` (2026-09-24), whose §1 reviews this plan
> point by point against the codebase. Where the two disagree, road map 10
> is the one that holds.

## Context

The editor is a macOS-only video editor built in Swift (UI, playback, export) and Rust (core engine). We are adding a new timeline component type: a **motion graphics component** defined by a small JavaScript file. Each component renders frames as a pure function of `(frame, props, meta)` and returns an SVG string. Rust rasterizes the SVG with `resvg` and hands the pixels to the existing compositor.

The model is similar to Remotion's (every frame is a deterministic function of the frame number), but there is no browser. The renderer is `resvg`, and the script runtime is embedded QuickJS. The tool will likely be open-sourced, so every dependency must be permissively licensed and there must be no paid or external services.

A key goal is that an LLM should be able to write components reliably. The API should be small, predictable, and shaped like APIs LLMs already know (`interpolate`, `spring`, easing, SVG).

**Before starting, inspect the existing codebase** for:
- How Swift and Rust communicate (swift-bridge, UniFFI, cbindgen, or hand-written C ABI). Follow the existing pattern; do not introduce a second FFI mechanism.
- How existing component or clip types are modeled on the timeline, and how they deliver frames to the compositor (pixel format, premultiplied or straight alpha, Metal textures or CPU buffers).
- Existing caching, threading, and asset-management infrastructure to reuse.

## Goals

- New component type backed by a `.js` file with a props schema.
- Deterministic rendering: the same script, props, and frame always produce byte-identical pixels on every machine.
- Random-access rendering (scrubbing), frame caching, and parallel rendering.
- Styled text with project-bundled fonts, including a text measurement API so scripts can wrap and fit text.
- Transparent backgrounds, composited correctly over other layers.
- Export with alpha via ProRes 4444 and HEVC with alpha.

## Non-goals (for now)

- HTML/CSS rendering or a browser engine.
- `<foreignObject>`, SMIL/CSS animation inside SVG (resvg ignores these; animation comes from the script).
- A Canvas2D or draw-command API. SVG output only; a faster path can be added later if profiling demands it.
- Audio generation from scripts.

## Architecture

```
Swift UI / timeline / export
        │  (existing FFI)
        ▼
Rust: MotionComponent
  ├─ ScriptRuntime (rquickjs, one context per worker thread)
  │     render(frame, props, meta) → SVG string
  │     host fns: measureText, random(seed), asset refs
  ├─ SvgRenderer (usvg + resvg + tiny-skia)
  │     shared Arc<fontdb::Database>, image href resolver
  ├─ FrameCache (LRU, keyed by content hash)
  └─ Worker pool (rayon or existing pool)
        ▼
Pixmap (RGBA8 premultiplied) → convert to compositor format
```

### Crates

| Purpose | Crate | Notes |
|---|---|---|
| JS engine | `rquickjs` | Small, fast startup, easy to sandbox. |
| SVG parse | `usvg` | Resolves SVG to a render tree; performs text shaping. |
| Rasterize | `resvg` + `tiny-skia` | Pure Rust, deterministic. |
| Fonts | `fontdb` | **Use the version re-exported by `usvg`** to avoid version mismatches. |
| Hashing | `blake3` or `xxhash-rust` | Cache keys. |
| Parallelism | `rayon` (unless the codebase already has a pool) | |

Verify that all crate licenses are compatible with the intended open-source license.

## Component file format

A component is an ES module:

```js
export const meta = {
  name: "Lower Third",
  durationInFrames: 150,   // default; timeline can override
};

export const schema = {
  title:    { type: "string", default: "Jane Doe" },
  subtitle: { type: "string", default: "Director" },
  accent:   { type: "color",  default: "#FF5A36" },
  fontSize: { type: "number", default: 64, min: 12, max: 200 },
};

export function render(frame, props, m) {
  // m = { fps, width, height, durationInFrames, assets }
  const x = interpolate(frame, [0, 20], [-600, 80], {
    easing: Easing.outCubic, clamp: true,
  });
  const s = spring({ frame: frame - 10, fps: m.fps, damping: 14 });

  return `<svg xmlns="http://www.w3.org/2000/svg"
               width="${m.width}" height="${m.height}">
    <rect x="${x}" y="${m.height - 260}" width="12" height="140"
          fill="${props.accent}"/>
    <text x="${x + 40}" y="${m.height - 180}"
          font-family="Inter" font-weight="700"
          font-size="${props.fontSize}" opacity="${s}">
      ${escapeXml(props.title)}
    </text>
  </svg>`;
}
```

Rules:
- `render` must be pure. No state carried between calls; the host may call frames in any order, on any thread.
- `schema` drives an auto-generated inspector panel in Swift and gives LLMs a typed way to modify props without editing code.
- Supported schema types to start: `string`, `number` (min/max/step), `boolean`, `color`, `enum`, `asset` (image/font reference).

## Script runtime (Rust)

- One `rquickjs::Runtime` + `Context` per worker thread. Load and evaluate the module once per thread, then call `render` per frame.
- **Sandboxing and determinism:**
  - Do not install any std/os modules. No filesystem, network, timers, or async.
  - Replace `Math.random` with a function that throws and points to `random(seed)`.
  - Freeze `Date.now()` and `new Date()` to a fixed epoch (or remove `Date`).
  - Set a memory limit (`set_memory_limit`) and an interrupt handler (`set_interrupt_handler`) that aborts a render exceeding a time budget (e.g. 500 ms).
- **Host functions** exposed as globals:
  - `measureText(text, { fontFamily, fontSize, fontWeight, fontStyle, letterSpacing })` returns `{ width, ascent, descent, lineHeight }`.
  - `random(seed)` is a deterministic PRNG (e.g. mulberry32 or splitmix) returning [0, 1).
  - `escapeXml(str)`.
- Errors (syntax, runtime, timeout, invalid SVG) are returned as structured errors with a message and line/column where available. The editor displays them as an overlay on the component's frame rather than crashing playback.

## Standard library (written in JS, bundled into every context)

Implement from scratch; do not copy code from Remotion or other libraries. Matching familiar API shapes is fine.

- `interpolate(value, inputRange, outputRange, { easing, clamp | extrapolateLeft/Right })` supports multi-segment ranges.
- `Easing`: linear, in/out/inOut for quad, cubic, quart, expo, sine, back, elastic, plus `bezier(x1, y1, x2, y2)`.
- `spring({ frame, fps, stiffness = 100, damping = 10, mass = 1, from = 0, to = 1 })` uses fixed-step numerical integration of a damped harmonic oscillator, evaluated deterministically up to `frame`. It returns `from` for negative frames.
- `interpolateColors(value, inputRange, colors)` interpolates in a perceptual space such as OKLab.
- `noise2D(seed, x, y)`, `noise3D(seed, x, y, z)` (simplex or Perlin).
- Text helpers built on `measureText`:
  - `wrapText(text, maxWidth, font)` returns lines.
  - `fitText(text, maxWidth, font, { min, max })` returns a fontSize.
  - `textLines(lines, { x, y, lineHeight, anchor, font })` returns `<text>` markup with `<tspan>`s.
- Path helpers (can come later): path length, point at length, stroke-draw-on via `stroke-dasharray`.

## SVG rendering

- Keep one `Arc<fontdb::Database>` per project, loaded explicitly from the project's bundled fonts. **Do not load system fonts** by default, so renders are identical across machines. Rebuild only when project fonts change.
- Build `usvg::Options` once per project with the shared fontdb and an **image href resolver** that maps `asset://<id>` to preloaded image bytes from the project's asset manager. No file paths or URLs in scripts.
- Render into a `tiny_skia::Pixmap` at the requested output size. For reduced-resolution preview, render with `Transform::from_scale(s, s)` into a smaller pixmap rather than changing `meta.width/height`. Scripts always work in composition coordinates.
- The pixmap starts fully transparent; unpainted regions stay transparent.
- **Alpha:** `tiny-skia` pixmaps are premultiplied RGBA8. Convert once at the boundary to whatever the compositor expects (likely premultiplied BGRA for Metal) and document the convention. Add a test for edge fringing (anti-aliased white text over transparent, composited over black and white backgrounds).

### `measureText` implementation

- **Step 1 (exact parity):** build a minimal SVG containing just the `<text>` element, parse it with `usvg` using the shared options, and read the text node's bounding box. This guarantees measurements match the final render exactly.
- **Step 2 (if profiling shows it's slow):** measure with `rustybuzz` directly using the same fontdb faces, with an LRU cache keyed on (text, font params). Keep the Step 1 path in tests to verify parity.

## Caching and parallelism

- Cache key = hash of (script source, serialized props, frame index, output width/height/scale, font database version, referenced asset versions).
- In-memory LRU with a configurable byte budget. An optional disk cache can come later.
- Invalidate on script file change (watch the file for hot reload), props edit, or font/asset change.
- During playback, prefetch upcoming frames across the worker pool. During export, render frames in parallel and reorder before encoding.

## Editor integration (Swift)

- New timeline component type: holds a script reference, props values, duration, and position/size/opacity/blend like other layers.
- Inspector auto-generated from `schema`.
- Error overlay when a render fails; the last good frame may be shown dimmed.
- "Duplicate as new component" and "Open script in external editor" actions.
- Consider a "copy component context for LLM" action that copies the script, schema, and a short API reference to the clipboard.

## Export

- Via AVFoundation / `AVAssetWriter`, using Apple's system encoders:
  - `AVVideoCodecType.proRes4444` for high-quality interchange (large files, intra-frame).
  - `AVVideoCodecType.hevcWithAlpha` for delivery (small files; Apple platforms and Safari).
  - Existing non-alpha codecs flatten the component onto the composition as usual.
- The encoder expects straight or premultiplied alpha depending on configuration; verify and convert accordingly.

## Testing

- **Golden image tests:** a folder of sample components, each rendered at a few frames, compared to checked-in PNGs, with a tolerance of zero by default.
- **Determinism test:** render the same frame on multiple threads and in different orders; assert byte-identical output.
- **Stdlib unit tests** in JS (run inside the embedded runtime): interpolate edge cases, spring settling, easing endpoints, wrapText with long words.
- **Sandbox tests:** `Math.random`, `Date.now`, infinite loops, and huge allocations are all handled and reported, never hang or crash.
- **measureText parity test:** measured width vs rendered bounding box.
- **Alpha compositing test** as described above.

## Milestones

1. **Static render:** Rust renders a hard-coded SVG with project fonts to a pixmap, with golden tests.
2. **Script runtime:** load a component module in rquickjs, call `render`, rasterize. Sandbox and error reporting in place.
3. **Stdlib:** interpolate, Easing, spring, random, noise, escapeXml, with unit tests.
4. **Text:** `measureText` (Step 1), wrapText, fitText, textLines.
5. **Editor integration:** timeline component type, schema-driven inspector, error overlay, hot reload.
6. **Performance:** frame cache, parallel rendering, playback prefetch, preview scaling. Profile before optimizing further.
7. **Assets:** `asset://` image resolver and `asset` schema type.
8. **Export:** ProRes 4444 and HEVC with alpha.
9. **Examples and docs:** 5–10 example components (lower third, title card, animated counter, kinetic typography, chart bars) and a concise API reference written so it can be pasted into an LLM prompt.

## Open questions (ask the user before deciding)

- Should system fonts be available as an opt-in, or only project-bundled fonts?
- Should a component be able to include video or other timeline layers as inputs, or only static assets?
- Is TypeScript authoring desired? (Would require a transpile step, e.g. via `swc` or `oxc`, before loading.)
- Target performance budget: e.g. real-time 1080p60 playback for typical components?
