# Reelcut — app-side file notes (moved out of `app/CLAUDE.md` on 2026-09-17)

This is `app/CLAUDE.md` as it stood on 2026-09-17, moved here verbatim when
that file was cut back to a file map and its rules. It is the long form of
each file's entry: the history of every size toll with its line counts, the
measurements behind each decision, what each review found, and the arguments
a comment in the file usually restates. Grep it when a file's PAST matters;
read `app/CLAUDE.md` for what governs the file now. Its line counts and phase
references are as of the phase that wrote them and are not maintained, and a
file or a function it describes may since have been DELETED — `app/CLAUDE.md`'s
map is the list of files that exist, and this one is not edited to follow it.
Deepening D1 (`designs/reelcut-roadmap-7.md`) took out a whole family at once:
the agent door's hand readers and hand checks — `colorArg`,
`requiredColorArg`, `shapePatchArg`, `gradientArg`, `textArg`, `shapeArg`,
`unitPoint`, `checkClipPatchTypes`, `checkActionPatch`, `checkVideoEnums`,
`checkTextEnums`, the per-group allowed-key sets, and in D1·6 `patchArg`
with its round-trip check, `decodePatch`, `withOpaqueColors`,
`nestedNumberArg` and `ClipPatch`'s lenient `init(from:)` — all of which the
paragraphs below still argue for. `zoomRegionArg` survives as eight lines
that read NOTHING about the region and refuse only an absent one. The rule
that replaced the paragraphs is in `app/CLAUDE.md`: lenient decoding is for
what the core wrote; nothing a caller wrote is decoded through it.

## Archived text — app/CLAUDE.md — Swift app rules

Applies to everything under `app/`. Build/verification commands and the FFI
lockstep are in the root `CLAUDE.md`; the full design is
`designs/reelcut-design.md` (§3–4 the UI, §7.4–7.8 this file map).

## File map

- `ReelCore.swift` · `ReelOps.swift` — the FFI and the op vocabulary, one file
  until road map 2's phase 9 made it pay the ~600-line cap it had been over
  since M2.
  `ReelCore.swift` is still the **only** home for `rc_*` calls: `ReelProject`
  (handle + lazily decoded `ProjectSnapshot`), timecode, snapping, export
  presets, sizes and settings (`ExportPreset`, `ExportSize`,
  `ExportSettings`), `RecipeSource`, and the op ARGUMENTS an edit is built out
  of — `MediaDescriptor`, the `dictionary` extensions on the §5.2 property
  types, and the four typed patches. `deinit` frees the Rust allocation.
  `ReelOps.swift` holds `OpArgs`, `ReelOp` and the typed op builders that
  mirror `core/src/edit.rs`'s op table. There is no untyped op-JSON call site
  anywhere else.
  **The STRUCT went with its factories rather than with the handle**, and
  phase 9 is the argument: it adds a `scope` to an op and folds it into
  `json`, which is one edit to `ReelOp` and to whichever of the fifty-odd
  factories set it, while the handle's half of the same phase is an
  `rc_project_scoped` wrapper — so each file gets exactly one of them, and
  neither half of one edit lands across a boundary. `ReelOp.coreNames()` is
  the ONE member that stayed behind, because it reads `rc_op_names()` and the
  root `CLAUDE.md`'s rule admits no second file; it sits in an
  `extension ReelOp` of its own. Unlike `ExporterLoudness.swift` and
  `ExportSheetOptions.swift` the cut cost NO visibility: `OpArgs` is
  `private`, every one of its users is a factory, so it travelled with them
  and is still `private`.
  **Phase 9 added two members and one list to `ReelOp`**: `scope`, a `var`
  with an initial value so the memberwise init defaults it and all ~55
  factories compiled untouched; `scoped(_:)`, the plain stamp, which the MCP
  handlers use for their own `scope` argument as well; and
  `documentLevelNames`, a MIRROR of `core/src/scope.rs`'s `refused_inside` —
  seven names, checkable by eye. The mirror exists because one edit can
  legitimately mix the two kinds (a Finder drop inside a nest is `add_media`
  on the document plus `add_clip` in the nest, as ONE undo step), so
  `ProjectDocument` sends a document-level op unscoped and everything else
  scoped. It is not a second opinion about what those ops mean: the core
  still refuses a scoped one by name, and an agent that asks for one still
  gets that refusal.
- `ProjectSnapshot.swift` — the `Codable` mirror of the §5.2 project JSON:
  the read-only view every view draws from.
- `MotionProps.swift` — `video.motion`'s vocabulary (format version 8, road
  map 5's E2): `EdgeMotion` and `DuringMotion` with their display names,
  `MotionEdge`, `MotionDuring` and `MotionProps`, decoded leniently like
  every other snapshot type, with the core's own defaults MIRRORED rather
  than derived so switching a slot on writes what the core would have
  defaulted to. Its `dictionary`s live here and not beside every other
  property type's in `ReelCore.swift`, which is over the cap and may not
  take a group's worth of new code. **`MotionProps.dictionary` always
  writes THREE keys, `NSNull` for a nil slot**, and that is load-bearing:
  a raw core patch DEEP-MERGES a motion, so a `MotionProps` holding only an
  `in` sent as `{"in": …}` would leave a stored `out` in place and choosing
  None from a popup would appear to do nothing and beep. Nothing here draws
  anything — the core turns a preset into placement inside the recipe, so
  the inspector and the canvas see the clip UN-MOVED while the picture
  moves, which is why a drag begun mid-motion starts from the base box.
- `VideoPane+Motion.swift` · `EditorViewController+Motion.swift` — the app
  half of `video.motion` (road map 5's E2): the Clip tab's Motion section
  (seven rows and Preview, shut by default, registered LAST in
  `ClipPane.makeSections()`'s effects group) and Clip ▸ Motion ▸ In / Out /
  During with Preview. Both write ONE `set_video` PER CLIP, because a
  motion patch replaces the whole object and each clip keeps its own other
  slots; `structural(video:for:)` puts `motion` on the BASE props even
  inside an action (the core refuses it in `set_action_end`). Preview sets
  the in/out range to the clip and turns Loop on, and both stay.
  **Proved 2026-09-19** by the four instruments road map 5 §4e and §6e owe:
  `tools/proof/e2_proof.py` (61 claims over MCP — every preset's arithmetic
  read off a rendered PNG, the tent, the composition rules, what a split and
  a ripple delete leave behind, and an `apng` export measured frame by
  frame) and `tools/proof/e2_chrome.py` (24 — the timeline's wedges and the
  During glyph measured in points against a card with no motion, the
  section's seven rows with the alpha each control is composited at, the
  three submenus and their checkmarks, and the two commands driven in a real
  window). Two of that pair's rows are what this entry's last two sentences
  claim: `setMotionDuring` with tag −1 leaves the arrival in place, and the
  section's In popup driven with the playhead INSIDE an action writes the
  base motion and leaves the action's `end` with no `motion` in it.
  `tools/proof/e1_proof.py` and `tools/proof/e1_chrome.py` are the same pair
  for E1's transitions.
- `AgentServer+Motion.swift` — **DELETED by road map 7's D1·3 (`eb17289`),
  where `set_video` began forwarding the caller's patch to the core
  unread; `motion` goes over the wire as written and is refused by the
  core's own decoder. The entry below is history, kept because it says what
  the file did and why a later reader may find it named in road map 5.**
  Reading `motion` out of a `set_video` patch
  BY HAND, `gradientArg`'s posture rather than the generic decoder's: a
  misspelt key at every level, a kind outside either vocabulary and a wrong
  type are all refused BY NAME. `patchArg`'s round trip cannot see inside a
  nested object and a motion has two levels of them, so `setVideo` strips
  `"motion"` out of the patch before `patchArg` runs and sets
  `patch.motion` after it — the two readers never see each other's key. The
  two durations go through `optionalTimeArg`, the one spelling of the frame
  snap, which is why the reader takes the targeted document. Ranges are the
  CORE's (`props_check.rs`): this decides the type and the grid, never
  whether a number is legal.
- `ProjectDocument.swift` — NSDocument, `.reelcut` package read/write, and
  the single mutation point (see Undo below). It also holds the FIVE pieces
  of VIEW state every view agrees on and nothing persists: the playhead, the
  clip selection, the in/out range, `selectedMedia` (the Media tab's
  selected row, which Edit ▸ Insert / Overwrite at Playhead place) and
  `nestPath`. All five
  are re-clamped to live ids by `clampViewState`, and `selectedMedia` lives
  here rather than on `MediaPane` because that pane is rebuilt whole
  whenever the media list changes.
  **`nestPath` is phase 9's, and three things about it are load-bearing.**
  It is a PATH rather than the nest id the core's `scope` wants, because a
  nest can be shown by two clips at two different starts — so the id alone
  cannot say where the nest's zero sits (the playhead maps in and out) or
  which clip to re-select on the way back. `scope` is its last step's nest.
  **`editedProject` is a STORED, memoised `rc_project_scoped` handle**, not
  a computed one: `ReelProject` memoises `json`, `snapshot` and `planJSON`
  PER HANDLE, so a fresh handle at each of the ~80 read sites would re-run
  `rc_project_to_json` and a whole snapshot decode at every one. Two reads
  answering the same object is also what `refreshFromDocument`'s
  object-identity guard depends on. And **`clampViewState`'s ORDER is the
  scope first**, then the selection, then `selectedMedia`, then the
  playhead: the selection clamp measures against whatever container the
  scope clamp left, so the two cannot be swapped. `applyEdit` changed by
  exactly one `map` — `addressed(ops)` — and everything else about it,
  including its three outcomes, is what it was; note that the `catch` arm
  now also carries the caps and the depth, which a scoped op can fail on
  where an unscoped one cannot.
  `ProjectDocument+DisplayStem.swift` is the document's title as a file
  STEM — `displayStem`, a trailing `.reelcut` removed and nothing else — an
  `extension ProjectDocument` in its own file because the base file is far
  over the ~600-line cap and should not take on code (comments it may — the
  cache marker's doc rewrite added four lines there); the `FrameWriter`
  row says which three panels read it and what proves it.
- `EditorViewController+NestScope.swift` · `TimelineView+NestScope.swift` —
  going inside a nest and coming back out (road map 2's phase 9, spec §4.4):
  Clip ▸ Open Nest ⌘↓ / Close Nest ⌘↑, the double-click on a nest clip, the
  playhead mapping, `NestScope`'s pure path arithmetic (`clamped`, `offset`,
  `names`, `clips`) and the breadcrumb the ruler draws in the corner over the
  track headers. The frozen `TimelineView.swift` carries two stored
  properties, two closures, one draw call, one hit-test token and one
  gesture case — `TimelineView+Candidates.swift`'s split exactly, and for
  the same reason: `TimelineRulerView.draw` paints the corner LAST, over the
  ticks that would otherwise slide under the header column, so anything in
  that square is drawn from inside that method. `revealPlayhead` widened to
  internal, which the change forces: `setPlayhead` guards on
  `time != playhead` and a scope change can leave the number equal, so the
  auto scroll has to be asked for by name.
  The corner's z-order — the ruler ABOVE the header column, which only
  matters once the pane has scrolled — is photographed SCROLLED by
  `tools/proof/phase9_chrome.py`, the one instrument in the tree that
  renders a scrolled `TimelineView`; a claim about that order is gated by
  its `init-order` mutant (52/62), which no render at scroll 0 can be.
  Three things to know before touching it. **A nest clip loses
  rename-by-double-click** — the open branch sits ABOVE the rename branch in
  `beginGesture`, the ⌥⇧ slip's precedent — keeping ⇧⌘R, Clip ▸ Rename… and
  the Clip tab's header field. **The three MARKER commands are off inside a
  nest**, which is more than polish: a nest has no markers, and the playhead
  in there is measured from the nest's zero, so `add_marker` sent unscoped
  (the way `add_media` is) would write one at the wrong project time.
  `validateNestScopeAction` runs FIRST in the base file's validator chain
  because it is the only arm that overrides another file's answer, and
  `addMarkerCommand` carries its own guard for the bare-M path no validator
  covers. And **the in/out range is cleared on every scope change**
  (`setNestPath`), because a pair of ticks means one thing inside a nest and
  another to an export.
- `TimelineView.swift` · `TimelineSessions.swift` — **the marquee's reach
  (2026-09-19).** `RangeSession` had banded a selection since M1, but a
  band could only START inside a lane: `hit(at:)` answered `.none` for the
  4 pt strip under the ruler and for everything below the last lane, and
  `beginGesture` swallows `.none` — so with one or two tracks the room a
  person naturally presses in to band the clips above it did nothing. The
  frozen file grew a `.outside` hit case for that room (the header column
  under the lanes stays `.none`, and so does a content view with no owner)
  and one private `beginMarquee` that both `.lane` and `.outside` call, so
  the two starting places cannot drift: a bare press clears the selection
  AT THE PRESS, ⇧ keeps it, then the band starts. Fourteen lines net,
  inside the frozen file's allowance, because they are the dispatch the
  file says it holds. A double-click in that room closes no gap — there is
  no row to name — which is why `.lane` keeps its row and `.outside`
  carries nothing. Measured by `tools/proof/marquee_probe.py`, a probe over
  `app/Sources` that drives the three gesture entry points with synthetic
  points, **28/28**; the old guard put back takes exactly the nine rows
  that press outside a lane (19/28), and the clear removed takes the
  bare-click row alone (27/28). A real mouse pressed there is
  `reelcut-remaining.md` §4's.
- `TimelineView.swift` · `MediaPeaks.swift` · `ReverseRenderer.swift` ·
  `ReverseMirror.swift` — **the timeline drew reversed clips unmirrored,
  from M3 until 2026-09-20.** A reversed clip's `in` point is measured in
  the stream it PLAYS, and the peaks and thumbnails on disk are of the
  FORWARD file — nothing ever writes either for `cache/reversed/`, which is
  not a media entry at all — so every reader has to mirror about the media's
  model duration. `MediaPeaks` did and `ReverseRenderer` did, agreeing by
  convention with nothing shared; `TimelineView.sourceTime` did NOT, and had
  not since Reverse landed in M3, so a reversed clip's filmstrip and
  waveform drew the forward file's picture. Nobody had noticed because the
  answer is always a plausible number and the only reader that could
  contradict it — `CompositionBuilder` — substitutes the reversed asset and
  so is right for a different reason, which its own comment says. Road map 7
  §10.3 suspected it, §10's phase C probed it on the unchanged tree (the
  reversed clip's waveform came out loud on the same side as the forward
  one's, 18 028 lit pixels against 760, pixel for pixel), and the fix is a
  new `in media:` parameter and a reversed arm INSIDE `sourceTime`, so the
  filmstrip and the waveform cannot diverge. The mirror itself moved to
  `ReverseMirror.swift`, which all three readers now call and which states
  the convention once (spec §11, D4-6); it is deliberately one tick HIGH,
  because `silence2_proof.py`'s claim 9 walks the current numbers
  tick-exact. `designs/reelcut-roadmap-7.md` §10.9 is the record and
  `tools/proof/source_mirror_probe.py` the instrument, **40/40**.
- `LayerRenderers.swift` · `LayerRenderersText.swift` — text and shape
  descriptions to textures, and
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
  **The TEXT half is `LayerRenderersText.swift` since phase 6** — the two
  caches, the attributed string, the measurement and the three reveals —
  because `LayerRenderers.swift` stood at 845 and the gradient was about to
  land on it; the shape half kept the file and is 467 with the gradient in
  it. Static stored properties are legal in a class extension, so only
  `bitmap` and `upload` widened to internal.
  **A shape's `gradient` (format version 6)** is drawn in `renderShape` by
  CLIPPING to the path and running `CGGradient` inside one `saveGState` —
  measured byte-identical to `fillPath()` over a 64 × 64 ellipse,
  antialiased edge included, so a transparency layer would buy a full-size
  buffer and a rounding step for nothing. Three things about it are load
  bearing. **The renderer SORTS the stops**, because the core deliberately
  does not police their order (a refusal would make dragging one stop past
  another stop working mid-gesture), and `CGGradient`'s output is undefined
  without monotonic locations — so this is the one place that requirement
  is met and it may not be moved back into a refusal. A linear ramp
  PROJECTS the stroke-inset box onto its direction, so the end stops land
  exactly on the box's edges at every angle, and the angle is degrees from
  the RIGHT counter-clockwise, the crate's one convention, which in this
  y-UP context is `(cos θ, sin θ)` with no minus. A radial one is the
  INSCRIBED ellipse for both area kinds, guarded against the negative-width
  rect a stroke wider than the box makes. `line` and `arrow` ignore a
  gradient entirely and keep `stroke.color`. The texture key needed no
  work and that is worth knowing rather than assuming: `recipe.rs`'s
  `Source::Shape` arm hashes the whole shape description, so the gradient
  is already inside `cacheHash` — the phase-4 text lesson arriving already
  answered, and still proved by measurement.
- `CompositionBuilder+InstructionRanges.swift` — the video composition's
  instruction ranges, and the one correction to them: the LAST instruction
  ends exactly where the COMPOSITION ends when the two differ by under a
  tick. `fill`'s held last frame is scaled from the source's timescale to
  ticks and AVFoundation reports the composition's duration in nanoseconds,
  rounded, so two recordings on a 28.172 fps canvas built a composition a
  third of a nanosecond longer than its instructions — and
  `AVPlayer` refuses an invalid video composition SILENTLY: the preview was
  black at every playhead position while `render_frame` and an export (the
  generator tolerates it) looked right. `AVVideoComposition.isValid` with a
  validation delegate is the instrument that names it, and an offline render
  never sees it — `tools/proof/preview_validity_probe.py` measures both
  that and the player's own layer.
- `Playback.swift` · `CompositionBuilder.swift` · `Compositor.swift` ·
  `CompositorEffects.swift` · `MediaImporter.swift` ·
  `Exporter.swift` · `ExporterLoudness.swift` · `ExporterSettings.swift` ·
  `ExporterWriter.swift` · `ExporterImageSequence.swift` —
  the AVFoundation/Metal side; see spec §7.5–7.8. Two phase-5 facts about
  the last four: an export is TWO passes wherever the file holds sound —
  a measurement build of its own (a mix copy would share the tap, and a tap
  carries per-instance state), reading 32-bit FLOAT so a mix over full scale
  is measured honestly, then the ordinary write with the gain applied to the
  decoded Int16 samples. `ExporterLoudness.swift` IS that first pass, a pure
  move out of `Exporter.swift` when the second one took it past the ~600-line
  cap, which is why `Exporter`'s `lock`, `measureReader`, `scratchStorage`,
  `scratchCapacity` and its two accessors are internal rather than private —
  stored properties cannot live in an extension. `ExporterSettings.swift`
  is the SECOND payment of the same toll, in phase 7, when `export` and
  `renderFrame` each grew a `RecipeOptions` argument: the resolved settings
  translated into AVFoundation's vocabulary — the time range, the fallback
  session preset, the file type, the UTI, the extension, and
  `ExportSettings.isAudioOnly` — pure functions of a settings value with no
  export state in them, and half their callers the export SHEET rather than
  the exporter. **`renderFrame` deliberately did NOT go with them**, though
  it is the other obvious cut: it is the app's only `copyCGImage` call, and
  the build baseline names that warning by FILE ("3 in
  `CompositionBuilder.swift`, 1 in `Exporter.swift`"), so moving it would
  falsify that sentence in the root `CLAUDE.md` for no gain.
  **`ExportWriter` refuses an alpha-carrying row at a PADDED size**
  (`checkAlphaSurvivesTheSize`, phase 7b), and the reason is measured
  rather than feared: the composition renders at the canvas size and
  `AVVideoScalingModeResizeAspect` fits it into the asked-for frame, and
  when that fit has to PAD, the padding path destroys the alpha channel —
  a 320 × 180 transparent canvas written `prores_4444` at 240 × 240 comes
  back with the PICTURE at alpha 0 and the letterbox BARS at alpha 255,
  the answer inverted rather than merely lost. A pure SCALE is correct at
  every pixel up or down (160 × 90 and 640 × 360 both measured clean), so
  what is refused is the aspect change and never the resize, and the test
  is the fit itself rather than a ratio, which would need a tolerance
  nobody can justify. **The guard tests the box the ENCODER is handed and
  not the size the core resolved**, which the review caught it failing to
  do: `videoSettings` rounds every dimension down to even, so an
  odd-edged transparent document — 1001 × 667 — passed the fit and was then
  encoded at 1000 × 666, reaching the padding path through the DEFAULT
  Document-size row with the guard silent. The rounding is one function
  now (`encodedSize`) and both the guard and the encoder ask it, so the
  two cannot be made to disagree again. With that closed, "only a
  hand-typed Custom size reaches it" is true: every row of the Size popup
  is already fitted to the document's aspect (`export_size.rs`).
  **The other alpha row does not need the guard and
  must not grow one** — `apng` takes the ImageIO path, which FITS instead
  of padding (240 × 240 asked of a 16∶9 canvas writes 240 × 135), so its
  alpha survives any size. And
  `CompositionBuilder.build`'s `metering` flag
  is passed true by `Playback.startRebuild` and by nothing else, so an
  export and a rendered frame build exactly the audio path they built before
  the level meter existed. **Nothing else may be added to that builder for the
  PREVIEW's sake**: phase 8a's Preview Quality scales the render size on a
  `mutableCopy()` inside `Playback` rather than taking a second such argument,
  which is what keeps the export path unreachable from a preview setting rather
  than merely unchanged by it (see `EditorViewController+PreviewQuality.swift`
  below). `CompositorEffects.swift`
  holds the M3 effect logic so `Compositor.swift` grew only the uniform
  fields; the uniform block's field ORDER is a contract with
  `Resources/Shaders/Compositor.metal` and is checked nowhere but by reading
  both, so change them in one edit. It is 104 floats (416 bytes, 26 × 16)
  since `video.obscure` landed, and the four regions in it are
  REGION-MAJOR — all eight fields of region 0, then region 1 — in the
  model's own field order, so the two files read as one list and a reader
  can check the contract by eye, which is the only way it is ever checked.
  Format version 6 added `video.blend` for **zero bytes**: `reserved0`
  became `blendMode`. Road map 2's phase 8 then spent the rest of the tail:
  `reserved1` / `reserved2` became **`canvasPerDestX` / `canvasPerDestY`**,
  canvas pixels per DESTINATION pixel, so the block is still 104 floats
  (416 bytes) and **the padding tail is now EMPTY** — the next field to
  land needs three companions, not none. `ShadowUniforms` went 8 floats →
  **12** (48 bytes) for the same pair, because 10 floats is 40 bytes and
  not a multiple of 16, which is why two fields cost four.
  **Zero means one**: the shader reads a non-positive ratio as 1, so a
  zeroed uniform block renders exactly what every frame rendered before the
  field existed — `blendMode`-is-0-is-`normal` applied a second time, and
  the reason the field was safe to add at all.
  **Why it exists, because it is the shape of a defect that will come
  back.** `[[position]].xy` arrives in DESTINATION pixels, and three shader
  tests took it to BE canvas pixels: a nest's `clip_rect`, the drop
  shadow's mask sample, and the outgoing dissolve's partner box. For the
  app's whole history the two were equal — `CompositionBuilder` is the only
  other writer of `renderSize` and always sets it to the canvas — so the
  assumption was true, was written into three comments AND into
  `core/src/nest.rs` and spec §7.3, and was invisible. Preview Quality made
  the destination smaller and it became a wrong PICTURE: three quarters of
  a nest erased at Half and all of it at Quarter, a shadow displaced to the
  corner or gone, a dissolve losing its weight correction. The phase's own
  doc had already leaned on the shadow mask being canvas-sized — but only
  to argue it does not get CHEAPER. **An invariant that holds because two
  numbers have always been equal is not an invariant**; name the one you
  mean.
  **The compositor is FIVE pipelines from three fragment functions**, and
  two of them carry rules a reader will otherwise undo. The layer stage has
  two INDEPENDENT specializations — `kGatherFilters`, a function constant
  that compiles the neighbourhood loops in or out, and
  `reelcut_layer_blend_fragment`, the entry point that reads the
  destination through `float4 dst [[color(0)]]` and computes
  `video.blend`'s combination itself — so four layer states, plus the
  shadow's quad. Both entry points forward to one `static inline` helper
  holding the whole stage, because Metal cannot call one `fragment`
  function from another.
  **Rule one: a programmable-blend pipeline MUST be built with
  `isBlendingEnabled = false`**, or the finished pixel is blended a second
  time by the fixed-function stage. Metal builds it either way — no error,
  no validation warning, nothing in the log — and at alpha 1 the double
  blend is INVISIBLE, because `oneMinusSourceAlpha` is 0. **What decides
  that is the DESTINATION's alpha and not the layer's**, and the phase got
  it backwards first: the fragment stage returns the finished composite,
  whose alpha is `as + ab·(1 - as)`, and over an OPAQUE destination that is
  1 whatever `as` is — so a half-opacity layer over an opaque backdrop
  shows nothing either. It takes a destination alpha below one AND a source
  that does not cover it, where the alpha lands 32/255 high while the
  colour moves by two. `phase6_proof.py`'s section 6b is that check and is
  the only one in the script that reads the alpha channel; the
  partial-opacity check written for the job first (section 6, a translucent
  LAYER over an opaque backdrop) scored 160/160 against the broken build.
  **Rule two: a shadow's silhouette pass takes `maskState` — the layer's
  gather specialization WITHOUT its blend — because the mask asks about the
  layer's SHAPE, which no blend mode changes.** It is DEFENSIVE and not
  load-bearing, and that was measured rather than assumed. The natural fear
  — step 1 draws coverage into a texture cleared to transparent black, so a
  `multiply` over an empty destination is 0 everywhere and every blended
  layer's shadow silently vanishes — is true of a naive `src · dst` and
  FALSE of the premultiplied composite the shader runs, whose `(1 - ab)·src`
  term carries the source through an empty destination: at `ab` = 0 the
  formula reduces to `src` exactly, for all eight modes. A build passing
  `state` here renders every shadow correctly and fails NO check in
  `phase6_proof.py` — named checks, never a fraction, which goes stale the
  next time the script grows and this one already had. Keep the
  separation — it costs nothing, it says what the mask pass means, and a
  formula without that term would make the hazard real — but do not repeat
  the claim that it is holding a bug back. The
  shadow's own DRAW stays fixed-function source-over whatever the mode (a
  shadow is light falling on the backdrop, not the layer's ink), while the
  REFLECTION goes the other way and inherits the blend, since it is part of
  the layer. And a layer mid-TRANSITION always blends `normal`, which the
  CORE emits (`recipe.rs`), so this side has no special case for it and
  must not grow one.
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
  **The paused refresh is a one-tick round trip, not a same-time seek**
  (`Playback.refreshPausedFrame`, 2026-09-17). Spec §7.6's property-only
  branch publishes the project to `RecipeSource` and then has to make the
  paused player compose one frame, and "the standard trick" — a
  zero-tolerance seek to the time the player is already at — is a NO-OP on
  macOS 26.5.1, measured by `tools/proof/preview_refresh_probe.py`: the
  completion fires with `finished`, no composition request is issued, and
  the layer keeps the frame it had, so every inspector edit showed only on
  the next playhead move. Re-assigning the item's `videoComposition` and
  `AVPlayerItem.seek` to the same time are the same no-op; only a seek to a
  DIFFERENT time composes. So the refresh seeks one tick off the playhead
  (inside the same frame, so the picture between the two seeks is the
  picture) with the return queued as `pendingSeek`, and the transport lands
  back on the playhead's own tick. Two edges, both measured: the END tick
  composes the empty canvas (every seek to it, tolerant or not, displays
  black, while a transport that PLAYED to the end holds whichever frame the
  pipeline composed last), so parked at the end the refresh rests on the
  last frame's final tick and does not return — a round trip there blanks
  the frame — and the timecode then names that frame; and a refresh asked
  for while a seek is in flight is remembered (`refreshWanted`) and run
  when the seek lands, where the old guard dropped it and the last tick of
  a live drag could be the one lost. View ▸ Preview Quality relies on the
  same refresh and was invisible on a paused player for the same reason.
  Do not put a same-time seek back, and do not "fix" the end case into a
  return to the end tick.
- `MediaImporter.swift` · `MediaImporter+Probe.swift` · `MediaCacheFiles.swift` · `FFmpegRewrap.swift` — the
  import funnel, the await-free half of its cache, and the opt-in ffmpeg step
  behind it (spec §7.7, §11). `async`/`await` is confined to
  `MediaImporter.swift`, and that rule is what decided the cut:
  `MediaCacheFiles.swift` is an `extension MediaImporter` holding where the
  two caches live and how they are read and written — the two path helpers
  and the three constants beside them, `loadThumbnail`, `thumbnailCount`,
  `loadPeaks`, `.mediaCacheDidChange` with its keys, and the plumbing
  `thumbnails` and `peaks` stand on — none of which awaits, so every
  `MediaImporter.x` call site in the tree is untouched, while
  `generateCaches`, `thumbnails` and `peaks`, the three that do await, kept
  the file that holds the exception. The cut was a PURE MOVE landed alone
  (`3e5b598`), the toll for the completion marker that followed it, paid at
  619 lines against the ~600 cap; it cost three widenings —
  `ensureDirectory`, `writeJPEG` and `postCacheChange`, `private` →
  internal — because the two async writers call them and `private` does not
  cross a file. **The completion marker lives in the new file too**
  (spec §5.6): `CacheStamp` (the source's size and modification second plus
  the record fields and constants that size a cache — no path, and its doc
  argues why), the two marker paths (`thumbs/<id>/complete.json`,
  `peaks/<id>.complete.json`), `readStamp` / `writeStamp`, `clearThumbnails`
  and `clearPeaks` (marker first, then the old frames or the old `.bin`;
  each answers whether it removed anything), `stripHolds` (the vouching
  rule below), `PeakBuckets` (the bucket arithmetic, await-free — it moved
  here when the fixes took `MediaImporter.swift` to 644, and a `.bin` from
  the moved code is byte-identical to one the pre-move binary wrote),
  `replacedKey`, `writeJPEG` now answering whether the frame landed, and
  `CacheLedger`, which runs the passes for one media one at a time IN CALL
  ORDER — an `NSLock`, not an actor, because each pass carries the URL the
  media resolved to when it was asked for, and an actor reached from
  synchronous code through a `Task` hop cannot promise two hops from one
  thread arrive in order. `generateCaches`'s task awaits the previous pass,
  computes the stamp ONCE and hands it to both halves (so a no-op costs a
  stat, a marker read per half and a `fileExists`, and the two markers
  cannot disagree about one file); `thumbnails` and `peaks` compare it with
  their marker at the head and return without decoding or posting when it
  matches. Otherwise the stale marker goes first, the old frames or the old
  `.bin` second — and a withdrawn `.bin` is POSTED at once, so no reader
  measures the previous file's sound while the new one is read; a `peaks`
  post can now mean withdrawn as well as landed — the marker is written
  LAST, and only for a strip the pass can vouch for: `stripHolds` — at least
  one frame landed, and every frame the pass wrote is still in the directory
  when the loop ends. That rule is what closes the case the first landing
  missed: a save of a TITLED document while a pass runs swaps the package
  under it (frames written between NSDocument's listing and the swap are
  lost, later ones land by path in the new package), and a reader that
  fails on every frame; both leave no marker and the next open rebuilds, as
  every strip did before markers existed. `replaced` rides the FIRST post
  of a replacing pass only — nothing of the old film is on disk once
  `clearThumbnails` returns, so every tile memoised after that post is the
  new film's — and an image whose decode fails after the clear posts it
  too. After the fixes: 586 and 490. **Pitfall**: `TimelineCaches.invalidate`
  clears only MISSES for thumbs — right while a strip fills in, wrong once
  it has been replaced — so the timeline reads `replaced` off the
  notification and drops that media's decoded HITS only then; a pass that
  replaced a strip but did not say so would leave the old film on screen
  until the 800-entry drop. Two limits, recorded and not fixed: `relink_media`
  never re-probes, so a relink to a file of another length sizes the new
  strip from the old `duration`; and the ledger's price is that a pass stuck
  inside one AVFoundation call (a stalled network volume) holds every later
  pass for that media, a relink away from the stalled file included — the
  escape (skip the wait when the URL differs) does not help a stuck call and
  reintroduces the interleave for a merely slow one, so it was argued and
  not built. And one residual window the pass cannot close: `stripHolds`'
  listing and the marker's write are two steps, so a swap landing between
  them (one directory read wide) would still certify holes. The one `Task`
  in the new file (`postCacheChange`'s main hop) awaits nothing. `FFmpegRewrap` runs `Process` on a serial queue, never on a
  cooperative thread, because ffmpeg blocks the thread it is on.
  **`AppSupport.swift` is the ONE spelling of
  `~/Library/Application Support/Reelcut/`**, and the argument for putting
  anything there is still `FFmpegRewrap.rewrapDirectory`'s doc: there is
  frequently no package to write into, and the one place a package survives a
  save is documented as deletable. Two things live under it —
  `Rewrapped/` and phase 7's `ExportPresets.json` — and a third asks
  `AppSupport` rather than writing the two path components out again. Every
  accessor answers a PATH and creates only the Application Support root; the
  caller creates the leaf, at the moment it has something to put in it, so
  building a path never litters a Library with folders for features nobody
  used.
  **`thumbnails` holds the last frame past the video track's end** (road
  map 3's R0 surprise): a screen recording's picture ends at the last screen
  change while its sound runs on and the record's `duration` is the sound's,
  so the seconds past the picture used to fail as tinted holes under a marker
  that certified them. The pass now finds the track's LAST SAMPLE's own time
  — an `AVSampleCursor` at the end of the sample table mapped through the
  edit list, `range.end − minFrameDuration` only when the file offers no
  cursor — and treats the seconds at or past it as a HELD suffix that asks
  for that frame once and is written under each index: `CompositionBuilder.fill`'s
  held tail, seen from the strip. It is the TRACK's time and never the
  record's rate, because a sparse recording's `nominalFrameRate` is its frame
  count over its length (three frames in 50 s read as 0.06 fps, a 16.7 s
  'frame'), and a tail measured from the record held the slide BEFORE the
  last one from 34 s on while the composition showed the last — the review's
  finding, `remaining_probe.py` 5f's sparse shape and its `record-rate-tail`
  mutant. What the generator answers between frames, measured: a second
  whose displayed frame is a SYNC sample lands however far after it (24 s
  after a keyframe); a real ScreenCaptureKit recording lands every second up
  to its track's end; an ffmpeg file of three frames 25 s apart FAILS
  (−11821) inside a non-sync frame's range and 0.7 ms after its last frame's
  time under VideoToolbox — so the held request is the frame's exact time,
  not the track's end less a frame. The failure arm still leaves a hole,
  deliberately; a file with no video track runs as it did; the every-16 post
  counts TILES; the marker's rules are untouched. `MediaImporter+Probe.swift`
  is the await-free half — `ImportError`, `imageTypes`/`isImage`,
  `probeImage` and the rate table `rationalFrameRate` rounds onto — cut when
  the held tail took the base file over the ~600 cap (619 → 518, 571 with
  the tail in it); every call site keeps its `MediaImporter.` spelling and
  the cut cost one token, `probeImage`'s `private`.
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
  Its save panel's format popup renames through `CaptionExporter.renamed`
  over `knownExtensions` = `{srt, vtt}` (`FrameWriter.renamed`'s six lines
  with `rawValue` for `fileExtension`; the `FrameWriter` row below carries
  the argument, the sibling helper and the probe), and seeds the field from
  `ProjectDocument.displayStem`, never a bare `deletingPathExtension`.
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
- **The nest scope's footprint in the panes**, phase 9's, said once here
  because it is a split rather than a file: `InspectorBinding.project` /
  `snapshot` / `canvas` are the SCOPED project — what the Clip tab reads and
  writes, since the clip it is showing is inside the nest — while
  `documentProject` / `documentSnapshot` / `documentCanvas` are the
  document's, and `DocumentPane.swift` reads only those. That pane is about
  the FILE: its canvas, its markers, its media count, what its background
  lets an export carry. `set_canvas` and the two marker ops it writes are
  document-level and go unscoped, so the tab keeps working with a nest open;
  reading a scoped snapshot there would mean answering about one project and
  editing another, visibly so, since a scoped view has NO markers and the
  nest's frozen size for a canvas. `MediaPaneCommands` asks
  `documentSnapshot` for exactly one question — "which clips use this file",
  for Remove's alert, because `remove_media` is document-level too — and the
  scoped one for everything about placement.
- `InspectorViewController.swift` (frozen at wiring: the tab strip and which
  pane is shown) + `InspectorPane.swift` (the pane protocol and base, the
  disclosure section with its collapsed-state key and its right-aligned
  summary, the row builders, and `InspectorBinding` — the one place that
  knows reads are evaluated inside an action and that writes there set
  `set_action_end`, with the ONE exception `structural(video:for:)` pulls
  out: a list-valued key (`filters`, `obscure`) whose new LENGTH differs
  from `editedList`'s goes to the BASE props wherever the playhead is,
  because `actions.rs`'s list rule interpolates per index only while the
  lengths match — an appended region written into an end patch is invisible
  for the whole span, does not even grow a row, and is then dropped by the
  next write of that list.
  **`editedList` is phase 6's, and both halves of it were defects.** A
  WRITE of a list-valued key must be built from, and measured against, the
  list it is about to REPLACE — the ACTION's own end list where the end
  patch carries one, the clip's base list otherwise — and never the
  EVALUATED list every `read:` closure uses. Building the array from the
  evaluated one re-pinned every entry the user did not touch at whatever it
  read at the playhead, silently flattening a neighbour's ramp; measuring a
  new length against the BASE alone misfired with two actions on a clip,
  where an earlier end patch had already changed the count, and rewrote the
  clip's base stack. A third list-valued property joins this rather than
  reading `videoProps` directly) + `ClipPane.swift` for the Clip tab,
  `MediaPane.swift` and `DocumentPane.swift` for the other two, with
  `VideoPane.swift`, `VideoPane+Transition.swift` (the Transition
  section — the one group that is not about the layer's own pixels but
  about how it MEETS the clip before it, shown only for a single clip
  with an overlap; an extension file because the base pane stood at 1465
  lines and the section grew road map 5 E1's Curve popup and Crossfade
  Audio row, and the cut cost no visibility),
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
  **And a fifth, which phase 8c had to design around:** `rebuild()` destroys
  every control in the pane and NOTHING here preserves the first responder, so
  a control a person TYPES into cannot depend on surviving one — a field
  rebuilt under the caret loses its field editor and the window becomes first
  responder (measured). Whatever such a control edits must therefore live
  outside `structureSignature`, which is a statement about the MODEL's shape,
  and its effect must be applied to the views that already exist.
  `MediaPane.arrange()` is the worked example: it hides and re-orders the
  list's arranged subviews and rebuilds nothing.
- `MediaPane.swift` · `MediaRowView.swift` · `MediaPaneCommands.swift` ·
  `MediaListFilter.swift` · `MediaUsage.swift` · `MediaReveal.swift` — the
  Media tab (§4.3): the list, one row of it, the commands a row calls back
  into, the find band phase 8c added, the one spelling of "is this media
  used", and Reveal in Timeline's editor half. The pane is the LIST: its one
  `InspectorSection`, the three chrome bands that overhang the section inset,
  the Finder drop onto the panel, and `arrange()`. The row is one FILE and the
  DRAG it starts. The seven commands a row calls back into (`select`, `place`,
  `revealInTimeline`, `reveal`, `relink`, `remove`, `drop`) are a third file,
  because every one of them applies an edit through `binding`, writes view
  state, or puts a panel up — the pane's business and never a row's — and none
  of them touches the list's views except `select`, which redraws them
  (`MediaPane.rows` widened to internal for it, and that is the whole cost of
  the split).
  **The find band never rebuilds the pane, and that is the whole design of
  it** (road map 2's phase 8c: a search by name, a sort, an "unused only"
  switch). `InspectorPaneView.rebuild()` removes every arranged subview and
  asks `makeSections()` for new ones, `InspectorViewController.refresh` runs
  it whenever `structureSignature` changes, and NOTHING in this panel
  preserves the first responder across one — so a search field built inside
  `makeSections()` with the filtered set in the signature is destroyed by the
  first keystroke that changes the list, taking the field editor and the caret
  with it (measured: remove a text field's ancestor and `currentEditor()` is
  nil and the window is first responder). So the signature stays a statement
  about the MODEL's shape — which media exist, and whether each file is
  there — and `MediaPane.arrange()` applies the search, the sort and the
  switch to rows that are already built, by hiding and re-ordering the list
  stack's arranged subviews. Both halves are measured rather than assumed: an
  `isHidden` arranged subview leaves an `NSStackView`'s layout entirely, and
  `insertArrangedSubview(_:at:)` MOVES a view that is already arranged (over
  all 24 permutations of four rows the arranged order, the laid-out order and
  every row's full-width constraint survive, and the subview count does not
  change) while leaving the window's first responder and the caret's offset
  exactly where they were. **Anything this panel ever grows that a person
  types into inherits the rule**: the rebuild is the hazard, not the typing.
  `MediaListFilter.swift` is the band as a VALUE — the search text, the order,
  the switch, and the pure `ordered` / `admits` over them — with the three
  controls that write it beside it, `AudioNormalize.swift`'s shape; the pane
  keeps only the layout (two LINES in one band, because the three controls
  measure 319 pt against the 284 the default panel leaves and the 260 the
  minimum does). Its state is deliberately NOT persisted, and the file argues
  it three ways — one of them being that a `UserDefaults` key would have to be
  pinned in the offscreen harness or every chrome render of this pane would
  depend on what the machine happened to store.
  **`MediaUsage.swift` is one spelling of a question Swift used to answer
  twice, and wrongly both times.** The core refuses `remove_media` against
  `every_clip()` — the timeline's clips CHAINED with every nest's, not a walk
  down from the timeline, because a nest nothing points at still holds clips
  that reference media (one id space, spec §5.2) — and both Swift copies
  filtered `snapshot.clips` alone. The live cost: removing media used only
  inside a nest showed no "and its clips" alert, went to the core as a plain
  `remove_media`, came back `Ok(None)` and reached the user as a bare beep.
  `clipsUsing` is that set; `timelineClipsUsing` is the narrower one a
  SELECTION can hold (`clampViewState` intersects with top-level ids), and the
  difference between the two is exactly what lets Reveal in Timeline validate
  FALSE for a file whose only users are nested rather than silently doing
  nothing.
  Reveal in Timeline itself is the pane writing `document.selection` (view
  state, the way it writes `selectedMedia`) and sending one selector to the
  editor; `MediaReveal.swift` publishes it and scrolls. It ACCEPTS being
  thrown off the Media tab — `InspectorViewController.refresh` shows the Clip
  tab for any changed non-empty selection — rather than making itself that
  rule's one exception. `TimelineView.scroll(toX:)` widened to internal for
  it, the widening the change forces: horizontally a revealed clip lands where
  `revealPlayhead` lands the playhead, and the body stays in the frozen file.
  The VERTICAL half needed no widening at all — `content.scrollToVisible`,
  with the rect grown UPWARD by the ruler's height, because the ruler is a
  floating subview pinned to the top of the visible rectangle and a lane flush
  with that edge would sit under it.
  **The cut fell below the drag rather than under the row's closing brace**,
  which is the only decision in it: the private pasteboard type, the two
  enums that name where a row may land, `MediaDragSession`, and the
  `TimelineView` / `PreviewCanvasView` drop targets all went with the row,
  because a drag source and the vocabulary it drags with are one sentence and
  a file boundary through the middle of one is not a seam. It is the size
  payment the pane owed at 822 lines against the ~600 cap before phase 8's
  search field, sort popup, unused-only filter and Reveal in Timeline item —
  three of which land on the pane and one on the row, so both halves got the
  room they are about to need. It cost NO visibility, unlike the splits
  above: a type carries its own scope, so every `private` member travelled
  with its privacy intact and nothing widened.
  **The room was not enough, which is phase 6's warning arriving again**
  ("budget the cut against the pessimistic number"): those four additions put
  the pane back over the cap, so phase 8c paid a SECOND toll and moved the row
  commands out (`MediaPaneCommands.swift`) — this time for one widening. The
  pane is 474 lines with the find band in it, the commands 206, the filter
  value and its controls 248, the usage question 58 and the reveal 87.
- `ExportSheetController.swift` · `ExportSheetOptions.swift` ·
  `ExportSheetResolve.swift` · `ExportSheetPresets.swift` (the export card —
  **eight control rows since phase 7's Preset row and Burn in timecode
  checkbox**, phase 5's Loudness popup being the sixth and its −1 dBTP ceiling
  still FIXED and stated in the hint rather than made a row of its own —
  split FOUR ways at the ~600-line cap, three of the cuts made when the file
  stood at 1114 and the fourth when phase 7's own additions put it back over:
  the controller BUILDS the controls and commits, `Options` holds what they
  MEAN before any of them is read (the ranges, the loudness targets and their
  menu spelling, the quality ladder, `Applies`), `Resolve` reads a selection,
  asks `rc_export_settings` about it and repaints the card from the answer,
  and `Presets` owns the saved-preset LIST — the one part of the card with a
  store behind it and a life longer than the sheet's. The
  toll is `ExporterLoudness.swift`'s: every stored control and every
  crossing member is internal, because `private` on an extension member
  reaches only its own file.
  **Phase 7's three additions are one idea: the card's controls are a VALUE**
  (`ExportChoice`, `ExportPresetsStore.swift`). The sheet reopens on the last
  choice EXPORTED with (not the last one dismissed), a named preset is that
  same value in a file, and both are written back by one method — `apply(_:)`
  in `Resolve`, **whose ORDER is load-bearing and is documented there**: the
  format before `rebuildSizes()` (a programmatic `selectItem` sends no action,
  so `formatChanged`'s guard never fires) and the size after it (it ends with
  an unconditional `selectItem(at: 0)`); a size stored as `ExportSize.id` and
  never an index, because `visibleSizes` drops rows a document already has;
  "Custom…" chosen before its loudness field is filled, or `syncReadout`
  overwrites it; and `in_out` degrading to "Whole project" where there is no
  range. **What a preset stores is the CONTROL CHOICES and not resolved
  overrides** — the road map's design for it cannot be built, and
  `ExportPresetsStore.swift` argues why at the top. The Preset popup carries
  each record in `representedObject`, is read from `selectedItem`, and its
  menu is built from `NSMenuItem`s rather than `addItem(withTitle:)`, which
  removes a same-titled row; the gear beside it is a pull-down because the
  control column is 258 pt and a popup plus two titled buttons is not.
  The Burn in timecode checkbox is the one control that is NOT an export
  override: it rides to `Exporter.export` as a `RecipeOptions` — it changes
  the picture, and `export_overrides.rs` drops an unknown key in silence —
  and it shows PROJECT time, so a range export starting at 00:00:10:00 writes
  a file that begins at 00:00 reading 00:00:10:00, which the hint says out
  loud), `ExportProgressSheetController.swift` (the
  progress sheet, a separate class and so a free cut, which says
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
  validates false while one is attached — **and, since phase 8b, because
  `EditorViewController.handleEditorKey` refuses while one is, which
  `validateUserInterfaceItem` alone no longer covers.** A sheet is
  WINDOW-modal, not application-modal (measured: with one attached
  `NSApp.modalWindow` is nil and the preview panel is still visible and still
  `canBecomeKey`), so the panel's forwarded bare keys reached the key map
  without passing a validator: `t` added a text clip behind an open export
  card that had already captured the project it was about to write, and
  Remove Silences — which computes its spans ONCE — would have shown a wash
  and a count for a placement that no longer existed and then rippled those
  ranges. The guard is one line beside the key map rather than in the panel,
  so both windows get it from one place.
  **The card has TWO commits since phase 7e** — Export… and Add to Queue, in
  `makeButtonRow`'s `secondary` slot — and they are ONE method (`commit(queue:)`),
  branching only at the handoff, because a queued job is not a second kind of
  export but this one held until its turn. Both are enabled by one fact, and
  only one of them is written: `syncReadout` sets Export…'s state from
  `resolved`, and `resolveCard()` — which is what every path in the card calls
  instead of `resolve()` — copies that ANSWER onto Add to Queue rather than
  reading `resolved` a second time.
- `ExportQueueController.swift` · `ExportQueueWindowController.swift` — the
  export queue (Window ▸ Export Queue, road map 2's phase 7e), and the split
  between them is the feature. **The controller has no AppKit in it**: the job
  list and its state machine are a thing a probe compiled from `app/Sources`
  can make, fill, run and read (`AudioNormalize.swift`'s shape, and phase 5's
  level meter's reason — a window cannot be photographed offscreen or driven
  over MCP), and the window is a READER of it that holds no job, decides
  nothing and stops nothing when it closes.
  **No MCP mirror is owed and none may be added**: the rule is that every
  user-visible EDIT gets one, a queue edits no project, and an agent can
  already call `export` N times in sequence — which is what this does, so
  `export` IS the mirror. A tool added so a proof could exist would be the
  proof deciding the API (`tools/proof/README.md`).
  Four things in the controller are load-bearing. **One job at a time, on the
  MAIN thread, a fresh `Exporter` each** — `Exporter.export` is documented
  main-thread-only and one-at-a-time, its progress timer must be invalidated
  on the thread that scheduled it, and an exporter carries per-export state
  (`recipeKey`, the loudness scratch), so this is a CHAIN and a `DispatchQueue`
  of exporters would be the wrong shape. **A job is what it will write,
  captured when it was confirmed**: the `ReelProject` needs no clone (handles
  are immutable and `Exporter` publishes it on a `RecipeSource` key of its
  own), and `mediaURLs()` is resolved at ENQUEUE by
  `EditorViewController.enqueueExport` — it reads bookmarks and the
  filesystem, so resolving at RUN time would pick up a Relink… or a moved file
  from after the job was queued. The rule is structural rather than
  remembered: a job holds a `[UInt32: URL]` and no document to ask again.
  **A cancelled job's half-written file is removed**, in `finished`, which is
  `ExportProgressSheetController.finished`'s line repeated so the two agree; a
  FAILED one's is left, which is that same class's posture. And `isLaunching`
  turns an early synchronous refusal (`noPlan`, `emptyTimeline` complete
  before `export` returns) from recursion into a loop.
  Two in the window. It is deliberately **not `WelcomeWindowController`
  copied**: that class closes itself on `NSWindow.didBecomeMainNotification`,
  which here would make the queue vanish the moment the person clicked back
  into the editor, and its window is deliberately not resizable where a list
  must be. And **`window.isExcludedFromWindowsMenu = true`** — `NSApp.windowsMenu`
  is AppKit's, so without it the Window menu carries "Export Queue" twice.
  It persists NOTHING (no autosave frame, no defaults key), so no chrome proof
  and no `pinDefaults` entry is affected by it. Phase 8b's preview window went
  the other way and says why in its own doc: a queue is a list you glance at,
  and a preview window is furniture you put on a particular display.
- `AgentCatalog.swift` · `AgentCatalog+Clips.swift` · `AgentCatalog+Files.swift`
  · `AgentCatalog+Transitions.swift`
  — the MCP tool catalog, in four files: the helper, the project group,
  tracks, markers and the canvas in the base file; the forty-five clip and
  action rows spliced in from `+Clips`; the TWO transition rows
  (`add_transition`, `set_transition_style`, road map 5's E1) spliced in
  from `+Transitions` immediately after them, beside `set_transition` and
  `set_transition_duration` and never at the end of the catalog, which is
  where `recording_probe.py` reads the last eleven names; the eleven FILE
  rows (Media, Captions, Rendering and export, and `record_screen`) spliced
  in from `+Files` (road map 3's R1·toll), each splice taking the hoisted
  locals it reads as arguments; a startup check enforces that catalog names match the
  dispatch registry (it traps in debug and logs in Release, because
  `make app` builds Release). The handlers live in
  `AgentServer+Project/Clips/Tracks/Media/Render/History/Silence/Captions/Audio/Background/Scope/Recording.swift`
  — `record_screen` being three files since the R1 fix wave:
  `+Recording.swift` (the tool, its three semaphore waits and the menu-bar
  chrome a tool recording gets — since R2 the same Pause / Resume / Stop
  item the panel puts up, its closures calling the recorder directly),
  `+RecordingArguments.swift` (the argument vocabulary and the
  shareable-content lookup) and `+RecordingResult.swift` (the result
  fields — `pauses` and `segments` since R2, one entry per file with its
  ids as `RecordingSegmentIds`, ONE shape for both doors, `duration` the
  TOTAL — and every sentence a refusal after the files exist names them
  with, over `RecordingResult.filesClause`; the stop ceiling is the
  recorder's finish ceiling plus two 30 s probe ceilings PER SEGMENT plus
  a margin, independent of `seconds`)
  — `+Scope.swift` being the newest and largest of them (the call's scope,
  `idScope`, `effectiveScope`, the `set_scope` handler and the parity
  check's fourth part)
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
  `AgentServer+Transitions.swift` is road map 5 E1's pair of handlers, and
  it is the reason `curveArg` widened from `private` to internal in
  `AgentServer+Clips.swift` — `private` on an extension member reaches only
  its own file, `ExporterLoudness.swift`'s toll. All four of its string
  arguments are refused by NAME before a builder is called, which is not
  automatic: `ProjectSnapshot`'s enums decode leniently, so a misspelt
  `kind` or `align` that reached a typed value would become the first case
  and the caller be told its wipe had landed. It also refuses a keyless
  `set_transition_style`, which is an argument the caller forgot rather
  than a rule saying no — the core's own answer is an identity, and an
  identity says only that the project is already in that state. It used to
  REWORD `add_transition`'s two refusals as well, trial-applying the op to
  see whether it would land; deepening D2·4 (road map 7 §5.4) deleted that
  trial and both sentences, and the core's own words arrive instead.
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
  wrong type by name. **`VideoPatch.motion` is the eleventh `T??` field
  and has NO gap either**, for the same reason one step further: it is
  hand-read by `motionPatchArg` and stripped out of the dictionary before
  `patchArg` ever sees it, so a wrong type, a misspelt key at any of its
  three levels and a kind outside either enum are each refused by name.)
  A second thing that round trip cannot do, older than phase 3 and
  measured again by its proof: a nested OBJECT in a patch is decoded into
  its typed struct and re-serialised, so an unknown key inside one is
  dropped where the core would have named it, and a known key the caller
  omitted is sent as that struct's DEFAULT — which resets the field. That
  is `shadow`, `chroma`, `duck`, every `obscure` entry, every `filters`
  entry and `animation`: the core
  refuses both (`deny_unknown_fields`), the decoder simply gets there
  first, so a patch of a nested object is a REPLACEMENT and has to be sent
  whole. `AgentCatalog`'s text-patch sentence spells that out for
  `animation` in the tool's own words, because a key left out of one comes
  back as a 1 s typewriter rather than as what the clip had.
  `filters` is the member of that family the list used to omit, and the
  omission had teeth: `{"filters": [{"amount": 1.0}]}` is the core's own
  idiom for "the same filter, more of it", `FilterProps` has no optionals,
  so the decoder filled the missing `kind` with `blur`, a `sepia` base
  animated and then switched to a blur, and the caller was told it had
  worked. `checkVideoEnums` refuses a partial filter entry by index now.
  **`shape.gradient` (format version 6) is the one exception in the whole
  family, and it is the READER's doing rather than the decoder's.**
  `ShapePatch` is built by hand (`shapePatchArg`), so `gradientArg` walks
  `stops` by name, takes three or four colour components exactly as
  `colorArg` does, and refuses a MISSPELT key inside `gradient` BY NAME —
  which `shadow` (since M3), `obscure` (since phase 3) and `animation`
  (since phase 4) cannot do. It is still a replacement rather than a merge,
  like all of them, so a caller sends every key it wants. Note what was NOT
  done for it: `AgentServer+Arguments.withOpaqueColors` recurses into
  nested dictionaries but not into arrays of them, so it would have refused
  a three-component stop colour with a serde message naming neither the key
  nor the patch — and widening that helper is the wrong fix, because it
  sits on every patch shape in the app. It never sees this object anyway.
  Beyond the §6 ops the catalog carries the app-state tools spec §7.9 names
  plus `set_range`, `set_selection`, `set_scope`, `undo` and `redo` — the
  mirrors of I/O/⌥X, a timeline or canvas click, the double-click that opens
  a nest (Clip ▸ Open Nest, ⌘↓), and ⌘Z/⇧⌘Z, without which the "one edit
  is one undo step", "the in/out range scopes the export", "the selection
  draws handles" and "an edit inside a nest lands inside it" properties could
  not be checked by driving the built app.
  None of the five is an op, so none registers an undo step.
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
  checks the FIVE string enums a video patch can carry and no more:
  `filters[].kind`, `spotlight.shape`, `obscure[].shape`, `obscure[].kind`
  and — format version 6 — `blend`, each against its own `allCases`.
  `blend` is a TOP-LEVEL key, so `patchArg`'s round trip looks as though it
  ought to catch a misspelling and does not: `BlendMode` decodes leniently
  to `normal` like every other enum in `ProjectSnapshot`, and a patch
  carrying `normal` is not equal to one carrying nothing, so the
  "would have been ignored" test passes and `"muliply"` reaches the core as
  source-over. It also checks a filter entry for COMPLETENESS, which is the
  same defect one step on. Nothing else in a
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
  and `MediaRowView.swift`'s drop targets use, and the reason `dragSnapper`
  and `makeSnapper` are internal.
- `SileroVAD.swift` · `MediaSpeech.swift` · `MediaImporter+Speech.swift` —
  road map 4's voice model, and the three files are its three concerns.
  `SileroVAD` is the streaming Core ML wrapper over
  `app/Resources/Models/silero_vad.mlmodelc` (vendored COMPILED, MIT, with
  `PROVENANCE.md` naming the upstream tag and the conversion's revision —
  spec §11): 512 new samples and 64 of carried context per prediction, the
  LSTM state fed back, the remainder HELD across `feed` calls so a reader
  handing it one `CMSampleBuffer` at a time never loses the tail of a chunk
  that straddled two buffers. It is **NOT `async`** and must not become so —
  `MLModel.prediction` is synchronous, which is what lets the same class
  serve the cache pass and (through the cache) a detector that runs on
  main. Its availability is ONE `NSLock`-guarded process-wide reason:
  `markUnavailable(_:)` keeps and logs the FIRST reason only, `isAvailable`
  reads it, and `bundled()` calls it for a nil bundle URL or a throwing
  init. **A marked-unavailable process never retries until relaunch** —
  recorded, not worked around: the sheet then opens in level and the tool
  refuses `mode: "voice"` by name. `bundledURL` looks in `Bundle.main`'s
  `Models` subdirectory FIRST and then beside `bundleURL`, which is the
  offscreen harness's layout (`build.sh` copies `Models` next to the binary,
  the Fonts copy's shape).
  `MediaSpeech` is the chunk grid and the reader: `chunkTicks` (19,200,
  written as the division for `MediaPeaks.bucketTicks`' reason),
  `chunkCount(duration:)`, a `Loader` that is `MediaPeaks.Loader`'s shape
  over `loadSpeech`, and `speechMax`, which asks `MediaPeaks.window` — the
  project→source conversion, the negative floor and the reversed MIRROR,
  generalised over the bucket size at road map 4's step 2 so `peak` and
  `speechMax` share ONE spelling rather than making a third.
  `MediaImporter+Speech.swift` is the await-free half of the pass
  (`MediaCacheFiles.swift`'s rule, same reason): `speechIsCurrent` and
  `writeSpeech`, whose reader settings are 16 kHz mono **float** — the
  spike's, NOT `Transcriber.extractSettings`, which is 16-bit int and would
  feed the model integers. A `canAdd`/`startReading` failure returns
  silently, `peaks`' posture; a thrown `feed`/`flush` calls
  `markUnavailable` and leaves no `.bin` and no marker, which turns the
  whole process's `voiceAvailable` false rather than leaving one media
  pending for ever. The async shell is `MediaImporter.speech(...)` and
  `generateCaches`'s order is **`thumbnails` → `peaks` → `speech`**: the
  `.bin` withdrawal at `peaks`' head is §2a's measured window and may never
  be held behind a full-file decode and an inference. `CacheStamp` is
  UNCHANGED — `SpeechStamp` WRAPS it with the model name and the chunk
  size, so a model change rebuilds speech caches and no filmstrip.
  **Proved 2026-09-19** by `tools/proof/silence2_probe.py` (61/61, claims
  12–17) and `silence2_proof.py` (59/59) — the road map's §8 has the scores
  and the ten mutants. Two things the probe wrote down that are not
  obvious from reading these three files. The pass POSTED its withdrawal
  **without `replaced`**: `speech` cleared a stale cache and posted at
  `MediaImporter.swift:594–596`, exactly as `peaks` does at `:529–540`, and
  only `thumbnails` set that flag (`:375–395`) — so an observer that tested
  for it saw nothing there, and §4g's "`replaced` on the first post" was read
  as wrong about the tree, not the other way round. And `writeSpeech`'s `.bin`
  is NOT bit-identical to `SileroVAD.probabilities(of:)` over the same file:
  30–70 of 325 chunks differ by at most 0.0022, because the pass reads with
  `alwaysCopiesSampleData = false` and a reader that does not gets different
  block sizes out of the 48 kHz → 16 kHz converter. Every decision at 0.5 is
  the same, and `feed` in 1000-sample buffers plus `flush` reproduces
  `probabilities(of:)` float for float — which is the row that proves the
  remainder is carried, and the one to keep if either is ever tightened.
  **2026-09-19, the withdrawal now posts `replaced`.** The paragraph above
  records what the tree DID; §4g's claim 14 was right about what it should
  do. `speech` clears a stale `.bin` and posts before the decode, and that
  post opens a pass replacing a file already on disk — the flag's own
  meaning — so it carries `replaced: true`
  (`MediaImporter.swift`'s `speech`). `writeSpeech`'s ARRIVAL post still does
  not, and `peaks` still posts without it at either end; the flag's only
  reader is `TimelineView.invalidate`, which acts on it for `thumbs` alone,
  so nothing downstream moved. Probe claim 14 now asserts §4g's wording —
  the FIRST post carries it, the SECOND does not — and a mutant that drops it
  takes that row and only that row (60/61). See
  `designs/reelcut-roadmap-4.md` §8.
- `SilenceDetector.swift` · `SilenceDetector+Walls.swift` ·
  `SilenceSheetController.swift` ·
  `TimelineView+Candidates.swift` — Remove Silences (Clip ▸ Remove
  Silences…, and the `detect_silence` tool). **Since road map 4 the
  detector has a `Mode`** — `voice` (the default) and `level` (the shipped
  rule, byte for byte) — and three things about it are load-bearing. The
  per-step test's ORDER is the gain FLOOR first (`gain(of:from:to:)`,
  factored out of `level`, which still answers exactly what it did): a step
  whose envelope alone lands full scale at or under `thresholdDB` is quiet
  in EITHER mode before the model is consulted, which is what keeps the
  sheet's hint and the tool's catalog sentence about a turned-down, faded or
  ducked clip TRUE in voice mode. Then a voice whose SOURCE WINDOW holds
  **no voice** — `speechMax` over its whole segment under `voiceConfidence`,
  computed once per scoped voice and read there — falls back to the level
  test for its whole span, its media named in `Outcome.judgedByLevel`. Then
  a media whose speech cache has not landed is NEVER quiet
  (`Outcome.voicePending`), the missing-peaks rule repeated. `detect` stays
  PURE and SYNCHRONOUS — the sheet re-detects per slider tick — so the model
  is never loaded on that path: `Input.read` reads only
  `SileroVAD.isAvailable`. `SilenceDetector+Walls.swift` is the
  nest walls and the directional frame snap, a pure move out at road map
  4's toll 1 (`NestExtent` and the five functions widened to internal for
  it); **`refine` joined them on 2026-09-20** as the toll for the sceptic's
  pass over the reader review (road map 4 §8), which needed room in the
  detector for `Outcome.proposedMedia` — the sixth function widened to
  internal, still answering to the snapshot alone, still calling both snaps.
  **2026-09-19, the fallback is keyed per VOICE.** It was computed per voice
  and READ per media: `detect` filled a `Set<UInt32>` of media holding no
  voice and asked `contains(segment.media)` inside the walk, so a file that
  is voice then tone, split in two, had its VOICE clip judged by level along
  with its tone clip. `detect` now builds one
  `[(voice: Voice, byLevel: Bool)]` with a single `scoped.map` and the walk
  passes `entry.byLevel` to `isQuiet`, so each scoped segment is judged by
  the window it actually plays. **The naming rule that follows:**
  `Outcome.judgedByLevel` keeps its type and stays a list of distinct MEDIA —
  a media with one window judged by level and another by voice IS named,
  because the sheet's note and the tool's note name FILES and a per-segment
  list would name nothing a person can see; the three sentences say "in at
  least one clip … there" so the note is true of a mixed file. MCP claim 4's
  two-clip variant scores the voice half tick for tick against the walk now
  (61/61 since claim 1(d) landed; 60/60 when it was measured), and the
  pre-fix read, put back as a mutant, takes that row alone (59/60, the N it
  had). See `designs/reelcut-roadmap-4.md` §8.
  The detector is pure
  arithmetic over values: `Input.read` is the one seam that takes a
  snapshot, a plan, a selection and the peak files off a `ProjectDocument`,
  and everything after it is a function of those — which is what lets the
  sheet re-detect SYNCHRONOUSLY on every control change (the document
  cannot change under an open sheet — the validator, and since phase 8b
  `handleEditorKey`'s own `attachedSheet` guard, which is what closed the
  preview panel's route past it) and lets the agent run the same code.
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
  `edit_zoom.rs`'s `evaluate_clip(clip, at)`. A zoom armed over a clip with a
  During motion draws a second hint pill (`CanvasRegionView.note`), because
  the zoom is solved without the motion that will move the clip under it.
- `FrameWriter.swift` · `EditorViewController+SaveFrame.swift` — File ▸ Save
  Frame… (⌥⌘E), road map 2's phase 7a, and the split between the two files is
  the feature. `FrameWriter` is a VALUE TYPE in `AudioNormalize.swift`'s
  shape — a `CGImage` and a format in, a written URL out, no save panel, no
  document, no AppKit view — because `render_frame` calls the SAME `write`,
  which is what makes "Save Frame's PNG is byte-identical to `render_frame`'s"
  a fact about the code rather than a claim, and the only way the line can be
  checked at all: a panel cannot be driven over MCP or offscreen, so a proof
  script can never press the item. Three rules live in it. **PNG's properties
  dictionary is `nil` and must stay `nil`** — every phase from 1 to 6 compares
  PNGs written that way, and anything that ADDS metadata changes the file
  (mutated to `[kCGImagePropertyDPIWidth: 144]` and caught by the extra `pHYs`
  chunk). It is a GUARD rather than an observation, and the difference is
  measured: on macOS 26.5.1 an EMPTY dictionary and no dictionary write
  byte-identical PNGs — same sha256, same 5330 bytes, same chunk list, across
  two processes — so `[:]` is indistinguishable to any byte comparison this
  project can make, and the rule stands because the next ImageIO owes us
  nothing. The one assertion that can see `[:]` at all is structural:
  `phase7_chrome.py` reads `Format.destinationProperties != nil`.
  **JPEG flattens onto black** in an opaque bitmap before
  encoding, at quality 0.9 (a delivery still; `MediaImporter.writeJPEG`'s 0.7
  is a thumbnail), because JPEG is the one of the three containers that cannot
  carry alpha and phase 7b makes a transparent canvas reachable — the panel's
  accessory view says which format keeps alpha as the format is chosen, so the
  flatten is never silent. And **HEIC is `UTType.heic`, never `public.heif`**:
  only the former is in `CGImageDestinationCopyTypeIdentifiers()` here, and a
  destination built over the latter is nil with nothing to say.
  Two more the review put there. A nil from
  `CGImageDestinationCreateWithURL` is TWO different failures and used to be
  reported as one: a format this Mac cannot write (asked of
  `CGImageDestinationCopyTypeIdentifiers`) versus a file it could not
  CREATE — a read-only folder, a bad path — and telling somebody "this Mac's
  image encoders do not offer that format" about a perfectly ordinary PNG is
  a diagnosis they cannot act on. And the format popup's rename is
  `FrameWriter.renamed`, a pure function over `Format.acceptedExtensions`
  rather than a bare `deletingPathExtension`, because the bare one eats
  whatever follows the last dot in a name somebody typed: a project called
  "Board v1.2" was offered as "Board v1.jpg". Being a pure function is also
  what lets a probe reach it, and `tools/proof/remaining_probe.py` now does
  (nine names, its 1b) — this sentence used to say a probe could, and none
  did. The same defect had two more homes, both closed on the same shape
  and proved in the same probe's section 1 — 63 checks when it landed, and
  three named mutants scored against those 63 (`caption-bare` 59,
  `stem-bare` 60, `site-unwired` 60); the probe has grown since and prints a
  larger total: the
  caption popup's rename is `CaptionExporter.renamed` over
  `knownExtensions` = `{srt, vtt}` — the caption formats' own set, a SUBSET
  of `AgentServer.replaceableExtensions` (pinned by the probe's 1f, which
  builds its rows FROM the set and calls `destinationURL`; the `no-vtt`
  mutant is what showed the tree had never asked a `.vtt` path for SubRip)
  and never `FrameWriter`'s image set — and the title-bar stem that all three panels (Export…, Save
  Frame…, Export Captions…) put an extension after is
  `ProjectDocument.displayStem`
  (`ProjectDocument+DisplayStem.swift`), whose set is `{reelcut}` only,
  since it strips the DOCUMENT's extension off a title and nothing else;
  `exportCaptionsCommand`, `saveFrameCommand`'s `frameStem` base and
  `ExportSheetController.suggestedName` all read it. The recorded limit: a
  caption name carrying another of the app's own containers parts company
  with MCP — `chart.png` under SubRip is `chart.png.srt` in the panel and
  `chart.srt` over MCP, since `png` is replaceable in `destinationURL` and
  not a caption spelling — and widening the set would be the bare strip
  with a longer list.
  The controller half owns only the URL and the thread: the panel copies
  `CaptionExporter`'s house pattern (an accessory view rather than a second
  sheet, the format popup rewriting BOTH `allowedContentTypes` and the
  extension of `nameFieldStringValue` and reading the stem back off the
  PANEL), the project is read in the completion rather than captured when the
  panel opened (a panel is not a sheet, so the document stayed editable), and
  the render goes off-main. Its `validateSaveFrameAction` arm is load-bearing:
  the honest test is `duration > 0`, the one question `Exporter.renderFrame`
  refuses on, and a "has a video track" test would wrongly grey out a
  text-only timeline, which renders through `CompositionBuilder`'s placeholder
  track. Save Frame passes NO burn-in — it omits `renderFrame`'s `options`
  argument and takes the default — while the export sheet, `export` and
  `render_frame` all offer one; a grab is of the picture, not of a deliverable.
- `RecordingSetup.swift` · `RecordingResult.swift` · `ScreenRecorder.swift` ·
  `ScreenRecorder+Pause.swift` · `ScreenRecorder+Delegates.swift` ·
  `ScreenRecorder+Microphone.swift` · `ScreenRecorder+Finishing.swift` ·
  `ScreenRecorder+Content.swift` — screen recording's session (road map 3,
  R1a; pause and resume R2a). `RecordingSetup.swift` is the half a probe can call: `RecordingChoice`,
  `RecordingFiles` (decision 2's folder, the Screenshot app's date stem, ` (2)`
  on collision, ` (Microphone).m4a` beside the movie), `RecordingConfiguration.make`
  (PURE — every field read back by `tools/proof/recording_probe.py`, BGRA when
  Show Clicks is on because `showMouseClicks` draws under no other pixel
  format, pixels asked for by hand under Best because `captureResolution`
  scales nothing — R0 q4/q6), `RecordingGrant` (the two synchronous grant
  reads and the refusal sentences; nothing here ever prompts); the three
  result types — `StopReason`, `RecordingResult` over `RecordingSegment`s
  and `RecorderError` — are `RecordingResult.swift` since R2's toll, still
  values a probe can make, with `filesClause` the ONE spelling of "the
  files on disk" both doors' failure sentences use. `ScreenRecorder` is the
  machine `idle → arming → recording ⇄ paused → finishing → idle`, six
  files at the 400-line cap: arming and `stop()` in the base file; the
  `Segment` and `pause()` / `resume()` in `+Pause` — ScreenCaptureKit has
  no pause, so a pause REMOVES the segment's `SCRecordingOutput` (its file
  closes 5–25 ms later) and a resume ADDS a fresh one to a file named by
  its own start time while the stream keeps capturing (R0 q7: 57 fps
  through the pause, the did-start ~10 ms after the add), the microphone
  writer stopped and restarted per segment on its one running session;
  everything that ENDS a session in `+Finishing`, from `.recording` or
  `.paused`, `settle` probing segment by segment (a movie that will not
  probe fails the recording naming EVERY file, a microphone file that will
  not is that SEGMENT's `micProblem`); the three delegates in `+Delegates`,
  each finding ITS segment by the output's identity or the microphone
  file's URL, because a closed segment's did-finish can land after the
  resume — a did-finish on a closed segment is inert, a did-FAIL on any
  segment ends the recording, and a stream that stops while PAUSED lands
  what was recorded (every file is closed) rather than failing it; the
  static content/filter/geometry/error helpers
  in `+Content`, and the capture session's preparation (`prepareMicrophone`,
  paid during the countdown so the first 0.4 s of voice is in the file — lane
  A's one smoke run measured −421 ms without it), its adoption by `start` and
  the meter poll in `+Microphone`; every crossing member is internal for it,
  `state` included.
  **The microphone is a SECOND FILE** (R0 q2: `SCRecordingOutput` folds a
  microphone INTO the system track, inseparable and clipping): an
  `AVCaptureSession` + `AVCaptureAudioFileOutput` started FIRST in the same
  run-loop turn (`startRunning()` blocks main 100–180 ms, measured and
  accepted), then the stream; the recording output's did-start arrives 86–107 ms
  BEFORE `startCapture`'s completion in every measured run, `fileOutput(_:didStartRecordingTo:)`
  on a private queue and its did-finish on main, so the machine stamps each
  callback where it lands and hops it, and `micOffset` (screen did-start minus
  microphone did-start; positive = the picture began after the microphone) is
  measured per SEGMENT and never a constant — one smoke run gave −421 ms
  where R0's mean was +11 ms, and q7 gave −22 to +33 ms across resumes. Refusals complete SYNCHRONOUSLY before `start`
  returns; success completes later from the framework. `.userStopped` (the
  menu bar's indicator) and `.systemStoppedStream` (a display that slept) take
  the same finishing path and land through the session's `onFinish`, the ONE
  hook `start` takes — there is no settable hook on the recorder, because a
  panel Record refused `.busy` once erased the tool's and an external stop
  then reached nobody (the review's finding) — and a `stop()` in any state
  past idle JOINS the finishing under way rather than answering `.busy`,
  which used to drop a landing when a person's Stop followed the menu bar's
  by a second. `elapsed` is the SUM of the segments' spans, frozen while
  paused and 0 while arming; `pauses` is a COUNT of Pause presses carried
  on the session (a pause with no resume before the stop still counts);
  `pause()` while paused is `.alreadyPaused`, `resume()` while not is
  `.notPaused`, and a resume whose add refuses leaves the machine PAUSED
  with the stream still capturing. The rest of the review's recorder findings live here too: a
  microphone problem is `micProblem` on that SEGMENT of a `.success` and never the
  recording's failure (the movie is probed FIRST; the mic file is left on
  disk and named), `settle` runs once (`Session.settling`), a microphone
  that dies mid-recording sets `microphoneProblem` live and silences the
  meter while the picture records on, the arm ceiling has its own sentence
  (`.startTimedOut`), and a failure past `beginFinishing` names its files
  through `RecorderError.filesKept` (comma-joined lists with segments; the
  one-file sentence byte for byte R1's). The meter is the file output connection's `AVCaptureAudioChannel`
  levels, polled from the panel's timer (R0 q6c) — no queue, no sample buffer.
  Pitfalls: `NSObject` already has `finalize()`, so the recorder's is `settle()`;
  reading `outputURL` off a fresh `SCRecordingOutputConfiguration` TRAPS
  (non-optional in Swift, nil underneath) — `make` assigns it first;
  `SCShareableContent`'s completion form is `getExcludingDesktopWindows(_:onScreenWindowsOnly:completionHandler:)`
  / `getWithCompletionHandler(_:)`, the docs' `current` is `async`-only, and
  the error type is `SCStreamError.Code`, not `SCError`.
- `RecordingLanding.swift` · `RecordingLanding+Placing.swift` ·
  `RecordingLanding+Microphone.swift` · `ProjectDocument+Recording.swift` —
  where a finished recording goes (road map 3, R1b; segments R2b).
  `+Placing.swift` is the R2 fix wave's seam — `placeBackToBack`,
  `placeClip` (every `add_clip` READ BACK; a landing under its floor is
  discarded and re-added a frame up), `tooShortNote` (the core's own "no
  duration" test asked over the FFI, `ReelTime.snapToFrame`, never a Swift
  replica) — cut out when the read-backs took the base file to 466.
  **2026-09-19, kpgalligan/reelcut#22:** the core's threshold for that test
  moved. A media clip's length is now the file's snapped DOWN (spec §11), so a
  file with no WHOLE frame in it is an `Err` — "shorter than a frame" above
  zero, "no duration" at it — where a nearest snap used to round a 12 ms file
  up into a clip. `tooShortNote` follows it through
  `SilenceDetector.snapDownToFrame` (`SilenceDetector+Walls.swift`), the one
  Swift spelling of that snap and itself `rc_time_snap_to_frame` over the FFI
  composed with `Fps.frameDuration`, so the predicate still agrees with the
  core exactly at 24981/1000 as at 30 and the file's "nothing re-derives a
  frame here" rule holds. Its sentence to the person is unchanged, and the
  two Swift callers that READ a landed clip back rather than predict it
  needed nothing.
  `RecordingLanding` is a value
  type, `AudioNormalize`'s shape: a `RecordingResult` and a document in, an
  UNSCOPED op list and the ids the core will mint out — `next_id` read off a
  purely-applied PARENT handle before each op that mints, the two-try track
  rule run over a project that already HOLDS the media (`add_media` applied
  purely first; a path already in the list is the documented identity and the
  id is the entry's by trimmed path — `backgroundMedia(for:in:)`'s rule, not
  `addGeneratedClip`, whose probe cannot see a media the project lacks).
  Nothing in it commits: the panel commits through `document.performGroupedEdit`,
  the tool through `AgentServer.performGroupedEdit`, so each door keeps its
  own refusal posture. **The pictures land as a SEQUENCE on ONE track**
  (`addSequence`: all on the front track or all on a new one, each at the
  previous clip's END as the core reports it, read back after every apply —
  touching, or a sub-frame GAP at an inexact canvas rate such as decision
  3's 24981/1000, where the end is not a grid point and an `add_clip` at it
  would snap DOWN into a 1-tick overlap and a minted cross dissolve; never
  an overlap). Each segment's microphone lands on ONE new BACK track named
  "Microphone" at its picture's start minus ITS offset, FLOORED at the
  previous voice's end (read off the trial, never summed) and at 0; a start
  below the floor is the head TRIMMED, not a clip placed late (`add_clip`
  at the floor, `trim_start`, `move_clip`, one grouped edit, the head
  snapped to the canvas frame BEFORE the floor test so a sub-frame offset
  sends no trim — `slip` cannot do it, a clip covering its whole media has
  nothing to slip into), and the placed clip is read back so a refused op
  can never ride a committed list. Two things are left as MEDIA with a
  sentence in `Placement.notes` naming the file, which both doors append to
  their note: a voice wholly under the previous one (its snapped length no
  longer than its head — `trim_start` clamps at a frame from the end and
  the move would land inside the previous voice), and any file under a
  frame (R0 q7 measured a real 2 ms microphone file; `add_clip` refuses it
  as "no duration", which used to take every picture down). `Placement`'s
  four id lists have ONE entry per segment, nil where nothing was minted.
  `placement` throws by name while `isLiveEditing`
  ("A drag is in progress; the recording can be added when it ends.").
  `untitled(around:)`'s ORDER is a contract: `openUntitledDocumentAndDisplay(false)`
  (adds the document; no `addDocument`) → `adoptImported` (before anything
  reads `displayName`, which AppKit pins on FIRST read) → the import count
  `makeWindowControllers` would have made (`fileModificationDate = nil`,
  `countEditChange(.changeDone)`), run HERE and BEFORE the microphone's edit,
  with or without one, so that edit stacks a SECOND count and its undo leaves
  the first standing — counted the other way round, the review measured one
  ⌘Z reading CLEAN and ⌘W closing the recording's document without a prompt
  → the REMAINDER's one grouped edit through `remainderPlacement` —
  segments 2…n's pictures after clip 1's end on its track, no two-try rule,
  then every voice by the floor rule; with no clip 1 (a first picture the
  core refused) the voices land as media only — named by
  `remainderActionName(for:)`: `microphoneActionName` "Add Microphone" for
  one segment with a voice, NOT "Add Recording", because the step removes
  the voice and keeps the picture (the picture is already at 0 on track 1
  from `makeProject`, so `placement`'s `add_clip` would refuse against its
  own clip), and "Add Recording Segments" otherwise → `makeWindowControllers()` (its own import count
  now skipped by its guard; it still runs `generateCaches()`) →
  `showWindows()`; a throw closes the document it opened. `ProjectDocument.swift` took ONE internal method for it,
  `adoptImported(_:source:fps:)` — `readMediaFile`'s whole post-probe body,
  moved so a recording becomes a document by the one spelling File ▸ Open
  uses — and `makeProject` gained `fps: Fps? = nil`, replacing the canvas rate
  alone (decision 3). Limits: the trial applies each scoped op to the PARENT
  handle — the scoped apply itself — so `check_caps`/`check_nesting` on the
  merged parent refuse in the TRIAL exactly as at the commit (a document at
  `MAX_TRACKS` throws the core's "too many tracks" before any list is
  answered, inside a nest or out — `recording_probe.py` section 4, row 8), and
  because the picture and the microphone are ONE list, a microphone track the
  caps refuse takes the picture down with it — neither lands, and both doors
  name the files; `place: false` lands every media — n pictures and every
  microphone file — and no clip, and the offsets are not stored (a
  recording is ordinary media). With a microphone, ⌘Z (Undo Add Microphone)
  removes the voice, keeps the picture and leaves the document dirty; for a
  paused recording ⌘Z (Undo Add Recording Segments) removes segments 2…n and
  every voice and keeps the first picture; without either there is no undo
  step at all.
- `RecorderPanelController.swift` · `+Rows.swift` · `+Recording.swift` ·
  `+Pause.swift` · `+Landing.swift` · `+Picker.swift` · `RecorderStatusItem.swift` ·
  `AppDelegate+Recording.swift` — File ▸ New Recording… (⌥⌘N, road map 3's
  R1c; R2c's pause), the app's second `NSPanel` and its first `NSStatusItem`, six files
  since the fix wave cut the recording's end and its landing (`+Landing`)
  and the window picker (`+Picker`) out of `+Recording` at the 400-line cap
  and R2 added `+Pause` (`pauseRecording` / `resumeRecording`, reachable
  only from the status item). The panel is `.floating` and `.nonactivatingPanel`
  (Record and the countdown's Cancel without bringing Reelcut over the thing
  ABOUT to be recorded — during the recording the panel is off screen),
  `hidesOnDeactivate` false (`NSPanel` defaults it TRUE), `isExcludedFromWindowsMenu`,
  `isReleasedWhenClosed` false, ONE instance (`shared`, `ExportQueueWindowController`'s
  mould, because it outlives documents and must exist with none, and because
  probes instantiate `AppDelegate()`, which therefore stores nothing), NO
  window delegate (there is no document to answer `windowWillReturnUndoManager`
  with), and it persists its six choices under `ReelcutRecording…` keys
  (pinned in the harness) and not its frame. Rows: Source (the `NSScreen`s,
  then Window… → `SCContentSharingPicker`), Microphone (+ a `LevelMeterView(meter:)`
  bound to the recorder's OWN meter — a microphone published to `.shared`
  would light the timeline bar), System Audio, Show Clicks, Rate, Size, Record
  Into (`NSMenuItem`s carrying `recipeKey`, never `addItem(withTitle:)`).
  **The panel is the ONLY place `CGRequestScreenCaptureAccess()` and
  `AVCaptureDevice.requestAccess` are called** (decision 4, `Transcriber.canAsk`'s
  rule for two grants), both BEFORE the 3-2-1 countdown, so a countdown never
  ends in a prompt. **The panel orders OUT at `recordingDidStart` for EVERY
  source** (decision 7; `showWhenLanded` remembers whether it was visible)
  and the status item is the recording's whole chrome: three closures,
  `update(elapsed:paused:)`, the menu rebuilt in place ONLY when `paused`
  flips (Pause Recording · Stop Recording, then Resume Recording · Stop
  Recording), `menuTitles` / `title(elapsed:paused:)` / `tooltip` pure so a
  probe pins them, `freeze()` at the Stop so the mark does not flip back to
  the coral dot through the finish; `Phase.paused` reads Stop on the button
  and the pause glyph with the FROZEN time in the footnote. The panel comes
  back after the landing only through `revealIfNoted` — visible when the
  recording began, and a non-empty note: the landing's own sentences, a
  refused resume's (`resumeProblem`, kept as STATE, never composed from the
  label — the 30 Hz tick used to wipe it), the files the landing could not
  place. A clean recording leaves it away; ⌥⌘N shows it again. The landing goes
  through `RecordingLanding` and the document's own door, a document mid-drag
  retried from a half-second timer bounded at 40 tries, and on any failure the
  note names EVERY file, which is on disk whatever went wrong after it. Quit
  while recording is cancelled by `applicationShouldTerminate`'s first line,
  which opens the status item's MENU when the panel is hidden for a
  recording (a bare beep left a person who paused and forgot with nothing on
  screen) — a BACKSTOP asked after NSDocumentController's
  review, so the save sheet comes first and a target closed by the review
  lands as a new project through the `recipeKey` lookup. The welcome
  window's New Recording… button has its own selector to `show()` (it used
  to route through `newRecording`, whose first arm STOPS a running
  recording). Two limits, recorded: macOS hides status items that do not
  fit the menu bar, and Pause / Resume live nowhere else (Stop survives in
  the File menu); and "●" and "❚❚" differ in width, so the bar shifts at a
  pause. The retitle
  (Stop Recording) is in `AppDelegate.validateMenuItem` beside the agent-server
  branch; the delegate's items never reach `validateUserInterfaceItem`.
  `LevelMeterView.init(meter: LevelMeter = .shared)` and `AccentButton.init(…,
  \1 The review's chrome
  findings, closed: the panel asks for BOTH grants unconditionally on a press
  (decision 4 is that the TOOL never asks — a `canAsk` gate here told a person
  under `-AgentServerEnabled` to press the button they had just pressed and
  left a `notDetermined` microphone unrecoverable); a `.starting` attempt is
  numbered and bounded by `ScreenRecorder.armCeiling`; `land()` reads the
  commit's outcome off the project HANDLE (`performGroupedEdit` answers
  nothing, and a beep-and-return refusal used to be reported as added);
  Record Into freezes at the captured choice through a recording;
  `fitWindowToContent` constrains the grown card to its screen; the countdown
  and the 30 Hz tick run in `.common` run-loop modes so the status item's
  label moves under its own menu; `show()` beeps while any recording has
  the panel hidden; closing the panel during `.starting` abandons or stops
  the attempt as the countdown's Cancel does, so a note never lands in a
  panel nobody can see; Record over the Window… row with no filter refuses first; the
  tick shows `ScreenRecorder.microphoneProblem` live and a landed
  `micProblem` after; `prepareMicrophone` is paid when the countdown begins;
  and File ▸ Stop Recording routes a TOOL's recording to `ScreenRecorder.shared.stop()`
  instead of beeping at it. Pitfalls: `NSPopUpButton`
  has no `item(withTag:)` — it is `menu?.item(withTag:)`; `selectItem(withTag:)`
  answers a Bool to discard by name.
- `EditorViewController+PreviewQuality.swift` · `PreviewWindowController.swift`
  — road map 2's phase 8a and 8b, two ways of LOOKING at the picture. They are
  one lane because they share `Playback` and the View menu, and neither is an
  edit: **neither gets an MCP mirror, and neither may be given one** — the
  parity rule is for user-visible edits, and phase 7e's export queue is the
  precedent.
  **Preview quality** scales the render size of the PLAYER's video composition
  and nothing else. There is exactly ONE constructor of
  `AVMutableVideoComposition` in the app (`CompositionBuilder.build`), shared by
  the preview, both export passes and the offline frame — so rather than give it
  an argument, `Playback.previewComposition` `mutableCopy()`s what it was handed
  and overrides `renderSize` on the copy, which is `ExportWriter`'s move for
  `frameDuration` exactly. The export and `render_frame` paths are then not
  merely unchanged but UNREACHABLE from the setting, which is the only way that
  claim is worth anything. Three things about it will otherwise be
  rediscovered. **`AVPlayerItem.videoComposition` is a COPY property**, so
  mutating the retained composition after the item exists does nothing at all —
  the setter re-assigns, and `finishRebuild` re-applies, or a structural rebuild
  would silently return the preview to Full. **The render size must carry the
  canvas's EXACT aspect**, because `PreviewCanvasView` maps every drag handle
  through `AVPlayerLayer.videoRect`, which is the aspect of the BUFFER: measured,
  a 640 × 360 canvas rendered at 501 × 333 reports `videoRect` at 1.504505
  against the canvas's 1.777778 and moves every handle in the frame. So the size
  is `m · (w/g, h/g)` with `g = gcd(w, h)` and `m = ceil(g / divisor)` — the
  exact fraction when the divisor divides `g`, the next COARSER exact-aspect
  size when it does not, and Full for a canvas whose dimensions are coprime
  (1001 × 667). Odd dimensions come out of that rule and are fine — measured, a
  custom compositor and an `AVPlayerLayer` both take 501 × 333 and 304 × 171
  exactly — and nothing here may start rounding to even numbers;
  `ExportWriter.encodedSize` does that for an ENCODER's requirement this path
  has not got. And **the shadow passes do not get cheaper**:
  `MetalRenderer.shadowSilhouette` allocates its mask/blur pair at the CANVAS
  size, so a shadowed layer costs the same at every quality. Decoding is
  untouched too — `preferredMaximumResolution` stays the canvas size on purpose,
  since it is the decode ceiling and lowering it would change the frame by more
  than the resample the menu promises.
  **The preview window is one more `AVPlayerLayer` on the same player**
  (`Playback.makePreviewLayer`, the one door, so `player` stays private), and
  three of its decisions are measurements rather than taste.
  The archived AVFoundation Programming Guide says a second layer blanks the
  first; measured false on macOS 26.5.1 in both creation orders, with
  byte-identical `displayedPixelBuffer` checksums — and in that measurement
  `isReadyForDisplay` and `videoRect` were USELESS as instruments, both reading
  true and plausible for a layer with no superlayer at all.
  **The window is an `NSPanel` and must stay one**: a titled `NSWindow` becomes
  key AND main, and AppKit resolves a nil-target action through the MAIN
  window's chain — measured, with a plain window every ⌘-item whose action lives
  on `EditorViewController` (⌘E, ⌘T, ⌘0) resolves to NOTHING and validates
  disabled, while with a panel the editor stays main and every one of them
  keeps working with no forwarding code. The recorder's panel (road map 3)
  is the second `NSPanel`, non-activating on top of that, and takes NO
  delegate — see its row.
  **What a panel keeps alive is the items whose action is on the EDITOR's own
  responder chain, and ⌘Z / ⇧⌘Z are NOT those** — the sentence that used to
  name ⌘Z in that list was a measured falsehood, and the honest version is the
  more useful one. Edit ▸ Undo is the bare `Selector(("undo:"))`
  (`AppDelegate+Menus.swift`) resolved down the KEY window's chain, and
  `NSWindow` implements `undo:` itself (measured;
  `NSResponder` does not), so the search stops AT the panel and asks the
  panel's own manager — a second, empty one, with ⌘Z dead and Edit ▸ Undo
  greyed out, in the one window the forwarded keys below can edit from. So the
  controller is the panel's DELEGATE and
  `windowWillReturnUndoManager` hands back the document's; measured, the panel
  then shares the editor window's manager (which is the document's through the
  responder chain — the editor window has no delegate at all and
  `NSWindowController` implements `windowWillReturnUndoManager:` nowhere), ⌘Z
  from the panel undoes the document's last step and Edit ▸ Undo validates
  true. It steals nothing: the panel's delegate was nil and `NSWindowController`
  neither conforms to `NSWindowDelegate` nor implements one of its methods
  (all measured), and the editor window's `willCloseNotification` observer is a
  notification on the OTHER window. **The assignment is an ORDERING**, the
  second in that init: `NSWindow.undoManager` asks the delegate every time, but
  the first ask that falls through — no delegate, or a delegate answering
  nil — mints a manager of the window's own and keeps it for good, the delegate
  never consulted again. Measured both ways: stripping the delegate and putting
  it straight back leaves the panel on its own empty manager for the rest of
  the process, and a bare panel whose delegate answered nil once never came
  back either. So nothing may ask a panel for its undo manager before the
  delegate is on it, and `windowWillReturnUndoManager` may never answer nil as
  a "not right now". **`NSPanel.hidesOnDeactivate` defaults
  to true** (measured), which would make a second-display preview vanish
  whenever the person switched apps, so it is set false; full screen works on a
  panel with `.fullScreenPrimary` (measured — the style mask gains
  `.fullScreen`) although a panel cannot become main.
  **The document does NOT own it**, and that is the one place the road map's
  design was refused: `addWindowController` is tidy, and AppKit only asks a
  document about SAVING when the LAST window controller closes — measured with a
  dirty untitled `NSDocument`, one controller gets a save sheet on close and two
  get NO sheet, a destroyed editor window and a document left open behind a
  panel with nothing to edit in. So `EditorViewController` holds one stored
  `previewWindow` (a stored property being exactly what an extension cannot
  hold), and the controller closes ITSELF on the editor window's
  `willCloseNotification` rather than waiting to be deallocated, since a window
  whose controller has gone while it is still on screen is nobody's. It persists
  its FRAME, which `ExportQueueWindowController` deliberately does not — a
  preview window is opened to put it on a second display, and one that comes
  back mid-laptop-screen has failed at its one job — under ONE fixed autosave
  name, never per-document, or every project would mint another defaults key.
  Bare transport keys reach it by one `keyDown` handing the event to
  `EditorViewController.handleEditorKey`, which widened from `private` to
  internal for exactly that: a second window's responder chain does not contain
  the editor, and a second copy of the key map is the one thing that could make
  the two windows' transports disagree. **That map is not only transport** —
  `t` adds a text clip, `w`/`e` trim, `m` marks, `,`/`.` nudge, `i`/`o` write
  the range — which is why `handleEditorKey` grew the `attachedSheet` refusal
  beside its `NSText` one (see the sheet paragraph above); a second copy of the
  guard in this window would be the same drift the single key map exists to
  prevent.
  Sizes, so the next reader picks a cut rather than discovering a debt:
  `Playback.swift` is **600** with both of these in it (470 before phase 8,
  570 after it, and the paused-refresh fix of 2026-09-17 took the last thirty
  after trimming its own comments to fit), which is AT the ~600 cap, so the
  next line to land on it pays a cut; the two files above are 408 and 191, and the frozen
  `EditorViewController.swift` took 41 lines — one stored property, two
  validator-chain lines, `handleEditorKey`'s `attachedSheet` guard, and the
  paragraphs that argue them, which is the whole of phase 8's footprint in a
  frozen file. The guard is the one of the four that is not wiring for a
  feature file: it is a refusal the key map itself owes, put where the map is
  so both windows inherit it.
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
  filmstrip under a tint wash, waveform, grips, transition zone; since road
  map 5's E2 the strip also carries `video.motion`'s in/out wedges and a
  During glyph, drawn only for a clip `InspectorTab.hasPixels` accepts),
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
transcription, which is what `Transcriber.swift` uses (spec §11), and
screen recording did not either — every ScreenCaptureKit and capture call
`ScreenRecorder` needs has a completion-handler form;
`DispatchQueue` only at the documented seams
(the compositor's render queue, the composition rebuild, import, the export
progress timer, `Transcriber`'s serial work queue (phase 4) with
the `OperationQueue` the recogniser delivers its callbacks on, which is not
optional: `SFSpeechRecognizer.queue` defaults to the app's MAIN queue, and
the OFFLINE ONE-FRAME RENDER, which is two queues rather than one:
`EditorViewController+Eyedropper.swift`'s `eyedropperQueue` for a chroma pick
and — since phase 7a — `EditorViewController+SaveFrame.swift`'s
`frameGrabQueue` for Save Frame. `Exporter.renderFrame` opens asset tracks
and decodes, and its own doc says to call it off the main thread; neither
belongs on the compositor's build queue, where a grab would sit behind a
preview rebuild and a rebuild behind a grab. They are two objects because
each is `private` to its own file, and putting two unrelated commands in one
line would buy nothing — the seam is the SHAPE, and a third one-frame render
joins this entry rather than growing the list). The RECORDER (road map 3)
adds NO queue: ScreenCaptureKit and AVFoundation deliver their delegate
callbacks on private queues, `ScreenRecorder` stamps each with `Date()`
where it arrives and hops it to main through `DispatchQueue.main.async` —
`Transcriber.requestAuthorization`'s and `MediaImporter.probe`'s shape — so
every state transition runs on the main thread and needs no lock; the
microphone meter is polled from the panel's timer, and `record_screen`'s
waits are semaphores on the server thread, `import_media`'s shape. Its ONE
seam is `ScreenRecorder.shareableContent` (`ScreenRecorder+Content.swift`),
which issues `SCShareableContent.getExcludingDesktopWindows` from
`DispatchQueue.global(qos: .userInitiated)` and hops the answer to main — one
spelling for both doors, because on a locked console the framework held the
calling thread ~37 s before answering nothing, and a panel that made the call
on main froze the whole app for it.
**`import Synchronization` is allowed only inside `LevelMeter.swift`** — the
same shape of exception, and phase 5's. Its `publish` runs on AVPlayer's
audio render thread inside the tap's process callback, where a lock invites
priority inversion and `main.async` allocates; two relaxed atomic words are
what a wait-free publish costs. Nothing else earns it by asking, and every
other cross-thread value here is an `NSLock` or a main hop.
Colors/fonts/metrics come from `DS` tokens; shared controls
go in `Controls.swift`. Refusals beep (`NSSound.beep()`), errors never
crash. 4-space indent, ~100 columns.

## Three Motion files, 2026-09-20 — the E2 reader review's nits

`EditorViewController+Motion.swift` (151 → 176). N·1: the tag gate was
`guard tag < 0 || tag < count`, so ANY negative tag was read as None and a
tag of −7 CLEARED a clip's arrival; the validator's `kindAt` said None for it
too. None is now exactly `Self.motionNoneTag`, and `slotAt` answers
three-valued — a kind, None, or nothing at all for a tag no builder writes.
The commit's other change is a comment: the batch's "a mixed one lands" was
true of two of `applying`'s three answers and silent about the `Err` that
THROWS, which a clip already carrying an out-of-range value produces (R3·1).

`TimelineClipDrawing.swift` (450 → 454). N·2: the `during` glyph inferred the
label dot's place from `nameEnd`, which is exact today and only because the
dot branch is the last thing to move `nameEnd` before it. It now carries what
that branch decided, in a `dotLeft` of its own. **The fix moves no pixel**,
so its proof rows pass with the fix reverted by construction; what fails them
is the pinned mutant, the one `let right =` line replaced whole.

`EditorViewController+ZoomRegion.swift` (482 → 502). N·3: the zoom band's
second pill was computed once at arm time into a `let`, and `syncRegionMode`
keeps the mode armed while the same clip stays the target — so a `during`
added or cleared while armed left the pill stale. `regionNote(_:clip:)` is
now re-read in `syncRegionMode`, where every `refreshCanvas` passes, and
`note` is a `var` that redraws on change.

## Two frame-rate pair readers, 2026-09-20 — the last `intValue` after the gate

`designs/reelcut-remaining.md` §5's residue, and road map 7 §11's: the
argument gate (kpgalligan/reelcut#21) made every SCALAR argument exact, and
two readers of a `[numerator, denominator]` PAIR were left taking each half
through `NSNumber.intValue`.

**What they did before.** `fpsArg` (`AgentServer+Tracks.swift`, read only by
`set_canvas`) accepted an array of two whose halves were any `NSNumber` with
`intValue > 0`: `[29.97, 1]` APPLIED as 29 fps and `[30000, 1001.5]` as
`[30000, 1001]`, both in silence, and `[true, 1]` was 1 fps, since a JSON
boolean arrives as an `NSNumber` too. `[9223372036854775807, 1]` and
`[4294967296, 1]` reached the core and came back as serde's "expected u32",
which names no argument of the tool. Its BARE-number path was worse than
silent: it ended in `Int(number)`, and `set_canvas {fps: 1e30}` — finite,
positive, equal to its own `rounded()` — TRAPPED there. That is the
`Int(number)` trap, a live crash reachable from any caller, fixed here.
The trap is READ, not measured: it is Swift's documented `Int(Double)`
precondition applied to the removed `return Fps(num: Int(number), den: 1)`
(baseline `AgentServer+Tracks.swift:241`), and no run in this repo crashed
an instance on it — the mutant that puts `intValue` back SATURATES at
`Int64.max` instead of trapping, so it can only show the wrong-sentence
half of that row.
`mediaDescriptor` (`AgentServer+Media.swift`, read only by `add_media`) had
the same pair test spelled a second time, and its refusal named `fps` with
no object in front of it.

**What they do now.** `AgentServer+Arguments.swift` gained `rateTerm` and
`fpsPair` (458 → **502** lines, `wc -l`), beside `rangePair`, which they are
modelled on: a term is refused as
`"<path> must be a whole number from 1 to 4294967295, not <value>."`, the
bound being the core's own type (`Fps` is `[u32; 2]`, `core/src/time.rs:32`),
and a pair of the wrong length as
`"<path> must be [numerator, denominator], e.g. [30, 1] or [30000, 1001]."`
Each term carries its own path — `fps[0]`, `fps[1]`, `descriptor.fps[0]` —
so a caller is told WHICH half it was. A term is stricter than `intArg` on
purpose: a numeric STRING is refused, as `scopeArg` refuses one, because a
rate is two terms that must agree. A whole double is still a whole number
(`[30000.0, 1001.0]` is `[30000, 1001]`, `whole`'s rule). Both callers came
DOWN — `AgentServer+Tracks.swift` 243 → **240**, `AgentServer+Media.swift`
320 → **318** — because the two hand-spelled pair tests went. No schema,
catalog, declarations, core or FFI change: the published `items.minimum: 1`
was already true, and `AgentCatalog+Declarations.swift`'s row saying `fpsArg`
refuses a zero term BY NAME still holds, with the name now `fps[0]`.

**Who refuses first.** The app does, for every term. The core refuses a ZERO
term in its own sentence (`core/src/edit_canvas.rs:204`,
`core/src/edit_track.rs:438`) but a negative or above-`u32` term only as
serde invalid input, which names the op and not the argument — no sentence
worth surfacing, so the app answers all four cases the same way.

**Proof.** `tools/proof/op_argument_proof.py`'s term group, 17 rows, 116 →
**133/133**: the fractions, the zero, the negative, `Int64.max`, one past
u32, a string term, a JSON `true`, `[30]` and `[30, 1, 1]`, the bare `1e30`,
a row that the app still answers with `canvas.fps` unchanged after all of
them, the two controls that apply and read back, and the same through
`add_media`'s descriptor. Made to fail in a tree copy with `rateTerm`'s read
put back to `intValue` with only `> 0`: **126/133, exit 1**, seven rows red
and all of them in the new group. `op_catalog_proof.py` is 23/23 either way;
one row's sentence there moved from `fps must be` to `fps[0] must be`.

## Three caption files, 2026-09-20 — road map 6's C1 tolls

Road map 6 §5h's three size tolls, paid before any cloud-captions code, each
a pure move landed and gated alone (`designs/reelcut-roadmap-6.md` §10 has
the trees, the gates and the printed scores). What moved, and where:

**`Transcriber.swift` 934 → 553.** Three blocks left, whole and in their own
order, each to an `extension Transcriber` of its own:
`Transcriber+Languages.swift` (**172**) took the `Language` row, the two
caches and the lock behind them, `languages()`, `supportedLanguages()`,
`named`, `defaultLanguage(in:)` and `language(matching:in:)`;
`Transcriber+Jobs.swift` (**117**) took `jobs(for:in:urls:)`,
`contentLength(of:)` and `hasTranscribableClip(in:)`;
`Transcriber+Extract.swift` (**143**) took `extractSampleRate`,
`extractSettings` and `extractAudio(_:cancel:)`. Two members came out of
`private`: `contentLength`, which no compiler error demanded and §5h asks for
by name, and `extractAudio`, which one did, `transcribe` having stayed
behind. Everything else stayed, the instance stored properties (`work`,
`delivery`, `sink`, `recognizer`) because an extension cannot hold one, and
`Job`, `Outcome`, `CancelToken`, `TranscribeError`, Authorization, Running,
Recognition and `TaskSink` because nothing asked them to move.
`tools/proof/cloud_spike/extract.swift`'s comment now names
`Transcriber+Extract.swift` as the file its settings were copied from.

**`AgentCatalog+Files.swift` 601 → 487.** The three caption rows —
`import_captions` from the Media group, `transcribe` and `export_captions`
with their own `// MARK: Captions` note and the hoisted
`captionFormatNames` / `captionFormatProperty` only they read — are
`AgentCatalog+Captions.swift`'s (**165**), in two functions,
`captionImportTools()` and `captionTools()`. They are SPLICED back at the
two points they left rather than appended, because the catalog's order is a
contract: `fileTools` builds `var rows` and reopens the array around
`rows += captionImportTools()` after `import_media` and
`rows += captionTools()` after `remove_media`, which is
`AgentCatalog+Audio.swift`'s shape exactly. Nothing widened — they are
members of the same internal extension. `AgentCatalog.swift` 524 → **525**:
one line of doc, since the eight app-state file tools it lists are still
`fileTools`'s but three of them are now built next door.

**`TranscribeSheetController.swift` 505 → 380.** `finish`, `summary`,
`truncationText`, `viewDidDisappear` and the menu-command
`extension EditorViewController` are `TranscribeSheetController+Commit.swift`'s
(**145**). `override func viewDidDisappear()` is legal in an extension
because it is an Objective-C method, the way `extension TimelineView`
overrides `NSView`'s in `MediaRowView.swift`. Ten members came out of
`private`, every one of them because the compiler said so, asked twice: the
nine stored properties the two moved methods read (`document`, `snapshot`,
`token`, `bar`, `statusLabel`, `detailLabel`, `stopButton`, `didStart`,
`didFinish`) and then `finish` itself, which `begin` still calls from the
file it left. `summary` and `truncationText` are still `private`: only
`finish` calls them and it moved with them. The FROZEN
`EditorViewController.swift` is **1123, unchanged to the line** — two
comments naming the file the command's body lives at the foot of.

## Six caption files, 2026-09-20 — road map 6's C1 parts

What road map 6's c1-parts pipeline did to files that already existed. Its
own record — the seven new files, every measured number and the mutants — is
`designs/reelcut-roadmap-6.md` §10.9.

**`Transcriber.swift` 553 → 584.** Two changes and nothing else.
`Job` gained `media: UInt32`, second after `clip`, because the on-device
engine extracts each clip's own source window and the cloud engine uploads a
MEDIA once and derives every clip on it from one transcript — so the grouping
key and the cache file's name are the media id (R6-3). `CancelToken` gained a
`URLSessionTask?` beside its `SFSpeechRecognitionTask?`, under the same lock,
read out and cancelled OUTSIDE it, with `attach` as an OVERLOAD rather than a
second name so a caller that holds a token cancels it the one way whatever is
running underneath. `release()` clears both. The two slots are independent:
only one engine runs at a time, and a token that had to be told which would
be a token every caller had to tell. No widening: `Job`'s one construction
site and `CancelToken`'s four callers are all internal already.

**`Transcriber+Jobs.swift` 117 → 117.** One line: `media: media` at the one
`Job(` site, taken from the `case .media` the function already bound.

**`Transcriber+Extract.swift` 143 → 305, and its header rewritten.** It is no
longer "a pure move out of `Transcriber.swift`" and the doc no longer says it
is. The old body became `static func extractAudio(url:name:range:to:cancel:
progress:)`, verbatim, with exactly two things lifted into arguments — the
destination and the range — and `range.start` written where the old code
wrote `CompositionBuilder.time(job.sourceIn)`; the instance
`extractAudio(_:cancel:)` keeps its signature and its doc, computes the same
destination and the same range as before, and calls it. That is a claim, and
`cloud_captions_probe.py`'s row W is the instrument: the same job extracted
by `git archive 515e6a80 app/Sources`'s own code and by today's, five decodes
a side, indistinguishable. Beside it landed `UploadFormat`, `Upload`,
`wholeAsset`, `writeFLAC(fromWAV:to:cancel:)` and `extractUpload`. Two things
are worth knowing about them: `wholeAsset` is `CMTimeRange(start: .zero,
duration: .positiveInfinity)` rather than a measured duration because
`AVAsset.duration` is a deprecated getter whose replacement is `async` and
`AVAssetReader` clamps a range that runs past the asset anyway (the probe's
row Q measures the two as indistinguishable); and `writeFLAC` streams in
16 384-frame buffers rather than decoding the file, because a cloud run's
input is a whole media and ten hours of 16 kHz mono is 1.1 GB of PCM.

**`CaptionLayout.swift` 444 → 473.** `CaptionCues.Word` gained
`speaker: String?`, defaulting to nil in the initialiser, so every existing
call site and the harness's `cues` mode are the code they were; and `build`
gained the fifth rule, twelve lines in the loop it already had. The rule is
tested BEFORE placement and not inside the placement test: a speaker change
on a word that happened to fit the line and the six seconds would otherwise
be placed and the rule would never fire, which is exactly the case row 19
measures. It flushes and opens a new cue on the same word, so it is one
break and never an empty cue. Three sentences of the file's header and the
`CaptionCues` doc that said "the four cue rules" say five.

**`MediaCacheFiles.swift` 555 → 556.** One line, `transcriptsKind`, beside
`speechKind`. The file was measured at 555 rather than the 550 road map 6
§5b quoted; it is not on `reelcut-remaining.md` §3's ledger. The kind
constant sits here rather than in `MediaTranscript.swift` because a
notification's `userInfo` is where the four are compared, and the paths sit
in `MediaTranscript.swift` because that is where a reader looks for the
mapping. §5b said the opposite about the kind and was revised, dated, to say
what 5h had said all along.

**`tools/proof/harness/main.swift` 881 → 901.** The `cues` mode's `Request`
gained an optional `speaker` and the header's `words.json` description says
so. The `CaptionCues.Word(` call is DUPLICATED under
`#if !HARNESS_REFERENCE_BUILD`, with the three-argument form in the `#else`,
because `phase5_chrome.py` and `recording_probe.py` compile this file against
OLDER trees under that flag and a bare `speaker:` would break both. A fixture
written before the rule existed produces byte-identical cues, which the probe
proves by `cmp` and which twenty of `phase4_chrome.py`'s own cue files prove
against a harness built from the baseline tree.

## Nine caption files, 2026-09-20 — road map 6's C1 run

The pipeline that gave `CloudTranscriber.transcribe` a body, put the cloud
engine behind `transcribe {engine: "assemblyai"}`, and clamped the caption
path's two `Double → Ticks` conversions (spec §11's R6-10 and R6-11). The
record, every number and every mutant is `designs/reelcut-roadmap-6.md`
§10.10.

**`CloudTranscriber.swift` 102 → 296.** The placeholder that threw "the
AssemblyAI engine is not built yet" became road map 6 §5a's run: `Report`
(what the `Outcome` has no room for), the janitor first, the jobs grouped by
MEDIA in first-clip order, each media classified cached / held / to upload
before any work starts so the progress shares are known, then the per-job
derivation through `MediaTranscript.words` and `CaptionCues.build`. `run` is
untouched. The two closing throws are `Transcriber.transcribe`'s own, for its
own reason. The file is 104 under the 400-line cap on a new file because the
janitor and the round trip went next door.

**`CloudTranscriber+Media.swift` — new, 183.** `retryDeletes` and `fetch`.
It is a second file rather than more of the first because
`CloudTranscriber.swift` holds the run's SHAPE and a reader following that
shape does not need the cache header's twelve fields or the order of the five
calls in front of them. `fetch`'s `progress` had to be `@escaping`: the two
closures it hands to `extractUpload` and to `upload` outlive the call, and
`make typecheck` does not say so — it stops before SILGen, and the probe's
own build is what caught it.

**`CloudProgress.swift` — new, 141.** The progress arithmetic as a value with
no run in it, so `cloud_captions_probe.py`'s `run` section can drive it over
a table and the sheet that shows it in c1-chrome inherits something measured.
`fraction` takes the two ends of a phase EXACTLY rather than computing them —
`0.65 + (0.95 − 0.65) × 1` is 0.9500000000000001 in binary floating point,
and "holds at 0.95" is a claim a proof compares against the constant.

**`AgentServer+CloudCaptions.swift` — new, 247.** `transcriptionEngine`,
`refuseCloudOnlyArguments`, `cloudTranscription` and the two private helpers
that normalise the language and the vocabulary. A file of its own because the
on-device path's refusals are a story about a GRANT and a downloaded MODEL
and the cloud path's are a story about a CREDENTIAL and somebody else's
service; interleaved they read as one tangle.

**`AgentServer+Captions.swift` 409 → 439.** Thirty lines: the `switch` on
`transcriptionEngine(a)`, the Apple arm's existing body moved inside it
unchanged, and `fields` built per arm instead of at the join.
`transcriptionScope` and `TranscriptionScope` stayed `private` — the cloud
arm is handed `jobs` and `frame` by value. 161 under the ~600 cap.

**`AgentCatalog+Captions.swift` 165 → 215.** `transcribe`'s entry rewritten:
one paragraph per engine with the consent sentence in the cloud one, four new
properties, and a comment naming File ▸ Generate Captions… and saying that
the sheet's Engine popup is c1-chrome's.

**`Transcriber+Jobs.swift` 117 → 178, and it is no longer a pure move.**
`maxSourceTicks` (1e15), `placed(offset:in:)` — the ONE door both caption
mappings convert through — the bound on `Job.sourceIn`, and the clamp inside
`contentLength`. Its header says so, and `contentLength`'s doc stops saying
it saturates "the same way" as the core: the core's cast tops out at
`i64::MAX` and this one at `maxSourceTicks`, because Swift SUMS this number
where the core does not. A product that overflows to `+infinity` is the BOUND
and not the fallback — "more source than there can be" is the honest answer
where the clip's own duration would be a number pulled out of the air.

**`MediaTranscript.swift` 379 → 383.** `project(_:in:)` lost its `limit`
argument and ends in `Transcriber.placed`; `words` lost the `let limit` line
that fed it. The two lines the probe's `mapping-no-in` and `no-speed-guard`
mutants patch are byte-identical to what they were, deliberately.
`:317`'s `job.sourceIn + job.sourceLength` is NOT edited: both terms are now
bounded to 1e15, so the sum cannot overflow. (It is `:333` after c1-chrome
added `sourceTicks(milliseconds:)` above it, and still not edited.)

**`Transcriber.swift` 584 → 583.** `project(_:in:)` is three lines instead of
four and ends in `placed` like its twin. Nothing else moved, and the file
came back one line UNDER where it was.

**`tools/proof/assemblyai_fake.py` 489 → 501**, one scenario key
(`transcript_error_first`) and the submission index it needs.
**`tools/proof/cloud_captions_probe.py` 2638 → 3280**, 196 → 283 rows: the
mapping mode's `projected` and its near-`Int64.max` job, the whole `jobs`
section (one child process per speed, because an unclamped `Ticks(_:)` traps
and a trap has to be that speed's own failure), the whole `run` section, two
replaced S rows and two new mutants. **`tools/proof/cloud_captions_proof.py`
— new, 1479**, 115 rows over three instances.

## Thirteen caption files, 2026-09-20 — road map 6's C1 chrome

Road map 6 §10.11 is the pipeline's record and has the scores; this is what
happened to each FILE. Three are new, ten changed, and `AppDelegate.swift`
was not touched at all.

**`CloudEstimate.swift` — new, 328.** `AssemblyAIRates` (§8's two dated
constants) and `CloudEstimate`, which is PURE except for one member. The
shape worth remembering is the split: `Facts` is what the DISK knows about a
media (its `CacheStamp` as it is now, its marker, whether the transcript
reads back, whether a delete is owed), `facts(jobs:media:cacheDirectory:)` is
the only thing that opens a file, and `fate`, `describe`, `reasons`, `money`
and `dollars` are functions of those facts alone. That is what lets the sheet
recompute its whole readout on every keystroke in the Vocabulary field
without stat-ing two files per media, and it is why every arm of `fate` is
reachable from a probe with no cache directory at all.

**Its classification is deliberately a SECOND one.** `CloudTranscriber.transcribe`
already sorts media into cached / held / to-upload, and merging the two would
be the obvious tidy. It was not done: one answers what a run WOULD do and the
other what it DID, they are read by different people at different times, and
`cloud_captions_probe.py`'s `chrome` section drives an estimate and a real
run over two rounds and compares them — so the day they drift is a scored
failure rather than a refactor nobody checked.

**`SettingsWindowController.swift` — new, 376**, with
`extension AppDelegate { showSettings }` at its foot. `AppDelegate.swift` is
untouched because of that foot, which is `CaptionImporter.swift`'s
precedent. Two decisions in it are worth carrying: the store is injected as a
FACTORY (`() -> any SecretStore`), not a value, because
`AssemblyAIConfiguration.store()` is built from the argument domain and the
offscreen harness has to be able to replace it wholesale — `Harness.pinDefaults`
REPLACES that domain with `setVolatileDomain`, so after it `store()` is the
person's real `FileStore` and this window's Save is exactly the code that
would write into it; and `sync()` never writes `keyField.stringValue`, only
`placeholderString`, so the key cannot be copied out of the field, read by
accessibility or photographed, and the mask is FIXED length because one as
long as the key leaks its length.

**`TranscribeSheetController+Cloud.swift` — new, 313.** The AssemblyAI half
of the card. `runRequest()` is the piece to know: ONE function from the
controls to a `RunRequest`, and the estimate, the notes, the button rule and
`beginCloud` all read it, so the summary can never describe a different
request from the one Generate sends.

**`TranscribeSheetController.swift` 380 → 540**, of the ~600 cap that toll 3
bought. Eleven members widened from `private` to internal for the new file
(`languages`, `mediaURLs`, `languagePopup`, `summaryLabel`, `noteLabel`,
`hintLabel`, `scope`, `jobs(in:)`, `startButton`, `showProgress()`,
`progressed(_:_:)`); `language` and `isBlocked` stayed private ON PURPOSE,
because the cloud half must not be able to read either. **`refresh`,
`noteText` and `startClicked` dispatch on `engine` as their FIRST
statement**, and the `.apple` arms are the code they were, moved under the
dispatch and not rewritten — `phase4_proof.py`'s exact-sentence rows read
those strings. `makeSheetView` is called with `hint: nil` and the sheet owns
its own `hintLabel`, first in the content, because the sentence changes with
the popup and the builder's hint is a constructor argument.

**`TranscribeSheetController+Commit.swift` 145 → 215.** `cloudReportLines`,
and `finish` calls it in BOTH arms — a run that failed can still have
uploaded one media and still owe a delete for it, and a card that printed
only the error would lose the one record a person has of that. The owed list
is the TOOL's own rule, read across: once per media id, because a media can
be in `janitorFailed` and in `uploaded` with `remoteDeleted` false at the
same time.

**`MediaTranscript.swift` 383 → 399**, and it went to **411** on the way. The
addition is `maxWordMilliseconds` and `sourceTicks(milliseconds:)` (R6-10's
extension: the one INTEGER multiply on the caption path, clamped in `Int`
before the `× 600`), and the doc comment was cut twice until the file fitted
under its own 400-line cap. That is what the cap is for. `project(_:in:)` is
byte-identical, because the `mapping-no-in` and `no-speed-guard` mutants aim
at its two lines.

**`AssemblyAITranscript.swift` 374 → 399** and
**`AgentServer+CloudCaptions.swift` 247 → 243**: `keyterms` moved out of the
tool and into `extension TranscriptOptions`, doc and body verbatim, so the
sheet's Vocabulary field and the tool's `vocabulary` argument cap and
de-duplicate through ONE function. A hygiene row asserts `func keyterms(`
occurs once in `app/Sources`. The tool's file also gained R6-12's position in
its header — that neither the key nor the REGION is a tool's to read or
write, and why `transcribe`'s result names no region.

**`CloudTranscriber.swift` 296 → 317.** `verify(completion:)` on the `work`
queue, capturing the CLIENT and not `self`; and the per-media closing publish
now carries `CloudProgress.detail(.saving, file:)` instead of an empty string
(c1-run's review, nit 1 — it would have blanked the sheet's detail label
between media).

**`AppDelegate+Menus.swift` 544 → 549.** One item and one separator.

**`tools/proof/harness/main.swift` 901 → 954** — two pinned defaults and a
`settings` mode beside `welcome`, which builds its OWN controller with a
`MemoryStore` and an EMPTY environment and never touches `.shared` or
`store()`. A hygiene row reads the harness's CODE (not its comments) for
both names. **`tools/proof/cloud_captions_probe.py` 3280 → 4753**, 283 → 469
rows: the `estimate` section, the `chrome` section, mapping rows for R6-10's
extension with one child process per millisecond, a run row, hygiene rows
and, from the review pass, six more `chrome` rows — the summary tooltip on
both sides of the Engine switch, a region changed under an open card, one
store per `sync`, and what Stop actually DID to a started run. Eight
mutants: five against the full 463 and three (`stale-tooltip`,
`stale-region-hint`, `two-stores-per-sync`) at 75/76 over `--only chrome`.
**`tools/proof/cloud_captions_proof.py` 1479 → 1494** — the same 115 rows,
with every instance now launched `-ReelcutCaptionEngine assemblyai` and one
more mutant (`agent-reads-remembered-engine`), which is what turns row 8
from a row that could not fail into one that can.
