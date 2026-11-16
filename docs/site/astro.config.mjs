// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';
import { sidebar } from './sidebar.mjs';

// https://astro.build/config
export default defineConfig({
  // Set `site` to the published URL when there is one: Starlight then writes the sitemap.
  integrations: [
    starlight({
      title: 'Frame Job',
      description:
        'The user documentation for Frame Job, a native macOS video editor that you, the built-in Assistant or any MCP agent can drive.',
      // The header shows the company mark, Boppa Llewyn's three blocks, with "Boppa Llewyn /
      // Frame Job" after it (SiteTitle.astro). The Frame Job mark stays the splash's hero image.
      logo: { src: './src/assets/boppa-llewyn-blocks.svg', alt: 'Boppa Llewyn' },
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/kpgalligan/framejob' }],
      editLink: { baseUrl: 'https://github.com/kpgalligan/framejob/edit/main/docs/site/' },
      // The Boppa Llewyn design system, as on Doctored's site. The @font-face rules load first so
      // the families are declared before the theme asks for them; tokens.css holds the system's
      // --bl-* tokens (Neutral Light and Neutral Dark), boppa-llewyn.css maps them onto Starlight,
      // and frame-job.css styles this site's own components with them.
      customCss: [
        './src/fonts/font-face.css',
        './src/styles/tokens.css',
        './src/styles/boppa-llewyn.css',
        './src/styles/frame-job.css',
      ],
      head: [
        // The two faces above the fold, Geist and Geist Mono (the header's version badge and the
        // page eyebrow are mono). Only the `latin` subsets are preloaded; `latin-ext` is fetched
        // on demand by unicode-range.
        {
          tag: 'link',
          attrs: {
            rel: 'preload',
            href: '/fonts/Geist-Variable-latin.woff2',
            as: 'font',
            type: 'font/woff2',
            crossorigin: 'anonymous',
          },
        },
        {
          tag: 'link',
          attrs: {
            rel: 'preload',
            href: '/fonts/GeistMono-Variable-latin.woff2',
            as: 'font',
            type: 'font/woff2',
            crossorigin: 'anonymous',
          },
        },
      ],
      // `useStarlightUiThemeColors` makes the code-block chrome (frame, copy button, borders)
      // follow the theme's tokens instead of the syntax theme's. Starlight then sets the code
      // background, the active tab's background and the frame's shadow at theme level, which
      // beats anything here, so those three live in boppa-llewyn.css; the title bars, which it
      // leaves alone, are set here: `--bl-surface` with a `--bl-line` rule under them.
      expressiveCode: {
        themes: ['github-dark-default', 'github-light'],
        useStarlightUiThemeColors: true,
        styleOverrides: {
          borderRadius: '10px',
          borderColor: 'var(--sl-color-hairline-light)',
          // 14 / 22 px, the system's `code` style.
          codeLineHeight: 'calc(22 / 14)',
          frames: {
            editorTabBarBackground: 'var(--bl-surface)',
            editorTabBarBorderBottomColor: 'var(--bl-line)',
            terminalTitlebarBackground: 'var(--bl-surface)',
            terminalTitlebarForeground: 'var(--bl-ink-subtle)',
            terminalTitlebarBorderBottomColor: 'var(--bl-line)',
          },
        },
      },
      // The four places the theme's CSS cannot reach: the header lockup ("Boppa Llewyn / Frame
      // Job" and its version badge), a two-state theme toggle, the eyebrow and description around
      // a page title, and the splash page's eyebrow.
      components: {
        SiteTitle: './src/components/SiteTitle.astro',
        ThemeSelect: './src/components/ThemeSelect.astro',
        PageTitle: './src/components/PageTitle.astro',
        Hero: './src/components/Hero.astro',
      },
      plugins: [starlightLinksValidator()],
      sidebar,
    }),
  ],
});
