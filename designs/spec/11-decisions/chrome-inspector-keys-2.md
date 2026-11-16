# Spec §11 — decisions: Chrome, the clip inspector and keys, the keys onward (#35 and after)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The SH-, CI- and K- series continue from [`chrome-inspector-keys.md`](chrome-inspector-keys.md), so
a citation never has to say which file. This file holds K-1…K-7, SH-3…SH-5, CI-16…CI-19, #495, #529,
#530 and #540, and a new decision of this kind is appended here. It is new because
`chrome-inspector-keys.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the
entries moved here unchanged, and an "above" or "below" in one may now point into a sibling file.

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
  **Amended 2026-11-10, by TX-37:** the Transcript tab's find field is
  (3)'s one exception — its Return and ⇧Return step to the next and the
  previous match and the field keeps the keys (`TextFocus.keptReturn`) —
  and for (1) the find bar is its field's host, so a press on the bar's
  own buttons keeps the typing.
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
  single clip's gesture refuses. **Amended by #529:** a multi-selection's
  gesture follows the same rule for each clip it writes, so its
  "multi-selection stays on the base" holds only past an action that is not
  a cut. **Amended by #530:** a typed value keeps the cut and the base
  together too, so a drag and a typed value no longer write different
  places.
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
  past an action that is not a cut (CI-13; #529), including a scale, rotate or crop on its primary box; a
  ⇧-press that takes the dragged clip out of the selection; a shape's box
  scale and an endpoint drag (`set_shape` has no action form, so selecting
  the action would not help); obscure grips (CI-16); the inspector's fields
  (CI-2, ◇); and `set_video`, `set_text` and `set_action_end` over MCP — no
  tool reaches a canvas gesture, so no agent mirror changes. CI-2 and CI-13
  stand: the refusal only says where the write would go. **Amended by
  #529:** a multi-selection's gesture on a clip whose first-frame cut holds
  a key it writes goes to the cut and the base (CI-17), and never refuses.
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
- **#529 — A multi-selection's canvas gesture moves each written clip's
  first-frame cut with its base; amends CI-13 and CI-17** (2026-11-06, the
  owner: "Both follow the drag"). With no action selected and several clips
  selected, a gesture writes each clip it writes as CI-17 writes one clip.
  A move or an arrow-key nudge writes every selected clip, and a scale,
  rotate or crop writes the pressed (front-most) clip. Where that clip's
  first-frame cut holds a key the gesture writes, the gesture starts from
  the cut's end and writes the cut and the base together, one undo step
  named as before ("Move", "Nudge", "Scale"). The owner's words name the
  front-most selected clip, the one a scale, rotate or crop writes; a move
  and a nudge write every selected clip, so each moved clip's cut moves
  with it: writing only the front clip's cut would leave every other moved
  clip jumping after its frame 0, which is #529's bug. Unchanged: past an
  action that is not a cut, a multi-selection writes the base and never
  refuses (CI-19 stays a single clip's); a shape's box scale stays on the
  base; a rotate stays on the base unless the cut holds `rotation`.
- **#530 — A video value typed or set in the inspector on a clip with a
  first-frame cut writes the cut and the base together; amends CI-2**
  (2026-11-06, the owner: "Both follow the drag"). It covers every write
  through `InspectorBinding.ops(video:)`: a typed field, a slider, Reset and
  the row menu. With the clip's cut (CI-17) selected, every value written
  to the cut's end goes to the base too. With no action selected, every key
  of the write that the cut's end already names goes to the cut too,
  beside the base; a `null` there, such as Shadow turned off, is keyed off
  at the cut's end (CI-14's `off`, which the typed builder lifts it into),
  so frame 0 and the rest agree. A key
  the cut's end does not name, such as a rotation on a landed camera, goes
  to the base only. Unchanged: with another action selected, CI-2; text,
  audio and graphic values; the marks (◆ ◇ ⊘). No MCP change: an agent
  sends `set_video` and `set_action_end` itself. **Amended by #540:** a cutout's
  presence never goes to the cut.
- **#540 — A cutout's presence never goes to a first-frame cut; amends
  #530.** With no action selected and the cut's end naming `cutout`, a
  write of a whole `cutout` sends to the cut only those of its
  `background`, `edge` and `feather` that differ from the clip's base
  cutout before the write: all three when the clip had none (Remove
  Background ticked), none for a Subject change, which leaves the cut's
  own Background, Edge and Feather. A `null` cutout (Remove Background
  unticked, the Background header's Reset) sends nothing to the cut: the
  base's `null` already removes the cutout on every frame
  (`restore_base_cutout`, CO-20). Before, the cut was sent the whole or
  null cutout, which the core answers with an `Err` (CO-20, CO-30 (b)), so
  the whole edit failed with an error sheet and Remove Background could not
  be turned off from the inspector on such a clip. A sparse cutout part
  (the Background, Edge or Feather control) goes to the cut as #530 says.
  Lists (`filters`, `obscure`) are unchanged.
