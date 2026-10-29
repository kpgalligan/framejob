// keyboard-keys — a bundled template (spec §11 G-44): a shortcut such as
// "cmd+shift+4" as keycaps popping in one after another, each pressed in
// turn, with a label under them. Modifier and arrow symbols are drawn as
// vector glyphs, never taken from a font.
export const meta = {
  name: "Keyboard keys",
  durationInFrames: 90,
};

export const schema = {
  keys:     { type: "string", default: "cmd+shift+4", animate: false },
  label:    { type: "string", default: "Screenshot a selection" },
  theme:    { type: "enum",   default: "light", options: ["light", "dark"] },
  position: { type: "enum",   default: "bottom", options: ["bottom", "center", "top"] },
  accent:   { type: "color",  default: "#ff5a36" },
};

const GLYPHS = {
  cmd: "command", command: "command", "⌘": "command",
  shift: "shift", "⇧": "shift",
  opt: "option", option: "option", alt: "option", "⌥": "option",
  ctrl: "control", control: "control", "⌃": "control",
  up: "up", down: "down", left: "left", right: "right",
};

// A glyph centred on (0, 0), `g` across, in `colour`.
function glyph(kind, g, colour) {
  const s = (v) => v * g;
  const line = `fill="none" stroke="${colour}" stroke-width="${0.085 * g}" stroke-linecap="round" stroke-linejoin="round"`;
  if (kind === "command") {
    const a = 0.16;
    const r = 0.15;
    const e = a + r;
    return `<path ${line} d="M ${s(a)} ${s(-e)} L ${s(a)} ${s(e)} M ${s(-a)} ${s(-e)} L ${s(-a)} ${s(e)}
      M ${s(-e)} ${s(a)} L ${s(e)} ${s(a)} M ${s(-e)} ${s(-a)} L ${s(e)} ${s(-a)}
      M ${s(a)} ${s(e)} A ${s(r)} ${s(r)} 0 1 0 ${s(e)} ${s(a)}
      M ${s(-a)} ${s(e)} A ${s(r)} ${s(r)} 0 1 1 ${s(-e)} ${s(a)}
      M ${s(a)} ${s(-e)} A ${s(r)} ${s(r)} 0 1 1 ${s(e)} ${s(-a)}
      M ${s(-a)} ${s(-e)} A ${s(r)} ${s(r)} 0 1 0 ${s(-e)} ${s(-a)}"/>`;
  }
  if (kind === "shift") {
    return `<path ${line} d="M 0 ${s(-0.42)} L ${s(0.42)} ${s(0.02)} L ${s(0.19)} ${s(0.02)} L ${s(0.19)} ${s(0.4)}
      L ${s(-0.19)} ${s(0.4)} L ${s(-0.19)} ${s(0.02)} L ${s(-0.42)} ${s(0.02)} Z"/>`;
  }
  if (kind === "option") {
    return `<path ${line} d="M ${s(-0.42)} ${s(-0.3)} L ${s(-0.14)} ${s(-0.3)} L ${s(0.16)} ${s(0.3)} L ${s(0.42)} ${s(0.3)}
      M ${s(0.08)} ${s(-0.3)} L ${s(0.42)} ${s(-0.3)}"/>`;
  }
  if (kind === "control") {
    return `<path ${line} d="M ${s(-0.32)} ${s(0.12)} L 0 ${s(-0.2)} L ${s(0.32)} ${s(0.12)}"/>`;
  }
  const turn = { up: 0, right: 90, down: 180, left: 270 }[kind];
  return `<path d="M 0 ${s(-0.3)} L ${s(0.3)} ${s(0.22)} L ${s(-0.3)} ${s(0.22)} Z" fill="${colour}"
    stroke="${colour}" stroke-width="${0.06 * g}" stroke-linejoin="round" transform="rotate(${turn})"/>`;
}

export function render(frame, props, ctx) {
  const u = Math.min(ctx.width, ctx.height) / 1080;
  const D = ctx.durationInFrames;
  const safeW = ctx.width * 0.9;
  const safeY = ctx.height * 0.05;
  const safeH = ctx.height * 0.9;
  const dark = props.theme === "dark";
  const face = dark ? "#2c2c33" : "#f6f6f8";
  const lip = dark ? "#121216" : "#b9b9c4";
  const ink = dark ? "#ffffff" : "#1c1c22";
  const tokens = props.keys.split("+").map((t) => t.trim()).filter((t) => t.length > 0);
  const capH = 130 * u;
  const gap = 22 * u;
  const wordFont = { family: "Montserrat", size: 40 * u, weight: 800 };
  const charFont = { family: "Montserrat", size: 60 * u, weight: 800 };
  const caps = tokens.map((t) => {
    const kind = GLYPHS[t.toLowerCase()];
    if (kind) return { kind, w: capH };
    const text = t.length === 1 ? t.toUpperCase() : t;
    const font = t.length === 1 ? charFont : wordFont;
    return { text, font, w: Math.max(capH, measureText(text, font).width + 70 * u) };
  });
  const rowW = caps.reduce((a, c) => a + c.w, 0) + gap * Math.max(0, caps.length - 1);
  const labelFont = { family: "Montserrat", size: 44 * u, weight: 800 };
  const labelSize = props.label.trim() ? fitText(props.label, safeW - 140 * u, labelFont, { min: 10 * u, max: labelFont.size }) : 0;
  const labelH = labelSize > 0 ? labelSize + 56 * u : 0;
  const fit = Math.min(1, (safeW - 80 * u) / Math.max(1, rowW));
  const groupH = capH * fit + (labelH > 0 ? 30 * u + labelH : 0);
  const margin = 50 * u;
  const top = props.position === "top" ? safeY + margin
    : props.position === "center" ? (ctx.height - groupH) / 2
    : safeY + safeH - margin - groupH;
  const cx = ctx.width / 2;
  const cy = top + groupH / 2;
  const enter = (i) => spring({ frame: frame - i * 5, fps: ctx.fps, stiffness: 200, damping: 13 });
  const pressAt = caps.length * 5 + 14;
  const out = interpolate(frame, [D - 15, D - 1], [0, 1], { easing: Easing.inCubic, clamp: true });
  const outScale = 1 - 0.1 * out;

  let row = "";
  let x = cx - (rowW * fit) / 2;
  const lipH = 12 * u * fit;
  caps.forEach((c, i) => {
    const w = c.w * fit;
    const h = capH * fit;
    const s = enter(i);
    const dip = interpolate(frame - pressAt - i * 5, [0, 3, 10], [0, 6 * u * fit, 0], { clamp: true });
    const kx = x + w / 2;
    const ky = top + h / 2;
    const rx = 0.18 * h;
    let mark = "";
    if (c.kind) {
      mark = `<g transform="translate(${kx} ${ky - lipH / 2 + dip})">${glyph(c.kind, h * 0.5, ink)}</g>`;
    } else {
      const size = c.font.size * fit;
      mark = `<text x="${kx}" y="${ky - lipH / 2 + dip + size * 0.36}" text-anchor="middle" font-family="Montserrat"
                    font-weight="800" font-size="${size}" fill="${ink}">${escapeXml(c.text)}</text>`;
    }
    if (s > 0.001) {
      row += `<g transform="translate(${kx} ${ky}) scale(${s}) translate(${-kx} ${-ky})">
        <rect x="${x}" y="${top}" width="${w}" height="${h}" rx="${rx}" fill="${lip}"/>
        <rect x="${x}" y="${top + dip}" width="${w}" height="${h - lipH}" rx="${rx}" fill="${face}"/>
        <rect x="${kx - w * 0.22}" y="${top + h - lipH - 18 * u * fit + dip}" width="${w * 0.44}" height="${5 * u * fit}"
              rx="${2.5 * u * fit}" fill="${props.accent}"/>
        ${mark}</g>`;
    }
    x += w + gap * fit;
  });

  let label = "";
  if (labelSize > 0) {
    const t = spring({ frame: frame - caps.length * 5 - 4, fps: ctx.fps, damping: 16 });
    const lw = measureText(props.label, { family: "Montserrat", size: labelSize, weight: 800 }).width + 64 * u;
    const ly = top + capH * fit + 30 * u + (1 - Math.min(1, t)) * 16 * u;
    label = `<g opacity="${Math.max(0, Math.min(1, t))}">
      <rect x="${cx - lw / 2}" y="${ly}" width="${lw}" height="${labelH}" rx="${labelH / 2}" fill="#101014"
            fill-opacity="0.82"/>
      <text x="${cx}" y="${ly + labelH / 2 + labelSize * 0.36}" text-anchor="middle" font-family="Montserrat"
            font-weight="800" font-size="${labelSize}" fill="#ffffff">${escapeXml(props.label)}</text></g>`;
  }
  return svg(ctx, `
    <g opacity="${1 - out}" transform="translate(${cx} ${cy}) scale(${outScale}) translate(${-cx} ${-cy})">
      ${row}${label}
    </g>`);
}
