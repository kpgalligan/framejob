# Road map 9 — the clip inspector redesign

- **Status:** Built. Phases 1, 2, 3a and 3b on 2026-09-23; phases 4 and 5 on 2026-09-24. Closed.
  What remains is a person's checks.
- **Original:** `archive/roadmap-9.md` (1120 lines) is the full record; "orig §x" below
  refers to it. The handoff it implemented stays at `designs/design_handoff_clip_inspector/`.
  Its README is normative for metrics, inks and behaviour, except where the decisions below
  deviate from it.
- **Spec decisions:** spec §11 CI-1..CI-15. CI-1..4 cover the selected action, END-state
  editing, base-routed audio switches and mint ink. CI-5..6 cover the sub-tabs, the pinned block,
  `◆N` and the block knob. CI-7..8 cover row marks and auto-open. CI-9..10 cover Reset/Clear, the
  row menu and the refusal strip. CI-11..12 cover band drags and lane decor. CI-13 covers the
  canvas following the mode, CI-14 `set_action_end.off`, and CI-15 `mixed` and Reduce Motion.

## Context

The Clip inspector brief (`77b96ee`) listed twelve problems, P1–P12:
- The inspector was dense.
- It split audio from video.
- Actions were buried in a section, and there was no selected action.
- Keyed properties carried no mark.
- Writes silently disappeared into an end patch (P7).
- Fields moved with the playhead (P8).

The product owner chose the handoff's direction 1b (a pinned lane plus sub-tabs), mint `#5CD6B0`
as the action ink, and 1g: fields show the END value, and the playhead's value is a read-only
tick. The phases were ordered so that the view state everything else depends on landed first. No
phase added an `rc_*` export or bumped the format. The core's only change was phase 5's `off`
argument.

## Decisions

**A selected action is explicit view state.** It is never simply the action under the playhead
(CI-1; orig §1).
- It is auto-selected only when the playhead *enters* a span by moving.
- `clampViewState` re-reads `lastInsideAction` before it writes the playhead. So an edit, undo or
  redo under a stationary playhead never selects an action.
- Leaving the span keeps the selection. esc, the Clip chip and any change of clip selection clear
  it.
- It is not undoable, not persisted, and has no MCP mirror. Agents address actions by id.

**Fields show and write the action's END state** (CI-2).
- They read `clip_state` at `clip.start + action.endTime`.
- Selecting an action parks the playhead there. It parks one frame short when the action ends
  with its clip, because that tick composes nothing.
- The park is clamped with `max(duration - frame, 0)`. Without it, a clip shorter than one frame
  parked the playhead before its own start (orig §3).

**Six audio switches always write the base: pan, mono, compressor, noise reduction, duck and
keep-pitch** (CI-3).
- The routing is app-side, in `structural(audio:for:)`.
- The core still accepts these keys in `set_action_end` from an agent.

**The Actions section is replaced by a lane in a block pinned above the scroll view** (CI-4,
CI-5).
- The pane owns the block (`pinnedBlock`). The frozen `InspectorViewController` hosts it.
- The outgoing block is kept for one generation (`retiredPinned`), because a sub-tab click lands
  inside the block's own `mouseDown`.
- The lane's black-22 % backing is drawn only on clips that have an action with length. The
  handoff draws it on every clip, which would have moved every chrome proof's pixels (orig §2).

**The sub-tabs follow the selection's kinds, and Clip is always last** (CI-5).
- A tab picked by hand is forgotten when the selection's ids change, so A → B → A comes back to
  the default tab.
- Section ids (the `UserDefaults` keys) are unchanged. Only two titles changed: *Motion presets*
  and *Reveal*.

**`◆N` counts KEYS, not rows** (CI-6, CI-7). This keeps a section's count and its sub-tab's count
in agreement.

**The label column stays 76 pt, not the handoff's 64** (CI-7). "Remove noise" measures 64.1 pt in
`DS.sans(11)`. The 14 pt gutter is every row's first view, so every control column moved right
14 pt.

**A row's mark comes from the ops it writes and follows** (CI-7; orig §5–§6).
- It is taken at build time from the row's own `ops(read())`. So it is right whether the write
  lands on the base or on the end patch.
- A popup, checkbox or segmented control makes a row discrete, which gets "at end". Colour counts
  as continuous.
- ◇ uses the single selected clip's numbering. With several clips selected, no row shows ◇. The
  handoff says marks follow the first clip; Frame Job deviates from that.

**Rows read at four times through `InspectorBinding.at(_:_:)`.** The modes are `.end`, `.start`,
`.playhead` and `.defaults`, and each is cached per clip and mode.
- The keyed slider segment runs from start to end.
- The coral tick shows the playhead's value.
- `.defaults` answers the identity props without calling the FFI.

**Auto-open reveals sections without writing the collapsed preference** (CI-8).
- The reveal is remembered per action selection.
- If a person closes a section by hand, it stays closed until the action selection changes.

**A row's default is its own `read` in `.defaults`** (CI-9).
- Rows whose read bypasses the props pass `resets: false`. That covers Rate, Transition's four
  rows, Reverse, Canvas W/H, Appearance's three rows, and Box ▸ Width. For Box ▸ Width, a derived
  default would have written a fixed width instead of restoring auto-size.
- Invariant: a section's `differs` is false right after its own Reset runs. Six sections needed
  an explicit `differs`: Speed, Filters, Obscure, Shape, Stroke and Appearance.

**With an action selected, the Reset slot reads Clear** (CI-9).
- Clear is one `set_action_end` with nulls.
- A keyed row's ◆ turns to × on hover. It uses the gutter's own glyph because a hover button
  would shrink a slider under the pointer.
- The × needs a key window. The row menu does not.

**A person's refusal shows at the inspector's foot, in the core's sentence verbatim** (CI-10).
- It clears on the next change of project handle, or on a click. There is no timer.
- Agent refusals never reach it. Neither does a live drag's refused tick.

**One `ActionDragSession`, in clip time, drives both lanes** (CI-11; orig §9–§10).
- Each tick sends one `set_action` carrying start and duration. The whole drag is one undo step.
- Drags snap to the frame grid only. The minimum is one frame, the core's, not the handoff's two.
- The walls are the core's own refusals: the neighbouring actions, and the clip length floored to
  the grid. The floored length is never below the action's own end; otherwise an off-grid clip
  end would shift every move left.
- The timeline selects on mouse-down. The lane selects on mouse-up, because the pane must not
  rebuild under the pointer.
- In the lane, the last band under the point wins, since it is the one painted on top.

**A zero-length action is never dragged** (CI-11). The core treats `duration ≤ 0` as invalid
input, not a refusal. `check_clips` makes such an action unrepresentable on open and on every
commit, so the guards in the code are defensive.

**The lane draws the timeline's decor through the timeline's own gates** (CI-12).
- Wedges are as long as the motion edge, not a fixed 0.5 s.
- The Curve popup uses short names next to a glyph, because Rasterize's `OptionPopupControl` is
  not forked.

**Canvas gestures and the nudge start from, and write to, the selected action's end state**
(CI-13; orig §11–§12).
- `CanvasEditTarget` is pushed by both `refreshCanvas` and `canvasPlayheadMoved`.
- A gesture writes through the target captured at mouse-down (`gestureTarget`). Before this
  (review 2), playback entering a span mid-drag switched the drag to `set_action_end`.
- A shape's box scale stays on the base, because `set_shape` has no action form.

**`set_action_end.off` keys an optional property OFF** (CI-14).
- A `null` in `patch` stays a removal, which is what Clear uses.
- The typed `ReelOp.setActionEnd` lifts top-level nulls into `off`. The raw builder, used by
  `clearOps` and agents, keeps them as removals.

**Every sub-row carries `mixed`, and the section collapse is the redesign's one animation**
(CI-15). The collapse runs through `DS.animate`, which respects Reduce Motion. `reveal()` stays
instant.

**#102 (the owner, 2026-09-30): two unbuilt handoff items built, six struck.** A section
header's hover is a second `DS.hoverFill` over its rest band. The rest band is already
`DS.hoverFill`, so the same ink once more is the visible step, as Rasterize's secondary button
lays it over `chromeBackground`. It is a subview whose alpha fades through
`DS.animate(DS.hoverDuration)` (CI-15, amended), because a band drawn in `draw(_:)` cannot fade.
Rows get no hover. Normalize, a lone ⊘ button in an animatable section, carries the handoff's
boxed mono 9 "clip" tag while an action is selected (`InspectorClipTag`, its own view).

**Harness pixel checks compare in the PNG's own colour space** (orig §2). The harness writes
Display P3 on this host, where sRGB mint (92, 214, 176) becomes (126, 211, 178). The probe
converts the inks and compares within ±1.

**Proofs read `RC_FORMAT_VERSION` from the header, never from a literal** (orig §12).
- This came out of stale `VERSION = 8` copies.
- A core test holds the header equal to `format.rs`.
- It is now a `core/CLAUDE.md` rule.

## What it built — where it lives now

**The selected action**
- `app/Sources/ProjectDocument+SelectedAction.swift`
- `app/Sources/EditorViewController+Actions.swift` (the park clamp)

**The bands and the lane**
- `app/Sources/ActionBands.swift` (the shared painter, `ordered`, grips)
- `app/Sources/TimelineActionBands.swift`
- `app/Sources/TimelineActionDrag.swift`
- `app/Sources/ActionDragSession.swift` (also the HUD and ghost painters)
- `app/Sources/ActionLaneView.swift`
- `app/Sources/ActionLaneView+Drag.swift`
- `app/Sources/ActionLaneDecor.swift`

**The pinned block and sub-tabs**
- `app/Sources/ClipPinnedBlock.swift`
- `app/Sources/ClipSelectionHeader.swift`
- `app/Sources/ClipPane.swift`. Timing later moved to `ClipPane+Timing.swift`, and road map 10
  added a Graphic tab.
- `app/Sources/OptionControls+Choices.swift`

**Marks, defaults and Reset/Clear**
- `app/Sources/InspectorMarks.swift` (`RowMark`, `InspectorRowDefault`, `clearOps`, `paths(of:)`,
  `InspectorClipTag`)
- `app/Sources/InspectorSection.swift` (`KeyedReveal`, `clear()`)
- `app/Sources/InspectorSectionHeader.swift` (the hover band)
- `app/Sources/InspectorSlider.swift`
- `app/Sources/InspectorRowMenu.swift`
- `app/Sources/InspectorRefusalStrip.swift`
- `app/Sources/InspectorBinding+Writes.swift`
- `app/Sources/InspectorPane.swift` (`ReadMode`, around l.762)

**The canvas**
- `app/Sources/CanvasEditTarget.swift`
- `app/Sources/CanvasSessions.swift` (the `to:` forms)
- `app/Sources/PreviewCanvasView.swift` (`gestureTarget`)

**The core**
- `core/src/edit_action.rs` (`not_a_target`, `check_off`, `key_off`)
- the `off` row in `core/src/op_table.rs`
- `core/tests/action_off.rs`

**The proofs**
- `tools/proof/clip_inspector{,2,3,4,5,6}_proof.py`, each with a `_probe.swift` and a
  `--mutant`.
- Phase 5's `clip_inspector6_proof.py` has the mutants `target`, `live` and `push`.
- `tools/proof/clip_inspector7_proof.py` (#102): the header hover and the "clip" tag, with eight
  mutants.

## Known limits

- **What is drawn and what is written can differ.** With an action selected, the canvas box is
  the frame at the playhead, but a drag writes the end state, offset by the animation's progress.
  This was accepted in CI-13.
- **A drag's refused tick is swallowed.** The band just stops. The typed Start and Length fields
  are where a refusal is heard (CI-11).
- **Bands do not snap** to the playhead or to other edits, and there is no closed-hand cursor.
  CI-11 decided this, not an oversight.
- **A multi-selection has no selected action and no ◇ marks** (CI-1, CI-7).
- **The light mint `#1E8F6E` is the handoff's placeholder** (`Theme.swift:105`). The handoff did
  not cover the light appearance.
- **Proofs cannot place the lane's band by photograph.** The pane's width varies with the host's
  scroller style, so the probe does it (orig §2).
- **Measured and rejected:**
  - A `labelColor` knob. It is translucent, so it split on its centreline: (221,221,221) against
    (224,224,224). Replaced by the opaque `DS.textStrong`.
  - A fixed 22 pt gutter. It would have grown every bare-text row.

## Open items

- A person checks each phase in the running app, in both appearances. Phases 1, 2, 3a, 3b, 4 and
  5 are tracked in #49, phase 1 written out in full (the lane and
  bands, the light ink, a real band click, and esc).
- #102's items were decided by the owner on 2026-09-30. The "clip" tag and the header hover
  were built (issue batch B50). Struck:
  - the 64 pt label: CI-7's 76 pt stands, so long labels fit
  - the dashed ⊘ border: it needs a dashed mode on every shared control, another fork from
    Rasterize; the ⊘ mark and the section note carry the meaning
  - "now …" on ○, colour and popup rows: the coral playhead tick covers the numeric rows, and
    text after a popup is clutter
  - a keyed colour-well border: the gutter's ◆ already marks the row
  - `DS.textDim`: its only use was the dashed ⊘ label
  - the 8/10 body padding: the current spacing passed the redesign review, and nobody would
    notice

## Where to look in the original

| Section | What it holds |
|---|---|
| orig §0 | The phase split, and which of the brief's P1–P12 each phase answers. |
| orig §1–§2 | Phase 1: the selected action, the lane, the timeline bands, esc and ⌫. Deviations: the P3 colour space, the ruler rule, the backing. |
| orig §3–§4 | Phase 2: the pinned block, each sub-tab's section list, the badge, the knob, the park clamp. |
| orig §5–§6 | Phase 3a: marks, read modes, auto-open. The list of handoff items not built. |
| orig §7–§8 | Phase 3b: row defaults, the `resets: false` rows, Reset/Clear, the row menu, the strip. Why each chrome proof was re-measured. |
| orig §9–§10 | Phase 4: the drag session's walls and modes, hit order, the HUD and ghost, the decor. The zero-length finding. |
| orig §11–§12 | Phase 5: the canvas target, `off` and its refusal order, `mixed`, Reduce Motion. The review rounds and their mutants, and the sweep of version literals from the proofs. |
