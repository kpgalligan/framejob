# Handoff: Clip inspector redesign (Reelcut)

## Overview

A redesign of the **Clip** tab of Reelcut's inspector (the 304 pt right-hand panel). It answers the brief in `uploads/clip_inspector_brief/README.md` (build `6e3f5c7`, 2026-09-23). It solves:

- **P1 density and P2 no audio/video split:** the Clip tab gets sub-tabs, Picture · Sound · Clip (Text · Picture · Clip for text clips).
- **P3/P4 buried actions:** a **pinned action lane** sits at the top of the Clip tab. It is a mini timeline of the selected clip's actions, where you select, move and retime them.
- **P4 selection:** an explicit **selected action**, highlighted on the timeline and in the lane.
- **P5/P6 marking:** row-level **marks** for what the selected action changes, with badges on collapsed section headers and sub-tabs.
- **P8:** fields always show and edit the action's **end value**. The value at the playhead is a read-only coral tick or readout.
- **P7, P10, P11:** one Reset/Clear rule, and explicit "not animated" handling.

Decisions confirmed by the product owner:

- Panel layout is direction **1b** (pinned lane + three sub-tabs).
- Action colour is **mint `#5CD6B0`**.
- Field behaviour is **1g** (end-value fields, playhead value shown but not editable).
- Appearance is dark only for now.

## About the design files

The files in this bundle are **design references created in HTML**. They are prototypes showing the intended look and behaviour, not production code to copy. Reelcut is a native **AppKit** app (Swift, `app/Sources/`) over a Rust core. The task is to **recreate these designs in AppKit** using the existing `DS` tokens (`Theme.swift`), controls (`Controls.swift`), `InspectorPane.swift` and `TimelineView.swift`.

Every new control that changes the project needs a matching MCP agent tool, as the brief says. The design adds no new edit types beyond what the core already supports (see "Engineering mapping").

## Fidelity

**High fidelity.** Colours, type, metrics and interactions are final for the dark appearance. Material Symbols icons in the HTML stand in for **SF Symbols**; use the mapping in "Assets".

## Files

| File | What it is |
|---|---|
| `Clip Inspector Prototype.dc.html` | **The spec.** Interactive prototype of the chosen direction: toolbar with transport, inspector, and timeline with draggable action bands. Open it in a browser from this folder. |
| `Clip Inspector Redesign.dc.html` | Exploration board. Shows directions 1a/1b/1c, colour options 1d–1f, P8 options 1g/1h, the timeline band states at S/M/L (1i), and the marking + Reset model (1j). **Chosen: 1b + 1e + 1g.** 1i and 1j apply as drawn. |
| `ClipRow.dc.html`, `ClipSectionHeader.dc.html`, `ActionCard.dc.html`, `ActionClip.dc.html` | Static sub-components used by the board. |
| `support.js`, `_ds/` | Runtime and design-system bundle needed to open the HTML. |

The prototype's logic class (the `<script data-dc-script>` block at the bottom of the prototype file) holds the full property schema: sections, rows, ranges, units, defaults and which properties are animatable. It is a useful checklist.

---

## Panel anatomy (304 pt wide, resizable 280–440)

From top to bottom, all regions separated by 1 pt `--border` (#3a3a3a) lines:

1. **Panel tabs** "Clip · Media · Document": unchanged, 32 pt.
2. **Selection header**: unchanged, 44 pt. Kind chip 8×26, name sans 12 semibold, mono 10 meta line.
3. **Pinned action lane block**: new. It is always visible on the Clip tab and does not scroll. Padding 8 top, 10 sides, 9 bottom; rows 6 pt apart.
   - **Header row** (18 pt):
     - "ACTIONS" in mono 10 / 500 / tracking 0.09em / `--text-muted`;
     - the count in mono 10 `--text-faint` (the word `none` when 0);
     - when an action is selected, "· editing N" in mono 10, action colour.
     - Right-aligned are three track-size ghost buttons (20×18, 13 pt symbols): **Zoom to Region** (Z), **Zoom Back**, **Add Action** (⌥⌘K).
   - **Lane row** (28 pt tall):
     - A **"Clip" chip** (40 pt wide) is the "edit the clip itself" target. It is active (`--selection-fill` + `--accent-border`, text `--text-strong`) when no action is selected. Otherwise it reads `--surface-control` / `--border` / `--text-muted`.
     - A 4 pt gap, then the **lane**: flex, 1 pt `--border` on `--surface-well` (#171717). It represents the whole clip, from its start to its end. Contents:
       - **Action bands** from inset 4 pt top and bottom, positioned by start/duration as a fraction of the clip:
         - Normal: action colour at 34% with 1 pt edges at 75%, and the number in mono 9 / 600, white.
         - Selected: solid action colour with the number in `#101010`.
         - A zoom action adds a `zoom_in` / `plus.magnifyingglass` 11 pt glyph after the number.
         - The outer 4 pt of each band is a resize zone.
       - **Playhead**: 1 pt coral `#F4653F` line, shown when the playhead is within the clip.
       - **Transition overlap**: the DS hatch (45°, 3/7 px, white 26%) at the clip start, with a 1 pt white-40% right edge.
       - **Fades**: 10 pt-tall ramps (white 16%) at the bottom-left (in) and bottom-right (out), sized by fade duration.
       - **Motion preset wedges**: 8 pt-tall triangles, `--text-faint`, 0.5 s wide, top-left for In and top-right for Out.
       - Empty state: centred mono 10 faint "no actions · ⌥⌘K adds one".
   - **Action detail row** (shown only when an action is selected): a grid of `76 | 58 | 1fr | 22` with 5 pt gaps, all controls 22 pt tall.
     - **Start**: the strong timecode field (`--border-strong` on `--surface-field`, mono 11 / 500), in **clip-relative `mm:ss:ff`** such as `00:02:15`. It also accepts plain seconds.
     - **Length**: a field such as `1.50 s`.
     - **Curve popup**: a 16×10 curve glyph drawn in the action colour, the curve name without "Ease " ("In Out"), and `unfold_more`. Menu: Linear / Ease In / Ease Out / Ease In Out.
     - **Remove**: a 22×22 boxed trash button.
   - When an action is selected, the whole lane block gets a 7% action-colour wash.
4. **Sub-tabs**: 8/10 padding. Three equal cells, 24 pt tall, 1 pt borders collapsed (−1 pt margin), sans 11 / 600.
   - Active cell: `--selection-fill` + `--accent-border`, text `--text-strong`.
   - Inactive cell: `--surface-control` + `--border`, text `--text-muted`.
   - With an action selected, a badge `◆N` in mono 9 / 500, action colour, follows the label. N is the number of keyed rows on that tab.
   - Tabs:
     - video, image and still clips: **Picture · Sound · Clip** (Sound only with live audio);
     - text clips: **Text · Picture · Clip**;
     - audio-only clips: **Sound · Clip**.
5. **Scroll view** of sections.

### Sub-tab contents

- **Picture:** Transform, Crop, Corner Radius, Color, Chroma Key, Shadow, Filters, Reflection, Spotlight, Obscure. The prototype omits Corner Radius, Chroma and Obscure for brevity; keep them.
- **Sound:** Volume, Fades, Ducking, Noise Reduction, Compressor, Mix.
- **Clip:** Timing, Speed, Transition (only when overlapping the previous clip), **Motion presets** (renamed from "Motion" to separate them from actions).
- **Text:** Content, Font, Style, Outline, Backdrop, Box, **Reveal** (renamed from "Animation" so it isn't confused with actions), Presets.
- Shape clips (not mocked): **Shape · Picture · Clip**. The Shape tab holds Shape, Stroke, Fill, Gradient and Arrowheads, all ⊘ (not animatable).
- The **Actions section is removed** from the list; the lane replaces it.

Default sub-tab when a clip is clicked: **Picture** (Sound for audio-only). In the prototype, text clips open on Text; confirm with the owner.

### Section header (28 pt)

- Background `--surface-bar` (#262626), 1 pt `--border-subtle` top, hover `--hover-row`. Padding 0 6 0 4.
- In order:
  - chevron 15 pt (`expand_more` / `chevron_right`);
  - TITLE in mono 10 / 500, uppercase, 0.09em tracking, `--text-muted`;
  - optional mark badge;
  - flexible space;
  - summary in mono 10;
  - optional Reset/Clear button (the DS `Button`, size sm, 22 pt, mono 11).
- Mark badges:
  - `◆N`: mono 9 / 500 in the action colour, where N is the number of rows keyed in the selected action.
  - `◇`: `--text-faint`. Another action on this clip changes something here.
  - `⊘`: `--text-faint`. With an action selected, nothing in this section can be animated.
- Summary colour: the action colour if the section has keys, `--text-body` if it differs from its default, otherwise `--text-faint`. With an action selected, the summary reflects the **end values**.
- Open state is remembered per section, as today. **Selecting an action auto-opens every section it keys.**

### Row (22 pt controls, 7 pt between rows, body padding 8 top / 10 bottom)

- **Columns:**
  - a **14 pt mark gutter** (mono 9–10, centred);
  - a **64 pt label** in sans 11. The colour is `--text-muted`, `--text-strong` when keyed, and `--text-dim` when ⊘;
  - the controls, with an 8 pt gap;
  - 6 pt right padding.
- **Slider + field:**
  - The rail is 3 pt in `--border`. Its fill is `--accent-rule` #62b0ff, except when keyed, where there is no blue fill (see below).
  - The knob is a **7×11 block** in `--text-strong`, replacing the round knob.
  - The value field is 70 pt, mono 11, with an optional `expand_more` quick-values menu.
- **Field only:** 76 pt. **Popup:** 116 pt (Family 150, transition Kind 140).
- Checkboxes carry their own label and have no label column.
- Colour well 22×22, segmented cells 28×22, text area min 56 pt, buttons 24 pt.
- Disabled rows use 42% opacity.

## Row marks (shared model, see board 1j)

| Mark | Meaning | Drawing |
|---|---|---|
| `◆` action colour | **Keyed** in the selected action. Numbers and colours glide to this end value. | The field/popup border turns the action colour. On sliders the blue fill is replaced by an **action-colour segment from the start value to the end value**, and the knob sits at the end value. |
| `◆` + "at end" tag | Keyed switch: on/off, text, enums, blend. It changes at the end of the span. | Mono 10 "at end" in the action colour after the control. |
| `◇` `--text-faint` | **Changed by another action** on this clip. Held during the selected action; editing it adds it to this action. With no action selected, it means some action changes this row. The owner can turn this off; the prototype has a `baseMarks` tweak. | Tooltip "Changed by action N". |
| `○` action colour | **Follows** a keyed value: a read-only readout that moves because its source is keyed (Gain follows Volume). | Shows a coral "now …" tag. |
| `⊘` `--text-faint` | **Not animatable:** Motion presets, shape properties, pan, compressor, noise reduction, ducking, mono, timing, speed, transition. With an action selected, **edits go to the clip itself** (P7), never into the action. | Label `--text-dim`, control border dashed. A section where everything is ⊘ shows `⊘` in the header and one note line in sans 11 `--text-dim`: "Actions don't animate this. Edits here change the clip." A single ⊘ button inside an animatable section (Normalize) gets a boxed mono 9 "clip" tag. |
| coral tick | **Value at the playhead** (P8). It uses the playhead's ink, so it reads as "now". | A 2×11 pt `#F4653F` mark on the slider rail at the playhead value. Field-only rows show mono 10 coral `now −212 px` after the field instead. Shown whenever the playhead value differs from the displayed value, in both modes. Never editable. |

## Behaviour

### Editing target (the "mode")

- **Selected action** is new view state, like the selection or the playhead. It is `nil` or one action on the selected clip.
- **With no action selected**, fields show and edit the clip's **base** values.
- **With an action selected**:
  - animatable fields show and edit that action's **end value** (keyed), or the held value (unkeyed; editing it adds a key);
  - ⊘ fields edit the base;
  - derived readouts show the end state.
- **Fields always show the value they write (P8).** Typing 60% leaves 60% in the field, and dragging a slider keeps the knob under the pointer. The coral tick moves to the interpolated playhead value.
- **Selecting an action** (click its band in the lane or on the timeline, or finish dragging it):
  - moves the **playhead to the action's end**, so the preview matches the fields;
  - auto-opens the sections it keys;
  - keeps the current sub-tab.
- **Scrubbing or playing into an action** auto-selects it, as today. This happens only on *entering* a span: after esc, the playhead can sit inside the span without re-selecting until it leaves and comes back. Scrubbing *out* of a span **does not** leave the mode.
- **Leaving the mode:** **esc**, clicking the **Clip** chip, or **selecting another clip**. Clicking empty timeline does *not* leave the mode.
- Selecting another clip clears the selected action. If the playhead is inside one of that clip's actions, that action is auto-selected.
- **Canvas handle drags** (move, scale, rotate, crop) follow the mode (P9): with an action selected they write the end state.
- **Unchecking a switch** with an action selected keys it **off** rather than removing the key (P10).

### Reset / Clear (P11)

- With no action selected:
  - **Reset** appears only when a section differs from its default, and always returns the whole section to its default (off, neutral, 100%, default font). Stroke, Shape and Style follow the same rule.
  - Sections with no default have no Reset slot: Content, Timing, Transition.
- With an action selected:
  - the same slot reads **Clear**, and appears only if the section has keys in the action;
  - it **removes those keys** from the action (the core's "clear property" op), and the values fall back to what was held. Tooltip: "Remove this section from action N".
- **Per row**:
  - on hover, a keyed row shows **×** at its right end ("Remove from action N");
  - **right-click** any row for a context menu: "Remove from action N" (keyed rows), "Go to action M" (◇ rows, which selects the action that sets the value), and "Reset to default" / "Set end value to default".
- The per-section blue "Editing action N's end state" note is **removed** everywhere (P6). The lane's "· editing N" label, the wash and the row marks replace it. Inline notes stay only for real warnings: blend with nothing behind it, and Reveal overridden by word captions.

### Actions

- **Add Action** (⌥⌘K, lane `+`) adds at the playhead:
  - 1 s, or up to the next action or clip end if shorter;
  - linear curve and an empty end state;
  - frame-snapped;
  - then selects it.
  - It is **refused** when the playhead is off the clip, or inside an existing action, or the gap is under 2 frames. Refusals appear as a message at the bottom of the panel (popover fill, sans 11), phrased as a rule plus what to do, for example: "Refused: actions on one clip can't overlap. Move the playhead into a gap between actions."
- **Zoom to Region** (Z) arms the canvas tool as today and adds an eased in-out action with scale, x and y keys. The prototype simulates it. **Zoom Back** adds an action that returns to the base scale and position. Zoom actions carry the zoom glyph in the lane and on the timeline, and a "Zoom 600%" label.
- **⌫ / Delete** removes the selected action.
- **Retime:** drag a band's body to move it, or its outer 4–5 pt to resize either end, in the lane or on the timeline. Rules:
  - frame snap (1/30 s);
  - a band stops at its neighbours and the clip edges and never overlaps;
  - minimum length 2 frames.
  - Maps onto the existing `set_action`. Dropping selects the action and parks the playhead at its end.
- Start and Length can also be typed in the detail row.
- **Numbering** is by time order (1…n), not creation order.

### Timeline treatment (board 1i)

Each clip gets an **action lane directly under its 16 pt name strip**, full clip width, on a black-22% backing. Lane height by track size:

| Track size | Text track | Video track | Lane |
|---|---|---|---|
| S | 30 | 54 | 5 |
| M | 44 | 84 | 12 |
| L | 58 | 116 | 18 |

Band states:

- **Normal:** action colour at 34%, 1 pt edges at 75%. From M up, the number (mono 9 / 600, white); at L also the label (sans 10 / 600, e.g. "opacity, rotation +2").
- **Hover:** 62% fill, solid edges, label at M/L, 5 pt white-80% grips at both ends (resize zones), cursor grab / col-resize.
- **Selected:**
  - solid action colour, text `#101010`, grips black-45%;
  - the **curve drawn inside** as a 1.25 pt line at black-45% (from M up);
  - a **12% action-colour wash with 55% edges down the clip body** under the span;
  - the span shaded on the **ruler** at 20% with a 2 pt action-colour bottom rule.
- **Dragging:**
  - a **dashed 1 pt ghost** at the original position;
  - a **HUD tag** above the clip (popover fill, mono 10) reading `00:02:21 → 00:03:21  +0:06` (new start → new end, then the offset in s:ff), or `len +6f` when only the length changes.
- S size draws bars only: no number, label or curve.

The clip keeps its coral 2 pt selection ring and 5 pt white-38% trim grips.

## State (per window)

- `selectedClipIDs`: existing.
- `selectedActionID: ActionID?`: new view state. It is not undoable.
- `lastInsideActionID: ActionID?`: tracks span *entry* so auto-select fires only when the playhead enters a span.
- `playhead`: existing. Selecting an action sets it to `clip.start + action.start + action.duration`.
- `clipSubTab`: `picture | sound | clip | text | shape`, reset to the kind's default on clip change.
- `sectionOpen[sectionID]`: existing, persisted.
- `trackSize`: existing S/M/L.

Display value for property `k`:

- no action selected: `base[k]`;
- action selected, `k` keyed: `action.end[k]`;
- action selected, `k` unkeyed: `evaluate(k, at: action.start)`.

The coral tick is `evaluate(k, at: playhead)`. Evaluation walks the actions in time order: completed actions set the value, and a span in progress interpolates from the held value along its curve. Numbers and colours glide; switches, text and enums change at the end.

## Design tokens

- **Surfaces:**

  | Token | Value |
  |---|---|
  | `--surface-panel` | #242424 |
  | `--surface-bar` | #262626 |
  | `--surface-control` | #2b2b2b |
  | `--surface-field` | #1d1d1d |
  | `--surface-well` | #171717 |
  | `--surface-timeline` | #1d1d1d |
  | `--surface-lane` | #1f1f1f |
  | `--surface-ruler` | #232323 |
  | `--surface-popover` | #2e2e2e, with border #454545 |

- **Borders:** `--border` #3a3a3a, `--border-subtle` #303030, `--border-strong` #55554f, `--border-lane` #2a2a2a.
- **Text:**

  | Token | Value |
  |---|---|
  | `--text-bright` | #f0efe9 |
  | `--text-strong` | #e6e6e4 |
  | `--text-body` | #dcdcd8 |
  | `--text-muted` | #b9b9b3 |
  | `--text-dim` | #9a9a95 |
  | `--text-meta` | #8f8f8a |
  | `--text-faint` | #6e6e68 |
  | `--text-ghost` | #55554f |

- **Accent:** `--accent-rule` #62b0ff, `--accent-border` #4a7fd0, `--accent-text` #8cc6ff, `--selection-fill` rgba(10,132,255,0.24), `--check-fill` rgba(10,132,255,0.30), `--menu-highlight` #3d6ea8.
- **Fixed inks:** playhead coral **#F4653F**, snap butter #F2C14E. Clip tints: video #3E5063, audio #2C7A58, text #B17C1E, shape #247686.
- **New action colour: mint `#5CD6B0`.**
  - Washes: 7% (lane block), 12% (clip-body span), 20% (ruler span), 34% (normal band), 62% (hover band).
  - Text on a solid band: #101010.
  - Light appearance, not yet designed: use **#1E8F6E** for marks and borders, with the same washes.
  - It must not be used for anything but actions.
- **Clip overlays:** strip black 26%, name white 92%, icon white 62%, grip white 38%, hatch white 26% with edge white 40%.
- **Type:**
  - Source Sans 3 400/600 at 10–13 pt for UI.
  - IBM Plex Mono 400/500 at 9–12 pt for all numbers and the uppercase micro-labels (0.09em tracking).
- **Metrics:** control 22, button 24, tab 32, sub-tab cell 24, section header 28, lane row 28, label column 64 plus a 14 mark gutter, slider field 70, field 76, popup 116.
- **Spacing:** 2 / 3 / 6 / 7 / 8 / 9 / 10 / 12.
- **Radii:** 0 on all chrome, 2 pt on timeline clips.
- **Motion:** 140 ms hover, 220 ms section collapse and track-size change, easing (0.2, 0.7, 0.3, 1). Respect Reduce Motion. Mode switches are instant.

## Assets

No images. Icons are Material Symbols in the HTML; use the SF Symbols equivalents:

| Material | SF Symbol | Used for |
|---|---|---|
| `zoom_in` | `plus.magnifyingglass` | Zoom to Region, zoom action glyph |
| `zoom_out` | `minus.magnifyingglass` | Zoom Back |
| `add` | `plus` | Add Action |
| `delete` | `trash` | Remove action |
| `close` | `xmark` | Remove from action |
| `unfold_more` | `chevron.up.chevron.down` | Popups |
| `expand_more` / `chevron_right` | `chevron.down` / `chevron.right` | Quick menus, section chevrons |
| `movie` | `film` | Clip strip |
| `title` | `textformat` | Clip strip |

The glyphs ◆ ◇ ○ ⊘ are text characters set in mono.

## Engineering mapping

- Moving or retiming an action: the existing `set_action`.
- Remove from action / Clear: the existing core "clear property from action" op, which today has no UI.
- ⊘ edits while an action is selected write the **base** value. This is a UI routing change; it stops the silent no-op writes of P7.
- Canvas handle drags go through the same routing as the inspector (P9).
- "Selected action" is view state and needs no op. Agents can keep addressing actions by ID.

## Not covered yet

- Light appearance.
- Audio-only, shape and multi-selection states. The rules above cover them: with a multi-selection, the lane reads "Select one clip to edit its actions.", marks follow the first clip, and `mixed` badges appear on every row, sub-rows included (P12).
- Snapping bands to the playhead.
- Canvas preview behaviour.
