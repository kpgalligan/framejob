# The Frame Job documentation site

The public user documentation, built with [Starlight](https://starlight.astro.build/) on Astro.
`CLAUDE.md` beside this file has the rules for writing a page.

Astro needs Node 22.23.4 or later (`engines` in `package.json`). `.node-version` names that version
for hosts and version managers that read it. mise reads it only when
`idiomatic_version_file_enable_tools` includes `node`.

```sh
pnpm install
pnpm dev        # http://localhost:4321, with live reload
pnpm build      # the static site into dist/, failing on a broken link or anchor
pnpm preview    # serve dist/
pnpm format     # Prettier over the config, components, styles and scripts
```

From the repository root, without a build:

```sh
node docs/site/scripts/check-pages.mjs [page.mdx …]   # parses, imports, links, captures
python3 tools/proof/docs_site_proof.py                # the site against the tree (make test)
```

## Theme

The site wears the **Boppa Llewyn** design system, the one the company website and every app's
documentation share, so this site and Doctored's (`public-docs/` in the Doctored repository) look
like one family: Geist for text and Geist Mono for eyebrows, code, keys and versions, with no serif
anywhere; neutral greys with the logo green as the one accent; 6, 10 and 16 px corners; hairlines
between things, and shadows only on cards and the screenshot window. The header carries the
company mark, three toy blocks, with **Boppa Llewyn / Frame Job** after it.

The light look is **Neutral Light** and the dark look **Neutral Dark**, the pair the design system
recommends. `tokens.css` also carries its three alternate palettes (Cream & Coral, Field Green,
Monochrome) for comparison; nothing switches to them. Changing the palette means changing its two
look blocks in `tokens.css` and nothing else.

| Where                                | What                                                                                                                                                                                                                                                                                         |
| :----------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/styles/tokens.css`              | The design system's `--bl-*` tokens (colour, shadow, spacing, radius, font), copied whole from the design handoff: Neutral Light under `[data-theme='light']`, Neutral Dark under `[data-theme='dark']`, the alternates at the end. Copy a new version in whole rather than editing a value. |
| `src/styles/boppa-llewyn.css`        | The theme, shared rule for rule with Doctored's `custom.css` (only Prettier's formatting differs): the tokens mapped onto Starlight's `--sl-*` properties, then the parts the properties cannot reach. Change it in both sites together.                                                     |
| `src/styles/frame-job.css`           | This site's own components (`Shot`, `AtAGlance`, the feature index) drawn with the tokens.                                                                                                                                                                                                   |
| `src/fonts/font-face.css`            | `@font-face` rules for Geist and Geist Mono, split by `unicode-range`.                                                                                                                                                                                                                       |
| `public/fonts/`                      | Self-hosted variable WOFF2 (the `latin` and `latin-ext` subsets from Google Fonts). Licence: `public/fonts/OFL.txt`.                                                                                                                                                                         |
| `src/assets/boppa-llewyn-blocks.svg` | The company mark in the header. `src/assets/logo.svg`, the Frame Job mark, is the splash's hero image, and `public/favicon.svg` stays the Frame Job icon.                                                                                                                                    |
| `src/components/`                    | The four Starlight overrides: `SiteTitle` (the mark, **Boppa Llewyn /**, the product's name and a version badge), `ThemeSelect` (a two-state toggle), `PageTitle` (the eyebrow and the description), `Hero` (the eyebrow).                                                                   |
| `src/site.ts`                        | The badge's version, read from the repository's `VERSION` file when the site is built.                                                                                                                                                                                                       |

`Shot` takes `frame` for a full-window capture (a `*.window` screen): the splash's editor window
is drawn in a window frame with a title bar. Partial captures (sheets, inspectors) stay unframed.

Every page may set an `eyebrow` in its frontmatter, the mono uppercase label above the title.
Without one, a page shows the name of the sidebar group it sits in.

Prefer the CSS over a new component override: unlayered CSS reaches almost everything, and each
override is a copy of Starlight's markup that has to be checked again on an upgrade.

## Publishing

`pnpm build` writes a static site to `dist/`, which any static host can serve. Page links are
root-absolute, so serving the site from a sub-path needs Astro's `base` as well as a change to
those links.

Nothing points at the published site yet, and nothing changes by itself once it has a URL. When
it is first published (the owner's Netlify step), someone changes three things by hand:

- `site` in `astro.config.mjs`, set to the published URL, so Starlight writes a sitemap;
- the repository's `README.md`, whose highlights link to each page's source under
  `src/content/docs/`: each link becomes that page's published URL;
- Help ▸ Frame Job Help, which today runs macOS's own Help (`NSApplication.showHelp`) and links
  to no page: it is pointed at the site.
