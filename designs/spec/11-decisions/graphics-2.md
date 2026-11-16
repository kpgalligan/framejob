# Spec §11 — decisions: Graphics, a file source's limit onward (road map 10)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the G- series of [`graphics.md`](graphics.md), so a citation never has to say which
file. This file holds G-20…G-29. G-30 on are in [`graphics-3.md`](graphics-3.md). It is new because
`graphics.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the entries moved here
unchanged, and an "above" or "below" in one may now point into a sibling file.

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
