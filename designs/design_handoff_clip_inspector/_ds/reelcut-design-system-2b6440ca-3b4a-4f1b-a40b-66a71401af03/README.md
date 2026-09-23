# Reelcut Design System

A sharp-edged redesign of the chrome shared by two macOS apps from the same house:

- **Reelcut** — a screencast video editor. A project is a document of tracks and clips, edited through "ops" that both the app and an AI agent speak. AppKit app (`app/Sources/`) over a Rust core (`core/src/`).
- **Rasterize** — the image editor sibling: left tool rail, fixed options bar, canvas, Layers/Assistant panel, status bar. Shares the brand inks (forest, butter, coral), the fonts, and a sibling logo.

**Direction.** The apps sit in macOS neutral gray, but the existing buttons and components are soft and rounded (3/4/5/7px radii, a retired "sticker" pill button). This system keeps the neutral gray and every metric from the source, and squares everything off: **all component radii are 0**, except timeline clips at **2px** (the one softened object). The OS-owned window corners and traffic lights stay round. Both **dark** (default) and **light** appearances are provided.

## Sources

- GitHub: https://github.com/kpgalligan/reelcut (branch `main`)
  - `app/Sources/Theme.swift` — `DS` tokens (colors, type, metrics, motion)
  - `app/Sources/Controls.swift` — `AccentButton`, `GhostButton`, `StickerButton` (retired), `DSField`, `DividerView`, `PanelTabsView`
  - `app/Sources/ClipKindStyle.swift` — clip kind → tint / symbol / word
  - `designs/design_handoff_reelcut/` — handoff README, `Reelcut Editor.dc.html` hi-fi mock, `Reelcut Logo.dc.html`, `logo/`
  - `app/Resources/Fonts/` — vendored fonts
- GitHub: https://github.com/kpgalligan/rasterize (branch `main`)
  - `designs/design_handoff_rasterize_ui_redesign/` — handoff README + `Rasterize Editor.dc.html` hi-fi mock (rail, options bar, layers, assistant, status bar)
  - `designs/app-icon/` — Rasterize icon (three multiplied circles on paper)
  - `app/Sources/ToolRailView.swift`, `ToolOptionsBar.swift`, `OptionControls.swift`, `LayersPanelViewController*.swift`
- Explore these repos further (especially the handoff README and `InspectorPane.swift`, `TimelineView.swift`, `ExportSheetController.swift`) to design additional screens faithfully.

## Index

- `styles.css` — entry point (imports only)
- `tokens/` — `colors.css` (dark, default), `theme-light.css` (`[data-theme="light"]` overrides), `typography.css`, `spacing.css` (metrics + radii), `effects.css` (shadows, motion), `fonts.css`, `icons.css`, `base.css`
- `assets/` — `fonts/`, `logo/` (Reelcut mark, mono mark, icon SVG/PNGs; `rasterize-icon.svg` + PNG), `images/reel-frame.png`, `images/canvas.png` (placeholders from the handoffs)
- `guidelines/` — foundation specimen cards (Colors, Type, Spacing, Brand)
- `components/controls/` — Icon, AccentButton, GhostButton, Button, Checkbox, PopupButton, SegmentedControl, Slider, ValueField, TimecodeField, Divider, Swatch, LabeledField, MoreButton
- `components/panels/` — KindChip, SelectionBlock, PanelTabs, PropertyGrid, InspectorSection, MediaRow, LayerRow, ChromeBar, TitleBar, StatusBar, ZoomPill
- `components/timeline/` — Clip, Transition, Playhead, Ruler, TrackHeader (Reelcut)
- `components/tools/` — RailSlot, ColorSwatches, ToolIdentity, Menu, OverflowPopover (Rasterize)
- `components/assistant/` — ChatMessage, Composer (Rasterize)
- `ui_kits/reelcut/` — `index.html` (dark), `light.html`
- `ui_kits/rasterize/` — `index.html` (dark), `light.html`

### Light mode
Set `data-theme="light"` on `<html>` (or any container). Every semantic token (`--surface-*`, `--text-*`, `--border*`, `--accent*`, popover, HUD, assistant) is remapped; clip tints, brand inks and the white-on-tint clip overlays stay fixed, as in the app. Light values are derived to mirror the dark ramp — the source handoffs only specify dark hexes and defer to AppKit semantic colours for light.
- `SKILL.md`, `github.md`, `thumbnail.html`

### Intentional additions
- **Icon** — wrapper for the Material Symbols stand-in font (SF Symbols can't ship on the web).
- **Button** (bordered secondary), **Checkbox**, **PopupButton**, **SegmentedControl**, **Slider**, **ValueField**, **KindChip**, **SelectionBlock**, **InspectorSection**, **MediaRow**, **TitleBar**, timeline pieces — not separate Swift classes, but each is a distinct, specified element in the handoff mock.
- **StickerButton** is intentionally *not* included: the source marks it retired.

## CONTENT FUNDAMENTALS

- **Terse, literal, lowercase-leaning.** Labels are one or two words in Title/Sentence case: "Add Media", "Consolidate…", "No selection", "Snap", "Safe", "Export". Tabs: "Clip · Media · Document".
- **Ellipsis** on commands that open a sheet ("Consolidate…").
- **Section headers are UPPERCASE mono micro-labels**: TRANSFORM, VIDEO, AUDIO, EFFECTS, TIMING, TIMELINE.
- **Machine numbers are always mono** and spelled precisely: `00:00:04:05`, `1080 × 1920 · 25.106 fps · edited`, `0.0 dB`, `1.00×`, `48 kHz stereo`. Use real `×` and `·` separators.
- **Explanations are one plain line**: "Copies sources into the package".
- **Kind words are lowercase**: video, audio, still, image, text, shape, nest ("Track V1 · video").
- **Refusals, not errors.** Core vocabulary (CONTEXT.md): an op applies, is an *identity*, or is *refused* — a refusal states the rule in its own sentence and names what to send instead. Avoid "error", "invalid", "failed".
- British "Colour" appears in the Document tab. No emoji, no exclamation marks, no "you/we" chatter in chrome.

## VISUAL FOUNDATIONS

- **Color.** Neutral macOS dark gray chrome (#101010 → #2c2c2c surfaces, #3a3a3a hairlines) with warm-gray text (#f0efe9 → #55554f). One accent: system blue (#3d6ea8 fill, #62b0ff rules). Three brand inks from the logo: **coral #F4653F is load-bearing** — playhead, selection ring, marquee, safe guides, meter clip. Butter = snap guide. Six fixed clip tints (video slate, audio green, still violet, text amber, shape teal, nest grey) identical across appearances.
- **Type.** Source Sans 3 for UI (10–13px, 400/600). IBM Plex Mono for every machine-produced number and micro-labels (9–12px). Darker Grotesque Black for display/wordmark only, never below 28px.
- **Shape.** 0px radius everywhere: buttons, fields, checkboxes, segmented cells, tabs, list rows, rail slots, menus, popovers, chat bubbles, zoom pill, chips, slider knob (a 7×11 block). Timeline clips alone take 2px. 1px borders do the work that rounding used to. The window (8px) and traffic lights are the OS's.
- **Boxes & borders.** Regions are separated by 1px `--border` lines, never shadows. Controls are boxed: 1px border on a slightly lighter fill (#2b2b2b). Strong fields (timecode) use `--border-strong` on a darker fill.
- **Shadows.** Only two: the window shadow and the preview frame's 1px ring + soft drop. No card shadows. The selection ring is a 2px coral outline.
- **Backgrounds.** Flat fills only. No gradients, textures or imagery in chrome. The one pattern is the transition hatch (45°, 3/7px, white 26%).
- **Layout.** Fixed chrome: title bar 30, toolbar 44, timeline bar 36, ruler 22, tabs 32; inspector 304 wide; track headers 132. Clusters are separated by 12px gaps and 1px × 20 (toolbar) / 18 (timeline bar) dividers. A flexible spacer pushes view + Export right.
- **Hover.** Ghost controls fill with `--hover-fill` (#333) and brighten the icon; list rows/section headers use `--hover-row` (#2a2a2a); the accent button lightens. 140ms, ease (0.2, 0.7, 0.3, 1).
- **Press.** Ghost buttons scale to 0.97; accent darkens ~16%. No bounces.
- **Selected / active.** `--selection-fill` (blue 24%) + `--accent-border`; active tab = lighter fill + 2px `--accent-rule` underline; selected clip = coral ring + white trim grips.
- **Disabled.** 42% opacity.
- **Motion.** Instant tab switches; 220ms for section collapse and track-height changes; respect reduce-motion.
- **Blur.** Only the Rasterize zoom HUD (`--hud-fill` + 12px backdrop blur) over the canvas.
- **Transparency.** Only over clip tints (name strip black 26%, text/icon white 62–92%, filmstrip at 72% under a 54% tint wash). No blur anywhere.
- **Imagery.** The only imagery is the user's footage (preview, filmstrips). Placeholder: `assets/images/reel-frame.png`.

## ICONOGRAPHY

- **Production: SF Symbols** via `GhostButton(symbol:fallback:)`, medium weight, 19pt toolbar / 17pt timeline bar / 15pt inline / 13pt track toggles / 11pt clip strip. Each has a Unicode fallback glyph (▦ ∿ ❄ ▣ T ▭ ▤).
- **Web stand-in: Material Symbols Outlined** (Google Fonts CDN, loaded in `tokens/icons.css`) — the same substitution the handoff mock makes. Use the `Icon` component. **This is a substitution; flagged.**
- Mapping (SF → Material): backward.end → skip_previous · backward → fast_rewind · play → play_arrow · forward → fast_forward · forward.end → skip_next · repeat → repeat · scissors → content_cut · arrow.right.to.line → first_page · arrow.left.to.line → last_page · delete.left → backspace · bookmark → bookmark_add · doc.on.doc → content_copy · textformat → title · minus/plus.magnifyingglass → zoom_out/zoom_in · square.and.arrow.up → ios_share · chevron.up.chevron.down → unfold_more · film → movie · waveform → graphic_eq.
- No emoji. Unicode used for keyboard hints (⇧⌘I) and the checkbox tick (✓).

## Brand

- Mark: two overlapping clips (forest + butter, overlap drawn in #1D651F) with a coral playhead in the cut. Files in `assets/logo/`. Note the source mark's clip rects are r 8 — the mark is left as delivered; ask before squaring it.
- Wordmark: Darker Grotesque Black, horizontal lockup mark 84 / gap 22 / type 68 at −0.015em; stacked mark 88 / gap 14 / type 52.
- Clear space: one clip height (43% of mark height).
- Rasterize icon: three r=31 circles (forest, butter, coral) multiplied on paper — `assets/logo/rasterize-icon.svg` relies on `mix-blend-mode: multiply`; the PNG is flattened.
- Rasterize rail icons (Material stand-ins): highlight_alt, crop, open_with, brush, format_color_fill, gradient, rectangle, title, colorize, zoom_in.
