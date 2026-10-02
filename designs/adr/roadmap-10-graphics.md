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

**Parallel rendering, prefetch and a worker pool were not built (G6)** (orig
§1, §9 G6). The compositor and export are serial, and q3 measured the six
samples at a worst p95 of 7.62 ms per frame at 1080p, against a 12 ms line.
At 4K, `title-card` measured 26 ms p95. The user played graphics at 4K on an
M2 Max, saw no stutter, and deferred G6.

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

**Six app-state tools** (orig §5h, §10.7):
- `write_graphic` answers the compile in the same call; its
  `store.rescan()` is synchronous so the reply is current;
- `get_graphic`;
- `render_graphic`, a contact sheet of up to 16 frames with no clip;
- `graphic_reference`;
- `import_graphic_font` and `import_graphic_asset`.

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
- **quickjs-ng 0.16.2 has no `Intl` and no `structuredClone`.**
  `formatNumber` exists for that reason (issue #39).
- **Largest string `render` can return:** 8 MiB (`graphic::SVG_BYTES`,
  spec §11 G-20 (c)); a longer one is the frame's error, naming its length.
  A 50 MB string is built but cannot be read out of a 64 MB heap at all; the
  engine's own sentence says so.
- **Deliberately not built** (orig §7):
  - keyframed props (G-10);
  - `paste_attributes` for graphics;
  - a revision history;
  - HEVC with alpha (ProRes 4444 and APNG already carry alpha);
  - mattes or video input to a graphic;
  - system fonts as an opt-in;
  - path helpers;
  - audio from a graphic;
  - `delete_graphic`/`rename_graphic`;
  - named CSS colours and `hsl()` in a `color` prop, and in
    `interpolateColors`;
  - generic CSS families such as `sans-serif`, which are warned like any
    missing name.
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
  interval. Issue batch B41 (2026-09-30, #197, #189) exported the engine's
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

## Open items

- G6 (prefetch plus parallel export against a before/after measurement) —
  deferred by the user; tracked in #127.
- The person's watched checks: the playback-check projects with no video
  underneath, memory at 4K, and the error card in the live preview —
  tracked in #56.
- Model and export correctness items:
  - `add_transition`'s handle form does not advance `graphic.in`;
  - a canvas rate change does not re-snap `in`/`length`;
  - `validate` accepts a graphic clip with no description.

  Tracked in #72.
- The not-built list (keyframed props, `paste_attributes`, revision history,
  HEVC with alpha, mattes, system fonts, path helpers, `delete_graphic` /
  `rename_graphic`) — tracked in #103.
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
