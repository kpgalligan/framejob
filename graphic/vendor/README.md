# graphic/vendor — the patched tiny-skia (spec §11 PR-13, PR-15)

`tiny-skia/` is tiny-skia **0.12.0** from crates.io, the version resvg 0.48.1
pins. It is vendored with two patches, applied in this order: a four-file
patch that dithers gradients (#375 part 1, PR-13), and an eight-file patch
that draws into a pixmap deeper than 8 bits (#374, PR-15). Nothing else in the
crate is edited.

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

## What the deep patch does, and why (spec §11 PR-15)

tiny-skia's only `Pixmap` is RGBA8, so a gradient lost its levels before the
16-bit-float compositor saw it. The patch lets a pixmap carry more, without
changing what an 8-bit pixmap draws: the crate's 8-bit path is byte for byte
what the dither patch alone draws.

- **The representation.** A deep `Pixmap` keeps its RGBA8 `data` and gains a
  residual plane of the same size (`lo`). A channel's value in 1/256 levels
  is `data × 256 + (lo as i8)`, with 65,280 as 1. `data` alone is the value
  rounded to 8 bits, so resvg, which is not vendored and reads `data()` as
  RGBA8, stays correct.
- **The door.** `tiny_skia::with_deep_pixmaps(f)` runs `f` with every
  `Pixmap::new` on the calling thread deep: the root and each layer resvg
  makes under it. It is a thread-local flag restored by a drop guard, so a
  panic restores it and another thread's 8-bit raster is untouched. It needs
  the `std` feature, which resvg enables.
- **The pipeline.** highp gains deep forms of load-destination, store,
  source-over and the pattern sampler's gather, and a real `load_mask_u8`
  (upstream leaves it empty because only lowp ever ran it). A deep
  destination forces highp. A gradient pushes no `Stage::Dither` for a deep
  destination and pushes it as before for an 8-bit one.
- **Reading a deep pixmap at 8 bits** rounds it with PR-13's offset
  (`pixmap::collapse`, through `highp::dither_offset_256`): in `data_mut`
  and `pixels_mut`, in `clone` and `clone_rect` (only resvg's filters copy a
  pixmap), and in a luminance `Mask::from_pixmap`. A value on a level never
  moves. So a filtered region and a luminance mask's coverage are 8-bit and
  dithered as before, and an owned pixmap is 8-bit after `data_mut`.
  `collapse` gives the offset to every pixel that holds a residual, not only
  a gradient's: in a filtered region of a deep raster, a flat translucent
  colour between two levels and a soft edge come out as a mix of the two
  neighbouring levels, where the 8-bit raster draws one level flat
  (`a_flat_colour_in_a_filter_takes_the_offset` pins it).
- **The output.** `Pixmap::copy_rgba16` writes premultiplied RGBA at 16 bits a
  channel, 65,535 as 1. The residual plane is not public.

The eight files, each hunk marked `// Frame Job (spec §11 PR-15):` (a
struct literal's `lo:` line carries no marker of its own):

- `src/pixmap.rs`: the plane on `Pixmap`, `PixmapRef`, `PixmapMut` and
  `SubPixmapMut`, the door, `collapse`, `copy_rgba16`, and `Clone` written
  out.
- `src/pipeline/highp.rs`: the deep stages, `load_mask_u8` and
  `dither_offset_256`.
- `src/pipeline/mod.rs`: `deep_dst` on the builder, the two-plane accessors
  and the offset's re-export.
- `src/pipeline/blitter.rs`: highp forced, and the solid memset's residual.
- `src/painter.rs`: `apply_mask` in highp for a deep pixmap.
- `src/mask.rs`: the luminance mask's read, and `lo: None` on a mask's
  sub-pixmaps.
- `src/shaders/gradient.rs`: no dither for a deep destination.
- `src/lib.rs`: the door's re-export.

The tests are `graphic/tests/deep.rs`, `core/tests/graphic_ffi.rs`'s
`a_gradient_keeps_its_levels_through_the_ffi`, and
`tools/proof/raster_dither_proof.py`'s rows E1 and D1–D7 with their mutants.

## How it is linked

Two `[patch.crates-io]` tables point at it:

- `graphic/Cargo.toml`: `tiny-skia = { path = "vendor/tiny-skia" }`.
- `core/Cargo.toml`: `tiny-skia = { path = "../graphic/vendor/tiny-skia" }`.

Cargo ignores a `[patch]` in a dependency's manifest, and the staticlib the
app links is built from `core/`, so both tables are needed. In both lock
files tiny-skia is a path package, with no `source` or `checksum`.

The crate is not a workspace member, so `make lint` and `cargo fmt --check`
never cover it. Never reformat it: the stored diff must stay exact.

## The stored diffs, and checking them

`tiny-skia-dither.diff` is the dither patch against the pristine crate, and
`tiny-skia-deep.diff` is the deep patch against the crate with the dither
patch applied. Each applies with `patch -p1`; the two in that order make the
vendored tree. To check them against the tree:

1. Make the pristine snapshot (gitignored):

   ```
   mkdir -p tools/proof/work/raster-dither/pristine
   cp -R ~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/tiny-skia-0.12.0 tools/proof/work/raster-dither/pristine/
   (cd tools/proof/work/raster-dither/pristine/tiny-skia-0.12.0 && rm -rf .cargo-ok .cargo .github .gitignore .typos.toml Cargo.lock)
   ```

   If the registry no longer holds the crate, `cargo fetch` in `graphic/` with
   the `[patch]` tables removed brings it back.

2. Make the dithered snapshot beside it: a copy of the pristine one with the
   dither diff applied.

   ```
   mkdir -p tools/proof/work/raster-dither/dithered
   cp -R tools/proof/work/raster-dither/pristine/tiny-skia-0.12.0 tools/proof/work/raster-dither/dithered/
   (cd tools/proof/work/raster-dither/dithered/tiny-skia-0.12.0 && patch -s --no-backup-if-mismatch -p1 < ../../../../../../graphic/vendor/tiny-skia-dither.diff)
   ```

   The dither diff applying cleanly to the pristine crate is its check: it is
   no longer the whole difference from the tree.

3. Run the diff command from the repository root. `command diff` skips a
   shell's `--color` wrapper, and the `sed` drops BSD diff's tab-separated
   mtimes and the long prefixes:

   ```
   command diff -ru tools/proof/work/raster-dither/dithered/tiny-skia-0.12.0 graphic/vendor/tiny-skia | sed -E -e 's#^--- tools/proof/work/raster-dither/dithered/tiny-skia-0\.12\.0/([^[:space:]]+).*#--- a/\1#' -e 's#^\+\+\+ graphic/vendor/tiny-skia/([^[:space:]]+).*#+++ b/\1#'
   ```

   Its output names exactly the deep patch's eight files and holds no
   `Only in` line.

4. Check it against the stored diff:

   ```
   <the diff command> | cmp - graphic/vendor/tiny-skia-deep.diff
   ```

   This must exit 0. After a deliberate change to the deep patch, write the
   command's output to `tiny-skia-deep.diff` instead. A deliberate change to
   the dither patch is made the same way against the pristine snapshot, with
   the deep patch's eight files left out of the comparison, and the deep diff
   regenerated after it.

## Re-applying on an upgrade

When resvg moves to a new tiny-skia:

1. Make the new version's pristine snapshot, as in step 1 above, with the new
   version's name.
2. Replace `tiny-skia/` with a copy of it.
3. Apply `tiny-skia-dither.diff` with `patch -p1` inside it, then
   `tiny-skia-deep.diff`. Resolve any hunk by hand, keeping the dither stage
   last in `Stage` and `STAGES`.
4. Bump the version in this README and the upstream commit from the new
   `.cargo_vcs_info.json`.
5. Re-pin both `[patch.crates-io]` tables (their paths stay the same), and
   let cargo rewrite both lock files.
6. Regenerate both stored diffs with the diff commands.
7. Run `cargo test --release --test dither`, `--test deep` and `--test pins` in `graphic/`.
   Re-pin `tests/pins.json` (`GRAPHIC_REPIN=1`) only after looking at the
   PNGs a failing run writes to `target/pins/`.
8. Run `cargo test --release --test graphic_ffi` in `core/`, then
   `raster_dither_proof.py` and its mutants.

If upstream gains a gradient dither of its own, drop the dither patch and
record that in PR-13; the vendoring and both tables stay while the deep patch
does.
