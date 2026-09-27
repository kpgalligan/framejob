# app/CLAUDE.md — Swift app rules

Applies to everything under `app/`. Build/verification commands and the FFI
lockstep are in the root `CLAUDE.md`; the full design is
`designs/spec/` (§3–4 the UI, §7.4–7.8 the platform side; its `README.md` is
the index). The
long form of each entry below — why each file is the shape it is, and the
traps its history turned up — is `designs/adr/app-file-history.md` (the
full history, every size toll and measurement, is archived; see its
"Original" line); this file is what governs a file now. Files
are listed by family; a file with a header comment of its own carries its
detail there.

## File map

**The core's edge.**
- `ReelCore.swift` — the **only** home for `rc_*` calls: `ReelProject`
  (handle + lazily decoded `ProjectSnapshot`; `json`, `snapshot` and
  `planJSON` are memoised PER HANDLE, so keep handles rather than minting
  them), timecode, snapping, export presets/sizes/settings, the
  `dictionary` extensions on the property types and the typed patches —
  except `TextPatch` (with `case`, `words` and `word_style`), which is
  `TextPatch.swift`'s, moved out so it could grow. `word_style` has ONE
  app-side writer, `CaptionLayout.place` (W-10).
  The graphics engine's wrappers are here too: `GraphicLibrary` (`addFont`,
  `addAsset`, `rasterize`, `families()`; frozen by its first compile,
  rasterize or `families()`) and
  `GraphicModule` (`compile`, `describeJSON`, `svg`; it holds its library
  strongly), with `GraphicDiagnostic`, `GraphicFailure` (what a `diag_out`
  failure throws; `err_out` stays `ReelCoreError`) and `GraphicRaster`.
  `MediaDescriptor`, `mediaURL(for:)` and `bookmarkString(for:)` are
  `MediaDescriptor.swift`'s: a `media[]` element minus its id, and the
  media-file resolvers; they call no `rc_*`.
  It is also where the op table is read BACK: `ReelOp.coreNames()` over
  `rc_op_names`, and `ReelOp.coreSchemas()` over `rc_op_schemas` — every
  op's ARGUMENTS as JSON Schema, keyed by op name, which
  `AgentCatalog.opTool` prints for all fifty-nine op tools.
  `deinit` frees the Rust allocation. It also holds **the one read of
  `rc_project_apply`'s TWO message channels**, in the header's own order — a
  sentence is a refusal, an error message is invalid input, neither written
  is an identity — answered as the `ReelEdit` below.
- `ReelOps.swift` — `OpArgs`, `ReelOp` and one typed factory per row of
  `core/src/edit.rs`'s op table, plus a RAW factory beside the typed one at
  each door that takes a CALLER's own object — ELEVEN of them (`setVideoRaw`,
  `setAudioRaw`, `setTextRaw`, `setShapeRaw`, `setClipRaw`,
  `setActionEndRaw`, `addTextClipRaw`, `addShapeClipRaw`, `setCanvasRaw`,
  `addBackgroundRaw`, `addZoomActionRaw`), which takes the
  caller's own object as `Any` — never `[String: Any]`, so a non-object is
  refused by the CORE in the words that name the group — and forwards it;
  there is no untyped op-JSON call site anywhere else. Where only ONE
  argument is the caller's (a colour, a region, a new clip's patch) the typed
  factory DELEGATES to the raw one, mapping its optional explicitly, because
  an `Optional<T>.none` widened to `Any?` is a non-nil `Any` wrapping a nil.
  The typed `setActionEnd` LIFTS every top-level null out of its patch into
  `off` (spec §11 CI-14: a typed `.some(nil)` is a switch turned OFF, kept
  at the end); `setActionEndRaw`'s nulls stay removals, which is what
  `clearOps` and every agent call send, and it writes `off` only when
  non-empty.
  `addZoomActionRaw`'s region is `Any` and not `Any?`: an absent key and an
  explicit null are opposite intentions there, and only the tool can tell
  them apart.
  `scope` is a member folded into `json`; `documentLevelNames` MIRRORS
  `scope.rs`'s `refused_inside` (seven names) so one edit can mix a
  document-level op with scoped ones. A table, with
  `edit.rs`'s size exemption.
- `ReelOpSchema.swift` — what an op TAKES, mirroring what
  `core/src/op_schema.rs` publishes: the `properties` and `required` of one
  op's arguments, which are the two things `AgentServer.tool` takes. Here
  rather than next door for `ReelEdit.swift`'s reason — it names no `rc_*`
  symbol — and `properties` stays `[String: Any]` because a Swift type per
  kind would be another spelling of the table.
- `ReelEdit.swift` — what an op ANSWERS, mirroring `core/src/outcome.rs`:
  `ReelEdit` (`.applied` / `.identity` / `.refused`), `ReelRefusal` (the op
  the core declined and the rule's own sentence, carried verbatim), and the
  fold that applies a LIST — which names no `rc_*` symbol, so it lives here
  and not next door. **Only `.applied` is an undo step**; the other two are
  both "the project did not change" and differ only in what a caller can
  SAY. `.project` is the spelling for a caller that treats a refusal as
  nothing happened (a probe, a live drag), and there is one on
  `ReelEdit?` too for the `try?` probes. In the fold **a refusal does not
  stop the list** — a later op still runs after one, exactly as after an
  identity — and the FIRST refusal is answered only when nothing applied.
- `ProjectSnapshot.swift` · `TextProps.swift` · `MotionProps.swift` ·
  `WordProps.swift` — the `Codable`, READ-ONLY mirror of spec §5.2 every view
  draws from. **Its enums decode LENIENTLY**
  — a misspelt kind becomes the first case, a `T??` field a clear — which is
  why a caller-authored object is never decoded through them (below). The
  one exception is `ClipSource`: an unknown `source.kind` THROWS, and
  `ReelProject.snapshot` then falls back to `.empty`, so the WHOLE project
  draws empty with no error. A new source kind in the core is therefore a
  `ClipSource` case in the same phase (road map 10's G2a added `graphic`): no
  agent handler reads a caller-authored OBJECT at all. A scalar enum
  argument is a different thing and several handlers still parse one by name
  (`add_zoom_action`'s `fit`, `curveArg`, `set_transition`'s `kind`): the
  core refuses those too, and what this rule forbids is decoding a caller's
  object through a lenient type.
  `MotionProps.dictionary` always writes all three keys, `NSNull` for a nil
  slot, because a core patch of `motion` deep-merges — it is the
  APP's writer saying all three slots, not a replace rule, and it is the only
  edge that writes a whole motion. `MotionEdge` also supplies nonpersisted
  zero-duration activity and inactive display/menu titles (E2-27).
  `TextProps.swift` is the text group and `RecipeReveal` (with format version
  9's `textCase` / `words` / `wordStyle` and the recipe's `word` / `wordPop`),
  a pure move out of `ProjectSnapshot.swift` because a stored property cannot
  be added from an extension. `ProjectSnapshot+Graphic.swift` mirrors
  `model_graphic.rs`'s `GraphicProps` as `GraphicSnapshot` (`in` is
  `sourceIn`) and `GraphicPropValue` (string, number, bool; anything else
  `.null`), decoded into `ClipSnapshot.graphic`; `props` keys keep the
  module's own spelling (snake-case conversion does not reach a dictionary's
  keys). `WordProps.swift` mirrors `model_words.rs`
  (`TextCase`, `TextWord`, `WordMode`, `ActivePill`, `WordStyle`)
  — `WordStyle.dictionary` writes ALL six keys, `NSNull` for a nil slot,
  `MotionProps.dictionary`'s rule, because the core deep-merges
  `word_style` — and holds
  what the renderer and the inspector share: `laidContent` (`case` applied —
  every layout and string index is in ITS UTF-16 space, never `content`'s),
  `tokenCount`, `isUntimedPage`, `TextPatch.contentEdit` and
  `InspectorBinding.contentOps` / `ops(textContent:)` — the Content write,
  decided PER CLIP: `words: []` beside the content in one `set_text` only for
  base clips whose count changed, and never `words` in an action end (W-2,
  W-6). It lives there, not in `InspectorPane.swift`, for the size rule.

**The document.**
- `ProjectDocument.swift` (+`DisplayStem`, +`Recording`, +`SelectedAction`, +`Import`, +`Graphics`)
  — NSDocument, `.reelcut` package read/write, and the single mutation
  point (see Undo); `applyEdit`'s `.refused` arm beeps and then posts
  `projectDocumentDidRefuse` with the `ReelRefusal` (spec §11 CI-10), which
  the editor forwards to the inspector's refusal strip. Holds the SIX pieces of view state nothing persists —
  playhead, clip selection, in/out range, `selectedMedia`, `nestPath` and
  `selectedAction` — re-clamped by `clampViewState` in that order with the
  scope FIRST, since the selection clamp measures against whatever
  container the scope left. `selectedAction` (spec §11 CI-1) is nil or one
  action of the SINGLE selected clip; `+SelectedAction` holds its queries,
  its one deliberate writer `selectAction(_:)` (which stores nil for an id
  that is not `singleSelectedClip`'s) and the ENTRY rule
  `syncSelectedAction()`, run from `playhead`'s and `selection`'s `didSet`
  against `lastInsideAction`. The clamp re-reads `lastInsideAction` BEFORE
  its last line writes the playhead, so an edit, undo or redo under a
  stationary playhead never enters a span — keep those two lines above
  that write. `nestPath` is a
  PATH of (nest, clip) steps, not a nest id, because two clips can show one
  nest at two starts; `editedProject` is a STORED, memoised `rc_project_scoped`
  handle, and `project` still means the parent for save, export and
  consolidate. A range is cleared on every scope change: a pair of ticks
  means one thing inside a nest and another to an export.
  `+Import` is File ▸ Add Media… and every drop into an open project
  (`importMedia`, the probe chain and the one grouped commit). `+Graphics`
  is the document's side of the package's `graphics/`:
  `startGraphicStore()`, run from `makeWindowControllers()` and seeding an
  untitled document's root from `autosavedContentsFileURL/graphics`, and
  `graphicsWrapper()`, the lazy wrapper the save whitelist carries — for a
  SAVED document it reads `<fileURL>/graphics` itself and never asks the
  store, so a nil store can never drop a saved folder; for an untitled one
  it carries the store's root only when `GraphicStore.holdsContent` (an
  entry, file or directory, that is neither hidden nor the manual) says so
  (spec §11 G-14).
  `startGraphicStore()` also installs the document's compiled set in
  `GraphicRegistry` and observes the store's `.graphicsDidChange`, whose
  handler updates the registry and THEN posts `.projectGraphicsDidChange`
  (object: the document) — never `rescan()` there; `stopGraphicStore()`,
  from `close()`, removes the observer, drops the set and stops the store.
- `MediaImporter.swift` (+`Probe`, +`Speech`, +`Peaks`) ·
  `MediaPeakBuckets.swift` · `MediaCacheFiles.swift` ·
  `FFmpegRewrap.swift` · `AppSupport.swift` — the import funnel and the
  three per-media caches (`thumbs/`, `peaks/`, `speech/`) inside the package.
  `async`/`await` is confined to `MediaImporter.swift`; the await-free halves
  are the `+` files, `MediaPeakBuckets` and `MediaCacheFiles`. A cache is CURRENT when its
  `complete.json` marker matches `CacheStamp` (the source's size and
  modification second plus the constants that size the cache — no path, so a
  moved or consolidated package keeps its caches); the marker is written
  LAST and only for a strip the pass can vouch for. Peaks alone wrap the
  unchanged source stamp in `PeaksStamp` version 1 and require a complete
  selected-track decode, valid PCM coverage and a usable record-sized
  Float32 payload; legacy or malformed peaks are unavailable until rebuilt.
  A stale cache is deleted
  first and a withdrawn peaks `.bin` is POSTED at once; passes for one media
  run one at a time in call order through `CacheLedger` (an `NSLock`, not an
  actor). The cache order is thumbnails → peaks → speech. `thumbnails` holds a
  video track's last frame past its end, from the track's last SAMPLE's time.
  `FFmpegRewrap` is opt-in (`-RCFFmpegImport always`), runs `Process` on a
  serial queue, and writes conversions under `AppSupport` — the ONE spelling
  of `~/Library/Application Support/Reelcut/` — never in the package.
- `MediaConsolidator.swift` (+`EditorViewController+Consolidate`) — writes
  inside the package behind NSDocument's back, so it MUST call
  `ProjectDocument.packageContentsDidChangeOnDisk()` afterwards.
- `GraphicStore.swift` — one document's `graphics/` (road map 10 §5f):
  where it is (`<package>/graphics`, or an untitled document's
  `<NSTemporaryDirectory()>/Reelcut/<UUID>-graphics`, re-pointed by
  `packageDidMove(to:)` from the `fileURL` setter, posting
  `.graphicsLocationDidChange`), the scan (each legal `*.js` with its
  SHA-256 revision, G-13; `fonts/` validated on a throwaway
  `GraphicLibrary`; `assets/` with a 0-byte file warned and skipped) and
  the watch. **`graphics/` is created on the app's first write, never at
  open** (G-14): `ensureFolder()` is the ONE creator inside a package, and
  every app-side writer goes through `write(name:source:)` or it. While the
  folder is absent the store watches the PACKAGE directory, and the first
  observed appearance calls `folderDidAppear` →
  `packageContentsDidChangeOnDisk()` once — without it the next save is
  refused as "changed by another application". A folder source raises
  `.write` only and an in-place save raises nothing on it (G0 q7), so each
  module has its own source; every pass re-opens every source BY PATH and
  arms BEFORE it scans; events coalesce over 100 ms. The queue owns the diff
  and an outbox; main publishes in order through `drain()` (`scan`, the
  callback, `.graphicsDidChange` with sorted names — every module and
  `library: true` when the font/asset set moved; with NO names when the
  folder holds no module and only the library moved, which still posts, G5b).
  `uniqueModuleName(_:)` is the one free-name rule (`-copy`, `-copy-N`)
  Duplicate and Insert ▸ Graphic share. **`drain()` is not
  re-entrant: never call `rescan()` from a `.graphicsDidChange` observer.**
  `stop()` bumps a generation under `queue.sync`. `makeLibrary()` is a NEW
  builder every call (a library freezes on first use). It also writes the
  app's bundled reference into an EXISTING folder as `API.md` and `API.d.ts`
  (`writeManual()`, from `start()` for a saved package, `ensureFolder()` and
  `write()`; only when the bytes differ) — never a reason to create the
  folder (G-14).
- `GraphicScan.swift` — `GraphicModuleFile`, `GraphicFile` and `GraphicScan`,
  what one pass of the store found. `GraphicTemplates.swift` — pure: the
  bundled `GraphicTemplates/` modules (copied by `project.yml`'s post-build
  script), their titles from the file stem (never compiled — every chrome
  probe builds the menu bar) and a stem sanitised to a legal module name.
  `GraphicStore+Manual.swift` — the
  manual: `manualNames` (`API.md`, `API.d.ts`), `bundledManualNames`
  (`GraphicsAPI.md`, `GraphicsAPI.d.ts`, copied into Resources by
  `project.yml`'s post-build step from `docs/`), `manualDirectory(besideFonts:)`,
  `writeManual()` and `holdsContent`.
- `ReverseRenderer.swift` — `Source::Media.reversed` resolved to
  `cache/reversed/<id>-<digest>.mov`, rendered on demand behind a sheet,
  substituted per CLIP by `CompositionBuilder`.
- `ReverseMirror.swift` — the app's ONE spelling of the reversed mirror and
  its pivot (spec §11, D4-6), in the three units its readers hold it in:
  `MediaPeaks.window`, `TimelineView.sourceTime` and `ReverseRenderer`. The
  core keeps no mirror on purpose; `CompositionBuilder` needs none because it
  swaps the asset.

**Frozen files.** `EditorViewController.swift`, `TimelineView.swift`,
`PreviewCanvasView.swift`, `AgentServer.swift` are **frozen at current
size**: anything adding more than ~50 lines goes in an extension file
(`EditorViewController+<Feature>.swift`, `TimelineView+<Feature>.swift`,
`AgentServer+<Feature>.swift`) or a new `…SheetController`, and the frozen
file keeps only the wiring — a stored property, a closure assignment, a
validator arm, a draw call. The pieces extension files build on are therefore
internal, not private. Pitfalls: a selector declared `@objc` on an extension
needs NO forward in the frozen file (a second declaration is an error); a
command whose body sits at the foot of a non-extension feature file carries
its validator arm there too, or the item falls through to the closing
`return true`; `handleEditorCharacter`'s bare-key `switch` matches in SOURCE
order, so a bare `case "x"` goes BELOW any modified `case "x" where …`; and
`handleEditorKey` refuses while a sheet is attached, because a sheet is
window-modal and the preview panel's forwarded keys would otherwise reach
the key map behind it.

**The editor.**
- `EditorViewController+Graphics` refreshes the paused frame on
  `.projectGraphicsDidChange` for its own document.
- `EditorViewController+Timeline` / `+Canvas` / `+Inspector` / `+Toolbar` —
  installing the three panes and the toolbar (transport · timecode — view ·
  Export, nothing else). `+Timeline` holds the delete family, including ⌫
  with a range and nothing selected, which LIFTS, and ⌫ with an action
  selected, which removes the action. `+Actions` selects an action (the
  playhead to its end FIRST, then `document.selectAction`), leaves the mode
  (esc, `case 27` in `handleEditorKey`, false when nothing was selected),
  removes the selected one, and selects what ⌥⌘K, Zoom to Region and Zoom
  Back just added.
- `+AddClips` (Add Text / Add Shape: the front track, else a new one;
  `addGeneratedClip` is internal and takes `grouped:` — `performGroupedEdit`
  when the edit lands outside the menu's event, as a panel's completion does),
  `+GraphicMenus` (Insert ▸ Graphic's templates and From File…, File ▸ Add
  Font/Image to Graphics…; the template item runs in-event through
  `applyEdit`, the panels through `performGroupedEdit`; the shared body
  `insertGraphic(from:grouped:) throws` shows no dialog, and a module that
  does not compile stays on disk and places nothing — G-16),
  `+Clipboard` (⌘X/⌘C/⌘V over the `com.kgalligan.reelcut.clips` pasteboard,
  the `paste` op's payload; ⌥⌘V Paste Attributes with no `groups`),
  `+Edge` (slip, roll, close gap, insert, overwrite, the `,` / `.` nudge —
  with an `extension TimelineView` because the two ⌥⇧ drags begin there),
  `+Identity` (Rename ⇧⌘R, the Label submenu over `ClipLabel.allCases`),
  `+Nest` (⌘G / ⇧⌘G), `+NestScope` (⌘↓ / ⌘↑ and the double-click that enters
  a nest; the three marker commands validate OFF inside one, because a
  nest-local tick sent unscoped would land at the wrong project time),
  `+Motion` (Clip ▸ Motion ▸, one `set_video` PER CLIP; inactive stored edge
  titles refreshed at validation), `+Assistant` (`assistantSession()`: the
  window's live session or a new one, stored in the frozen file's
  `assistant` — spec §11 AI-4 — and closed by the window's `willClose`),
  `+Export` (the
  dialogs), `+SaveFrame` (⌥⌘E; renders off-main on `frameGrabQueue`; passes
  no burn-in), `+PreviewQuality`, `+Eyedropper` and `+ZoomRegion`.
- The two modal canvas modes (`+Eyedropper`, `+ZoomRegion`) install a bare
  view over the canvas whose PRESENCE is the mode, through `armCanvasMode`,
  which ends every OTHER armed mode first; a third mode inherits that by being
  installed at all. The region frame reads the EVALUATED props (the opposite
  of every session in `CanvasSessions.swift`) because a region is drawn on
  what is on screen; ⇧ during the drag chooses `fill`.
- `EditorWindowController.swift`, `WelcomeWindowController.swift`,
  `AppDelegate.swift` (+`Menus`, +`Recording`, +`GraphicMenu` — the Insert
  menu's builder and Help ▸ Graphics Reference, `showGraphicsReference`, on
  the delegate), `main.swift` — the window,
  the no-document window, the launch/terminate flow and the whole menu bar
  (spec §9). Menu items are nil-target selectors down the responder chain.
- `EditorWindow.swift` — the editor's `NSWindow` subclass: its `sendEvent`
  routes a bare Space to play/pause unless the first responder types or
  presses on it (spec §11 K-1), so Space never beeps when focus has fallen
  to the window. A new text-taking or Space-handling view must be added to
  `SpaceKey.route` and to `tools/proof/space_key_probe.swift`.

**Timeline.**
- `TimelineView.swift` (frozen) · `TimelineLayout.swift` (every ticks ↔
  points ↔ lanes conversion; `rowTop` is a prefix sum because S/M/L drives
  real heights per track KIND) · `TimelineBar.swift` · `TimelineClipDrawing.swift`
  (a clip is ONE object: body, name strip with the kind symbol, label dot,
  motion wedges for active edges only, filmstrip under a tint wash, waveform, grips on the
  selected clip, hatched transition zone) · `TimelineSessions.swift` (drag,
  trim, slip, roll sessions) · `TimelineView+Rename` (the one inline editor
  for clips, tracks and markers; it drops an unchanged and an empty commit,
  follows its target through relayout, and ends with its commit DROPPED when
  the target is gone) · `+TrackMenu` (the right-click menu on a header or an
  empty lane: the four toggles, checked, and Remove Track through
  `onRemoveTrack` to `removeTrackCommand`, which asks when clips would go;
  a clip hit answers no menu) · `+Candidates` (Remove Silences' wash, drawn not
  overlaid) · `+NestScope` (the breadcrumb, painted LAST in the ruler's
  corner so it stays above the header column when scrolled) ·
  `TimelineActionBands.swift` (each clip's action lane under its name strip,
  the band hit — `actionHit`, which `hit(at:)` asks AFTER the fade handles,
  since on an audio-only clip they sit inside the lane, and BEFORE the edge
  grabs, answering `.actionEdge` in a band's grip and `.action` in its body
  over the unchanged `actionBandHit` — the selected span's wash down the
  body and its shade on the ruler) · `TimelineActionDrag.swift` (spec §11
  CI-11: the band drag's begin/continue/end bodies, the hover, the cursor
  rects and the ghost with its HUD; `TimelineView.swift` keeps
  `actionDrag`, `bandHover`, one arm per gesture phase, a draw call, a
  cursor call and three one-line overrides on `TimelineContentView`).
  `ActionBands.swift` is what the timeline and the Clip tab's lane share:
  time order (an action's NUMBER is its index there plus one), the label's
  keys, the zoom test, the 5 pt `grip` and `gripEdge` (none on a band 15 pt
  wide or less), `curvePath`, and the ONE band painter — hover and grips
  are its `hovered:` argument, never a second painter.
  `ActionDragSession.swift` is the ONE session both lanes drag a band with,
  in clip time: frame snap, the two walls the core's refusals name, one
  `set_action` of start AND duration per tick, "Move Action" / "Resize
  Action", the HUD's text, and the HUD and ghost painters. It is only ever
  built for an action with a positive duration (`duration: 0` is invalid
  input to the core, not a refusal; no opened project holds one).
- `ClipLabel.swift` — the ONE home of the label and marker colour
  vocabulary; the core stores names unvalidated, so an unknown name draws in
  `DS.textStrong`. `ClipKindStyle.swift` — the ONE mapping from a clip to its
  tint, symbol and kind word; it asks whether the FILE has pictures, not
  `enabled.video`, which is the Detach switch.

**Canvas.**
- `PreviewCanvasView.swift` (frozen, 1132 lines) · `CanvasSessions.swift`
  · `PreviewCanvasView+TextEditFrame.swift` · `+TextEditKeys` — the picture at
  document size and the handle gestures. All coordinate mapping goes through
  `viewToCanvas` / `canvasToView`, and every handle maps through
  `AVPlayerLayer.videoRect`, which is the aspect of the BUFFER — the reason
  Preview Quality must keep the canvas's exact aspect. `+TextEditFrame`
  sizes the on-canvas text editor after every keystroke from the SAME
  measurement that sizes the applied box (`LayerRenderers.measuredSize`
  placed by `canvasRect`); never give the editor a second sizing rule, or
  the text jumps at apply (kpgalligan/reelcut#36). `+TextEditKeys` is the
  editor's keys (spec §11 K-2): bare Return applies, a modified Return is a
  newline, Esc over changed text asks Cancel · Revert · Apply in a sheet
  whose Apply goes through `performGroupedEdit` (a sheet completion is
  outside an AppKit event).
- `CanvasEditTarget.swift` — what a gesture edits (spec §11 CI-13): the
  base, or the selected action's END state. It reaches the canvas as
  `editTarget` through two writers, `refreshCanvas` and
  `canvasPlayheadMoved`, and a gesture captures it at mouse-down as
  `gestureTarget`, which every tick writes through; the sessions' `ops(to:)` /
  `op(to:)` ask it for `set_video` or `set_action_end` (and `set_text` for a
  text clip's width), and every `begin*` and the nudge start from
  `start(of:in:)` — one `clip_state` at the action's end, decoded through
  `InspectorBinding.decode`. A shape's box scale is `.base` whole
  (`forScale(of:)`): `set_shape` has no action form.

**Inspector.**
- `InspectorViewController.swift` (frozen: the tab strip, and the PINNED
  container between it and the scroll view that hosts a pane's
  `pinnedBlock`, one generation retired like the strip; the FOOT container
  under the scroll view, collapsed at priority 1 like the pinned one, which
  hosts `refusalStrip`, and the first line of `refresh(isLive:)` that
  clears a stale refusal; `selectClipSubTab`
  is a sub-tab pick's one refresh, and `refresh(isLive:)` calls
  `ClipPane.forgetSubTab()` whenever the selection's ids change, spec §11
  CI-5) · `InspectorRefusalStrip.swift` (spec §11 CI-10: "Refused: " and the
  core's sentence verbatim, remembered with the `editedProject` handle it
  was shown under and cleared on the first refresh under another handle or
  a click; `showRefusal` is the editor's forward of
  `projectDocumentDidRefuse`) · `InspectorPane.swift`
  (the pane base — `pinnedBlock` is the header `makeHeader()` built, never
  stacked — the row builders, whose four typed ones derive a row's DEFAULT
  from its own `read` and `ops` unless `resets: false`, and
  `InspectorBinding` — the one place that knows the fields read the
  SELECTED action's END state
  (`action(_:)` answers the selected action and never consults the playhead;
  `evaluated(_:)` asks `clip_state` at `clip.start + action.endTime`, spec
  §11 CI-2, or in `at(.start)` / `at(.playhead)` at the action's start or
  the playhead, over a cache keyed by clip and `ReadMode`; `.defaults` is
  what a row resets to — `VideoProps.identity`, `AudioProps()`,
  `TextProps()`, `ShapeProps()` — with no FFI and no cache entry, CI-9)) ·
  `InspectorSlider.swift` (`InspectorSliderControl`, a pure move: the 7 × 11
  block knob snapped to device pixels (CI-6) and, keyed, the mint segment
  from the action's start value and the coral playhead tick) ·
  `InspectorBinding+Writes.swift` (a pure move: a write with an action
  selected goes to `set_action_end`, with `structural(video:for:)` the
  exception that sends a list of a different LENGTH, or `motion`, to the
  BASE props, and `structural(audio:for:)` the one that sends pan, mono,
  compressor, noise reduction, duck and keep-pitch there (CI-3)) ·
  `InspectorSection.swift` (`InspectorSection` with its `id`, `title`,
  `header` and folded `marks` readable — `differs` from an explicit closure
  else the rows' defaults, `editing` the selected action's number when a
  row animates — `clear()`, `reveal()` which writes no preference and is
  instant, the header click's `toggle()`, the redesign's one animation,
  through `DS.animate(DS.stateDuration)` (unanimated under Reduce Motion,
  spec §11 CI-15; the state is set at once), and
  `didToggle`, called by the header's click alone; and `KeyedReveal`,
  `ClipPane`'s auto-open, CI-8) · `InspectorSectionHeader.swift` (a pure
  move, then CI-9: the `◆N` / ◇ / ⊘, the one trailing slot — Clear while
  editing an action that keys the section, else Reset while it differs —
  `buttonTitle`, and `summaryInk`'s three tiers; the summary stops short of
  the VISIBLE button) ·
  `InspectorMarks.swift` (spec §11 CI-7: `RowMark`, `SectionMarks`,
  `InspectorRowDefault` (CI-9), the
  14 pt `InspectorMarkGutter` that is the FIRST view of every
  `inspectorRow` — blank at `.none`, so it must stay first for the refresh
  walk to reach it before the controls whose label ink and layer border it
  sets; hovered while keyed it draws × and a click removes the row's keys —
  `InspectorRowTag` ("at end", "now …"), and the binding's mark
  queries, `selectedActionNumber`, `actionID(number:)` and `clearOps`, the
  ONE `set_action_end` of nulls; a row's paths come from the ops it WRITES,
  `writes:` / `follows:`, and an un-annotated row is `.none`, never ⊘) ·
  `InspectorRowMenu.swift` (`InspectorRowView`, the row's stack: its own
  tracking area sets the gutter's hover, and its context menu — Remove from
  action N, Go to action M, Reset to default / Set end value to default —
  never reads the hover) ·
  `ClipPane.swift` (the sub-tabs — `subTabs` by kind, `activeSubTab`, and
  `choose` / `forgetSubTab`, which never refresh — and `makeSections()`, the
  function from the selection's kind and the active sub-tab to its
  sections, with the open rule per tab) · `ClipPane+Timing.swift` (the
  Timing section — `timingSection`, `reverseTimingSection`, `reverseRows` —
  a pure move out of `ClipPane.swift`; `makeSections()` is its only caller) ·
  `ClipSelectionHeader.swift`
  (`ClipSelectionHeaderView`, a pure move out of `ClipPane.swift`) ·
  `ClipPinnedBlock.swift` (`ClipSubTab` — six cases in display order, text,
  shape, graphic, picture, sound, clip; `graphic` keys nothing, G-10 — with
  its `◆N` key count,
  `ClipSubTabsView`, and `ClipHeaderBlock` — header, lane, sub-tabs — which
  `makeHeader()` builds once per pane build) · `ActionLaneView.swift` (the
  action lane, the Actions section's replacement, with the clip and action
  ids it shows captured, and the stored `drag` / `pressed` / `hover` its
  forwarding mouse overrides feed) · `ActionLaneView+Drag.swift` (the band
  drag in the lane, CI-11: a press records the band and starts a session
  only for a positive length, and the RELEASE selects — a click and a drop
  alike — so the pane never rebuilds under the pointer; the last band
  holding a point wins, the one painted on top) · `ActionLaneDecor.swift`
  (CI-12: the lane's hatch, fades and wedges as geometry by the timeline's
  own gates, drawn under the bands; `Curve.laneName`; `CurveGlyphView`,
  beside the Curve popup because `OptionPopupControl` is not forked) · `VideoPane.swift` (+`Transition`,
  +`Motion`, +`Obscure` — the Obscure section, a pure move) · `AudioPane.swift` · `TextPane.swift` · `ShapePane.swift` ·
  `GraphicPane.swift` (the Graphic sub-tab, road map 10 §5j, spec §11 G-15:
  a factory `ClipPane` calls when EVERY selected clip is a graphic; the
  shared module from `GraphicRegistry.entry(named:for:)`, main only, never a
  rescan; a structure signature of schema keys and types, stale keys, the
  asset popup's names and diagnostics — never values, the revision or the
  playhead; Properties, Size and Timeline; every write is `set_graphic`) ·
  `GraphicPane+Source.swift` (Source: name, file, revision, Open / Reveal /
  Duplicate as New Graphic… — `store.write`, `rescan()` inside the button's
  event, one `set_graphic {name}` step — and `report(for:)`, the compile's
  diagnostics plus the first frame rasterized at the clip's OWN size,
  memoised and frozen during a live gesture) · `GraphicSchemaRows.swift`
  (pure, probe-callable: the schema in the MODULE's key order —
  `GraphicSchema.orderedKeys` scans `describeJSON()`'s text because the
  registry's dictionary lost it — one row per schema type, stale rows
  sorted with ⌫ writing `null`, CSS ↔ `RGBA`, and the null rule: a value
  equal to the default is written as `null`, a colour compared by parsed
  channels) ·
  `DocumentPane.swift` (reads `documentSnapshot`, never the scoped one: its
  ops are document-level) · `OptionControls.swift` (the descriptor-driven
  row controls) · `OptionControls+Choices.swift` (the typed, value-carrying
  `OptionPopupControl` init over the index one). `VideoPane+Motion.swift` owns the local wrapping
  `MotionInactiveNote` for selected zero-duration edges; it refreshes with
  the section and leaves stored kind and Duration editable. Its old "Motion
  belongs to the clip" note is gone: every Motion presets row is ⊘, so the
  section's own ⊘ note says it.
  `TextPane.swift`'s Style section carries UPPERCASE (`case`, through
  `binding.apply` like `align`); its Content write is
  `binding.ops(textContent:)` (`WordProps.swift`). On a word-styled page the
  Animation section's three rows are greyed with W-5's sentence, and a styled
  page left untimed carries the Content footnote; nothing in the inspector
  writes `word_style` (W-10).
- Pitfalls, each measured: **a section factory is not a section until
  `makeSections()` calls it** — nothing type-checks the omission, and two
  phases shipped a section invisible in the app; `editedList` — a write of a
  list-valued key is built from the list it is about to REPLACE (the action's
  end list, else the base), never the evaluated one; the collapsed-state
  `UserDefaults` key records COLLAPSED, so `defaultExpanded` applies only when
  nothing is stored; a field's `refresh` is skipped while its field editor is
  attached, which it still is inside `controlTextDidEndEditing`; the pane's
  low-priority bottom pin is **249**, one below `.defaultLow`, because at 250
  it tied with a section's hugging and the solver picked per PROCESS; and
  `rebuild()` destroys every control and preserves no first responder, so a
  control a person TYPES into must live outside `structureSignature` and be
  applied to views that already exist (`MediaPane.arrange()` is the shape).
- `MediaPane.swift` · `MediaRowView.swift` (a row and the drag it starts,
  with `MediaDropMode` read from `NSEvent.modifierFlags` at the drop) ·
  `MediaPaneCommands.swift` · `MediaListFilter.swift` (the find band as a
  VALUE; not persisted) · `MediaUsage.swift` (the ONE spelling of "is this
  media used", over the timeline's clips AND every nest's) ·
  `MediaReveal.swift` — the Media tab. The find band never rebuilds the pane.

**Playback and rendering.**
- `Playback.swift` (+`Meter`) — one `AVPlayer` over the plan's composition; the
  transport, JKL, the rate KVO; `+Meter` is the level meter, moved out under
  the size rule. **Only a seek someone ASKED for reports a time**:
  `seek(to:)` is that door, and Playback's own RESTORES — the rebuild's item
  swap and re-seek, the paused refresh's round trip — go through `startSeek`
  silently and report once, only if they come to rest off the last reported
  tick; `report(_:)` is the one caller of `onTimeChanged`. An echoed restore
  moved the playhead (0 and back on every rebuild), and the timeline reveals
  every moved playhead, so a clip drag yanked the view
  (`playhead_echo_probe.py`). **A paused refresh is a one-tick round trip**
  (`refreshPausedFrame`): a zero-tolerance seek to the current time is a
  NO-OP on macOS 26.5.1, so the refresh seeks one tick off and returns; parked
  at the end it rests on the last frame's final tick, because the end tick
  composes black. Do not put a same-time seek back. Preview Quality overrides
  `renderSize` on a `mutableCopy()` of the composition here, keeping the
  canvas's EXACT aspect (`m · (w/g, h/g)`, coarser when the divisor does not
  divide `g`, Full for a coprime canvas); `AVPlayerItem.videoComposition` is
  a COPY property, so the setter re-assigns. `makePreviewLayer` is the one
  door to a second `AVPlayerLayer`.
  The item is dropped only for an EMPTY timeline (`plan.duration <= 0`,
  where the transport beeps). Never gate it on the plan's track lists: a
  timeline of only graphics, text, shapes or images has no plan track and
  plays over the builder's placeholder (road map 10 §10.8,
  `media_less_playback_probe.py`).
- `CompositionBuilder.swift` (+`InstructionRanges`, +`AudioTracks`) — the app's ONE
  constructor of `AVMutableVideoComposition`, shared by the preview, both
  export passes and the offline frame. **Do not give it a preview-shaped
  argument**; the `metering` flag is passed true by `Playback.startRebuild`
  and nothing else. `fill` holds a video track's last frame over any part of
  a segment the track does not cover (a screen recording's picture ends at
  the last screen change). `+InstructionRanges` ends the last instruction
  exactly on the composition when the two differ by under a tick — AVPlayer
  refuses an invalid composition SILENTLY, black at every time, while the
  generator and the writer tolerate it. `+AudioTracks` builds the audio
  half: an audio plan track becomes one composition track per source stream
  format (spec §11 R2-1) — a tapped track that changes format part-way
  STALLS the player (kpgalligan/reelcut#34), so never feed one composition
  track two formats.
  `addPlaceholderIfNeeded` gives a plan with no video track but a duration
  a one-frame `Blank.mp4` track scaled across it. The preview's item, both
  export passes and the offline frame all rely on it for a media-less
  timeline.
- `RecipeSource.swift` — the process-wide registry the compositor reads a
  recipe from (§7.6): a slot per document (`ProjectDocument.recipeKey`) and
  per export (`Exporter` mints its own), the project published under `set`
  after every edit and the `RecipeOptions` stored BESIDE it per key, both
  read under one lock hold in `recipe(for:at:)`.
- `GraphicRegistry.swift` · `LayerRenderersGraphic.swift` — a graphic layer
  drawn (road map 10). The registry maps a `RecipeSource` key to one
  immutable `GraphicSet` (library, `libraryVersion`, each module `.compiled`
  with `meta`/`schema` or `.failed`), installed at store start and swapped on
  `.graphicsDidChange` — a NEW library and every module recompiled only when
  `library` is true (or the last library failed to build), else just the
  named modules against the existing (frozen) library. `install`/`update`/
  `remove`/`entry` are main-only; `resolve` is the one cross-thread read of
  the set: a document's own key at the 250 ms preview budget, a PINNED
  offline key at 2 s, else nil — the slate. **An offline key draws only what
  its caller pinned** (`pin(set, for: key)` with the document's
  `snapshot(for: recipeKey)`, captured on main): every `pin` has its `unpin`
  — `Exporter.finish` AND `deinit`, and `renderFrameReported`'s `defer`. A
  pin also keeps its REPORTS: the first failure in a slot of its own for the
  pin's life, then at most 64 distinct warnings, so a warning can never
  displace a failure. `LayerRenderersGraphic` hands the engine the core's
  own `props_json` / `ctx_json` untouched and keys the texture by the SVG
  TEXT, the size and the library version, in `LayerRenderers`' separate
  six-entry graphic pool. A graphic that fails — no module, not compiled, a
  throw or timeout, a refused raster — draws its ERROR CARD, keyed by its
  own text in the graphic pool, never the last good frame; a raster's
  warnings ride in `Rendered.warnings` so a pool hit still reports them.
  Only no set and a failed upload are nil.
- `Compositor.swift` · `CompositorEffects.swift` · `Resources/Shaders/Compositor.metal`
  — the per-layer pass. The uniform block's field ORDER is a contract with the
  shader checked only by reading both, so change them in one edit; it is 104
  floats and **the padding tail is EMPTY** (the next field needs three
  companions). **Five pipelines from three fragment functions**: the two
  programmable-blend pipelines MUST be built with fixed-function blending
  OFF, or the finished pixel is blended twice — invisible over an opaque
  destination, so a proof of it reads the ALPHA channel over a translucent
  one. A shadow's silhouette pass takes `maskState`, the gather
  specialization without the blend (defensive, not load-bearing). Blending
  is in the ENCODED sRGB space, deliberately. `[[position]]` arrives in
  DESTINATION pixels, and `canvasPerDestX/Y` is what turns it into canvas
  pixels — an invariant that held only because the two had always been
  equal, until Preview Quality. A layer mid-transition blends `normal`
  because the CORE emits it; grow no second opinion here. Where two obscure
  regions cover one fragment the GREATER hiding wins.
- `LayerRenderers.swift` · `LayerRenderersText.swift` · `LayerRenderersReveal.swift`
  · `LayerRenderersWords.swift` — text and shape descriptions to textures,
  keyed by the recipe's `hash` (`RecipeSourceRef.cacheHash` is the WHOLE key;
  nothing here may append to it — a graphic's key is its SVG text instead,
  `LayerRenderersGraphic.swift`, in its own six-entry pool). Text draws what the recipe computed; the
  LAYOUT is always the full text's, laid from `laidContent`, cached without
  the reveal or the word, and `reveal = 1` takes the plain `CTFrameDraw` path
  so a full reveal is byte-identical to no animation; a line or token at
  PARTIAL alpha draws inside a transparency layer so fill and stroke composite
  once. `LayerRenderersText` is measuring, layout, the per-axis `textInsets`
  and `drawText`, which dispatches — the words arm FIRST, then the three
  reveals, which are `LayerRenderersReveal`'s. `LayerRenderersWords` is a
  timed page (road map 8's W3): tokens of `laidContent` only, clipped at the
  whitespace midpoints; the active token `word − 1` scaled about its pill's
  centre, the pill filled UNCLIPPED, then the midpoint clip set in TEXT space
  so it scales with the token. `wordHeadroom` sits inside `measuredSize`
  (zero with no style or a colour-only one; 0.45 em and 0.30 em are FLOORS
  under the formula, plus `wordHeadroomEdgePx` horizontally and `wordHeadroomVerticalEdgePx`
  vertically; with NO pill the horizontal term ADDS the popped stroke,
  `peak × outline / 2`, where a pill's keeps `− outline` — road map 8
  §10.7, W4a), so the box never depends on
  `word`, and `layoutKey` gains `case` and the headroom's inputs only when set
  — never `words`, `word` or `word_pop`. `renderTextBitmap` is the drawn
  bitmap `renderText` uploads; its body is `static textBitmap`, which the
  Generate Captions sheet's preview draws with, off-Metal (road map 8's W4b). A shape's gradient SORTS its stops (the core
  does not police order), projects a linear ramp onto the box, and is ignored
  by `line` and `arrow`.
- `AudioTap.swift` · `AudioDSP.swift` — the `MTAudioProcessingTap` playback
  and export share, and the four sample-level effects: noise reduction (a
  512-sample delay), the compressor, the mono fold (BEFORE the pan, or it is
  algebraically self-cancelling) and pan (constant-power, unity at centre).
  A track whose clips ask for none is bit-identical.
- `Exporter.swift` · `ExporterLoudness.swift` · `ExporterSettings.swift` ·
  `ExporterWriter.swift` · `ExporterImageSequence.swift` ·
  `ExporterErrors.swift` · `ExporterGraphics.swift` — the writer
  (`ExportWriter` REPLACED `AVAssetExportSession` so chapters, bitrate and
  size have one path) and the one-frame offline render. An export is TWO
  passes wherever the file holds sound: a measurement build of its own in
  32-bit float, then the write with the gain applied to decoded Int16 (which
  saturates BEFORE the gain: a mix that clips is measured honestly and still
  clipped). `ExportWriter` refuses an alpha-carrying row at a PADDED size
  (padding inverts the alpha; a pure scale is fine), testing the box the
  ENCODER is handed through `encodedSize`; `apng` FITS instead and must not
  grow the guard. GIF and APNG refuse past 600 frames rather than truncate.
  `renderFrame` is documented off-main. Audio export is NOT bit-deterministic
  within an 8 ms window at a duck ramp edge (AVFoundation's mix); a duck-free
  project decodes byte-identical. `ExportError` is `ExporterErrors.swift`'s.
  An export PINS the `GraphicSet` it was handed for its whole life, GATES it
  before the build (`ExporterGraphics.graphicsRefusal`: a graphic clip in the
  range, or in a nest a clip in the range shows, whose module did not
  compile or is missing, refuses before the destination is touched), and
  ABORTS on a recorded failure: `pollProgress` cancels and `finish` removes
  the file and answers `.graphicFailed`, whatever the pipeline said.
  **`ExportWriter.cancel()` only sets the flag**; the reader and the writer
  are cancelled in `allInputsFinished`, after every pump has left its loop —
  cancelling the reader under a running `copyNextSampleBuffer` crashed the
  process. Never call `cancelReading` from another thread while a pump runs.
- `FrameWriter.swift` — a `CGImage` and a format in, a URL out, no panel:
  Save Frame and `render_frame` both call it, so their PNGs are
  byte-identical by construction. PNG keeps a NIL properties dictionary
  (anything added changes the file); JPEG flattens onto BLACK at 0.9; HEIC is
  `UTType.heic`, never `public.heif`.

**Captions.** A caption is an ordinary text clip, which is what makes burn-in
free.
- `CaptionLayout.swift` — placement ONLY (snap, abut, drop sub-frame
  cues, a new front-most track), shared by every producer, and
  `CaptionCues` at its foot — the FIVE cue rules (≤ 2 lines, ≤ 42
  characters, ≤ 6 s, a frame between cues, and never two speakers in
  one cue), used only by a producer that must INVENT line breaks. An
  SRT brings its own. `Word.speaker` defaults to nil, so every caller
  that knows nothing about speakers is byte-identical to what it was.
  `place` takes a `CaptionStyle`: `.subtitles` is the Caption-preset
  path, byte for byte; a word style writes `CaptionStyle.pagePatch` per
  page — the pager's own props at the page's size (a shrunk one or the
  style's), its wrap `width`, and the cue's `words` in CLIP time — at the
  style's `y`. `replacing` removes caption tracks WITH
  their clips as the plan's FIRST ops (a removal mints no id, so the
  new track is still `next_id`), and `replaceableTracks` is the one
  test of which qualify: named "Captions"/"Captions N", AT LEAST ONE
  clip, only text clips, each overlapping a job's `span` — an empty caption
  track is never replaced.
- `CaptionStyle.swift` — road map 8 §5h's five word styles and
  Subtitles as one enum: the PostScript face, `case`, size (of
  min(W, H)), `y` (of H), outline, `word_style`, `maxWords`, `maxLines`,
  `textProps`, the ONE construction the pager
  measures and the sheet previews, and `pagePatch`, the patch `place` writes,
  built from it — so a committed page is the measured one and a shrunk
  page's outline is em × its own size. A GENERATION choice, not an inspector preset;
  `defaultsKey` is the sheet's remembered style, read when the Style popup
  is built and written by `styleChanged`; the tool never reads it (R6-2
  read across).
- `CaptionPages.swift` — word-caption PAGES (spec §11 W-7), pure and
  synchronous so it runs on whichever engine thread calls it:
  `normalize` (trim, split, sort, the per-engine `lead` — its ONE home —
  and the clamp into the job's `span`, a word pushed off the end on the
  clip's last frame), the pager (speaker, 0.25 s gap, sentence mark,
  3 s, `maxWords`, and the MEASURED width through
  `LayerRenderers.measuredSize`), the balance step once per width
  break, the clause preference, shrink-then-wrap for a lone word, and
  page timing that abuts under `breakGap` and never passes the span.
  `cues(...)` is what both engines call: `.subtitles` goes to
  `CaptionCues.build`, untouched. `samplePage` is `cues(...)`'s first page
  over a span past the words' hold — the sheet's preview page, a real one,
  balance step included. Pauses are word gaps and punctuation;
  `SilenceDetector`/`MediaSpeech` are not consulted.
- `CaptionImporter.swift` (SubRip grammar) · `CaptionExporter.swift` (`.srt` /
  `.vtt` from one all-text track, never guessed; a popup built from
  `NSMenuItem`s carrying `representedObject`, because `addItem(withTitle:)`
  REMOVES a same-titled row).
- `CloudTranscriber.swift` (+`Report`, +`Media`) — `TranscriptionEngine` (`apple` |
  `assemblyai`, persisted under `ReelcutCaptionEngine`) and the cloud engine
  over the SAME `Transcriber.Job` / `Outcome` / `CancelToken`. `run` is its
  serial queue and the main-thread completion; `transcribe` is the
  synchronous body — the janitor FIRST, the jobs grouped by MEDIA, each
  media classified cached / HELD / to upload, then each job's words cut out
  of its media's one transcript. `+Report` holds what the `Outcome` has no room
  for (`uploaded` with the initial transcript-write result, `cached`,
  `janitorDeleted`, `janitorFailed`, `janitorDeferred`, `held`) and owns the
  shared cleanup warning wording for the sheet and MCP result or failure.
  A nil client admits only a nonempty, entirely
  current batch and skips janitor/network, retaining pending IDs as deferred.
  One media's failure is one media's problem
  and the run carries on, with exactly two exceptions: a CANCEL and a
  REFUSED KEY. `+Media` holds `retryDeletes` and `fetch` — the ten-hour
  refusal BEFORE the extract, the `defer` that removes the temporary audio on
  every exit, the cache file written before its marker, and the DELETE last
  with its answer recorded. Spec §11's R6-11: a media in this run's
  `janitorFailed` is never fetched, since its cache file is the one record of
  the id still owed a delete.
- `CloudEstimate.swift` — what a cloud run would COST and why, PURE: a
  `Fate` per media (`upload(Reason)` / `cached` / `awaitingDelete(Reason)` /
  `unreadable`), `describe` (the sheet's summary line), `reasons` (one line
  per file that is not already transcribed, plus the DATED rate) and
  `money`, over `AssemblyAIRates`' two dated constants. Spec §11's R6-13: a
  media R6-11 will hold is its OWN clause and its line carries what it would
  cost if the delete clears. `facts(jobs:media:cacheDirectory:)` is the ONE
  member that opens a file, so a sheet can recompute the readout per
  keystroke. `canReuseWithoutCredential` is true only for nonempty all-cached
  rows and gates the keyless sheet. Its classification is deliberately NOT shared with
  `CloudTranscriber`'s — one says what a run WOULD do, the other what it DID
  — and a probe row compares them.
- `CloudProgress.swift` — the cloud run's one number and the words beside it,
  PURE: a share per media TO UPLOAD (cached and held media have none), the
  four phases at 0.25 / 0.65 / 0.95, the wait advancing on the clock against
  q8's 147× and holding, and the four detail lines. The run publishes
  `max(previous, computed)`.
- `AssemblyAITranscript.swift` — the wire VALUES, and
  `TranscriptOptions.keyterms`, the ONE spelling of the vocabulary's
  trim/de-duplicate/cap that the sheet's field and the tool's argument share:
  `TranscriptOptions`,
  `TranscriptRequest` (whose `encode` is the whole wire body — `language_code`
  absent for auto, `keyterms_prompt` absent when empty), `TranscriptWord`,
  `TranscriptResponse` and `JSONValueRange`. `TranscriptStamp.swift` owns the
  cache marker: `TranscriptSourceStamp` projects `CacheStamp` to size,
  modification second, duration and audio presence, then pairs those with
  the provider and REQUEST (R6-15); old wide markers decode by projection.
  Nothing here speaks HTTP or touches disk. **Three encoders write every key
  with nil as `null`** through
  `encodeOrNull`, because `encodeIfPresent` would drop a key a cache file and
  its marker have to carry; `TranscriptResponse` reads `words` through a
  `try?` so the CLIENT's rule about a missing words array is the sentence a
  caller gets.
- `AssemblyAIClient.swift` (+`Session`, +`Submission`) — AssemblyAI's REST API as five
  SYNCHRONOUS calls over one `.ephemeral` `URLSession` with its own one-wide
  delegate queue (R6-7: no `async`). `willPerformHTTPRedirection` always
  answers nil, so a 3xx is `.redirected` and the credential reaches no other
  host; an upload retries once on a 5xx or a transport error and never on a
  4xx or after a cancel; `poll` sleeps in ≤ 0.1 s slices that read the token
  and EVERY throwing exit deletes the transcript first. A `completed` body
  whose `words` is absent, null or not an array is `.malformed`, never an
  empty transcript; `[]` is zero words. `request` and `send` stay in the
  first file, with `withoutCredential(_:)` beside them: those three are the
  members that touch `credential`, and that helper keeps the three sentences
  the client RELAYS verbatim — a 402's, a 4xx's and a transcript's `error` —
  from carrying a key a server echoed back. `delete` answers THREE states
  (`deleted`, `failed`, `notSent`): an id that is not a plain identifier is
  never put on the wire. `+Submission` owns the single paid submit and R6-14's
  bounded recovery: three newest-page looks for an exact uploaded URL, with
  no retry of the POST or requests by any unrelated id.
- `AssemblyAIConfiguration.swift` · `AssemblyAILanguages.swift` ·
  `SecretStore.swift` — WHERE the client speaks and WHAT it says it is.
  `AssemblyAIConfiguration` is the ONE reader of `-RCAssemblyAIEndpoint` and
  `-RCSecretFolder`, both out of the ARGUMENT domain only (its `argument` is
  the one argument-domain reader, which `AssistantConfiguration` and
  `DevAssistantLaunch` reuse), and the ONE line
  in the feature that names `AppSupport.directory` (spec §11's R6-9: with an
  endpoint set and no secret folder, `store()` answers an EMPTY `MemoryStore`
  so a proof never opens the person's key). `FileStore` has a `name`:
  `assemblyai-key` by default, `anthropic-key` for the assistant's key
  (AI-8, AI-13, whose `RC_ASSISTANT_BASE_URL` plays R6-9's endpoint). Non-`https` is accepted only for
  `127.0.0.1`, `localhost` and `::1`. `FileStore` creates its file with
  `O_CREAT|O_EXCL` at `0600` under a temporary name and `rename(2)`s it, in a
  directory it `mkdir`s at `0700` — never `chmod`ed after; `MemoryStore` is
  the probe's. The language table is a DATED static list, not an authority:
  a code AssemblyAI refuses comes back as AssemblyAI's own sentence.
- `MediaTranscript.swift` — `cache/transcripts/<id>.json` and its
  `.complete.json` sidecar (`MediaImporter.transcriptsKind` is the post kind,
  and lives beside the other three in `MediaCacheFiles.swift`). The provider's
  `words` are stored VERBATIM as BYTES: `File.encoded()` splices `wordsJSON`
  in after a `.sortedKeys` header, `init(data:)` cuts it back out with
  `JSONValueRange`, and neither ever re-serialises — a `0.98` does not
  survive that. Both `File` inits throw on a `words` that is not an array, so
  `read` answers nil and `isCurrent` false rather than caching zero words.
  THE MAPPING is here: a word is a clip's when `in ≤ start × 600 <
  in + duration × speed`, landing at `start + (m − in) / speed`, clamped
  through `Transcriber.placed` (R6-10). That `× 600` goes through
  `sourceTicks(milliseconds:)`, the one integer multiply on the caption
  path, clamped in `Int` to ±`Ticks.max / 600` first and deliberately NOT to
  `maxSourceTicks` (R6-10's extension).
  `Loader` is `MediaPeaks.Loader`'s shape; `undeleted(in:)` is the janitor's.
- `SpeechEngine.swift` — the on-device engine (`SpeechAnalyzer`,
  `SpeechTranscriber`, `AssetInventory`) and the ONE file under
  `app/Sources` that imports Speech or says `async` for it (spec §11 W-8).
  Every entry point is synchronous or a main-queue completion: `transcribe`
  refuses main by precondition and blocks its caller on a semaphore a
  `Task.detached` analysis signals, waited for in 0.1 s slices so a cancel
  answers at once, bounded at max(120, 4× the audio); the asks
  (`supportedLocales`, `installedLocales`, `isInstalled`) answer `[]` or nil
  past `askBound` (10 s); `download` is the Download row's alone and no tool
  calls it. **Never `Task {}` here** — a main-thread caller's actor would be
  inherited and the semaphore would deadlock. `Handle` is what
  `CancelToken` holds for a running analysis. Two host facts it is built on
  (road map 8 §10.6): `status(forModules:)` is `.installed` only for a
  RESERVED locale, so `isInstalled` reserves, reads and releases what it
  reserved; and `release(reservedLocale:)` matches the framework's own
  spelling (`fr_FR`, not `fr-FR`), so a release walks `reservedLocales` by
  BCP-47 tag. Every path that constructs a transcriber releases on every
  exit (a cap of 5). Reserve → status → release and every release run one
  at a time, in arrival order, through the `Gate` actor; `releaseNow` is the
  in-gate form, and an analysis or a download SIGNALS its caller before it
  queues its release, so a stalled gate cannot hold a finished run hostage.
- `Transcriber.swift` (+`Languages`, +`Extract`, +`Jobs`) ·
  `TranscribeSheetController.swift` (+`Cloud`: the AssemblyAI half — the
  Language popup's second population, `RunRequest` (the ONE function from
  the card's controls to what a run would receive), the estimate's readout,
  §5e's two hint texts, the notes and `beginCloud`; +`Commit`: the run's one
  exit, `cloudReportLines` and the menu command with its validator arm;
  +`Download`: the Download row; +`Style`: the Style popup, the preview and
  the Replace checkbox with its list — `style`, `replaceExisting` and
  `pagesRequest` COMPUTED off those controls) — on-device recognition through
  `SpeechEngine` (spec §11 W-8: no grant, no ceiling, nothing `async` here)
  over each clip's source window EXTRACTED to a temporary mono 16 kHz WAV,
  on `Transcriber`'s serial `work` queue with the one completion posted to
  main. "Has sound" is `enabled.audio`, not the media's track. One job's
  failure is reported under `problems` and the run carries on. `transcribe`
  asks `SpeechEngine.isInstalled` for the ONE chosen locale first — nil (a
  slow ask) is `.unavailable`, false is `.notInstalled`, never the other way
  round. `+Languages` ASKS both lists of the engine and tags every row in
  BCP-47 (`identifier(.bcp47)`, `en-US`, never `en_US` — a raw compare
  never matches); `languages()` is the installed rows, `supportedLanguages()`
  every row marked `installed` from the installed SET (no transcriber per
  locale: a reservation cap of 5), `forgetLanguages()` drops both caches,
  and `defaultLanguage(in:)` prefers an installed row at each step. The
  tool's refusal ORDER is the caller's own mistakes first (scope, `engine`,
  cloud-only arguments, the tag's spelling), then the installed model, then
  the run; the tool NEVER downloads — a person does, from the sheet. `Job`
  carries `media` for the cloud engine, which uploads a MEDIA once;
  `CancelToken` holds a `SpeechEngine.Handle` and a `URLSessionTask`, under
  one lock and cancelled outside it. Both engines hand each job's words to `CaptionPages.cues` with the
  job's `span` and their own `TranscriptionEngine`; `Job.span`
  (`+Jobs`) is the one spelling of a job's timeline span. The sheet's `style` is read off the Style popup's item and
  `replaceExisting` is true only while the checkbox is ENABLED and on —
  enabled only for a word style over tracks `replaceableTracks` names, the
  tool's two rules — and `finish` passes both to `place`, so the sheet
  commits what `transcribe {style, replace}` commits. The preview is
  `CaptionPages.samplePage` of the first job's cached transcript (up to
  twelve words) else "This is how it looks", laid out by the style's
  `textProps` and drawn by `LayerRenderers.textBitmap`: two stacked frames
  for a word style (the first word active, then the second), one for
  Subtitles, over `DS.captionPreviewPlate`. `sampleWordsCache` stores the
  ANSWER per clip, a miss included, and the drawn preview is cached under
  `PreviewKey` (style, first job's clip, canvas) in `previewKey`, so a
  Vocabulary keystroke reads and draws nothing. `refresh()`'s `defer` runs
  `refreshStyleRow()` then `refreshDownloadRow()`. `+Jobs` is no longer a pure move: it
  owns `maxSourceTicks` (1e15) and `placed(offset:in:)`, the ONE door both
  caption mappings convert through, because spec §11's R6-10 says a
  hand-written `speed` the ops cannot write reaches the app and every
  `Double → Ticks` there has to clamp IN `Double` first — the offset at one
  end, the source length and `Job.sourceIn` at the other. `+Extract` is no
  longer only the on-device extractor: `extractAudio(url:name:range:to:)` is
  the general form, `wholeAsset` is what a cloud run asks for,
  `writeFLAC(fromWAV:to:)` is the 16 kHz mono 16-bit FLAC through
  `AVAudioFile` (NEVER `AVAssetWriter`, which has no FLAC file type on macOS
  26 and refuses as an uncatchable Objective-C exception), and
  `extractUpload` is the pair with the WAV as the fallback when the FLAC
  write refuses. **The sheet's three readouts — `refresh`, `noteText` and
  `startClicked` — dispatch on `engine` as their FIRST statement**, and
  under `.assemblyai` none of them reads `language` or `languages`: a Mac
  with no on-device model can still transcribe in the cloud. The Language
  popup lists every SUPPORTED locale, a missing model titled "— not
  installed", and Generate is live only for an installed one. **The
  Download row** (grid row 1; `cloudRows` is `[3, 4, 5]`; Style,
  preview and Replace are rows 7, 8 and 9) shows for an
  uninstalled apple language or while a download runs; `downloading` names
  the running download's locale, and while it is set BOTH popups are
  locked — applied in `refreshDownloadRow()`, AFTER `populateLanguages()`
  sets the popup's own `isEnabled`, never inside it — and the label names
  that locale whatever the popup shows. `downloadFinished` captures the
  identifier before `populateLanguages()` reselects the default and selects
  it again after; a cancel is not reported. Closing the sheet mid-download
  lets the download run on (a decision). `init` takes `store`, `defaults`,
  `environment` and `languages` so a probe can build every one of those
  states.
- `SilenceDetector.swift` (+`Walls`) · `SilenceSheetController.swift` ·
  `SileroVAD.swift` · `MediaSpeech.swift` · `MediaPeaks.swift` — Remove
  Silences and `detect_silence`. The detector has a `Mode`, `voice` (default)
  or `level`, and is PURE and synchronous over `Input.read`'s snapshot so the
  sheet re-detects per control change. Per step, in this ORDER: the gain
  FLOOR — the plan's ENVELOPE alone against the threshold, which is what makes
  a muted, soloed-away, faded or ducked clip quiet in EITHER mode before the
  model is asked, and is not `peak × envelope`, the level test after it — then
  a voice whose source window holds no voice falls back to
  level (its media named), then a media whose speech cache has not landed is
  never quiet. A silenced clip is dropped from either scope rather than
  counted; a NEST is a wall. `SileroVAD` is the streaming Core ML wrapper over
  the vendored compiled model, NOT `async`, with one process-wide
  `NSLock`-guarded unavailability reason that never retries until relaunch.
  `MediaPeaks` is the one spelling of the project → source window arithmetic;
  the reversed MIRROR it applies is `ReverseMirror`'s.
- `AudioNormalize.swift` — Normalize Clip as a value type: peaks in, ops out,
  measured PRE-FADER from the plan segment, REPLACING `volume` so a second
  press is a no-op, always to BASE props.
- `LevelMeter.swift` · `LevelMeterView.swift` · `Loudness.swift` — the meter
  reads the DSP tap that already exists and multiplies by the plan's
  envelope; a second `PostEffects` tap cannot be built (one
  `audioTapProcessor` per input, exclusive flags). Do not "fix" it back. The
  MODEL publishes a raw peak and RMS and the VIEW owns the ballistics, with
  ONE resting appearance so the harness settles. `Loudness` is BS.1770-4 with
  no AVFoundation in it, refusing any rate but 48 kHz.

**Dialogs and windows.**
- `Sheets.swift` (the `makeSheetView` builders every sheet uses) ·
  `ExportSheetController.swift` (+`Options`, +`Resolve`, +`Presets`,
  `ExportPresetsStore.swift`) · `ExportProgressSheetController.swift` ·
  `SpeedSheetController.swift` · `RelinkSheetController.swift`. A sheet
  captures a project handle and trusts it; every editor action and
  `handleEditorKey` refuse while one is attached. The export card's controls
  are a VALUE (`ExportChoice`); presets store control choices, not resolved
  overrides; `apply(_:)`'s order is load-bearing and documented there; the
  burn-in checkbox rides as a `RecipeOptions`, not an override. The sheet has
  TWO commits, Export… and Add to Queue, one method.
- `ExportQueueController.swift` · `ExportQueueWindowController.swift` — the
  controller has NO AppKit in it so a probe can drive it; one job at a time on
  the MAIN thread with a fresh `Exporter` each (two concurrent ones deadlock);
  `mediaURLs()` AND the document's compiled graphics (`Job.graphics`)
  captured at ENQUEUE. No MCP mirror: `export` called N times is
  the capability.
- `SettingsWindowController.swift` — Reelcut ▸ Settings… ⌘,, the app's one
  window for something PERSISTED beyond view state, with
  `extension AppDelegate { showSettings }` at its foot
  (`CaptionImporter.swift`'s command-at-the-foot precedent, which is why
  `AppDelegate.swift` is untouched). `ExportQueueWindowController`'s mould.
  One pane, the `Transcription` HEADING that is the content stack's first
  arranged subview — which is what makes the `transcribe` tool's and the
  catalog's "Settings ▸ Transcription" sentence true without either being
  edited. The key goes in through an `NSSecureTextField` and NEVER comes
  back out: `sync()` writes a FIXED-LENGTH mask into the field's
  PLACEHOLDER, never its `stringValue`. Save and Remove go through
  `AssemblyAIConfiguration.store()`, so R6-9's folder override holds; the
  initialiser takes a store FACTORY so the offscreen harness can photograph
  it with a `MemoryStore`. Verify runs on `CloudTranscriber`'s `work` queue
  (`CloudTranscriber.verify(completion:)`, spec §11's R6-12 — no new queue).
  Its latest request owns the answer and controls by UUID; completion also
  matches the effective credential, persisted region and resolved base URL
  captured at click time. Text edits, Save, Remove, sync and reopening keep
  Verify enabled only when an effective credential exists and no current
  request is checking those same inputs.
  **No key set is not an error** anywhere in it.
- `PreviewWindowController.swift` — a second `AVPlayerLayer` on the same
  player (measured: two layers both display). It is an **`NSPanel`** (a titled
  window becomes main and every editor selector goes dead), the controller is
  its DELEGATE for `windowWillReturnUndoManager` alone (`NSWindow` implements
  `undo:` itself and mints its own empty manager on the first unanswered
  ask, so the delegate goes on before anything asks), `hidesOnDeactivate` is
  set false, and it is retained by one stored property on the editor, NOT
  `addWindowController`, which would silence the save prompt on close. It
  forwards bare keys to `handleEditorKey`, the one key map.
- `RecorderPanelController.swift` (+`Rows`, +`Recording`, +`Pause`,
  +`Landing`, +`Picker`) · `RecorderStatusItem.swift` — File ▸ New Recording…
  A `.floating`, `.nonactivatingPanel` with `hidesOnDeactivate` false, ONE
  instance, no window delegate. **The panel is the only place the two grants
  are requested**, both before the countdown; it orders OUT at
  `recordingDidStart` for every source and comes back only with a note. The
  status item is the recording's whole chrome (Pause / Resume / Stop).

**Recording.**
- `RecordingSetup.swift` · `RecordingResult.swift` — the half a probe can
  call: choices, file naming, `RecordingConfiguration.make` (PURE), the grant
  reads, the result types. Nothing here prompts.
- `ScreenRecorder.swift` (+`Pause`, +`Delegates`, +`Microphone`,
  +`Finishing`, +`Content`) — the machine `idle → arming → recording ⇄ paused
  → finishing → idle`. **The microphone is a SECOND FILE** through an
  `AVCaptureSession`, because `SCRecordingOutput` folds it inseparably into
  the system track; its offset is measured per SEGMENT. **A pause is a
  sequence of files over one stream**: the recording output is removed and a
  fresh one added while the stream keeps capturing. Every framework callback
  is stamped where it lands and hopped to main; each finds ITS segment by
  the output's identity. `onFinish` on the session is the one hook; `stop()`
  past idle JOINS the finishing under way; a microphone problem is
  `micProblem` on a success, never the recording's failure.
- `RecordingLanding.swift` (+`Microphone`, +`Placing`) · `ProjectDocument+Recording.swift`
  — a `RecordingResult` and a document in, an UNSCOPED op list out; nothing
  here commits. Pictures land back to back on ONE track, every `add_clip`
  READ BACK (at an inexact canvas rate a raw add snaps down into a one-tick
  overlap and a minted dissolve); each voice on one Microphone track at its
  picture's start minus its offset, floored at the previous voice's end.
  `untitled(around:)`'s order is a contract, documented there.

**The agent.**
- `AgentServer.swift` (frozen) and `AgentServer+Project` / `Clips` / `Tracks`
  / `Media` / `Render` / `History` / `Silence` / `Captions` / `Audio` /
  `Background` / `Scope` / `Transitions` / `CloudCaptions` / `Recording` /
  `Graphics`
  (+`RecordingArguments`, +`RecordingResult`) — the handlers, one file per
  group. `+CloudCaptions` is `transcribe`'s CLOUD arm alone — the `engine`
  reader, the three cloud-only arguments refused by name under `apple`, the
  vocabulary's trim/de-dup/cap, the credential and the endpoint read ABOVE
  the network, and the result keys; `+Captions` dispatches on `engine` and is
  otherwise the code it was. `+Graphics` holds the two graphic op tools and
  the three app-state ones — `write_graphic` (the store's one writer, then a
  synchronous `rescan()` so the reply is the compile of THAT text; a failed
  compile is `ok: false`, not an error; not undoable, never dirty, G-3),
  `get_graphic` (one module, or the folder with `folder_exists`, the
  engine's `families` and the `assets`) and
  `graphic_reference` (the bundled `GraphicsAPI.md`; it never calls
  `target(a)`, so it answers with no project open) — and `graphicsSummary`,
  `get_project`'s `graphics`. `+GraphicRender` is `render_graphic`, an
  `offMainTools` member: one `onMain` for the target, the registry's
  compiled module, the canvas and `meta`; then, off main, the ctx built by
  hand (`recipe_graphic.rs`'s keys) and a contact sheet or one frame's SVG;
  a failing frame is its error card, drawn by
  `LayerRenderers.paintErrorCard`, the one card painter.
  `+GraphicImports` is `import_graphic_font` / `import_graphic_asset`, on
  main, thin: they call `GraphicStore+Import.swift`'s `importFont(from:)` /
  `importAsset(from:as:)` — the ONE body File ▸ Add Font/Image to Graphics…
  also runs (the copy via `ensureFolder()`, G-14, `.partial` moved into
  place, then `rescan()`), and the store's own post reaches the registry; a
  font's `families` come from a throwaway
  library holding that file alone. `GraphicContactSheet.swift` is pure: the
  layout (the scale is over the cells alone, so the sheet is exactly
  `width × height ≤ max_width × 8192`), the painter and
  `GraphicRaster.cgImage()`. `AgentCatalog.swift`
  (+`Clips`, +`Audio`, +`Transitions`, +`Files`, +`Captions`, +`Graphics`,
  +`Declarations`)
  — the catalog, spliced in ORDER (`recording_probe.py` reads the last eleven
  names). **A tool is built one of two ways**: `tool`, which declares its own
  schema, or `opTool`, which declares PROSE and prints the argument STRUCTURE
  from the core's published table (`Self.opSchemas` over `rc_op_schemas`).
  **Every one of the fifty-nine op tools is `opTool`'s** and carries no
  `"type"`, no `"enum"` and no hand-written required list; `tool`'s remaining
  callers are the twenty-six APP-STATE tools, which have no op behind them
  and so nothing to read from the table — the ten of the Projects group,
  `AgentCatalog+Audio.swift`'s two composites and
  `AgentCatalog+Captions.swift`'s three, spliced back at the two points they
  left, the five other file tools, `record_screen` among them, and
  `AgentCatalog+Graphics.swift`'s six, after its two `opTool` rows. `opTool`
  goes THROUGH `tool`, so `project` and `scope` are injected by one piece of
  code either way. `AgentCatalog+Declarations.swift` is the one list of places
  a tool deliberately takes more or less than its op does — a bare-string
  body, a boolean's string spellings, a null that MEANS something, a range the
  core clamps to rather than refusing, a default taken from app state, a list
  the tool will not take empty — each row carrying the op, the argument, what
  the app adds and why, and the schema DECLARES it. A new row is a decision
  with a reason, like an entry in `opsWithoutTools`; a leniency the tools have
  never declared is not a row until someone decides to OFFER it, because a
  schema narrower than what is accepted costs a caller nothing where a wider
  one is a promise the app breaks. A `.filledByTheApp` row takes an argument
  OUT of the tool entirely — `declaredInput` omits it from `properties` and
  `required` and the parity check's `expectedArguments` subtracts it — for an
  argument only the app can fill: the two graphic ops' `schema`, read from
  the module's current revision (G-4), which the gate therefore refuses as a
  stranger. `AgentServer+Parity.swift` is the FIFTH
  part of the startup parity check — the one part that looks INSIDE an op
  tool's schema: its arguments must be the core's own (both directions, the
  envelope's two keys and the declarations list apart), each one must carry a
  description, and a description whose key is no argument is a complaint
  rather than a sentence `opTool` drops in silence. Parts 1 to 3 stay in the
  frozen file with the private dispatch table they read and part 4 in
  `AgentServer+Scope.swift` with the feature it is about; all five assert in
  debug, log `Reelcut: ` in release and start the server either way.
  `AgentServer+Gate.swift` is the CALL-time half of the same contract
  (kpgalligan/reelcut#21): one comparison in `dispatch`, for all eighty-five product
  tools, of a caller's keys against the schema the tool published, every
  stranger refused by name — the tool, the strangers and the whole of what it
  takes — before the scope or any handler reads a thing. Its map is read once
  from the catalog string `prepareCatalog()` built at launch (spec §11 AI-3),
  which `start()` then registers. What it cannot see is a
  declared argument no handler reads, which is the optional half of
  `op_argument_proof.py`'s section 3. `target(_:)` resolves the implicit
  document through `NSApp.orderedDocuments`, never `documents.first`, and an
  explicit path through `AgentServer.canonical`. `offMainTools` names the
  handlers that wait for something the main thread must deliver
  (`import_media`, `transcribe`, `record_screen`, `export`,
  `render_graphic`, …); the criterion
  is "waits on main", not "touches the disk".
- `AgentLane.swift` — every tool call's one door (road map 12 A1, spec §11
  AI-2, AI-3, AI-5, AI-12): the MCP trampoline's `serve` (server thread,
  synchronous) and the assistant session's `submit` (returns at once; one
  completion, on the lane's serial queue). One `NSLock` admits one call at a
  time, which is what keeps `callScope` and `callDocument` race-free; it is
  NEVER taken on main, because an `offMainTools` member holding it waits for
  main. A `submit` is refused (a withheld tool) or asked (an ask-first one,
  through the session's hook on main, BEFORE the lock) and then runs inside
  `AgentServer.pinning(document)`; `serve` never pins and never asks.
  `onMainWhenIdle` is `onMain`'s body: off main it waits, retrying every
  20 ms, while any open document `isLiveEditing`, so a call mid-drag lands
  after mouse-up above the gesture's undo step (AI-12, #144); ON main it runs
  in place — a wait there could never end. `pinnedTarget` is
  `targetDocument`'s first statement for a pinned call: the pinned document,
  or a refusal by name when it is closed or `project` names another.
  `prepareAtLaunch()` runs `prepareCatalog()` from `main.swift`, at top level
  before `NSApplicationMain` — `assistant_lane_proof.py`'s L0 reads that line.
  `releasingLock` runs a body with the lock released and relocks in a
  `defer`; its only callers are the two assistant dev tools, which `serve`
  runs under the lock on that thread and which wait for a turn whose own
  `submit` calls need it.
- `AssistantToolTable.swift` — spec §11 AI-7's ONE table: withheld
  (`record_screen`; `transcribe` only with `engine: "assemblyai"`; every dev
  tool, from `AgentServer.devToolNames`) and ask-first (`export`,
  `export_captions`, `save_project`, `consolidate_media`), a reason on every
  row; the refusal sentence, the question (main only: the path the call
  writes, tilde-expanded, and whether a file is already there — "REPLACES")
  and the assistant's catalog, which drops only an unconditional withheld row.
- `AssistantSession.swift` — one window's assistant conversation (road map
  12 A1, spec §11 AI-1, AI-4, AI-5, AI-7), a port of Rasterize's
  `AssistantHelperSession`. `open(document:)` refuses, in order and each in
  its own sentence, a bad `RC_ASSISTANT_BASE_URL`, no key, a catalog not
  prepared at launch (it READS `AgentServer.preparedCatalog` and never
  prepares — AI-3 stays a trap that can fail), and no bundled helper; the
  helper gets exactly `HOME`, `TMPDIR` and `PATH=/usr/bin:/bin`, and the key
  only in the first stdin line, `configure`. Main only; every write goes
  through the one serial `writeQueue` (`HelperInput`, so a write after the
  close is nothing), `F_SETNOSIGPIPE` on the write end. Tool requests run ONE
  at a time through `AgentLane.submit` (never `execute`), results spliced
  verbatim. `send` sets busy BEFORE its write, so the phase reads `busy` the
  moment it returns true; `turn_started` does not clear `cancelRequested`.
  **Every question is answered exactly once** — Allow/Deny, Stop, `close`,
  the helper's exit, `deinit`, and a hop that reaches a closed, cancelling or
  released session (the `askFirst` closure is `[weak self]` and REPLIES when
  `self` is nil) — because an unanswered one holds the lane's one queue for
  every window. `events` is append-only and never holds a `tool_request` or
  the key.
- `AssistantConfiguration.swift` — the assistant's key (spec §11 AI-8), base
  URL (AI-13), model (AI-11) and chat settings. `store()` is AI-13's whole
  decision: `-RCSecretFolder` (read through
  `AssemblyAIConfiguration.argument`, the argument domain alone) → a
  `FileStore` named `anthropic-key`; else `RC_ASSISTANT_BASE_URL` set → an
  EMPTY `MemoryStore`; else the one `AppSupport.directory` line. The store
  first, `ANTHROPIC_API_KEY` second. `model()` is `ReelcutAssistantModel`,
  else `claude-opus-5-5`; no tool reads or writes it.
- `AssistantPrompt.swift` — the core tools loaded up front (`get_project`,
  `render_frame`, `undo`, `redo`; the lane probe's L6 holds each to the
  assistant's catalog) and the three PLACEHOLDER texts A3 replaces: the
  system prompt, the search guide and the compaction instructions.
- `AgentServer+DevTools.swift` — the dev tools' seam (road map 11, spec
  §11 V-1/V-2): the handler table, catalog rows and off-main set compiled
  only under `REELCUT_DEV_TOOLS`, which Debug and Release set and
  Distribution does not. The frozen file merges them (`withDevHandlers`, a
  union) and `catalogJSON()` splices the rows in BEFORE the file tools. It
  holds `devToolsMarker`, the string `tools/proof/dist_check.py` requires in
  Release's binary and absent from Distribution's; a tool NAME cannot be the
  marker, because an `-O` binary stores a literal of 15 bytes or fewer
  inline. Its tables hold
  `snapshot_ui` (V2a), `perform_menu_item` and `cancel_sheet` (V2b),
  `select_inspector_tab` (V3), and `assistant_send` and `assistant_answer`
  (road map 12 A1); a dev tool is counted apart from the product tools (`tools/proof/dev_tools.py`).
- `AgentServer+MenuItem.swift` — `perform_menu_item` and `cancel_sheet`
  (road map 11's V2b, dev only, wholly under the flag). It runs a main-menu
  item by path in a NAMED project window's own responder chain, never
  nil-targeted, and works with the app inactive and the window occluded
  (measured, V2b's D rows). It refuses by name an item that is disabled, a
  submenu, `framework`, `modal` or unclassified. It answers after a settle:
  reads 20 ms apart, answered on 5 equal, bounded at 3 s. `cancel_sheet`
  closes an attached sheet through its own Cancel. Both run off main
  (`devOffMainTools`), and every AppKit touch is an `onMain` hop.
- `UIMenu.swift` — the menu tool's main-thread half. It walks the menu's
  leaves and looks up a path, validating each level first because a
  validator may retitle an item. It holds the refusal, an ALLOW table where
  a selector with no row is `unclassified`, and the responder walk and
  validation, which never write `isEnabled`. It performs the item inside one
  explicit undo group on the window's document, with `performGroupedEdit`'s
  discipline; without that, two performed edits merge into one undo step
  (mutant M3).
- `UIMenuTable.swift` — `UIMenu.verdicts`, one row per selector, a mirror of
  `tools/proof/capture_spike/inventory.json` in its order. `v2_menu.py`'s H2
  holds the two together, and H1 holds the inventory to the live menu, so a
  new menu item needs a row in both.
- `UISheet.swift` — the settle fingerprint (the attached sheet, the modal
  window, the visible window numbers) and the Cancel: a file panel is ended
  with `.cancel`, otherwise the Escape button is pressed, otherwise a lone
  button.
- `AgentServer+InspectorTab.swift` — `select_inspector_tab` (road map 11's
  V3, dev only, wholly under the flag). It picks the inspector's tab and the
  Clip tab's sub-tab through `InspectorViewController.select(_:)` and
  `selectClipSubTab(_:)`, the strips' own click paths, so a `snapshot_ui`
  capture is what a click shows. It runs on MAIN, not in `devOffMainTools`.
  With no tab it changes nothing, and answers the tab, the active sub-tab
  and the sub-tabs on offer. Every refusal leaves the inspector as it was.
- `DevAppearance.swift` — `-RCDevAppearance light|dark`, a dev-only launch
  default (road map 11's V3). It sets `NSApp.appearance` from `main.swift`
  before `NSApplicationMain`, so every view is built in that look. A live
  switch leaves colours taken at build time in the launch look, which is why
  `snapshot_ui` refuses `appearance` and names this default instead. It is
  not in `AppDelegate.swift`, because a line added there moves the `runModal`
  sites that `inventory.json` pins by line.
- `AgentServer+Assistant.swift` — `assistant_send` and `assistant_answer`
  (road map 12 A1, dev only, wholly under the flag). Both run off main
  (`devOffMainTools`): one `onMain` resolves the target, the editor and the
  session and sends, answers or stops; then the wait for "not busy" runs
  INSIDE `AgentLane.releasingLock`, polling the phase every 50 ms, because
  the turn's own calls need the lock. The target is resolved BEFORE the
  release, never inside it, where an assistant call may hold
  `callDocument`. `assistant_answer` never opens a session. The answer is
  the state, the question, the text deltas joined and the other events since
  the call — never the key or the model.
- `DevAssistantLaunch.swift` — `-RCDevAssistantSend <text>
  -RCDevAssistantReport <path>`, a dev-only launch default (road map 12 A1),
  both from the argument domain alone: after launch, one turn in an untitled
  project with or without the MCP server, a `get_project` through the lane,
  one atomic JSON report, and the session closed. One key alone is one
  stderr line. Installed from `main.swift` after `DevAppearance.apply()`.
- `AgentServer+Snapshot.swift` — `snapshot_ui` (road map 11's V2a, dev only,
  wholly under the flag). It lists the windows, or captures the editor (whole
  or a region), an attached sheet, Settings, Welcome or the recorder panel through `cacheDisplay`:
  an image block plus JSON and a PNG, with a `<name>.layout.json` beside it.
  It runs OFF main (`devOffMainTools`): the fill renders through
  `Exporter.renderFrameReported`, the settle sleeps between passes, and every
  AppKit touch is an `onMain` hop. A `defer` unstages on every exit. It works
  with the app inactive and its window occluded (measured, V2a's O rows).
  `appearance` is refused, naming `-RCDevAppearance`.
- `UISnapshot.swift` — `snapshot_ui`'s main-thread half. It resolves the
  window (Settings, Welcome and the recorder panel found in `NSApp.windows`
  by controller class, never `.shared`, which would build them) and the regions (the root's `BarView` and the three pane
  containers), holds the window facts and the listing, and stages the fill
  as an `NSImageView` just above
  `playerHost`, under `safeGuides` and `overlay` (V1's W4a). It also runs one
  `cacheDisplay` pass. `kind(of:)` and `row(_:)` are internal, not private,
  because the menu tool's result rows use them.
- `UISnapshotLayout.swift` — the layout dump. A pre-order walk over non-hidden
  views and three rules, each with a 0.5 pt tolerance: ambiguous;
  outside_superview, except under an `NSClipView` or at zero area; truncated,
  except when wrapping. Problems on `_NS…` views go to `private_problems`. A
  secure field's text is never written. It is pure over an `NSView` tree, so
  `tools/proof/v2_layout_probe.swift` calls it.
- `AgentServer+Arguments.swift` — the shared argument vocabulary
  (`intArg`, `timeArg`, `rangesArg`, `rawPatchArg`, …), each refusing a
  value it cannot read BY NAME, and ONLY what the core cannot know: target
  and scope, an id checked against the container it names, a time on the
  document's frame grid, and the in-band refusal. A whole number is read
  EXACTLY: `3.0` is 3 and `3.7` is refused, never truncated (`whole`).
  `fpsPair` reads a rate's two terms, each through `rateTerm` and each
  refused by its own path (`fps[0]`, `descriptor.fps[1]`), for the two
  callers that spell a `[numerator, denominator]` pair — `fpsArg`
  (`AgentServer+Tracks.swift`) and `mediaDescriptor`
  (`AgentServer+Media.swift`).
  **`rawPatchArg` is the
  door every op that takes a caller-authored object goes through**: it reads
  nothing about the value and hands the object to the core, which is the one
  validator of what a patch may carry and names the dotted path and the
  value in every refusal (`core/src/patch.rs`). Its one refusal is the
  ABSENT argument, a mistake about the CALL. A colour-only ARGUMENT
  (`set_canvas`'s background, `add_background`'s colour) goes the same way,
  straight off the call: a colour is four numbers each 0–1 and nothing on
  this side fills in an alpha or clamps a component. **There is no decoder
  for a caller's object in this file and a new door does not add one** (the
  rule under Rules; what was deleted and what it measured,
  `archive/reelcut-roadmap-7.md` §2–§3).

**Shared chrome.** `Theme.swift` (`DS` tokens, including the three track
heights S/M/L per kind), `Controls.swift`, `OptionControls.swift`,
`Sheets.swift`, `EditorChrome.swift` (`BarView`), `FileDropView.swift`
(Finder drops + the first responder the bare-key map needs) — copied from
Rasterize; keep them in sync rather than forking. `BrandMark.swift` is
Reelcut's own, drawn from `designs/design_handoff_reelcut/`.
`Controls.swift`'s `BlockSlider` is the timeline's zoom slider. Two known
divergences, each recorded: `StickerButton` still has its pill, the one
place `Controls.swift` lags Rasterize (spec §11 SH-1, owed); and
`BlockSliderCell.drawBar` dims through the context's alpha rather than
`withAlphaComponent`, the one deliberate fork (SH-2) — Rasterize's spelling
paints the translucent `DS.border` track opaque in the knob's own ink.

## Rules

**Placement.** New feature = small model/value file + VC extension file +
gesture session struct (`ClipDragSession`, `TrimSession`, `CanvasSession` are
the template): one stored property on the view, logic in the feature's file.
Closures assigned in `loadView` are one-line forwards to named methods — no
business logic in closure bodies. New files are capped at 400 lines; a file
at the ~600-line cap gives something up first, as a pure move landed alone.

**Undo and dirty tracking.** All document mutation flows through
`ProjectDocument`'s entry points — `applyEdit` and the
`beginLiveEdit`/`updateLiveEdit`/`endLiveEdit` trio for gestures.
`registerUndo` appears nowhere outside `ProjectDocument`. It overrides
`updateChangeCount` to drop AppKit's automatic counting; the entry points
count deterministically via `countEditChange()`. **Pitfall:** undo
registrations outside an AppKit event (agent edits, async callbacks) land in
the implicit event group AppKit never closes, silently merging edits into one
undo step; any off-event path goes through `ProjectDocument.performGroupedEdit`.
**Do not "flush" the manager to grouping level zero** to close that group: the
undo checkpoint `NSDocument` posts inside every save then raises, the
exception is swallowed inside the file coordinator, and ⌘S and `save_project`
hang for good.

**A refusal is the CORE's sentence, and nothing on this side writes one.**
An op answers `.applied`, `.identity` or `.refused` (`ReelEdit.swift`); a
person hears a beep for both non-applied arms and, for a refusal, reads the
core's sentence verbatim after "Refused: " at the inspector's foot (spec
§11 CI-10), and an agent hears
`<Action> made no change: the project is already in that state.` or
`<Action> was refused at <op>: <the rule's own sentence>`, written once in
`AgentServer.performGroupedEdit`. **No handler applies an op to see what
would happen and then writes its own reason**, and none re-derives a rule's
arithmetic to predict one. Spec §11's **D2-1** is the line: a check that
predicts a RULE goes, a check that names the CALL stays — an argument a
handler cannot read or was not given (`AgentServer+Arguments.swift`), or a
composite's own reading, like `normalize_clip` with nothing it could
MEASURE. Prose that TEACHES a rule before the call belongs in a tool
description; prose that explains a refusal after it is the core's to write.

**Two callers swallow a refusal on purpose.** `ReelProject.scoped(_:)` drops
the core's message because every caller is a VIEW asking about view state
`clampViewState` has already cleared, so a nil is a race with an undo and
not a failure to report. `ProjectDocument.updateLiveEdit` swallows every
answer but `.applied` because a refused tick is NORMAL mid-drag — the edge
is past a neighbour for a moment — and recovers on the next one with the
last good frame still on screen, where a drag that spoke would interrupt the
gesture to say what the person is already fixing with the mouse;
`endLiveEdit` then registers no step at all. Neither is a gap to be closed
(kpgalligan/reelcut#8's eighth decision).

**Lenient decoding is for what the CORE wrote; nothing a caller wrote is
decoded through it.** `ProjectSnapshot`/`MotionProps`' `lenient` and
`nullable` exist so a project, plan, recipe or export setting a NEWER build
wrote still opens — a misspelt kind becomes the first case, an unreadable
value a default or a clear. Run over an agent's own object that same
leniency is a silent correction, so a caller-authored object (a patch, a
colour, a region, a new clip's text or shape) goes to the core unread
through `rawPatchArg` and the RAW factory beside its typed one, and the core
names the dotted path and the value it refused. A scalar enum ARGUMENT
parsed by name is not this (`add_zoom_action`'s `fit`, `curveArg`,
`set_transition`'s `kind`): what the rule forbids is decoding a caller's
object through a lenient type, and the ONE caller-authored object the app
still reads by hand is `add_media`'s descriptor, which is a media row rather
than a patch and has no op of its own to be refused by
(`AgentServer+Media.swift`'s `mediaDescriptor`, named here so it is an
exception on purpose). The hand checks this rule replaced were deleted
rather than moved, so a new door that wants one is a door that has not been
read; the spec says the same in §7.9, and what went and what it measured is
`archive/reelcut-roadmap-7.md` §2–§3.

**Agent parity.** Every user-visible EDIT gets an MCP mirror: a handler, a
catalog entry declaring `scope`, and a comment naming the UI path. Handlers
follow the canonical shape: `target(a)` → validate ids → `performGroupedEdit`
→ `jsonResult`; failures throw `ToolError` and return in-band
(`isError: true`). View state and preferences are the one exemption, and it
is a decision: Preview Quality, the preview window, the export queue, the
Media tab's search and sort get no mirror, because they edit no project and
`set_selection` / `export` already are the capability.

**State flow.** Views → VC through `on*` closures (`[weak self]`); document →
observers via `.projectDocumentDidChange` with `userInfo["isLive"]` — live
gestures pass `isLive: true` and observers skip expensive reloads
mid-gesture. VC → views is direct property assignment.

**Tracking areas.** `updateTrackingAreas` removes only the view's OWN areas —
`for area in trackingAreas where area.owner === self` — never
`trackingAreas.forEach(removeTrackingArea)`: tooltips are tracking areas owned
by `NSToolTipManager`, and nothing reinstalls one that is removed.

**Popups.** A popup built from model objects carries the object in
`representedObject` and is read from `selectedItem`, never by index, and its
rows are `NSMenuItem`s: `addItem(withTitle:)` REMOVES an existing row with the
same title. `menu.autoenablesItems = false` comes before disabling a row. An
`OptionPopupControl` over model values takes them through the typed init
(`OptionControls+Choices.swift`: `choices:` of title and value, `read` and
`write` in values), not the index init with a hand-kept array beside it.

**Hygiene.** No storyboards/xibs. No `!` force-unwraps, `as!`, or `try!`;
implicitly-unwrapped optionals only for post-`loadView` view refs. Every
non-NSCoder class: `@available(*, unavailable) required init?(coder:)
{ fatalError("<Type> does not support NSCoder") }`. `[weak self]` in retained
closures, never `unowned`. Main-thread AppKit. **`async`/`await` is allowed
only inside `MediaImporter.swift`** (AVFoundation's loading API is
async-only) **and `SpeechEngine.swift`** (spec §11 W-8: `SpeechAnalyzer`
is async-only; every caller gets a synchronous wrapper or a main-queue
completion, and `Task.detached`, never `Task {}`). Nothing else earns the
exception by asking — screen recording has a complete callback API and
uses it. **`import Synchronization` is allowed only inside `LevelMeter.swift`**,
whose `publish` runs on the audio render thread where a lock invites priority
inversion and `main.async` allocates; every other cross-thread value is an
`NSLock` or a main hop. `DispatchQueue` only at the documented seams: the
compositor's render queue, the composition rebuild, import, the export
progress timer, `Transcriber`'s serial queue, `CloudTranscriber`'s serial
queue and the AssemblyAI client's delegate `OperationQueue` (spec §11's
R6-7), the transcribe sheet's Download row's KVO main hop
(`DispatchQueue.main.async` from `Progress`'s `fractionCompleted`
observation), `FFmpegRewrap`'s serial queue, the two one-frame render
queues (`eyedropperQueue`, `frameGrabQueue` — a third one-frame render joins
this entry rather than growing the list), `ScreenRecorder.shareableContent`'s
global hop, `GraphicStore`'s serial queue (its file-system sources'
handlers, the coalesced pass and the outbox; main publishes through
`drain()` and never waits on it but by `queue.sync`), the cache's main
hop, the agent lane's serial queue (`AgentLane.swift`), and the assistant
session's write queue (`AssistantSession.swift`). The recorder adds
NO queue of its own:
framework callbacks are stamped where they land and hopped to main. Colors,
fonts and metrics come from `DS` tokens; shared controls go in
`Controls.swift`. **A refusal and an identity both beep** (`NSSound.beep()`)
and neither makes an undo step — that is what makes a person's experience of
the two alike, and it is deliberate (spec §5.5); a refusal ALSO shows its
sentence at the inspector's foot (CI-10), the one difference a person
sees; only invalid input throws, and errors never crash.
4-space indent, ~100 columns.

**`make typecheck` is authoritative for TYPE errors, and only those.** It
stops before SILGen, so `closure captures 'x' before it is declared` and its
kin never appear; declare captured copies at the TOP of their scope, and
prove a build with `make app`.
