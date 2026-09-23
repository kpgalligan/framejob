# Reelcut — road map 9: the clip inspector redesign

**Status: phases 1 and 2 BUILT, 2026-09-23 (§2, §4). Phases 3–5 are
designed by the handoff and not built (§0).**

The handoff is `designs/design_handoff_clip_inspector/` — its README is the
normative text for the redesign's metrics, inks and behaviour, with this
document's §1 and spec §11's CI-1 to CI-4 as the decisions taken where the
README had to be read against Reelcut. It answers the Clip inspector brief
(`87aa425`): P1 density, P2 no audio/video split, P3/P4 buried actions and
no selected action, P5/P6 marking, P7 silent no-op writes, P8 fields that
move with the playhead, P9–P12. The product owner chose direction 1b
(pinned lane + sub-tabs), mint `#5CD6B0` as the action ink and 1g (fields
show the END value; the playhead's value is a read-only tick).

## 0. The five phases

The handoff is split so each phase is buildable and provable alone, and so
the view state everything else hangs on lands first.

1. **The selected action** (P3, P4, P6, P7, P8) — BUILT, §1 and §2. Explicit
   view state the inspector EDITS (end values), the timeline HIGHLIGHTS and
   a lane in the Clip tab SELECTS; the lane replaces the Actions section;
   pan, compressor, noise reduction, duck, mono and keep-pitch routed to the
   clip; the per-section "Editing action N's end state" note removed.
2. **Sub-tabs and the pinned block** (P1, P2) — BUILT, §3 and §4.
   Picture · Sound · Clip (Text · Picture · Clip, Shape · Picture · Clip,
   Sound · Clip), the section regrouping and the two renames (Motion
   presets, Reveal), the selection header and lane PINNED above the scroll
   view, the 7 × 11 block knob on the inspector's sliders, sub-tab badges.
3. **Marks and Reset/Clear** (P5, P11) — the row marks ◆ ◇ ○ ⊘ and "at
   end", the coral playhead tick, header badges, auto-opening the sections
   an action keys, summary colours, the Reset/Clear model with per-row ×,
   the row context menus, and the refusal strip at the panel's foot.
4. **Retiming by drag** — band drags in the lane and on the timeline
   (`set_action`), hover, grips, the HUD and the ghost; the lane's fades,
   wedges, hatch and curve glyph.
5. **The rest of the mode** (P9, P10, P12) — canvas handle drags following
   the mode, keyed-off switches, `mixed` on sub-rows, Reduce Motion.

## 1. Phase 1's design

**State.** `ProjectDocument.selectedAction` is the sixth piece of view state
(spec §11 CI-1): nil, or one action of the single selected clip. Three
writers — `selectAction(_:)`, `syncSelectedAction()` and
`clampViewState` — and the first stores nil for an id that is not
`singleSelectedClip`'s. `lastInsideAction` records the span the playhead
was last inside, and `syncSelectedAction()` (from `playhead`'s and
`selection`'s `didSet`) selects only on a CHANGE of span: entering selects,
leaving keeps, and after esc the playhead can sit in a span without
re-selecting it. `clampViewState` runs on every `projectDidChange`, live
ticks included, and ends by writing the playhead; the two selected-action
lines go ABOVE that write, so an edit, undo or redo under a stationary
playhead never counts as entering.

**Reads and writes.** `InspectorBinding.action(_:)` answers the selected
action when it is the clip's, never the one under the playhead; everything
downstream of it — `editedList`, `structural(video:)`, `split` and the
default `structureSignature` — follows. `evaluated(_:)` reads `clip_state`
at `clip.start + action.endTime`: the core merges an action whose
`end <= t` and interpolates one whose span holds `t`, so the answer is the
keyed keys at their end values and the unkeyed ones at what is held (CI-2).
`structural(audio:for:)` sends pan, mono, compressor, noise reduction, duck
and keep-pitch to the base props (CI-3). No op is new and no tool is new.

**The lane** (`ActionLaneView.swift`, inside `ClipHeaderBlock` under the
selection header): the header row (ACTIONS, the count or `none`, "·
editing N", and Zoom to Region / Zoom Back / Add Action through
`onCommand`); the lane row (the Clip chip, the whole clip with its bands by
fraction through the shared painter, the playhead line, the empty and
multi-selection sentences); and the detail row, only with a selection —
Start (clip-relative timecode), Length, Curve and a trash button.

**The timeline** (`TimelineActionBands.swift`, `ActionBands.swift`): each
clip's lane directly under its name strip, 5 / 12 / 18 pt at S / M / L, on a
black-22 % backing; normal bands mint 34 % with 1 pt ends at 75 %; the
selected band solid with its number in `#101010` and its curve from the
bottom-left corner to the top-right; the number, the zoom glyph and (at L)
the keys from the leading edge, so a band's bottom-right corner holds fill
only; the selected span washed at 12 % down the clip body with 55 % ends,
and shaded on the ruler at 20 % over a 2 pt rule. `hit(at:)`'s order is
locked → fade → band → edge grab → clip.

**Keys.** esc leaves the mode (`case 27` in `handleEditorKey`; not consumed
when nothing is selected); ⌫ removes the selected action before it would
delete the clip; ⌥⌘K, Zoom to Region and Zoom Back select what they add.

## 2. Phase 1's record

**What landed.** Five new files — `ProjectDocument+SelectedAction.swift`,
`EditorViewController+Actions.swift`, `ActionBands.swift`,
`TimelineActionBands.swift`, `ActionLaneView.swift` — and wiring in
`ProjectDocument`, `InspectorPane` (the binding only),
`InspectorViewController`, `ClipPane`, `VideoPane` (the Actions section
deleted), `AudioPane`, `TextPane`, `VideoPane+Motion`, `TimelineSessions`,
`TimelineView` (frozen; twelve lines), `TimelineClipDrawing`,
`EditorViewController` (frozen; one line), its `+Timeline`, `+Inspector`
and `+ZoomRegion`, `AgentServer+Clips` (comments only) and `Theme`. The
sizes are `designs/reelcut-remaining.md` §3's phase-1 paragraph.

**What was measured.** `make typecheck` at its baseline (0 errors, 7
warnings); `make test` and `make lint` green, the core untouched; `make app`
rc 0. `python3 tools/proof/clip_inspector_proof.py` **38/38**: the probe's
31 rows (S1 entry ×10, S2 ×2, S3 ×4, S4 ×5, S5 ×6, S6 ×4) and five harness
rows. `--mutant entry` (a sync that ignores `lastInsideAction`) exits 0:
four S1 rows fail — esc then a move inside re-selects, the redo under a
stationary playhead selects, the live `moveClip` selects — and no other row
does.

**Deviations, each for a reason.**

- **The playhead parks one frame SHORT** of an action that ends with its
  clip: the clip's end tick composes nothing, so parking there would show
  the next clip or black instead of the end state.
- **The lane scrolls with the pane** until phase 2 pins it above the scroll
  view: `InspectorPaneView` has one header slot, inside the scroll view.
- **Start is 104 pt, not 76**: it is `InspectorTimecodeField`, the Timing
  section's field, whose width is fixed at 104 for an `hh:mm:ss:ff` string.
  The Curve popup takes what is left — 70 pt at the 304 pt panel — and "Ease
  In Out" crowds its chevron; phase 2's regrouping is where the row widths
  are revisited.
- **The lane's black-22 % backing is drawn only on a clip that has an action
  with a length.** The handoff draws it on every clip; a dark stripe under
  every existing clip's name would move every chrome proof's pixels for
  nothing.
- **The harness's pixel rows compare in the PNG's OWN colour space.** The
  harness writes at the display's space — Display P3 on this host — so the
  spec's sRGB literals are not what the file holds: sRGB mint
  (92, 214, 176) is (126, 211, 178) there. The proof asks its probe
  (`--convert`, ColorSync through `NSColor.usingColorSpace`) for mint and
  `DS.clipShape` in the PNG's space and compares within ±1; the normal band
  is `0.34·mint + 0.66·(0.78·clipShape)` of the CONVERTED inks, since the
  fills composite in that space.
- **The ruler's 2 pt rule sits above the ruler's own 1 pt border line**
  (y 17–19 of 22), because the frozen `draw` paints that line and the ticks
  after the one call this phase may add; the proof scans the rule's row
  across the span and requires at least 70 % mint (a minor tick crosses it
  every few points; measured 102/118 px).
- **Where the lane's selected band sits is proved by the probe, not the
  photograph** (S6, `bandRects()` against `laneRect`): the pane's width in
  the harness depends on whether the host shows legacy scrollers, so the
  harness row checks the band's height and its sample ink only.
- **Motion's note stays, reworded** — "Motion belongs to the clip; the
  selected action does not animate it" — because it is a real warning about
  where the edit lands, not the removed "editing N" note;
  `InspectorBinding.editsAction` stays for it.
- **`DS.action` is a `static let`** over a dynamic provider rather than a
  stored `static var`, like the other fixed inks.
- **The harness's `selectAction` argument**: an index selects, `-` selects
  nothing, and ABSENT leaves whatever the playhead's entry selected, so every
  earlier caller renders what the new view state makes of its playhead.

**Owed.** Three earlier chrome proofs were re-run on the phase's tree
(2026-09-23): `sharp_chrome.py` **29/29** and `e2_chrome.py` **52/52** hold,
and `phase3_chrome.py` was **32/33**. Its failing row was "the content below
is the one-region render pushed DOWN by six rows" (the best shift was still
174 pt, but at 157 mismatched rows of 400): that proof held `video.actions`
open so the section stack had no slack when Obscure opened, and the Actions
section no longer exists. **Corrected by phase 2 (§4):** Obscure is now the
last section of the Picture sub-tab, `INSPECTOR_BELOW` is deleted, and the
row, re-measured on the section's own tail, scores **33/33**. The lane is
no longer inside the scroll view either: phase 2 pins the whole block above
it (§3), retiring the deviation above. Every other Clip-tab photograph now
carries the lane block under its header and was not re-run in this phase. A
person still checks the lane and the bands in both appearances (the light
ink `#1E8F6E` is the handoff's placeholder), and a real click on a band and
esc in the running app.

## 3. Phase 2's design

**The block, pinned** (spec §11 CI-5). `InspectorPane.pinnedBlock` is the
header `makeHeader()` builds on every `rebuild()` — no longer stacked into
the scroll view. The frozen `InspectorViewController` hosts it in a
`pinnedContainer`, a vertical `NSStackView` between the tab strip and the
scroll view (0 pt when empty, a priority-1 zero height), filled by
`installPinned(_:)` right after `pane.rebuild()`; a swap to Media or
Document rebuilds, so the container empties there. The outgoing block is
held one generation in `retiredPinned`, `buildTabs()`'s reason: a sub-tab
click lands inside the block's own `mouseDown`. For the Clip tab the block
is `ClipHeaderBlock` (`ClipPinnedBlock.swift`), stacked header → lane →
sub-tabs.

**The sub-tabs.** `ClipPane.subTabs` is Text for an all-text selection,
Shape for an all-shape one, Picture when a selected clip has pixels, Sound
when one has audio, and Clip always, last. `activeSubTab` is the hand-picked
`chosen` while the selection still has that tab, else the first.
`choose(_:)` and `forgetSubTab()` set and clear `chosen` and trigger
nothing; `InspectorViewController.selectClipSubTab(_:)` is the one refresh
(and scrolls to the top), and `refresh(isLive:)`'s existing
`ids != lastSelection` block calls `forgetSubTab()` — whatever tab is
showing — so A → B → A comes back on the default and a detour through the
Media tab keeps nothing stale. `structureSignature` carries the active tab
and the tab list. `makeSections()` switches on the active tab: **Text**
Content, Font, Style, Outline, Backdrop, Box, Reveal, Presets; **Shape**
Shape, Stroke, Fill, Gradient, Arrows; **Picture** Transform, then Crop,
Corner radius, Colour and Chroma key when `allSourcePixels`, then Shadow,
Filters, Reflection, Spotlight, Obscure; **Sound** Volume, Fades, Duck,
Noise reduction, Compressor, Mix; **Clip** Timing (single) or its Reverse
half (several media clips), Speed (media), Transition (single, with an
overlap), Motion presets (pixels). The open rule lost its `!hasPixels`
guard: on any tab with nothing expanded, the first section with no stored
preference opens. Ids are unchanged; `video.motion` is titled *Motion
presets* and `text.animation` *Reveal*.

**The strip** (`ClipSubTabsView`): 40 pt — 8 above, 24 pt cells, 8 below —
with 10 pt sides; equal cells whose 1 pt borders collapse, with
`PanelTabsView.tabRect`'s rounding; the active cell `DS.selectionFill` with
a `DS.accent` border and `DS.textStrong`, inactive ones
`controlBackgroundColor`, `DS.border` and `DS.textMuted`; labels
`DS.sans(11, .semibold)`; a 1 pt `DS.border` line at the foot. No hover.
The badge (spec §11 CI-6) is "◆N" in `DS.mono(9, .medium)` and `DS.action`
after the label, only for N > 0, where N counts the KEYS of the selected
action's end patch the tab's sections write — Picture the video keys but
`motion`, Clip `motion`, Sound the audio keys, Text the text keys, Shape
none. `refresh()` redraws only when a count changed.

**The block knob.** `InspectorSliderControl` draws `BlockSliderCell.drawKnob`'s
7 × 11 pt block in `DS.textStrong` at full alpha, its rect snapped to device
pixels (`backingAlignedRect`, `.alignAllEdgesNearest`); the rail's inset
and the value mapping use the 7 pt width, and the accent fill runs to the
SNAPPED knob's `midX`, so the two meet on a pixel edge. Dimming stays the
view's `alphaValue`.

**Two owed items from phase 1.** The park clamp is
`min(action.endTime, max(snapshot.duration - frame, 0))`: a clip shorter
than a frame (which `Project::validate` lets through on read) parked the
playhead BEFORE its own start. The Curve popup goes through the new typed
`OptionPopupControl` init (`OptionControls+Choices.swift`), values in and
out, no index array beside it.

## 4. Phase 2's record

**What landed.** Three new files — `ClipSelectionHeader.swift` (a pure move
of `ClipSelectionHeaderView` out of `ClipPane.swift`), `ClipPinnedBlock.swift`
(`ClipSubTab`, `ClipSubTabsView`, and `ClipHeaderBlock` moved out of
`ActionLaneView.swift`) and `OptionControls+Choices.swift` — and changes in
`ClipPane`, `ActionLaneView` (the Curve popup), `InspectorPane`
(`pinnedBlock`, `sections` readable, `InspectorSection.id`/`title`
readable, the knob), `InspectorViewController` (frozen; wiring only),
`VideoPane+Motion` and `TextPane` (one title each) and
`EditorViewController+Actions` (the clamp). No core, FFI, op or tool change.
The sizes are `designs/reelcut-remaining.md` §3's phase-2 paragraph.

**What was measured.** The two pure moves alone, before anything else:
`make typecheck` at its baseline, 0 errors and 7 warnings. At the end:
`make typecheck` 0 errors and 7 warnings; `make test` (816 passed, 0
failed) and `make lint` clean, the core untouched; `make app` rc 0; the
built app's log carries no `Reelcut: ` line. `clip_inspector2_proof.py`
**32/32** — the probe's 21 rows (T1 ×5, T2 ×6, T3 ×4, T4 ×2, T5, T6 ×2, T7)
plus its build and presence rows, and nine harness rows (H1, H2 ×3, H3 ×2,
H4 ×3). `--mutant tabs` exits 0: the six T2 rows fail and nothing else
does. T7 was run once over a copy of `app/Sources` with l.29 put back to
`min(action.endTime, snapshot.duration - frame)`: it FAILED, the playhead
parked at **1 180 000** (the clip starts at 1 200 000), 20/21 probe rows.
Re-run: `phase3_chrome.py` **33/33**, `e2_chrome.py` **52/52**,
`sharp_chrome.py` **29/29**, `clip_inspector_proof.py` **39/39**.

**Deviations, each for a reason.**

- **"8/10 padding" is 8 pt top and bottom, 10 pt sides**, and a text clip
  opens on Text (its first tab) — both recorded in CI-5.
- **The knob is `DS.textStrong` at full alpha**
  (`withAlphaComponent(1)`), which is `BlockSliderCell.drawKnob`'s own ink
  when enabled. `labelColor` is translucent, so a knob in it composited
  over the two-colour rail split in two on its centreline (measured
  (221, 221, 221) and (224, 224, 224) at scale 2); opaque, it is one run of
  (255, 255, 255), 14 px, between the accent and the rail.
- **`clip_inspector_proof.py` scores 39/39, not 38/38.** It scored 39 on the
  phase-1 tree before this phase touched it: S3 has five rows, which phase
  1's record counted as four. Its row 4 now takes the FIRST run of mint
  rows down the column, a gap of up to 4 pt staying inside the run: the
  selected band's curve crosses the column (mint at 156–164.5 and
  167–175.5 pt), so a run of strictly adjacent rows stops at the curve and
  measured a 9 pt band. The strip's `◆1` is 40 pt and more below.
- **`e2_chrome.py`'s embedded probe changed too**, not only its four
  renders: its `editor()` helper selects the Clip sub-tab (Motion presets
  lives there), and `rowControl` looks inside the `video.motion` section
  first, because on the Clip tab Timing's own "In" row comes before
  Motion's. Before the two edits the file scored 32/36 and then 50/52.
- **`phase3_chrome.py`'s shift band** starts at 955 pt, just above the
  two-region render's tail (the Add Region · Place on Canvas row, 963–985
  pt) and runs 200 pt; at the winning shift it is compared with the
  one-region render's 781–981 pt, which holds that render's tail (789–811
  pt). A band holding both tails in the SAME rows also passes, but thinly
  (50 mismatched rows against a runner-up of 235), because it compares
  Region 2's rows with Region 1's. TALL stays 1500: the two-region section
  ends at 993 pt against a visible area ending at 1200, so neither render
  has a scroller.
- **The detail row's widths are decided**: Start stays 104 pt
  (`InspectorTimecodeField`'s `hh:mm:ss:ff`) and Curve 70 pt, closing phase
  1's note.

**Owed.** A person checks the strip, the badge and the block knob in both
appearances, the block staying put while the sections scroll, and a real
click on a sub-tab (remaining §4). The other Clip-tab photographs
(`phase2`, `phase4`, `phase6`–`phase9`, `e1`, the word-caption chrome) were
not re-run in this phase; each now opens on its selection's first sub-tab.
