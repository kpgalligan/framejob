# graphic/CLAUDE.md — the graphics engine's rules

Applies to everything under `graphic/`, the crate that draws a graphic clip
(road map 10: `designs/adr/roadmap-10-graphics.md`; the full design is
`archive/roadmap-10.md` §5a). Build commands are the root
`CLAUDE.md`'s: `make test` and `make lint` run this crate after the core.
The crate's record is road map 10 §10.4.

## Module map

- `lib.rs` — `#![forbid(unsafe_code)]`, module declarations and re-exports
  only. No implementation code.
- `diagnostic.rs` — `Level`, `Diagnostic` (`{level, message, line, column,
  frame}`, §5b) and its JSON, keys in that order.
- `images.rs` — the decoded-image cache (spec §11 G-39, #127): `Asset
  {data, digest}`, a process-wide `Mutex` map from an asset's own SHA-256
  to `Ready`/`Building`/`Refused`/`Skipped {len}`, `set_image_cache_limit`,
  `image_cache_bytes`, the doc-hidden `image_cache_builds`, `cached_kind`,
  and the builder of a stored-deflate RGBA8 PNG copy, used only when it
  decodes to exactly the original's pixmap and `imagesize` reads the same
  size. No lock is held across a decode, an encode or a usvg call; a
  build writes only while its digest is still `Building`; the default limit
  is 0, so a binary that sets none takes the original route.
- `library.rs` — `Library`: the font set (`fontdb`, from bytes, never
  `load_system_fonts`, G-6) and the asset map (each asset keeps its own
  SHA-256; a PNG or JPEG kind is asked of the cache first), their content `version`
  (SHA-256 with length prefixes), the `measure_text` memo, and the
  crate-private `options()` builder whose resolvers record into a `Probe`
  what resvg never reports. The generic families map to bundled faces
  (`serif` Source Serif 4, `sans-serif` Source Sans 3, `monospace` IBM Plex
  Mono, G-6), and `select_font` queries only the text's own families,
  never usvg's appended serif fallback, so a missing family still draws
  nothing and is warned.
- `raster.rs` — `rasterize`, `MAX_SIDE`, the RGBA→BGRA row copy into the
  caller's strided buffer, and every warning text `rasterize` answers:
  missing family, unparseable `font-family` (the scan of attributes, `style`
  attributes and `<style>` sheets, and the family of a `font` shorthand in
  a `style` attribute or sheet), unknown href, data: URL, non-image
  asset, size mismatch. The texts are load-bearing: tests match them and
  the app shows them on the clip.
- `measure.rs` — `FontStyle`, `TextFont` (with `preserve_space`, the
  `xmlSpace` key, G-22), `TextMetrics`, `measure_text`; a generic family
  is written unquoted.
- `module.rs` — `Module` (`Send + Sync + Clone`, holds no QuickJS object):
  `compile`, the SHA-256 revision (G-13), `meta`/`schema` read through
  `JSON.stringify` in the module's key order (`{}` when not exported),
  `defaults()`, its top-level warnings (`warnings()`, G-21 (b)).
- `runtime.rs` — `Engine` (one QuickJS `Runtime` + `Context` per (thread,
  module), §5b's limits, the interrupt deadline), the `thread_local!` map
  swept by `Weak` before each call, at most `ENGINES_PER_THREAD` (16, spec
  §11 G-21) engines with the least recently used evicted after the call,
  `svg`, `Engine::parse_colours` (the stdlib's `__parseColour` per text
  under one deadline, storing nothing; G-25), `engine_count`, `HEAP_BYTES`,
  `STACK_BYTES`, `SVG_BYTES` (8 MiB, spec §11 G-20 (c)). The crate's one
  clock.
- `sandbox.rs` — the sandbox script (G-5) and the loader that resolves no
  specifier, with `IMPORT_REFUSAL`.
- `exception.rs` — QuickJS error → Diagnostic: `{name}: {message}`, the
  position from `stack` (the module's own frame first), the budget's
  sentences, what `render` returned (a string over `SVG_BYTES` refused by its
  length, before the `<svg` check). The texts are load-bearing.
- `host.rs` — the globals `__measureText`, `__assetNames`, `__warn` and
  `__namedColour` (svgtypes' named-colour table for the stdlib's colour
  parser).
- `props.rs` — `check_schema` (compile, strict; it takes a colour reader,
  which `Module::compile` builds from `Engine::parse_colours` over the
  schema's colour defaults, G-25 (a)), `overlay` (render,
  lenient; every surprise a warning) and the schema's limits `MAX_PROPS`,
  `MAX_OPTIONS`, `MAX_STRING` and `TYPES`, which the core restates as
  `GRAPHIC_<X>` (`core/tests/graphic_ffi.rs` pins each pair;
  `tests/reference.rs` pins the numbers the reference states, and its
  typings' key cap).
- `stdlib.js`, `noise.js`, `path.js` — §5c's standard library, evaluated
  as SCRIPTS (globals) in that order before the sandbox; each under 400
  lines. `path.js` is G-31's path helpers (`getLength`,
  `getPointAtLength`, `evolvePath`): pure JavaScript, a curve measured as
  64 chords, a draw-on dashed by the longest subpath, the last paths
  memoised per engine (at most 32, at most 50,000 chords and characters) —
  a cache that changes no answer, held in a closure no module can reach.
  No helper answers `Infinity` or NaN: a path that would make one do so
  is refused in the parse sentence (five checks through one predicate,
  `finite`; `path.test.js`'s row `T8 a number that is not finite`).

## Rules

- **The crate takes bytes and answers bytes** (G-2, G-5): no file system,
  environment or network anywhere in `src/`, and no clock except the call
  deadline. `rg 'std::(fs|env|net)' graphic/src` must print nothing, and
  `rg -n 'std::time' graphic/src` must print exactly one line, the import
  in `src/runtime.rs`: the interrupt deadline stops a call that runs too
  long and feeds no pixel, so a frame stays a function of G-5's inputs.
  Tests may read files and the clock; `src/` may not.
- `#![forbid(unsafe_code)]` stays in `lib.rs`.
- Every `src/` file stays under 400 lines.
- Tests are black-box in `tests/`, through `graphic::` only, and every claim
  is an oracle — a pixel read back through `common::pixel`, an exact
  message, a comparison of two answers. The one exception is
  `tests/pins.json` (road map 10 §5l), a tripwire for upgrades.
- The root `CLAUDE.md`'s FFI three-file rule does not apply here: no `rc_*`
  export lives in this crate. G1d's `core/src/ffi_graphic.rs` is its one
  caller.
- **No closure handed to usvg holds the probe lock across a usvg call.** A
  nested SVG asset is parsed by `Tree::from_data_nested` inside
  `resolve_string`, and usvg forwards our `select_font` into that parse on
  the same thread; `std::sync::Mutex` is not re-entrant, so a lock held
  across it hangs the render. Each closure calls usvg first and locks only
  for its own push afterwards. `tests/families.rs`'s nested-asset case is
  the oracle.
- `usvg::Options` is not `Clone`: build it per call with `options()`.
- **`Engine`'s fields drop in declaration order: `render`, then the
  context, then the runtime.** Reversing them aborts the process in
  QuickJS's `JS_FreeRuntime`; `tests/module.rs`'s
  `dropped_modules_engines_are_swept` is the oracle (it SIGABRTs). A
  runtime never leaves the thread that made it, and the thread map's
  `RefCell` is never borrowed while JavaScript runs.
- The module is an ES module evaluated UNWRAPPED, so stack positions are
  the file's own. The standard library and the sandbox are scripts, which
  rquickjs names `eval_script`; `position` prefers the module's frame over
  theirs (`render.rs`'s positioned-throw test and the sandbox's
  `math_random` are the oracles).
- `tests/pins.json` is re-pinned with `GRAPHIC_REPIN=1 cargo test
  --release --test pins`, only after looking at the PNGs a mismatch
  writes to `target/pins/`.

## Dependencies, and why each

- `resvg` 0.48.1, `default-features = false`, features `text`,
  `raster-images`, `svgz`: its defaults minus `system-fonts` and
  `memmap-fonts`, which reach the file system — off for G-6 (the fonts are
  the bundled faces and the package's) and G-2 (the crate reads no files),
  NEVER for size. Binary size and build time are not reasons to leave a
  feature out. `raster-images` is required: without it resvg draws no PNG,
  JPEG, GIF or WebP `<image>`.
- `serde_json` with `preserve_order`: JSON key order is part of the
  contract (the Diagnostic's and TextMetrics' keys; a module's schema).
- `sha2`: the Library's content version.
- `svgtypes` 0.16.1 (usvg 0.48.1's own pin): parse `font-family` exactly as
  usvg does, so the scan agrees with usvg on what failed; and its
  named-colour table (`__namedColour`), so a colour name means what usvg
  draws.
- `simplecss` 0.2 (usvg's own pin; usvg does not re-export it): read
  `<style>` sheets and `style` attributes as usvg does.
- `rquickjs` 0.14.0 with `loader` only: quickjs-ng 0.16.2, vendored and
  built by `rquickjs-sys`. `loader` exists for `set_loader`; the resolver
  and loader installed refuse every specifier, and none of rquickjs's own
  loaders (which reach the file system) is used.
- `png` 0.18 (tiny-skia 0.12's own decoder, already in the lock): decode as
  `Pixmap::decode_png` does and write the stored copy (G-39); still the
  pins' PNG dump.
- `zune-jpeg` 0.5 (resvg 0.48.1's own JPEG decoder): decode as resvg does,
  so a JPEG's copy is checked against resvg's own pixels.
- `imagesize` 0.15 (usvg's own size reader): check a copy's size reads the
  same as its original's.
- Dev: `flate2`, to gzip an `.svgz` asset in a test.
