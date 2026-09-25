# Reelcut — road map 10: graphics, motion graphics drawn by code

**Status: SPIKED 2026-09-24 — G0 ran complete, all nine rows of §3 measured
on this host (§10.1); no product code built. EXPERIMENTAL, on the branch
`svg-motion`.** Nothing here lands on `main` until the user decides to merge
it (§9). The input to this design was `designs/svg-motion-components-plan.md`,
a tech plan the user had drafted. §1 reviews that plan against this codebase,
and every section after §1 is the design that came out of the review.

Every claim about the code is a scout's reading at `ed42a56`, cited with a
`file:line`. The claims about the crates and frameworks that §3 asked about
were MEASURED by G0 on 2026-09-24 (§10.1), and every section that depended
on one was REWRITTEN, not annotated, as in road map 8; §3a lists them. A
crate claim §3 did not ask about is still a reading.

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
| Worker pool, parallel prefetch, parallel export | Not built (G6 is NOT owed: G0's q3 measured the six graphics at 1920×1080 at a worst p95 of 7.62 ms per frame, JavaScript, parse and raster together, against the 12 ms line) | The compositor is one serial queue with one frame in flight (`Compositor.swift:112,162-217`), and export is serial (`ExporterWriter.swift:103-111`). Parallelism is a change to both, and is paid only against a measured shortfall, which 1080p does not have (§10.1 q3). |
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

**All nine ran on 2026-09-24. §10.1 is the record, row by row; §3a lists what
each one changed, and the instruments are `tools/proof/graphics_spike/` with
their own README.** Nothing below this line in §3 is a prediction any more:
read the section a row names, which has been rewritten, and §10.1 for the
numbers behind it.

## 3a. What G0 changed in this document

| Section | Before G0 | Now | Row |
|---|---|---|---|
| Status header, intro | designed, nothing built; crate claims unmeasured | spiked; the crate claims §3 asked about are measured | all |
| §1 table, worker pool | "only if G0/G3 measure a need" | not owed: worst 1080p p95 7.62 ms per frame | q3 |
| §4 G-2, licences | `tiny-skia` Apache-2.0 OR MIT; `rustybuzz` | the resolved graph: `tiny-skia` BSD-3-Clause; usvg 0.48 shapes with `harfrust`, not `rustybuzz`; QuickJS is quickjs-ng | q1, q2 |
| §4 G-6, fonts | "a `font-family` the set does not have is a warning" | the same, and now necessary: a missing family draws NOTHING (no fallback), and a family name starting with a digit (`Source Sans 3`) lays out nothing unless quoted | q4 |
| §5a, the crate's features | `raster-images` OFF, "usvg's own image support" decodes PNG/JPEG; a cargo feature if `make test` slows > 2× | `raster-images` ON (resvg 0.48.1 skips every `<image>` decode without it — a reading, `src/image.rs:26-32`), priced at +974 352 bytes of staticlib, and then (the user, 2026-09-24: size is not a reason) resvg's defaults minus the two file-system features, so `svgz` too; NO cargo feature (`make test` 1.12× warm); `serde_json` with `preserve_order` | q1, q2 |
| §5b, the runtime | the limits and refusals as designed | CONFIRMED by 18 cases, each a structured answer, the process alive; REWRITTEN in detail: where an interrupt's line points, the loader's refusal sentence, a big string that is built but cannot be read, no `line()`/`column()` in rquickjs 0.14 | q6 |
| §5c, the module and `measureText` | "ES2020+ as QuickJS evaluates it"; `measureText` returns `{width, ascent, descent, lineHeight}` | quickjs-ng 0.16.2 takes §5c's module verbatim; `measureText` also returns the INK box, which is what agrees with the pixels; whitespace and family quoting stated | q2, q4 |
| §5d, JavaScript every frame | "q3 measures its cost" | measured: JavaScript p95 ≤ 1.67 ms at 1080p; 85–252 of 299 consecutive frames repeat their SVG, so the SVG-keyed texture cache pays | q3 |
| §5e, the FFI | the shape, unmeasured | CONFIRMED: an export in `ffi_graphic.rs` is in `libreelcut_core.a` and Swift calls it byte-identically; the engine rides in the app (+7 194 848 bytes) whether or not anything calls it | q9 |
| §5f, the watcher | `.write`, `.rename`, `.delete` on the folder; "an editor's atomic save shows as a rename" | a folder source raises `.write` only, never `.rename`; an IN-PLACE save raises nothing on the folder, so each module file gets its own source; only CREATING a folder inside the open package trips NSDocument | q7 |
| §5l, parity and sandbox tests | "within 1 px"; "q6's eight cases" | the ink box against whole-pixel columns within 2 px; eighteen cases | q4, q6 |
| §5m, `core/Cargo.toml` | "behind a feature if q1 says so" | a plain path dependency | q1 |
| §6 item 6 | the target, unmeasured | met with room at 1080p30 | q3 |
| §8 | — | a row for the largest string a render can hand back | q6 |
| §9 G6 | "only if owed" | not owed at 1080p; 4K full-frame fills are the case a person watches | q3 |
| §10 | "Empty." | §10.1 the record, §10.2 what did not run | all |

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

Licences, of the graph G0 resolved (`tools/proof/graphics_spike/Cargo.lock`,
q1):
- `rquickjs`, `rquickjs-core`, `rquickjs-sys` 0.14.0 MIT; the QuickJS it
  vendors is quickjs-ng 0.16.2, MIT (q2);
- `resvg` and `usvg` 0.48.1 Apache-2.0 OR MIT;
- `tiny-skia` 0.12.0 BSD-3-Clause (not Apache-2.0 OR MIT, as this section
  first said);
- `fontdb` 0.24.0 and `harfrust` 0.12.0 MIT — usvg 0.48 shapes with
  `harfrust`, not `rustybuzz`; `skrifa`/`read-fonts` MIT OR Apache-2.0.

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
does have. G0 measured why the warning cannot be skipped (q4): with no
system fonts there is NO fallback, so a `<text>` whose family the set lacks
draws nothing at all and `measureText` has nothing to measure; a list
(`"Nope, Montserrat"`) falls through to the family it names. A family name
that starts with a digit is not a CSS identifier: `font-family="Source Sans
3"` lays out nothing, and `font-family="'Source Sans 3'"` draws. So the
standard library quotes every family it writes, the reference says to
quote, and the warning names an unquoted digit-led family as the likely
cause. The variable faces load as one face each (`SourceSans3-Roman`
weight 200, `DarkerGrotesque-Light` weight 300) and draw the instance
`font-weight` asks for: Source Sans 3's advance for the same word at 64 px
is 438.9, 462.3, 491.5 and 502.7 px at weights 200, 400, 700 and 900.
`import_graphic_font` (§5h) copies a font into the package. This is the
open question from the plan, answered.

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

### G-14 — `graphics/` is created on first write, never at open

Recorded by G3a (2026-09-25), before its code; amends G-3's last sentence.
- A package that never gets a graphic is not touched. Opening, saving and
  autosaving a package without `graphics/` leaves it without one.
- `GraphicStore.ensureFolder()` is the ONE creator of `graphics/` inside a
  package. G4's `write_graphic`, G5's templates and the font and asset
  imports all go through it.
- While the folder is absent the store watches the package directory
  itself, so a `graphics/` made from outside (an agent's own `mkdir`) is
  picked up. The first observed appearance, whether the app made it or
  found it, calls `packageContentsDidChangeOnDisk()` once (§9a item 2).
- An untitled document's folder is the app's own scratch,
  `<NSTemporaryDirectory()>/Reelcut/<UUID>-graphics`, created eagerly. It
  sits BESIDE the temporary cache root, not under it as G-3 said, because
  `cacheWrapper()` would carry a child of the cache root into `cache/`.
  The first save carries it only when it holds at least one entry.
- An untitled document restored from autosave has its saved `graphics/`
  copied into a fresh root.

---

## 5. The design

### 5a. The crate — `graphic/`

```
graphic/
  Cargo.toml         rquickjs (loader), resvg (default-features = false, features = ["text", "raster-images", "svgz"]),
                     serde_json (preserve_order), sha2
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
- **`resvg` takes its default features minus the two that reach the
  file system**: `text`, `raster-images` and `svgz` are ON, and
  `system-fonts` and `memmap-fonts` are OFF. Those two are off for G-6
  (fonts are the bundled faces and the package's) and for G-2 (the crate
  reads no files, and the app hands it bytes), and NOT for size. **The
  user's ruling (2026-09-24): binary size and clean-build time are not
  reasons to leave a feature out.** So no feature is excluded to save
  bytes or seconds.
  - **`raster-images` is required, not optional.** resvg 0.48.1 decodes no
    raster `<image>` without it: `src/image.rs:26-32` logs "Images decoding
    was disabled by a build feature" and draws nothing. That is a reading;
    G0 did not render an image, and G1's tests must. q1c measured it at
    +974 352 bytes of staticlib. It brings the JPEG, GIF and WebP decoders
    (PNG decoding is tiny-skia's), so §5c's `asset` type offers all four,
    with GIF drawing its first frame.
  - **`svgz`** lets an asset be a gzipped SVG. It is on because it is a
    default and costs nothing that matters. An `.svg` asset needs no
    feature at all, because usvg parses a nested SVG image with itself
    (a reading, confirmed by G1's tests), so `asset` also offers `.svg`
    and `.svgz`.
- **`rquickjs` takes `loader`**, which the sandbox needs to refuse imports
  in its own sentence. Its other features are Rust-side conveniences
  (`macro`, `classes`, `properties`), debug dumps, or async (`futures`,
  which G-5 rules out). None of them changes what a script can do.
- **What quickjs-ng itself lacks** has nothing to do with any feature:
  there is no `Intl`, so `toLocaleString` does not format by locale, and
  no `structuredClone` (q2). The standard library gains
  `formatNumber(n, {decimals, separator})` so a counter does not have to
  hand-roll thousands separators.
- `serde_json` takes `preserve_order`. Without it a module's `schema` crosses
  as a `BTreeMap` and comes out ALPHABETICAL (q2 printed §5c's schema as
  `accent, align, boxed, logo, size, subtitle, title`), and the inspector
  builds its rows in schema order (§5j).
- NO cargo feature. q1 measured the core's own `make test` at 13.62 s before
  the dependency and 15.20 s after, on the same warm edit (1.12×, far under
  the 2× that would have put the engine behind `features = ["graphic"]`),
  and the cold `cargo build --release` at 25.0 s before and 43.2 s after:
  QuickJS's C is compiled once per clean build. The engine's own tests run
  in `graphic/`.

### 5b. The runtime and its limits

G0's q6 ran every refusal below in its own process, and each ended in a
structured answer with the process alive and the SAME engine then loading
and drawing `lower-third` byte-identically to a fresh one (18 of 18; §10.1).

- One `rquickjs::Runtime` and one `Context` per (thread, module).
  - `set_memory_limit(64 MB)` and `set_max_stack_size(1 MB)`.
  - `set_interrupt_handler` compares a monotonic deadline set before each
    call (250 ms preview, 2 s export and `render_frame`, G-5). `while (true)
    {}` answered at 250.07 ms with `InternalError: interrupted`.
- The fields of the Rust type that holds them drop in the order the saved
  `render` function, then the context, then the runtime: dropping the
  runtime first aborts the process in QuickJS's `JS_FreeRuntime` assertion
  (`list_empty(&rt->gc_obj_list)`), which G0 hit before it fixed the order.
- Nothing from `rquickjs`'s `std`/`os` loaders. The module loader resolves
  NO specifier. Both a static `import x from "x"` and a top-level `await
  import("x")` fail the module's LOAD with `ReferenceError: Error resolving
  module 'x' from '<name>': imports are not available in a graphic; the
  standard library is global` — the prefix is QuickJS's, the sentence
  ours — with no line or column. An `import()` inside `render` returns a
  promise nobody awaits, so it is only refused if the module awaits it.
- Replaced globals are `Math.random` (throws `Math.random is not available;
  use random(seed)`) and `Date` (`Date.now()` is 946684800000 and `new
  Date()` is 2000-01-01T00:00:00Z). `Date.prototype.constructor` is
  redefined to the frozen `Date` too, or `new Date().constructor.now()`
  reads the wall clock (it answers 946684800000). The deletions are `eval`
  (a call is then `ReferenceError: eval is not defined`) and `Function`:
  the global, `Function.prototype.constructor`, and the `constructor` of
  the AsyncFunction, GeneratorFunction and AsyncGeneratorFunction
  prototypes, each of which otherwise compiles code from a string
  (`(async () => {}).constructor("…")`); every one throws the sandbox's own
  sentence. G0's review found the `Date` and three function-kind holes;
  the cases were then shown to leak against the sandbox without those four
  lines. quickjs-ng 0.16.2 defines no `WebAssembly` (a
  reading of its `quickjs.c`; the sandbox deletes it anyway).
- Memory: `new Array(1e9)` is NOT an allocation (it answers `length`
  1000000000); a loop pushing 1 MiB `Uint8Array`s and `"x".repeat(1e8)`
  both end in `InternalError: out of memory` with a line and column.
  `"<svg" + "x".repeat(5e7)` is BUILT and returned, but reading it out of
  QuickJS allocates inside the same 64 MB heap and fails, and rquickjs
  names that failure "QuickJS library created a unknown error"; the engine
  must answer it in its own words ("render's string could not be read —
  is it tens of megabytes?"), and §8 records the ceiling. Deep recursion
  is `RangeError: Maximum call stack size exceeded` with a line and column.
- A syntax error at compile, and an exception, timeout or out-of-memory at
  render, each become a Diagnostic `{level: "error", message, line, column,
  frame}`. rquickjs 0.14's `Exception` has NO `line()`/`column()`: the
  position is parsed from `stack` (quickjs-ng writes `at render
  (<name>:L:C)`), preferring a frame in the module's own name. An
  interrupt's position is the FUNCTION's line, not the loop's (the case's
  `render` opens on line 3 and loops on line 4; the answer said 3:1). The
  module is evaluated unwrapped, so there is no offset to map back.
- `render` must return a string that starts with `<svg`. Anything else is an
  error naming what came back ("render returned undefined at frame 12 —
  did you forget `return`?"; q6 printed it word for word, at frame 0). An agent's
  most common mistake gets its own sentence.

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

**What runs it.** `rquickjs` 0.14.0 vendors quickjs-ng 0.16.2 (its
`quickjs.h` defines `QJS_VERSION_MAJOR 0`, `MINOR 16`, `PATCH 2`; q2), not
Bellard's QuickJS. It evaluates the module above VERBATIM — `export const`,
the template literal, the object literals — and `??`, `?.`, `**`,
`Array.prototype.at`, `Object.hasOwn`, `replaceAll` and `findLast` all work.
`structuredClone` does not exist, and there is no `navigator` (so no
`userAgent`); neither is needed.

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
- `measureText(text, font)` returns `{width, ascent, descent, lineHeight,
  inkX, inkWidth}`. `font` is `{family, size, weight, style,
  letterSpacing}`, and it is a host function (§5b) that parses a one-`<text>`
  SVG with the engine's own options — step 1 of the plan, and q4 found no
  step 2 (direct shaping) is needed. `width` is the text node's
  `bounding_box()`, the ADVANCE box, which is what layout wants (the next
  word starts there) and is NOT the ink: over 2 400 measurements it differed
  from the drawn ink by p50 3.46 px and up to 78 px (a monospace face's
  side bearings at 160 px). `inkX`/`inkWidth` are the flattened glyphs'
  box (`flattened().abs_bounding_box()`), and those agree with the pixels
  of the same text drawn inside a composed SVG to within 1.70 px counted in
  whole pixel columns (p50 0.77, p95 1.46). `ascent` and `descent` are read
  off the advance box around the baseline. A result is memoised per
  `(family, size, weight, style, text)`, which changes no output.
- It measures as the default `xml:space` draws: runs of spaces collapse and
  leading and trailing spaces go, so `"a  b"`, `"a b "` and `" a b"` all
  measure 103.30 px like `"a b"` (Montserrat 800, 64 px), and 121.92 px
  under `xml:space="preserve"`. A helper that relies on a trailing space
  measures without one.
- Every family the helpers write is QUOTED (`font-family="'Source Sans
  3'"`, G-6), and a family the set lacks throws from `measureText` naming the
  families it has.
- The text helpers are built on `measureText`:
  - `wrapText(text, maxWidth, font)` returns lines, breaking an over-long
    word by characters;
  - `fitText(text, maxWidth, font, {min, max})` returns a size;
  - `textLines(lines, {x, y, lineHeight, anchor, font})` returns
    `<text>` + `<tspan>` markup.
- `escapeXml(s)`.
- `formatNumber(n, {decimals, separator})`, because quickjs-ng has no `Intl` (§5a).
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
- **The JavaScript still runs every frame**, and q3 measured it cheap: at
  1920×1080 its p95 per frame is 0.10 ms (`title-card`) to 1.67 ms
  (`kinetic-type`, which wraps and measures every word), against a parse of
  0.32–0.68 ms and a raster of 1.85–7.29 ms. A string cache keyed by the
  recipe hash would save the smallest of the three and is not built. What
  the SVG-keyed texture cache saves is the RASTER: of 299 consecutive frame
  pairs, 85 (`kinetic-type`) to 252 (`title-card`) returned the same SVG.
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
char *rc_graphic_library_families(const RcGraphicLibrary *);   // G4b, the tenth: the engine's family names, JSON; freezes
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

**The shape, measured (q9).** A `#[no_mangle]` export in a throwaway
`core/src/ffi_graphic.rs` delegating to the spike crate is in
`libreelcut_core.a` (`nm -g` finds it once, and `JS_NewRuntime` three
times), a Swift probe linked with `-lreelcut_core` alone calls it, and its
render of `lower-third` frame 30 at 1920×1080 is byte-identical to the
spike's own CLI given the same one font (SHA-256 `86f017e8…`). One staticlib
is enough; the second is not needed. What the link costs is q1's app: the
Release binary grows from 12 661 264 to 19 856 112 bytes (+7 194 848; the
bundle 15 368 → 22 392 KiB) with NOTHING calling the export — the app's
dead-stripping dropped `rc_graphic_spike_render` (`nm` ×0) and kept QuickJS
(`JS_NewRuntime` ×2). So G1's app is about 7 MB bigger from its first
build, before any graphic draws. The two probes differ by only 25 072 bytes
because the CONTROL probe, which calls only `rc_op_names`, carries QuickJS
too; that difference is not the engine's cost.

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
    assets/            # optional; .png/.jpg/.gif/.webp/.svg/.svgz (§5a, §5c `asset`)
```

**The store.** `GraphicStore` owns one document's graphics:
- **Where the folder is**: the package, or the untitled document's
  temporary root. It re-points when the first save moves the folder, and
  posts `.graphicsLocationDidChange`, so `get_graphic`'s `path` is always
  current.
- **The scan**: every `*.js` with a legal name → `(name, bytes, revision)`,
  plus a font and asset scan → `library.version`.
- **The watch**: a `DispatchSource.makeFileSystemObjectSource` on
  `graphics/` and on each subfolder, AND one on each `*.js` file. q7(c)
  measured what a folder source raises: a file moved in from outside, a
  write to `x.js.tmp` renamed over `x.js` (an editor's atomic save) and a
  removal each raise `.write` on the folder — never `.rename` — and an
  IN-PLACE save (the file truncated and rewritten, `O_TRUNC`) raises
  NOTHING on the folder, because no directory entry changed. The per-file
  source (`.write`, `.extend`, `.delete`, `.rename`) catches that editor,
  and is re-armed on every folder event, since an atomic save replaces the
  inode it was watching. The number of folder events per action is not
  stable (the rename-over raised two `.write`s 1 ms apart in one run and
  one in another), so events are coalesced over 100 ms, then the folder
  is rescanned and only changed revisions are recompiled.
- **What a change does**: it posts `.graphicsDidChange(names)`. Playback
  refreshes the paused frame, the inspector re-reads the schema, and
  `GraphicRegistry` swaps the preview's modules.
- **Writing**: the app's own writes (`write_graphic`, templates, `API.md`)
  go to `<name>.js.partial` and are then moved into place, as
  `ReverseRenderer` does (`:437-461`). After the folder is CREATED, the
  store calls `packageContentsDidChangeOnDisk()` (`ProjectDocument.swift:793-798`),
  and only then. q7 measured both halves with the unchanged app and
  `media/` as the stand-in for `graphics/` (the same lazy `directoryWrapper`,
  inert at open): creating a folder inside an OPEN package moves the
  package's own date, and the next save is refused with "The document
  “P2.reelcut” could not be saved. The file has been changed by another
  application."; a file moved into a folder that already exists does not
  move it, and the save succeeds. A file written by another process
  survives a save both when it landed while the app was closed and while
  it was open, and survives an autosave in place (one fired 16.0 s after an
  edit, with all three files still there). The CONTROL — the same file in
  `graphics/`, which today's whitelist does not name — was gone after the
  save, folder and all, which is the whitelist line this design adds.

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
| `import_graphic_asset` | `path`, `name?` | Copies a PNG, JPEG, GIF, WebP, SVG or SVGZ file into `graphics/assets/` | File ▸ Add Image to Graphics… |
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
- **Sandbox**: q6's eighteen cases (`tools/proof/graphics_spike/src/rows_stress.rs`'s
  `CASES`) each end in the answer G0 recorded (§10.1 q6) within the budget,
  and the same engine then draws a control frame byte-identically.
- **The standard library**: JavaScript unit tests in
  `graphic/tests/js/*.test.js` run by a Rust harness. They cover
  `interpolate` extrapolation and multi-segment ranges, easing endpoints
  (0 → 0, 1 → 1), `spring` settling to `to` within a tolerance and being
  independent of call order, `wrapText` on a word longer than the width,
  and `random` being stable across calls.
- **measureText parity** (q4, kept): the measured INK box (`inkWidth`)
  equals the ink drawn inside a composed SVG within 2 px counted in whole
  pixel columns — a fractional box rounds out on both sides, so G0's worst
  was 1.70 px and "within 1 px" held for only 1 680 of 2 400. The advance
  `width` is not compared with ink; it is what layout wants.
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
| `core/Cargo.toml` | — | `graphic = { path = "../graphic" }`, a plain dependency (q1: `make test` 1.12× warm, no feature); the `core/CLAUDE.md` dependency list gains its reason |
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
   export allowed to be slower. G0 measured it met with room: the six at
   1920×1080 cost a p95 of 2.38 to 7.62 ms per frame (JavaScript, parse and
   raster; worst max 15.81 ms), on the one serial queue, against 33 ms a
   frame. G6 is not owed.
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
| Largest string a `render` can hand back | well under 50 MB: a 50 MB string is built but cannot be read out of a 64 MB heap (q6) | §5b |
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
- **G6 — performance, NOT owed by G0.** q3's worst 1080p p95 was 7.62 ms per
  frame against the 12 ms line, so the six templates need no cache,
  prefetch or parallel export at 1080p30. At 3840×2160 the full-frame
  gradient of `title-card` costs a p95 of 26.19 ms (max 57.74 ms) and
  `kinetic-type` 13.33 ms, which is the case the person's playback check
  (G3, remaining §4) watches on a 4K canvas. If that check stutters, G6 is:
  prefetch of the next N frames on a concurrent queue during playback, and
  parallel frame rendering in export with an ordered writer, each against
  a before and after measurement. An SVG-string cache is not among them:
  the JavaScript is the smallest of the three costs (§5d).

### 9a. How the phases run, and what each inherits from G0

**The user's instruction (2026-09-24):** "Each phase should be run with
/litecode, with a commit after each."
- The phases run one pipeline at a time, in order: G1, G2, G3, G4, G5.
  §9's "G2 beside G1" is a fact about dependencies, not a schedule.
- Each pipeline's baseline is the HEAD commit it starts from. Its
  `request.md` names that commit and this section's list for the phase.
- A phase is committed only after its last review passes. The commit
  message says what was verified and what is owed, and so does the
  phase's §10 record.
- After G4 the feature works end to end for an agent. Merging
  `svg-motion` into `main` is the user's decision at that point, so stop
  after G4 and report.
- The commits so far on `svg-motion`: `c874069` (the design), `0d3c376`
  (G0), `9899fca` (§5a's features, after the user's ruling on size).
- **Do not re-run the spike.** Its output under
  `tools/proof/work/graphics_spike/` is what §10.1 quotes, and a re-run
  overwrites it (§10.3).

**What G1 (the engine) must carry from G0.** Every item is a test or a
line of code, and none is optional:
1. `serde_json` with `preserve_order`, so the schema keeps the module's
   order (q2).
2. resvg with `text`, `raster-images` and `svgz` (§5a). A test renders an
   `<image>` of each of PNG, JPEG, GIF, WebP and a nested `.svg`, because
   all five are readings so far (§10.2).
3. The sandbox, with all EIGHTEEN q6 cases as tests. That includes the
   four `.constructor` escapes the G0 review found: `new
   Date().constructor.now()`, and the Async, Generator and AsyncGenerator
   function constructors. Add a case for `performance` too, and delete it
   if quickjs-ng defines it (§10.3 item 1).
4. Line and column come from the exception's `stack`, because rquickjs
   0.14's `Exception` has no `line()`/`column()`. An interrupt's position
   points at the enclosing function, not at the loop, and the diagnostic
   says so (§5b).
5. `measureText` returns the advance AND the ink box, and the parity test
   compares the ink box within 2 px (q4, §5c, §5l).
6. **A missing font family draws NOTHING in resvg, with no fallback**, and
   an unquoted family name starting with a digit (`Source Sans 3`) lays out
   nothing (q4). So the engine must itself detect a `font-family` the font
   set cannot resolve and emit the G-6 warning naming the families it
   does have. usvg will not report it. Every standard library helper
   quotes the family name (§10.3 item 2 — the spike's `textLines` does
   not).
7. `formatNumber` in the standard library (§5a, §5c).
8. The error for a string too large to read out is the engine's own
   sentence, not rquickjs's message, which names nothing (§5b, §8).
9. The `ReelCore.swift` toll first, landed and gated alone (§5e).

**What G2 (the model) inherits:** nothing from G0. It stands on §4 and §5g
as designed.

**What G3 (the picture) must carry from G0:**
1. **One `DispatchSource` per module file, plus one on the folder.** A
   folder source raises `.write` only, never `.rename`, and an editor that
   saves IN PLACE raises nothing on the folder (q7). The folder's source
   catches files being added and removed; each file's own source catches
   edits.
2. Call `packageContentsDidChangeOnDisk()` after CREATING `graphics/`
   (or a subfolder) in an open package, and not after every event. Only
   creating a folder trips NSDocument's "changed by another application"
   (q7).
3. The "Package" proof rows run against `graphics/` itself. G0 measured
   through `media/` as a stand-in, and the direct measurement is G3's
   (§10.2).
4. The G-6 missing-font warning from item 6 above shows on the clip and
   in `render_frame`'s reply.
5. The person's playback check includes a 4K canvas with `title-card`
   (q3: 26 ms p95 there). If it stutters, G6 is owed.

---

## 10. Record

### 10.1. G0 — the spike, run on 2026-09-24

Nine rows, all `run`, exit 0, and the tree's `core/` and `app/` back at
`c874069` (`git diff c874069 --stat -- core app` and `git status --short --
core app` both empty, in `answers.json`'s `git_check`). The instruments are
`tools/proof/graphics_spike/` and its README says how to run them again;
every number below was printed by a run and is in the CURRENT
`tools/proof/work/graphics_spike/answers.json`, which three runs wrote: the
full run (all nine rows, exit 0), then `--only q5 --mutant` (which writes
`mutants.q5` and leaves `rows.q5` alone, exit 0), then `--only q7` (which
rewrote `rows.q7`, exit 0; the file's `carried_forward` names the other
eight).

**The host.** macOS 26.5.1 (build 25F80) on an Apple M2 Max (Mac14,6, 12
cores); Xcode 26.2 (17C52); Apple Swift 6.2.3; rustc and cargo 1.92.0;
Python 3.14.5. **The crates, as resolved** in the spike's `Cargo.lock`:
`rquickjs`, `rquickjs-core`, `rquickjs-sys` 0.14.0; `resvg` and `usvg`
0.48.1; `tiny-skia` 0.12.0; `fontdb` 0.24.0; `harfrust` 0.12.0; `skrifa`
0.44.0; `roxmltree` 0.21.1; `svgtypes` 0.16.1; `serde_json` 1.0.151; `sha2`
0.10.9; `cc` 1.4.7. The spike depends on `resvg` with `default-features =
false, features = ["text"]` and reaches `usvg`, `tiny-skia` and `fontdb`
through it, so none is duplicated. Fonts are `app/Resources/Fonts/*.ttf`,
read by the caller and handed over as bytes; `load_system_fonts` is never
called.

**The workload.** The six graphics of §5k, written from scratch in §5c's
shape (`tools/proof/graphics_spike/graphics/`), over a standard library of
the functions they use (`src/stdlib.js`). Each was rendered at frames 0, 30
and 150 to `work/graphics_spike/frames/` and looked at once. One change came
of looking: `lower-third`'s subtitle was first set in Source Sans 3, which
drew nothing (q4's unquoted-family finding), and is set in Montserrat,
which also keeps q9's one-font comparison a comparison of drawn text.

---

#### q1 — does the engine build into the core, and at what cost?

**Measured.** The same sequence on each side: `rm -rf core/target`, a cold
`cargo build --release`, `make test`, a comment line prepended to
`core/src/outcome.rs` (remaining §6's edit) with `cargo build --release`
and `make test` again, the comment removed, then `make app`. PATCHED is
`graphics_spike = { path = "../tools/proof/graphics_spike" }` in
`core/Cargo.toml`, `pub mod ffi_graphic;` and the one throwaway export.

| | BASELINE (`c874069`) | PATCHED | |
|---|---|---|---|
| cold `cargo build --release` | 25.0 s | 43.2 s | +18.2 s (QuickJS's C) |
| `make test`, first | 47.0 s, 827 passed | 48.0 s, 827 passed | |
| warm `cargo build --release` after the edit | 1.36 s | 2.24 s | |
| `make test` after the edit | 13.62 s, 827 passed | 15.20 s, 827 passed | **1.12×** |
| `libreelcut_core.a` | 22 680 048 bytes, 591 members | 34 438 200 bytes, 917 members | +11 758 152 |
| `make app` (incremental) | 5.6 s | 19.1 s | |
| `Reelcut.app` (`du -sk`) | 15 368 KiB | 22 392 KiB | +7 024 KiB |
| `Contents/MacOS/Reelcut` | 12 661 264 bytes | 19 856 112 bytes | +7 194 848 |

q1c, `raster-images` switched ON in the spike's `Cargo.toml` while patched:
one core build 28.3 s, the staticlib 35 412 552 bytes and 960 members
(+974 352 over PATCHED); switched back, it rebuilt in 3.0 s to 34 438 200
bytes exactly.

**Verdict.** §5a **CHANGED**: the engine builds as a path dependency into
the `staticlib`+`rlib`, and the core's own `make test` slows 1.12×, so the
cargo feature §5a held in reserve is dropped (§5m's `core/Cargo.toml` row
with it). The cold build pays 18 s once per clean build. `raster-images` is
ON, priced. The app is ~7 MB bigger from the first build (q9 says why).

---

#### q2 — which QuickJS, and does it take §5c's module?

**Measured.** `rquickjs-sys` 0.14.0's vendored `quickjs.h` defines
`QJS_VERSION_MAJOR 0`, `QJS_VERSION_MINOR 16`, `QJS_VERSION_PATCH 2`,
suffix empty: **quickjs-ng 0.16.2**. `navigator` is undefined (userAgent
`null`). The feature probes: `??`, `?.`, `**`, template literals,
`Array.prototype.at`, `Object.hasOwn`, `String.prototype.replaceAll` and
`Array.prototype.findLast` all **true**; `structuredClone` **false**. §5c's
module, evaluated VERBATIM as an ES module: `ok`, its `meta` and `schema`
read back, and `render` at frame 30 returned a string starting `<svg
xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0
1920 1080">`. The schema came back with its keys ALPHABETICAL (`accent,
align, boxed, logo, size, subtitle, title`), because the spike carries it
through `serde_json` without `preserve_order`.

**Verdict.** §5c **CONFIRMED** (the module format stands) and extended with
what runs it; §5a **CHANGED** (`serde_json` takes `preserve_order`, so the
inspector's rows keep the module's order); §4 G-2's licence list names
quickjs-ng.

---

#### q3 — render cost per frame, in three parts

**Measured.** Six graphics × 300 frames × two sizes, one thread, release
build, `durationInFrames` 300, each frame's JavaScript call, usvg parse and
resvg raster (the BGRA swizzle included) timed apart. Per-frame rows are
`work/graphics_spike/q3.csv`; milliseconds:

| Graphic | Size | JS p95 | Parse p95 | Raster p95 | Total p50 | Total p95 | Total max | First frame | Same SVG as the frame before |
|---|---|---|---|---|---|---|---|---|---|
| `bar-chart` | 1920×1080 | 0.94 | 0.68 | 4.07 | 3.28 | 5.90 | 15.81 | 4.67 | 96 |
| `callout` | 1920×1080 | 0.18 | 0.33 | 1.95 | 2.03 | 2.38 | 3.55 | 2.11 | 197 |
| `counter` | 1920×1080 | 0.22 | 0.32 | 1.90 | 1.81 | 2.38 | 9.75 | 1.43 | 89 |
| `kinetic-type` | 1920×1080 | 1.67 | 0.57 | 3.32 | 3.97 | 5.10 | 12.00 | 2.38 | 85 |
| `lower-third` | 1920×1080 | 0.34 | 0.32 | 1.85 | 1.80 | 2.45 | 5.26 | 1.57 | 139 |
| `title-card` | 1920×1080 | 0.10 | 0.35 | 7.29 | 6.07 | **7.62** | 10.57 | 7.60 | 252 |
| `bar-chart` | 3840×2160 | 0.85 | 0.64 | 9.94 | 8.60 | 11.20 | 16.01 | 9.48 | 96 |
| `callout` | 3840×2160 | 0.25 | 0.51 | 8.92 | 5.25 | 9.59 | 51.00 | 4.91 | 197 |
| `counter` | 3840×2160 | 0.25 | 0.46 | 9.85 | 5.16 | 10.48 | 48.06 | 10.97 | 89 |
| `kinetic-type` | 3840×2160 | 1.78 | 1.01 | 11.15 | 9.10 | 13.33 | 32.12 | 5.70 | 85 |
| `lower-third` | 3840×2160 | 0.33 | 0.32 | 6.30 | 5.16 | 6.86 | 11.01 | 3.99 | 139 |
| `title-card` | 3840×2160 | 0.11 | 0.38 | 25.85 | 21.05 | **26.19** | 57.74 | 27.90 | 252 |

Module load (compile and evaluate once) took 0.55–1.40 ms. The whole row
took 252.6 s of wall clock, most of it SHA-256 over every raster for the
CSV, which is not a render cost.

**Verdict.** G6 **CONFIRMED not owed** at 1080p: the worst p95 is 7.62 ms,
under §3's 12 ms line, and the raster — not the JavaScript — is most of
every frame. §1's table, §5d, §6 item 6 and §9 G6 are REWRITTEN with the
numbers; 4K full-frame fills are named as what the person's check watches.

---

#### q4 — `measureText` parity

**Measured.** 200 strings from a seeded generator (words, digits,
punctuation, `é`/`ü`, 1–40 characters) × Montserrat 800, Anton, IBM Plex
Mono 400 and Bebas Neue × 24, 64 and 160 px = 2 400 measurements. Each was
measured from a lone `<text>` and compared with the ink drawn by the same
text inside a COMPOSED SVG (a bar above, a disc below, the text in a
translated group), ink read as the columns with alpha > 0 in the text's
band.

| | p50 | p95 | max | within 1 px |
|---|---|---|---|---|
| `bounding_box()` width (the advance box) vs ink | 3.46 px | 20.0 px | 78.0 px | 495 / 2 400 |
| flattened glyphs' box vs ink | 0.77 px | 1.46 px | 1.70 px | 1 680 / 2 400 |

Per face, the flattened box's worst is 1.66 (Montserrat), 1.69 (Anton),
1.63 (IBM Plex Mono) and 1.70 px (Bebas Neue); the advance box's worst is
78.0 px, in IBM Plex Mono, whose narrow glyphs sit in wide cells.
Whitespace, Montserrat 800 at 64 px: `"a b"`, `"a  b"`, `"a b "` and `" a
b"` all measure 103.30 px by default and 103.30, 121.92, 121.92 and 121.92
px under `xml:space="preserve"`. Variable fonts: `SourceSans3.ttf` loads as
ONE face, `SourceSans3-Roman` at weight 200, and `DarkerGrotesque.ttf` as
one, `DarkerGrotesque-Light` at 300; the instance drawn follows
`font-weight` (Source Sans 3's advance at 64 px: 438.91, 462.34, 491.46 and
502.66 px at 200, 400, 700, 900; Darker Grotesque's 379.46, 389.57, 419.71,
439.94). Family attributes: `Source Sans 3` unquoted lays out **nothing**,
`'Source Sans 3'` lays out; `Darker Grotesque` lays out; `Nope` lays out
nothing; `Nope, Montserrat` lays out.

**Verdict.** §5c **CHANGED**: step 1 (a one-node parse) is enough and no
direct shaping is needed, but only the flattened box agrees with the
pixels, so `measureText` answers both the advance (for layout) and the ink
box, and §5l's parity test compares the ink box within 2 px of whole-pixel
columns. §4 G-6 **CHANGED**: a missing family draws nothing, and a
digit-led family must be quoted.

---

#### q5 — determinism

**Measured.** The six graphics × frames 0, 7, 30, 90, 150 and 299 at
1920×1080: a reference render each (one engine per graphic, in order), then
8 threads sharing one `Arc` font database, each with its own engines,
rendering all 36 three times in its own shuffled order — 864 renders.
**0 raster mismatches and 0 SVG mismatches** against the reference (6.9 s).
After each graphic's engine had rendered frames 0–299, its six frames were
rendered again: **equal, 6 of 6**. Frames of the one engine in QuickJS are
therefore a function of their inputs, across threads, orders and history.

The on-purpose failure (`--mutant`): a copy of `counter.js` with a
module-level call counter drawn into its frame, the graphic G-5 says the
standard library cannot stop. The same 864 renders: **137 raster and 137
SVG mismatches**, and `counter`'s after-300 check **unequal**; the other
five stayed equal.

**Verdict.** §4 G-5 **CONFIRMED**, and the instrument that must catch the
one thing G-5 cannot prevent caught it.

---

#### q6 — the sandbox

**Measured.** Eighteen cases, each its own process under a 30 s bound, with
the §5b limits (64 MB heap, 1 MB stack, 250 ms). Every process exited 0
within 0.55 s, and in every one the SAME engine then loaded `lower-third`
and drew frame 0 byte-identically to a fresh engine (**control 18 of 18**).
The table is the `--only q6` re-run after the review's sandbox fix (the
four `constructor` rows are new); the other rows answer word for word as
in the full run, with these timings.

| Case | Answer | Line:col | ms |
|---|---|---|---|
| `while (true) {}` | `over the 250 ms budget at frame 0 (InternalError: interrupted)` | 3:1 | 250.14 |
| `new Array(1e9)` | ok — `length` 1000000000, no allocation | — | 0.05 |
| deep recursion | `RangeError: Maximum call stack size exceeded` | 4:26 | 0.17 |
| `"<svg" + "x".repeat(5e7)` returned | `render's string could not be read at frame 0: QuickJS library created a unknown error` | — | 116.46 |
| the same with `1e8` | `InternalError: out of memory` | 4:23 | 0.05 |
| `Math.random()` | `Error: Math.random is not available; use random(seed)` | 4:31 | 0.04 |
| `Date.now()`, `new Date()` | ok — `946684800000`, `2000-01-01T00:00:00…` | — | 0.05 |
| `eval("1")` | `ReferenceError: eval is not defined` | 4:26 | 0.04 |
| `new Function("return 1")()` | `Error: Function is not available in a graphic; the module is the one source of code` | 4:30 | 0.04 |
| `new Date().constructor.now()` | ok — `946684800000` (the wall clock, 1790304515352, without the fix) | — | 0.04 |
| `(async () => {}).constructor("return 1")` | the `Function` sentence (a function, without the fix) | 4:50 | 0.05 |
| `(function* () {}).constructor("yield 1")` | the `Function` sentence (a function, without the fix) | 4:51 | 0.04 |
| `(async function* () {}).constructor("yield 1")` | the `Function` sentence (a function, without the fix) | 4:57 | 0.04 |
| `await import("x")` at top level | `ReferenceError: Error resolving module 'x' from 'dynamic_import': imports are not available in a graphic; the standard library is global` | — | 0.03 |
| `import x from "x"` | the same sentence, from `'static_import'` | — | 0.03 |
| `typeof WebAssembly` | ok — `undefined` | — | 0.04 |
| push 1 MiB `Uint8Array`s forever | `InternalError: out of memory` | 4:59 | 0.29 |
| `render` without `return` | ``render returned undefined at frame 0 — did you forget `return`?`` | — | 0.04 |

Each case's `render` opens on line 3 and its body is line 4.

**Verdict.** §5b **CONFIRMED** for the limits and **REWRITTEN** for what
they answer: an interrupt points at the function, not the loop; the import
refusal carries QuickJS's prefix and no position; a string of tens of
megabytes is built but cannot be read out, under an rquickjs message that
names nothing (a new §8 row); line and column come from `stack`, since
rquickjs 0.14's `Exception` has no `line()`/`column()`.

---

#### q7 — the package, with the unchanged app

**Measured.** `rows_app.py`, run as `--only q7` after the full run: the git
check empty, `make app` (rc 0, 2.7 s, incremental), and the launched binary's
SHA-256 `228faea7b13c8c71483cccc454edc0b11704d398773bd077c078b9f0794007d0`.
One owned instance on port
4843, by PID, launched twice; `grep "Reelcut: "` over its log printed
nothing.

The app at `c874069` whitelists `project.json`, `cache/` and `media/` in
`fileWrapper(ofType:)` (`ProjectDocument.swift:659-677`), so `graphics/`
cannot survive a save today. **`media/` is the STAND-IN**: it goes through
the same lazy `directoryWrapper` (`:694-702`) a `graphics/` line would call,
and the app reads it at open only to re-anchor missing media by name
(`:557-572`), so a stray `.js` there is inert. `graphics/` is run once as
the **CONTROL**.

| Sub-row | What was done | Answer |
|---|---|---|
| (a) | `new_project P1`; app stopped; `mkdir P1/media`, `mv` from outside to `P1/media/x.js`; relaunched; `open_project`, `add_track`, `save_project` | save ok; `x.js` **present** |
| (a2) | `mv` `y.js` into the existing `P1/media/` while open; `add_track`; `save_project` | save ok (0.03 s), no conflict; `x.js` and `y.js` **present** |
| (a-auto) | `mv` `z.js` in; `add_track`; poll `project.json`'s mtime | an autosave in place wrote it **16.0 s** after the edit; `x.js`, `y.js`, `z.js` **present** |
| (ctrl) CONTROL | the same as (a) with `P3/graphics/x.js` | save ok; `x.js` **ABSENT**, and the `graphics/` folder gone, as the whitelist predicts |
| (b) | `new_project P2` open; `mkdir P2/media` and `mv` `w.js` in (the package's own mtime moved); `add_track`; `save_project` | refused: "The document “P2.reelcut” could not be saved. The file has been changed by another application." |
| (c) | `q7_watch` (a `DispatchSource` on a plain folder's fd, every mask) | `mv` in from outside: `.write` ×1; `x.js.tmp` written then renamed over `x.js`: `.write` ×2 (1.1 ms apart); in-place `O_TRUNC` rewrite of `x.js`: **nothing**; `rm`: `.write` ×1. **No `.rename`, ever.** |

The full run's q7, whose transcript is kept as
`work/graphics_spike/full-run.log` (its `answers.json` entry was replaced
by this run's), printed the same (a)–(b) answers and ONE `.write` for (c)'s
rename-over, so the COUNT of folder events per action is not stable.

**Verdict.** §5f **CHANGED**. What a whitelisted, lazily wrapped folder
does with a file another process put there is measured by proxy: it
survives a save and an autosave in place, landed while closed or while
open. NSDocument's check trips only when a folder is CREATED in the open
package, so `packageContentsDidChangeOnDisk()` is called after creating
`graphics/` and not after every event. The watcher's premise was wrong: a
folder source raises `.write`, not `.rename`, and misses in-place saves
entirely, so each module file gets its own source.

---

#### q8 — is QuickJS's floating point the same in every build?

**Measured.** `math_hash()`, SHA-256 over the bit patterns of 10 000 results
of `Math.sin`, `cos`, `tan`, `pow` and `exp`+`log`, from the release
binary, the debug binary, `cargo test --release --test q8` and `cargo test
--test q8`: all four
`ff4d9866561df3268abc62a9729cca14a6e87c3c81fee58199f2eeed424eb47a`.

**Verdict.** **CONFIRMED**: preview (a release build) and the engine's tests
(either profile) can be compared byte for byte on this host.

---

#### q9 — the FFI shape

**Measured.** With the core patched (q1): `nm -g libreelcut_core.a` finds
`rc_graphic_spike_render` **once** and `JS_NewRuntime` three times.
`q9_probe.swift`, built `xcrun swiftc -O -target arm64-apple-macos26.0
-import-objc-header q9_probe.h -L core/target/release -lreelcut_core` (no
other flag), called it on `lower-third.js` frame 30 at 1920×1080 with
`Montserrat-ExtraBold.ttf` as its one font: SHA-256
`86f017e88897403b38f8fc2fd5692d19f882b88ae91598558393df8dd7c2a595`, 613
bytes of SVG. The REFERENCE, `graphics_spike render --fonts
work/graphics_spike/q9_fonts/` (that one font, nothing else): the **same
SHA-256**. The engine probe is 12 235 712 bytes and the CONTROL probe
(`-D CONTROL`, calling only `rc_op_names`) 12 210 640, a difference of 25 072
— but the CONTROL holds `JS_NewRuntime` ×2 as the engine probe does, so
that difference is the export's own code, not the engine's. The patched
app's `nm` shows `rc_graphic_spike_render` ×0 and `JS_NewRuntime` ×2.

**Verdict.** §5e **CONFIRMED**: an export in `core/src/ffi_graphic.rs`
delegating to a separate crate is in the one staticlib and callable from
Swift, byte-identically; no second staticlib. What is new is the cost: the
linker keeps QuickJS in any binary that links the archive, whether or not
the export is referenced, which is q1's +7 194 848 bytes of app.

### 10.2. Not run

Every row and sub-row ran. Two things were measured by PROXY and are named
as such: q7's (a), (a2) and (a-auto) used `media/` as the stand-in for
`graphics/`, because adding the whitelist line is G1's and `app/` had to
stay at `c874069` (the direct measurement is §5l's "Package" proof row, in
G3); and no `<image>` was rendered, so "resvg 0.48.1 decodes nothing
without `raster-images`" is a reading of `src/image.rs:26-32`, priced by
q1c but not photographed. q1's `make app` times are incremental builds
over a warm `build/` and compare only with each other.

### 10.3. Owed from G0's review

G0's second review passed with four nits, none of which changes a §10.1
answer. They are written here so G1 finds them:

1. **`performance` is untouched by the sandbox**
   (`tools/proof/graphics_spike/src/runtime.rs:144`). If quickjs-ng defines
   `performance.now()`, that is a clock the frozen `Date` does not cover.
   It is unverified: no q6 case checks it. **Owed to G1:** a
   `typeof performance` case in the sandbox tests, and the global deleted
   if it exists (G-5).
2. **`textLines` writes `font-family` unquoted**
   (`tools/proof/graphics_spike/src/stdlib.js:181`), against the rewritten
   §5c. The spike's fixtures never call it with a spaced family. **Owed to
   G1:** the engine's `stdlib.js` quotes the family in every helper.
3. **The name `engine_linked_bytes` is wrong**
   (`tools/proof/graphics_spike/rows_build.py:245,272`). The key and its
   printed label contradict §10.1 q9, which says that difference is not
   the engine's cost. This is an instrument label, and the record's prose
   is the one that holds.
4. **`patch()` never checks its anchors**
   (`tools/proof/graphics_spike/rows_build.py:152,160`). If an anchor were
   missing, q1 would silently measure the baseline twice. The recorded run
   shows different before and after numbers, so it did not happen here. It
   would matter only if the spike is re-run against a changed
   `core/src/lib.rs`.

One file-state caveat: the fix pass's verification re-run overwrote
`tools/proof/work/graphics_spike/q3.csv`, `frames/`, `q7/` and `q9/`, so
those artefacts no longer match the record. `answers.json` is the recorded
run, with q6 replaced by the post-fix re-run (the spike README says so).

### 10.4. G1 — the engine

G1 runs as four `/litecode` pipelines, each committed on its own (the
user, 2026-09-24: "Break down large phases as needed. Commit after each
completed phase."): **G1a** the `ReelCore.swift` toll; **G1b** the
`graphic/` crate's drawing half (library, fonts, raster, `measureText`, the
font-family warning); **G1c** its JavaScript half (runtime, sandbox,
module, standard library, props, fixtures); **G1d** the link into the core
and the app (`ffi_graphic.rs`, the header, the `ReelCore.swift` wrappers,
the probe, `docs/graphics-api.md`, the spec's amendments). The split is by
what each can prove alone.

#### G1a — the ReelCore.swift toll (2026-09-24)

A pure move, landed and gated alone before G1d's wrappers (§5e, §9 step 9),
against baseline `c5f3265`.

**What moved, and why this and not §5e's candidate.** `final class
RecipeSource` — the compositor's process-wide recipe registry, from its
`// MARK: - The compositor's recipe registry` line through the class's
closing brace (baseline lines 1274–1406, **133** lines measured) — is
`app/Sources/RecipeSource.swift`'s, verbatim, after `import Foundation` and
a blank line. It was picked over §5e's candidate, `MediaDescriptor` +
`mediaURL(for:)` + `bookmarkString(for:)` (baseline lines 729–789 and
1408–1440, ~94 by line arithmetic), because it is larger than the ~110 lines
G1d will add where the media candidate is not, and because it is the one
concern in the file that is not the core's edge at all: it exists because
AVFoundation instantiates the compositing class itself (spec §7.6), it names
no `rc_*` symbol and none of the file's three `private` helpers
(`takeString`, `takeErrorMessage`, `jsonArray`), and every caller reaches it
through `RecipeSource.shared`, so no caller changed. `RecipeOptions` stayed
in `ReelCore.swift` beside `recipeJSON`, whose header spelling its `json`
is.

**Measured** (`wc -l`): `ReelCore.swift` **1440 → 1309** — the 133-line
block and the blank line before it out (134), and 3 lines in: the header's
new sentence naming `RecipeSource.swift` as the payment owed at 1440.
`RecipeSource.swift` **135**, new (133 + the import and its blank). The
move frees 131 lines net against G1d's ~110.

**Verbatim check.** `git show c5f3265:app/Sources/ReelCore.swift | sed -n
'1274,1406p' | diff - <(sed -n '3,$p' app/Sources/RecipeSource.swift)`
printed nothing, then `VERBATIM`.

**Verified**, each printed by a run:

| Command | Result |
|---|---|
| `wc -l` | `ReelCore.swift` 1309, `RecipeSource.swift` 135 |
| the verbatim diff | empty, `VERBATIM` |
| `make typecheck` | exit 0; 0 `error:` lines; the 7 baseline deprecation warnings and no eighth (`grep -c 'warning:'` prints 14, because each diagnostic prints its `warning:` twice — on its location line and in its source excerpt; the 7 location lines are exactly the root `CLAUDE.md`'s list) |
| `make test` | exit 0; 54 `test result:` lines, 827 passed, 0 failed (a control: no `core/` file touched) |
| `make lint` | exit 0; no warning or error (a control) |
| `make app` | exit 0, `** BUILD SUCCEEDED **`, `Reelcut.app` present |
| `tools/proof/harness/build.sh --force` | exit 0, `built …/tools/proof/work/harness/harness in 86 s` — every file in `app/Sources` compiles together |

Nothing was launched; no MCP session was needed.

**Pointers and records edited.** `ReelCore.swift`'s header (the type list
loses `RecipeSource`; the size-payment paragraph gains the sentence);
`Compositor.swift:32`, the one comment that named the FILE, now
`RecipeSource.swift`; spec §7.4's Swift file map (`RecipeSource` out of
`ReelCore.swift`'s row, a `RecipeSource.swift` row after `Compositor.swift`'s);
the README's file map (both rows). Also this record, remaining §3 and
`designs/reelcut-app-notes.md`. `app/CLAUDE.md`'s two sentences (the
`ReelCore.swift` bullet's list, a new `RecipeSource.swift` bullet under
Playback and rendering) were written by the orchestrator after the
review, not by the pipeline. The review passed first time with no blocker or
should-fix (nit: `ReelCore.swift:6`'s "and … and" is the spec's exact text,
left as written).

**Owed.** If G1d's wrappers measure more than the 131 lines this move
freed, G1d pays a second pure move first: the next seam is §5e's own
candidate, `MediaDescriptor` + `mediaURL(for:)` + `bookmarkString(for:)`
(baseline lines 729–789 and 1408–1440, ~94 by line arithmetic), then the
`dictionary` extensions (baseline 791–896). §5e's candidate sentence and
§9's table row were left as written; this record says what was picked.

#### G1b — the drawing half (2026-09-25)

The `graphic/` crate at the repo root, its drawing half only, against
baseline `b54c1be`: the Library, `rasterize`, `measure_text` and the
Diagnostic, with no QuickJS (G1c) and no dependency from `core/` (G1d).

**What landed.** `graphic/Cargo.toml` (resvg 0.48.1 with `text`,
`raster-images`, `svgz` and no default features; `serde_json` with
`preserve_order`; `sha2`; `svgtypes` 0.16.1 and `simplecss` 0.2, usvg's own
pins, so a `font-family` value and a CSS sheet are read exactly as usvg
reads them; dev `flate2`), its `Cargo.lock`, and five `src/` files:
`lib.rs` (declarations and re-exports, `#![forbid(unsafe_code)]`),
`diagnostic.rs`, `library.rs` (the font set from bytes, the asset map, the
content version, the `measure_text` memo, and the crate-private
`options()` whose resolvers record into a per-call probe), `raster.rs`
(`rasterize`, `MAX_SIDE` = 8192, the RGBA→BGRA row copy into the caller's
strided buffer, and every warning text) and `measure.rs`. The Makefile's
`test`, `lint`, `fmt` and `clean` each run the crate after the core;
`.gitignore` gains `/graphic/target/`. Four committed 8×8 test images in
`graphic/tests/assets/` with a README holding the ImageMagick 7.1.2
command and colour of each (`ls -l`: `red.png` 312 bytes, `steel.jpg` 285,
`blue-then-yellow.gif` 101, `magenta.webp` 36).

`wc -l`: `diagnostic.rs` 59, `lib.rs` 19, `library.rs` 226, `measure.rs`
173, `raster.rs` 250 — each under 400.

**What `rasterize` reports that resvg never does**, each as a warning
(deduplicated, first-occurrence order) while the frame still draws: a
family list no face answers (`select_font` wraps usvg's default selector
and records the list when it answers `None`); a `font-family` value usvg
could not parse — found by a scan of attributes, `style` attributes and
`<style>` sheets through svgtypes and simplecss, run only when the probe
recorded usvg's default family — with the quoting advice when an unquoted
word starts with a digit (`Source Sans 3`); a `<text>` with no family; an
`<image>` href that is not an asset; a data: URL; an asset that is not an
image; and a root whose rounded size is not the graphic's.

**Tests** — 40 in six binaries, black-box through `graphic::`, every pixel
claim read back from `out`:

| File | Tests | What it proved |
|---|---|---|
| `pixels.rs` | 6 | a `#ff8000` rect is exactly `[0x00,0x80,0xff,0xff]` inside and `0` outside; half-alpha white is **128** on all four channels; stride 32 at width 5 leaves the padding bytes `0xAB`; the five refusals by leading text, each leaving `out` untouched; four threads draw identical bytes; `Library: Send + Sync` |
| `edges.rs` | 1 | white Montserrat 800 at 64 px, composited premultiplied: every channel over white is 255 and over black equals the source, across 2 017 partially covered pixels |
| `images.rs` | 7 | PNG, JPEG, GIF (its first frame, blue) and WebP each draw the README's colour at the centre (JPEG measured exact, `[192,128,64,255]`) and nothing at the corner; an `.svg` asset and its gzip `.svgz` draw byte-identical frames; the unknown-href (with and without assets), data:, not-an-image and size-mismatch warnings, exact text |
| `families.rs` | 10 | a missing family is named with the set and draws nothing; `Source Sans 3` unquoted draws nothing and gets the digit advice, from an attribute, a `style` attribute and a sheet; quoted, and `Nope, Montserrat`, draw without a warning; a list of misses is named as a list; no family gets the default's sentence; a sheet's missing family is seen; a nested `.svg` asset's missing family is seen, and the test completes (the lock-discipline oracle) |
| `measure.rs` | 9 | parity over 288 cases (24 strings × Montserrat 800, Anton, IBM Plex Mono, Bebas Neue × 24/64/160 px): `|ink_width − columns|` ≤ 2.0, worst **1.656 px** (IBM Plex Mono 24 px `"résumé naïve"`: 169.344 vs 171 columns); whitespace collapses; variable faces widen with weight; the four errors; whitespace-only is zeros; letter-spacing widens the advance; the memo answers `==`; `to_json`'s key order |
| `library.rs` | 7 | the six bundled families sorted; one `Source Sans 3` face (`SourceSans3-Roman`, weight 200) and one `Darker Grotesque` (300); the version is 64 lowercase hex, stable, and changes with one asset byte; `version_differs_at_entry_boundaries`; a 16-zero-byte blob is named by index; an empty library draws a rect; the Diagnostic's JSON key order |

Measured through `measure_text` at 64 px, `"Hamburgefonstiv"`, weights
200/400/700/900: **Source Sans 3** 438.912, 462.336, 491.456, 502.656;
**Darker Grotesque** 379.456, 389.568, 419.712, 439.936. One `measure_text`
call measured 197.9 µs cold and 583 ns from the memo.

**Made to fail**, each reverted: removing the byte swap fails
`pixels::a_rect_draws_in_bgra_and_nothing_else_is_touched`; dropping the
`select_font` wrapper fails eight of `families.rs`'s ten; `resolve_string`
answering `None` fails five of `images.rs`'s seven; answering the advance
as `ink_width` fails `measure::ink_width_matches_the_ink_a_composed_render_draws`;
hashing without the length prefixes fails only
`library::version_differs_at_entry_boundaries`; compositing un-premultiplied
fails `edges::white_text_edges_composite_exactly`. A seventh, recorded and not kept
as a test: holding the probe lock across `from_data_nested` hung
`families::a_missing_family_inside_a_nested_svg_asset_is_seen` (the other
nine passed) until Rule H's 900 s bound killed it (`expired: True`, rc −9).

**Verified**, each through `bounded.run` where it runs tests: `cargo fmt
--check` and `cargo clippy --all-targets -- -D warnings` in `graphic/` exit
0; `cargo test --release -- --nocapture` in `graphic/` exit 0, 40 passed, 0
failed, 2.8 s warm; `make test` exit 0, 62 `test result:` lines, **867**
passed (the core's 827, unchanged, plus these 40), 0 failed; `make lint`
exit 0; `make typecheck` exit 0, 0 `error:`, the 7 baseline warning
locations and no eighth (a control); `rg 'std::(fs|env|net|time)'
graphic/src` prints nothing.

**Deviations from the design.**
- A fourth `src/` file beyond §5a's list, `measure.rs`, so each file stays
  under 400.
- `letter_spacing` is in the `measure_text` memo key: §5c's key list omits
  it, and it changes the advance (a test proves it).
- Two warnings §5 does not list: a data: URL is refused (drawn as nothing,
  with the way out — put the file in `graphics/assets/` and use `asset(name)`),
  so every image a graphic draws is an asset the Library's version covers;
  and a root whose size is not the graphic's is drawn at 1:1 (G-7) and
  warned.
- The digit warning says "a family name with a word that starts with a
  digit must be quoted", because svgtypes refuses `Source Sans 3` on its
  third word, not its first.

**Review.** Passed first time, no blocker or should-fix. Its three nits,
kept as they are and owed here:
- `raster.rs:76`: an SVG that names `font-family="Times New Roman"`
  explicitly is warned "a <text> has no font-family", because usvg's
  fallback family and an explicit one look the same to the resolver; and
  when one `<text>` has no family while another's cannot be parsed, only
  the second warning appears (the gate at `raster.rs:205`). Both follow the
  design as written; a sharper sentence is owed if an agent is misled.
- `tests/edges.rs:30`: the "over black" composite cannot fail (source plus
  zero is the source); only "over white" tests anything. A per-channel
  `colour ≤ alpha` assertion would give it teeth.
- `raster.rs:85`: the asset-name list is rebuilt per unknown href inside
  the loop (cost only).

`graphic/CLAUDE.md` and the root `CLAUDE.md`'s Commands and File map lines
were written by the orchestrator from this pipeline's drafts, after the
review.

**Owed.** G1c (the JavaScript half), G1d (the link into the core and app).
Out of scope and not built: generic CSS families mapped to bundled faces
(`sans-serif` is warned like any missing name), the `font` shorthand in the
scan, `xml:space="preserve"` measurement, an in-place render when
`stride == width × 4` (a G6 candidate), and asset-name validation.

#### G1c — the JavaScript half (2026-09-25)

The `graphic/` crate's JavaScript half, against baseline `93c0181`:
QuickJS through `rquickjs` 0.14.0 (`loader` feature only), a `Module`
compiled once, a sandboxed engine per (thread, module), the §5c standard
library, G-4's props overlay and `svg(module, frame, props, ctx,
budget_ms)`. Nothing outside `graphic/` and this record was touched; the
core does not depend on the crate yet (G1d).

**What landed.** Seven new `src/` files: `module.rs` (`Module`, `Send +
Sync + Clone`, holding no QuickJS object: name, source, the SHA-256
revision of G-13, `meta` and `schema` read through `JSON.stringify` in the
module's own key order, `{}` when not exported); `runtime.rs` (`Engine` —
one `Runtime` + `Context` with §5b's 64 MB heap and 1 MB stack, the
interrupt deadline, the refusing loader — the `thread_local!` map keyed by
the module's id with a `Weak` swept before each call, `svg`,
`engine_count`, `HEAP_BYTES`, `STACK_BYTES`; the ONE `std::time` import in
`src/`); `sandbox.rs` (G0's sandbox script plus `delete
globalThis.performance`, since `JS_NewContext` installs a clock there);
`exception.rs` (exception → Diagnostic, the position from `stack`
preferring the module's own frame, the budget's three sentences, what
`render` returned); `host.rs` (`__measureText` with six arguments,
`__assetNames`, `__warn`); `props.rs` (the compile-time schema check, the
lenient render-time `overlay`); and the library as two scripts,
`stdlib.js` and `noise.js`. `Cargo.toml` gains `rquickjs` and dev `png`
(0.18, already in the lock through tiny-skia).

`wc -l`: `exception.rs` 114, `host.rs` 71, `lib.rs` 30, `module.rs` 103,
`noise.js` 132, `props.rs` 161, `runtime.rs` 284, `sandbox.rs` 74,
`stdlib.js` 318 — each under 400.

**The warning sink.** Arming a call (load or render) clears the sink;
`svg` answers what `__warn` collected only on its `Ok` arm, stamped with
the call's frame, after the overlay's own warnings. A refused call's
warnings and a module's load-time warnings are discarded; `compile` has no
warnings channel.

**Tests** — 55 new in seven binaries, black-box through `graphic::`:

| File | Tests | What it proved |
|---|---|---|
| `sandbox.rs` | 19 | G0's eighteen q6 cases plus `performance`, each answering §10.1 q6's words and positions exactly (`while (true) {}` → the budget sentence with `3:1`, 250.03 ms; `string_50mb` → the could-not-be-read sentence, 116.72 ms; every other call under 0.3 ms); the SAME-ENGINE check — each of the 17 cases that compile called a second time on the same `Module` and thread, answering identically; then the module dropped and the CONTROL — `lower-third` frame 0 at 1920×1080 hashed on the same thread equal to a fresh thread's; every call under the 1 000 ms bound |
| `module.rs` | 9 | §5c's module compiles with schema keys `title, subtitle, accent, size, boxed, align, logo` and meta keys in order; the revision is SHA-256 of the source and moves with one byte; `Module: Send + Sync + Clone`; absent exports are `{}`; every compile sentence (20 sources) and the limits (64 keys, a 32-character key, a 4 096-character default) that pass; a syntax error answers `SyntaxError: unexpected token in expression: ';'` at **3:11**; a top-level loop answers `over the 250 ms budget while loading (InternalError: interrupted)`; five dropped modules' engines are swept (`engine_count` 5 → 1); a module draws on a thread that did not compile it |
| `render.rs` | 7 | the six fixtures at frames 0/30/90 answer `<svg…` with zero warnings from `svg` and from `rasterize`; `42`, `"<div>"`, `ctx = []` each in its sentence with the frame; `Error: boom` at the module helper's **3:13**; the positioned throw — `interpolateColors` refusing `"boom"` inside the stdlib — reported at the module helper's **3:10**; a load that runs past a 1 ms budget inside `svg` on a thread with no engine yet answers `over the 1 ms budget while loading (…)` WITH the frame |
| `determinism.rs` | 3 | 6 fixtures × 20 frames × 8 threads × 3 shuffled repeats: **2 880** renders, **0** SVG or BGRA differences from the single-thread reference; each fixture's frames 0/30/90 equal after 300 others; the MUTANT (a module-level call counter) through the same comparison: **468 of 480** differ |
| `props.rs` | 6 | the overlay keeps schema order; a stale key passes through with its warning; five wrong types each fall back with their sentence; an enum outside its options; stored `[]` and `"x"`; through `svg` the warnings carry the frame |
| `stdlib.rs` | 10 | the six `tests/js/*.test.js` files (interpolate, easing, spring, text, random, format) pass; the directory holds exactly those six; an unknown asset warns naming the four committed files; `warnings_do_not_leak_across_calls`; `load_time_warnings_are_discarded` |
| `pins.rs` | 1 | frames 0/30/90 of each fixture hash to `tests/pins.json` (written by `GRAPHIC_REPIN=1`); on a mismatch the PNGs go to `target/pins/` |

`counter.js` uses `formatNumber` in place of its hand-rolled `grouped`;
the other five fixtures are G0's, verbatim.

**Made to fail**, each reverted: the MUTANT is built in (above). Removing
the four sandbox lines that redefine `Date.prototype.constructor` and the
three function-kind constructors failed exactly `date_constructor` and the
three `*_constructor` cases (15 passed, 4 failed). `position` taking the
first frame instead of the module's failed the positioned-throw test
(it read `133:62`, inside `stdlib.js`) and FIVE sandbox cases —
`math_random` and the four that throw the sandbox's `Function` sentence,
all of which start in the sandbox script's frame (they read line 15 or
16); `Error: boom` did NOT fail, since its first frame is the module's.
Reversing the `Engine`'s field order aborted
`dropped_modules_engines_are_swept` (SIGABRT). Dropping `delete
globalThis.performance` failed the `performance` case. Unquoting
`textLines`' family failed `text_test_js`. Dropping the sink clear from
`arm` failed `warnings_do_not_leak_across_calls` (two warnings) and
`load_time_warnings_are_discarded` (one).

**Review fixes** (the pipeline's review, one should-fix and three nits,
all fixed). A load failing inside `svg` (a thread with no engine yet)
now carries the frame, as every render-time diagnostic does; dropping
the `get_or_insert(frame)` failed
`a_load_that_fails_inside_svg_names_the_frame` (`None`, not `Some(9)`).
`formatNumber` returns `toFixed`'s exponent form ungrouped
(`formatNumber(1e21)` was `"1e,+21"`), and `svg()` escapes `background`;
each reverted alone failed `format_test_js` on its new assertion.
`engine_count`'s doc now says it counts dropped modules' engines not yet
swept. The re-review passed, with one nit kept: that new test is
TIMING-dependent — its top-level 1e6-step loop must finish inside the 250 ms
compile budget yet overrun a 1 ms budget on a fresh thread. Both margins
are wide; if it ever flakes, replace the loop with one sized to the budget.

**Verified**, test runs through `bounded.run`: `cargo fmt --check` and
`cargo clippy --all-targets -- -D warnings` in `graphic/` exit 0; `cargo
test --release` in `graphic/` rc 0, not expired, 18.55 s, **95** passed (G1b's
40 plus these 55), 0 failed; `make test && make lint` rc 0, 69 `test
result:` lines, **922** passed (the core's 827, unchanged, plus 95), 0
failed; `make typecheck` exit 0, 0 `error:`, the 7 baseline warning
locations (a control); `rg 'std::(fs|env|net)' graphic/src` prints nothing;
`rg -n 'std::time' graphic/src` prints one line, `src/runtime.rs:15`.

**Deviations from the spec.**
- `render returned {type}`: rquickjs names a number `int` or `float` and a
  boolean `bool`; the sentence says `number` and `boolean`, as the spec's
  own examples do.
- The easings are wrapped to answer exactly 0 at `t === 0` and 1 at `t ===
  1`: G0's `inBack(1)` is 0.9999999999999998 and `inSine(1)`
  0.9999999999999999, which the endpoint test refuses.
- `Engine::new` makes its own warning sink rather than taking one;
  `engine_count` counts without sweeping (the call's sweep is what the test
  proves), and `compile` sweeps too when it adopts its engine.
- `textLines` escapes `fill` as well as the family.

`graphic/CLAUDE.md`'s module map, amended purity rule (the one deadline
clock), drop-order and evaluation rules were written by the orchestrator
from the pipeline's draft, after the review.

**Owed**, and out of scope here: G1d (the core's `ffi_graphic.rs`, the
header, the `ReelCore.swift` wrappers, `docs/graphics-api.md`); path helpers; an SVG size cap; an
LRU cap on per-thread engines (sweep-on-drop only); named CSS colours in
`interpolateColors`; a warnings channel on `compile`; refusing the module
name `eval_script`, whose frames `position` would take for a module's.

#### G1d — the link into the core and the app (2026-09-25)

Against baseline `cea2ddf`: the nine exports of §5e in one new core module,
the header and `ReelCore.swift` in lockstep, a probe that draws through the
app's own wrappers, and `docs/graphics-api.md` with a test that runs it. No
format bump (G2's); nothing user-visible, so the README is untouched.

**What landed.** `core/Cargo.toml` gains `graphic = { path = "../graphic" }`
(plain, no cargo feature), `serde_json`'s `preserve_order` spelled out with
the reason (below), and dev `sha2` (already in the lock through `graphic`).
`core/src/ffi_graphic.rs` (397 lines) is the ONLY module of `core/src/`
that names the crate: `RcGraphicLibrary` (a `Mutex<Option<Pending>>` of
fonts and assets and a `OnceLock<Arc<graphic::Library>>`), `RcGraphic`
(wrapping `graphic::Module`), and `rc_graphic_library_new`, `_add_font`,
`_add_asset`, `_free`, `rc_graphic_compile`, `_describe`, `_svg`,
`_rasterize` and `rc_graphic_free`. `ffi_util.rs` gains
`fallible_op_wrapped` (the panic message shaped by the caller; `fallible_op`
is it with identity), so `ffi_graphic.rs` hand-rolls no `catch_unwind`. The
header gains `<stddef.h>` and a `/* graphics */` section with the two
opaque types, the nine prototypes and the `diag_out` contract in prose.
`ReelCore.swift` gains `// MARK: - Graphics` at its end —
`GraphicDiagnostic`, `GraphicFailure`, `GraphicRaster`, `GraphicLibrary`,
`GraphicModule` and a private diag-taker — and its header's type list the
two classes: **1309 → 1440**, 131 lines net, exactly the room G1a made, so
no second move was needed.

**The `diag_out` contract.** NULL, or a JSON ARRAY of `{level, message,
line, column, frame}` in that order (`Diagnostic::to_json`). A failure
always writes exactly ONE error: the crate's own, or the FFI's for an
argument it could not read (`library is NULL`, `name is NULL`, `source is
NULL`, `graphic is NULL`, `svg is NULL`, `out_bgra is NULL`, `ctx_json is
NULL`, `props_json is not JSON: …`, `ctx_json is not JSON: …`, `height ×
stride overflows`), or `internal error: <what>` for a caught panic, wrapped
the same way. A success writes it only when there are warnings.

**Deviations from §5e** (its C block is left as written; this is what was
picked, as G1a did):
1. **A library is a builder that FREEZES.** `graphic::Library` is immutable
   (its `version` hashes every byte), so `rc_graphic_library_add_font` /
   `_add_asset` fill a pending set that the first `rc_graphic_compile` or
   `rc_graphic_rasterize` against it turns into one `Arc<Library>`; an add
   after that answers false with `the library is frozen: a graphic was
   compiled or a frame drawn against it; build a new one`. A library never
   changes under a compiled graphic, and `RcGraphic`'s `Module` holds the
   `Arc`, so the fonts outlive `rc_graphic_library_free`.
2. **`rc_graphic_compile` takes `budget_ms`**, passed to
   `Module::compile` (0 passes through): a top-level `while (true) {}` must
   stop, and §5e's prototype had no deadline for it.
3. **The adds refuse where the crate warns.** `add_font` refuses bytes that
   load no face (`font bytes loaded no face`, read off a throwaway one-font
   `Library`'s `warnings()`), and `add_asset` an empty name (`name is
   empty`) and a duplicate (`asset "<name>" is already in the library`),
   so a library built through the FFI never carries a `warnings()` entry.
   Also a correction to the request: `app/Resources/Fonts/` holds EIGHT
   `.ttf` files, not seven (six families; Montserrat and IBM Plex Mono have
   two faces each).

**The `preserve_order` finding — feature unification, measured here for
the first time.** `graphic/Cargo.toml` enables `serde_json`'s
`preserve_order`, and a path dependency unifies it into the core's build,
so `serde_json::Map` in `core/` became insertion-ordered the moment the
dependency was added (the G0 spike's `serde_json = "1"` never exercised
this). With only `Cargo.toml` changed, `cargo test --release
--no-fail-fast` in `core/` printed **826 passed, 1 failed**: exactly
`evaluate_tests::an_unanimated_text_layer_shows_all_of_itself_and_hashes_as_it_always_did`,
whose oracle is a sorted literal hashed by FNV. No refusal test failed on
key order. The fix is in `recipe.rs`, not the literal: `content_hash` now
hashes `sorted(description)` (every object's keys through a `BTreeMap`,
recursively), which is the order every hash before the link was taken in,
so no texture key changes; `RecipeLayer::object()`'s doc, which said "`Map`
is a `BTreeMap` in this build", was rewritten, and the test's doc comment
re-worded. `recipe.rs` 582 → 594. After it: 827 passed, 0 failed. The wire
order of recipe, plan and schema objects is now insertion order — harmless
(Swift decodes by key; the proofs parse JSON), and recorded here.

**Lock drift.** Resolving `core/Cargo.lock` with `graphic` added differs
from `graphic/Cargo.lock` in three packages: `smallvec` 1.16.2 (graphic
1.16.1), `syn` 3.0.4 (3.0.6) and `unicode-ident` 1.0.24 (1.0.26). `syn` and
`unicode-ident` are compile-time only; none touches a pixel, and the probe's
P5 (the crate's pin, through the core's lock) is the proof.

**Tests.** `core/tests/graphic_ffi.rs`, 9, through the FFI only, with the
bundled faces, the `lower-third` fixture and G1c's `ctx(30, 30.0, 150,
1920, 1080)`: the library takes all eight faces and refuses 16 zero bytes,
an empty name and a duplicate asset; `describe` answers the schema keys
`title, subtitle, accent, size, boxed, align` in the module's order (read
off the TEXT) and a revision equal to `sha2` of the source; frame 30 writes
no `diag_out`, and `{"size":"big"}` answers the one warning `props.size is
a string but the schema says number; the default 64 is used` with frame
30; the BGRA of frame 30 at 1920×1080 hashes to `graphic/tests/pins.json`'s
`lower-third.30` (read from the file), and stride 32 at width 5 leaves the
`0xAB` padding; a syntax error (line 3) and a top-level loop at 50 ms
(`over the 50 ms budget while loading`) each answer one error; every refused
argument above is one error Diagnostic with the five keys in order; a
library freezes at its first compile and at its first rasterize, and a
graphic draws the same SVG after its library is freed; a graphic drawn from
a second thread answers byte-identical SVG; and only `ffi_graphic.rs` in
`core/src/` names the crate. `model_tests.rs`'s NULL sweep covers the nine
(the header-coverage test fails until it does). `graphic/tests/reference.rs`,
3: every `js` block of `docs/graphics-api.md` runs (20 blocks; a block that
`export`s compiles and draws frames 0 and 30, any other is a `render` body
drawn at frame 30); every `^function` name of `src/stdlib.js` AND
`src/noise.js` not starting `__`, plus `Easing`, is in the doc in
backticks; every bundled family and the three sandbox sentences appear.

**The probe.** `tools/proof/graphics_ffi_probe.py` builds
`graphics_ffi_probe.swift` over `app/Sources` with `harness/build.sh`'s
swiftc line and runs it under `graphics_spike/bounded.py`'s `run` (600 s
bound); the Swift side drives `GraphicLibrary` and `GraphicModule` and
writes the raw BGRA and a PNG, and Python scores with its own oracles:
**9/9** — P1 built and answered; P2 all 8 `.ttf` taken, 16 zero bytes
refused; P3 the schema order and `hashlib`'s revision
(`38b382b6…`); P4 frame 30 `<svg`, no warnings; P5 the BGRA's SHA-256
`86f017e8…a595` equal to the pin, and
`work/graphics-ffi-probe/lower-third-30.png` a PNG with a 1920×1080 IHDR;
P6 frame 30 twice byte-identical, frame 0 different; P7 `SyntaxError:
unexpected token in expression: ';'` at line 3; P8 `over the 50 ms budget
while loading (InternalError: interrupted)` after 0.051 s; P9 the
`props.size` warning at frame 30.

**Made to fail**, each reverted: `--mutant frame-off-by-one` (a COPY of
`app/Sources` with `GraphicModule.svg`'s `Int64(frame)` replaced by
`Int64(frame + 1)`, the anchor asserted once) exited 0 — P5 FAILED
(`cf1a6048…237b` against the pin) and P9 FAILED (frame 31). The reference
test: `measureText("x", { family: "Nope" });` appended to the `escapeXml`
block failed `every_js_block_in_the_reference_runs` (`the block at line 212
failed: Error: measureText: no face for family "Nope"; the set has: Anton,
Bebas Neue, Darker Grotesque, IBM Plex Mono, Montserrat, Source Sans 3`),
and passed again with the line removed.

**Binary size.** `stat -f %z` of `Reelcut.app/Contents/MacOS/Reelcut`,
Release: **12 661 536** before (the untouched tree, `make app`), **20 596 752**
after — **+7 935 216** bytes, against G0 q1's +7 194 848 with nothing
calling the engine; `nm` finds the nine `rc_graphic_*` symbols in the
binary, since the wrappers now call them. The bundle after is 23 116 KiB
(`du -sk`).

**Verified**, each printed by a run: `make test` exit 0 — core **836**
passed (827 + 9), graphic **98** (95 + 3), 0 failed; `make lint`, `cargo
fmt --check` in both crates, exit 0; `make typecheck` exit 0, 0 `error:`,
the 7 baseline warning locations and no eighth; `make app` `** BUILD
SUCCEEDED **`; `tools/proof/harness/build.sh --force` exit 0 (a CONTROL:
every app file compiles against the fatter staticlib, with `project.yml`'s
and the harness's link lines unchanged); the probe 9/9 and its mutant exit
0; `rg -n "graphic::|use graphic" core/src` prints only
`core/src/ffi_graphic.rs` lines; `rg 'std::(fs|env|net)' graphic/src`
prints nothing (a CONTROL); `wc -l`: `ReelCore.swift` 1440,
`ffi_graphic.rs` 397, `recipe.rs` 594, `docs/graphics-api.md` 389.

**Spec and glossary.** Spec §1's non-goal gains G-1's clause; §7's first
sentence is G-2's; §7.1's code block gains the typedefs and nine prototypes;
§7.10 gains `graphic` in its deps sentence and an `ffi_graphic.rs` row; §11
gains G-1, G-2 and G-5, dated 2026-09-25. `CONTEXT.md` gains **Graphic**,
**Module** and **Revision**.

**Owed from G1d.** A `rc_graphic_library_version` export for §5d's texture
key is G3's to add if it needs it; `describe` carries no `name` or
`defaults` (G2/G5 may add); `GraphicLibrary.rasterize` refuses a side over
8192 in Swift before it allocates, restating the crate's `MAX_SIDE` in
`GraphicLibrary.maxSide` — one constant in two places, to be read through
the FFI if it ever moves; a zero-length asset crosses from Swift as a NULL
pointer and is refused as `bytes is NULL`.

**Review.** Passed first time, no blocker or should-fix. Its three nits:
- `ReelCore.swift:7` has one 123-column comment line from the header's
  rewrap; reflowing it costs a line over the 1440 budget, so it waits for
  the file's next pure move. Owed.
- `core/tests/graphic_ffi.rs`'s `only_ffi_graphic_names_the_graphic_crate`
  reads only the top level of `core/src`; a future subdirectory would
  panic its `read_to_string` and go unchecked. Owed (recurse when the core
  first gains a subdirectory).
- Does any serialized core value come from a `HashMap`, whose order
  `preserve_order` would now carry through a `Value` instead of sorting?
  Answered by the orchestrator: NO. `rg 'HashMap|HashSet' core/src` finds
  only `edit_paste.rs`'s and `model_query.rs`'s `u32 → u32` id remaps and
  `model_query.rs:217`'s id set, none of them serialized. What DOES change
  is that a `Value` the core stores or answers (a patch echoed, props) now
  keeps its caller's key order instead of sorting — deterministic, and
  what G-4's props want; the 836 core tests pass on it. One more
  consequence, found by G2a's adversary: under `preserve_order`,
  `Map::remove` SWAPS the last key into the removed slot (serde_json's
  `swap_remove`), so a removal no longer keeps the others' order;
  `shift_remove` does. The core's existing removals are harmless (checked
  by the orchestrator): `edit.rs:655` takes `scope` out before a decode,
  `recipe_text.rs:305-311` trims a description that `content_hash` sorts
  anyway, and `edit_action.rs:106`'s `prune_removed` reorders an action
  end's keys deterministically, where they were sorted before. New code
  that promises an order (G2a's props) uses `shift_remove`.

The `core/CLAUDE.md`, `app/CLAUDE.md` and root `CLAUDE.md` lines were written
by the orchestrator from the pipeline's drafts, after the review.

#### G1 closed — what it delivered against §9a

G1 (G1a–G1d, 2026-09-24/25) is BUILT. §9a's checklist, item by item:
1. `serde_json` with `preserve_order` — BUILT: `graphic/Cargo.toml`, the
   schema in the module's order (`tests/module.rs`, `graphic_ffi.rs`), and
   unified into the core, whose `content_hash` now sorts (G1d).
2. resvg `text`, `raster-images`, `svgz` — BUILT (G1b): `tests/images.rs`
   draws PNG, JPEG, GIF, WebP and a nested `.svg`/`.svgz`.
3. The sandbox, eighteen q6 cases plus `performance` — BUILT (G1c):
   `tests/sandbox.rs`, 19.
4. Line and column from `stack`, an interrupt at its function — BUILT
   (G1c): `exception.rs`; `tests/module.rs`, `tests/sandbox.rs`.
5. `measureText`'s advance AND ink box within 2 px — BUILT (G1b):
   `measure.rs`; `tests/measure.rs`, worst 1.656 px.
6. A missing or unquoted family warned, every helper quoting — BUILT (G1b
   `raster.rs`, `tests/families.rs`; G1c `textLines`).
7. `formatNumber` — BUILT (G1c): `stdlib.js`, `tests/js/format.test.js`.
8. The engine's own sentence for a string too large to read — BUILT (G1c):
   `exception.rs`, the `string_50mb` case.
9. The `ReelCore.swift` toll first — BUILT (G1a): `RecipeSource.swift`;
   G1d's wrappers took exactly the 131 lines it freed.

**Owed from G1 as a whole**: G1b's three review nits and its out-of-scope
list, G1c's list (path helpers, an SVG size cap, an LRU cap on per-thread
engines, named CSS colours, a warnings channel on `compile`, refusing the
module name `eval_script`) and G1d's above. **G2 (the model, format
version 10) is next**, from §5g and §4's G-3, G-4 and G-6 to G-13.

### 10.5. G2 — the model

#### G2a — the persisted graphic clip and its two ops (2026-09-25)

Against baseline `fe16e94`: §5g's model and §5h's two ops in the core,
format version 10, and the app decoding a graphic clip rather than
emptying the project. The timeline rules (`split`, the trims, the
action-end refusal, `paste_attributes`), `recipe_graphic.rs` and the tools
are G2b's and G3's. Nothing a person sees exists yet.

**What landed.** `core/src/model_graphic.rs` (**399** of 400):
`GraphicProps` (`name`, `width`, `height`, `in`, `length`, `props`, every
key defaulted), `GRAPHIC_MIN_SIDE` 1 / `GRAPHIC_MAX_SIDE` 8192 /
`GRAPHIC_MAX_PROPS` 64 (restating the crate's `MAX_SIDE` and `MAX_KEYS`,
since G-2 forbids importing them), and the `pub(crate)` checks —
`check_name` (G-3), `check_side`, `check_schema` (the crate's eight
sentences, copied), `check_props` (by dotted path with a schema, shape
only without), `check_count` (on the map about to be STORED) and
`normalise_color` (G-12). `core/src/edit_graphic.rs` (**283**):
`add_graphic_clip`, every argument checked before `add_described_clip`
places it, and `set_graphic` with its patch reader. `Source::Graphic` and
`Clip.graphic` (after `shape`) in `model.rs`; the six exhaustive arms
(`source_size` answers `[width, height]`, `validate` refuses a stored name
that breaks G-3, the plan never gives a graphic a segment, `draws()` is
true, `recipe.rs` answers `missing` until G2b); `RC_FORMAT_VERSION` 10 in
`format.rs` and the header; `OP_COUNT` 59, the two rows (`width` and
`height` BOUNDED 1–8192, sourced from the constants), both ops allowed
inside a nest. App: `ClipSource.graphic` (so `ReelCore.swift`'s `?? .empty`
no longer empties a project holding one — opened over MCP from the
`schema_v10.rs` fixture, `get_project` answered one clip), its arms in
`TimelineView`, `TimelineLayout`, `InspectorPane` and `ClipKindStyle`
(`curlybraces`, shape's tint until G5), `ReelOps.addGraphicClipRaw` /
`setGraphicRaw`, and the two ops in `AgentServer.opsWithoutTools` with a
comment each naming G3 as the phase that deletes them. Spec §5.2, §6,
§7.10 and §11 G-3, G-4, G-12, G-13; `CONTEXT.md`'s **Props**.

**The props rules, as built.** A value is stored with `Map::insert` (an
existing key keeps its slot, a new one is appended) and a `null` removes
with `shift_remove`; under `preserve_order`, `Map::remove` is
`swap_remove` and would move the last key into the hole, and `Project ==`
cannot see an order change, so `core/tests/graphic.rs` reads the order off
the written text. The count is taken on the merged map, with or without a
schema, so 64 stored keys plus a one-key patch is `props has 65 keys; the
most is 64`, and the same patch with one `null` beside it applies at 64.
A colour is normalised from the four hex forms and `rgb()` / `rgba()` (3–4
components, commas, spaces or `/`, channels 0–255 or `%`, alpha 0–1 or
`%`); an opaque alpha is dropped, and a colour re-sent in another spelling
is an identity.

**Measured.** `cargo test --release`: 857 (836 + 21 new — `graphic.rs` 14,
`schema_v10.rs` 7); `make test` 955; `make lint` and `cargo fmt --check`
clean; `make typecheck` 0 errors and the 7 baseline warnings; `make app`
succeeded; the parity log clean and 77 tools. Made to fail once each:
`graphic.rs` (a range sentence reworded; `shift_remove` swapped for
`remove`, which failed the order test and the 64-key twin), `schema_v10.rs`
(`graphic` declared before `shape`: the key-order, round-trip and props
tests failed) and the parity check (`set_graphic` dropped from the
allow-list: `Reelcut: the core's op table has ops with no agent tool:
["set_graphic"]`).

**Deviations from the spec.** Four test files the spec did not list held a
literal the bump or the new key moved, and were changed to keep `make test`
green: `core/tests/model_tests.rs` (three more `"version": 9` literals and
the clip-defaults key list), `core/tests/common/commit_placement.rs` (the
nest clip's key list), `core/tests/evaluate_tests.rs` (a `Clip` literal) and
`edit_tests.rs`'s `remove_media` count (4 → 5, the other re-measured
`general()` count). `check_side` takes a `u64` rather than a `u32`, so a
patch's `5000000000` is named as sent.

**Owed from G2a.**
- `tools/proof/op_catalog_proof.py:282` (`len(ops) == 57 and ops <= tools`)
  FAILS from G2a until G3 adds the two tools and deletes the allow-list
  lines.
- `tools/proof/words_core_proof.py` hard-codes the format version (moved to
  11/10 by G2a) where it should read the header's `RC_FORMAT_VERSION`, as
  `phase9_proof.py:168-173` does.
- `core/src/edit_action.rs:106` removes an action end-patch key with
  `target.remove(key)`, the same `swap_remove` under `preserve_order` — a
  pre-existing, deterministic reorder of an opaque object, judged harmless
  in §10.4's G1d review paragraph ("One more consequence, found by G2a's
  adversary"); not changed here.
- Named CSS colours and `hsl()` in a `color` prop (with G1c's "named CSS
  colours").

#### G2b — the graphic's timeline rules and its recipe (2026-09-25)

Against baseline `986cf5a`: G-9's timeline arithmetic under `split`,
`trim_start`, `roll` and `trim_end`, G-10's refusal in `set_action_end`,
and the real layer source in place of `recipe.rs`'s `missing`
placeholder. Core only; the app still draws an unknown source kind as the
`missing` slate (`ProjectSnapshot.swift`'s default), so nothing a person
sees changes until G3's `LayerRenderersGraphic`.

**What landed.** `core/src/recipe_graphic.rs` (**129**, new, declared
`mod` in `lib.rs`): `effective_length` (`graphic.length`, or `in +
duration` when `null`), `graphic_advanced` (`in` through
`source_window.rs`'s `in_advanced` at speed 1, never below 0) and
`graphic_source`, the layer's `{kind, name, hash, frame, ctx, props}` and
`[width, height]` — `frame` floored onto the canvas grid,
`durationInFrames` ceiled, `progress` over `max(1, durationInFrames − 1)`
clamped, `ctx.canvas` the PROJECT's size inside a nest too, every float
through `evaluate::number`, `props` the stored map cloned whole, the hash
`content_hash` over `{name, frame, ctx, props}`. It holds the arithmetic
because the writers and the reader must share one equation and the two
natural homes stand at their caps (`model_graphic.rs` 399, `source_window.rs`
396). `recipe.rs`: one arm calling `graphic_source`, `missing_source`
`pub(crate)`, "graphic" in `layer_source`'s kind list (**596 → 596**).
`edit_split.rs`: the effective length measured on the ORIGINAL, the second
half's `in` advanced by the cut, BOTH halves' `length` pinned to it —
written once, so every splitter (`split_clips`, `split_under_playhead`,
`clear_range` and so the range cuts and `lift_range`, `insert_clip`,
`overwrite_clip`, `freeze_frame`) obeys it. `edit_clip_timing.rs`'s
`trim_start` and `edit_edge.rs`'s `roll` each call `graphic_advanced` on
the clip whose start moves; `trim_end` has no code (null follows the end, a
number stays). `edit_action.rs`: `GRAPHIC_NOT_A_TARGET` and
`graphic_not_a_target`, asked in `check_end_patch` and `check_off` BEFORE
the `END_GROUPS` lookup, so the answer is G-10's sentence rather than
`unknown key "graphic"`. Docs: `model_graphic.rs`'s `in` comment (`trim_start`,
`roll` and `split` own it; 399 unchanged), `edit.rs`'s six rows, spec §6's
six rows, §7.3 (the kind list, a graphic bullet, `source_size`, a graphic
layer in the example), §7.10 (a `recipe_graphic.rs` row; `recipe.rs`'s row
names it), and §11 G-6 to G-11 copied from §4, G-9 carrying G-9·a (no
head bound; `roll` is a front trim), G-9·b (the hash covers `ctx`) and
G-9·c (a null length is `in + duration`).

**The layer, as published** (`core/tests/fixtures/graphic_v10_recipe.json`,
from `graphic_v10.json` at t = 740000, 30 fps, `in` 0, `length` null,
duration 5000000):

```json
{ "kind": "graphic", "name": "lower-third", "hash": "3f58effee3657324", "frame": 37,
  "ctx": { "fps": 30.0, "time": 1.2333333333333334, "durationInFrames": 250,
           "progress": 0.14859437751004015, "width": 1920, "height": 1080,
           "canvas": { "width": 1920, "height": 1080 } },
  "props": { "title": "Kevin", "accent": "#2d7ff9" } }
```

The hash was printed by the first green run and then recomputed
independently — FNV-1a 64 over Python's `json.dumps(sort_keys=True)` of
`{name, frame, ctx, props}` — to the same `3f58effee3657324`.

**Measured.** `cargo test --release` in `core/`: **867** (857 + 10 new, all
in `graphic.rs`, now 24); `make test` **965** (955 + 10); `cargo test
--release --test edge` 16/16, untouched; `graphic_ffi`'s
`only_ffi_graphic_names_the_graphic_crate` passes; `cargo fmt --check` and
`make lint` clean; `make typecheck` 0 errors and the 7 baseline warnings;
`make app` succeeded; the parity grep on a fresh instance (port 4817)
printed nothing. `wc -l`: `recipe.rs` 596, `recipe_graphic.rs` 129,
`model_graphic.rs` 399, `edit_split.rs` 218 → 233, `edit_clip_timing.rs`
177 → 182, `edit_edge.rs` 203 → 207, `edit_action.rs` 451 → 469,
`edit.rs` 893 (row clauses only), `lib.rs` 95 → 96, `core/tests/graphic.rs`
399 → 755.

**Mutants, run by hand, each failing its named test:**
- (a) the split pin removed (both halves) — `split_advances_the_second_halfs_in_and_pins_both_lengths`,
  at the first half's stored `length` (`Null` for 3000000);
- (b) `trim_start` without `graphic_advanced` — `trim_start_advances_in_with_no_head_bound_and_trim_end_leaves_length_alone`
  (`in` 0 for 600000);
- (c) `roll` without `graphic_advanced` — `roll_advances_the_graphics_in_as_a_front_trim`
  (`in` 0 for 600000);
- (d) `effective_length` as `length.unwrap_or(clip.duration)` — three tests:
  `frame_and_ctx_follow_the_graphics_own_timeline` (150 for 180), the
  `trim_start` test (120 for 150) and the `roll` test (60 for 90);
- (e) the hash over `{name, frame, props}` only — `the_hash_follows_everything_render_is_called_with`
  (the `trim_end` hash equal) and `the_recipe_publishes_the_seams_shape`
  (hash `1eec510985f5a1f4` for the fixture's);
- (f) `graphic_not_a_target` not called — `an_action_end_naming_graphic_is_an_error_in_g10s_sentence`
  (`unknown key "graphic" in an action end patch`).

**Deviations from the spec.** `core/src/lib.rs` gained `mod recipe_graphic;`
(a new module must be declared; not in the spec's file list). The mutant
harness restored each file with `mv`, which left the last restored file
OLDER than the build and cargo reused the mutant-f build once; the next
run caught it (the action test failed on clean source), every source was
`touch`ed and every check in this record was re-run after that — the
mutant results stand, because each mutant's own build rewrote a file and
recompiled the crate from the files as they were.

**Owed from G2b.**
- `add_transition`'s handle form extends the incoming clip's HEAD leftward
  without moving `graphic.in` (`source_advanced` cannot reach
  `Clip.graphic`); it is `rebase_words`'s fourth caller and
  `graphic_advanced`'s missing one. Not fixed here (the spec's out of scope).
- A canvas rate change does not re-snap `graphic.in` / `length`
  (`frame_grid.rs`); `validate` does not refuse a graphic clip with no
  description (the recipe answers `missing` for it); keyframed props and
  `paste_attributes` for graphics are §7's.
- `core/CLAUDE.md` is not edited by this phase: its `recipe_graphic.rs`
  entry, the `edit_split.rs` / `edit_clip_timing.rs` / `edit_edge.rs`
  clauses and the `recipe.rs` bullet's mention are drafted in the
  pipeline's `04-impl-notes.md` for the orchestrator to land.
- Still owed from G2a: `op_catalog_proof.py:282` and `words_core_proof.py`'s
  version literal (G3's).
- `set_graphic`'s row (`edit.rs` and spec §6) and spec §5.2 glossed
  `length: null` as "the clip's duration"; under G-9·c it is `in +
  duration`. Reworded by the orchestrator after the review. (The root
  `CLAUDE.md` row this list also named had already been updated at G1d.)

**Review.** Passed first time, no blocker or should-fix. Its three nits,
kept and owed:
- `core/tests/graphic.rs:751`: the nest test cannot tell the project's
  canvas from the nest's, because `nest` freezes the nest's canvas at the
  project's current size — so "`ctx.canvas` is the PROJECT's inside a nest"
  is claimed but not proved. A test that changes the project canvas after
  nesting would prove it.
- `core/tests/graphic.rs:627`: `Value ==` ignores key order, so `ctx`'s wire
  key order is never checked (only `source`'s top level is, from the text).
- `core/tests/graphic.rs:459`: `graphic_starts`'s doc says it returns ids;
  it returns clip values.

The `core/CLAUDE.md` lines drafted above were written by the orchestrator
after the review.

#### G2 closed

G2 delivered §5g's model and its timeline: a graphic clip persists (format
version 10), is added and patched by two ops that check props against the
schema the op carries, is cut, trimmed and rolled along its own timeline
with one equation shared by the writers and the recipe, refuses to be an
action target, and publishes a layer whose `frame`, `ctx` and `hash` are
everything `render` is called with. What it does not do is DRAW: the app
still shows the `missing` slate for a graphic layer. G3, the picture
(§9: `GraphicStore`, the watcher, `LayerRenderersGraphic`, the error card,
`render_frame`'s diagnostics and the export gate, with the two op tools'
handlers landing minimally), is next.

### 10.6. G3 — the picture

G3 runs as three pipelines, each committed on its own: G3a the package's
`graphics/` folder, its store and its watcher; G3b drawing
(`GraphicRegistry`, `LayerRenderersGraphic`, the compositor case, the two op
tools); G3c failure and export (the error card, `render_frame`'s
diagnostics, the export pin, the missing-font warning).

#### G3a — the package's `graphics/` folder, its store and its watcher (2026-09-25)

Against baseline `b1f045e`: §5f's store and watch, §9a's G3 items 1 to 3,
and the decode of a clip's `graphic`. Nothing draws yet (G3b); nothing
observes the two notifications yet.

**Decided first.** G-14 (§4, and spec §11 before the code): `graphics/` is
created on the app's first write, never at open, and an empty untitled
root is not carried by the first save — so a package that never gets a
graphic is not touched. It amends G-3's last sentence: the untitled root is
`<NSTemporaryDirectory()>/Reelcut/<UUID>-graphics`, BESIDE the temporary
cache root, because `cacheWrapper()` would carry a child of the cache root
into `cache/`.

**What landed.**
- **The pure move, first and alone.** `importMedia`, `probeNext` and
  `commitImport` verbatim from `ProjectDocument.swift` to the new
  `ProjectDocument+Import.swift` (63), `present(_:)` internal; gated alone
  (`make typecheck` 0 errors and the 7 baseline warnings, `make app`
  succeeded) and saved as its own patch before any feature line.
  `ProjectDocument.swift` 1380 → 1329.
- **`GraphicStore.swift`** (399). Two modes, chosen on every pass by
  whether the folder exists: FOLDER (a source on `graphics/`, on each of
  `fonts/` and `assets/` that exists, and on each legal `*.js`) and PACKAGE
  (a saved package without `graphics/`: one source on the package
  directory, so an outside `mkdir` is seen). Every pass cancels and
  re-opens every source BY PATH, arms FIRST and then scans; events are
  coalesced over 100 ms into one pass. The queue owns the diff (`lastScan`,
  `folderPresent`, an outbox of outcomes) and main publishes the outcomes in
  order through `drain()`, setting `scan`, calling `folderDidAppear` once
  per observed absent → present, and posting `.graphicsDidChange` with the
  sorted names (every module, `library: true`, when the font and asset set
  moved). `stop()` bumps a generation under `queue.sync`, cancels the
  pending pass and every source and empties the outbox. The scan: a
  module's revision is CryptoKit's SHA-256 (G-13), a bad stem is warned in
  the core's sentence, a font is validated on a throwaway `GraphicLibrary`,
  a 0-byte asset is warned and skipped (an empty `Data` crosses as NULL),
  and `libraryVersion` hashes the fonts then the assets, name then bytes.
  `write(name:source:)` refuses a bad name in the core's sentence, calls
  `ensureFolder()` (the ONE creator inside a package), writes
  `<name>.js.partial` and moves it into place; `makeLibrary()` is a new
  builder every call (the bundled faces, then `fonts/`, then `assets/`).
- **`ProjectDocument+Graphics.swift`** (71): `graphicsWrapper()` — for a
  saved document a lazy wrapper over `<fileURL>/graphics` read directly,
  never through the store, so a document with no store cannot drop a saved
  folder; for an untitled one the store's root, only when it holds an
  entry — and `startGraphicStore()`, which seeds an untitled document's
  root from `autosavedContentsFileURL/graphics` and wires
  `folderDidAppear` to `packageContentsDidChangeOnDisk()` weakly.
- **`ProjectDocument.swift`** 1329 → 1336: the stored `graphicStore`, its
  re-point in the `fileURL` setter, `startGraphicStore()` in
  `makeWindowControllers()`, its stop in `close()`, and the whitelist line.
- **`ProjectSnapshot+Graphic.swift`** (88): `GraphicSnapshot` (every key
  defaulted, `in` through an explicit coding key) and `GraphicPropValue`;
  `ProjectSnapshot.swift` 2305 → 2309 for `ClipSnapshot.graphic`.
- Spec §5.6's package tree gains `graphics/`; spec §11 and §4 gain G-14.

**Measured.** `make test` 965 (unchanged; nothing in the core moved);
`make lint` clean; `make typecheck` 0 errors and the 7 baseline warnings;
`make app` succeeded; `tools/proof/harness/build.sh --force` built (88 s),
so every app file compiles with CryptoKit in the mix.
`graphics_store_probe.py` 17/17 (W1–W13, C1–C4); the three mutants each
exited 0 — `whitelist-removed` (C1's file ABSENT; C2 failed with it),
`no-file-sources` (W4 failed; W2, W10 and W11 with it, all in-place edits),
`strong-callback` (C4 failed, `closed_freed` true and `dropped_freed`
false). Every watcher post landed 0.10–0.11 s after its action.
`graphics_store_proof.py` 9/9 on its own instance (port 4851), the parity
grep empty; the autosave in place wrote `project.json` 15.1 s after the
edit. Made to fail by hand, twice, each reverted and rebuilt: the whitelist
line commented out, 3/9 with S3's `x.js` ABSENT after the save (S4–S7 and
S9 with it); and `folderDidAppear` set to nil, 8/9 with S3's save REFUSED —
"The document “P1.reelcut” could not be saved. The file has been changed
by another application." — which is the evidence that the observed
creation's date re-read, not luck, is what lets S3's save through.
`op_catalog_proof.py` still fails at its first check ("the core declares
59 ops and every one of them is a tool"), owed to G3b.

**Deviations from the spec.**
- **`TMPDIR` does not move `NSTemporaryDirectory()`** on this host
  (measured: it answers `DARWIN_USER_TEMP_DIR` whatever the variable says).
  The store keeps `NSTemporaryDirectory()`, the cache root's spelling, as
  the spec's interface says; the probe reports that directory and scores W1
  and C2 against it (and removes the roots it made), and the proof's S7
  lists `<getconf DARWIN_USER_TEMP_DIR>/Reelcut/*-graphics` before and
  after rather than a `<TMPDIR>` the app never used. Both still launch
  their child with `TMPDIR` set, as specified; it is inert.
- **C4 has two halves.** As specified — `startGraphicStore()`, `close()`,
  drop — C4 passes even with `[weak self]` removed, because `close()` sets
  `graphicStore = nil` and breaks the cycle, so the `strong-callback`
  mutant could not kill it. C4 also drops a second document WITHOUT
  closing it; that half is the one the mutant fails. Still one row.
- `ClipSource.graphic`'s doc said the `graphic` key was "not decoded yet";
  it now names `ClipSnapshot.graphic`, reworded inside its two lines.
- `GraphicStore.scan` is behind an `NSLock` (a computed property over a
  stored copy), because the spec allows `module(named:)` and
  `makeLibrary()` off main while making `scan` main-confined.
- A `running` flag beside `generation`, so a `rescan()` after `stop()` does
  not re-arm.
- `ensureFolder()` rescans only when it CREATED the folder; with the
  folder already there the watcher's own pass reports the write.

**Limits, recorded.**
- `fonts/` and `assets/` have folder sources only: an in-place rewrite of a
  font or an asset is seen at the next folder event or the next open.
- An untitled root is never deleted — after the first save, or when an
  untitled draft is closed — as the temporary cache root is not (§5f's
  out-of-scope list). `new_project {path}` makes one too, because the
  document is untitled until the save that follows.
- Nothing observes `.graphicsDidChange` or `.graphicsLocationDidChange`
  yet; G3b's registry and `Playback.refreshPausedFrame` will read `scan`
  after `start()` and observe the posts after that.
- The `DispatchQueue` the store creates is a new seam; `app/CLAUDE.md`'s
  list of documented seams names it only once the orchestrator lands the
  drafted sentences.

**Owed from G3a.**
- `op_catalog_proof.py:282` (G2a's) and `words_core_proof.py`'s version
  literal — G3b and later.
- `app/CLAUDE.md`'s entries for `GraphicStore.swift`,
  `ProjectDocument+Graphics.swift`, `ProjectDocument+Import.swift` and
  `ProjectSnapshot+Graphic.swift`, and the store's queue in the hygiene
  rule's seam list, were written by the orchestrator from the pipeline's
  drafts after the review.

**Review.** Passed first time, no blocker or should-fix; it read
`GraphicStore.swift` for races, leaked descriptors and re-arm-after-stop and
found none. Its four nits, owed:
- `ProjectDocument+Graphics.swift:44-45`: "the untitled root holds an
  entry" counts hidden files the scan skips, so a root holding only a
  `.DS_Store` would be carried into the first save (against G-14).
- `GraphicStore.swift:338-347`: every pass, even one module's edit,
  re-reads and re-validates every font through the FFI. **G3b must know**:
  its registry rebuilds on `.graphicsDidChange`; fonts should be
  re-validated only when the font set's bytes moved (`library: true`).
- `GraphicStore.swift:251-260`: `drain()` is not re-entrant — an observer
  that calls `rescan()` from inside the notification publishes newer
  results before older ones. Nothing observes it in G3a; **G3b's registry
  must not call `rescan()` from the observer** (or `drain()` must be made
  re-entrant first).
- `GraphicStore.swift:223-228`: a failed move in `write()` leaves
  `<name>.js.partial` in `graphics/`, which every later save carries.

#### G3b — a graphic clip drawn (2026-09-25)

Against baseline `7bf518c`: §5d's rendering, §5f's registry paragraph, G-7,
G-4's render-time leniency, G-13's "preview follows the newest revision"
and §5h's two OP tools. Failure still draws the `missing` slate — the error
card, `render_frame`'s diagnostics and the export pin are G3c's.

**What landed.**
- **The core hands the engine its own JSON text.** `recipe_graphic.rs`
  (129 → 133): `graphic_source` publishes `props_json` and `ctx_json` after
  `props`, each `serde_json::to_string` of the same `Value`; `hash` is
  unchanged (still over `{name, frame, ctx, props}`). The fixture
  `graphic_v10_recipe.json` carries both; `core/tests/graphic.rs`'s seam
  test lists them, and a new test parses each back equal to its object with
  `accent_color` kept as written. The engine takes JSON TEXT
  (`GraphicModule.svg(frame:propsJSON:ctxJSON:budgetMs:)`), so the app has
  no Swift mirror of `ctx` and re-encodes nothing; the engine's overlay of
  defaults and its stale-key and wrong-type warnings stay inside
  `rc_graphic_svg`. **The snake-case hazard was measured ABSENT**: the
  reviewer's scratch decode on Swift 6.2.3 / Darwin 25.5 of
  `{"props":{"accent_color":1}}` through `.convertFromSnakeCase`, as
  `[String: Int]` and as a `GraphicPropValue`-shaped enum, nested included,
  kept the key (and `.convertToSnakeCase` leaves `accentColor` alone), which
  matches `app/CLAUDE.md`'s note; `GraphicSnapshot.props` is correct and
  nothing about it is owed.
- **`RecipeSourceRef.graphic(name:hash:frame:propsJSON:ctxJSON:)`**:
  `ProjectSnapshot.swift` 2309 → 2313 (the case, one decode and one encode
  dispatch line, the `cacheHash` arm); the bodies and `GraphicSourceKeys` —
  a second keyed container on the same decoder, `CodingKeys` being private —
  in `ProjectSnapshot+Graphic.swift` (88 → 130). `measuredSize` answers
  `source_size` for it.
- **`GraphicRegistry.swift`** (183): a `RecipeSource` key → one immutable
  `GraphicSet` (the library, the store's `libraryVersion`, and each module
  `.compiled(module, revision, meta, schema)` or `.failed(diagnostics,
  revision)`). `install` builds one library through `makeLibrary()` and
  compiles every module of `store.scan` at a 250 ms budget; `update` builds
  a NEW library and recompiles everything only when `library` is true, and
  otherwise compiles only the named modules against the existing library (a
  frozen library still compiles; only adds are refused), dropping a name the
  scan no longer holds; either way a new set is swapped in under the lock.
  `resolve(key)` is the one cross-thread read: a document's own key answers
  its set at the 250 ms preview budget; any other key answers the set of the
  document whose `RecipeSource` handle is `===` the handle published under
  it, at the 2000 ms offline budget (`ReverseSource`'s handle-match
  precedent); else nil. Nothing calls `rescan()`.
- **`LayerRenderersGraphic.swift`** (78): `resolve` → the `.compiled`
  module → `svg` → the texture key `"graphic:" + hex(SHA-256(svg)) + ":" +
  "WxH" + ":" + libraryVersion` → `cached(key, graphic: true)` (made
  internal, with `device`) → `rasterize` at the layer's `source_size` →
  `upload`, a `.bgra8Unorm` texture of the raster's own size. Any throw or
  miss answers nil. **Graphic textures have their own LRU pool of six**
  (`LayerRenderers.graphicCacheLimit`, 467 → 492 lines, the cache now a
  `Pool` struct): an animated graphic mints a new full-layer texture every
  frame (~8 MB at 1080p, ~33 MB at 4K), which in the shared 64-entry pool
  would have evicted every text and shape texture and held ~2 GB at 4K; a
  held or static graphic still hits. Taken from the review's nit 3; resident
  memory during playback is still unmeasured (owed below).
  `Compositor.swift` 1391 → 1396: the `case .graphic`, which slates on nil.
- **The document and the editor.** `ProjectDocument+Graphics.swift` (71 →
  111): `startGraphicStore()` installs the registry after `store.start()`
  and observes the store's `.graphicsDidChange`; the observer updates the
  registry and THEN posts the new `.projectGraphicsDidChange` (object: the
  document, the store's two `userInfo` keys passed through);
  `stopGraphicStore()` removes the observer, drops the set, stops the store.
  `ProjectDocument.swift` 1336 → 1335 (`close()`). The frozen editor takes
  one `addObserver` (1124 → 1127); `EditorViewController+Graphics.swift`
  (16) refreshes the paused frame for its own document.
- **The two op tools** (77 → 79 tools; the core's 59 ops all have one).
  `AgentServer+Graphics.swift` (138): `add_graphic_clip` refuses a module
  the folder does not hold ("No module named "x" in graphics/ — the folder
  holds: …"), one that did not compile (its first diagnostic and line), a
  `width`/`height` outside 1–8192 by name, and a `meta.durationInFrames`,
  `meta.width` or `meta.height` that is not a whole number in range by name;
  it defaults `duration` to `meta.durationInFrames` at the canvas rate — read
  only when the caller passed no `duration`, so an explicit one is never
  refused for a bad meta value (the review's finding 1) — and
  `width`/`height` to meta's, and sends the module's `schema`.
  `set_graphic` sends the schema of the patch's `name`, else of the one
  module every clip shares (two different ones refused naming both), when
  the patch carries `props` or `name`. Neither handler reads `a["schema"]`;
  both name "none yet — G5's Graphic sub-tab (§5j)" as their UI path.
  `AgentCatalog+Graphics.swift` (60), spliced right after the transition
  rows. `AgentCatalog+Declarations.swift`: `Requirement.filledByTheApp`,
  which `declaredInput` omits from `properties` and `required`, and two rows
  (`schema` of each op, G-4); the parity check's `expectedArguments`
  subtracts such an argument. `AgentServer.swift` (frozen, 790 → 788): two
  `handlers` rows, `opsWithoutTools` empty.

**Measured.** `cargo fmt --check` clean; `make test` 0 failed — 868 in the
core (one new) and 98 in `graphic/`, 966 in all; `make lint` clean;
`make typecheck` 0 errors and exactly the 7 baseline warning locations;
`make app` succeeded; the parity grep empty on every launch.
`op_catalog_proof.py` 23/23 (failing its first check since G2a until now);
`op_argument_proof.py` 138/138; `graphics_proof.py` 14/14 on its own
instance (port 4879): P1–P3, S1, R1, H1, L1, F1, K1, K2, T1, K3, A1, Z1. F1
MEASURED, not scored: 0 of 2 073 600 pixels of the app's frame 30 differ
from `graphics_ffi_probe.py`'s frame-30 BGRA over black, max channel delta
0. **Made to fail**: `--mutant frame-plus-one` (a COPY of `app/` with the
one anchor in `LayerRenderersGraphic.swift` asserted and replaced by
`frame: frame + 1`, built with xcodegen and xcodebuild into its own
directory) held P1 and FAILED P2 — (122,50) read (0,0,0) and (222,50) read
(255,90,54), the rect one frame on; the real app was never mutated.

**Where `resolve` answers nil, so the layer draws the slate — owed to
G3c's revision pin (G-13).** `RecipeSource.shared.project(for: D)` is what
the document last published (`editedProject`); `render_frame` and Save Frame
pass `editedProject` and an export passes `document.project`, equal handles
while no nest is open. Nil, therefore:
- (a) an export with a nest open;
- (b) the eyedropper's suppression handle
  (`EditorViewController+Eyedropper.swift:191`);
- (c) a QUEUED export, or any export that outlives an edit, undo or close of
  its document — the job keeps the handle it captured
  (`ExportSheetController.swift:384-386`) while the document publishes a new
  one, so the match fails for every remaining frame. `ReverseSource.pin`
  exists for exactly this; G3b adds no analogue.

**Deviations from the spec.**
- `op_argument_proof.py` needed more than its two constants: it had also
  been failing since G2a, and `schema` not being published broke three of
  its sections. Section 2 counts a `filledByTheApp` row as used when the
  tool OMITS the argument; section 3 leaves such an argument out of what a
  tool takes; section 4 counts 13 opaque doors and reaches the two graphic
  ones by moving a `proof.js` into the untitled fixture's graphics root and
  pointing `set_graphic` at the clip `add_graphic_clip` lands from it. The
  probe's `requirement()` switch gained the case, as `op_catalog_proof.py`'s
  did.
- Spec §7.10 is the RUST module map; the rows for `GraphicRegistry.swift`
  and `LayerRenderersGraphic.swift` went into §7.4, the Swift file map, and
  §7.10's `recipe_graphic.rs` row names the two keys.
- Count prose beyond the spec's list, each because the sentence became
  false: `AgentCatalog+Declarations.swift` "every argument but six" → eight
  and "six kinds of difference" → seven; `AgentServer+Parity.swift`'s
  "all fourteen rows" → sixteen;
  `AgentCatalog.swift`'s list of `opTool`'s callers gained "the two
  graphics".
- `install` answers a library `makeLibrary()` could not build by marking
  every module `.failed` with that sentence (on an empty library), rather
  than leaving the key without a set. That set carries `libraryFailed`, and
  `update` rebuilds it whole through `install` rather than compiling a named
  module against the empty stand-in (the review's nit 2: one module would
  otherwise have drawn with no fonts and lost the failure sentence).
- `stopGraphicStore()` removes the observer before it stops the store.
- S1 undoes its `split`, so R1 onwards act on one clip.
- `graphics_proof.py` reads PNG pixels with `e1_proof.py`'s decoder stopped
  after the needed row, so a 5 s poll is not spent decoding; `ffmpeg`'s
  rawvideo is read through `subprocess.run` with a timeout, since
  `bounded.run` is text-mode.

**Numerals left, whose referent is not the tool or op count.**
`AgentCatalog+Files.swift:120` ("some seventy literals");
`op_argument_proof.py`'s "fifty-eight handlers" and `op_catalog_proof.py`'s
"the last fourteen tools" (D3·4's migrated set).

**Owed from G3b.**
- The three comment numerals in the frozen `AgentServer.swift` (`:49`
  "fifty-eight handlers", `:189` and `:193` "seventy-seven", `:194`
  "fifty-seven") — frozen-file rule: wiring only.
- The slate cases (a), (b) and (c) above → G3c's revision pin (G-13).
- `words_core_proof.py`'s version literal (G2a); `add_transition`'s handle
  form (G2b).
- `core/CLAUDE.md:131` and `app/CLAUDE.md:31, 897, 924` still say
  fifty-seven / seventy-seven, and `app/CLAUDE.md` has no entries yet for
  `GraphicRegistry.swift`, `LayerRenderersGraphic.swift`,
  `AgentServer+Graphics.swift`, `AgentCatalog+Graphics.swift`,
  `EditorViewController+Graphics.swift` or `.filledByTheApp` — the
  pipeline drafted the sentences for the orchestrator.
- G3c: the error card (G-8), `render_frame`'s diagnostics block, the export
  compile gate and revision pin, the missing-font warning, the Sandbox and
  Failure proof rows, the playback check (remaining §4) — which should
  also read resident memory while an animated graphic plays, the one
  number the six-entry graphic texture pool was sized without. G4/G5: the six
  app-state tools, `get_project`'s `graphics` block, the Graphic sub-tab,
  typed builders in `ReelOps.swift`.

#### G3c — failure and export: the error card, `render_frame`'s diagnostics, the export gate and pin (2026-09-25)

Against baseline `b29d981`: G-8 (the error card, the reply, the gate and the
abort), G-13's export pin, §9a's G3 items 4 and 5, and G3b's three slate
cases (a)–(c), which the pin retires.

**What landed.**
- **The toll, first and alone.** `Exporter.ExportError` moved verbatim to the
  new `ExporterErrors.swift` as `extension Exporter { enum ExportError … }`:
  `Exporter.swift` **609 → 539**, `ExporterErrors.swift` **74**; gated alone
  (`make typecheck` 0 errors and the 7 baseline warnings, `make app`
  built). Then two cases: `.graphicsNotCompiled([(name, message)])` —
  "The export was not started: the graphic "x" does not compile — <m>; the
  graphic "y" has no module in graphics/. Fix the module and export again."
  — and `.graphicFailed(name:frame:message:)` — "The export was stopped at
  frame N of the graphic "x": <m>. No file was written."
- **The pin replaces the handle match** (`GraphicRegistry.swift` 183 →
  263). `snapshot(for:)` is a document's set; `pin(set, for: key)` opens a
  `Pin {set, failure, warnings}` on an offline key and `unpin` drops it;
  `resolve` answers a document's own key at 250 ms, a PINNED key at
  2000 ms, and anything else nil — the slate. `record` keeps a failure only
  in the pin's `failure` slot, first one wins for the pin's life, and a
  warning in a list of at most 64 distinct ones, so a graphic that warns on
  every frame can never hide a later failure; `reports(for:)` is the
  failure first, then the warnings. A pin is a RETAIN of an immutable set,
  not a recompile; it outlives `remove(recipeKey)`.
- **Every offline door passes the set**, captured on main from
  `document.recipeKey` (never a scoped handle): `render_frame` and `export`
  inside their `onMain` blocks, the export sheet and Add to Queue
  (`Job.graphics`, captured at ENQUEUE — the queue type doc's "anything
  else the picture depends on … joins that list"), Save Frame, and the
  eyedropper. `Exporter.export(… graphics:)` pins on its key and unpins in
  `finish` and in `deinit` (the build and `startWriting` hold `self`
  weakly, so a released exporter never reaches `finish`);
  `renderFrameReported` pins on its own key and `defer`s the unpin after
  reading the reports; GIF and APNG go through it per frame.
- **The error card** (`LayerRenderersGraphic.swift` 78 → 195): the layer
  is nil only with no set or a failed upload. No module of the name, a
  module that did not compile, an `svg` throw or timeout, a `rasterize`
  throw — each draws `errorCard(text:size:)`: sRGB (64,8,8), a 2-pixel
  (230,40,40) border, and `<name> · frame <N>` (or `· does not compile`),
  the message and `line L, column C` in white `DS.mono(max(11, min(w,h) /
  28))` through a `CTFramesetter` inset by three times its point size,
  keyed `graphic-error:<sha256(text)>:WxH` in the graphic pool — so a
  failed frame never serves the last good frame's texture. Each failure and
  warning is RECORDED on the recipe key (a no-op for a preview key); a
  raster's warnings ride in `LayerRenderers.Rendered.warnings` (one new
  field) and are reported from the returned value on every call, so a pool
  hit still warns.
- **`render_frame`'s reply**: one sentence per report before the last —
  `Graphic "x" failed at frame N: <m> (line L, column C).`, `… warned at
  frame N: …`, `… does not compile: …` — and still `isError: false`; the
  last sentence stays ` Written to <path>.`. §9a item 4's missing-font
  warning arrives this way: "font-family "Nope Sans" is not in the font
  set; the set has: Anton, Bebas Neue, Darker Grotesque, IBM Plex Mono,
  Montserrat, Source Sans 3".
- **The gate and the abort** (`ExporterGraphics.swift`, 95, new).
  `graphicsRefusal` runs on `buildQueue` BEFORE the build and flows through
  `startWriting`'s `.failure` arm, so an existing file at the destination
  is untouched: every top-level graphic clip overlapping the range, plus
  every graphic clip of each nest a clip in the range shows (the whole
  nest, over-inclusive by decision), nothing for an audio-only row. A frame
  that fails mid-export records the failure; `pollProgress` sees it on
  main and cancels; `finish` — before anything else — removes the file and
  answers `.graphicFailed`, whatever the pipeline said.
- **Two catalog sentences** (`AgentCatalog+Files.swift`), prose only.

**The crash the abort found, and the Cancel button shared.** The first
proof run lost the app at E1's export. Both crash reports carry the same two
stacks: on `com.kgalligan.reelcut.export.video`, `ExportWriter.pump` →
`-[AVAssetReaderOutput copyNextSampleBuffer]` →
`CMVideoFormatDescriptionMatchesImageBuffer` → `CFDictionaryGetValue`,
EXC_BREAKPOINT; on main, `Exporter.pollProgress` → `Exporter.cancel` →
`ExportWriter.cancel` → `-[AVAssetReader cancelReading]` →
`_tearDownFigAssetReader`, releasing. `ExportWriter.cancel()` had cancelled
the reader from main while a pump was inside a copy — and that is the path
the export sheet's and the queue's Cancel buttons had taken since road map
2's phase 7; the abort only made it frequent. `ExportWriter.stopped(with:)`
did the same from one pump's queue under another's copy. **The fix**
(`ExporterWriter.swift`, 1114 → 1096, so no toll): `cancel()` sets the flag
the pumps already test before each sample and nothing else; `stopped` only
records the failure; `allInputsFinished` — which runs on main from the
pumps' `DispatchGroup` once every pump has left its loop — cancels the
reader, then the writer (which removes the part-file), then reports.
`started`, whose only job was to keep `cancelReading` away from an unstarted
reader, went with its paragraph; `start` still refuses a cancel that came
first. The cost: a pump blocked on a slow read finishes that one sample
before it stops — measured at 0.1–0.3 s from a cancel to the completion on
a 4K graphic export.

| Row | Before the fix (CONTROL) | After |
|---|---|---|
| Failing exports over MCP (a project with `bar` plus `throw10` on a front track, `export h264`, the app relaunched after each crash) | 40 exports: **16 crashed**, 24 stopped cleanly | 40 exports: **0 crashed**, 40 stopped naming `"throw10"` and `frame 10`, no file |
| Mid-export cancels through `Exporter.cancel()` (an in-process probe; a 4K canvas with `title-card` and a 3840 × 2160 `kinetic-type`, 10 s, `h264`, 12.8 s to export whole; the cancel at a random 0.5–8 s) | 30 cancels: **12 crashed**, same stack | 30 cancels: **0 crashed**, 30 answered "cancelled" with no file |

(An earlier, shorter reproduction put the failing-export rate at 1 in 7;
the 40-export CONTROL above is the one recorded. The two loops are scratch
instruments, not in the tree — kept with their outputs in the pipeline's
handoff, `~/.claude/litecode/reelcut/graphics-g3c-failure-export/instruments/`;
the cancel probe is `graphics_pin_probe.swift`'s build line with a
`main.swift` that cancels on a timer.)

**Measured.** `make test` 966 passed, 0 failed; `make lint` clean; `make
typecheck` 0 errors and exactly the 7 baseline warning locations (the
`copyCGImage` one still in `Exporter.swift`, now line 566); `make app`
built. `graphics_proof.py --port 4881` **21/21**: P1…A1 as in G3b; E1 frame
10's reply `Graphic "throw10" failed at frame 10: Error: boom at ten (line
3, column 31).`, (1,540) (230,40,40), (1900,1060) (64,8,8), the export
stopped and no file; E2 `render_frame` in 2.04 s, "over the 2000 ms budget
at frame 0", `get_project` at once; E3 the Nope Sans warning above; E4
(255,90,55); Q1 and Q2 pinned (255,90,55) and (0,0,0), unpinned (25,28,33)
— the slate; Q3 both answers warn and the texture is the same object; Z1
empty. `--mutant frame-plus-one` exit 0 (P1 held, P2 failed). **Made to
fail by hand**, each reverted and rebuilt: (a) `finish`'s mapping line
deleted — E1 alone fell, the export answering "The export was cancelled."
(20/21); (b) the `pin` line in `Exporter.export` deleted — E4, Q1 and Q2
fell to the slate's (25,28,33), and A1 (the slate is opaque) and E1 (the
export succeeded with a slate for the card) fell with them (16/21).
`phase7_chrome.py`, whose queue section cancels a job mid-write, was
re-run against the fix: **78/78**, the cancelled job's half-written file
removed and the next job run.

**Measured, not raced: a module swap cannot be observed over MCP.** The
core's agent server is one `tiny_http` thread and `export` holds it on a
semaphore until the file is written, so no second call can land while an
export runs. E4 therefore proves only that the `export` tool passes the
document's set (an unpinned offline key slates), and the swap is Q1's and
Q2's, made deterministic in-process: `stopGraphicStore()` removes the
document's set synchronously after the job is enqueued and before the run
loop turns, and the file still draws the set it was handed.

**Deviations from the spec.**
- `ExporterWriter.swift` was out of scope in the spec; the orchestrator
  brought it in for the cancel fix alone (the decision record is the
  pipeline's `04b-orchestrator-decision.md`). It shrank, so no pure move.
- E1 checks that frame 9 names no `Graphic "throw10"`, not no graphic at
  all: P1's `bar` clip keeps the `color` prop L1 stored after its schema
  dropped it, and its "props.color is not in the schema; it is passed
  through" warning on every frame is G-4's leniency, correct.
- E1 checks the exact destination path: AVFoundation's `<path>.sb-<hex>-…`
  temporary sits beside a cancelled `.mp4` for a moment and is not the
  file.
- A MISSING module's report carries the frame ("failed at frame N: No
  module named "x" in graphics/"); only a module that did not compile has
  frame nil.
- The gate's clause text is carried in each entry ("has no module in
  graphics/", "does not compile — <m (line L, column C)>"), and a
  `.graphicFailed` with no frame reads "…the graphic "x" does not compile —
  <m>. No file was written."
- A warned report with several diagnostics is one sentence, the messages
  joined by "; ".
- The E rows share one FRONT track added to P1, so each row's clip draws
  over `bar`; P1 is reopened with `open_project` since K3's relaunch
  closed it.

**Owed from G3c.**
- The export-cancel crash fix is on `svg-motion` only; `main` still has the
  crash (12 of 30 expensive Cancels). Filed as kpgalligan/reelcut#38 for
  the user's decision on cherry-picking the `ExporterWriter.swift` hunk.
- The gate walks ONE nest level; a graphic in a nest inside a nest is
  caught by the mid-export abort instead of the gate.
- `Exporter.cancel()` still cancels the loudness MEASUREMENT's reader from
  main while `buildQueue` may be inside its `copyNextSampleBuffer`
  (`ExporterLoudness.swift`). It is an audio-mix reader with no compositor
  and was not seen to crash, but it is the same shape as the race fixed
  above; unmeasured.
- A successful export's warnings are recorded and dropped at `unpin`: no
  channel reports them, and the clip's own surface for a warning is G5's
  Graphic sub-tab (§9a item 4's second half).
- The playback check, now `designs/reelcut-remaining.md` §4's first
  bullet.
- (Review nit.) A `copyNextSampleBuffer` that never returns — a pump
  starved because the other pump stopped reading — can no longer be woken
  by a cancel, since `cancel()` only sets the flag; the completion would
  then never fire, so an MCP `export` would hold the server's one thread
  and a queue would stall. Not seen in 70 runs; the doc at
  `ExporterWriter.swift`'s `cancel()` says so.
- G3b's list: the frozen `AgentServer.swift`'s numerals,
  `words_core_proof.py`'s version literal, `add_transition`'s handle form,
  and the `app/CLAUDE.md` entries below.

**Drafted for app/CLAUDE.md**, landed by the orchestrator after the
review (which passed first time, no blocker or should-fix; its nits: the
hung-pump case above, a stale comment in `ExporterImageSequence.swift`
reworded, and the loudness reader already owed).
- `GraphicRegistry.swift` · `LayerRenderersGraphic.swift` (replacing the
  entry's `resolve` and failure sentences): "`resolve` is the one
  cross-thread read of the set: a document's own key at the 250 ms preview
  budget, a PINNED offline key at 2 s, else nil — the slate. **An offline
  key draws only what its caller pinned** (`pin(set, for: key)` with the
  document's `snapshot(for: recipeKey)`, captured on main): every
  `pin` has its `unpin` — `Exporter.finish` AND `deinit`, and
  `renderFrameReported`'s `defer`. A pin also keeps its REPORTS: the first
  failure in a slot of its own for the pin's life, then at most 64 distinct
  warnings, so a warning can never displace a failure. A graphic that fails
  — no module, not compiled, a throw or timeout, a refused raster — draws
  its ERROR CARD, keyed by its own text in the graphic pool, never the last
  good frame; a raster's warnings ride in `Rendered.warnings` so a pool hit
  still reports them. Only no set and a failed upload are nil."
- `Exporter.swift` · `ExporterErrors.swift` · `ExporterGraphics.swift`
  (added to the export entry): "`ExportError` is `ExporterErrors.swift`'s.
  An export PINS the `GraphicSet` it was handed for its whole life, GATES
  it before the build (`ExporterGraphics.graphicsRefusal`: a graphic clip
  in the range, or in a nest a clip in the range shows, whose module did
  not compile or is missing, refuses before the destination is touched),
  and ABORTS on a recorded failure: `pollProgress` cancels and `finish`
  removes the file and answers `.graphicFailed`, whatever the pipeline
  said. **`ExportWriter.cancel()` only sets the flag**; the reader and the
  writer are cancelled in `allInputsFinished`, after every pump has left
  its loop — cancelling the reader under a running `copyNextSampleBuffer`
  crashed the process (road map 10 §10.6 G3c). Never call `cancelReading`
  from another thread while a pump runs."
- `ExportQueueController.swift` (added): "`mediaURLs()` AND the document's
  compiled graphics (`Job.graphics`) are captured at ENQUEUE."

#### G3 closed — what it delivered against §9a

G3 (G3a–G3c, 2026-09-25) is BUILT. §9a's G3 checklist, item by item:
1. One `DispatchSource` per module file plus one on the folder — BUILT
   (G3a): `GraphicStore.swift`.
2. `packageContentsDidChangeOnDisk()` after CREATING `graphics/`, not per
   event — BUILT (G3a): `folderDidAppear`, `ensureFolder()` the one
   creator.
3. The package rows against `graphics/` itself — BUILT (G3a):
   `graphics_store_proof.py`.
4. The G-6 missing-font warning in `render_frame`'s reply — BUILT (G3c):
   E3 names the family and the set. On the CLIP it is not shown: the clip
   has no surface for it until G5's Graphic sub-tab.
5. The person's playback check, 4K `title-card` included — WRITTEN, not
   run: `designs/reelcut-remaining.md` §4's first bullet, with the memory
   reading the six-entry pool was sized without. If it stutters, G6 is
   owed.

**G4 (the six app-state tools, §5h) is next.** After G4 the feature works
end to end for an agent, and merging `svg-motion` into `main` is the
user's decision (§9a).

### 10.7. G4 — the agent

§9's G4 is split in two: **G4a** the write/read loop and the reference
(below), and **G4b** `render_graphic`, `import_graphic_font`,
`import_graphic_asset`, §5l's Contact-sheet and Placement rows and the loop
end to end (below). Both are built; G4's closing paragraph follows G4b. The
Help menu item is G5's.

#### G4a — `write_graphic`, `get_graphic`, `graphic_reference`, and the reference in three places (2026-09-25)

Against baseline `7ff17ce`, branch `svg-motion`.

**What landed.**
- **The toll, first and alone.** `GraphicModuleFile`, `GraphicFile` and
  `GraphicScan` moved verbatim out of `GraphicStore.swift` (399 of the 400
  cap) into the new `GraphicScan.swift` (32 lines): `GraphicStore.swift`
  **399 → 373**; gated alone — `make typecheck` 0 errors and the 7 baseline
  warnings, `make app` built, `graphics_store_probe.py` 17/17 — and saved
  as its own patch before any feature line. With the three `writeManual()`
  calls it ends at **376**.
- **Three app-state tools** (`AgentServer+Graphics.swift` 138 → 296,
  `AgentCatalog+Graphics.swift` 60 → 112, three `tool(...)` rows after the
  two `opTool` rows, so the catalog's last eleven are unchanged).
  `write_graphic {name, source}` — `target` → the two strings → the store's
  one writer (`write(name:source:)`; a bad name is its
  `GraphicStore.nameSentence`, the core's words) → `rescan()`, synchronous,
  so the document's `.graphicsDidChange` observer has recompiled THAT text
  in `GraphicRegistry` before the reply is built → `{ok, name, path,
  revision, meta, schema, diagnostics, clips, note}`. A module that does not
  compile is `ok: false` with `meta {}`, `schema {}` and the engine's
  diagnostics, and is NOT an error. Not undoable, never dirty (G-3); the
  note says so. `get_graphic {name?}` — one module (`source` added) or, with
  no name, `{folder, folder_exists, modules}`, `folder` being where
  `graphics/` is or WILL be. `graphic_reference {}` — the bundled
  `GraphicsAPI.md` verbatim; it never calls `target(a)`, so it answers on a
  fresh launch with only the welcome window up. All three run on main.
  `compiledModule`'s "No module named …" sentence is hoisted into
  `noModuleSentence` so `get_graphic` speaks it too.
- **`get_project` gains `graphics: [{name, revision, ok, clips}]`**, always
  present (`graphicsSummary`; `[]` with no store). `clips` are the ascending
  ids of every clip, the timeline's and every nest's, drawn by the module.
- **The reference in three places.** `docs/graphics-api.d.ts` (212 lines,
  NEW, G-11): global declarations — `Ctx`, `Meta`, `SchemaEntry`/`Schema`,
  `Font`, `TextMetrics`, `declare const Easing` with `linear`, `bezier` and
  the 21 named eases, and a `declare function` per standard-library
  function — checked by `graphic/tests/reference.rs`'s new
  `the_typings_declare_every_standard_library_function` (every stdlib name
  from `stdlib.js`/`noise.js` declared, `Easing`, the seven `ctx` keys, no
  line starting `import ` or `export `; made to fail by renaming `asset`'s
  declaration). `docs/graphics-api.md` gains "## Working over MCP", eight
  lines, no fence (389 → 399). `project.yml`'s post-build script copies both
  into `Contents/Resources` as `GraphicsAPI.md` and `GraphicsAPI.d.ts`;
  `codesign --verify --deep --strict` passes on the built app.
  `GraphicStore+Manual.swift` (53 lines, NEW) writes them into an EXISTING
  `graphics/` as `API.md` and `API.d.ts` — at `start()` for a saved package,
  in `ensureFolder()` after creating it, and in `write()` — each only when
  its bytes differ, and never creates the folder (G-14).
- **`holdsContent` replaces `!entries.isEmpty`** in `graphicsWrapper()`'s
  untitled branch: any non-hidden entry, file or directory, that is not
  `API.md`/`API.d.ts`. A root holding only `fonts/` or `assets/` is still
  carried (row G8), a root holding only the manual is not, and — as a side
  effect — G3a's review nit is FIXED: a root holding only a `.DS_Store` is
  no longer carried into the first save.
- **Counts**: 82 tools (59 op + 23 app-state); the gate, the catalog prose,
  spec §7.9, `op_argument_proof.py`'s `TOOLS = 82`, and the three
  `APP_STATE_TOOLS` sets (`phase9_proof.py`, `recording_proof.py`,
  `recording_probe.py`) with their "twenty-three" labels.

**Measured.** `make test` core 868 + graphic 99, 0 failed; `make lint`
and both `cargo fmt --check` clean; `make typecheck` 0 errors and the 7
baseline warnings; `make app` built. `graphics_proof.py --port 4883`
**29/29** (the G3 rows unchanged); `--mutant frame-plus-one` caught (P1
held, P2 failed). On a fresh 4823 instance: `op_catalog_proof.py` 23/23,
`op_argument_proof.py` 141/141 (EXACTLY 82 tools, 23 of them app-state),
`phase9_proof.py` 218/218, `recording_proof.py` 186/187 — the one FAIL is
the known Bluetooth-INPUT head-loss row (`designs/reelcut-remaining.md`
§4), two tone rows skipped by name; `recording_probe.py --only catalog`
28/28; the parity grep empty on every launch. `graphics_store_probe.py`
17/17 on the final tree. From G1: the broken module's diagnostic is
`SyntaxError: unexpected token in expression: ';'` at line 2 (column 32,
not asserted).

**The rows** (`graphics_proof.py`, now 29): G6 first, before any project
is open — `graphic_reference` equals `docs/graphics-api.md` and the app's
`GraphicsAPI.md`; G1–G5 and G7 after A1 on their own packages WG and NG;
G8 on a fresh instance after them, before E1. `tools/proof/README.md`'s
G4a section has each row.

**Made to fail by hand (2026-09-25)**, each reverted and rebuilt:
- (a) `store.rescan()` deleted from `writeGraphic`: G1–G4 fell (25/29).
  Without it the store's scan does not yet hold the file the handler just
  wrote, so every write answered `No module named "bar" in graphics/ — the
  folder holds: nothing`, and G2's listing and G3's add, made within the
  watcher's ~100 ms coalesce, saw nothing either. A side diagnostic on the
  same mutant build showed the watcher itself catching up within 0.5 s of
  a lone write — the rescan is what makes the REPLY current, as §5h asks.
- (b) `writeManual()` deleted from `write()` and `ensureFolder()`: G2 fell
  alone (28/29), `API.md`/`API.d.ts` absent.
- (c) `holdsContent` counting regular files only: G8 fell alone (28/29) —
  the untitled root holding only `fonts/` was not carried, and
  `NF/graphics` did not exist after the save.

**Deviations from the spec.**
- G1 compares `schema`'s keys SORTED (`["color", "title"]`): a JSON object
  from `JSONSerialization` has no key order, so `["title", "color"]` in
  order was not a claim the reply can make.
- G4 also asserts the reply's `revision` is the blue source's hashlib
  digest and its `clips` the G3 clip — a strengthening, not in the spec.
- The spec's `recording_probe.py --only 7` is spelled `--only catalog`: the
  script's `--only` takes section NAMES and refused `7`.
- `graphics_proof.py`'s `--mutant` copy now symlinks `docs/` beside `core/`:
  the post-build step reads `docs/`, and without it the mutant copy failed
  to build (xcodebuild rc 65) — found on the first mutant run.

**Owed.**
- G4b (above). The Help menu item and G5's Graphic sub-tab are the UI
  paths `graphic_reference` and `get_graphic` name as "none yet".
- `graphic_reference`, like every tool, carries the injected `project`
  argument, which it ignores (it never resolves a document).
- The offscreen harness and the probes copy no manual: for them
  `writeManual()` is a no-op (out of scope).
- `AgentServer.swift`'s own numerals and the rest of G3b's list, still.
- (Review nits, owed to G4b.) `AgentServer+Graphics.swift:118`: a file
  written but not read back by the scan answers "No module named …", which
  reads as a failed write. `:215`: a module with no registry entry answers
  `ok: false` with EMPTY `diagnostics` — the agent gets no reason.
  `GraphicStore+Manual.swift:51`: `holdsContent` counts a leftover
  `.js.partial` (only after a crash mid-write), so an untitled root holding
  only that is carried by the first save.
- `make typecheck | grep -c "warning:"` prints 14 for the 7 baseline
  warnings on this run (each printed twice); G3 runs printed each once. Count
  distinct `file:line:col` lines.

The review passed first time, no blocker or should-fix; it confirmed
`write_graphic`'s `rescan()` can never run inside a `.graphicsDidChange`
observer (the handler runs as a main-queue block, which is serial, and
neither observer runs a handler), and that `recording_proof.py`'s 186/187 is
the Bluetooth head-loss row remaining §4 names (a FAIL by design on this
host, not a skip). The `app/CLAUDE.md` and root `CLAUDE.md` entries were
written by the orchestrator from the pipeline's drafts after the review.

#### G4b — `render_graphic`, `import_graphic_font`, `import_graphic_asset`; the tenth export (2026-09-25)

Against baseline `e7dfacb`, branch `svg-motion`.

**What landed.**
- **Two tolls, each landed and gated alone, each its own patch, before any
  feature line.** *Core* (`step1a-move.patch`): `read_bytes` moved out of
  `ffi_graphic.rs` into `ffi_util.rs` verbatim but for `pub(crate)` (the
  diff of the ten lines against `e7dfacb` is that one line), and the two
  frees' identical bodies became `ffi_util.rs`'s `free_boxed<T>(p, what)`,
  each free keeping its doc, attribute and signature with a one-line body —
  nothing else crate-free in the file was large enough (`diag_json` and
  `diag_error` name `Diagnostic`). `ffi_graphic.rs` **397 → 373**,
  `ffi_util.rs` **161 → 189**; gated alone — `make test` core 868 + graphic
  99, 0 failed (a CONTROL: the counts before it), `make lint` clean. *App*
  (`step1b-move.patch`): `ReelCore.swift`'s `// MARK: - Media descriptors`
  block (`MediaDescriptor`) and `// MARK: - Media files` block
  (`mediaURL(for:)`, `bookmarkString(for:)`) moved verbatim into the new
  `MediaDescriptor.swift` after `import Foundation` — `git show
  e7dfacb:app/Sources/ReelCore.swift | sed -n '732,793p;1277,1309p'` diffs
  EMPTY against `sed -n '3,$p' app/Sources/MediaDescriptor.swift` — and the
  header's type list and size-payment paragraph say so. `ReelCore.swift`
  **1440 → 1346**, `MediaDescriptor.swift` **97**; gated alone — `make
  typecheck` 0 errors and the 7 baseline warnings, `make app` built.
- **The tenth export, `rc_graphic_library_families`** (Rust → header →
  `GraphicLibrary.families()`): the frozen library's family names as a
  sorted, deduplicated JSON array — the ENGINE's own names, what a
  `font-family` must say — freezing the library as a compile would; NULL
  only for NULL; through `fallible_op` with no channel. `graphic_ffi.rs`'s
  `families_answers_the_bundled_faces_sorted_and_freezes` (the eight bundled
  files are six families: Anton, Bebas Neue, Darker Grotesque, IBM Plex
  Mono, Montserrat, Source Sans 3; an add after it answers `FROZEN`; NULL is
  NULL) and the null-safety sweep's line. `ffi_graphic.rs` **373 → 397** of
  400, `ReelCore.swift` **1346 → 1353**. Why an export and not CoreText: the
  spec review ran fontdb 0.24 (the pinned version) and CoreText's
  `kCTFontFamilyNameAttribute` over every `.ttf`/`.otf` on this host and
  they disagreed on **13 of 2500** files — `/Library/Fonts/Oswald-Medium.ttf`
  is "Oswald Medium" to CoreText and "Oswald" to the engine, likewise
  `PublicSans-Light.ttf`, `PowerrLight.ttf`, cuts of Archivo, Bodoni Moda,
  Bricolage Grotesque and Noto Sans Kannada, and `SFNS.ttf` (".SF NS" vs
  "System Font"); the eight bundled faces and Arial agree. (That run was the
  review's, recorded in the pipeline's objections; this phase did not
  repeat it. Row I1 measures the one file that matters to it.) A second
  copy of fontdb's name rule in Swift would drift silently on an upgrade.
- **`render_graphic`** (`AgentServer+GraphicRender.swift`, 263 lines, NEW;
  an `offMainTools` member): one `onMain` for the target, the module as the
  registry compiled it (`compiledModule` now answers the `GraphicModule`
  too), the canvas and `meta`; then, off main, the ctx `recipe_graphic.rs`
  builds for a clip — `fps`, `time`, `durationInFrames` (`meta`, else 5 s at
  the canvas rate, ceiled), `progress`, `width`/`height` (the arguments,
  else `meta`, else the canvas) and `canvas` — per frame, `svg` and
  `rasterize` at `GraphicRegistry.offlineBudgetMs`. A frame that throws or
  will not rasterize is its ERROR CARD in the cell — `LayerRenderers.
  paintErrorCard`, extracted from `errorCard` so the preview's card and the
  sheet's are one painter — and a sentence (`graphicSentence`, now
  internal); a warning is a sentence. `frames` (1…16, whole, ≥ 0) or
  `frame`, never both, `[0]` for neither; each refused by name.
  `format: "svg"` answers `{name, frame, ok, svg, diagnostics, ctx}` for one
  frame. The PNG goes through `FrameWriter.write` with its nil properties
  dictionary and the reply ends "Written to <path>." like `render_frame`'s.
- **The sheet** (`GraphicContactSheet.swift`, 189 lines, NEW, pure): the
  layout rule of the spec's objection 2 — the scale is over the CELLS alone
  (`min(1, (max_width − (c−1)·8) / (c·w), (8192 − r·24 − (r−1)·8) /
  (r·h))`), the 8 px gaps and 24 px label strips drawn full size — so the
  context is exactly the sheet and `width ≤ max_width`, `height ≤ 8192` by
  construction; at scale 1 a cell is the raster's own bytes at an integer
  origin. Backgrounds `transparent` (default), `checker` (16 px, 128/192),
  or `#rgb`/`#rrggbb`/`#rrggbbaa`. `GraphicRaster.cgImage()`.
- **`import_graphic_font` and `import_graphic_asset`**
  (`AgentServer+GraphicImports.swift`, 123 lines, NEW; main): the copy is
  `GraphicStore+Import.swift`'s `importFile` (37 lines, NEW; through
  `ensureFolder()`, G-14, then `<name>.partial` moved into place, write's
  shape — `GraphicStore.swift` untouched), then `store.rescan()` from the
  handler. A font is checked on a throwaway `GraphicLibrary` first (a
  refusal is "<path>: font bytes loaded no face", the engine's words) and
  that throwaway's `families()` is the reply's `families`;
  `library_families` is the registry's set. An asset's name (default the
  file's) must carry one of the six extensions, and an empty file is
  refused before the copy (it would cross the FFI as NULL). Both answer
  `replaced` and the note; neither is undoable.
- **The library catch-up** — found by this phase, not in the spec. The
  store posts NO `.graphicsDidChange` for a pass whose module list is empty
  (`drain()` skips an outcome with no names), so a face imported into a
  `graphics/` holding no module never reached the registry: the reply's
  `library_families` lacked it, and a module written AFTER it recompiled
  against the set's OLD library and drew nothing, with the missing-family
  warning (measured on a probe instance before the fix). Both imports now
  end with `catchUpLibrary`: when the registry's `libraryVersion` differs
  from the scan's, `GraphicRegistry.install` rebuilds the set — main, from
  the handler, never from an observer. Row I4 proves it. The watcher path
  (a person dropping a font into an empty `graphics/`) still has the gap;
  owed below.
- **The two nits G4a owed.** `write_graphic` whose file the scan does not
  list answers "graphics/<name>.js was written but the folder's scan does
  not list it — graphics/ may not be readable by Reelcut, or was replaced
  mid-write; get_graphic {} shows what the scan sees" (row G9); a module
  with no registry entry answers `ok: false` with ONE error diagnostic, "The
  module "<name>" is in graphics/ but the app has not compiled it yet — call
  again" (no row reaches it: the rescan is synchronous through to the
  registry in every path a script can drive).
- **`get_graphic {}`** gains `families` (the export, through
  `libraryFamilies`) and `assets`.
- **Counts**: 85 tools (59 op + 26 app-state); `AgentServer.swift` (frozen)
  took three handler lines, the `offMainTools` entry and "eight"; the
  catalog prose, the gate, spec §7.9, `op_argument_proof.py`'s `TOOLS = 85`
  and the three `APP_STATE_TOOLS` sets with their "twenty-six" labels.
  `docs/graphics-api.md`'s "Working over MCP" reworded in place (**400**
  lines).

**Measured.** `make test` core **869** + graphic **99**, 0 failed; `make
lint` and both `cargo fmt --check` clean; `make typecheck` 0 errors and the
7 baseline warnings (distinct `file:line:col`); `make app` built.
`graphics_proof.py --port 4883` **39/39**; `--mutant frame-plus-one` caught
(P1 held, P2 failed, exit 0). On a fresh 4823 instance:
`op_catalog_proof.py` 23/23, `op_argument_proof.py` **144/144** (EXACTLY 85
tools, 26 of them app-state), `phase9_proof.py` 218/218,
`recording_proof.py` 186/187 — the one FAIL is the Bluetooth head-loss row
remaining §4 names, two tone rows skipped by name —
`recording_probe.py --only catalog` 28/28; the parity grep empty on every
launch. **A 16-frame 4K sheet**: `render_graphic` of `title-card` at
3840×2160, frames 0, 8, … 112, 119, `max_width` 8192, took **1.03 s** wall
clock on a probe instance (well under `CALL_BOUND`'s 300 s), a sheet of
**8192×4712** at scale 0.531771 on 4×4 — the float did not floor low.

**The rows** (`graphics_proof.py`, now 39): C1 C2 C3 on WG after G7, then
I1 I2 G9 I3 I4, then L2 on a new LP; C4 in `run_e` after E1.
`tools/proof/README.md`'s G4b section has each row. The sheets are decoded
through ffmpeg (`decode_rgba`), because `decode_png`'s Python loops are too
slow for 3848 px rows. C2, the placement row: `render_frame` at frame 30
and `render_graphic {frame: 30}` over black agree in every RGB pixel, **0
of 2 073 600** differ.

**Made to fail by hand (2026-09-25)**, each reverted and rebuilt:
- (a) `module.svg(frame: frame + 1, …)` in `renderGraphic`: **36/39** — C2
  fell (1440 of 2 073 600 pixels differ), and so did C3 (its SVG is frame
  31's, `x="124"`) and C4 (frame 9's cell became frame 10's card and frame
  10's cell frame 11's rect). The spec expected C2 alone; the other two go
  through the same call and are right to fall.
- (b) `store.rescan()` deleted from `importGraphicFont`: **37/39** — I1
  (`library_families` without Oswald, the render still warning) and I4 (the
  same reply on the module-less package).
- (c) the extension check deleted from `importGraphicAsset`: **38/39**, I2
  alone (`notes.txt` was copied, not refused).
- (d) `catchUpLibrary` deleted from `importGraphicFont`: **38/39**, I4 alone
  (`library_families` without Oswald on the module-less package).

**Deviations from the spec.**
- The loop row is **L2**, not L1: `graphics_proof.py` already has an L1 (the
  stale-colour row), and `rows` is keyed by the two characters.
- L2's `set_graphic` title is **"Looped"**, not "Loop": `bar()` draws only
  the title's LENGTH and "Loop" is as long as the default "Jane", so the
  frame did not change (the first run's one failure, 37/38).
- **I4 and `catchUpLibrary`** are additions (above); the score is 39, not
  the spec's 38.
- By-hand failure (a) dropped three rows, not one (above).
- `render_graphic`'s arguments are read BEFORE its `onMain`, so a bad
  argument is refused before a document is looked up; the spec's order put
  them after. Nothing reads a document off main either way.
- `docs/graphics-api.md`'s paragraph kept the `API.d.ts` mention by
  rewrapping rather than adding a line (400, the cap).

**Owed.**
- The watcher path of the library gap: a font or picture put into a
  `graphics/` holding no module by hand (or by any writer but the two
  imports) never reaches the registry, and a module written after it draws
  without it until a font or asset changes again or the project reopens.
  The fix is `GraphicStore`'s (post the library change with no names, or
  have `update` rebuild when the scan's `libraryVersion` moved) and was
  out of this phase's files.
- Under `format: "svg"`, `render_graphic`'s `background` and `max_width`
  are checked and then unused, and `path` is not read at all (all three are
  declared, so the gate passes them).
- `frames` larger than the graphic's length draw (progress clamps), as a
  clip held past its length does; nothing refuses them.
- From G4a, still: `graphic_reference` ignores its injected `project`;
  `AgentServer.swift`'s numerals and the rest of G3b's list;
  `holdsContent`'s `.partial` nit.
- (Review nit.) A contact sheet keeps every cell's full-size raster until
  it paints, and copies each once more on the way: 16 frames at 8192×8192
  (what the schema allows) would peak near 4 GB; the measured 16-frame 4K
  case is about 530 MB. Painting each cell as it is rendered would cap it
  at one raster.
- G5 — below.

**Review.** One should-fix, in the RECORD: this section and remaining §3
gave `AgentServer+GraphicImports.swift` as 108 lines, measured before
`catchUpLibrary`; it is 123, corrected by the orchestrator. Its nits (the
`svg` form's unused arguments, the sheet's peak memory) are the two owed
lines above. The review read `render_graphic`'s threading (every document
and registry touch inside its one `onMain`), `catchUpLibrary` (no race; it
cannot loop) and the tenth export against `core/CLAUDE.md`'s FFI rules,
and found nothing. The `CLAUDE.md` sentences were written by the
orchestrator after the review.

#### G4 closed — the merge point (§9a)

**What an agent can do now, end to end, over MCP alone:** read the API
(`graphic_reference`); write a module and read its compile back —
`ok: false` with the engine's line is an answer, not an error
(`write_graphic`); look at up to sixteen of its frames with no clip, as a
contact sheet with each frame number printed and a failing frame shown as
its error card, or at one frame's SVG (`render_graphic`); bring in a font —
told the exact family names the engine reads from it — or a picture
(`import_graphic_font`, `import_graphic_asset`); place it
(`add_graphic_clip`), look at it in the timeline (`render_frame`, which
agrees with `render_graphic` pixel for pixel), change its props
(`set_graphic`), save, and export — which refuses a module that does not
compile and stops at a frame that fails. `graphics_proof.py`'s L2 is that
loop in one row.

**What a person cannot do yet — G5:** the Graphic sub-tab (§5j: the module
picker, the props form from the schema, the source and diagnostics, the
preview strip `render_graphic` mirrors), File ▸ Add Font to Graphics… and
File ▸ Add Image to Graphics… (which the two imports mirror), Help ▸
Graphics Reference (which `graphic_reference` mirrors), and the six
templates (§5k). Until then a person sees a graphic clip drawn and can
move, trim and split it, and edits its module in their own editor.

**Merging `svg-motion` into `main` is the user's decision now** (§9a:
"stop after G4 and report"). Owed across G4: the list above and G4a's, the
person's playback check (remaining §4), and kpgalligan/reelcut#38 (the
export-cancel crash's cherry-pick to `main`).

### 10.8. After G4 — a defect the person found, and where G5 stands

#### The defect: a project of only graphics does not play (DIAGNOSED 2026-09-25; OWED, deferred by the user)

**What the user saw.** The user built Reelcut from `svg-motion` and opened
the three playback-check projects (`tools/proof/work/playback-check/`, made
by `tools/proof/graphics_playback_samples.py`, remaining §4's graphics
bullet). "The clips are there, but they show no preview, and playback just
plays a beep."

**What the user then found (2026-09-25).** The same graphics PLAY once any
video clip is on the timeline: "I added a video and stacked it below the
'graphic' clips. Then it plays fine. Scrolling seems smooth, or smooth
enough. It actually works quite well. I added an action to one that would
fade it out, and it worked perfectly." So the live path — `Playback`'s
`AVPlayer`, the document's `RecipeSource` key through
`GraphicRegistry.resolve`'s 250 ms preview arm, `LayerRenderersGraphic`,
the compositor, and an action on a graphic clip — works in the running app
when the timeline has a video track. The user's ruling: **graphics by
themselves must be playable, but later — record it and move on**; G5 is
unblocked.

**The cause, read from the code (not yet driven by a probe).**
`Playback.startRebuild` (`app/Sources/Playback.swift:360-371`) drops the
player item when `plan.videoTracks.isEmpty && plan.audioTracks.isEmpty`
("An empty timeline has no tracks to compose"), and `Playback.play()`
(`:448-452`) beeps on a nil `currentItem` — the beep the user heard. The
core's `segment_of` (`core/src/evaluate.rs:271-275`) gives NO segment to
`Image`, `Text`, `Shape` or `Graphic` clips, so a project made only of them
has no tracks at all and never reaches `CompositionBuilder.build`, whose
`addPlaceholderIfNeeded` (`CompositionBuilder.swift:173-188`) exists for
exactly that case (a one-frame `Blank.mp4` scaled to `plan.duration`).
`render_frame` and export go through the builder directly, which is why
they drew all three samples. The guard dates from the first commit
(`da962fa`), so the defect is **not graphics-specific**: a timeline of
only text, shapes or images should fail the same way — inferred from the
code, not run.

**The fix, when it is taken.** The guard in `startRebuild` should test
`plan.duration > 0` (the empty-timeline case) rather than the track
lists, and let the builder add the placeholder. It owes a live proof that
fails today: a graphics-only (and a text-only) project whose Play does not
refuse — through a probe driving `Playback`, or an MCP row if one can read
the live player's state — made to fail on purpose, then the person's
re-check of the three sample projects without a video underneath.

**Still owed from the same look:** `ProjectSnapshot.sourceSize(of:)`
answers nil for `.graphic` (`ProjectSnapshot.swift:~1791`, under a stale
comment saying G3 would read `graphic.width`/`height` once `ClipSnapshot`
decoded them — G3a did). It affects canvas handles and Fit/Fill, not the
picture.

#### G5 — paused on 2026-09-25, resumed the same day

Paused for the defect above and resumed once the user deferred it. G5 (the person: road map 9-style Graphic sub-tab, menus, templates) was
split into two `/litecode` pipelines. Neither has changed code:
- **G5a — the Graphic sub-tab.** `request.md` and triage (full route) are
  written in `~/.claude/litecode/reelcut/graphics-g5a-graphic-subtab/`; the
  designer was stopped by the user mid-exploration, before `01-spec.md`.
  Resume from the design stage.
- **G5b — menus, templates, G4b's watcher library gap, closing G5.**
  `request.md` drafted in `~/.claude/litecode/reelcut/graphics-g5b-menus-templates/`
  (its baseline and "what earlier pipelines found" section are filled in
  when G5a lands).
The requests' substance: §5j, §5k, and G4b's owed watcher gap (§10.7 G4b).
