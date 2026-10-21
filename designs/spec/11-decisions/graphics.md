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
  `graphic/`, a crate at the repo root. `framejob-core` depends on it by
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
  **Amended by NM-6** (rename R0): `reelcut-core` is now `framejob-core`.
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
- **G-10 — Props are not action targets (superseded by G-34);
  everything about the LAYER is**
  (road map 10 §4, 2026-09-25; built by G2b). The graphic animates itself,
  so `graphic` is not among the groups an action's `end` may carry, which
  is W-6's precedent: `set_action_end` answers a `graphic` object (a `null`
  included) or `graphic` in `off` with the **error** `props are not
  animated by actions; a graphic animates itself — change the module or its
  props`, as it answers `video.motion` and `text.words`; a file or paste
  payload whose `end` names `graphic` keeps it and animates nothing. Nor is
  `graphic` a `paste_attributes` group: a target keeps its module, size,
  timeline and props (amended by G-32). `video.*` actions, motion presets,
  transitions and blend all apply, because they belong to the layer.
  Keyframed props are road map 10 §7's. **G-34 supersedes** this entry's
  first sentence, its error and "a file or paste payload whose `end` names
  `graphic` keeps it and animates nothing"; what it says of the layer
  stands.
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
  `<NSTemporaryDirectory()>/FrameJob/<UUID>-graphics`, created eagerly,
  BESIDE the temporary cache root rather than under it as G-3 said —
  `cacheWrapper()` would carry a child of the cache root into `cache/` —
  and the first save carries it into the package only when it holds at
  least one entry. An untitled document restored from autosave has its
  saved `graphics/` copied into a fresh root.
  **Amended by NM-4** (rename R0):
  `<NSTemporaryDirectory()>/Reelcut/<UUID>-graphics` is now
  `<NSTemporaryDirectory()>/FrameJob/<UUID>-graphics`.
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
  as transparent black, and its Reset writes `null`. (Amended by G-34 (l):
  with an action selected a row writes the value itself into the action's
  end, never `null`.)
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
    running Frame Job, which held 28 numbered descriptors (`lsof -p`; its
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
  (e) **The switch.** `FrameJobGraphicPrefetchOff` (a Bool default; YES is
  the serial path) is a measurement switch, not a setting.
  (f) **Risk accepted.** Each graphic's JavaScript runs twice per frame,
  once on a worker and once on the compositor. A repeated SVG is
  rasterized by a worker once per recent-key window (the pool's six keys),
  plus once for each later frame whose worker reached it before an earlier
  frame's worker did. Why: the compositor's queue is serial, and the
  rasterization is most of a heavy graphic's time; moving only the raster
  keeps G-8's reports and G-5's purity where they were.
  **Amended by NM-6** (rename R0): `ReelcutGraphicPrefetchOff` is now
  `FrameJobGraphicPrefetchOff`.
  **Amended by G-36**: (a)'s "or the preview" no longer holds — a playing
  preview has its own session on the document's key.
  **Amended by G-37**: (d)'s slot count and 1 GiB are gone — every
  session's held rasters share one process-wide budget, a quarter of
  physical memory, under a ceiling of 1,024 entries per session.
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
  written — `graphics/history/<name>/<file> was changed outside Frame Job
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
  **Amended by NM-5** (rename R0): the refusal's "was changed outside
  Reelcut" is now "was changed outside Frame Job".
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
- **G-32 — `paste_attributes` takes a fifth group, `graphic`, that copies
  a clip's props whole onto clips drawn by the same module; it is never in
  the default set; `skip_missing` skips what cannot take a named group;
  Edit ▸ Paste Graphic Properties is the person's door** (issue #103,
  2026-10-05, issue batch B85, phase 2). It amends G-10's sentence "Nor is
  `graphic` a `paste_attributes` group": `graphic` is now a group a caller
  may NAME, and G-10's sentence still describes a paste that names none.
  "The owner's choice N" below is one of this phase's seven, each accepted
  as recommended (2026-10-05); batch B85's own choice 7 is named as such.
  (a) **No `groups`: unchanged.** With `groups` absent the op copies the
  four groups in `patch::GROUPS` (`video`, `audio`, `text`, `shape`), each
  where both sides have it, exactly as before this entry. `graphic` is
  never in that set, and `skip_missing` changes nothing there: with no
  `groups`, the answer with the flag is the answer without it. **Why
  `graphic` is not in the default set** (batch B85's choice 7, answered
  (c) by the owner on 2026-10-04): a graphic's props hold its WORDS as
  well as its look, and ⌥⌘V has no picker, so a default that carried them
  would overwrite one lower third's name with another's on a paste that
  was asked for the position and the opacity.
  (b) **Who has it, who can take it.** A side HAS `graphic` when its
  source is `Source::Graphic` and `clip.graphic` is set, which is
  `set_graphic`'s test. A target can TAKE it when it has it and its
  `graphic.name` equals the payload clip's. The payload clip is the
  EARLIEST (then the front-most, then the lower id), as for every group.
  (c) **Named, `skip_missing` false (the default): all or nothing**, as
  the four groups are. The exact errors: `payload clip has no graphic
  properties`; `clip {id} has no graphic properties`; and `clip {id} is
  drawn by "{its name}" and the payload clip by "{payload's name}";
  graphic props are pasted only between clips of one module` (the owner's
  choice 6). The four existing groups keep their sentences. Targets are
  visited in `selected_clips`' order and the first error met is the
  answer.
  (d) **Named, `skip_missing` true.** A named group the payload clip
  lacks is dropped, and a target that lacks a named group (for `graphic`:
  one that cannot take it) is skipped for that group. A missing group is
  never an error, and the answer is an identity when nothing changed. The
  flag applies to all five groups, so an agent can ask for exactly what
  the menu item does (the owner's choice 5).
  (e) **What travels: `props`, whole.** The target keeps `name`, `width`,
  `height`, `in`, `length` and everything outside `graphic`. A target key
  the payload lacks is removed with `shift_remove`; a key both have keeps
  its slot (`insert`); new keys are appended in the payload's order —
  `model_graphic.rs`'s insert-and-`shift_remove` rule, so the written
  text moves no key it did not have to. (Amended by G-34 (d): a target
  key that an action on the target names is kept.)
  (f) **When the copied map is read.** The map is checked for shape only,
  once, the first time a target TAKES it, before anything is written to
  that target: `model_graphic::check_props(_, None)`, its `null`s
  dropped, then `check_count`, each in its own sentence, unprefixed. No
  schema is read and no colour is normalised (the core has no module to
  ask, G-4). **A paste in which no target takes `graphic` never reads
  the map**: with `skip_missing` it is an identity however the map is
  shaped, and without it it is (c)'s error, not the map's. A malformed
  map and at least one target that takes it is the map's error in both
  modes, and nothing changes. So the menu item BEEPS and shows no alert
  whenever no selected clip takes the props, however the copied map is
  shaped, and a malformed map onto a matching clip is the core's sentence
  in an alert (the owner's choice 7). **Why**: the owner's choice 3
  ("choosing it beeps and changes nothing … when nothing matches") then
  holds without exception, and the four groups already check a copied
  group only after it has landed on a target (`normalise_and_check_group`
  follows `copy_group`).
  A malformed map can reach the MENU only from a project file written by
  hand or from an agent's `paste` of a hand-written payload, neither of
  which checks a graphic's props for shape (`validate` in
  `model_query.rs` reads only its name, `normalise_and_check_pasted` only
  the four groups); an agent can also hand one to the tool directly.
  (g) **The door.** Edit ▸ Paste Graphic Properties, directly under Paste
  Attributes, with no key equivalent (the owner's choices 1 and 2). It
  sends ONE op — `paste_attributes` over the selection with `groups:
  ["graphic"]` and `skip_missing: true` — as the undo step "Paste Graphic
  Properties", and interprets nothing about the payload: an identity is
  the edit path's beep, and an error is its alert sheet with the core's
  sentence and no undo step. It is enabled when Frame Job clips are on the
  clipboard and at least one selected clip is a graphic (the owner's
  choice 3); greying it exactly would mean reading the clipboard's bytes
  every time a menu opens. When several clips were copied the props come
  from the earliest, and if that clip is not a graphic nothing is pasted
  (the owner's choice 4). An agent's step is still named "Paste
  Attributes": it calls the same tool with the group named.
  (h) **A paste-only enum, not a fifth `patch::Group`.** `patch::Group`
  is the four groups a PATCH can address, and it is matched exhaustively
  where a patch is read: `patch.rs` (`name`, `subject`, `template`),
  `edit_props.rs` (`normalise_and_check_group`, `check_group`,
  `patch_clips`) and `edit_action.rs` (`check_end_patch`'s probe). A
  `Graphic` variant there would need a template that means nothing — a
  graphic's keys are its module's, not the vocabulary's — and would make
  `graphic` look like a group an action's `end` could carry, which G-10
  refuses. So `paste_attributes` takes its own `PasteGroup` (the four and
  `Graphic`), whose first four map onto `patch::Group` and still go
  through `normalise_and_check_group` after each copy.
  **Not done, and why:** the props are not checked against the module's
  schema and their colours are not normalised, because the op carries no
  schema and the payload's props were stored through one already; a
  subset of props, or the look without the words, would need the module's
  schema sent with the edit. **Risks accepted:** a target written before
  its module dropped a key receives the payload's keys as they are,
  stale ones included, as `set_graphic` without a schema would store
  them; the item can be enabled when choosing it only beeps ((g)).
- **G-33 — On every export row that needs even pixel dimensions the CORE
  resolves and lists the even size the file will have, so the size
  reported is the size written and no size of the canvas's own shape is
  refused for being odd; `hevc_alpha`,
  "HEVC with Alpha (MOV)", is a tenth row whose frames carry the canvas's
  alpha; every movie row FILLS the frame instead of padding it when the
  miss is within a pixel; a missing encoder ends in the preset's own
  sentence and no file** (issue #103, 2026-10-05, issue batch B85, phase
  3). Built in two phases, gated in order and committed apart: A is the
  even rule alone, which moved the REPORT and no picture (commit fcfeebf);
  B is the row, the fill rule, the guard's test, the encoder outcome and
  the Document tab's note. Every figure below was measured by the designer
  on 2026-10-05 (Apple M2 Max, macOS 26.5.1, ffmpeg 9.0.2) in a scratch
  `AVAssetWriter` program at 320 × 180 and 30 frames, unless it says "on
  the built app": those are `tools/proof/hevc_alpha_proof.py`'s, on the
  same host and day, one-second exports no larger than 1296 × 728. That
  proof's `--rows size` was phase A's gate, and its row G1 is red by
  design on a build that holds phase B (it requires the pad the baseline
  recorded and an unknown `hevc_alpha`).
  (a) **Whose choices.** Batch B85's choices 12–17, accepted as
  recommended on 2026-10-04: a NEW format row "HEVC with Alpha (MOV)"
  directly after "HEVC (MP4)", `hevc_alpha` to the `export` tool; `.mov`,
  AAC sound, HEVC's Quality tiers and bit-rate controls, "optimize for
  network use" off by default; the sheet's summary says "alpha" (its
  footnote's text is "HEVC_ALPHA · MOV · alpha". On the built app the
  footnote's slot beside the sheet's three buttons is 88 pt and that line
  needs 144, so it is DRAWN cut with a tail ellipsis, before the word — a
  footnote gives way before a button (#141), and ProRes 4444's
  "PRORES4444 · MOV · alpha" has been cut the same way, 144 pt in 88,
  on this build (measured beside it). Its TOOLTIP is the whole line:
  `syncReadout` writes the tooltip after the text and clears it where it
  clears the text, so resting the pointer on the footnote shows "HEVC_ALPHA
  · MOV · alpha" (the proof's row E1 requires the layout dump's `tooltip`
  to equal the text; on the build before those two lines it read the empty
  string `sheetFootnote("")` set once). ProRes 4444's footnote takes the
  same two lines and no row opens the sheet on it. So the choice holds of
  the footnote's text and its tooltip and NOT of the sheet's drawn face;
  the sheet's layout is not changed by this entry, and (h) names what is
  left); the `export` tool's
  `preset` description names
  the three rows that keep transparency and its answer reports `preset:
  "hevc_alpha"`, `container: "mov"`, `codec: "hevc_alpha"`; the Document
  tab's note becomes "Transparent — kept by 3 export formats." (one or two
  rows are still named; three or more are counted, because three names
  run to about 295 pt in a row 244 pt wide at the inspector's narrowest;
  on the built app the counted note is 183 pt); a custom size of a different
  shape from the canvas is refused with ProRes 4444's sentence; the row is
  always listed, and a Mac whose encoder refuses it ends with "This Mac
  cannot export with the “hevc_alpha” preset." and no file. The owner's
  four answers of 2026-10-05: a miss of under a pixel is FILLED rather
  than fitted on `h264`, `hevc` and `prores_422`; an odd size is NEVER
  refused — the owner's answer (c): the core resolves and reports the even
  size that will be written (as built this holds of every size of the
  canvas's own shape; section (c) below says what becomes of a typed size
  of another shape) — which SUPERSEDES choice 18 (a) of 2026-10-04 (a
  refusal in a sentence of its own: there is no such error case and no
  such sentence); ProRes 4444 is filled too; and the sheet's footnote
  keeps the core's codec as it prints every row's, `HEVC_ALPHA`. One
  choice was left to the orchestrator, who took the NARROWER of two fill
  rules the same day and then amended its first arm, because as built it
  refused an odd size typed in the canvas's own proportions ((c) below
  says which, why, and what the amendment costs).
  (b) **The even rule (phase A).** A row is EVEN-SIZED when AVFoundation
  writes it (`avf_preset` is not null) and its codec is not `prores4444`
  (`Preset::even_sized` in `export_table.rs`): `h264`, `hevc`,
  `prores_422` and the three audio-only rows, which have no picture and go
  on listing what `h264` lists — and `hevc_alpha`. `prores_4444`, `gif`
  and `apng` KEEP an odd edge.
  A new AVFoundation row is therefore even-sized until someone exempts it,
  and `core/tests/export_size.rs` fails on a row nobody classified. On an
  even-sized row each edge is resolved on its own
  (`export_size::even_size`): below 2 it is 2, an odd edge is one SMALLER,
  an even edge is itself. The core applies it in the two places a size is
  answered: `Project::export_settings`, after the width and height are
  read (the override, else the preset's cap, else the canvas) — an image
  format is fitted as before, else an even-sized row answers the even
  pair, else the pair as asked — and `Project::export_sizes`, whose
  `document` row on an even-sized row holds the canvas evened and is named
  exactly "Document (even)" when those are not the canvas's numbers and
  "Document size" when they are. The id stays `document`; the standard
  rows are unchanged (the short edge named, the long edge to the nearest
  even integer, a tie going up); no key is added to either answer. **Down,
  because** it is the size `ExportWriter.evenDimension` already wrote on
  `h264`, `hevc` and `prores_422`, so the change moves the report to the
  file and no shipped file changes size; rounding up would hand the
  encoder a frame larger than the picture on that axis; and every listed
  row is then its own fixed point (a row's numbers sent back as `width`
  and `height` resolve to themselves). **What reports it.** The Size
  popup's title (`"\(name) · \(width) × \(height)"`), the sheet's readout
  and the size fields under a popup row, and the `export` tool's `width`
  and `height` each print the resolved pair, and each is proved
  (`hevc_alpha_proof.py`: rows R1–R4 hold the tool's answer to ffprobe's
  reading of the file, and E2 reads the popup, the readout and the two
  fields off the sheet — on a 321 × 181 document all of them say 320 ×
  180, where the build before this entry answered 321 × 181 beside a 320 ×
  180 file; the baseline recorder requires that failure before it writes,
  and its two recordings agreed on every value they kept). The queue's
  tooltip prints the same `ExportSettings` value BY CONSTRUCTION and no
  row reads it: the sheet hands its own resolved settings to
  `enqueueExport`, `ExportQueueController.Job.settings` is a `let`, and
  `ExportQueueRowView.toolTip(for:)` prints its `width` × `height`; no MCP
  tool adds a job and Add to Queue ends in a save panel.
  `ExportWriter.encodedSize` stays as the floor under any other caller and
  is the identity on what the core answers. In Custom the fields keep what
  was typed and the readout shows the resolved pair. **What does not
  move.** No stored value: `ExportChoice` keeps a row id (`document` is
  unchanged) or the typed pair, which stays as typed and resolves even on
  use; `get_project` reports the canvas and nothing about export. On an
  even canvas with no odd size asked, and on `prores_4444`, `gif` and
  `apng` on any canvas, the settings object is byte-for-byte what it was.
  Where an odd edge is evened — the Document row on an odd canvas, or an
  odd size asked for on any canvas (R4's `h264` at `[321, 181]` on 640 ×
  360) — the settings object's `width` and `height` are the even pair; the
  frame the encoder is given, the scaling mode and the picture are what
  they were; and what changes in a FILE is a bit rate computed from that
  pair. There are two. The DEFAULT, when no rate is asked, which
  `ExportWriter.defaultVideoBitrate` computes from the resolved pair: 0.25
  % lower at 1001 × 667 (2,797,200 against 2,804,201 bits per second for
  `h264` at 30 fps, by arithmetic) and identical under its 1 Mbps floor at
  321 × 181. And the rate a chosen Quality tier of the sheet sends, which
  is computed from the frame the controls ask for
  (`ExportSheetResolve.requestedFormat()`, by reading): with the Size
  popup on its first row that is the Document row's numbers, now even, so
  the tier is computed over the smaller area too — but
  `QualityTier.videoBitsPerSecond` rounds to the nearest 100 kbps, so the
  rate sent moves only where the smaller area crosses a rounding step
  (High for `h264` at 1001 × 667 is 2,600,000 either way, by arithmetic:
  2,583,871 and 2,577,420 before rounding). On another row of the popup it
  is that row's numbers, which did not move, and in Custom the TYPED pair,
  as before, even where the file is a pixel smaller. This amends
  `export_size.rs`'s earlier "a Document size that was not the document's
  size would be a lie" — the lie was a row that said 321 × 181 over a file
  of 320 × 180 — and spec §7.8's Document row.
  (c) **The fill rule.** One shape test, in integers, shared by the alpha
  guard and the scaling mode (`ExportWriter.shapeGap`; nothing else
  compares shapes). With `cw`, `ch` the canvas's rounded width and
  height (each at least 1) and `bw` × `bh` the frame the encoder is given:
  `d = bw*ch − bh*cw` and `gap = |d|`. `gap == 0` is the canvas's exact
  shape. When `d > 0` the frame is wider than the canvas's shape: a fit
  leaves `gap/ch` px of width uncovered and a fill overshoots the height
  by `gap/cw` px; when `d < 0` it is the other way round. `limit` has two
  arms. **A canvas-shaped size less at most one pixel on each axis** —
  `(bw + a)·ch == (bh + b)·cw` for some `a`, `b` in {0, 1}, which is `d`
  one of 0, `cw`, `−ch` and `cw − ch`: `max(cw, ch)` — the fit leaves at
  most a pixel OR the fill overshoots by at most a pixel. **Any other
  frame**: `ch` when `d > 0`, else `cw` — the fit leaves at most a pixel,
  which is the phase-7b guard in integers. `gap <= limit` is "within a
  pixel", `<=` and in integers on purpose: an evened canvas whose odd edge
  is the SHORT one sits exactly on the limit (181 × 320 into 180 × 320:
  gap 320, limit 320). A frame with `0 < gap <= limit` is FILLED
  (`AVVideoScalingModeResizeAspectFill`), whatever the codec; `gap == 0`
  and `gap > limit` are fitted as before (`…ResizeAspect`), and on a row
  whose `alpha` is true `gap > limit` is REFUSED with
  `alphaAspectMismatch`'s sentence instead, so an alpha row is exact or
  filled and never padded. **No size of the canvas's own shape is refused
  for being odd.** The evened Document row, and any `[width, height]`
  typed in the canvas's proportions (`w·ch == h·cw`, each edge at least
  2), is after the core's evening a canvas-shaped size less at most a
  pixel on each axis, where `gap = |b·cw − a·ch|` is never above
  `max(cw, ch)`: exact or filled at any scale, smaller than the canvas or
  larger, on every row. So the shape sentence's last clause, "or at any
  size with the same proportions", is true of both alpha rows. A typed
  size of ANOTHER shape is judged as the even frame it becomes, which is
  the size the sentence names, and the evening can carry a frame from
  within a pixel to past it: 1279 × 720 on 1920 × 1080 is filled on
  `prores_4444` (a fit leaves 0.562 px) and is 1278 × 720 on `hevc_alpha`
  (1.125 px), refused. **Why the
  fit's half is not enough alone:** an evened row can miss by more than a
  pixel fitted — 181 × 320 into 180 × 320 leaves 320/181 = 1.77 px and 481
  × 181 into 480 × 180 leaves 1.66 px — so the old test would letterbox
  those rows and refuse `hevc_alpha` at its own default size, on 6,285,314
  of the 16,769,025 canvases with both edges in 2…4096 (the first is 3 ×
  4). With the first arm the evened row (W−a) × (H−b), a and b each 0 or
  1, has `gap = |bW − aH|`, one of 0, W, H and |W − H| and never above
  `max(W, H)`: exact on 4,196,351 of those canvases, filled on 12,572,674,
  neither on none. A standard row's short edge is exact and its long edge
  within a pixel of exact, so a fit leaves at most a pixel and the second
  arm is enough: of 67,076,100 rows over the same canvases 1,961,452 are
  exact, 65,114,648 filled and none is neither, under the old test and the
  new alike. These counts are an integer sweep with no encoder, not the
  scratch writer's, swept with the two arms as written above (2026-10-05,
  the sweep's column `shaped`): the Document row's three counts and the
  standard rows' three are also what the arm phase B first built — the
  canvas ITSELF less at most a pixel on each axis, the column `tight` —
  printed beside them in the same run (no standard row's verdict differs
  between the two), and what the designer's wider first arm, every frame
  no larger than the canvas, printed in the run before. **Why the first
  arm is not every frame a fill would overshoot by at most a pixel:** a
  frame typed LARGER than the canvas to pad it (736 × 90 on 728 × 90, 2560
  × 1080 on 2558 × 1080, 402 × 100 on 400 × 100) is a picture written
  pixel for pixel between bars — measured at 402 × 100: `hevc`, `h264` and
  `prores_422` write 2 wholly black columns, both at the right, and the
  picture between is pixel for pixel (ProRes 4444's ramp: 0 of 402
  blended) — and stays one; a rule that looked only at the overshoot would
  fill it (gap 200 against 400), stretching 400 columns over 402 (312 of
  402 blended). None of those three is a canvas-shaped size less a pixel,
  so each is still past the limit, as 394 × 98 on 400 × 100 and 640 × 480
  on 640 × 360 are. **Why it is a canvas-shaped size at ANY scale** (the
  orchestrator, twice on 2026-10-05). The first decision was narrower
  than the designer's "every frame no larger than the canvas": only the
  canvas itself less at most a pixel on each axis, because the owner
  agreed to fill "at an under-a-pixel miss" and a hand-typed frame a few
  pixels inside the canvas is outside that. Built so, it REFUSED an odd
  size typed in the canvas's own proportions on `hevc_alpha` — `[720,
  405]` on 1920 × 1080 is evened to 720 × 404, gap 1920 against a limit of
  1080 — in a sentence naming a size the caller never sent and ending "or
  at any size with the same proportions", against the owner's answer that
  an odd size is never refused: 256 of the 512 sizes in 1920 × 1080's
  proportions with each edge in 2…8192 (every one with an odd edge), and
  on the built app `[400, 225]` and `[1296, 729]` on 640 × 360, with a
  typed 400 × 224 as `prores_4444` (the proof's row O5, which that build
  failed). The amended arm refuses none: 0 of those 512, and 0 on each of
  the ten canvases swept, as typed and evened alike. **What the amendment
  costs, accepted with it**, each because Swift is handed only the even
  frame and cannot tell a typed even size from an odd one the core
  evened: (1) 396 × 98 on a 400 × 100 document — the frame the first
  decision named, and also an evened 396 × 99 — is FILLED on every row
  (gap 400; a fit leaves 4 px, a fill overshoots 1) where it was scaled
  down between bars; (2) on a canvas whose ratio is a whole number, a
  frame typed that many pixels wider than a canvas-shaped size — 404 ×
  100 on 400 × 100, 2002 × 1000 on 2000 × 1000, each also an evened 404 ×
  101 or 2002 × 1001 — is filled where it was padded, or on an alpha row
  refused; (3) on the opaque
  rows an odd size typed in the canvas's proportions (`[720, 405]` on
  1920 × 1080 as `h264`, written 720 × 404) is filled where a fit left
  1.778 px to the pad; (4) on `prores_4444`, which keeps an odd edge, the
  same even frames typed as they are, and a frame one pixel short of a
  canvas-shaped size on both axes (395 × 98, 403 × 100 on 400 × 100), are
  written, filled, where the guard refused them; (5) the pixel is a large
  share of a tiny frame — `[16, 9]` on 1920 × 1080 is written 16 × 8 on
  the even-sized rows, the fill carrying one of the picture's nine rows
  past the frame, where it was refused or letterboxed. Among typed frames
  within 8 px of nine canvases (400 × 100, 728 × 90, 2558 × 1080, 1920 ×
  1080, 640 × 360, 181 × 320, 321 × 180, 321 × 181, 1081 × 1920) the
  amended arm fills, beyond the first decision's, 396 × 98 and 404 × 100
  on 400 × 100 on the even-sized rows and seven frames there on
  `prores_4444` (392 × 97, 395 × 98, 396 × 98, 403 × 100, 404 × 100, 407 ×
  101, 408 × 101), none on the other eight canvases, and letterboxes or
  refuses nothing the first decision wrote. (1) to (5) are by arithmetic
  over `shapeGap` — the same integer sweep, no encoder; what the built
  app wrote of them is O5's three files, below. The amended arm loses no
  row the sheet offers: an evened Document row is the canvas less at most
  a pixel on each axis by construction, and a standard row is filled by
  the second arm alone. **What is newly
  written:** on the opaque rows a frame within a pixel is filled where it
  was padded with black — the evened size on an odd canvas (2 wholly black
  rows or columns before on `hevc`, `h264` and `prores_422` in every one
  of four canvas classes measured, `prores_422` 1 row at 321 × 180; none
  after) and a standard row that misses by under a pixel (334 × 222 at
  `720p`, 1084 × 720: 2 black columns at the right before, none after).
  That is where `hevc` is no longer "the same file as before" (choice 12),
  and nowhere else: at an exact shape the encoder's dictionary is the one
  it was, and a frame further off is letterboxed as it was. On
  `prores_4444`, which keeps an odd edge, a typed frame one pixel short on
  one axis or both (400 × 99 and 399 × 99 on 400 × 100, 180 × 320 on
  181 × 320) is written, filled, where the phase-7b guard refused it, and
  so is a canvas-shaped size less a pixel at another scale (400 × 224 on
  640 × 360). On `hevc_alpha` an odd size typed in the canvas's
  proportions is written one pixel smaller on its odd edges. On
  the two alpha rows a fitted miss of under a pixel left an edge at the
  wrong alpha (`hevc_alpha` up to 16, ProRes 4444 255); filled, all four
  edges are 0. **On the built app** (the proof's rows, each beside the
  baseline the build before this entry recorded): a 321 × 181 and a 181 ×
  320 opaque red document at their evened sizes, as `hevc`, `h264` and
  `prores_422`, are red at both ends of the middle row and of the middle
  column where the baseline had two black pixels among those eight (B3);
  334 × 222 on white at `720p` has its last three columns white where the
  baseline's last two were black (B2); 400 × 100 at `[402, 100]` keeps
  exactly two black columns, 400 and 401, as the baseline has them (L2),
  and 334 × 222 at `[640, 640]` is letterboxed (L1); `prores_4444` at
  three sizes equals the baseline by frame digest, a kept odd edge among
  them (B4), and `hevc` on an even canvas equals it in the stream's and
  the file's fixed parameters and by frame digest (B1; its byte count and
  bit rates are printed, not compared — (h)). On the alpha rows every
  pixel of all
  four edges is alpha 0 — `hevc_alpha` at an evened 320 × 180 and 180 ×
  320 and at 1276 × 720 and 1084 × 720, `prores_4444` at 1084 × 720 and at
  a typed 180 × 320 on 181 × 320 (O1, O2, O4, P1, P2), and on 640 × 360
  `hevc_alpha` asked `[400, 225]` and `[1296, 729]`, written 400 × 224 and
  1296 × 728 as its answer says, and `prores_4444` at a typed 400 × 224
  (O5) — and both refuse
  402 × 100 on 400 × 100, and `hevc_alpha` 640 × 480 on 640 × 360, in the
  shape sentence, no file (S2, S1). Three mutants hold the rows to the rule: with the
  core's even rule and the fill switched off the size and fill rows fail;
  with the limit `max(cw, ch)` for every frame L2 and S2 fail — the two
  rows that tell the limits apart — and with every frame filled L1 fails.
  **What the fill costs, by ramp** (ProRes 4444; a pattern whose red and
  green carry the source coordinate and whose blue alternates 255 and 0,
  so a blend reads as a blue that is neither). ONE odd edge, 181 × 320
  into 180 × 320: output column 0 is source column 1 and output 179 is
  source 179, each unblended, so source columns 0 and 180 are read by
  nothing — one source pixel dropped on each side of the odd axis, two in
  all — and the 179 left are stretched over 180 (180/179, 0.56 %), 141 of
  the 180 output pixels a blend; the other axis is pixel for pixel (0 of
  320 blended). 321 × 180 into 320 × 180 is the same on its odd axis:
  columns 0 and 320 dropped, 319 stretched over 320 (320/319, 0.31 %), 249
  of 320 blended, 0 of 180 on the other axis. BOTH odd, 321 × 181 into 320
  × 180: nothing is dropped and every output pixel on both axes is a
  blend, 321 columns over 320 and 181 rows over 180. The same three
  FITTED, as before this entry: every output pixel of the picture is a
  blend on both axes, beside the black lines. So the scaler drops whole
  source pixels per side — one at an arithmetic overshoot of 1.000 px,
  none at 0.436, 0.50 or 0.624, two at 3.56 — and stretches what is left:
  the quotient `gap/cw` or `gap/ch` is the arithmetic overshoot and NOT
  the measured cut.
  (d) **The encoder.** The row is written by `AVAssetWriter(.mov)` with
  `AVVideoCodecType.hevcWithAlpha` (`"hevc_alpha"` in
  `ExportWriter.codecType(for:)`), fed the compositor's premultiplied
  32BGRA as every row is. Its compression dictionary is the HEVC row's —
  the average bit rate, the 2 s key-frame interval,
  the expected frame rate, and HEVC's 0.07 bits per pixel per frame when
  no rate is asked — plus `kVTCompressionPropertyKey_AlphaChannelMode:
  kVTAlphaChannelMode_PremultipliedAlpha`, which says what the pixels are
  (0 of 57,600 pixels differ from leaving it unset; the decoded buffer
  then reads `PremultipliedAlpha`). No
  `kVTCompressionPropertyKey_TargetQualityForAlpha` and no profile key:
  unset, the file's size and error figures are those of 0.75 — alpha off
  by at most 2 at 960 of 57,600 pixels on a hard-edged card and by at most
  5 on a soft disc — and 1.0 is exact on the card at 4,951 bytes against
  4,654 (7,029 against 5,753 on the disc); an alpha-quality control is out
  of scope. Decoded, in the scratch writer: `hvc1`, `ContainsAlphaChannel`
  1, pixels (0,0,0,0), (128,0,0,128) and (255,0,0,255) for clear, half and
  opaque red, through `ExportWriter`'s own shape (a custom compositor,
  `AVAssetReaderVideoCompositionOutput`, `append(sampleBuffer)`). On the
  built app a hard-edged opaque red card on a clear 640 × 360 canvas
  decodes with two alphas in the whole frame, 0 and 255, the corner
  (0,0,0,0) and the card's centre (255,0,0,255); the same card at half
  opacity decodes (129,0,0,128) at its centre; an opaque canvas decodes
  every alpha 255; and ffprobe says `hevc`, `hvc1`, `yuv420p` (rows A1–A4).
  AAC in a `.mov` is a combination no row wrote before: the file holds an
  `aac` stream at 48 kHz with 2 channels, and the export's loudness is
  measured as on every row (A5).
  (Amended by G-35 (e): the row's frames are un-premultiplied before the
  encoder and the key says `StraightAlpha`.)
  (e) **Hardware, and a Mac without the encoder.** This host lists "Apple
  Muxed Alpha-Apple HEVC (HW)" and "(SW)"; with hardware disabled the file
  still carries alpha (largest error 6). The row is always listed. A
  refusing encoder was measured with an encoder
  specification nothing satisfies, on `.hevcWithAlpha` and `.hevc` alike:
  `canApply` is TRUE, the input constructs, `canAdd` is TRUE, and
  `startWriting()` returns false with `AVFoundationErrorDomain` −11834
  ("Cannot Encode", underlying `NSOSStatusErrorDomain` −12908), leaving a
  0-byte file — so `addVideo`'s `canAdd` test does not catch it.
  `Exporter.encoderOutcome`, applied where `startWriting` hears the
  pipeline, maps exactly that domain and code to
  `ExportError.presetUnavailable` with the preset's name and removes the
  file, and returns every other result as it came. No new error case.
  `.hevcWithAlpha` in an `.mp4` is refused by `canApply` and `canAdd`, the
  existing `.presetUnavailable` branch. On the built app this is proved by
  a mutant, since no Mac without the encoder was to hand: a copy of the
  tree whose `videoSettings` adds that same unsatisfiable specification
  for `.hevcWithAlpha` answers `export` with exactly "This Mac cannot
  export with the “hevc_alpha” preset." and leaves nothing at the path
  (row X1), and the same copy with the mapping switched off answers
  AVFoundation's own "Cannot Encode" over a 0-byte file.
  (f) **How alpha is proved.** ffprobe reports `hevc`, `hvc1`,
  `Main`, `yuv420p` for an HEVC-with-alpha file and for a plain HEVC file
  in the same `.mov`, so `phase7_proof.py`'s `startswith("yuva")` test
  cannot see this row; only the DECODED frame tells them apart (plain
  `.hevc`: every alpha 255; the alpha file through `phase7_proof.py`'s
  `Raster` command: (0,0,0,0), (129,0,0,128), (255,0,0,255)). The proof's
  alpha rows read a transparent, a half and an opaque pixel back from the
  decoded RGBA, and its control `plain-hevc-reader` scores the same
  readers over plain `hevc` exports of the same two projects, where both
  fail.
  (g) **`RC_FORMAT_VERSION` stays 11.** No project stores a preset id or
  an export size; the remembered export choice is a `UserDefaults` record
  holding a row id or the typed pair, and a build without the `hevc_alpha`
  row leaves its Format popup where it was (`apply(_:)`'s `firstIndex`).
  Nothing persisted changes shape.
  (h) **Risks accepted.** Only this host's encoders were measured.
  Playback in Safari, QuickTime Player and Final Cut is a person's check:
  the row SE-9 of `docs/manual-checks.md`. The proof's baseline is this
  host's bytes: on another chip, macOS or ffmpeg the rows that read a
  digest (B1, B4, and G1 under `--rows size`) are not scored, every other
  row is, and the script exits 2 to say the claim is incomplete there.
  And B1 compares no byte count: the stream's `bit_rate` and the file's
  `size` and `bit_rate` are printed beside the baseline's and not scored
  — they are byte counts of a hardware HEVC bitstream, which the encoder
  does not promise to repeat — while the stream's and the file's fixed
  parameters (codec, tag, profile, level, pixel format, size, frame
  rates, frame count, colour values; container, stream count, duration),
  the alphas, the corner and frame 0's digest are compared. The row
  compared all of it until one full run on the built app printed `hevc`
  on an even canvas differing from the baseline in its stream and format
  values with frame 0's digest equal, where eight later reads of the same
  build were equal: not reproduced, and that line did not print WHICH
  values moved, so nothing here says it was those three — a frame count
  or a duration that moves still fails the row, by name. What the row no
  longer sees is a change of the encoder's rate — and on its 640 × 360
  fixture it could not see the line of `defaultVideoBitrate` this entry
  changed either: 483,840 at 0.07 bits a pixel and 967,680 at 0.14 are
  both raised to the 1,000,000 floor (arithmetic, not run).
  `tools/proof/README.md` has the runs. A
  canvas
  with an edge of exactly 1 px is raised to 2 on an even-sized row and can
  then be a different shape, where the shape sentence answers on the alpha
  rows: of the 8,192 canvases 1 × n and n × 1 with n in 1…4096 the evened
  Document row is neither exact nor filled on 4,094 ((c)'s integer sweep,
  the same under the old test, the designer's wider first arm, the arm
  phase B first built and the first arm as written), and a size TYPED
  with an edge of 1 is raised the same way (3 × 1 on 300 × 100 becomes 2
  × 2, refused on `hevc_alpha`) — not proved on the built
  app. The 481 × 181 class (both edges odd, wider than 2:1) is measured in
  the scratch writer only, and a both-odd canvas far from square (an
  arithmetic overshoot between 0.62 and 1 px) was not measured at all.
  Phase A's gate compares pixels only on canvases under the default bit
  rate's 1 Mbps floor; the 0.25 % lower default rate on a larger odd
  canvas, and a Quality tier's rate where it crosses a rounding step
  ((b)), are by arithmetic. A reader that ignores the declared
  premultiplied mode draws translucent pixels dark, **and Frame Job is such
  a reader**: `Compositor.swift` builds every video source as straight
  alpha and nothing in `app/Sources` reads a file's declared mode, so an
  exported `hevc_alpha` or `prores_4444` movie re-imported is multiplied
  by its alpha a second time (the proof's line I1 prints the composite
  and never scores it: on the built app a half-opaque red card over an
  opaque white canvas comes back (191,127,127) from the `hevc_alpha` file
  and (193,129,127) from the `prores_4444` one, where a correct composite
  is about (255,128,128); the ProRes 4444 file also holds premultiplied
  colour under a `StraightAlpha` label — a half-red source pixel decodes
  (129,0,0,128)). The export sheet's footnote is DRAWN cut before the
  word "alpha" on both alpha movie rows; its tooltip carries the whole
  line ((a)), and whether the summary gets room on the sheet's face — a
  line of its own, or a wider sheet, either a visible change to every
  format's sheet — is the owner's choice. What to do about any of the
  three is an issue's, not this entry's.
  **Amended 2026-10-09 (issue #243, issue batch B91; the owner chose a
  wider sheet, the issue's (b), and then "own line + wider", both of
  (a) and (b)):** the export sheet is 480 pt wide, 60 more than every
  other sheet (`ExportSheetController.cardWidth`), and its footnote is
  the content stack's last line, under the readout and above the buttons,
  no longer in the button row's leading slot — 436 pt of room where the
  slot beside the three buttons was 88 pt on the 420 pt sheet and 148 on
  the 480. Every row of the preset table draws its footnote whole at its
  default quality (the alpha movie rows' lines are 144 pt, ProRes 422's
  "PRORES422 · MOV" 90, which the 88 pt slot also cut), and so do the
  footnotes a Quality tier and a loudness target lengthen: "H264 · MP4 ·
  900 kbps · 256 kbps audio" (228 pt) and `hevc_alpha` at Maximum with −14
  LUFS (378 pt), which the 148 pt slot cut. `hevc_alpha_proof.py` E1 and
  E3 hold it: E1 and E3's first form were red on the 420 pt sheet, and E3
  as it stands (the long footnotes and the own line scored) on the 480 pt
  sheet with the footnote beside the buttons. (a)'s and (h)'s sentences on
  the cut footnote describe the 420 pt sheet.
- **G-34 — A graphic's props are action targets: a number and a colour
  ramp, a string, a boolean and an enum switch at the action's end, an
  asset is refused; supersedes G-10's first sentence and its error, and
  amends G-32 (e)** (issue #239, 2026-10-07, issue batch B87; the owner's
  seven answers, each "as recommended", are (b), (d), (e), (f), (g), (i)
  and the limits, and the owner's answer on the paste is (d)). G-10's
  layer half stands, and so does G-32 (h): `graphic` is not a
  `patch::Group`; the action door has its own graphic arm.
  (a) **The shape.** An action's `end` may carry `graphic: {props: {<key>:
  <value>}, kinds: {<key>: <type>}}`. `set_action_end` writes each named
  prop's schema `type` into `kinds` and removes it with the prop. A
  `kinds` in a patch is read and DISCARDED, whatever it holds, because
  every named prop's kind is rewritten from the schema; so an end read
  back from `get_project` can be sent again, and a caller never decides a
  kind (G-4). `name`, `width`, `height`, `in` and `length` are errors
  (`graphic.<key> is not an animation target; an action animates
  graphic.props`); any other key is an unknown key.
  (b) **Which kinds move (answers 1 and 2).** A `number` and a `color` ramp
  along the action's curve. A `string`, `boolean` and `enum` hold their
  start and take the end's value at the action's END, as every
  non-numeric property does (§5.4). An `asset` is an error naming the prop
  (`graphic.props.<key> is an asset; an action does not animate an image —
  set it with set_graphic`).
  (c) **How the kind is known, and the check.** From the `schema` the op
  carries. The app fills it from the module's CURRENT revision and never
  takes it from a caller (G-4; a `.filledByTheApp` row). A non-null prop
  with no schema is an error naming it (`graphic.props.<key> needs its
  module's schema to animate, and none came with the op`). A prop the
  schema lacks is `unknown key "graphic.props.<key>" in an action end
  patch`. Every value is checked as `set_graphic` checks it (type,
  `min`/`max`, options, length, a colour normalised) and refused under
  `graphic.props.<key>`. This is the one end that IS range-checked (§5.4's
  ends are not), because nothing clamps a prop: the engine reads no
  `min`/`max`, and `clamp_video` never sees `graphic`. Every curve is
  monotone (§5.4), so a ramp between two in-range ends stays in range.
  Only the props a patch names are checked; a stored end is never
  re-checked. So when a module later narrows a range, a project holding an
  old end still opens and renders as stored (the module is handed the old
  value, as it is a stored base prop), an edit naming another prop of that
  end is not refused, and only a new value for that prop is checked. The
  evaluator knows a colour by `kinds`, never by a value's shape; two numbers
  ramp whatever `kinds` holds, which is how a version-12 end ramps its
  numbers ((k)).
  (d) **The start (answer 4).** The first time an action names a prop that
  the clip's own `graphic.props` does not hold, the schema's CURRENT
  default (a colour normalised) is appended to it in the same edit, so in
  the same undo step. A later change to the module's default does not move
  it. The start is kept in two places it would otherwise be lost.
  G-15 (b)'s "A value equal to the schema's default is written as `null`"
  gains one exception in the core: `set_graphic` with a schema answers a
  `null` for a prop that
  an action on that clip names by storing the schema's default; without a
  schema, or for a key the schema lacks, a `null` still removes. And
  G-32 (e) is amended (the owner's answer, 2026-10-07): Paste Graphic
  Properties, and `paste_attributes`' `graphic` group, KEEP a target key
  the payload lacks when an action on the target names it, in its slot,
  so the ramp survives the paste. Every other key pastes as G-32 (e) says.
  (e) **Numbers arrive fractional (answer 5)**: `a + (b − a) × eased` in
  floating point, never rounded and never snapped to `step`, so two whole
  ends 64 and 129 give 96.5 halfway. A module that needs a whole number
  rounds it. A module written before this entry that does
  `new Array(props.count)` throws on a fraction and draws its error card
  for those frames (G-8), which stops an export.
  (f) **Colours blend channel by channel (answer 6)**, as every colour
  action already does (the model's `[r, g, b, a]`, element by element).
  The red, green, blue and alpha of the two `#rrggbb[aa]` strings (no alpha
  is 255) each interpolate STRAIGHT, not premultiplied: `#00000000` to
  `#ffffff` is `#80808080` halfway. Each channel is rounded to the nearest
  byte and the result written as G-12 writes a colour (`#rrggbb` when the
  alpha is 255). Not OKLab.
  (g) **Playback (answer 7).** Nothing is built. Every frame of an
  animated prop is drawn at the recorded per-frame cost, so a graphic that
  had settled misses its texture for the action's span. A
  `docs/manual-checks.md` row watches a 4K clip with an animated prop for
  stutter. #127 stays deferred.
  (h) **Evaluation.** Each finished action's `graphic.props` is laid over
  the clip's map in start order, then the spanning action's are
  interpolated. `clip_state` answers the result as `graphic` beside
  `shape`, and the recipe's `props` and `props_json` (and so its hash,
  G-9·b) are those values. The texture key, the export pin (G-13) and the
  prefetch (G-26) do not change. The evaluator is total. Two values of
  different JSON kinds, a colour it cannot read, a malformed `graphic`,
  `props` or `kinds`, and a prop with no start (removed by a `set_graphic`
  without a schema, or a hand-written end) all hold, then switch at the
  end; no frame fails.
  (i) **Edits.** `split` gives the second half the props evaluated at the
  cut, and gives a straddled action's first half an end of those values,
  so a split is invisible: a number exactly on a linear curve (to
  floating-point rounding), a colour to within one byte per channel, and
  on an eased curve at its ends, as for every property. `trim_start` and
  `roll` touch an action's span, never its end; an op under `scope` acts
  on the nested clip as on any other; `rate_stretch` and `set_speed` are
  media-only. `get_project` shows an end as stored, `kinds` included. The
  inspector edits an end as it edits every animated property (CI-1, CI-2,
  CI-6, CI-7, CI-9): the Graphic tab stops being the exception (answer 3).
  (j) **Removing.** `graphic: null` and `graphic.props: null` remove the
  group from the end. A `null` prop removes the prop and its kind,
  unchecked, so a stale key can go. `off` cannot name `graphic` (`graphic
  props cannot be keyed off; name the value a prop ends at in patch`).
  `video.motion` and `text.words` stay errors in their own sentences (W-6).
  (k) **Format version 13**, so an older build refuses the file instead of
  drawing it un-animated. There is no migration step: an end is stored as
  found. A file of version 12 or older whose end already names `graphic`
  (hand-written or pasted; G-10 kept it inert) now animates by these
  rules, its colours switching at the end for want of `kinds`.
  (l) **The Graphic tab** (issue batch B87 phase 3, 2026-10-07). With an
  action of a graphic clip selected, the Properties rows show the selected
  action's END state (`clip_state`'s `graphic`, CI-2), and a row's write is
  ONE `set_action_end` naming `graphic.props.<key>`, carrying the module's
  current schema, filled by the app ((c)). The end takes the value itself,
  never `null`, because a `null` in an end removes ((j)); G-15 (b)'s null
  rule stays the base's. An asset is the base's: its row writes
  `set_graphic` as before, marked ⊘ and still changing the clip, the way
  CI-3 sends a structural write to the base. With no action selected every
  row writes `set_graphic`, as before. The owner's answers, all as
  recommended: a keyed string row's one-line field narrows by about 35 pt
  and reads "at end" only while the selected action keys it, and is full
  width otherwise (O1); a key the end names that its module no longer
  declares gets a stale row of its own — ◆, the end's value and ⌫ ("The
  module no longer declares <key> — remove it from action N") — beside the
  clip's own stale row for that key (O2); a graphic action's band is
  labelled with the prop keys its end changes ("accent, size"), and an
  end's empty `graphic.props` does not stop a zoom being one (O3); the
  Graphic sub-tab's and the Properties section's `◆N` count the keys of the
  end's `graphic.props`, a stale key included (O4, CI-6 amended); the Text
  tab's keyed Content row reads "at end" (O5). Two follow from answer 3
  with CI-7 and CI-9: with an action selected, Width, Height and Follow
  Clip show ⊘, since their writes never reach `set_action_end` and (a)
  refuses those keys in an end (O6); and Properties' Reset writes the end
  through the same split, each declared prop's default into the end and an
  asset's `null` to the base (O7). ◇, Clear, the gutter's ×, the row menu's
  "Set end value to default", the slider's mint segment and coral playhead
  tick are the shared pattern (CI-6, CI-7, CI-9), not new rules.
  **A row short of room: the CONTROL gives way, never the tag** (O8, on
  every tab). Every row's "at end" / "now …" tag is one line
  (`InspectorRowTag.maximumNumberOfLines = 1`): a wrapping tag gave its
  width away by growing tall, so a row short of room squeezed it into a
  sliver instead of narrowing a control. What gives way is fixed by
  priority, below the tag's compression resistance (750): the one-line
  string field (≤ 170 required, == 170 at 249, O1) and, in `inspectorRow`,
  the row's widest pop-up, or in a row with no pop-up its widest checkbox
  (its intrinsic width held at 749). A row with room is untouched; the rows
  the tag leaves short at `DS.panelWidth` are Font ▸ Family (150 → 140), a
  filter's kind (92 → 74), an obscure region's kind (96 → 74) and a
  module's boolean whose label is longer than about 200 pt (its title
  cut at the checkbox's edge), each narrowing only while keyed and full width
  otherwise (`graphics_inspector_proof.py` K18a, K18b, K18c).
  **Limits accepted (answer 3).** A clip's actions do not overlap, and one
  action has one span and one curve for everything it animates. There is
  no per-prop opt-out: a module's own animation composes by being handed
  that frame's value. A prop that a later revision renames or drops stays
  in the end, and the engine passes it through with a warning. `kinds`
  goes stale only if a module changes a prop's type.
- **G-35 — A video frame is composited as premultiplied only when its
  buffer says so, and every other frame, an unlabelled one included, as
  straight; the two alpha movie rows are written STRAIGHT — each frame
  un-premultiplied, its transparent pixels' colour filled from the
  nearest visible pixel within 4 px, and labelled `StraightAlpha` —
  so a re-imported export composites to the right colour; amends G-33
  (d) and the reader sentence of G-33 (h)** (issue #242, 2026-10-09,
  issue batch B92, phase 2).
  (a) **Whose choice.** #242 offered two ways, reading the declared mode
  on import or un-premultiplying before encoding. The owner, 2026-10-09:
  "I think we should do both. Compensate for other apps, but export
  straight." And: "We're not using Reelcut in any real work yet, so we
  don't generally need to worry about old files."
  (b) **Import.** `Compositor.swift`'s track source asks
  `MetalRenderer.declaresPremultipliedAlpha` about each frame
  `request.sourceFrame(byTrackID:)` hands it: true only when the
  buffer's `kCVImageBufferAlphaChannelModeKey` attachment equals
  `kCVImageBufferAlphaChannelMode_PremultipliedAlpha`; absent or anything
  else is straight, so an unlabelled movie draws as it always did. The
  answer is the layer's existing `premultiplied` uniform, which
  `layerSample` already divides by, as it does for a text, shape, image or
  graphic texture: no uniform and no shader code changes. It is asked per
  BUFFER, not per file: the decoder attaches the mode to the frames it
  hands over ((f)), and no format description is read for it (a
  synchronous `formatDescriptions` would be a fifth deprecation, and
  `async` stays where W-8 put it). This fixes a premultiplied movie from
  another application (After Effects, Motion) as well as an `hevc_alpha`
  file made before this entry.
  (c) **Export.** On the two rows `ExportWriter` writes whose `alpha` is
  true — `prores_4444` and `hevc_alpha`; `apng` is `ImageSequenceWriter`'s
  and is unchanged — the video pump straightens each frame after the
  reader hands it over and before it is re-timed
  (`ExportStraightAlpha.straighten`): in place on the reader's own copy of
  the 32BGRA buffer, every pixel with a > 0 becomes
  c' = min(255, (c·255 + ⌊a/2⌋) / a) in integers, and the buffer is
  wrapped in a new sample whose format description is made from it. The
  division is exact for 8 bits: re-premultiplying with (s·a + 127) / 255
  gives back c for every one of the 32,895 pairs 0 ≤ c ≤ a, a in 1…255
  (R0, (f)). The rows are split over `DispatchQueue.concurrentPerform`
  inside the video pump. A frame that cannot be straightened (not
  32BGRA, not lockable, no sample made) stops the export with "A frame's
  transparency could not be written straight."
  (Amended by PR-3: the reader's frames are `64RGBAHalf`. `prores_4444`'s
  frame is un-premultiplied in place in float, s = min(1, c/a) for a > 0,
  then filled by (d)'s rule over its half-float pixels; `hevc_alpha`'s is
  first rounded to 8-bit premultiplied BGRA, round(v·255), into a pooled
  32BGRA buffer and then straightened by this paragraph and (d) unchanged.
  A frame in neither format stops the export with the sentence above.)
  (d) **The fill.** Un-premultiplied, a transparent pixel is black at
  alpha 0, and a codec that subsamples colour (HEVC's 4:2:0) or a scaler
  that resamples the frame (the writer's own, at a size off the canvas)
  can carry that black into a half-transparent edge pixel beside it: a
  dark fringe on a straight file. So a pixel with a = 0 within Chebyshev distance
  `ExportStraightAlpha.bleedRadius` = 4 px of a pixel with a > 0 takes
  that pixel's straightened colour — the nearest by dx² + dy², a tie
  going to the first in row-major order — and keeps alpha 0; every other
  a = 0 pixel is left as it was. The nearest is found without walking the
  square: pass 1 records, per row with a visible pixel, each column's
  nearest visible pixel in that row (its smallest |dx| ≤ 4, a tie to the
  left), and a transparent pixel reads that entry in each of the 9 rows of
  its band, top to bottom, keeping only a strictly smaller dx² + dy² — the
  same pixel the sorted square named (issue batch B93 phase 2, #254; K1
  holds the two byte-identical). The fill reads only pixels with a > 0,
  which it never writes, so in place is race-free. A band of rows with no
  visible pixel within 4 rows is skipped whole. The fill changes no alpha
  and no visible pixel, so a reader that composites straight colour by
  its alpha draws the same picture with or without it; what it changes is
  the colour the codec averages into an edge ((f), F1).
  (e) **The labels.** Each straightened buffer carries
  `kCVImageBufferAlphaChannelModeKey` = `StraightAlpha`
  (`.shouldPropagate`), which the ProRes 4444 encoder writes into its
  file, and `hevc_alpha`'s `kVTCompressionPropertyKey_AlphaChannelMode`
  is `kVTAlphaChannelMode_StraightAlpha` where G-33 (d) set
  `PremultipliedAlpha`. Decoded, either row's frame reads `StraightAlpha`
  (M1).
  (f) **The figures** (2026-10-09, Apple M2 Max, macOS 26.5.1, ffmpeg
  9.0.2; `tools/proof/hevc_alpha_proof.py` on the gate's Release build,
  39/39 with the phase review's F2 and Q1, and its mutants on Debug copies; the probe is
  `tools/proof/alpha_mode_probe.swift`). **I1:** FAINT's half-opaque red
  card, re-imported over an opaque white canvas, composites (255,128,128)
  from the `prores_4444` file and (255,127,127) from the `hevc_alpha` one,
  where G-33 (h) recorded (193,129,127) and (191,127,127); the files' own
  centres decode (255,0,0,129) and (255,0,0,128) (A2's is the second).
  **M1:** the first decoded frame of either file reads `StraightAlpha`,
  and so does its track's format description. **T1:** the probe's
  premultiplied (128,0,0,128) card labelled `PremultipliedAlpha` — a
  third-party writer's file, decoding (129,1,0,128) from ProRes 4444 and
  (128,0,0,128) from HEVC with alpha, both labelled `PremultipliedAlpha`
  — composites (255,129,127) and (255,127,127); with the helper answering
  false (mutant `import-straight`) the same files composite (193,129,127)
  and (191,127,127). So the decoder's attachment reaches
  `request.sourceFrame(byTrackID:)`. **T2:** an unlabelled (255,0,0,128)
  ProRes 4444 card decodes `StraightAlpha` and composites (255,128,128).
  **F1:** a red 200 × 200 disc on a clear canvas, exported, re-imported over
  white and compared with the same disc drawn on white over all 230,400
  pixels: the largest channel difference is 1 on `prores_4444` and 18 on
  `hevc_alpha` (2 pixels over 10). Without the fill (mutant `no-bleed`) it
  is 2 and 100 (324 pixels over 10 on `hevc_alpha`, the worst (155,31,30)
  against (255,3,3)): at the document size the fill is what keeps an
  HEVC edge from darkening, and ProRes 4444's 4:4:4 colour does not need
  it. **F2** (off the canvas's size, through the writer's scaling): the
  same disc exported at `720p` (1280 × 720, ×2) and re-imported over white
  at that size, where a red disc keeps red at 255 at every pixel: red falls
  at most 0 on `prores_4444` and 2 on `hevc_alpha`; without the fill 26 and
  45 — a scaled export needs the fill on BOTH rows. Against the same disc
  on white exported at `720p` as `prores_4444` (an opaque frame through the
  same scaler) the edge differs by up to 73 and 75 in a ring of about
  3,100 pixels, which is not a fringe: the scaler resamples a frame's
  alpha apart from its colour, and down column 640 the alpha file's top
  edge reads alpha 51, 203, 255 where the opaque file's coverage reads
  0.09, 0.51, 1 — the alpha edge sits about a third of a pixel outside the
  opaque one. **Q1:** the first cached thumbnail — the JPEG
  `AVAssetImageGenerator` and CoreGraphics make, which the filmstrip and
  the Media tab's row draw — of I1's two straight files, T1's two
  premultiplied-labelled ones and T2's unlabelled one reads (255,127,126)
  at the card's centre for all five: half red over white, the label
  honoured by the generator with no change here. **R0:** 0 mismatches of
  the 32,895 pairs; the 16 × 16 fill exact; the tie to (4,8). **Speed**
  (B93 phase 2, 2026-10-09, Apple M2 Max, macOS 26.5.1, on a host other
  sessions loaded, `vm.loadavg` 25 then 11 over the run;
  `--measure straighten-speed`: the probe built `-O` with whole-module
  optimisation, as the Release app is; 12 cores; best of five, the fill
  before B93 timed on the same frames in the same run, alternating): an
  opaque card on a clear frame 0.53 ms at 1920 × 1080 and 0.87 ms at
  3840 × 2160 (before B93 0.56 and 0.71 ms); soft alpha at every pixel
  (pass 1 divides them all) 0.81 and 2.98 ms (0.86 and 2.87 ms); one
  visible pixel in every 9 × 9 block (pass 2's worst case, nearly every
  pixel transparent and within reach) 0.88 and 3.33 ms (14.78 and
  59.16 ms; B92 recorded 15.1 and 61.4 ms). **K1** (B93): the fill and the
  one before it give the same bytes, padding included, over 65 seeded and
  lattice frames and all 3,160 pairs of visible pixels around a
  transparent centre, 216 of them ties.
  The unoptimised probe takes 33–41 ms for the 1080p card frame. B4:
  `prores_4444`'s sizes and sampled alphas equal the baseline's, and its
  frame digests moved, as (c) and (d) intend.
  (g) **`RC_FORMAT_VERSION` is unchanged and nothing is migrated.**
  Nothing persisted changes shape. An `hevc_alpha` file written before
  this entry is labelled premultiplied and now composites right on import
  ((b)); a `prores_4444` file written before it holds premultiplied
  colour under a straight label and still composites dark. It is not
  relabelled or re-encoded: the owner's answer in (a).
  (h) **Risks accepted.** The writer's own scaling
  (`AVVideoScalingModeKey`) of a straight frame was measured at one size
  off the canvas, ×2 (F2: no fringe with the fill), and its alpha edge
  lands about a third of a pixel from where an opaque row's does; a
  downscale was not measured. A reader that scales the file down by more
  than about 4× or blurs it further than the fill reaches can still pull
  black into an edge. A frame of scattered visible pixels costs pass 2
  the most: 61 ms at 3840 × 2160 in the optimised build, nearly twice a
  30 fps frame's time, so such a 4K export runs slower by up to that much
  a frame; a title, a card or soft alpha costs under 3 ms. Thumbnails,
  filmstrips and poster frames go through CoreGraphics, not (b), and
  draw both labels right (Q1). Only this host's
  encoders and decoders were measured; playback of either row in Safari,
  QuickTime Player and Final Cut is a person's check (`docs/manual-checks.md`
  SE-9). G-33 (h)'s sentence that Frame Job is a reader that ignores the
  declared mode, and its I1 figures, describe the build before this entry.
- **G-36 — Playback rasterizes upcoming graphic frames ahead on worker
  threads too; the compositor stays the one consumer and the texture key
  decides** (issue #127, G6 phase 2, 2026-10-21; amends G-26 (a)).
  (a) **Where.** On the document's own key, while the transport's rate is
  above 0, the project draws a graphic clip (on the timeline or in any
  nest), the switch is off and an item is built
  (`Playback+Prefetch.swift`'s `syncPrefetch(from:)`). Never while paused,
  in reverse, for `render_frame`, or on an export's key.
  (b) **The grid.** A session starts at its start time — the seek's
  target when a seek starts it, else the playhead — snapped down onto the
  composition's frame grid from 0, at the built composition's
  `frameDuration`. It ends at the in/out range's end while playback loops
  inside that range, else at the composition's end.
  (c) **Restart.** Play, a seek (at its target, a loop's return included),
  an item swap and a property-only edit while playing each stop the
  session and start a fresh one. Pause, a rate of 0 or below and
  `invalidate` stop it.
  (d) **Follow.** Every compositor request reports its time
  (`GraphicPrefetch.reach`). A worker never claims a frame at or before the
  last one the compositor reached; the frames it passes over are counted
  `skipped`. A held raster of a frame before the reached one is dropped as
  unused, freeing its room. A request outside the session's range is not
  followed, and a seek's session (a loop's return included) follows
  nothing until a request lands in its first four frames: a seek installs
  the new session before AVFoundation cancels the old position's requests,
  and those served in between must not move the new one's floor.
  (e) **Bounds.** G-26 (d)'s, per session: `activeProcessorCount − 1`
  workers, `4 × workers` slots and 1 GiB of rasters. An export running
  alongside has its own session. **The owner's choice** (2026-10-21): first
  the same limits as an export's, with no setting; then, shown the
  measurement below, no fixed limit at all — memory limits are relative to
  the Mac (one budget of 25 % of physical memory, given back under memory
  pressure; 16 GB is the floor, 32 GB the usual machine), and drawing ahead
  while paused is a setting, as in Final Cut. #127's next phase replaces
  this paragraph's 1 GiB and slot count, and G-26 (d)'s, with that budget.
  Until it lands the bounds below stand. **What the bound holds, and
  what it does not:** the 1 GiB and the slots bound only the finished
  rasters HELD ahead for the compositor. Outside them are each worker's
  raster in flight (its output and the images it decodes, one per worker
  at a time) and the freed large blocks the system allocator keeps
  resident after them, which stay counted in the process's memory after
  the play until the system needs them. Measured on parive-promo's
  `section` scene (Release, 12 cores, 11 workers, 2026-10-21, fix pass 1's
  instrumented copy): the held rasters peaked at 373 MB in 53 slots, under
  the bound (the slot limit binds first; a frame's layers go in together,
  so the count can pass `4 × workers` by a frame's worth); live large
  allocations were 855 MB in mid-play, the allocator's kept free blocks
  602 MB then and 939 MB after; the process's footprint rose from 366 MB
  to a peak of 2.07 GB while playing (the serial path, the switch on:
  116 MB to 392 MB) and stood at 1.24 GB after the play (serial: 499 MB).
  (f) **The switch.** `FrameJobGraphicPrefetchOff` turns both off.
  (g) **Purity.** G-26 (c) holds unchanged, so every preview frame is the
  serial path's bytes (G-5). A wait that `stop` ends counts as neither a
  hit nor a mismatch. In a following session, a slot the worker left to
  the compositor's pool (the same-texture shortcut) that reaches `take`
  counts `missed`, because playback may have dropped the earlier frame
  whose raster the pool was to hold. The session's log line is an
  export's with `, playback from <start>, <skipped> skipped` appended.
  (h) **Preview Quality.** It does not shrink a graphic's raster (G-7), so
  Quarter gains little: measured on parive-promo's `section` scene (clip 8
  from tick 25 120 000, 10 s, Release, 12 cores, 2026-10-21), the share of
  frames composed was 0.115 at Full and 0.112 at Quarter with the switch
  on, and 0.279 at Full and 0.325 at Quarter with the prefetch
  (`designs/adr/roadmap-10-graphics.md`, "G6 phase 2").
  (i) **Risk accepted.** While playing, a graphic's JavaScript runs twice
  per frame, and up to all cores but one are busy. A restart wastes the
  rasters in flight. `cancelAllPendingVideoCompositionRequests` can wait
  up to one raster on a `take`, no longer than the serial path's own
  raster.
  **Amended by G-37**: (e)'s `4 × workers` slots and 1 GiB are replaced by
  G-37 (a)'s one budget; a document also keeps the frames it drew (G-37
  (c)).
- **G-37 — Graphic rasters share one memory budget, a quarter of the Mac's
  physical memory; a document keeps the graphic frames it drew** (#127, G6
  phase 3, 2026-10-21; amends G-26 (d) and G-36 (e)).
  (a) **Budget.** `ProcessInfo.physicalMemory / 4` for the whole process
  (4 GB on 16 GB, 8 GB on 32 GB). It covers every session's held rasters
  (export and playback) plus the kept frames. A worker waits while the
  held rasters of all sessions reach it. The kept frames give way, least
  recently used first. The `4 × workers` slot count is gone: bytes decide
  how far ahead workers go, under a bookkeeping ceiling of 1,024 entries
  per session that also bounds entries holding no bytes (a deferred or
  kept-texture skip), so a static graphic cannot run the workers to the
  range's end. The kept frames never exceed the room the held rasters
  leave: every change to either trims them to `max(0, budget − held)`.
  Outside the budget, as G-36 (e) measured: rasters in flight and the
  allocator's retained blocks. **The owner's choice** (2026-10-21): limits
  relative to the Mac; 16 GB is the floor.
  (b) **Pressure.** A `DispatchSourceMemoryPressure` sets the budget:
  warning halves it (physical / 8) and trims the kept frames to fit;
  critical sets it to 0, empties the kept frames, and lets no worker
  claim, so preview and export draw serially; normal restores it. Held
  rasters are still served.
  (c) **Kept frames.** Only a `Playback`'s key keeps frames (registered in
  its `init`); exports, `render_frame` and thumbnails never keep, so G-26's
  export is unchanged. Kept under its texture key: each raster the
  compositor used (a worker's or its own), and each finished raster a
  worker made for that key when it leaves its slot (taken, passed by
  `reach`, dropped by `remove` or `stop`). On a pool miss `take` answers
  from the kept frames before any slot, with no session needed (a paused
  scrub). A worker whose texture key is kept rasterizes nothing
  (`deferred`, G-36 (g)'s `missed` rule). `invalidate` drops the key's kept
  frames, and so does the document's `close` (`stopGraphicStore`), which a
  window controller still retained cannot delay as it delays the editor's
  deinit (measured: an idle app kept a closed window's frames for 40 s, until
  another window opened); `deinit` unregisters it.
  (d) **Purity.** A raster is a function of its texture key: the SVG text,
  the size and the library version, which is a content hash
  (`GraphicStore.swift`). So a kept raster is the serial path's (G-26 (c),
  G-5). Its warnings ride with it (G-8).
  (e) **Switches.** `FrameJobGraphicKeepOff` (YES) keeps nothing. It is a
  measurement switch, not a setting, and is independent of
  `FrameJobGraphicPrefetchOff`.
  (f) **Risk accepted.** Up to a quarter of memory stays held after a
  play, until the window closes, pressure arrives, or newer frames push it
  out. #127's next phase adds drawing ahead while paused as a setting.
