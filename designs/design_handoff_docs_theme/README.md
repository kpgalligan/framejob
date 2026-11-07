# Handoff: documentation site theme (Boppa Llewyn redesign)

## Overview

This handoff moves the documentation site (`docs/site/`) from the old Boppa Llewyn theme to the new Boppa Llewyn design system. The old theme imitated a furniture workshop: Cormorant Garamond display type, IBM Plex, warm-ebony greys, a cream light look, a brass accent and 2/4/8 px "joinery" corners. The new system is the one the company website and every app's docs share:

- **Type:** Geist for text, Geist Mono for eyebrows, code, keys and versions. No serif anywhere.
- **Colour:** neutral greys, with the logo green as the one accent. The app icons and the company mark supply the rest of the colour.
- **Shape:** 6/10/16 px corners. Hairlines separate things; shadows are limited to a 1 px card shadow and the screenshot window.
- **Brand:** the company mark (three toy blocks) and the name in the header, with the product after it: **Boppa Llewyn / Frame Job**.

Decisions confirmed by the owner:

- The new Boppa Llewyn design system replaces the old theme everywhere.
- The company mark is the building-blocks mark (`assets/boppa-llewyn-blocks.svg`).
- Body type is sans-serif; nothing is set in a serif.

Not yet confirmed: which palette ships. This handoff ships **Neutral Light** for the light look and **Neutral Dark** for the dark look, the pair the design system recommends. The system also has three alternates (Cream & Coral, Field Green, Monochrome). They're in `tokens.css` and switchable in the reference page, so the owner can compare. Changing the palette later means changing two blocks of `tokens.css` and nothing else.

## About the design files

`Docs Theme.html` is a **design reference in HTML**: a static mock of a content page and the splash page, not Starlight's markup. Recreate it in the existing Starlight theme files. Map each part by the tables below, and don't copy the mock's class names. Open it from this folder in a browser (it loads Geist from Google Fonts and the real screens and mark from `docs/site/src/assets/`). The bar at the top switches page, look and palette; `?theme=dark&page=splash&bare=1` does the same from the URL.

## Fidelity

**High fidelity** for colour, type, spacing, corners and borders, in both looks, at 1440 px and 390 px. The page structure doesn't change: the 280 px sidebar and 680 px prose column are the site's current widths, and the table of contents keeps Starlight's own width (224 px in the mock). The header grows from 60 to 64 px (`--sl-nav-height: 4rem`). Icons in the mock are simple stand-ins; keep Starlight's own icons.

## Files

| File | What it is |
|---|---|
| `Docs Theme.html` | **The spec.** Content page (Split clips) and splash, light and dark, desktop and phone. |
| `tokens.css` | Every colour, shadow, spacing, radius and font token as `--bl-*` custom properties: Neutral Light under `[data-theme='light']`, Neutral Dark under `[data-theme='dark']`, the three alternate palettes at the end. Generated from the design system; copy it into the site whole rather than retyping values. The type scale is in its closing comment. |
| `assets/boppa-llewyn-blocks.svg` | The company mark, 1024 × 1024 on the cream app-icon plate. |

## What changes, file by file

All paths are under `docs/site/`.

| File | Change |
|---|---|
| `src/styles/boppa-llewyn.css` | Rewritten on the new tokens: the old `--bl-*` block is replaced by `tokens.css`, the `--sl-*` mapping follows the table below, and every rule below "Site layer" is restyled to the mock. Keep its structure (tokens, mapping, base rules, then the parts Starlight's variables can't reach) and its rule of preferring CSS over overrides. |
| `src/styles/frame-job.css` | `Shot`, `AtAGlance` and the feature index restyled (below). |
| `src/fonts/font-face.css`, `public/fonts/` | Cormorant Garamond and IBM Plex removed; Geist and Geist Mono added (below). |
| `astro.config.mjs` | `logo` points at the blocks mark; the two `preload` links name the Geist files; `expressiveCode.styleOverrides` follow "Code blocks". |
| `src/assets/boppa-llewyn-blocks.svg` | New: copied from this folder. `src/assets/logo.svg` (the Frame Job mark) stays, for the splash hero and anywhere the product is shown. |
| `src/components/SiteTitle.astro` | The lockup (below). |
| `src/components/Shot.astro` | One new optional prop, `frame`, for full-window captures (below). |
| `src/content/docs/index.mdx` | The editor-window `Shot` gains `frame`. No other content changes. |
| `README.md` ("Theme") | Rewritten to describe the new system: the families, the palette pair, the files. |
| `CLAUDE.md` | The `src/fonts/, public/fonts/` row names the new faces, if it names them. |

`ThemeSelect.astro`, `PageTitle.astro` and `Hero.astro` keep their markup; they change through CSS only. `public/favicon.svg` stays the Frame Job icon, because the tab belongs to the product.

## Fonts

- **Geist** (variable, weights 100 to 900) and **Geist Mono** (variable, 100 to 900), both under the SIL Open Font Licence 1.1. Take the `latin` and `latin-ext` WOFF2 subsets from Google Fonts, as the current faces were. Self-host them in `public/fonts/` as now, split by `unicode-range` in `font-face.css`.
- Replace `public/fonts/OFL.txt` with Geist's licence text (it names the Geist Project Authors). Delete every Cormorant Garamond and IBM Plex file and rule; nothing uses them afterwards.
- Preload the two `latin` files, Geist and Geist Mono: the page's first screen has both (the header's version badge and the page eyebrow are mono).
- `--sl-font: var(--bl-font-sans)` and `--sl-font-mono: var(--bl-font-mono)`. The stacks in `tokens.css` fall back to the Mac's own San Francisco and SF Mono. Remove `--bl-font-display` and every rule that sets headings in it.

## Starlight's colour variables

Map these in both looks; each value is a token from `tokens.css`, so the light and dark values come from the token, not from this table. Starlight's grey scale runs from strongest ink to page background.

| Starlight variable | Token | Notes |
|---|---|---|
| `--sl-color-white` | `--bl-ink` | Headings, strongest text |
| `--sl-color-gray-1` | `--bl-ink` | |
| `--sl-color-gray-2` | `--bl-ink-muted` | Descriptions, card bodies |
| `--sl-color-gray-3` | `--bl-ink-subtle` | Eyebrows, captions, meta |
| `--sl-color-gray-4` | `--bl-line-strong` | Control borders, hover borders |
| `--sl-color-gray-5` | `--bl-line` | |
| `--sl-color-gray-6` | `--bl-surface` | Cards, header, AtAGlance |
| `--sl-color-gray-7` | `--bl-surface-sunken` | Hovers, code, kbd wells |
| `--sl-color-black` | `--bl-bg` | |
| `--sl-color-text` | `--bl-ink` | Body copy |
| `--sl-color-text-accent` | `--bl-accent-ink` | Links |
| `--sl-color-text-invert` | `--bl-on-accent` | Text on the accent |
| `--sl-color-accent-low` | `--bl-accent-soft` | Current sidebar item |
| `--sl-color-accent` | `--bl-accent` | Primary button, ToC rail |
| `--sl-color-accent-high` | `--bl-accent-ink` | Text on `accent-low` |
| `--sl-color-bg` | `--bl-bg` | |
| `--sl-color-bg-nav` | `--bl-surface` | Solid; the header no longer blurs |
| `--sl-color-bg-sidebar` | `--bl-bg` | Separated by a `--bl-line` hairline |
| `--sl-color-bg-inline-code` | `--bl-surface-sunken` | |
| `--sl-color-bg-accent` | `--bl-accent` | |
| `--sl-color-hairline`, `-light`, `-shade` | `--bl-line` | |
| `--sl-color-backdrop-overlay` | light `rgba(24, 24, 27, 0.4)`, dark `rgba(0, 0, 0, 0.6)` | |
| `--sl-color-blue-low` / `blue` / `blue-high` | `surface-sunken` / `ink-muted` / `ink` | Note |
| `--sl-color-purple-low` / `purple` / `purple-high` | `accent-soft` / `accent` / `accent-ink` | Tip |
| `--sl-color-green-low` / `green` / `green-high` | `accent-soft` / `accent` / `accent-ink` | Success badge |
| `--sl-color-orange-low` / `orange` / `orange-high` | `caution-soft` / `caution` / `caution` | Caution |
| `--sl-color-red-low` / `red` / `red-high` | `danger-soft` / `danger` / `danger` | Danger |
| `--sl-shadow-sm` | `--bl-shadow-card` | |
| `--sl-shadow-md`, `--sl-shadow-lg` | `--bl-shadow-window` | The search dialog only |

Every text pairing here holds at least 4.5:1 in both looks, and every control border and focus ring at least 3:1. Don't introduce a colour that isn't a token.

## Type

| Where | Style | Size / line height | Weight | Tracking |
|---|---|---|---|---|
| Splash hero title | `display` | 64 / 64 px (40 / 42 below 50rem) | 600 | −0.035em |
| Page title (`h1`) | `heading-1` | 40 / 44 px (32 / 36 below 50rem) | 600 | −0.03em |
| `h2` | `heading-2` | 28 / 34 px | 600 | −0.02em |
| `h3`, card and pagination titles | `heading-3` | 20 / 28 px | 600 | −0.01em |
| `h4` | | 17 / 24 px | 600 | 0 |
| Page description, hero tagline | `lede` | 19 / 30 px (17 / 26 below 50rem) | 400 | 0 |
| Body | `body` | 16 / 26 px | 400 | 0 |
| Sidebar links, tables, asides, AtAGlance | | 15 px, 20–24 px leading | 400 | 0 |
| ToC, captions, meta, footer | `small` | 14 / 20 px | 400 | 0 |
| Eyebrows: page eyebrow, sidebar group labels, ToC label, table headers, AtAGlance terms | `eyebrow` | 12 / 16 px mono, uppercase | 500 | 0.06em |
| Inline code, code blocks | `code` | 14 / 22 px mono | 400 | 0 |

So `--sl-text-body: 1rem`, `--sl-line-height: 1.625`, `--sl-text-h1: 2.5rem`, `--sl-text-h2: 1.75rem`, `--sl-text-h3: 1.25rem`, `--sl-text-h4: 1.0625rem`, `--sl-line-height-headings: 1.1`, `--sl-text-code: 0.875rem`. Headings are `--sl-color-white`; there's no bold 700 and no italic heading anywhere.

## Corners, borders and depth

| Radius | Used on |
|---|---|
| `--bl-radius-sm` 6 px | `kbd`, inline code, sidebar links, the Steps markers, the feature filter's input |
| `--bl-radius-md` 10 px | Buttons, the search field, icon buttons (menu, theme, GitHub), asides, code frames, AtAGlance, Shot |
| `--bl-radius-lg` 16 px | Cards, link cards, pagination links, the framed Shot, dialogs, the mobile ToC dropdown |
| `--bl-radius-pill` | The header's version badge |

Hairlines are `--bl-line`; a hover strengthens a border to `--bl-line-strong`. Nothing lifts, scales or moves on hover.

## The parts, in order down the page

**Header** (64 px). Solid `--bl-surface` with a `--bl-line` bottom border, no blur. Gaps of 24 px.

- **Lockup** (`SiteTitle.astro`): the blocks mark at 32 px, then **Boppa Llewyn** in Geist 600 17 / 24 px at −0.02em, a `/` in `--bl-ink-subtle` weight 400, the site title (**Frame Job**) in weight 500, and the version badge. Gap 8 px. The badge is mono 500 12 / 16 px, `--bl-ink-subtle`, padding 2 px 8 px, pill-shaped, drawn with an inset 1 px `--bl-line-strong` ring. Below 50rem the company name and the slash hide, leaving the mark, **Frame Job** and the badge. The lockup still links to the docs home.
- **Search** (desktop): a 260 × 36 px field on `--bl-surface-sunken` with a `--bl-line` border, `--bl-radius-md`, the placeholder in `--bl-ink-subtle` 14 px, and the ⌘K keys as small `kbd` (20 px tall). Below 50rem it's a 36 px icon button.
- **Theme toggle and GitHub link**: 36 px square ghost buttons, `--bl-radius-md`, icon in `--bl-ink-muted`; hover `--bl-surface-sunken` with `--bl-ink`. The toggle keeps its two-state behaviour and its storage key.
- **Menu button** (below 50rem): the same 36 px ghost button, keeping the 44 px hit area the current CSS gives it.

**Sidebar** (280 px). Background `--bl-bg`, a `--bl-line` hairline on the right, padding 32 px 16 px 48 px 24 px.

- Group labels: `eyebrow`, `--bl-ink-subtle`, 8 px above the links, 28 px between groups.
- Links: 15 / 20 px, `--bl-ink-muted`, padding 6 px 10 px, `--bl-radius-sm`, 1 px apart. Hover: `--bl-surface-sunken`, `--bl-ink`. Current page: `--bl-accent-soft` background, `--bl-accent-ink` text, weight 550. Keep the existing guard so hover doesn't override the current item.

**Page opener** (`PageTitle.astro`, through CSS). The content column is 680 px (`--bl-prose-width`), 56 px from the header.

- Eyebrow: `eyebrow` in `--bl-accent-ink`, 12 px above the title. This is the page's one accent-coloured label.
- Title: `heading-1`.
- Description: `lede` in `--bl-ink-muted`, 16 px below the title.

**Body.** Paragraphs and lists 16 px apart; list items 6 px apart. Links are `--bl-accent-ink`, no underline until hover (1 px underline, 3 px offset). `h2` has 48 px above and 12 px below; `h3` 32 px above and 8 px below.

**AtAGlance** (`.fj-glance`). `--bl-surface`, a 1 px `--bl-line` border, `--bl-radius-md`, padding 16 px 20 px, 32 px above. A two-column grid (terms at their own width, 24 px gap, 10 px between rows). Terms are `eyebrow` in `--bl-ink-subtle`; values 15 / 24 px, menu paths bold, keys as `kbd`, tools as inline code at 13 px.

**Shot** (`.fj-shot`). The capture at up to half its pixel width, as now, with a 1 px `--bl-line` border, `--bl-radius-md` and `--bl-shadow-card`, 32 px above. The caption is 14 / 20 px `--bl-ink-subtle`, centred, 10 px below.

- **New `frame` prop**: for a full-window capture (a `*.window` screen), `<Shot name="04-editor.window" frame alt="…" />` draws the capture in a window frame instead:
  - a 36 px title bar on `--bl-surface` with three 12 px dots in `--bl-line` (not traffic-light colours) and the window title centred in 13 px weight 500 `--bl-ink-subtle`;
  - `--bl-radius-lg`, no border, and `--bl-shadow-window`, the site's only large shadow.
- Use `frame` on the splash's editor window. Leave partial captures (sheets, inspectors) unframed.

**Steps** (Starlight's `<Steps>`). Each number sits in a 28 px square:

- `--bl-surface-sunken` fill, 1 px `--bl-line` border, `--bl-radius-sm`;
- the number in mono 500 13 px `--bl-ink`;
- a 1 px `--bl-line` connector down to the next square.

Text is indented 48 px, with 20 px between steps.

**Tables**. Full width, 15 / 22 px. Headers are `eyebrow` in `--bl-ink-subtle`, 10 px above a `--bl-line-strong` rule. Cells are padded 10 px 12 px 10 px 0, with a `--bl-line` rule under each row. Code in a cell doesn't wrap, as now.

**Asides** (`:::note`, `:::tip`, `:::caution`, `:::danger`). Each is the system's callout:

- a full-tint background, the icon, and the type's word as the title;
- no border and no left accent bar;
- `--bl-radius-md`, padding 16 px 20 px, 24 px above;
- a 20 px icon beside a 15 / 24 px title (weight 600) and a 15 / 24 px body in `--bl-ink-muted`.

Show Starlight's aside icon; the current CSS hides it. The colours come from the blue / purple / orange / red mapping above, `-low` for the background and `-high` for the icon and title. The title stays sentence case; drop the mono uppercase it has now.

**Code blocks** (Expressive Code). `styleOverrides`:

- `borderRadius: '10px'` and `borderColor: 'var(--sl-color-hairline-light)'`;
- the code background on `--bl-surface-sunken`;
- the frame's title bar on `--bl-surface`, with a `--bl-line` rule under it and its title in mono 500 12 / 16 px `--bl-ink-subtle`, not uppercase.

Keep the two syntax themes (`github-light`, `github-dark-default`) and `useStarlightUiThemeColors`. Inline code is mono at 0.875em on `--bl-surface-sunken`, `--bl-radius-sm`, padding 2 px 5 px.

**`kbd`**. 24 px tall, 6 px side padding, mono 500 13 px `--bl-ink`, on `--bl-surface` with a 1 px `--bl-line` border and a 2 px bottom edge, `--bl-radius-sm`. Use the same anywhere a key is shown, search included.

**Buttons** (`LinkButton`). 16 / 24 px weight 550, padding 12 px 20 px, `--bl-radius-md`.

- `primary`: `--bl-accent` with `--bl-on-accent` text; hover `--bl-accent-hover`.
- `secondary`: `--bl-surface` with `--bl-ink` text and a `--bl-line-strong` border; hover `--bl-surface-sunken`.
- `minimal`: `--bl-ink` text, 12 px side padding; hover `--bl-surface-sunken`.

**Cards and link cards**. `--bl-surface`, a 1 px `--bl-line` border, `--bl-radius-lg`, `--bl-shadow-card`, padding 24 px, 24 px grid gap. The title is `heading-3`; the body is 15 / 22 px `--bl-ink-muted`. Hover strengthens the border to `--bl-line-strong`. A card's icon chip loses its box; the icon is `--bl-ink-subtle`.

**Pagination**. Two cards as above, padded 16 px 20 px, 16 px apart, 64 px above. The label (Previous, Next) is 14 / 20 px `--bl-ink-subtle`; the title is `heading-3`.

**Footer meta** ("Edit page" and the like). 14 / 20 px `--bl-ink-subtle`, under a `--bl-line` rule 32 px below the pagination. Not mono.

**Table of contents** (224 px). Its label is `eyebrow` `--bl-ink-subtle`, 12 px above the list. The list has a 1 px `--bl-line` rail. Links are 14 / 20 px `--bl-ink-muted`, padded 5 px 0 5 px 12 px. The current link is `--bl-ink` weight 500, with a 2 px `--bl-accent` rail sitting over the hairline. The mobile ToC bar keeps its current behaviour, recoloured with the same tokens.

**Splash** (`template: splash`).

- **Hero band**: full viewport width on `--bl-band`, with text in `--bl-on-band`. One way to bleed past the content width is `box-shadow: 0 0 0 100vmax var(--bl-band); clip-path: inset(0 -100vmax)` on `.hero`.
  - Content stays in the 1120 px container (`--bl-content-width`), padded 96 px top and bottom (64 px and 16 px sides below 50rem).
  - Two columns, `1fr 192px`, 48 px apart. The Frame Job mark (the existing hero image) shows at 192 px, and above the text at 96 px below 50rem.
- **Hero text**: the eyebrow is `eyebrow` in `--bl-on-band` at 80% opacity; the title is `display`; the tagline is `lede` in `--bl-on-band` at 86% opacity, at most 34em wide, 24 px below the title; the actions sit 32 px below it, 12 px apart.
- **Below the hero**: 64 px down, the framed editor-window Shot at the full container width. Then the requirements paragraph in `--bl-ink-muted`, 680 px wide, 48 px below. Then "Start here" as an `h2` with a `--bl-line` rule and 64 px above it, and the link cards in two columns (one below 50rem).

**Focus**. One rule everywhere: `outline: 2px solid var(--bl-focus); outline-offset: 2px`. It replaces the current two-ring box shadow and holds 3:1 on every surface in both looks.

**Motion**. Colour, background and border transitions at 120 ms, nothing else. Keep the reduced-motion rule.

**Feature index** (`.fj-filter`, `.fj-features`). The filter box sits on `--bl-surface` with a `--bl-line` border and `--bl-radius-md`. Its input is on `--bl-bg` with a `--bl-line-strong` border and `--bl-radius-sm`, with a 14 px placeholder in `--bl-ink-subtle`. The count is mono 12 px `--bl-ink-subtle`. The table follows "Tables".

## Doctored's site

`boppa-llewyn.css` is shared rule for rule with Doctored's documentation site (`public-docs/src/styles/custom.css` in the Doctored repository), and its header says to change both together. This handoff covers Frame Job only. Port the finished file to Doctored in a change of its own; until then, the two sites look different. Doctored's lockup reads **Boppa Llewyn / Doctored** with the same mark.

## Out of scope

- Page content, the sidebar's order and labels, `src/data/features.json`, search behaviour and anything the docs proof reads. The only content edit is the `frame` prop on the splash's Shot.
- Shipping the alternate palettes or a palette switcher.
- The company website (boppallewyn.com), which has its own handoff.

## Checking it

- `pnpm build` in `docs/site/` (the last word: links, anchors and imports), `node docs/site/scripts/check-pages.mjs src/content/docs/index.mdx`, and `python3 tools/proof/docs_site_proof.py`.
- Look at the built site beside `Docs Theme.html`, in both looks, at 1440 px and 390 px. Check the splash, a page with every part (Split clips has steps, a table and AtAGlance), a page with each aside, and the feature index. Nothing should scroll sideways at 390 px.
- Search the built CSS for `Cormorant`, `IBM Plex`, `oklch(` and `--bl-brass`. None should remain.
