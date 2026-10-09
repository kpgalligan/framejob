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
  them), timecode, snapping, export presets/sizes/settings, `SpeedLimits`
  / `ReelSpeed.limits` (the core's speed range and audio ceiling — no Swift
  file types a speed bound), `ReelColor` (`rc_normalise_color`, G-25) and
  `ReelContainer` (`rc_container_*`, a WebM/Matroska file's index,
  #216-R); the typed patches are `TypedPatches.swift`'s (`VideoPatch`,
  `AudioPatch`, `ClipPatch`, the `ActionPatch` extension; a pure move, B73),
  `TextPatch` (with `case`, `words` and `word_style`) is `TextPatch.swift`'s,
  moved out so it could grow, and `ShapePatch` `ShapePatch.swift`'s (a pure
  move, the toll for `ReelColor`). `word_style` has ONE
  app-side writer, `CaptionLayout.place` (W-10). `ReelAgentSocket` (road map
  14's MC2) wraps `rc_agent_socket_start` / `_release`: `start` throws the
  core's sentence, `release` is the quit's unlink-if-still-ours with no join.
  The `dictionary` extensions on the property types are
  `OpDictionaries.swift`'s (below).
  The graphics engine's wrappers are here too: `GraphicLibrary` (`addFont`,
  `addAsset`, `rasterize`, `families()`; frozen by its first compile,
  rasterize or `families()`) and
  `GraphicModule` (`compile`, `describeJSON`, `svg`; it holds its library
  strongly), with `GraphicDiagnostic`, `GraphicFailure` (what a `diag_out`
  failure throws; `err_out` stays `ReelCoreError`) and `GraphicRaster`.
  `MediaDescriptor`, `MediaOriginal`, `mediaURL(for:)`, `originalURL(for:)`,
  `revealURL(for:)` (the original, else the copy), `isTrashed` and
  `bookmarkString(for:)` are `MediaDescriptor.swift`'s: a `media[]` element
  minus its id, and the media-file resolvers; they call no `rc_*`.
  It is also where the op table is read BACK: `ReelOp.coreNames()` over
  `rc_op_names`, and `ReelOp.coreSchemas()` over `rc_op_schemas` — every
  op's ARGUMENTS as JSON Schema, keyed by op name, which
  `AgentCatalog.opTool` prints for all fifty-nine op tools.
  `deinit` frees the Rust allocation. It also holds **the one read of
  `rc_project_apply`'s TWO message channels**, in the header's own order — a
  sentence is a refusal, an error message is invalid input, neither written
  is an identity — answered as the `ReelEdit` below.
- `OpDictionaries.swift` — the `dictionary` extensions on the §5.2
  property types (`CropInsets` … `Gradient`), the model's own key names; a
  pure move out of `ReelCore.swift` (#190, issue batch B52b; road map 14's
  MC2 made the same move as `PropsDictionaries.swift`, and the merge kept
  main's file). With
  `ReelCore.swift` and `ReelOps.swift`, the only files that write an op
  argument.
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
  `clearOps` and every agent call send, and it writes `off` only when non-empty and `schema` only when non-nil
  (the agent door fills it for a graphic end from the module's current
  revision, spec §11 G-34).
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
  `WordProps.swift` · `MediaSnapshot.swift` · `ActionSnapshot.swift` — the `Codable`, READ-ONLY mirror
  of spec §5.2 every view draws from. `ActionSnapshot.swift` (a pure move out of
  `ProjectSnapshot.swift`, B87) holds `ActionPatch`, `ActionSnapshot` and `ActionGraphicPatch` — an
  end's `graphic.props` and `kinds`, whose `dictionary` sends `props` only. `MediaSnapshot` (a pure move out of
  `ProjectSnapshot.swift`) carries a copy's or an ffmpeg conversion's `original`, and its `name` is
  the one display-name spelling: the original's name when one is recorded. **Its enums decode LENIENTLY**
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
  9's `textCase` / `words` / `wordStyle`, the recipe's `word` / `wordPop` and,
  since format version 12, `wordGlide` / `wordFill` / `wordDim`), a pure move
  out of `ProjectSnapshot.swift` because a stored property cannot be added
  from an extension. `RecipeReveal` reads and writes its OWN keys — siblings of
  `hash` and `text` in the `text` source — through `init(siblingsOf:)` and
  `encodeSiblings(to:)`, so a new recipe key costs `FrameRecipe.swift`
  nothing; a key spelled other than the snake-case converter spells it
  decodes silently to that key's default (the amount to 1, the rest to nil).
  `ProjectSnapshot+Graphic.swift` mirrors
  `model_graphic.rs`'s `GraphicProps` as `GraphicSnapshot` (`in` is
  `sourceIn`) and `GraphicPropValue` (string, number, bool; anything else
  `.null`), decoded into `ClipSnapshot.graphic`; `props` keys keep the
  module's own spelling (snake-case conversion does not reach a dictionary's
  keys). `WordProps.swift` mirrors `model_words.rs`
  (`TextCase`, `TextWord`, `WordMode`, `ActivePill`, `WordStyle`)
  — `WordStyle.dictionary` writes ALL eight keys (`active_fill` and `pause_dim` since format version 12; `ActivePill.dictionary` writes `glide`), `NSNull` for a nil slot,
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
- `ProjectDocument.swift` (+`DisplayStem`, +`Recording`, +`SelectedAction`, +`Import`, +`Graphics`, +`GraphicFiles`, +`UndoGroup`, +`CacheSaves`, +`Alerts`)
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
  consolidate. A range is cleared on every scope change: a pair of ticks means
  one thing inside a nest and another to an export. `+UndoGroup`:
  `inUndoGroupIfRegistered` runs a body with an undo group pending, and
  `registerUndo(restoring:actionName:)`'s first statement
  (`openPendingUndoGroup()`) opens it at the body's first registration, at the
  body's level and never while undoing or redoing; a body that registers
  nothing leaves undo and redo untouched (#167); `registerUndo` stays the one
  registrar. `cacheDirectory` calls `packageContentsDidChangeOnDisk()` when it
  creates `cache/` — only if the package's date, read through a fresh `URL`
  before the create, is still `fileModificationDate`, so an outside change made before it is not absorbed — and that method re-reads the date through a fresh
  `URL`, because `fileURL` still holds the date it cached at open (#138).
  `+CacheSaves` is the `save(to:ofType:for:completionHandler:)` override
  every save funnels through, bracketing it with the cache ledger's
  `saveBegan` / `saveEnded` (#115, #169).
  `+Import` is File ▸ Add Media… and every drop into an open project
  (`importMedia`, the probe chain and the one grouped commit), the opening
  read's probe (`probeForOpening`, a cancelled copy as `.userCancelled`), and the Media
  tab's Relink… and the missing-media sheet's body (`relinkMedia(_:)`: each
  file probed through `MediaImporter.probe`, one grouped "Relink Media" edit
  carrying each descriptor as `relink_media`'s `probe`, spec §11 #63, then
  `generateCaches()`; the missing-media sheet's door then alerts each
  unreadable file and each refused sentence (#180) through `present(_:)`).
  `+MissingCopies` re-copies, on open, a WebM/MKV copy that is missing or in
  the Trash from its recorded original (spec §11 #228-O), through
  `MediaImporter.probeBuiltInCopy` (never ffmpeg, never a question); a
  read on main or inside `withoutAsking` (an agent's `open_project`, off
  main since #231) passes no watch.
  `+Alerts` is `present(_:)`: every error the document shows waits in one
  queue (`DocumentAlertQueue`) and shows one alert sheet at a time, each asked
  for a main-queue turn after the last one's `didPresent` or the window's last
  sheet end, and only while no sheet is attached, since AppKit drops an error
  sheet asked for while another is attached (#195, `relink_sheet_probe.py`
  A1–A5); with no window, it is app-modal at once. `+Graphics`
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
  (object: the document) — never `rescan()` there; `stopGraphicStore()`, from
  `close()`, removes the observer, drops the set, stops the store and removes
  BOTH untitled roots — the graphics root (`removeScratchRoot()`) and
  `temporaryCacheDirectory` (`removeTemporaryCacheDirectory()`); the cache
  root goes at close ONLY, never at the first save, because the timeline and
  any pass in flight still hold its path (G-19 (d)). `startGraphicStore()` also observes the document's own
  `.projectDocumentDidChange` and ends with one `reconcileGraphicNames()`;
  `stopGraphicStore()` removes that observer. `+GraphicFiles` holds the three
  bodies BOTH doors call — `deleteGraphic(named:)` (refused while a clip
  draws the module, naming the clips per container),
  `renameGraphic(named:to:apply:)` (the file, its history, then one
  `set_graphic {name}` per container handed to `apply` as ONE step, moved
  back when `apply` throws or leaves a clip behind, the journal put back as
  it was read before the rename — only when the move back succeeded, so a
  failed one keeps its pair for the repair (G-28 (d)); refused with a nest
  open) and `restoreGraphic(named:revision:)` (which refuses a kept file
  whose bytes are not the revision in its name, G-29 (d)) — each ending its
  file act in one `rescan()`, every throw of its own a `ReelCoreError`; and
  the repair `reconcileGraphicNames()` (spec §11 G-28 (e)): after every
  committed change and once at the store's start, a journalled pair `[a, b]`
  says the app moved the file from `a` to `b`, and when a clip draws `a`,
  with no file and NO kept revision, while `b` has a file and no clip, the
  file is moved back from `b` — one direction only, never from a pair's
  first name to its second (G-28 (e), (f)) — and a file-less name WITH kept
  revisions is left alone even when a crash inside a rename, not a delete,
  left it so (G-28 (f)): it is otherwise a deleted module (G-27 (f)). Never
  call it, or any of the three bodies, from a `.graphicsDidChange` or
  `.projectGraphicsDidChange` observer.
- `MediaImporter.swift` (+`Probe`, +`Speech`, +`Peaks`) ·
  `MediaPeakBuckets.swift` · `MediaCacheFiles.swift` · `MediaCacheLedger.swift` ·
  `FFmpegRewrap.swift` (+`Plan`) · `AppSupport.swift` · `DecoderSupport.swift` ·
  `ContainerRewrap.swift` (+`Writer`) · `RewrapProgress.swift` ·
  `RewrapProgressWindowController.swift` — the import funnel and the three per-media caches (`thumbs/`, `peaks/`,
  `speech/`) inside the package. `DecoderSupport.swift` (await-free) is the
  per-process opt-in to macOS's supplemental VP9 and AV1 decoders (`enable()`:
  `main.swift`, `generateCaches`, `CompositionBuilder.firstTrack`, the harness
  and the formats probe), the import's one-frame decode (`decodesFirstFrame`,
  refusing only for `refusingErrorCodes`, -11833 and -11855) and the codec
  refusal sentence (`refusal`), spec §11 #216. `ContainerRewrap.swift`
  (+`ContainerRewrapWriter.swift`, both await-free) opens a WebM or Matroska
  file with no question (spec §11 #216-R): the core indexes it through
  `ReelContainer`, the first video and audio streams are copied unchanged by
  `AVAssetWriter` into `Rewrapped/` under `FFmpegRewrap.destination(for:)`'s
  digest name, the movie's timescale the least common multiple of 600 and
  the tracks' timescales (`ContainerRewrapWriter.movieTimeScale`, spec §11
  #232), the free space is checked first, #216's codecs are refused
  before the copy, and a codec the copy does not carry (`.unsupported`) alone
  falls through to the opt-in ffmpeg step. `RewrapProgress.swift` +
  `RewrapProgressWindowController.swift`: a click door's copy reports to a
  non-modal window shown after 1 s, which never takes the keyboard from a
  Reelcut window, and Cancel removes the partial copy (spec §11 #228-P). A
  tool call passes no watch.
  `async`/`await` is confined to `MediaImporter.swift`; the await-free halves
  are the `+` files, `MediaPeakBuckets`, `MediaCacheFiles` and `MediaCacheLedger`. A cache is CURRENT when its
  `complete.json` marker matches `CacheStamp` (the source's size and
  modification second plus the constants that size the cache — no path, so a
  moved or consolidated package keeps its caches); the marker is written
  LAST and only for a strip the pass can vouch for. Peaks alone wrap the
  unchanged source stamp in `PeaksStamp` version 1 and require a complete
  selected-track decode, valid PCM coverage and a usable record-sized
  Float32 payload; legacy or malformed peaks are unavailable until rebuilt.
  A stale cache is deleted
  first and a withdrawn peaks `.bin` is POSTED at once, and a media with no
  audio withdraws its peaks and voice files the same way (#180); passes for one file
  run one at a time in call order through `CacheLedger`
  (`MediaCacheLedger.swift`, an `NSCondition`, not an actor); a pass asked for
  another file cancels the earlier ones, which write nothing more and are
  waited for at most 30 s; no marker, waveform or voice file is written while
  a save of the package is in flight (`ProjectDocument+CacheSaves.swift`
  announces every save, which stops counting 120 s after it began), and a save
  waits for one being written; a failed waveform pass is retried in the
  session after 2 s and 10 s. The cache order is thumbnails → peaks → speech.
  `thumbnails` holds a
  video track's last frame past its end, from the track's last SAMPLE's time.
  `FFmpegRewrap+Plan.swift` (a pure move, issue batch B80) holds the plan,
  the command and the frame check; neither file imports AVFoundation. A
  conversion records the file it was made from as the descriptor's
  `original` (`MediaImporter.probeConverted`, spec §11 #233), as the
  built-in copy does; the re-copy on open stays the built-in copy's alone.
  A VP9 Profile 0 or 2 stream with a frame rate is COPIED, not re-encoded
  (spec §11 #227): into an MP4-format file under the `.mov` digest name,
  snapped to its frame rate (`-bsf:v setts=time_base=D/N:prescale=1`) and
  kept only when every frame is on that grid (`keepsFrameGrid`, ffprobe's
  packet times read from the `.partial.mov` before `convert` moves it into
  place); a copy that ffmpeg fails, that fails the check or that will not
  open is re-encoded once (`assist(_:mayAsk:planned:reencodingVP9:)` with
  `reencodingVP9: true`, from `probeConverted`, which hands it the first
  attempt's plan and makes no second call for a plan that copied no VP9),
  under the same policy; a re-encode this process made and kept is answered
  rather than discarded (`isKeptReencode`, `noteReencode`, under the
  conversion lock), and a conversion that will not probe is discarded only
  while it is still the file that was probed (`discard(_:ifStill:)`).
  `FFmpegRewrap+Plan.swift` also holds the step's named bounds and their
  sum `longestAssist`, from which `AgentServer.probeCeiling`
  (`import_media`'s and `relink_media`'s wait) is built, and the pure
  `onFrameGrid` the frame check calls.
  `FFmpegRewrap` is opt-in (`-RCFFmpegImport always`), and `assist`'s
  `mayAsk` is the CALLER's (spec §11 MC-5): `MediaImporter.probe` requires
  it, every click path passes `true`, a tool call's import passes `false`
  (`import_media`, `relink_media`, `record_screen` through
  `ScreenRecorder.start`), and `open_project` runs its synchronous
  `makeDocument` inside `MediaImporter.withoutAsking`, a thread-scoped key
  `probeBlocking` and the re-copy on open read (`isWithoutAsking`), on the
  lane's thread since #231 — never process-wide state, so a person's own
  import still asks while a call runs. It runs `Process` on a
  serial queue, and writes conversions under `AppSupport` — the ONE spelling
  of `~/Library/Application Support/Reelcut/` — never in the package.
  `AppSupport.ensureDirectory` is the ONE creator of that folder and of any
  folder under it: `0700` at each level it makes, an existing folder left
  alone (#108).
- `MediaConsolidator.swift` (+`EditorViewController+Consolidate`) — writes
  inside the package behind NSDocument's back, so it MUST call
  `ProjectDocument.packageContentsDidChangeOnDisk()` afterwards.
- `GraphicStore.swift` — one document's `graphics/` (road map 10 §5f):
  where it is (`<package>/graphics`, or an untitled document's
  `<NSTemporaryDirectory()>/Reelcut/<UUID>-graphics`, re-pointed by
  `packageDidMove(to:)` from the `fileURL` setter, posting
  `.graphicsLocationDidChange`), the scan (each legal `*.js` with its
  SHA-256 revision, G-13; `fonts/` validated on a throwaway
  `GraphicLibrary` once per file identity — size, modification date and
  file number — in `GraphicStore+Fonts.swift`'s `validatedFonts`, whose
  `fontVerdicts` is queue-confined and survives `stop()`/`start()` (spec
  §11 G-23 (f)); `assets/` with a 0-byte file, or a name `asset(name)`
  cannot use, warned and skipped, G-23 (e)) and the watch. **`graphics/` is created on the app's first write, never at
  open** (G-14): `ensureFolder()` is the ONE creator inside a package, and
  every app-side writer goes through `write(name:source:)` or it. While the
  folder is absent the store watches the PACKAGE directory, and the first
  observed appearance calls `folderDidAppear` →
  `packageContentsDidChangeOnDisk()` once — without it the next save is
  refused as "changed by another application". A folder source raises
  `.write` only and an in-place save raises nothing on it (G0 q7), so each
  module, font and asset file has its own source, up to `fileSourceLimit` (16
  a pass, modules first, then fonts, then assets, each in name order; spec §11
  G-19 (c), G-20 (a)); a source whose `open` fails is a scan warning,
  "`<subject>` is not watched: open failed (`<strerror>`)", `errno` copied
  first (G-20 (b); `GraphicScan.warnings`, shown by the Source section and `get_graphic {}`,
  G-24 (b));
  every pass re-opens every source BY PATH and
  arms BEFORE it scans; events coalesce over 100 ms. The queue owns the diff
  and an outbox; main publishes in order through `drain()` (`scan`, the
  callback, `.graphicsDidChange` with sorted names — every module and
  `library: true` when the font/asset set moved; with NO names when the
  folder holds no module and only the library moved, which still posts, G5b).
  `GraphicStore+Files.swift` holds the store's own writes:
  `uniqueModuleName(_:)`, the one free-name rule (`-copy`, `-copy-N`)
  Duplicate and Insert ▸ Graphic share, which takes a name as held when the
  scan OR the disk has it (`holdsModule(named:)`, #75); `write(name:source:)`
  and `importFile` land through `land(at:writing:)`, whose `.partial` is
  removed on any failure; and `removeScratchRoot()`, which removes an untitled
  root after `stop()` — from `packageDidMove(to:)` and `stopGraphicStore()`
  (G-19 (d)). It also holds the app's delete and rename, each inside
  `onQueue` (main only, never on the store's queue) so no pass runs between
  their steps: `removeModule(named:)` keeps the file's bytes and then removes
  it, refusing when the text could not be kept, and `moveModule(from:to:)`
  moves the file, journals the pair and reads it back — a rename that cannot
  be journalled is refused — and then moves its history, a throw leaving the
  file and the history where they were and the journal put back as it was
  read (its bytes, or no file: `renameJournalBytes` / `putBackRenameJournal`
  in `GraphicStore+History.swift`), so a refused rename journals no pair; a
  crash between the three steps is G-28 (f)'s limit; neither rescans.
  `write(name:bytes:)` is `write(name:source:)` for bytes as they are, and
  `noModuleSentence(_:)` the one sentence for an absent module.
  `GraphicStore+History.swift` is the kept revisions and the rename journal
  (spec §11 G-27..G-29): `graphics/history/<name>/<%06d sequence>-<revision>.js`,
  the last `historyLimit` (10) per module, and `history/renames.json`, at
  most `renameJournalLimit` (32) pairs. `keepReplaced`, called by `pass` on
  the queue before it stores its scan, keeps the bytes a module's new text
  replaced and drops the new text's own revision, so history never holds the
  current text; nothing is kept at `start()` or for a removal the app did not
  make, and `start()` drops each module's current revision from its history.
  `history/` is created only inside an existing `graphics/` (G-14) with no
  `packageContentsDidChangeOnDisk()` call, and `moveHistory` leaves no
  `history/<from>/` behind — which is what makes 'no file, something kept'
  mean a DELETED module. `GraphicStore+Import.swift`'s `importAsset` files a name
  `asset(name)` cannot use under `GraphicAssetName.legalized`, a renamed
  copy taking `-2`, `-3`, … while `holdsAsset(named:)` (scan or disk) says
  the name is held, and answers `name`/`renamedFrom` (G-23 (c), (d)). **`drain()` is not
  re-entrant: never call `rescan()` from a `.graphicsDidChange` observer.**
  `stop()` bumps a generation under `queue.sync`. `makeLibrary()` is a NEW
  builder every call (a library freezes on first use). It also writes the
  app's bundled reference into an EXISTING folder as `API.md` and `API.d.ts`
  (`writeManual()`, from `start()` for a saved package, `ensureFolder()` and
  `write()`; only when the bytes differ) — never a reason to create the
  folder (G-14).
- `GraphicScan.swift` — `GraphicModuleFile`, `GraphicFile` and `GraphicScan`,
  what one pass of the store found. `GraphicAssetName.swift` — pure: G-23's
  asset-name rule (`isLegal`, `legalized`, `withSuffix`, `maxBytes` 247 —
  255 less `.partial` — `rule`, `renameNotice`). `GraphicStore+Fonts.swift`
  — `GraphicFontIdentity`, `GraphicFontVerdict` and the scan's font pass,
  `validatedFonts(_:)`, queue only. `GraphicTemplates.swift` — pure: the
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
- `SpeedAudioDrop.swift` — the ×`audio_max` crossing (a trial through the
  core), the question's and the agent note's copy, and its one alert sheet
  (`ask`); every door that sets speed asks through it (#212, §11 #190).
  `EditorViewController+SpeedAudio` holds the Speed section's and the rate
  stretch's doors; the latter ends the live edit BEFORE asking (an autosave
  must never write a speed Cancel then takes back) and re-applies the
  frozen file's `lastLiveOps` on Set Speed, so it reads `ProjectDocument`'s
  `private(set)` `liveEditBase`.
- `+AddClips` (Add Text / Add Shape: the front track, else a new one;
  `addGeneratedClip` is internal and takes `grouped:` — `performGroupedEdit`
  when the edit lands outside the menu's event, as a panel's completion does),
  `+GraphicMenus` (Insert ▸ Graphic's templates and From File…, File ▸ Add
  Font/Image to Graphics…; the template item runs in-event through
  `applyEdit`, the panels through `performGroupedEdit`; the shared body
  `insertGraphic(from:grouped:) throws` shows no dialog, and a module that
  does not compile stays on disk and places nothing — G-16; a file that is not
  UTF-8 is refused by name before anything is written (#75); Add Image to
  Graphics…'s body is `addGraphicImage(from:) throws` (no panel), which
  shows `showGraphicNotice`'s informational sheet when the picture was
  renamed, G-23 (d); its `validateGraphicMenuAction` answers the four and
  forwards every other action to `validateGraphicFileAction`),
  `+GraphicFiles` (File ▸ Rename Graphic…, Delete Graphic… and Restore
  Graphic Version…, spec §11 G-30: three `@objc` actions, the ONE
  `presentAsSheet` of `GraphicFileSheetController`, in
  `presentGraphicFileSheet`, which beeps when the item has nothing to
  offer, and the validator arm `validateGraphicFileAction` — something to
  list, and for Rename no nest open; Rename and Restore open on the ONE
  selected clip's graphic when it is a row, a deleted one included, and
  Delete always on the first; nothing there writes a file or applies an
  op),
  `+Clipboard` (⌘X/⌘C/⌘V over the `com.kgalligan.reelcut.clips` pasteboard,
  the `paste` op's payload; ⌥⌘V Paste Attributes with no `groups`; and
  Edit ▸ Paste Graphic Properties, whose `@objc` action
  `pasteGraphicProperties(_:)` lives here and sends ONE `paste_attributes`
  with `groups: ["graphic"]` and `skip_missing` (spec §11 G-32). Every reader
  and writer takes its `NSPasteboard` as a parameter, the general one by
  default, and that action reads a pasteboard SENDER in place of the general
  one (a menu sends its `NSMenuItem`), so a probe drives all of them over a
  private pasteboard),
  `+Edge` (slip, roll, close gap, insert, overwrite, the `,` / `.` nudge —
  with an `extension TimelineView` because the two ⌥⇧ drags begin there),
  `+Identity` (Rename ⇧⌘R, the Label submenu over `ClipLabel.allCases`),
  `+Nest` (⌘G / ⇧⌘G), `+NestScope` (⌘↓ / ⌘↑ and the double-click that enters
  a nest; the three marker commands validate OFF inside one, because a
  nest-local tick sent unscoped would land at the wrong project time;
  `finishScopeChange` lands the player through `Playback.seekAfterRebuild`,
  never `setPlayhead`),
  `+Matte` (Track ▸ Matte, `setTrackMatte`, spec §11 MT-7: the current
  track's mode, undo "Track Matte"; its checkmark is the validator arm beside
  Solo's in `+Identity`),
  `+Motion` (Clip ▸ Motion ▸, one `set_video` PER CLIP; inactive stored edge
  titles refreshed at validation), `+Assistant` (`assistantSession()`: the
  window's live session or a new one, stored in the frozen file's
  `assistant` — spec §11 AI-4 — and closed by the window's `willClose`; its
  `onEvent` is set there, the ONE line that feeds `assistantTranscript`, which
  `assistant_tab_proof.py`'s mutant deletes. Road map 13 P2: that line is
  `assistantEventHandler(spendFolder: AssistantSpend.folder())`, the spend
  folder resolved once per session; the handler feeds the transcript and
  records each `cost` in the ledger, a ledger failure being at most one
  transcript note per session. Road map 12 A2 added the tab's
  glue: `installAssistant(on:)` from `installInspector`, `attachAssistant`
  wiring the view's five intents as one-line forwards, `assistantRefresh()`
  — run LAST in every path that can change the phase or the question, since
  `AssistantSession.send` goes busy and emits nothing, and the Assistant tab's
  dot's one writer (`inspector?.showAssistantBadge`, AI-19) — `assistantSend`
  (false = not taken, the composer keeps the text), Stop, Allow/Deny, Clear,
  View ▸ Assistant ⌃⌘A `showAssistant`, and `assistantConfigurationDidChange`,
  whose first arm writes a `settings` change to the live session
  (`updateSettings(settingsJSON())`) and returns, and which otherwise ends the
  conversation with a note on a Settings key or model change;
  the frozen file stores `assistantTranscript` and a weak `assistantView`),
  `+Export` (the
  dialogs), `+SaveFrame` (⌥⌘E; renders off-main on `frameGrabQueue`; passes
  no burn-in), `+PreviewQuality`, `+Eyedropper` and `+ZoomRegion`.
- The two modal canvas modes (`+Eyedropper`, `+ZoomRegion`) install a bare
  view over the canvas whose PRESENCE is the mode, through `armCanvasMode`,
  which ends every OTHER armed mode first; a third mode inherits that by being
  installed at all. The region frame reads the EVALUATED props (the opposite
  of every session in `CanvasSessions.swift`) because a region is drawn on
  what is on screen; ⇧ during the drag chooses `fill`. Their overlays sit
  above the canvas's region grips (CI-16) and take every press while armed;
  the outlines stay drawn under them.
- `EditorWindowController.swift`, `WelcomeWindowController.swift`,
  `AppDelegate.swift` (+`Menus`, +`Recording`, +`GraphicMenu` — the Insert
  menu's builder, File's three graphic-file items (`addGraphicFileItems(to:)`,
  called once from `fileMenu()` right after Add Image to Graphics…: a
  separator, then Rename Graphic…, Delete Graphic… and Restore Graphic
  Version…, no key equivalents, spec §11 G-30) and Help ▸ Graphics
  Reference, `showGraphicsReference`, on the delegate), `main.swift` — the window,
  the no-document window, the launch/terminate flow and the whole menu bar
  (spec §9). Menu items are nil-target selectors down the responder chain.
  `AppDelegate.swift` binds the agent socket at launch, then calls
  `ProjectDocumentController.complainUnlessShared()`, and releases the
  socket at quit. Copy MCP Command is Settings' MCP pane's (`MCPSettingsPane.swift`,
  spec §11 MC-7); there is no Tools menu.
  `main.swift` calls `ProjectDocumentController.install()` straight after
  `DecoderSupport.enable()`, and `AgentCatalogSnapshot.writeIfAsked()`
  straight after `AgentLane.prepareAtLaunch()`, at `#if` depth 0.
- `ProjectDocumentController.swift` — the app's `NSDocumentController`
  (spec §11 #234), made once by `main.swift` before any other can be (the
  first one instantiated is `.shared`); no other product file instantiates
  it. Its overrides of the two public asynchronous opens count, per
  `AgentServer.canonical` path and on main, the opens AppKit has in flight:
  one added before `super`, one taken off in the completion before the
  caller's runs; a reopen with no URL is not counted. `isOpening(url)`
  (main only) is what `open_project`'s two main-thread steps and
  `refuseHeldPath` ask; it answers false when `.shared` is not this class,
  which is every proof probe but `agent_open_probe.swift`, which subclasses
  it (so it is not `final`). A launch whose shared controller is not this
  class logs `Reelcut: `; `agent_socket_proof.py`'s `no-controller` mutant
  removes the `install()` line and must fail Z1.
- `EditorWindow.swift` — the editor's `NSWindow` subclass: its `sendEvent`
  routes a bare Space to play/pause unless the first responder types or
  presses on it (spec §11 K-1), so Space never beeps when focus has fallen
  to the window. A new text-taking or Space-handling view must be added to
  `SpaceKey.route` and to `tools/proof/space_key_probe.swift`.
  `EditorKey.isBare` is the bare-key map's modifier rule (⇧ ⇪ always;
  `.numericPad`/`.function` on function-key scalars; never ⌘ ⌥ ⌃), read by
  `handleEditorKey` (#61).

**Timeline.**
- `TimelineView.swift` (frozen) · `TimelineLayout.swift` (every ticks ↔
  points ↔ lanes conversion; `rowTop` is a prefix sum because S/M/L drives
  real heights per track KIND) · `TimelineBar.swift` · `TimelineClipDrawing.swift`
  (a clip is ONE object: body, name strip with the kind symbol, label dot,
  motion wedges for active edges only, filmstrip under a tint wash, waveform, grips on the
  selected clip, hatched transition zone; a track paints in three passes —
  bodies, transition zones, selection rings (`drawClips`, #66) — because a
  zone lies inside the PREVIOUS clip's body) · `TimelineSessions.swift` (drag,
  trim, slip, roll sessions) · `TimelineView+Rename` (the one inline editor
  for clips, tracks and markers; it drops an unchanged and an empty commit,
  follows its target through relayout, and ends with its commit DROPPED when
  the target is gone or on Escape; a commit goes through `onGroupedEdit`
  (`performGroupedEdit`), so a rename is its own undo step even when the
  mouse-down that ended it edits too (#69)) · `+TrackMenu` (the right-click
  menu on a header or an
  empty lane: the four toggles, checked, the Matte submenu (spec §11 MT-7),
  and Remove Track through
  `onRemoveTrack` to `removeTrackCommand`, which asks when clips would go;
  a clip hit answers no menu) · `+Candidates` (Remove Silences' wash, drawn not
  overlaid) · `+NestScope` (the breadcrumb, painted LAST in the ruler's
  corner so it stays above the header column when scrolled) · `+Matte` (spec
  §11 MT-7: `TimelineMatteTag` — the header tag's words, dimmed with no
  target, on its own line when the row has room above the toggles, else
  right-aligned on the name's line, and there `fitted` to "Matte" alone when
  the name would keep under 40 pt; `textColor` / `fillColor`, an undimmed
  tag's words `DS.textStrong` over the accent tint, never the accent itself,
  a dimmed tag's `DS.textMuted` over a fainter tint; `drawMatteTag` answers
  the words and box it drew; `drawMatteLane` — a matte lane's body passes in
  one transparency layer at 0.5, dashed accent outlines, and the accent
  bracket to its target at `pinnedX + headerWidth + 2`, repainted on scroll
  by `invalidateMatteBrackets`, which `pinFloatingBands` calls) ·
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
  keys (`graphic.props` keys included), the zoom test (an empty `graphic.props` does not stop
  `isZoom`), the 5 pt `grip` and `gripEdge` (none on a band 15 pt
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
- `PreviewCanvasView.swift` (frozen, 1124 lines) · `CanvasSessions.swift`
  · `PreviewCanvasView+TextEditFrame.swift` · `+TextEditKeys` — the picture at
  document size and the handle gestures. All coordinate mapping goes through
  `viewToCanvas` / `canvasToView`, and every handle maps through
  `AVPlayerLayer.videoRect`, which is the aspect of the BUFFER — the reason
  Preview Quality must keep the canvas's exact aspect. `+TextEditFrame`
  sizes the on-canvas text editor after every keystroke from the SAME
  measurement that sizes the applied box (`LayerRenderers.measuredSize`
  placed by `canvasRect`); never give the editor a second sizing rule, or
  the text jumps at apply (kpgalligan/reelcut#36). It also STYLES the editor
  from `LayerRenderers.textAttributes` at the box's view scale (spec §11 K-3):
  the render's font, kern and paragraph style, the editor's own ink.
  `+TextEditKeys` is the
  editor's keys (spec §11 K-2): bare Return applies, a modified Return is a
  newline, Esc over changed text asks Cancel · Revert · Apply in a sheet
  whose Apply goes through `performGroupedEdit` (a sheet completion is
  outside an AppKit event).
- `PreviewCanvasView+Obscure.swift` — the selected clip's obscure regions on
  the canvas (spec §11 CI-16): outline, centre and eight resize grips drawn
  through the layer's transform; hit test after the layer's own handles
  (`CanvasHit.yieldsToObscureGrip`), no grip while the target's start list
  and the drawn list differ in length (`obscureStartList`); cursor rects.
- `CanvasObscureSession.swift` — the region-grip drag (spec §11 CI-16): the
  whole `video.obscure` list with one entry replaced, through
  `CanvasEditTarget.op(video:clip:)`, travel read through the box on screen
  (`sourcePoint`), one "Move Region" / "Resize Region" step.
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
- `InspectorTab.swift` — `InspectorTab` (Clip, Media, Document, Assistant; the
  raw value is the strip index) and the three kind tests the Clip tab's
  sections are chosen by; a pure move out of `InspectorPane.swift` (road map
  12 A2) before `assistant` was added.
- `InspectorNameField.swift` — a pure move out of `InspectorPane.swift`:
  the one-line name field, drawn by `InspectorNameFieldCell` as the value
  field is (spec §11 SH-3); its placeholder is kept off the cell, which draws
  it at rest and under an empty field editor, so the field editor draws none
  (#199).
- `InspectorViewController.swift` (frozen: the tab strip, and the PINNED
  container between it and the scroll view that hosts a pane's
  `pinnedBlock`, one generation retired like the strip; the FOOT container
  under the scroll view, collapsed at priority 1 like the pinned one, which
  hosts `refusalStrip`, and the first line of `refresh(isLive:)` that
  clears a stale refusal; `selectClipSubTab`
  is a sub-tab pick's one refresh, and `refresh(isLive:)` calls
  `ClipPane.forgetSubTab()` whenever the selection's ids change, spec §11
  CI-5; a changed selection switches to Clip only from the Media and
  Document tabs, never from the Assistant tab, and `clipPicked()` from any,
  spec §11 AI-14; `onAssistantView` hands the editor the Assistant tab's view;
  `assistantBadge`, the Assistant tab's question dot, installed over the strip
  as the root's last subview, spec §11 AI-19)
  · `InspectorClipView.swift` (the inspector scroll view's clip view,
  installed first: a width change re-lays its document view, so a pane follows
  an autohiding legacy scroller, #142) · `InspectorRefusalStrip.swift` (spec
  §11 CI-10: "Refused: " and the
  core's sentence verbatim, remembered with the `editedProject` handle it
  was shown under and cleared on the first refresh under another handle or
  a click; `showRefusal` is the editor's forward of
  `projectDocumentDidRefuse`) · `InspectorTabBadge.swift` (spec §11 AI-19: the
  Assistant tab's question dot, a passive view over the tab strip — `hitTest`
  nil — mirroring `PanelTabsView.tabRect`'s arithmetic, since `Controls.swift`
  is not forked; `showAssistantBadge(_:)` is its inspector-side setter) ·
  `InspectorPane.swift`
  (the pane base — `pinnedBlock` is the header `makeHeader()` built, never
  stacked — and
  `InspectorBinding` — the one place that knows the fields read the
  SELECTED action's END state
  (`action(_:)` answers the selected action and never consults the playhead;
  `evaluated(_:)` asks `clip_state` at `clip.start + action.endTime`, spec
  §11 CI-2, or in `at(.start)` / `at(.playhead)` at the action's start or
  the playhead, over a cache keyed by clip and `ReadMode`; `.defaults` is
  what a row resets to — `VideoProps.identity`, `AudioProps()`,
  `TextProps()`, `ShapeProps()` — with no FFI and no cache entry, CI-9;
  `graphicProps(_:)` — a graphic clip's props in the binding's mode (the END with an action
  selected, the stored props with none), `[:]` in `.defaults`)) ·
  `InspectorRows.swift` (a pure move out of `InspectorPane.swift`, B87: the row builders, whose
  four typed ones derive a row's DEFAULT from its own `read` and `ops` unless `resets: false`;
  `inspectorRow(discrete:)` makes a row discrete — "at end" — when its control is none of the
  popup, checkbox or segmented control: the graphic string row and the Text tab's Content area;
  a row's widest `OptionPopupControl` — or, in a row with none, its widest
  `OptionCheckboxControl`, clipped to its bounds so its title stops at its edge — holds its
  intrinsic width only at compression resistance 749, below the one-line tag's 750, so a keyed
  row short of room narrows that control and never the tag (O8, G-34 (l): Font ▸ Family, a
  filter's and an obscure region's kind, a module's boolean with a long label)) ·
  `InspectorSlider.swift` (`InspectorSliderControl`, a pure move: the 7 × 11
  block knob snapped to device pixels (CI-6) and, keyed, the mint segment
  from the action's start value and the coral playhead tick) ·
  `InspectorBinding+Writes.swift` (a pure move: a write with an action
  selected goes to `set_action_end`, with `structural(video:for:)` the
  exception that sends a list of a different LENGTH, or `motion`, to the
  BASE props, and `structural(audio:for:)` the one that sends pan, mono,
  compressor, noise reduction, duck and keep-pitch there (CI-3);
  `ops(graphic:entries:clips:schema:)` / `ops(graphic:for:clips:schema:)` are G-34 (l)'s split: the base
  write keeps G-15 (b)'s nulls (`patchProps`), the end write carries the values and the module's schema,
  and an asset is the base's, by CI-3's mechanism; `split` forwards `schema`) ·
  `InspectorSection.swift` (`InspectorSection` with its `id`, `title`,
  `header` and folded `marks` readable — `differs` from an explicit closure
  else the rows' defaults, `editing` the selected action's number when a
  row animates — `clear()`, `reveal()` which writes no preference and is
  instant, the header click's `toggle()`, the collapse animation,
  through `DS.animate(DS.stateDuration)` (unanimated under Reduce Motion,
  spec §11 CI-15; the state is set at once), and
  `didToggle`, called by the header's click alone; and `KeyedReveal`,
  `ClipPane`'s auto-open, CI-8) · `InspectorSectionHeader.swift` (a pure
  move, then CI-9: the `◆N` / ◇ / ⊘, the one trailing slot — Clear while
  editing an action that keys the section, else Reset while it differs —
  `buttonTitle`, and `summaryInk`'s three tiers; the hover band
  (`InspectorHeaderHoverBand`, a second `DS.hoverFill` faded through
  `DS.animate(DS.hoverDuration)`, CI-15 amended by #102); the summary stops
  short of the VISIBLE button) ·
  `InspectorMarks.swift` (spec §11 CI-7: `RowMark`, `SectionMarks`,
  `InspectorRowDefault` (CI-9), the
  14 pt `InspectorMarkGutter` that is the FIRST view of every
  `inspectorRow` — blank at `.none`, so it must stay first for the refresh
  walk to reach it before the controls whose label ink and layer border it
  sets; hovered while keyed it draws × and a click removes the row's keys —
  `InspectorRowTag` ("at end", "now …"), `InspectorClipTag` (Normalize's boxed
  "clip" while an action is selected, #102), and the binding's mark
  queries, `selectedActionNumber`, `actionID(number:)` and `clearOps`, the
  ONE `set_action_end` of nulls (a `graphic.props.<key>` path nested one level deeper); `paths` read
  `set_graphic` (`graphic.props.<key>`, and `graphic.<key>` for width/height/length, so those rows
  are ⊘) and an end's `graphic.props.<key>`; `InspectorRowTag` is one line
  (`maximumNumberOfLines = 1`) so a row short of room narrows a CONTROL — the string field (O1) or
  the row's widest popup, else its widest checkbox (`inspectorRow`, O8) — never the tag; a row's paths come from the ops it WRITES,
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
  `ClipPane+Matte.swift` (`matteNote`, spec §11 MT-7: the note
  `ClipHeaderBlock` shows under the sub-tab strip when every selected clip
  sits on a matte track of one mode; `structureSignature` carries whether it
  shows) ·
  `ClipSelectionHeader.swift`
  (`ClipSelectionHeaderView`, a pure move out of `ClipPane.swift`) ·
  `ClipPinnedBlock.swift` (`ClipSubTab` — six cases in display order, text,
  shape, graphic, picture, sound, clip; `graphic` counts `graphic.props`, a stale key included (G-34 (l), CI-6 amended) — with
  its `◆N` key count,
  `ClipSubTabsView`, and `ClipHeaderBlock` — header, lane, sub-tabs and, when given one, the matte
  note — which
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
  +`Motion`, +`Obscure` — the Obscure section, a pure move; +`Speed` — the
  Speed section, Fit to and the "Audio is silent above ×12" note, #190) · `AudioPane.swift` · `TextPane.swift` · `ShapePane.swift` ·
  `GraphicPane.swift` (the Graphic sub-tab, road map 10 §5j, spec §11 G-15:
  a factory `ClipPane` calls when EVERY selected clip is a graphic; the
  shared module from `GraphicRegistry.entry(named:for:)`, main only, never a
  rescan; a structure signature of the schema's entries spelled WHOLE
  (default, bounds, options), stale keys, each asset entry's
  `GraphicSchemaRows.assetNames` (the rows' own call) and diagnostics — never
  stored values, the revision or the playhead; `schema(_:)` is memoised by
  name and revision (`schemaMemo`) and `report(for:)` reads a clip's layer
  through `layerMemo`, emptied on a new project handle; Properties, Size and
  Timeline; with no action selected every write is `set_graphic`; with one selected a Properties
  write — Reset's included (O7) — is one `set_action_end` naming `graphic.props.<key>` with the
  module's current schema, except an asset's, which stays `set_graphic`; Size, Timeline and Source
  still write `set_graphic` (Width, Height and Follow Clip ⊘); the structure signature also carries
  the selected action's end's stale keys (`endProps()`)) ·
  `GraphicPane+Source.swift` (Source: name, file, revision, Open / Reveal /
  Duplicate as New Graphic… — `store.write`, `rescan()` inside the button's
  event, one `set_graphic {name}` step — and `report(for:)`, the compile's
  diagnostics plus the first frame rasterized at the clip's OWN size,
  memoised and frozen during a live gesture; its groups sit under
  "Compiling the module" (the compile's top-level warnings, when any), the
  first-frame note (only when a frame was drawn) and "In the graphics
  folder" (the scan's warnings, each with Reveal), G-24, #221) ·
  `GraphicSchemaRows.swift` (pure, probe-callable; a colour default is read
  through the core, `ReelColor.normalise`, G-25 (c): the schema in the MODULE's key order —
  `GraphicSchema.orderedKeys` (in `GraphicSchema.swift`) scans
  `describeJSON()`'s text because the
  registry's dictionary lost it — one row per schema type, stale rows
  sorted with ⌫ writing `null`, CSS ↔ `RGBA`, and the null rule: a value
  equal to the default is written as `null`, a colour compared by parsed
  channels); rows read `binding.graphicProps`; `patchProps` (the base null rule over a
  map) and `actionStaleRow` (an end key the module no longer declares, ⌫ through `clearOps`);
  `decimals(for:)` (a step decides, else a fractional default, min
  or max) and `assetNames(for:files:clips:)`; a one-line string field's own
  height is re-pinned to `DS.controlHeight`, and its width is ≤ 170 required, == 170 at 249,
  compression 248, so it gives way only to "at end" (O1), as is `DocumentPane`'s marker
  name field. `GraphicSchema.swift` holds `GraphicSchemaEntry` and
  `GraphicSchema` (with `orderedKeys`), a pure move out of it ·
  `DocumentPane.swift` (reads `documentSnapshot`, never the scoped one: its
  ops are document-level; its transparency note names one or two alpha
  export formats and counts three or more, spec §11 G-33) · `OptionControls.swift` (the descriptor-driven
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
- `AssistantPane.swift` · `AssistantView.swift` · `AssistantTranscriptView.swift`
  · `AssistantComposer.swift` · `AssistantTranscript.swift` · `AssistantContextMeter.swift` — the
  Assistant tab (road map 12 A2, spec §11 AI-4). The pane builds its ONE
  `AssistantView` in `init`, never in `makeSections()` (a rebuild would take
  the composer's first responder), calls `onAssistantView` with it, and is
  exactly the visible height (`== 0` at priority 1 under the controller's
  `>=`), so the transcript scrolls itself. **The views hold no
  conversation**: the transcript is `EditorViewController.assistantTranscript`
  (`AssistantTranscript`, Rasterize's `handleEvent` ported as storage — a
  delta extends the last entry only while the previous event was the same
  delta type; `argumentSummary` drops `project`; road map 13 P2: it sums the
  `cost` events from `turn_started` to `turn_finished` into an
  `AssistantTurnCost` and ends the turn with its line as `.meta`, and
  `clear()` and `endConversation` reset the sum; road map 13 P4: every `cost`
  also adds to `conversationCost` and emits `.conversationCost`, and `clear()`
  and `endConversation` reset it and emit `.conversationCost` BEFORE their
  `.usage`, which `assistant_tab_probe`'s P1 needs last), the question the session's
  `pendingQuestion`, the session `EditorViewController.assistant`; a floating
  window later calls `attachAssistant` with the same view. **Return never
  answers**: Allow and Deny are `OptionButtonControl`s (a click, no key), Send
  is a 64 pt `AccentButton` with no key equivalent that reads Stop while busy
  or asking, and the composer's bare Return sends only while idle and beeps
  otherwise; a modified Return is a new line (spec §11 AI-17, K-2). No spinner
  (the harness settles). A label's frame is 2 pt wider
  than its text each side, and a row that holds a wrapping label is inset by 2
  pt; `snapshot_ui`'s outside_superview rule measures alignment rects since
  #140 and no longer needs the inset, which is kept. `AssistantTranscriptView`
  is a scroll view owning ONE non-editable, selectable TextKit 1 text view
  (spec §11 AI-17): each entry is a UTF-16 range of its one text (`spans`),
  one "\n" between entries, so a selection and a plain-text copy cross entries
  — its writable type is the legacy `NSStringPboardType`, because
  `writeSelection` answers false for `.string` (measured, B18); `.extended`
  inserts only the new suffix into its own entry's range; `entryLayout()`
  gives each entry's rect in the view's coordinates, and the layout dump reads
  the entries as parts it names (`UISnapshotParts`, dev only), which
  `assistant_tab_proof.py`'s `no-entry-parts` mutant empties; its
  `setFrameSize` holds the text view's minimum height at the clip view's, so a
  click below a short transcript reaches the text (`short-transcript` zeroes
  it), and `init` puts the text view's origin back at 0 after `documentView`
  (adopting it left the origin at minus its height, #182);
  `AssistantContextMeterView`
  the inline meter, `figures(_:)` (its three sentences) and `figureLadder(_:)`
  (the shorter rungs it shows, chosen in `setFrameSize`, when the full one
  does not fit; the tooltip always the full one; `full-figure-only`'s target);
  `AssistantConversationCostView` (the same file, road map 13 P4, spec §11
  P-7) the Spend row 6 pt under the meter and Clear, the rule under it:
  the first rung of `AssistantTurnCost.figureLadder` of `conversationCost`
  that fits beside its title ("≥"/"<" for "at least"/"under", still ending "·
  Reelcut's estimate", spec §11 P-8; the tooltip stays `figureTooltip`), which
  `reload(_:usage:cost:)` and `apply`'s `.conversationCost` set. Accessibility ids
  `assistant.composer|send|allow|deny|question|clear|settings|nokey|spend` and
  `assistant.entry.<kind>` are what the proofs read.
- `AssistantComposer.swift` — the Assistant tab's composer (spec §11
  AI-17). `AssistantComposerTextView` is a plain-text `NSTextView`: its
  `keyDown` is `TextEditKey.route` — a bare Return or keypad Enter is
  `onReturn`, a modified Return `insertNewline`, nothing routed while an
  input method has marked text; `insertTab` / `insertBacktab` move focus
  and never type a tab; and its undo is its OWN `UndoManager`, through a
  one-line `undoManager` override, because an editor window's manager IS
  the document's and typing would otherwise land on the project's stack.
  It also answers `undo:` and `redo:` itself (validated in
  `validateUserInterfaceItem`), because `NSWindow`'s own `undo:` reads the
  WINDOW's manager (measured, `assistant_tab_probe` P11). A set `string`
  (a send, the dev tools' pane path) drops its undo history.
  `AssistantComposerField` is its scroll view: DSField's 1 pt layer border,
  26 pt for one line plus one line height per further line up to five,
  then scrolling; it refits on every change and on a width change (in
  `layout()`, which P13 scores and `no-width-refit` removes; #182 item 3 is an
  accepted limit since B47: a refit from `AssistantView.layout()` lagged a
  pass); the placeholder is drawn in `placeholderRect`, one line high.
  `assistant_tab_proof.py`'s `modified-return-sends`, `tab-types`,
  `shared-undo` and `tall-placeholder` mutants edit its `.newline` arm,
  `insertTab`'s body, the override and `placeholderRect`'s height, each
  exactly once.
- `MediaPane.swift` · `MediaRowView.swift` (a row and the drag it starts,
  with `MediaDropMode` read from `NSEvent.modifierFlags` at the drop) ·
  `MediaPaneCommands.swift` · `MediaListFilter.swift` (the find band as a
  VALUE; not persisted) · `MediaUsage.swift` (the ONE spelling of "is this
  media used", over the timeline's clips AND every nest's) ·
  `MediaReveal.swift` — the Media tab. The find band never rebuilds the pane.
  A filter that hides the selected row clears `selectedMedia`
  (`dropHiddenSelection`, #68).

**Playback and rendering.**
- `Playback.swift` (+`Meter`, +`PreviewQuality`, +`Step`, +`Scope`) — one
  `AVPlayer` over the plan's composition; the transport, JKL, the rate KVO; `+Meter` is the level meter, moved out under
  the size rule. **Only a seek someone ASKED for reports a time**:
  `seek(to:)` is that door, and Playback's own RESTORES — the rebuild's item
  swap and re-seek, the paused refresh's round trip — go through `startSeek`
  silently and report once, only if they come to rest off the last reported
  tick; a scope change seeks through `seekAfterRebuild(to:)`: its time is the
  NEW container's, so the outgoing item is neither sought nor heard and the
  rebuild in flight lands there, heard once (#130, `scope_playhead_probe.py`);
  an asked seek that arrives while a restore is seeking is heard once, when it
  lands; `update`'s same-plan and empty-plan arms discard a rebuild in flight;
  a held scope change whose rebuild fails, or whose new plan is empty, drops
  the item rather than leave the outgoing one, keeps its time and is heard
  once (`endHoldWithoutItem` in `+Scope`, #185; the seek flags are internal
  for `+Scope` alone); `rebuildHop` is the probe's seam, nil in the app, and
  its block takes an error it delivers as the build's failure; `report(_:)` is the one
  caller of `onTimeChanged`. While paused, an observer callback is heard only
  for the tick the player is at or seeking to, and only when it differs from
  the last report — a late callback for a superseded seek or a swapped-out
  item is dropped (#204, #209; `playhead_echo_probe.py` twice·1, pause·1) —
  and every seek's landing reports its rest once when it differs. `+Step`
  also holds the main hop `onMain`. An echoed restore
  moved the playhead (0 and back on every rebuild), and the timeline reveals
  every moved playhead, so a clip drag yanked the view
  (`playhead_echo_probe.py`). **A paused refresh is a one-tick round trip**
  (`refreshPausedFrame`): a zero-tolerance seek to the current time is a
  NO-OP on macOS 26.5.1, so the refresh seeks one tick off and returns; parked
  at the end it rests on the last frame's final tick, because the end tick
  composes black. Do not put a same-time seek back. Preview Quality overrides
  `renderSize` on a copy of the builder's
  `BuiltComposition.videoConfiguration` here (`Playback.previewComposition`,
  static so `phase8_chrome.py` calls it), keeping the
  canvas's EXACT aspect (`m · (w/g, h/g)`, coarser when the divisor does not
  divide `g`, Full for a coprime canvas); `AVPlayerItem.videoComposition` is
  a COPY property, so the setter re-assigns. `makePreviewLayer` is the one
  door to a second `AVPlayerLayer`.
  The item is dropped only for an EMPTY timeline (`plan.duration <= 0`,
  where the transport beeps). Never gate it on the plan's track lists: a
  timeline of only graphics, text, shapes or images has no plan track and
  plays over the builder's placeholder (road map 10 §10.8,
  `media_less_playback_probe.py`).
- `CompositionBuilder.swift` (+`InstructionRanges`, +`AudioTracks`) — the
  app's ONE builder of the video composition, from an
  `AVVideoComposition.Configuration` it keeps on
  `BuiltComposition.videoConfiguration` (#91; a variant — Preview Quality's
  size, an export row's rate — is that value with one field changed, never a
  `mutableCopy()`), shared by the preview, both
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
  track two formats. `+AudioTracks` also holds `audioParameters`, whose
  `volumeLegs` holds each composition track's envelope at its first sounding
  segment (one whose source resolved) from time 0: AVFoundation starts an
  input at 1.0 and slews every change at full scale per 1200 frames (#87,
  §11 #87).
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
  pin's life, then at most 64 warnings distinct by graphic and messages,
  frame aside (`sameWarning`, G-24 (c)), so a warning can never displace a
  failure. `GraphicModule.compileWarnings` decodes describe's `warnings`. `LayerRenderersGraphic` hands the engine the core's
  own `props_json` / `ctx_json` untouched and keys the texture by the SVG
  TEXT, the size and the library version, in `LayerRenderers`' separate
  six-entry graphic pool. A graphic that fails — no module, not compiled, a
  throw or timeout, a refused raster — draws its ERROR CARD, keyed by its
  own text in the graphic pool, never the last good frame; a raster's
  warnings ride in `Rendered.warnings` so a pool hit still reports them.
  Only no set and a failed upload are nil.
- `GraphicPrefetch.swift` — an export's graphics rasterized AHEAD on worker
  threads (spec §11 G-26, #127): only an `ExportWriter` export with a
  pinned set and a graphic in range. `activeProcessorCount − 1` Foundation
  `Thread`s (8 MiB stacks, their QuickJS engines dying with them) walk
  `range.start + i × frameDuration` on the export's key, reading only
  `RecipeSource.recipe(for:at:)` and `GraphicRegistry.resolve` (the pin,
  G-13), and fill `Slot`s — exactly `LayerRenderers.graphic`'s inputs —
  with a texture key and a raster; at most `4 × workers` slots and 1 GiB
  held. `LayerRenderersGraphic` asks `take` on a pool MISS and uses the
  raster only when the worker's texture key equals its own, else rasterizes
  as before; a pool hit `discard`s the slot. The compositor still runs
  `svg`, records every report and draws every card (G-8), so the file is
  the serial path's. One `NSCondition` guards everything; a worker never
  waits holding an unfinished entry, so `take`'s wait always ends.
  `ReelcutGraphicPrefetchOff` (YES) is the measurement switch; each session
  logs one `[reelcut] graphic prefetch: …` line once it is stopped and its
  last worker has exited.
- `FrameRecipe.swift` — the frame recipe's Swift side (spec §7.3), decoded
  leniently: `RecipeCanvas`, `RecipeSourceRef`, `RecipeTransition`,
  `RecipeClipRect`, `RecipeLayerMatte`, `RecipeLayerDissolve`,
  `RecipeMatteGroup`, `RecipeLayer` (with `matte` and `dissolve`) and `FrameRecipe` (with `mattes`), out of
  `ProjectSnapshot.swift`; the canvas hit-tests through `CanvasLayerBox`.
- `TrackMatte.swift` — a track's matte mode, mirroring `model_matte.rs`: raw
  values, `displayName`, `shaderCode` (the case index — a shader
  discriminant, append only) and `target(of:in:)` (the core's
  `matte_target`, for the chrome only); `TrackSnapshot.matte` decodes it
  leniently.
- `Compositor.swift` · `Compositor+Uniforms.swift` · `Compositor+Shadow.swift` ·
  `Compositor+Matte.swift` · `MattePlan.swift` · `Compositor+Dissolve.swift` ·
  `CompositorEffects.swift` · `LayerUniforms.swift` (`LayerUniforms`,
  `ShadowUniforms`, `TransitionCode`) · `Resources/Shaders/Compositor.metal`
  — the per-layer pass. The working format is `rgba16Float`
  (`MetalRenderer.workingFormat`, from `Compositor.outputPixelFormat`,
  `64RGBAHalf`; spec §11 PR-1): every layer, blend, shadow and dissolve
  pipeline's attachment, the destination, each matte composite and dissolve
  half, and the shadow pair. The coverage stays `r8Unorm`. `texture(from:)`
  wraps a buffer by its own format. The uniform block's field ORDER is a contract with the
  shader checked only by reading both, so change them in one edit; it is 104
  floats and **the padding tail is EMPTY** (the next field needs three
  companions). **Seven pipelines from five fragment functions**: the two
  programmable-blend pipelines MUST be built with fixed-function blending
  OFF, or the finished pixel is blended twice — invisible over an opaque
  destination, so a proof of it reads the ALPHA channel over a translucent
  one. A shadow's silhouette pass takes `maskState`, the gather
  specialization without the blend (defensive, not load-bearing). A shadow's
  three passes and its canvas-sized pair are `Compositor+Shadow.swift`'s
  (`encodeShadow`); a layer's uniforms and source texture are made by
  `prepare` in `CompositorEffects.swift`, which `encodeLayers` calls once per layer.
  A video frame is premultiplied only when its buffer's
  `kCVImageBufferAlphaChannelModeKey` attachment says `PremultipliedAlpha`
  (`declaresPremultipliedAlpha`, asked by `source(for:…)`), and straight
  otherwise, an unlabelled one included (spec §11 G-35 (b)).
  A layer's uniform block is filled by `uniforms(for:…)` in
  `Compositor+Uniforms.swift`, with `partnerBox` and `clearColor`.
  The matte pass is `Compositor+Matte.swift`'s `encodeMattes`, run BEFORE the
  destination pass opens: each group the recipe's `mattes` lists is drawn by
  the layer pipelines into a pooled destination-sized target (`MattePool`),
  scheduled by `MattePlan.swift` (spec §11 MT-9: each cut set resolved once
  its last matte is drawn, a composite given back after its last resolve; the
  pool keeps what the renderer's last 30 frames held, a frame being one
  `render` call),
  each cut set resolved by the sixth pipeline, the matte resolve (r8, source
  factor zero, destination factor `sourceColor`), into a pooled coverage the
  layer stage samples at `texture(1)` — every layer draw binds one, the 1×1
  placeholder when nothing cuts it, and so do the shadow's silhouette pass
  and the reflection. A layer whose `matte.into` is non-null is never drawn
  on the canvas, and a cut naming a matte not drawn before it fails the frame
  (`MatteError.unordered`). Blending is in the ENCODED sRGB space,
  deliberately. `[[position]]` arrives in
  DESTINATION pixels, and `canvasPerDestX/Y` is what turns it into canvas
  pixels — an invariant that held only because the two had always been
  equal, until Preview Quality. A layer mid-transition blends `normal`
  because the CORE emits it; grow no second opinion here. Where two obscure
  regions cover one fragment the GREATER hiding wins. A layer's opacity is read as
  `RecipeLayer.drawnOpacity` (`CompositorEffects.swift`): the recipe's
  `opacity`, times `1 − word_dim × pause_dim` for a timed text page with no
  backdrop (spec §11 W-16). A routed `cross_dissolve` or `zoom` (a layer's
  `dissolve`, spec §11 MT-8) is `Compositor+Dissolve.swift`'s. `encodeLayers`
  walks a layer list — the canvas's in `render`, a group's members in
  `encodeMattes` — and draws each routed dissolve's two halves into two pool
  targets, then mixes them onto the pass with the seventh pipeline
  (`reelcut_dissolve_fragment`), which scales a zoom's halves about their
  anchors there. `drawLayer` is the one per-layer draw both use.
- `LayerRenderers.swift` · `LayerRenderersText.swift` · `LayerRenderersReveal.swift`
  · `LayerRenderersWords.swift` · `LayerRenderersBackdrop.swift` — text and
  shape descriptions to textures,
  keyed by the recipe's `hash` (`RecipeSourceRef.cacheHash` is the WHOLE key;
  nothing here may append to it — a graphic's key is its SVG text instead,
  `LayerRenderersGraphic.swift`, in its own six-entry pool). Text draws what the recipe computed; the
  LAYOUT is always the full text's, laid from `laidContent`, cached without
  the reveal or the word, and `reveal = 1` takes the plain `CTFrameDraw` path
  so a full reveal is byte-identical to no animation; a line or token at
  PARTIAL alpha draws inside a transparency layer so fill and stroke composite
  once. `LayerRenderersText` is measuring, layout, the per-axis `textInsets`,
  `textAttributes(_:scale:)` (the one attribute set, which `attributedString`
  and the canvas editor both take) and `drawText`, which dispatches — the
  words arm FIRST, then the three
  reveals, which are `LayerRenderersReveal`'s. `LayerRenderersWords` is a
  timed page (road map 8's W3): tokens of `laidContent` only, clipped at the
  whitespace midpoints; the active token `word − 1` scaled about its pill's
  centre, the pill filled UNCLIPPED, then the midpoint clip set in TEXT space
  so it scales with the token. `drawWords` takes the recipe's `glide`,
  `fill` and `dim` (spec §11 W-14; each defaulted to nil, each clamped to 0…1 —
  `glide` and `fill` there, `dim` and `pauseDim` in `dimAmount`): with `activePill.glide` not set and the
  other two nil it makes the calls it always made, in their order
  (`word_looks_proof.py` B1 holds an older project's frames to the bytes).
  A GLIDING pill is filled BEFORE the base pass in every frame of the page,
  between token `word − 2`'s pill and the active one's at `easeOut(glide)`
  when each lies on one line, else settled, scaled about its own centre; the
  active token then draws with no plate. A FILL clips the active ink at a
  hard edge on a whole device pixel (`left + fill × (right − left)`; the
  token's own clip bound at 1), with the upcoming ink right of it in
  `highlight` and nothing in `build`. A DIM is drawn in one of two places, by one rule
  (`wordDim(of:reveal:)`, spec §11 W-16): on a page with no backdrop the
  bitmap holds none of it and the compositor multiplies the layer's opacity
  (`RecipeLayer.drawnOpacity`); on a page with a backdrop `drawText` hands
  `drawWords` the dim, and it is one multiply of the page's bitmap
  (`scaleBitmap`) at `1 − dim × pauseDim`, after which `textBitmap`
  composites the backdrop under the words (spec §11 W-17).
  `LayerRenderersBackdrop` is the backdrop of a text page: its fully covered
  pixels written by vImage with CoreGraphics' own bytes, its edge by
  CoreGraphics; under the words on a timed page (spec §11 W-17).
  `dimAmount` is the one clamp, and the texture key is still the recipe's
  hash, `word_dim` included. None of the three moves a glyph or the box:
  `layoutKey`, `frameKey` and `wordHeadroom` do not read them.
  `wordHeadroom` sits inside `measuredSize`
  (zero with no style or a colour-only one; 0.45 em and 0.30 em are FLOORS
  under the formula, plus `wordHeadroomEdgePx` horizontally and `wordHeadroomVerticalEdgePx`
  vertically; with NO pill the horizontal term ADDS the popped stroke,
  `peak × outline / 2`, where a pill's keeps `− outline` — road map 8
  §10.7, W4a), so the box never depends on
  `word`, and `layoutKey` gains `case` and the headroom's inputs only when set
  — never `words`, `word`, `word_pop` or the three looks' values. `renderTextBitmap` is the drawn
  bitmap `renderText` uploads; its body is `static textBitmap`, which the
  Generate Captions sheet's preview draws with, off-Metal (road map 8's W4b). A shape's gradient SORTS its stops (the core
  does not police order), projects a linear ramp onto the box, and is ignored
  by `line` and `arrow`. `maxTextureSide` is never below
  `GraphicLibrary.maxSide`, since an error card is drawn through `bitmap(_:)`
  at the graphic's size; `core/tests/graphic_ffi.rs` reads its `static let`
  line, so it stays one integer literal.
- `AudioTap.swift` · `AudioDSP.swift` — the `MTAudioProcessingTap` playback
  and export share, and the four sample-level effects: noise reduction (a
  512-sample delay), the compressor, the mono fold (BEFORE the pan, or it is
  algebraically self-cancelling) and pan (constant-power, unity at centre).
  A track whose clips ask for none is bit-identical.
- `Exporter.swift` · `ExporterLoudness.swift` · `ExporterSettings.swift` ·
  `ExporterWriter.swift` · `ExporterWriter+Settings.swift` ·
  `ExporterWriter+Chapters.swift` · `ExporterAudioGain.swift` ·
  `ExportStraightAlpha.swift` · `ExportStraightAlphaHalf.swift` ·
  `ExporterImageSequence.swift` ·
  `ExporterErrors.swift` · `ExporterGraphics.swift` — the writer
  (`ExportWriter` REPLACED `AVAssetExportSession` so chapters, bitrate and
  size have one path) and the one-frame offline render. An export is TWO
  passes wherever the file holds sound: a measurement build of its own in
  32-bit float, then the write: un-normalised from a 16-bit decode (a mix
  past full scale clips there, and `mixClipped` says so); normalised from the
  same float decode the measurement read, gained and quantised once by
  `ExportAudioGain` (#86). The alpha movie rows' frames (`prores_4444`,
  `hevc_alpha`) are straightened in the video pump before `retimed`:
  un-premultiplied, each transparent pixel within 4 px of a visible one
  filled with the nearest one's colour, and labelled `StraightAlpha`, with
  `hevc_alpha`'s encoder key straight too (`ExportStraightAlpha.swift`, spec
  §11 G-35): `prores_4444`'s in place in float, `hevc_alpha`'s rounded first
  into a pooled 32BGRA buffer (`ExportFrames`, `ExportStraightAlphaHalf.swift`,
  PR-3); the fill is one generic pass over `StraightAlphaLayout` (`BGRA8`,
  `RGBAHalf`), whose `allVisible` keeps the whole-row check vectorised.
  `h264`'s and `hevc`'s frames are rounded to 8 bits the same way and not
  straightened, and `hevc` is pinned to Main; every other row's frame goes
  to the encoder as drawn.
  `ExportWriter` FILLS the frame when a fit would leave at most
  a pixel uncovered, or — the frame a canvas-SHAPED size less at most one
  pixel on each axis, `(bw + a)·ch == (bh + b)·cw` for some `a`, `b` in
  {0, 1}, at any scale — when a fill would overshoot by at most one
  (`shapeGap`: `gap <= limit`, in integers), and letterboxes past that, where
  an alpha-carrying movie row (`prores_4444`, `hevc_alpha`) is refused instead
  (padding inverts the alpha; a pure scale is fine); so no size of the
  canvas's own shape is refused for being odd, and a typed size of another
  shape is judged as the even frame it becomes; the frame is the size the
  CORE resolved, already even where the row needs it (spec §11 G-33), and
  `encodedSize` is only the floor under it; a missing encoder is
  `.presetUnavailable` and no file (`Exporter.encoderOutcome`, in
  `ExporterErrors.swift`, applied where `startWriting` hears the pipeline); `apng` FITS instead and must not
  grow the guard. GIF and APNG refuse past 600 frames rather than truncate.
  `renderFrame` is documented off-main. Audio export is NOT bit-deterministic
  within an 8 ms window at a duck ramp edge (AVFoundation's mix); a duck-free
  project decodes byte-identical. `ExportError` is `ExporterErrors.swift`'s.
  An export PINS the `GraphicSet` it was handed for its whole life, GATES it
  before the build (`ExporterGraphics.graphicsRefusal`: a graphic clip in
  the range, or in any nest reached from one, however deep, whose module did
  not compile or is missing, refuses before the destination is touched), and
  ABORTS on a recorded failure: `pollProgress` cancels and `finish` removes
  the file and answers `.graphicFailed`, whatever the pipeline said.
  `startWriting` starts the graphic prefetch (`startGraphicPrefetch`, G-26)
  after the pipeline is picked, and `finish` and `deinit` `stop` it on the
  line before each `unpin`.
  `Exporter.graphicWarnings` (`ExporterGraphics.swift`'s
  `ExportGraphicWarning`, each (name, message) once with its first frame) is
  published in `finish` before the unpin and read by the progress sheet
  (count on the line, list in the tooltip), the queue (`Job.graphicWarnings`;
  the count right after "Exported “…”." since the row truncates its tail;
  `ExportQueueRowView.toolTip(for:)`) and `export`'s `graphic_warnings`
  (G-24 (c)).
  **`ExportWriter.cancel()` and `Exporter.cancel()` only set flags**; the
  measurement's loop cancels its own reader, and the writer's reader and
  writer are cancelled in `allInputsFinished`, after every pump has left its
  loop — cancelling a reader under a running `copyNextSampleBuffer` crashed
  the process. Never call `cancelReading` from another thread while a loop
  reads; a read that never returns is not woken (spec §11 G-17).
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
  `place` takes a `CaptionStyle` and the run's `CaptionLooks` (`looks:`,
  `.none` by default, handed to `pagePatch`; spec §11 W-15): `.subtitles` is the
  Caption-preset
  path, byte for byte for a cue with no speaker (a speaker's cue adds its
  palette `color`, spec §11 R6-22); a word style writes
  `CaptionStyle.pagePatch` per page — the pager's own props at the page's size (a shrunk one or the
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
  built from it (both take `looks:`, a `CaptionLooks`, `.none` by default: the
  pager asks with none, the sheet's preview and `place` pass the run's, and they
  change `word_style` alone, never the measurement, W-14), and `speakerPalette` / `speakerColors`, R6-22's four colours
  by first appearance — so a committed page is the measured one and a shrunk
  page's outline is em × its own size. A GENERATION choice, not an inspector preset;
  `defaultsKey` is the sheet's remembered style, read when the Style popup
  is built and written by `styleChanged`; the tool never reads it (R6-2
  read across).
- `CaptionLooks.swift` — the three LOOKS a run may add to a word style's
  pages (spec §11 W-15): `CaptionLooks` (`slide`, `fill`, `dim`; `.none`;
  `dimDepth` 0.5, the `pause_dim` a ticked Dim writes; the three remembered
  keys `ReelcutCaptionSlide` / `Fill` / `Dim`, read and written by the
  sheet alone), `Look` (the tool's argument names; `title`, `defaultsKey`,
  and `isLive(for:)` DERIVED from the style's own `wordStyle` — a slide
  needs a pill, a fill `build` or an upcoming colour that is not the active
  one, a dim a word style — with `styles` and `styleList`, the one list
  `transcribe`'s descriptions and refusals print), `live(for:)`, `names`,
  and `CaptionStyle.wordStyle(_:)`, the preset with the live looks turned
  on and EVERY other field carried by name (`word_captions_chrome.py`'s
  `rebuild-drops-preset` removes one). The no-argument `wordStyle` is the
  presets and is not edited by a look.
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
  of its media's one transcript. `+Report` holds what the `Outcome` has no
  room for (`uploaded` with the transcript-write and marker-write results,
  `transcriptWritten` and `stampWritten`, `cached`,
  `janitorDeleted`, `janitorFailed`, `janitorDeferred`, `held`, and
  `refusedUndeleted` — a transcript refused after it was made whose DELETE
  failed, owed to the dashboard with no retry, R6-20) and owns the
  shared cleanup warning wording for the sheet and MCP result or failure.
  `billedSeconds` is the ONE sum of `audioSeconds` — each term floored at 0,
  saturating at `Int.max` — that the bill sentence and `audio_seconds` read;
  `cacheWarnings` is one sentence per uploaded media whose marker did not
  land, and promises nothing about the next run.
  A nil client admits only a nonempty, entirely
  current batch and skips janitor/network, retaining pending IDs as deferred.
  One media's failure is one media's problem (the catch first records a
  `Refusal` whose DELETE `failed` in `refusedUndeleted`, then reads its
  `ClientError`) and the run carries on, with exactly two exceptions: a CANCEL
  and a REFUSED KEY. `+Media` holds `retryDeletes` and `fetch` — the ten-hour
  refusal BEFORE the extract, the `defer` that removes the temporary audio on
  every exit, the server's model and language filtered through
  `withoutCredential` and then bounded at 64 Unicode scalars (`bounded`,
  `serverStringLimit`, #200), `audio_duration` floored at 0, words any of
  whose served strings — every key and value at any depth, scanned from the
  bytes (`TranscriptWord.servedStrings`, R6-23) — repeat the key refused
  (the transcript deleted) before any write, the cache file
  written before its marker, and the DELETE last with its answer recorded —
  its `remote_deleted` rewrite only over a first write that landed (#187).
  Spec §11's R6-11: a media in this run's
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
  four phases at 0.25 / 0.65 / 0.95, the submit holding at the upload's end
  (0.65) with a line of its own, the wait advancing on the clock against q8's
  147× and holding, and the five detail lines, a count under a megabyte spelt
  `<1`. The run publishes
  `max(previous, computed)`.
- `AssemblyAITranscript.swift` — the wire VALUES, and
  `TranscriptOptions.keyterms`, the ONE spelling of the vocabulary's
  trim/de-duplicate/cap that the sheet's field and the tool's argument share:
  `TranscriptOptions`,
  `TranscriptRequest` (whose `encode` is the whole wire body — `language_code`
  absent for auto, `keyterms_prompt` absent when empty), `TranscriptWord`
  (with `servedStrings`, every string literal of a served `words` array
  decoded by a lexical scan, which `fetch` reads for the key),
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
  and EVERY throwing exit deletes the transcript first — `refusing`
  (`+Session`) answers a `Refusal` carrying that DELETE's answer
  (`deleted`/`failed`/`notSent`), which `CloudTranscriber.transcribe` unwraps
  before reading its `ClientError` (R6-20). A `completed` body
  whose `words` is absent, null or not an array is `.malformed`, never an
  empty transcript; `[]` is zero words. A `completed` body whose `id` is not
  the polled id is `.malformed` too (`requireEchoedID` in `+Session`, #71), so
  the id `fetch` stores and deletes is always the submitted one. `note` writes
  straight to fd 1 through `FileHandle.standardOutput`, never `print`, so a
  file-redirected log is complete (#116). `request` and `send` stay in the
  first file, with `withoutCredential(_:)` beside them: those three are the
  members that touch `credential`, and that helper keeps the three sentences
  the client RELAYS verbatim — a 402's, a 4xx's and a transcript's `error` —
  from carrying a key a server echoed back; `relayed` (`+Session`) then cuts
  each to 300 Unicode scalars (R6-23). `isSendableIdentifier`
  (`+Session`: `isPlainIdentifier` AND not `carriesCredential`) is the ONE id
  gate — `poll`, `delete`, a submit reply and a recovery-list row — so an id
  that carries the key is never sent or accepted. `delete` answers THREE
  states (`deleted`, `failed`, `notSent`): an id that is not sendable is never
  put on the wire. `delete(id:cancel:)` reads the run's token as a STOP and
  never attaches it: a DELETE is cut `deleteAfterStop` (2 s) of wall clock
  after the later of the Stop and its own start and answers `failed`, owed
  like any other (R6-19); `send`'s `stop`/`grace` and `+Session`'s
  `waitForReply` are that bound. `+Session` also holds `ClientError`'s two
  readings, `isRetriable` and `shortName`, moved out at the cap. `+Submission`
  owns the single paid submit and R6-14's
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
  directory `AppSupport.ensureDirectory` makes, `0700` at each level it makes
  — never `chmod`ed after; `MemoryStore` is
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
  `pagesRequest` COMPUTED off those controls; +`Looks`: the three look
  checkboxes and the on-device note, spec §11 W-15 — `looks` is each box
  ENABLED and on, `lookChanged` the card's third `defaults.set`, written by
  a click and never by Generate, `refreshLooksRow()` greys a box that is not
  live and leaves its tick) — on-device recognition through
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
  tool's refusal ORDER is the caller's own mistakes first (the style, `replace` and a `slide` / `fill` / `dim` that would show
  nothing, then scope, `engine`, cloud-only arguments, the tag's spelling), then the installed model, then
  the run; the tool NEVER downloads — a person does, from the sheet. `Job`
  carries `media` for the cloud engine, which uploads a MEDIA once;
  `CancelToken` holds a `SpeechEngine.Handle` and a `URLSessionTask`, under
  one lock and cancelled outside it. Both engines hand each job's words to `CaptionPages.cues` with the
  job's `span` and their own `TranscriptionEngine`; `Job.span`
  (`+Jobs`) is the one spelling of a job's timeline span. The sheet's `style` is read off the Style popup's item and
  `replaceExisting` is true only while the checkbox is ENABLED and on —
  enabled only for a word style over tracks `replaceableTracks` names, the
  tool's two rules — and `finish` passes both, and `looks`, to `place`, so the sheet
  commits what `transcribe {style, replace, slide, fill, dim}` commits. The preview is
  `CaptionPages.samplePage` of the first job's cached transcript (up to
  twelve words) else "This is how it looks", laid out by the style's
  `textProps` and drawn by `LayerRenderers.textBitmap`: two stacked frames
  for a word style (`previewReveals`: the first word active, then the
  second, a ticked fill half done in both and a ticked pill at
  `previewGlide` in the second; the dim is not previewed), one for
  Subtitles, over `DS.captionPreviewPlate`. `sampleWordsCache` stores the
  ANSWER per clip, a miss included, and the drawn preview is cached under
  `PreviewKey` (style, first job's clip, canvas, and the PREVIEWED looks —
  `dim` always false there) in `previewKey`, so a Vocabulary keystroke or a
  click on Dim reads and draws nothing. `refresh()`'s `defer` runs
  `refreshStyleRow()` — whose first statement is `refreshLooksRow()`, since
  the key reads `looks` — then `refreshDownloadRow()`. `+Jobs` is no longer a pure move: it
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
  Download row** (grid row 1; `cloudRows` is `[3, 4, 5]`; Style, the looks,
  the preview and Replace are rows 7, 8, 9 and 10) shows for an
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
- `SilenceDetector.swift` (+`Walls`, +`Vocabulary`) · `SilenceSheetController.swift` ·
  `SileroVAD.swift` · `MediaSpeech.swift` · `MediaPeaks.swift` — Remove
  Silences and `detect_silence`. The detector has a `Mode`, `voice` (default)
  or `level`, and is PURE and synchronous over `Input.read`'s snapshot so the
  sheet re-detects per control change. Per step, in this ORDER: the gain
  FLOOR — the plan's ENVELOPE alone against the threshold, which is what makes
  a muted, soloed-away, faded or ducked clip quiet in EITHER mode before the
  model is asked, and is not `peak × envelope`, the level test after it — then
  a voice whose source window holds no voice falls back to
  level (its clip named: `Outcome.answers` is one `VoiceAnswer` per scoped
  voice — clip, media, span, judged by level, waiting on a cache, proposed —
  from which the sheet and `detect_silence` name the clip, #107), then a media
  whose speech cache has not landed is
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
  no AVFoundation in it, refusing any rate but 48 kHz. A metered track counts
  only while one of its OWN sounding spans holds the playhead
  (`LevelMeterTrack.mix`; its format family's resolved segments, #65): a sink
  keeps its last buffer across silence.

**Dialogs and windows.**
- `Sheets.swift` (the `makeSheetView` builders every sheet uses) ·
  `ExportSheetController.swift` (+`Options`, +`Resolve`, +`Presets`,
  `ExportPresetsStore.swift`) · `ExportProgressSheetController.swift` ·
  `SpeedSheetController.swift` · `RelinkSheetController.swift` ·
  `GraphicFileSheetController.swift`. A sheet
  captures a project handle and trusts it; every editor action and
  `handleEditorKey` refuse while one is attached. The export card's controls
  are a VALUE (`ExportChoice`); presets store control choices, not resolved
  overrides; `apply(_:)`'s order is load-bearing and documented there; the
  burn-in checkbox rides as a `RecipeOptions`, not an override. The
  footnote's tooltip follows its text: `syncReadout` (`+Resolve`) writes both
  and clears both, because `sheetFootnote` sets a tooltip only for the text
  it is built with and this sheet's text changes after (spec §11 G-33 (a)). The sheet has
  TWO commits, Export… and Add to Queue, one method. `GraphicFileSheetController.swift` is the ONE sheet of File ▸ Rename
  Graphic…, Delete Graphic… and Restore Graphic Version… (spec §11 G-30):
  `GraphicFileAct`, `GraphicFileChoice`, and the model statics a probe
  calls — `choices` (the folder's modules for Rename and Delete; every name
  with a kept text for Restore, a deleted module titled `<name>
  (deleted)`), `isOffered` (what the validator asks on every menu open: the
  last scan for Rename and Delete, `keptNames()` for Restore — it never
  builds `choices`), `opening`, `keptLine`, `canConfirm` and `perform`.
  Every act is ONE call of a body in `ProjectDocument+GraphicFiles.swift`,
  from the button's action only (the bodies end in `rescan()`: never from a
  `.graphicsDidChange` observer); Rename's `apply` is `performGroupedEdit`,
  never `applyEdit`, and the name goes to the body as typed. A refusal is
  the body's sentence verbatim in `messageLabel`, with a beep, and the sheet
  stays up — it writes no sentence, calls no `GraphicStore` writer, builds
  no op and registers no undo; its two guards name the CALL (an empty or
  unchanged name, nothing to list). The pop-up's rows are `NSMenuItem`s
  carrying the name in `representedObject`. `graphics_menu_proof.py`'s ten
  phase-2 mutants each replace one of its lines (or of `+GraphicFiles`' and
  `AppDelegate+GraphicMenu`'s), asserted to occur once.
- `ExportQueueController.swift` · `ExportQueueWindowController.swift` — the
  controller has NO AppKit in it so a probe can drive it; one job at a time on
  the MAIN thread with a fresh `Exporter` each (two concurrent ones deadlock);
  `mediaURLs()` AND the document's compiled graphics (`Job.graphics`)
  captured at ENQUEUE. No MCP mirror: `export` called N times is
  the capability.
- `SettingsInfoButton.swift` — Settings' ⓘ: an image-only `NSButton` whose
  `NSPopover` shows a pane's explanation on hover (0.35 s) or press (SH-5),
  its `infoState` (closed/hover/held) deciding a press and its
  `popoverShouldClose` keeping `.transient` off the icon; owner-filtered
  tracking area.
- `MCPSettingsPane.swift` — Settings' MCP pane, the window's first (issue
  batch B74, spec §11 MC-7): a bare heading (no ⓘ), a visible two-paragraph
  blurb, the helper's path as selectable 12 pt monospace text, Copy MCP
  Command and a status line. The helper URL and the pasteboard are
  parameters (`AgentServer.mcpHelperURL` and `.general` through
  `SettingsWindowController`'s defaults); the line is
  `AgentServer.mcpCommand(helperPath:)`, never spelled here. `sync()`
  enables the button exactly while the helper is executable, and says
  `missingStatus` when it is not; a press writes the line and says
  `copiedStatus` until the next `sync()`. Not an edit, so no MCP mirror.
- `SettingsWindowController.swift` — Reelcut ▸ Settings… ⌘,, the app's one
  window for something PERSISTED beyond view state, with
  `extension AppDelegate { showSettings }` at its foot
  (`CaptionImporter.swift`'s command-at-the-foot precedent, which is why
  `AppDelegate.swift` is untouched). `ExportQueueWindowController`'s mould.
  `+Verify` holds the Verify bookkeeping (pure move, #58).
  Three panes as `content`'s arranged subviews, MCP (`mcpPane`,
  `MCPSettingsPane`, spec §11 MC-7), Assistant (`AssistantSettingsPane`)
  then Transcription (`transcriptionPane`), 24 pt apart; the Assistant and
  Transcription panes open with `settingsSectionHeader` (a heading and a
  `SettingsInfoButton` holding its explanation, spec §11 SH-5), the MCP
  pane with its bare heading. Two defaulted parameters build the MCP pane,
  `mcpHelper:` (`AgentServer.mcpHelperURL`; the harness passes a fixed
  absent path) and `pasteboard:` (`.general`; the probe passes a private
  one); `show()` syncs it, and `initialFirstResponder` is the Assistant key
  field so the selectable path never opens selected. A later section is one
  more pane in `buildContent`'s list. The key goes in through an `NSSecureTextField` and NEVER comes
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
  **No key set is not an error** anywhere in it. The Assistant pane,
  `AssistantSettingsPane.swift` (road map 12 A2), is `content`'s second pane
  and synced in `show()`; the
  window takes its store as a second FACTORY, `assistantStore:`
  (`AssistantConfiguration.store()` by default, a `MemoryStore` in the
  harness). It mirrors the Transcription pane's key rules (secure field,
  fixed mask in the placeholder, Save empties the field) with no Verify and
  no account link (AI-1), holds the model (blank is AI-11's default), and is
  the ONE poster of `AssistantConfiguration.didChangeNotification` —
  `key` on Save and Remove, `model` only when `AssistantConfiguration.model`
  actually changes, and `settings` only when `AssistantChatSettings` actually
  changes (the compaction box, its threshold field, the clearing box; applied
  at once, no Save; a threshold outside the range beeps and shows the stored
  value again; the field is never written while it is being edited, AI-20).
  Road map 13 P4 (spec §11 P-7) ends the pane with the
  UTC month's spend (`spendLabel`, `settings.assistant.spend`) and its note
  (`spendNoteLabel`, `settings.assistant.spendnote`); the spend folder is a
  third FACTORY, `spendFolder:` (`AssistantSpend.folder()` by default, an
  absent folder in the harness, whose `pinDefaults` wipes `-RCSpendFolder`).
  `init` and `sync()` never read the ledger: `show()` calls
  `refreshSpend()`, and the pane's observer of
  `AssistantSpend.didRecordNotification` calls `refreshSpend(keepShown:
  true)` only while its window is visible, keeping a shown summary until
  the fold answers. No folder and an absent ledger answer synchronously;
  a generation counter shows only the latest read. The window is
  wiring-only for it (#58).
- `PreviewWindowController.swift` — a second `AVPlayerLayer` on the same
  player (measured: two layers both display). It is an **`NSPanel`** (a titled
  window becomes main and every editor selector goes dead), the controller is
  its DELEGATE for `windowWillReturnUndoManager` alone (`NSWindow` implements
  `undo:` itself and mints its own empty manager on the first unanswered
  ask, so the delegate goes on before anything asks), `hidesOnDeactivate` is
  set false, and it is retained by one stored property on the editor, NOT
  `addWindowController`, which would silence the save prompt on close. It
  forwards bare keys to `handleEditorKey`, the one key map.
- `RecorderPanelController.swift` (+`Rows`, +`Recording`, +`Grants`,
  +`Pause`, +`Landing`, +`Picker`, +`VoiceOver`) · `RecorderStatusItem.swift`
  — File ▸ New
  Recording… A `.floating`, `.nonactivatingPanel` with `hidesOnDeactivate`
  false, ONE instance, no window delegate. `show()` makes it key only when
  Reelcut is active; from the background it is ordered front without key, so
  the person's Return stays in the app in front (spec §11 recording.md, #137).
  **The panel is the only place the
  two grants are requested, and the only place System Settings is opened
  for them** (`+Grants`, through `RecorderPanelController.grantDoors`, which
  a probe seals), both before the countdown; it orders OUT at
  `recordingDidStart` for every source but Microphone Only and comes back
  only with a note. The
  status item is the recording's chrome (Pause / Resume / Stop). File ▸
  Pause/Resume Recording (`AppDelegate+Recording.swift`) is a second door to
  the same two calls. **A voice-over** (the Source row "Microphone Only",
  session-only, `+VoiceOver`) never reads or asks the Screen Recording
  grant, greys System Audio, Show Clicks and Size with their values kept,
  refuses Microphone Off by a note, and keeps the panel UP: rows locked,
  meter live, Record reading Stop, a Pause/Resume button beside it.

**Recording.**
- `RecordingSetup.swift` · `RecordingResult.swift` — the half a probe can
  call: choices, file naming, `RecordingConfiguration.make` (PURE), the grant
  reads, the step a press takes, the two pane URLs, the result types;
  nothing here prompts or opens.
- `ScreenRecorder.swift` (+`Pause`, +`Delegates`, +`Microphone`,
  +`Finishing`, +`Content`, +`VoiceOver`, +`VoiceOverFinishing`) — the machine `idle → arming → recording ⇄ paused
  → finishing → idle`. **The microphone is a SECOND FILE** through an
  `AVCaptureSession`, because `SCRecordingOutput` folds it inseparably into
  the system track; its offset is measured per SEGMENT. **A pause is a
  sequence of files over one stream**: the recording output is removed and a
  fresh one added while the stream keeps capturing. Every framework callback
  is stamped where it lands and hopped to main; each finds ITS segment by
  the output's identity. `onFinish` on the session is the one hook; `stop()`
  past idle JOINS the finishing under way; a microphone problem is
  `micProblem` on a success, never the recording's failure. A movie that will
  not probe, or a closed segment whose output reported a failure (#181), is
  LEFT OUT as `RecordingResult.unreadable` with its readable microphone; only
  a recording with no readable movie fails, naming every file on disk — the
  microphone files alone when no movie is. **A voice-over is the same machine
  with no stream** (#99): `voiceSession` instead of `session`, the
  microphone's writer alone, one `.m4a` per segment named `Voice-over <date>
  at <time>`, its own `VoiceOverFileDelegate`; `stop()`, `elapsed`, `pause()`
  and `resume()` forward to it, there is no arming state, and a writer that
  stops on its own — judged by when its report arrived, so a Pause or Stop
  press that reached main first does not hide it — ends it.
- `RecordingLanding.swift` (+`Microphone`, +`Placing`, +`LeftOut`,
  +`VoiceOver`) · `ProjectDocument+Recording.swift`
  — a `RecordingResult` and a document in, an UNSCOPED op list out; nothing
  here commits. Pictures land back to back on ONE track, every `add_clip`
  READ BACK (at an inexact canvas rate a raw add snaps down into a one-tick
  overlap and a minted dissolve); each voice on one Microphone track at its
  picture's start minus its offset, floored at the previous voice's end.
  A left-out segment's readable voice lands in its picture's slot on the
  Microphone track, at offset 0, and the pictures after it start at the
  slot's end (`+LeftOut`, #181). `untitled(around:)`'s order is a contract,
  documented there. A voice-over's files land back to back from the playhead
  on ONE new back Microphone track, kept only when a clip lands on it
  (`+VoiceOver`); as a new project, `untitled(around:)` and
  `remainderPlacement` take it unchanged.

**The agent.**
- `AgentServer.swift` (frozen) and `AgentServer+Project` / `Clips` / `Actions` / `Tracks`
  / `Media` / `Render` / `ExportResult` / `History` / `Silence` / `Captions` / `Audio` /
  `Background` / `Scope` / `Transitions` / `CloudCaptions` / `Recording` /
  `Graphics`
  (+`RecordingArguments`, +`RecordingResult`, +`RecordingChrome` —
  `RecordingToolChrome`, the tool's status item, flipped by the recorder's
  `pauseDidChangeNotification` and frozen at its
  `finishingDidBeginNotification`) — the handlers, one file per group. `+CloudCaptions` is `transcribe`'s CLOUD arm alone — the `engine`
  reader, the three cloud-only arguments refused by name under `apple`, the
  vocabulary's trim/de-dup/cap, the credential and the endpoint read ABOVE
  the network, and the result keys; `+Captions` dispatches on `engine` and is otherwise the code it was.
  `+Actions` is the five action tools (a pure move out of `+Clips`, issue
  batch B87 phase 2); `set_action_end` fills `schema` from the CURRENT
  revision of the module its clip — found in the call's scope — is drawn
  by, only when the patch names `graphic`, and sends none for any other
  clip or a module missing or not compiling, so the core answers (spec §11
  G-34). `+Graphics` holds the two graphic op tools and
  the three app-state ones — `write_graphic` (the store's one writer, then a
  synchronous `rescan()` so the reply is the compile of THAT text; a failed
  compile is `ok: false`, not an error; not undoable, never dirty, G-3; its replaced text kept, G-29),
  `get_graphic` (one module — a compiled one's `diagnostics` are its
  top-level warnings — or the folder with `folder_exists`, the engine's
  `families`, the `assets` and the scan's `warnings`, G-24) and
  `graphic_reference` (the bundled `GraphicsAPI.md`; it calls `target(a)` only
  when given a non-null `project`, so it answers with no project open and
  refuses a path no open project is at, G-20 (e)) — and `graphicsSummary`,
  `get_project`'s `graphics`. `+GraphicRender` is `render_graphic`, an
  `offMainTools` member: one `onMain` for the target, the registry's
  compiled module, the canvas and `meta`; then, off main, the ctx built by
  hand (`recipe_graphic.rs`'s keys) and a contact sheet or one frame's SVG;
  `format` is read first, and svg refuses a non-null `path`, `background` or
  `max_width` by name (G-19 (a)); a frame past `durationInFrames` is drawn,
  `progress` clamped at 1 (G-19 (b)); a png sheet past
  `GraphicContactSheet.maxCellPixels` (`2 × maxSide²`, 134,217,728 px of
  frames) is refused before any frame is drawn or file written (G-20 (d));
  a failing frame is its error card, drawn by
  `LayerRenderers.paintErrorCard`, the one card painter.
  `+GraphicImports` is `import_graphic_font` / `import_graphic_asset`, on
  main, thin: they call `GraphicStore+Import.swift`'s `importFont(from:)` /
  `importAsset(from:as:)` — the ONE body File ▸ Add Font/Image to Graphics…
  also runs (the copy via `ensureFolder()`, G-14, `.partial` moved into
  place, then `rescan()`), and the store's own post reaches the registry; a
  font's `families` come from a throwaway
  library holding that file alone. `+GraphicFiles` is `delete_graphic`, `rename_graphic` and
  `restore_graphic` (spec §11 G-27..G-29), on main, thin: each calls its body
  in `ProjectDocument+GraphicFiles.swift` — the body File ▸ Delete Graphic…,
  Rename Graphic… and Restore Graphic Version… call through
  `GraphicFileSheetController` (G-30) — and rethrows a `ReelCoreError` as
  the tool's error; rename's `apply` is `performGroupedEdit(document, "Rename
  Graphic", …)`. `kept` — the module's kept revisions, newest first — is in
  their answers and in `write_graphic`'s and `get_graphic {name}`'s;
  `get_graphic {}` answers `history`. `write_graphic`'s note is `keptNote`;
  `notUndoableNote` stays for the two imports. `GraphicContactSheet.swift` is pure: the
  layout (the scale is over the cells alone, so the sheet is exactly
  `width × height ≤ max_width × maxSide`, `maxSide` being
  `GraphicLibrary.maxSide`), `maxCellPixels`, the painter and
  `GraphicRaster.cgImage()`. `AgentCatalog.swift` (+`Clips`, +`Actions`, +`Audio`, +`Transitions`, +`Files`, +`Captions`, +`Graphics`,
  +`Declarations`)
  — the catalog, spliced in ORDER (`+Actions`' rows are appended to
  `+Clips`' array last) (`recording_probe.py` reads the last eleven
  names). **A tool is built one of two ways**: `tool`, which declares its own
  schema, or `opTool`, which declares PROSE and prints the argument STRUCTURE
  from the core's published table (`Self.opSchemas` over `rc_op_schemas`).
  **Every one of the fifty-nine op tools is `opTool`'s** and carries no
  `"type"`, no `"enum"` and no hand-written required list; `tool`'s remaining
  callers are the thirty APP-STATE tools, which have no op behind them
  and so nothing to read from the table — the eleven of the Projects group,
  `AgentCatalog+Audio.swift`'s two composites and
  `AgentCatalog+Captions.swift`'s three, spliced back at the two points they
  left, the five other file tools, `record_screen` among them, and
  `AgentCatalog+Graphics.swift`'s nine, after its two `opTool` rows.
  `set_text`'s clause for `case`, `words` and `word_style` is
  `AgentServer.textWordsClause` in `AgentCatalog+Captions.swift` (a pure move
  out of `+Clips`), where the three looks' keys are taught. `opTool`
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
  argument only the app can fill: the two graphic ops' `schema` and
  `set_action_end`'s (G-34), read from the module's current revision (G-4),
  which the gate therefore refuses as a stranger. `AgentServer+Parity.swift` is the FIFTH
  part of the startup parity check — the one part that looks INSIDE an op
  tool's schema: its arguments must be the core's own (both directions, the
  envelope's two keys and the declarations list apart), each one must carry a
  description, and a description whose key is no argument is a complaint
  rather than a sentence `opTool` drops in silence. Parts 1 to 3 stay in the
  frozen file with the private dispatch table they read and part 4 in
  `AgentServer+Scope.swift` with the feature it is about; all five assert in
  debug, log `Reelcut: ` in release and start the server either way.
  `AgentServer+Gate.swift` is the CALL-time half of the same contract
  (kpgalligan/reelcut#21): one comparison in `dispatch`, for all eighty-nine
  product tools, of a caller's keys against the schema the tool published, every
  stranger refused by name — the tool, the strangers and the whole of what it
  takes — before the scope or any handler reads a thing. Its map is read once
  from the catalog string `prepareCatalog()` built at launch (spec §11 AI-3),
  which `bindSocket()` then registers. What it cannot see is a
  declared argument no handler reads, which is the optional half of
  `op_argument_proof.py`'s section 3. `target(_:)` resolves the implicit
  document through `NSApp.orderedDocuments`, never `documents.first`, and an
  explicit path through `AgentServer.canonical`. `offMainTools` names the
  handlers that wait for something the main thread must deliver
  (`import_media`, `transcribe`, `record_screen`, `export`,
  `render_graphic`, `open_project`, …); the criterion
  is "waits on main" or, for `open_project`, "must not hold main for a
  read" (spec §11 #231), not "touches the disk". `open_project`'s two
  main-thread steps also wait, up to `AgentServer.personOpenWait` (30 s)
  each, for a person's open of the same path that is still in flight, and
  then answer `already_open` or refuse by name; `refuseHeldPath` refuses a
  path being opened (spec §11 #234).
- `AgentServer+Socket.swift` — the agent server's Unix socket, its only
  listener since road map 14's MC4 deleted TCP (MC2, spec §11 MC-1, MC-2,
  MC-6). `socketPlan` is pure: a non-empty `RC_AGENT_SOCKET`, else
  `AppSupport`'s `Agent/agent.sock`. `bindSocket` (the first statement of
  `applicationDidFinishLaunching`) runs `socketRefusal` — the folder made
  through `AppSupport.ensureDirectory`, then a real folder this user owns
  with no group or world bits; a socket at the path that ACCEPTS is left
  alone, one that REFUSES is unlinked, anything else is left alone — then
  `ReelAgentSocket.start` with the prepared catalog and the frozen file's
  `agentToolTrampoline`, and sets `boundSocketPath` (`isRunning` reads it)
  after a bind. It never alerts: one log line, `Reelcut agent socket
  listening at <path>` or `Reelcut agent socket not bound: <reason>`, never
  the `Reelcut: ` prefix. `unbindSocket` (all of `applicationWillTerminate`)
  releases with no join. `mcpHelperURL` is this bundle's own
  `Contents/Helpers/reelcut-mcp` and `mcpCommand(helperPath:)` the
  `claude mcp add --scope user reelcut -- '<path>'` line Settings' MCP
  pane copies (spec §11 MC-7; each `'` written `'\''`). The mode check, the connect,
  the listening line and `mcpHelperURL` are each one statement that
  `agent_socket_proof.py`'s mutants replace.
- `AgentCatalogSnapshot.swift` — the build's catalog snapshot (road map
  14's MC3, spec §11 MC-4): with `-RCWriteCatalog <path>`, read from the
  ARGUMENT domain only, the launch writes `{"version":…,"tools":…}` — the
  bundle's short version and `AgentServer.shared.preparedCatalog` verbatim —
  atomically to `<path>` and exits before `NSApplicationMain`; a nil catalog
  or a failed write is one stderr line, `reelcut catalog snapshot: …`, and
  exit 1. `project.yml`'s "Write Agent Catalog" phase runs the just-built
  binary (ad-hoc signed in place first) this way to put
  `Contents/Resources/agent-catalog.json` in the bundle, which `reelcut-mcp`
  lists from while no Reelcut runs; `dist_check.py` D21–D24 check it.
- `AgentLane.swift` — every tool call's one door (road map 12 A1, spec §11
  AI-2, AI-3, AI-5, AI-12): the MCP trampoline's `serve` (server thread,
  synchronous) and the assistant session's `submit` (returns at once; one
  completion, on its document's serial queue — one per document with a call
  outstanding, so a pending question holds only its own window, #148). One
  `NSLock` admits one call at a time, which is what keeps `callScope` and
  `callDocument` race-free; it is
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
  `submit` calls need it. `submit` takes a per-call `AgentCallCancel`
  (`cancel:`, nil by default; spec §11 AI-16). A call whose token is cancelled
  when it takes the lock answers `AssistantSession.cancelledResult` and never
  runs. While a submitted call runs, `callCancel` is its token (nil in
  `serve`; written only in `answer`, under the lock, and cleared before the
  unlock); `export` links it to `Exporter.cancel()` and the on-device
  `transcribe` to its `Transcriber.CancelToken`, each through `onCancel`.
  `AgentCallCancel` is NSLock-guarded: `cancel()` is main only and idempotent,
  and runs each handler once, outside the lock; `onCancel` on a token already
  cancelled runs the handler at once, on the caller's thread.
- `AssistantToolTable.swift` — spec §11 AI-7's ONE table: withheld
  (`record_screen`; `close_project`; `transcribe` only with
  `engine: "assemblyai"`; every dev tool, from `AgentServer.devToolNames`) and ask-first (`export`,
  `export_captions`, `save_project`, `consolidate_media`), a reason on every
  row; the refusal sentence, the question (main only: the path the call
  writes, tilde-expanded, and whether a file is already there — "REPLACES")
  and the assistant's catalog, which drops only an unconditional withheld row.
- `AssistantSession.swift` · `AssistantHelperInput.swift` — one window's
  assistant conversation (road map
  12 A1, spec §11 AI-1, AI-4, AI-5, AI-7), a port of Rasterize's
  `AssistantHelperSession`. `open(document:)` refuses, in order and each in
  its own sentence, a bad `RC_ASSISTANT_BASE_URL`, no key, a catalog not
  prepared at launch (it READS `AgentServer.preparedCatalog` and never
  prepares — AI-3 stays a trap that can fail), and no bundled helper; the
  helper gets exactly `HOME`, `TMPDIR` and `PATH=/usr/bin:/bin`, and the key
  only in the first stdin line, `configure`. Main only; every write goes
  through the one serial `writeQueue` (`HelperInput`, in
  `AssistantHelperInput.swift`, a pure move out of this file (issue batch
  B15), so a write after the close is nothing), `F_SETNOSIGPIPE` on the write
  end. Tool requests run ONE
  at a time through `AgentLane.submit` (never `execute`), results spliced
  verbatim. `send` writes the person's text behind the window's live
  context, `AssistantPrompt.message(text, document:)` (AI-15; the
  transcript keeps the bare text), and sets busy BEFORE its write, so the
  phase reads `busy` the moment it returns true; `turn_started` does not clear
  `cancelRequested`. `updateSettings(_:)` writes `{type: "settings"}` to the
  helper (AI-20); it does nothing once closed, and it ends nothing.
  **Every question is answered exactly once** — Allow/Deny, Stop, `close`,
  the helper's exit, `deinit`, and a hop that reaches a closed, cancelling or
  released session (the `askFirst` closure is `[weak self]` and REPLIES when
  `self` is nil) — because an unanswered one holds its window's queue on the
  lane. `events` is append-only and never holds a `tool_request` or
  the key. `configure` merges `AssistantSpend.configureFields()` (road map
  13 P2) — the one line that changed. Stop also cancels the running call's
  token (`runningCall`, AI-16), so a running `export` or on-device
  `transcribe` stops.
- `AssistantSpend.swift` — what the assistant's responses cost, on the app's
  side (road map 13 P2, spec §11 P-4, P-5). `folder()` is P-5's whole
  decision: `-RCSpendFolder` (the argument domain alone, through
  `AssemblyAIConfiguration.argument`); else `RC_ASSISTANT_BASE_URL` set →
  none; else the one `AppSupport.directory` line. `configureFields()` gives
  `price_cache` (the folder's `anthropic-prices.json`; with the override set
  only beside `-RCPriceFeed`) and `price_feed`. `ledgerLine` turns a `cost`
  event into `spend.jsonl`'s line — `time`, `service`, `model`, a
  whitelisted `usage`, `dollars`, `unknown`, `rows`, `prices`, and
  `partial: true` for a response cut short (spec §11 P-8, `isPartial`: a JSON true
  only), nothing else —
  and `record` creates the folder (`AppSupport.ensureDirectory`, `0700`) and
  appends it with one `write`
  (`O_APPEND|O_CREAT`, 0600), answering a failure sentence. `toolView` is a
  `cost` as a dev tool may show it: `{type, cost: {kind, dollars|cause},
  prices}`, plus `partial: true` for one cut short. `AssistantTurnCost` sums a
  turn's dollars and formats the
  transcript line (`$%.4f`, `under $0.0001`, `unknown (…)`, the table's
  `day` in the local zone) and, summed over a conversation, the tab's Spend
  `figure` ("Nothing yet", "at least …", "unknown …", never $0) with its
  `figureTooltip`. A partial `cost` makes the turn line `Cost: at least $… (a
  response was cut short) · …` and the figure `at least $… · Reelcut's
  estimate` (`lowerBound`), unless a response was unknown, which keeps today's
  words. Road map 13 P4: `record` posts `didRecordNotification`
  (object nil) exactly when it wrote a line; `number` (a JSON number, not a
  boolean) and `instant` (ISO 8601, whole or fractional seconds) are
  internal for the month's fold. **No pricing arithmetic**: the helper
  priced it.
- `AssistantSpendMonth.swift` — Settings' month line (road map 13 P4, spec
  §11 P-4, P-7): `month(containing:)` and `title` ("September 2026 (UTC)")
  in `zone`, `TimeZone.gmt`, spelled once — the ledger's `time` and P-6's
  budget month are UTC, so app and proofs count one month; `fold`, pure, over
  `spend.jsonl` (another `service` skipped; no parse or no readable `time` is
  `unreadable`; a `dollars` that is not a finite non-negative number is
  `unpriced`, never $0); `read`, the fold on `queue` (serial) with the answer
  on main; `amount` (`$%.2f`, `under $0.01`) and `sentence`, the pane's
  words for each `Reading`. It only sums the helper's dollars.
  `spend_ui_proof.py --mutant local-month|unknown-as-zero` edits its
  `TimeZone.gmt` and `summary.unpriced += 1`, each exactly once.
- `AssistantConfiguration.swift` — the assistant's key (spec §11 AI-8), base
  URL (AI-13), model (AI-11) and chat settings. `store()` is AI-13's whole
  decision: `-RCSecretFolder` (read through
  `AssemblyAIConfiguration.argument`, the argument domain alone) → a
  `FileStore` named `anthropic-key`; else `RC_ASSISTANT_BASE_URL` set → an
  EMPTY `MemoryStore`; else the one `AppSupport.directory` line. The store
  first, `ANTHROPIC_API_KEY` second. `model()` is `ReelcutAssistantModel`,
  else `claude-opus-5-5`; no tool reads or writes it. `didChangeNotification`
  (`userInfo[changeKey]` "key", "model" or "settings") is posted by Settings'
  Assistant pane alone. `AssistantChatSettings` is the person's chat settings
  (spec §11 AI-20): `ReelcutAssistantAutoCompact` (absent = on),
  `ReelcutAssistantAutoCompactTokens` (a whole number in 20 000–900 000;
  absent or outside = `defaultCompactTokens`, 300 000, the one such constant,
  AI-9) and `ReelcutAssistantClearToolResults` (absent = off), with `load`,
  `save` and `helperJSON` (null tokens when off); no tool reads or writes
  them. `settingsJSON()` sends `AssistantChatSettings.load(from:)`'s
  `helperJSON` (read there exactly once). In a dev build,
  `-RCDevAssistantAutoCompact <tokens>` from the argument domain replaces the
  threshold, even with compaction off (AI-18 as amended).
- `AssistantPrompt.swift` — the core tools loaded up front (`get_project`,
  `render_frame`, `undo`, `redo`; the lane probe's L6 holds each to the
  assistant's catalog), the system prompt, the search guide, the compaction
  instructions, `searchTopics`, `sharedIdKinds` and `message(_:document:)`
  (road map 12 A3). **The drift rule: every fact in a text is INTERPOLATED
  from the code that decides it or CHECKED against it by `make test`** —
  never "remember to update the prompt". The texts are Swift literals, not
  bundled files, so they can interpolate `ReelTime.perSecond`,
  `AssistantToolTable.rows` (the ask-first and conditional withheld rows)
  and `AssistantLiveContext.tag`, and `assistant_prompt_proof.py --probe`
  (rows F1–F8, in `make test`; F7 also holds `"none"`/`"null"` in double
  quotes and the no-scope word to the block's, F8 each ask-first row's reason
  to a write) fails the build's tests when a backticked
  token is not a tool, an argument or a `get_project` key, a withheld tool
  is named, an id kind or the timescale is wrong, `searchTopics` does not
  cover the assistant's catalog but the core tools exactly once, a text
  holds a blank line (the helper joins system and guide with one) or passes
  its length bound. Backticks hold identifiers only; literals go in double
  quotes; no menu path is written by hand. A new tool needs a topic here or
  F4 fails.
- `AssistantLiveContext.swift` — the `<reelcut_context>` block each person
  message carries (spec §11 AI-15): the project's name and path, the open
  nest, the playhead in ticks and seconds, the selection ascending, each
  label a key of `get_project`'s answer; `init(document:)` is main only. The
  system prompt names it by `tag`; F7 holds its text to the template.
- `AgentServer+DevTools.swift` — the dev tools' seam (road map 11, spec
  §11 V-1/V-2): the handler table, catalog rows and off-main set compiled
  only under `REELCUT_DEV_TOOLS`, which Debug and Release set and
  Distribution does not. The frozen file merges them (`withDevHandlers`, a
  union) and `catalogJSON()` splices the rows in BEFORE the file tools. It
  holds `devToolsMarker`, the string `tools/proof/dist_check.py` requires in
  Release's binary and absent from Distribution's, and absent from each
  bundle's assistant helper (D12, D13); a tool NAME cannot be the
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
  submenu, `framework`, `modal` or unclassified, and one whose own target does
  not answer its action. It answers after a settle:
  reads 20 ms apart, answered on 5 equal, bounded at 3 s. The answer's
  `sheet_at_return` says whether a sheet was attached when the action
  returned, read in the perform's own hop. `cancel_sheet` closes an attached
  sheet through its own Cancel, and refuses a file panel with no parent window
  in its own words (unreachable as far as known). Both run off main
  (`devOffMainTools`), and every AppKit touch is an `onMain` hop.
- `UIMenu.swift` — the menu tool's main-thread half. It walks the menu's
  leaves and looks up a path, validating each level first because a
  validator may retitle an item. It holds the refusal, an ALLOW table where
  a selector with no row is `unclassified`, and the responder walk and
  validation, which never write `isEnabled`. An item's explicit target counts
  only when it answers the action; otherwise the item has no target and is
  disabled, as AppKit greys it, with no fallback to the chain (#133,
  `v2_menu.py` H5). It performs through
  `ProjectDocument.inUndoGroupIfRegistered`: an item's edits are one step
  (M3); an item that registers nothing leaves undo and redo untouched (#167,
  `v2_menu.py` U2); an `NSText` target keeps the eager group except for
  `copy:` and `selectAll:`, which change no text (#176, `v2_menu.py` U3); a
  target whose own `undoManager` is not the document's — the Assistant
  composer, and every field editor, which answers its own
  `NSCellUndoManager` — gets no eager group, and on a `ProjectDocument` runs
  in `inUndoGroupIfRegistered`, so its Cut and Paste leave no empty step and a
  document edit it commits is one step (#184, `menu_undo_probe.py` M1, M2, V1,
  F1).
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
  `snapshot_ui` refuses `appearance` and names this default instead.
- `AgentServer+Assistant.swift` — `assistant_send` and `assistant_answer`
  (road map 12 A1, dev only, wholly under the flag). Both run off main
  (`devOffMainTools`): one `onMain` resolves the target, the editor and the
  session and sends, answers or stops; then the wait for "not busy" runs
  INSIDE `AgentLane.releasingLock`, polling the phase every 50 ms, because
  the turn's own calls need the lock. The target is resolved BEFORE the
  release, never inside it, where an assistant call may hold
  `callDocument`. `assistant_answer` never opens a session. The answer is
  the state, the question, the text deltas joined and the other events since
  the call — never the key or the model, each `cost` passed through
  `AssistantSpend.toolView` (road map 13 P2). `assistant_send` without `pane`
  sends through `EditorViewController.assistantSend`, so the transcript gets
  the person's line; with `pane` (road map 12 A2) both tools go through the
  Assistant tab's own controls — the composer (its `string` set, any marked
  text committed first) and a `performClick` on Send,
  Allow's or Deny's `mouseDown` with a synthesized click at its centre, Send
  while it reads Stop — refused by name, changing nothing, when the control
  is not in a window or is hidden. The pane check comes before the session
  opens, and the idle check before the click, so a pane send never clicks
  Stop. `stop_after` (seconds, 0.1…600 and less than `timeout`; on
  `assistant_answer` only with `allow`) presses Stop once inside the wait,
  through `editor.assistantStop()`, when the turn is still busy or asking, and
  the answer carries `stopped_ms` (else null).
- `DevAssistantLaunch.swift` — `-RCDevAssistantSend <text>
  -RCDevAssistantReport <path>`, a dev-only launch default (road map 12 A1),
  both from the argument domain alone: after launch, one turn in an untitled
  project with or without the MCP server, a `get_project` through the lane,
  one atomic JSON report (its events' `cost`s through
  `AssistantSpend.toolView`, road map 13 P2), and the session closed. One key
  alone is one stderr line. Installed from `main.swift` after `DevAppearance.apply()`.
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
  outside_superview, measured on the view's ALIGNMENT rect
  (`alignmentRect(forFrame:)`), so a label pinned flush is clean, except under
  an `NSClipView` or at zero area (the frame's); truncated,
  except when wrapping. Problems on `_NS…` views go to `private_problems`. A
  secure field's text is never written, nor a field editor's; an ordinary text
  view's text is. Each view's record carries its `tooltip` too (first 200
  characters, `null` for none and always for a secure field). A view that `is UISnapshotParts` adds one `UISnapshotPart`
  record per part it names (id, text, rect), after its own record and before
  its subviews, never a problem (the Assistant tab's transcript, spec §11
  AI-17). It is pure over an `NSView` tree, so
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
`Controls.swift`'s `BlockSlider` is the timeline's zoom slider. Four known
divergences, each recorded: `makeButtonRow` gives its `leading` views
compression resistance `.defaultLow`, so a footnote gives way before a button
(#141); `OptionFieldControl.finishEditing` returns first
responder to `window.contentView` (#60) where Rasterize's copy keeps
`makeFirstResponder(nil)`; every `updateTrackingAreas` in `Controls.swift` and
`OptionControls.swift` removes only the view's own areas (`area.owner ===
self`), where Rasterize's removes them all and the tooltip with them (spec §11
SH-4; kpgalligan/rasterize#335); and
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
undo step; any off-event path goes through
`ProjectDocument.performGroupedEdit`. It opens its explicit group only for an
`.applied` answer (`commitEdit`, shared with `applyEdit`), so an identity, a
refusal or an error leaves the stack — redo included — untouched (#59).
`endLiveEdit(_:cancelled: true)` is the cancel path (Esc during a canvas
drag, `PreviewCanvasView.onLiveCancel`): it puts the `beginLiveEdit` snapshot
back and registers nothing, with no change count.
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
Media tab's search and sort, the Assistant tab (view state; the dev tool
`select_inspector_tab` shows it in a Release build, and the assistant's own
calls already are tool calls) and Settings' Assistant pane (the key, the model
and the chat settings are the person's, spec §11 AI-8, AI-11, AI-20) and
Settings' MCP pane (copies a line, edits nothing, MC-7) get no
mirror, because they edit no project and `set_selection` / `export` already are the capability.
Opening System Settings at a grant's pane (the recorder panel) is no edit
and gets no mirror; `record_screen` refuses by name instead (spec §11
recording).

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
`NSLock`, the cache ledger's `NSCondition`, the prefetch's `NSCondition`, or
a main hop. `DispatchQueue`
only at the documented seams: the
compositor's render queue, the composition rebuild, import, the export
progress timer, `Transcriber`'s serial queue, `CloudTranscriber`'s serial
queue and the AssemblyAI client's delegate `OperationQueue` (spec §11's
R6-7), the transcribe sheet's Download row's KVO main hop
(`DispatchQueue.main.async` from `Progress`'s `fractionCompleted`
observation), `FFmpegRewrap`'s serial queue, the container rewrap's per-input writer
queues (`ContainerRewrapWriter.swift`), the two one-frame render
queues (`eyedropperQueue`, `frameGrabQueue` — a third one-frame render joins
this entry rather than growing the list), `ScreenRecorder.shareableContent`'s
global hop, `GraphicStore`'s serial queue (its file-system sources'
handlers, the coalesced pass and the outbox; main publishes through
`drain()` and never waits on it but by `queue.sync`), the cache's main
hop, the alert queue's main hop (`ProjectDocument+Alerts.swift`), the agent lane's per-document serial queues (`AgentLane.swift`), the
assistant session's write queue (`AssistantSession.swift`), the alpha rows'
straightening and the 8-bit rounding (`ExportStraightAlpha.swift`,
`ExportStraightAlphaHalf.swift`, `DispatchQueue.concurrentPerform` over rows,
inside the video pump), and the spend-month
queue (`AssistantSpendMonth.queue`, Settings' ledger fold, answered by a
main hop), and — not a queue but a seam all the same — the graphic
prefetch's worker `Thread`s (`GraphicPrefetch.swift`, G-26). The recorder adds
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
prove a build with `make app-debug`, and Release with `make app` at the gate.

**Debug and Release.** The loop and mutant tiers build and drive a Debug app
(spec §11 V-4, V-5); the gate builds Release and the run a phase records is on
Release. (a) The 18 `assert`/`assertionFailure` sites are live in Debug: a trap
is a defect to fix, never an assert to delete or a reason to switch
configuration. (b) Debug is unoptimised: a proof that measures time or
throughput is `release_only`, as is one that needs a TCC grant. (c) A failure
only Release shows is found by the recorded run and fixed in that phase.
