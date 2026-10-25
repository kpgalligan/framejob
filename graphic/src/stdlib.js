// The graphics standard library — road map 10 §5c. Written from scratch
// (G-2): the names and argument shapes follow Remotion's, none of its code
// is here. Evaluated as a SCRIPT before `noise.js`, `path.js` and the sandbox,
// so every declaration is a global. The host functions `__measureText`,
// `__assetNames`, `__warn` and `__namedColour` are installed before it runs.

function svg(ctx, body, options) {
  const o = options || {};
  const background = o.background
    ? `<rect x="0" y="0" width="${ctx.width}" height="${ctx.height}" fill="${escapeXml(o.background)}"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${ctx.width}" height="${ctx.height}" ` +
    `viewBox="0 0 ${ctx.width} ${ctx.height}">${background}${body}</svg>`;
}

// The segment of `input` that `value` falls in: the index of its right end.
function __segment(value, input) {
  let i = 1;
  while (i < input.length - 1 && value > input[i]) i++;
  return i;
}

function interpolate(value, input, output, options) {
  const o = options || {};
  const n = input.length;
  if (n < 2 || output.length !== n) {
    throw new Error("interpolate: input and output need the same length, at least 2");
  }
  const left = o.extrapolateLeft || (o.clamp ? "clamp" : "extend");
  const right = o.extrapolateRight || (o.clamp ? "clamp" : "extend");
  const i = __segment(value, input);
  const a = input[i - 1];
  const b = input[i];
  let t = b === a ? 0 : (value - a) / (b - a);
  if (t < 0) {
    if (left === "clamp") t = 0;
    else if (left === "identity") return value;
  }
  if (t > 1) {
    if (right === "clamp") t = 1;
    else if (right === "identity") return value;
  }
  const eased = o.easing ? o.easing(t) : t;
  return output[i - 1] + (output[i] - output[i - 1]) * eased;
}

const Easing = (() => {
  const E = { linear: (t) => t };
  const curves = {
    quad: (t) => t * t,
    cubic: (t) => t * t * t,
    quart: (t) => t * t * t * t,
    expo: (t) => (t <= 0 ? 0 : Math.pow(2, 10 * (t - 1))),
    sine: (t) => 1 - Math.cos((t * Math.PI) / 2),
    back: (t) => t * t * (2.70158 * t - 1.70158),
    elastic: (t) =>
      t <= 0 || t >= 1 ? t : -Math.pow(2, 10 * (t - 1)) * Math.sin(((t - 1.075) * 2 * Math.PI) / 0.3),
  };
  for (const name of Object.keys(curves)) {
    const f = curves[name];
    const cap = name[0].toUpperCase() + name.slice(1);
    // Exact at the ends: a clamped animation lands where it was told to.
    const ends = (g) => (t) => (t === 0 ? 0 : t === 1 ? 1 : g(t));
    E["in" + cap] = ends(f);
    E["out" + cap] = ends((t) => 1 - f(1 - t));
    E["inOut" + cap] = ends((t) => (t < 0.5 ? f(2 * t) / 2 : 1 - f(2 * (1 - t)) / 2));
  }
  E.bezier = (x1, y1, x2, y2) => {
    const at = (p1, p2, s) => 3 * p1 * s * (1 - s) * (1 - s) + 3 * p2 * s * s * (1 - s) + s * s * s;
    const slope = (p1, p2, s) => 3 * p1 * (1 - s) * (1 - s) + 6 * (p2 - p1) * s * (1 - s) + 3 * (1 - p2) * s * s;
    return (t) => {
      if (t <= 0 || t >= 1) return t;
      let s = t;
      for (let k = 0; k < 8; k++) {
        const d = slope(x1, x2, s);
        if (Math.abs(d) < 1e-7) break;
        s -= (at(x1, x2, s) - t) / d;
      }
      if (!(s >= 0 && s <= 1) || Math.abs(at(x1, x2, s) - t) > 1e-6) {
        let lo = 0;
        let hi = 1;
        for (let k = 0; k < 40; k++) {
          s = (lo + hi) / 2;
          if (at(x1, x2, s) < t) lo = s;
          else hi = s;
        }
      }
      return at(y1, y2, s);
    };
  };
  return Object.freeze(E);
})();

// Semi-implicit Euler at a fixed 1/240 s from frame 0, so a frame's value
// never depends on which frames were asked before it.
function spring(options) {
  const { frame, fps, stiffness = 100, damping = 10, mass = 1, from = 0, to = 1 } = options;
  if (!(frame > 0)) return from;
  const steps = Math.round((frame / fps) * 240);
  const dt = 1 / 240;
  let x = from;
  let v = 0;
  for (let i = 0; i < steps; i++) {
    const a = (-stiffness * (x - to) - damping * v) / mass;
    v += a * dt;
    x += v * dt;
  }
  return x;
}

// ---- colour ----------------------------------------------------------------

// G-12's grammar, the second implementation of `core/src/model_color.rs`
// (both answer `graphic/tests/colours.json`) → [r, g, b, a], r, g, b integer
// bytes and a the alpha byte / 255, so it quantises as the core stores. A
// value outside its range throws; nothing is clamped.
function __parseColour(text) {
  const fail = () => {
    throw new Error(`interpolateColors: cannot parse colour "${text}"`);
  };
  let s = String(text);
  if (/[^\x00-\x7f]/.test(s)) fail();
  s = s.replace(/^[ \t\n\f\r]+|[ \t\n\f\r]+$/g, "").toLowerCase();
  const hex = /^#([0-9a-f]+)$/.exec(s);
  if (hex) {
    let h = hex[1];
    if (![3, 4, 6, 8].includes(h.length)) fail();
    if (h.length <= 4) h = [...h].map((c) => c + c).join("");
    const byte = (k) => parseInt(h.slice(k, k + 2), 16);
    return [byte(0), byte(2), byte(4), (h.length === 8 ? byte(6) : 255) / 255];
  }
  const call = /^(rgba?|hsla?)\((.*)\)$/s.exec(s);
  if (call) {
    const parts = call[2].split(/[,\/ \t\n\f\r]+/).filter((p) => p.length);
    if (parts.length !== 3 && parts.length !== 4) fail();
    const number = (p) => (/^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/.test(p) ? Number(p) : fail());
    const unit = (u) => (u >= 0 && u <= 1 ? u : fail());
    const byte = (u) => Math.round(u * 255);
    const percent = (p) => (p.endsWith("%") ? number(p.slice(0, -1)) / 100 : fail());
    const alpha = parts.length === 4
      ? byte(unit(parts[3].endsWith("%") ? percent(parts[3]) : number(parts[3])))
      : 255;
    if (call[1].startsWith("rgb")) {
      const channel = (p) => byte(unit(p.endsWith("%") ? percent(p) : number(p) / 255));
      return [channel(parts[0]), channel(parts[1]), channel(parts[2]), alpha / 255];
    }
    const hue = number(parts[0].endsWith("deg") ? parts[0].slice(0, -3) : parts[0]);
    if (!isFinite(hue)) fail();
    let h = hue % 360;
    if (h < 0) h += 360;
    const sat = unit(percent(parts[1]));
    const l = unit(percent(parts[2]));
    // The core's steps in the core's order (G-12), so both round one byte.
    const a = sat * Math.min(l, 1 - l);
    const channel = (n) => {
      const k = (n + h / 30) % 12;
      return byte(l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)));
    };
    return [channel(0), channel(8), channel(4), alpha / 255];
  }
  const named = JSON.parse(__namedColour(s));
  if (!named) fail();
  return [named[0], named[1], named[2], named[3] / 255];
}

function __toLinear(c) {
  const v = c / 255;
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

function __fromLinear(v) {
  const s = v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
  return Math.max(0, Math.min(255, Math.round(s * 255)));
}

function __toOklab([r, g, b, a]) {
  const [lr, lg, lb] = [__toLinear(r), __toLinear(g), __toLinear(b)];
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    a,
  ];
}

function __fromOklab([L, A, B, alpha]) {
  const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
  const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
  const s = Math.pow(L - 0.0894841775 * A - 1.291485548 * B, 3);
  return [
    __fromLinear(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    __fromLinear(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    __fromLinear(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
    alpha,
  ];
}

function __hex(rgba, withAlpha) {
  const byte = (v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0");
  return "#" + byte(rgba[0]) + byte(rgba[1]) + byte(rgba[2]) + (withAlpha ? byte(rgba[3] * 255) : "");
}

// Interpolates in OKLab between the colours at the two ends of the segment
// `value` falls in, clamped outside `input`; `#rrggbb`, or `#rrggbbaa` when
// any colour's alpha is not 1.
function interpolateColors(value, input, colors) {
  if (input.length < 2 || colors.length !== input.length) {
    throw new Error("interpolateColors: input and colors need the same length, at least 2");
  }
  const parsed = colors.map(__parseColour);
  const withAlpha = parsed.some((c) => c[3] !== 1);
  const i = __segment(value, input);
  const a = input[i - 1];
  const b = input[i];
  const t = b === a ? 0 : (value - a) / (b - a);
  if (t <= 0) return __hex(parsed[i - 1], withAlpha);
  if (t >= 1) return __hex(parsed[i], withAlpha);
  const from = __toOklab(parsed[i - 1]);
  const to = __toOklab(parsed[i]);
  return __hex(__fromOklab(from.map((v, k) => v + (to[k] - v) * t)), withAlpha);
}

// splitmix32 over an FNV-1a hash of the seed's text: a number in [0, 1).
function random(seed) {
  const text = String(seed);
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  let a = (h + 0x9e3779b9) | 0;
  let t = a ^ (a >>> 16);
  t = Math.imul(t, 0x21f0aaad);
  t ^= t >>> 15;
  t = Math.imul(t, 0x735a2d97);
  t ^= t >>> 15;
  return (t >>> 0) / 4294967296;
}

// ---- text ------------------------------------------------------------------

// The host measures and memoises (its key has letter-spacing and xmlSpace
// in it); a family the set lacks throws the host's sentence naming the
// families, and an xmlSpace other than "default" / "preserve" its own (G-22).
function measureText(text, font) {
  const { family = "Montserrat", size = 16, weight = 400, style = "normal", letterSpacing = 0,
    xmlSpace = "default" } = font || {};
  const m = JSON.parse(__measureText(String(text), String(family), Number(size), Number(weight),
    String(style), Number(letterSpacing), String(xmlSpace)));
  if (m.error) throw new Error(m.error);
  return m;
}

function wrapText(text, maxWidth, font) {
  const lines = [];
  let line = "";
  const fits = (s) => measureText(s, font).width <= maxWidth;
  for (const word of String(text).split(/\s+/).filter((w) => w.length)) {
    const candidate = line ? line + " " + word : word;
    if (fits(candidate)) {
      line = candidate;
      continue;
    }
    if (line) lines.push(line);
    line = "";
    if (fits(word)) {
      line = word;
      continue;
    }
    let piece = "";
    for (const ch of word) {
      if (piece && !fits(piece + ch)) {
        lines.push(piece);
        piece = "";
      }
      piece += ch;
    }
    line = piece;
  }
  if (line) lines.push(line);
  return lines;
}

function fitText(text, maxWidth, font, options) {
  const o = options || {};
  const min = o.min === undefined ? 8 : o.min;
  const max = o.max === undefined ? 400 : o.max;
  const width = measureText(text, Object.assign({}, font, { size: 100 })).width;
  if (!(width > 0)) return max;
  return Math.max(min, Math.min(max, Math.floor((100 * maxWidth) / width)));
}

// `<text>` + one `<tspan>` per line. The family is QUOTED (G-6), so a name
// with a word that starts with a digit (`Source Sans 3`) parses — except a
// CSS generic keyword, written bare as `measureText`'s probe writes it.
// `xmlSpace: "preserve"` is written on the `<text>` (G-22), and a style or
// letterSpacing other than normal / 0 as the probe writes them, normalised
// as the host does, so what is drawn is what was measured (#348).
const __GENERIC_FAMILIES = ["serif", "sans-serif", "cursive", "fantasy", "monospace"];

function textLines(lines, options) {
  const o = options || {};
  const f = o.font || {};
  const name = String(f.family || "Montserrat");
  const family = __GENERIC_FAMILIES.includes(name)
    ? name
    : `'${escapeXml(name.replace(/'/g, ""))}'`;
  const space = f.xmlSpace === "preserve" ? ` xml:space="preserve"` : "";
  const style = f.style === "italic" || f.style === "oblique" ? ` font-style="${f.style}"` : "";
  const spacing = Number(f.letterSpacing) || 0;
  const tracking = spacing ? ` letter-spacing="${spacing}"` : "";
  const anchor = o.anchor || "start";
  const size = f.size || 16;
  const lineHeight = o.lineHeight || size * 1.2;
  const x = o.x || 0;
  const spans = lines
    .map((l, i) => `<tspan x="${x}" dy="${i === 0 ? 0 : lineHeight}">${escapeXml(l)}</tspan>`)
    .join("");
  const fill = o.fill ? ` fill="${escapeXml(o.fill)}"` : "";
  return `<text x="${x}" y="${o.y || 0}" font-family="${family}" ` +
    `font-size="${size}" font-weight="${f.weight || 400}"${style}${tracking} text-anchor="${anchor}"${fill}${space}>` +
    `${spans}</text>`;
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// quickjs-ng has no `Intl`: the integer part grouped, `-` kept.
function formatNumber(n, options) {
  const { decimals = 0, separator = "," } = options || {};
  if (!isFinite(n)) return String(n);
  const fixed = Number(n).toFixed(decimals);
  if (fixed.includes("e")) return fixed;
  const negative = fixed[0] === "-";
  const digits = negative ? fixed.slice(1) : fixed;
  const dot = digits.indexOf(".");
  const whole = dot < 0 ? digits : digits.slice(0, dot);
  const fraction = dot < 0 ? "" : digits.slice(dot);
  let grouped = "";
  for (let i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 === 0) grouped += separator;
    grouped += whole[i];
  }
  return (negative ? "-" : "") + grouped + fraction;
}

// The href the rasterizer resolves for a file in `graphics/assets/`; an
// unknown name is a warning naming the folder's files.
function asset(name) {
  const names = JSON.parse(__assetNames());
  if (names.includes(name)) return name;
  const has = names.length ? names.join(", ") : "(no assets)";
  __warn(`asset("${name}") is not in graphics/assets/; the folder has: ${has}`);
  return escapeXml(name);
}
