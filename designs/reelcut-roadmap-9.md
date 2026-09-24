# Reelcut — road map 9: the clip inspector redesign

**Status: phases 1, 2, 3a and 3b BUILT, 2026-09-23 (§2, §4, §6, §8).
Phases 4 and 5 are designed by the handoff and not built (§0).**

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
3. **Marks and Reset/Clear** (P5, P11), split in two:
   - **3a, the row marks** — BUILT, §5 and §6. The ◆ ◇ ○ ⊘ gutter and "at
     end", the keyed slider segment and field border, the coral playhead
     tick and the "now" tag, header badges, summary ink, the all-⊘ note,
     and auto-opening the sections an action keys.
   - **3b, Reset/Clear** — BUILT, §7 and §8. Reset only when a section
     differs from its default and the summary's body tier; Clear in the
     header with an action selected; per-row × on hover; the row context
     menus (Remove from action N, Go to action M, Reset to default, Set end
     value to default); the refusal strip at the panel's foot.
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

## 5. Phase 3a's design

**Two pure moves first** (app/CLAUDE.md "Placement"), each typechecked at
the baseline alone: `InspectorSection` and `InspectorSectionHeader` out of
`InspectorPane.swift` into `InspectorSection.swift`, and the binding's
`// MARK: Writes` … `edited()` into `InspectorBinding+Writes.swift` as an
extension (its `inspector` loses `private`).

**The mark** (spec §11 CI-7, `InspectorMarks.swift`). A row's paths are the
`"group.key"` strings of the ops it writes — `set_video`, `set_audio` and
`set_text` by their patch's keys, `set_action_end` by its patch's groups —
taken from the row's own `ops(read())` at BUILD time, so they are right
whether the write lands on the base or on the end patch; any other op has
none. `RowMark` is `.none`, `.keyed`, `.keyedAtEnd`, `.other(N)`,
`.follows` or `.notAnimatable`. Both lists empty is `.none`, action or no
action. With an action selected: writes and no `set_action_end` among them
is ⊘; a write in the action's end patch is ◆ (`.keyedAtEnd` for a popup or
a checkbox); a follow in it is ○; another action keying one is ◇ with that
action's time-order NUMBER; else none. With none selected, ◇ when any
action keys it. The gutter (`InspectorMarkGutter`, 14 pt, the row's FIRST
view with no stack spacing after it) draws the glyph in mono 10 — ◆ and ○
`DS.action`, ◇ and ⊘ `DS.textFaint` — sets the label's ink (`textStrong`
keyed, `textFaint` ⊘, else `textMuted`) and a 1 pt `DS.action` layer border
on the row's fields and popups while keyed. "at end" is an
`InspectorRowTag`; a field-only value row gets a coral "now …" tag when the
value at the playhead differs by more than half a display unit.

**Reads at three times.** `InspectorBinding.at(_:_:)` runs a read in a
`ReadMode` — `.end` (the selected action's end, CI-2), `.start`
(`clip_state` at `clip.start + action.start`) or `.playhead` (the document's
playhead whenever it is inside the clip, whatever is selected) — over a
cache keyed by clip and mode. `startValue` and `nowValue` are the slider's
two new inputs: keyed, its fill runs in `DS.action` from the start's
fraction to the knob (no accent fill), and a 2 × 11 pt `DS.playhead` tick
marks the playhead's value, over the fill and under the knob.

**The section** folds its gutters into `marks` (keys written that the
action holds, any ◇, all-⊘) at the end of `init` and on every `refresh()`,
draws `◆N` / ◇ / ⊘ after its title and the summary in `DS.action` when
keyed, and shows the ⊘ note first in its content when every writing row is
⊘ — which replaces Motion presets' own note. `reveal()` expands without a
preference; only the header's click (`toggle()`) writes one and calls
`didToggle`.

**Auto-open** (spec §11 CI-8). `KeyedReveal`, one per `ClipPane`, is
applied at the end of `makeSections()` with the selected action's id and
the sub-tab: a new action resets it; a sub-tab not yet seen adds its keyed
sections; every section it holds is revealed on each rebuild; a header
click removes that section. Nothing changes in `InspectorViewController`.

## 6. Phase 3a's record

**What landed.** Three new files — `InspectorSection.swift` and
`InspectorBinding+Writes.swift` (the two pure moves out of
`InspectorPane.swift`, each typechecked at the baseline alone, 0 errors and
7 warnings, before anything else landed) and `InspectorMarks.swift` — and
changes in `InspectorPane` (the metric, the gutter in `inspectorRow`, the
builders' `writes:`, the slider's segment and tick, the "now" tag,
`ReadMode` and `at(_:_:)`, `editsAction` deleted), `ClipPane` (the
`KeyedReveal` and its call; In and Out's `writes:`), `VideoPane` (the
`writes:` of Blend, the filter row, the Region row, Center and Size),
`VideoPane+Motion` (its note deleted), `TextPane` (Content inside an
`inspectorRow`; `writes:` on Family, Style, Align, Vertical and Mode) and
`AudioPane` (Gain's `follows:`). `InspectorViewController` (frozen) took 0
lines. No core, FFI, op or tool change. The sizes are
`designs/reelcut-remaining.md` §3's phase-3a paragraph.

**What was measured** (2026-09-23). `make typecheck` 0 errors and 7
warnings after each move and at the end; `make test` (816 passed, 0
failed) and `make lint` clean, the core untouched; `make app` rc 0, and the
built app's log carries no `Reelcut: ` line. `clip_inspector3_proof.py`
**31/31** — the probe's 24 rows (M1 ×11, M2 ×4, M3 ×2, M4 ×4, M5, M6, M7
×2) plus its build and presence rows, and five harness rows (H1, H2, H3 ×2,
H4): on this host, scale 2 in Display P3, Opacity's rail at 412.5 pt held
78 mint px and no accent, the coral tick was one 4 px run 22 px tall, and
the gutter's ◆ sat at 412–417 pt with none in the Scale row.
`--mutant marks` (a `keyedPaths()` that answers nothing) exits 0: eleven
rows of M1, M2, M3, M4 and M6 fail — Opacity, Volume, Gain and the filter
row, Transform's header, "at end", all four auto-open rows and the `◆N`
agreement — and M5, M7 and the rows that do not read the selected action's
keys (◇, ⊘, blank) hold.

**Re-runs.** `clip_inspector_proof.py` **39/39**,
`clip_inspector2_proof.py` **32/32**, `phase3_chrome.py` **33/33**,
`sharp_chrome.py` **29/29** and `e2_chrome.py` **52/52** hold on this
tree. No row needed re-measuring for the 14 pt shift: none of them reads a
control column's x. `e2_chrome.py` scored **51/52** until one row was
updated in place, dated: "zero In inside an action keeps the base-props
note" looked for Motion presets' deleted sentence and now looks for the ⊘
note that replaces it. **`e1_chrome.py` scores 10/15**, its first run since
phase 1, and scores the SAME 10/15 on phase 2's tree (`835c399`, run in a
worktree): five rows fail for a phase-2 reason — the Transition section
lives on the Clip sub-tab since phase 2, and the instrument photographs and
probes a shape clip on its default tab (Shape), so "this tree's Transition
section opens", "the two trees' section bodies are compared", "Kind, Curve
and Duration, in that order", the Crossfade Audio checkbox and "both style
rows are reachable" find no Transition section. **Owed**, not fixed here:
the instrument asks for the `clip` sub-tab (the harness's fourteenth
argument, and `selectClipSubTab` in its probe).

**Deviations, each for a reason.**

- **`inspectorRow` takes `binding:`** beside `writes:` and `follows:`. The
  gutter asks the binding about the selected action and a `ReelOp` carries
  none, so every call site that passes `writes:` passes the binding too;
  the gutter holds it weakly and a row without one is `.none`.
- **A row is DISCRETE by its controls**, not by a builder argument: a
  popup, a checkbox or a segmented control. That covers the typed builders
  and the hand-built Blend, filter, Region, Family, Style, Align, Vertical
  and Mode rows alike. A colour row is continuous (a colour ramps), so it
  never says "at end".
- **The gutter is as tall as its row, not 22 pt.** A fixed 22 would have
  grown every row of bare text ("No filters on this clip.", "No markers…")
  and moved everything under it.
- **◇ is the single selected clip's.** An action's number is its clip's;
  with several clips selected no row is ◇.
- **The Content area stretches**: `InspectorTextArea` hugs at priority 1 and
  `inspectorRow` gives it no trailing spacer, as it does a slider.
- **The "at end" tag is on every row**, hidden unless the gutter says
  `.keyedAtEnd`; the "now" tag is on every field-only value row, hidden
  unless the playhead's value differs by more than half a display unit.
  Both are detached while hidden, so neither moves a row.
- **Not built, from the handoff:** the 64 pt label (76 stays, CI-7), the
  dashed ⊘ border, the boxed "clip" tag on a lone ⊘ button, a "now"
  readout on ○ and on colour and popup rows, a keyed border on colour
  wells, `DS.textDim` (⊘ is `DS.textFaint`), hover states, Reduce Motion
  and the 8/10 body padding.

**Owed.** Phase 3b (§0). A person checks the marks, the segment, the tick
and the auto-open in both appearances in the running app (remaining §4).
`e1_chrome.py`'s five phase-2 rows, above. The other Clip-tab photographs
(`phase2`, `phase4`, `phase6`–`phase9`, the word-caption chrome) were not
re-run in this phase; every control column in them is 14 pt right of
where it was.

## 7. Phase 3b's design

**Three pure moves first** (app/CLAUDE.md "Placement"), each typechecked at
the baseline alone: `InspectorSectionHeader` out of `InspectorSection.swift`
into `InspectorSectionHeader.swift`, `InspectorSliderControl` out of
`InspectorPane.swift` into `InspectorSlider.swift`, and Obscure's section
out of `VideoPane.swift` into `VideoPane+Obscure.swift` as an extension.

**A row's default** (spec §11 CI-9). `InspectorBinding.ReadMode` gains
`.defaults`, in which the four props readers answer `VideoProps.identity`,
`AudioProps()`, `TextProps()` and `ShapeProps()` with no FFI call and no
cache entry. `InspectorRowDefault` is a row's undo name, whether it
differs and the ops that restore it; `.derived` builds one from the row's
own `read` and `ops`: it differs when `read()` is not `at(.defaults, read)`,
and it restores `ops(at(.defaults, read))`. The four typed builders derive
one unless called with `resets: false`, which the eleven rows whose read
bypasses the props pass (Rate; Transition's Kind, Curve, Crossfade Audio and
Duration; Reverse; Canvas Width and Height; Appearance's Background,
Timecode and Fit) — a derived default there could never differ. Blend,
Align, Vertical and Mode build theirs by hand from their existing `read` and
`ops`.

**Reset and Clear.** A section differs when its explicit `differs` says so,
else when any gutter's default differs; Speed, Filters, Obscure, Shape,
Stroke and Appearance pass an explicit one (their rows do not read the
props, or their Reset writes fewer keys than their rows read). A section is
EDITING action N when an action is selected and any of its rows animates.
The header then builds the Clear button always and shows it iff the
section's `◆N` is above zero (tooltip "Remove this section from action
N"); otherwise it shows the Reset button (built only when the section has a
`reset`) iff the section differs. `InspectorSection.clear()` gathers the
keys every gutter writes that the action holds and applies ONE
`set_action_end` whose patch nulls them, under the undo name "Clear". The
summary is drawn short of the VISIBLE button only, in `DS.action` when
keyed, `DS.textMuted` when it differs, else `DS.textFaint`.

**The row.** `inspectorRow` answers an `InspectorRowView` — the horizontal
stack it always built, which now tracks the pointer over itself and owns a
context menu. Hovered, a keyed gutter draws × in `DS.textMuted` in place of
◆, with the tooltip "Remove from action N", and a click on it removes the
row's keys from the action ("Remove from Action"). The menu, never read
from the hover: "Remove from action N" when the gutter is keyed, "Go to
action M" when it is ◇ (selecting action M), then, when the row has a
default, "Set end value to default" with an action selected on a row that
animates, else "Reset to default", enabled only while the default differs.
A field's or a popup's own right-click keeps its own menu.

**The refusal strip** (spec §11 CI-10). `applyEdit`'s `.refused` arm beeps
and posts `projectDocumentDidRefuse`; the editor forwards the refusal to
`InspectorViewController.showRefusal`, and `InspectorRefusalStrip` in the
new foot container under the scroll view shows "Refused: " and the core's
sentence (sans 11, `DS.textStrong`, over `DS.hoverFill` with a 1 pt
`DS.border` top, up to three lines). It remembers the project handle it was
shown under and clears on the first refresh whose `editedProject` is a
different handle — an applied edit, undo, redo or a scope change — or on a
click. An identity still only beeps; an agent's refusal and a live tick's
never reach it.

## 8. Phase 3b's record

**What landed** (2026-09-23). Spec §11's CI-9 and CI-10, §4.3's "Reset,
Clear and the row menu" paragraph and §5.5's amendment were written before
the code. Three pure moves, each typechecked at the baseline alone (0
errors, 7 warnings) before anything else: `InspectorSectionHeader.swift`,
`InspectorSlider.swift` and `VideoPane+Obscure.swift`. Then two new files,
`InspectorRowMenu.swift` (`InspectorRowView`: the row's own tracking area
and its context menu) and `InspectorRefusalStrip.swift` (the strip and
`showRefusal`), and changes in `InspectorMarks.swift` (`InspectorRowDefault`
and `.derived`, `SectionMarks.differs` / `editing`, the gutter's hover, ×,
`removeFromAction()` and appearance-change border, `selectedActionNumber`,
`actionID(number:)`, `clearOps`), `InspectorPane.swift` (`ReadMode.defaults`
and the four readers' short-circuit, `inspectorRow`'s `default:` and
`InspectorRowView`, the four typed builders' `resets:`), `InspectorSection`
(`differs:`, `header`, `clear()`, the fold), the header (Clear,
`buttonTitle`, `summaryInk`), `InspectorViewController` (frozen, +14: the
foot container, the strip, one line in `refresh(isLive:)`),
`ProjectDocument` (`projectDocumentDidRefuse`, `applyEdit`'s two arms),
`EditorViewController+Inspector` (the observer and `documentDidRefuse`),
and the panes: Blend, Align, Vertical and Mode build `.derived` by hand;
Speed, Filters, Obscure, Shape, Stroke and Appearance pass an explicit
`differs`; Rate, Transition's four rows, Reverse, Canvas Width/Height and
Appearance's three rows pass `resets: false`. No core, FFI, op, schema or
tool change; the parity check is untouched. The sizes are remaining §3's
phase-3b paragraph.

**What was measured.** `make typecheck` 0 errors and 7 warnings after each
move and at the end; `make test` 816 passed, 0 failed, and `make lint`
clean, the core untouched; `make app` rc 0, and the built app's log (port
4833) carries no `Reelcut: ` line. `clip_inspector4_proof.py` **46/46** —
the probe's 41 rows (R1 ×4, R2 ×3, R3 ×5, R4 ×4, R5 ×9, R6 ×2, R7 ×6, R8
×8; R7's sixth, that the shown strip spans the inspector's width, added by
the review's fix — it passed on the unfixed tree as well) with its build and presence rows, and three
harness rows: on this host (scale 2, dark) the Transform header's trailing
70 pt, found to end at x 1423 pt (the scroller keeps the rest), held a
tallest non-fill run of 7.5 pt with no action — the "100%" summary — and
22 pt with action 1 selected, the Clear button's edge. `--mutant reset` (a
`derived` whose `differs` answers true) exits 0: exactly R1's
Transform-at-default and Shadow-off rows, R2's faint tier, R5's disabled
row and H2 fail, and R8's explicit rows hold.

**Re-runs on this tree.** `clip_inspector_proof.py` **39/39**,
`clip_inspector2_proof.py` **32/32**, `clip_inspector3_proof.py` **31/31**,
`phase3_chrome.py` **33/33**, `e2_chrome.py` **52/52**, `sharp_chrome.py`
**29/29**; the eight owed since phase 2: `phase2_chrome.py` **26/26**,
`phase4_chrome.py` **59/59**, `phase6_chrome.py` **70/70** (54/70 before the
review's fix, below),
`phase7_chrome.py` **78/78**, `phase8_chrome.py` **150/150**,
`phase9_chrome.py` **62/62**, `words_picture_chrome.py` **5/5**,
`word_captions_chrome.py` **31/31**. Rows re-measured in place, each dated
2026-09-23 in its file:

- `clip_inspector3_probe.swift` scored **29/31** first: M2's two header
  rows compared a whole `SectionMarks`, which gained `differs` and
  `editing`; they now compare the three fields phase 3a measured.
- `phase3_chrome.py` scored **29/33** first and `phase4_chrome.py`
  **57/59**: Reset now appears only once a section leaves its default, so
  the "one region vs an empty list" and "typewriter vs no animation" pairs
  also change the header's Reset — a second cluster inside the same
  header, whose top sits above the summary's. The band is now that first
  pair's extent, and the later pairs must lie inside it.
- `phase7_chrome.py` scored **76/78** first: the translucent canvas makes
  Appearance differ from its default, so its Reset appears; that one
  control-tall cluster straddling the section's line is excused from
  "nothing above moved", and the note's row is found under it.
- `phase6_chrome.py` scored **40/70** first. Its blend fixtures now ask for
  the `picture` sub-tab (Transform is not on a shape clip's default tab),
  and the Transform Reset that Opacity 90% and multiply now show — the
  pixels the two diffs SHARE — is taken out of the row inks and excused
  from the "only the Blend row" checks, which brought it to 54/70. Its 16
  Gradient rows (sections 4–6) failed for a phase-2 reason: on the Shape
  sub-tab only Arrowheads follows Gradient, so a band starting 250 pt
  under the header held only pane fill and every body solved to 0 pt. The
  review's fix pins Arrowheads open in every gradient render and reads the
  band in the SHUT render right under the header, found again in the open
  one (`shift_under`): every body is an exact match at 0 mismatched rows
  against a runner-up of 76, two stops 177 pt as the arithmetic predicts,
  **70/70**.

**e1.** `e1_chrome.py` asks for the `clip` sub-tab in its renders
(arguments 12–14 `-`, `-`, `clip`) and its probe calls
`selectClipSubTab(.clip)` before it reads — the spec's fix — and, beyond
it, finds the Transition section by its id rather than as the LAST
section, because on the Clip sub-tab Motion presets follows it. It scores
**21/21**, not 15/15: the "15" was the count phase 3a saw with sections
2 and 3 short-circuited, and all 21 rows now run. The extent row scored
20/21 first: opening Transition moved the Motion presets section below it
and shut Timing (opened by default only while no other section is), so
this tree's changed-pixel extent was 197 pt against the reference's 71 pt.
The review's fix opens Timing in both of this tree's renders and cuts the
extent at the header of the section that follows Transition: B_now 129 pt,
B_ref 71 pt, 58 = 2 × 29.

**Deviations, each for a reason.**

- **H2 is read as "no button", not "only the header fill".** With Reset
  hidden the summary stops short of the VISIBLE button only, so it is drawn
  inside the trailing 70 pt; H2 asks that no column there carry a run of
  non-fill pixels of 14 pt or more (a mono 10 glyph is under 12), and H3
  that one carries 18 pt or more (a 22 pt button's edge).
- **`SectionMarks.differs` and `editing` have default values**, so the
  three-field initialiser phase 3a's probe and `.empty` use still compiles.
- **The × is the gutter's own glyph** (`DS.textMuted`) and the summary's
  body tier is `DS.textMuted` — CI-9's two recorded deviations from the
  handoff.
- **A hovered row's × needs a key window** (`.activeInKeyWindow`); the
  menu's "Remove from action N" does not, since it reads `isKeyed`.

**Phase 3a's review nits.** (1) In and Out's `writes:` are deleted: a trim
has no patch, so `paths(of:)` always answered `[]` and the rows were
`.none` either way. (2) The binding's `Evaluated` doc says a clip under the
playhead reaches the FFI too, in `.playhead`. (3) The header's comment names
`refresh(summary:marks:)`. (4) `inspectorValueRow` reads `row.gutter`
rather than `row.subviews.first`. (5) The gutter re-resolves its keyed
border's `CGColor` in `viewDidChangeEffectiveAppearance()`.

**Owed.** A person checks Reset, Clear, the ×, the menus and the strip in both
appearances (remaining §4). Phases 4 and 5 (§0). Two review-2 nits, not
fixed:
- Box ▸ Width's derived default is `currentWidth()` in `.defaults`, which
  is `canvas.width × 0.6`, so its "Reset to default" writes a FIXED width
  rather than returning the box to auto-size (`TextPane.swift`, the Width
  row). The fix is `resets: false` there, since Mode's own default already
  restores auto.
- The probe's "shown strip spans the inspector's width" row passed on the
  tree before review 05's fix as well, so nothing proves `span(_:)` is
  needed. Showing, clearing and re-showing the strip at a changed inspector
  width would.
