#!/usr/bin/env node
// Turns a `tools/proof/screens.py` run into the site's screenshots.
//
//     python3 tools/proof/screens.py --out <dir>            # from the repository root
//     node docs/site/scripts/import-screens.mjs <dir> [--used]
//
// Each `<id>.<capture>.<look>.png` becomes `src/assets/screens/<id>.<capture>.<look>.webp`.
// `--used` keeps only the captures a page names in a <Shot>, and removes the rest.
//
// This site is public and a capture is taken on someone's machine, so a capture whose layout dump
// holds a local path is refused unless CROP cuts that part away. The refusal is the point of this
// script: nothing else stands between a home folder and the published site.

import { readdirSync, readFileSync, mkdirSync, rmSync, statSync } from 'node:fs';
import { homedir, userInfo } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const SITE = join(dirname(fileURLToPath(import.meta.url)), '..');
const SCREENS = join(SITE, 'src/assets/screens');
const CONTENT = join(SITE, 'src/content/docs');
const MAX_WIDTH = 1800;
const QUALITY = 82;

// A capture that shows a local path keeps only what starts at this view's text. Settings prints
// the framejob-mcp helper's full path in its MCP section, so the capture starts at Assistant.
const CROP = { '02-settings.window': { startAt: 'Assistant', margin: 14 } };

const localPath = new RegExp(`/Users/|/private/|/var/folders/|${userInfo().username}`);

function views(layout) {
  const found = [];
  const walk = (node) => {
    if (Array.isArray(node)) node.forEach(walk);
    else if (node && typeof node === 'object') {
      const text = node.text ?? node.title ?? node.string ?? node.label;
      const frame = node.frame ?? node.rect ?? node.window_frame;
      if (typeof text === 'string') found.push({ text, y: frame?.[1] ?? 0 });
      Object.values(node).forEach(walk);
    }
  };
  walk(layout.views);
  return found;
}

/** The pixels to cut from the top of a capture, after checking what is left shows no local path. */
function topCut(stem, layout) {
  const all = views(layout);
  const crop = CROP[stem];
  let top = 0;
  if (crop) {
    const anchor = all.find((view) => view.text === crop.startAt);
    if (!anchor) throw new Error(`${stem}: no view reads "${crop.startAt}" to crop from`);
    top = anchor.y - crop.margin;
  }
  const leak = all.find((view) => view.y >= top && localPath.test(view.text));
  if (leak) throw new Error(`${stem}: shows a local path: ${leak.text}`);
  return Math.round(top * (layout.scale ?? 2));
}

function usedNames() {
  const names = new Set();
  const walk = (folder) => {
    for (const entry of readdirSync(folder)) {
      const path = join(folder, entry);
      if (statSync(path).isDirectory()) walk(path);
      else if (/\.mdx?$/.test(entry)) {
        for (const match of readFileSync(path, 'utf8').matchAll(/<Shot[^>]*\bname="([^"]+)"/g)) {
          names.add(match[1]);
        }
      }
    }
  };
  walk(CONTENT);
  return names;
}

const [folder, flag] = process.argv.slice(2);
if (!folder) {
  console.error('usage: import-screens.mjs <screens.py out folder> [--used]');
  process.exit(2);
}
const used = flag === '--used' ? usedNames() : null;

mkdirSync(SCREENS, { recursive: true });
if (used) for (const file of readdirSync(SCREENS)) rmSync(join(SCREENS, file));

let written = 0;
let bytes = 0;
for (const file of readdirSync(folder).filter((name) => name.endsWith('.png'))) {
  const match = /^(.+)\.(light|dark)\.png$/.exec(file);
  if (!match) continue;
  const [, stem, look] = match;
  if (used && !used.has(stem)) continue;

  const layoutPath = join(folder, `${stem}.${look}.layout.json`);
  const layout = JSON.parse(readFileSync(layoutPath, 'utf8'));
  const top = topCut(stem, layout);

  let image = sharp(join(folder, file));
  const { width, height } = await image.metadata();
  if (top > 0) {
    await image
      .extract({ left: 0, top, width, height: height - top })
      .png()
      .toBuffer()
      .then((buffer) => (image = sharp(buffer)));
  }
  if (width > MAX_WIDTH) image = image.resize({ width: MAX_WIDTH });
  const target = join(SCREENS, `${stem}.${look}.webp`);
  const { size } = await image.webp({ quality: QUALITY }).toFile(target);
  written += 1;
  bytes += size;
}

console.log(
  `${basename(SCREENS)}: ${written} captures, ${(bytes / 1024 / 1024).toFixed(1)} MB` +
    (used ? ` (${used.size} screens named by pages)` : ''),
);
