# Reelcut — road map 10: graphics, motion graphics drawn by code

**Status: DESIGNED 2026-09-24, nothing built. EXPERIMENTAL, on the branch
`svg-motion`.** Nothing here lands on `main` until the user decides to merge
it (§9). The input to this design was `designs/svg-motion-components-plan.md`,
a tech plan the user had drafted. §1 reviews that plan against this codebase,
and every section after §1 is the design that came out of the review.

Every claim about the code is a scout's reading at `ed42a56`, cited with a
`file:line`. Every claim about a crate or a framework was taken from a
document and has not been measured. §3 lists the questions that only G0,
the spike, can settle. When G0 measures something this document only read
about, the section that depended on it is REWRITTEN, not annotated, as in
road map 8.

The baseline this design was written against:
- format version 9 (`core/src/format.rs:158`);
- `OP_COUNT` 57 (`core/src/op_table.rs:82`);
- 77 catalog tools;
- deployment target macOS 26;
- four crates in `core/Cargo.toml` (`serde`, `serde_json`, `serde_path_to_error`, `tiny_http`);
- no C code compiled anywhere in the build.

**The ask (2026-09-24).** Something like Remotion, which makes motion
graphics from code. Remotion's JavaScript renders React into a DOM. Here, a
JavaScript function returns SVG for a given frame. It is a new clip type.
These clips will almost always be created and edited by an AI through MCP,
and a clip's code lives on disk, inside the `.reelcut` package.

---

## 0. The idea, in one paragraph

A **graphic** is a clip whose pixels come from a small JavaScript module in
the package, at `graphics/<name>.js`. The module exports `render(frame, props,
ctx)`, which returns an SVG string. An embedded QuickJS runs the module and
`resvg` rasterizes the string, both inside a new Rust crate, `graphic/`,
which is linked into the one staticlib. The core crate stays pixel-free and
filesystem-free. The model stores only the clip's reference and values: the
module's name, its size, where in its own timeline the clip starts, and the
props. The core computes the frame number into the recipe, as it already
does for every other time-dependent thing. The app reads the file, hands its
text to the engine, and uploads the result as one more premultiplied BGRA
layer texture. That texture is composited by the one Metal pipeline, so it
gets placement, actions, blend modes, transitions, motion presets and export
(alpha included, through ProRes 4444) without any change to them. The agent
writes a graphic in one call and sees any errors in the reply. It then looks
at a contact sheet of frames without placing a clip, places the graphic with
an op, and changes its props with another op. Any editor, Claude Code
included, can also edit the file directly, and the app reloads it.

---

## 1. The proposed plan, reviewed

`designs/svg-motion-components-plan.md` is sound on its technology:
QuickJS, resvg, a Remotion-shaped standard library, and `render` as a pure
function of the frame. It was written without reading this codebase, and
this codebase changes about a dozen of its points. The table gives what
each point became and why.

| Plan says | This design | Why |
|---|---|---|
| "Rust: MotionComponent" beside the model | A separate crate `graphic/`, linked into the staticlib through core's `ffi_graphic.rs` | Spec §7: "all pixel and sample work happens on the platform"; `model.rs:245` "the core does no pixel work"; `model.rs:275` "the core has no filesystem". The rule is kept for the crate it was written for, and the exception is a crate boundary rather than a module (G-2). |
| Name "motion component" | **graphic** (`Source::Graphic`, `add_graphic_clip`, `graphics/`) | "motion" is taken: `video.motion` presets, `model_motion.rs`, `motion.rs`, spec §11 R5-4/R5-5. |
| Script paths / `asset://` ids from "the asset manager" | Package-relative names only: `graphics/<name>.js`, `graphics/fonts/`, `graphics/assets/` | Reelcut has no asset manager. Media is referenced by absolute path plus bookmark (`model.rs:116-124`), and a graphic's files travel with the package instead (G-3). |
| Frame cache keyed on script+props+frame+size+fonts+assets | Two levels. The recipe hash gives which JavaScript result to ask for. The texture cache is keyed on the **SVG text** plus size | A graphic that has settled returns the same SVG every frame, so a hold costs one JavaScript call and no rasterization. An SVG hash also cannot go stale when a file changes (§5d). |
| Worker pool, parallel prefetch, parallel export | Not in the first build (G6, only if G0/G3 measure a need) | The compositor is one serial queue with one frame in flight (`Compositor.swift:112,162-217`), and export is serial (`ExporterWriter.swift:103-111`). Parallelism is a change to both, and would be paid only against a measured shortfall. |
| Export ProRes 4444 and HEVC with alpha | Nothing new. ProRes 4444 and APNG already carry alpha from a transparent canvas | Spec §7.8 "ProRes 4444, and what `alpha` means". HEVC-with-alpha is a separate encoder row and goes in §7 as not built. |
| Reduced-resolution preview by scaling the pixmap | Rendered at the graphic's own size, 1 source px = 1 canvas px | That is exactly what text and shapes do (`LayerRenderers.swift:175-179`, `:53-56`). Preview Quality already scales the composition (`Playback.swift:329-334`). |
| Schema drives an auto-generated inspector | Kept, and it is the FIRST data-driven section | Every section today is hand-built from closures (`InspectorSection.swift:41`). The row builders it needs already exist (`InspectorPane.swift:514-616`). |
| Props validated by the component | Props are checked by the CORE against the schema the app passes with the op, and leniently at render time | D1 (road map 7): the core is the one validator of a caller's patch. The schema lives in a file the core never reads, so the op carries it (G-4). |
| `durationInFrames` from `meta` | The graphic's own timeline is the clip's `graphic.in` and `graphic.length`, and `split` pins it | Without this, splitting a graphic restarts its animation, and an outro plays at the end of both halves (G-9). |
| Open questions (system fonts, video inputs, TypeScript, performance budget) | Settled in §4 and listed in §6 | The user's standing preference is one pick with a reason. |
| Golden image tests with zero tolerance | Oracle tests first: exact pixels of solid shapes, byte-identity across threads and orders. A few pinned SHA-256 renders serve as tripwires for a crate upgrade | `core/CLAUDE.md:478-485`: black-box tests against independent oracles, no golden files. The engine crate adopts the rule and names its one exception (§5l). |

What the plan got right, and this design keeps word for word in spirit:
- `render` is pure;
- `Math.random` throws and names `random(seed)`;
- `Date` is frozen;
- the runtime has no I/O, a memory limit and an interrupt handler;
- `measureText` asks the rasterizer's own text engine, so a measurement
  cannot disagree with what is drawn;
- the standard library is written from scratch in Remotion's shapes;
- errors carry a line and column and show on the clip rather than stopping
  playback.

---

## 2. What Reelcut already has that a graphic reuses

- **An app-rendered layer path.** Text and shapes are drawn on the CPU into
  a premultiplied BGRA sRGB `CGContext` (`LayerRenderers.swift:433-446`) and
  uploaded as `.bgra8Unorm` (`:454-466`). They are cached in a 64-entry LRU
  under a string key (`:40,73-98`) and drawn at the texture's size as
  `sourceWidth/Height` (`Compositor.swift:849-853`). The shader already takes
  a `premultiplied=1` flag for app textures (`Compositor.metal:539`). A
  graphic is a third producer of exactly that texture.
- **A recipe that carries per-frame answers.** Text reveals and word
  captions fold their per-frame state into the layer's hash
  (`recipe_text.rs:240-258`). A graphic's frame number is one more answer of
  that kind.
- **Placement and effects are per layer, not per kind**
  (`Compositor.metal:380-418`). Blend, transitions, `video.motion`, actions
  on `video.*`, crop, shadow, filters and obscure all apply to a graphic for
  free.
- **Alpha export exists.** ProRes 4444 and APNG carry the canvas's alpha
  (spec §7.8). A lower third made as a graphic on a transparent canvas
  exports ready for another editor today, once the graphic draws.
- **`render_frame`** renders through the same Metal path as export
  (`Exporter.swift:559-597`), so a PNG the agent looks at is what export
  writes.
- **The package is a directory `FileWrapper`** (`ProjectDocument.swift:659-702`)
  with a temporary stand-in for an untitled document's cache (`:743-761`).
  `graphics/` follows the `cache/` pattern.
- **The MCP machinery**:
  - op tools print the core's arguments (`AgentCatalog.opTool`, `:128-139`);
  - a declarations table covers tools that take more or less than their op
    (`AgentCatalog+Declarations.swift:151`);
  - the argument gate (`AgentServer+Gate.swift:86-94`);
  - `performGroupedEdit` phrases refusals (`AgentServer.swift:605-613`).

## 2a. What is new, and has no precedent here

- **The first C code in the build** (QuickJS, through `rquickjs`'s sys
  crate) and the first Rust crate besides the core.
- **The first core-side state that outlives a call**: compiled modules and
  per-thread QuickJS contexts. Today the only global is the agent server
  (`ffi_agent.rs:48`), and `RcProject` is the only opaque handle type
  (`reelcut_core.h:86`).
- **The first file watching** in the app. There is no `DispatchSource`,
  `FSEvents` or `NSFilePresenter` anywhere in `app/Sources`.
- **The first user content inside the package that the app did not
  derive.** `media/` is only ever a copy the app made during Consolidate.
- **The first inspector section built from data.**
- **The first "Open in external editor" action.** Today the only
  `NSWorkspace` uses are Reveal in Finder and one web URL.

---

## 3. G0 — the spike: questions only a run can answer

No product code. The instruments go in `tools/proof/graphics_spike/`: a
scratch crate that depends on `rquickjs` and `resvg`, a copy of the six
sample graphics of §5k, and a Python driver. Each row is answered with a
number or a transcript, as road map 8 §10.1 was.

| # | Question | How it is answered | What the answer changes |
|---|---|---|---|
| q1 | Does `rquickjs` 0.14 + `resvg` 0.48 (default features OFF except `text`) build as a path dependency of `reelcut-core` into the `staticlib`+`rlib`, and at what cost? | Cold and warm `cargo build --release`, `make test` wall time before/after (baseline ~3 s warm, remaining §6), staticlib and `Reelcut.app` size before/after | If `make test` grows past ~2× warm, the engine goes behind a cargo feature the 32 test binaries do not enable (§5a) |
| q2 | Which QuickJS does `rquickjs` 0.14 vendor (bellard or quickjs-ng), and does it take ES modules with `export const` / optional chaining / template literals? | Evaluate §5c's module shape | The module format in §5c |
| q3 | Render cost per frame, in three parts: the JavaScript call, the usvg parse, the resvg rasterize | Six samples × 1920×1080 and 3840×2160 × 300 frames, p50/p95 per part, on this host | Whether G6 is owed: if the p95 at 1080p is over ~12 ms, playback cannot hold 30 fps next to decode on one serial queue |
| q4 | `measureText` parity: does usvg's text bbox for a lone `<text>` equal the width drawn inside a composed SVG? | 200 strings × 4 bundled faces × 3 sizes; compare with ink bounds of the raster | Whether `measureText` step 1 (parse a one-node SVG) is exact, or step 2 (`rustybuzz` direct) is needed |
| q5 | Determinism: the same frame on 8 threads, in shuffled order, repeated 3×, compared byte for byte | SHA-256 of every raster | G-5's claim; any difference is a stop |
| q6 | Sandbox: `while(true){}`, `new Array(1e9)`, deep recursion, a 50 MB string, `Math.random()`, `Date.now()`, `eval`, `import("x")` | Each returns a structured error within the budget, and the process survives | §5b's limits |
| q7 | The package: does a file written into `<pkg>/graphics/` by another process (a) survive an autosave-in-place, (b) not trip "changed by another application", (c) raise a `DispatchSource` event when an editor saves by atomic rename? | A probe opens a package in the built app, writes with `mv tmp x.js` from a shell, autosaves, and reads back | §5f's watcher and the whitelist line. If (b) trips, the watcher calls `packageContentsDidChangeOnDisk()` (`ProjectDocument.swift:793-798`) on every event |
| q8 | Is QuickJS's `Math.sin`/`Math.pow` bit-identical between a debug build, a release build and the test binary on this host? | Hash 10 000 results | Whether preview (app) and `cargo test` can be compared byte for byte |
| q9 | Is a `#[no_mangle]` function defined in core's `ffi_graphic.rs` and delegating to the `graphic` crate present in `libreelcut_core.a` and callable from Swift? | `nm` and a harness call | The FFI shape of §5e. A second staticlib is ruled out in advance: two Rust staticlibs in one binary duplicate `std`'s symbols |

## 3a. What G0 changes in this document

Empty until G0 runs.

---

## 4. Decisions for spec §11 — recorded before G1's first line

Each of these is copied into spec §11 by the phase that first depends on
it: G-1, G-2 and G-5 by G1, and the rest by G2. Until then they are
proposals on the branch.

### G-1 — A graphic is a SOURCE, not an effect; R5-1 stands for effects

Spec §1 lists "a plugin system" as a non-goal. R5-1 says effects are
"closed vocabularies, never a runtime… no expression language". A graphic
changes neither rule for what they govern:
- a transition, a motion preset, a filter and a blend stay closed
  vocabularies the one compositor draws;
- a script cannot reach another clip's pixels, the timeline, the model or
  the editor.

A graphic is a clip's CONTENT, in the same place a media file or an image
sits. It is closer to "the user can import any PNG" than to a plugin. §1's
non-goal gains one clause: "a clip may draw itself from a JavaScript module
in its package (road map 10); nothing else is scriptable". The user asked
for this reversal, as road map 3 reversed screen recording.

### G-2 — The engine is a separate Rust crate; the core crate keeps its two rules

- QuickJS and resvg live in `graphic/`, a crate at the repo root.
- `reelcut-core` depends on it by path, and ONE file, `core/src/ffi_graphic.rs`,
  calls into it.
- No module of the model, the ops, the plan or the recipe imports it.
- `core/src/` keeps "no pixel work" and "no filesystem" exactly. The
  `graphic` crate does pixel work and still no filesystem: the app reads
  every byte and hands it over.

Spec §7's first sentence becomes: "All pixel and sample work happens on the
platform, except a graphic's rasterization, which is the `graphic` crate's
(G-2)."

Why not JavaScriptCore and a platform rasterizer:
- **measureText has to be the rasterizer's own measurement**, or wrapped
  text overflows by a pixel. Only one process-side engine can promise that,
  and macOS has no public SVG rasterizer (CoreSVG is private, and WebKit is
  asynchronous, heavy and out-of-process).
- **QuickJS gives public memory and time limits.** JavaScriptCore's
  execution time limit is SPI.
- **One call in, pixels out** is a smaller seam than JavaScriptCore in Swift
  plus resvg over FFI.

Licences:
- `rquickjs` MIT, QuickJS MIT;
- `resvg`, `usvg` and `tiny-skia` Apache-2.0 OR MIT;
- `fontdb` and `rustybuzz` MIT.

No copyleft code, and no code from Remotion (whose licence is not
permissive).

### G-3 — A graphic's source is a FILE in the package, and is not an undo step

- The code lives at `graphics/<name>.js`. `<name>` matches
  `^[a-z0-9][a-z0-9-]{0,62}$`, so it is safe on disk, in a URL and in a
  tool argument.
- The clip names its module (`graphic.name`). Many clips may share one
  module, as many clips share one media file.
- Editing the file is NOT an undo step and does not dirty the document,
  exactly as a change to a media file on disk is not. Undo covers what the
  model holds: which module, the size, the timeline and the props.
- The reason is that a file is edited by things that are not the app (an
  agent's own Write tool, a person's editor). An undo stack that owned the
  file would have to be rebuilt from whatever those tools did.
- The price is stated to the agent in the `write_graphic` reply: "not
  undoable; keep your own copy if you want the old one back."
- A revision history is §7's.

The package gains `graphics/` beside `cache/` and `media/`, and the
`fileWrapper` whitelist gains its line (`ProjectDocument.swift:659-677`;
spec §5.6 "a directory not named there is DELETED by the next save"). An
UNTITLED document keeps its `graphics/` under its temporary cache root
(`:743-761`), and the first save carries it into the package, as `cache/`
is carried (`:738-740`).

### G-4 — The core checks props against the schema the OP carries; render time is lenient

- The schema is declared in the module (`export const schema`), and the core
  never reads the module. So `add_graphic_clip` and `set_graphic` take a
  `schema` argument (JSON, §5c's shape).
- The app fills it from the module's current revision, and the tools
  declare it as the one argument an agent does not send (a Declarations row,
  `AgentCatalog+Declarations.swift`). An agent that sends one anyway is
  refused by the gate, since the tool never published it.
- With a schema, the core checks every key of a `props` patch by its dotted
  path (`props.accent`), with type, range and enum membership. A refusal is
  in the core's words, and no handler predicts one (`app/CLAUDE.md:944-958`).
- Without a schema (a file read, or a replayed op), the core checks shape
  only: an object of at most 64 keys whose values are a string of at most
  4096 characters, a finite number, or a boolean.

At RENDER time props are lenient, because a file edit can change the
schema after the props were set:
- `ctx`'s props are the schema's defaults overlaid with the stored values;
- a stored key the schema no longer has is passed through, and a wrong type
  falls back to the default;
- both are reported as WARNINGS in the graphic's diagnostics (§5g), and
  never as errors.

A clip whose module was edited keeps drawing, and the agent is told what no
longer matches.

### G-5 — A graphic is a pure function of its inputs (R5-5 for code)

A frame is a function of these inputs only:
- source text;
- props;
- frame number;
- size;
- the font set;
- the asset bytes.

Anything that could make it depend on something else is removed or made to
throw:
- no wall clock: `Date` is frozen at 2000-01-01T00:00:00Z and `Date.now()`
  returns its epoch;
- no randomness: `Math.random` throws `"Math.random is not available; use
  random(seed)"`;
- no I/O: no `std` or `os` module is installed, and `import` of anything is
  refused;
- no state between calls: the module is evaluated once per thread, and a
  test renders the same frame after 300 others and compares bytes.

`render_frame` at a tick is byte-identical run after run, and preview and
export agree. A graphic that keeps a module-level counter produces a
different frame and breaks that guarantee. The standard library cannot
stop it, and §5l's proof row catches it.

Limits:
- 64 MB heap per context;
- 1 MB stack;
- 250 ms per `render` call in preview and 2 s in export and `render_frame`.
  Over budget is an error for that frame, not a hang.

These limits are also what makes a package from someone else safe to
open. Their code runs, and it can reach nothing.

### G-6 — Fonts: the app's bundled faces and the package's, never the system's

The engine's font set has two parts:
- the faces bundled in `app/Resources/Fonts/`: Anton, Bebas Neue, Darker
  Grotesque, IBM Plex Mono, Montserrat and Source Sans 3, all OFL;
- every `.ttf`/`.otf` in `graphics/fonts/`.

The system's fonts are NOT loaded. A graphic authored on this Mac then
renders the same on another, and the agent is told exactly what exists: a
`font-family` the set does not have is a warning naming the families it
does have, not a silent fallback. `import_graphic_font` (§5h) copies a font
into the package. This is the open question from the plan, answered.

### G-7 — A graphic draws at its own size, and crosses the FFI as premultiplied BGRA

- A graphic has a `width` and `height` in canvas pixels: the module's
  `meta.width/height` if it declares them, else the canvas size at the time
  of the add.
- Like a nest's, the size is frozen: a later canvas change does not re-lay
  out a graphic.
- It rasterizes at exactly that size, 1 source px = 1 canvas px, which is
  what a shape does (`LayerRenderers.swift:175-179`). Scale, position and
  rotation are the layer's.
- The engine writes premultiplied BGRA8 in sRGB into a buffer the app owns.
  That is the format `LayerRenderers` already uploads (`:433-466`), so
  tiny-skia's RGBA is swizzled once, in Rust, and nowhere else.
- The maximum side is 8192, the renderer's own cap (`LayerRenderers.swift:43`).

### G-8 — A failing graphic shows its error in preview, answers it to the agent, and stops an export

- **Preview.** A module that does not compile, or a frame that throws or
  times out, draws an ERROR CARD in the layer's box: a dark red fill, a 2 pt
  red border, and the first diagnostic in IBM Plex Mono with its line and
  column. It never draws the last good frame, which would hide the error
  from a person scrubbing.
- **`render_frame` and `render_graphic`.** They return the diagnostics as
  text beside the image.
- **Export.** Before it starts, export compiles every module a clip in the
  range names and refuses on a compile error, listing each one. A frame
  that fails during export aborts it, naming the graphic and the frame.
  An error card is never written into a video.

### G-9 — A graphic has its own timeline: `in` and `length`, and `split` pins it

- `graphic.in` (ticks, ≥ 0) is where on the graphic's own timeline the
  clip's first frame falls.
- `graphic.length` (ticks, or `null`) is how long the graphic's timeline
  is. `null` means "it ends with the clip", which is what a fresh clip wants:
  stretch the clip and the animation stretches its outro to the new end.
- `split` gives the right half `in + cut` and pins BOTH halves' `length` to
  the original's effective length. The animation then continues across the
  cut and plays its outro once, at the true end.
- `trim_start` advances `in`, and `trim_end` never changes `length`, so
  trimming a graphic cuts it as trimming media cuts a file.
- There is no source bound: a clip longer than `length` keeps calling
  `render` with frames past `durationInFrames`, and what it draws there is
  the module's business.

The core computes the frame number:
- `frame = floor((in + clip_time) / frame_ticks)` on the canvas grid;
- `ctx.durationInFrames = ceil(effective_length / frame_ticks)`;
- clip time is §7.3's, which already accounts for nests.

A graphic has no `speed` (speed applies to media only, spec §5.2).

### G-10 — Props are not action targets; everything about the LAYER is

The graphic animates itself, so `graphic` is not among the groups an
action's `end` may carry, which is W-6's precedent. `video.*` actions,
motion presets, transitions and blend all apply, because they belong to the
layer. Keyframed props are listed in §7.

### G-11 — Plain JavaScript, one ES module, no TypeScript

- A module is ES2020+ JavaScript as QuickJS evaluates it, with no build
  step.
- Agents write plain JavaScript as reliably as TypeScript, and a
  transpiler (`swc`/`oxc`) would be a second large dependency whose only
  output is the same JavaScript.
- `graphics/API.d.ts` (§5i) gives an editor completions without making
  types part of the format.

### G-12 — Colours in props are CSS strings

- A `color` prop is a CSS colour string, normalised by the core to
  `#rrggbb` or `#rrggbbaa` lowercase.
- It is not the model's `[r,g,b,a]` floats, because props are the module's
  vocabulary, which goes straight into SVG attributes. The inspector's
  colour well converts at its edge.

### G-13 — The revision is a content hash, and an export pins it

- A module's revision is the SHA-256 of its bytes, computed with CryptoKit.
- Preview always uses the newest revision, and the watcher refreshes the
  paused frame when one lands (`Playback.refreshPausedFrame`,
  `Playback.swift:251`).
- An EXPORT pins, at its start, the revisions (and the font and asset sets)
  it compiled, so an agent editing a file mid-export cannot produce a video
  whose first half is one version and its second half another.

---

## 5. The design

### 5a. The crate — `graphic/`

```
graphic/
  Cargo.toml         rquickjs, resvg (default-features = false, features = ["text"]), serde_json, sha2
  CLAUDE.md          the crate's rules: purity, no filesystem, limits, the one exception to oracle-only tests
  src/lib.rs         Library, Module, render — the whole public surface
  src/library.rs     the font set (Arc<fontdb::Database>) and the asset map, and their versions
  src/module.rs      compile a source into a Module: evaluate once, read meta and schema, keep the text
  src/runtime.rs     per-thread QuickJS runtimes and contexts, keyed by (module id, revision); limits
  src/sandbox.rs     the globals removed or replaced (G-5)
  src/host.rs        the host functions: measureText, random, escapeXml, asset
  src/stdlib.js      the standard library, embedded with include_str!, evaluated into every context
  src/props.rs       defaults-overlay and the lenient render-time check (G-4)
  src/raster.rs      usvg parse with the shared options, resvg render, RGBA→BGRA swizzle
  src/diagnostic.rs  { level, message, line, column, frame } and its JSON
  tests/             black-box through lib.rs (§5l)
```

- **Library** holds the font database and the asset map. It is built by the
  app once per document and rebuilt when `graphics/fonts/` or
  `graphics/assets/` changes. It is immutable once built and shared by
  `Arc`. Its `version` is a hash of the font and asset bytes.
- **Module** is compiled from `(library, name, source)`. Compiling evaluates
  the module once, to read `meta` and `schema` and to surface syntax errors.
  A Module is `Send + Sync` and holds no QuickJS object: each render thread
  keeps its own context in a `thread_local!` map keyed by module id, evicted
  when the Module drops.
- **`svg(module, frame, props_json, ctx_json) → (svg, diagnostics)`** runs the
  JavaScript.
- **`rasterize(library, svg, width, height, out, stride) → diagnostics`**
  draws. The two are separate calls on purpose, because the app keys its
  texture cache on the SVG text (§5d).
- `resvg`'s `system-fonts` and `raster-images` default features are OFF.
  Images in a graphic are PNG and JPEG from `graphics/assets/`, decoded by
  usvg's own `image` support, if G0 confirms that it builds without
  `raster-images`, and otherwise that feature comes back on.
- If q1 finds the 32 core test binaries slowed by more than ~2×, the
  dependency sits behind `features = ["graphic"]`: on for the staticlib
  build in the Makefile, and off for `cargo test` in `core/`. The engine's
  own tests run in `graphic/`.

### 5b. The runtime and its limits

- One `rquickjs::Runtime` and one `Context` per (thread, module).
  - `set_memory_limit(64 MB)` and `set_max_stack_size(1 MB)`.
  - `set_interrupt_handler` compares a monotonic deadline set before each
    call (250 ms preview, 2 s export and `render_frame`, G-5).
- Nothing from `rquickjs`'s `std`/`os` loaders. The module loader resolves
  NO specifier, so `import "x"` is "imports are not available in a graphic;
  the standard library is global".
- Replaced globals are `Math.random` and `Date` (G-5). The deletions are
  `eval`, `Function` and `WebAssembly` if present: one source of code is
  the module.
- A syntax error at compile, and an exception, timeout or out-of-memory at
  render, each become a Diagnostic `{level: "error", message, line, column,
  frame}`. QuickJS's backtrace gives line and column. The column is
  mapped back through the module wrapper's fixed offset.
- `render` must return a string that starts with `<svg`. Anything else is an
  error naming what came back ("render returned undefined at frame 12 —
  did you forget `return`?"). An agent's most common mistake gets its own
  sentence.

### 5c. The module format and the API

```js
// graphics/lower-third.js
export const meta = {
  name: "Lower third",        // shown in the inspector; the file name is the id
  width: 1920, height: 1080,  // optional; default the canvas at add time (G-7)
  durationInFrames: 150,      // optional; default length of a new clip
};

export const schema = {
  title:    { type: "string",  default: "Jane Doe", label: "Title" },
  subtitle: { type: "string",  default: "Director" },
  accent:   { type: "color",   default: "#ff5a36" },
  size:     { type: "number",  default: 64, min: 12, max: 200, step: 1 },
  boxed:    { type: "boolean", default: true },
  align:    { type: "enum",    default: "left", options: ["left", "center", "right"] },
  logo:     { type: "asset",   default: null },          // a file in graphics/assets/
};

export function render(frame, props, ctx) {
  // ctx = { fps, time, durationInFrames, progress, width, height, canvas: {width, height} }
  const x = interpolate(frame, [0, 20], [-600, 80], { easing: Easing.outCubic, clamp: true });
  const s = spring({ frame: frame - 10, fps: ctx.fps, damping: 14 });
  const out = interpolate(frame, [ctx.durationInFrames - 15, ctx.durationInFrames], [1, 0], { clamp: true });
  return svg(ctx, `
    <g opacity="${out}">
      <rect x="${x}" y="${ctx.height - 260}" width="12" height="140" fill="${props.accent}"/>
      <text x="${x + 40}" y="${ctx.height - 180}" font-family="Montserrat" font-weight="800"
            font-size="${props.size}" opacity="${s}">${escapeXml(props.title)}</text>
    </g>`);
}
```

**The schema's types.** A schema has at most 64 keys, each matching
`^[A-Za-z_][A-Za-z0-9_]{0,31}$`.

| type | value | options | inspector row |
|---|---|---|---|
| `string` | ≤ 4096 chars | `multiline: bool` | text field, or text area when multiline |
| `number` | finite | `min`, `max`, `step` | value row with slider when both bounds are given |
| `boolean` | | | checkbox |
| `color` | CSS colour → normalised hex (G-12) | | colour well |
| `enum` | one of `options` (≤ 32 strings) | `options` | popup |
| `asset` | a file name in `graphics/assets/`, or `null` | `kind: "image"` | popup of the folder |

Every entry takes `default` (required, and checked against its own type),
`label` (optional, else the key) and `help` (optional, shown as the row's
tooltip). The schema's own JSON is the `schema` argument G-4 sends, so the
core parses the same shape: `core/src/model_graphic.rs` holds the type, and
the engine emits it.

**`ctx`**:
- `fps` is the canvas rate as a number, e.g. 29.97002997;
- `time` is `frame / fps`;
- `durationInFrames` is G-9's;
- `progress` is `frame / max(1, durationInFrames - 1)`, clamped 0–1;
- `width` and `height` are the graphic's;
- `canvas` is the project's.

**The standard library**, written from scratch, in `stdlib.js`:
- `svg(ctx, body, {background})` wraps a body in the root element with the
  right `width`, `height` and `viewBox`, the most common thing to get
  wrong.
- `interpolate(value, input, output, {easing, clamp, extrapolateLeft,
  extrapolateRight})`, multi-segment.
- `Easing`:
  - `linear`;
  - `in`/`out`/`inOut` × `quad`, `cubic`, `quart`, `expo`, `sine`, `back`
    and `elastic`, as `Easing.outCubic` and so on;
  - `bezier(x1, y1, x2, y2)`.
- `spring({frame, fps, stiffness = 100, damping = 10, mass = 1, from = 0,
  to = 1})` uses fixed-step integration at 1/240 s from frame 0, so the
  same frame costs the same whatever was asked before.
- `interpolateColors(value, input, colors)` works in OKLab and returns hex.
- `random(seed)` is splitmix32 → [0, 1). `seed` is a number or a string.
- `noise2D(seed, x, y)` and `noise3D(seed, x, y, z)` are simplex.
- `measureText(text, font)` returns `{width, ascent, descent, lineHeight}`.
  `font` is `{family, size, weight, style, letterSpacing}`, and it is a host
  function (§5b).
- The text helpers are built on `measureText`:
  - `wrapText(text, maxWidth, font)` returns lines, breaking an over-long
    word by characters;
  - `fitText(text, maxWidth, font, {min, max})` returns a size;
  - `textLines(lines, {x, y, lineHeight, anchor, font})` returns
    `<text>` + `<tspan>` markup.
- `escapeXml(s)`.
- `asset(name)` returns the href the rasterizer resolves. An unknown name is
  a warning naming the folder's files.
- The path helpers (length, point at length, draw-on by dash) are §7's,
  until an example needs them.

### 5d. Rendering in the app

```
Compositor.serve (serial renderQueue)
  recipe layer {kind: "graphic", name, frame, ctx, props, size, hash}
    → GraphicRegistry.shared.module(for: recipeKey, name)        // pinned for export (G-13)
    → svg = ReelCore graphicSVG(module, frame, props, ctx)       // JS, every frame
    → key = "graphic:" + fnv(svg) + ":" + w×h + ":" + library.version
    → LayerRenderers.cached(key) ?? rasterize(library, svg, w, h) → BGRA → MTLTexture
```

- **The texture key is the SVG text**, so a graphic that has settled (a
  title that has arrived and holds) rasterizes once. A file edit changes
  the SVG and can never hit a stale texture.
- **Where it plugs in**: `LayerRenderers`' existing 64-entry LRU (`:40`),
  one `case .graphic` in the compositor's source switch, and the drawing in
  a new `LayerRenderersGraphic.swift`. `Compositor.swift` (1391) takes a
  call line only.
- **The JavaScript still runs every frame.** q3 measures its cost, and a
  string cache keyed by the recipe hash is G6's if the measurement asks
  for it.
- **The error card** (G-8) is drawn by `LayerRenderersGraphic` with Core
  Graphics into the same bitmap type. Its key is the diagnostic's text, so
  it is cached like any texture.
- **`render_frame`**: `Exporter.renderFrame` builds a fresh composition per
  call (`Exporter.swift:559-597`). Its RecipeSource key maps to a
  `GraphicRegistry` snapshot, and any diagnostics raised while that key was
  live are returned with the image.

### 5e. The FFI — nine exports, one new file per side

In `core/src/ffi_graphic.rs`, delegating to the `graphic` crate, with
`reelcut_core.h` and a `ReelCore.swift` wrapper each (the lockstep rule):

```c
typedef struct RcGraphicLibrary RcGraphicLibrary;
typedef struct RcGraphic RcGraphic;

RcGraphicLibrary *rc_graphic_library_new(void);
bool  rc_graphic_library_add_font(RcGraphicLibrary *, const uint8_t *bytes, size_t len, char **err_out);
bool  rc_graphic_library_add_asset(RcGraphicLibrary *, const char *name, const uint8_t *bytes, size_t len, char **err_out);
void  rc_graphic_library_free(RcGraphicLibrary *);
RcGraphic *rc_graphic_compile(const RcGraphicLibrary *, const char *name, const char *source, char **diag_out);
char *rc_graphic_describe(const RcGraphic *);                  // {"meta":…, "schema":…, "revision":…}
char *rc_graphic_svg(const RcGraphic *, int64_t frame, const char *props_json, const char *ctx_json,
                     uint32_t budget_ms, char **diag_out);     // NULL + diag = error
bool  rc_graphic_rasterize(const RcGraphicLibrary *, const char *svg, uint32_t w, uint32_t h,
                           uint8_t *out_bgra, size_t stride, char **diag_out);
void  rc_graphic_free(RcGraphic *);
```

- A library is freed only after every graphic compiled against it, and
  `RcGraphic` holds an `Arc` to it so the order cannot go wrong.
- `diag_out` is always a JSON array of Diagnostics, written on success too
  when there are warnings.
- The usual rules apply: `catch_unwind` through `ffi_util.rs`, NULL
  tolerance first, strings freed with `rc_string_free`, and every export
  both tested and in the null-safety sweep (`core/CLAUDE.md:440-444,478-485`).

**The toll on `ReelCore.swift` (1440 lines, over the cap).** Its rule is
that it is the ONLY file calling `rc_*`, so the ~110 lines of wrappers
(`GraphicLibrary`, `GraphicModule`) must go in it. It first gives up at
least that much as a pure move, landed and gated alone, before G1's
wrappers. The candidate is `mediaURL(for:)` and the value types beside it
(`:1417-1431`), which call no `rc_*`. The pick and the measured counts go
in §10's G1 record and in remaining §3.

### 5f. The package and the watcher — `GraphicStore.swift`

```
Talk.reelcut/
  project.json
  cache/ …
  media/ …
  graphics/            # NEW (G-3); user content, not a cache
    API.md             # the reference (§5i), written by the app, overwritten when stale
    API.d.ts           # types for editors (G-11)
    lower-third.js
    title-card.js
    fonts/             # optional; .ttf/.otf (G-6)
    assets/            # optional; .png/.jpg (§5c `asset`)
```

**The store.** `GraphicStore` owns one document's graphics:
- **Where the folder is**: the package, or the untitled document's
  temporary root. It re-points when the first save moves the folder, and
  posts `.graphicsLocationDidChange`, so `get_graphic`'s `path` is always
  current.
- **The scan**: every `*.js` with a legal name → `(name, bytes, revision)`,
  plus a font and asset scan → `library.version`.
- **The watch**: a `DispatchSource.makeFileSystemObjectSource` on
  `graphics/` and on each subfolder, for `.write`, `.rename` and `.delete`.
  An editor's atomic save shows as a rename in the folder (q7 verifies
  this). Events are coalesced over 100 ms, then the folder is rescanned
  and only changed revisions are recompiled.
- **What a change does**: it posts `.graphicsDidChange(names)`. Playback
  refreshes the paused frame, the inspector re-reads the schema, and
  `GraphicRegistry` swaps the preview's modules.
- **Writing**: the app's own writes (`write_graphic`, templates, `API.md`)
  go to `<name>.js.partial` and are then moved into place, as
  `ReverseRenderer` does (`:437-461`). After the folder is CREATED, the
  store calls `packageContentsDidChangeOnDisk()` (`ProjectDocument.swift:793-798`).
  If q7 finds that a file write inside `graphics/` also trips NSDocument's
  modification check, it calls it after every event.

**What `ProjectDocument` takes.** `ProjectDocument.swift` (1380, over the
cap) takes one whitelist line in `fileWrapper(ofType:)` and one line in the
untitled carry-over. The store, the wrapper builder and the re-pointing go
in `ProjectDocument+Graphics.swift`.

**`GraphicRegistry`** (`GraphicRegistry.swift`) maps a RecipeSource key to
the compiled modules and library the compositor should use:
- **preview's key** always follows the newest revision;
- **an export's key or a `render_frame`'s** is a snapshot taken when it
  starts (G-13).

This is how `Compositor.serve`, which AVFoundation instantiates, finds
the modules, in the same way it finds `mediaURLs` through the instruction
(`Compositor.swift:961-966`).

### 5g. The model — format version 10

```json
{ "id": 40, "track": 3, "start": 0, "duration": 5000000,
  "source": { "kind": "graphic" },
  "graphic": { "name": "lower-third", "width": 1920, "height": 1080,
               "in": 0, "length": null,
               "props": { "title": "Kevin", "accent": "#2d7ff9" } },
  "video": { … }, "audio": null, "text": null, "shape": null, … }
```

- `Source::Graphic` is a unit variant, as `Text` and `Shape` are
  (`model.rs:237-271`). The description lives on `Clip.graphic:
  Option<GraphicProps>` in the new `core/src/model_graphic.rs`, together
  with the schema type (G-4) and the name rule (G-3).
- Every key defaults, and a v9 file has no graphic clips, so v9 reads
  unchanged (`core/tests/schema_v10.rs`).
- `props` is stored as the caller wrote it after G-12's normalisation. Key
  order is preserved, because the text is read back byte for byte.
- `audio` is `null`: a graphic has no sound.
- `source_size` is `[width, height]`, like a shape's box
  (`model_query.rs:156-169`).
- `evaluate.rs`: `segment_of` → `None` (`:271`), and `draws()` → true
  (`:384`). No AVFoundation track.
- The exhaustive matches that gain an arm are `model_query.rs:156-169,336-339`,
  `edit_paste.rs:108-147`, `edit_track.rs:63` and `scope.rs:215-216`.

**The recipe — `core/src/recipe_graphic.rs` (new).** `recipe.rs` is at 582
and takes one call line in `layer_source`. The layer's source is:

```json
{ "kind": "graphic", "name": "lower-third", "hash": "…",
  "frame": 37, "ctx": { "fps": 29.97002997, "time": 1.2345, "durationInFrames": 150,
                        "progress": 0.248, "width": 1920, "height": 1080,
                        "canvas": { "width": 1920, "height": 1080 } },
  "props": { … } }
```

It carries `source_size` `[w, h]`, and the hash is FNV-1a over name, props,
size and frame (`recipe.rs:71-95`'s function).

### 5h. The ops and the tools

**Two ops** (`OP_COUNT` 57 → 59). Their semantics go in the new
`core/src/edit_graphic.rs` (`edit_clip.rs` is 751, over the cap). It reuses
`add_described_clip` (`edit_clip.rs:380`) by adding one field to
`Described`.

| op | arguments (`op_table.rs`) | semantics |
|---|---|---|
| `add_graphic_clip` | `track` Id req, `at` Ticks req, `duration` Ticks opt, `name` String req, `width` Int opt, `height` Int opt, `props` Object opt, `schema` Object opt | Places a graphic clip:<br>• `width`/`height` default to the canvas;<br>• `duration` defaults to 5 s, and the TOOL fills it from `meta.durationInFrames` when the caller omits it;<br>• `props` are checked against `schema` when given (G-4);<br>• the name is checked against G-3's pattern;<br>• the core does not know whether the file exists (it has no filesystem), and the tool refuses a missing module before the op is built. |
| `set_graphic` | `clips` Ids req, `patch` Object req, `schema` Object opt | Patches `name`, `width`, `height`, `length` and `props`, merged key by key (spec §5.2's patch rule). `props.x: null` clears x back to its default. It refuses a non-graphic clip by id. `in` is not patchable, because trims and split own it (G-9). |

**The editing rules the other ops take** (G-9, G-10):
- `split` pins `length`;
- `trim_start` advances `in`;
- an action `end` naming `graphic` is refused in `edit_action.rs` with the
  sentence "props are not animated by actions; a graphic animates itself —
  change the module or its props";
- `paste_attributes` does not carry `graphic` (§7).

**Six app-state tools**, in a new `AgentCatalog+Graphics.swift` and
`AgentServer+Graphics.swift`, taking the catalog from 77 to 85 (two op
tools and six app-state tools):

| tool | arguments | answers | mirrors |
|---|---|---|---|
| `write_graphic` | `name`, `source` | Writes `graphics/<name>.js` atomically and compiles it, and answers `{path, revision, meta, schema, diagnostics, clips}` in ONE call. `clips` is the ids that use it. It is not undoable (G-3), and the reply says so. It refuses an illegal name with the pattern. | the file on disk (an external editor) |
| `get_graphic` | `name?` | With a name: `{path, source, revision, meta, schema, diagnostics, clips}`. Without one: every module's `{name, revision, ok, clips}`, plus `folder`, the absolute path of `graphics/`, which an agent with its own file tools may edit directly. | the Graphic sub-tab's Source section |
| `render_graphic` | `name`, `frames` (list, ≤ 16) or `frame`, `props?`, `width?`, `height?`, `max_width?`, `background?` (`transparent` \| `checker` \| a CSS colour), `format?` (`png` \| `svg`) | Renders the module WITHOUT a clip, as a contact sheet of the frames with each frame number printed under its cell, plus the diagnostics per frame. `svg` returns the SVG text of one frame, for debugging. The images are written the way `render_frame` writes them (`FrameWriter`). | the Graphic sub-tab's preview strip (G5) |
| `import_graphic_font` | `path` | Copies a `.ttf`/`.otf` into `graphics/fonts/`, rebuilds the library, and answers the new family list | File ▸ Add Font to Graphics… |
| `import_graphic_asset` | `path`, `name?` | Copies a PNG/JPEG into `graphics/assets/` | File ▸ Add Image to Graphics… |
| `graphic_reference` | — | The API reference as markdown (the bundled `GraphicsAPI.md`, §5i) | Help ▸ Graphics Reference |

- **Declarations rows**:
  - `schema` on both op tools is filled by the app and not published, so
    the tool takes less than its op;
  - `duration`, `width` and `height` on `add_graphic_clip` are filled from
    `meta` when omitted, so the tool's default differs from the op's.
- **`get_project` gains** `graphics`: `[{name, revision, ok, clips}]`, and
  `render_frame`'s reply gains a `graphics` diagnostics block when a
  graphic in the frame warned or failed.
- **`AgentServer.swift` (frozen) takes eight `handlers` lines** and nothing
  else. The count prose "twenty app-state tools" (`AgentCatalog.swift:54-65`,
  `AgentServer.swift:214-224`, spec §7.9) becomes twenty-six.

**The agent's loop**, which the proof drives and `API.md` teaches:
1. `graphic_reference` (once).
2. `write_graphic` → read the diagnostics → fix → `write_graphic` again.
3. `render_graphic {frames: [0, 15, 30, 60, 120]}` → look at it → go back
   to step 2.
4. `add_graphic_clip`, then `render_frame` in context.
5. `set_graphic {patch: {props: …}}` for copy changes, with no code touched.

### 5i. The reference — one document, three places

`docs/graphics-api.md` is the source. It is written for an LLM to read
once: the module shape, `ctx`, the schema table, every standard library
function with a one-line example, the sandbox's refusals, the fonts that
exist, and five idioms (a slide-in, a staggered list, a counter, fit and
wrap a title, a draw-on stroke). It is kept under ~400 lines so it fits in
a prompt.

The build copies it into the app's Resources as `GraphicsAPI.md`:
- `graphic_reference` serves it;
- the store writes it into each `graphics/` as `API.md` (with `API.d.ts`),
  so an agent that finds the folder finds the manual;
- the Help menu opens it.

A test in `graphic/` evaluates every code block in the document and fails
if one throws, so the reference cannot rot away from the engine.

### 5j. The inspector — the Graphic sub-tab (G5)

- **Sub-tab.** `graphic` joins `ClipPane.subTabs` (`ClipPane.swift:99-107`)
  and gets a case in `makeSections()` (`:134-206`).
- **Source section**:
  - the module's `meta.name` and the file name, then the revision's first
    8 hex digits;
  - three buttons: **Open in Editor** (`NSWorkspace.shared.open` on the
    `.js`, the first such use), **Reveal in Finder** and **Duplicate as New
    Graphic…**, which copies the file under a new name and repoints this
    clip, one undo step for the repoint;
  - the diagnostics, as a list of error and warning rows, each line/column
    clickable to Open in Editor.
- **Properties section, generated from the schema.** One row per key,
  built with the existing builders:
  - `inspectorValueRow` for string and number;
  - `inspectorCheckRow` for boolean;
  - `inspectorColorRow` for colour;
  - `inspectorPopupRow` for enum and asset.

  Every write is `set_graphic {clips, patch: {props: {key: v}}, schema}`.
  Slider drags use the live trio (`ProjectDocument.swift:1227-1266`), so a
  drag is one undo step. Reset shows when a value differs from the
  schema's default, and writes `null` (CI-9). Stored keys the schema
  no longer has show below the rows, dimmed, with ⌫ to remove each one
  (G-4's leniency, made visible).
- **Size section**: width, height and "Fit to Canvas".
- **Timeline section**: `in` as read-only and `length` as a field with
  "Follow Clip" (`null`).
- **Structure signature.** Rebuilt when the schema's KEYS change, so an
  external edit adding a prop adds a row live.
- **New file.** `GraphicPane.swift`, under 400. The row generator gets its
  own file (`GraphicSchemaRows.swift`) if the pane passes ~300.

**Menus** (`AppDelegate+Menus.swift`, 549):
- **Insert ▸ Graphic** is a submenu of the bundled templates (§5k) plus
  "From File…". A template is copied into `graphics/` under a unique name
  and placed at the playhead on the selected track, in one undo step.
- **File ▸ Add Font to Graphics…** and **Add Image to Graphics…**.
- **Help ▸ Graphics Reference**.

The file is at 549, so the three items (~30 lines) fit under 600. If they
do not, the Insert submenu is built in `AppDelegate+GraphicMenu.swift`.

### 5k. Templates and fixtures — six graphics, written once

`graphic/tests/graphics/` holds six modules. They are the engine's test
fixtures, the spike's workload (q3) and, copied into the app's Resources
at build, the Insert ▸ Graphic templates:

1. `lower-third`: slide-in bar and title, spring, a staggered subtitle, an
   outro keyed to `durationInFrames`.
2. `title-card`: `fitText` on a long title, a background gradient, a fade.
3. `counter`: a number counting from `from` to `to` with a thousands
   separator, IBM Plex Mono.
4. `bar-chart`: `values` as a comma-separated string prop, bars growing in
   sequence, labels.
5. `kinetic-type`: a sentence shown word by word, each word scaled in by a
   spring, wrapped with `wrapText`.
6. `callout`: a circle drawing itself on (a stroke-dasharray draw-on) and
   an arrow, over a transparent background, for pointing at a screen
   recording.

### 5l. Tests and the proof

**`graphic/tests/`** are black-box through `lib.rs`, checked against
oracles:
- **Pixels**: a solid `<rect>` fills exactly the pixels it covers, with
  the exact BGRA premultiplied value; the outside is `0,0,0,0`; half-alpha
  white is `(127|128, …, 127|128)`, pinned to one value.
- **Edges**: anti-aliased white text over transparent, composited in the
  test over black and white by the shader's formula (`(one,
  oneMinusSourceAlpha)`), shows no dark fringe. The check is that no pixel
  of the composite over white is darker than the text's own colour times
  coverage.
- **Determinism** (q5, kept as a test): 6 fixtures × 20 frames, 8 threads,
  shuffled, compared byte for byte.
- **Sandbox**: q6's eight cases each end in a named Diagnostic within the
  budget.
- **The standard library**: JavaScript unit tests in
  `graphic/tests/js/*.test.js` run by a Rust harness. They cover
  `interpolate` extrapolation and multi-segment ranges, easing endpoints
  (0 → 0, 1 → 1), `spring` settling to `to` within a tolerance and being
  independent of call order, `wrapText` on a word longer than the width,
  and `random` being stable across calls.
- **measureText parity** (q4, kept): the measured width equals the
  rendered ink box within 1 px.
- **The props overlay**: defaults, stale keys and wrong types → warnings
  (G-4).
- **The reference**: every code block in `docs/graphics-api.md` evaluates.
- **The one non-oracle**: the SHA-256 of frame 0/30/90 of each fixture is
  pinned in `graphic/tests/pins.json`. A mismatch fails with "the
  rasterizer's output changed — if this is a resvg upgrade, re-pin after
  looking at the PNGs in target/pins/". It is a tripwire for upgrades, not
  a correctness claim, and `graphic/CLAUDE.md` names it as the exception.

**`core/tests/graphic.rs`** (the model):
- the ops' three answers;
- the schema checks by dotted path;
- the shape-only check without a schema;
- `split` pinning `length` and continuing `frame`;
- `trim_start` advancing `in`;
- an action naming `graphic` refused;
- the recipe's `frame`, `ctx` and `hash`;
- the FFI null sweep for the nine exports.

**`core/tests/schema_v10.rs`**: v9 reads unchanged, a v10 round trip is
byte for byte, and key order is kept.

**`tools/proof/graphics_proof.py`** drives the built app over MCP. It has
been made to fail on purpose, as each proof must be. Every row is a
placement read back, a byte comparison of two PNGs, or a reply's text:
- **Loop.** `write_graphic` with a syntax error answers a diagnostic with
  the right line. After the fix it answers `ok` with the schema.
- **Contact sheet.** `render_graphic` of frames `[0, 0]` gives two
  byte-identical cells. Frames `[0, 30]` differ.
- **Placement.** `add_graphic_clip` then `get_project` shows the stored
  `graphic`. `render_frame` at `start + 30 frames` crops byte-identically
  to `render_graphic {frame: 30}` placed on the same canvas: the placement
  proof that the timeline and the engine agree.
- **Split.** `split` at frame 40: `render_frame` at frame 41 is the same
  before and after.
- **Props.** `set_graphic {props: {title: "B"}}` changes the frame and undo
  restores it byte for byte. `{props: {nope: 1}}` is refused with the
  core's sentence naming `props.nope`, and the undo stack does not move.
- **Hot reload.** The proof writes the file itself with `mv` from the
  shell, not through MCP. The next `render_frame` differs, and `get_graphic`
  shows the new revision.
- **Leniency.** Removing a prop from the schema keeps the clip drawing, and
  `render_frame`'s reply lists the stale key as a warning.
- **Failure.** A module that throws at frame 10: `render_frame` at 9 is
  clean. At 10 the reply names the error and the frame, and the picture
  holds the error card. `export` refuses before it starts.
- **Sandbox.** `while(true){}` in `render`: `render_frame` answers the
  timeout within 3 s, and the app stays responsive (`get_project` answers).
- **Package.** Save, close, reopen: the module is there and renders the
  same bytes. Save As to a new path: the same. An untitled project with a
  graphic, saved for the first time: the same.
- **Alpha.** A transparent canvas plus `callout`, exported as ProRes 4444
  and decoded with `ffmpeg`, has alpha 0 at a corner and 255 on the stroke.
- **Rate.** On a 29.97 canvas, frame N is at tick `N × 20020`, and the same
  frame number renders identically on a 30 fps canvas.

**The offscreen harness** photographs the Graphic sub-tab with a fixture's
schema in both appearances (G5).

**The playback check** (G3) is a person's, in remaining §4. `lower-third`
and `kinetic-type` play at 1080p30 with Preview Quality Full and no
visible stutter. If q3 predicted a shortfall, G6 runs first.

### 5m. Files, tolls, seams

| File | Lines now | What happens |
|---|---|---|
| `graphic/**` | — | new crate; each `src/` file under 400 |
| `core/Cargo.toml` | — | `graphic = { path = "../graphic" }` (behind a feature if q1 says so); the `core/CLAUDE.md` dependency list gains its reason |
| `core/src/ffi_graphic.rs` | — | new, the nine exports |
| `core/src/model_graphic.rs` · `edit_graphic.rs` · `recipe_graphic.rs` | — | new, each under 400 |
| `core/src/model.rs` | 505 | `Source::Graphic`, `Clip.graphic` — a few lines |
| `core/src/recipe.rs` | 582 | one call line in `layer_source` |
| `core/src/edit.rs` | 843 (exempt table) | two rows, two enum arms, two dispatch arms |
| `core/src/edit_clip.rs` | 751 (ledger) | `Described` gains one field; nothing else |
| `core/src/op_table.rs` | 331 of 400 | two rows, `OP_COUNT` 59 |
| `core/src/edit_split.rs` · `edit_action.rs` · `model_query.rs` · `edit_paste.rs` · `edit_track.rs` · `scope.rs` · `evaluate.rs` | 218 · — · 441 · 575 · 522 · 395 · 591 | an arm or a few lines each (G-9, G-10) |
| `core/src/format.rs` · header | 366 · 370 | v10 paragraph and `#define`, nine prototypes, two opaque types |
| `app/Sources/ReelCore.swift` | 1440 (ledger) | TOLL first (§5e), then ~110 lines of wrappers |
| `app/Sources/ProjectDocument.swift` | 1380 (ledger) | two call lines; the rest in `ProjectDocument+Graphics.swift` |
| `app/Sources/ProjectSnapshot.swift` | 2293 (ledger) | one call line per decode site; types in `ProjectSnapshot+Graphic.swift` |
| `app/Sources/Compositor.swift` | 1391 (ledger) | one `case` line |
| `app/Sources/AgentServer.swift` | 785 (frozen) | eight `handlers` lines |
| `app/Sources/ClipPane.swift` | 403 | the sub-tab and its `makeSections` case |
| `app/Sources/AppDelegate+Menus.swift` | 549 | ~30 lines, or a new file (§5j) |
| new app files | — | `GraphicStore.swift`, `GraphicRegistry.swift`, `LayerRenderersGraphic.swift`, `GraphicPane.swift`, `AgentCatalog+Graphics.swift`, `AgentServer+Graphics.swift`, `ProjectDocument+Graphics.swift`, `ProjectSnapshot+Graphic.swift`, each under 400 |
| `ReelOps.swift` | 1163 (exempt table) | `addGraphicClip`, `setGraphic`, `setGraphicRaw` |
| `project.yml` · `Makefile` | — | Resources gain `GraphicsAPI.md` and `GraphicTemplates/`; `make test` also runs `cd graphic && cargo test --release`; `make lint` covers both crates |
| `docs/graphics-api.md` | — | new |
| spec §1, §5.2, §5.6, §6, §7 (intro, §7.1, §7.3, §7.9, §7.10), §11 | — | as each phase lands |
| `CONTEXT.md` | — | **Graphic**, **Module**, **Props** (distinct from a **Patch**), **Revision** |

**The seam between the lanes** goes into the tree first:
`core/tests/fixtures/graphic_v10.json` holds §5g's clip and recipe shapes.
The engine lane (G1) and the model lane (G2) can then run side by side,
and G3 builds against both.

---

## 6. Settled for the user — say if any is wrong

The user's standing preference is one pick with a reason. These are the
picks, and each is cheap to reverse before its phase starts:

1. **The name is "graphic".** "motion" is taken. The menu says Insert ▸
   Graphic, and the tools say `write_graphic`.
2. **Code edits are not undoable** (G-3). The file is on disk for other
   tools to edit, and undo covers the clip's values.
3. **Fonts are the app's bundled faces plus the package's, never the
   system's** (G-6). A graphic moves between Macs intact, and
   `import_graphic_font` adds one.
4. **JavaScript, not TypeScript** (G-11).
5. **No video or timeline input to a graphic.** It is a layer, and it
   combines with what is under it through blend modes and track order.
   Mattes are §7's.
6. **Performance target: 1080p30 in preview for the six templates**, with
   export allowed to be slower. G0 measures, and G6 exists only if the
   measurement misses.
7. **Experimental on `svg-motion`.** Merging to `main` is the user's call
   after G4 (§9).

---

## 7. Not built, and why

- **Keyframed props** (an action animating `props.x`). A graphic animates
  itself, and G-10 keeps one animation system per property. It is the
  first candidate after G5 if people want to time copy changes from the
  timeline.
- **`paste_attributes` for graphics.** Pasting props onto a clip of a
  different module is undefined. The same module is easy and can come with
  a request.
- **A revision history** (restore the module as it was an hour ago). The
  `cache/graphics/<revision>.js` shape is obvious and cheap, and waits for a
  person to miss it.
- **HEVC with alpha.** ProRes 4444 and APNG already carry alpha.
  `hevcWithAlpha` is a new export row (spec §7.8), not a graphics feature.
- **Mattes and inputs** (a graphic masking the clip below, or reading a
  video frame). These are compositor features, and they are what R5-1's
  closed vocabulary is for.
- **Parallel rendering and prefetch** (G6). This is only built against
  q3's or G3's measurement.
- **System fonts as an opt-in** (G-6). Easy to add as a document setting
  if the bundled and package faces are not enough.
- **Path helpers** (length, point at length). They wait for an example
  that needs them.
- **Audio from a graphic.** Out of scope, as the plan said.
- **`delete_graphic` and `rename_graphic`.** The file system does the
  first. The second needs an op to repoint every clip, and waits for the
  first time someone renames one.

---

## 8. Numbers a person may want to change before the build

| Number | Value | Where |
|---|---|---|
| Heap per context | 64 MB | G-5 |
| Stack | 1 MB | G-5 |
| Render budget (preview / export) | 250 ms / 2 s | G-5 |
| Schema keys, string length, enum options | 64 / 4096 / 32 | §5c |
| Default duration without `meta` | 5 s | §5h |
| Contact sheet frames | ≤ 16 | §5h |
| Watcher coalescing | 100 ms | §5f |
| Frozen epoch | 2000-01-01T00:00:00Z | G-5 |

---

## 9. The build's shape

Each phase is its own `/litecode` pipeline with its own reader review, on
the branch `svg-motion`. G2 alone bumps the format.

- **G0 — the spike** (§3). Nine rows, no product code, instruments in
  `tools/proof/graphics_spike/`, recorded in §10.1. §3a lists every
  section it rewrote.
- **G1 — the engine**:
  - the `ReelCore.swift` toll first, landed and gated alone;
  - then the crate, the standard library, the six fixtures, `graphic/CLAUDE.md`,
    `ffi_graphic.rs`, the header and the wrappers;
  - `docs/graphics-api.md` with its evaluating test;
  - spec §7's amended sentence and §11 G-1, G-2, G-5.
  - Proved by `make test` (both crates), `make lint`, `make typecheck`, and
    a harness probe that compiles a fixture through `ReelCore` and writes a
    PNG.
- **G2 — the model** (beside G1, over the fixture seam):
  - format v10, `model_graphic.rs`, the two ops, `edit_graphic.rs`, G-9's
    split and trim rules, G-10's refusal and `recipe_graphic.rs`;
  - `core/tests/graphic.rs` and `schema_v10.rs`;
  - spec §5.2, §6, §7.3 and §11 G-3, G-4, G-6 to G-13.
  - Proved by `make test` and a core-only proof over the recipe.
- **G3 — the picture**:
  - `GraphicStore`, the watcher, the whitelist, the untitled carry-over,
    `GraphicRegistry`, `LayerRenderersGraphic`, the error card,
    `render_frame`'s diagnostics and the export gate.
  - Proved by the Package, Hot reload, Failure, Sandbox, Alpha and Rate
    rows of §5l (driven with the two op tools, whose handlers land here
    minimally) and the person's playback check.
- **G4 — the agent**:
  - the six app-state tools;
  - the declarations rows;
  - `get_project`'s `graphics`;
  - `API.md` and `API.d.ts` written into the folder.
  - Proved by the whole of `graphics_proof.py`, with the parity log clean.
  - **After G4 the feature is usable by an agent end to end, and it is
    the natural point for the user to decide on merging.**
- **G5 — the person**:
  - the Graphic sub-tab, the menus, the templates in Resources, Open in
    Editor and Duplicate as New Graphic.
  - Proved by the harness photographs and a probe over
    `GraphicSchemaRows` (a row per schema type, and a stale key shown).
- **G6 — performance, only if owed.** An SVG-string cache, prefetch of the
  next N frames on a concurrent queue during playback, and parallel frame
  rendering in export with an ordered writer, each against a before and
  after measurement.

---

## 10. Record

Empty. G0's run is §10.1.
