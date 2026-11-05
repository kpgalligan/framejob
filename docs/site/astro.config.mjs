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
      customCss: [
        '@fontsource-variable/source-sans-3/index.css',
        '@fontsource/ibm-plex-mono/400.css',
        '@fontsource/ibm-plex-mono/500.css',
        '@fontsource/darker-grotesque/800.css',
        '@fontsource/darker-grotesque/900.css',
        './src/styles/frame-job.css',
      ],
      expressiveCode: { styleOverrides: { borderRadius: '0' } },
      plugins: [starlightLinksValidator()],
      sidebar,
    }),
  ],
});
