# core/CLAUDE.md — Rust core rules

Applies to everything under `core/`. Build commands and the FFI three-file
lockstep are in the root `CLAUDE.md`; the full design is
`designs/reelcut-design.md` (§5–7 are the schemas, §7.10 this module map).

## Module map

- `lib.rs` — module declarations and re-exports only. No implementation code.
- `model.rs` — the spec §5.2 types with serde derives and the serde
  defaults that say what an absent key means. The struct field names ARE
  the JSON keys, and the file is only the schema.
- `model_query.rs` — reading a project: `Project::new`, id allocation, the
  `clip`/`track`/`media`/`marker`/`nest` lookups, `clips_on`,
  `is_missing_media`, `duration`, `validate` with its nesting walk, and the
  three source-window measurements every placement op clamps against —
  `source_head` (what lies before the window), `content_length` (the window)
  and `source_length` (what a window starting at `in` could grow to).
- `time.rs` — `Ticks`, `TIMESCALE`, `Fps`, frame snapping, timecode
  format/parse (non-drop `HH:MM:SS:FF` and `HH:MM:SS.mmm`).
- `edit.rs` — the op enum + serde and `apply`. **Its module doc IS the op
  schema table** (the `adjust.rs` pattern in Rasterize) and
  `app/Sources/ReelCore.swift`'s typed builders mirror it.
- `edit_clip.rs` / `edit_props.rs` / `edit_track.rs` / `edit_time.rs` — the
  §6 ops in `impl Project` blocks: clip placement; the four property patches
  with the range checks that police them; tracks, markers, canvas, media;
  ripple, insert time, range delete, freeze frame.
- `edit_edge.rs` / `edit_insert.rs` — the cutting moves that keep something
  fixed on purpose: `slip` and `roll` (the clip's place, and the pair's
  outer edges), `insert_clip` and `overwrite_clip` (the other tracks, and
  the whole timeline's length). `edit_edge.rs` clamps against
  `model_query.rs`'s three source measurements rather than restating them;
  `edit_insert.rs` takes its one length from `edit_clip.rs`'s
  `whole_media_length`, which is the length `add_clip` itself uses, so the
  room an insert opens is exactly the room the clip needs.
- `edit_action.rs` / `edit_nest.rs` / `edit_paste.rs` — the ops with a
  concern of their own: the action ops and their no-overlap rule; `nest` and
  `unnest`; `paste`, which has to make another document's clips fit.
  (Spec §7.10's table is the same list. Each of these was split out of
  `edit_clip.rs` under the "a new concern is a new module" rule, which is
  also how `edit_props.rs` came about; `edit_clip.rs` was 1736 lines and is
  still ~1220 — see "Modules and size" below.)
- `actions.rs` — action evaluation and interpolation; `clip_state`.
- `transition.rs` — overlap detection, the overlap rule, progress at *t*.
- `evaluate.rs` — `composition_plan()` (A/B assignment, instruction
  tiling) and the `assign()` the recipe shares with it.
- `recipe.rs` — `frame_recipe(t)`: the layer list at one instant.
- `nest.rs` — flattening a nest into the clips it stands for, and the
  transform they inherit. Every walk over "what actually plays" goes
  through it: `evaluate.rs`, `recipe.rs` and `audio.rs` all consume its
  instances rather than `Project::clips`.
- `audio.rs` — envelopes: fades, volume actions, ducking, mute.
- `snap.rs` — candidates and `resolve`.
- `format.rs` — `RC_FORMAT_VERSION`, `RC_CAPS`, read-any-version /
  write-current.
- `export.rs` — presets (one per encoding; the two image caps are the only
  sizes in the table) and settings resolution. `preset(id)` is the one
  lookup both resolvers share.
- `export_size.rs` — `export_sizes(preset)`: the sizes the export sheet
  offers for a document and a format — the format's cap, the document's
  own size, then the standard sizes named by their SHORT edge and fitted to
  the document's aspect, rounded to even; rows may repeat and the sheet
  hides them. Also `fit_within`, what a size MEANS on an image format (the
  picture fitted inside it, never upscaled), which `export_settings` uses
  so the resolved numbers are the file's.
- `agent.rs` — embedded MCP server (streamable HTTP, tools only).
  **Generic** — knows nothing about video; the host registers the catalog
  and a callback. Copied from Rasterize; do not add domain knowledge.
- `ffi.rs` / `ffi_edit.rs` / `ffi_query.rs` / `ffi_agent.rs` — thin shims
  only; shared plumbing lives in `ffi_util.rs`, never copy-pasted.

## Rules

**Modules and size.** New feature area = new module with its own
`impl Project` block. Soft cap ~600 lines; needing a new `// ---- name --`
banner section is the signal to split. Every module keeps a `//!` doc;
numeric/algorithmic choices get prose "why" comments.

Two modules are over the cap today and are known debt, not licence:
`edit_clip.rs` (~1200 — the placement ops are one concern and every further
cut fragments it; the action ops were the M3 cut, into `edit_action.rs`) and
`model.rs` (~940 — almost all of it is §5.2 type declarations). Do not add
to either without taking something out: a new placement op goes in a new
module (`edit_edge.rs`, `edit_insert.rs`), and the next cut in `model.rs`,
which the schema will need within a phase or two, is the §5.2 property
types (`VideoProps` and its friends) into a `model_props.rs`. `model.rs`
came DOWN from 1330 when the lookups and `validate` moved to
`model_query.rs`; `evaluate.rs` came off the list the same way, its recipe
half moving to `recipe.rs` and the nest walk to `nest.rs`.

**One implementation per algorithm.** Before writing time math, find the
existing implementation and route through it. Shared constants have exactly
one home (`TIMESCALE` in `time.rs`; `RC_*` caps in `format.rs`).

**Purity.** Every edit takes `&self` and returns a new value — internally
clone-then-mutate. An op that would change nothing returns `None`, never an
identical copy: an identical copy registers a phantom undo step in the app.

**Errors.** Two tiers, no error enum: `Option<T>` = the op is valid but
changes nothing, or a domain refusal, with the reason in the doc comment;
`Err(String)` = invalid arguments, unknown ids, parse failures — lowercase
messages naming the offending value. No input may panic. FFI mapping:
`None` → NULL with `err_out` untouched; `Err` → `set_err(err_out, …)`;
caught panic → `"internal error: <what>"`.

**Times.** Every tick value that reaches the model is snapped to the
document's frame grid first (`time::snap_to_frame`). Never store a
sub-frame time.

**FFI exports.** Every export: `#[no_mangle] pub unsafe extern "C"`, a `///`
comment restating the header contract, a `/// # Safety` paragraph, NULL
tolerance first, narrow `unsafe {}` blocks. Route through the shared helpers
in `ffi_util.rs` — a freshly hand-rolled `catch_unwind` is a review flag.
Export names mirror the Rust method exactly.

**Format changes.** Any change to persisted project state bumps
`RC_FORMAT_VERSION` in `format.rs` **and** the `#define` in
`core/include/reelcut_core.h`; the reader must keep accepting every prior
version; the writer enforces the reader's caps.

**Tests.** All tests are black-box in `core/tests/` (no `#[cfg(test)]` in
`src/`), exercised **through the FFI** wherever possible, and verified
against independently written oracles — never golden files. Shared helpers
live in `tests/common/`; new feature area = new test file. Every new export
gets at least one test plus inclusion in the null-safety sweep. Finish Rust
work with `cargo fmt` and a clean `make lint`.
