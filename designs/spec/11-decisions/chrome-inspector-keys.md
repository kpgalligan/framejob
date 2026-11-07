# Spec §11 — decisions: Chrome, the clip inspector and keys (the sharp pass, road map 9, #35)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **SH-1 — `StickerButton` keeps its pill** (the sharp pass, 2026-09-23).
  The sharp handoff deletes it "once it has no callers"; it has callers in
  12 files (`Sheets`, `Welcome`, `Settings`, `ExportQueue`,
  `Relink`, `ReverseRenderer`, `Silence`, `Transcribe`, `ExportProgress`,
  `ExportSheet`, `Consolidate`, `RecorderPanel`) and `recording_probe.py`
  §6 measures its 2 pt shadow margins against a reference build. Squaring
  it (Rasterize's shape) or moving its callers is a phase of its own; it is
  the one place `Controls.swift` lags Rasterize. Superseded by SH-4 (#100,
  2026-09-30).
- **SH-2 — `BlockSliderCell.drawBar` is forked from Rasterize's copy** (the
  sharp pass, 2026-09-23; the user's call: the handoff is a guideline, and a
  working Frame Job wins). Rasterize's cell dims its two fills with
  `withAlphaComponent(isEnabled ? 1 : 0.42)`. On a dynamic, translucent
  system colour that REPLACES the colour's own alpha rather than scaling it,
  so the enabled track (`DS.border`, `.separatorColor`) painted OPAQUE — the
  same solid white (dark) or black (light) as the `DS.textStrong` knob, and
  the knob vanished into the track on its right (measured in the harness:
  one 115 px run of (255, 255, 255) from the knob to the track's end).
  Frame Job's cell dims through the context's alpha instead and fills with
  `.sourceOver`, so the track is the quiet grey the handoff asks for
  (measured (52, 52, 52) dark over the bar's (30, 30, 30), (230, 230, 230)
  light; the handoff's `#3a3a3a`) and the knob reads against it. It is the
  ONE deliberate divergence in the synced chrome files; Rasterize's copy
  very likely has the same defect, owed there.
- **CI-1 — The selected action is the SIXTH piece of view state** (road map
  9 §1, the clip inspector redesign's phase 1). `ProjectDocument.selectedAction`
  is nil or ONE action of the SINGLE selected clip, and the document's
  `selectAction(_:)` enforces it: an id that is not `singleSelectedClip`'s is
  stored as nil, so a multi-selection never holds one. Like the other five it
  is not undoable, not persisted and has no MCP mirror — agents address
  actions by id through `add_action` / `set_action` / `set_action_end` /
  `remove_action`, which is the whole capability. It is AUTO-selected when
  the playhead ENTERS a span by moving (`lastInsideAction` records the span
  it was last inside, so only a change counts), and never by an edit: an
  edit, an undo or a redo under a stationary playhead enters nothing,
  because `clampViewState` re-reads `lastInsideAction` BEFORE its playhead
  write. It is KEPT when the playhead leaves the span, and cleared by esc,
  by the lane's Clip chip and by any change of the clip selection (which
  then auto-selects the new clip's action under the playhead, if any).
- **CI-2 — The editing target is the selected action, not the playhead.**
  With an action selected every animatable field shows AND writes its END
  state: `InspectorBinding.action(_:)` answers the selected action, and
  `evaluated(_:)` reads `clip_state` at `clip.start + action.endTime`,
  where the core has merged every action ending at or before that tick and
  none that starts there has progressed — keyed keys at their end values,
  unkeyed ones at what is held. The playhead no longer decides where an
  edit lands, so fields do not move with it. Selecting an action parks the
  playhead at its end (one frame short when the action ends with the clip,
  whose end tick composes nothing), so the preview shows the state the
  fields show.
- **CI-3 — Pan, mono, compressor, noise reduction, duck and keep-pitch go
  to the BASE props whatever is selected.** The app routes them there
  (`InspectorBinding.structural(audio:for:)`, beside
  `structural(video:for:)`'s motion and list-length rule); the core's door
  is unchanged and `set_action_end` still takes them from an agent. They
  are switches or effects an action cannot usefully ramp, and a write
  that disappeared into an end patch was the redesign's P7. Narrowed by
  AU-88: inside an action pan, mono, the compressor and noise reduction go
  to the end with the rest of the tap's keys; duck and keep-pitch stay.
- **CI-4 — Mint is the action ink, and nothing else uses it.**
  `DS.action` (dark `#5CD6B0`, light `#1E8F6E`) with `DS.actionInk`
  (`#101010`) on a solid band. The Clip tab's pinned action lane REPLACES
  the Actions section, and actions are numbered by TIME order (start, then
  id), not by creation — the timeline's bands, the lane and "editing N"
  all count the same way (`ActionBands.ordered`).
- **CI-5 — The Clip tab is sub-tabs over a pinned block** (road map 9 §3,
  the clip inspector redesign's phase 2). Above the scroll view, and not in
  it, sits one block — the selection header, the action lane and a strip of
  sub-tabs — OWNED by the pane (`InspectorPane.pinnedBlock`, built by
  `makeHeader()` on every rebuild and never stacked) and HOSTED by the
  controller in a container between the tab strip and the scroll view. The
  tabs follow the selection's kinds: Text for an all-text selection, Shape
  for an all-shape one, Picture when a selected clip draws pixels, Sound
  when one has audio, and Clip ALWAYS, last; Text and Shape come first. The
  default is the first tab, so a text clip opens on Text. A tab picked by
  hand is KEPT while an action is selected or changed and is FORGOTTEN by
  the controller whenever the selection's ids change, whatever tab is
  showing (`refresh(isLive:)`'s `ids != lastSelection` block calls
  `ClipPane.forgetSubTab()`), so A → B → A comes back on the default. Each
  tab lists its own sections (spec §4.3), and the open rule applies per
  tab: on a tab with no expanded section the first one with no stored
  preference opens. Section ids — the `UserDefaults` keys — are unchanged;
  two titles are renamed, `video.motion` to *Motion presets* and
  `text.animation` to *Reveal*. The handoff's "8/10 padding" is read as 8 pt
  top and bottom and 10 pt sides (`InspectorMetrics.inset`).
  **Amended by GR-2** (grading GR2): a **Color**
  tab sits after Picture, shown when the selection has clips that draw and
  every selected clip has source pixels (media, image, still), holding Light
  and the Color section moved from Picture; Picture stays the default.
- **CI-6 — `◆N` counts KEYS, and the slider knob is the block.** In this
  phase a sub-tab's `◆N` badge counts the KEYS of the selected action's end
  patch that the tab's sections write (Picture: `video` minus `motion`;
  Clip: `motion`; Sound: `audio`; Text: `text`; Shape: none), drawn only for
  N > 0 in `DS.action`. Phase 3's row marks may re-count to ROWS and must say
  so where they do. The inspector slider's knob is the 7 × 11 pt block of
  `BlockSliderCell.drawKnob` in `DS.textStrong` at full alpha, its rect snapped to device
  pixels (`backingAlignedRect`, nearest) with the accent fill running to the
  snapped knob's centre; the accent fill is kept until phase 3's keyed
  segment replaces it.
  **Amended 2026-10-07, by issue batch B87 (#239, G-34 (l))**: Graphic
  counts the keys of the end's `graphic.props`, a key its module no longer
  declares included, so the tab's and the Properties section's `◆N` agree.
  **Amended by GR-2** (grading GR2): Color counts
  `color` (1 when the end holds `video.color`), and Picture counts `video`
  minus `motion` and `color`.
  **Amended by SR-21** (speed ramps SR5): Clip also counts `speed` (1 when the
  end names a rate), the Speed section's Rate.
- **CI-7 — Every inspector row carries the 14 pt mark gutter, and the label
  stays 76** (road map 9 §5, the clip inspector redesign's phase 3a). The
  gutter is the FIRST view of every `inspectorRow`, blank when its mark is
  none, so the label column lines up down the whole inspector — the
  Document and Media tabs included, where no row can be marked. It is
  followed by no stack spacing, so every control column moves right by
  exactly `InspectorMetrics.markGutter` = 14 pt (a labelled row's controls
  from 82 to 96 pt, an unlabelled row's from 0 to 14). The label field
  stays 76 pt, not the handoff's 64: "Remove noise" measures 64.1 pt in
  `DS.sans(11)`, "Corner radius" 62.1 and "Out Duration" 59.3, and the
  label truncates at its tail. A row's mark is derived from the ops it
  WRITES (`writes:`, the typed builders' own `ops(read())`) and the ones it
  FOLLOWS (`follows:`): none when both are empty, with or without an action;
  with an action selected ⊘ when it writes and none of its writes reach
  `set_action_end`, ◆ (or ◆ with "at end" for a discrete control) when it
  writes a key the selected action's end patch holds, ○ when it follows one,
  ◇ when another action keys it; with none selected ◇ when any action keys
  it. ⊘'s ink is `DS.textFaint`; no `DS` token is new. The header's `◆N`
  counts KEYS, CI-6's count, so a section's `◆N` and its sub-tab's agree.
- **CI-8 — A section the selected action keys opens once per selection,
  and a person's close sticks** (phase 3a). When an action is selected the
  sections of the showing sub-tab that write one of its keys are revealed
  (`KeyedReveal`) — expanded WITHOUT writing the collapsed preference, so
  the panel goes back to the person's own layout when the action is left.
  The reveal is remembered per action selection: a rebuild under the same
  action (a filter added, a family changed) re-reveals the same sections, a
  sub-tab first shown later adds its own, a header click that closes one
  drops it for the rest of that selection, and selecting another action
  (or the same one again after leaving it) starts over.
- **CI-9 — Reset shows only while a section differs from its default, and
  with an action selected the same slot reads Clear** (road map 9 §7, the
  clip inspector redesign's phase 3b). A row's DEFAULT is its own `read`
  run in `InspectorBinding.ReadMode.defaults`, where the four props readers
  answer `VideoProps.identity`, `AudioProps()`, `TextProps()` and
  `ShapeProps()` without the FFI; a section differs when its explicit
  `differs` says so, else when any of its rows' defaults differs. **A
  section's `differs` is false right after its own `reset` runs**: the
  Reset writes every key its `differs` reads, or `differs` reads only what
  the Reset writes — measured for every derived section, and made true for
  Shape (whose Reset writes only `radius`) and Stroke (whose Reset writes
  `StrokeProps()`, where the default is no stroke) by an explicit
  `differs`; the existing Reset closures are unchanged. A section with a
  row that animates, while an action is selected, shows **Clear** instead,
  and only while the action keys one of its rows: it removes those keys
  from the action's end patch through `set_action_end` nulls, so the values
  fall back to what was held (tooltip "Remove this section from action
  N"). A section none of whose rows animates (Document, Shape, a ⊘-only
  section) keeps the Reset arm, since its edits go to the clip. Rows whose
  read bypasses the props (Rate, In/Out, Transition, Reverse, Canvas,
  Appearance, a list entry's kind) carry no row default, so no "Reset to
  default" item and nothing toward `differs`. A keyed row's ◆ becomes a ×
  on hover — the gutter's own glyph, not the handoff's right-end button,
  because an arranged view shown on hover would shrink a slider under the
  pointer and an overlay would cover a field's tail — and every row has a
  right-click menu: "Remove from action N" (keyed), "Go to action M" (◇),
  then "Set end value to default" (an action selected and the row animates)
  or "Reset to default", disabled when the row is already at its default.
  The summary's middle tier ("differs") is `DS.textMuted`, not the
  handoff's `--text-body`: no `DS` token is new.
- **CI-10 — A person's refusal is shown, in the core's own sentence, at the
  inspector's foot** (phase 3b). `ProjectDocument.applyEdit` still beeps
  for both non-applied arms and makes no undo step for either (§5.5); on a
  `.refused` it also posts `projectDocumentDidRefuse`, and the editor puts
  "Refused: " and the rule's sentence VERBATIM in a strip under the
  inspector's scroll view. The strip lasts until the project changes — the
  next applied edit, an undo, a redo or a scope change — or it is clicked;
  a playhead or selection move leaves it. It is not the handoff's "rule
  plus what to do" phrasing and has no timer: the sentence is the core's
  (app/CLAUDE.md "A refusal is the CORE's sentence"). Agent edits never
  reach it (`AgentServer.performGroupedEdit` answers its refusal before any
  document call) and a live drag's refused tick stays swallowed.
- **CI-11 — A band is dragged: its body moves the action, its outer 5 pt
  resize it, in the timeline's lane and the Clip tab's lane alike** (road
  map 9 §9, the clip inspector redesign's phase 4). A band 15 pt wide or
  less is all body. One gesture is ONE undo step through the live trio
  (`onLiveBegin/Update/End` on the timeline, `binding.liveBegin/liveUpdate/
  liveEnd` in the lane), one `set_action` per tick carrying start AND
  duration, named "Move Action" or "Resize Action". Times snap to the frame
  grid only — no candidate snapping and no guide (the handoff leaves
  band-to-playhead snapping uncovered) — and the minimum is ONE frame, the
  core's own, not the handoff's two. The session (`ActionDragSession`)
  clamps to the two walls the core's refusals name — `edit_action.rs`
  `overlapping_action`'s `start < o.end && o.start < end` and the clip's
  length — so the band stops where the core would refuse (a zero-length
  action at the band's start or end would be a wall by the same test).
  **A zero-length action is never dragged**: in either lane a press on one
  would select and start no session, because the core answers
  `duration ≤ 0` as INVALID INPUT (`edit_action.rs`, the `err_out`
  channel), not a refusal, so the swallowed-refusal decision does not cover
  it and a session sending `duration: 0` every tick would be an error per
  tick. Measured while building it: no opened or committed project can hold
  one — `model_query.rs` `check_clips` refuses an action whose duration is
  not positive, on open and on every commit — so both lanes' guards are
  defensive, and the proof asks the wall of an in-memory clip. A tick the core
  still refuses stays SWALLOWED (#8's eighth decision, CI-10's last
  sentence): nothing new surfaces a drag's refusal, and the typed Start and
  Length fields remain where a person hears the sentence. A drop re-selects
  the action and parks the playhead at its NEW end through the existing
  `selectAction(_:on:)`. The timeline selects at mouse-DOWN, as it did; the
  lane selects at mouse-UP, because a selection rebuilds the pane and the
  pane must not rebuild under the pointer (`refresh(isLive:)` skips
  rebuilds while `isLiveEditing`). Grips draw on HOVER only (white 80 %,
  black 45 % on the selected band), so an unhovered selected band is phase
  1's pixels; a hovered band fills at 62 % with solid ends. Cursors are
  `.openHand` over a body and `.resizeLeftRight` over a grip, by cursor
  rects, and there is no closed hand. While a drag has moved, a HUD —
  mono 10 `DS.textStrong` on `DS.chromeBackground`, a 1 pt
  `DS.borderStrong` edge, 16 pt tall, 4 pt padding — reads "new start →
  new end  ±s:ff" for a move or a start resize and "len ±Nf" for an end
  resize: on the timeline at the band's left, 18 pt above the clip,
  clamped to the lanes' top and the visible rect; in the lane IN PLACE of
  the header row's text, its buttons staying. A 1 pt dashed [3, 3]
  `DS.action` ghost marks the original band. No `DS` token is new.
- **CI-12 — The Clip tab's lane carries the clip's transition hatch, fades
  and motion wedges, and its Curve popup a glyph and the short names**
  (phase 4). Drawn under the bands, with the timeline's gates verbatim: the
  hatch when `clip.transitionIn` is set and the track's predecessor (the
  last clip with an earlier start) ends after the clip's start, as wide as
  the overlap's fraction of the clip (at least 2 pt), the timeline's hatch
  (white 26 %, 3 pt on a 7 pt perpendicular period) with a 1 pt white-40 %
  right edge; a fade when `InspectorTab.hasAudio` and `fade_in` /
  `fade_out` is positive, a 10 pt-tall right triangle at the lane's bottom
  corner, white 16 %, as wide as the fade's fraction (at least 2 pt); a
  wedge when `InspectorTab.hasPixels` and the motion edge is active, 8 pt
  tall at the lane's top corner in `DS.textFaint`, as long as the EDGE —
  `drawMotionWedges`' rule, not the handoff's fixed 0.5 s. The detail
  row's Curve popup titles drop "Ease " in the lane only (`Curve.laneName`;
  `displayName` is untouched everywhere else), and a 16 × 10
  `CurveGlyphView` in the action ink precedes it with a 3 pt gap: the popup
  gives up 19 pt and, already at `.defaultLow` compression resistance,
  truncates first at the panel's minimum width. `OptionPopupControl` is
  Rasterize's and is not forked, so the glyph sits beside the popup rather
  than inside it.
- **CI-13 — The canvas's handles follow the mode** (road map 9 §11, the
  clip inspector redesign's phase 5, P9). With an action selected, a move,
  scale, rotate or crop drag on the canvas and an arrow-key nudge START
  from that action's END state — `clip_state` at the clip's start plus the
  action's end, decoded as the inspector decodes it (CI-2) — and WRITE it
  through `set_action_end`, one undo step per gesture as before. The box
  drawn is still the frame at the PLAYHEAD; the drag moves the end state by
  the pointer's travel, the inspector's "fields show the value they write".
  A text clip's wrap-width drag follows the same rule. Two things stay on
  the base: a multi-selection (CI-1: no action is selected then), and a
  SHAPE's box scale, whole — `set_shape` has no action form, and the
  `set_video` that pins the box's pivot must land beside it, so splitting
  the gesture would put the box and its placement on two different states.
  An endpoint drag is `set_shape` too and stays base. The mode reaches the
  canvas as a `CanvasEditTarget` value on the refresh that already follows a
  selection (`refreshCanvas`) AND on the playhead's own path
  (`canvasPlayheadMoved`), and a gesture writes through the target captured
  at mouse-down (`gestureTarget`), so playback entering a span mid-drag
  does not move the drag's writes. **Amended by CI-17:** a single clip's
  gesture on a first-frame cut goes to the cut, and writes the base too.
  **Amended by CI-19:** past a finished action holding a key it writes, a
  single clip's gesture refuses.
- **CI-14 — `set_action_end.off` keys an optional property OFF at the end**
  (phase 5, P10). The end state holding `null` at an optional key is the
  property switched off when the action finishes: the evaluator already
  switches a `null` at the end, and `prune_removed` already leaves a stored
  `null` alone. A `null` in `patch` stays a REMOVAL (§6, CI-9's Clear), so
  the off state needs its own spelling: `off`, a list of `"group.key"`
  paths written as `null` after the merge. `off` refuses what `patch`
  refuses — `video.motion` and `text.words` in the op's own two sentences,
  a key the group lacks, and a required key (`video.opacity`, `video.crop`)
  in the walk's words — plus a malformed path and a path `patch` also
  names. No format bump: `end` is stored as found, and such a `null` was
  always legal on read. On the app side the TYPED builder
  (`ReelOp.setActionEnd`) lifts every top-level null in its patch's groups
  into `off`, because a typed `.some(nil)` is the inspector's "switch it
  off"; the RAW builder, which `clearOps` and every agent call use,
  forwards its nulls as removals and its caller chooses `off` itself. Extended by AU-88: `off` also accepts
  `audio.eq.<slot>`, one EQ slot keyed off, which the typed builder lifts
  from a null slot inside `audio.eq`. Extended by GR-36: `off` also accepts
  `video.qualifier.<range>`, one qualifier range keyed off, which the typed
  builder lifts from a null range inside `video.qualifier`.
- **CI-15 — Every sub-row carries `mixed`, and the collapse is the one
  animation** (phase 5, P12 and Reduce Motion). A row nested under a switch
  (a shadow's Blur, a compressor's Ratio, a stroke's Width) shows the
  `mixed` badge when the selected clips disagree on it, like every
  top-level row. The only animation the redesign adds is a section's
  header-click collapse, at `DS.stateDuration` through `DS.animate` —
  Rasterize's one door, which runs the change unanimated when the system's
  Reduce Motion is on. `reveal()` (an action's auto-open) stays instant;
  hover, bands and gutters are painted in `draw(_:)` and do not animate.
  **Amended 2026-10-01, by #102** (the owner, 2026-09-30): a section
  header is clickable, so it takes a hover. The hover is a second
  `DS.hoverFill` over its band, faded in and out at `DS.hoverDuration`
  (140 ms) through the same `DS.animate`, so it is instant under Reduce
  Motion. Rows take none, because they are not clickable. Bands and gutters
  still paint in `draw(_:)` and do not animate.
- **K-1 — Space is the transport's unless the first responder is typing or
  claims it** (kpgalligan/framejob#35, 2026-09-24). The editor window routes
  a bare Space key-down (⇧ and ⇪ allowed, any other modifier untouched)
  before dispatch: it toggles play/pause unless the first responder is an
  editable `NSTextView` — every field editor, the Text tab's area, the
  canvas's inline editor, the Media tab's search field, so a Space is typed
  there — an `NSButton` or `NSSegmentedControl` (they press on Space by
  AppKit's own convention, reachable only under Full Keyboard Access, and an
  accessibility user keeps it), the canvas overlay (its own Space arms a pan
  and toggles on key-up, `PreviewCanvasView.handleKeyUp`), or a sheet is
  attached. An auto-repeat of a Space the window took is swallowed. A
  non-editable field editor (a selectable label), a slider, the window
  itself and every custom inspector control are the transport's. No MCP
  mirror: playback is view state, app/CLAUDE.md's exemption, and no play
  tool exists today; `set_playhead` stays the capability.
- **K-2 — In the canvas text editor Return applies, a modified Return is a
  new line, and Esc asks before dropping a change** (kpgalligan/framejob#37,
  2026-09-24). A bare Return or keypad Enter (⇪ allowed) commits the string
  and leaves the editor — the `set_text` it always sent, one undo step,
  nothing for an unchanged string; Return with ⇧, ⌘, ⌥ or ⌃ inserts "\n",
  one rule, so ⌃Return no longer inserts AppKit's U+2028 line separator;
  while an input method holds marked text none of the three keys is routed.
  Esc leaves an unchanged edit at once; with the string changed a sheet
  asks: Cancel (Esc — back to typing, text kept), Revert (editor closed,
  clip untouched, no undo step), Apply (Return, the default — editor
  closed, the change applied, one undo step). Apply is the default because
  Return applies everywhere in the session and Apply is undoable; Revert is
  the one destructive answer and is never the default. The Text tab's
  `InspectorTextArea` keeps its form-field bargain (Return a newline,
  ⌘Return a commit in place, blur commits): it sits among fields that
  commit on blur, and a session that must be left is the canvas's alone
  (withdrawn by K-4: the area now takes this Return too). No MCP mirror:
  the keys are view state, `set_text` is the apply.
- **K-3 — The canvas text editor lays its text out with the renderer's
  attributes at view scale; an UPPERCASE text is edited as typed**
  (kpgalligan/framejob#117, 2026-09-30). The font, `.kern` and paragraph
  style are `LayerRenderers.textAttributes` at `video.scale × canvasScale`,
  unclamped; the font is the renderer's `CTFontCreateWithName` face, its
  fallback included. The editor keeps its own ink (`DS.textStrong` on the
  chrome backdrop) and draws no stroke: a stroke moves no glyph, and a
  clip's colours can vanish on the backdrop. `case: upper` is shown as
  typed, because the storage is what `set_text` commits and `uppercased()`
  cannot be inverted ("ß" → "SS"); so a capital wider than its letter can
  wrap where the render does not, and that is the accepted limit. A rotated
  clip is edited axis-aligned: AppKit text editing in a rotated frame fights
  the input method. The 60 × 24 pt floor still widens a box narrower than
  60 pt.
- **K-4 — Typing in the editor window is focus-averse; amends K-2 for the
  Text tab's area and AI-17 for the composer's Tab** (the owner,
  2026-10-30). Only a click or double-click — or a command that exists to
  type, View ▸ Assistant or a rename — gives text the keys, and the editor
  window takes them back BEFORE dispatch, first responder to its content
  view (the root that holds the bare-key map, #60), so Space and the
  transport keys work the moment typing ends: (1) a mouse-down inside the
  content view whose hit lies outside the text — a field editor's field,
  or the `OptionFieldControl` that frames it; a text view's scroll view; the
  text view — so a click on the timeline, which refuses first responder
  and so left the field editor attached, now ends the typing (the title
  bar is outside the content view and keeps it); (2) Tab or ⇧Tab in any
  editable text, unless Full Keyboard Access is on — then Tab stays
  AppKit's key-view loop, how such a user reaches a control (K-1's
  exception), and the Text tab's area types a tab as it did; (3) a Return
  or keypad Enter (⇧ ⇪ allowed) in a one-line field. Never while an input method has marked text, never with
  a sheet attached, and a field that refuses to resign keeps the key. Each
  field commits through its own end-of-editing path, as a blur always did;
  AppKit's own Return handling, which re-selected the field after the
  commit (so the next Space was typed into it, behind no focus ring), and
  Tab's next key view are no longer reached. The multi-line editors take
  K-2's Return: the Text tab's `InspectorTextArea` applies and leaves on a
  bare Return or keypad Enter and inserts "\n" on Return with ⇧, ⌘, ⌥ or
  ⌃ — K-2's "form-field bargain" for it is withdrawn, so ⌘Return is a new
  line where it was a commit in place — and the Assistant composer leaves
  after a Return that sends (a beep keeps it) and on Tab, where AI-17 moved
  focus to the next key view (it still does with Full Keyboard Access on).
  Esc is unchanged everywhere. Sheets, Settings
  and Welcome are other windows and keep AppKit's dialog keys. No MCP
  mirror: focus is view state, app/CLAUDE.md's exemption.
- **K-5 — The canvas's keys take ⇧ ⇪ and the keypad and fn flags, an arrow on
  a focused canvas nudges a clip that is showing, and a press outside the
  canvas hands the keys back** (kpgalligan/framejob#463, 2026-11-05). The
  canvas's keys read `CanvasKey.isPlain`: ⇧, ⇪, `.numericPad` and `.function`
  are allowed, ⌘ ⌥ ⌃ never, because every real arrow carries `.numericPad`
  and `.function` and keypad Enter `.numericPad`. An arrow on a focused canvas
  nudges when a selected clip is drawn at the playhead (`primaryBox`), and
  otherwise stays the transport's: §4.2's nudge is the exception to §9's arrow
  rows. Space arms only under K-1's rule (⇧ ⇪), and a key-up settles only a
  press the canvas armed, so ⌥Space and a Space the window took toggle nothing
  on release. A press in the content view outside the canvas hands the keys to
  the content view before dispatch, as K-4 does for text, because a timeline
  click, which refuses first responder, otherwise left the arrows nudging.
  While a canvas drag is open an arrow does nothing: a committed edit inside a
  live edit keeps its undo step through Esc, which CI-16 forbids. No MCP
  mirror: focus is view state, and `set_video` is the nudge's capability.
- **K-6 — Crop mode's Esc, Return and keypad Enter work from any focus but
  typing** (kpgalligan/framejob#474, 2026-11-05). They leave the mode from the
  bare-key map as well as from the canvas, plain by K-5's rule, ahead of its
  other arms; typing and an attached sheet keep them, as they keep the whole
  map. Entering the mode takes no focus. Esc leaves crop mode before it
  deselects an action, as it does on the canvas. No MCP mirror: the mode is
  view state.
- **K-7 — Crop mode opens only on a clip with source pixels** (§4.3's rule,
  `InspectorTab.hasSourcePixels`; kpgalligan/framejob#475, 2026-11-05). C and
  a double-click beep on any other clip; a text clip's double-click still
  edits it. The mode ends when its primary clip stops qualifying, by a click,
  a selection or the playhead. A clip on a matte track keeps the mode whatever
  its kind, because crop shapes the matte (MT-4) and MT-7 has it handled like
  any clip; the owner kept it (#475, 2026-11-05, 'Keep it'): no Crop section
  is added, so such a crop has no field and no Reset. `set_video` and
  `paste_attributes` were unchanged by K-7 (amended by #524).
- **SH-3 — An inspector name field is the inspector's value field**
  (kpgalligan/framejob#171, 2026-09-30). `InspectorNameField` — the Graphic
  sub-tab's string rows, the Document tab's marker name and the clip
  header's name — is drawn as `OptionFieldControl` draws: an
  `NSColor.controlBackgroundColor` fill, a 1 pt `DS.border` stroke on
  `bounds.insetBy(0.5)`, `DS.controlRadius`, 7 pt padding, the line centred
  vertically, no focus ring. Its cell draws it, not a layer border, so it
  follows the appearance and a `cacheDisplay` capture holds it. The type is
  Source Sans (`DS.sans(11)`; the header's 12 semibold), not the handoff's
  Mono, because a name is a person's words. The clip header's name, which
  the handoff draws as a label, is this field at 20 pt, because the header
  is where a clip's own name is set. `DSField.style` (shared chrome, and
  Rasterize's) is unchanged.
- **CI-16 — The selected clip's obscure regions are drawn and dragged on
  the canvas; the layer's own handles outrank them, an armed modal mode's
  overlay takes every press over them, and Esc cancels any canvas drag**
  (kpgalligan/framejob#85, 2026-09-30). With exactly one clip selected,
  unlocked, outside crop mode and the text editor, each region of the list
  AT THE PLAYHEAD (the recipe's `video.obscure`) is outlined as its box's
  quad through the layer's scale, crop and rotation — an ellipse too, as its
  box — with a move grip at its centre and the eight resize handles. The
  grips exist only while the edit target's start list (CI-13) has as many
  entries as the list drawn; otherwise the outlines are drawn with no grip,
  because an index would name a different region (§5.4's list rule; §4.3:
  adding or removing an entry writes the base). Press order: the rotation
  grip, the endpoints and the eight scale handles first, as before; then
  the region grips; then bodies. A region's inside is not a grip (a drag
  there moves the clip), and a double-click never presses a grip. A drag
  writes the WHOLE list with one entry replaced, never its length, through
  CI-13's target: `set_video` at the base, `set_action_end` with the clip's
  action selected. The list is the target's start state; the pointer's
  travel is read in source pixels through the box on screen, as the region
  band reads it. The centre moves the region; a handle moves the edges it
  drives with the far ones pinned, ⌥ about the centre; each side stays in
  [1, 20 000] px. No snapping. One undo step, "Move Region" or "Resize
  Region". No new tool: `set_video` and `set_action_end` are the
  capability. Esc during any canvas drag (move, scale, rotate, crop,
  endpoint, region grip) puts the project back to the press's state with
  no undo step; until #85 it kept the drag as a step named "Cancel". While
  the region band or the eyedropper is armed, its overlay takes every
  press; the outlines and grips stay drawn under it, as the layer's box and
  handles do. Accepted: a grip under a layer handle is not reachable there,
  and an ellipse is outlined as its box.
- **CI-17 — A canvas gesture on a clip with a first-frame cut writes the cut
  and the base; amends CI-13** (#469, 2026-11-05). A **cut** is a layout
  action (`VerticalVersion.isLayoutAction`) at clip time 0, at most one
  canvas frame long (CO-61, CO-80 (b)): it holds the clip's placement for
  every frame after the first, so a base write moves frame 0 alone. With ONE
  clip selected and no action selected, a move, nudge, scale or crop on a
  clip whose cut holds a key the gesture writes goes to that cut: it starts
  from the cut's end and writes it as CI-13's selected action. A gesture on
  a cut, held this way or selected, writes the same patch to the base too,
  so frame 0 and the rest stay together: CAM-10 (3)'s "an ordinary clip a
  person moves". The two ops go as one list, one undo step named as before.
  The selection is not changed, and the playhead decides nothing, so CI-2
  stands. Unchanged: every other finished action (CI-13's base); a
  multi-selection and a shape's box scale stay on the base; a rotate stays
  on the base unless the cut holds `rotation`, which `PLACEMENT_KEYS` does
  not name; the inspector's fields keep CI-2 and their ◇. A cut is therefore
  the one case where a drag and a typed value write different places.
  **Amended by CI-19:** past a finished action holding a key it writes, a
  single clip's gesture refuses.
- **CI-18 — A list's add and remove buttons carry the boxed "clip" tag**
  (#481, 2026-11-05). Add Filter, Add Region with Place on Canvas (one tag
  for the row) and each Remove take `InspectorClipTag`, #102's mark for a
  lone ⊘ button in an animatable section, and not a gutter ⊘: their section
  animates, and the gutter on a Remove row speaks for the kind popup beside
  it. Shape rows take the real ⊘ under CI-7, through `paths(of:)`'s
  `set_shape` group, and CI-9's Reset stays.
- **CI-19 — A canvas gesture past a finished action that holds a key it
  writes refuses, when it writes one clip and no action is selected; amends
  CI-13 and CI-17** (#469, the owner 2026-11-05, "Refuse and explain"). It
  applies when the selection is exactly the clip the gesture writes (the
  anchor for a move, the pressed clip for a scale, width, rotate or crop,
  `primaryBox` for a nudge), no action is selected, the clip's track is
  unlocked, and some action of that clip that is not its first-frame cut
  (CI-17) has FINISHED at the playhead — its end at or before the playhead's
  clip time — with an end naming a key the gesture WRITES: x or y for a move
  or nudge ("position"); x, y or `scale` for a scale, which is a picture's
  handles and a text clip's corners and top and bottom edges ("position",
  "size"); `text.width` alone for a text clip's left or right edge
  ("width"); `rotation` for a rotate; `crop` for a crop. Then the gesture
  makes no edit and no undo step: Frame Job beeps and CI-10's strip shows
  the app's sentence, naming the LATEST such action by its lane number,
  "action N on this clip's lane holds its position at the playhead, so a
  move here would show only before it. Select action N first." (the noun is
  move, resize, rotation or crop; two keys are joined by "and"). A drag
  refuses on its first drag tick, so a press that only selects stays
  silent; a nudge refuses at once. The playhead decides here, where CI-17
  does not let it: before the action starts, or while it runs with no
  action selected (after Esc), the gesture writes CI-13's base, and a clip
  whose only holder is its cut keeps CI-17. Unchanged: a multi-selection
  (CI-13; #529), including a scale, rotate or crop on its primary box; a
  ⇧-press that takes the dragged clip out of the selection; a shape's box
  scale and an endpoint drag (`set_shape` has no action form, so selecting
  the action would not help); obscure grips (CI-16); the inspector's fields
  (CI-2, ◇); and `set_video`, `set_text` and `set_action_end` over MCP — no
  tool reaches a canvas gesture, so no agent mirror changes. CI-2 and CI-13
  stand: the refusal only says where the write would go.
- **SH-4 — `StickerButton` is Rasterize's square block, drawn in place;
  supersedes SH-1** (kpgalligan/framejob#100, the owner, 2026-09-30). The
  class, its name, its `init(title:style:target:action:)` and all 28 calls
  in 13 files stay. Its drawing and `intrinsicContentSize` are Rasterize's:
  a block on `bounds.insetBy(0.5)` at `DS.buttonRadius`, with no shadow and
  no margin. It is ⌈title width⌉ + 32 by 28 pt, 6 pt narrower and shorter
  than the pill. Primary fills `DS.accent`, or `DS.accentHover` while
  hovered (the accent 12 % toward white, Rasterize's token), with no stroke.
  Secondary fills `DS.chromeBackground`, adds `DS.hoverFill` while hovered,
  and strokes 1 pt of `DS.borderStrong`. A press scales the drawing 0.97
  about the centre; disabled is 42 %. `DS.stickerShadow` goes with its one
  caller. One difference stays: `updateTrackingAreas` removes only the
  view's own areas (`area.owner === self`), because removing them all
  deletes a tooltip. Rasterize's copy still removes them all
  (kpgalligan/rasterize#335, item 4). A window loses 6 pt per row of these
  buttons. The welcome window's centred column moves 3 pt, which
  `recording_probe.py` §6 scores against its pre-button reference. The sharp
  handoff says to delete `StickerButton` once it has no callers. That is not
  followed: the class has callers everywhere, and the square shape is what
  that line was after.
- **SH-5 — Settings' explanations are an info button's AppKit `NSPopover`,
  which keeps its own rounded bubble** (issue batch B71, the owner,
  2026-10-02). Each Settings section's heading carries an ⓘ
  (`SettingsInfoButton`, the system "info.circle" symbol) in place of the
  long grey paragraph under it, and the paragraph's text, sentence for
  sentence, is the popover's: 13 pt in `DS.textStrong`, where the paragraph
  was 11 pt in `DS.textFaint`. A deviation from the sharp handoff's square
  radii, as SH-2 is one: a system popover gives the arrow, the
  appearance-correct material, VoiceOver's reach and its dismissal for free,
  and a plain `toolTip` cannot be styled (small, the system font). Resting
  on the icon for `hoverDelay` (0.35 s) opens it, leaving closes a
  hover-opened one, a press opens and holds it (promoting a hover-opened
  one) and a press on a held one closes it; a press on the icon never
  closes it through `.transient` (`popoverShouldClose` refuses that
  mouse-down), so the press's action alone decides. The button has no
  `toolTip`, which would double the popover; VoiceOver reads it as "About
  <section>" with the text as its help. Accepted: one rounded shape in
  square chrome.
- **#495 — The Document tab's Rate popup reads Custom for a rate it does
  not list** (2026-11-05). Its items are `Fps.common`, Match First Clip and
  a trailing **Custom**, the Canvas Preset's own Custom
  (`DocumentPane.canvasSection`). Custom is shown, and checked, for a
  project rate the popup does not list, such as 59.94 or 48 fps from a file
  or an agent; picking it beeps and changes nothing, since no field types a
  rate there. The popup used to fall back to its first item, so it drew and
  checked 24 for any unlisted rate. `Fps.common` and the Export sheet's
  rates are unchanged.
