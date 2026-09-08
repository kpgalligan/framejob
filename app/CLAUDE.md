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
- `LayerRenderers.swift` — text and shape descriptions to textures, and
  since format version 5 the three text REVEALS (spec §5.2's
  `text.animation`). It draws what the recipe's `reveal` / `reveal_phase` /
  `reveal_kind` say and computes nothing: the core owns the number
  (`recipe.rs`), and the layer's `hash` already covers it, so
  `RecipeSourceRef.cacheHash` stays the WHOLE texture key and nothing here
  may append to it. Two rules hold the drawing together: the LAYOUT is
  always the full text's, cached in `layoutCache` beside `sizeCache` and
  keyed WITHOUT the reveal, so an animation can never reflow the box or
  walk the overlay's handles; and `reveal = 1` (or no animation) takes the
  original single `CTFrameDraw` path rather than the span machinery, which
  is what makes a full reveal byte-identical to no animation at all.
  `wordOverlap` (0.5) and `lineRiseFraction` (0.35) are named constants,
  not schema — whatever is chosen there ships as the animation's identity.
  **And a third, which the review put there: a line drawn at a PARTIAL
  alpha goes inside a transparency layer.** An outlined glyph is filled and
  THEN stroked — `attributedString` sets a negative `.strokeWidth`, Core
  Text's spelling of "fill and stroke" — and `CGContext.setAlpha` applies
  to each of those draws separately, so the inner half of the stroke lands
  on ink the fill already laid down and composites twice: at reveal 0.5 the
  outline sat at 0.75, and a black outline on a white word read as a grey
  halo for the whole ramp. A transparency layer makes the two draws one
  composite, which is what the shader had always given a texture faded
  WHOLE. An opaque line skips it — at alpha 1 the stroke covers the fill
  exactly as it does in the finished glyph, and the buffer would buy a
  rounding step and an allocation. Anything else here that draws one piece
  of a glyph at a time inherits the rule.
- `Playback.swift` · `CompositionBuilder.swift` · `Compositor.swift` ·
  `CompositorEffects.swift` · `MediaImporter.swift` ·
  `Exporter.swift` · `ExporterLoudness.swift` · `ExporterWriter.swift` ·
  `ExporterImageSequence.swift` —
  the AVFoundation/Metal side; see spec §7.5–7.8. Two phase-5 facts about
  the last four: an export is TWO passes wherever the file holds sound —
  a measurement build of its own (a mix copy would share the tap, and a tap
  carries per-instance state), reading 32-bit FLOAT so a mix over full scale
  is measured honestly, then the ordinary write with the gain applied to the
  decoded Int16 samples. `ExporterLoudness.swift` IS that first pass, a pure
  move out of `Exporter.swift` when the second one took it past the ~600-line
  cap, which is why `Exporter`'s `lock`, `measureReader`, `scratchStorage`,
  `scratchCapacity` and its two accessors are internal rather than private —
  stored properties cannot live in an extension. And
  `CompositionBuilder.build`'s `metering` flag
  is passed true by `Playback.startRebuild` and by nothing else, so an
  export and a rendered frame build exactly the audio path they built before
  the level meter existed. `CompositorEffects.swift`
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
- `MediaConsolidator.swift`
  with `EditorViewController+Consolidate.swift` (File ▸ Consolidate Media…) —
  the §5.6 file feature. Consolidate writes inside the package behind
  NSDocument's back, so it MUST tell
  `ProjectDocument.packageContentsDidChangeOnDisk()` afterwards, or every
  later save is refused as "changed by another application".
- **Captions**, four files and one shape: a caption is an ordinary text
  clip, which is what makes burn-in free, so every producer ends at the
  same placement code.
  `CaptionLayout.swift` is that placement and ONLY placement — snap to the
  frame grid, give a collapsed cue its frame back, sort, trim an
  overlapping cue back to ABUT its successor (never a gap: `b.start ==
  a.end` is not an overlap and mints no transition), drop what is left
  shorter than a frame, and place the survivors on a new front-most track
  in the Caption preset, which is the one placement the overlap rule can
  never refuse. Every refusal keeps the `tag` its producer gave it, so a
  file says `line 12` and a transcript says `clip 7`.
  `CaptionImporter.swift` (File ▸ Import Captions…) is now the SubRip
  grammar and nothing else. **The four cue rules are NOT in either of
  them** — ≤ 2 lines, ≤ 42 characters a line, ≤ 6 s a cue, a frame between
  cues live in `CaptionCues` at the foot of `CaptionLayout.swift`, because
  only a producer that has to INVENT line breaks needs them: an SRT brings
  its own, and moving the rules into the shared path would silently re-wrap
  every caption file that imports correctly today and break 4b's round
  trip.
  `Transcriber.swift` (File ▸ Generate Captions…, `transcribe`) is the
  recogniser: `SFSpeechRecognizer` through its CALLBACK API (spec §11 — no
  second `async` exception), over each clip's source window EXTRACTED to a
  temporary mono 16 kHz WAV in `NSTemporaryDirectory()`, never the media
  file and never inside the package. Two queues, and the second is not
  optional: `SFSpeechRecognizer.queue` defaults to the app's MAIN queue,
  which would make an off-main tool's wait depend on the main runloop being
  free. The framework's roughly one-minute ceiling per task is REPORTED —
  a run that stopped early says where — rather than chunked around.
  Two rules the review put there, and neither is local: **"has sound" is
  `enabled.audio` and not the media's** audio track, because Detach Audio
  leaves the picture clip with the switch off and an audio-only twin over
  the SAME media beside it, so asking the file would transcribe one
  recording twice and place two identical cues at one time; and **one
  job's failure is one job's problem** — an extraction that fails (a file
  whose audio track is shorter than its picture, trimmed into the tail) is
  reported under `problems` and the run carries on, where throwing would
  discard every cue the earlier clips had produced. Cancellation is the
  exception and stays a throw: it means place nothing.
  `TranscribeSheetController.swift` is one sheet in two states (settings,
  then its own progress card, `ConsolidateProgressSheetController`'s shape),
  and is the ONLY place the app calls `requestAuthorization`: the system
  prompt needs a frontmost app, so the tool reads
  `authorizationStatus()` and refuses instead (`Transcriber.canAsk`, which
  is `FFmpegRewrap.canAsk`'s argument). The ORDER of the tool's refusals is
  load-bearing and the review is what put it in that order: the caller's
  own mistakes — an id naming nothing, a scope with nothing audible, a
  language tag the framework has never heard of — are answered FIRST, so
  they stay reachable with no grant; the grant next; and only then whether
  this Mac has a downloaded MODEL for the language, which is a question an
  ungranted Mac cannot be asked and must not be sent to System Settings
  over. That ordering is also the only reason a headless proof can measure
  anything about `transcribe` at all.
  `CaptionExporter.swift` (File ▸ Export Captions…, `export_captions`)
  writes `.srt` and `.vtt` out of one track's text clips; it never guesses
  the track — a candidate is a track whose clips are ALL text, and none or
  several means refuse and NAME them. Its round trip returns every cue to
  the TICK it was written from at every ordinary rate: a timestamp is
  rounded to the nearest millisecond, 300 ticks at most, and half a frame
  is 10,000 ticks even at 30 fps, so the snap on the way back in can only
  find the frame the cue left. What needs a whole-millisecond frame (25 and
  50 fps) is byte identity with the FILE, and then only for a file whose
  times are already on the frame grid — which is why the proof fixture is
  at 25 fps and why the same fixture at 30 fps must NOT come back, rather
  than carrying a tolerance.
  **Pitfall, and it is not the exporter's alone:**
  `NSPopUpButton.addItem(withTitle:)` REMOVES an existing row carrying the
  same title before adding the new one — three rows, two of them reading
  alike, come back as two — so a popup built from model objects must carry
  the object in `representedObject` and be read from `selectedItem`, never
  by `indexOfSelectedItem`. The save panel's track popup did the latter,
  and two caption tracks renamed alike would have exported a DIFFERENT
  track and reported success; `Candidate.menuTitle` now spells the track id
  into the title as well, so nothing is dropped either.
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
  what `importCaptions`, `removeSilences`, `generateCaptions`
  (`TranscribeSheetController.swift`) and `exportCaptions`
  (`CaptionExporter.swift`) are — each of those carries its validator arm
  down there with it, and the arm is load-bearing rather than decoration:
  without one the item falls through to `validateUserInterfaceItem`'s
  closing `return true` and is enabled on a timeline where it can only
  beep.
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
  **Pitfall:** a section factory is not a section until `makeSections()`
  CALLS it. Nothing type-checks the omission — an unused method on a pane
  is legal Swift — so a new group can be written, documented, mirrored over
  MCP and invisible in the app, which has now happened in two consecutive
  phases (`VideoPane.obscureSection`, `TextPane.animationSection`). Adding
  a section is two edits, and the second one is in `ClipPane.swift`.
  **And a second:** an `InspectorSection`'s `UserDefaults` key records
  COLLAPSED, so an untouched section has no stored value and
  `defaultExpanded` applies;
  never flip that polarity or every saved panel inverts. And section ids are
  shared across contexts (`video.speed` is the Speed group for a video clip
  and the first group an audio-only one gets), so a "open the first section"
  rule has to walk until it finds one the user has not stored.
  **And a third:** a field's `refresh` is skipped while its field editor is
  attached, which it still is inside `controlTextDidEndEditing` (after
  Return or Tab AppKit even re-attaches it), so every refresh a commit runs
  is skipped — `InspectorNameField` and the timecode field set their
  `stringValue` directly as the commit ends, or a cleared name would keep
  showing blank while the strip shows the fallback.
  **And a fourth:** `InspectorPaneView`'s low-priority bottom pin is 249,
  one BELOW `.defaultLow`, and the one point is the whole point. An
  `InspectorSection` sets no hugging priority, so it keeps AppKit's default
  250; at 250 the pin tied with it, and "give the pane its content's height"
  and "stretch a section past its rows" cost the solver the same. Auto
  Layout reports nothing for a tie — it just picks, per PROCESS, so the
  offscreen harness wrote two different PNGs for one package and
  `phase3_chrome.py` scored anywhere from 29 to 33 out of 33 on identical
  input. Any constraint here that competes with a subview's own hugging
  needs that gap, and a proof that scores differently run to run is the
  symptom to recognise: a stable-but-different render is an ambiguity, not a
  race, and no amount of waiting will settle it.
- `ExportSheetController.swift` (the export card — six control rows since
  phase 5's Loudness popup, whose −1 dBTP ceiling is FIXED and stated in the
  hint rather than made a seventh — and its progress sheet, which says
  "Measuring loudness…" through pass 1 and reports the measured peak and
  loudness on its last line, normalised or not),
  `SpeedSheetController.swift`, `RelinkSheetController.swift`,
  `TranscribeSheetController.swift` (settings, then its own progress card,
  because a second sheet presented out of the first one's action is
  refused — `ReverseProgressSheetController.viewDidDisappear` records it) —
  the dialogs, all built from `Sheets.swift`'s `makeSheetView` pieces. The
  first three are put up by `EditorViewController+Export.swift`; the
  transcribe sheet puts itself up, from the `generateCaptionsCommand` at
  its own foot, the shape `SilenceSheetController` set. A sheet captures a project
  handle and trusts it, which is safe because every editor action
  validates false while one is attached.
- `AgentCatalog.swift` — the MCP tool catalog; a startup check enforces that
  catalog names match the dispatch registry (it traps in debug and logs in
  Release, because `make app` builds Release). The handlers live in
  `AgentServer+Project/Clips/Tracks/Media/Render/History/Silence/Captions/Audio.swift`
  and their shared
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
  after it; the other TEN `T??` patch fields still have the gap —
  `VideoPatch.shadow` / `chroma` / `reflection` / `spotlight`,
  `AudioPatch.duck` / `compressor`, `TextPatch.outline` / `backdrop` /
  `width` / `animation` — and on the object-valued ones a wrong type
  CLEARS the effect. (`ShapePatch` is not in that count: it is the one
  patch built by hand rather than decoded, so `stroke` and `fill` refuse a
  wrong type by name.)
  A second thing that round trip cannot do, older than phase 3 and
  measured again by its proof: a nested OBJECT in a patch is decoded into
  its typed struct and re-serialised, so an unknown key inside one is
  dropped where the core would have named it, and a known key the caller
  omitted is sent as that struct's DEFAULT — which resets the field. That
  is `shadow`, `chroma`, `duck`, every `obscure` entry and now
  `animation`: the core
  refuses both (`deny_unknown_fields`), the decoder simply gets there
  first, so a patch of a nested object is a REPLACEMENT and has to be sent
  whole. `AgentCatalog`'s text-patch sentence spells that out for
  `animation` in the tool's own words, because a key left out of one comes
  back as a 1 s typewriter rather than as what the clip had.
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
  new enum inside a patch has to be added by hand. `checkTextEnums` is its
  sibling and guards the one a TEXT patch carries, `animation.kind`; both
  are run again per group by `checkActionPatch`, since an action's end
  state carries the same patches. `align` and `valign` are not in either,
  because they are plain strings in the schema rather than Swift enums.
  **A check like these belongs at every DOOR a patch comes through, not at
  the one it was written for.** `add_text_clip` takes the same `set_text`
  patch (a bare string being shorthand for `{"content": …}`) and was the
  one entrance that never ran `checkTextEnums`, so
  `{"animation": {"kind": "fade"}}` reached the core as a typewriter and
  the caller was told the clip they asked for had been made. `textArg` runs
  it now, on the RAW object rather than on the decoded patch, which is the
  only place the misspelling still exists; `add_shape_clip` is the pattern
  beside it. A new composite op that carries a property group inherits the
  same duty.
  `AgentServer.offMainTools` names the few handlers that run on the server
  thread instead of the main one — they wait on the main thread (an async
  probe's completion, NSDocument's save) or on a long decode, so hopping first
  would deadlock or freeze the UI; they reach the document through
  `AgentServer.onMain`. The criterion is "waits for something the main
  thread must deliver", not "touches the disk": `detect_silence` reads a
  few hundred KB of peak files and does one arithmetic pass, and stays
  ON-main for that reason, as `consolidate_media`, `import_captions` and
  `export_captions` do. `transcribe` is the newest member and is the
  criterion read the other way twice over: the Speech framework delivers
  its callbacks on an `OperationQueue` that defaults to the app's MAIN
  one, and a recognition is seconds to minutes of work that must not
  freeze the UI.
- **Sound**, five files road map 2's phase 5 added, all of them arithmetic
  with one view among them.
  `MediaPeaks.swift` is the cached waveform and the ONE way to ask it
  about a source window: the bucket size, the project→source tick mapping
  taken from the plan segment's own resolved rate (never
  `TimelineView.sourceTime`, which multiplies by `clip.speed` and rounds
  the rate a second time), the floor for the bucket index, and the
  reversed MIRROR — a reversed clip's `in` is measured in a stream no
  peaks file exists for, so the window is mirrored about the media's model
  duration. All four were `private static` inside `SilenceDetector` until
  a second caller needed them, and a third copy is the drift the rule
  exists to stop.
  `AudioNormalize.swift` is Normalize Clip as a value type — peaks in, ops
  out, `CaptionLayout`'s shape applied to sound — so the Audio pane's
  button and the `normalize_clip` tool provably do the same thing. It
  measures PRE-FADER (normalise is a statement about the material, where
  `SilenceDetector` asks what the ear hears and multiplies by the
  envelope), takes its window from the PLAN segment (one test —
  "this clip has no audio segment" — correctly refuses no media, missing
  media, no audio track, `enabled.audio` off anywhere, a still and a
  nested clip), REPLACES `volume` rather than multiplying it so a second
  press is a no-op, and always writes BASE props even inside an action.
  `LevelMeter.swift` is the meter's model and `LevelMeterView.swift` its
  one view, subscribed directly to the process-wide `LevelMeter.shared` so
  that neither frozen file gained a stored handle or a fan-out line.
  **The meter reads the DSP tap that already exists and multiplies by the
  plan's envelope**; the road map's second `PostEffects` tap cannot be
  built, because `AVMutableAudioMixInputParameters` has exactly one
  `audioTapProcessor` and the flags are exclusive. Do not "fix" it back.
  Two more rules here: the MODEL publishes a raw measurement and the VIEW
  owns the ballistics (peak hold, fall, clip dwell), which is what lets a
  proof assert on the number without photographing a window; and the view
  has ONE resting appearance and starts no free-running animation, because
  the offscreen harness writes only when two consecutive captures agree.
  `Loudness.swift` is BS.1770-4 and the export gain — plain float buffers
  in, a value type out, no player and no reader, `AudioDSP.swift`'s rule
  applied to measurement, which is what lets the meter be checked against
  synthesized tones with no fixture file. Its coefficients are quoted from
  the recommendation at 48 kHz and it REFUSES any other rate rather than
  filtering with the wrong numbers.
  **`import Synchronization` is confined to `LevelMeter.swift`**, and it is
  an exception of the same class as `async` being confined to
  `MediaImporter.swift` (see Hygiene). `LevelMeterSink.publish` runs inside
  the tap's process callback on AVPlayer's render thread, where nothing may
  lock and nothing may allocate — a lock can block on a lower-priority
  thread that holds it and a `main.async` allocates, and both fail as an
  occasional glitch nobody can reproduce — so the sink is two 64-bit words
  written and read with relaxed atomic stores. Every other cross-thread
  value in `app/Sources` stays an `NSLock` or a main hop.
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
  second Swift copy of `silenced` to drift from the first. Since phase 5c
  the peak arithmetic it used to keep privately is `MediaPeaks.swift`'s and
  it calls it.
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
  `TimelineBar.swift` (the 36 pt bar, its selection block, and — since
  phase 5b — the level meter in the flexible gap left of the zoom cluster,
  where the arithmetic for "no divider before it" is written down),
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
speech recognition landed in phase 4 and did not, because
`SFSpeechRecognizer`'s callback and delegate API is complete for a
transcription, which is what `Transcriber.swift` uses (spec §11);
`DispatchQueue` only at the documented seams
(the compositor's render queue, the composition rebuild, import, the export
progress timer, and — since phase 4 — `Transcriber`'s serial work queue with
the `OperationQueue` the recogniser delivers its callbacks on, which is not
optional: `SFSpeechRecognizer.queue` defaults to the app's MAIN queue).
**`import Synchronization` is allowed only inside `LevelMeter.swift`** — the
same shape of exception, and phase 5's. Its `publish` runs on AVPlayer's
audio render thread inside the tap's process callback, where a lock invites
priority inversion and `main.async` allocates; two relaxed atomic words are
what a wait-free publish costs. Nothing else earns it by asking, and every
other cross-thread value here is an `NSLock` or a main hop.
Colors/fonts/metrics come from `DS` tokens; shared controls
go in `Controls.swift`. Refusals beep (`NSSound.beep()`), errors never
crash. 4-space indent, ~100 columns.
