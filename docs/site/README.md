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
