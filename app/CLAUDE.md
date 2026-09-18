# app/CLAUDE.md — Swift app rules

Applies to everything under `app/`. Build/verification commands and the FFI
lockstep are in the root `CLAUDE.md`; the full design is
`designs/reelcut-design.md` (§3–4 the UI, §7.4–7.8 the platform side). The
long form of each entry below — the history of every size toll, the
measurements behind each decision, what each review found — is
`designs/reelcut-app-notes.md`; this file is what governs a file now. Files
are listed by family; a file with a header comment of its own carries its
detail there.

## File map

**The core's edge.**
- `ReelCore.swift` — the **only** home for `rc_*` calls: `ReelProject`
  (handle + lazily decoded `ProjectSnapshot`; `json`, `snapshot` and
  `planJSON` are memoised PER HANDLE, so keep handles rather than minting
  them), timecode, snapping, export presets/sizes/settings, `RecipeSource`,
  the `dictionary` extensions on the property types and the typed patches.
  `deinit` frees the Rust allocation.
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
  `addZoomActionRaw`'s region is `Any` and not `Any?`: an absent key and an
  explicit null are opposite intentions there, and only the tool can tell
  them apart.
  `scope` is a member folded into `json`; `documentLevelNames` MIRRORS
  `scope.rs`'s `refused_inside` (seven names) so one edit can mix a
  document-level op with scoped ones. A table, with
  `edit.rs`'s size exemption.
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
- `ProjectSnapshot.swift` · `MotionProps.swift` — the `Codable`, READ-ONLY
  mirror of spec §5.2 every view draws from. **Its enums decode LENIENTLY**
  — a misspelt kind becomes the first case, a `T??` field a clear — which is
  why a caller-authored object is never decoded through them (below): no
  agent handler reads a caller-authored OBJECT at all. A scalar enum
  argument is a different thing and several handlers still parse one by name
  (`add_zoom_action`'s `fit`, `curveArg`, `set_transition`'s `kind`): the
  core refuses those too, and what this rule forbids is decoding a caller's
  object through a lenient type.
  `MotionProps.dictionary` always writes all three keys, `NSNull` for a nil
  slot, because a core patch of `motion` deep-merges — it is the
  APP's writer saying all three slots, not a replace rule, and it is the only
  edge that writes a whole motion.

**The document.**
- `ProjectDocument.swift` (+`DisplayStem`, +`Recording`) — NSDocument,
  `.reelcut` package read/write, and the single mutation point (see Undo).
  Holds the FIVE pieces of view state nothing persists — playhead, clip
  selection, in/out range, `selectedMedia`, `nestPath` — re-clamped by
  `clampViewState` in that order with the scope FIRST, since the selection
  clamp measures against whatever container the scope left. `nestPath` is a
  PATH of (nest, clip) steps, not a nest id, because two clips can show one
  nest at two starts; `editedProject` is a STORED, memoised `rc_project_scoped`
  handle, and `project` still means the parent for save, export and
  consolidate. A range is cleared on every scope change: a pair of ticks
  means one thing inside a nest and another to an export.
- `MediaImporter.swift` (+`Probe`, +`Speech`) · `MediaCacheFiles.swift` ·
  `FFmpegRewrap.swift` · `AppSupport.swift` — the import funnel and the
  three per-media caches (`thumbs/`, `peaks/`, `speech/`) inside the package.
  `async`/`await` is confined to `MediaImporter.swift`; the await-free halves
  are the `+` files and `MediaCacheFiles`. A cache is CURRENT when its
  `complete.json` marker matches `CacheStamp` (the source's size and
  modification second plus the constants that size the cache — no path, so a
  moved or consolidated package keeps its caches); the marker is written
  LAST and only for a strip the pass can vouch for; a stale cache is deleted
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
- `ReverseRenderer.swift` — `Source::Media.reversed` resolved to
  `cache/reversed/<id>-<digest>.mov`, rendered on demand behind a sheet,
  substituted per CLIP by `CompositionBuilder`.

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
- `EditorViewController+Timeline` / `+Canvas` / `+Inspector` / `+Toolbar` —
  installing the three panes and the toolbar (transport · timecode — view ·
  Export, nothing else). `+Timeline` holds the delete family, including ⌫
  with a range and nothing selected, which LIFTS.
- `+AddClips` (Add Text / Add Shape: the front track, else a new one),
  `+Clipboard` (⌘X/⌘C/⌘V over the `com.kgalligan.reelcut.clips` pasteboard,
  the `paste` op's payload; ⌥⌘V Paste Attributes with no `groups`),
  `+Edge` (slip, roll, close gap, insert, overwrite, the `,` / `.` nudge —
  with an `extension TimelineView` because the two ⌥⇧ drags begin there),
  `+Identity` (Rename ⇧⌘R, the Label submenu over `ClipLabel.allCases`),
  `+Nest` (⌘G / ⇧⌘G), `+NestScope` (⌘↓ / ⌘↑ and the double-click that enters
  a nest; the three marker commands validate OFF inside one, because a
  nest-local tick sent unscoped would land at the wrong project time),
  `+Motion` (Clip ▸ Motion ▸, one `set_video` PER CLIP), `+Export` (the
  dialogs), `+SaveFrame` (⌥⌘E; renders off-main on `frameGrabQueue`; passes
  no burn-in), `+PreviewQuality`, `+Eyedropper` and `+ZoomRegion`.
- The two modal canvas modes (`+Eyedropper`, `+ZoomRegion`) install a bare
  view over the canvas whose PRESENCE is the mode, through `armCanvasMode`,
  which ends every OTHER armed mode first; a third mode inherits that by being
  installed at all. The region frame reads the EVALUATED props (the opposite
  of every session in `CanvasSessions.swift`) because a region is drawn on
  what is on screen; ⇧ during the drag chooses `fill`.
- `EditorWindowController.swift`, `WelcomeWindowController.swift`,
  `AppDelegate.swift` (+`Menus`, +`Recording`), `main.swift` — the window,
  the no-document window, the launch/terminate flow and the whole menu bar
  (spec §9). Menu items are nil-target selectors down the responder chain.

**Timeline.**
- `TimelineView.swift` (frozen) · `TimelineLayout.swift` (every ticks ↔
  points ↔ lanes conversion; `rowTop` is a prefix sum because S/M/L drives
  real heights per track KIND) · `TimelineBar.swift` · `TimelineClipDrawing.swift`
  (a clip is ONE object: body, name strip with the kind symbol, label dot,
  motion wedges, filmstrip under a tint wash, waveform, grips on the
  selected clip, hatched transition zone) · `TimelineSessions.swift` (drag,
  trim, slip, roll sessions) · `TimelineView+Rename` (the one inline editor
  for clips, tracks and markers; it drops an unchanged and an empty commit,
  follows its target through relayout, and ends with its commit DROPPED when
  the target is gone) · `+Candidates` (Remove Silences' wash, drawn not
  overlaid) · `+NestScope` (the breadcrumb, painted LAST in the ruler's
  corner so it stays above the header column when scrolled).
- `ClipLabel.swift` — the ONE home of the label and marker colour
  vocabulary; the core stores names unvalidated, so an unknown name draws in
  `DS.textStrong`. `ClipKindStyle.swift` — the ONE mapping from a clip to its
  tint, symbol and kind word; it asks whether the FILE has pictures, not
  `enabled.video`, which is the Detach switch.

**Canvas.**
- `PreviewCanvasView.swift` (frozen) · `CanvasSessions.swift` — the picture at
  document size and the handle gestures. All coordinate mapping goes through
  `viewToCanvas` / `canvasToView`, and every handle maps through
  `AVPlayerLayer.videoRect`, which is the aspect of the BUFFER — the reason
  Preview Quality must keep the canvas's exact aspect.

**Inspector.**
- `InspectorViewController.swift` (frozen: the tab strip) · `InspectorPane.swift`
  (the pane base, `InspectorSection`, the row builders, and `InspectorBinding`
  — the one place that knows a read is evaluated inside an action and a write
  there goes to `set_action_end`, with `structural(video:for:)` the exception
  that sends a list of a different LENGTH, or `motion`, to the BASE props) ·
  `ClipPane.swift` (the selection header and `makeSections()`, the function
  from a selection's kind to its sections) · `VideoPane.swift` (+`Transition`,
  +`Motion`) · `AudioPane.swift` · `TextPane.swift` · `ShapePane.swift` ·
  `DocumentPane.swift` (reads `documentSnapshot`, never the scoped one: its
  ops are document-level) · `OptionControls.swift` (the descriptor-driven
  row controls).
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
- `Playback.swift` — one `AVPlayer` over the plan's composition; the
  transport, JKL, the rate KVO. **A paused refresh is a one-tick round trip**
  (`refreshPausedFrame`): a zero-tolerance seek to the current time is a
  NO-OP on macOS 26.5.1, so the refresh seeks one tick off and returns; parked
  at the end it rests on the last frame's final tick, because the end tick
  composes black. Do not put a same-time seek back. Preview Quality overrides
  `renderSize` on a `mutableCopy()` of the composition here, keeping the
  canvas's EXACT aspect (`m · (w/g, h/g)`, coarser when the divisor does not
  divide `g`, Full for a coprime canvas); `AVPlayerItem.videoComposition` is
  a COPY property, so the setter re-assigns. `makePreviewLayer` is the one
  door to a second `AVPlayerLayer`.
- `CompositionBuilder.swift` (+`InstructionRanges`) — the app's ONE
  constructor of `AVMutableVideoComposition`, shared by the preview, both
  export passes and the offline frame. **Do not give it a preview-shaped
  argument**; the `metering` flag is passed true by `Playback.startRebuild`
  and nothing else. `fill` holds a video track's last frame over any part of
  a segment the track does not cover (a screen recording's picture ends at
  the last screen change). `+InstructionRanges` ends the last instruction
  exactly on the composition when the two differ by under a tick — AVPlayer
  refuses an invalid composition SILENTLY, black at every time, while the
  generator and the writer tolerate it.
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
- `LayerRenderers.swift` · `LayerRenderersText.swift` — text and shape
  descriptions to textures, keyed by the recipe's `hash` (`RecipeSourceRef.cacheHash`
  is the WHOLE key; nothing here may append to it). Text draws the reveal the
  recipe computed; the LAYOUT is always the full text's, cached without the
  reveal, and `reveal = 1` takes the plain `CTFrameDraw` path so a full reveal
  is byte-identical to no animation; a line at PARTIAL alpha draws inside a
  transparency layer so fill and stroke composite once. A shape's gradient
  SORTS its stops (the core does not police order), projects a linear ramp
  onto the box, and is ignored by `line` and `arrow`.
- `AudioTap.swift` · `AudioDSP.swift` — the `MTAudioProcessingTap` playback
  and export share, and the four sample-level effects: noise reduction (a
  512-sample delay), the compressor, the mono fold (BEFORE the pan, or it is
  algebraically self-cancelling) and pan (constant-power, unity at centre).
  A track whose clips ask for none is bit-identical.
- `Exporter.swift` · `ExporterLoudness.swift` · `ExporterSettings.swift` ·
  `ExporterWriter.swift` · `ExporterImageSequence.swift` — the writer
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
  project decodes byte-identical.
- `FrameWriter.swift` — a `CGImage` and a format in, a URL out, no panel:
  Save Frame and `render_frame` both call it, so their PNGs are
  byte-identical by construction. PNG keeps a NIL properties dictionary
  (anything added changes the file); JPEG flattens onto BLACK at 0.9; HEIC is
  `UTType.heic`, never `public.heif`.

**Captions.** A caption is an ordinary text clip, which is what makes burn-in
free.
- `CaptionLayout.swift` — placement ONLY (snap, abut, drop sub-frame cues, a
  new front-most track in the Caption preset), shared by every producer, and
  `CaptionCues` at its foot — the four cue rules (≤ 2 lines, ≤ 42
  characters, ≤ 6 s, a frame between cues), used only by a producer that must
  INVENT line breaks. An SRT brings its own.
- `CaptionImporter.swift` (SubRip grammar) · `CaptionExporter.swift` (`.srt` /
  `.vtt` from one all-text track, never guessed; a popup built from
  `NSMenuItem`s carrying `representedObject`, because `addItem(withTitle:)`
  REMOVES a same-titled row).
- `Transcriber.swift` · `TranscribeSheetController.swift` — on-device
  recognition through the CALLBACK API (spec §11: no second `async`
  exception) over each clip's source window EXTRACTED to a temporary mono
  16 kHz WAV; the recogniser's queue is set explicitly because it defaults to
  MAIN. "Has sound" is `enabled.audio`, not the media's track. One job's
  failure is reported under `problems` and the run carries on. The SHEET is
  the only caller of `requestAuthorization`; the tool refuses by status. The
  tool's refusal ORDER is the caller's own mistakes first, the grant second,
  the model third, so a headless proof can measure the first tier.

**Silence and sound.**
- `SilenceDetector.swift` (+`Walls`) · `SilenceSheetController.swift` ·
  `SileroVAD.swift` · `MediaSpeech.swift` · `MediaPeaks.swift` — Remove
  Silences and `detect_silence`. The detector has a `Mode`, `voice` (default)
  or `level`, and is PURE and synchronous over `Input.read`'s snapshot so the
  sheet re-detects per control change. Per step, in this ORDER: the gain
  FLOOR (`peak × envelope`, so mute and solo fall out of the plan's zero
  envelope), then a media with no voice anywhere falls back to level, then a
  media whose speech cache has not landed is never quiet. A silenced clip is
  dropped from either scope rather than counted; a NEST is a wall. `SileroVAD`
  is the streaming Core ML wrapper over the vendored compiled model, NOT
  `async`, with one process-wide `NSLock`-guarded unavailability reason that
  never retries until relaunch. `MediaPeaks` is the one spelling of the
  project → source window arithmetic, including the reversed MIRROR.
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
  `mediaURLs()` captured at ENQUEUE. No MCP mirror: `export` called N times is
  the capability.
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
- `AgentServer.swift` (frozen) and `AgentServer+Project` / `Clips` /
  `Tracks` / `Media` / `Render` / `History` / `Silence` / `Captions` / `Audio`
  / `Background` / `Scope` / `Transitions` / `Recording`
  (+`RecordingArguments`, +`RecordingResult`) — the handlers, one file per
  group. `AgentCatalog.swift` (+`Clips`, +`Audio`, +`Transitions`, +`Files`)
  — the catalog, spliced in ORDER (`recording_probe.py` reads the last
  eleven names). `target(_:)` resolves the implicit document through
  `NSApp.orderedDocuments`, never `documents.first`, and an explicit path
  through `AgentServer.canonical`. `offMainTools` names the handlers that
  wait for something the main thread must deliver (`import_media`,
  `transcribe`, `record_screen`, `export`, …); the criterion is "waits on
  main", not "touches the disk".
- `AgentServer+Arguments.swift` — the shared argument vocabulary
  (`intArg`, `timeArg`, `rangesArg`, `rawPatchArg`, …), each refusing a
  value it cannot read BY NAME, and ONLY what the core cannot know: target
  and scope, an id checked against the container it names, a time on the
  document's frame grid, and the in-band refusal. **`rawPatchArg` is the
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
  `designs/reelcut-roadmap-7.md` §2–§3).

**Shared chrome.** `Theme.swift` (`DS` tokens, including the three track
heights S/M/L per kind), `Controls.swift`, `OptionControls.swift`,
`Sheets.swift`, `EditorChrome.swift` (`BarView`), `FileDropView.swift`
(Finder drops + the first responder the bare-key map needs), `BrandMark.swift`
— copied from Rasterize; keep them in sync rather than forking.

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
person hears a beep for both non-applied arms, and an agent hears
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
`designs/reelcut-roadmap-7.md` §2–§3.

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
same title. `menu.autoenablesItems = false` comes before disabling a row.

**Hygiene.** No storyboards/xibs. No `!` force-unwraps, `as!`, or `try!`;
implicitly-unwrapped optionals only for post-`loadView` view refs. Every
non-NSCoder class: `@available(*, unavailable) required init?(coder:)
{ fatalError("<Type> does not support NSCoder") }`. `[weak self]` in retained
closures, never `unowned`. Main-thread AppKit. **`async`/`await` is allowed
only inside `MediaImporter.swift`** (AVFoundation's loading API is
async-only), and nothing else earns the exception by asking — speech
recognition and screen recording both have complete callback APIs and use
them. **`import Synchronization` is allowed only inside `LevelMeter.swift`**,
whose `publish` runs on the audio render thread where a lock invites priority
inversion and `main.async` allocates; every other cross-thread value is an
`NSLock` or a main hop. `DispatchQueue` only at the documented seams: the
compositor's render queue, the composition rebuild, import, the export
progress timer, `Transcriber`'s serial queue and the recogniser's
`OperationQueue`, `FFmpegRewrap`'s serial queue, the two one-frame render
queues (`eyedropperQueue`, `frameGrabQueue` — a third one-frame render joins
this entry rather than growing the list), `ScreenRecorder.shareableContent`'s
global hop, and the cache's main hop. The recorder adds NO queue of its own:
framework callbacks are stamped where they land and hopped to main. Colors,
fonts and metrics come from `DS` tokens; shared controls go in
`Controls.swift`. Refusals beep (`NSSound.beep()`), errors never crash.
4-space indent, ~100 columns.

**`make typecheck` is authoritative for TYPE errors, and only those.** It
stops before SILGen, so `closure captures 'x' before it is declared` and its
kin never appear; declare captured copies at the TOP of their scope, and
prove a build with `make app`.
