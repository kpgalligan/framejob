# Graphics — motion graphics drawn by code (road map 10)

- **Status:** Built and merged into `main` 2026-09-25 (G0 spike, G1–G5 built;
  G6 performance deferred by the user).
- **Original:** `archive/roadmap-10.md` (3859 lines) — the full record;
  sections cited below as "orig §x" refer to it. Its input was the user's
  proposal, `archive/svg-motion-components-plan.md` (ADR:
  `designs/adr/svg-motion-plan.md`).
- **Spec decisions:** G-1..G-16 in spec §11 (`designs/spec/11-decisions/`),
  with G-9·a/b/c and G-15(a)–(f). One-line gists:
  G-1 a graphic is a clip's SOURCE, not an effect (spec §1's plugin non-goal
  gains one clause; R5-1 stands);
  G-2 the engine is a separate crate, `graphic/`, and the core keeps "no
  pixels, no filesystem";
  G-3 a module is a FILE in the package, and editing it is not an undo step;
  G-4 the core checks props against the schema the OP carries, render time is
  lenient;
  G-5 a frame is a pure function of source, props, frame, size, fonts, assets;
  G-6 fonts are the bundled faces plus `graphics/fonts/`, never the system's;
  G-7 a graphic draws at its own frozen size, premultiplied BGRA across the FFI;
  G-8 a failure draws an error card, answers the agent, and stops an export;
  G-9 a graphic's own timeline is `in` + `length`, and `split` pins it;
  G-10 props are not action targets (its props half superseded by G-34,
  #239, below);
  G-11 plain JavaScript, one ES module, no TypeScript;
  G-12 colour props are CSS strings normalised to hex;
  G-13 the revision is a SHA-256 content hash, and an export pins it;
  G-14 `graphics/` is created on first write, never at open;
  G-15 the Graphic sub-tab's multi-clip and write rules;
  G-16 Insert ▸ Graphic's placement, naming and compile-failure rules.

## Context

The user asked for something like Remotion: motion graphics made from code
(2026-09-24). Here a JavaScript module returns an SVG string for a frame, and
the result is a new clip type. An AI over MCP would create and edit most of
these clips. A clip's code lives on disk inside the `.framejob` package.

Before this, Frame Job had no scripting and no C code in the build. The core
did no pixel work and had no filesystem. The design fits the feature into
those rules. A graphic is one more producer of the premultiplied BGRA layer
texture that text and shapes already make. So placement, actions, blend
modes, transitions, motion presets and alpha export all apply to it with no
change (orig §0, §2).

## Decisions

**The engine is QuickJS (via `rquickjs`) plus resvg, in the `graphic/` crate at
the repo root, linked into the one staticlib** (G-2; orig §4 G-2, §10.1 q1/q9).
Only `core/src/ffi_graphic.rs` names the crate, and no model, op, plan or
recipe module imports it. The crate does pixel work but never touches the
filesystem: the app reads every byte and hands it over. A second staticlib
was ruled out because two Rust staticlibs duplicate `std`'s symbols.
JavaScriptCore plus a platform rasterizer was rejected for three reasons:
- `measureText` must be the rasterizer's own measurement, and macOS has no
  public SVG rasterizer;
- JSC's execution time limit is SPI, where QuickJS's memory and interrupt
  limits are public;
- one call in and pixels out is a smaller seam.

The risk accepted: the first C code in the build, costing about 18 s per
cold build and about 7–8 MB of app binary. The linker keeps QuickJS even
when nothing calls it. **Issue #39** (open) asks to revisit this choice for
JavaScriptCore, perhaps through `objc2` from Rust, mainly because
quickjs-ng has no `Intl`. Anyone who takes it up must answer every one of
these G-2 and G-5 arguments:
- the time-limit SPI;
- byte-identical frames across machines and OS versions — q8 proved
  QuickJS's float identity only across build profiles on one host, and a
  system JSC changes with the OS;
- the sandbox's removals (orig §5b);
- the preview/export determinism test.

Keeping `measureText` in resvg is not affected by that choice.

**No cargo feature gates the engine.** Linking it made `make test` 1.12×
slower warm, well under the 2× threshold that would have put it behind
`features = ["graphic"]` (orig §5a, §10.1 q1).

**resvg takes its defaults minus the two features that reach the filesystem**
(`text`, `raster-images` and `svgz` on; `system-fonts` and `memmap-fonts`
off). The user ruled that binary size and clean-build time are not reasons
to drop a feature. `raster-images` is required: resvg 0.48 decodes no
`<image>` without it (orig §5a).

**`serde_json` has `preserve_order`,** so a module's schema keeps its key
order, which is the order the inspector's rows appear in. Cargo feature
unification pushed it into the core. `recipe.rs`'s `content_hash` now hashes
a recursively SORTED copy, so no existing texture key moved. Under
`preserve_order`, `Map::remove` is `swap_remove`: code that promises an
order must use `shift_remove`, as the props code does (orig §10.4 G1d).

**The sandbox (G-5), with each rule made to fail on purpose** (orig §5b,
§10.1 q6):
- limits: a 64 MB heap, a 1 MB stack, and a 250 ms interrupt deadline per
  call in preview (2 s in export and `render_frame`);
- no `std`/`os` modules, and a loader that resolves no specifier;
- `Math.random` throws and names `random(seed)`;
- `Date` is frozen at 2000-01-01, including via `Date.prototype.constructor`;
- `eval`, `Function` and the Async/Generator/AsyncGenerator function
  constructors are deleted or throw;
- `performance` is deleted (quickjs-ng installs a clock there).

The one thing the sandbox cannot stop is module-level state. The
determinism test's mutant (a module-level call counter) is what catches it.

**One QuickJS runtime and context per (thread, module), in a `thread_local!`
map.** A `Module` is `Send + Sync` and holds no QuickJS object; engines are
swept when their module drops. The engine's fields must drop in the order
`render` fn, then context, then runtime; the reverse aborts inside
`JS_FreeRuntime` (orig §5b). There is no LRU cap on engines.

**A diagnostic's line and column are parsed from the exception's `stack`,
preferring a frame in the module's own name.** rquickjs 0.14's `Exception`
has no `line()`/`column()`. For an interrupt, the position is the enclosing
function, not the loop (orig §5b).

**`measureText` parses a one-`<text>` SVG with the engine's own options and
answers both the advance box and the INK box** (orig §5c, §10.1 q4). The
advance is what layout wants, but it differs from the drawn ink by up to
78 px. The ink box agrees with the pixels within 2 px of whole-pixel
columns. Direct shaping (the plan's "step 2") was measured as unnecessary.

**Fonts: a missing family draws NOTHING, so the engine warns itself** (G-6;
orig §10.1 q4, §10.4 G1b). resvg has no fallback with system fonts off, and
it does not report the miss. An unquoted family name with a digit-led word
(`Source Sans 3`) lays out nothing. So every standard-library helper quotes
family names, and `rasterize` warns about a family the set cannot resolve,
naming the families it has.

**The texture cache is keyed on the SVG TEXT plus size and library version,
not on the recipe hash** (orig §5d). A graphic that has settled on one frame
rasterizes once, and an edited file can never hit a stale texture. The
JavaScript still runs every frame; it is the cheapest of the three costs
(p95 ≤ 1.67 ms at 1080p). Graphic textures get their own LRU pool of six
(`LayerRenderers.graphicCacheLimit`), because a new 8–33 MB texture every
frame would evict every text and shape texture from the shared pool of 64.

**Parallel rendering, prefetch and a worker pool were not built in the road
map (G6)** (orig §1, §9 G6). The compositor and export were serial, and q3
measured the six samples at a worst p95 of 7.62 ms per frame at 1080p,
against a 12 ms line. At 4K, `title-card` measured 26 ms p95. The user
played graphics at 4K on an M2 Max, saw no stutter, and deferred G6. Since
issue #127 (2026-09-30, spec §11 G-26) an `ExportWriter` export rasterizes
its graphics ahead on worker threads (`GraphicPrefetch.swift`); the
compositor stays serial and the one writer, uses a worker's raster only on a
pool miss whose texture key matches its own, and still runs `svg`, records
every report and draws every card, so the file is the serial path's.
Since G6 phase 2 (2026-10-21, spec §11 G-36) a preview playing forward does
the same on the document's own key, its workers following the frame the
compositor last asked for (below, "G6 phase 2 — playback prefetch").
Since G6 phase 3 (2026-10-21, spec §11 G-37) every session's held rasters
share one budget, a quarter of physical memory, with the graphic frames a
playing document keeps, so a replay, loop or paused scrub over a span
already drawn is served from memory (below, "G6 phase 3 — one memory
budget and kept frames"). Since G6 phase 4 (2026-10-21, spec §11 G-38),
once the person has left Frame Job alone for a few seconds (Settings ▸
Playback ▸ Background render, on after 5 s, as Final Cut's), the window
whose transport last moved draws its graphic frames ahead of the paused
playhead into those kept frames, marked so they give way last; any
activity stops it, and it never runs beside a play (below, "G6 phase 4 —
background render"). Since G6 phase 5 (2026-10-22, spec §11 G-39) a
PNG or JPEG asset is drawn from a stored PNG copy that decodes to the same
pixmap, kept in one process-wide cache sized from that budget (below, "G6
phase 5 — decoded-image cache"). In-place raster was measured in G6
phase 6 (2026-10-22) and not built: what a frame pays outside resvg's own
render is 0.3% of a `section` frame (below, "G6 phase 6 — in-place
raster").

**The FFI is ten `rc_graphic_*` exports (eleven since G6 phase 5's
`rc_graphic_image_cache`), and a library is a builder that
FREEZES** at its first compile, rasterize or `families` call
(orig §5e, §10.4 G1d):
- `diag_out` is always a JSON array of `{level, message, line, column,
  frame}`, with exactly one error on failure;
- `rc_graphic_compile` takes a budget, so a top-level infinite loop stops;
- the tenth export, `rc_graphic_library_families`, gives the ENGINE's
  family names. CoreText and fontdb disagreed on 13 of 2500 host font
  files, so a Swift copy of the rule would drift (orig §10.7 G4b).

**The model: `Source::Graphic` plus `Clip.graphic {name, width, height, in,
length, props}`, format version 10** (orig §5g, §10.5):
- the core computes `frame = floor((in + clip_time) / frame_ticks)` and the
  whole `ctx` into the recipe;
- the recipe publishes `props_json` and `ctx_json` as text, so the app
  passes them straight to the engine and keeps no Swift mirror of `ctx`;
- the hash covers name, frame, ctx and props (G-9·b).

The timeline arithmetic lives in `recipe_graphic.rs`, shared by the writers
and the reader. `split` pins both halves' `length`; `trim_start` and `roll`
advance `in` with no head bound (G-9·a). A null length means `in + duration`
(G-9·c).

**Two ops, `add_graphic_clip` and `set_graphic`, carry a `schema` argument
that the app fills and never publishes** (G-4;
`Requirement.filledByTheApp` in `AgentCatalog+Declarations.swift`). With a
schema, the core refuses a bad prop by its dotted path. Without one (a
replayed op), it checks shape only. At render time, stale keys and wrong
types become warnings, never errors.

**Nine app-state tools** (orig §5h, §10.7; the last three issue batch
B84's, spec §11 G-27..G-29):
- `write_graphic` answers the compile in the same call; its
  `store.rescan()` is synchronous so the reply is current;
- `get_graphic`;
- `render_graphic`, a contact sheet of up to 16 frames with no clip;
- `graphic_reference`;
- `import_graphic_font` and `import_graphic_asset`;
- `delete_graphic`, `rename_graphic` and `restore_graphic`, over the last 10
  texts of each module kept in `graphics/history/`.

The agent's loop is `graphic_reference` → `write_graphic` →
`render_graphic` → `add_graphic_clip` → `set_graphic`.

**The package's `graphics/` folder is whitelisted in `fileWrapper`,
created only by `GraphicStore.ensureFolder()`, and watched** (G-3, G-14; orig
§5f, §10.1 q7, §10.6 G3a):
- one `DispatchSource` on the folder, one on each subfolder, and one on
  each `*.js` file. A folder source raises only `.write`, and misses an
  editor's in-place save;
- events coalesce over 100 ms into one pass;
- `packageContentsDidChangeOnDisk()` is called only when the folder is
  CREATED. Creating a folder inside an open package is the one thing that
  trips "changed by another application";
- an untitled document's folder sits BESIDE the temporary cache root, and
  the first save carries it only when it holds real content.

**`GraphicRegistry` maps a recipe key to an immutable compiled set.
Preview follows the newest revision, and every offline door PINS the set it
was handed** (G-13; orig §10.6 G3b/G3c). The offline doors are export, the
queue (captured at enqueue), `render_frame`, Save Frame and the eyedropper.
An offline key without a pin draws the missing slate. A pin keeps the first
failure in a slot of its own, plus at most 64 warnings.

**Failure** (G-8): an error card (dark red, a red border, the message in
IBM Plex Mono), never the last good frame. Export compiles every module in
range before it starts, refuses without touching the destination, and
aborts at the first failing frame, leaving no file.

**`ExportWriter.cancel()` only sets a flag; the reader and writer are
cancelled in `allInputsFinished`** (orig §10.6 G3c). Cancelling the reader
under a running `copyNextSampleBuffer` had crashed the app since road map
2's phase 7: 12 of 30 mid-export cancels crashed. G3c found and fixed it
(issue #38, closed with the merge). The accepted cost is that a pump
blocked on a read finishes one sample first (0.1–0.3 s).

**Media-less timelines play** (orig §10.8). `Playback.startRebuild` now
drops the player item only when `plan.duration == 0`, so the builder's
`Blank.mp4` placeholder gives a timeline of only graphics, text, shapes or
images something to tick against. This defect dated from the first commit.

**The inspector's Graphic sub-tab is the first section built from data**
(G-15; orig §5j, §10.9 G5a). It has one row per schema key in module order.
A value equal to its default writes `null`. Stale keys show dimmed, each
with ⌫. The diagnostics shown are checked at the clip's first frame. It has
no preview strip. The pane rebuilds when the schema's keys or types change,
not when a default changes.

**The reference is one document in three places** (orig §5i):
`docs/graphics-api.md`, kept at 400 lines or fewer so it fits a prompt, and
`docs/graphics-api.d.ts`. The build copies them into the bundle, and the
store writes them into an existing `graphics/` as `API.md` and `API.d.ts`.
`graphic/tests/reference.rs` runs every `js` block and checks that every
stdlib function is documented and typed.

**Tests are oracle tests, with one exception: `graphic/tests/pins.json`**
(orig §5l). It pins the SHA-256 of fixture frames as a tripwire for a resvg
upgrade (re-pin with `GRAPHIC_REPIN=1`). Zero-tolerance golden PNGs, as the
plan proposed, were rejected under `core/CLAUDE.md`'s rules.

## What it built — where it lives now

- `graphic/` — the crate. `src/`: `lib.rs`, `library.rs`, `raster.rs`,
  `measure.rs`, `module.rs`, `runtime.rs`, `sandbox.rs`, `exception.rs`,
  `host.rs`, `props.rs`, `diagnostic.rs`, `stdlib.js`, `noise.js`, `path.js`;
  rules in
  `graphic/CLAUDE.md`. `tests/graphics/` holds the six fixtures, which are
  also the Insert ▸ Graphic templates (copied into the bundle as
  `GraphicTemplates/` by `project.yml`).
- Core: `ffi_graphic.rs` (the ten exports; `read_bytes`/`free_boxed` in
  `ffi_util.rs`), `model_graphic.rs`, `edit_graphic.rs`, `recipe_graphic.rs`;
  arms in `edit_split.rs`, `edit_clip_timing.rs`, `edit_edge.rs` and
  `edit_action.rs` (`GRAPHIC_NOT_A_TARGET`); tests `core/tests/graphic.rs`,
  `graphic_ffi.rs`, `schema_v10.rs`.
- Header `core/include/framejob_core.h` (`/* graphics */` section); Swift
  wrappers at the end of `app/Sources/ReelCore.swift`. The size toll moved
  code out first, into `RecipeSource.swift` and `MediaDescriptor.swift`.
- App: `GraphicStore.swift` (+`Manual`, +`Import`), `GraphicScan.swift`,
  `GraphicRegistry.swift`, `LayerRenderersGraphic.swift`,
  `GraphicContactSheet.swift`, `GraphicTemplates.swift`,
  `ProjectDocument+Graphics.swift`, `ProjectSnapshot+Graphic.swift`,
  `ExporterGraphics.swift`, `ExporterErrors.swift`, `GraphicPane.swift`
  (+`Source`), `GraphicSchemaRows.swift`, `EditorViewController+Graphics.swift`
  and `+GraphicMenus.swift`, `AppDelegate+GraphicMenu.swift`,
  `AgentServer+Graphics.swift`, `+GraphicRender.swift`, `+GraphicImports.swift`,
  `AgentCatalog+Graphics.swift`.
- Docs: `docs/graphics-api.md`, `docs/graphics-api.d.ts`; `CONTEXT.md`
  terms Graphic, Module, Props, Revision.
- Proofs: `tools/proof/graphics_proof.py` (40 rows, the agent loop),
  `graphics_ffi_probe.py`, `graphics_store_probe.py`/`_proof.py`,
  `graphics_inspector_proof.py`, `graphics_menu_proof.py`,
  `graphics_pin_probe.swift`, `media_less_playback_probe.py`,
  `graphics_playback_samples.py`. The G0 spike's instruments are in
  `tools/proof/graphics_spike/`; do not re-run it, because it overwrites the
  recorded `work/` outputs.

## Known limits

- **Cost.** The app binary is about 7.9 MB larger, and QuickJS is kept even
  when nothing calls it. A cold build pays about 18 s for QuickJS's C.
- **Performance** was measured on one M2 Max only. The worst 1080p p95 was
  7.62 ms per frame; 4K `title-card` was 26 ms p95 (57 ms max). Rasterizing
  dominates, not the JavaScript. A slower machine or a heavier graphic is
  unmeasured, and so is resident memory while an animated 4K graphic plays.
  An export's graphics are rasterized ahead on `activeProcessorCount − 1`
  worker threads (G-26); each graphic's JavaScript then runs twice per frame
  (worker and compositor), and resvg still decodes an embedded image inside
  every render. Preview playback is still serial.
- **quickjs-ng 0.16.2 has no `Intl` and no `structuredClone`.**
  `formatNumber` exists for that reason (issue #39).
- **Largest string `render` can return:** 8 MiB (`graphic::SVG_BYTES`,
  spec §11 G-20 (c)); a longer one is the frame's error, naming its length.
  A 50 MB string is built but cannot be read out of a 64 MB heap at all; the
  engine's own sentence says so.
- **Deliberately not built** (orig §7):
  - video input to a graphic — wanted, #251 (iceboxed; split out of #240,
    whose matte half is built: road map "mattes", spec §11 MT-1..MT-7,
    `designs/adr/mattes.md`);
  - system fonts as an opt-in — CLOSED by the owner 2026-10-04: Add Font to
    Graphics… / `import_graphic_font` already puts a face in the package and
    keeps a project portable; G-6 stands;
  - audio from a graphic;
  - `cursive` and `fantasy`, which have no bundled face and are warned like
    any missing name (`serif`, `sans-serif` and `monospace` draw in bundled
    faces, G-6).

  Built since, and so off this list: a revision history and
  `delete_graphic` / `rename_graphic` (issue batch B84, spec §11
  G-27..G-29), path helpers (issue batch B85 phase 1, spec §11 G-31:
  `graphic/src/path.js`), `paste_attributes` for graphics (issue batch B85
  phase 2, spec §11 G-32: the `graphic` group and Edit ▸ Paste Graphic
  Properties), named CSS colours and `hsl()` in a `color` prop and in
  `interpolateColors` (#219: `core/src/model_color.rs`,
  `docs/graphics-api.md`'s schema table and `interpolateColors` section),
  and keyframed props (#239, spec §11 G-34: the section below).
- **The watcher:** each module, font and asset file has its own source, but
  a store arms at most 16 of them per pass (`GraphicStore.fileSourceLimit`),
  modules first, then fonts, then assets, each in name order; an in-place
  rewrite of a later one is seen at the next pass (spec §11 G-19 (c), which
  carries the descriptor arithmetic, and G-20 (a)). A source whose `open`
  fails is a scan warning, "`<subject>` is not watched: open failed
  (`<strerror>`)" (G-20 (b)), which nothing shows yet. The untitled graphics
  root is removed at close and
  when the first save re-points the store; the untitled cache root at close
  only, never at the first save (G-19 (d)). `GraphicStore.drain()` is not
  re-entrant, so never call `rescan()` from a `.graphicsDidChange` observer
  (`app/CLAUDE.md`).
- **Export:** a successful export's warnings are dropped at unpin.
- **An agent cannot observe a module swap during an export over MCP:** the
  core's agent server is one thread, and `export` holds it.
- **Constants restated across the G-2 boundary:** `MAX_SIDE` 8192 (the crate,
  `model_graphic.rs`'s `GRAPHIC_MAX_SIDE`, and the header's
  `RC_GRAPHIC_MAX_SIDE`, which `GraphicLibrary.maxSide` reads — the three
  pinned equal by `core/tests/graphic_ffi.rs`'s
  `one_max_side_in_the_engine_the_core_and_the_header`), the 64-key limit
  (the crate's `MAX_PROPS` and `GRAPHIC_MAX_PROPS`, pinned equal by
  `one_max_props_in_the_engine_and_the_core`), the engine's `MAX_OPTIONS`
  (32), `MAX_STRING` (4096) and `TYPES` (the core's `GRAPHIC_MAX_OPTIONS`,
  `GRAPHIC_MAX_STRING` and `GRAPHIC_TYPES`, pinned equal by
  `one_max_options_…`, `one_max_string_…` and
  `one_type_list_in_the_engine_and_the_core`), and the app's
  `LayerRenderers.maxTextureSide`, which `the_app_texture_side_holds_the_largest_graphic`
  reads from the Swift source and holds at or above `MAX_SIDE`, since a
  graphic's error card is drawn at the graphic's own size (G-8). The
  numbers `docs/graphics-api.md` states for `MAX_PROPS`, `MAX_STRING` and
  `MAX_OPTIONS`, and the key cap `docs/graphics-api.d.ts` states, are pinned to
  the engine's by `graphic/tests/reference.rs`'s
  `the_reference_states_the_engine_schema_limits`.
- Fixed since: the export's compile gate walked one nest level, deeper nests
  caught only by the mid-export abort — it now walks every nest reached from
  the range, however deep (#73); the loudness reader was cancelled from main
  under a running read — `Exporter.cancel()` now only sets flags, and the
  measurement's loop cancels its own reader (#74). A starved pump's read that
  never returns is not woken, accepted in spec §11 G-17 (#73). Both proved by
  `tools/proof/export_cancel_proof.py` (issue batch B1, 2026-09-29). Issue
  batch B8 (2026-09-29) closed the store and menu gaps — a free name checks
  the disk, a non-UTF-8 module is refused, a failed write leaves no
  `.partial` and `holdsContent` ignores one, the untitled roots are removed,
  fonts and assets are watched per file (#75) — made `render_graphic`'s svg
  refuse the sheet's arguments while a frame past the length stays drawn
  (#104, G-19), and fixed the Graphic sub-tab's signature, decimals, Title
  height, repeated parses and two asset-name builders (#106), each pinned by
  a row of `graphics_store_probe.py`, `graphics_menu_proof.py`,
  `graphics_inspector_proof.py` or `graphics_proof.py` made to fail once.
  Issue batch B19 (2026-09-30) capped module sources with the library files'
  (16 a store, modules first) and made a failed `open` a scan warning
  (#172, G-20 (a), (b)); from #105 it named an explicit `font-family` equal
  to usvg's default as missing rather than absent, built the asset list once
  per rasterize, capped `render`'s SVG at 8 MiB and the png contact sheet at
  134,217,728 px of frames, pinned `MAX_SIDE` in one test with the header's
  `RC_GRAPHIC_MAX_SIDE`, made `graphic_reference` check a `project` it is
  given, had the harness copy the manual, and dropped `graphicImportSource`'s
  unused path (G-20 (c)–(e)). Pinned by `graphic/tests/families.rs` and
  `render.rs`, `core/tests/graphic_ffi.rs`, `graphics_store_probe.py` W17
  and `graphics_proof.py` C7, G10 and G11, each made to fail once. Issue
  batch B31 (2026-09-30, #183 items 1–4) exported the engine's `MAX_PROPS`
  and pinned it and `maxTextureSide` in `core/tests/graphic_ffi.rs` (each
  test made to fail once, by a 65-key cap and a 4096 side), completed
  `watchSubject`'s doc, and replaced G11's 0.5 s settle with an in-place
  rewrite of `m00.js` polled until its revision is seen, then one coalesce
  interval. Issue #127 (2026-09-30, spec §11 G-26) rasterizes an
  `ExportWriter` export's graphics ahead on worker threads. Measured on a
  12-CPU host (11 workers) under heavy load from other work:
  `graphics_prefetch_proof.py`'s fixture (1080p, 150 frames, `prores_422`)
  took 16.7 s serial and 3.46 s with the prefetch, byte-identical after
  masking; the owner's `parive-promo` (a copy) took 360.1 s serial and
  47.34 s with it as `h264` (load average 115 and 180 before each), and
  445.75 s and 43.31 s as `prores_422` (load 270 and 84), the ProRes pair
  byte-identical after masking. The `h264` pair differs after masking, and
  so do two serial `h264` exports of the same copy (324.2 s and 412.52 s,
  load 220), so that encoder is not byte-deterministic here. Every prefetched raster the compositor
  asked for was used: 3 596 hits, 0 mismatched, 0 missed over 1 766 frames
  with graphics. The load made the absolute times noisy, and the ratio
  overstates the gain on an idle host. Pinned by
  `graphics_prefetch_proof.py` (S0–S5, Z1) and its two mutants, each made to
  fail once.
  Issue batch B41 (2026-09-30, #197, #189) exported the engine's
  `MAX_OPTIONS`, `MAX_STRING` and `TYPES` and pinned each to the core's
  `GRAPHIC_` restatement in `core/tests/graphic_ffi.rs`, and pinned the
  numbers the reference and its typings state in `graphic/tests/reference.rs`
  (each made to fail once: a 31-option engine cap failed both its pin and
  the reference's, a 4095 core string cap and an `"image"` type their pins,
  and each of the four stated numbers changed in turn the reference's), and
  gave `sandbox.rs`'s `string_50mb` its own 2000 ms budget, since it is the
  string-size refusal's case and not the deadline's (`while_true` is), and
  under host load its 50 MB build ran past 250 ms: under 48 spinners five
  runs marked loaded passed with its calls at 526.58–811.20 ms, and five loaded
  runs with the budget set back to 250 failed it all five times. Issue
  batch B63 (2026-10-01, #105 part 1) had `raster.rs`'s unparsed-family scan
  read a `font` shorthand's family in `style` attributes and sheets (not a
  `font="…"` attribute, which usvg never reads), capped each thread at
  `ENGINES_PER_THREAD` = 16 engines with the least recently used evicted
  after the call and reloaded on its next frame (G-21 (a)), and kept the
  warnings a module's top level raises on the `Module` as
  `Module::warnings()` instead of losing them to the next call's `arm` (G-21
  (b)); pinned by four new cases in `graphic/tests/families.rs` and three in
  `module.rs`, each made to fail once: deleting the shorthand branch failed
  the style-attribute and sheet cases with the "has no font-family"
  sentence, reading the attribute failed the attribute case with the digit
  sentence, no eviction left 40 engines (17 in the LRU case), a cap of 17
  left 17, evicting by smallest module id or by newest stamp made m0 answer
  1 not 3, evicting m15 made m1 answer 2 not 1, and a `load` that returned
  no warnings left `warnings()` empty. Issue batch B65 (2026-10-02, #105
  part 2) widened an author's vocabulary under amended G-6 and G-12 and a
  new G-22. First, as a pure move landed and gated alone (`cargo test
  --release` in `core/` and `make lint` green, `model_graphic.rs` 399 → 328
  lines), `normalise_color` and its helpers left `model_graphic.rs` for a
  new `core/src/model_color.rs`. Colours: G-12's one grammar — hex, `rgb()`
  / `rgba()`, `hsl()` / `hsla()` and svgtypes 0.16.1's 147 CSS names plus
  `transparent`, out of range refused and never clamped — implemented in
  `model_color.rs` (svgtypes now a core dependency for its name table) and
  in `stdlib.js`'s `__parseColour` (through a new host global,
  `__namedColour`), both answering one hand-worked fixture,
  `graphic/tests/colours.json` (30 accepted, 21 refused), from
  `core/tests/graphic.rs` and `graphic/tests/stdlib.rs`; `interpolateColors`
  now throws on an `rgb(300, 0, 0)` it used to clamp. Fonts: Source Serif 4
  4.004 bundled (one variable face); `Library::new` maps `serif`,
  `sans-serif` and `monospace` to Source Serif 4, Source Sans 3 and IBM
  Plex Mono, and `select_font` became a `fontdb` query over the text's own
  families, because usvg's default selector appends `serif` and would have
  drawn every missing family in Source Serif 4 unwarned; a generic is
  written bare by `measureText`'s probe and `textLines`. `measureText` takes
  `xmlSpace` (G-22, `TextFont.preserve_space`, in the memo key; `"a  b"` in
  Source Sans 3 at 64 px measured 80.448 default and 93.248 preserved), and
  whitespace-only text measures zero under either value. Each new case was
  made to fail once and reverted: the core clamping instead of refusing and
  an hsl channel by `floor` failed the core's fixture test; no `set_*_family`
  failed the generic-families case, usvg's default selector restored failed
  `a_missing_family_is_named_with_the_set_and_draws_nothing`, a quoted
  generic failed the generic measure case, the zero gated on
  `!preserve_space` failed the preserved-whitespace case with the family
  error, the flag left out of the memo key failed the preserve case,
  `__namedColour` answering nothing, the JS clamp restored and a JS hsl
  `floor` failed the stdlib fixture test (the clamp also `interpolate.test.js`),
  and `textLines` writing no `xml:space`, quoting a generic, or
  `measureText` dropping `xmlSpace` each failed `text.test.js`.
  `pins.json` passed unchanged. Issue batch B67 (2026-10-02, #105 part 3,
  phase c1: the store only) added G-23. An asset's name must be one
  `asset(name)` can use (no leading `.` or `#`, none of `/ : " ' < > &`, no
  control scalar, at most 247 bytes, which is 255 less the `.partial` the
  landing writes). `GraphicAssetName.swift` (pure) legalises a bad name as
  `importAsset` copies it in, so `#logo&mark.png` becomes `logo-mark.png`.
  A renamed copy never replaces: it takes `-2`, `-3`, … while the name is
  held on the scan or on disk. `import_graphic_asset` answers the name used
  and `renamed_from`, and File ▸ Add Image to Graphics… (its body moved into
  `addGraphicImage(from:)`) shows an informational sheet. The scan skips an
  illegal visible asset file with a warning. The font pass moved into
  `GraphicStore+Fonts.swift` (`GraphicStore.swift` stays at 394 lines) and
  keeps a verdict per file: a file whose size, modification date and file
  number are unchanged is not read or validated again. Accepted limit: a
  rewrite that keeps all three is not seen. Pinned by `graphics_store_probe`
  W18–W20 (26/26), `graphics_menu_proof` M13 (17/17) and `graphics_proof`
  I5 (46/46). Each was made to fail once. With `font-uncached`, W18's
  start() listed no font and warned `graphics/fonts/f.ttf: font bytes
  loaded no face`. With `asset-name-kept`, the copy landed as
  `#logo&mark.png`, unlisted, and the 300-byte name threw. With
  `asset-name-unchecked`, the scan listed `#bad.png` with no warning. With
  `notice-dropped`, no sheet appeared within 3 s. Run against B65's build
  (the baseline), I5 answered `name` `#logo&mark.png`, replaced it the
  second time, and the render warned that `logo-mark-2.png` is not in
  `graphics/assets/`. In that run G6, G2 and G10 also failed, because the
  baseline bundles the `graphics-api.md` from before this batch.
  `capture_spike/inventory.json` gained the notice's sheet site, and
  `addGraphicImage:`'s anchor became `@objc func addGraphicImage(`. The
  person's residue is GR-5 in `docs/manual-checks.md`: the sheet after the
  real open panel closes, in both appearances. Phase c2 (the three warning
  sources) is still owed. Issue batch B68 (2026-10-02, #105 part 3b, phase
  c2) landed it under a new G-24, and #105 closes with it. First, as a pure
  move gated alone (`make typecheck` 0 errors, 4 warnings), `loudnessResult`
  left `AgentServer+Render.swift` (591 → 542 lines) for a new
  `AgentServer+ExportResult.swift`. Compile: `rc_graphic_describe` answers
  `Module::warnings()` as `warnings` after `revision` (no new export, no
  format bump; `ffi_graphic.rs` 397 → 399), decoded by
  `GraphicModule.compileWarnings` in `GraphicRegistry.swift`, so
  `ReelCore.swift` gained no line; `write_graphic` and `get_graphic {name}`
  answer them as `diagnostics` with `ok` true, and they lead the Source
  section's rows. Scan: `get_graphic {}` answers `warnings`, and the Source
  section lists them under "In the graphics folder", each with Reveal.
  Accepted: a pass whose only change is a warning posts nothing (W7), so the
  pane shows it at its next rebuild. Export: a pin keeps a warning once per
  graphic and message set (`GraphicRegistry.sameWarning`), where before one
  graphic warning every frame filled the 64 and hid every later one;
  `Exporter.graphicWarnings`, published in `finish` before the unpin, feeds
  `export`'s `graphic_warnings`, the progress sheet's finish line ("N
  graphic warnings (hover for details).") and the queue row, whose count
  sits right after "Exported “…”." because its label truncates its tail;
  each tooltip lists them. Pinned by `core/tests/graphic_describe.rs` (2
  tests; both failed before the key with no `warnings` in the text),
  `graphics_proof` X1–X3 and Q4–Q5 (51/51, Z1 clean) and
  `graphics_inspector_proof` I18–I19 (61/61). Each was made to fail once.
  With `warnings-per-frame`, X1's export answered only `nofont`. With
  `sheet-unwarned` and `queue-unwarned`, Q5's line ended `Exported
  “q5-warnsheet.mov”.` and Q4's message was `Exported “q4-warnqueue.mov”.`.
  With `compile-warnings-dropped` and `folder-warnings-dropped`, I18 and I19
  alone failed. Against a build of HEAD plus only the pure move, X1 answered no
  `graphic_warnings`, X2 `diagnostics` `[]` and X3 no `warnings` (43/51; Q1–Q5
  failed there because the pin probe, which now calls
  `ExportQueueRowView.toolTip(for:)`, did not build over that tree). The
  person's residue is GR-6 in `docs/manual-checks.md`.

  Issue batch B69 (2026-10-02, #219 and #221) made a colour DEFAULT G-12's
  under a new G-25, and gave each Source group a heading true of it. First,
  as a pure move gated alone (`make typecheck` 0 errors, 4 warnings),
  `ShapePatch` left `ReelCore.swift` (1280 → 1196 lines) for a new
  `ShapePatch.swift`, the toll for the addition. #219 took the issue's
  option 2, an FFI export: a Swift copy would have been a third
  implementation of G-12, and hex defaults in `describe` would have changed
  the schema an agent reads back, in a file (`ffi_graphic.rs`) at 399/400.
  `rc_normalise_color` (`ffi.rs`, a new `colour` banner in the header) is
  `normalise_color` over the FFI, NULL for NULL, non-UTF-8 or refused text;
  `ReelColor.normalise` wraps it, and `GraphicSchemaRows.defaultColor` reads
  a default through it, so a name or `hsl()` default draws in the well as
  its colour and `patchValue` nulls a value equal to it. Compile now refuses
  a default G-12 refuses, in the same sentence in both crates,
  `schema.<key>.default "<text>" is not a color`: the core's `check_entry` by
  `normalise_color`, the engine's by a reader `Module::compile` builds from
  `Engine::parse_colours`, which calls the stdlib's own `__parseColour` once
  per `colour_defaults` text under the compile's budget (`runtime.rs` 344 →
  371). `props` still receive the default as written. Accepted: a top level
  that reassigns `__parseColour` decides the engine's answer, bounded by the
  budget (a looping one refuses the default rather than hanging). #221: the
  Source section's compile rows sit under "Compiling the module" when there
  are any; the first-frame note shows only when a frame was drawn, "No
  errors or warnings at the clip's first frame" over no render rows and
  "Checked at the clip's first frame" over some; "In the graphics folder"
  is unchanged, as are the summary's counts. Pinned by
  `core/tests/colour.rs` (2 tests), `core/tests/graphic.rs`'s
  `a_colour_default_is_checked_against_the_colour_grammar`, the sweep's
  `rc_normalise_color` line, `graphic/tests/module.rs`'s fixture and tamper
  tests and `every_compile_sentence`'s `"bluish"`, and
  `graphics_inspector_proof` I20–I21 (65/65, Z1 clean). Each was made to
  fail once. With the core's arm back to `is_string()`, the
  `add_graphic_clip` test applied a refused default; with the export
  answering NULL, the fixture test failed at its first accepted case; with
  the engine's arm back to `default.is_string()`, the fixture, tamper and sentence tests
  failed. Mutants: `default-color-hex-only` failed I21 a and b,
  `compile-heading-dropped` I20 a and b, and `first-frame-note-unconditional`
  I20 b; `compile-warnings-dropped` and `folder-warnings-dropped` now fail
  I20 a and I20 c beside I18 and I19. I20 a's six keeps a family
  (`sans-serif`) where the spec stripped it: a `<text>` with none warns that
  the default family is not in the set.

  Issue batch B84 (2026-10-04, #103 part 1, phase 1; spec §11 G-27, G-28,
  G-29) built three of the not-built list's items for an agent:
  `delete_graphic`, `rename_graphic` and `restore_graphic`, over a store
  that keeps the last 10 texts of each module in `graphics/history/`
  (`GraphicStore+History.swift`: a pass keeps the text a module's new text
  replaced; `removeModule` keeps the deleted one; `moveModule` carries the
  history with the file and journals the pair in `history/renames.json`).
  The three bodies are `ProjectDocument+GraphicFiles.swift`'s, which both
  doors call. A delete is refused while a clip draws the module, naming the
  clips per container. A rename repoints every clip, the timeline's and
  every nest's, by `set_graphic {name}` with no schema as one step, "Rename
  Graphic" — no core op, no FFI; the op count stays 59 — and Undo is made
  safe by a repair the document runs after every committed change and once
  at the store's start, in one direction only: a journalled pair `[a, b]`
  says the app moved the file from `a` to `b`, and when a clip draws `a`,
  with no file and nothing kept, the file is moved back from `b` (which
  journals `[b, a]`, so Redo is the same repair). A file-less name WITH
  kept texts is a deleted module, and the repair leaves it alone, so Undo
  never puts a live module under a deleted one's name.
  The batch's review changed four things before the commit, each with a
  probe row and a mutant: the repair tried BOTH directions of a pair and so
  moved a live module under a name whose file was removed outside the app
  (now one direction, H10; G-28 (f) records the one case that cannot be
  told from an Undo); a rename whose journal pair was not written
  succeeded with nothing to heal its Undo (now refused, the pair written
  and read back before the history is folded, H13, and the journal put
  back as it was read when the fold then fails, H14); `start()` left a
  module's current text in its history, so a default restore rewrote the
  same bytes (now dropped at `start()`, H12); and a kept file changed by
  hand was restored under the revision in its name (now refused, H2). A
  rename onto a deleted module's name still folds the two histories and
  can prune the deleted text: G-28's accepted risk, said in the tool's
  description.
  The second review changed one thing and recorded three. Changed: a
  rename refused at the fold first journalled its pair the other way
  round, which invented a pair for two names that had none and could push
  the oldest real pair out of the 32; it now puts `renames.json` back as
  it was read, so a refused rename journals nothing and an earlier pair of
  the same two names is still there for Undo (H14, H16). Recorded as
  limits, G-28 (f) and G-29 (d): a crash inside a rename is not healed
  when it lands before the pair is written, or after it with kept texts
  still under the old name, where the repair reads the old name as a
  deleted module (H15 builds that state and measures that nothing moves;
  no order of the three steps closes both windows without a marker on
  disk); and a kept file changed by hand stays listed, and refuses a
  default restore while it is the newest. A chain of renames undone and
  redone step by step, claimed by G-28 (e), has its row (H17).
  The third review changed one thing and measured one. Changed: a rename
  refused at the CLIPS (the edit throws, or leaves a clip behind) moved
  the file back through `moveModule`, which journalled that move as a pair
  of its own — the invented pair the second review had removed from the
  fold's arm. `renameGraphic` now reads `renames.json` before the rename
  and puts it back after the move back, so "a refused rename journals
  nothing" holds for both arms (H18, with the probe's own `apply` throwing
  and applying nothing, with no journal and with an earlier pair). The
  put-back runs only when the move back succeeded: a move back that fails
  leaves the file at the new name, and the pair with it, so the repair can
  still make it (H18's last part, which fails the move back and then
  repairs). What that arm cannot put back is recorded in G-28 (d) and
  measured by H18: onto a deleted module's name the histories fold before
  the clips are asked, so the move back leaves the deleted text kept under
  the renamed module. Measured: G-28 (f)'s sentence that a default restore in
  the crashed state writes an older text was an inference; H15 now runs
  that restore in its own package.
  Rename is refused with a nest open, onto a name whose file exists, and
  onto a name a clip already draws with no file behind it. History is in
  the package, not `cache/`, because the cache is safe to delete; an
  untitled document's first save carries it. `write_graphic`'s note
  changed from "keep your own copy" to naming the kept text, and
  `write_graphic` / `get_graphic` answer `kept` (and `history` for the
  folder). The catalog is 89 product tools, thirty of them app-state.
  What a run printed: `graphics_store_probe.py` 45/45 (rows H1–H18 and C7
  new), its fifteen new mutants each `MUTANT PASS` (`history-unkept` failed
  H1, H2, H3, H5, H12, H13, H14, H15, H16, H17, H18 and C7;
  `history-uncapped` H3; `delete-used` H4; `rename-unreconciled` H5, H16,
  H17 and H18, of which H5 and H17 are required; `history-left-behind` H5,
  H14, H16, H17 and H18; `reconcile-over-delete` H11 and H15;
  `rename-onto-drawn` H8; `journal-uncapped` H9;
  `reconcile-both-directions` H10; `rename-unjournalled` H13;
  `start-undropped` H12; `restore-unhashed` H2; `rollback-unjournalled`
  H14, H16 and H18, of which H14 and H16 are required;
  `moveback-unjournalled` H18; `moveback-unconditional` H18);
  `graphics_files_proof.py` 10/10 over MCP on its own instance in a scratch
  home, and its `--mutant rename-unreconciled`, an app built in a tree copy,
  9/10 with N2 failed (after the undo clips 2 and 3 named `title` beside a
  folder holding `headline`, and the frames differed).
  **Phase 2** (2026-10-04 into 2026-10-05, #103; spec §11 G-30) is the
  person's door. File ▸ Rename Graphic…, Delete Graphic… and Restore
  Graphic Version… sit in a group of their own under Add Image to
  Graphics…, with no key equivalents, and put up ONE sheet
  (`GraphicFileSheetController`): a pop-up of the project's graphics, a
  New name field for Rename, a "<n> versions kept" line for Restore and no
  history browser. Every act is one call of a phase-1 body, so the two
  doors refuse in the same sentences: a refusal is shown word for word in
  a label inside the sheet, which stays up, the tool's hint
  `(set_graphic {name})` included — the owner chose one wording over a
  second for people. A delete has no second confirmation, because the text
  is kept. Rename and Restore open on the one selected clip's graphic when
  it is a row, a deleted one too (how a clip showing the error card gets
  its code back); Delete always opens on the first, since a selected
  clip's graphic could not be deleted. The items are greyed with nothing
  to list, and Rename while a nest is open. The hints were corrected in
  design: the first wording promised an Undo for renaming a graphic no
  clip uses, which makes no edit, and a way back after restoring a deleted
  graphic, which keeps nothing in its place. No op, tool or count changed
  (89 product tools, thirty app-state). `EditorViewController+GraphicFiles.swift`
  holds the three actions, the one `presentAsSheet` and the validator arm
  that `validateGraphicMenuAction`'s default forwards to; no line of the
  frozen `EditorViewController.swift` changed.
  What a run printed: `graphics_menu_proof.py` 27/27 on one instance in a
  scratch home (rows S0, M14–M20, S1 and S2 new; a confirm is reached in
  the probe's process through the sheet's own controls, because no dev
  tool presses a sheet's default button); its ten new probe-tier mutants
  each `MUTANT PASS` under Rule R1, the mutant's row the FIRST failure
  (`item-dropped` M14; `rename-in-nest` M15; `refusal-unshown` M16, then
  M19; `refusal-unwrapped` M16; `delete-opens-selected` M16;
  `success-undismissed` M17, then M18 and M20; `rename-ungrouped` M18;
  `opening-first` M18, then M19 and M20; `rename-field-lowercased` M19;
  `restore-deleted-unlisted` M20), `notice-dropped` still M13; its two
  app-tier mutants, an app built in a tree copy each, `app-rename-in-nest`
  failing S1 and `app-sheet-unpresented` S2; `screens.py` over the three
  new screens (15b, 15c, 15d) 8 pass of 8 with 0 new problems;
  `graphics_files_proof.py` 10/10 and `graphics_proof.py` 51/51 as before.
  One instrument fault was found on the way: the first `opening-first` run
  ended the probe with an exception, because after its row failed a later
  step pressed Cancel on a sheet that a mis-opened rename had already
  closed; the probe's `press` now refuses a button whose sheet is no
  longer attached, and the runs quoted are the ones made after that.
  The review changed two things. A proof run under a scratch home that did
  not exist yet was told every key of the owner's defaults had moved,
  though none had: `defaults export` answers no key under a
  `CFFIXED_USER_HOME` naming an absent folder and the whole domain once
  the folder is there, so `mcp.py`'s guard recorded one thing and compared
  another. The guard now reads with that variable taken out of `defaults`'
  environment (`proof_defaults.read_env`; `defaults_proof.py` rows H1 and
  H2, 10/10, with `--mutant home-followed` failing exactly those two), and
  the three screens run from a work folder with no home in it scored 8
  pass of 8 with no `DEFAULTS MOVED` line. And the three items' validator
  built every pop-up row on each menu open, listing each module's history
  folder for a count the Rename and Delete sheets do not show; `isOffered`
  now asks the last scan for Rename and Delete and `keptNames()` for
  Restore, with the same answers (`graphics_menu_proof.py` 27/27 again;
  `rename-in-nest`, `restore-deleted-unlisted` and `app-rename-in-nest`
  still caught).
  What only a person can judge — how the three sheets look in both
  appearances, a refused Delete's sentence on screen, a real keyboard
  typing into New name — is `docs/manual-checks.md`'s GR-7.

  Issue batch B85, phase 1 (2026-10-05, #103 part 2; spec §11 G-31) built
  the not-built list's path helpers: `getLength(d)`,
  `getPointAtLength(d, length)` and `evolvePath(progress, d)` in
  `graphic/src/path.js`, a third standard-library script evaluated after
  `noise.js` and before the sandbox. Pure JavaScript, no host function:
  the path is parsed once (every command, both cases, SVG's number
  grammar, unseparated arc flags), flattened — a line exactly, a curve as
  64 chords, an arc as chords of at most π/128 rad — and memoised by its
  text, at most 32 paths and 50,000 chords-plus-characters, in a closure
  no module can reach. The global the spec named, `__path(d, who)`, is not
  one: a global answering the memoised record would hand a module the
  memo's state, so the closure answers the three functions and the record
  never leaves it (`noise.js`'s shape). A draw-on is dashed by the LONGEST
  subpath times 1.001, because tiny-skia restarts the dash on each
  contour; a heading where the derivative is zero is the tangent's limit;
  a path that cannot be read throws, naming the character. The reference
  gained the section, the draw-on idiom was rewritten over `evolvePath`
  and "Follow a path" was added; both idioms were drawn once through
  `render_graphic` on a scratch instance and looked at (a throwaway run,
  not a row).
  What a run printed (`cargo test --release --test path -- --nocapture`,
  6 passed): the relative errors against the closed forms — the circle
  of radius 500 and the ellipse, plain and turned 30°, 2.51e-5 each; the
  parabola as a `Q` and as a `C` 4.92e-5; the cusp 6.29e-6 — all inside
  G-31's 1e-4, the parabola by a factor of two; a fresh path of 200
  cubics with 1,000 points taken, 16.6 ms of the preview's 250; a
  17,000-segment path over the memo's cost bound measured twice with a
  point taken, 56.3 ms. `path_test_js` (rows T1–T9, each in its own `try`,
  T5's two limit rows scored apart) passed. The five mutants, each applied
  to `path.js` by hand, run and restored: `chords-4` — the one message
  named T2 (the circle 3121.445 for 3141.593), T3 and T4, and R1's circle
  and R5 failed too; `unpadded` — T7 failed, and R1 PASSED (recorded, not
  required: no pixel row catches a missing pad);
  `relative-as-absolute` — T1 failed (54.14 for 40), and R4; `total-dash` — T7 failed (160.16 for 100.1) and R1's
  two-subpath pixels (the long line red past its tip); `raw-derivative` —
  both of T5's limit rows failed (0 for 90). `graphics_path_proof.py`, on
  its own instance in a scratch home, 6/6: its control M0 (the oracle
  answers False for a ring of half the radius), the ring's dash
  1886.7932 for 2π·300·1.001 = 1886.8405, the offset half of it, the dot at
  (960, 840), and `graphic_reference` naming `evolvePath(progress, d)`.
  `make test` exit 0 (94 `test result: ok`), `make lint` clean, `make
  typecheck` 0 errors and the 4 warnings, `make app` built. No core, FFI,
  Swift, op, tool or catalog file is in the diff, so no count moved (B84
  left 89 product tools and 59 ops), and `tests/pins.json` was not
  re-pinned. Owed by the batch's later phases, each its own pipeline:
  `paste_attributes` between graphic clips of one module with Edit ▸
  Paste Graphic Properties (phase 2), and HEVC with alpha as an export
  row (phase 3).

  The review's fix pass (2026-10-05) made one thing the first build
  answered a refusal, and G-31 (e) now says so: no helper answers a
  number that is not finite. As built, a number too large for a double's
  arithmetic was answered — `getLength` `Infinity` or NaN, and for an arc
  whose centre form came out NaN the answers of a path with nothing
  drawn, the silent zero (e) rules out — and G-31 had recorded it as a
  risk accepted. `path.js` (385 lines) now refuses such a path in the
  parse sentence, at the number or at its command, by five checks: the
  number read, a move's point, an arc's centre form, the running length,
  and the point answered. `path.test.js` gained the row `T8 a number that
  is not finite` — twelve cases, ten refusals over the five checks and
  two controls that expect an answer, every case run though another
  failed — and T5 an arc drawn with sweep 0, the sign of whose heading no
  row held. A sixth mutant, `non-finite` (the one predicate answering
  true): the one message named all ten refusals — `M 0 0 L 1e999 0`
  answered `Infinity`, the same path going on NaN, `M 0 0 A 1e300 1e300 0
  0 1 1 0` answered 0, a point of a curve one step under the largest
  double x `Infinity` — and neither control; `path.rs` passed, holding no
  such row. Each of the five checks was then removed alone (extras,
  `path_test_js` only): number 2 cases, move 1, arc 2, running length 4,
  point 1 — each case under exactly one. The five earlier mutants, run
  again on the fixed file, failed the rows named above,
  `relative-as-absolute` now two of the new row's cases as well; an
  extra, `arc-turn` (the sign dropped), failed T5 (angle 1.6e-14 for
  180); and `path.js` was written back byte-equal to the copy taken
  before. On the fixed file `cargo test --release --test path --
  --nocapture` printed 16.6 ms for the 200 cubics and 67.6 ms for the
  17,000-segment path (56.3 in the first build's run), the six relative
  errors unchanged. The reference gained the refusal and the memo's two
  limits, which an agent otherwise meets as a budget error. After it:
  `cargo test --release` in `graphic/` 125 passed, `make test` exit 0 (94
  `test result: ok`), `make lint` clean, `make app` built,
  `graphics_path_proof.py` 6/6 again. `make typecheck` was not run again:
  no Swift or helper file is in the pass.

  Issue batch B85, phase 2 (2026-10-05, #103; spec §11 G-32, amending
  G-10's paste sentence) built the not-built list's `paste_attributes`
  for graphics. `paste_attributes` takes a fifth group, `graphic`, that
  copies the payload clip's `graphic.props` whole onto clips drawn by the
  SAME module — the target keeps its name, size, `in` and `length` — and
  a flag, `skip_missing`, that drops a named group the payload clip lacks
  and skips a target that cannot take one instead of refusing the call.
  `graphic` is never in the default set, so ⌥⌘V and a tool call with no
  `groups` do what they did (the owner, 2026-10-04: props hold a
  graphic's words as well as its look). The person's door is a new item,
  Edit ▸ Paste Graphic Properties, directly under Paste Attributes with no
  key: one op, `groups: ["graphic"]` with `skip_missing`, the undo step
  "Paste Graphic Properties"; it is enabled when Frame Job clips are on the
  clipboard and a graphic is selected, and beeps when nothing takes the
  props. The copied map is checked for shape only, the first time a
  target takes it, so a paste nothing takes never reads it.
  The phase opened with a pure move, gated alone: `paste_attributes`, its
  two helpers and its doc section left `core/src/edit_paste.rs` (593
  lines) for a new `edit_paste_attributes.rs` (467 and 143 at the gate:
  `cargo fmt --check`, `cargo test --release` 73 `test result: ok` with
  1,014 passed, `make lint` clean); the group is a paste-only enum,
  `PasteGroup`, and `patch::Group` gained no variant. The clipboard
  extension's readers and writers now take their pasteboard as a
  parameter, the general one by default, so the probe below never
  touches the owner's clipboard. No FFI export, no format bump, no new op
  and no new tool: no count moved.
  What the runs printed. `cargo test --release` in `core/`: 74 `test
  result: ok`, 1,025 passed, 0 failed; the new `core/tests/paste_graphic.rs`
  10 passed (T1–T8, T10, T11), `op_default_booleans.rs` 5 passed (T9).
  Eight core mutants, each one replacement in a scratch copy of `core/`
  and `graphic/` under `tools/proof/work/paste-graphic/core-copy/`, each
  run alone after a control that passed: the default set gaining
  `graphic` failed
  `a_paste_that_names_no_graphic_group_copies_no_props` (and the
  no-groups-under-the-flag test); the copy also writing `width` failed
  `naming_graphic_copies_the_props_whole_and_the_target_keeps_the_rest`
  (and the nest test); the name comparison removed failed
  `a_named_graphic_group_a_side_cannot_serve_is_an_error_and_nothing_changes`
  and `skip_missing_skips_what_cannot_take_a_named_group` (and the
  unread-map test); `check_props` removed failed
  `a_malformed_copied_map_onto_a_matching_clip_is_the_maps_own_sentence`
  (and the unread-map test); `skip_missing` read as false failed
  `skip_missing_skips_what_cannot_take_a_named_group` (and the unread-map
  test); the default set gaining `graphic` only under the flag failed
  `with_no_groups_skip_missing_changes_nothing_and_copies_no_props` alone,
  the no-groups test still passing; the shape check hoisted above the
  target loop failed `a_copied_map_no_target_takes_is_never_read` alone;
  and `Kind::Groups`' values losing `"graphic"` failed `op_table`'s
  `every_closed_vocabulary_answers_with_its_own_members`. 8 of 8 caught.
  `paste_graphic_probe.py` (the menu door, compiled from `app/Sources`,
  every Copy and paste over a private pasteboard) 9/9: K0–K8, the general
  pasteboard's `changeCount` 2480 at start and at end; its six mutants
  each caught (1/2, exit 1) — `door-no-groups` and `door-strict` failed
  K3, `validator-any-selection` K2, `attributes-names-graphic` K5,
  `action-empty` and `action-pastes-attributes` K8.
  `paste_graphic_proof.py` (the tool over MCP, its own instance in a
  scratch home) 8/8: H0, T0, P1–P5, Z1; its two mutants, each an app built
  in a tree copy, `MUTANT PASS` — `handler-drops-skip` failed P4 (and
  P5), `groups-without-graphic` failed P1 (and P3–P5) while T0, a
  control, passed, as designed. On one instance in a scratch home, its log
  holding no `Reelcut: ` line: `clip_catalog_proof.py` 24/24,
  `op_catalog_proof.py` 23/23, `phase2_proof.py` 86/86. `v2_menu.py --only
  H` 5 pass, `op_schema_probe.py` 28/28, `inventory.py --check` 5/5,
  `spec_index_proof.py` 138/138. `make test` exit 0 (95 `test result:
  ok`) on its second run — the first failed in
  `core/tests/op_nullability.rs`, which holds the list of plain booleans
  and now names `paste_attributes.skip_missing` as the fifth — `make
  lint` clean, `make typecheck` 0 errors and the 4 warnings, `make app`
  built. `AgentServer+Clips.swift` and `AgentCatalog+Clips.swift`, both
  over the cap, ended at the 856 and 801 lines they began at.
  The phase's review found the menu's one-line action,
  `pasteGraphicProperties(_:)`, held by the typecheck alone: emptied, or
  given ⌥⌘V's body, it passed every row. The action now reads a
  pasteboard SENDER in place of the general pasteboard (a menu sends its
  `NSMenuItem`, so the app still reads the general one), and K8 sends
  `pasteGraphicProperties:` to the controller with the private pasteboard
  as its sender and holds K3's claims: `K8 pass`, B's props equal to A's,
  the undo step "Paste Graphic Properties", in the 9/9 above. Its two
  mutants each printed `caught — K8 failed`: with the body emptied the
  project did not change, and with ⌥⌘V's body over the same sender it
  changed under the step "Paste Attributes", B keeping its own props and
  not what is outside `graphic`.
  After that fix — Swift, the probe and documents, no core or graphic
  file — `make typecheck` (0 errors, the 4 warnings), the probe and its
  six mutants, `make app` (built), `paste_graphic_proof.py` (8/8),
  `inventory.py --check` (5/5), `spec_index_proof.py` (138/138) and
  `v2_menu.py --only H` (5 pass) ran again; `make test` and `make lint`
  did not. Owed: the person's check, TL-8 step 4 in
  `docs/manual-checks.md`; and by the batch's last phase, HEVC with alpha
  as an export row (phase 3).

  Issue batch B85, phase 3, PHASE A (2026-10-05, #103; spec §11 G-33) is
  the first of the two phases the HEVC-with-alpha work is gated in, and
  builds no row: it makes the size an export REPORTS the size the file
  has. G-33 was written first, for the whole feature — the even rule,
  the fill rule, the `hevc_alpha` row, the encoder outcome — with the
  NARROWER fill rule the orchestrator chose on 2026-10-05 (the overshoot
  half only for a frame within one pixel of the canvas on each axis; the
  integer sweep G-33 (c) quotes was re-run in fix pass 1 with that arm
  as its own column, `tight` — 4,196,351 exact, 12,572,674 filled and 0
  neither of 16,769,025 evened Document rows, 1,961,452 / 65,114,648 / 0
  of 67,076,100 standard rows, 4,094 of the 8,192 one-pixel-edge
  canvases neither, each the designer's wider arm's count), and it
  supersedes the owner's choice 18 (a): there is no refusal for an odd
  size as such (what holds exactly, as phase B's fix pass 1 left it: no
  size of the canvas's own shape is refused for being odd). Of G-33 this
  phase BUILDS only (b): the row, the fill rule, the
  guard's test and the encoder outcome are decisions phase B builds, and
  until it does G-33 says so in a note under its heading and words them
  as what is to be — after fix pass 1 of this phase's review, which
  found (d), (e), (f) and (h) reading as built. Phase A is G-33 (b).
  `Preset::even_sized` (`export_table.rs`) is true for every row
  AVFoundation writes but `prores_4444`; `export_size::even_size` makes
  an odd edge one pixel smaller and an edge below 2 two;
  `Project::export_settings` applies it after the width and height are
  read, and `Project::export_sizes` lists the canvas evened as the
  `document` row, named "Document (even)" when that is not the canvas's
  size. No `rc_*` export, no schema, no format version, and no Swift
  logic: the three Swift files touched are comments and the `export`
  tool's `size` description (`ExporterWriter+Settings.swift`,
  `AgentCatalog+Files.swift`, and `ReelCore.swift`, which stays at 999
  lines). So `h264`, `hevc` and `prores_422` write the files they wrote
  (frame and picture; the bit rate, below), and the Size popup, the
  readout, the size fields and the tool's answer now say 320 × 180 on a
  321 × 181 document where they said 321 × 181. **The baseline came
  first**: `tools/proof/hevc_alpha_baseline.json` was recorded twice on
  the build of main at 055a5ed before any core or Swift edit, 17 cases,
  the two recordings agreeing on every value; the recorder requires that
  build's answer to say the odd size over an evened file and each
  odd-canvas file to hold a black edge pixel, and Gate A's rows on that
  build printed 6/11 (T0, R1, R2, R4 and E2 failed). The baseline is one
  host's bytes — hardware bitstreams, ffprobe's values, ffmpeg's digests
  — and since fix pass 1 says whose: it carries `host` (Apple M2 Max,
  macOS 26.5.1 (25F80), ffmpeg 9.0.2) and `head`, now the commit of the
  BUILD's own work tree and not of the checkout the script sits in; the
  rows print the host and, on another host, score nothing and exit 2
  (the instrument, not the product). The host was stamped into the
  existing file without re-recording — the recorder cannot run on a tree
  with the resolver — so the 17 cases are the two 055a5ed recordings,
  unchanged (`tools/proof/README.md` says how). **Gate A, on phase A's
  build:** `cargo test --release --test export_size` 20 passed (five new
  tests, three rewritten; five hand mutants of `core/src/`, each
  caught), `--test export` 35 passed, `cargo fmt --check` clean, `make
  lint` clean, `make typecheck` 0 errors and the 4 warnings,
  `spec_index_proof.py` 138/138, `make app` built, and
  `hevc_alpha_proof.py --rows size` 11/11: the answer and ffprobe agree
  at 320 × 180 and 180 × 320 on the three rows (R1, R2), `prores_4444`,
  `apng` and `gif` keep 321 × 181 (R3), the sheet reads "Document (even)
  · 320 × 180" (E2), `hevc` on an even canvas and `prores_4444` at three
  sizes equal the baseline by frame digest (B1, B4), and the six
  odd-canvas files equal the baseline by frame digest and by eight edge
  pixels, the black pad still there, with `hevc_alpha` still an unknown
  preset (G1) — phase A moved no pixel of them. `make test` was not run
  in this phase (Gate A does not name it). One thing the proof found on
  the way: the launch argument `-FrameJobExportChoice {"preset_id":…}` is
  dropped by the argument domain, so the instance read the owner's
  remembered export choice; the value is sent as a `<string>` plist
  fragment. E2 also requires the Format popup to read "H.264 (MP4)" or
  "HEVC with Alpha (MOV)", which fails the row when the pin did not take
  and the owner's remembered format is another one (as it was on this
  host); in phase A, where a taken pin names a row the build lacks and
  the sheet falls back to H.264, an owner who last exported H.264 cannot
  be told apart — phase B's row requires "HEVC with Alpha (MOV)"
  exactly. **The owner's defaults, which those launches read:** by
  reading, nothing the proof does can write the remembered choice —
  `ExportChoice.remember()` (`ExportPresetsStore.swift`) is the key's
  one writer and `ExportSheetController.commit(queue:)`, the Export and
  Add to Queue buttons, its one caller; `cancel_sheet` presses the
  sheet's Escape button, whose action only dismisses; and the `export`
  tool's handler (`AgentServer+Render.swift`) reads and writes no
  default. By a run: the stderr of the two recordings and of the gate's
  red and green runs was NOT kept, and another Frame Job was alive then,
  so `mcp.py`'s guard would only have printed a moved key there, not
  failed the run — nothing is claimed of those four from their output.
  Fix pass 1's `--rows size` run kept it: 11/11, exit 0, stderr empty —
  no `mcp: DEFAULTS MOVED` line and no line saying the guard could not
  read the domain (another Frame Job, `/Applications/Reelcut.app`, was
  alive, so the line and not status 3 is what a moved key would have
  been). Not shown by the gate: a bit rate computed from the evened
  pair, the one thing of a FILE phase A moves. The default
  (`ExportWriter.defaultVideoBitrate`) on an odd canvas above its 1 Mbps
  floor is 0.25 % lower at 1001 × 667, by arithmetic; and the rate a
  chosen Quality tier of the sheet sends is computed from the Document
  row's numbers, now even (`ExportSheetResolve.requestedFormat()`, by
  reading) and rounded to the nearest 100 kbps, so it moves only across
  a rounding step (High for `h264` at 1001 × 667: 2,600,000 either way)
  — in Custom it is computed from the typed pair, as before. An odd size
  ASKED on an even canvas resolves even too (R4), so "an even canvas is
  byte-for-byte what it was" holds only with no odd size asked; G-33 (b)
  says both. Owed by phase B, its own pipeline: the `hevc_alpha` row,
  the fill rule and the guard's integer test, `Exporter.encoderOutcome`,
  the Document tab's note, the rest of the proof with its mutants and
  controls, SE-9 in `docs/manual-checks.md`, and this list's "HEVC with
  alpha" entries; and the `CLAUDE.md` edits for both phases.

  Issue batch B85, phase 3, PHASE B (2026-10-05, #103; spec §11 G-33) is
  the row and what it needed, and the last of #103 this batch builds.
  `hevc_alpha`, "HEVC with Alpha (MOV)", is the tenth export row, directly
  after `hevc`: `ExportWriter` writes `AVVideoCodecType.hevcWithAlpha`
  into a QuickTime movie with AAC sound, HEVC's dictionary and default
  rate plus the one key that declares the pixels premultiplied, network
  optimisation off unless asked. **The fill rule** is one integer test,
  `ExportWriter.shapeGap`, shared by the alpha guard and the scaling mode,
  with the first arm G-33 (c) records — a canvas-shaped size less at most
  one pixel on each axis, at any scale; fix pass 1, below, is how it came
  to be that and not the tighter arm first built: a frame within a pixel
  of the canvas's shape, or such a size, is written
  `AVVideoScalingModeResizeAspectFill` on every movie row, an exact one
  and one further off as before, and on the two alpha movie rows one
  further off is refused in the shape sentence. No size of the canvas's
  own shape is refused for being odd, and there is no new error case.
  `Exporter.encoderOutcome`,
  one replaced line in `Exporter.swift`'s `startWriting`, turns a failed
  write whose error is `AVFoundationErrorDomain` −11834 into the preset's
  own sentence and removes the 0-byte file. `DocumentPane.transparencyNote`
  names one or two alpha formats and counts three or more. The `export`
  tool's `preset` and `size` descriptions say all of it; no handler, no
  `rc_*` export, no schema and no format version moved (10 presets; the
  op and tool counts are B84's). `ExporterWriter.swift`, `Exporter.swift`
  and `ReelCore.swift` stay at 782, 588 and 999 lines;
  `ExporterWriter+Settings.swift` is 391 and `export_table.rs` 564. G-33
  was read back against the build: its note is gone, (c)–(f) are in the
  present tense with the built app's figures beside the designer's, and
  two things it had not foreseen are written into (a) and (h) — below.
  **Verified:** `cargo test --release --test export` 38 passed (three new
  tests; `the_hevc_row_is_what_it_was` holds the `hevc` row and its
  settings to literals printed before the row was added) and `--test
  export_size` 20; `make test`, `make lint`, `cargo fmt --check`, `make
  typecheck` (0 errors, the 4 warnings) and `make app`;
  `hevc_alpha_proof.py` 29/29 with an empty stderr — the decoded alpha of
  a clear, a half and an opaque pixel (A1–A4), AAC in the `.mov` (A5),
  the two refusals (S1, S2), every edge at alpha 0 on the evened and the
  within-a-pixel sizes of both alpha movie rows (O1, O2, O4, P1, P2), no
  black line on `hevc`, `h264` and `prores_422` where the baseline has
  two (B2, B3), the letterbox kept for another shape and for a frame
  typed wider than the canvas (L1, L2), `hevc` on an even canvas and
  `prores_4444` at three sizes equal to the baseline by frame digest (B1,
  B4), the note (N1) and the sheet's Format popup and footnote text (E1);
  its two controls (the alpha readers fail on plain `hevc`; the sheet
  with no pinned choice fails E1); its three mutants, each built in a
  tree copy and each exit 0 (`encoder-refused`: the sentence and no file,
  and "Cannot Encode" over a 0-byte file with the mapping off;
  `report-and-fill`: the size and fill rows fail; `shape-and-note`: S1,
  N1, L2 and S2 fail, S2's `prores_4444` half by the wider limit alone,
  and L1 with every frame filled); `phase7_chrome.py` 79/79 and
  `phase7_proof.py` 92/92 on an instance of its own. The first
  `report-and-fill` run failed on a fault in the script (a mutant's launch
  was not handed the baseline, so L2's columns clause could not hold); it
  was fixed and that mutant built again. **Gate A is red on this build by
  design:** `--rows size` prints 10/11 and exits 1, G1 saying so — it
  requires the pad and an unknown `hevc_alpha`. **Another host:** the
  rows that read no digest are scored there, B1, B4 and G1 are not, and
  the script exits 2 (run once against a foreign-stamped copy of the
  baseline: 27/27, exit 2). **Found on the way, and not fixed:** (1) the
  export sheet's footnote is drawn CUT on both alpha movie rows, before
  the word "alpha" — its slot beside the three buttons is 88 pt and
  "HEVC_ALPHA · MOV · alpha", like the shipped "PRORES4444 · MOV · alpha",
  needs 144. Its tooltip was set once, empty, and never followed the
  text; fix pass 1, below, made it follow, so resting the pointer on the
  footnote shows the whole line. Owner choice 14 therefore holds of the
  footnote's text and its tooltip and not of the sheet's drawn face: the
  spec's row E1 required it untruncated, E1 scores the text and the
  tooltip and prints the cut, and room for the summary on the face — a
  line of its own, or a wider sheet, either a visible change to every
  format's sheet — is the owner's choice. (2) Frame Job composites a
  re-imported `hevc_alpha` or `prores_4444` movie as straight alpha: a
  half-opaque red card over white comes back (191,127,127) and
  (193,129,127), where about (255,128,128) is right (the proof's line I1,
  printed and never scored). (2) goes to an issue. Owed: the person's
  check SE-9 in `docs/manual-checks.md` (the note, the footnote and its
  tooltip, and the file played in Safari, QuickTime Player and Final
  Cut), and the `CLAUDE.md` edits for the phase.

  Phase B, fix pass 1 (2026-10-05, the phase's review: two findings,
  both fixed). **(1) The first arm of the fill rule.** As first built —
  the canvas ITSELF less at most a pixel on each axis, the orchestrator's
  tighter choice — it REFUSED an odd size typed in the canvas's own
  proportions on `hevc_alpha`: the core evens `[720, 405]` on 1920 ×
  1080 to 720 × 404, gap 1920 against a limit of 1080, and the sentence
  named a size nobody sent and ended "or at any size with the same
  proportions". The orchestrator amended its decision: the arm is a
  canvas-SHAPED size less at most one pixel on each axis, at any scale
  (one line of `shapeGap`: `d` is one of 0, `cw`, `−ch`, `cw − ch`),
  with the costs G-33 (c) lists accepted — 396 × 98 and 404 × 100 on
  400 × 100 are filled on every row, an odd canvas-shaped typed size is
  filled on the opaque rows, `prores_4444` writes such frames where it
  refused them, and a tiny frame gives up a large share. The new row O5
  — `hevc_alpha` asked `[400, 225]` and `[1296, 729]` on 640 × 360 and
  `prores_4444` a typed 400 × 224, each written with all four edges at
  alpha 0 — printed all three REFUSED on the build before the line
  changed, and `report-and-fill` names it. The integer sweep was run
  again with the amended arm as its own column: the Document and
  standard rows' six counts are unchanged, none of the sizes in the
  canvas's proportions is refused on ten canvases (the first arm refused
  256 of 512 on 1920 × 1080), and the frames of L1, L2, S1 and S2 are
  past the limit under both. Every sentence that said no size is refused
  for being odd says what holds: no size of the canvas's own SHAPE is,
  and a typed size of another shape is judged as the even frame it
  becomes (1279 × 720 on 1920 × 1080 is filled on `prores_4444` and, as
  1278 × 720, refused on `hevc_alpha`; by arithmetic). **(2) The export
  sheet's footnote** — its tooltip follows its text (two lines in
  `ExportSheetResolve.syncReadout`, now 578 lines;
  `ExportSheetController.swift` stays at 639), the layout dump carries
  each view's `tooltip` (`UISnapshotLayout.swift`, 222), and E1 requires
  the footnote's to equal its text: on a build with the key and without
  the two lines it read the empty string. No layout changed; SE-9 says
  what a person sees. **Verified after the last source edit:** `make
  typecheck` (0 errors, the 4 warnings), `make app`,
  `hevc_alpha_proof.py` 30/30 with an empty stderr (its red, on the build
  with the dump's key and neither fix: 28/30, O5 and E1), both controls,
  `report-and-fill` and `shape-and-note` built again and passing
  (`encoder-refused` was not: its two anchors still occur once and its
  rows did not change), `phase7_chrome.py` 79/79, `phase7_proof.py`
  92/92 on an instance of its own, `make test` (1171 tests in 95 result lines, 0 failed, and its six proofs and the defaults sweep) and `spec_index_proof.py` 138/138; the core did not
  change, so `make lint` and `cargo fmt --check` were not run again.
  **Seen once:** the first full run on the fixed build printed 29/30 —
  B1, `hevc` on an even canvas, differing from the baseline in its
  ffprobe stream and format values with frame 0's digest equal — and
  eight later reads of the same build were equal; that line did not print
  which values moved (`held` prints them since). **Fix pass 2
  (2026-10-05, the second review of phase B)** took the byte counts out
  of the row, changing no app source. B1 had compared the stream's
  `bit_rate` and the file's `size` and `bit_rate` — byte counts of a
  hardware HEVC bitstream, which the encoder does not promise to repeat —
  and now prints those three beside the baseline's and compares the rest:
  the stream's and the file's fixed parameters, the alphas, the corner
  and frame 0's digest (`B1_UNSCORED`; the baseline file is as it was
  recorded). Shown by import on the built app, through the row itself:
  today's case and a copy with only the three values altered read equal,
  and copies with the profile, the frame count, the duration or frame 0's
  digest altered fail, each line naming what moved (7 of 7 variants as
  expected); then `hevc_alpha_proof.py` 30/30 with an empty stderr and
  both controls. Whether the one failed run was those three values is not
  known — a frame count or a duration that moves still fails the row —
  and what the row gives up is a change of the encoder's rate, which this
  640 × 360 fixture could not see for the line phase B changed (G-33
  (h)). The same pass wrote the dump's `tooltip` into spec §7.9c and ran
  the two readers of the dump not run since the key was added, each on an
  instance of its own in a scratch home: `v2_snapshot.py` 29 pass, 0
  fail, one named host skip (O2), and `screens.py --only 12-export-sheet`
  6 of 6 over its two looks; `spec_index_proof.py` 138/138. Nothing was built
  and no mutant run: no anchor is in the proof. Owed as before, with the
  `CLAUDE.md` text now following the amended arm.

## Keyframed props (#239, spec §11 G-34)

Issue batch B87, 2026-10-07, four phases after the owner answered I-239's
seven choices "as recommended" (G-34's preamble names which sub-entry holds
each; the paste answer is G-34 (d)). G-10's props half is superseded; its
layer half and G-32 (h) stand.

- **Phase 1, the core rule (826439d).** Toll A first, gated alone:
  `actions.rs`'s clamps to `actions_clamp.rs`. Then `set_action_end` takes
  `graphic.props` with an app-filled `schema` (`edit_action_graphic.rs`);
  the end stores each prop's schema type in `kinds` (a caller's is
  discarded); a prop the clip lacks starts from the schema's default,
  written into the clip in the same step (G-34 (d)); `actions_graphic.rs`
  evaluates — a number in floating point, never rounded, a colour four
  channels straight, everything else switching at the end; the recipe draws
  the evaluated props, `split` carries them, and `set_graphic`'s and
  `paste_attributes`' nulls keep an animated prop's start. Format version 13.
  Measured: `cd core && cargo test --release` 1082 passed (three new
  binaries, `graphic_actions.rs`, `graphic_action_door.rs`,
  `schema_v13.rs`); seventeen mutants (M1–M16, M2 in two forms), each
  failing its named test.
- **Phase 2, the agent's door (34c11e4).** Toll B first, gated alone (the
  action handlers and catalog rows to `AgentServer+Actions.swift` and
  `AgentCatalog+Actions.swift`, the bundle's catalog equal to the
  baseline's). The `set_action_end` handler fills `schema` from the
  CURRENT revision of the clip's module, in the call's scope; the tool's
  prose and `docs/graphics-api.md`'s "Animating a prop from the timeline".
  Measured: `graphic_prop_action_proof.py` 17/17 — `render_frame` mid-action
  equals a still clip holding the evaluated values byte for byte, a string
  switches on the end tick, undo and redo restore the bytes, the export with
  the prefetch on equals it off — and its two mutants
  (`handler-no-schema`, `recipe-stored-props`) caught.
- **Phase 3, the Graphic tab (242c33d).** Tolls C and D first, each gated
  alone (`ActionSnapshot.swift`, `InspectorRows.swift`). With an action
  selected the Properties rows read and write the action's END (G-34 (l)):
  ◆ and "at end", the mint segment and playhead tick, ×, Clear, `◆N` with a
  stale end key counted, the end's own stale rows, ⊘ on Width, Height and
  Follow Clip, Reset writing the end, the band's label naming graphic keys.
  The row tag became one line, and a keyed row short of room narrows a
  CONTROL, never the tag (O8). Measured: `graphics_inspector_proof.py`
  90/90 with 27 mutants caught; `clip_inspector3_proof.py` 31/31,
  `clip_inspector4_proof.py` 46/46; `screens.py` 07b.
- **Phase 4, the close-out (this record).** O8's one gap: a module's
  boolean whose label is longer than about 200 pt tied with the tag at
  compression resistance 750. `inspectorRow` now gives a row with no popup
  its widest checkbox the 749 and clips that checkbox to its bounds — its
  title had drawn past them into the tag (`clipsToBounds` is off by
  default since macOS 14). Measured: `graphics_inspector_proof.py` 91/91
  with K18c (keyed, the checkbox 222 of its 260 at 749 against the tag's
  750, the tag 40/40, no ink of the title beside or over the tag), its
  mutants `checkbox-fixed-width` and `checkbox-title-unclipped` caught, and
  `popup-fixed-width` now failing K18c too. Left alone: the checkbox is
  `OptionControls.swift`'s, carried from Rasterize unforked, so its title is
  cut at its edge rather than ended in an ellipsis.

Owed: the person's checks CT-8 (a keyed graphic row's look, both
appearances) and GR-8 (a 4K animated prop plays without stutter, G-34 (g))
in `docs/manual-checks.md`. Left out by G-34's accepted limits and filed
as issues: a per-prop `animate: false` opt-out for module authors
(#248) and an asset prop in an action (#249). The OKLab blend (#250) is
built: "Graphics gaps" below, spec §11 G-40.

## G6 phase 2 — playback prefetch (#127, spec §11 G-36)

2026-10-21, on `858146a`. A preview playing forward over a project that
draws a graphic now runs G-26's workers on the document's own key
(`Playback+Prefetch.swift`'s `syncPrefetch(from:)`, called from the rate
KVO, `startSeek` with its target, and a property-only edit while playing;
stopped in `invalidate` and `deinit`). The session FOLLOWS the compositor:
`Compositor.serve` reports each request's time (`GraphicPrefetch.reach`),
a worker never claims a frame at or before the last one reached (counted
`skipped`), and held entries of earlier frames go as unused. A slot the
worker left to the pool (the same-texture shortcut, now marked `deferred`)
that reaches `take` in a following session counts `missed`, and a wait
that `stop` ends counts as nothing. The export's session is unchanged but
for that last rule. The owner chose G-26's limits for playback too, with
no setting.

**The instrument came first**: the dev tool `play_preview`
(`AgentServer+PlayPreview.swift`, `PlaybackTrial.swift`, spec §7.9c)
plays the preview for a while and answers the share of the frames it
passed that the compositor composed, and how long each took.

**Baseline**, before any prefetch code (Release, `playback_prefetch_proof.py
--bench` over a copy of parive-promo, clip 8's `section` scene from tick
25 120 000 for 10 s; 12 cores, `powermode 0` in every cell; ON equals OFF
here because nothing yet read the switch for playback):

| Cell | Load average before | Composed | compose_ms mean / p95 / worst | RSS after |
|---|---|---|---|---|
| OFF Full | 15.84 | 35 of 277 (0.126) | 266.94 / 589.54 / 613.63 | 414 320 KiB |
| OFF Quarter | 13.24 | 36 of 296 (0.122) | 271.96 / 590.25 / 612.54 | 420 736 KiB |
| ON Full | 11.58 | 35 of 277 (0.126) | 266.63 / 595.72 / 603.97 | 422 960 KiB |
| ON Quarter | 9.07 | 36 of 295 (0.122) | 270.24 / 604.07 / 611.07 | 422 528 KiB |

The rule written before the run — stop if OFF at Full composed ≥ 0.95 —
did not hold, so the phase went on.

**After**, the same bench on the built phase (Release, `powermode 0`):

| Cell | Load average before | Composed | compose_ms mean / p95 / worst | RSS after | Playback line |
|---|---|---|---|---|---|
| OFF Full | 9.51 | 34 of 295 (0.115) | 279.40 / 636.99 / 652.37 | 413 600 KiB | — |
| OFF Quarter | 13.12 | 33 of 294 (0.112) | 286.28 / 606.54 / 634.23 | 415 968 KiB | — |
| ON Full | 13.29 | 83 of 298 (0.279) | 115.65 / 564.70 / 836.55 | 1 748 944 KiB | 260 frames, 136 hits, 0 mismatched, 12 missed, 390 unused, 29 skipped |
| ON Quarter | 19.17 | 94 of 289 (0.325) | 95.78 / 640.38 / 765.00 | 1 721 328 KiB | 247 frames, 151 hits, 0 mismatched, 12 missed, 349 unused, 35 skipped |

So the prefetch composes about 2.4 times the frames on parive's heaviest
scene and still does not keep up there: 28% of its 30 fps frames at
Full, 33% at Quarter. The process's RSS just after the play stood about
1.27 GiB above OFF's. Fix pass 1 measured what that is, on a Release copy
instrumented to log the held bytes and `phys_footprint` (same scene, 10 s,
Full, load 24.51 at the start): the held rasters peaked at 373 MB in 53
slots, well under the 1 GiB bound (the 44-slot limit binds first; a
frame's layers go in together, so the count passes it by a frame's
worth). The rest is outside the bound: `vmmap` in mid-play read 855 MB of
live large allocations (the held rasters, eleven workers' rasters in
flight with the images they decode, the compositor's taken rasters) and
602 MB of freed large blocks the allocator keeps resident (939 MB after
the play), and IOSurface 130 MB against OFF's 68 MB. The footprint rose
from 366 MB to a peak of 2.07 GB while playing and stood at 1.24 GB after
(OFF: 116 MB to 392 MB, 499 MB after). G-36 (e) and GR-9 now say that the
1 GiB bounds only the held rasters.
Quarter gains little, because a graphic draws at its own size (G-7). On
the proof's lighter fixture H the same change takes the share from 0.264
to 0.978. The decoded-image cache and the in-place raster (#127's phases 3
and 4) are what is left on the time per frame.

**Rows** (`playback_prefetch_proof.py`, Release, two owned instances):
10/10 — P0 CONTROL L composed 1.0 on both; P1; P2 232 hits, 0 mismatched,
0 missed; P3 H OFF 24 of 91 (0.264, 122.71 ms mean) against ON 89 of 91
(0.978, 13.24 ms mean, 36.55 ms p95); P4; P5; P6 30 skipped at rate 4;
P7 98 common ticks equal; P8 22 common ticks equal; P9; Z1. The same on
Debug, 10/10. **Mutants**, each built in a tree copy and driven through
every row, all six caught: `worker-frame-plus-one` (P2: 39 mismatched),
`unguarded` (P8: 20 of 21 common digests differ), `no-stop-on-pause` (P2:
no line), `no-graphic-gate` (P4: a line for L), `no-follow` (P6: 0
skipped), `seek-reads-player` (P9: no line from 1 800 000). G-26 still
holds: `graphics_prefetch_proof.py` 7/7 (S2 301 hits, 0 mismatched; S6
OFF 15.63 s, ON 2.41 s) with both of its mutants caught;
`op_argument_proof.py` 161/161 (31 product and 7 dev tools);
`assistant_session_proof.py` 13/13; `make gate` exit 0.

**Fix pass 1** (the review's should-fix): a seek installs its session
before AVFoundation cancels the old position's requests, and one of those
served in between raised the new session's floor — past a loop's end, so
the whole lap drew serially, or ahead of a backward seek's target.
`reach` now ignores a request outside the session's range, and a seek's
session (`syncPrefetch(from:seeking:)`) follows nothing until a request
lands in its first four frames (`armFrames`). A first try, ignoring
requests AVFoundation issued before the session began, was not enough: an
`unguarded` run of that build showed a backward seek's session with 0
hits and 86 skipped. New row P10 (H from 1 200 000, `seek_to` 0: hits >
0); P8 now merges three plays a side (39 common ticks on Release, against
22). Release 11/11; Debug 11/11; `unguarded` caught on the first try's
build (P8: 38 of 39 common digests differ), `seek-reads-player` (P9) and
`no-follow` (P6) on the final one. P10 has no mutant: with the guard and the
arming taken out it passed twice, because this play seldom serves an old
request in that window. `make gate` exit 0.

Owed: GR-9 in `docs/manual-checks.md` (a heavy project plays; memory).
Filed: #326, `export`'s missing MCP progress notifications (agent
transport, not graphics speed).

## G6 phase 3 — one memory budget and kept frames (#127, spec §11 G-37)

2026-10-21, on `1e7f64c`. G-26 (d)'s and G-36 (e)'s fixed bounds (1 GiB
and `4 × workers` slots a session) are gone. Every session's held rasters,
export and playback, and the graphic frames a document keeps share one
process-wide budget, `ProcessInfo.physicalMemory / 4` (the owner's choice:
limits relative to the Mac, 16 GB the floor), which a
`DispatchSourceMemoryPressure` halves at warning and sets to 0 at critical
(no worker claims; preview and export draw serially). A worker waits while
the held rasters of all sessions reach it, or while its session holds
1,024 entries, bytes or none (the bookkeeping ceiling that keeps a static
graphic from running the workers to the range's end). A `Playback`'s key
KEEPS each raster the compositor used and each finished raster a worker
made for it when it leaves its slot, under its texture key, least
recently used out first and never past the room the held rasters leave
(`GraphicPrefetch+Memory.swift`'s `KeptFrames`); `take` answers from them
on a pool miss before any slot, with no session needed, and a worker skips
a texture key already kept. A raster is a function of its texture key, so
a kept raster is the serial path's. `FrameJobGraphicKeepOff` keeps
nothing. The instrument is the dev tool `graphic_memory` (spec §7.9c).
Residue folded in: the rate KVO and a property-only edit while playing
pass `seeking: isSeeking` to `syncPrefetch`.

**One deviation from the brief.** The brief dropped a window's kept frames
in `Playback.invalidate`, which the editor's `deinit` calls. On the first
Debug run M8 failed: after `close_project` the frames stayed for 40 s and
more, until another window opened, because the editor is freed only later
(the retained window controller `ProjectDocument.close()` already names
for the recipe key). The document's close now drops them too
(`ProjectDocument+Graphics.swift`'s `stopGraphicStore`, beside
`GraphicRegistry.remove`); G-37 (c) says so.

**Bench** (Release, `graphic_memory_proof.py --bench` over a copy of
parive-promo, clip 8's `section` scene from tick 25 120 000 for 10 s,
played twice per cell; Full; 12 cores, 96 GiB, `powermode 0`; the load
average was 130–182 throughout, from other sessions' builds on the host,
so the ratios are low against phase 2's and are compared only within this
run):

| Cell, play | Load before | Composed | compose_ms mean / p95 | Playback line | `graphic_memory` after | RSS after |
|---|---|---|---|---|---|---|
| KEEP-OFF, 1 | 130.43 | 136 of 300 (0.453) | 57.27 / 522.82 | 250 hits, 15 missed, 28 skipped, 0 kept | held peak 812 851 200 B in 98 entries; nothing kept | 894 304 KiB |
| KEEP-OFF, 2 | 140.41 | 121 of 301 (0.402) | 76.24 / 569.68 | 214 hits, 9 missed, 30 skipped, 0 kept | held peak 754 790 400 B in 91 | 920 032 KiB |
| KEEP, 1 | 175.44 | 116 of 296 (0.392) | 79.02 / 605.88 | 198 hits, 11 missed, 23 skipped, 0 kept | held peak 862 617 600 B in 104; 3 176 755 200 B kept in 383 frames | 4 451 040 KiB |
| KEEP, 2 | 182.37 | 201 of 301 (0.668) | 32.05 / 69.01 | 72 hits, 1 missed, 10 skipped, 281 kept | held peak 2 513 203 200 B in 303; 6 386 688 000 B kept in 770 frames, 291 kept hits | 7 690 592 KiB |

So the replay with kept frames composed 0.668 of its frames against the
first play's 0.392 (KEEP-OFF's replay: 0.402), with its p95 compose time
down from 606 to 69 ms; the kept frames held 6.4 GB after two plays, a
quarter of the budget, and the process's RSS stood at 7.3 GiB, against
0.9 GiB with keeping off. Memory figures are only these printed ones.

**Rows** (`graphic_memory_proof.py`, Release, three owned instances: SERIAL,
KEEP, KEEP-SERIAL): 13/13 — M0 CONTROL L composed 1.0 on both; M1 the
budget a quarter of `hw.memsize`; M2 242 hits, 301 frames kept, nothing
held after; M3 kept 245, `kept_hits` 0 → 248, 92 of 92 composed; M4
KEEP-SERIAL `kept_hits` 0 → 28 (MEASURED 0.259 then 0.33); M5 45 common
ticks equal; M6 a paused scrub, `kept_hits` 984 → 1000; M7 warning
physical / 8, critical 0 with nothing kept and 0 frames with graphics, then
normal physical / 4; M8 296 kept → 0 after the close; M9; M10 held peak
171 entries; M11 over 15 answers; Z1. The same on Debug, 13/13.
**Mutants**, each built in a tree copy and driven through every row, all
seven caught: `kept-any-texture` (M5: 48 of 48 common digests differ),
`no-compositor-keep` (M4: nothing kept), `no-pressure-trim` (M7: 301 kept
under critical), `budget-ignored` (M7: 120 frames with graphics under
critical), `slot-limit` (M10: 74 entries), `kept-outlives-window` (M8: 272
kept after the close), `keep-switch-ignored` (M9: 170 kept on SERIAL).
`slot-limit` survived M10's first bound, `4 × workers`: a claim reserves
no slot, so a `4 × workers` limit held 74 entries; M10's bound is now what
such a limit can hold, `4 × workers + workers × 4` (H's four layers a
frame), and the real build's 171 clears it.

**Phase 2's proofs keep their meaning**: `playback_prefetch_proof.py`
launches every instance with `-FrameJobGraphicKeepOff YES`, and gains P11,
a loop lap (Clip ▸ Motion ▸ Preview on H's first `heavy` clip, 6 s): Release
12/12 (the lap 150 hits), Debug 12/12; `worker-frame-plus-one`,
`unguarded`, `no-follow`, `seek-reads-player` caught again, and
`no-arming` (P11: the laps 0 hits) is a new mutant. `no-range-guard`
(`reach`'s `ticks < session.endTicks` out) survived P11 twice (the lap 169
and 156 hits), so it is residue like P10's, not a mutant.
`graphics_prefetch_proof.py` 7/7 (S2 301 hits; S6 OFF 16.01 s, ON 3.79 s)
with both mutants caught: the export without slots is the serial path's
file. `op_argument_proof.py` 162/162 (31 product and 8 dev tools);
`assistant_session_proof.py` 13/13 (A0's marker 8); `make gate` exit 0.

Owed: GR-10 in `docs/manual-checks.md` (a replay plays from memory, and the
memory is given back). Next in #127: drawing ahead while paused, a
setting.

## G6 phase 4 — background render (#127, spec §11 G-38)

2026-10-21, on `adf9807`. Settings gets a fourth pane, Playback
(`PlaybackSettingsPane.swift`): "Background render", on, and "Start after
[5] seconds" (1–60), a person's setting with no tool, stored in
`FrameJobBackgroundRender` and `FrameJobBackgroundRenderDelay`. The idle
clock (`BackgroundRender.swift`) is one run-loop `Timer` restarted by every
key, modifier, button, drag, scroll and trackpad gesture event the app
receives (an `NSEvent` local monitor), every `.projectDocumentDidChange` and
every `syncPrefetch` (play, pause, rate change, seek), each restart stopping
the running pass. At the delay the document whose transport last moved —
paused, built, drawing a graphic, still open (its graphics registered) —
asks `GraphicPrefetch` for a background session over G-36 (b)'s grid from
the playhead (`Playback+Prefetch.swift`'s `startBackgroundRender`); seeking,
restoring, rebuilding, holding or a refused start (a window plays, a pass
runs, the key does not keep) runs the clock again. A pass's workers run at
utility QoS; each finished raster goes straight into the kept frames,
marked as drawn ahead (`KeptFrames.markAhead`), and a texture key already
kept is touched and marked, not drawn. It ends `done` at its range's end,
`full` when its marked frames, every held raster and the next frame's bytes
would pass the budget, `stopped` on activity, close (`stopGraphicStore`
now stops the key's session before dropping its frames) or `invalidate`;
its line is written at once on a stop. The kept frames give way unmarked
first, least recently used first, marked last. A play from the pass's own
key and grid start keeps the marks: its workers wait while the held rasters
and the marked frames reach the budget — in `claim`, and again in `insert`
with the frame's own bytes, because concurrent claims reserve nothing and
eleven workers at once pushed the nearest marked frames out (a 4K LONG,
Debug: kept share 0.576 before, 1.0 after) — and `reach` unmarks the frames
it passes; that play's stop, a play from anywhere else and a new pass clear
every mark. Phase 3's review: a pool hit touches its kept frame
(`discard(_:slot:textureKey:)`), and `heldEntries` counts only entries
holding bytes.

**Deviations, all in the instrument but the second.** (1) B3 sets the
playhead to 1 frame again, not to 0: frame 0's rasters are emptied before B1
and still in the compositor's pool, so a seek to 0 keeps none and the pass
drew frame 0's two `heavy` layers. (2) The `insert` wait above, and `full`
counting the next frame's bytes, beside `claim`'s check: without them a
pass's own inserts, and a play's concurrent claims, evicted marked frames.
(3) B13 plays LONG through Clip ▸ Motion ▸ Preview, not a second client's
`play_preview`: the agent lane serialises every call (AI-2), so the second
client held the first's `set_playhead` to the play's end; and B13 reads
"before LONG's playback line" as before the pausing call, since a following
session's line is written by its last worker, which a loaded host held
seconds past the pause. (4) B7 runs after B12 and B13 and saves LONG: run
first, B12's pass was stopped 15 s after B7's edit, the autosave in place's
delay (its edited-state change is activity), with no other line to explain
it. (5) LONG's canvas is 2560 × 1440 (the spec left it
open): at 1080p B12's 1,553 frames of deferred entries reached the
1,024-entry ceiling before unguarded workers passed the pass's end, at 4K
the rasters were too slow to outrun the play; both let `ahead-unguarded`
survive. (6) A mid-pass control and B12's are performed again once, and
BG's instances run with `-NSAppSleepDisabled YES`. (7) `screens.py` pins
the two new keys and lists phase 3's `FrameJobGraphicKeepOff` as not shown
(its P2 failed on all three).

**Bench** (Release, `background_render_proof.py --bench` over a copy of
parive-promo, clip 8's `section` scene from tick 25 120 000 for 10 s, Full;
12 cores, 96 GiB, `powermode 0`):

| Cell | Load before the play | Pass | Composed | compose_ms mean / p95 | Playback line | RSS after |
|---|---|---|---|---|---|---|
| BG-OFF | 31.84 | none | 88 of 301 (0.292) | 104.59 / 640.19 | 136 hits, 8 missed, 58 skipped, 0 kept | 3 667 520 KiB |
| BG | 87.11 | `full`: 3 103 drawn, 330 already kept, 25 762 406 400 bytes kept | 301 of 301 (1.0) | 5.82 / 9.48 | 0 hits, 537 kept | 26 158 368 KiB |

So after an idle wait the first play composed every frame, against 0.292
with Background render off, at the cost of a quarter of memory held (the
budget, 25.8 GB of kept frames) and the RSS that comes with it. An earlier
bench on the code before the `insert` wait read 0.442 off and 0.857 on (load
31.02 and 113.39).

**Rows** (`background_render_proof.py`, Release, the final instrument): 14/14
— B1, B2 (300 drawn), B3 (0 drawn, 476 already kept), B4 (kept 245), B11
(48 common ticks equal), B9 (`full`, 0 drawn), B5, B6, B12 (873 frames
`full`; the 22.7 s play's kept share 1.0), B13, B7, B10, B8, Z1.
**Mutants** (Release): eight caught — `no-idle-delay` B1, `ignores-setting`
B8, `activity-stops-own-only` B5, `background-past-budget` B9,
`close-keeps-drawing` B10, `draws-kept-again` B3, `ahead-evicted-first` B12
(share 0.861), `background-beside-play` B13. `ahead-unguarded` is NOT
caught: it survived at 1080p (0.994) and 4K (0.958), and at 2560 × 1440 its
control failed twice (passes stopped by activity the proof did not make).
`graphic_memory_proof.py` 13/13 with its six re-run mutants caught,
`playback_prefetch_proof.py` 12/12 with four, `graphics_prefetch_proof.py`
7/7 with both; `settings_layout_probe.py` 13/13 (L12) with `order-swapped`,
`mcp-last` and `delay-unclamped` caught; `cloud_captions_probe.py --only
chrome,settings_verify` 117/117 (the window re-pinned at 460 × 863);
`assistant_tab_proof.py` 26/26; `screens.py --only 02-settings` 6/6; `make
gate` exit 0.

**Fix pass 1** (its review's two should-fixes, three nits, and the owner's
App Nap answer). (1) `ahead-unguarded` is caught: `KeptFrames` counts the
marked frames a trim pushes out while still marked (`aheadEvicted`), and
`graphic_memory` answers it as `ahead_evicted` beside `ahead_bytes` and
`pass_activity`, reset by each answer. B12 reads it before and after its
play and wants 0. The share alone could not see an unguarded play: a
`full` pass leaves under one frame of room, so the play's first
reservations trim marked frames out at once, about one per worker, and the
rest of the damage waits on the workers passing the pass's end, which the
host's speed decides; the count sees the first trim on any host (the
mutant's run: share 0.981, which passed 0.9, and 19 evicted). The
reviewer's other bound (`held_peak_bytes` plus the pass's bytes within the
budget plus what the compositor passed) was not used: a guarded play's
workers also reach eleven frames held once the compositor has passed
eleven, so by the time a reply can be read the slack swallows the
difference. (2) Settings' panes sit in a scroll view capped at the screen's
visible height less the title bar (`fitScreen`, from `init` and `show()`),
so the 863-point window fits a 1440 × 900 display and scrolls there; on a
taller screen nothing changes (row 18 still 460 × 863), and
`settings_layout_probe.py`'s L13 drives both, with the mutant
`screen-uncapped`. (3) `idle()` runs the clock again while any transport
that has moved plays, forward or in reverse, with graphics or without
(`BackgroundRender.transports`, weak); `background-beside-play` now removes
this check and `start(background:)`'s refusal both. (4) A pass's layer
deferred to an earlier frame's unfinished entry of the same texture raises
that entry's mark index (`Entry.sharedUpTo`) and counts as already kept
when it is kept (`Entry.sharers`). (5) `startBackgroundRender` answers
`.notNeeded`, not `.busy`, under `FrameJobGraphicPrefetchOff` or a key that
does not keep, so neither switch re-arms the clock. (6) The owner
(2026-10-21), "Keep going (Recommended)": a pass holds a `ProcessInfo`
activity (`userInitiatedAllowingIdleSystemSleep`) from `beginAhead` to its
end (`stop`, or its last worker's exit unstopped), recorded in G-38 (c);
B14 reads `pass_activity` false after B2's `done`, true during B5's pass,
false after B10's close, and the mutant `nap-outlives-stop` fails it.
`GraphicPrefetch.Slot` moved to `LayerRenderersGraphic.swift` (a pure move)
to hold `GraphicPrefetch.swift` at 600.

Fix pass 1's runs (Release): `background_render_proof.py` 15/15 (B12: 873
frames `full`, 850 drawn; the 22.7 s play kept 686 of 686, share 1.0,
`ahead_evicted` 0); mutants caught: `ahead-unguarded` B12 (19 evicted,
share 0.981), `ahead-evicted-first` B12 (179 evicted, share 0.872),
`background-beside-play` B13, `nap-outlives-stop` B14, `draws-kept-again`
B3; `graphic_memory_proof.py` 13/13, `playback_prefetch_proof.py` 12/12,
`graphics_prefetch_proof.py` 7/7, `assistant_tab_proof.py` 26/26,
`screens.py --only 02-settings` 6/6 (0 new problems),
`agent_socket_proof.py` 17/17; `settings_layout_probe.py` 14/14 with
`screen-uncapped`, `order-swapped`, `mcp-last` and `delay-unclamped`
caught; `cloud_captions_probe.py --only chrome,settings_verify` 117/117
(460 × 863); `make gate` exit 0. The bench answered both plays, but its BG
pass was `stopped` after 20 frames by activity it did not make (load 55
before), so its 0.306 (against 0.402 off) measures no pass; the table above
is the earlier code's.

Owed: GR-11 in `docs/manual-checks.md` (now with a hidden wait) and CH-6's
scrolling step.

## G6 phase 5 — decoded-image cache (#127, spec §11 G-39)

2026-10-22, on `2d003d1`. resvg decodes each `<image>` asset's PNG or JPEG
on every frame. Measured first: `tools/proof/image_cache_bench.py` copies a
package under `work/image-cache-bench/`, dumps 40 evenly spaced frames of
the graphic clip covering `--from` as SVG through `render_graphic {format:
"svg"}` on its own instance, and runs `graphic/tests/image_bench.rs`
(ignored) over them: the original assets (ORIG) alternating with a second
arm, 5 rounds, every frame's bytes compared across the arms. The stop rule,
written before the run: build only if the saving is at least 0.03 and above
ORIG's spread.

The spike (STORED: the same library with each PNG asset swapped for a
stored-deflate RGBA8 PNG copy the test built; the package has no JPEG), on
the owner's parive promo's `section` clip at 25120000 (clip 8, frames
0…529, 1920 × 1080), `powermode 0`, load average 6.10 before and 6.16
after: ORIG median 11,595.0 ms, STORED 11,097.4 ms; saving 0.0429, spread
0.0330, PNG decodes 0.0753 of ORIG (872.7 ms); every frame identical. The
rule said build.

Built, in this order. Spec §11 G-39 first. The tolls, one pure move gated
alone (`make gate` exit 0): T1, `ffi_graphic.rs`'s crate-free builder half
to the new `ffi_graphic_pending.rs` (399 → 333; its widenings in
`core-file-history.md`), and T2, `ReelCoreError` and `Fps.ffiPair` to
`CoreValues.swift` (`ReelCore.swift` 817 → 803). Then the crate's
`images.rs`: one `Mutex` over a map from the SHA-256 of an asset's bytes to
`Ready` (the copy and its use stamp), `Building`, `Refused` or `Skipped
{len}`, under a limit (default 0: nothing cached) and a byte total. The
first frame that draws a PNG or JPEG builds its copy with no lock held
(png 0.18's decode expanded as tiny-skia's, or resvg's own zune-jpeg
decode; written stored and unfiltered), used only if `Pixmap::decode_png`
of it is the original's pixmap and `imagesize` reads the same size; a copy
over the limit, and every copy a trim evicts, is remembered as `Skipped`
by its length and takes the original route until it fits without
evicting, so nothing is rebuilt per frame. `library.rs` keeps each asset
with its digest and asks the cache before answering a PNG or JPEG kind.
`rc_graphic_image_cache` sets the limit and answers the bytes held;
`GraphicLibrary.imageCache(limit:)` wraps it; `GraphicPrefetch+Memory.swift`
sets `budgetBytes / 16` at launch and in `setPressure` (after the
broadcast, so `graphic_memory_proof.py`'s `no-pressure-trim` anchor holds),
0 under `FrameJobGraphicImageCacheOff`; `graphic_memory` answers
`image_cache_bytes` and `image_cache_limit`. `graphic/tests/pins.json` is
unchanged. Outside the spec's file list: `core/tests/model_tests.rs`'s NULL
sweep covers the new export (the sweep reads the header's list), and
`tools/proof/screens.py`'s NOT_SHOWN names the new switch.

The after run (CACHED: the ORIG library at a limit of 1 GiB after one
untimed warm frame), same clip, `powermode 0`, load average 12.30 before
and 5.73 after: ORIG median 11,202.9 ms, CACHED 10,689.6 ms; saving 0.0458,
spread 0.0333, PNG decodes 0.0730 of ORIG (818.0 ms); 14,972,870 bytes
cached (one asset's copy, `feature-map.png`'s); every frame identical.

Rows: `graphic/tests/image_cache.rs` I1–I6 pass; `image_cache_proof.py`
6/6 on Debug and on Release (C2 ON 922,430 bytes under a 1,610,612,736
limit on 96 GiB; C3 critical 0 and 0, warning 805,306,368, normal
1,610,612,736). Mutants, each caught (exit 0) before fix pass 1 changed
the miss path (below):
`name-key` I2, `premultiplied-copy` I1 (bytes), `unchecked` I1 (pixels),
`no-trim` I3, `over-limit` I4 (bytes), `no-skip-marker` I4 (builds),
`pressure-ignored` C3 (Release). `graphic_memory_proof.py` 13/13 on
Release, and its `no-pressure-trim` caught (M7). `screens.py --only
02-settings` 6/6 on Release. `make gate` exit 0 after the tolls and at the
end. No person check is created.

**Fix pass 1** (its review's should-fix and three nits). (1) A build that
re-locked wrote its result without asking whether the digest was still its
own: a limit of 0 and back while it ran (critical, then normal) let a
second worker mark and build the same digest, and both added their length
to `bytes`, or the over-limit arm overwrote the other's `Ready` with
`Skipped`, so `bytes` counted copies nobody held. `cached_kind` now writes
only while the entry is still `Building`, and otherwise returns its copy
and leaves the map alone; the `limit == 0` removal sits behind the same
check. (2) `ffi_graphic_pending.rs`'s moved doc link to
`rc_graphic_library_free` names `crate::ffi_graphic::` (`cargo doc`
reports no broken link). (3) G-39 (h) states the first frame's exact cost:
two decodes of a PNG original (png, then `Pixmap::decode_png`) or one of a
JPEG, one encode and one decode of the copy. (4) G-39 (c) says what is
true rather than serialising a test: `core/tests/graphic_ffi.rs` sets a
64 MiB limit and then 0 while its other tests run, and none of them draws
an image asset. The Lines cells moved with (3) and (4) (`graphics.md`
2109, `11-decisions/` 10703). Runs: `image_cache.rs`, `images.rs`,
`library.rs`, `pins.rs` and `graphic_ffi.rs` pass; `spec_index_proof.py`
177/177; `make lint` exit 0; `make gate` exit 0 (152 s);
`image_cache_proof.py` 6/6 on Release. Not re-run, each with its reason:
the seven mutants (no anchor line was touched, and the new check passes
straight through on the single-threaded path the I-rows drive),
`graphic_memory_proof.py` and its mutant (no Swift changed), and the
bench (one map lookup under a lock already held; its single-threaded
figures do not depend on interleaved builds). No row drives two builds of
one digest across a limit of 0; the race has no instrument.

## G6 phase 6 — in-place raster (#127)

2026-10-22, on `f06c9bb`. Measured first, and stopped by its rule before
any product code. The question: how much of a graphic frame's raster time
sits outside resvg's own render — the pixmap's allocation and first touch,
the RGBA→BGRA copy, the Swift buffer's zero-fill and the copy into the
texture (no un-premultiply: `rasterize` hands on tiny-skia's premultiplied
bytes as they are). `tools/proof/raster_bench.py` dumps the clip's frames
as `image_cache_bench.py` does (its `dump_scene`, which that bench now
shares), then runs `graphic/tests/image_bench.rs`'s ignored
`section_scene_raster_overhead` over them with the image cache on (1 GiB,
one warm frame), 5 rounds, single-threaded: ROW (every SVG through
`rasterize` at stride `w×4`), PADDED (at `w×4 + 64`, every frame's rows
compared with ROW's), ALLOC (`Pixmap::new` and a touch of every page),
SWIZZLE (raster.rs's row loop from a held pixmap) and CLEARSWAP (the clear
and in-place R↔B swap an in-place route would still pay), each arm as many
times as there are frames. The probe `tools/proof/raster_upload_probe.swift`
times, at the dump's size, the zeroed buffer `GraphicLibrary.rasterize`
allocates (Z), the app's own `LayerRenderers.upload` (U) and
`makeTexture` alone (M). Per frame: `net = max(0, alloc + swz − cs)`, `copy
= max(0, U − M)`, `F = row + Z + U`, `share = (net + Z + copy)/F`, `rust =
net/F`, `swift = (Z + copy)/F`, `spread` ROW's `(max − min)/median`. The
stop rule, written before the run: STOP if `share < 0.03` or `share ≤
spread`; else BUILD if `rust ≥ 0.03` and `> spread`; else SWIFT (the
texture path, a phase 6b) if `swift ≥ 0.03` and `> spread`; else STOP.

The run that decided: the owner's parive promo's `section` clip at
25120000 (clip 8, frames 0…529, 40 of 1920 × 1080), on a 12-CPU host
shared with other sessions, `powermode 0`, load average 68.05 24.51 15.42
before and 23.87 25.57 17.34 after. Medians over 5 rounds of 40 frames:
ROW 11,134.0 ms, PADDED 11,267.1 ms, ALLOC 2.7 ms, SWIZZLE 7.0 ms,
CLEARSWAP 29.0 ms; ROW's spread 0.2987, PADDED's 0.2659; every frame's ROW
bytes equal PADDED's rows. The probe (40 iterations): Z 0.048 ms, U
0.845 ms, M 0.022 ms. (A Z that small for an 8.3 MB buffer suggests its
pages are zeroed lazily, so the first write into a fresh one is counted in
neither Z nor ROW; under 0.03 the verdict holds either way.) Per frame: row 278.349 ms, alloc 0.067, swz 0.176,
cs 0.725, net 0 (the clear and swap cost more than the allocation and
copy they would replace), copy 0.823, F 279.242, outside 0.871; share
0.0031, rust 0, swift 0.0031. **Verdict: STOP** (share under 0.03).

For the record only, `--module bg` at the same `--from` (clip 4, frames
0…3775, 1920 × 1080; bg is cheap and full-frame, and the overhead depends
only on the size): load 20.66 24.82 17.17 before, 15.35 23.23 16.82 after;
ROW 1,407.5 ms, PADDED 1,401.7 ms, ALLOC 2.1, SWIZZLE 6.7, CLEARSWAP
28.7; spreads 0.0714 and 0.0695; Z 0.043, U 0.796, M 0.020; per frame row
35.188, net 0, copy 0.776, F 36.027, outside 0.819; share 0.0227, rust
0, swift 0.0227. Its own verdict was STOP too, so nothing is filed.

Nothing under `graphic/src/`, `core/` or `app/Sources/` changed; spec §11
gains no decision, and G-7's row copy stands. What landed is the
instrument: `section_scene_raster_overhead` beside the phase 5 bench (the
scene's loading factored into one `load_scene`), `raster_bench.py` with
its probe, `image_cache_bench.py`'s `dump_scene` (and `covering_clip`'s
`module`; its cargo line now runs only its own test). `raster_bench.py
--mutant` carries the in-place route's three anchors (`no-clear`,
`no-swap`, `padded-in-place`) and answers 2 while the route is unbuilt.
`image_cache_bench.py --frames 4 --rounds 1` still passes (every frame
identical across the arms). #127's phases are all done; it can close.

## Graphics gaps (#248, #249, #250)

Three of G-34's accepted limits, one phase each.

**Phase 1 — an animated colour prop blends in OKLab (#250, spec §11
G-40)**, 2026-10-22, on `d2a3b82`. The owner's answer: "OKLab always" — no
setting, no per-action or per-end key. Every action on a graphic `color`
prop now blends as stdlib's `interpolateColors` does: `core/src/model_color.rs`
gains `oklab_mix`, the stdlib's `__toLinear`, `__toOklab`, `__fromOklab`
and `__fromLinear` ported operation for operation (alpha straight, mixed
as a unit value), and `actions_graphic.rs`'s `lerp_prop` colour arm is one
line calling it. One fixture, `graphic/tests/oklab.json` (ten blends; the
first two and `#aabbcc` → itself worked by hand, the rest written from
what `interpolateColors` answered), is answered by
`graphic/tests/stdlib.rs`'s `interpolate_colors_answers_the_shared_oklab_fixture`
and `core/tests/graphic_actions.rs`'s `a_colour_answers_the_shared_oklab_fixture`,
exact string equality on every case; `a_colour_ramps_channel_by_channel_with_straight_alpha`
became `a_colour_ramps_in_oklab_with_straight_alpha` (`#00000000` →
`#ffffff` is `#63636380` halfway, red → blue `#8c53a2`).
`a_split_through_an_animated_prop_is_invisible` passes unchanged. No
format bump and no migration: older projects re-render with the new
middle. The catalog's `set_action_end` prose, `docs/graphics-api.md` and
§5.4 say OKLab. `graphic_prop_action_proof.py`'s B1, C1 and E1 read the
red → blue middle from the fixture (`BLEND`).

Verified: `make gate` PASS; the proof against Release, 17/17, exit 0
(B1's (150,60) (140, 83, 162), E1's decoded (138, 82, 160)); its new
mutant `channel-blend` (the arm as a per-channel straight lerp) `MUTANT
PASS`, B1, C1 and E1 failed. The core mutants, applied by hand to the tree
and reverted: the arm as a channel lerp failed both colour tests; `oklab_mix`
without the sRGB decode failed the fixture test (and the split test);
`to`'s alpha taken instead of mixed failed both on `#63636380`.

Not changed: the model's own `[r, g, b, a]` colours (text, shadow,
background, shape groups) keep §5.4's element-by-element blend.

## Open items

- G6 (#127) has no phase left. The export's parallel rasterization landed
  (G-26), playback's (G-36), one memory budget with kept frames (G-37),
  drawing ahead while paused, Background render (G-38), and the
  decoded-image cache (G-39); in-place raster was measured and stopped
  (G6 phase 6), so #127 can close.
- The person's watched checks: the playback-check projects with no video
  underneath, memory at 4K, and the error card in the live preview —
  tracked in #56.
- Model and export correctness items:
  - `add_transition`'s handle form does not advance `graphic.in`;
  - a canvas rate change does not re-snap `in`/`length`;
  - `validate` accepts a graphic clip with no description.

  Tracked in #72.
- The not-built list: mattes or video input — #240. (HEVC with alpha and
  keyframed props were on it and are built: spec §11 G-33, G-34.)
- G-34's accepted limits, as candidates: the per-prop opt-out
  (#248) and asset props in an action (#249).
- Replacing QuickJS with JavaScriptCore — GitHub issue #39.

## Where to look in the original

- orig §0–§2a — the idea, the proposal reviewed point by point (the table
  behind `svg-motion-plan.md`'s ADR), what a graphic reuses, what was new.
- orig §3, §3a, §10.1–§10.3 — the G0 spike: nine questions, their numbers
  (q1 build cost, q2 quickjs-ng, q3 per-frame cost, q4 `measureText`, q5
  determinism, q6 the eighteen sandbox cases, q7 the package and watcher, q8
  float identity, q9 the FFI shape) and what each rewrote.
- orig §4 — G-1..G-14 as first argued (the JSC rejection is in G-2).
- orig §5a–§5m — the design: crate layout, runtime limits, module format and
  stdlib, rendering and caches, FFI, store and watcher, model v10, ops and
  tools, reference, inspector, templates, tests, file tolls.
- orig §6–§8 — the picks settled for the user, not built, and tunable
  numbers.
- orig §9, §9a — phase shape and what each phase had to carry from G0;
  G6's deferral quote.
- orig §10.4 — G1a–G1d: the toll, the drawing half, the JavaScript half, the
  link (`preserve_order` unification, the freezing library).
- orig §10.5 — G2a/G2b: props rules, the timeline arithmetic, the mutants.
- orig §10.6 — G3a–G3c: store and watcher, the registry and pools, the error
  card, the pin, and the export-Cancel crash and its fix.
- orig §10.7 — G4a/G4b: the six tools, the tenth export, the contact sheet.
- orig §10.8 — the media-less playback defect and its fix.
- orig §10.9–§10.10 — G5a/G5b (sub-tab, menus, templates) and the merge.
