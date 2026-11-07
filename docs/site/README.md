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

The site wears the **Boppa Llewyn** design system, the theme Doctored's documentation site
(`public-docs/` in the Doctored repository) was built in, so the two sites look like one family:
warm-ebony neutrals with a cream light surface, a brass accent, Cormorant Garamond display type,
IBM Plex Sans and Mono, small corners and hairlines instead of shadows. Its inks are the Frame Job
mark's: forest, butter, coral and cream are the system's teal, brass, ember and cream.

| Where                         | What                                                                                                                                                                                                                                   |
| :---------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/styles/boppa-llewyn.css` | The theme, Doctored's `custom.css` rule for rule (only Prettier's formatting differs): the `--bl-*` tokens mapped onto Starlight's `--sl-*` properties, then the components the tokens cannot reach. Change it in both sites together. |
| `src/styles/frame-job.css`    | This site's own components (`Shot`, `AtAGlance`, the feature index) drawn with the theme's tokens.                                                                                                                                     |
| `src/fonts/font-face.css`     | `@font-face` rules for the three families, split by `unicode-range`.                                                                                                                                                                   |
| `public/fonts/`               | Self-hosted WOFF2 (the `latin` and `latin-ext` subsets from Google Fonts). Licence: `public/fonts/OFL.txt`.                                                                                                                            |
| `src/components/`             | The four Starlight overrides: `SiteTitle` (the mark, the wordmark and a version badge), `ThemeSelect` (a two-state toggle), `PageTitle` (the eyebrow and the description), `Hero` (the eyebrow).                                       |
| `src/site.ts`                 | The badge's version, read from the repository's `VERSION` file when the site is built.                                                                                                                                                 |

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
