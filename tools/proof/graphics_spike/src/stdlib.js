// The graphics standard library — road map 10 §5c, the spike's subset: only
// what the six graphics of §5k use. Written from scratch (G-2): the names and
// argument shapes follow Remotion's, none of its code is here.
// Evaluated as a SCRIPT before the sandbox, so every declaration is global.

function svg(ctx, body, options) {
  const o = options || {};
  const background = o.background
    ? `<rect x="0" y="0" width="${ctx.width}" height="${ctx.height}" fill="${o.background}"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${ctx.width}" height="${ctx.height}" ` +
    `viewBox="0 0 ${ctx.width} ${ctx.height}">${background}${body}</svg>`;
}

function interpolate(value, input, output, options) {
  const o = options || {};
  const n = input.length;
  if (n < 2 || output.length !== n) {
    throw new Error("interpolate: input and output need the same length, at least 2");
  }
  const left = o.extrapolateLeft || (o.clamp ? "clamp" : "extend");
  const right = o.extrapolateRight || (o.clamp ? "clamp" : "extend");
  let i = 1;
  while (i < n - 1 && value > input[i]) i++;
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
    E["in" + cap] = f;
    E["out" + cap] = (t) => 1 - f(1 - t);
    E["inOut" + cap] = (t) => (t < 0.5 ? f(2 * t) / 2 : 1 - f(2 * (1 - t)) / 2);
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
        let lo = 0, hi = 1;
        for (let k = 0; k < 40; k++) {
          s = (lo + hi) / 2;
          if (at(x1, x2, s) < t) lo = s; else hi = s;
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

const measureText = (() => {
  const memo = new Map();
  return (text, font) => {
    const f = font || {};
    const family = f.family || "Montserrat";
    const size = f.size || 16;
    const weight = f.weight || 400;
    const style = f.style || "normal";
    const key = `${family}|${size}|${weight}|${style}|${text}`;
    let m = memo.get(key);
    if (!m) {
      m = JSON.parse(__measureText(String(text), family, size, weight, style));
      if (m.error) throw new Error(m.error);
      if (memo.size > 4096) memo.clear();
      memo.set(key, m);
    }
    const spacing = (f.letterSpacing || 0) * [...String(text)].length;
    return {
      width: m.width + spacing, ascent: m.ascent, descent: m.descent, lineHeight: m.lineHeight,
      x: m.x, inkWidth: m.inkWidth + spacing, inkX: m.inkX,
    };
  };
})();

function wrapText(text, maxWidth, font) {
  const lines = [];
  let line = "";
  const fits = (s) => measureText(s, font).width <= maxWidth;
  for (const word of String(text).split(/\s+/).filter((w) => w.length)) {
    const candidate = line ? line + " " + word : word;
    if (fits(candidate)) { line = candidate; continue; }
    if (line) lines.push(line);
    line = "";
    if (fits(word)) { line = word; continue; }
    let piece = "";
    for (const ch of word) {
      if (piece && !fits(piece + ch)) { lines.push(piece); piece = ""; }
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

function textLines(lines, options) {
  const o = options || {};
  const f = o.font || {};
  const anchor = o.anchor || "start";
  const size = f.size || 16;
  const lineHeight = o.lineHeight || size * 1.2;
  const spans = lines
    .map((l, i) => `<tspan x="${o.x || 0}" dy="${i === 0 ? 0 : lineHeight}">${escapeXml(l)}</tspan>`)
    .join("");
  const fill = o.fill ? ` fill="${o.fill}"` : "";
  return `<text x="${o.x || 0}" y="${o.y || 0}" font-family="${f.family || "Montserrat"}" ` +
    `font-size="${size}" font-weight="${f.weight || 400}" text-anchor="${anchor}"${fill}>${spans}</text>`;
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
