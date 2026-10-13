# 3. Window layout

The chrome below is the one the design handoff in
`designs/design_handoff_chrome/` specifies; it replaced the first cut, whose
toolbar was a grab bag, whose Export was a system pill, and whose clips had no
visible boundary. That handoff's README is the normative source for the
metrics; this section is the summary. The sharp pass in
`designs/design_handoff_sharp/` (2026-09-23) then squared every
chrome corner (a clip keeps 2 pt) and gave the zoom slider a block knob; its
README is normative for radii and the knob, with the deviation in §11 SH-2
(SH-4 squared `StickerButton`, superseding SH-1).

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                    Demo — 1080 × 1920 · 25 fps · edited          (OS title bar) │
├────────────────────────────────────────────────────────────────────────────────┤
│ ⏮ ◀◀ ▶ ▶▶ ⏭ ↻ │ 00:00:20:12 / 00:01:00:00          [Fit ▾] [Safe] │ [⤴ Export…] │
├───────────────────────────────────────────────────────┬────────────────────────┤
│                                                       │  Clip  Media  Document │
│      ┌─────────────────────────────────────────┐      │────────────────────────│
│      │ Intro title                             │      │ ▌clipA.mov             │
│      │                                         │      │  video · 00:00:21:00 … │
│      │            (screen recording)           │      │ ▾ TRANSFORM       100% │
│      │                                     ──▶ │      │   Scale    ──o──  100 %│
│      │                           ┌────────┐    │      │   Position x 480 y 270 │
│      │                           │ webcam ○┼   │      │ ▸ CROP        none [⟲] │
│      │                           └────────┘    │      │ ▸ CORNER RADIUS 0 px   │
│      └─────────────────────────────────────────┘      │ ▸ SHADOW           off │
│        1080 × 1920 · 25 fps                           │ ▸ SPEED         1.00×  │
│                                                       │ ▸ TIMING  00:00:21:00  │
├───────────────────────────────────────────────────────┴────────────────────────┤
│ ▌clipA.mov     │ ✂ ⇥ ⇤ ⌫ ◆ ⧉ Aa ▭ │ Snap ●  ▁▃▅▂  ⊖ ──o── ⊕ ⇔ │ [S][M][L]     │
│  V1 · video    │                                                               │
├────────────────────────────────────────────────────────────────────────────────┤
│          ┆0:00      0:10   ▼  0:20      0:30      0:40      0:50      1:00     │
│ T1       ┆ [Aa Intro title      ]                                              │
│ V1       ┆ [▦ Screen recording.mov ███████████████████][/][▦ B-roll ██████████] │
│ A1       ┆ [∿ Music.m4a ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]  │
└────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Default | Range | Holds |
|---|---|---|---|
| Title bar | OS | — | the document name, and its size · rate · edited state as the subtitle |
| Toolbar | 44 pt | fixed | transport, timecode, canvas zoom, safe guides, Export |
| Preview canvas | flexible | — | the composition at canvas size, letterboxed in the void |
| Inspector | 304 pt | 280–440, collapsible (⌥⌘I) | four tabs + collapsible sections |
| Timeline bar | 36 pt | fixed | the selection block, the clip actions, snap, the output level meter, zoom, S/M/L |
| Timeline | 300 pt | 140 pt – 60 % of window | ruler, track headers + lanes |

The toolbar carries only what applies to the whole document at all times —
*where you are in it*, *how you are looking at it*, and *getting it out*.
Everything that acts on a clip is in the timeline bar, beside blade and
ripple-delete. Document identity is the title bar's, because the OS already
gives it a home.

Inspector and timeline are `NSSplitView` panes; sizes persist in
`UserDefaults`. There is no left panel: the media library is an inspector
tab, as in a screencast editor, so the canvas gets the width. Below about 1080 pt wide,
narrow the inspector before anything else. The window has a welcome sibling
(`WelcomeWindowController`, as in Rasterize) offering Open Video…, New
Project, New Recording… (road map 3) and Recent, under the stacked wordmark.
