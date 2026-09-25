# graphic/CLAUDE.md — the graphics engine's rules

Applies to everything under `graphic/`, the crate that draws a graphic clip
(road map 10, `designs/reelcut-roadmap-10.md` §5a). Build commands are the
root `CLAUDE.md`'s: `make test` and `make lint` run this crate after the
core. The crate's record is road map 10 §10.4.

## Module map

- `lib.rs` — `#![forbid(unsafe_code)]`, module declarations and re-exports
  only. No implementation code.
- `diagnostic.rs` — `Level`, `Diagnostic` (`{level, message, line, column,
  frame}`, §5b) and its JSON, keys in that order.
- `library.rs` — `Library`: the font set (`fontdb`, from bytes, never
  `load_system_fonts`, G-6) and the asset map, their content `version`
  (SHA-256 with length prefixes), the `measure_text` memo, and the
  crate-private `options()` builder whose resolvers record into a `Probe`
  what resvg never reports.
- `raster.rs` — `rasterize`, `MAX_SIDE`, the RGBA→BGRA row copy into the
  caller's strided buffer, and every warning text `rasterize` answers:
  missing family, unparseable `font-family` (the scan of attributes, `style`
  attributes and `<style>` sheets), unknown href, data: URL, non-image
  asset, size mismatch. The texts are load-bearing: tests match them and
  the app shows them on the clip.
- `measure.rs` — `FontStyle`, `TextFont`, `TextMetrics`, `measure_text`.

## Rules

- **The crate takes bytes and answers bytes** (G-2, G-5): no file system,
  clock, environment or network anywhere in `src/`.
  `rg 'std::(fs|env|net|time)' graphic/src` must print nothing. Tests may
  read files; `src/` may not.
- `#![forbid(unsafe_code)]` stays in `lib.rs`.
- Every `src/` file stays under 400 lines.
- Tests are black-box in `tests/`, through `graphic::` only, and every claim
  is an oracle — a pixel read back through `common::pixel`, an exact
  message, a comparison of two answers. The one exception is G1c's
  `tests/pins.json` (road map 10 §5l).
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

## Dependencies, and why each

- `resvg` 0.48.1, `default-features = false`, features `text`,
  `raster-images`, `svgz`: its defaults minus `system-fonts` and
  `memmap-fonts`, which reach the file system — off for G-6 (the fonts are
  the bundled faces and the package's) and G-2 (the crate reads no files),
  NEVER for size. Binary size and build time are not reasons to leave a
  feature out. `raster-images` is required: without it resvg draws no PNG,
  JPEG, GIF or WebP `<image>`.
- `serde_json` with `preserve_order`: JSON key order is part of the
  contract (the Diagnostic's and TextMetrics' keys; G1c's schemas).
- `sha2`: the Library's content version.
- `svgtypes` 0.16.1 (usvg 0.48.1's own pin): parse `font-family` exactly as
  usvg does, so the scan agrees with usvg on what failed.
- `simplecss` 0.2 (usvg's own pin; usvg does not re-export it): read
  `<style>` sheets and `style` attributes as usvg does.
- Dev: `flate2`, to gzip an `.svgz` asset in a test.
