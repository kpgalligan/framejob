# graphic/vendor — the patched tiny-skia (spec §11 PR-13)

`tiny-skia/` is tiny-skia **0.12.0** from crates.io, the version resvg 0.48.1
pins. It is vendored with a four-file patch that dithers gradients (#375
part 1). Nothing else in the crate is edited.

## Provenance

- Crate: `tiny-skia` 0.12.0, crates.io (`Cargo.toml`'s `[package]`).
- Upstream commit: `e48b9027762d33731e60e40eb17eaa4f583b0185`, from the
  crate's own `.cargo_vcs_info.json`. Repository:
  <https://github.com/linebender/tiny-skia>.
- Copied from the cargo registry
  (`~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/tiny-skia-0.12.0/`)
  whole, except `.cargo-ok`, `.cargo/`, `.github/`, `.gitignore`,
  `.typos.toml` and `Cargo.lock`. `tests/` and `examples/` are kept, because
  the crate's manifest names them.
- Licence: BSD-3-Clause, `tiny-skia/LICENSE` (kept as shipped).

## What the patch does, and why

Before the patch, tiny-skia evaluated a gradient in float and rounded it to 8
bits at store, with no dither. A dark gradient over a wide area therefore
drew in visible single-level bands; #374 measured 14–50 px wide steps. The
patch adds one pipeline stage, `Stage::Dither`, and pushes it once, at the
end of `Gradient::push_stages`, after the gradient's own stages and before
blend and store. That is Skia's own place for a dither.

- **The offset.** The stage adds a fixed offset by pixel position, uniform
  over ±7/16 of a level (`DITHER_SPAN` 0.875), to R, G and B alike. It clamps
  each channel to [0, a] and leaves alpha alone.
- **The hash.** It is lowbias32 of `lowbias32(y ^ 0x9E3779B9) ^ x`. It reads
  no frame, thread or global state, so a graphic draws the same pixels on
  every call, on any thread.
- **Exactness.** The span is under one level, so a premultiplied value on a
  level stays exact.
- **Highp only.** lowp has no dither (its entry is `null_fn`), so any
  pipeline holding the stage compiles highp.

Linear and radial gradients are covered, both the two-stop fast path and the
many-stop stage. Solid fills, images and text never reach the stage.

The four files, each change marked `// Frame Job (spec §11 PR-13):`:

- `src/pipeline/mod.rs`: `Stage::Dither` appended, and `STAGES_COUNT` taken
  from it.
- `src/pipeline/highp.rs`: `dither` appended to `STAGES`, plus the stage, its
  hash and its constants.
- `src/pipeline/lowp.rs`: `null_fn, // Dither` appended to `STAGES`.
- `src/shaders/gradient.rs`: `p.push(pipeline::Stage::Dither);` after
  `push_stages_post(p);`.

The tests are `graphic/tests/dither.rs`, `core/tests/graphic_ffi.rs`'s
`a_gradient_is_dithered_through_the_ffi`, and
`tools/proof/raster_dither_proof.py` with its mutants.

## How it is linked

Two `[patch.crates-io]` tables point at it:

- `graphic/Cargo.toml`: `tiny-skia = { path = "vendor/tiny-skia" }`.
- `core/Cargo.toml`: `tiny-skia = { path = "../graphic/vendor/tiny-skia" }`.

Cargo ignores a `[patch]` in a dependency's manifest, and the staticlib the
app links is built from `core/`, so both tables are needed. In both lock
files tiny-skia is a path package, with no `source` or `checksum`.

The crate is not a workspace member, so `make lint` and `cargo fmt --check`
never cover it. Never reformat it: the stored diff must stay exact.

## The stored diff, and checking it

`tiny-skia-dither.diff` is the whole patch. It applies with `patch -p1`
inside a fresh copy of the pristine crate. To check it against the tree:

1. Make the pristine snapshot (gitignored):

   ```
   mkdir -p tools/proof/work/raster-dither/pristine
   cp -R ~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/tiny-skia-0.12.0 tools/proof/work/raster-dither/pristine/
   (cd tools/proof/work/raster-dither/pristine/tiny-skia-0.12.0 && rm -rf .cargo-ok .cargo .github .gitignore .typos.toml Cargo.lock)
   ```

   If the registry no longer holds the crate, `cargo fetch` in `graphic/` with
   the `[patch]` tables removed brings it back.

2. Run the diff command from the repository root. `command diff` skips a
   shell's `--color` wrapper, and the `sed` drops BSD diff's tab-separated
   mtimes and the long prefixes:

   ```
   command diff -ru tools/proof/work/raster-dither/pristine/tiny-skia-0.12.0 graphic/vendor/tiny-skia | sed -E -e 's#^--- tools/proof/work/raster-dither/pristine/tiny-skia-0\.12\.0/([^[:space:]]+).*#--- a/\1#' -e 's#^\+\+\+ graphic/vendor/tiny-skia/([^[:space:]]+).*#+++ b/\1#'
   ```

   Its output names exactly the four files and holds no `Only in` line.

3. Check it against the stored diff:

   ```
   <the diff command> | cmp - graphic/vendor/tiny-skia-dither.diff
   ```

   This must exit 0. After a deliberate change to the patch, write the
   command's output to `tiny-skia-dither.diff` instead.

## Re-applying on an upgrade

When resvg moves to a new tiny-skia:

1. Make the new version's pristine snapshot, as in step 1 above, with the new
   version's name.
2. Replace `tiny-skia/` with a copy of it.
3. Apply `tiny-skia-dither.diff` with `patch -p1` inside it. Resolve any hunk
   by hand, keeping the stage last in `Stage` and `STAGES`.
4. Bump the version in this README and the upstream commit from the new
   `.cargo_vcs_info.json`.
5. Re-pin both `[patch.crates-io]` tables (their paths stay the same), and
   let cargo rewrite both lock files.
6. Regenerate the stored diff with the diff command.
7. Run `cargo test --release --test dither` and `--test pins` in `graphic/`.
   Re-pin `tests/pins.json` (`GRAPHIC_REPIN=1`) only after looking at the
   PNGs a failing run writes to `target/pins/`.
8. Run `cargo test --release --test graphic_ffi` in `core/`, then
   `raster_dither_proof.py` and its mutants.

If upstream gains a gradient dither of its own, drop this vendoring and both
tables, and record that in PR-13.
