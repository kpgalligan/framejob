# Frame Job graphics — the API

A **graphic** is a motion graphic drawn by code: one JavaScript ES module
whose `render` returns an SVG string for each frame. Frame Job runs it in a
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
| `color` | a CSS colour string: `"#ff5a36"`, `"rgb(255, 90, 54)"`, `"hsl(11, 100%, 61%)"`, `"tomato"` | |
| `enum` | one of `options` | `options`: 1–32 strings |
| `asset` | a file name in `graphics/assets/`, or `null` | `kind: "image"` |

A schema that breaks a rule does not compile, and the error says which rule.
A `color` entry's `default` must be a colour in the grammar
`interpolateColors` lists below, or the module does not compile:
`schema.accent.default "bluish" is not a color`. `props` receives the
default as written, not normalised.
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
has alpha). Clamped outside `input`. A colour is `#rgb`, `#rgba`, `#rrggbb`,
`#rrggbbaa`, `rgb()` / `rgba()` (channels 0–255 or a percentage, alpha 0–1
or a percentage), `hsl()` / `hsla()` (hue in degrees, saturation and
lightness percentages), or one of the 147 CSS colour names or
`transparent` — the same colours a `color` prop takes. A value out of range
(`rgb(300, 0, 0)`) throws rather than being clamped.

```js
const fill = interpolateColors(frame, [0, 60], ["#ff5a36", "#3666ff"]);
const glass = interpolateColors(ctx.progress, [0, 1], ["rgba(255, 255, 255, 0)", "#ffffff"]);
const sky = interpolateColors(ctx.progress, [0, 1], ["hsl(200, 80%, 30%)", "skyblue"]);
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

### Paths: `getLength(d)`, `getPointAtLength(d, length)` and `evolvePath(progress, d)`

`d` is SVG path data: every command (`M L H V C S Q T A Z`) and its
relative form. `getLength` answers the path's length, curves and arcs
measured to within about 0.01 %. `getPointAtLength` answers `{x, y, angle}`:
the point that far along the path (`length` is clamped to the path) and the
way the path is heading there, in degrees, ready for `rotate()`.
`evolvePath` answers `{strokeDasharray, strokeDashoffset}` for a `progress`
of 0–1: put both on the `<path>` and it is drawn from its start up to that
fraction. Its dash is 0.1 % longer than the measured length, so a closed
outline closes at 1.

A path of several pieces (more than one `M`) draws them all at once, each
from its own start and at the same speed, the longest finishing at 1; pieces
drawn one after another are one `<path>` each. A path that cannot be read
throws, naming where reading stopped —
`getLength: cannot parse the path at character 6: "X 5 5"` — and is never a
silent zero. A number too large to do arithmetic with (`1e999`, or a line
1e200 long, whose square overflows) is refused in the same sentence, so no
answer is ever `Infinity` or `NaN`.

The paths a graphic measures are remembered, so the same `d` costs a lookup
on later calls and frames — up to 32 paths, and about 50,000 characters and
measured pieces between them (a curve is 64 pieces). Past either limit all
are forgotten and measured again when next asked for, so with paths that
large take every length and point from one before turning to the next.

```js
const d = `M 200 ${ctx.height / 2} C 600 100 1000 900 1400 ${ctx.height / 2}`;
const total = getLength(d);
const tip = getPointAtLength(d, total * ctx.progress);
const dash = evolvePath(ctx.progress, d);
const line = `<path d="${d}" fill="none" stroke="#ffffff" stroke-width="8"
  stroke-dasharray="${dash.strokeDasharray}" stroke-dashoffset="${dash.strokeDashoffset}"/>
  <circle cx="${tip.x}" cy="${tip.y}" r="12" fill="#ffcc00"/>`;
```

### `measureText(text, font)`

`font` is `{family, size, weight, style, letterSpacing, xmlSpace}`
(defaults Montserrat, 16, 400, `"normal"`, 0, `"default"`). Answers
`{width, ascent, descent, lineHeight, inkX, inkWidth}`: `width` is the
advance (where the next word starts); `inkX` / `inkWidth` are the drawn
glyphs. With `xmlSpace: "default"` runs of spaces collapse as SVG draws
them; with `"preserve"` a run of spaces beside a drawn glyph counts, as
`xml:space="preserve"` draws it, and any other value throws. Text that is
only whitespace measures zero either way. A family that is not installed
throws, naming the families that are.

```js
const m = measureText("Hello", { family: "Montserrat", size: 64, weight: 800 });
const boxWidth = m.width + 80;
const gap = measureText("a  b", { family: "sans-serif", size: 48, xmlSpace: "preserve" });
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

A `<text>` with one `<tspan>` per line, the family QUOTED for you (a CSS
generic such as `sans-serif` is written bare, as it must be).
`anchor` is `"start"`, `"middle"` or `"end"`; `lineHeight` defaults to
1.2 × the size. A font with `xmlSpace: "preserve"` writes
`xml:space="preserve"` on the `<text>`, so it draws the spaces `measureText`
counted.

```js
const font = { family: "Source Sans 3", size: 48, weight: 600 };
const body = textLines(wrapText("Two short lines of text", 400, font),
  { x: 100, y: 200, anchor: "start", fill: "#ffffff", font });
const code = textLines(["let  x = 1;"],
  { x: 100, y: 300, font: { family: "monospace", size: 32, xmlSpace: "preserve" } });
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

An asset's name must not start with `.` or `#`, must hold none of
`/ : " ' < > &` and no control character, and is at most 247 bytes. A
picture added under any other name is renamed as it is copied in —
`#logo&mark.png` becomes `logo-mark.png`, then `logo-mark-2.png` if that is
taken — and you are told the name to use. A file put in the folder by hand
under such a name is skipped, with a warning.

```js
const logo = `<image href="${asset("logo.png")}" x="40" y="40" width="200" height="200"/>`;
```

## Fonts

A graphic draws with the fonts bundled with Frame Job, plus any `.ttf` /
`.otf` in the project's `graphics/fonts/`. Never the system's.

| family | weights |
|---|---|
| Anton | 400 |
| Bebas Neue | 400 |
| Darker Grotesque | variable, 300–900 |
| IBM Plex Mono | 400, 500 |
| Montserrat | 800, 900 |
| Source Sans 3 | variable, 200–900 |
| Source Serif 4 | variable, 200–900 |

The CSS generic families draw in bundled faces: `serif` is Source Serif 4,
`sans-serif` is Source Sans 3 and `monospace` is IBM Plex Mono. Write a
generic unquoted (`font-family="sans-serif"`); quoted, it names a family
called "sans-serif", which is not installed. `cursive` and `fantasy` are not
installed.

**Quote a family** in `font-family` or the `font` shorthand when any word
of it starts with a digit: `font-family="'Source Sans 3'"`,
`font: 48px 'Source Sans 3'`. Unquoted, `Source Sans 3` is not a
valid family list: it draws nothing, with a warning. `textLines` quotes
for you. A family the set lacks draws nothing, with a warning naming the
families that are installed; in a list (`"Nope, Montserrat"`) the first
installed family draws.

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
  The string may be at most 8 MiB (8388608 bytes); a longer one is
  `render returned 9000000 bytes at frame 12; the SVG may be at most
  8388608 bytes`.

## Diagnostics

Every problem comes back as `{level, message, line, column, frame}`.
`level` is `"error"` (nothing drew) or `"warning"` (it drew anyway).
`line` and `column` are the module's own, when known; for a timeout they
are where the function begins, not the statement that ran long. `frame` is
set for a problem found while drawing. A warning from the module's top level
(such as `asset("x")` outside `render`) has no frame, and comes back with the
module's compile: `ok` is still `true`.

## Working over MCP

Read `graphic_reference` once. `write_graphic {name, source}` answers `ok` and
`diagnostics`: write again until `ok` is true. `render_graphic {name, frames}`
draws up to 16 frames on a contact sheet with no clip, at most 134217728
pixels of frames in all (two at 8192×8192, or sixteen at 3840×2160);
`add_graphic_clip {name}` places it, `render_frame` shows a frame,
`set_graphic {patch: {props}}` changes it.
`paste_attributes {clips, payload, groups: ["graphic"]}` copies one clip's props onto other clips
drawn by the same module. `import_graphic_font {path}` answers `families`, the exact names
`font-family` must say; `import_graphic_asset {path}` adds a picture for
`asset(name)`; its `name` is the one to use, and `renamed_from` says it was
renamed. `get_graphic` reads a module or names the folder, which your file
tools may edit too; its `API.md` is this page, `API.d.ts` its types.
`get_graphic {}`'s `warnings` says what the folder's scan skipped or could
not watch, such as a file whose name is not a module name. The app keeps the
last 10 texts of each module whenever it sees one replaced: `kept`, in
`write_graphic`'s and `get_graphic {name}`'s answers, lists their revisions,
newest first, and `get_graphic {}`'s `history` lists every name with a kept
text, deleted modules included. `restore_graphic {name, revision?}` writes a
kept text back (the newest by default) and keeps the one it replaced.
`delete_graphic {name}` removes a module no clip draws and keeps its text, so
`restore_graphic` brings it back. `rename_graphic {name, to}` renames a
module and repoints every clip that draws it as one undo step; undo renames
the file back. The folder's `history/` is the app's: leave it to those three
tools. A successful
`export` answers `graphic_warnings`, each distinct warning a graphic gave
while the file was drawn, with its name and frame.

## Animating a prop from the timeline

A graphic clip's props can be the target of an action, as a clip's position or opacity can:
`add_action {clip, at, duration}` makes the span, and `set_action_end {clip, action, patch:
{graphic: {props: {…}}}}` names the values the props end at. Each value is checked against your
schema as `set_graphic` checks it, `min` and `max` included, using the module as it is now. Across
the action a `number` and a `color` ramp along its curve; a `string`, `boolean` and `enum` change to
the end's value when the action ends; an `asset` cannot be animated. A prop the clip holds no value
for starts from the schema's `default` as it is when an action first names it, and that value is
written into the clip, so a later change to the default does not move the animation. `render` gets
that frame's values every frame, and your own animation from `frame` still runs on top. A `null`
for a prop in `set_action_end`'s patch stops animating it.

**An animated number arrives with decimals**: 64 to 129 is 96.5 halfway, never rounded and never
snapped to `step`. A module that needs a whole number rounds it itself. One that does not —
`new Array(props.count)` is the usual case — throws on a fraction, so those frames draw the error
card, and an export stops there.

```js
export const meta = { name: "Bars", durationInFrames: 90 };
export const schema = {
  count: { type: "number", default: 5, min: 1, max: 20, step: 1 },
  accent: { type: "color", default: "#ff5a36" },
};

export function render(frame, props, ctx) {
  const n = Math.round(props.count);
  const w = ctx.width / (2 * n);
  let bars = "";
  for (let i = 0; i < n; i++) {
    bars += `<rect x="${(2 * i + 0.5) * w}" y="${ctx.height / 3}" width="${w}"
      height="${ctx.height / 3}" fill="${props.accent}"/>`;
  }
  return svg(ctx, bars);
}
```

A colour blends channel by channel with straight alpha: `#ff0000` to `#0000ff` is `#800080`
halfway, and `#ffffff` to `#00000000` is `#80808080`, grey and half transparent. While a prop
moves, every frame is drawn anew, so a graphic that had settled costs a full draw per frame for the
length of the action.

## Video inside a graphic: the matte

A graphic cannot read a video's pixels. To show video inside a shape the graphic draws, put the
graphic on the track directly above the video and switch that track to a **matte**: Track ▸ Matte
in the app, or `set_track {track, matte}` over MCP. A matte track's clips are never drawn. What
they show cuts the track directly behind: with `alpha`, the video shows where the graphic is
opaque; with `alpha_inverted`, where it is transparent; with `luma` and `luma_inverted`, by the
brightness of what it draws. `matte: "none"` turns it off. Where the matte track has no clip, the
video shows uncut. The module is written and called exactly as anywhere else. Fill the window in
white so it works in every mode, and animate it as usual: the cut follows each frame.

```js
export const meta = { name: "Window", durationInFrames: 90 };
export const schema = { radius: { type: "number", default: 24, min: 0, max: 200 } };

export function render(frame, props, ctx) {
  const t = spring({ frame, fps: ctx.fps, damping: 18 });
  const w = ctx.width * 0.6 * t;
  const h = ctx.height * 0.6 * t;
  return svg(ctx, `<rect x="${(ctx.width - w) / 2}" y="${(ctx.height - h) / 2}"
    width="${w}" height="${h}" rx="${props.radius}" fill="#ffffff"/>`);
}
```

On a matte track a clip's position, scale, opacity, crop and actions still shape the window. Its
blend mode, drop shadow and reflection do nothing. The matted video's own drop shadow follows the
cut-out shape.

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

`evolvePath` measures the path and answers the dash that draws it up to a
progress of 0–1.

```js
export const meta = { name: "Underline", durationInFrames: 60 };
export const schema = { color: { type: "color", default: "#ff5a36" } };

export function render(frame, props, ctx) {
  const y = ctx.height * 0.62;
  const d = `M ${ctx.width * 0.2} ${y} q ${ctx.width * 0.3} ${ctx.height * 0.05} ${ctx.width * 0.6} 0`;
  const drawn = interpolate(frame, [0, 24], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const dash = evolvePath(drawn, d);
  return svg(ctx, `<path d="${d}" stroke="${props.color}"
    stroke-width="${ctx.height / 90}" stroke-linecap="round" fill="none"
    stroke-dasharray="${dash.strokeDasharray}" stroke-dashoffset="${dash.strokeDashoffset}"/>`);
}
```

### Follow a path

`getPointAtLength` answers where the path is and which way it is heading;
`rotate(angle)` turns an arrowhead drawn pointing right to match.

```js
export const meta = { name: "Arrow", durationInFrames: 60 };
export const schema = { color: { type: "color", default: "#ffffff" } };

export function render(frame, props, ctx) {
  const w = ctx.width;
  const h = ctx.height;
  const d = `M ${w * 0.2} ${h * 0.7} C ${w * 0.4} ${h * 0.2} ${w * 0.6} ${h * 0.2} ${w * 0.8} ${h * 0.5}`;
  const drawn = interpolate(frame, [0, 30], [0, 1], { easing: Easing.inOutCubic, clamp: true });
  const dash = evolvePath(drawn, d);
  const tip = getPointAtLength(d, getLength(d) * drawn);
  const s = h / 36;
  return svg(ctx, `<path d="${d}" stroke="${props.color}" stroke-width="${h / 120}" fill="none"
    stroke-dasharray="${dash.strokeDasharray}" stroke-dashoffset="${dash.strokeDashoffset}"/>
    <path d="M ${-s} ${-s * 0.6} L ${s * 0.5} 0 L ${-s} ${s * 0.6} Z" fill="${props.color}"
    transform="translate(${tip.x} ${tip.y}) rotate(${tip.angle})"/>`);
}
```
