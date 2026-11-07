# CLAUDE.md — the documentation site

The public user documentation: Astro with Starlight, one page per feature or tight family of
features. `pnpm` manages it, and `engines` in `package.json` sets the Node it needs. `README.md` has
the commands.

## Where things are

```
astro.config.mjs        Starlight's settings: title, logo, fonts, theme, plugins
sidebar.mjs             every page's place in the navigation, in order
src/content/docs/       the pages: <section>/<page>.mdx
src/data/features.json  THE FEATURE LIST: what /features/ renders and what the proof reads
src/components/         AtAGlance (a page's facts), Shot (a screen in both looks),
                        FeatureIndex (the filterable list); SiteTitle, ThemeSelect,
                        PageTitle and Hero are the theme's Starlight overrides
src/assets/screens/     WebP captures, written only by scripts/import-screens.mjs
src/styles/             boppa-llewyn.css (the theme, shared with Doctored's site) and
                        frame-job.css (this site's components in it); README "Theme"
src/fonts/, public/fonts/  the theme's self-hosted faces and their licence
src/site.ts             the header badge's version, read from the repository's VERSION
```

## The rule that matters

**Every claim is written from the code.** A label, a default, a range, a shortcut, a limit or a
refusal is checked against `app/Sources/`, `core/src/`, `graphic/` or `mcp-proxy/` before it is
written, and the code wins over a spec or an ADR. Never write what a feature
probably does. If the code cannot settle it, leave it out.

Nothing dev-only, deferred or unbuilt is documented. That excludes the dev tools (`snapshot_ui`,
`perform_menu_item`, `cancel_sheet`, `select_inspector_tab`, `play_preview`, `graphic_memory`,
`loudness_meter`, `land_recording`, `analysis_job`, `transcript_view`, `playback_rebuilds`,
`assistant_send`, `assistant_answer`) and every `-RCDev` launch default.

## Who reads this

Someone editing a video, who has never read this repository. They want to know what a thing does,
how to do it, and what will stop them. They do not care how it is built.

So a page never mentions: spec or decision IDs (`AU-12`, `§11`), road maps, phases, issue numbers,
source file or type names, `rc_*` exports, format version numbers, proofs, tests, or the history
of a feature. Internal words get translated: "refused" becomes what the user sees ("Frame Job
won't do this while…"), "the core" and "the op" disappear. A tool name is the one exception: the
MCP pages and `tools=` in `AtAGlance` name agent tools, because those are the product's interface.

## Voice

- Plain, direct and second person. Say what it does, then how. Short sentences.
- Open with what the feature is for, in a sentence or two, before any steps.
- British spelling in prose (colour, centre, grey, normalise), and the
  app's exact spelling for its own labels (the **Color** tab, **Normalize**).
- Contractions are fine. No marketing: never "powerful", "seamless", "effortless", "robust",
  "simply", "just", "easily", "unleash", "supercharge".
- Prefer a full stop or a comma to an em dash.
- State defaults, ranges and limits as numbers. Say what happens at the edges, because that is
  what a reader comes to a reference for.
- No filler sections. A page with nothing to say under a heading doesn't have that heading.

## Page shape

```mdx
---
title: Markers
description: One sentence, what this page helps you do. Search results show it.
---

import { Steps } from '@astrojs/starlight/components';
import AtAGlance from '@components/AtAGlance.astro';
import Shot from '@components/Shot.astro';

What the feature is for, in a sentence or two.

<AtAGlance menu="Mark ▸ Add Marker" keys="M" tools="add_marker" />

<Shot name="04-editor.window" alt="What the picture shows, for someone who can't see it." />

## Add a marker

<Steps>

1. Move the playhead to the moment.
2. Press <kbd>M</kbd>.

</Steps>

## Options

| Control | What it does | Default |
| ------- | ------------ | ------- |

## Good to know

Limits, edge cases and what stops it, in plain words.

## Related

- [Snapping](/timeline/snapping/)
```

Every section is optional except the opening. Order the task sections as a reader needs them.

- **Eyebrow:** the mono label above a page's title is the name of its sidebar group. Set
  `eyebrow:` in the frontmatter only when that name is wrong for the page.
- **Headings** start at `##`, are sentence case, and name the job: "Add a marker", not "Adding".
  A feature in `src/data/features.json` with an `anchor` needs a heading that makes that anchor.
- **Menus** are bold with `▸`, spelled as the app spells them: **Clip ▸ Split**.
- **Keys** use the app's symbols in `<kbd>`: <kbd>⌘T</kbd>. Inside `AtAGlance`, pass the string.
- **Controls** are bold where they appear in a step: choose **Save**.
- **Links** are root-absolute with a trailing slash: `/timeline/markers/#add-a-marker`. The build
  fails on a link or anchor that does not exist.
- **Asides** are for what a reader must not miss, not for decoration: `:::note`, `:::tip`,
  `:::caution`, `:::danger`.
- **Screens** come from `src/assets/screens/`. A `name` is the file name without its look and
  extension. Use a screen only when it shows what the page is about, not when the thing is out
  of frame, and give it real alt text.

## MDX traps

MDX is JSX. In prose, `{`, `}` and `<` start code. Put anything like `{x}`, `<1 s` or `a<b` in a
code span, or write it out ("under 1 s"). `<kbd>` and every component must close. A line starting
with `import` or `export` is code. Leave a blank line after an opening component tag and before
its closing tag, or the Markdown inside won't render.

## Checking a page

```sh
node docs/site/scripts/check-pages.mjs <page.mdx>…        # parses, imports, links, captures
python3 tools/proof/docs_site_proof.py --pages <page.mdx>…  # internal words, local paths
pnpm build                                                # in docs/site: the last word
```

## Screens

The captures come from the screen catalog (`designs/screens/`, `tools/proof/screens.py`), so the
pictures are of the real app. To refresh them:

```sh
python3 tools/proof/screens.py --out <dir>                      # from the repository root
node docs/site/scripts/import-screens.mjs <dir> --used
```

**This site is public.** `import-screens.mjs` refuses a capture whose layout dump holds a local
path, and its `CROP` table is the only way past that, by cutting the region away. Settings needs
it: its MCP section prints the helper's full path. Never weaken the refusal.

## When the app changes

A user-visible change edits its page here, and a new feature adds its row to
`src/data/features.json`. `tools/proof/docs_site_proof.py` runs in `make test` and fails on a
menu item or agent tool the site doesn't document, a feature whose page or anchor is missing, a
page that names something internal, or `docs/guide/` (the retired user guide) existing or a link
into it; its `--guide` row also runs in `make gate`'s `names` step.
