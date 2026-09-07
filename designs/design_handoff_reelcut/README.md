# Handoff: Reelcut — UI cleanup and new identity

## Overview

Two pieces of work in one package:

1. **A new logo** — mark, app icon and wordmark, built as a deliberate sibling to the Rasterize app icon so the two apps read as one house.
2. **A chrome cleanup** — the top toolbar regrouped, the Export button brought into the house button style, the six inspector tabs collapsed to three, and the timeline's clips redrawn as real objects.

The three problems the user named, in their words: the top toolbar is a grab bag, the Export button looks out of place, and clip appearance in the timeline needs work. Everything else in this document exists to serve those three.

Target codebase: `kpgalligan/reelcut` @ `main` — AppKit in `app/Sources/`, Rust core in `core/src/`. **No core changes.** This is entirely `app/Sources/` plus one asset catalogue.

## About the design files

The `.dc.html` files here are **design references** — prototypes of look and behavior, not production code to port. Recreate them in AppKit using the patterns already in the repo: `NSView` subclasses that draw themselves, `DS` tokens from `app/Sources/Theme.swift`, `BarView` from `EditorChrome.swift` for chrome bars, `GhostButton` / `StickerButton` / `PanelTabsView` from `Controls.swift`.

Two things that make this easier than it looks:

- **`Theme.swift` already has almost every token this redesign needs.** `DS.tabHeight`, `DS.controlHeight`, `DS.controlRadius`, `DS.panelWidth`, the clip tints (`clipVideo`, `clipAudio`, `clipStill`, `clipText`, `clipShape`, `clipNest`), `DS.playhead`, `DS.snapGuide`, `DS.timelineRangeShade`, `DS.hoverFill`, the three brand inks. Section *Design tokens* lists the handful to add. Do **not** hardcode the hex values in this document — the mock is dark-mode only, the app must work in both appearances.
- **`PanelTabsView` already draws exactly the tab style the mock shows** — square, equal widths, 1px dividers, 2px accent rule under the active tab. The inspector change is a change to *how many* tabs and what is inside them, not to the tab control.

The mock uses **Material Symbols Outlined** as a browser stand-in for icons. Ship **SF Symbols**; `GhostButton` already takes a `symbol:` + `fallback:` pair.

## Fidelity

- `Reelcut Logo.dc.html` — **high fidelity, and the vectors are exact.** The SVG and PNG files in `logo/` are the real deliverable; the HTML page is the spec sheet around them.
- `Reelcut Editor.dc.html` — **high fidelity** for layout, metrics and the timeline's clip drawing. Interactive: switch inspector tabs, collapse sections, click clips to select, toggle Snap and Safe, change track size with S/M/L.

---

# Part 1 — Identity

## The mark

Two clips overlap and the playhead stands in the overlap. The shape is the edit: where two pieces of footage meet, and where you are in them. It is the Rasterize mark's sibling — same flat geometry, same three house inks, same paper ground, same squircle tile with an ink rule — but its overlap is a cut rather than a colour mix.

### Geometry (a 120 × 120 box)

| Element | Rect | Fill |
|---|---|---|
| Outgoing clip | x 18, y 36, w 54, h 52, r 8 | forest `#1F8564` |
| Incoming clip | x 48, y 36, w 54, h 52, r 8 | butter `#F2C14E` |
| Overlap | x 48, y 36, w 24, h 52, r 8 | `#1D651F` |
| Playhead head | triangle (49.5, 20) (70.5, 20) (60, 36) | coral `#F4653F` |
| Playhead bar | x 56.5, y 20, w 7, h 82, r 3.5 | coral `#F4653F` |

Three things worth knowing about that table:

- **The overlap is drawn, not blended.** The Rasterize mark relies on `mix-blend-mode: multiply` and has to be flattened before any tool that ignores blend modes touches it. Here the two clips share a y and a height, so their intersection is exactly a 24-wide rounded rect with radius 8 on both sides — it can be drawn as its own shape in the pre-multiplied ink (forest × butter = `#1D651F`). No blend mode anywhere in the files.
- **The playhead sits on top at full opacity**, deliberately not multiplied. It is above the media in the mark for the same reason it is above the media in the app.
- **The playhead's head apex meets the clips' top edge** at y 36. That contact is what stops the head reading as a separate floating triangle.

Total mark bounds are x 18–102, y 20–102 — the same optical inset as the Rasterize mark in the same box.

### Files in `logo/`

| File | What it is |
|---|---|
| `reelcut-mark.svg` | Vector master, 120 × 120, no tile. Use for the welcome screen, the About panel, web, print. |
| `reelcut-mark-mono.svg` | Single-ink variant. The playhead is knocked out in paper and re-drawn in ink, so it survives as a cut line with one colour. Use for template images, the menu bar, anywhere tinting is applied. |
| `reelcut-icon.svg` | Vector master of the app icon, 1024 × 1024, standard macOS art inset (824 of 1024), corner radius 26% of the art side, ink border scaled proportionally. |
| `AppIcon.appiconset/` | Drop straight into `app/Assets.xcassets`, replacing the existing set. `Contents.json` plus PNGs at 16, 32, 64, 128, 256, 512, 1024 — every mac idiom slot from 16pt@1x to 512pt@2x. |

### Notes

- The tile is a rounded rect, not Apple's true superellipse. If you want the exact squircle, rebuild from `reelcut-icon.svg` in Icon Composer; nothing else is affected.
- **This mark holds at 16px**, which the Rasterize mark does not. The two clip blocks fuse into one dark bar at that size, but the coral playhead stays legible against it, so the 16pt slot needs no hand-tuning. That was the main argument for this direction over the other four.
- Colours: paper `#FBF8F1`, forest `#1F8564`, butter `#F2C14E`, overlap `#1D651F`, coral `#F4653F`, ink `#101915`. Forest, butter and coral are already in `Theme.swift` as `DS.forest` / `DS.butter` / `DS.coral`.
- **The coral is load-bearing.** `DS.playhead` is coral, `DS.marquee` is coral, and the mark's playhead is coral. Keep that alignment — it is the one thread tying the brand to the interface.

## The wordmark

Darker Grotesque Black — the house display face, `DS.display(_:)`, never below 28px. Two lockups:

- **Horizontal**: mark at 84 tall, 22px gap, "Reelcut" at 68px with -0.015em tracking, baselines optically aligned to the clip blocks rather than the playhead's overhang.
- **Stacked**: mark at 88, 14px gap, "Reelcut" at 52px, both centred. This is the welcome-screen lockup.

Clear space on all sides is one clip height — 52 units of the 120 box, so 43% of the mark's height.

---

# Part 2 — Chrome cleanup

## Region map

```
┌──────────────────────────────────────────────────────────────┐
│ title bar — project name + meta, centred        30pt  (OS)   │
├──────────────────────────────────────────────────────────────┤
│ toolbar: transport · timecode ——— view · Export  44pt        │
├────────────────────────────────────────┬─────────────────────┤
│                                        │                     │
│  preview well (flexible)               │  inspector   304pt  │
│                                        │                     │
├────────────────────────────────────────┴─────────────────────┤
│ timeline bar: selection · edit · snap ——— zoom · S M L  36pt │
├──────────────────────────────────────────────────────────────┤
│ ruler                                            22pt        │
│ ┌──────────┬───────────────────────────────────────────────┐ │
│ │ headers  │ lanes                                         │ │
│ │  132pt   │                                               │ │
└─┴──────────┴───────────────────────────────────────────────┴─┘
```

Window in the mock is 1440 × 862 content. Below about 1080pt wide, narrow the inspector before anything else; the toolbar and timeline bar heights are fixed.

## 1. Toolbar — one job instead of four

**The problem.** The current 44pt row carries transport, document meta, a view control, a safe-area toggle, three unrelated edit actions (`Aa`, duplicate, bookmark) and Export. The bookmark button also duplicates the one already in the timeline row.

**The fix.** The toolbar keeps only what applies to the whole document at all times: *where you are in it*, *how you are looking at it*, and *getting it out*. Everything that acts on a clip moves down to the timeline bar, next to blade and ripple-delete where it belongs.

Left to right, 12pt padding, 12pt between clusters:

| Cluster | Contents |
|---|---|
| Transport | Six `GhostButton`s, 30 × 26pt, 4pt radius, 19pt symbol, 2pt gaps: `backward.end` · `backward` · `play` · `forward` · `forward.end` · `repeat` |
| — | 1pt × 20pt `DS.border` divider |
| Timecode | Current position field: 24pt tall, 4pt radius, 1pt `DS.borderStrong`, `.textBackgroundColor` fill, mono 12pt medium. Then `/ 00:00:37:05` in mono 11pt `DS.textFaint` |
| — | flexible space |
| View | Fit popup (24pt, 4pt radius, mono 11pt + 13pt `chevron.up.chevron.down`) · Safe checkbox (13pt box, 3pt radius, 11pt sans label) |
| — | divider |
| Export | See below |

**Moved out of the toolbar:** `Aa` → timeline bar as *add text*; duplicate → timeline bar; bookmark → deleted, the timeline bar already has one.

**Moved into the title bar:** the project name and its meta (`1080 × 1920 · 25.106 fps · edited`), centred, 12pt semibold + mono 11pt `DS.textFaint`. It is document identity, and the OS already gives it a home.

## 2. Export — the house button, not a system pill

**The problem.** It is a large blue rounded-rect pill with a system focus ring. Nothing else in the app looks like it, and it is the loudest thing on screen.

**The fix.** 26pt tall, 4pt corner radius, `DS.accent` fill, `DS.onAccent` label at 12pt semibold, a 15pt `square.and.arrow.up` symbol at 6pt gap, 12pt horizontal padding. Hover lightens the fill; that is the whole state model.

Note this is **not** `StickerButton`. The sticker pill with its 1.5px border and 2px offset shadow was retired in the Rasterize redesign, and Reelcut's chrome should follow — square-ish, flat, quiet. If `StickerButton` has no other callers after this change, delete it; if it does, leave it and add the flat variant alongside.

## 3. Timeline clips — the real work

**The problem.** Clips have no visible boundary. The filmstrip and the waveform run edge to edge as two stacked bands, the name sits in a black strip that reads as part of the image, and a clip's kind is invisible. You cannot see where one clip ends and the next begins.

**The fix — a clip is one object.**

| Part | Spec |
|---|---|
| Body | 4pt corner radius, `overflow` clipped, 1pt `rgba(white, 0.14)` border, 3pt inset from the lane's top and bottom edges |
| Fill | `DS.tint(for:)` by source kind — the existing mapping, unchanged |
| Name strip | 16pt tall along the top, `rgba(black, 0.26)` over the tint, 6pt padding: 11pt kind symbol at 62% white, then the name at 10pt semibold, 92% white, truncating with an ellipsis |
| Video body | Filmstrip thumbnails, 34pt wide, at 72% opacity, with the clip's tint washed over them at 54% so the clip still reads as one tinted object rather than a strip of photos |
| Audio body | Waveform filled at `rgba(white, 0.44)`, symmetric about the body's centre line |
| Text / shape body | The clip's content as a single line, 11pt semibold at 72% white, 8pt padding |
| Selected | 2pt `DS.playhead` ring (coral) — the same ink as the playhead and the marquee, so "what you picked" and "where you are" agree |
| Trim grips | On selection only: 6pt wide, `rgba(white, 0.38)`, full body height, at both ends, `col-resize` cursor |
| Transition | Over the overlap: 45° hatch at `rgba(white, 0.26)` on 3pt/7pt spacing, 1pt solid edges, drawn above both clips |

Track heights follow the S/M/L control, which currently exists but is visual only:

| | Text track | Video track | Audio track |
|---|---|---|---|
| S | 30pt | 54pt | 40pt |
| M | 44pt | 84pt | 60pt |
| L | 58pt | 116pt | 82pt |

At S a clip is its name strip and little else — that is correct and intended.

## 4. Timeline bar — a selection anchor, and the moved actions

36pt, `BarView(border:)` top and bottom, matching `DS.optionsBarHeight`. This mirrors the Rasterize options bar: a fixed identity block at the left edge that never moves, then the tools.

| Cluster | Contents |
|---|---|
| Selection | Min width 176pt: an 8 × 20pt rounded tint chip in the clip's kind colour, then the clip name at 11pt semibold over `Track V1 · video` in mono 9pt `DS.textFaint`. With no selection: a `DS.borderStrong` chip and "No selection" |
| — | divider |
| Edit actions | Seven `GhostButton`s, 28 × 24pt, 17pt symbol: `scissors` (blade) · `arrow.right.to.line` (trim start) · `arrow.left.to.line` (trim end) · `delete.left` (ripple delete) · `bookmark` (marker) · `doc.on.doc` (duplicate) · `textformat` (add text) |
| — | divider |
| Snap | 13pt checkbox, 11pt label |
| — | flexible space |
| Zoom | `minus.magnifyingglass` 15pt · 110 × 3pt track with an 11pt knob · `plus.magnifyingglass` 15pt |
| — | divider |
| Track size | S / M / L segmented, 24 × 22pt cells, shared borders, 3pt radius on the end cells, active cell `DS.selectionFill` + `DS.accent` border |

The last two icons in that list are the ones that came down from the toolbar.

## 5. Inspector — six tabs become three

**The problem.** Video, Audio, Text, Shape, Media, Document in 304pt is about 50pt per tab. The labels barely fit and four of the six are about the same thing: the selected clip.

**The fix.** Three tabs — **Clip · Media · Document** — through the existing `PanelTabsView`, unchanged. The four clip-related panes become collapsible sections inside the Clip tab.

**Clip tab.** A 44pt selection header (8 × 26pt tint chip · name at 12pt semibold · mono 10pt meta line), then sections:

| Section | Rows |
|---|---|
| `TRANSFORM` | Position · Scale · Rotation · Anchor |
| `VIDEO` | Opacity · Blend · Corner radius · Speed |
| `AUDIO` | Volume · Pan · Fade in · Fade out · Duck |
| `EFFECTS` | Filter · Chroma key · Shadow · Reflection |
| `TIMING` | In · Out · Duration · Reverse |

Section header: 28pt tall, 10pt padding, a 15pt `chevron.right` / `chevron.down`, then the name as `DS.microLabel`, then a right-aligned mono 10pt summary of the section's current state (`100%`, `normal`, `0.0 dB`, `none`) so a collapsed section still tells you something. Body: a 76pt label column and a flexible control column, 7pt row gap, `DS.controlHeight` controls at `DS.controlRadius`.

Open/closed state persists per section in `UserDefaults`. Default: Transform and Video open, the rest closed.

**Only show sections that apply to the selection** — Shape rows on a shape clip, Text rows on a text clip, no Audio section on a muted still. This is what makes three tabs work where six did not: the panel is already contextual, it just was not admitting it.

**Media tab.** A 38pt action row (Add Media button, its `⇧⌘I` hint, a right-aligned item count), then a list of 52pt rows — 34 × 38pt thumbnail, name at 12pt, mono 10pt meta — then a 40pt footer with Consolidate… and a one-line explanation of what it does. Rows are drag sources, as now.

**Document tab.** An 86pt label column: Resolution · Frame rate · Duration · Colour · Tracks · Background.

## 6. Preview well

Unchanged but for one thing: the resolution caption under the video moves to mono 10pt `DS.textFaint` with 0.06em tracking, matching every other machine-produced number in the app. `SafeGuidesView` keeps its two rings; the mock draws them in coral at 85% and 50% to match `DS.marquee`.

No status bar. The timeline bar's selection block and the title bar's meta line carry what a status bar would have said, and adding one would cost 26pt of a window that is already tall.

---

## Interactions & behavior

- **Tab switch** is instant. **Section collapse** animates height over `DS.stateDuration` (0.22s), respecting `DS.reduceMotion`.
- **Clicking a clip** selects it, switches the inspector to the Clip tab, and updates both the inspector header and the timeline bar's selection block. One selection model, three views of it.
- **Hover** on any ghost button fills with `DS.hoverFill` over `DS.hoverDuration` (0.14s).
- **S/M/L** relayouts track heights; the playhead, the ruler and the lane contents keep their horizontal positions.
- **Snap** and **Safe** are plain toggles; both persist.
- Trim grips appear only on the selected clip, so an unselected timeline stays quiet.

## State management

```
selectedClip: ClipID?                    // exists
inspectorTab: .clip | .media | .document // WAS six cases — now three
openSections: Set<SectionID>             // NEW, persisted
trackSize: .s | .m | .l                  // exists; now drives real heights
snapEnabled: Bool                        // exists
safeGuides: Bool                         // exists
```

`SectionID` is one case per section per pane kind. The Clip tab's section list is **derived from the selection's kind**, not fixed — a function from `ClipSource` to `[SectionID]`, which is the piece of logic that replaces the old tab-visibility juggling.

## Design tokens

Everything the chrome needs is already in `Theme.swift`. Colours: `chromeBackground`, `hoverFill`, `selectionFill`, `border`, `borderStrong`, `textStrong`, `textMuted`, `textFaint`, `accent`, `onAccent`, `canvasVoid`, `playhead`, `snapGuide`, `timelineLane`, `timelineLaneAlt`, and the six clip tints. Type: `DS.sans`, `DS.mono`, `DS.display`, `DS.microLabel`. Motion: `DS.hoverDuration`, `DS.stateDuration`, `DS.reduceMotion`, `DS.animate`.

Metrics to **add** to `DS`:

```
toolbarHeight      44    trackHeaderWidth  132    clipRadius          4
timelineBarHeight  36    rulerHeight        22    clipHeaderHeight   16
trimGripWidth       6    filmstripThumb     34
trackHeights  S (30, 54, 40)  M (44, 84, 60)  L (58, 116, 82)   // text, video, audio
```

`DS.optionsBarHeight` is 36 and `timelineBarHeight` is also 36 — keep them as separate names anyway; they are the same number for a reason but they are not the same thing.

Spacing scale 2 / 3 / 6 / 8 / 10 / 12pt. Radii 3 (controls) / 4 (buttons, clips) / 5 (list rows) / 7 (existing fields).

## Assets

- `assets/reel-frame.png` — a brightened crop of the user's own screenshot, standing in for the preview frame and every filmstrip thumbnail in the mock. **Placeholder only.**
- `logo/` — the real identity deliverable; see Part 1.
- Icons: SF Symbols, named per region above. Material Symbols in the HTML is a browser stand-in.
- Fonts: already vendored in `app/Resources/Fonts` — Source Sans 3, IBM Plex Mono, Darker Grotesque.

## Suggested implementation order

1. **Icon.** Drop `logo/AppIcon.appiconset/` into `app/Assets.xcassets`, replacing the existing set. One commit, zero risk, immediately visible in the Dock.
2. **`Theme.swift`** — add the metrics above.
3. **Toolbar** (`EditorViewController.swift`) — regroup into the four clusters, move the project meta to the title bar, delete the bookmark duplicate, restyle Export. The three displaced buttons move in step 4.
4. **Timeline bar** (`EditorViewController+Timeline.swift`) — add the selection block at the left edge, take in the three actions from the toolbar, wire S/M/L to real track heights.
5. **Clip drawing** (`TimelineView.swift`, `TimelineLayout.swift`) — the name strip, the tint wash over the filmstrip, the coral selection ring, the trim grips, the transition hatch. This is the largest single change and the one the user cares most about; do it on its own.
6. **Inspector** (`InspectorViewController.swift`) — three tabs, the selection header, the collapsible section shell. The pane contents move from `VideoPane` / `AudioPane` / `TextPane` / `ShapePane` into sections largely as-is; the work is the shell and the kind-to-sections function, not the rows.
7. **Media and Document tabs** (`MediaPane.swift`, `DocumentPane.swift`) — the row restyle and the footer.
8. **Welcome screen and About panel** — swap in `reelcut-mark.svg` and the stacked wordmark.

Steps 1–2 are mechanical. Steps 3–5 are the three things the user actually asked for, and each is independently shippable.

## Files in this bundle

| File | What it is |
|---|---|
| `Reelcut Editor.dc.html` | Hi-fi interactive mock. Switch inspector tabs, collapse sections, click clips, toggle Snap and Safe, change track size. |
| `Reelcut Logo.dc.html` | Identity spec sheet — mark, four grounds, icon with a true-pixel size ladder, both wordmark lockups, palette. |
| `logo/` | The vectors and the drop-in `AppIcon.appiconset`. |
| `support.js` | Runtime the two HTML files need. Keep alongside them. |
| `assets/reel-frame.png` | Placeholder preview frame. |

Open either HTML file directly in a browser.
