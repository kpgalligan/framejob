# Handoff: Reelcut — sharp chrome

> **Scope: Reelcut only** (`kpgalligan/reelcut`, AppKit in `app/Sources/`).
> Everything in this folder is about the Reelcut editor window. A separate handoff exists for Rasterize. It is not referenced here and none of its parts belong in this codebase. Do **not** add a tool rail, options bar, layers panel, assistant panel, status bar or zoom HUD to Reelcut.
> *Amended 2026-09-27 by spec §11 AI-4 (road map 12): the Assistant is the inspector's fourth tab, never a panel of its own; the rest of this line stands.*

## Overview

This visual pass follows on from the existing chrome-cleanup handoff (`designs/design_handoff_reelcut/`). That handoff's layout, regions, clusters, metrics and behaviour stay as specified. This one changes three things:

1. **Corners.** Every chrome component goes square (0 radius). Timeline clips are the one exception and take **2pt**.
2. **Slider knob.** The zoom slider's round 11pt knob becomes a 7 × 11pt block.
3. **Light appearance.** Reference values are provided so both appearances can be checked. In AppKit, keep the semantic `DS` colours; they already follow the system appearance.

No core (Rust) changes are needed.

## About the design files

`design/` holds **design references built in HTML**: a clickable prototype of the Reelcut editor. It is not production code to port. Recreate it in AppKit with the repo's existing patterns: self-drawing `NSView` subclasses, `DS` tokens in `Theme.swift`, and `GhostButton`, `AccentButton`, `PanelTabsView`, `DSField` and `DividerView` in `Controls.swift`. Ship SF Symbols. The Material Symbols font in the HTML is only a browser stand-in.

`design/runtime/ds_bundle.js` is a compiled browser runtime that lets the prototype render. It comes from a shared web library that also contains components for another app. **Do not read it, port it, or treat any name in it as a Reelcut requirement.** The Reelcut component list is the one below.

## Fidelity

**High fidelity.** Colours, type and metrics are final. Dark appearance is authoritative; light is reference (see *Design tokens*).

## Screen: Editor window (1440 × 862 content)

```
title bar 30  ─ traffic lights · centred "Untitled Project" + mono meta
toolbar 44    ─ transport ×6 · | · timecode ——— Fit popup · Safe ☐ · | · Export
preview well (flex) ─────────────────────────────┬─ inspector 304
                                                 │  tabs 32: Clip · Media · Document
timeline bar 36 ─ selection block · | · edit ×7 · | · Snap ☑ ——— zoom slider · | · S M L
ruler 22 ─ track headers 132 │ lanes
```

### Radius changes (the core of this handoff)

| Element | Current | New |
|---|---|---|
| `DS.controlRadius` (fields, checkboxes, segmented cells, popups) | 3 | **0** |
| `DS.buttonRadius` (AccentButton/Export, GhostButton hover fill, bordered buttons) | 4 | **0** |
| `GhostButton(cornerRadius:)` default | 8 | **0** |
| `DS.listRowRadius` (Media tab rows) | 5 | **0** |
| `DS.fieldRadius` (`DSField` legacy fields) | 7 | **0** |
| Timecode field | 4 | **0** |
| Media thumbnail (34 × 38) | 3 | **0** |
| Kind chips (8 × 20 / 8 × 26) and the 6 × 6 track dot | 2 / 1 | **0** |
| S/M/L segmented end cells | 3 | **0** |
| Zoom slider track | 2 | **0** |
| Zoom slider knob | 11pt circle | **7 × 11pt rect** (fill `textStrong`, centred on the value) |
| `DS.clipRadius` (timeline clip body, and the selection ring that follows it) | 4 | **2** |
| Window corners, traffic lights | OS | unchanged |

Delete `StickerButton` once it has no callers (its pill shape is retired).

### Components (all existing, only corners and the knob change)

- **Transport GhostButton**: 30 × 26, 19pt symbol, 2pt gaps. Rest tint `#c8c8c2`. Hover fill `#333333` and tint `#e6e6e4`. Press scales to 0.97. Disabled 42% opacity.
- **Edit-action GhostButton**: 28 × 24, 17pt symbol, rest tint `#a3a39c`.
- **Track toggle GhostButton**: 20 × 18, 13pt symbol, rest tint `#8f8f8a`.
- **Timecode**: 24 tall, 1pt `#55554f` border, fill `#1d1d1d`, 9pt horizontal padding, IBM Plex Mono 12 Medium in `#f0efe9`. Followed by `/ 00:00:37:05` in Mono 11 `#6e6e68` at an 8pt gap.
- **Fit popup**: 24 tall, 1pt `#3a3a3a` border, fill `#2b2b2b`, 8pt padding, Mono 11 `#dcdcd8`, then a 13pt `chevron.up.chevron.down` in `#8f8f8a` at an 8pt gap.
- **Checkbox (Safe, Snap)**: 13 × 13. Off: 1pt `#55554f` border on `#2b2b2b`. On: 1pt `#4a7fd0` border, fill `rgba(10,132,255,0.30)`, Mono 9 ✓ in `#8cc6ff`. Label is Source Sans 3, 11 Regular, `#b9b9b3`, at a 6pt gap.
- **Export (AccentButton)**: 26 tall, 12pt horizontal padding, fill `#3d6ea8`, hover `#4a7fbd`, press darkens about 16%. 15pt `square.and.arrow.up` symbol at a 6pt gap, label Source Sans 3 12 Semibold `#f0f6ff`.
- **Dividers**: 1pt `#3a3a3a`, 20 tall in the toolbar and 18 tall in the timeline bar.
- **Inspector tabs (PanelTabsView)**: 32 tall, equal widths, 1pt dividers. Active tab has fill `#2c2c2c`, a 2pt `#62b0ff` bottom rule and a semibold `#e6e6e4` label. Inactive labels are `#b9b9b3`.
- **Selection header**: 44 tall, 12pt padding. 8 × 26 kind chip, 9pt gap, name Source Sans 3 12 Semibold `#e6e6e4`, meta Mono 10 `#8f8f8a`.
- **Section header**: 28 tall, 10pt padding. 15pt chevron in `#8f8f8a`, then the label in Mono 10 Medium uppercase (0.09em tracking, `#b9b9b3`), then a right-aligned summary in Mono 10 `#6e6e68`. Hover fill `#2a2a2a`. 1pt `#303030` bottom rule.
- **Section body**: 76pt label column (Source Sans 3 11 `#8f8f8a`), 7pt row gap, 10pt column gap. Value fields are 22 tall with a 1pt `#3a3a3a` border, fill `#2b2b2b`, 7pt padding, Mono 11 `#dcdcd8`, and an optional 12pt affix symbol in `#55554f`.
- **Media tab**:
  - Action row: 38 tall. Add Media is a bordered button, 24 tall, 1pt `#55554f` border, fill `#2b2b2b`, 14pt `plus`, Source Sans 3 11 Semibold. Then `⇧⌘I` and `3 items` in Mono 10 `#6e6e68`.
  - Rows: 52 tall, 1pt `#303030` border, 3pt gap. Hover fill `#2a2a2a`. Selected rows get fill `rgba(10,132,255,0.24)` and a `#4a7fd0` border.
  - Footer: 40 tall. Consolidate… button, plus "Copies sources into the package" in Source Sans 3 10 `#6e6e68`.
- **Document tab**: 86pt label column, 8pt row gap, the same value fields.
- **S/M/L segmented**: 24 × 22 cells with shared 1pt borders and Mono 10 Medium labels. The active cell has fill `rgba(10,132,255,0.24)`, a `#4a7fd0` border and `#8cc6ff` text. Inactive text is `#9a9a95`.
- **Zoom slider**: 110 × 3 track in `#3a3a3a`, fill `#62b0ff`, with 15pt `minus`/`plus.magnifyingglass` symbols (`#8f8f8a`) at 8pt gaps.
- **Timeline clip** (drawing unchanged except the radius):
  - Body: 2pt radius, clipped, 1pt `rgba(255,255,255,0.14)` border, 3pt inset top and bottom.
  - Name strip: 16 tall, `rgba(0,0,0,0.26)`, 6pt padding. 11pt kind symbol at 62% white, name in Source Sans 3 10 Semibold at 92% white.
  - Video: filmstrip at 72% opacity under a 54% tint wash. Audio: waveform at 44% white. Text/shape: caption in 11 Semibold at 72% white.
  - Selected: 2pt `#F4653F` ring and 6pt `rgba(255,255,255,0.38)` trim grips.
  - Transition: 45° hatch, 3/7pt, `rgba(255,255,255,0.26)`, with 1pt edges at 40% white.
- **Playhead**: 2pt `#F4653F` line and a 13 × 9 triangle head.
- **Ruler**: 22 tall, fill `#232323`, "TIMELINE" in Mono 9 at 0.09em `#6e6e68`, tick labels in Mono 9 `#7c7c76` with 1pt `#3a3a3a` tick lines.

## Interactions & behaviour

These are unchanged from the chrome-cleanup handoff:
- Hover transitions take 0.14s and state changes 0.22s, on ease (0.2, 0.7, 0.3, 1). Respect `DS.reduceMotion`.
- Tab switches are instant.
- Clicking a clip selects it, switches the inspector to the Clip tab and updates both selection blocks.
- S/M/L changes lane heights (see *Design tokens*).

The prototype also demos play (Space), ruler scrubbing, blade at the playhead (B), ripple delete (⌫), duplicate, and an Export toast. These show intent only; the toast is not a spec.

## State management

No new state. The chrome-cleanup handoff's `selectedClip`, `inspectorTab`, `openSections`, `trackSize`, `snapEnabled` and `safeGuides` still apply.

## Design tokens

The full list is in `design/tokens.css`. Change these in `Theme.swift`:

```
controlRadius 0   buttonRadius 0   listRowRadius 0   fieldRadius 0   clipRadius 2
```

Colours in `DS` stay **semantic** (`.windowBackgroundColor`, `.separatorColor`, `.controlAccentColor` and so on), so light appearance comes for free. The dark hexes above are what those resolve to in the mock. The `[data-theme="light"]` block in `tokens.css` is a *web approximation* of the light appearance, for design review only. Don't hardcode it.

Fixed colours (identical in both appearances):
- Clip tints: video `#3E5063`, audio `#2C7A58`, still `#6A4B93`, text `#B17C1E`, shape `#247686`, nest `#55595F`.
- Coral `#F4653F` (playhead, selection ring, marquee, safe guides, meter clip).
- Butter `#F2C14E` (snap guide).
- Forest `#1F8564`.

Type:
- **Source Sans 3**: UI text, 10–13pt, Regular and Semibold.
- **IBM Plex Mono**: every machine-produced number and the micro-labels, 9–12pt, Regular and Medium.
- **Darker Grotesque Black**: wordmark only, never below 28pt.

Metrics (unchanged):
- Chrome: title bar 30, toolbar 44, timeline bar 36, ruler 22, tabs 32, inspector 304, track header 132, control 22, field 24, button 26, clip strip 16, trim grip 6, filmstrip tile 34.
- Track heights (text / video / audio): S 30/54/40, M 44/84/60, L 58/116/82.
- Spacing scale: 2 / 3 / 6 / 7 / 8 / 9 / 10 / 12.

## Assets

- `design/assets/logo/` holds the Reelcut mark, the mono mark and the icon SVG. The mark keeps its own rounded geometry; don't square it.
- `design/assets/reel-frame.png` is a placeholder preview frame.
- `design/assets/fonts/` holds the fonts, which are already vendored in `app/Resources/Fonts`.

## Files

- `design/index.html` (dark) and `design/light.html` (light reference): open either directly in a browser.
- `design/toolbar.jsx`, `preview.jsx`, `inspector.jsx`, `timeline-bar.jsx`, `timeline.jsx`: one file per region.
- `design/data.js`: the sample project.
- `design/tokens.css` and `design/styles.css`: Reelcut tokens only.
- `design/runtime/ds_bundle.js`: rendering runtime only (see the warning above).
