# core/CLAUDE.md — Rust core rules

Applies to everything under `core/`. Build commands and the FFI three-file
lockstep are in the root `CLAUDE.md`; the full design is
`designs/spec/` (§5 the schemas, §6 the op table, §7 the architecture,
§7.10 this module map in the spec's words; its `README.md` is the index). The long form of
each entry below — why the seam fell where it did — is
`designs/adr/core-file-history.md` (the full history of every cut, with its
line counts, is archived; see its "Original" line); this file is what
governs a module now.

## Module map

- `lib.rs` — module declarations and re-exports only. No implementation code.
- `model.rs` — the spec §5.2 SHAPE: the project, its tracks, clips, sources,
  actions, markers and nests, with the serde defaults that say what an absent
  key means. The struct field names ARE the JSON keys. Nothing else lives here.
- `model_props.rs` — the schema's VOCABULARY: the per-clip property types
  (`VideoProps`, `AudioProps`, `Crop`, `Shadow`, `ColorAdjust`, `Chroma`,
  `Filter`, `Reflection`, `BlendMode`, `Compressor`, `Duck`) and their
  defaults, re-exported whole by `model.rs` so every `crate::model::X` path
  holds. **`BlendMode`'s and `ObscureKind`'s declaration ORDER are shader
  discriminants** (`ProjectSnapshot.swift` derives the code from the case
  index, `Compositor.metal` compares against the same integers): append,
  never reorder. `Normal` is 0 with no `+1`, so a zeroed uniform block, an
  older recipe and a file with no `blend` key all render source-over.
- `model_text.rs` · `model_shape.rs` · `model_regions.rs` · `model_motion.rs`
  — the text, shape, region and motion vocabularies, each re-exported through
  `model_props.rs`. Text and shape are the two sources the model only
  DESCRIBES and the platform draws and measures: nothing in either file is
  ever a measured size. Regions (`Spotlight`, `ObscureRegion`, `SpotShape`,
  `MAX_OBSCURE`) share one coordinate frame — the centre as an offset in
  SOURCE pixels from the centre of the layer's cropped rect — which
  `edit_zoom.rs` writes out as an equation and nothing else restates. The
  one load-bearing declaration order in these four is `ObscureKind`'s
  (`model_regions.rs`), a shader discriminant like `BlendMode`'s above;
  elsewhere only the JSON spelling of every variant is, so a rename needs a migration step. The enums are closed:
  there is no neutral kind to fall back to.
- `model_words.rs` — the word-caption vocabulary (format version 9, road
  map 8's W1b): `TextCase`, `Word`, `WordMode`, `ActivePill` and
  `WordStyle` (whose `template()` is what `patch.rs`'s text template walks
  against), re-exported through `model_props.rs`; the FIELDS (`case`,
  `words`, `word_style`) close `TextProps`. Format version 12 (spec §11
  W-12) added three looks as KEYS, each off by default: `ActivePill.glide`,
  `WordStyle.active_fill` and `WordStyle.pause_dim` (0–1, range-checked in
  `props_check.rs`); `Word.end` is read by the recipe since then, not only
  by the pager. It also holds the two facts
  every writer of `text.words` shares, both `pub(crate)` and so named
  directly by their callers (a glob re-export cannot widen them):
  `token_count`, THE token rule (`split_whitespace` — the core is the one
  counter, spec §11 W-2), and `rebase_words`, the one saturating
  subtraction `trim_start`, `roll`, `add_transition`'s handle form and
  `split`'s second half make (W-3). Word times are clip-time POSITIONS: a
  negative start is legal, equal starts are legal, and `snap_animation`
  puts them on the grid after `check_text` has named what the caller sent.
- `model_graphic.rs` — the graphic vocabulary (format version 10, road
  map 10): `GraphicProps` (`name`, `width`, `height`, `in`, `length`,
  `props`) and `GRAPHIC_MIN_SIDE` / `GRAPHIC_MAX_SIDE` and the schema limits
  `GRAPHIC_MAX_PROPS` / `GRAPHIC_MAX_OPTIONS` / `GRAPHIC_MAX_STRING` /
  `GRAPHIC_TYPES` (`GRAPHIC_MAX_SIDE` restates the engine's `MAX_SIDE` and the
  header's `RC_GRAPHIC_MAX_SIDE`, and each other `GRAPHIC_<X>` the engine's
  `<X>`; `tests/graphic_ffi.rs`'s
  `one_max_side_in_the_engine_the_core_and_the_header` and its four
  `one_…_in_the_engine_and_the_core` tests pin them),
  re-exported through `model_props.rs`; the FIELD `Clip.graphic` stays in
  `model.rs`. And the `pub(crate)` checks every writer shares: `check_name`
  (G-3's `^[a-z0-9][a-z0-9-]{0,62}$`, its clause `NAME_RULE` shared with
  `validate`), `check_side`, `check_schema` (the engine's sentences, COPIED —
  no module of the model may name the crate, G-2), `check_props` (by dotted
  path against the schema the op carries, shape only without one; a `null`
  is a removal and is never checked), `check_typed` (one value against its
  entry, answered normalised; `edit_action_graphic.rs` calls it under
  `graphic.props.<key>`), `check_count` (on the map about to be
  STORED). **A props map is changed only by `insert` and
  `shift_remove`**: under `preserve_order`, `Map::remove` is `swap_remove`,
  and `Project ==` cannot see the reorder.
- `model_color.rs` — `normalise_color`, G-12's colour grammar (hex,
  `rgb()`/`rgba()`, `hsl()`/`hsla()` and the CSS named colours, from
  svgtypes' table) to lowercase `#rrggbb[aa]`; out of range is refused,
  never clamped. The stdlib's `__parseColour` implements the same grammar,
  and both suites read `graphic/tests/colours.json`. `rc_normalise_color`
  (`ffi.rs`) exports it for the Inspector's colour defaults (spec §11 G-25
  (c)), and `model_graphic.rs`'s `check_schema` refuses a `color` default
  it refuses (G-25 (a)). `color_channels` and `color_hex` (which
  `normalise_color` writes through) are `actions_graphic.rs`'s blend's.
- `model_query.rs` — reading a project: `Project::new`, id allocation, the
  `clip`/`track`/`media`/`marker`/`nest` lookups, `clips_on`, `duration`,
  `validate` with its nesting walk, and `source_size`. The three
  source-window measurements moved out to `source_window.rs`.
- `frame_grid.rs` — clip-time normalization shared by canvas rate changes,
  both full-paste paths and unnest. It snaps placement start, delegates the
  source-bounded duration to `source_window.rs`, clamps action spans, snaps
  present base motion/text timing through the patch snappers, and snaps a
  graphic's `in` and `length` through `recipe_graphic.rs`'s
  `graphic_resnapped` (spec §11 G-18). It does not change source positions,
  action-end payloads or audio envelopes.
- `source_window.rs` — THE source window: how much material a clip shows,
  how much lies either side of it, and the one way a source in point moves.
  **Every name here carries its UNIT**, because the readers divide by a
  clip's speed where the movers multiply by it: `content_length_in_source`,
  `last_in_point` and `last_still_time` answer in SOURCE ticks;
  `source_head_on_timeline`, `source_length_on_timeline` and
  `longest_duration_on_grid` — the bound, snapped DOWN (spec §11, #22) — in
  TIMELINE ticks. **Every site that WRITES a media clip's window reads the
  bound here, and which function it reads says what it writes** (spec §11,
  D4-2 to D4-5): `longest_duration_on_grid_of` is the bound from the pieces,
  with the clip's `start` among them, because a DURATION is measured from 0
  and an END from the clip's own start and the two are not the same number;
  `latest_end_on_grid` and `earliest_start_on_grid` are the timeline
  POSITIONS `trim_end` / `roll` and `trim_start` / `roll` /
  `head_handle_frames` clamp to (positions, so not a `SourceBound`);
  `duration_resnapped` is what every RE-SNAP of a media duration writes
  (`resnap`, `paste` twice, `unnest`, `relink_media`'s hold to a shorter file)
  and `duration_at_speed` what
  `set_speed` writes. No local clamp anywhere else. A measurement is a
  `SourceBound` and not an `Option`,
  because `None` meant "unbounded, apply no clamp" to a trim and "no handle
  at all" to a transition: the three arms are `Unbounded` (a source with no
  window), `Unmeasured` (a media window that exists and cannot be measured)
  and `Timeline`, and a caller picks what `Unmeasured` means to it BY NAME,
  `or_unbounded` or `or_empty`. `in_advanced` / `source_advanced` is the one
  `round(Δ × speed)` mover the six placement sites used to write out. Cut
  out of `model_query.rs` by road map 7 §10's phase A.
- `time.rs` — `Ticks`, `TIMESCALE`, `Fps`, frame snapping, timecode
  format/parse (non-drop `HH:MM:SS:FF` and `HH:MM:SS.mmm`). Snapping keeps
  frame indices wide through directional adjustment and saturates only at the
  public tick/index result. `frames_in` (whole grid frames in a length),
  `frames_back` (the grid position k frames before the frame nearest a
  position) and `frames_within` (the most whole frames back from a position
  that stay within a span), `frames_between` (the whole grid frames between
  two positions) and `one_frame` (the grid's own first frame, which
  `Project::frame` is at every rate, 1/30 s only at a degenerate rate; spec
  §11 #174) count on the canvas's own grid at a rate the
  timescale does not divide (spec §11 #42).
- `time_bounds.rs` — the single structural-time admission checker and
  `MAX_STORED_TICKS`: ±9,000,000,000,000,000 for stored media, markers,
  clips, source positions and actions, including clip/action endpoints in
  i128. `Project::validate` and `format::write` both call it; vocabulary
  property timings and finite positive speeds are outside this envelope.
- `outcome.rs` — `Outcome`, the THREE arms every edit answers with
  (spec §5.5): applied with the new project, an identity, or refused with
  the rule's own sentence. An enum and its doc, nothing else. It is an enum
  rather than a side channel so that a site which has not decided which
  answer it gives does not compile; the fourth possibility, a request that
  could not be read, stays the `Err(String)` beside it. Its `Identity` doc
  is also the one place that says which non-edits speak and which stay
  identities on purpose (spec §5.5, §11 #88).
- `edit.rs` — the op enum, `parse` and `apply`. **Its module doc IS the op
  table's SEMANTICS half** — what each op means, and what an absent
  optional argument means — where `op_table.rs` is the ARGUMENTS half;
  `app/Sources/ReelOps.swift`'s typed builders, `AgentCatalog*.swift`'s
  tools and spec §6 mirror the two together. `OP_NAMES` is re-exported from
  here, at the path it has always had. `parse` answers an `Envelope` — the
  op AND the envelope's `scope` — and `apply_op(&Op)` knows nothing about
  nests. The semantics table is the reason this file is over the size cap
  and stays exempt (below).
- `op_table.rs` — the op table as DATA (road map 7's D3): one `OpRow` per
  op and one `Argument` per argument — its name, its `Kind`, whether the
  decoder requires it and, for the few that have one, its `Bound` — and
  `OP_NAMES` as a projection of it, re-exported by
  `edit.rs` so no caller moved. A published interface, where the `Op` enum
  and the dispatch are its implementation. Its one reader in the crate is
  `op_schema.rs`, which carries the rows out through the FFI; the APP's
  reader is every one of the fifty-nine op tools in the agent catalog,
  which print these rows instead of restating them. **A `Bound` is
  published only where the core REFUSES outside it** — `set_canvas`'s two
  dimensions, sourced from `edit_canvas.rs`'s own constants, and
  `add_graphic_clip`'s `width` and `height`, from `model_graphic.rs`'s, never
  retyped — and never where it CLAMPS, which is the app's to say in its
  prose. A row holds no prose, no semantics and no default spelled twice;
  `Kind` is closed (eighteen kinds; `Texts`, a list of strings, is
  `set_action_end`'s `off`), carries each vocabulary's members, and has exactly ONE
  kind per answer serde gives, because a distinction the
  decoder cannot see is one no test could prove. Nothing here is the
  authority — the enum's fields are, and `core/tests/op_table.rs` proves
  every row by asking the decoder. Capped at 400 lines like any new module:
  it does NOT inherit `edit.rs`'s table exemption.
- `op_schema.rs` — `op_table.rs` written as JSON Schema, which is what
  `rc_op_schemas` publishes (road map 7's D3·2): one object per op, its
  properties the arguments and its `required` the ones the decoder will not
  do without. **The match over `Kind` is exhaustive** — a kind added to the
  table does not compile until this says what JSON it is — and it is a
  module of its own because a row changes when an OP does and this changes
  when the published DIALECT does. It says nothing about what an argument is
  FOR (the catalog's prose), nothing about what a patch may CARRY
  (`Kind::Object` is an object with no properties; D1 left the core the one
  validator of that), and nothing about `additionalProperties` on an op,
  because the catalog merges `project` and `scope` in afterwards. Tested
  through the FFI in `core/tests/op_schemas.rs`.
- `scope.rs` — editing INSIDE a nest: the envelope's `scope` key. Builds a
  VIEW project from the nest (its tracks and clips at top level, its frozen
  size as the canvas, the parent's rate, media, `next_id` and nests, no
  markers), applies the op to it UNCHANGED, merges back. So `Project::clip`
  keeps its one meaning and no op has a nest-aware branch. Three things are
  counter-intuitive and measured: the scoped nest's own row stays in the view
  with its tracks and clips EMPTIED (removing it dangles every other nest's
  reference; leaving it whole doubles every id under `validate`); the nests
  write-back is union first, orphans after; and **a scoped apply has a wider
  `Err` arm than any unscoped op** — `check_caps` and `check_nesting` are
  document-wide and run on the MERGED parent, so an op valid inside the nest
  can still return `Err`. `refused_inside` is an EXHAUSTIVE match over every
  op, so a new op does not compile until it is classified. The READ half is
  `rc_project_scoped` in `ffi.rs`, which calls the same `scoped_view`.
- `edit_graphic.rs` — `add_graphic_clip` and `set_graphic`: every argument
  checked through `model_graphic.rs` BEFORE `edit_clip.rs`'s
  `add_described_clip` (`pub(crate)`, with `Described`) places the clip, so
  the op table's bound probe reaches the side check on any project;
  `set_graphic`'s patch reader takes `name`, `width`, `height`, `length`,
  `props` and refuses `in` by name. With a `schema`, a `null` for a prop
  an action on the clip names stores the schema's default (G-34 (d)).
- `edit_clip.rs` — clip construction and placement callers: `add_clip`, move,
  duplicate, delete, join, detach, `fit_scale` and `fill_scale` (Fit is a RESCUE for oversized
  footage and honours `canvas.fit_new_clips`; Fill is a REQUIREMENT, ignores
  it, scales up as readily as down and clamps to `SCALE_MAX`). `whole_media_length`,
  `edit_clip_timing.rs`'s `trim_end` and `set_speed` hold a media clip's window INSIDE its file, each
  through `source_window.rs`'s one bound, so
  `in + duration × speed ≤ media.duration` and the plan's segment rate is
  exactly the clip's speed (spec §11, #22 and D4-2 to D4-5); the other
  writers are `edit_canvas.rs`'s `resnap`, `edit_paste.rs`'s two loops,
  `edit_nest.rs`'s `unnest` and `edit_background.rs`'s timed plate. Over
  the cap, known debt (below).
- `edit_clip_timing.rs` — `trim_start`, `trim_end`, `rate_stretch`, `set_speed`,
  their speed bounds and clip-relative action rescaling; `AUDIO_SPEED_MAX`
  (×12, spec §11 #190) and `speed_limits`, which `rc_speed_limits` publishes;
  `set_speed` takes a `rate` or a `duration` (Fit to duration), exactly one.
  `trim_start` advances a graphic's `in` through `graphic_advanced` (no speed,
  no head bound, saturating at 0); `trim_end` leaves `length` alone.
- `edit_commit.rs` — the placement commit protocol: replacements preserve
  caller order and check old tracks before destination tracks; additions
  check caller-allocated candidates against the input project; both write
  one draft and call `finish_placement`, which mints gained transitions on
  exactly the chosen tracks before `finish`. `finish` remains equality first,
  validation second, and does not itself refuse.
- `edit_split.rs` — `split_clip` and what the SECOND clip inherits: base
  props from the evaluation at the cut, unfinished actions rebased, a
  straddled one narrowed, presets and motion halves anchored to the two
  ends. Every splitter in the crate routes here, so a rule stated once is a
  rule they all obey. A free function over `&mut Project` because it is
  called mid-edit on a clone the caller is still assembling.
  A graphic's second half gets `in + cut` through `recipe_graphic.rs`'s
  `graphic_advanced`, and BOTH halves' `length` are pinned to the ORIGINAL's
  `effective_length` (G-9), so every splitter obeys it, and its `props` the
  evaluated ones, a straddled action's first half ending at them (G-34).
- `edit_props.rs` — the five patches (`set_video`, `set_audio`, `set_text`,
  `set_shape`, `set_clip`), `Project::check_group` (the range check
  `paste_attributes` runs on each group it has just replaced and `paste` on
  every group of every clip it lands — the same `check_video` /
  `check_audio` / `check_text` / `check_shape` the patch path calls
  directly; its only caller is `normalise_and_check_group`) and
  `normalise_and_check_group` beside it (the one NORMALISATION a copied
  group needs first: a clipboard payload is a third door for a `Motion`, and
  an empty one has two spellings; only the file reader does not normalise;
  the copied group is checked before its present video/text timing is
  snapped), and `normalise_and_check_pasted`, which runs it over every group
  of every clip `paste` lands — nested ones in a second pass, once every
  copy is in — naming the PAYLOAD's clip id (`pasted clip N: …`, issue #62),
  `check_blend`, the one check about a CLIP rather than a value (a nest clip
  cannot blend), and `snap_motion` / `snap_animation`, which put the ticks a
  patch or checked copied group carries on the frame grid AFTER the range
  check, so a refusal names what the caller sent. What a patch may CARRY is
  `patch.rs`'s and nothing here restates it.
- `patch.rs` — reading a caller-authored patch, cut out of `edit_props.rs`
  under the size rule: `Group` — the four PATCH groups; `paste_attributes` takes these four and
  `graphic` as `edit_paste_attributes.rs`'s `PasteGroup`, and a patch has no
  fifth group — and its per-group template, `check_keys` (the
  walk of keys and JSON kinds, array indices in the path) and `merge_group`
  (the one read of a group patch — the walk, the deep merge and the
  path-tracking deserialise — the new text and shape clips' patches
  included), so every refusal names the path, indices included, and the
  value. `check_group_patch` is the same walk and read for a group that is
  NOT being merged into a stored one (an action's end state), and
  `unknown_key` is that refusal's one spelling. A patch merges key by key at
  every depth, an array replaces its list, and `null` clears an optional key
  (a required one refuses it). `COMPLETE_ENTRIES` is the one exception to
  "absent keeps": a `video.filters` entry must name both its keys, because a
  list replaces whole and the type's defaults would invent a filter. Nothing
  here is handed a clip or a project: what a patch may carry is a fact about
  the vocabulary, which is `props_check.rs`'s reason for existing one step
  further on. `GROUPS` — every group in its order on `Clip`, the order
  `paste` and a default `paste_attributes` visit them — lives here, its one
  home.
- `props_check.rs` — the range checks every value written into a property
  group passes first (`check_video` / `check_audio` / `check_text` /
  `check_shape`, the `finite` / `in_range` family, the bounds `actions_clamp.rs`'s `clamp_video` reads too). A range check is a fact about the vocabulary,
  not about an edit — and it runs BEFORE `edit_props.rs` snaps a patch's
  ticks, which is what lets a refusal name the number the caller sent rather
  than the one a snap rounded it to. Gradient stops are deliberately NOT
  order-checked: a refusal would break dragging one stop past another
  mid-gesture, so the renderer sorts, and the comment says so where the
  check would have gone. A list entry's key names its index —
  `video.filters[0].amount`, `video.obscure[1].x`,
  `shape.gradient.stops[0].color` — so a refusal names the entry as well as
  the field (issue #89).
- `edit_track.rs` — tracks, markers and the media list: the three lists a
  clip sits in. The canvas left here at road map 7's D2·3 toll. `clip_list`
  is the ONE spelling of the clips a `with_clips` refusal names — three ids
  and then a count, so a media used by two hundred clips still answers a
  sentence a caller can read — shared by `remove_track` and `remove_media`. It
  keeps `MEDIA_KEYS` and `check_media_fields` (the post-schema checks a media
  record passes, in one order and one set of sentences), which
  `edit_relink.rs` reads for a relink's probe; `relink_media` itself moved to
  `edit_relink.rs`.
- `edit_relink.rs` — `relink_media` (spec §11 #63): points a media at another
  file and, given the new file's `probe` (the host's `MediaImporter.probe`
  descriptor minus `path` and `bookmark`), takes its duration, size, rate and
  flags, refuses a file of another kind in its own sentence, and holds every
  `media`-source clip of it, on the timeline and in every stored nest, whose
  duration runs past the new file's window to `source_window.rs`'s
  `duration_resnapped`. A probe's `original` replaces the stored one (none
  clears it). No probe keeps the record (Consolidate, the open-time
  re-anchor).
- `edit_canvas.rs` — the document's own shape: `set_canvas` and the three
  things it does to the rest of the document — `check_dimension` (a
  dimension is even, because H.264 encodes in macroblocks), `rescale` (a
  size change moves every clip's `x`, `y` and `scale`, each axis by its own
  ratio and `scale` by the smaller of the two) and `resnap` (a rate change
  normalizes top-level and each stored nest's clip times through `frame_grid.rs`
  and drops the second of two top-level markers a coarser grid lands on one tick).
- `edit_time.rs` — ripple, insert time, `ripple_delete_ranges` (the pairs are
  ordered, MERGED — touching as well as overlapping — then cut and closed
  right to left as ONE edit; the singular delegates to it), `lift_range`
  (the hole left open), `close_gap` (refuses rather than closing part way, and
  refuses naming what is there when `at` is on a clip or nothing follows it,
  spec §11 #88),
  freeze frame, `shift_clips`, and `locked_track` — THE locked-track
  refusal's sentence, written once here for its three callers
  (`close_gap`, `edit_insert.rs`'s `insert_clip`, `edit_transition.rs`'s
  rippled form), each passing the clause after the comma.
- `edit_edge.rs` · `edit_insert.rs` — the cutting moves that keep something
  fixed on purpose: `slip` and `roll` (a `still` slips the frame it holds;
  any other non-media source is an `Err`; roll's predecessor must end
  EXACTLY at the clip's start); `insert_clip` and `overwrite_clip`,
  compositions of split + insert time + add made ONE op so a drop is one
  undo step and carries the rule neither half states — an insert cuts only
  the destination track and then shifts every unlocked one.
  `roll` is a front trim on its clip, so it advances `graphic.in` as
  `trim_start` does; the predecessor's end is an end trim and keeps `length`.
- `edit_transition.rs` — the WRITE half of a transition: `set_transition`,
  `set_transition_duration`, `set_gained_transitions` (a clip that gains an
  overlap gains a transition), `add_transition` (an overlap built from the
  two clips' handles at a hard cut) and `set_transition_style` (curve and
  audio crossfade). `transition.rs` is the READ half and nothing here restates
  it. `transition_too_short`, THE too-short sentence both forms of
  `add_transition` share (spec §11 #88); `set_transition_duration` refuses on
  a track's first clip and past the pair's snapped overlap limit, naming it
  (#88, #175).
- `edit_transition_shift.rs` — `add_transition_by_shift`, the `ripple` half
  of `add_transition`: the same overlap made by sliding the incoming clip
  and everything at or after the cut left through `shift_clips`. Cut out of
  `edit_transition.rs` under the size rule (the E1 reader review's toll T),
  a pure move: the handle form spends unused SOURCE and moves nothing,
  this one spends the TIMELINE and moves `close_gap`'s set by `close_gap`'s
  rules. The request is counted in whole frames of the real grid
  (`time::frames_in`) and the incoming clip lands on it (`time::frames_back`);
  a request under one grid frame refuses in `transition_too_short`'s words,
  right after the lock check.
- `edit_action.rs` · `edit_nest.rs` · `edit_paste.rs` — the action ops and
  their no-overlap rule, plus `check_end_patch`, the END patch's door: the
  three groups §5.4 allows (a `shape` is an unknown key), a `null` that
  REMOVES at every depth rather than clearing, and `patch.rs`'s walk and
  read per group. The door is composed here because which groups an end
  patch names, and what a `null` in one means, are facts about an ACTION;
  values are deliberately not range-checked, except a graphic prop's end
  (G-34 (c), `edit_action_graphic.rs`), and `actions_clamp.rs`'s
  `clamp_video` is the last line of defence for them. `set_action_end`'s
  `off` (spec §11 CI-14) is the one way to STORE a `null` — the optional
  property keyed OFF at the end — written after the merge and the prune;
  `check_off` refuses what `patch` refuses (`not_a_target`'s two sentences,
  and `merge_group`'s read of a `null` for an unknown or a required key),
  and a non-object group slot is replaced by `{}`, never indexed. `nest` and `unnest`
  (fresh ids, content byte-equal);
  `paste`, whose payload schema is its module doc; `Payload` and
  `parse_payload` are `pub(crate)`, because `edit_paste_attributes.rs` reads
  the same payload.
  `graphic` in a `patch` is `edit_action_graphic.rs`'s arm, read against
  the op's `schema` after the three groups' walk (G-34); in an `off` path it
  is an `Err`.
- `edit_action_graphic.rs` — `set_action_end`'s graphic arm (G-34):
  `read_graphic_end` checks the patch's `graphic.props` (never the stored
  end's) against the op's `schema` through `check_typed` under
  `graphic.props.<key>`, discards a `kinds`, refuses an asset, an
  undeclared prop, a layer key and a missing schema by name, and answers
  each prop's kind and the default for each the clip lacks
  (`schema_default`); `write_graphic_end` stores `props` and `kinds` by
  `insert` / `shift_remove`.
- `edit_paste_attributes.rs` — `paste_attributes`, cut out of `edit_paste.rs`
  under the size rule as a pure move ahead of spec §11 G-32: the payload's
  EARLIEST clip's property groups (then the front-most, then the lower id —
  never the array's first) copied onto each target, replaced whole and never
  merged. `PasteGroup` is the five names it takes — the four patch groups and
  `graphic`, which is never in the default set: a graphic's `props` copied
  whole onto clips drawn by the SAME module, the target keeping its name,
  size, `in` and `length`, written with `insert` and `shift_remove`
  (`model_graphic.rs`'s rule). A target key the payload lacks that an
  action on the target names (`names_prop`) is kept (G-34 (d), amending
  G-32 (e)). `skip_missing` drops a named group the payload
  clip lacks and skips a target that cannot take one. **The copied props are
  shape-checked once, the first time a target takes them**: a paste nothing
  takes never reads the map. `patch::Group` gains no variant for it.
- `edit_zoom.rs` — `add_zoom_action`, the screencast zoom, and `ZoomRegion`,
  the one op ARGUMENT that is a caller-authored object: its `Deserialize` is
  written out rather than derived so it answers as a patch does — an object
  required (a list is not read member by member), an unknown or missing
  member named, a wrong-typed one named by its path. **Its module doc
  IS the placement equation** between the region frame and canvas pixels,
  rotation and crop included; it composes `add_action` + `set_action` +
  `set_action_end` so a drag is one undo step and every refusal is inherited.
- `edit_background.rs` — `add_background` and `add_blurred_background`: one
  clip on a NEW back-most track, OPS rather than app-side composites because
  the composite carries constraints no half states. A blurred copy drops
  `enabled.audio`, `audio.duck`, the transition, the actions and the label
  (each a wrong picture or a wrong sound if carried) and refuses a nest.
  Default plate colour is white: the canvas is already black.
- `actions.rs` — action evaluation and interpolation, and `clip_state`;
  its last line of defence is `actions_clamp.rs`'s, and a graphic's props
  are `actions_graphic.rs`'s (spec §11 G-34), carried in `Evaluated.graphic`
  and `clip_state`'s `graphic`. **The LIST rule is stated here once as the
  crate's**: an end patch interpolates a list per index when the lengths
  match and each pair of entries agrees on its discrete fields (`kind`,
  `shape`), and switches at the end otherwise; `video.filters` and `video.obscure` are both governed by it and carry no code of their own.
- `actions_clamp.rs` — `clamp_video` and `clamp_audio`, the evaluator's
  last line of defence (`set_action_end` checks a `video`, `audio` or
  `text` end patch's keys and kinds but deliberately not its VALUES, and
  never looks at the clip for them; this bounds every value such a patch
  can carry and forces `normal` on a nest clip), with `bounded` /
  `finite_or`; a pure move out of `actions.rs` (issue batch B87, toll A).
- `actions_graphic.rs` — a graphic clip's props at a clip time (format
  version 13, spec §11 G-34): finished actions' `end.graphic.props` laid
  over the clip's map by `insert`, the spanning one interpolated — a number
  in floating point, never rounded; a `color` (by `end.graphic.kinds`,
  never by shape) four channels straight through `model_color.rs`'s
  `color_channels` / `color_hex`; anything else, a malformed end, or a prop
  with no start, held and switched at the end. Total. `names_prop` is
  `set_graphic`'s and `paste_attributes`' question.
- `transition.rs` — overlap detection, THE overlap rule (spec §11), eased
  progress at *t*. An overlap with no kind still dissolves
  (`unwrap_or_default`), and `add_clip` onto an overlap mints a
  `cross_dissolve`, so a no-transition baseline is built by moving clips
  apart, not by clearing the kind.
- `transition_search.rs` — the bounded fitting arithmetic for both hard-cut
  transition forms: the old handle decrement path by total, and exact
  forbidden shift intervals across fixed/moved clips for ripple, counted in
  whole grid frames back from the cut (`time::frames_within`). It does
  not enumerate timeline frames; final placements still pass
  `check_overlap_rule`.
- `evaluate.rs` — `composition_plan()` (A/B assignment, instruction tiling)
  and the `assign()` the recipe shares with it. `assign` leaves a clip's audio
  out above `AUDIO_SPEED_MAX`, and `place` gives every plan audio track ONE
  `pitch` (#190, #211).
- `recipe.rs` · `recipe_text.rs` — `frame_recipe(t)`: the layer list at one
  instant. `RecipeLayer` is the twenty keys of a layer written in ONE place
  (`RecipeLayer.init(from:)` on the Swift side defaults a missing key
  silently, so a copied skeleton drifts with no diagnostic). `RecipeOptions`
  is what a caller wanted besides `t` — the burn-in timecode — and is a
  recipe option, never an export override, because the override table drops
  an unknown key in silence. A layer whose `transition` is non-null is
  emitted `blend: "normal"` whatever the clip says: the core's ONE deliberate
  override of a model value, because the dissolve's weight correction is the
  inverse of a fixed-function destination factor. The inspector therefore
  shows the model's value while the frame draws `normal` during an overlap.
  `recipe_text.rs` computes what a text layer SHOWS — `Reveal::of` turns
  `text.animation` into `reveal`, `reveal_phase` (the ORDER the renderer draws
  in, not a label on the amount) and `reveal_kind`, folded into the content
  hash so an animating layer is never served a stale texture — and
  `burn_in_layer`. `serde_json`'s `Map` keeps INSERTION order in this
  build (`graphic` enables `preserve_order` and cargo unifies it), so
  `content_hash` sorts every object's keys before it hashes — the order
  every texture key was taken in — and nothing may lean on the wire order
  of a map.
  A graphic layer's source is one arm calling `recipe_graphic.rs`'s
  `graphic_source`; `missing_source` is `pub(crate)` for it.
- `recipe_words.rs` — what a timed text PAGE shows at one instant:
  `Words::of(text, clip_t, duration)` answers five keys — `word` (how many
  of `text.words` have started, 0 to n), `word_pop` (0..1 through the active
  word's pop over `WORD_POP`, 0.12 s; null at `active_scale` 1.0), and,
  since format version 12 (spec §11 W-13), `word_glide` (0..1 from the
  active word's start over `WORD_GLIDE`, 0.2 s, or the time to the next
  word when sooner; null unless `active_pill.glide` and a second word has
  started — the pill comes from token `word − 2`, no second index is
  carried), `word_fill` (0..1 to the active word's `end`, at most
  `WORD_FILL_MAX`, 0.6 s, holding 1.0 after; null unless `active_fill` and a
  word has started) and `word_dim` (0 inside a word and in a pause under
  `WORD_DIM_GAP`, 0.25 s; else `WORD_DIM`, 0.1 s, ramps either side of the
  pause, none on a side with no word — the tail runs to `duration`; null
  unless `pause_dim > 0`) — all null unless the text has a `word_style`,
  non-empty `words` and a matching token count. Total and order-blind — a
  count, `get`, saturating subtractions and `recipe_text.rs`'s `ramp`
  (`pub(crate)` for this) for every division — because the file reader
  stores `words` unchecked. `insert_into` writes the five keys in order;
  `recipe_text.rs` calls it for every text layer's `source` and, only for a
  styled page, for the hash, gives a styled page a WHOLE reveal (W-5), and
  strips `words` from the description (and `word_style` when unset, `case`
  when `as_written`, so an unstyled title hashes as before version 9).
- `recipe_graphic.rs` — a graphic clip's own timeline (road map 10's G-9)
  and its layer: `effective_length` (`graphic.length`, or `in + duration`
  when null — G-9·c), `graphic_advanced` (`in` moved through
  `source_window.rs`'s `in_advanced` at speed 1, never below 0),
  `graphic_resnapped` (what every re-snap through `frame_grid.rs` writes:
  `in` to the nearest frame, ≥ 0; a set `length` to the nearest frame with a
  one-frame floor; null stays null — G-18), and `graphic_source`, the
  layer's `{kind, name, hash, frame, ctx, props}` and `[width, height]` —
  `frame` floored onto the canvas grid, `durationInFrames` ceiled, `ctx`
  exactly the engine's keys (the app passes it through verbatim),
  `ctx.canvas` the PROJECT's size inside a nest too, `props` the map evaluated at the clip time (`Evaluated.graphic`, G-34), the hash over everything `render` is called with (G-9·b). It
  holds ONE equation for the writers and the reader together: `trim_start`,
  `roll`, `split`'s second half and `add_transition`'s handle form call
  `graphic_advanced`, every `frame_grid.rs` re-snap calls
  `graphic_resnapped`, `split` pins both halves' `length` to
  `effective_length`, and the recipe reads the same `effective_length`.
  **`Clip.graphic`'s `in` and `length` are written nowhere else**
  (`set_graphic` refuses `in`). Never write the bare token `graphic::` here
  (`graphic_ffi.rs` greps `core/src/`).
- `motion.rs` — `video.motion` turned into PLACEMENT: presets to `scale`,
  `rotation`, `opacity`, `x`, `y` from the clip time, its duration, the
  source size and the container's canvas. **Its only callers are
  `recipe.rs`'s `layer` and `frame_of`**: every edit path — `evaluate_clip`,
  `clip_state`, `get_project`, splitting, zooming, freezing, the audio plan
  — reads the clip un-moved. It never trusts the file (a non-positive
  duration or period is inactive, amounts clamp) and short-circuits to
  `video.clone()` when no slot runs, because `x + b − b` is not `x` in
  floats.
- `nest.rs` — flattening a nest into the clips it stands for and the
  transform they inherit; `evaluate.rs`, `recipe.rs` and `audio.rs` all
  consume its instances rather than `Project::clips`; `lifted`, the clip as
  the plan sees it, lives here too.
- `audio.rs` · `audio_duck.rs` · `audio_crossfade.rs` — envelopes: fades,
  volume actions, mute and solo (both ZERO envelopes; solo is judged per
  container in `Voice::of` — muted, or some track in the set soloed and this
  one not; mute wins — so the plan's segments never see it); ducking, the
  one term imposed by a clip on ANOTHER track; and the constant-power
  crossfade with the breakpoints it must be sampled at to survive coalescing.
- `snap.rs` — candidates and `resolve`.
- `format.rs` — `RC_FORMAT_VERSION`, the `MAX_*` caps (four of them
  `RC_MAX_*` in the header), read-any-version / write-current, the migration
  hook.
- `export.rs` · `export_overrides.rs` · `export_size.rs` · `export_table.rs`
  — settings resolution (`Project::export_settings`, the one thing that reads
  a canvas, a duration, a rate and an override against a preset row); how an
  override is READ and REFUSED, naming the key and the value (`peak_dbtp`
  without `loudness_lufs` is an `Err`, because a ceiling with nothing to cap
  would be a key accepted and silently inert); the sizes the sheet offers and
  `fit_within`, and `even_size` — on every row AVFoundation writes but
  `prores_4444` an odd edge resolves one pixel smaller, in the list's
  Document row (named "Document (even)") and in the resolved settings alike,
  so the size reported is the size written (G-33); and the rows themselves. In a row, `avf_preset: null` routes
  an export to the ImageIO writer (so the two LPCM rows repeat `audio_m4a`'s
  name), and `alpha` means "this ENCODING carries an alpha channel" — true for
  `prores_4444`, `hevc_alpha` and `apng`, false for `gif`, which has one palette index and
  no partial value — never "the canvas is translucent".
- `agent.rs` — embedded MCP server (streamable HTTP, tools only).
  **Generic** — knows nothing about video; the host registers the catalog
  and a callback. Copied from Rasterize; do not add domain knowledge. Since
  road map 14 it differs from Rasterize's (a Unix socket only here; TCP with
  `admit` there), and kpgalligan/rasterize#430 offers the change. One
  listener, `start_socket` (a Unix socket at an absolute path of at most
  `MAX_SOCKET_PATH_BYTES`, 103, chmod 0600, never unlinking a file already
  there), into the `serve` loop; road map 14's MC4 deleted the TCP `start`.
  **`tiny_http` 0.12's `Server` drop unlinks its path unconditionally (MC1's
  S7)**, so a socket listener records its file's
  device and inode as a `SocketClaim`: `shutdown` lets the drop run only
  while the claim `is_current`, and forgets the server otherwise; `release`
  (the quit path) unlinks only a current file and then forgets the whole
  listener — no unblock, no join — so a call in flight cannot hold a quit.
  The protocol revisions it negotiates are `mcp_versions.rs`'s, not its own.
- `mcp_versions.rs` — the MCP protocol revisions (`SUPPORTED_VERSIONS`,
  `LATEST_VERSION`) and `negotiate` (the requested one when supported, else
  the newest), moved out of `agent.rs` by road map 14's MC3 so ONE list
  serves two readers: `agent.rs`'s `initialize` and `mcp-proxy/`, which
  includes this file by `#[path]`. It therefore uses `std` alone and names
  nothing of this crate (no `use crate::…`).
- `ffi.rs` / `ffi_edit.rs` / `ffi_query.rs` / `ffi_agent.rs` — thin shims
  only; shared plumbing lives in `ffi_util.rs`, never copy-pasted.
  `ffi_query.rs`'s rule: a query never allocates a handle and has no
  `err_out`, which is why `rc_project_scoped` lives in `ffi.rs`.
  `rc_speed_limits` is its answer for the speed range and the audio ceiling;
  `rc_normalise_color` (`ffi.rs`) is the colour grammar's (G-25).
  `ffi_agent.rs` has one slot, one listener per process: `SOCKET`
  (`rc_agent_socket_start` / `_release`; MC4 deleted the TCP pair and its
  slot), whose `AgentConfig` is built by `host_config`, one catalog
  through one handler.
- `container.rs` · `container_header.rs` · `container_blocks.rs` ·
  `container_codec.rs` · `container_timing.rs` · `container_vorbis.rs` ·
  `container_vorbis_setup.rs` · `ffi_container.rs` — a WebM
  or Matroska file being imported, read as an INDEX (spec §11 #216-R),
  read-only, bounds-checked, no input may panic: `container_header.rs` the
  EBML reading and the header before the first Cluster (a CodecPrivate over
  1 MiB refused by name); `container_blocks.rs` the Cluster walk
  (unknown-size Clusters end at the next level-1 element, three lacings,
  payloads skipped, a truncated tail ends the index); `container_codec.rs`
  codec ID → fourcc, the synthesised `vpcC`, the AAC ES_Descriptor, Opus TOC
  counts; `container_timing.rs` raw and grid-snapped video times, decode
  times by the largest reorder, audio in samples less CodecDelay,
  laced-frame times, `required_bytes`, and Vorbis's lead (the first packet's
  count); `container_vorbis.rs` the three Vorbis headers walked to the mode
  table, each packet's count by the overlap rule (spec §11 #228-V), with
  `container_vorbis_setup.rs` the setup header's walk (codebooks, floors,
  residues, mappings, modes); `container.rs` the first video and
  audio track and `describe`/`retime`/`sample_count`/`sample`;
  `ffi_container.rs` the six `rc_container_*` exports. The only payload read
  is the first VP9 keyframe's header, each Opus packet's TOC and each Vorbis
  packet's first byte.
- `ffi_graphic.rs` — the ten `rc_graphic_*` exports (road map 10 §5e)
  and the ONLY module of `core/src/` that names the `graphic` crate (spec
  §11 G-2; `core/tests/graphic_ffi.rs` reads `core/src/` to hold it). An
  `RcGraphicLibrary` is a BUILDER that the first compile or rasterize
  FREEZES into one `Arc<graphic::Library>` (the crate's `Library` is
  immutable — its `version` hashes every byte); an add after that is
  refused. `RcGraphic` wraps `graphic::Module`, whose `Arc` keeps the
  fonts alive past the library's free. `diag_out` is a JSON array of
  Diagnostics, exactly one error on failure; its panic arm goes through
  `ffi_util.rs`'s `fallible_op_wrapped`. `rc_graphic_library_families`
  answers the frozen library's family names as JSON — the engine's own,
  which a `font-family` must match (CoreText names 13 of 2500 host fonts
  differently) — and freezes it. `rc_graphic_describe` answers `{meta,
  schema, revision, warnings}`, `warnings` being `Module::warnings()`
  through `Diagnostic::to_json` (spec §11 G-24 (a)). At 399 of 400: the
  next export pays a toll,
  and nothing crate-free is left in it (`diag_json`/`diag_error` name
  `Diagnostic`). `ffi_util.rs` holds the two crate-free helpers it gave up:
  `read_bytes` (a pointer and a length into an owned `Vec`, `bytes is NULL`
  refused) and `free_boxed` (drops a handle `boxed` made, under
  `fallible_op` with no channel; NULL a no-op).

## Rules

**Modules and size.** New feature area = new module with its own
`impl Project` block. Soft cap ~600 lines; needing a new `// ---- name --`
banner section is the signal to split. Every module keeps a `//!` doc;
numeric and algorithmic choices get prose "why" comments. **A file at the cap
gives something up BEFORE it takes anything on**: the cut is a PURE MOVE,
landed and gated alone, so the feature's diff is attributable; budget the cut
against the pessimistic number, because an estimate here has run about two
thirds of the truth. Over the cap today and known debt, not licence:
`edit_clip.rs` and `edit.rs`, whose
standing exemption is that its module doc IS the op table's semantics half
(the cut there, if ever forced, is the `Op` enum into an `edit_ops.rs`, and
never in the same phase as a feature). The current list is `wc -l`; named
seams are in `designs/adr/core-file-history.md` "Named next cuts".

**Dependencies.** `serde` and `serde_json` (the JSON the FFI speaks),
`tiny_http` (the agent's socket), and `serde_path_to_error`, which is there
so a patch refusal names the path to what only the type can refuse (a
misspelt variant, a `null` a required field cannot take), where serde alone
names only the value. `graphic` (the path crate `../graphic`, road map
10's motion-graphics engine), named by `ffi_graphic.rs` alone. It enables
`serde_json`'s `preserve_order`, and a feature is unified across a path
dependency, so the core's `serde_json` has it too; `Cargo.toml` spells it
out. `svgtypes` 0.16.1 (usvg's own pin, already in the lock) for its
named-colour table only, so a stored name agrees with what usvg draws
(`model_color.rs`). Dev: `sha2`, `graphic_ffi.rs`'s revision oracle.

**One implementation per algorithm.** Before writing time math, find the
existing implementation and route through it. Shared constants have exactly
one home (`TIMESCALE` in `time.rs`; `RC_*` caps in `format.rs`; the
inspector's bounds in `props_check.rs`).

**Purity.** Every edit takes `&self` and returns a new value — internally
clone-then-mutate. An op that would change nothing returns
`Outcome::Identity`, never an identical copy: an identical copy registers a
phantom undo step in the app.

**Errors.** Every edit answers `Result<Outcome, String>` — three arms and
one tier, no error enum. `Outcome::Applied` = the new project;
`Outcome::Identity` = the op is valid and nothing needed to change;
`Outcome::Refused(String)` = a rule declined it, carrying the rule's OWN
sentence rather than a second one written at the call site; `Err(String)` =
invalid arguments, unknown ids, parse failures — lowercase messages naming
the offending value. A refusal is not an error tier: both middle arms leave
the project untouched and register no undo step. No input may panic. FFI
mapping (`ffi_edit.rs`): `Applied` → a new handle; `Identity` → NULL with
neither channel written; `Refused` → NULL with the sentence through
`reason_out`; `Err` → NULL with the message through `err_out`; caught panic
→ `"internal error: <what>"`. The two channels are never both written.

**Times.** Every tick value that reaches the model is snapped to the
document's frame grid before it is stored (`time::snap_to_frame`). Never
store a sub-frame time. Where a range check names the value, the check runs
on what the CALLER sent and the snap follows it, so a refusal never names a
number the door rounded to (`props_check.rs`, `edit_props.rs`'s
`snap_motion` / `snap_animation`). The one family that is deliberately NOT
on the grid is the audio ramps — `audio.fade_in` / `fade_out`, the duck's
and the compressor's attack and release — because they are envelope lengths
sampled at the audio rate, not positions in the picture, and quantising them
to a video frame would round a 10 ms attack to nothing. The other is a SHIFT
(spec §11 #42): an op that moves several clips — the ripples, `close_gap`,
`insert_time`, `move_clip` — moves them all by ONE delta so abutments stay
exact, and at a rate whose frame is not a whole number of ticks (7 fps) a
moved start may sit a tick off the grid; a canvas rate change re-snaps (D7-3).

**FFI exports.** Every export: `#[no_mangle] pub unsafe extern "C"`, a `///`
comment restating the header contract, a `/// # Safety` paragraph, NULL
tolerance first, narrow `unsafe {}` blocks. Route through the shared helpers
in `ffi_util.rs` — a freshly hand-rolled `catch_unwind` is a review flag.
Export names mirror the Rust method exactly.

**Format changes.** Any change to persisted project state bumps
`RC_FORMAT_VERSION` in `format.rs` **and** the `#define` in
`core/include/reelcut_core.h`; the reader must keep accepting every prior
version; the writer enforces the reader's caps. A bump whose new fields all
carry a serde default needs no migrate step (versions 3 through 13 have none)
but still bumps, because unknown keys are ignored at every level by design
and an older build would otherwise open the file, drop the new fields on read
and write the loss back on the next save; a bump that changes a field's
SHAPE adds a step at the migration hook (`migrate_1_to_2`). Each bump gets a
`schema_vN.rs` test that opens the previous versions' fixtures and reads the
new keys' ORDER off the written text, since a parsed `Value` sorts them.
**Nothing that checks the version writes the current number as a
literal**, so a bump edits `format.rs` and the header and no test or proof:
- The "one past the current version, refused" tests in
  `core/tests/schema_v3.rs` and `core/tests/model_tests.rs` compute
  `RC_FORMAT_VERSION + 1` and assert the refusal's whole message with
  both numbers.
- `schema_v3.rs`'s `the_header_states_the_same_format_version_as_the_core`
  holds the header's `#define` to `format.rs`'s constant, so a bump that
  moves only one of them fails `make test`.
- The schema tests' and `model_tests.rs`'s `/version` assertions read
  `RC_FORMAT_VERSION`; `schema_v10.rs`'s byte-for-byte round trips rewrite
  the fixture's version line through its `current()` helper.
- The proof scripts (`tools/proof/*_proof.py`) read the HEADER's number
  through a `format_version()` helper. `phase9`'s "one past" fixture is
  `format_version() + 1`, and its every-version loop runs up to the current
  version. A proof that expected a literal would fail weeks later, in
  someone else's session, with nothing pointing at the bump.

A fixture's own version (`e2_proof.py`'s `VERSION = 8`, a
`schema_vN.rs`'s older files) is a literal on purpose. One claim still
moves with the schema rather than the number: when a bump appends a key to
the video object, `schema_v4.rs`'s text assertion about what follows
`obscure` fails in `make test` and names the new neighbour.

**Tests.** All tests are black-box in `core/tests/` (no `#[cfg(test)]` in
`src/`), exercised **through the FFI** wherever possible, and verified
against independently written oracles — never golden files. Shared helpers
live in `tests/common/` (`content` / `contents` — "the same clips, ids
aside" — is the one spelling of that comparison, used by `nest`'s identity
claim and `scope`'s oracle alike); new feature area = new test file. Every
new export gets at least one test plus inclusion in the null-safety sweep.
Finish Rust work with `cargo fmt` and a clean `make lint`.
