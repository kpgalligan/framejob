import { defineCollection, z } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({
      extend: z.object({
        /** The mono uppercase label above the page title. Without one, a page shows the name of
         *  the sidebar group it sits in. */
        eyebrow: z.string().optional(),
      }),
    }),
  }),
};
