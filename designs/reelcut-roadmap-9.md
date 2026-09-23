# Reelcut — road map 9: the clip inspector redesign

**Status: phase 1 BUILT, 2026-09-23 (§2). Phases 2–5 are designed by the
handoff and not built (§0).**

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
2. **Sub-tabs and the pinned block** (P1, P2) — Picture · Sound · Clip
   (Text · Picture · Clip, Shape · Picture · Clip, Sound · Clip), the
   section regrouping and the two renames (Motion presets, Reveal), the
   selection header and lane PINNED above the scroll view, the 7 × 11 block
   knob on the inspector's sliders, sub-tab badges.
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
and `phase3_chrome.py` is **32/33**. Its failing row is "the content below is
the one-region render pushed DOWN by six rows" (the best shift is still
174 pt, but at 157 mismatched rows of 400): that proof holds `video.actions`
open (`INSPECTOR_BELOW`) so the section stack has no slack when Obscure
opens, and the Actions section no longer exists, so the stack now has slack
and the rows below Obscure redistribute. The instrument needs a new
section to hold open below Obscure (or a taller window), re-measured —
not done here, because the phase's spec does not name the file. Every
other Clip-tab photograph now carries the lane block under its header and
was not re-run in this phase. A person still checks the lane and the bands
in both appearances (the light ink `#1E8F6E` is the handoff's placeholder),
and a real click on a band and esc in the running app.
