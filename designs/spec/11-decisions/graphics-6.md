# Spec §11 — decisions: Graphics, the rasters' memory budget onward (road map 10)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the G- series of [`graphics.md`](graphics.md), so a citation never has to say which
file. This file holds G-37…G-45. G-46 on are in [`graphics-7.md`](graphics-7.md). It is new because
`graphics.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries moved here
unchanged, and an "above" or "below" in one may now point into a sibling file.

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
  **Amended by G-38**: the kept frames are also filled while paused;
  frames a pass drew ahead give way last; a pool hit touches its kept
  frame.
  **Amended by G-39**: the engine's decoded-image cache is sized from this
  budget, `budgetBytes / 16` at the level in force, beside it.
- **G-38 — Graphic frames are drawn ahead while paused once the person has
  left Frame Job alone: Settings ▸ Playback ▸ Background render, on after
  5 s by default, as Final Cut's** (#127, G6 phase 4, 2026-10-21; amends
  G-36 (a) and G-37 (c)).
  (a) **The setting.** Settings' fourth pane, "Playback", holds a
  "Background render" checkbox (on) and "Start after [N] seconds" (1–60,
  default 5), stored in `FrameJobBackgroundRender` and
  `FrameJobBackgroundRenderDelay`. It is a person's setting like AI-11 and
  R6-12: no tool reads or writes it, and it has no MCP mirror. A proof sets
  it in the argument domain and writes nothing. The owner (2026-10-21):
  "should be configurable (same as Final cut)"; "On, after 5 s
  (Recommended)". With four panes Settings is taller than a 1440 × 900
  display leaves, so its panes sit in a scroll view capped at the screen's
  visible height less the title bar; on a taller screen nothing scrolls.
  (b) **Idle.** These events restart the clock: any key, modifier, mouse
  button, drag, scroll or trackpad gesture event the app receives (pointer
  motion alone and events in other apps do not count); every edit of any
  document (`.projectDocumentDidChange`, live ticks included); every play,
  pause, rate change and seek of any transport (`syncPrefetch`). Each
  restart stops the running background session at once. An agent's call
  counts only when it edits or moves a transport.
  (c) **What is drawn.** At the delay, the document whose transport last
  moved starts a background session if all of these hold: it is paused, it
  is built, it draws a graphic, it is still open, and no window plays —
  forward or in reverse, with graphics or without. If it is seeking,
  restoring or rebuilding, or any window plays, the clock runs again. The grid and range are G-36 (b)'s, from the playhead.
  Workers are `activeProcessorCount − 1` threads at utility QoS. One
  background session runs at a time, and a play's session ends it. Each
  finished raster goes straight into the kept frames, marked as drawn
  ahead. A texture key already kept is touched, marked, and not drawn; one
  an earlier frame of the pass is still drawing is not drawn either, and
  that frame's mark serves the later frame too. While a pass runs, Frame
  Job opts out of App Nap: a `ProcessInfo` activity
  (`userInitiatedAllowingIdleSystemSleep`, so idle system sleep is still
  allowed) begun with the pass and ended when it ends, so it keeps drawing
  while Frame Job is hidden or behind other windows. The owner
  (2026-10-21): "Keep going (Recommended)". The session ends `done` when
  its range is done. It ends `full` when its
  marked frames plus every session's held rasters reach the budget; older
  unmarked kept frames give way first. It ends `stopped` on activity, close
  or `invalidate`. Its log lines read `[framejob] graphic background: key
  K, from T, started` and, once at the end, `[framejob] graphic
  background: key K, W workers, from T, F frames with graphics, D drawn, A
  already kept, B bytes kept, done|full|stopped`, B being the marked
  frames' bytes.
  (d) **The play that follows.** Marked frames give way last. A play from
  the pass's own grid start does not push them out: its workers wait while
  the held rasters plus the marked frames reach the budget. A frame stops
  being marked once the compositor passes it. Every mark clears when that
  play stops, when a play starts anywhere else, or when a new pass starts.
  `graphic_memory` answers the marked bytes, the marked frames a trim
  pushed out since its last answer (`ahead_evicted`, 0 while the rule
  holds) and whether a pass holds the App Nap opt-out.
  (e) **Switches.** Only a keeping key draws in the background, so
  `FrameJobGraphicKeepOff` and `FrameJobGraphicPrefetchOff` turn it off
  too; under either, or with the setting off, the clock waits for the next
  activity instead of running again. The measurement proofs launch with
  `-FrameJobBackgroundRender NO` unless they measure it.
  (f) **Purity.** A kept raster is the serial path's (G-37 (d)), so
  drawing ahead changes when a frame is ready, never its pixels.
  (g) **Phase 3's review.** A pool hit touches its kept frame, so a graphic
  held on screen is not the first one evicted. `heldEntries` counts only
  entries that hold bytes.
  (h) **Risk accepted.** While idle, up to all cores but one are busy at
  utility QoS, even while Frame Job is hidden, and memory up to the budget
  is held. A pass covers only what
  lies after the playhead. The mouse-and-keyboard path is a person's check
  (GR-11).
- **G-39 — A graphic's PNG and JPEG assets are kept as stored PNG copies
  that decode to the same pixmap, in one process-wide cache keyed by
  content and sized from G-37's budget** (#127, G6 phase 5, 2026-10-22;
  amends G-37).
  (a) **The copy.** On the first frame that draws a PNG or JPEG asset, the
  engine (`graphic/src/images.rs`) decodes it once and writes its straight
  RGBA8 as an RGBA PNG at 8 bits, stored (`DeflateCompression::NoCompression`)
  and unfiltered (`Filter::NoFilter`). A PNG is decoded by png 0.18 with
  `normalize_to_color8`, Rgb, Grayscale and GrayscaleAlpha expanded to RGBA
  exactly as tiny-skia 0.12's `Pixmap::decode_png` expands them; a JPEG by
  resvg 0.48.1's own `decode_jpeg` (zune-jpeg, RGBA out). Any other colour
  type, or a JPEG that does not answer RGBA, is refused and keeps the
  original route. The copy is used only if `Pixmap::decode_png` of it
  equals `Pixmap::decode_png` of the PNG (width, height and data), or the
  JPEG's RGBA, and `imagesize::blob_size` of the original is the copy's
  size, which usvg reads at parse. resvg is unchanged and decodes the
  copy. GIF, WebP and SVG assets never reach the cache.
  (b) **Key.** The SHA-256 of the asset's own bytes. A replaced asset, a
  rebuilt library or a renamed one can never draw a stale copy, and
  identical bytes share one copy across libraries.
  (c) **Limit.** `budgetBytes / 16` at the level in force: physical/64 at
  normal (256 MB on 16 GB, 512 MB on 32 GB), physical/128 at warning, 0 at
  critical, which empties the cache. It is set at launch and on every
  pressure change, simulated ones included (`rc_graphic_image_cache`). It
  sits beside G-37's raster budget, as the rasters in flight do; this
  follows the owner's standing rule (2026-10-21) that limits are relative
  to the Mac and share or are sized from G-37's budget. The engine's
  default is 0, so a process that never sets it caches nothing. Three
  test binaries set a positive limit: the cache's own
  (`graphic/tests/image_cache.rs`, serialised); the ignored bench
  (`graphic/tests/image_bench.rs`); and `core/tests/graphic_ffi.rs`, whose
  one cache test sets 64 MiB and then 0 while the binary's other tests run
  in parallel threads, none of which draws an image asset, so nothing else
  there reaches the cache. Every other test binary caches nothing. Copies are trimmed least recently used
  first. `graphic_memory` answers `image_cache_bytes` and
  `image_cache_limit`.
  (d) **Switch.** `FrameJobGraphicImageCacheOff` (YES) sets the limit to 0.
  It is a measurement switch, not a setting.
  (e) **Purity.** The copy is used only when it decodes to the original's
  pixmap, so every frame is the serial path's (G-5, G-26 (c)), and
  `graphic/tests/pins.json` is unchanged.
  (f) **No rebuild loop.** A copy that does not fit, alone or after an
  eviction, is remembered by its size and drawn by the original route
  until there is room for it without evicting; an asset never costs more
  per frame with the cache on than off, after its first frame. The
  remembered refusals and sizes are capped at 1,024 entries, and reaching
  the cap clears them. No lock is held across a decode, an encode or a
  usvg call.
  (g) **Measured** (`tools/proof/image_cache_bench.py`, 2026-10-22, the
  owner's parive promo's `section` clip at 25120000, 40 frames of
  1920 × 1080, 5 alternating rounds, load average 6.10, powermode 0): the
  original assets' median 11,595.0 ms, the stored copies' 11,097.4 ms, a
  saving of 0.0429 against a spread of 0.0330, and PNG decodes 0.0753 of
  the original's time. The stop rule, written before the run (build only
  if the saving is at least 0.03 and above the spread), said build.
  (h) **Risk accepted.** The first frame that draws an asset pays for the
  copy and its check: two decodes of a PNG original (png, then
  `Pixmap::decode_png`) or one of a JPEG (zune-jpeg), one encode, and one
  decode of the copy, before the frame's own decode of the copy. Each copy
  holds about w × h × 4 bytes.

- **G-40 — An action on a graphic `color` prop blends in OKLab, as
  stdlib's `interpolateColors` does, with straight alpha; no setting, no
  per-action or per-end key** (#250, graphics gaps phase 1, 2026-10-22;
  the owner's answer, 2026-10-22: "OKLab always"; amends G-34 (f)).
  (a) **The blend.** Every action on a graphic prop whose end's `kinds`
  names it `color` (G-34 (c)) moves it from its start toward its end in
  OKLab: stdlib's `interpolateColors`' conversion, mix and rounding
  (`graphic/src/stdlib.js`'s `__toLinear`, `__toOklab`, `__fromOklab`,
  `__fromLinear`), ported operation for operation into the core's
  `model_color.rs` as `oklab_mix`, so both round the same byte. Each end's
  red, green and blue are decoded from sRGB to linear, taken to OKLab,
  mixed component by component by the eased progress, taken back and
  rounded to the nearest byte. Alpha is carried straight in unit form,
  `a0 + (a1 − a0) × u`, rounded to the nearest byte: never premultiplied.
  `#000000` to `#ffffff` is `#636363` halfway (L 0.5, linear 0.125, sRGB
  99.09) and `#00000000` to `#ffffff` is `#63636380`. There is no setting
  and no per-action or per-end key. This supersedes G-34 (f)'s "channel by
  channel … Not OKLab"; its rounding to the nearest byte and its written
  form (G-12: `#rrggbb` when the alpha is 255) stand.
  (b) **Older projects.** A project whose ends already ramp a colour
  re-renders with the new middle. No persisted shape changes, so
  `RC_FORMAT_VERSION` is not bumped, and there is no migration (no real
  use yet, the owner, 2026-10-09). An end without `kinds` (version 12 or
  older) still switches its colours at the end (G-34 (k)).
  (c) **One fixture.** `graphic/tests/oklab.json` holds the blends both
  implementations answer — `core/tests/graphic_actions.rs` through the FFI
  and `graphic/tests/stdlib.rs` through `interpolateColors` — as
  `colours.json` holds G-12's grammar. A change to one is a change to the
  other; the JavaScript is the reference.
  (d) **Not changed.** The model's own colours (`[r, g, b, a]` in video,
  text and shape groups) still blend element by element in actions
  (§5.4); a graphic prop's other kinds keep G-34's rules; `split` stays
  invisible to within one byte per channel (G-34 (i)).
  (Amended by G-43: the model's nine colour keys in `video` and `text`
  blend in OKLab with straight alpha, through the same arithmetic in
  floating point; `shape` is not an action target.)

- **G-41 — A module marks a prop `animate: false` and no action animates
  it: `set_action_end` refuses a value for it by name, and the Graphic tab
  marks its row ⊘ and writes the clip; amends G-34 (b), (l) and its
  accepted limits** (#248, graphics gaps phase 2, 2026-10-22).
  (a) **The key.** Any schema entry may carry an optional boolean
  `animate`; absent or `true` animates, `false` does not, whatever the
  entry's type (an `asset` included). A present non-boolean is refused
  when the module compiles (the engine's `check_schema`) and when an op
  carries the schema (the core's), in one sentence, copied and not
  shared (G-2): `schema.<key>.animate <value> is not a boolean`, e.g.
  `schema.a.animate 1 is not a boolean`, checked after the default. An
  older build ignores the key, so the module still loads there.
  (b) **The refusal.** `set_action_end` refuses a non-null value for such
  a prop in its own sentence: `graphic.props.<key> is marked animate:
  false by its module; an action does not animate it — set it with
  set_graphic`. It is checked after a prop the schema lacks (G-34 (c))
  and before an asset (G-34 (b)), so an asset marked `animate: false`
  gets this sentence. A `null` still removes, unchecked (G-34 (j)); only
  the props a patch names are checked. The use: a count, a layout mode, a
  data series — e.g. `new Array(props.count)`, which a fractional ramp
  breaks (G-34 (e)). (Amended by G-42: there is no asset check any more;
  an asset marked `animate: false` still gets this sentence.)
  (c) **Stored ends are not re-checked** (G-34 (c)). An end that named the
  prop before its module said `animate: false` still animates it as
  stored, and an edit naming another prop of that end is not refused. The
  Graphic tab lists the key as the end's own stale row (G-34 (l)'s O2
  row: ◆, the end's value, ⌫ through the shared clear, its tooltip "The
  module does not let <key> be animated — remove it from action N"), and
  `set_action_end` with `null` for it removes it over MCP.
  (d) **The Graphic tab.** With an action selected, such a prop's row is
  ⊘ and writes `set_graphic`, as an asset's does (G-34 (l)); Properties'
  Reset writes its default to the base. With no action selected it is a
  row like any other. No format bump: the schema lives in the module, not
  the project. (Amended by G-42: an asset's row writes the end like any
  other; only an `animate: false` prop's row stays ⊘ and the clip's.)

- **G-42 — An action changes a graphic's image: an `asset` prop in an
  end switches at the action's END, `""` names no image there, and the
  Graphic tab's image row writes the end** (#249, graphics gaps phase 3,
  2026-10-22; amends G-4, G-34 (b), (d), (l) and G-41 (b), (d)).
  (a) **The switch.** An `asset` prop in an action's end is checked as
  `set_graphic` checks it (any string), its `kinds` is `asset`, and it
  switches at the action's END, as a string does. `set_action_end` no
  longer refuses an asset; its sentence is gone. A prop marked `animate:
  false` is still refused in G-41's sentence, whatever its type.
  (b) **No image.** In an end, "no image" is `""`, because a `null` there
  removes the prop (G-34 (j)). At the base, `null` still removes the key
  and the module draws its default. `""` is no image even over a string
  default. The engine's `overlay` hands `render` `null` for an asset
  stored as `""`, with no warning, so a module sees one "no image" from
  every path.
  (c) **The start.** `schema_default` gives an asset its string default,
  or `""` when the default is `null`. So an action's first naming writes
  that start into the clip (G-34 (d)), and `set_graphic`'s `null` for an
  animated asset stores it too.
  (d) **The Graphic tab.** With an action selected, the image row writes
  the end (◇/◆, never ⊘). Every asset row lists "None" first. "None"
  writes `""` into an end. At the base it writes `null` when the default
  is `null` and `""` when the default is a string. A `""` value reads as
  "None" and is never a popup item. The popup also lists a name the
  selected action's end holds that the folder lacks, as it lists a
  clip's. Properties' Reset writes an asset's default into the end (`""`
  for `null`). `GraphicSchemaEntry.animatable` is `animate`.
  (e) **No format bump.** No persisted shape changes; `""` was already a
  stored string. An older build draws an asset end but hands `""` to the
  module as `""`; there is no real use yet (owner, 2026-10-09).

- **G-43 — Every colour an action animates blends in OKLab, with
  straight alpha, by key; amends G-40 (d), G-34 (f)** (graphics gaps
  phase 4, 2026-10-22).
  (a) **The keys.** Nine keys of an action's state are colours, known by
  key and never by the value's shape: `video.shadow.color`, `text.color`,
  `text.outline.color`, `text.backdrop.color`,
  `text.word_style.active_color`, `.spoken_color`, `.upcoming_color`,
  `text.word_style.active_pill.color` (each `[r, g, b, a]`, sRGB-encoded
  0–1) and `video.chroma.key` (`[r, g, b]`, no alpha). Inside the spanning
  action each one whose start and end differ moves from its start toward
  its end in OKLab: the inputs clamped to [0, 1], then G-40's operations
  (sRGB → linear → OKLab, a mix by the eased progress, and back) in
  floating point, never rounded to a byte. Alpha is `a0 + (a1 − a0) × u`,
  straight, never premultiplied, clamped to [0, 1]; the chroma key is rgb
  only. A key whose start and end are the same numbers (compared parsed, so
  a stored `1.0` and an end's `1` are equal) is not blended, so it stays
  exactly as stored (the round trip would drift it by ~1e-7). A value that
  does not read as a colour of its key's arity (a `null`, a missing
  group, a wrong length, a non-number) keeps §5.4's rule: it holds and
  switches at the end. The ends are the stored values: an action's first
  tick is its start and its end is its end, exactly. Red to blue halfway
  is `#8c53a2` (×255 rounded), never `[0.5, 0, 0.5]`.
  (b) **One implementation.** `model_color.rs`'s unit path
  (`oklab_mix_unit`, `oklab_mix_rgb`) is the blend; G-40's `oklab_mix`
  is that path with each byte read as byte/255 and each unit rounded to
  the nearest byte, so its output does not change by a byte.
  `graphic/tests/oklab.json` is answered by three readers:
  `graphic/tests/stdlib.rs`, `core/tests/graphic_actions.rs` (bytes), and
  `core/tests/action_colours.rs`, which takes each case's bytes/255 in and
  compares the result ×255 rounded to the fixture.
  (c) **Older projects** re-render with the new middle. No persisted
  shape changes, so `RC_FORMAT_VERSION` is not bumped and there is no
  migration.
  (d) **Not changed.** The `shape` group and `canvas.background` are not
  action targets (§5.4's three groups), so they have no blend; a colour
  plate is a shape. At a `split` the join is exact (`clip_state` either
  side of the cut is equal); inside the head and the tail a sample
  matches the unsplit clip within the matrices' round-trip error (1e-6
  per channel), not exactly.

- **G-44 — The bundled templates: one unit, title-safe at every frame,
  a static card, the bundled faces, generic glyphs, an accent and an
  outro, held by a test** (owner, 2026-10-29: "I want to create some more
  default graphics"; seventeen added to road map 10's six).
  (a) **The unit.** A template sizes everything by
  `u = Math.min(ctx.width, ctx.height) / 1080`, which is the six's
  `ctx.height / 1080` in landscape and keeps a portrait (1080 × 1920)
  frame from drawing at 1.78 times the size.
  (b) **Title-safe at every frame.** Everything a template draws, at
  every frame, lies inside the 90 % title-safe rectangle
  (x ∈ [0.05W, 0.95W), y ∈ [0.05H, 0.95H)), at 1920 × 1080, at
  1080 × 1920 and at 1080 × 1080 (the square social canvas, which takes
  the landscape layout). An entrance is a spring, a clipPath wipe or a
  fade, never a move in from off-frame. Long user text is fitted or
  wrapped to stay inside, never kept out by narrowing the schema.
  (c) **A card's background is static.** A full-frame template (one that
  passes `background` to `svg`) draws the same background at frame 0 as at
  every later frame; its outro fades or moves the content only.
  (d) **The faces.** Montserrat 800/900 for text, IBM Plex Mono 500 for
  ticking digits, and `'Source Sans 3'` 600 only for window-frame's UI
  text. Bundled faces only (G-6).
  (e) **Glyphs.** A keycap symbol, a bell, a heart, a play triangle or a
  platform glyph is a generic vector shape drawn by the module; no brand's
  artwork.
  (f) **Accent and outro.** Every template has an `accent` colour prop and
  an outro in about its last 15 frames, keyed to `ctx.durationInFrames`,
  that leaves its last frame bare: clear for an overlay, the background
  alone for a card.
  (g) **The test.** `graphic/tests/templates.rs` holds every module of
  `graphic/tests/graphics/` except `common::FIXTURES` (road map 10's six,
  which keep their own look and pins) to (b), (c) and (f)'s bare last
  frame at all three sizes, with its defaults, with every combination of
  its `enum` options, and with long text (every `string` property given a
  realistic long value: about 40 characters for a title or label, about
  120 for a quote, ticker or subtitle, a list's longest plausible entries;
  `tests/templates/long_text.rs` names one for each, and a string it does
  not name fails): every sampled frame equals frame 0 outside
  title-safe, and frame 0 has one alpha value there; no warning from `svg`
  or `rasterize`, no `NaN` or `Infinity` in the SVG, with defaults and with
  degenerate data (one point, an all-zero series, `max ≤ min`); and
  `project.yml`'s "Copy Graphic Templates" lists exactly the folder's
  `*.js` files.

- **G-45 — Insert ▸ Graphic… is a dialog: categories, the graphics of
  one, and a looping preview; a template declares its category and a
  one-line description** (owner, 2026-10-29: a graphic browser in place of
  the Insert ▸ Graphic submenu; phase 1 of 2, `.fjgraphic` export being
  the second). Amends G-16.
  (a) **A module's category** is `meta.category` when it is a string that
  is not empty after trimming (trimmed), else "Other".
  (b) **Every bundled template declares one** of Data & Time,
  Screencast, Social & YouTube and Titles & Text, and a one-line
  `meta.description` of at most 120 characters, held by
  `graphic/tests/template_meta.rs` to (c)'s table.
  (c) **The table.** Data & Time: bar-chart, counter, countdown,
  donut-chart, gauge, line-chart, progress-bar. Screencast:
  arrow-highlight, callout, keyboard-keys, step-badge, window-frame.
  Titles & Text: chapter-card, kinetic-type, logo-reveal, lower-third,
  news-ticker, quote-card, title-card. Social & YouTube: end-screen,
  handle-tag, social-popup, subscribe-button.
  (d) **The list.** This Project first, and only when the package's
  `graphics/` holds a module: every project module, whatever its own
  category. Then the templates' categories by case-insensitive name, Other
  last. Within a category the graphics go by title case-insensitively,
  then by name. `list_graphics` answers the same order.
  (e) **The title** is `meta.name` when it is a non-empty string, else the
  stem's title (`lower-third` → "Lower Third"). A This Project graphic whose
  title equals another This Project graphic's, case-insensitively, is shown
  as "<title> — <module name>", in the dialog and in `list_graphics` alike,
  so two copies of one template can be told apart. The templates are now
  COMPILED to read their `meta`, once per process, against the bundled
  fonts; the menu bar still compiles nothing (chrome probes instantiate
  `AppDelegate()`).
  (f) **The door** is Insert ▸ Graphic…, a sheet (the submenu and its From
  File… item are gone; From File… is the sheet's bottom-left button, and
  its open panel follows once the sheet is down). Insert is G-16's act for
  a template: the module written under a free name (G-16 (b)), then one
  clip. For a This Project graphic it places a clip drawn by that module
  and writes no copy. Either is one undo step "Insert Graphic". A module
  that does not compile places nothing, and its sentence is
  "graphics/<name>.js does not compile: <the first diagnostic> (line N)" — in the
  dialog's message line, which stays up, or, for From File…, in a sheet
  (G-16 (c)'s "was written but" is gone, since a This Project graphic was
  not written). The agent's mirror is `list_graphics` and
  `insert_graphic {name, from}`.
