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
      logo: { src: './src/assets/logo.svg', alt: 'Frame Job' },
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/kpgalligan/framejob' }],
      editLink: { baseUrl: 'https://github.com/kpgalligan/framejob/edit/main/docs/site/' },
      // The Boppa Llewyn theme, as on Doctored's site. The @font-face rules load first so the
      // families are declared before the theme asks for them; frame-job.css styles this site's
      // own components with the theme's tokens.
      customCss: [
        './src/fonts/font-face.css',
        './src/styles/boppa-llewyn.css',
        './src/styles/frame-job.css',
      ],
      head: [
        // The two faces above the fold. Only the `latin` subsets are preloaded; `latin-ext` is
        // fetched on demand by unicode-range.
        {
          tag: 'link',
          attrs: {
            rel: 'preload',
            href: '/fonts/IBMPlexSans-Variable-latin.woff2',
            as: 'font',
            type: 'font/woff2',
            crossorigin: 'anonymous',
          },
        },
        {
          tag: 'link',
          attrs: {
            rel: 'preload',
            href: '/fonts/CormorantGaramond-Variable-latin.woff2',
            as: 'font',
            type: 'font/woff2',
            crossorigin: 'anonymous',
          },
        },
      ],
      // `useStarlightUiThemeColors` makes the code-block chrome (frame, copy button, borders)
      // follow the theme's tokens instead of the syntax theme's.
      expressiveCode: {
        themes: ['github-dark-default', 'github-light'],
        useStarlightUiThemeColors: true,
        styleOverrides: {
          borderRadius: '4px',
          borderColor: 'var(--sl-color-hairline-light)',
        },
      },
      // The four places the theme's CSS cannot reach: the header lockup with its version badge,
      // a two-state theme toggle, the eyebrow and description around a page title, and the
      // splash page's eyebrow.
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
