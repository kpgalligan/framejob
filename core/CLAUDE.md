# core/CLAUDE.md — Rust core rules

Applies to everything under `core/`. Build commands and the FFI three-file
lockstep are in the root `CLAUDE.md`; the full design is
`designs/reelcut-design.md` (§5–7 are the schemas, §7.10 this module map).

## Module map

- `lib.rs` — module declarations and re-exports only. No implementation code.
- `model.rs` — the spec §5.2 types with serde derives and the serde
  defaults that say what an absent key means. The struct field names ARE
  the JSON keys, and the file is only the schema — its SHAPE: the project,
  its tracks, clips, sources, actions, markers and nests.
- `model_props.rs` — the schema's VOCABULARY: the §5.2 per-clip property
  types (`VideoProps`, `Crop`, `Shadow`, `ColorAdjust`, `Chroma`,
  `Filter`, `Reflection`, `Spotlight`, `AudioProps`, `Compressor`, `Duck`,
  `TextProps`, `Outline`, `Backdrop`, `ShapeProps`, `Stroke` and their
  enums) with their defaults. Re-exported whole by `model.rs`, so every
  `crate::model::X` path and the `lib.rs` re-exports are unchanged; it is a
  separate file because of the size rule, not a separate concern.
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
  §6 ops in `impl Project` blocks: clip placement; the five property
  patches (the four groups, and `set_clip` for the clip's own name and
  label) and `Group`, the vocabulary the patches and `paste_attributes`
  share; tracks, markers, canvas, media; ripple, insert time, range delete,
  freeze frame.
- `props_check.rs` — the range checks every value written into a property
  group passes first: `check_video` / `check_audio` / `check_text` /
  `check_shape`, the `finite` / `in_range` family they are built from, and
  the bounds they check against (`SCALE_MIN`, `SPOT_ZOOM_MAX`, the
  compressor's…), which `actions.rs`'s `clamp_video` reads too. Cut out of
  `edit_props.rs` in road map 2's phase 2, and cut THERE because a range
  check is a fact about the vocabulary, not about an edit: it neither knows
  nor cares whether a patch, a paste, a new title or a canvas colour
  produced the struct it reads. `Project::check_group` (still in
  `edit_props.rs`) is how a patch and a `paste_attributes` copy run the
  same check, so a hand-written payload cannot smuggle in a value the
  inspector would refuse.
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
  `unnest`; `paste`, which has to make another document's clips fit, and
  `paste_attributes`, which reads the same payload and places nothing —
  the EARLIEST clip's property groups (then the front-most, then the
  lower id; never the array's first, which is creation order) replaced
  whole onto clips already there, never merged.
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
- `audio.rs` — envelopes: fades, volume actions, ducking, mute and solo.
  Solo is judged per container — the timeline, or one nest's own tracks —
  in `Voice::of` against that container's track set (`silenced`: muted, or
  some track in the set soloed and this one not; mute wins), and it is an
  envelope exactly like mute: the plan's segments, `plays_audio` and
  `assign` never see it.
- `snap.rs` — candidates and `resolve`.
- `format.rs` — `RC_FORMAT_VERSION`, the `MAX_*` caps (four of them
  `RC_MAX_*` in the header), read-any-version / write-current.
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
`edit_clip.rs` (~1225 — the placement ops are one concern and every further
cut fragments it; the action ops were the M3 cut, into `edit_action.rs`) and
`edit_track.rs` (674 — tracks, markers, canvas and media, four small
concerns in one block). Do not add to either without taking something out:
a new placement op goes in a new module (`edit_edge.rs`, `edit_insert.rs`),
and the next cut in `edit_track.rs` is `set_canvas` with its `rescale` /
`resnap` / `check_dimension` helpers into an `edit_canvas.rs`. Two more
sit at the line and take nothing without a cut of their own: `edit.rs`
(691, a module doc that IS the op table and grows a row per op) and
`edit_paste.rs` (600). `model.rs` is OFF the list: it came DOWN from 1330
to 940 when the lookups and `validate` moved to `model_query.rs`, and to
462 in road map 2's phase 2 when the §5.2 property types moved to
`model_props.rs` (531); `edit_props.rs` came back under the cap in the
same phase when its range checks moved to `props_check.rs`; `evaluate.rs`
came off the list the same way, its recipe half moving to `recipe.rs` and
the nest walk to `nest.rs`.

**One implementation per algorithm.** Before writing time math, find the
existing implementation and route through it. Shared constants have exactly
one home (`TIMESCALE` in `time.rs`; `RC_*` caps in `format.rs`; the
inspector's bounds in `props_check.rs`).

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
version; the writer enforces the reader's caps. The version is 3. A bump
whose new fields all carry a serde default needs no migrate step —
version 3 (a clip's `name` and `label`, a track's `solo`) has none, and
`format.rs`'s MIGRATION HOOK comment says so — but it still bumps, so an
older build refuses a file whose fields it would otherwise silently drop;
a bump that changes a field's SHAPE adds a step there (`migrate_1_to_2`).
Either way a `schema_vN.rs` test opens the previous versions' fixtures
and reads the new keys' ORDER off the written text, since a parsed
`serde_json::Value` sorts them.

**Tests.** All tests are black-box in `core/tests/` (no `#[cfg(test)]` in
`src/`), exercised **through the FFI** wherever possible, and verified
against independently written oracles — never golden files. Shared helpers
live in `tests/common/`; new feature area = new test file. Every new export
gets at least one test plus inclusion in the null-safety sweep. Finish Rust
work with `cargo fmt` and a clean `make lint`.
