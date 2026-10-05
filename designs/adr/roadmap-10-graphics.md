# Graphics — motion graphics drawn by code (road map 10)

- **Status:** Built and merged into `main` 2026-09-25 (G0 spike, G1–G5 built;
  G6 performance deferred by the user).
- **Original:** `archive/reelcut-roadmap-10.md` (3859 lines) — the full record;
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
  G-10 props are not action targets;
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
these clips. A clip's code lives on disk inside the `.reelcut` package.

Before this, Reelcut had no scripting and no C code in the build. The core
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
Playback prefetch and in-place raster are still not built.

**The FFI is ten `rc_graphic_*` exports, and a library is a builder that
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
  `host.rs`, `props.rs`, `diagnostic.rs`, `stdlib.js`, `noise.js`; rules in
  `graphic/CLAUDE.md`. `tests/graphics/` holds the six fixtures, which are
  also the Insert ▸ Graphic templates (copied into the bundle as
  `GraphicTemplates/` by `project.yml`).
- Core: `ffi_graphic.rs` (the ten exports; `read_bytes`/`free_boxed` in
  `ffi_util.rs`), `model_graphic.rs`, `edit_graphic.rs`, `recipe_graphic.rs`;
  arms in `edit_split.rs`, `edit_clip_timing.rs`, `edit_edge.rs` and
  `edit_action.rs` (`GRAPHIC_NOT_A_TARGET`); tests `core/tests/graphic.rs`,
  `graphic_ffi.rs`, `schema_v10.rs`.
- Header `core/include/reelcut_core.h` (`/* graphics */` section); Swift
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
  - keyframed props (G-10) — wanted, #239;
  - `paste_attributes` for graphics;
  - HEVC with alpha (ProRes 4444 and APNG already carry alpha);
  - mattes or video input to a graphic — wanted, #240;
  - system fonts as an opt-in — CLOSED by the owner 2026-10-04: Add Font to
    Graphics… / `import_graphic_font` already puts a face in the package and
    keeps a project portable; G-6 stands;
  - path helpers;
  - audio from a graphic;
  - generic CSS families such as `sans-serif`, which are warned like any
    missing name.

  Built since, and so off this list: a revision history and
  `delete_graphic` / `rename_graphic` (issue batch B84, spec §11
  G-27..G-29), and named CSS colours and `hsl()` in a `color` prop and in
  `interpolateColors` (#219: `core/src/model_color.rs`,
  `docs/graphics-api.md`'s schema table and `interpolateColors` section).
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

## Open items

- G6's rest — playback prefetch, in-place raster (`graphic/src/raster.rs`)
  and a decoded-image cache past resvg's per-render decode — tracked in
  #127. The export's parallel rasterization landed (G-26).
- The person's watched checks: the playback-check projects with no video
  underneath, memory at 4K, and the error card in the live preview —
  tracked in #56.
- Model and export correctness items:
  - `add_transition`'s handle form does not advance `graphic.in`;
  - a canvas rate change does not re-snap `in`/`length`;
  - `validate` accepts a graphic clip with no description.

  Tracked in #72.
- The not-built list: `paste_attributes`, HEVC with alpha and path helpers —
  tracked in #103; keyframed props — #239; mattes or video input — #240.
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
