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
  both, so change them in one edit. It is 104 floats (416 bytes, 26 × 16)
  since `video.obscure` landed, and the four regions in it are
  REGION-MAJOR — all eight fields of region 0, then region 1 — in the
  model's own field order, so the two files read as one list and a reader
  can check the contract by eye, which is the only way it is ever checked.
  `CompositorEffects.swift`'s header doc is where the amount→length
  mappings are written down (a blur's outer tap ring at `amount × 24`
  source pixels; a pixelate's block at `1 + amount × 63`, so amount 1 is a
  flat 64 × 64 SOURCE-pixel block anchored at the texture origin) — a proof
  that measures a block has to read a number from somewhere.
  **Two rules the review put into the region pass**, both in
  `Compositor.metal` and both about what happens where regions meet: where
  two cover one fragment the GREATER hiding wins and the other is not
  applied at all (a source-pixel length times the mix it would be applied
  at, a tie going to the pixelate), because both mixes take a fresh sample
  of the RAW texture and running the second would put back what the first
  hid; and a slot's share of a cover is weighted by its own strength, so a
  region at `amount` 0 — "there but hides nothing" — cannot pull a
  neighbour's effect to full strength inside its own box.
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
  `AgentServer+<Feature>.swift`, `TimelineView+<Feature>.swift` — three
  precedents for the view: the `extension TimelineView` inside
  `EditorViewController+Edge.swift`, `TimelineView+Rename.swift`, and
  `TimelineView+Candidates.swift` — or a
  new `…SheetController` file. The pieces those extension files build on
  are therefore internal, not private, and the frozen file keeps only the
  wiring.
  **Pitfall:** a selector declared `@objc` on an
  `extension EditorViewController` needs NO forward in the frozen file — a
  second declaration there is a redeclaration error, not a forward
  (`pickChromaKey` is the precedent; `zoomToRegion`, `zoomBack` and
  `placeObscureRegion` followed it). The forward block is for commands
  whose body lives at the foot of a NON-extension feature file, which is
  what `importCaptions` and `removeSilences` are.
  **And a second:** `handleEditorCharacter`'s bare-key `switch` matches in
  SOURCE order, so a new `case "x"` must go BELOW any
  `case "x" where <modifier>` above it. A bare `case "z"` placed first
  would swallow ⇧Z and kill Fit Timeline with no compiler warning at all.
- `InspectorViewController.swift` (frozen at wiring: the tab strip and which
  pane is shown) + `InspectorPane.swift` (the pane protocol and base, the
  disclosure section with its collapsed-state key and its right-aligned
  summary, the row builders, and `InspectorBinding` — the one place that
  knows reads are evaluated inside an action and that writes there set
  `set_action_end`, with the ONE exception `structural(video:for:)` pulls
  out: a list-valued key (`filters`, `obscure`) whose new LENGTH differs
  from the clip's own goes to the BASE props wherever the playhead is,
  because `actions.rs`'s list rule interpolates per index only while the
  lengths match — an appended region written into an end patch is invisible
  for the whole span, does not even grow a row, and is then dropped by the
  next write of that list) + `ClipPane.swift` for the Clip tab,
  `MediaPane.swift` and `DocumentPane.swift` for the other two, with
  `VideoPane.swift`,
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
  **And a second:** a field's `refresh` is skipped while its field editor is
  attached, which it still is inside `controlTextDidEndEditing` (after
  Return or Tab AppKit even re-attaches it), so every refresh a commit runs
  is skipped — `InspectorNameField` and the timecode field set their
  `stringValue` directly as the commit ends, or a cleared name would keep
  showing blank while the strip shows the fallback.
- `ExportSheetController.swift` (the export card and its progress sheet),
  `SpeedSheetController.swift`, `RelinkSheetController.swift` — the
  dialogs, all built from `Sheets.swift`'s `makeSheetView` pieces and put
  up by `EditorViewController+Export.swift`. A sheet captures a project
  handle and trusts it, which is safe because every editor action
  validates false while one is attached.
- `AgentCatalog.swift` — the MCP tool catalog; a startup check enforces that
  catalog names match the dispatch registry (it traps in debug and logs in
  Release, because `make app` builds Release). The handlers live in
  `AgentServer+Project/Clips/Tracks/Media/Render/History/Silence.swift` and
  their shared
  argument vocabulary in `AgentServer+Arguments.swift` — `intArg`,
  `doubleArg`, `boolArg`, `stringArg`, `stringsArg` (an optional list of
  strings, a lone string counting as a one-element list; emptiness and
  vocabulary are the caller's), the id readers (`clipArg`, `clipsArg`,
  `trackArg`, …), `timeArg`, `rangesArg` (a list of `[from, to]` pairs,
  every tick through the same `snappedTick` `timeArg` uses, a lone flat
  pair counting as one range), `nestedNumberArg` (a number one level down,
  named by its path — how a `{x, y, width, height}` object is read without
  dropping a member it cannot parse), `colorArg` and `patchArg`, each
  refusing a
  value it cannot read BY NAME rather than dropping it; a new op means a
  handler, a catalog entry and a comment naming the UI path it mirrors.
  One gap in that guard worth knowing: `patchArg`'s round-trip check
  cannot see a wrong-typed value for a `T??` field — the `nullable()`
  decoder in `ProjectSnapshot.swift` swallows every decode error and
  answers `.some(nil)`, so `{"label": 7}` decodes as a CLEAR and passes.
  `set_clip`'s handler adds a per-key type check (`checkClipPatchTypes`)
  after it; the other nine `T??` patch fields still have the gap —
  `VideoPatch.shadow` / `chroma` / `reflection` / `spotlight`,
  `AudioPatch.duck` / `compressor`, `TextPatch.outline` / `backdrop` /
  `width` — and on the object-valued ones a wrong type CLEARS the effect.
  A second thing that round trip cannot do, older than phase 3 and
  measured again by its proof: a nested OBJECT in a patch is decoded into
  its typed struct and re-serialised, so an unknown key inside one is
  dropped where the core would have named it, and a known key the caller
  omitted is sent as that struct's DEFAULT — which resets the field. That
  is `shadow`, `chroma`, `duck` and now every `obscure` entry: the core
  refuses both (`deny_unknown_fields`), the decoder simply gets there
  first, so a patch of a nested object is a REPLACEMENT and has to be sent
  whole.
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
  compares the same way, or it opens one file twice. One trap the phase-2
  proof measured: an explicit path is matched with `documents.first(where:)`,
  so when several OPEN documents hold one path — only `new_project {path}`
  and `save_project {path}` can make that, the GUI cannot — an unspecified
  one answers, and there is no close tool to clear the others. A script
  that saves at a path uses a fresh name per run for that reason.
  A second lenient decode worth knowing: `ProjectSnapshot`'s enums fall
  back to a default rather than throwing, so `{"kind": "glow"}` inside an
  `obscure` region would silently become `pixelate` and the caller be told
  it worked. `AgentServer.checkVideoEnums` is what closes that, and it
  checks the FOUR string enums a video patch can carry and no more:
  `filters[].kind`, `spotlight.shape` and now `obscure[].shape` and
  `obscure[].kind`, each against its own `allCases`. Nothing else in a
  video patch is an enum — `chroma` is a colour and three numbers — so a
  new enum inside a patch has to be added to it by hand.
  `AgentServer.offMainTools` names the few handlers that run on the server
  thread instead of the main one — they wait on the main thread (an async
  probe's completion, NSDocument's save) or on a long decode, so hopping first
  would deadlock or freeze the UI; they reach the document through
  `AgentServer.onMain`. The criterion is "waits for something the main
  thread must deliver", not "touches the disk": `detect_silence` reads a
  few hundred KB of peak files and does one arithmetic pass, and stays
  ON-main for that reason, as `consolidate_media` and `import_captions` do.
- `EditorViewController+Edge.swift` — the cutting moves (spec §6's `slip`,
  `roll`, `close_gap`, `insert_clip`, `overwrite_clip`) plus the `,` / `.`
  nudge and Select All on Track. `lift_range` is the odd one out: it is the
  ⌫ branch of `deleteSelection` in `EditorViewController+Timeline.swift`,
  beside the ⌘⌫ ripple it pairs with. It carries an
  `extension TimelineView` as well as the controller's, because the two ⌥⇧
  drags are begun from there — the same split `TimelineClipDrawing.swift`
  and `MediaPane.swift`'s drop targets use, and the reason `dragSnapper` and
  `makeSnapper` are internal.
- `SilenceDetector.swift` · `SilenceSheetController.swift` ·
  `TimelineView+Candidates.swift` — Remove Silences (Clip ▸ Remove
  Silences…, and the `detect_silence` tool). The detector is pure
  arithmetic over values: `Input.read` is the one seam that takes a
  snapshot, a plan, a selection and the peak files off a `ProjectDocument`,
  and everything after it is a function of those — which is what lets the
  sheet re-detect SYNCHRONOUSLY on every control change (the document
  cannot change under an open sheet) and lets the agent run the same code.
  **It reads the PLAN, not the peaks alone**: a peak bucket is pre-fader,
  so the level it asks about is `peak × envelope`, and because `audio.rs`
  expresses mute and solo as a ZERO envelope both fall out for free with no
  second Swift copy of `silenced` to drift from the first.
  **Pitfall the review found:** that same zero envelope makes a silenced
  voice pass the quiet test at EVERY tick while still covering its span, so
  it is dropped from both scopes rather than counted — in scope it would
  propose one cut across its whole clip, and `ripple_delete_ranges` cuts
  every unlocked track, taking whatever is audible under it. `defaultScope`
  answers `.audible` for a selection of silenced clips for the same reason,
  and the sheet's "Selected clips" row is disabled off that answer. **And a
  NEST is a wall**: the plan flattens one, so its segments carry the INNER
  clips' ids, and a candidate that reached inside would split a nest clip —
  which has no in point, so its tail is stranded, not trimmed. A nest's
  sound counts toward the quiet test and no candidate may intersect one.
  The menu
  command and its validator sit at the FOOT of the sheet's own file, the
  shape `CaptionImporter.swift` set. The candidate wash is drawn, not
  overlaid — an overlay view cannot work, because the ruler fills its whole
  bounds opaquely first — so `TimelineView.swift` carries one stored
  property and two one-line draw calls and the bodies live in the
  extension.
  **Pitfall:** an `NSPopUpButton`'s menu validates its own rows, so
  `menu.autoenablesItems = false` has to come before disabling one or
  AppKit puts it straight back on.
- `EditorViewController+Eyedropper.swift` ·
  `EditorViewController+ZoomRegion.swift` — the two modal canvas modes:
  the chroma pick, armed from the Chroma section's eyedropper button, and
  the region band on bare `Z`. Both install a bare `NSView` over
  `canvasContainer` whose PRESENCE is the mode, hand it one-line closures
  back to named methods on the controller, and end themselves when the
  selection changes (`syncChromaEyedropper` / `syncRegionMode` in
  `refreshCanvas`); the frozen `PreviewCanvasView.swift` gains no seventh
  stored session for either. Both are installed through **`armCanvasMode`,
  which ends every OTHER armed mode first** — the review found the
  eyedropper arming over a live region mode, so one canvas drag could
  commit a zoom nobody asked for; a third mode inherits the rule by being
  installed at all, and no arming path has to remember the others.
  The region mode's key TOGGLES rather than only
  arming, because an overlay that has lost first responder can no longer be
  dismissed by Esc — the eyedropper's practical failure, not a
  hypothetical. All coordinate mapping goes through
  `PreviewCanvasView.viewToCanvas` / `canvasToView` (spec §11), and
  `CanvasLayerBox.sourcePoint` — the region frame — reads the EVALUATED
  props, the opposite of every other session in `CanvasSessions.swift`,
  because a region is drawn on what is on SCREEN and has to agree with
  `edit_zoom.rs`'s `evaluate_clip(clip, at)`.
- `TimelineView+Rename.swift` — the inline clip rename (a double-click on a
  clip, Clip ▸ Rename…) over the one editor `TimelineView` keeps for track
  and marker renames; the frozen file holds only the `clicks == 2` hook and
  the `relocateRename()` at the end of `rebuildLayout`. Every rename hands
  `beginRename` a `relocate` closure answering its field's rect under the
  CURRENT layout, so the field FOLLOWS its target through a zoom, a resize
  and any document change (an agent's edit, a save's dirty crossing) rather
  than being ended — removing the field commits what was typed, and under
  an agent's grouped edit that half-typed rename would land inside the
  agent's undo step. A relocator answering nil (the target was deleted)
  ends the field with its commit DROPPED, never sent to a dead id. The
  shared editor also drops an UNCHANGED commit (an accidental double-click
  would otherwise pin a clip's fallback as its own name, and beep as an
  identity on a track or marker) and an EMPTY one, so a name is CLEARED in
  the Clip tab's header field (`ClipSelectionHeaderView`), never in the
  strip; and it blurs whatever else is being typed into BEFORE installing
  its field, because that editor's commit rebuilds the layout. The strip
  field is clamped to the visible lanes: AppKit does not scroll a timeline
  to a field editor's caret.
- `EditorViewController+Identity.swift` — Clip ▸ Rename… (⇧⌘R), Clip ▸
  Label ▸ (a tagged submenu over `ClipLabel.allCases`) and the Track ▸ Solo
  item's checkmark; Solo's body is `toggleTrack(.solo)` in `+Timeline.swift`
  beside its siblings, and Edit ▸ Paste Attributes (⌥⌘V) is in
  `+Clipboard.swift`, beside the pasteboard it reads.
- `EditorViewController+Clipboard.swift` — ⌘X / ⌘C / ⌘V over the
  `com.kgalligan.reelcut.clips` pasteboard type (the `paste` op's payload,
  whose schema is `core/src/edit_paste.rs`'s module doc), and ⌥⌘V Paste
  Attributes, which sends that same payload to `paste_attributes` with no
  `groups` — the core's default rule, every group both clips have.
- `ClipLabel.swift` — the ONE home of the marker-colour vocabulary: the six
  names in order (`red`, `orange`, `yellow`, `green`, `blue`, `purple`),
  their display names and their inks, the ruler's marker palette verbatim.
  The timeline's label dot, the ruler's marker flags
  (`TimelineRulerView.markerColor` routes through `color(named:)`), the
  Clip ▸ Label submenu and the Clip tab header all read it. The core stores
  a label or a marker colour NAME unvalidated (the `Marker.color` policy:
  a build that policed the list would refuse a newer build's project), so
  an unknown name is an error nowhere here — it draws in `DS.textStrong`.
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
