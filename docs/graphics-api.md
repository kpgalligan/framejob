# Reelcut graphics — the API

A **graphic** is a motion graphic drawn by code: one JavaScript ES module
whose `render` returns an SVG string for each frame. Reelcut runs it in a
sandboxed QuickJS engine and rasterizes the SVG with resvg. The same frame
with the same props always draws the same pixels. This page is the whole
API. Every `js` block on it is run by a test, so the examples work as
written.

## The module

```js
export const meta = {
  name: "Lower third",        // shown in the inspector
  durationInFrames: 150,      // optional: the default length of a new clip
};

export const schema = {
  title:    { type: "string",  default: "Jane Doe", label: "Title" },
  subtitle: { type: "string",  default: "Director of Photography" },
  accent:   { type: "color",   default: "#ff5a36" },
  size:     { type: "number",  default: 64, min: 12, max: 200, step: 1 },
  boxed:    { type: "boolean", default: true },
  align:    { type: "enum",    default: "left", options: ["left", "center", "right"] },
};

export function render(frame, props, ctx) {
  const x = interpolate(frame, [0, 20], [-600, 96], { easing: Easing.outCubic, clamp: true });
  const fade = interpolate(frame, [ctx.durationInFrames - 15, ctx.durationInFrames - 1], [1, 0],
    { clamp: true });
  const y = ctx.height - 200;
  return svg(ctx, `
    <g opacity="${fade}">
      ${props.boxed ? `<rect x="${x}" y="${y - 90}" width="700" height="150" fill="#101014"/>` : ""}
      <rect x="${x}" y="${y - 90}" width="12" height="150" fill="${props.accent}"/>
      <text x="${x + 40}" y="${y}" font-family="Montserrat" font-weight="800"
            font-size="${props.size}" fill="#ffffff">${escapeXml(props.title)}</text>
    </g>`);
}
```

- `render(frame, props, ctx)` is required. It must return a string that
  starts with `<svg`; use `svg(ctx, body)` to write the root element.
- `meta` is optional (`{}` when absent). `name` and `durationInFrames` are
  read from it.
- `schema` is optional (`{}` when absent). It declares the props (below).
- The module is the only source of code: no `import`, no `eval`, no
  `Function`. The standard library below is already global.
- `frame` is an integer counted from the clip's first frame.

## `ctx`

| key | what |
|---|---|
| `fps` | the project's frame rate, e.g. `30` or `29.97002997` |
| `time` | `frame / fps`, in seconds |
| `durationInFrames` | the clip's length in frames |
| `progress` | `frame / max(1, durationInFrames - 1)`, clamped to 0–1 |
| `width`, `height` | the graphic's size in pixels |
| `canvas` | `{width, height}`, the project's canvas |

Write every coordinate in terms of `ctx.width` and `ctx.height` (or a unit
such as `const u = ctx.height / 1080`) so the graphic draws at any size.

## The schema

At most 64 keys. A key is letters, digits and `_`, starts with a letter or
`_`, and is at most 32 characters. Every entry needs a `type` and a
`default` of that type; `label` (else the key) and `help` (a tooltip) are
optional.

| `type` | value | options |
|---|---|---|
| `string` | text, at most 4096 characters | `multiline: true` for a text area |
| `number` | a finite number | `min`, `max`, `step` |
| `boolean` | `true` / `false` | |
| `color` | a CSS colour string: `"#ff5a36"`, `"rgb(255, 90, 54)"` | |
| `enum` | one of `options` | `options`: 1–32 strings |
| `asset` | a file name in `graphics/assets/`, or `null` | `kind: "image"` |

A schema that breaks a rule does not compile, and the error says which rule.
`props` always has every schema key: a stored value replaces the default
only when it fits the type. A value that does not fit is a WARNING, the
default is drawn, and the frame still draws, e.g.
`props.size is a string but the schema says number; the default 64 is used`.

## The standard library

### `svg(ctx, body, {background})`

The root element with the right `width`, `height` and `viewBox`.

```js
const plain = svg(ctx, `<circle cx="100" cy="100" r="50" fill="#fff"/>`);
const onBlack = svg(ctx, "", { background: "#000000" });
```

### `interpolate(value, input, output, {easing, clamp, extrapolateLeft, extrapolateRight})`

Maps `value` through matching `input` and `output` ranges (two or more
points, `input` ascending). Outside `input` it extends the end segment
unless `clamp: true`; `extrapolateLeft` / `extrapolateRight` take
`"extend"`, `"clamp"` or `"identity"`.

```js
const x = interpolate(frame, [0, 30], [0, 400], { clamp: true });
const pulse = interpolate(frame, [0, 15, 30], [1, 1.2, 1], { easing: Easing.inOutSine });
```

### `Easing`

`Easing.linear`, `Easing.bezier(x1, y1, x2, y2)`, and `in`, `out` and `inOut`
of `quad`, `cubic`, `quart`, `expo`, `sine`, `back` and `elastic`, spelled
`Easing.inQuad`, `Easing.outCubic`, `Easing.inOutBack` and so on. Each takes
`t` in 0–1 and is exact at 0 and 1.

```js
const eased = Easing.outCubic(0.5);
const custom = Easing.bezier(0.25, 0.1, 0.25, 1)(0.5);
const y = interpolate(frame, [0, 20], [300, 0], { easing: Easing.outBack, clamp: true });
```

### `spring({frame, fps, stiffness = 100, damping = 10, mass = 1, from = 0, to = 1})`

A physical spring from `from` to `to`, starting at frame 0 (use
`frame - delay` to start later). It overshoots unless damped. The same frame
always answers the same value.

```js
const scale = spring({ frame, fps: ctx.fps, damping: 14 });
const late = spring({ frame: frame - 12, fps: ctx.fps, stiffness: 180, from: 0.5, to: 1 });
```

### `interpolateColors(value, input, colors)`

Blends colours in OKLab and answers `#rrggbb` (or `#rrggbbaa` when a colour
has alpha). Clamped outside `input`.

```js
const fill = interpolateColors(frame, [0, 60], ["#ff5a36", "#3666ff"]);
const glass = interpolateColors(ctx.progress, [0, 1], ["rgba(255, 255, 255, 0)", "#ffffff"]);
```

### `random(seed)`

A number in [0, 1) that depends only on `seed` (a number or a string).
`Math.random` does not exist in a graphic; this replaces it.

```js
const jitter = random(`dot-${frame}`) * 10;
const hue = Math.floor(random(42) * 360);
```

### `noise2D(seed, x, y)` and `noise3D(seed, x, y, z)`

Simplex noise in about −1..1. Use `noise3D` with time as the third axis for
smooth drift.

```js
const drift = noise2D("wave", frame / 60, 0) * 40;
const wobble = noise3D(7, 0.5, 0.5, ctx.time) * 20;
```

### `measureText(text, font)`

`font` is `{family, size, weight, style, letterSpacing}` (defaults
Montserrat, 16, 400, `"normal"`, 0). Answers `{width, ascent, descent,
lineHeight, inkX, inkWidth}`: `width` is the advance (where the next word
starts); `inkX` / `inkWidth` are the drawn glyphs. Spaces collapse as SVG
draws them. A family that is not installed throws, naming the families that
are.

```js
const m = measureText("Hello", { family: "Montserrat", size: 64, weight: 800 });
const boxWidth = m.width + 80;
```

### `wrapText(text, maxWidth, font)`

Lines that each fit `maxWidth`; a word longer than the width breaks by
characters.

```js
const lines = wrapText("A title long enough to need two lines", 600,
  { family: "Source Sans 3", size: 64, weight: 700 });
```

### `fitText(text, maxWidth, font, {min = 8, max = 400})`

The largest whole font size at which `text` fits `maxWidth` on one line.

```js
const size = fitText("BREAKING", ctx.width - 200, { family: "Anton" }, { max: 300 });
```

### `textLines(lines, {x, y, lineHeight, anchor, fill, font})`

A `<text>` with one `<tspan>` per line, the family QUOTED for you.
`anchor` is `"start"`, `"middle"` or `"end"`; `lineHeight` defaults to
1.2 × the size.

```js
const font = { family: "Source Sans 3", size: 48, weight: 600 };
const body = textLines(wrapText("Two short lines of text", 400, font),
  { x: 100, y: 200, anchor: "start", fill: "#ffffff", font });
```

### `escapeXml(s)`

Escapes `& < > " '` — put every prop you write into markup through it.

```js
const safe = escapeXml("Tom & Jerry <live>");
```

### `formatNumber(n, {decimals = 0, separator = ","})`

There is no `Intl` in the engine; this groups thousands.

```js
const label = formatNumber(1234567.891, { decimals: 2 });
const plain = formatNumber(Math.round(interpolate(frame, [0, 60], [0, 5000], { clamp: true })));
```

### `asset(name)`

The href for a file in the project's `graphics/assets/` folder, for
`<image href="…">`. A name that is not there is a warning naming the files
that are; the image then does not draw.

```js
const logo = `<image href="${asset("logo.png")}" x="40" y="40" width="200" height="200"/>`;
```

## Fonts

A graphic draws with the fonts bundled with Reelcut, plus any `.ttf` /
`.otf` in the project's `graphics/fonts/`. Never the system's.

| family | weights |
|---|---|
| Anton | 400 |
| Bebas Neue | 400 |
| Darker Grotesque | variable, 300–900 |
| IBM Plex Mono | 400, 500 |
| Montserrat | 800, 900 |
| Source Sans 3 | variable, 200–900 |

**Quote a family** in `font-family` when any word of it starts with a
digit: `font-family="'Source Sans 3'"`. Unquoted, `Source Sans 3` is not a
valid family list and falls back to the default face. `textLines` quotes
for you. A family the set lacks draws in the fallback face with a warning.

## The sandbox

A graphic is a pure function of `frame`, `props`, `ctx` and its fonts and
assets. These refuse, with these sentences:

```text
Math.random()        → Math.random is not available; use random(seed)
import x from "x"    → imports are not available in a graphic; the standard library is global
new Function("…")    → Function is not available in a graphic; the module is the one source of code
eval("…")            → ReferenceError: eval is not defined
```

`Date` is frozen: `Date.now()` is `946684800000` and `new Date()` is
2000-01-01T00:00:00Z. There is no `fetch`, file, clock, `performance`,
`WebAssembly` or `Intl`. Modern syntax works: template literals, `??`, `?.`,
`**`, destructuring, `Array.prototype.at`, `replaceAll`, `findLast`.

## Limits

- **Time**: each call has a budget — 250 ms per frame in preview, 2 s in an
  export. The module's top level has one too. Over it, the answer is an
  error such as `over the 250 ms budget at frame 12 (InternalError:
  interrupted)`.
- **Memory**: 64 MB of heap and 1 MB of stack per engine. Past either is an
  error with a line and column.
- **Size**: a graphic draws at most 8192 pixels on a side.
- **The answer**: `render` must return an SVG string. `undefined` is
  ``render returned undefined at frame 12 — did you forget `return`?``.

## Diagnostics

Every problem comes back as `{level, message, line, column, frame}`.
`level` is `"error"` (nothing drew) or `"warning"` (it drew anyway).
`line` and `column` are the module's own, when known; for a timeout they
are where the function begins, not the statement that ran long. `frame` is
set for a problem found while drawing.

## Working over MCP

Read `graphic_reference` once. `write_graphic {name, source}` answers `ok` and
`diagnostics`: write again until `ok` is true. `render_graphic {name, frames}`
draws up to 16 frames on a contact sheet with no clip; `add_graphic_clip {name}`
places it, `render_frame` shows a frame, `set_graphic {patch: {props}}` changes
it. `import_graphic_font {path}` answers `families`, the exact names
`font-family` must say; `import_graphic_asset {path}` adds a picture for
`asset(name)`. `get_graphic` reads a module or names the folder, which your file
tools may edit too; its `API.md` is this page, `API.d.ts` its types.

## Idioms

### A slide-in

```js
export const meta = { name: "Slide in", durationInFrames: 90 };
export const schema = { text: { type: "string", default: "Hello" } };

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const x = interpolate(frame, [0, 18], [-ctx.width / 2, ctx.width / 2],
    { easing: Easing.outCubic, clamp: true });
  return svg(ctx, `<text x="${x}" y="${ctx.height / 2}" text-anchor="middle"
    font-family="Montserrat" font-weight="800" font-size="${120 * u}"
    fill="#ffffff">${escapeXml(props.text)}</text>`);
}
```

### A staggered list

```js
export const meta = { name: "Agenda" };
export const schema = {
  items: { type: "string", default: "Intro\nDemo\nQuestions", multiline: true },
  accent: { type: "color", default: "#ffcc00" },
};

export function render(frame, props, ctx) {
  const u = ctx.height / 1080;
  const rows = props.items.split("\n").filter((s) => s.trim()).map((item, i) => {
    const t = spring({ frame: frame - i * 6, fps: ctx.fps, damping: 16 });
    const y = 300 * u + i * 110 * u;
    return `<g opacity="${Math.min(1, t)}" transform="translate(${(1 - t) * 80 * u} 0)">
      <rect x="${160 * u}" y="${y - 50 * u}" width="${14 * u}" height="${64 * u}" fill="${props.accent}"/>
      <text x="${200 * u}" y="${y}" font-family="'Source Sans 3'" font-weight="600"
        font-size="${64 * u}" fill="#ffffff">${escapeXml(item)}</text></g>`;
  });
  return svg(ctx, rows.join(""));
}
```

### A counter

```js
export const meta = { name: "Counter", durationInFrames: 120 };
export const schema = {
  to: { type: "number", default: 25000, min: 0 },
  suffix: { type: "string", default: " views" },
};

export function render(frame, props, ctx) {
  const value = interpolate(frame, [0, 60], [0, props.to], { easing: Easing.outExpo, clamp: true });
  const text = formatNumber(Math.round(value)) + props.suffix;
  return svg(ctx, `<text x="${ctx.width / 2}" y="${ctx.height / 2}" text-anchor="middle"
    font-family="'IBM Plex Mono'" font-weight="500" font-size="${ctx.height / 8}"
    fill="#ffffff">${escapeXml(text)}</text>`);
}
```

### Fit and wrap a title

```js
export const meta = { name: "Title card" };
export const schema = {
  title: { type: "string", default: "The quick brown fox jumps over the lazy dog" },
};

export function render(frame, props, ctx) {
  const maxWidth = ctx.width * 0.8;
  const base = { family: "Bebas Neue", weight: 400 };
  const size = fitText(props.title, maxWidth * 2, base, { min: 48, max: 220 });
  const font = Object.assign({}, base, { size });
  const lines = wrapText(props.title, maxWidth, font);
  const top = ctx.height / 2 - (lines.length - 1) * size * 0.6;
  const fade = interpolate(frame, [0, 12], [0, 1], { clamp: true });
  return svg(ctx, `<g opacity="${fade}">${textLines(lines,
    { x: ctx.width / 2, y: top, anchor: "middle", fill: "#ffffff", font })}</g>`,
    { background: "#16161a" });
}
```

### A draw-on stroke

Give the path a known length (or overestimate it), dash it that long, and
move the dash offset from the length to 0.

```js
export const meta = { name: "Underline", durationInFrames: 60 };
export const schema = { color: { type: "color", default: "#ff5a36" } };

export function render(frame, props, ctx) {
  const length = ctx.width * 0.6;
  const drawn = interpolate(frame, [0, 24], [length, 0], { easing: Easing.inOutCubic, clamp: true });
  const y = ctx.height * 0.62;
  return svg(ctx, `<path d="M ${ctx.width * 0.2} ${y} h ${length}" stroke="${props.color}"
    stroke-width="${ctx.height / 90}" stroke-linecap="round" fill="none"
    stroke-dasharray="${length} ${length}" stroke-dashoffset="${drawn}"/>`);
}
```
