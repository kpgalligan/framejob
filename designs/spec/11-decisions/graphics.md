# Spec §11 — decisions: Graphics (road map 10)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **G-1 — A graphic is a SOURCE, not an effect; R5-1 stands for effects**
  (road map 10 §4, 2026-09-25). §1 lists "a plugin system" as a non-goal,
  and R5-1 says effects are "closed vocabularies, never a runtime… no
  expression language". A graphic changes neither rule for what they
  govern: a transition, a motion preset, a filter and a blend stay closed
  vocabularies the one compositor draws, and a script cannot reach another
  clip's pixels, the timeline, the model or the editor. A graphic is a
  clip's CONTENT, in the same place a media file or an image sits — closer
  to "the user can import any PNG" than to a plugin. §1's non-goal gains one
  clause: "a clip may draw itself from a JavaScript module in its package
  (road map 10); nothing else is scriptable". The user asked for this
  reversal, as road map 3 reversed screen recording.
- **G-2 — The engine is a separate Rust crate; the core crate keeps its two
  rules** (road map 10 §4, 2026-09-25). QuickJS and resvg live in
  `graphic/`, a crate at the repo root. `reelcut-core` depends on it by
  path, and ONE file, `core/src/ffi_graphic.rs`, calls into it; no module of
  the model, the ops, the plan or the recipe imports it. `core/src/` keeps
  "no pixel work" and "no filesystem" exactly; the `graphic` crate does
  pixel work and still no filesystem — the app reads every byte and hands it
  over. §7's first sentence becomes: "All pixel and sample work happens on
  the platform, except a graphic's rasterization, which is the `graphic`
  crate's (G-2)." Not JavaScriptCore and a platform rasterizer, because
  `measureText` has to be the rasterizer's own measurement or wrapped text
  overflows by a pixel (macOS has no public SVG rasterizer), because QuickJS
  gives public memory and time limits where JavaScriptCore's execution time
  limit is SPI, and because one call in, pixels out is a smaller seam than
  JavaScriptCore in Swift plus resvg over FFI. The graph's licences (road
  map 10 §4) are MIT, Apache-2.0 OR MIT and BSD-3-Clause; no copyleft code,
  and no code from Remotion.
- **G-3 — A graphic's source is a FILE in the package, and is not an undo
  step** (road map 10 §4, 2026-09-25). The code lives at
  `graphics/<name>.js`, and `<name>` matches `^[a-z0-9][a-z0-9-]{0,62}$`, so
  it is safe on disk, in a URL and in a tool argument. The clip names its
  module (`graphic.name`), and many clips may share one module, as many
  clips share one media file. Editing the file is NOT an undo step and does
  not dirty the document, exactly as a change to a media file on disk is
  not; undo covers what the model holds — which module, the size, the
  timeline and the props. The reason is that a file is edited by things
  that are not the app (an agent's own Write tool, a person's editor), and
  an undo stack that owned the file would have to be rebuilt from whatever
  those tools did. The price is stated to the agent in the `write_graphic`
  reply: "not undoable; keep your own copy if you want the old one back". A
  revision history is road map 10 §7's. The package gains `graphics/`
  beside `cache/` and `media/`, and the `fileWrapper` whitelist gains its
  line (§5.6: a directory not named there is DELETED by the next save); an
  UNTITLED document keeps its `graphics/` under its temporary cache root,
  and the first save carries it into the package, as `cache/` is carried.
- **G-4 — The core checks props against the schema the OP carries; render
  time is lenient** (road map 10 §4, 2026-09-25). The schema is declared in
  the module (`export const schema`), and the core never reads the module,
  so `add_graphic_clip` and `set_graphic` take a `schema` argument (JSON,
  road map 10 §5c's shape). The app fills it from the module's current
  revision, and the tools declare it as the one argument an agent does not
  send (a Declarations row); an agent that sends one anyway is refused by
  the gate, since the tool never published it. With a schema, the core
  checks every key of a `props` patch by its dotted path (`props.accent`),
  with type, range and enum membership, in the core's words, and no handler
  predicts a refusal. A `null`, which removes its key, is not checked, so a
  stored key the schema no longer has can always be cleared. Without a
  schema (a file read, or a replayed op), the core checks shape only: at most 64 keys, each value a string of at most
  4096 characters, a finite number or a boolean. The 64 is counted on the
  map about to be STORED — after a `set_graphic` merge and its removals —
  since a one-key patch can push a full map over. At RENDER time props are
  lenient, because a file edit can change the schema after the props were
  set: `ctx`'s props are the schema's defaults overlaid with the stored
  values, a stored key the schema no longer has is passed through and a
  wrong type falls back to the default, both reported as WARNINGS in the
  graphic's diagnostics and never as errors. A clip whose module was edited
  keeps drawing, and the agent is told what no longer matches.
- **G-5 — A graphic is a pure function of its inputs (R5-5 for code)**
  (road map 10 §4, 2026-09-25). A frame is a function of its source text,
  props, frame number, size, font set and asset bytes only. Anything else is
  removed or made to throw: no wall clock (`Date` is frozen at
  2000-01-01T00:00:00Z and `Date.now()` returns its epoch); no randomness
  (`Math.random` throws "Math.random is not available; use random(seed)");
  no I/O (no `std` or `os` module, and `import` of anything is refused); no
  state between calls (the module is evaluated once per thread, and a test
  renders the same frame after 300 others and compares bytes). So
  `render_frame` at a tick is byte-identical run after run, and preview and
  export agree; a graphic that keeps a module-level counter breaks that, the
  standard library cannot stop it, and road map 10 §5l's proof row catches
  it. Limits: 64 MB heap per context, 1 MB stack, 250 ms per `render` call
  in preview and 2 s in export and `render_frame` — over budget is an error
  for that frame, not a hang. These limits are also what makes a package
  from someone else safe to open: its code runs, and it can reach nothing.
- **G-6 — Fonts: the app's bundled faces and the package's, never the
  system's** (road map 10 §4, 2026-09-25). The engine's font set is the
  faces bundled in `app/Resources/Fonts/` (Anton, Bebas Neue, Darker
  Grotesque, IBM Plex Mono, Montserrat and Source Sans 3, all OFL) and
  every `.ttf`/`.otf` in the package's `graphics/fonts/`. The system's
  fonts are NOT loaded, so a graphic authored on this Mac renders the same
  on another and the agent is told exactly what exists: a `font-family` the
  set does not have is a warning naming the families it does have. The
  warning cannot be skipped: with no system fonts there is NO fallback, so a
  `<text>` whose family the set lacks draws nothing and `measureText` has
  nothing to measure; a list (`"Nope, Montserrat"`) falls through to the
  family it names. A family that starts with a digit is not a CSS
  identifier, so `font-family="Source Sans 3"` lays out nothing and
  `"'Source Sans 3'"` draws: the standard library quotes every family it
  writes, the reference says to quote, and the warning names an unquoted
  digit-led family as the likely cause. The variable faces load as one face
  each and draw the instance `font-weight` asks for. `import_graphic_font`
  copies a font into the package.
- **G-7 — A graphic draws at its own size, and crosses the FFI as
  premultiplied BGRA** (road map 10 §4, 2026-09-25). A graphic has a
  `width` and `height` in canvas pixels — the module's `meta.width/height`
  if it declares them, else the canvas size at the time of the add — and,
  like a nest's, the size is frozen: a later canvas change does not re-lay
  out a graphic. It rasterizes at exactly that size, 1 source px = 1 canvas
  px, as a shape does; scale, position and rotation are the layer's. The
  engine writes premultiplied BGRA8 in sRGB into a buffer the app owns,
  the format `LayerRenderers` already uploads, so tiny-skia's RGBA is
  swizzled once, in Rust, and nowhere else. The maximum side is 8192, the
  renderer's own cap.
- **G-8 — A failing graphic shows its error in preview, answers it to the
  agent, and stops an export** (road map 10 §4, 2026-09-25). In PREVIEW a
  module that does not compile, or a frame that throws or times out, draws
  an ERROR CARD in the layer's box — a dark red fill, a 2 pt red border and
  the first diagnostic in IBM Plex Mono with its line and column — and never
  the last good frame, which would hide the error from a person scrubbing.
  `render_frame` and `render_graphic` return the diagnostics as text beside
  the image. An EXPORT compiles every module a clip in the range names
  before it starts and refuses on a compile error, listing each; a frame
  that fails during the export aborts it, naming the graphic and the frame.
  An error card is never written into a video. Built by G3c (road map 10
  §10.6): the card's border is 2 PIXELS of the layer's texture, and the
  missing module draws a card of its own; `render_graphic` was built by
  G4b (road map 10 §10.7): a failing frame is its cell's error card, through
  the same painter.
- **G-9 — A graphic has its own timeline: `in` and `length`, and `split`
  pins it** (road map 10 §4, 2026-09-25; built by G2b). `graphic.in`
  (ticks, ≥ 0) is where on the graphic's own timeline the clip's first
  frame falls; `graphic.length` (ticks, or `null`) is how long that
  timeline is, and `null` means "it ends with the clip", which is what a
  fresh clip wants: stretch the clip and the animation stretches its outro
  to the new end. `split` gives the right half `in + cut` and pins BOTH
  halves' `length` to the original's effective length, so the animation
  continues across the cut and plays its outro once, at the true end.
  `trim_start` advances `in` and `trim_end` never changes `length`, so
  trimming a graphic cuts it as trimming media cuts a file. There is no
  source bound: a clip longer than `length` keeps calling `render` with
  frames past `durationInFrames`, and what it draws there is the module's
  business. The core computes the frame: `frame = floor((in + clip time) /
  frame_ticks)` on the canvas grid and `ctx.durationInFrames =
  ceil(effective length / frame_ticks)`, clip time being §7.3's, which
  already accounts for nests. A graphic has no `speed`. Three decisions
  G2b made building it (road map 10 §10.5):
  - **G-9·a — no head bound, and `roll` is a front trim.** The head clamp
    (`source_window.rs`'s `earliest_start_on_grid`) stays media-only and
    answers nothing for a graphic, so a graphic's start can be dragged or
    rolled to 0 and `in` saturates at 0 through `in_advanced` at speed 1.
    `roll` moves `in` on the clip whose start it moves, as `trim_start`
    does (its predecessor's end is an end trim and keeps `length`), because
    it is the crate's other front-trim writer and has no source guard.
    `in` and `length` are written only by `recipe_graphic.rs`'s
    `graphic_advanced` (from `trim_start`, `roll` and `split`'s second
    half) and the split pin; `set_graphic` refuses `in`.
  - **G-9·b — the layer's hash covers `ctx`.** It is `content_hash` over
    `{name, frame, ctx, props}` — everything `render` is called with — not
    over name, props, size and frame alone: at one frame a `trim_end`
    changes `durationInFrames` and so the outro, and a rate change changes
    `time`, and a narrower key would serve a stale texture, the defect
    `recipe_text.rs` folds `reveal` in to prevent. The module's revision is
    the app's to add (G-13).
  - **G-9·c — a `null` length is `in + duration`, not `duration`.** "It
    ends with the clip" places the graphic's timeline end at the clip's
    end, which is graphic time `in + duration`. With `duration` alone a
    `trim_start` to 1 s on a fresh 5 s clip would give `durationInFrames`
    120 while the clip's last frame is graphic frame 149 — the outro would
    finish a second early and then hold — and split-then-delete-the-head,
    which looks the same, would give 150. Under this rule a front trim or
    a roll leaves `durationInFrames` where it was, and the split pin writes
    the number the unsplit clip already had.
- **G-10 — Props are not action targets; everything about the LAYER is**
  (road map 10 §4, 2026-09-25; built by G2b). The graphic animates itself,
  so `graphic` is not among the groups an action's `end` may carry, which
  is W-6's precedent: `set_action_end` answers a `graphic` object (a `null`
  included) or `graphic` in `off` with the **error** `props are not
  animated by actions; a graphic animates itself — change the module or its
  props`, as it answers `video.motion` and `text.words`; a file or paste
  payload whose `end` names `graphic` keeps it and animates nothing. Nor is
  `graphic` a `paste_attributes` group: a target keeps its module, size,
  timeline and props. `video.*` actions, motion presets, transitions and
  blend all apply, because they belong to the layer. Keyframed props are
  road map 10 §7's.
- **G-11 — Plain JavaScript, one ES module, no TypeScript** (road map 10
  §4, 2026-09-25). A module is ES2020+ JavaScript as QuickJS evaluates it,
  with no build step: agents write plain JavaScript as reliably as
  TypeScript, and a transpiler (`swc`/`oxc`) would be a second large
  dependency whose only output is the same JavaScript. `graphics/API.d.ts`
  gives an editor completions without making types part of the format.
- **G-12 — Colours in props are CSS strings** (road map 10 §4,
  2026-09-25). A `color` prop is a CSS colour string, normalised by the core
  to `#rrggbb` or `#rrggbbaa` lowercase (an opaque alpha is dropped). It is
  not the model's `[r, g, b, a]` floats, because props are the module's
  vocabulary, which goes straight into SVG attributes; the inspector's
  colour well converts at its edge. The core takes the four hex forms and
  `rgb()` / `rgba()`; named colours and `hsl()` are not taken yet (road
  map 10 §10.5).
- **G-13 — The revision is a content hash, and an export pins it** (road
  map 10 §4, 2026-09-25). A module's revision is the SHA-256 of its bytes,
  computed with CryptoKit. Preview always uses the newest revision, and the
  watcher refreshes the paused frame when one lands
  (`Playback.refreshPausedFrame`). An EXPORT pins, at its start, the
  revisions (and the font and asset sets) it compiled, so an agent editing
  a file mid-export cannot produce a video whose first half is one version
  and its second half another. Built by G3c (road map 10 §10.6): the pin is
  the whole compiled `GraphicSet`, retained, captured on main when the
  export (or a queued job, or `render_frame`) is asked for.
- **G-14 — `graphics/` is created on the app's first write into it, never
  at open** (road map 10 §4, 2026-09-25, G3a; amends G-3's last sentence).
  A package that never gets a graphic is not touched: opening, saving and
  autosaving a package without `graphics/` leaves it without one.
  `GraphicStore.ensureFolder()` is the ONE creator of `graphics/` inside a
  package, and every app-side writer — G4's `write_graphic`, G5's
  templates, the font and asset imports — goes through it. While the folder
  is absent the store watches the package directory itself, so a
  `graphics/` made from OUTSIDE (an agent's own `mkdir`) is picked up; the
  first observed appearance, whether the app made it or found it, calls
  `packageContentsDidChangeOnDisk()` once, which is what keeps the next
  save from being refused as "changed by another application". An untitled
  document's folder is the app's own scratch at
  `<NSTemporaryDirectory()>/Reelcut/<UUID>-graphics`, created eagerly,
  BESIDE the temporary cache root rather than under it as G-3 said —
  `cacheWrapper()` would carry a child of the cache root into `cache/` —
  and the first save carries it into the package only when it holds at
  least one entry. An untitled document restored from autosave has its
  saved `graphics/` copied into a fresh root.
- **G-15 — The Graphic sub-tab: what it shows for several clips, and what a
  write sends** (road map 10 §10.9 G5a, 2026-09-25).
  (a) **Several clips.** The sub-tab exists when EVERY selected clip is a
  graphic clip. Source and Size always show; Properties shows only when
  every clip is drawn by ONE module, because that is the one schema rows can
  be built from and the one `set_graphic` checks against; Timeline shows
  only for one clip, because `in` and `length` are that clip's own. With
  clips of different modules, Source names them and says to select one
  module's clips.
  (b) **A value equal to the schema's default is written as `null`.** The
  key leaves the stored props and the module draws its own default, which
  is what Reset writes too (CI-9), so "differs from the default" and "is
  stored" agree. A colour is equal by its parsed channels (the core accepts
  any string as a colour default and normalises only stored values). A
  default the four hex forms cannot parse (a named colour, `rgb()`) shows
  as transparent black, and its Reset writes `null`.
  (c) **Stale keys are listed sorted by key** — the stored props reach the
  app as a dictionary, which has no order. ⌫ writes `{key: null}` with no
  schema; a `null` always removes (G-4).
  (d) **The diagnostics are checked at the clip's FIRST frame**, drawn and
  rasterized at the clip's own size (the paused frame's two calls), memoised
  by module, revision, library, frame hash and size, and never recomputed
  during a live gesture.
  (e) **A string prop is a one-line text field, or a text area when
  `multiline`**, not §5j's value row: `OptionFieldControl` is numeric.
  (f) **No preview strip.** `render_graphic` has no inspector control; a
  person looks at the preview well.
- **G-16 — Insert ▸ Graphic: where the clip goes, what the module is
  called, and what a module that does not compile does** (road map 10
  §10.9 G5b, 2026-09-25). Insert ▸ Graphic is `write_graphic` of a template
  or a chosen `.js`, then `add_graphic_clip` at the module's `meta`
  duration and size, as ONE undo step "Insert Graphic" (the file write is
  not undoable, G-3).
  (a) **Placement is Add Text's** (`addGeneratedClip`, §4.1 "at the
  playhead"): the front track if the clip fits there, else a new track
  above everything. So no track, or a playhead over a clip, never disables
  the item; it validates on the document's graphics store alone.
  (b) **The name is the file's stem made a module name, then made free**:
  lowercased, every run of anything but `a-z0-9` one `-`, trimmed, at most
  63 (`graphic` when nothing is left) — `My Counter (v2).js` is
  `my-counter-v2` — then `GraphicStore.uniqueModuleName`: the name when
  the folder holds no module of it, else `-2`, `-3`, …, so an insert never
  overwrites a module another clip draws. Duplicate as New Graphic…'s
  suggestion uses the same rule.
  (c) **A module that does not compile stays on disk and places nothing**:
  the person reads "graphics/<name>.js was written but does not compile:
  <the first diagnostic> (line N)" in a sheet, and can fix the file where
  it is.
- **G-17 — An export's Cancel only sets flags; a reader is cancelled only
  by the loop that reads it, and a read that never returns is not woken —
  accepted** (issues #73, #74, 2026-09-29). `ExportWriter.cancel()` and
  `Exporter.cancel()` set flags and nothing else. The measurement's loop
  (`Exporter.measureLoudness`) sees the flag between samples and cancels
  its own reader; the writer's reader and writer are cancelled in
  `allInputsFinished`, after every pump has left its loop. Why:
  `cancelReading()` from main while a pump was inside
  `copyNextSampleBuffer` crashed 12 of 30 mid-export cancels (road map 10
  §10.6 G3c, #38). A cross-thread watchdog that cancels a stuck reader is
  that same mechanism again, and abandoning the completion instead would
  leave a live reader and writer on the destination. The risk accepted: a
  read that never returns (a pump starved because the other stopped
  reading, or a volume that stops answering) keeps its export alive — the
  sheet or the queue's job never completes and the queue stalls behind it,
  and an MCP `export` holds the server until its one-hour ceiling. Not seen
  in 70 runs (G3c) nor in issue batch B1's M1 runs
  (`tools/proof/export_cancel_proof.py`). Revisit only if one is observed.
