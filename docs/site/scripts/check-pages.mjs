#!/usr/bin/env node
// A fast check of pages, in about a second, with no site build:
//
//     node docs/site/scripts/check-pages.mjs [page.mdx …]      # all pages when none is named
//
// Each page must parse (frontmatter and MDX), name a title and a description, import every
// component it uses, link only to pages in the sidebar, and name only captures that exist.
// `pnpm build` is still the last word: it also checks that every link's #anchor exists.

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { compile } from '@mdx-js/mdx';
import remarkGfm from 'remark-gfm';
import { parse } from 'yaml';
import { sidebar } from '../sidebar.mjs';

const SITE = join(dirname(fileURLToPath(import.meta.url)), '..');
const CONTENT = join(SITE, 'src/content/docs');
const SCREENS = join(SITE, 'src/assets/screens');
const COMPONENTS =
  /<(Steps|Aside|Tabs|TabItem|Card|CardGrid|LinkCard|LinkButton|Badge|FileTree|Icon|AtAGlance|Shot|FeatureIndex)\b/g;

function slugs(items, found = new Set(['', 'features'])) {
  for (const item of items) {
    if (typeof item === 'string') found.add(item);
    else if (item.slug) found.add(item.slug);
    else if (item.items) slugs(item.items, found);
  }
  return found;
}

function pages(folder, found = []) {
  for (const entry of readdirSync(folder)) {
    const path = join(folder, entry);
    if (statSync(path).isDirectory()) pages(path, found);
    else if (/\.mdx?$/.test(entry)) found.push(path);
  }
  return found;
}

const known = slugs(sidebar);

async function check(path) {
  const problems = [];
  const source = readFileSync(path, 'utf8');
  const parts = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(source);
  if (!parts) return ['no frontmatter'];
  const [, head, body] = parts;

  let front = {};
  try {
    front = parse(head) ?? {};
  } catch (error) {
    problems.push(`frontmatter: ${error.message.split('\n')[0]}`);
  }
  if (!front.title) problems.push('frontmatter: no title');
  if (!front.description) problems.push('frontmatter: no description');

  try {
    await compile(body, { remarkPlugins: [remarkGfm] });
  } catch (error) {
    problems.push(
      `MDX ${error.place?.start?.line ?? error.line ?? '?'}: ${error.reason ?? error.message}`,
    );
  }

  for (const [, name] of body.matchAll(COMPONENTS)) {
    const imported = new RegExp(`import\\s+(?:\\{[^}]*\\b${name}\\b[^}]*\\}|${name})\\s+from`);
    if (!imported.test(body)) problems.push(`<${name}> is used but not imported`);
  }

  // Links outside code: fenced blocks and code spans may show a path as an example.
  const prose = body.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');
  for (const [, target] of prose.matchAll(/\]\((\/[^)\s]*)\)|href="(\/[^"]*)"/g)) {
    if (!target) continue;
    const path = target.split('#')[0];
    if (!path.endsWith('/')) problems.push(`link has no trailing slash: ${target}`);
    if (!known.has(path.replace(/^\/|\/$/g, ''))) problems.push(`link to no page: ${target}`);
  }

  for (const [, name] of body.matchAll(/<Shot[^>]*\bname="([^"]+)"/g)) {
    for (const look of ['light', 'dark']) {
      if (!existsSync(join(SCREENS, `${name}.${look}.webp`))) {
        problems.push(`no capture: ${name}.${look}`);
      }
    }
  }
  return problems;
}

const named = process.argv.slice(2);
const targets = named.length ? named : pages(CONTENT);
let failed = 0;
for (const path of targets) {
  for (const problem of await check(path)) {
    console.log(`${relative(process.cwd(), path)}: ${problem}`);
    failed += 1;
  }
}
console.log(`${targets.length} pages, ${failed} problems`);
process.exit(failed ? 1 : 0);
