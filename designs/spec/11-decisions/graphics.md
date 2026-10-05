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
  **Amended 2026-10-02 (issue #105):** the bundled faces gain **Source
  Serif 4** (OFL, Reserved Font Name "Source", so vendored unmodified, never
  subset or renamed), the variable roman `SourceSerif4[opsz,wght].ttf` from
  `https://github.com/google/fonts/tree/main/ofl/sourceserif4` (google/fonts
  commit `7b203a635ebe80801c80f29633d4fc467cd1214e`, font version 4.004),
  saved as `app/Resources/Fonts/SourceSerif4.ttf`, SHA-256
  `97b2d4da6e3cb494b5a1e66ae176914d852ccabef49e0c02c0df25f3e39aca0b`, with
  its licence as `OFL-SourceSerif4.txt`; it loads as ONE face. The CSS
  generic families map onto the set: `serif` → Source Serif 4, `sans-serif`
  → Source Sans 3, `monospace` → IBM Plex Mono (named on the engine's
  `fontdb::Database`). `cursive` and `fantasy` are not mapped and are warned
  like any family the set lacks. The engine's font selector queries the
  text's OWN families only; usvg's default selector, which appends `serif`
  as a last fallback, is not used, because with `serif` mapped every
  missing family would then draw in Source Serif 4 with no warning, and
  "no fallback" above would be false. A family that is exactly `serif`,
  `sans-serif`, `cursive`, `fantasy` or `monospace` (case-sensitive, as usvg
  matches the keywords) is a CSS keyword and is written UNQUOTED by the
  standard library and `measureText`'s probe — quoted, it would name a
  family called "serif", which the set lacks; every other family is quoted
  as above. The standard library's default family stays Montserrat, and a
  `<text>` with no `font-family` still falls to usvg's default "Times New
  Roman" and is still warned.
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
  colour well converts at its edge. The core took the four hex forms and
  `rgb()` / `rgba()` until named colours and `hsl()` were added
  (2026-10-02, issue #105).
  **Amended 2026-10-02 (issue #105): the grammar**, written once, which the
  core (`core/src/model_color.rs`) and the standard library's
  `interpolateColors` (`graphic/src/stdlib.js`'s `__parseColour`) each
  implement exactly, both pinned by ONE shared fixture,
  `graphic/tests/colours.json` (`{"accepted": [[sent, stored], …],
  "refused": [sent, …]}`, its values worked by hand from the CSS
  definitions, never generated by either implementation):
  1. Any non-ASCII character is refused. Trim ASCII whitespace (space, tab,
     LF, FF, CR), then ASCII-lowercase.
  2. `#` and exactly 3, 4, 6 or 8 hex digits (a short digit × 17).
  3. `rgb(`, `rgba(`, `hsl(` or `hsla(` … with `)` the last character. The
     inside splits on runs of `,`, `/` and ASCII whitespace, empties
     dropped; 3 or 4 parts under either name. Each part's number matches
     `[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?`, so `inf`, `nan` and `0x10` are
     refused before any parse.
     - rgb: parts 0–2 are `N%` (unit N/100) or `N` (unit N/255); part 3,
       the alpha, `N%` (N/100) or `N` (N). A unit outside [0, 1] is REFUSED,
       never clamped. byte = round(unit × 255).
     - hsl: part 0 is `N` or `Ndeg`, h = N mod 360 (+ 360 when negative);
       `rad`, `turn` and `grad` are refused. Parts 1 and 2 MUST be `N%`, N/100
       in [0, 1]. Alpha as rgb's. With s, l in 0–1 and a = s × min(l, 1 − l):
       channel(n) = l − a × max(−1, min(k − 3, 9 − k, 1)), k = (n + h/30) mod
       12, n = 0 (red), 8 (green), 4 (blue); byte = round(channel × 255).
       Every step in f64 in this order (JavaScript's `%` and Rust's are both
       fmod).
  4. Else a word of `[a-z]+` looked up in svgtypes 0.16.1's table — the
     table usvg draws `fill` with: its 147 CSS named colours (no
     `rebeccapurple`, which usvg would not draw either) and `transparent` =
     `#00000000`. `currentcolor` and any other word are refused.
  The core stores `#rrggbb` when the alpha byte is 255, else `#rrggbbaa`;
  the standard library answers `[r, g, b, alphaByte / 255]` with integer
  bytes, so it quantises exactly as the core stores. **Refuse, never clamp,
  holds in `interpolateColors` too**: an `rgb(300, 0, 0)` that it clamped
  to red before now throws `interpolateColors: cannot parse colour
  "rgb(300, 0, 0)"`. The core's refusal names every form:
  `props.<key> must be a CSS colour (#rgb, #rgba, #rrggbb, #rrggbbaa, rgb(),
  rgba(), hsl(), hsla() or a colour name), not <value>`. Nothing stored or
  accepted as hex or `rgb()` decimals changes. A schema's colour DEFAULT is
  still not checked against the grammar (G-15 (b)).
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
- **G-18 — A graphic's own timeline moves with a transition's head and
  crosses a frame grid; a graphic clip with no description is tolerated**
  (issue #72, 2026-09-29).
  (a) **`add_transition`'s handle form moves `in` back by the head
  extension** through `graphic_advanced`, its fourth writer. G-9·a stands —
  no head bound — so where `in` is less than the extension it saturates at
  0 and the graphic's first frame lands on the clip's new first frame:
  `trim_start`'s answer at 0, and the one step 9 gives a text reveal.
  (b) **`graphic.in` is not a source position in D7-3's sense**: the
  graphic's frames are the canvas's (G-9's `floor((in + clip time) /
  frame)`). So every re-snap through `frame_grid.rs` (`set_canvas` fps,
  both paste paths, `unnest`) snaps `in` to the nearest frame, ≥ 0, and a
  set `length` to the nearest frame with `set_graphic`'s one-frame floor. A
  null length stays null.
  (c) **Declined: `validate` keeps accepting a `Source::Graphic` clip with
  no `graphic`.** The recipe answers `missing`, and the app draws the slate
  it draws for missing media. `set_graphic` answers `clip N is not a
  graphic clip`, so the clip is deleted rather than repaired. Refusing
  would make a whole document unreadable over a clip that holds nothing,
  which is `validate`'s canvas posture (model_query.rs:205-208).
  `schema_v10.rs`'s
  `a_file_with_a_bad_module_name_is_refused_and_an_absent_description_is_not`
  is the oracle.
- **G-19 — `render_graphic`'s svg takes no sheet arguments and draws past
  the length; the library files' watch is capped; the untitled roots are
  removed** (issues #75, #104, 2026-09-29).
  (a) **`format: "svg"` refuses a non-null `path`, `background` or
  `max_width` by name.** They belong to the png sheet, and svg answers text
  and writes no file. This was chosen over writing a `.svg` at `path` so
  that each format keeps one reply shape.
  (b) **Declined: a frame at or past `durationInFrames` is drawn, not
  refused.** G-9 says a clip longer than its `length` keeps calling
  `render` past `durationInFrames`, with `progress` clamped at 1
  (`recipe_graphic.rs` `graphic_source`). `render_graphic`'s ctx is that
  clip's ctx, so the frame is one that clips draw. `graphics_proof.py` C6
  pins this.
  (c) **Each font and asset file gets its own source**, as a module does (a
  folder source raises nothing for an in-place rewrite; G0 q7). A store
  arms at most 16 of them per pass, fonts first, in name order. An in-place
  rewrite of a later file is seen at the next folder event, which is
  accepted. Why 16:
  - Every source holds a descriptor until its cancel handler runs on the
    store's queue, which happens after the pass that replaced it. So a pass
    briefly holds two sets.
  - A store's folders and library files therefore hold at most 19
    descriptors, or 38 during a pass.
  - Four documents at the cap hold 76, or 152 if all four pass at once.
    That is arithmetic, not a measurement.
  - The comparison is with the soft limit of 256 (`launchctl limit
    maxfiles` printed `256 unlimited` on 2026-09-29) and with the owner's
    running Reelcut, which held 28 numbered descriptors (`lsof -p`; its
    documents were unknown).
  - Modules keep one source each and are uncapped, as before. Superseded
    by G-20 (a).
  (d) **The untitled graphics root (G-14) is removed when its document
  closes.** It is also removed when the first save re-points the store,
  which happens after NSDocument has written the package: `fileURL` is set
  after the write, and the writes are synchronous. `graphics_proof.py` G8
  shows it.
  - The untitled CACHE root (`temporaryCacheDirectory`, the same leak) is
    removed at close ONLY, whether or not the document was ever saved. It
    is not removed at the first save, for two reasons. Until the next
    `refreshTimeline`, the timeline still draws from that path, and
    `TimelineCaches` remembers a miss without its directory. An import or
    transcription pass that is in flight also keeps writing there.
  - By close, every save has finished. So the first save's copy is
    complete, and that copy holds any transcript still owing AssemblyAI a
    DELETE (`MediaTranscript.undeleted`). Whatever the root still holds
    after that is read by nothing, because the janitor reads
    `cacheDirectory`, which is the package's once the document is saved.
- **G-20 — Every file source shares G-19 (c)'s limit, modules first; a
  failed open is a scan warning; `render` answers at most 8 MiB of SVG; the
  png sheet draws at most 134,217,728 px; `graphic_reference` checks a
  `project` it is given** (issues #172, #105, 2026-09-30).
  (a) **Module, font and asset files share G-19 (c)'s 16 sources per store
  per pass, modules first**, then fonts, then assets, each in name order.
  The folder and package sources are outside the limit. Why: an uncapped
  module list let one document spend the process's descriptors, which G-19
  (c) had closed for the library files only. G-19 (c)'s arithmetic now
  covers every file: 19 descriptors a store, 38 during a pass, 152 for four
  documents passing at once, against the soft limit of 256. A file past the
  16th is not watched for an in-place rewrite; it is seen at the next pass,
  which is accepted, as it was for the library files.
  (b) **A failed `open` is a scan warning**: "`<subject>` is not watched:
  open failed (`<strerror>`)", where the subject is `graphics/`,
  `graphics/fonts/`, `graphics/assets/`, `graphics/<file>`,
  `graphics/fonts/<file>`, `graphics/assets/<file>` or `the package`. Why:
  a source that did not arm was silent, so a store that stopped seeing
  edits said nothing. G-24 (b) says where it shows.
  (c) **`render` answers at most 8 MiB of SVG** (`graphic::SVG_BYTES`);
  a longer string is the frame's error, naming its length. Why: the text
  is a preview pool key, crosses the FFI and an MCP reply, and is parsed
  whole, so an unbounded string costs memory at every one of those.
  (d) **The png contact sheet draws at most 134,217,728 px of frames**
  (`2 × 8192²`: two frames at the largest side, or sixteen 3840×2160). A
  call past it is refused before any frame is drawn, and no file is
  written. Why: every cell's raster is held until the sheet is painted, and
  sixteen 8192² frames are about 4 GB. `svg` writes no raster and is not
  capped.
  (e) **`graphic_reference` checks a `project` it is given**: when present
  and not null, it must name an open project, or the call is refused with
  the sentence every tool uses ("No open project is at …"). Without one it
  still answers when no project is open. Why: every tool publishes
  `project` (§7.9), so refusing the key would contradict the schema, and
  ignoring it would pass a wrong path in silence.
- **G-21 — A thread holds at most 16 graphic engines, least recently used
  dropped first; a module's top-level warnings are its compile's** (issue
  #105, 2026-10-01).
  (a) **`graphic::ENGINES_PER_THREAD` = 16.** A thread's map stamps each
  engine with a use counter when it is adopted (after a compile or a
  frame). It is not a clock. When an adoption takes the map past 16, the
  least recently used entries are dropped after the call. An evicted
  module is loaded again (stdlib, sandbox, top level) on its next frame on
  that thread. Why: each engine may hold G-5's 64 MB heap, and before this
  the map shrank only when a `Module` was dropped everywhere. Accepted: a
  reload re-evaluates the top level, so a module that keeps module-level
  state (already outside G-5) can restart its count.
  (b) **What `__warn` collects while a module's top level evaluates**, e.g.
  `asset("x")` outside `render`, **is drained when the module loads and
  kept on the `Module`** (`Module::warnings()`), in order and not
  de-duplicated. It is never attributed to a frame. A reload's copy is
  discarded. Before this the next call's `arm` cleared it, so it was lost.
  G-24 (a) publishes it.
- **G-22 — `measureText` and `textLines` take `xmlSpace`; whitespace-only
  text measures zero** (issue #105, 2026-10-02). A `font` object may carry
  `xmlSpace: "default"` (the default) or `"preserve"`, SVG's `xml:space`.
  Any other value throws `measureText: xmlSpace must be "default" or
  "preserve", not "<value>"`. Under `"default"` runs of spaces collapse as
  SVG draws them (`"a  b"` measures as `"a b"`); under `"preserve"` the
  probe `<text>` carries `xml:space="preserve"`, so a run of spaces beside a
  drawn glyph counts (`"a  b"` in Source Sans 3 at 64 px measures 80.448
  under `"default"` and 93.248 under `"preserve"`). The value is part
  of the memo's key. **Whitespace-only text measures zero under either
  value**, because usvg 0.48.1 lays out nothing for a text with no outlines,
  preserved or not, and there would be no text node to read; so preserve
  counts spaces only beside a drawn glyph. `textLines` writes
  `xml:space="preserve"` on its `<text>` when its font says `"preserve"`, so
  what is drawn is what was measured. `graphic::TextFont.preserve_space`
  carries the flag in Rust, and `__measureText` takes it as its seventh
  argument (rquickjs 0.14's most).
- **G-23 — An asset's name is one `asset(name)` can use; a bad one is
  renamed as it is copied in and skipped by the scan; a font file unchanged
  on disk is not read again** (issue #105, 2026-10-02).
  (a) **A legal asset name** is non-empty, at most 247 UTF-8 bytes (APFS's
  255 less the `.partial` that `GraphicStore.land(at:writing:)` writes
  first), does not start with `.` or `#`, and holds no `/ : " ' < > &` and
  no control scalar (U+0000–U+001F, U+007F–U+009F). Why: a leading `.` is
  hidden from the scan, a leading `#` is an internal href to usvg, `data:`
  routes to the data resolver, and `asset()` returns a known name unescaped
  (`stdlib.js`), so a quote, `&` or `<` breaks the SVG.
  (b) **Legalising** splits the name at its last `.`; in the stem it drops
  leading characters that are `.`, `#` or forbidden and trailing forbidden
  ones, and replaces each interior run of forbidden characters with one
  `-`; an empty stem becomes `image`; the stem is cut by whole scalars to
  fit 247 bytes. `#logo&mark.png` → `logo-mark.png`.
  (c) **A renamed copy never replaces**: when the legal name is held (by
  the scan or on disk) it takes `-2`, `-3`, … (the stem's tail cut by whole
  scalars so the name stays within 247 bytes). A name that needed no
  renaming keeps the replace it always had. An empty name and a name
  holding `/` stay refused.
  (d) **Both doors rename and say the name used**: `import_graphic_asset`
  answers `name` (the name used) and `renamed_from` (the name asked for,
  only when they differ); File ▸ Add Image to Graphics… shows an
  informational sheet, "\"<from>\" was added as \"<to>\": asset(name)
  cannot use the name it had."
  (e) **The scan skips an illegal visible asset file** with the warning
  `graphics/assets/<file> is not an asset name (no leading . or #; no / :
  " ' < > & or control character; at most 247 bytes) and was skipped`.
  Hidden files stay silent, as before; a 248–255-byte name on disk is now
  skipped and warned.
  (f) **A font file's verdict is reused** while its size, modification
  date and file number are unchanged: it is not read or validated again.
  Accepted: a rewrite that keeps all three is not seen until one changes.
- **G-24 — A graphic's warnings show where its other messages do** (issue
  #105, 2026-10-02; owner decision 3).
  (a) **Compile**: `rc_graphic_describe` answers `Module::warnings()` as
  `warnings`. They are the module's `diagnostics` in `write_graphic` and
  `get_graphic` when `ok` is true, and they lead the Graphic sub-tab's
  Source section rows.
  (b) **Scan**: `get_graphic {}` answers `warnings`, the store's scan
  warnings in their own sentences. The Source section lists them under an
  "In the graphics folder" note, each with Reveal (the folder in Finder, a
  beep when it is absent). Accepted: a pass whose only change is a warning
  posts nothing (store probe W7 pins that), so the pane shows it at its
  next rebuild.
  (c) **Export**: a pin keeps a warning once per graphic and message set,
  its first frame kept. Before this it was kept once per frame, so one
  graphic that warned every frame filled the 64 and hid every later one. A
  successful export answers `graphic_warnings`; the progress sheet's
  finish line ends "N graphic warning(s) (hover for details).", and the
  queue row reads "Exported “…”. N graphic warning(s)." with the count
  ahead of the loudness figures (the row truncates its tail, so a note on
  the end is the part a narrow window cuts). Each lists the warnings in its
  tooltip. A failed export answers as before.
- **G-25 — A colour default is G-12's, checked at compile and read through
  the core** (#219, 2026-10-02).
  (a) A `color` entry's `default` that G-12 refuses fails compile in the
  engine, by the stdlib's own `__parseColour` inline in `check_entry`, and
  in the core's `check_schema`, by `normalise_color`. The sentence is
  `schema.<key>.default "<text>" is not a color`.
  (b) The module's `props` still receive the default as written.
  (c) The Inspector reads a default through `rc_normalise_color`, so there
  is no third implementation.
  Accepted: a module whose top level reassigns a standard-library global
  can make (a)'s engine check answer either way. The check runs under the
  compile's budget, so it never hangs, and the core's check at
  `set_graphic` still holds. A module that compiled before and has an
  invalid default now shows a compile error.
- **G-26 — An export rasterizes its graphics ahead on worker threads; the
  compositor stays the one writer and the texture key decides** (issue
  #127, 2026-09-30).
  (a) **Where.** Only the `ExportWriter` path, with a pinned set and a
  graphic clip in the export's range (`Exporter.graphicNames`). Not GIF or
  APNG (`ImageSequenceWriter`), `render_frame`, Save Frame, the eyedropper,
  `render_graphic` or the preview.
  (b) **What a worker does.** `GraphicPrefetch` starts
  `activeProcessorCount − 1` threads (at least one). They walk the export's
  frames at `range.start + i × frameDuration` on the export's own key. The
  grid is anchored at `range.start` because the core snaps the start onto
  the export's own grid from 0 (`core/src/export.rs`), at the export's rate
  after any override. A worker reads the recipe through
  `RecipeSource.recipe(for:at:)` and draws only `GraphicRegistry.resolve`'s
  pinned set for that key (G-13). For each graphic layer the compositor
  would draw (opacity above 0, module compiled) it runs `svg`, computes the
  texture key and rasterizes. It records nothing and draws no card.
  (c) **What the compositor still does.** It runs `svg` itself for every
  graphic layer, records every warning and failure, and draws every error
  card (G-8). It uses a prefetched raster only on a pool miss, and only
  when the worker's texture key equals its own. Otherwise it rasterizes
  as before, so the file is byte-identical to the serial path's (G-5).
  (d) **Bounds.** At most `4 × workers` slots and 1 GiB of rasters are held
  ahead; a worker waits while either is reached. Every `start` has its
  `stop` in `Exporter.finish` and `deinit`, beside the unpin.
  (e) **The switch.** `ReelcutGraphicPrefetchOff` (a Bool default; YES is
  the serial path) is a measurement switch, not a setting.
  (f) **Risk accepted.** Each graphic's JavaScript runs twice per frame,
  once on a worker and once on the compositor. A repeated SVG is
  rasterized by a worker once per recent-key window (the pool's six keys),
  plus once for each later frame whose worker reached it before an earlier
  frame's worker did. Why: the compositor's queue is serial, and the
  rasterization is most of a heavy graphic's time; moving only the raster
  keeps G-8's reports and G-5's purity where they were.
- **G-27 — Deleting a graphic is refused while a clip draws it; the deleted
  text is kept, and that kept text is what marks the name as deleted**
  (issue #103, 2026-10-04, issue batch B84).
  (a) **The tool and the menu item.** `delete_graphic {name}`; File ▸
  Delete Graphic… is its menu item (G-30), one small sheet with a pop-up
  of the project's graphics, over the same body
  (`ProjectDocument.deleteGraphic(named:)`).
  (b) **Used is refused, saying which clips**: `The graphic "<name>" is
  still drawn by <where>; delete those clips or point them at another
  module (set_graphic {name}) first`. `<where>` is one group per
  container, the timeline first then nests by id, joined by " and "; a
  group is `clip 4`, `clips 4 and 9` or `clips 4, 9 and 12`, ids
  ascending, then ` on the timeline` or ` in nest <id>`. The sentence is
  the app's, not a core rule's: it names a file act's precondition.
  (c) **Not the Trash.** `graphics/<name>.js` leaves the folder and its
  bytes are kept with the module's other kept revisions (G-29), so
  `restore_graphic` brings it back. The Trash is somewhere an agent cannot
  reach and a proof would litter. Removing a module for good is deleting
  its folder under `graphics/history/` in Finder.
  (d) **Fonts and assets are left alone**: other modules share them.
  (e) **Not an undo step, never dirty** (G-3). The answer's `note` says so.
  (f) **A file-less name that has kept revisions is a DELETED module.** A
  rename carries its history away with it (G-28 (d)) and a delete always
  leaves the deleted text, so "no file, and something kept" is what a
  deleted name looks like — and, of everything the app FINISHES, only a
  deleted name. A rename killed part-way can leave the same state (G-28
  (f)). G-28 (e)'s repair reads that test and stands aside.
  **Risk accepted:** Undo can bring back a clip whose module was deleted
  after the clip was (delete the clip, delete the module, Undo). That clip
  shows the error card (G-8) until the module is restored by hand; no
  other module is ever moved onto the deleted one's name to fill the gap,
  even one it was once renamed from. The alternative, restoring the file
  on Undo, would make a file write an undo step, which G-3 refuses.
- **G-28 — Renaming a graphic moves the file, its kept revisions and every
  clip that names it; Undo renames the file back** (issue #103,
  2026-10-04, issue batch B84).
  (a) **The tool and the menu item.** `rename_graphic {name, to}`; File ▸
  Rename Graphic… is its menu item (G-30), over the same body
  (`ProjectDocument.renameGraphic(named:to:apply:)`).
  (b) **What moves.** `graphics/<name>.js` becomes `graphics/<to>.js`,
  `graphics/history/<name>/` is folded into `graphics/history/<to>/`, and
  every clip that names the module — on the timeline and inside every
  nest — is repointed by `set_graphic {name}` with no schema, as ONE undo
  step called "Rename Graphic". The project is marked edited only when
  clips changed. No core op was added: the op count stays 59.
  (c) **Refusals, in this order.** The module is absent: `No module named
  "<name>" in graphics/ — the folder holds: <list>`. `to` is not a module
  name: the core's own sentence (`GraphicStore.nameSentence`). **`to` is
  in use by a file** (the scan or the disk, `to == name` included):
  `graphics/<to>.js already exists`. **`to` has no file but a clip already
  names it** (a clip left behind by a deleted module): `The name "<to>" is
  already drawn by <where>; delete those clips or point them at another
  module (set_graphic {name}) first`, `<where>` as in G-27 (b) —
  otherwise that clip would silently start drawing the renamed module and
  Undo could not put things back. A nest is open: `rename_graphic has no
  meaning inside nest <id>: it renames the module for every clip in the
  project, the timeline's included. set_scope with no arguments comes back
  out; then rename.`
  (d) **The kept revisions follow the name**, and `graphics/history/<name>/`
  is gone afterwards. A rename that RETURNS is all-or-nothing: a failure
  part-way leaves the file, the history and the journal where they were —
  a rename refused after its pair was written puts `renames.json` back as
  it was read (its bytes, or no file), so a refused rename journals no
  pair, and an earlier pair of the same two names is still there for Undo.
  That holds for both refusals that come after the pair: the history that
  cannot be folded, and the CLIPS that refuse the new name (the edit
  throws, or leaves a clip behind) — there the file and its history are
  moved back under `<name>` and the journal is put back as it was read
  before the rename; a failed move back leaves the file at `<to>` and the
  pair, so (e)'s repair can make it. One thing the clips' arm cannot put
  back: a rename onto a DELETED module's name (the risk accepted below)
  has folded the two histories before the clips are asked, so the move
  back carries the deleted module's kept texts under `<name>` and leaves
  nothing kept under `<to>` (store probe H18 measures each of these).
  A crash between its steps is not a failure the app can put back: (f).
  The journal pair of (e) is written, and read back, after the file moves
  and BEFORE the history is folded (a fold cannot be undone): **a rename
  that could not be journalled is refused** — `graphics/<name>.js could
  not be renamed: its rename could not be journalled in
  graphics/history/renames.json` — so no rename succeeds that Undo could
  not repair.
  (e) **What Undo does.** The file rename itself is not an undo step
  (G-3), but the clips' names are model state. So the store journals each
  rename as a pair `[a, b]` in `graphics/history/renames.json` (at most
  32, oldest first, a repeated unordered pair moved to the end): the app
  moved the file FROM `a` TO `b`. After every committed project change,
  and once when the store starts, the document REPAIRS, **in one
  direction only**: for each pair, newest first, when the pair's FIRST
  name is drawn by a clip, has no file and has no kept revision, while its
  SECOND name has a file and no clip, the file (and its history) is moved
  back under the first. That move journals the pair the other way round,
  so Redo is the same repair. Undo therefore renames the file back with
  the clips, Redo forward again, a chain of renames undoes and redoes step
  by step, and a project opened after a crash between a FINISHED rename
  and a save is healed (a crash inside the rename is (f)'s). A clip never
  names a module a finished rename took away.
  (Amended by B84's review, 2026-10-04: the repair first tried BOTH
  directions of a pair, which moved a live module under a name whose file
  had been removed outside the app and — once `history/<name>/` was
  removed in Finder, as G-27 (c) tells a person to — under a deleted
  module's name.)
  (f) **What the repair skips, and its limits.** A file-less name WITH
  kept revisions is a deleted module (G-27 (f)): its clips keep the error
  card and no live module is moved under its name. A drawn name with no
  file at a pair's SECOND name is a removal the app did not make — the
  app's own moves leave the file there — and nothing is moved under it. A
  rename made outside the app (Finder, a shell `mv`) writes no journal
  pair and is not repaired, a `mv` back to a pair's first name included.
  **Three limits.** The first: the store cannot see a removal made
  outside the app (nothing is kept for one, G-29 (c)), so with the pair
  `[a, b]`, clips that name `a` with no file and nothing kept for a reason
  OTHER than Undo — repointed onto a new `a.js` that was then removed
  outside the app — cannot be told from an Undo, and `b.js`, when no clip
  draws it, is moved under `a`. The other two are a crash INSIDE a rename
  `<from>` → `<to>`, whose three steps — the file moves, the pair is
  journalled, the history is folded — are not one act on disk. Killed
  after the file moved and before the pair was written, there is no pair:
  `<to>.js` is on disk, the clips name `<from>`, and nothing is repaired
  (a rename made outside the app leaves the same). Killed after the pair
  was written and before the fold finished, the repair heals it when
  `<from>` had nothing kept, and does NOT when it had:
  `history/<from>/` is still there, so `<from>` reads as a deleted module
  (G-27 (f)), its clips keep the error card, and a default
  `restore_graphic {name: <from>}` writes an OLDER text while the current
  one sits undrawn at `<to>.js` (store probe H15 builds that state and
  runs the restore in it). That state cannot be told from a rename
  followed by a new `<from>` written and deleted — the same pair, kept
  texts under `<from>`, an undrawn `<to>.js` — and no order of the three
  steps closes both windows; telling them apart needs a marker on disk
  this decision does not have. The way out of either, by hand:
  `set_graphic {name: <to>}` on the clips.
  (g) **The nest limit.** Rename is refused while a nest is open (the
  menu item is greyed there, G-30 (f)). An unscoped op is re-addressed to the
  open nest (`ProjectDocument.addressed`), so the timeline's clips cannot
  be reached from inside one; making it work there needs a document-level
  core op, which is a larger change and is not built.
  **Risk accepted:** the alternative to (e), a rename that empties the
  undo history, is not safe in this app (`removeAllActions` on a document
  is the "do not flush" pitfall). The repair's cost is one journal read
  per committed change in which some drawn name has no file, and none
  otherwise. **A rename onto the name of a DELETED module** (no file, no
  clip, kept revisions) is none of (c)'s refusals: the two histories fold
  under `to` ((b)), the deleted module's texts as the oldest, and the
  prune past 10 (G-29 (b)) removes those first — a renamed module that
  brings 10 kept texts removes, in one call, the deleted text that G-27
  (c) says only a Finder delete removes. `rename_graphic`'s description
  says so; a sixth refusal was not chosen.
- **G-29 — The last 10 texts of each module are kept in the package;
  amends G-3's price** (issue #103, 2026-10-04, issue batch B84).
  (a) **Where.** `graphics/history/<name>/<%06d sequence>-<revision>.js`,
  inside the package and not in `cache/`: the cache is documented as safe
  to delete and is rebuilt freely, so history there could vanish silently,
  while `graphics/` is user content carried by every save, Save As and
  copy (§5.6). `history/` is created only inside an existing `graphics/`
  (G-14 stands: `ensureFolder()` is still the one creator of the folder).
  The next sequence is the highest plus one; any other file there is
  ignored.
  (b) **How much.** The last 10 per module (`GraphicStore.historyLimit`),
  a few kilobytes each; the lowest sequences are pruned. History never
  holds the current text, and a text kept twice is listed once: a pass
  drops a module's new revision from its history, and `start()` drops
  each module's current one — a text put back while the project was
  closed, or a crash between a delete's keep and its removal — so a
  default restore always reaches an OLDER text. A drop is not a keep.
  (c) **When.** Whenever the app SEES a module's text replaced while the
  project is open — `write_graphic`, a save from an outside editor, a
  restore — and when `delete_graphic` removes it. Nothing is kept at
  `start()`, for a removal the app did not make, or for a text that came
  and went inside one 100 ms pass.
  (d) **Restore.** `restore_graphic {name, revision?}` writes a kept text
  back as `graphics/<name>.js` and keeps the text it replaced, so
  restoring twice returns to where you were; `revision` defaults to the
  newest kept, and the tool works when `<name>.js` is absent (a deleted
  module). Refusals: `No kept revision of "<name>" — one is kept when a
  write replaces a module's text or delete_graphic removes it`, and
  `"<name>" has no kept revision <revision> — kept: <revisions>`. A kept
  file whose bytes no longer hash to the revision in its name (changed by
  hand) is not a kept text (§5.6): restoring it is refused and nothing is
  written — `graphics/history/<name>/<file> was changed outside Reelcut
  and no longer holds the revision in its name; it is not restored — other
  kept revisions: <revisions, or "none">` — and the file is left for the
  person. Listing reads names, not bytes (hashing every kept file on
  every read is not done), so that file is still listed in `kept` and
  `history`, still counts toward the 10 and still marks a file-less name
  as deleted, and while it is the newest a default restore is refused
  until it is removed or another revision is named. File ▸
  Restore Graphic Version… is its menu item (G-30); it restores the newest
  and has no history browser. Not an undo step, never dirty (G-3).
  (e) **What an agent sees.** `kept` — `[revision]`, newest first — in
  the answers of `write_graphic`, `get_graphic {name}` and the three new
  tools, and `history: [{name, kept}]`, deleted modules included, in
  `get_graphic {}`.
  (f) **G-3's price is amended.** `write_graphic`'s note is now "not
  undoable; the text it replaced is kept (the last 10 per module) —
  restore_graphic brings it back", in place of "keep your own copy if you
  want the old one back". The built-in Assistant may call all three tools
  without asking first, because a delete keeps the text.
  (g) **An untitled document** keeps its history in its temporary
  graphics root; the first save carries it into the package, and closing
  without saving loses it with the graphics themselves.
  **Risk accepted:** an edit made while the project was closed, or two
  saves within a tenth of a second, keeps nothing extra; an eleventh text
  drops the oldest for good.
- **G-30 — File ▸ Rename Graphic…, Delete Graphic… and Restore Graphic
  Version… are one small sheet over G-27..G-29's three bodies; a refusal
  is the body's own sentence, shown in the sheet** (issue #103,
  2026-10-04, issue batch B84, phase 2).
  (a) **The items.** In the File menu, in a separator group of their own
  straight under Add Image to Graphics…, in the order Rename Graphic…,
  Delete Graphic…, Restore Graphic Version…, with no key equivalents (the
  caption items' reason, §9). Each is a nil-target selector the editor
  implements: `renameGraphic(_:)`, `deleteGraphic(_:)`,
  `restoreGraphicVersion(_:)`.
  (b) **The one sheet** (`GraphicFileSheetController`). Its title is the
  item's without the "…"; under it a hint ((c)), a `Graphic:` pop-up of
  the project's graphics, Cancel, and a button reading Rename, Delete or
  Restore. Rename adds a `New name:` field, filled with the chosen
  graphic's name, and the footnote `lowercase letters, digits and -`; its
  button is dimmed until the name is filled in and differs from the
  chosen one. Restore adds one line under the pop-up, `1 version kept` or
  `<n> versions kept`, and lists no version: it restores the newest
  (G-29 (d)), and there is no history browser. Rename and Delete list the
  folder's modules by name. Restore lists every name that has a kept
  text, a deleted module (G-27 (f)) reading `<name> (deleted)` — which is
  how a delete is taken back.
  (c) **The hints, word for word.** Rename: `Every clip that uses the
  graphic follows its new name, on the timeline and inside nests. Undo
  renames it back when a clip uses it; a graphic no clip uses is renamed
  back by renaming it again.` Delete: `A graphic that clips still use
  cannot be deleted. Its code is kept with its earlier versions, so
  Restore Graphic Version… brings it back. Deleting is not an Undo step.`
  Restore: `Puts back the newest kept version of the graphic's code. If
  the graphic has code now, that code is kept in its place, so restoring
  again returns to where you were. Restoring is not an Undo step.` They
  promise only what holds: a rename of a graphic no clip uses makes no
  edit (G-28 (b)) and so no undo step, and a restored DELETED graphic
  replaced nothing, so nothing is kept in its place.
  (d) **Where a sheet opens.** Rename and Restore open on the graphic of
  the selected clip when exactly one clip is selected and its graphic is
  a row — a deleted one included, which is how a clip showing the error
  card gets its code back; otherwise on the first row by name. Delete
  always opens on the first: a selected clip's graphic is in use and
  could not be deleted.
  (e) **A refusal shows in the sheet, which stays up.** The body's
  sentence is shown word for word, with a beep, in a label at the foot of
  the sheet's content, so the person can fix the name or pick another
  graphic; no alert sheet is put up. It is the sentence an agent reads,
  the hint `(set_graphic {name})` included (the owner's choice,
  2026-10-04). The sheet owns two guards, both about the CALL (D2-1): a
  new name that is empty or unchanged (the dimmed button), and an item
  with nothing to list ((f)). The name goes to the body as typed, neither
  trimmed nor lowercased. **There is no second confirmation**: the
  sheet's Delete button is the confirmation, because the code is kept and
  Restore brings it back (G-27 (c)). After a success the sheet closes and
  says nothing; a restored text that does not compile shows the error
  card as any broken graphic does (G-8).
  (f) **When an item is greyed.** Rename and Delete in a project whose
  folder holds no module; Restore when no name has a kept text; Rename
  also while a nest is open (G-28 (g)); all three before the document's
  graphics store exists, and while a sheet is attached.
  (g) **One implementation.** Each act is one call of the body the tool
  calls — `ProjectDocument.renameGraphic(named:to:apply:)`, its `apply`
  the document's `performGroupedEdit("Rename Graphic", …)`,
  `deleteGraphic(named:)`, `restoreGraphic(named:revision:)` with no
  revision — and the sheet reaches no store writer, no op and no undo
  registration of its own.
  **Risk accepted:** a person reads a tool's hint in a refusal. A second
  wording for people would be a second spelling of every sentence to keep
  in step with the first.
- **G-31 — The standard library measures a path: `getLength`,
  `getPointAtLength` and `evolvePath`, in JavaScript, a curve as 64
  chords, a draw-on dashed by the longest subpath** (issue #103,
  2026-10-05, issue batch B85, phase 1).
  (a) **The names.** `getLength(d)` answers a number, `getPointAtLength(d,
  length)` answers `{x, y, angle}` and `evolvePath(progress, d)` answers
  `{strokeDasharray, strokeDashoffset}`. The three names and their
  argument orders are Remotion's, which an agent already knows, as the
  rest of the library's are (G-2); none of its code, nor any other
  library's, is carried over. The heading comes with the point, in
  degrees as SVG's `rotate()` takes them, rather than from a fourth
  function.
  (b) **What is measured.** `d` is read as `String(d)`: `M L H V C S Q T A
  Z` in both cases, implicit repeats (the pairs after an `M` are `L`),
  SVG's number grammar (`.5.5`, `1e2`, `-1-1`, commas optional) and arc
  flags written without separators (`a50 50 0 01100 0`). `S` and `T`
  reflect the previous control point only after a curve of their own
  family, else the current point. An arc with a zero radius is a line;
  radii too small for the chord are scaled up, and the centre
  conversion's radicand is clamped at 0, so a length is never NaN. A
  SUBPATH begins at each `M`/`m` and at the first drawing command after a
  `Z`/`z`, from that subpath's start point. `getLength` is the sum over
  every subpath, a `Z` adding its closing line and a move adding nothing;
  an empty string is 0.
  (c) **The point and the heading.** `length` is `Number(length)`, NaN
  read as 0, clamped to 0…total. The point is on the true curve, not on a
  chord. `angle` is `Math.atan2(dy, dx) * 180 / Math.PI` of the curve's
  own derivative there (y down); at a joint it is the segment ending
  there, at 0 the first drawn segment's start, and a zero-length segment
  gives no heading. Where the derivative is (0, 0) on a segment of
  non-zero length the heading is the tangent's LIMIT: at the segment's
  start, the direction from the start to the first later control point
  (or end) that differs from it; at its end, the direction to the end
  from the last earlier control point (or start) that differs from it; at
  an interior parameter (a cubic's cusp), the direction of the chord the
  point lies on. A path with no drawn length answers its last `M` point
  (or 0, 0) with `angle: 0`.
  (d) **The draw-on.** `progress` is `Number(progress)`, NaN read as 0,
  clamped to 0…1. With `D = L × 1.001`, `L` being the length of the
  LONGEST subpath, the answer is `{strokeDasharray: "D D",
  strokeDashoffset: D × (1 − progress)}`, and `{strokeDasharray: "none",
  strokeDashoffset: 0}` when `L` is 0. The pad is there so a closed
  outline always closes at progress 1 although the measure is a
  flattening; mid-way the tip is at most 0.1 % ahead. The longest subpath
  and not the total, because the rasterizer restarts the dash on each
  subpath (`tiny-skia-path` 0.12.0's `dash.rs` walks the contours, each
  from the pattern's first interval): a dash as long as the total would
  draw a short subpath too slowly, and no single dash can draw the
  subpaths one after another. So every subpath draws from its own start
  at once and at the same speed, the longest ending at progress 1; pieces
  drawn in turn are one `<path>` each, which the reference says.
  (e) **The two errors**, thrown as `Error`s, `<fn>` being the function
  the module called: `<fn>: cannot parse the path at character <i>:
  "<d.slice(i, i + 12)>"` — an unknown command, a path that does not
  begin with `M`/`m`, a number where none can be read, an arc flag that
  is not `0` or `1`, a number that is not finite, `<i>` the 0-based index
  — and `<fn>: the path ends inside a command`, when the data ran out
  while a command still wanted numbers. A path that cannot be read is
  never a silent zero.
  **Not finite is a refusal, not an answer**: no helper ever answers
  `Infinity` or NaN, and a path that would make one do so is refused in
  the first sentence. Five checks in `path.js` hold it, each with a case
  in `path.test.js`'s row `T8 a number that is not finite`. At the
  number's own character: a number that reads as `Infinity` (`1e999`). At
  the character where its command, or its repeat of one, begins: a move
  to a point that is not finite (`M 1e308 0 m 1e308 0`); an arc whose
  centre form is not, which is radii whose squares overflow (`A 1e300
  1e300 …`) or end points so close that theirs underflow (`M 0 0 A 1 1 0
  0 1 1e-200 0`) — unchecked, each was answered as a path with nothing
  drawn, the silent zero; a segment that takes the running length out of
  a double's range, which is a point past the largest number or a chord
  whose square is (`H 1e200`, or the diagonal that closes `M 0 0 H 1.2e154
  V 1.2e154 Z`, while the same path at 1e153 measures); and, asked of
  `getPointAtLength` alone, a point that is not finite between two
  measured points that are — a curve one step under the largest double,
  whose length `getLength` answers. The length is checked padded, so
  `evolvePath`'s dash is finite whenever the length is. The sentence says
  "cannot parse" of a number that was read: one sentence for every path
  the helpers will not answer was preferred to a third.
  (f) **The tolerance.** A path is measured as its flattening: a line
  exactly, each `C S Q T` as 64 chords at uniform parameter, each arc as
  chords of at most π/128 rad of sweep. That is within 0.01 % (1e-4
  relative) on the reference shapes, whose lengths are closed forms: a
  circle of radius 500 (2π·500), the ellipse of radii 200 and 100
  (4a·E(e), 968.8448220547675) plain and rotated 30°, the parabola
  y = x² from −1 to 1 (√5 + asinh(2)/2) as a `Q` and as a `C`, and the
  cusp x = t², y = t³ ((13√13 − 8)/27). Exact formulas exist only for
  some curves and would cost much more code.
  (g) **The memo.** The last paths measured are kept per engine, keyed by
  the `d` string. A path's cost is its chord count plus `d.length`;
  before an insert that would take the memo past 32 paths or past a total
  cost of 50,000 the memo is cleared whole, and the new path is then kept
  — so a path over the cost bound on its own is kept alone until the next
  insert, and its own calls in a render do not re-measure it. An engine's
  heap is 64 MB and outlives a render (G-5's limit); the cost bound keeps
  what the memo holds to a few MB of it, except a single path over the
  bound, which is held whole until the next insert and is limited only by
  what one render's budget can measure. It breaks no G-5 purity: an
  answer never depends on what the memo holds, and the memo's state is
  reachable by no module — the Map sits in a closure, as `noise.js`'s
  permutation tables do, because the library's `__` functions and
  top-level `const`s are visible to a module.
  (h) **Pure JavaScript, not a host function.** `graphic/src/path.js`,
  evaluated as a script after `stdlib.js` and `noise.js` and before the
  sandbox, uses only `Math`, `Map`, `Float64Array`, `String`, `Number`
  and `Error`: nothing crosses into Rust, and nothing the sandbox removes
  is used. A path the memo still holds costs a lookup per call; paths
  that together pass a bound are measured again in turn; a path rebuilt
  every frame is re-measured, and a fresh path of 200 cubic segments with
  1,000 points taken along it stays inside the preview's 250 ms
  (`graphic/tests/path.rs` prints the figure).
  **Risks accepted:** a curve tighter than the references can exceed the
  tolerance, and the pad covers 0.1 %. No row measures the memo's held
  bytes, because reading them would make the memo's state visible to a
  module, which is the G-5 hole the closure prevents.
