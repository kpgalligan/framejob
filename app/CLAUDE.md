# app/CLAUDE.md — Swift app rules

Applies to everything under `app/`. Build/verification commands and the FFI
lockstep are in the root `CLAUDE.md`; the full design is
`designs/reelcut-design.md` (§3–4 the UI, §7.4–7.8 this file map).

## File map

- `ReelCore.swift` — the **only** home for `rc_*` calls: `ReelProject`
  (handle + lazily decoded `ProjectSnapshot`), the typed op builders that
  mirror `core/src/edit.rs`'s op table, timecode, snapping, export presets,
  sizes and settings (`ExportPreset`, `ExportSize`, `ExportSettings`),
  and `RecipeSource`. `deinit` frees the Rust allocation. There is no
  untyped op-JSON call site anywhere else.
- `ProjectSnapshot.swift` — the `Codable` mirror of the §5.2 project JSON:
  the read-only view every view draws from.
- `ProjectDocument.swift` — NSDocument, `.reelcut` package read/write, and
  the single mutation point (see Undo below). It also holds the four pieces
  of VIEW state every view agrees on and nothing persists: the playhead, the
  clip selection, the in/out range and `selectedMedia` (the Media tab's
  selected row, which Edit ▸ Insert / Overwrite at Playhead place). All four
  are re-clamped to live ids by `clampViewState`, and `selectedMedia` lives
  here rather than on `MediaPane` because that pane is rebuilt whole
  whenever the media list changes.
- `Playback.swift` · `CompositionBuilder.swift` · `Compositor.swift` ·
  `CompositorEffects.swift` · `LayerRenderers.swift` · `MediaImporter.swift` ·
  `Exporter.swift` · `ExporterWriter.swift` · `ExporterImageSequence.swift` —
  the AVFoundation/Metal side; see spec §7.5–7.8. `CompositorEffects.swift`
  holds the M3 effect logic so `Compositor.swift` grew only the uniform
  fields; the uniform block's field ORDER is a contract with
  `Resources/Shaders/Compositor.metal` and is checked nowhere but by reading
  both, so change them in one edit.
- `MediaImporter.swift` · `FFmpegRewrap.swift` — the import funnel and the
  opt-in ffmpeg step behind it (spec §7.7, §11). `async`/`await` is confined
  to `MediaImporter.swift`; `FFmpegRewrap` runs `Process` on a serial queue,
  never on a cooperative thread, because ffmpeg blocks the thread it is on.
- `CaptionImporter.swift` (File ▸ Import Captions…) · `MediaConsolidator.swift`
  with `EditorViewController+Consolidate.swift` (File ▸ Consolidate Media…) —
  the two §5.6 file features. Consolidate writes inside the package behind
  NSDocument's back, so it MUST tell
  `ProjectDocument.packageContentsDidChangeOnDisk()` afterwards, or every
  later save is refused as "changed by another application".
- `EditorViewController.swift`, `TimelineView.swift`,
  `PreviewCanvasView.swift`, `AgentServer.swift` — **frozen at current
  size.** Any change adding more than ~50 lines goes in an extension file
  instead: `EditorViewController+<Feature>.swift`,
  `AgentServer+<Feature>.swift`, or a new `…SheetController` file. The
  pieces those extension files build on are therefore internal, not
  private, and the frozen file keeps only the wiring.
- `InspectorViewController.swift` (frozen at wiring: the tab strip and which
  pane is shown) + `InspectorPane.swift` (the pane protocol and base, the
  disclosure section with its collapsed-state key and its right-aligned
  summary, the row builders, and `InspectorBinding` — the one place that
  knows reads are evaluated inside an action and that writes there set
  `set_action_end`) + `ClipPane.swift` for the Clip tab, `MediaPane.swift`
  and `DocumentPane.swift` for the other two, with `VideoPane.swift`,
  `AudioPane.swift`, `TextPane.swift` and `ShapePane.swift` surviving as the
  section factories `ClipPane` composes. Descriptor-driven from
  `OptionControls.swift`. **Three tabs, not six**: `InspectorTab` is
  `clip | media | document`, all always live, and the old
  disabled-tab / preferred-tab / pin apparatus is gone — which sections
  appear is `ClipPane.makeSections()`'s answer.
  **Pitfall:** an `InspectorSection`'s `UserDefaults` key records COLLAPSED,
  so an untouched section has no stored value and `defaultExpanded` applies;
  never flip that polarity or every saved panel inverts. And section ids are
  shared across contexts (`video.speed` is the Speed group for a video clip
  and the first group an audio-only one gets), so a "open the first section"
  rule has to walk until it finds one the user has not stored.
- `ExportSheetController.swift` (the export card and its progress sheet),
  `SpeedSheetController.swift`, `RelinkSheetController.swift` — the
  dialogs, all built from `Sheets.swift`'s `makeSheetView` pieces and put
  up by `EditorViewController+Export.swift`. A sheet captures a project
  handle and trusts it, which is safe because every editor action
  validates false while one is attached.
- `AgentCatalog.swift` — the MCP tool catalog; a startup check enforces that
  catalog names match the dispatch registry (it traps in debug and logs in
  Release, because `make app` builds Release). The handlers live in
  `AgentServer+Project/Clips/Tracks/Media/Render/History.swift` and their shared
  argument vocabulary in `AgentServer+Arguments.swift`; a new op means a
  handler, a catalog entry and a comment naming the UI path it mirrors.
  Beyond the §6 ops the catalog carries the app-state tools spec §7.9 names
  plus `set_range`, `set_selection`, `undo` and `redo` — the mirrors of
  I/O/⌥X, a timeline or canvas click, and ⌘Z/⇧⌘Z, without which the "one edit
  is one undo step", "the in/out range scopes the export" and "the selection
  draws handles" properties could not be checked by driving the built app.
  None of the four is an op, so none registers an undo step.
  `target(_:)` resolves the implicit document: an agent-driven app is never
  the ACTIVE app, so `NSDocumentController.currentDocument` is nil there and
  the fallback must be `NSApp.orderedDocuments`, never `documents.first`
  (which silently targets the OLDEST project). An EXPLICIT `project` path is
  matched through `AgentServer.canonical` — never as a raw string: a caller
  may spell one file `~/…`, `/tmp/…` or `/private/tmp/…`, and AppKit's save
  machinery can re-spell `fileURL` into the other half of that last pair
  mid-session, which made a path that had worked for twenty calls start
  answering "No open project is at …". `open_project`'s already-open check
  compares the same way, or it opens one file twice.
  `AgentServer.offMainTools` names the few handlers that run on the server
  thread instead of the main one — they wait on the main thread (an async
  probe's completion, NSDocument's save) or on a long decode, so hopping first
  would deadlock or freeze the UI; they reach the document through
  `AgentServer.onMain`.
- `EditorViewController+Edge.swift` — the cutting moves (spec §6's `slip`,
  `roll`, `close_gap`, `insert_clip`, `overwrite_clip`) plus the `,` / `.`
  nudge and Select All on Track. `lift_range` is the odd one out: it is the
  ⌫ branch of `deleteSelection` in `EditorViewController+Timeline.swift`,
  beside the ⌘⌫ ripple it pairs with. It carries an
  `extension TimelineView` as well as the controller's, because the two ⌥⇧
  drags are begun from there — the same split `TimelineClipDrawing.swift`
  and `MediaPane.swift`'s drop targets use, and the reason `dragSnapper` and
  `makeSnapper` are internal.
- The chrome cleanup's own files (the design handoff in
  `designs/design_handoff_reelcut/`, spec §3–§4.4):
  `EditorViewController+Toolbar.swift` (the 44 pt row; the frozen file keeps
  only the stored views, which are internal for exactly that reason),
  `TimelineBar.swift` (the 36 pt bar and its selection block),
  `TimelineClipDrawing.swift` (a clip is one object — body, name strip,
  filmstrip under a tint wash, waveform, grips, transition zone),
  `ClipPane.swift` (the Clip tab: the selection header, and
  `makeSections()`, the function from a selection's kind to the sections it
  gets — the four old clip panes are held there as section FACTORIES, never
  in a view hierarchy), `ClipKindStyle.swift` (the ONE mapping from a clip to
  its tint, symbol and kind word; it takes the snapshot, because a `media`
  clip is video or audio by whether its FILE has pictures and not by
  `enabled.video`, which is the Detach switch), and `BrandMark.swift` (the
  mark drawn from the handoff's geometry table — no blend mode, unlike the
  motif it replaced).
- Shared chrome: `Theme.swift` (`DS` design tokens), `Controls.swift`,
  `OptionControls.swift`, `Sheets.swift`, `EditorChrome.swift` (`BarView`),
  `FileDropView.swift` (Finder drops + the first responder the bare-key map
  needs) — copied from Rasterize, keep them in sync rather than forking.

## Rules

**Placement.** New feature = small model/value file + VC extension file +
gesture session struct. Interactive gestures are modeled as a session struct
(`ClipDragSession`, `TrimSession`, `CanvasSession` are the template): one
stored property on the view, logic in the feature's file. Closures assigned
in `loadView` are one-line forwards to named methods
(`timeline.onClipDrag = { [weak self] in self?.clipDragged($0) }`) — no
business logic in closure bodies.

**Undo and dirty tracking.** All document mutation flows through
`ProjectDocument`'s entry points — `applyEdit` and the
`beginLiveEdit`/`updateLiveEdit`/`endLiveEdit` trio for gestures.
`registerUndo` appears nowhere outside `ProjectDocument`. It overrides
`updateChangeCount` to drop AppKit's automatic undo-based counting; the
entry points count deterministically via `countEditChange()`.
**Pitfall:** undo registrations outside an AppKit event (agent edits, async
callbacks) land in the implicit event group `NSUndoManager` opens per event
and that AppKit never closes there, silently merging edits into one undo
step; any off-event path must go through
`ProjectDocument.performGroupedEdit`, which turns `groupsByEvent` OFF for
the duration and balances one explicit group.
**Do not "flush" the manager to grouping level zero** to close that implicit
group. That leaves an end with no begin, and the undo CHECKPOINT `NSDocument`
posts from inside the file-coordination accessor of every save then raises
`endUndoGrouping called with no matching begin`. Under `autosavesInPlace`
the exception is swallowed inside the coordinator, so the save never
completes, never writes, and never relinquishes its file-access claim —
⌘S and `save_project` hang for good after the first off-event edit.

**Agent parity.** Every user-visible edit gets an MCP mirror: a handler in
the dispatch registry + a catalog entry in `AgentCatalog.swift` (the startup
parity check enforces the names match) + a comment naming the UI path it
mirrors. Handlers follow the canonical shape: `target(a)` → validate ids →
`performGroupedEdit` → `jsonResult`; failures throw `ToolError` and return
in-band (`isError: true`) so models can self-correct.

**State flow.** Views → VC through `on*` closures (`[weak self]`); document
→ observers via `.projectDocumentDidChange` with `userInfo["isLive"]` —
live gestures pass `isLive: true` and observers skip expensive reloads
mid-gesture. VC → views is direct property assignment.

**Tracking areas.** `updateTrackingAreas` must remove only the view's OWN
areas — `for area in trackingAreas where area.owner === self` — never
`trackingAreas.forEach(removeTrackingArea)`. `NSView.toolTip` and
`addToolTip(_:owner:userData:)` are both implemented as tracking areas owned
by `NSToolTipManager`, they sit in `trackingAreas` beside yours, and nothing
reinstalls one that is removed. The blanket form silently killed the tooltip
on every custom control in the app, which for an icon-only button is the only
thing that names it.

**Hygiene.** No storyboards/xibs. No `!` force-unwraps, `as!`, or `try!`;
implicitly-unwrapped optionals only for post-`loadView` view refs. Every
non-NSCoder class: `@available(*, unavailable) required init?(coder:)
{ fatalError("<Type> does not support NSCoder") }`. `[weak self]` in
retained closures, never `unowned`. Main-thread AppKit. `async`/`await` is
allowed **only inside `MediaImporter.swift`** (AVFoundation's loading API is
async-only going forward) — and nothing else earns the exception by asking:
speech recognition uses `SFSpeechRecognizer`'s callback API for exactly this
reason (spec §11); `DispatchQueue` only at the documented seams
(the compositor's render queue, the composition rebuild, import, the export
progress timer). Colors/fonts/metrics come from `DS` tokens; shared controls
go in `Controls.swift`. Refusals beep (`NSSound.beep()`), errors never
crash. 4-space indent, ~100 columns.
